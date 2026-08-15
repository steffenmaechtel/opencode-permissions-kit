# opencode permissions kit — Manual

## What It Does

This kit runs [opencode](https://opencode.ai) as a dedicated Linux user
(`opencode`) against a **rootless container backend** (docker-rootless or
podman-rootless) that belongs to that user, and prepares **ddev** to run as
that user.

File permissions are enforced by **opencode's own soft permission layer**
(`opencode.jsonc`) — the kit no longer mirrors deny rules into Linux ACLs.
The kit's hard guarantees are UID-level:

- the agent's processes run as `opencode`, never as the developer (no
  credentials, SSH keys, or dotfiles in `/home/<developer>` are reachable),
- containers run under the `opencode` host UID via a rootless backend — the
  agent can never reach a root-equivalent docker socket,
- no code path executes as the developer (no RunAs-developer sudoers rule).

**Trade-off (deliberate, this is the "ddev must work" decision):** a soft deny
gates opencode's own read/edit tools only. Processes spawned outside opencode
(ddev, its containers, `cat` in bash) can read every project file — including
`settings.php`, which ddev's web container needs to boot. See
[Security Model](#security-model-soft-only). The design record is
`docs/design/DDEV-WORKING.md`.

## Security Model (soft-only)

| Guarantee | Mechanism |
|---|---|
| Agent ≠ developer | wrapper execs `sudo -u opencode`; the developer's home is `750` and not group-shared |
| Containers ≠ root | rootless backend owned by `opencode` (per-user socket / daemonless podman) |
| No developer-RunAs | the sudoers carry only `(opencode)` rules for the kit binary, the socket probe, and the ddev-as-opencode helper |
| File denies (`.env`, keys, …) | `opencode.jsonc` soft rules — enforced by opencode's tools, prompted via bash tripwires |
| Developer ↔ agent file sharing | the `opencode` usergroup: setgid + default group ACLs + umask 002 |
| ddev runs as one user | the `ddev()` terminal function + the sudoers helper exec the real ddev as `opencode`; project `.ddev/` is handed over (one owner, one daemon) |

Known residual gaps, documented rather than hidden:

- Bash-spawned reads (`cat .env`) are only caught by the template's
  **lexical ask-tripwires**, never by the OS.
- A container with a bind mount reads the mounted tree freely.
- Renamed copies of secrets are invisible to the name-based leak scan.

## The Two States

Whether the project's `opencode.jsonc` enables container tools decides what
the session gets — there is exactly one backend mode (rootless) either way:

| | **no container tools** | **container tools opted in** |
|---|---|---|
| Enabled by | project has no docker/ddev allow | project `permission.bash` allows `docker *` / `ddev *` (broadly, not subcommand-only) |
| opencode runs as | `opencode` user | `opencode` user, `DOCKER_HOST` → the user's rootless socket (docker-rootless), or the daemonless podman CLI |
| ddev | denied | runs as `opencode` — always (terminal and agent) |

A project opts in via its own `opencode.jsonc`:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "bash": {
            "ddev *": "allow",
            "docker *": "allow"
        }
    }
}
```

```bash
cd /var/www/vhosts/myproject/ && opencode
```

The wrapper prints the detected tools and asks `Y/n` before starting with the
backend. The bundled global config denies `docker *` / `ddev *` (and their
`sudo` forms), so nothing is granted implicitly.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

The script detects that it is being streamed, fetches its sibling files
(config.sh, update.sh, uninstall.sh, status.sh, wrapper, templates) from the
same `master` branch, and walks you through the setup:

1. **Project folders** — e.g. `/var/www/vhosts` (multi-select or custom).
2. **Rootless container tool** — docker-rootless (default) or podman-rootless.
   Provisioning is mandatory: if it fails, the install aborts (podman needs
   no systemd — try it when docker-rootless cannot run).
3. **Router ports** — lower `net.ipv4.ip_unprivileged_port_start` to 80 so
   ddev-router can bind 80/443? (host-wide sysctl; declined → use higher
   router ports).
4. **Allow git commands** — no (default) or yes (soft-only `.git/config`
   deny via `--secure-git-config`).

Non-interactive:

```bash
sudo bash files/install.sh --yes --container-backend podman-rootless --projects /var/www/vhosts
```

(`--container-backend` must come **before** `--projects` — the projects flag
consumes the rest of the command line.)

ddev ≥ 1.25 is a hard requirement when ddev is installed; the installer
aborts on older versions.

After the install, `cd` into a project and run:

```bash
opencode
```

No npm package and no opencode plugin are involved — the kit is system-level
only.

## Managing Project Directories

Project roots are stored in `/etc/opencode-permissions-kit/projects.conf`
(one absolute path per line). The wrapper only allows `opencode` to start
inside one of these directories or their subdirectories.

### Adding More Projects

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh projects add /var/www/vhosts/new-project
```

