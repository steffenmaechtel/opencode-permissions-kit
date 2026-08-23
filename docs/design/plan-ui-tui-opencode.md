# PLAN-UI-TUI-OPENCODE: Surface the kit mode inside the opencode TUI

**Status: implemented 2026-08-23** (A' + B v1 as specced below; commit
history on `feature/improve-ui-tui-opencode`). Payload:
`files/opencode-permissions-kit-lib/tui/` (plugin `kit-mode.tsx`,
`opencode-danger.theme.json`, both tui.json templates), deployed by
install.sh Step 8c + update.sh, guarded by
`tests/test-tui-mode.sh`. Everything below is kept as the design
record; claims were verified against the pinned opencode checkout at
v1.18.15 (`github/opencode`, `git log -1` → `release: v1.18.15`) and
the opentui checkout at **v0.4.5** (`github/opentui`, tag
`Release v0.4.5` — the exact version opencode v1.18.15 pins via its
package.json catalog).

## 1. Motivation

The kit installs opencode in one of several security postures, but once
the TUI is running **nothing on screen says which one you are in**:

| Kit mode (working title) | Meaning | Display (decided 2026-08-23, revised same day) |
|---|---|---|
| `[no ddev/docker]` hardened | no container backend at all — docker/ddev denied everywhere | footer text `opencode-permissions-kit (<version>) Mode: no ddev/docker` — theme stays the USER's choice |
| `[with ddev/docker]` rootless | rootless container backend, soft permission layer (today's default install) | footer text `opencode-permissions-kit (<version>) Mode: with ddev/docker` — theme stays the USER's choice |
| `[danger]` bypassed | the agent is NOT running under the kit's separation — e.g. the developer launches the original opencode binary as **their own user** (self-update bypass, the case the deny-all lockout exists for) | custom **`opencode-danger`** (red) theme — draft in appendix A |

Wording note: the user-facing strings deliberately avoid the internal
`[full]`/`[strong]` working titles and the docs' older "no container
tools / container tools opted in" — `opencode-permissions-kit (<version>) Mode: no ddev/docker` and
`opencode-permissions-kit (<version>) Mode: with ddev/docker` are what a user can read at a glance (the
docs' state names were aligned to this wording on 2026-08-23).

Two ideas from the maintainer (2026-08-23):

1. **Status display** — while the TUI is open, show something like
   `opencode-permissions-kit (<version>) Mode: with ddev/docker`.
2. **Theme-by-mode** — start opencode with a theme that encodes the mode
   (`opencode --theme=green|red`), so a glance at the window is enough.

Revision (maintainer, same day): **no kit themes for the opencode user**
— users like picking their own theme via `/theme`, and there is a hard
technical reason: `config.theme` from tui.json **shadows the KV the
`/theme` picker writes** (`context/theme.tsx:121` —
`config.theme ?? kv.get("theme")`). A kit-set theme would silently
disable the user's own theme selection. The red warning theme stays —
but ONLY for the default user (the bypass case), where "theme freedom"
is not the point:

- wrapper path (`opencode` → `sudo -u opencode`) → HOME is
  `/home/opencode` → **no tui.json from the kit at all**; the mode is
  shown as text in the TUI (option B).
- original binary as the developer (`~/.opencode/bin/opencode` or
  wherever the self-updater put it) → HOME is `/home/$DEFAULT_USER` →
  the developer's global `tui.json` applies → **red**
  `opencode-danger` (appendix A) — deliberate warning styling on the
  path that bypasses the kit's UID separation.

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
  `OC | <session> — with ddev/docker` would show in tab bars / tmux
  pane titles **even when the TUI is not focused**. Caveat: the app
  re-sets the title on route changes — a plugin must re-assert after
  `event.on(...)` route/session events or the suffix disappears (no
  upstream hook API for "title changed").
- **`renderer.triggerNotification(message, title)`** — desktop
  notifications (opentui `renderer.ts:1823`). opencode's attention
  system uses it (`attention.ts:185`). A kit plugin could notify when
  the rootless socket dies mid-session ("backend gone — mode downgraded
  to no ddev/docker").
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

### 3.8 Slot mechanics — where a plugin's UI can actually land

Verified at opencode v1.18.15 + opentui v0.4.5 (registry sorting:
ascending by `order`; slot `mode` is chosen by the HOST when mounting):

- **What the stock footer is:** the home-screen footer (path left,
  MCP indicator, version right) is itself a TUI plugin —
  `feature-plugins/home/footer.tsx`, id `internal:home-footer`,
  registered in slot **`home_footer` with `order: 100`**.
- **`home_footer` is mounted `mode="single_winner"`** (routes/home.tsx):
  only the FIRST registration (lowest order) renders. A kit plugin
  cannot append "opencode-permissions-kit (<version>) Mode: …" after the path — it would have to register
  with `order < 100` and re-render the whole footer itself (directory,
  MCP, version) = forking upstream footer code, drift on every update
  (1.18.21 already reshuffles it: version replaced by cost/context on
  narrow widths).
- **The session footer is not a slot at all** (routes/session/footer.tsx
  is hardcoded app UI: directory left, permissions/LSP/MCP right) — no
  plugin can append after the path during a session.
- **`app_bottom` is mounted without a mode → default append**
  (app.tsx:1125): every registered plugin renders, stacked — a thin
  full-width row at the very bottom, present on BOTH home and session
  screens. This is the only universal, non-forking in-canvas slot for
  the mode text; the TUI is responsive, an own row never competes with
  the footer's shrinkable columns.

Consequence for the design: "opencode-permissions-kit (<version>) Mode: … after the path"
is only achievable by replacing the home footer (fork) — the robust
v1 is `app_bottom` (own thin row) + the terminal-title suffix (F),
with footer replacement as an optional variant behind a compatibility
check (B1, §5).

## 4. Options, weighed

| # | Mechanism | Shows mode? | Sets theme? | Pros | Cons |
|---|---|---|---|---|---|
| A' | Kit-written `tui.json` + `opencode-danger` theme — **default user ONLY** | no (static) | at start (danger only) | no code in opencode, no plugin runtime, red warning exactly on the bypass path | none relevant — the bypass user is being warned, not styled; if they change the theme, the warning styling is gone (acceptable: deny-all still guards) |
| A | ~~Kit themes for the opencode user (`matrix`/`github`)~~ | — | — | **rejected in revision**: `config.theme` shadows the `/theme` picker's KV (theme.tsx:121) — a kit theme would lock users out of their own theme selection | — |
| B | Kit TUI plugin (absolute path spec from the kit dir) in the opencode user's tui.json | **yes, live** | n/a now (dropped by revision) | real status text (`opencode-permissions-kit (<version>) Mode: with ddev/docker`), can probe socket/install.conf itself, reacts to mode changes without restart | TUI plugin API is young/undocumented upstream — pin + smoke-test per opencode version; JS surface to maintain; plugin runs with TUI privileges |
| C | `OPENCODE_TUI_CONFIG` env from the wrapper + env_keep | no | at start | per-launch choice without writing files | **rejected**: env_keeping it = JS injection path into the TUI process from any calling shell (3.2) |
| D | Upstream `--theme` CLI flag | no | at start | nicest UX (`opencode --theme=green`) | does not exist in v1.18.15; upstream PR + release lag; still only start-time; theme-for-opencode-user dropped anyway |
| E | Terminal-level tricks (title bar via OSC, wrapper-set env in PS1) | outside TUI | no | zero opencode coupling | fragile, invisible inside tmux/pane titles, not "in the TUI" |
| F | Plugin-driven terminal title (`renderer.setTerminalTitle`, 3.7) | **yes — in tab/tmux title, even unfocused** | no | exists + battle-tested in pinned 0.4.5 (opencode sets `"OC | <session>"` itself); zero layout risk; visible across tmux panes | not inside the TUI canvas; app re-sets the title on route changes — plugin must re-assert after route/session events; users who disable the title (`terminal_title_enabled`) must be respected |

**Recommendation (revised): A' + B, F as a B bonus:**

- **A' (danger theme, default user only):** `/home/$DEFAULT_USER/.config/
  opencode/tui.json` with `"theme": "opencode-danger"` + the theme file
  in `~/.config/opencode/themes/` — deployed only-if-absent exactly
  like the deny-all lockout next door (install.sh:1442 pattern). No
  tui.json for the opencode user at all (theme freedom preserved —
  nothing shadows `/theme`).
- **B (status text — now the primary mode display):** `files/tui-plugin/`
  ships a tiny plugin rendering `opencode-permissions-kit (<version>) Mode: no ddev/docker` / `opencode-permissions-kit (<version>) Mode: with ddev/docker`,
  reading install.conf + probing the socket. Placement constraints
  (verified, see §3.8): "right after the path" is NOT available as an
  append — the only universal, non-forking slot is `app_bottom`
  (append mode, one thin row, home + session screens). Rendering in
  `home_footer` itself is possible but single_winner means replacing
  the built-in footer wholesale (fork risk on every upstream update,
  e.g. 1.18.21's cost/context column) — B1 below.
- **F (cheap extra inside B):** the same plugin suffixes the terminal
  title (e.g. `OC | session — docker/ddev`), re-asserted on route/
  session events, gated on the user's `terminal_title_enabled` KV
  state; and may call `triggerNotification` when the backend socket
  dies mid-session.

## 5. Design sketch (for the implementing PR)

1. **Mode derivation helper** (`opencode-permissions-kit-lib/`):
   `kit_mode()` → `no-ddev-docker|with-ddev-docker` from install.conf
   (backend stamps) + optional socket probe. Used by the plugin (which
   reads install.conf itself — a shell-out or a duplicated tiny
   parser). `danger` is not an install.conf state — it is the identity
   signal (TUI running under the developer's HOME) and needs no
   derivation: the red theme
   file is static.
2. **Theme choice (revised):** exactly ONE shipped custom theme —
   `files/tui-themes/opencode-danger.json` (appendix A draft), deployed
   to `/home/$DEFAULT_USER/.config/opencode/themes/` only. The opencode
   user gets NO theme/tui.json (theme freedom preserved). The
   default-user tui.json references the theme by name; if a future
   opencode renames the schema, the theme silently stops loading
   (fallback: default theme) — the deny-all lockout still guards, the
   red was always only a visual amplifier.
3. **tui.json ownership (default user only):** kit writes the file
   only if absent or previously kit-written (marker key
   `_opencode_permissions_kit: true`, ignored by opencode's schema).
   Never clobber user edits — identical to the deny-all policy at
   install.sh:1441; document the escape hatch (`config.sh tui-reset`?).
   Project-level `tui.json` (closer to cwd) still outranks the global
   file — acceptable and worth a docs note. The opencode user's
   tui.json (plugin registration, see 4) follows the same ownership
   rules.
4. **Plugin (primary mode display)** in `files/tui-plugin/`: no npm
   deps, plain JS, defensive `try/catch` everywhere (a broken plugin
   must never take the TUI down), unit-testable mode parser,
   version-pinned CI smoke test (start TUI headless, assert the slot
   renders). Renders `opencode-permissions-kit (<version>) Mode: no ddev/docker` / `opencode-permissions-kit (<version>) Mode: with ddev/docker`:
   - v1: slot **`app_bottom`** (append, own thin row, all screens) —
     zero fork risk.
   - optional variant **B1**: register `home_footer` with `order < 100`
     to win single_winner and re-render the stock footer plus a mode
     chip after the path — behind a per-opencode-version compatibility
     check (the stock footer's internals drift, e.g. 1.18.21).
   - the plugin tui.json lives on the opencode user only (the bypass
     TUI deliberately gets NO kit plugin — it is the thing being
     warned about, and the plugin could not trust its environment
     anyway).
 5. **Update flow:** `update.sh` re-deploys the theme/plugin and
   re-renders the tui.json files (same KIT_FILES pattern as the other
   payloads); backend toggles (`config.sh container-backend`) need no
   re-render anymore (the plugin derives the mode live).

## 5a. Spike validation (2026-08-23, WSL2, opencode 1.18.21)

Option B proved on the maintainer's machine with a minimal spike
(project `.opencode/tui.json` + bare `.tsx` plugin registering
`app_bottom`):

- **The bare plugin loads with ZERO npm installs** in the project or
  config dir — JSX (`@opentui/solid` runtime) and the
  `@opencode-ai/plugin/tui` type-only import resolve against
  opencode's own transpile/bundle. The feared dependency-resolution
  blocker does not exist; the shipped kit plugin needs no node_modules.
- **`app_bottom` renders** as a thin own row at the very bottom, on the
  home screen and inside sessions.
- **`api.theme.current` colors work** — the text followed the user's
  own theme (osaka-jade: cyan-ish `info`), i.e. the status text adapts
  to any user theme instead of fighting it.
- **Mode derivation live from install.conf** (`CONTAINER_BACKEND=`
  regex) worked; the displayed string was the pre-revision wording
  (`Mode: docker/ddev`) — later revised to
  `opencode-permissions-kit (<version>) Mode: with ddev/docker`.
- Side observation: the wrapper correctly refused to start in an
  unregistered directory (`/tmp/...`) until
  `config projects add` registered it — the plugin path needs no
  change, but an install-time note "the TUI shows Mode: ..." should
  mention nothing here; behavior is orthogonal.

Remaining unknowns after the spike: long-term API stability across
opencode releases (pin + smoke test per version stays in the plan) and
whether `theme.install()`/`theme.set()` behave the same for the danger
theme (A' ships the theme as a FILE instead — no plugin needed there,
so this is moot for v1).

## 6. Open questions

- ~~Is `danger` a real kit state?~~ Resolved by the HOME refinement:
  danger = TUI under the developer's own HOME (original binary,
  self-update bypass) — the state the deny-all lockout already guards.
- ~~Theme picks?~~ Decided 2026-08-23 (`matrix`/`github`/custom red),
  then REVISED same day: no kit themes for the opencode user (theme
  freedom + `/theme` shadowing), red `opencode-danger` for the default
  user only. Open: final red tuning after seeing it in a real terminal
  (values in appendix A are a first draft).
- Does a project-local `tui.json` (precedence 3.3-3) override the kit
  theme too easily? Do we care (docs vs code)?
- TUI plugin API stability across opencode releases — do we gate the
  plugin on the installed opencode version (kit knows it) and fall back
  to A-only? Includes the opentui pin (0.4.5 today) — recheck the
  `CliRenderer` surface we use whenever opencode bumps @opentui/*.
- ~~`home_footer` vs `app_bottom`~~ Resolved by §3.8: `home_footer` is
  single_winner (replace-only, fork risk) and the session footer is not
  slotted at all → v1 uses `app_bottom`; footer replacement (B1) is an
  opt-in variant behind a version check.
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
