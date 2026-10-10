# OpenChamber 2.x hardening — design record

> Status: **CURRENT (verification done, implementation pending).** How the
> kit closes the OpenChamber settings-pin bypass: wrapper detection
> (Tier 1), an admin-owned policy pin (Tier 2), and `opk` integration
> (Tier 3). Issue #154, follow-up to #144 (2.x compatibility, PR #153).
> Mechanism findings are source-verified (openchamber v2.2.0 and opencode
> v2.0.22 checkouts); the policy pin was live-verified end-to-end on a
> second WSL install (2026-10-10, §6). User-facing how-to:
> [openchamber.md](../how-to/openchamber.md).

## 1. Problem: the one-click bypass

The kit secures `opencode` through the PATH wrapper
(`/usr/local/bin/opencode`). OpenChamber bypasses PATH in exactly one
place: its **settings pin** (`opencodeBinary` in
`~/.config/openchamber/settings.json`). The pin is created by the
one-click "Update to OpenCode 2" that OpenChamber offers whenever the
kit-managed opencode is below OpenChamber's 2.0.20 minimum. Once pinned:

1. every OpenChamber session runs as the developer — no UID separation,
   no permission layer (split brain with the secured terminal),
2. OpenChamber's own update affordances stay active (they do not know
   about `opk`),
3. after deleting the binaries without clearing the pin, OpenChamber
   hangs permanently ("OpenCode port is not available", survives a
   reboot).

The wrapper sees none of this — OpenChamber spawns the pinned binary
directly. A hard block in the wrapper is therefore the wrong tool: it
would only hit the still-secured terminal/headless starts, not the
bypass.

## 2. Verified facts (Oct 2026)

| Fact | Source |
|---|---|
| OpenChamber 2.x version gate: opencode ≥ 2.0.20, major 2 | `compatibility.js:15`; live (2.0.19 → update screen) |
| Compatible and secured from 2.0.20 through the wrapper | live (2.0.20, 2.0.26) |
| Update-toast button fails harmlessly (no install method detected) | `updater.ts` method detection; live |
| One-click installs `~/.opencode/bin/opencode` + `opencode2` shim and pins settings | `v2-install.js:109/110`, `index.js:2466`; live |
| A dead pin blocks server start (strict, no retry) | `lifecycle.js:731`, `:861`; live |
| Only the compatibility check falls back to PATH (masks the pin < 2.0.20) | live |
| Policy file `/etc/openchamber/policy.json` (Linux, admin-owned) with `opencodeBinary` field | `enterprise-mode.js:99/:105`, `policyFilePaths` |
| Policy pin wins over settings pin, env, PATH — "never falls back" | `env-runtime.js` `applyPinnedOpencodeBinary`; live 2026-10-10 |
| Policy pin disables install-v2 (`canInstall` factor `!pinnedByPolicy`) | `index.js:1533f`, `compatibility.js:94`; live 2026-10-10 |
| Policy pin disables the upgrade affordances | `upgrade-capability.js:17-23`; live: the affordance never renders |
| Policy is read by web server, desktop (same server core), and the VS Code extension | `vscode/src/opencode.ts:223-246`, `opencode-upgrade-runtime.ts:49` |
| `opencodeBinary` works without `enterpriseMode: true`; empty string = unset | `enterprise-mode.js:100f`; live 2026-10-10 |
| `root:root 0644` is sufficient (OpenChamber reads it as the user) | live 2026-10-10 |

## 3. Tier 1 — detection: extend the wrapper guard (warn and continue)

Extend the self-installed-binary guard in `opencode-as-opencode` (the
block around `SHADOW="$HOME/.opencode/bin/opencode"`). Detection, all in
the calling user's context:

- `$HOME/.opencode/bin/opencode` and/or the `opencode2` shim, **and/or**
- an OpenChamber settings pin: `opencodeBinary` in
  `~/.config/openchamber/settings.json` (covers the binary-deleted hang
  state too — the pin outlives the binaries).

State-specific messages, at most three states:

1. binary + pin → "OpenChamber sessions currently run OUTSIDE the kit"
2. binary without pin → the current message, corrected (naming `opencode2`)
3. pin without binary → "OpenChamber will hang: OpenCode port is not
   available"

Fix advice is always two-step: delete the binaries **and** remove the
settings line (or set it to `""`), with a link to the how-to. Warn and
continue, consistent with the other wrapper guards — no hard block (§1).

Constraints confirmed live (2026-10-10): the guard only runs on regular
interactive session starts — never for `--version|-v|-h|--help`
(fast-path since #91) and not from invalid directories (the
"cannot be started here" exit comes first). The current message's gaps,
as captured on a live bypass state:

```
WARNING: self-installed opencode detected at /home/<dev>/.opencode/bin/opencode
New shells would run it instead of this wrapper. Fix: rm -rf /home/<dev>/.opencode/bin/opencode
```

It does not mention the `opencode2` shim, not the settings pin (the
actual bypass), its fix advice would **create the documented hang state**
(pin without binary), and "new shells would run it" is the wrong risk
description for the OpenChamber case (the bypass rides the settings pin,
not PATH).

Unit tests for the three states in
`tests/unit/test-opencode-as-opencode.sh`; e2e per the wrapper
definition-of-done (`e2e` + `e2e-rootless`).

## 4. Tier 2 — prevention: the policy pin (the actual lever)

The kit writes (opt-in, §7 A) `/etc/openchamber/policy.json`:

```json
{ "opencodeBinary": "/usr/local/bin/opencode" }
```

Effects (all code-verified, §2; the first three live-verified, §6):

- OpenChamber spawns the kit wrapper from then on — the policy beats the
  settings pin, env, and PATH, **retroactively**: an existing one-click
  pin is defused without anything to clean up first.
