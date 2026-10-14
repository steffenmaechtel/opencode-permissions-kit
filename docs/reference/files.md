# Files and paths

This page lists every file and directory the kit manages, and every key in
`install.conf`.

## /etc/wsl.conf

Never written by the kit — your WSL configuration stays yours: install
and update only *print* snippets for you to apply yourself
([why](../../internal/records/wsl-conf-consent.md)). One optional kit artifact can
live in it, written by a single explicit command:
`sudo opk wsl-add-opencode-1-fix` places the browser-bridge **comment
block** at the top (WSL only; its carrier line — a `#` comment containing
a raw carriage return before `root = …` — wins the `open` package's scan
and redirects opencode's powershell lookup to the browser bridge
stand-in; WSL itself only ever sees comments, so no warning, no restart
needed). Only relevant for opencode **1.x < 1.18.33 and 2.x < 2.0.18** —
newer versions ship a WSL-safe browser opener (open@11 falls back to
`xdg-open`; the kit deploys a fallback shim when no real one exists).
The `[automount]` hardening is yours to add manually.
Uninstall asks before removing the kit block (or assumes yes with
`--yes`); your own entries always stay.

## /etc/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `install.conf` | Install settings (keys below) |
| `projects.conf` | Project roots, one per line |
| `handover/` | Scan-skip stamps for the ddev handover |

- `projects.conf` paths must not contain spaces — the writer splits on
  them and every consumer reads the file line-by-line.