Multiple paths at once are fine. `config.sh` appends to `projects.conf` and
applies the **group baseline** (group `opencode`, setgid, default ACLs
`g:opencode:rwx`) in one step. Manual equivalent:

```bash
echo /var/www/vhosts/new-project | sudo tee -a /etc/opencode-permissions-kit/projects.conf
sudo chgrp -R opencode /var/www/vhosts/new-project
sudo chmod g+s /var/www/vhosts/new-project
sudo setfacl -R -d -m g:opencode:rwx /var/www/vhosts/new-project
```

### Listing Configured Directories

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh projects list
```

### Removing a Project Directory

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh projects remove /var/www/vhosts/old-project
```

Only the `projects.conf` line is removed; files and their group bits stay.

## The Sharing Group (opencode usergroup)

The kit uses the `opencode` user's own primary usergroup (created by
`useradd -m`) as the sharing group — no `www-data`, no extra group:

- the developer is added as a member (`usermod -aG opencode <dev>`),
- project roots carry setgid + default ACLs `g:opencode:rwx`,
- `umask 002` (via the kit's profile script) makes agent-created files
  group-writable for the developer.

If you serve files with a **host-side** webserver (not ddev), add its user to
the `opencode` group — ddev itself does not care (the web server runs in the
container).

## How the Wrapper Works

Every `opencode` invocation goes through the wrapper at
`/usr/local/bin/opencode`:

1. **Validate working directory** — the current directory must be inside a
   path listed in `projects.conf`. Otherwise opencode does not start.
2. **Detect container tools** — if the project's `opencode.jsonc` broadly
   allows docker/ddev, the wrapper proposes running with the configured
   rootless backend and asks for confirmation.
3. **Probe the backend** — docker-rootless: the per-user socket is verified
   reachable (as the `opencode` user, via the kit's `socket-check.sh`
   sudoers rule); podman-rootless: the `podman` CLI must be installed (an
   optional `OPENCODE_PODMAN_SOCKET` enables docker-CLI compat). A stale
   legacy `docker-group` value produces a loud warning and **no** container
   tools — never a silent fallback to a root-equivalent path.
4. **Execute** — `sudo -u opencode` with `DOCKER_HOST`/`XDG_RUNTIME_DIR`
   exported for the rootless socket (preserved across sudo via the kit's
   `env_keep`).

## Container Tools (docker/ddev)

- The bundled `opencode.jsonc` denies `docker` / `docker-compose` / `ddev`
  (and their `sudo` forms) as bash commands — nothing is reachable unless a
  project explicitly opts in (see [The Two States](#the-two-states)).
- The backend is configured at install time (`--container-backend
  docker-rootless|podman-rootless`) and can be switched later:

  ```bash
  sudo bash /usr/local/lib/opencode-permissions-kit/config.sh container-backend podman-rootless
  sudo bash /usr/local/lib/opencode-permissions-kit/config.sh container-backend status
  ```

  Rootless provisioning (packages, subuid/subgid auto-allocation, linger) is
  handled by `setup-container-backend.sh`.

- `docker ps` inside an `opencode` session talks to the **opencode user's**
  daemon — the developer's ddev containers (started in their own terminal)
  are a different daemon/user and will not be listed. That is expected.

### ddev as the opencode user

ddev runs **always as `opencode`** — no delegation shim, no transaction, and
no two owners for `.ddev/`. How that works in practice:

- **Agent (opencode session):** ddev runs natively as `opencode`.
- **Your terminal (default user):** the kit hooks a `ddev()` shell function
  into your `~/.bashrc` / `~/.zshrc` / `~/.profile`. It execs
  `/usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode` via a
  passwordless sudoers rule, which re-sets the opencode environment
  (`HOME`, `XDG_RUNTIME_DIR`, `DOCKER_HOST` per backend) and runs the **real**
  ddev. So the terminal and the agent share one ddev home and one rootless
  daemon.

  Non-interactive scripts calling `ddev` are not intercepted — either run
  them in a terminal or call the helper directly:
  `sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode <args>`.

- **`.ddev/` ownership (the EPERM fix):** every registered project's `.ddev`
  belongs to `opencode:opencode` and is group-writable (`g+w`), so ddev can
  chmod its build stamps (the old
  `chmod .ddev/.webimageBuild: operation not permitted` is gone). The
  handover happens on install, when a project is added via `config.sh
  projects add`, on `config.sh refresh`, and unconditionally on every
  `update.sh`. Your `.git/` stays yours (mode 700, untouched).

Install/update provision the rest:

- `/home/opencode/.ddev` — the opencode user's global ddev home (project
  registry, mutagen binaries, `ddev auth ssh` key cache).
- **Router ports** — rootless containers cannot bind <1024; either the
  sysctl (`ip_unprivileged_port_start=80`, asked at install) or higher ports:

  ```bash
  sudo -u opencode ddev config global --router-http-port 8080 --router-https-port 8443
  ```

- **mkcert CA** — reused from the Windows user (WSL2) or the developer's
  CAROOT so browsers keep trusting ddev's HTTPS certs; a new CA is generated
  only as a last resort.

Notes:

- **`ddev auth ssh` / composer private keys** now live in
  `/home/opencode/.ddev` and are agent-readable. This is a deliberate
  soft-only trade-off: ddev runs as one user, so what ddev may read, the
  agent may read. Use `.gitignore`d per-machine credentials and rotate keys
  if the machine is not trusted.
- The **first** `ddev start` as `opencode` is slow (mutagen download, image
  pulls into the rootless daemon); everything afterwards reuses that state.

### `CONTAINER_BACKEND` keys in `install.conf`

| Key | Meaning |
|---|---|
| `CONTAINER_BACKEND` | `docker-rootless` \| `podman-rootless` (legacy `docker-group` → warning, no tools) |
| `OPENCODE_DOCKER_HOST` | `docker-rootless` socket, e.g. `unix:///run/user/<opencode-uid>/docker.sock` |
| `OPENCODE_PODMAN_SOCKET` | optional podman docker-CLI-compat socket |
| `DDEV_VERSION` | recorded ddev version (advisory; `status.sh` flags < 1.25) |
| `WWW_GROUP` | always the `opencode` usergroup (informational) |
| `HARD_DENY_REMOVED` | migration stamp — `1` once the soft-only migration ran |

## Customizing the Deny List

### Global Config

Edit the config file (as your default user, no `sudo` needed — the directory
is group-writable):

```bash
nano /home/opencode/.config/opencode/opencode.jsonc
```

Add deny patterns under `permission.read` / `permission.edit`. Changes take
effect on the next `opencode` start. **All rules are soft** — they gate
opencode's tools, not the OS.

The bundled template runs `permission.bash` as **ask-by-default**
(`"*": "ask"`) with a small allowlist of provably harmless read-only commands
and hard denies for system-destructive and container commands. On top of
that it carries a **sensitive-file tripwire**: the read/edit deny patterns
mirrored as `ask` rules *after* the allowlist, with trailing `*` so a name
mid-command (`cat settings.php | grep DB`) still triggers. The tripwire is
lexical — variables (`F=.env; cat $F`), globs and indirection evade it; there
is no OS backstop anymore (see [Security Model](#security-model-soft-only)).

**Scope boundary — the kit protects locations, not information flows.** Once
content leaves the project roots (`cp .env /tmp/backup`), no scan recaptures
it. As a visibility aid, `status.sh` ends with a **leak scan**: a name-based,
report-only sweep of the scratch directories (`/tmp`, `/var/tmp`, `/dev/shm`,
overridable via `LEAK_SCAN_DIRS`) listing files matching the deny patterns.
Renamed copies stay invisible; false positives are expected. On the git side,
prevent secrets from entering history in the first place (pre-commit secret
scanning, e.g. gitleaks).

### Self-Update Bypass Protection (Default-User Config)

`opencode`'s installer and self-updater can re-add `~/.opencode/bin` to your
`PATH`. If that happens, typing `opencode` would run the real binary **as
your user** instead of the wrapper.

As a safety net, the kit installs a lockout config for the default user
(`~/.config/opencode/opencode.jsonc`) that denies **everything** — even if
the real binary takes over, it cannot read or modify anything. Template:
`files/opencode-deny-all.jsonc`.

- During `install.sh`, an existing file is renamed to
  `opencode.jsonc_BAK_<timestamp>` before the deny-all config is installed.
- `update.sh` only installs the lockout config when no config exists yet.
- To use opencode normally as your own user, delete or rename that config.

### Wrapper-Bypass Guard (detect a bypass, warn loudly)

1. **Binary exec restricted to root + the sandbox group.** The real binary
   at `/usr/local/lib/opencode-permissions-kit/bin/opencode` is owned
   `root:opencode` with mode `750`. Note: the developer is a member of the
   `opencode` group (file sharing), so the group bit grants them execution
   too — running the real binary as your user is mitigated by the deny-all
   config above, not by the mode bits.
2. **Shell-start warning.** `shell-warn.sh` is hooked into `~/.bashrc`,
   `~/.zshrc`, `~/.profile` and the profile.d script; every new shell prints
   a loud warning when a real `~/.opencode/bin/opencode` exists or `command -v
   opencode` resolves to anything but the wrapper.
3. **Wrapper self-check.** Every wrapper start re-checks both conditions.

### Project-Specific Config

Each project can have its own `opencode.jsonc` in its root directory.
Project configs **extend** the global config — opencode merges them with its
standard semantics (last matching rule wins).

Example `/var/www/vhosts/my-project/opencode.jsonc`:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "read": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny"
        },
        "edit": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny"
        },
        "bash": {
            "yarn dev": "allow",
            "composer install*": "allow"
        }
    }
}
```

A project without its own config gets only the global protection.

### `.git/config` Hardening (Optional, soft-only)

`.git/config` can contain remote URLs with embedded credentials. The deny
blocks opencode's **tools** (read/edit + a `*.git/config*` bash tripwire) —
a bash-spawned `cat .git/config` is not OS-blocked.

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash -s -- --secure-git-config
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config on
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config off
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config status
```