- Both self-update paths are disabled (install-v2 + upgrade affordances);
  with the policy in place the update hints do not render at all.
- Machine-wide for web, desktop, and VS Code; independent of whether
  OpenChamber is installed before or after the kit.
- The version gate stays: kit-opencode < 2.0.20 → update screen with no
  working install path ("Check again" only) → the only way forward is
  `opk upgrade-opencode`. That is exactly the desired behavior.

Rollout lives in `files/opencode-permissions-kit-lib/management/` — the
same lifecycles as sudoers/Projects.conf: install prompt + update.sh
re-apply (only when chosen or already present) + uninstall.sh removal.
The file is new kit-owned property in `/etc` — no third-party config is
edited (the `wsl-conf-consent` precedence does not apply; the opt-in
prompt exists anyway, §7 A).

Upstream risk: OpenChamber could change the policy format. Mitigation: a
release check in the compatibility process (like the opencode matrix);
an advisories-style break check would be overkill —
[compatibility.md](../reference/compatibility.md) keeps the page current.

## 5. Tier 3 — repair and visibility: `opk`

- `opk status`: an "OpenChamber" line — not installed / secured via
  policy / **BYPASSED** (pin or binaries present) / policy missing —
  analogous to the sharing/backend lines.
- `opk openchamber-secure`: idempotent command — 1. write policy.json
  (Tier 2), 2. clean bypass binaries + settings pin (with confirmation),
  3. report. For after-the-fact installs and for repair when the install
  prompt was declined.

## 6. Live verification (2026-10-10)

Second WSL install: kit 0.0.47, OpenChamber 2.2.0, kit-opencode
2.0.26 / 2.0.20 / 2.0.19. The bypass state was reproduced **naturally**
(downgrade to 2.0.19 → one-click → real binaries + shim + pin), then the
policy `{"opencodeBinary": "/usr/local/bin/opencode"}` was applied as
`root:root 0644`, no `enterpriseMode`. Results:

1. **Policy wins standalone, retroactively** — with the settings pin
   still pointing at the developer-installed 2.0.26, OpenChamber spawned
   the wrapper: `openchamber(dev) → sudo -u opencode (NOPASSWD via the
   kit sudoers rule) → serve as user opencode`.
2. **Version gate under policy** — update screen reads "OpenCode 2.0.19
   is installed. This version of OpenChamber requires OpenCode 2.0.20 or
   newer."; only button left: "Check again". Hours earlier, in the same
   state without the policy, the one-click button worked.
3. **Update hints suppressed entirely** — policy + 2.0.20 (compatible,
   not latest): no toast, no upgrade button. Stronger than the
   code-verified expectation (expected a disabled button plus the
   "Your administrator manages this OpenCode installation." message).
4. **Settings UI: no conflict** — with both pins present, Settings →
   General → OpenCode shows the policy path read-only ("Your
   administrator set this path, so OpenChamber always starts OpenCode
   from it."); the stale settings pin is masked in the UI but stays in
   the file (cleanup case for Tier 3).
5. **Permissions** — `root:root 0644` suffices.

Not tested: the Electron desktop app (web only on the machine; a
Windows-side desktop app reads Windows policy paths, not
`/etc/openchamber` — a docs caveat when Tier 2 ships) and the VS Code
extension (policy read is code-verified).

## 7. Decisions (2026-10-10)

- **A — rollout: opt-in install prompt** ("Protect OpenChamber sessions
  too?"), because it changes third-party app behavior (update buttons
  disappear). `opk openchamber-secure` retrofits; update re-applies only
  when chosen or already present.
- **B — command name: `opk openchamber-secure`.**
- **C — no e2e with real OpenChamber in stage 1** — unit tests for the
  guard states + the manual verification checklist folded into the docs;
  optional later: a scripted e2e that only checks policy resolution of
  the real openchamber CLI (npm-installable), without UI.

## 8. Scope decisions

- **Everything stays in this repo** — no separate
  "openchamber-permissions-kit" repository: OpenChamber ultimately spawns
  opencode, and the protected asset is this kit's wrapper plus its
  user/project/backend model. A second repo would have to duplicate the
  whole install/update/channel/status machinery. The OpenChamber-specific
  surface here is small: one guard block, one policy file, one `opk`
  command, one docs page.
- **No `openchamber` command wrapper** (PATH shadowing of the
  `openchamber` command): with Tier 2 in place the policy enforces the
  wrapper as spawn target more reliably than a shell wrapper (which only
  sees interactive starts and would need the user's start context). A
  second shadowed command would add trust/maintenance surface for pure
  detection/messaging. **Revisit criterion:** if OpenChamber-specific
  features grow (per-chat worktree ACLs, `OPENCHAMBER_CHATS_DIR`
  management), reassess — then as a plugin/command here, not as a repo.

## 9. Non-goals

- No hard wrapper block on the bypass state (breaks the secured paths,
  does not stop the bypass — §1).
- No monitoring of or interference with running OpenChamber processes.
- No support for running OpenChamber 2.x against opencode < 2.0.20
  (upstream gate; the sanctioned path is `opk upgrade-opencode`).
- No second repo, no `openchamber` command wrapper (§8).

## 10. Implementation order

1. **Tier 1** — guard extension + unit tests; e2e per the wrapper DoD.
2. ~~Live verification of the policy pin~~ — done (§6).
3. **Tier 2** — policy via install/update/uninstall + opt-in prompt.
4. **Tier 3** — `opk status` line + `opk openchamber-secure`.
5. Docs sync with each tier: how-to extension, compatibility caveat,
   cli reference for the new command.
