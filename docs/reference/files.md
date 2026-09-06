# Files and paths

This page lists every file and directory the kit manages, and every key in
`install.conf`.

## /etc/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `install.conf` | Install settings (keys below) |
| `projects.conf` | Project roots (one per line) |

### `install.conf` keys

| Key | Meaning |
|---|---|
| `DEFAULT_USER` | The developer's user (kit admin) |
| `OPENCODE_USER` | The agent user (always `opencode`) |
| `CONTAINER_BACKEND` | `docker-rootless` \| `podman-rootless` |
| `OPENCODE_DOCKER_HOST` | `docker-rootless` socket, e.g. `unix:///run/user/<opencode-uid>/docker.sock` |
| `OPENCODE_PODMAN_SOCKET` | Optional podman docker-CLI-compat socket |
| `DDEV_VERSION` | Recorded ddev version (advisory; `status.sh` flags < 1.25) |
| `OPENCODE_GROUP` | Always the `opencode` usergroup (informational) |
| `HARD_DENY_REMOVED` | unused (historical migration stamp; updates from < 0.0.14 are refused — see [update](../how-to/update.md)) |
| `VERSION` | Deployed kit version |

## /etc/sudoers.d/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit` | `(opencode)` RunAs for the kit binary, the socket-check/cwd-check probes, and the ddev-as-opencode helper; `DOCKER_HOST`/`XDG_RUNTIME_DIR` env_keep |

## /etc/profile.d/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit-umask.sh` | umask 002 + PATH precedence + wrapper-bypass warning at login |

## /home/

| Path | Purpose |
|---|---|
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with the soft deny list |
| `/home/opencode/.ddev/` | opencode user's global ddev home |
| `/home/<dev>/.config/opencode/opencode.jsonc` | deny-* lockout config (self-update bypass) |

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
| `/usr/local/lib/opencode-permissions-kit/bin/opencode` | The actual opencode binary (`root:opencode` 750) |
| `/usr/local/lib/opencode-permissions-kit/bin/opencode-as-opencode` | The wrapper: directory validation, container opt-in, rootless exec |
| `/usr/local/lib/opencode-permissions-kit/bin/opk` | CLI dispatcher (status/config/update/uninstall routing) |
| `/usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode` | Sudoers helper that runs the real ddev as `opencode` (re-sets `HOME`/`XDG_RUNTIME_DIR`/`DOCKER_HOST`) |
| `/usr/local/lib/opencode-permissions-kit/bin/ddev-migrate` | Database bridge CLI for the daemon switch: export (dev user, install time) + import/list (post-install) |
| `/usr/local/lib/opencode-permissions-kit/bin/setup-container-backend` | Rootless backend provisioning |
| `/usr/local/lib/opencode-permissions-kit/bin/socket-check` | Rootless socket probe (`test -S` only) |
| `/usr/local/lib/opencode-permissions-kit/bin/cwd-check` | Headless serve cwd probe (readable-for-opencode check) |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh` | Sourced `ddev()` terminal function (hooked into the default user's rc files) |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-handover.sh` | Shared helper: `.ddev` + settings-dir chown |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-hosts.sh` | Shared helper: Windows hosts bridge |
| `/usr/local/lib/opencode-permissions-kit/sh/ddev-migrate.sh` | Shared helper: migration functions (sourced by install.sh and `bin/ddev-migrate`) |
| `/usr/local/lib/opencode-permissions-kit/sh/fs-baseline.sh` | Shared helper: group baseline recursion |
| `/usr/local/lib/opencode-permissions-kit/sh/log.sh` | Shared helper: audit logging |
| `/usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh` | Shared helper: bypass warnings |
| `/usr/local/lib/opencode-permissions-kit/sh/ui.sh` | Shared helper: labeled output |
| `/usr/local/lib/opencode-permissions-kit/management/config.sh` | Management: projects, git-config, backend, refresh |
| `/usr/local/lib/opencode-permissions-kit/management/update.sh` | Management: re-deploy, binary upgrades |
| `/usr/local/lib/opencode-permissions-kit/management/status.sh` | Management: status + leak scan |
| `/usr/local/lib/opencode-permissions-kit/management/uninstall.sh` | Management: uninstall |
| `/usr/local/lib/opencode-permissions-kit/py/jsonc-parser.py` | Shared helper: config parsing |
| `/usr/local/lib/opencode-permissions-kit/templates/sudoers.template` | Template: sudoers rendering |
| `/usr/local/lib/opencode-permissions-kit/templates/opencode.jsonc` | Template: the agent's soft deny config |
| `/usr/local/lib/opencode-permissions-kit/templates/opencode-deny-all.jsonc` | Template: default-user lockout config |
| `/usr/local/lib/opencode-permissions-kit/tui/` | TUI mode display: plugin + theme/config templates |

## /var/log/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit.log` | Audit log (mode 750/640, self-rotating) — see [audit log](audit-log.md) |

## ddev-managed directories

Which project directories the kit hands over to the `opencode` user (and
why) is explained in [ddev integration](../concepts/ddev-integration.md).