When to enable: remote URLs contain embedded tokens, or you don't want
opencode to run git at all. When to leave open: SSH remotes, credential
helpers, or you want opencode to commit/push on your behalf.

## Migration from a hard-ACL install (DDEV-WORKING)

`update.sh` performs a one-time migration, gated by `HARD_DENY_REMOVED` in
`install.conf`:

1. Removes every `u:opencode:---` ACL deny from the registered project
   roots (via `migrate-denies.sh`).
2. Re-bases the sharing group to the `opencode` usergroup (chgrp + setgid +
   default ACLs), hands over every project's `.ddev` to `opencode`, and adds
   the developer to the group.
3. Removes the legacy artifacts: git hooks, `protect-projects.sh`,
   `ddev-transaction.sh`, the ddev delegation shim, the rewrite list.
4. Unsets `core.hooksPath`, provisions `/home/opencode/.ddev` + mkcert,
   re-renders the sudoers (now incl. the ddev-as-opencode rule), hooks the
   `ddev()` terminal function into your rc files, stamps
   `HARD_DENY_REMOVED=1`.

A legacy `docker-group` install **aborts with instructions** — re-run
`install.sh --container-backend docker-rootless|podman-rootless` (rootless is
mandatory now). Group membership changes need a fresh login shell.
`status.sh` reports the migration state and scans for leftover denies.

