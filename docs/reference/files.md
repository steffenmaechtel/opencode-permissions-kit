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
| `CONTAINER_BACKEND` | `docker-rootless` \| `podman-rootless` (legacy `docker-group` → warning, no tools) |
| `OPENCODE_DOCKER_HOST` | `docker-rootless` socket, e.g. `unix:///run/user/<opencode-uid>/docker.sock` |
| `OPENCODE_PODMAN_SOCKET` | Optional podman docker-CLI-compat socket |
| `DDEV_VERSION` | Recorded ddev version (advisory; `status.sh` flags < 1.25) |
| `OPENCODE_GROUP` | Always the `opencode` usergroup (informational; legacy installs may still carry the old `WWW_GROUP` key — readers fall back to it, `update.sh` renames it away) |
| `HARD_DENY_REMOVED` | Migration stamp — `1` once the soft-only migration ran |
| `VERSION` | Deployed kit version |

## /etc/sudoers.d/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit` | `(opencode)` RunAs for the kit binary, the socket-check probe, and the ddev-as-opencode helper; `DOCKER_HOST`/`XDG_RUNTIME_DIR` env_keep |

## /home/

| Path | Purpose |
|---|---|
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with the soft deny list |
| `/home/opencode/.ddev/` | opencode user's global ddev home |
| `/home/<dev>/.config/opencode/opencode.jsonc` | deny-* lockout config (self-update bypass) |

## /usr/local/

| Path | Purpose |
|---|---|
| `/usr/local/bin/opencode` | Wrapper symlink |
| `.../opencode-permissions-kit/bin/opencode` | The actual opencode binary (`root:opencode` 750) |
| `.../opencode-permissions-kit/bin/socket-check.sh` | Rootless socket probe (`test -S` only) |
| `.../opencode-permissions-kit/bin/ddev-as-opencode` | Sudoers helper that runs the real ddev as `opencode` (re-sets `HOME`/`XDG_RUNTIME_DIR`/`DOCKER_HOST`) |
| `.../opencode-permissions-kit/ddev-as-opencode.sh` | Sourced `ddev()` terminal function (hooked into the default user's rc files) |
| `.../opencode-permissions-kit/wrapper` | Directory validation, container opt-in, rootless exec |
| `.../opencode-permissions-kit/migrate-denies.sh` | One-time hard-deny → soft-only migration (+ `.ddev` handover) |
| `.../opencode-permissions-kit/setup-container-backend.sh` | Rootless backend provisioning |
| `.../opencode-permissions-kit/{config,update,status,uninstall}.sh` | Management |
| `.../opencode-permissions-kit/{jsonc-parser.py,log.sh,shell-warn.sh,sudoers.template,opencode.jsonc,opencode-deny-all.jsonc}` | Shared helpers/templates |

## /var/log/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit.log` | Audit log (mode 750/640, self-rotating) — see [audit log](audit-log.md) |

## ddev-managed directories

Which project directories the kit hands over to the `opencode` user (and
why) is explained in [ddev integration](../concepts/ddev-integration.md).