- `handover/` holds one root-owned file per project root recording the
  last completed handover pass
  ([issue #112](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/112)). A matching stamp lets a plain
  `opk update` skip the rescan; `update --refresh` and the `opk config`
  paths always re-scan. Purely an optimization — deleting it costs one
  extra scan.

### `install.conf` keys

| Key | Meaning |
|---|---|
| `DEFAULT_USER` | The developer's user (kit admin) |
| `OPENCODE_USER` | The agent user (always `opencode`) |
| `CONTAINER_BACKEND` | `docker-rootless` \| `podman-rootless` |
| `OPENCODE_DOCKER_HOST` | `docker-rootless` socket, e.g. `unix:///run/user/<opencode-uid>/docker.sock` |
| `OPENCODE_PODMAN_SOCKET` | Optional podman docker-CLI-compat socket |
| `DDEV_VERSION` | ddev version recorded at install time, re-probed by every `opk update` |
| `DDEV_DEV_OWNED` | `true` = dev-owned settings mode, `false` = ddev-managed (handover model) |
| `DDEV_EXPORTED` | `1` once a ddev database export wave completed — later installs/updates skip the export |
| `OPENCODE_MAJOR` | installed opencode binary's major (1 or 2); gates the wrapper's 2.x-only flags |
| `OPENCHAMBER_POLICY` | `yes` = the OpenChamber policy pin is active |
| `KIT_CHANNEL` | Ref installs/updates track (`stable`, `master`, a feature branch, or a pinned tag) |
| `OPENCODE_GROUP` | Always the `opencode` usergroup (informational) |
| `HARD_DENY_REMOVED` | unused (historical migration stamp; see [update](../how-to/update.md)) |
| `VERSION` | Deployed kit version |

Key notes:

- `DDEV_VERSION` is a fallback — `status.sh` reports the live
  `ddev --version`: directly, or through the ddev-as-opencode helper
  when run as root, since ddev ≥ 1.25.4 refuses root (flags < 1.25).
- `DDEV_DEV_OWNED`: dev-owned mode makes the kit write
  `disable_settings_management: true`; toggled by
  `opk config ddev-settings`.
- `OPENCODE_MAJOR` is best effort — the wrapper detects the major at
  runtime when missing.
- `OPENCHAMBER_POLICY`: opt-in from the install prompt,
  `--openchamber-policy yes`, or `opk openchamber-secure`; `opk update`
  re-applies the pin only on `yes`.
- `KIT_CHANNEL` is set by `install.sh`, re-stamped by `update.sh`,
  shown by `opk status`.
- `HARD_DENY_REMOVED`: updates from < 0.0.14 are refused.

## /etc/openchamber/

| Path | Purpose |
|---|---|
| `policy.json` | OpenChamber system policy — kit-owned while it pins the kit wrapper (see below) |

Kit-owned when it pins `opencodeBinary` to `/usr/local/bin/opencode`
(`root:root` 0644): makes OpenChamber spawn the kit wrapper
machine-wide (web, desktop, VS Code) regardless of its settings pin —
see [the how-to](../how-to/openchamber.md#prevent-the-bypass-the-policy-pin).
Written by the install opt-in or `opk openchamber-secure`, re-applied by
`opk update` only while the file still matches the kit one-liner — a
file with other content is admin-owned: install/update skip it with a
warning, and only `opk openchamber-secure` replaces it (announced).
`opk uninstall` removes it only when it pins the kit wrapper.

## /etc/sudoers.d/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit` | `(opencode)` RunAs rights for the kit binary, the probes, and the ddev helper |

Grants `(opencode)` RunAs for the kit binary, the socket-check/cwd-check
probes, and the ddev-as-opencode helper; keeps `DOCKER_HOST` and
`XDG_RUNTIME_DIR` in env_keep.

## /etc/profile.d/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit-umask.sh` | umask 002 + PATH precedence + wrapper-bypass warning at login |

## /home/

| Path | Purpose |
|---|---|
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with the soft deny list |
| `/home/opencode/.ddev/` | opencode user's global ddev home |
| `/home/opencode/.config/opencode/tui.json` | TUI mode display registration (kit-managed) |
| `/home/<dev>/.config/opencode/opencode.jsonc` | deny-* lockout config (self-update bypass) |
| `/home/<dev>/.config/opencode/tui.json` | TUI mode display registration for the default user |
| `/home/<dev>/.config/opencode/themes/opencode-danger.json` | red danger theme (the bypass warning) |
| `/home/<dev>/.config/opencode/plugins/opencode-permissions-kit/` | opencode 2.x local CLI plugin dir |

- `tui.json` is kit-managed for the mode registration only — the user's
  own theme choice is never touched.
- The plugin dir carries the kit-mode-2x registration; it is skipped
  when user-managed symlinks are present.

## /usr/local/

The deployed library mirrors the repository layout
(`files/opencode-permissions-kit-lib/`) one-to-one. Folder semantics:
`bin/` = commands (no extension), `sh/` = sourced shell libraries,
`py/` = python, `management/` = management entry scripts,
`templates/` = render sources, `tui/` = TUI assets.

| Path | Purpose |
|---|---|
| `/usr/local/bin/opencode` | Wrapper symlink → `bin/opencode-as-opencode` |
| `/usr/local/bin/opk` | CLI dispatcher symlink (see [CLI](cli.md)) |
| `/usr/local/bin/xdg-open` | xdg-open fallback shim symlink → `bin/xdg-open` |
| `/usr/local/lib/opencode-permissions-kit/bin/opencode` | The actual opencode binary (`root:opencode` 750) |
| `/usr/local/lib/opencode-permissions-kit/bin/opencode-as-opencode` | The wrapper: validation, opt-in, rootless exec |
| `/usr/local/lib/opencode-permissions-kit/bin/opk` | CLI dispatcher (status/config/update/uninstall routing) |
| `/usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode` | Sudoers helper: runs ddev as `opencode` |
| `/usr/local/lib/opencode-permissions-kit/bin/ddev-migrate` | Database bridge CLI for the daemon switch |
| `/usr/local/lib/opencode-permissions-kit/bin/setup-container-backend` | Rootless backend provisioning |
| `/usr/local/lib/opencode-permissions-kit/bin/socket-check` | Rootless socket probe (`test -S` only) |
| `/usr/local/lib/opencode-permissions-kit/bin/cwd-check` | Headless serve cwd probe (readable-for-opencode check) |
| `/usr/local/lib/opencode-permissions-kit/bin/browser-bridge` | WSL browser bridge stand-in source (`wsl/` tree) |
| `/usr/local/lib/opencode-permissions-kit/bin/xdg-open` | xdg-open fallback shim → `bin/browser-bridge` |
| `/usr/local/lib/opencode-permissions-kit/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` | WSL bridge |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh` | Sourced `ddev()` terminal function |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-handover.sh` | Shared helper: `.ddev` + settings-dir chown |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-hosts.sh` | Shared helper: Windows hosts bridge |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-migrate.sh` | Shared helper: migration functions |
| `/usr/local/lib/opencode-permissions-kit/sh/advisories.sh` | Shared helper: security-advisory database |
| `/usr/local/lib/opencode-permissions-kit/sh/fs-baseline.sh` | Shared helper: group baseline recursion |
| `/usr/local/lib/opencode-permissions-kit/sh/git-check.sh` | Shared helper: git presence/version probe |
| `/usr/local/lib/opencode-permissions-kit/sh/wsl-browser-bridge.sh` | Shared helper: WSL browser bridge deploy |
| `/usr/local/lib/opencode-permissions-kit/sh/log.sh` | Shared helper: audit logging |
| `/usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh` | Shared helper: bypass warnings |
| `/usr/local/lib/opencode-permissions-kit/sh/staged-write.sh` | Shared helper: symlink-safe privileged writes |
| `/usr/local/lib/opencode-permissions-kit/sh/sudoers-deploy.sh` | Shared helper: the sudoers pipeline |
| `/usr/local/lib/opencode-permissions-kit/sh/secure-binary.sh` | Shared helper: binary hardening |
| `/usr/local/lib/opencode-permissions-kit/sh/deploy-lib.sh` | Shared helper: library deployment manifest |
| `/usr/local/lib/opencode-permissions-kit/sh/render-agent-config.sh` | Shared helper: opencode.jsonc render |
| `/usr/local/lib/opencode-permissions-kit/sh/tui-plugin.sh` | Shared helper: TUI 2.x plugin registration |
| `/usr/local/lib/opencode-permissions-kit/sh/ui.sh` | Shared helper: labeled output |
| `/usr/local/lib/opencode-permissions-kit/management/config.sh` | Management: projects, git-config, backend, refresh |
| `/usr/local/lib/opencode-permissions-kit/management/update.sh` | Management: re-deploy, binary upgrades |
| `/usr/local/lib/opencode-permissions-kit/management/status.sh` | Management: status + leak scan |
| `/usr/local/lib/opencode-permissions-kit/management/uninstall.sh` | Management: uninstall |
| `/usr/local/lib/opencode-permissions-kit/py/jsonc-parser.py` | Shared helper: config parsing |
| `/usr/local/lib/opencode-permissions-kit/py/tui-register.py` | Shared helper: cli.json plugin-entry cleanup |
| `/usr/local/lib/opencode-permissions-kit/templates/sudoers.template` | Template: sudoers rendering |
| `/usr/local/lib/opencode-permissions-kit/templates/opencode.jsonc` | Template: the agent's soft deny config |
| `/usr/local/lib/opencode-permissions-kit/templates/opencode-deny-all.jsonc` | Template: default-user lockout config |
| `/usr/local/lib/opencode-permissions-kit/tui/` | TUI mode display: plugin + theme/config templates |

Deployment notes (details that do not fit the table above):

- `/usr/local/bin/xdg-open` is deployed only while no real xdg-open
  exists — opencode 1.18.33+/2.0.18+ device-logins crash without it.
- `bin/opencode-as-opencode` — the wrapper: directory validation,
  container opt-in, rootless exec.
- `bin/ddev-as-opencode` re-sets `HOME`/`XDG_RUNTIME_DIR`/`DOCKER_HOST`.
- `bin/ddev-migrate` — export (dev user, install time) + import/list
  (post-install).
- `bin/browser-bridge` is deployed into the `wsl/` tree (see below);
  re-deployed by `opk wsl-add-opencode-1-fix`.
- `bin/xdg-open` delegates to `bin/browser-bridge` (Start-Process);
  symlinked as `/usr/local/bin/xdg-open` while no real xdg-open exists.
- `wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe` —
  stand-in the bundled `open` package spawns for device logins; it
  forwards to the real powershell.exe when the caller may execute it,
  `exit 0` otherwise (WSL only; see
  [security model](../concepts/security-model.md#wsl2-the-browser-bridge-login-survival-on-a-hardened-mntc)).
- `sh/ddev-terminal.sh` is hooked into the default user's rc files.
- `sh/ddev-migrate.sh` is sourced by install.sh and `bin/ddev-migrate`.
- `sh/advisories.sh` — the kit's static advisory database; checked by
  the wrapper on every start, diffed against the upstream feed by
  `opk status`.
- `sh/git-check.sh` probes against the soft tested floor; sourced by
  the install/update pre-flight and the `git` row in `opk status`.
- `sh/wsl-browser-bridge.sh` — wsl.conf comment block + stand-in.
- `sh/staged-write.sh` — `staged_write` staging + the `agent_home_sane`
  walker.
- `sh/sudoers-deploy.sh` — charset gate, render, visudo validation,
  install, sudoers.d link.
- `sh/secure-binary.sh` — `chown root:<group>` + the load-bearing
  `chmod 750`, fail-loud.
- `sh/deploy-lib.sh` — `lib_deploy`, the single source of truth for
  what ships into `$LIBDIR`.
- `sh/render-agent-config.sh` — `agent_config_render`, the SECURE_GIT
  on/off pair.
- `sh/tui-plugin.sh` — `tui_plugin_sync_user`: per-user plugin dir +
  symlink, major-gated.
- `py/tui-register.py` — opencode 2.x.

## /var/log/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit.log` | Audit log (mode 750/640, self-rotating) — see [audit log](audit-log.md) |

## ddev-managed directories

Which project directories the kit hands over to the `opencode` user (and
why) is explained in [ddev integration](../concepts/ddev-integration.md).
