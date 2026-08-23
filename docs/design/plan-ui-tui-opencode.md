# PLAN-UI-TUI-OPENCODE: Surface the kit mode inside the opencode TUI

**Status: brainstorm** — nothing implemented, all source claims verified
against the pinned opencode checkout at v1.18.15
(`github/opencode`, `git log -1` → `release: v1.18.15`) and the opentui
checkout at **v0.4.5** (`github/opentui`, tag `Release v0.4.5` — the
exact version opencode v1.18.15 pins via its package.json catalog).

## 1. Motivation

The kit installs opencode in one of several security postures, but once
the TUI is running **nothing on screen says which one you are in**:

| Kit mode (working title) | Meaning | Theme (decided 2026-08-23) |
|---|---|---|
| `[full]` hardened | no container backend at all — docker/ddev denied everywhere | built-in **`matrix`** (green) |
| `[strong]` rootless | rootless container backend, soft permission layer (today's default install) | built-in **`github`** (blue primary, purple/cyan accents) |
| `[danger]` bypassed | the agent is NOT running under the kit's separation — e.g. the developer launches the original opencode binary as **their own user** (self-update bypass, the case the deny-all lockout exists for) | custom **`opencode-danger`** (red) — draft in appendix A |

Two ideas from the maintainer (2026-08-23):

1. **Status display** — while the TUI is open, show something like
   `Mode: [strong] rootless containers`.
2. **Theme-by-mode** — start opencode with a theme that encodes the mode
   (`opencode --theme=green|red`), so a glance at the window is enough.

Refinement (maintainer, same day): the theme does not need a CLI flag
at all — it can follow **which user's HOME the TUI runs under**:

- wrapper path (`opencode` → `sudo -u opencode`) → HOME is
  `/home/opencode` → the opencode user's global `tui.json` applies →
  green (`[full]`, no backend) or cyan/blue (`[strong]`, backend on).
- original binary as the developer (`~/.opencode/bin/opencode` or
  wherever the self-updater put it) → HOME is `/home/$DEFAULT_USER` →
  the developer's global `tui.json` applies → **red**.

This works without any env transport: sudo's env_reset rewrites HOME to
the target user (HOME is not in the kit's env_keep — verified against
`files/sudoers.template`), and the TUI loads its global config from
`$HOME`-based `Global.Path.config`. The danger theme lands exactly where
the deny-all lockout already lives (`/home/$DEFAULT_USER/.config/opencode/`,
deployed by install.sh "only if absent" — same policy applies).

This record inventories **every way the kit can influence opencode from
the outside**, weighs them, and sketches a design.

## 2. What the kit knows (source of truth for "mode")

- `/etc/opencode-permissions-kit/install.conf` — stamps written by
  install/update (`CONTAINER_BACKEND=docker-rootless|podman-rootless|none`,
  `OPENCODE_DOCKER_HOST`, …). Readable by all (root:root 644) → a process
  running as `opencode` can read it.
- The deployed global `/home/opencode/.config/opencode/opencode.jsonc` —
  the soft permission layer the kit renders (container allow/deny rules).
- Reachability of the rootless socket
  (`/run/user/<uid>/docker.sock`, probed by `socket-check.sh`).

"Mode" is therefore **derivable at runtime** from install.conf + the
socket; no new state needs to be introduced for a read-only display.

## 3. Verified inventory: influencing opencode from outside

Everything below checked in the v1.18.15 source:

### 3.1 CLI flags (`packages/opencode/src/cli/cmd/run.ts`)

`--model --agent --port --password --username --dir --variant --share
--command --continue --session --fork --attach ...` — **there is no
`--theme` flag and no generic `--config` override flag.**
`opencode --theme=green` does not work today and cannot be added without
an upstream change.

### 3.2 ENV variables (`Flag.*`, read at process start)

| Var | Effect | Kit-relevant? |
|---|---|---|
| `OPENCODE_TUI_CONFIG` | path to a tui.json **merged over** the global one (config/tui.ts:189) | theme + keybinds + **TUI plugins** |
| `OPENCODE_CONFIG` / `OPENCODE_CONFIG_DIR` / `OPENCODE_CONFIG_CONTENT` | agent config file/dir/raw JSON | security-relevant — see 3.6 |
| `OPENCODE_PERMISSION` | JSON merged into `permission` (config/config.ts:545) | security-relevant |
| `OPENCODE_DISABLE_PROJECT_CONFIG`, `OPENCODE_DISABLE_MODELS_FETCH`, … | behavior switches | not needed here |

Note: our sudoers `env_keep` deliberately keeps NONE of these (only
`SERVER_PASSWORD/USERNAME`, `DOCKER_HOST`, `XDG_RUNTIME_DIR`,
`DDEV_DEBUG`) — see `files/sudoers.template`. `OPENCODE_TUI_CONFIG` in
`env_keep` would let any calling shell inject a tui.json containing a
`plugin` entry, i.e. **JS execution in the TUI process as opencode** —
the exact injection class env_reset protects against. Verdict: never
env_keep it.

### 3.3 TUI config file: `tui.json` (packages/opencode/src/config/tui.ts)

Loaded (in precedence order, later wins):

1. global `~/.config/opencode/tui.json` (opencode user's own)
2. `OPENCODE_TUI_CONFIG` explicit file
3. project `tui.json` / `.opencode/tui.json` walking up from cwd
   (unless `OPENCODE_DISABLE_PROJECT_CONFIG`)

Relevant keys (`packages/tui/src/config/index.tsx`): `theme: "<name>"`,
`keybinds`, `plugin: [spec, …]`, `attention`, `prompt`, …

The active theme reacts to `config.theme` via a Solid effect
(`context/theme.tsx:131`) — a config reload swaps the theme live.

### 3.4 Custom themes (packages/tui/src/context/theme.tsx:47)

Any `themes/*.json` in `~/.config/opencode/` or a `.opencode/` dir
between cwd and root is discovered (35+ built-ins ship; gruvbox et al.).
Format: `{"$schema": "https://opencode.ai/theme.json", "defs": {...},
"theme": {dark/light color maps}}`. The kit can ship its own theme files
without touching upstream code.

**SIGUSR2** re-runs theme discovery in the running TUI
(`themeSource.subscribeRefresh`, context/theme.tsx:54) — themes can be
added/reloaded without restarting opencode.

### 3.5 TUI plugins (tui.json `plugin`, packages/opencode/src/plugin/tui/)

Plugin specs may be **absolute local paths**
(config/plugin.ts:42 — resolved to `file://`). A plugin is a Solid
component running inside the TUI with a host API:

- **Slots** to render into (packages/plugin/src/tui.ts:455):
  `app`, `app_bottom`, `home_logo`, `home_prompt_right`,
  `session_prompt_right`, `home_bottom`, `home_footer`, `sidebar_title`,
  `sidebar_footer` — a status line has two natural homes
  (`home_footer`, `app_bottom`).
- **`theme.set(name)`** at runtime (plugin/adapters.tsx:342) — a plugin
  can switch the theme itself, on a timer, on an event, whatever.
- Event bus (`event.on(...)`), KV store, dialogs, toasts.

This is the only mechanism that can show **dynamic** state (mode,
socket up/down) inside the TUI.

### 3.6 Agent config / permissions (`opencode.jsonc`, `OPENCODE_CONFIG*`)

The kit already renders these as files. They cannot change the TUI's
look, and the env variants are (correctly) not env_kept. Listed only to
close the inventory.

### 3.7 opentui layer (github/opentui, checked out at v0.4.5 — the pin)

opencode's TUI is built on **opentui** (opencode `package.json` catalog:
`@opentui/core|solid|keymap` → `0.4.5`). The TUI plugin API exposes the
**full `CliRenderer`** (opencode `packages/plugin/src/tui.ts:616`,
`renderer: CliRenderer`), so everything opentui's renderer offers is
reachable from a kit plugin. All claims below verified against the
v0.4.5 tag:

- **`renderer.setTerminalTitle(title)`** — OSC terminal/tab title
  (opentui `renderer.ts:3838`, native zig fn). opencode's own TUI uses
  it (`app.tsx:457-474`, title `"OpenCode"` / `"OC | <session>"`) — so
  it exists and works in the pinned 0.4.5. A mode suffix like
  `OC | <session> — [strong] rootless` would show in tab bars / tmux
  pane titles **even when the TUI is not focused**. Caveat: the app
  re-sets the title on route changes — a plugin must re-assert after
  `event.on(...)` route/session events or the suffix disappears (no
  upstream hook API for "title changed").
- **`renderer.triggerNotification(message, title)`** — desktop
  notifications (opentui `renderer.ts:1823`). opencode's attention
  system uses it (`attention.ts:185`). A kit plugin could notify when
  the rootless socket dies mid-session ("backend gone — mode downgraded
  to [full]").
- **Mouse events, keyboard events** via the renderer (`enableMouse`,
  kitty keyboard protocol flags, RawMouseEvent/KeyEvent parsing) —
  enough to build a hoverable status widget later; not needed for v1.
- **`renderer.getPalette()` / terminal capabilities** — live palette +
  capability detection incl. `kitty_graphics`/`sixel` capability flags
  (types.ts:69-78; the theme system already builds its `system` theme
  from the palette). Kit themes can therefore stay dark/light-agnostic
  like the built-ins.
- Also shipped at 0.4.5, potentially useful later but **not needed for
  the mode display**: the **animation Timeline**
  (`animation/Timeline.ts`, e.g. animating a mode-change transition),
  **OSC 52 clipboard** (`zig.ts:copyToClipboardOSC52`), and the
  separate **qrcode** package (QR renderable — e.g. rendering the
  `opencode serve` URL as a scannable QR in the TUI) and **ssh**
  package.
- **Not in 0.4.5** (main-only, verified absent at the tag): the image
  renderable (`renderables/Image.ts` + `image_protocol` enum) and the
  embedded-terminal renderable (`EmbeddedTerminal.ts`). Do not plan
  around them until opencode bumps its opentui pin.

API-stability caveat: everything the kit uses must be re-verified
against the pinned @opentui/* version whenever opencode bumps it (the
opencode catalog is the source of truth; today 0.4.5).

## 4. Options, weighed

| # | Mechanism | Shows mode? | Sets theme? | Pros | Cons |
|---|---|---|---|---|---|
| A | Kit-written `~/.config/opencode/tui.json` (`theme` key) + kit theme files in `~/.config/opencode/themes/` | no (static) | at start | no code in opencode, no plugin runtime, survives updates, mode changes only via `config.sh` anyway (rare) → re-render then | static per start; a user's own tui.json edits could drift (kit owns the file — needs merge policy) |
| B | Kit TUI plugin (absolute path spec from the kit dir) in that tui.json | **yes, live** | **yes, live** (`theme.set`) | real status line (`Mode: [strong] rootless`), can probe socket/install.conf itself, reacts to mode changes without restart | TUI plugin API is young/undocumented upstream — pin + smoke-test per opencode version; JS surface to maintain; plugin runs with TUI privileges |
| C | `OPENCODE_TUI_CONFIG` env from the wrapper + env_keep | no | at start | per-launch choice without writing files | **rejected**: env_keeping it = JS injection path into the TUI process from any calling shell (3.2) |
| D | Upstream `--theme` CLI flag | no | at start | nicest UX (`opencode --theme=green`) | does not exist in v1.18.15; upstream PR + release lag; still only start-time |
| E | Terminal-level tricks (title bar via OSC, wrapper-set env in PS1) | outside TUI | no | zero opencode coupling | fragile, invisible inside tmux/pane titles, not "in the TUI" |
| F | Plugin-driven terminal title (`renderer.setTerminalTitle`, 3.7) | **yes — in tab/tmux title, even unfocused** | no | exists + battle-tested in pinned 0.4.5 (opencode sets `"OC | <session>"` itself); zero layout risk; visible across tmux panes | not inside the TUI canvas; app re-sets the title on route changes — plugin must re-assert after route/session events; users who disable the title (`terminal_title_enabled`) must be respected |

**Recommendation: A + B combined, delivered in kit terms (F as a B bonus):**

- **A (theme-by-identity, cheap, do first):** two global `tui.json`
  files, following HOME (see §1 refinement):
  - `/home/opencode/.config/opencode/tui.json` — rendered by the kit
    with `"theme": "<green|cyan/blue built-in>"` depending on the
    backend stamps in install.conf (`[full]` vs `[strong]`).
  - `/home/$DEFAULT_USER/.config/opencode/tui.json` — `"theme":
    "<red>"`; deployed only-if-absent exactly like the deny-all
    lockout next door (install.sh:1442 pattern).
  **Built-ins first, custom files only where needed** (decided
  2026-08-23):
  - `[full]` green: built-in `matrix` (primary `rainGreen`)
  - `[strong]`: built-in `github` — blue primary (`#58a6ff`) with
    purple secondary / cyan accent (reads blue-purple; maintainer's
    pick — docker/ddev tier)
  - `[danger]` red: **no built-in has a red primary** → ship exactly
    ONE custom theme `opencode-danger.json` (appendix A), a fork of
    the built-in `lucent-orng` with the orange system remapped to red
    (same structure: transparent backgrounds, small defs table).
    Deployed to `~/.config/opencode/themes/` of BOTH users — custom
    themes are discovered from `themes/*.json` in either config dir,
    no upstream code involved.
  Trade-off built-ins vs customs: built-ins = zero shipped files but
  their look can drift with opencode updates (a renamed/removed
  built-in would fall back to `opencode` default — acceptable, the
  mode still exists); customs = stable look but files to maintain
  (here: one).
  Precedence note: `config.theme` from tui.json **outranks the KV**
  the `/theme` picker writes (`context/theme.tsx:121` —
  `config.theme ?? kv.get("theme")`) — a kit-set theme is
  authoritative; the escape hatch is editing/removing tui.json
  (document it).
- **B (status line, second step):** `files/tui-plugin/` ships a tiny
  plugin registered by the same tui.json (`plugin:
  ["/usr/local/lib/opencode-permissions-kit/tui-plugin/index.js"]`),
  rendering `Mode: [strong] rootless containers` in `home_footer`/
  `app_bottom`, reading install.conf + probing the socket; may also
  call `theme.set()` so the theme tracks reality (e.g. socket gone →
  visually downgraded) and send itself `SIGUSR2` after theme installs.
- **F (cheap extra inside B):** the same plugin suffixes the terminal
  title (e.g. `OC | session — [strong]`), re-asserted on route/session
  events, gated on the user's `terminal_title_enabled` KV state; and
  may call `triggerNotification` when the backend socket dies
  mid-session.

## 5. Design sketch (for the implementing PR)

1. **Mode derivation helper** (`opencode-permissions-kit-lib/`):
   `kit_mode()` → `full|strong|danger` from install.conf + optional
   socket probe. Shared by config.sh render + the plugin (which reads
   install.conf itself — a shell-out or a duplicated tiny parser).
   `danger` is not an install.conf state — it is the identity signal
   (TUI running under the developer's HOME), so the helper only picks
   `full|strong` for the opencode user's render; the dev-side file is
   static red.
2. **Theme choice (decided):** built-in `matrix` for `[full]`,
   built-in `github` for `[strong]`, and one shipped custom theme
   `files/tui-themes/opencode-danger.json` (appendix A draft) for
   `[danger]`, deployed to both users' `~/.config/opencode/themes/`.
   Anti-drift test: unit check that `matrix`/`github` still exist in
   the installed opencode's theme list is not possible from the kit —
   instead the docs note the fallback (unknown theme name → default
   `opencode` theme, mode display unaffected).
3. **tui.json ownership:** kit writes each file only if absent or
   previously kit-written (marker key `_opencode_permissions_kit: true`,
   ignored by opencode's schema). Never clobber user edits — identical
   to the deny-all policy at install.sh:1441; document the escape hatch
   (`config.sh tui-reset`?). Project-level `tui.json` (closer to cwd)
   still outranks the global file — acceptable and worth a docs note.
4. **Plugin (phase 2)** in `files/tui-plugin/`: no npm deps, plain JS,
   defensive `try/catch` everywhere (a broken plugin must never take the
   TUI down), unit-testable mode parser, version-pinned CI smoke test
   (start TUI headless, assert the slot renders).
5. **Update flow:** `update.sh` re-deploys themes/plugin and re-renders
   both tui.json files (same KIT_FILES pattern as the other payloads);
   backend toggles (`config.sh container-backend`) re-render the
   opencode user's file so `[full]`↔`[strong]` recolors.

## 6. Open questions

- ~~Is `danger` a real kit state?~~ Resolved by the HOME refinement:
  danger = TUI under the developer's own HOME (original binary,
  self-update bypass) — the state the deny-all lockout already guards.
- ~~Theme picks?~~ Decided 2026-08-23: `matrix` / `github` /
  custom `opencode-danger` (lucent-orng fork, appendix A). Open: final
  red tuning after seeing it in a real terminal (values in appendix A
  are a first draft).
- Does a project-local `tui.json` (precedence 3.3-3) override the kit
  theme too easily? Do we care (docs vs code)?
- TUI plugin API stability across opencode releases — do we gate the
  plugin on the installed opencode version (kit knows it) and fall back
  to A-only? Includes the opentui pin (0.4.5 today) — recheck the
  `CliRenderer` surface we use whenever opencode bumps @opentui/*.
- `home_footer` vs `app_bottom` — which slot survives upstream UI
  reshuffles better?
- Title suffix (F): respect the KV key `terminal_title_enabled` —
  read it via the plugin KV api or leave title handling entirely alone
  when disabled?

## 7. Non-goals

- No new env_keep entries (3.2/3.6 rationale).
- No patching/forking of opencode; everything via supported files,
  themes and the plugin spec system.
- No live theme switching from the developer's shell into a running
  TUI (SIGUSR2 only refreshes *discovered theme files*, not the active
  selection — active selection changes need config reload or
  `theme.set` from inside).

## Appendix A: `opencode-danger.json` draft

Fork of the built-in `lucent-orng` (v1.18.15, `theme/assets/`) with the
orange system remapped to red. Same structure (defs + dark/light
references, transparent backgrounds); renamed def keys so nothing lies
(`darkDanger`, not `darkOrange` holding a red). Diff vs lucent-orng in
prose: orange→red everywhere it carried the identity (primary,
secondary, border, markdown headings/links/list items, syntax keyword,
panel tint), warning moved off the identity color to the theme's
yellow, everything else (blues/cyans/yellows for diffs, syntax,
success/info) untouched. Values are a first draft — tune after seeing
it rendered; the JSON is valid as-is and loads as a custom theme.

```json
{
  "$schema": "https://opencode.ai/theme.json",
  "defs": {
    "darkStep6": "#3c3c3c",
    "darkStep11": "#808080",
    "darkStep12": "#eeeeee",
    "darkSecondary": "#f07178",
    "darkAccent": "#FFF7F1",
    "darkRed": "#e06c75",
    "darkDanger": "#e5484d",
    "darkBlue": "#6ba1e6",
    "darkCyan": "#56b6c2",
    "darkYellow": "#e5c07b",
    "darkPanelBg": "#2a151899",
    "lightStep6": "#d4d4d4",
    "lightStep11": "#8a8a8a",
    "lightStep12": "#1a1a1a",
    "lightSecondary": "#c4372f",
    "lightAccent": "#c4372f",
    "lightRed": "#d1383d",
    "lightDanger": "#d1383d",
    "lightBlue": "#0062d1",
    "lightCyan": "#318795",
    "lightYellow": "#b0851f",
    "lightPanelBg": "#fff0ef99"
  },
  "theme": {
    "primary": { "dark": "darkDanger", "light": "lightDanger" },
    "secondary": { "dark": "darkSecondary", "light": "lightSecondary" },
    "accent": { "dark": "darkAccent", "light": "lightAccent" },
    "error": { "dark": "darkRed", "light": "lightRed" },
    "warning": { "dark": "darkYellow", "light": "lightYellow" },
    "success": { "dark": "darkBlue", "light": "lightBlue" },
    "info": { "dark": "darkCyan", "light": "lightCyan" },
    "text": { "dark": "darkStep12", "light": "lightStep12" },
    "textMuted": { "dark": "darkStep11", "light": "lightStep11" },
    "selectedListItemText": { "dark": "#0a0a0a", "light": "#ffffff" },
    "background": { "dark": "transparent", "light": "transparent" },
    "backgroundPanel": { "dark": "transparent", "light": "transparent" },
    "backgroundElement": { "dark": "transparent", "light": "transparent" },
    "backgroundMenu": { "dark": "darkPanelBg", "light": "lightPanelBg" },
    "border": { "dark": "darkDanger", "light": "lightDanger" },
    "borderActive": { "dark": "darkSecondary", "light": "lightAccent" },
    "borderSubtle": { "dark": "darkStep6", "light": "lightStep6" },
    "diffAdded": { "dark": "darkBlue", "light": "lightBlue" },
    "diffRemoved": { "dark": "#c53b53", "light": "#c53b53" },
    "diffContext": { "dark": "#828bb8", "light": "#7086b5" },
    "diffHunkHeader": { "dark": "#828bb8", "light": "#7086b5" },
    "diffHighlightAdded": { "dark": "darkBlue", "light": "lightBlue" },
    "diffHighlightRemoved": { "dark": "#e26a75", "light": "#f52a65" },
    "diffAddedBg": { "dark": "transparent", "light": "transparent" },
    "diffRemovedBg": { "dark": "transparent", "light": "transparent" },
    "diffContextBg": { "dark": "transparent", "light": "transparent" },
    "diffLineNumber": "textMuted",
    "diffAddedLineNumberBg": { "dark": "transparent", "light": "transparent" },
    "diffRemovedLineNumberBg": { "dark": "transparent", "light": "transparent" },
    "markdownText": { "dark": "darkStep12", "light": "lightStep12" },
    "markdownHeading": { "dark": "darkDanger", "light": "lightDanger" },
    "markdownLink": { "dark": "darkDanger", "light": "lightDanger" },
    "markdownLinkText": { "dark": "darkCyan", "light": "lightCyan" },
    "markdownCode": { "dark": "darkBlue", "light": "lightBlue" },
    "markdownBlockQuote": { "dark": "darkAccent", "light": "lightYellow" },
    "markdownEmph": { "dark": "darkYellow", "light": "lightYellow" },
    "markdownStrong": { "dark": "darkSecondary", "light": "lightDanger" },
    "markdownHorizontalRule": { "dark": "darkStep11", "light": "lightStep11" },
    "markdownListItem": { "dark": "darkDanger", "light": "lightDanger" },
    "markdownListEnumeration": { "dark": "darkCyan", "light": "lightCyan" },
    "markdownImage": { "dark": "darkDanger", "light": "lightDanger" },
    "markdownImageText": { "dark": "darkCyan", "light": "lightCyan" },
    "markdownCodeBlock": { "dark": "darkStep12", "light": "lightStep12" },
    "syntaxComment": { "dark": "darkStep11", "light": "lightStep11" },
    "syntaxKeyword": { "dark": "darkDanger", "light": "lightDanger" },
    "syntaxFunction": { "dark": "darkSecondary", "light": "lightAccent" },
    "syntaxVariable": { "dark": "darkRed", "light": "lightRed" },
    "syntaxString": { "dark": "darkBlue", "light": "lightBlue" },
    "syntaxNumber": { "dark": "darkAccent", "light": "lightDanger" },
    "syntaxType": { "dark": "darkYellow", "light": "lightYellow" },
    "syntaxOperator": { "dark": "darkCyan", "light": "lightCyan" },
    "syntaxPunctuation": { "dark": "darkStep12", "light": "lightStep12" }
  }
}
```

Color rationale: `#e5484d` (dark) / `#d1383d` (light) as the danger
identity — clearly distinct from the theme's own error red
(`#e06c75`) and from diff reds, readable on transparent backgrounds.
Secondary `#f07178` (dark) keeps lucent-orng's "warm second voice"
character in the red family. The one deliberate off-identity change:
`warning` was orange (= the old identity) and is now the theme's
yellow, so a red theme does not show orange warnings that read as
accents.