## Verification

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/status.sh
```

Shows the mode, backend + socket reachability, ddev runtime readiness
(`~opencode/.ddev`, router ports, mkcert CA), the migration state, and the
leak scan. Works before install too (reports "NOT active").

### Development Tests

```bash
sh tests/test-*.sh        # unit suite (per AGENTS.md: never rely on mode bits)
make check-version
make e2e                  # Docker-based end-to-end suite
```

The e2e suite builds an Ubuntu container, installs the kit (podman-rootless),
verifies the soft-only model (files readable, rootless container reads
`settings.php`), the update/binary flows, the hard-deny migration, and the
uninstall. `make e2e-rootless` additionally exercises a real docker-rootless
daemon (needs systemd-in-container; skips when unavailable).

## Management Scripts

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/status.sh       # show status
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh       # change settings (projects, git-config, backend, refresh)
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh       # re-deploy the kit after an update
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh         # remove everything (no sudo prefix)
```

## Audit Log

Every kit script that changes the system writes to
`/var/log/opencode-permissions-kit/opencode-permissions-kit.log`
(root-owned dir `750` / file `640` in the default user's primary group,
self-rotating at 1 MB, best-effort). The `opencode` user cannot read it; the
default user (the kit admin) can read it without sudo. Notable events:
install/update/uninstall completion, backend switches, the hard-deny
migration (`hard-deny migration ...`), binary upgrades, leak-scan findings.

