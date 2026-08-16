# UX Improvement Plan — install / update / status / config / wrapper

Status: **DRAFT for discussion** — interactive style demos live in `tests/ux/`
(run them, pick what you like, then we implement phase by phase).

## 1. Goals

- Professional, calm, consistent output across all kit scripts.
- **Standard install ≤ 3 questions**; an Advanced mode for everything else.
- A **pre-flight inventory** that detects what already exists on the system
  (previous install, tools, risks) before anything is touched.
- One shared visual language (labels, symbols, alignment, colors) in a single
  POSIX-sh helper library, reused by every script.
- Stay scriptable: `--yes` / flags keep working non-interactively, output is
  still greppable, `NO_COLOR` and non-tty are honored.

## 2. Non-goals

- Big ASCII logos / wordmarks (openchamber's block logo is explicitly *not*
  wanted — we liked its `info` / `success` log lines instead).
- Spinners or progress bars — fragile in POSIX sh over `curl | bash`.
- TUI (whiptail/dialog) — must work in a plain piped shell.
- New dependencies (no npm, no python for rendering).

## 3. Visual language

Reference: `local/LAYOUT-EXAMPLES.txt` (openchamber) and
`github/openchamber/scripts/install.sh`.

Two building blocks, one per context:

1. **Process log lines** (what the script is doing right now) — colored,
   aligned keyword labels:

   ```
   info     Checking Node.js...
   success  Node.js v24 found
   warn     /mnt/c is world-readable
   error    ddev 1.24 is too old
   ```

2. **Inventory / checklist items** (state of the world) — symbol column with
   aligned label + note:

   ```
   ✔  WSL2 (Ubuntu 24.04)                    present
   +  user 'opencode' + sharing group        will be created
   ⚠  /mnt/c drvfs mount                     world-readable — restrict pending
   ✖  ddev                                   not installed
   ```

Plus:

- **Section rules**: `  ── Pre-flight ─────────────────────────────`.
- **Slim banner** (default) and an optional **boxed banner** (variant B, see
  `example-styles.sh`) for install/update only.
- **Aligned key/value panels** for status.sh and the completion summary.
- Colors: green / yellow / red / cyan / blue / dim. Disabled automatically
  when `NO_COLOR` is set or stdout is not a tty. `UI_ASCII=1` forces plain
  ASCII fallbacks (`ok`, `+`, `!`, `x`) for broken locales.
- Every script ends with a **summary block**: what changed, where the backup
  is, pending manual steps (`wsl --shutdown`, terminal restart), next command.

Implementation: the demo lib `tests/ux/lib/ux.sh` is the candidate for the
real `files/opencode-permissions-kit-lib/ui.sh`. POSIX sh, zero deps.

## 4. Install flow redesign

### 4.1 First prompt: mode

```
  [1] Standard   recommended — 2–3 questions, safe defaults
  [2] Advanced   full control over every step
  [x] Abort
```

`--yes` maps to Standard with defaults (current flag semantics unchanged).

### 4.2 Pre-flight inventory (always, both modes)

Run **before** any question, render as checklist (§3.2). Probes:

| Probe | How | Influences |
|---|---|---|
| WSL2 | `/proc/version` | non-WSL2 → warn + explicit continue |
| curl, acl | `command -v` | acl missing → apt install + gate |
| ddev | PATH + version parse | < 1.25 → hard abort (unchanged) |
| docker (rootless capable?) | `command -v`, systemd --user | default backend choice |
| podman | `command -v` | Standard exception question (§4.3) |
| existing kit | `opencode` user + group, `install.conf`, wrapper symlink, `projects.conf` | **previous install detected → offer `update.sh` instead**; install = explicit "repair / reconfigure" |
| legacy install | `/etc/opencode/`, `/usr/local/lib/opencode`, docker-group backend | migration hints (existing logic, restyled) |
| opencode binary | `~/.opencode/bin`, `/usr/bin/...` | will be copied + secured; shadow removal noted |
| default-user deny-all config | file exists | backup prompt (Advanced) / auto-backup (Standard) |
| shadow binary risk | `~/.opencode/bin/opencode` exists | listed as ⚠, removal is part of the plan |
| `/mnt/c` exposure | mode bits | ⚠ + auto-restrict in Standard |
| ports | `ip_unprivileged_port_start` | sysctl step in plan |
| audit log dir | `/var/log/opencode-permissions-kit` | info only |

This answers "user opencode exists → there was an install": Standard then
says *"Existing kit v0.0.10 detected — use update.sh to upgrade, or continue
to reconfigure?"*

### 4.3 Standard mode

Exactly these questions:

1. **Project directory** (default `/var/www/vhosts` if it exists).
2. **Git access for opencode?** (default `N`).
3. *Exception*: podman installed → **stay with podman-rootless?** (default
   `Y`). Otherwise docker-rootless, no question.

Everything else runs with recommended values, shown as a numbered plan:

```
  The installer will:
    1. Create user 'opencode' + sharing group (add 'infoai')
    2. Provision docker-rootless for the opencode user        (mandatory)
    3. Group + setgid + default ACLs on /var/www/vhosts
    4. Secure the opencode binary, install the wrapper
    5. Restrict /mnt/c via /etc/wsl.conf                      (pending wsl --shutdown)
    6. Lower ip_unprivileged_port_start to 80                 (ddev-router 80/443)
    7. Deny-all config for your user                          (self-update bypass guard)
    8. Deploy library, sudoers, audit log

  [C] Confirm   [A] Switch to Advanced   [X] Abort
```

Hard gates stay hard: ddev ≥ 1.25, rootless provisioning failure aborts.

### 4.4 Advanced mode

Same steps, but every decision gets its own (restyled) prompt, logically
reordered: environment → existing install → backend → ports → WSL →
projects → binary → git-config → deny-all handling. Advanced extras worth
adding: skip the ACL baseline, keep existing configs untouched.

### 4.5 Completion screen

What was installed (paths), backup dir, **pending manual steps** (new
terminal, `wsl --shutdown`), and the next commands (`opencode`, `status.sh`,
`config.sh`). No wall of text — key/value panel.

## 5. Decision needed: docker classic (root docker)

**Recommendation: keep it removed — do not re-add, not even in Advanced.**

- A root docker socket is root-equivalent; in the soft-only model UID
  separation is the *only* hard guarantee. Shipping a mode that disables the
  product's core promise is a contradiction for a "permissions kit".
- It was deliberately removed (DDEV-WORKING); `update.sh` already aborts on
  legacy docker-group installs. Re-adding means reopening sudoers, docs,
  tests, and e2e for an insecure path.
- Better answer for rootful-docker-only users: the pre-flight detects
  "rootful docker only" and prints how to add rootless (doc link), offering
  podman-rootless as the alternative. Never a silent fallback.

For the feeling of the alternative, `tests/ux/example-install-advanced.sh`
demonstrates the warning-flow variant (selectable behind a typed
confirmation) — implemented only for this discussion.

## 6. update / status / config / wrapper

- **update.sh**: banner + numbered steps (fetch → deploy → sudoers →
  migrations → binary → refresh) with `info/success` lines, summary incl.
  pending WSL actions and old→new version. Flags unchanged.
- **status.sh**: aligned panel grouped by concern (Mode / Backend / ddev /
  Projects / Warnings), checklist symbols for readiness, leak scan at the
  end. Exit-code semantics unchanged.
- **config.sh**: numbered **menu loop** (projects add/remove/list, backend
  switch, git-config, refresh) instead of flag-only; flags stay for scripts.
- **wrapper**: stays minimal — one header line plus warnings only. It runs
  daily; it must never become a wall of text.

## 7. Rollout (each phase ships independently)

1. Extract `files/opencode-permissions-kit-lib/ui.sh` from the demo lib +
   unit tests (`tests/test-ui.sh`: NO_COLOR, non-tty, ASCII fallback).
2. `status.sh` (read-only, lowest risk — first visible win).
3. `update.sh` + `config.sh`.
4. `install.sh` Standard/Advanced + pre-flight inventory; e2e asserts the
   new flow; `--yes` path verified non-interactive.
5. Wrapper touch-ups last.

Constraints: file names, flags, `install.conf`/`projects.conf`/
`opencode.jsonc` semantics unchanged. Update MANUAL.md per phase.

## 8. Demo playground: `tests/ux/`

Nothing there executes anything — pure simulated output with short sleeps.

| Script | Shows |
|---|---|
| `example-install-standard.sh` | Full Standard flow: inventory, 2 questions, plan, confirm, simulated run, completion |
| `example-install-advanced.sh` | Advanced prompts incl. the docker-classic warning variant (§5) |
| `example-update.sh` | Proposed update.sh output |
| `example-status.sh` | Proposed status.sh panel |
| `example-styles.sh` | Side-by-side style variants (labels vs symbols vs brackets, banner variants, density) |

Run: `sh tests/ux/example-install-standard.sh` (questions accept Enter for
the default; piped/EOF input falls back to defaults).

## 9. Open questions (need your call)

1. Docker classic: follow §5 recommendation (keep removed)?
2. Non-WSL2 host: keep "continue anyway?" prompt, or hard-abort in Standard?
3. Standard + `/mnt/c` world-readable: auto-restrict without asking (it only
   takes effect after `wsl --shutdown` anyway)?
4. Symbols default: Unicode (✔ ⚠ ✖) with `UI_ASCII=1` fallback — OK?
5. Banner: slim line (default) or boxed variant B?

## 10. References

- openchamber installer — `github/openchamber/scripts/install.sh` (label
  style, hand-off-to-update pattern).
- Other installers worth studying for patterns (no need to fetch, but
  transcripts help): rustup, oh-my-zsh, Homebrew `install.sh`,
  `get.docker.com`, pnpm / bun / deno one-liners, ddev's install script.
- `NO_COLOR` convention — https://no-color.org.
- Most useful thing you can provide: raw terminal transcripts of tools whose
  output you like (like `local/LAYOUT-EXAMPLES.txt`), one file per tool.