During an interactive `uninstall.sh` run you are asked whether the audit log
should be deleted too (recommended).

## Updating the Kit

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/update.sh | sudo bash
```

`update.sh` re-deploys the kit files and refreshes the `install.conf` version
stamp (+ `WWW_GROUP` re-base and the migration stamp). It does **not** touch
`projects.conf` or `/home/opencode/.config/opencode/opencode.jsonc`.
`--refresh` re-applies the group baseline.

### Upgrading the opencode binary

`opencode upgrade` and the auto-updater cannot work behind the wrapper
(root-owned binary, unprivileged user) — `autoupdate: false` is set in the
kit config and `update.sh` is the upgrade entry point:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary                  # latest release
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary-path ./opencode  # specific file
```

Binary upgrades are best-effort; the previous binary is kept in
`/tmp/opencode-upgrade-backup-*`.

## Uninstalling

```bash
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh
```

Options: `--yes`, `--dry-run`, `--debug`. Removes the `opencode` user (and
its usergroup), the kit library, sudoers rules, the profile scripts, project
ACLs/setgid, `/run/opencode-permissions-kit`, and the router-port sysctl
file. Project files are untouched. Shell RC hook lines and the default-user
config remain (harmless); the script prints manual cleanup steps.

## File Overview

### /etc/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `install.conf` | `DEFAULT_USER`, `OPENCODE_USER`, `WWW_GROUP`, `DDEV_VERSION`, `CONTAINER_BACKEND`, `OPENCODE_DOCKER_HOST`, `OPENCODE_PODMAN_SOCKET`, `HARD_DENY_REMOVED`, `VERSION` |
| `projects.conf` | Project roots (one per line) |

### /etc/sudoers.d/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit` | `(opencode)` RunAs for the kit binary, the socket-check probe, and the ddev-as-opencode helper; `DOCKER_HOST`/`XDG_RUNTIME_DIR` env_keep |

### /home/

| Path | Purpose |
|---|---|
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with the soft deny list |
| `/home/opencode/.ddev/` | sandbox user's global ddev home |
| `/home/<dev>/.config/opencode/opencode.jsonc` | deny-* lockout config (self-update bypass) |

### /usr/local/

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

### /var/log/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `opencode-permissions-kit.log` | Audit log (mode 750/640, self-rotating) |
