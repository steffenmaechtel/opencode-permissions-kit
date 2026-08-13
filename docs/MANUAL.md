# opencode permissions kit — Manual

## What It Does

This kit secures [opencode](https://opencode.ai) by running it as a dedicated Linux user (`opencode`) with hard Linux-ACL denies on sensitive files (`.env`, `settings.php`, `auth.json`, SSH keys, etc.).

Once installed, a developer opens a terminal in a project directory and runs `opencode` — the wrapper validates the directory, refreshes ACLs, then starts opencode as the `opencode` user. Denied files are unreadable at the Linux level; not even `cat .env` works.

## Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

The script detects that it is being streamed, fetches its sibling files (config.sh, update.sh, uninstall.sh, status.sh, wrapper, hooks, templates) from the same `master` branch, and walks you through the setup. Follow the prompts to select project directories. After the install, `cd` into a project and run:

```bash
opencode
```

No npm package and no opencode plugin are involved — the kit is system-level only.

## Managing Project Directories

Project roots are stored in `/etc/opencode-permissions-kit/projects.conf` (one absolute path per line). The wrapper only allows `opencode` to start inside one of these directories or their subdirectories.

### Adding More Projects

**Option A — Use `config.sh` (recommended after install):**

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh projects add /var/www/vhosts/new-project
```

You can pass multiple paths:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh projects add /var/www/vhosts/site-a /var/www/vhosts/site-b
```

`config.sh` updates `projects.conf`, applies the base filesystem bits (group `www-data`, setgid, default ACL), and re-runs `protect-projects.sh --force` in one step. It is non-interactive when you pass `--yes`.

**Option B — Re-run `install.sh` (during initial setup):**
```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash -s -- --projects /var/www/vhosts/new-project
```
You can pass multiple paths:
```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash -s -- --projects /var/www/vhosts/site-a /var/www/vhosts/site-b
```
(Or re-run a local checkout with `sudo bash files/install.sh --projects ...`.)

**Option C — Edit the config directly:**
```bash
sudo nano /etc/opencode-permissions-kit/projects.conf
```
Add one path per line, then apply ACLs to the new directory:
```bash
sudo /usr/local/lib/opencode-permissions-kit/protect-projects.sh --force
```

### Listing Configured Directories

```bash
cat /etc/opencode-permissions-kit/projects.conf
```

### Removing a Project Directory

**Option A — Use `config.sh`:**

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh projects remove /var/www/vhosts/old-project
```

Removes the line from `/etc/opencode-permissions-kit/projects.conf`. ACL denies on that directory remain on disk until you clear them manually.

**Option B — Edit the config directly:**

Remove the line from `/etc/opencode-permissions-kit/projects.conf`. ACLs on that directory remain in place but are no longer refreshed — use `getfacl` / `setfacl -x` to clean up manually or run `uninstall.sh`.

## How the Wrapper Works

Every `opencode` invocation goes through the wrapper at `/usr/local/bin/opencode`:

1. **Validate working directory** — the current directory must be inside a path listed in `/etc/opencode-permissions-kit/projects.conf`. If not, an error is shown with the list of valid directories and opencode does not start.
2. **Parse `-g` / `--gid`** — an optional container-group argument for the docker sandbox (see [Container Tools](#container-tools-dockerddev)).
3. **Detect container tools** — if the project's `opencode.jsonc` explicitly enables docker/ddev, the wrapper proposes running opencode with the docker group and asks for confirmation.
4. **Refresh ACL denies** — runs `protect-projects.sh` to ensure sensitive files are blocked.
5. **Execute** — starts opencode as the `opencode` user, optionally with the docker group (`sudo -u opencode -g docker`).

## Container Tools (docker/ddev)

opencode runs as a dedicated user, so container commands like `docker ps`, `docker exec`, `ddev start` or `ddev exec` would normally have no access to the Docker daemon. The kit fixes this with a controlled escalation:

- The bundled `opencode.jsonc` **denies** `docker` / `docker-compose` / `ddev` (and their `sudo` forms) as bash commands, so opencode can never reach them directly — even through `sudo`.
- The sudoers rule grants the wrapper the `opencode:docker` RunAs group: `sudo -u opencode -g docker`. The wrapper is the **only** path to Docker.
- Inside the sandbox, opencode's shell has the docker group, so `docker` / `docker-compose` / `ddev` work as usual — while file protection stays fully in effect.

### Manual escalation

```bash
opencode -g docker
```

Run opencode with the docker group (confirmed only by the fact that you typed the flag). `--gid docker` and `-g 0` are equivalent. An unsupported group (`-g ddev`, `-g foo`, …) aborts with an error — there is no silent fallback.

### Automatic detection

If the project's own `opencode.jsonc` explicitly allows docker or ddev in `permission.bash` (e.g. `"docker *": "allow"`, `"*": "allow"`, or `"permission": "allow"`), the wrapper prints which tools it detected and asks:

```
  Run opencode with the docker group? [Y/n]
```

- **Y** (default) → starts opencode with the docker group, so the project's docker/ddev commands work.
- **n** → starts opencode without the docker group (commands will fail with a permission error, matching the non-granted state).

Detection mirrors opencode's own rule semantics (last matching rule wins) and only counts rules that would let a real `docker`/`ddev` invocation through — subcommand-only allows like `"ddev composer *": "allow"` do **not** trigger the grant. If the `docker` group does not exist on the system, the wrapper warns and runs without the container group.

### Notes

- Granting the group does **not** grant the command: the bundle's deny rules keep opencode from running `docker *` itself. The group only matters for the wrapper-started shell.
- `status.sh` reports whether the docker group exists and whether the docker/ddev deny rules are active.
- Docker must be usable by the group: if Docker was installed so that members of `docker` can access the daemon (the default), this just works. The `opencode` user is **not** added to the `docker` group — membership is granted per-invocation via sudo.
- **`.ddev` write access:** `ddev start` rewrites the project's `.ddev/` files (e.g. `.homeadditions`, `README.txt`). ddev recreates them as the launching developer user and `chmod 755` them, which caps the ACL mask to `r-x` and blocks the `opencode` user (group `www-data`). Each `protect-projects.sh` run (wrapper start, `config.sh`, git hook) now re-asserts the kit base bits on every `.ddev` tree under the registered root (ddev projects are usually subdirectories, e.g. `/var/www/vhosts/<project>/.ddev`) — group `www-data` and a `rwx` mask — so opted-in docker/ddev projects keep working. If `ddev start` is run manually as the developer right after, the next wrapper start repairs the tree automatically.

### Container backend

The kit records a **container backend** in `install.conf` (`CONTAINER_BACKEND=`). It decides how the wrapper reaches the container runtime when a project enables docker/ddev — it does **not** change the policy layer (docker/ddev stay denied in `opencode.jsonc`; the wrapper stays the only path).

| Backend | How the wrapper grants container access | Host privilege of containers |
|---|---|---|
| `docker-group` (default) | `sudo -u opencode -g docker` — the supplementary docker group lets the sandbox talk to the root-owned system daemon | **root-equivalent** on the host (the classic docker-socket gap) |
| `docker-rootless` | `sudo -u opencode` with `DOCKER_HOST` pointing at the `opencode` user's rootless dockerd socket (`OPENCODE_DOCKER_HOST=`), verified reachable before start | confined to the `opencode` host UID → the kit's `u:opencode:---` ACL denies hold inside bind-mounted containers |
| `podman-rootless` | `sudo -u opencode` (no `DOCKER_HOST`) — podman is daemonless, so the wrapper just verifies `podman` is installed. Optionally `OPENCODE_PODMAN_SOCKET=` enables a podman docker-CLI-compat socket (then verified like `docker-rootless`) | confined to the `opencode` host UID → ACL denies hold |

`docker-group` is the default and the status quo: **no behaviour change for existing installs.** If the configured rootless socket is not reachable, the wrapper warns loudly and starts **without** container tools — it never silently falls back to `-g docker` (that would reintroduce root-equivalent host access). `--yes`/scripts keep `docker-group` unless a backend is chosen explicitly.

Reachability is probed as the **`opencode` user** — the context that actually connects — not as the developer: rootless sockets live in the `opencode` runtime dir (`/run/user/<uid>`, mode `700`), which a developer-running wrapper cannot stat. The wrapper tries the direct check first, then re-runs the kit's `socket-check.sh` helper (nothing but `test -S`, gated to that script in sudoers) via `sudo -u opencode`, so a reachable daemon is detected even though the developer cannot traverse the runtime dir.

> **Phase 1 + 2 (current state):** the kit is *backend-aware* and can
> **provision** rootless backends. `install.sh` detects the container situation
> and offers an interactive backend choice (or `--container-backend
> podman-rootless` for scripts). `config.sh container-backend` switches
> post-install. Rootless provisioning (packages, subuid/subgid auto-allocation,
> linger) is handled by `setup-container-backend.sh`. An admin who already runs
> a rootless backend can also point the kit at it manually by editing
> `/etc/opencode-permissions-kit/install.conf`:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh container-backend podman-rootless
```

For `docker-rootless` the helper also records the socket
(`OPENCODE_DOCKER_HOST=unix:///run/user/$(id -u opencode)/docker.sock`). For
`podman-rootless` the `podman` CLI path needs no socket — the helper installs
`podman` + `uidmap` + `slirp4netns` and auto-allocates `/etc/subuid` + `/etc/subgid`
ranges for the `opencode` user.

The two-daemon reality and the ddev ≥ 1.25 gate (ddev-shim `--preserve-env`
pass-through) are tracked in `docs/DOCKER-ROOTLESS.md` as Phase 3. `status.sh`
reflects whichever backend is configured; `docker ps` inside an `opencode`
session will not list the developer's ddev containers when a rootless backend is
selected (different daemon/user) — that is expected. The §9.1 value proposition
(a rootless bind mount respects `u:opencode:---`) is **proven by e2e** —
`tests/e2e/run.sh` section 12i provisions real rootless podman via `config.sh`,
runs a container as the `opencode` user, and asserts `.env` is denied while a
normal file is readable.

#### `CONTAINER_BACKEND` keys in `install.conf`

| Key | Meaning |
|---|---|
| `CONTAINER_BACKEND` | `docker-group` \| `docker-rootless` \| `podman-rootless` (empty/unknown → `docker-group`) |
| `OPENCODE_DOCKER_HOST` | `docker-rootless` socket, e.g. `unix:///run/user/<opencode-uid>/docker.sock` |
| `OPENCODE_PODMAN_SOCKET` | `podman-rootless` socket |
| `DDEV_VERSION` | recorded ddev version (advisory; `status.sh` flags a `< 1.25` ddev next to a rootless backend) |

### ddev delegation (running ddev as the developer)

`docker` commands only talk to the daemon socket, so running them as the
`opencode` user (with the docker group) just works. `ddev` is different: it also
**rewrites project files on the host** — TYPO3 `config/system/settings.php` /
`additional.php`, `config/system/.gitignore`, and the `.ddev/.webimageBuild` /
`.dbimageBuild` directories. Those host-side files are owned by the developer
(`DEFAULT_USER`) and hardened by the kit (hard ACL denies on
`*settings.php` / `*additional.php`, developer-owned `config/system/` at `755`
with no `www-data` write, `.ddev` build dirs `chmod`-able only by their owner).
Running `ddev` as `opencode` therefore collides with the very protections the
kit applies, and `ddev start` fails host-side even though the docker socket is
reachable.

The kit solves this with a **delegating shim**. A tiny script is installed at
`/usr/local/lib/opencode-permissions-kit/bin/ddev` and shadowed as `/usr/local/bin/ddev`
(ahead of the real ddev in `PATH`). For the `opencode` sandbox user it re-execs
every `ddev` invocation as the developer via a passwordless sudoers rule:

```
opencode ALL=(<developer>) NOPASSWD: <ddev-binary>
```

So when the agent runs `ddev start` inside an opt-in project, the shim runs the
real ddev **as the developer** — exactly as if the developer had typed it in a
second terminal. Host files are written with the developer's ownership, no ACL
conflict, and `.ddev` build dirs are `chmod`-able. The developer's own `ddev`
calls pass through the shim untouched (it only delegates for the `opencode`
user).

What the kit records and where:

| Artefact | Location | Purpose |
|---|---|---|
| shim | `/usr/local/lib/opencode-permissions-kit/bin/ddev` | gates on the `opencode` user, delegates to `<developer>` |
| shadow symlink | `/usr/local/bin/ddev` -> shim | intercepts the agent's bare `ddev` (ahead of the real ddev) |
| real ddev path | `DDEV_BIN=` in `/etc/opencode-permissions-kit/install.conf` | the shim's delegation target |
| sudoers rule | `/etc/sudoers.d/opencode-permissions-kit` | `opencode ALL=(<developer>) NOPASSWD: <DDEV_BIN>` |

Requirements & limitations:

- **`ddev` must resolve to the shim, not the real binary.** The kit shadows
  `/usr/local/bin/ddev` only when that path is free or already the shim — it
  never clobbers a real ddev installed there. If your ddev lives at
  `/usr/local/bin/ddev` (some installers place it there), move it below
  `/usr/local/bin` (e.g. to `/usr/bin/ddev`) and re-run `update.sh` so the shim
  can take over. The Debian/Ubuntu apt package already installs to `/usr/bin/ddev`.
- **The developer must have docker access.** The shim delegates `ddev` to the
  developer, who in turn needs the docker socket — i.e. the developer is a
  member of the `docker` group (the normal setup on a dev machine). The kit does
  not manage the developer's docker membership.
- **Subcommand gating is soft.** The shim delegates every `ddev` subcommand the
  agent invokes; it does not itself block `ddev ssh` or any other subcommand.
  Whether the agent may call a given `ddev` subcommand at all is controlled by
  the project's `permission.bash` rules (the soft layer), evaluated before the
  command reaches the shim. Deny `ddev ssh *` in the project config if you do
  not want the agent to use it.
- **`ddev exec` ignores host ACLs.** As with raw `docker`, anything the agent
  runs via `ddev exec` runs as container root over bind-mounts and can read
  files regardless of `u:opencode:---` ACLs. Enabling `ddev` for a project
  accepts this gap.
- `status.sh` reports whether the shim is active, the real ddev path, and the
  delegation target.
- Uninstall removes the `/usr/local/bin/ddev` shadow; the real ddev (wherever
  it lives) is left intact.

## Customizing the Deny List

### Global Config

Edit the config file (as your default user, no `sudo` needed — the directory is group-writable):

```bash
nano /home/opencode/.config/opencode/opencode.jsonc
```

Add deny patterns under `permission.read.deny` and `permission.edit.deny`. Changes take effect on the next `opencode` start.

**Only `deny` patterns become filesystem ACLs.** `ask` and `allow` patterns affect opencode's prompts only — no hard ACL is set, so normal processes (e.g. `ddev` reading its command docs from `.ddev/commands/<svc>/README.txt`) are never blocked. The bundled template therefore ships `*README.md` as `deny` (the kit's documented self-block) but `*README.txt` as `ask` so ddev keeps working. When you remove a deny pattern from the config, `protect-projects.sh` clears the now-stale ACLs automatically on the next run (wrapper start, `config.sh`, or git hook).

See `files/opencode.jsonc` for the default template.

The bundled template runs `permission.bash` as **ask-by-default** (`"*": "ask"`): every bash command prompts the user for approval unless it matches an explicit `allow` or `deny` rule. It ships a small allowlist of provably harmless read-only commands (`ls`, `pwd`, `whoami`, `git status`, `git diff`, `git log`, ...) and hard-denies system-destructive and container commands. To allow additional commands, add `allow` rules before the deny block — opencode applies the last matching rule, so a later `deny` always wins over a broader `allow`.

### Self-Update Bypass Protection (Default-User Config)

`opencode`'s installer and self-updater can re-add `~/.opencode/bin` to your `PATH`. If that happens, typing `opencode` would run the real binary **as your user** instead of our wrapper — bypassing the wrapper's ACL refresh and the dedicated `opencode` user.

As a safety net, the kit installs a lockout config for the default user:

```bash
nano /home/$USER/.config/opencode/opencode.jsonc
```

It denies **everything** (`read`, `edit`, `bash`, …), so even if the real binary takes over, it cannot read or modify anything. Template: `files/opencode-deny-all.jsonc`.

- During `install.sh`, if that file already exists you are asked whether it may be renamed to `opencode.jsonc_BAK_<timestamp>` before the deny-all config is installed.
- `update.sh` only installs the lockout config when no config exists yet — it never clobbers an existing one (re-run `install.sh` to get the backup prompt).
- To use opencode normally as your own user, delete or rename that config — the wrapper path is unaffected.

### Wrapper-Bypass Guard (detect a bypass, warn loudly)

The deny-all config above protects the data, but silently. The kit therefore adds three layers that make a bypass **visible** and harden the only remaining vectors:

1. **Binary exec restricted to root + the sandbox user.** The real binary at `/usr/local/lib/opencode-permissions-kit/bin/opencode` is owned `root:opencode` with mode `750`. Only `root` and the `opencode` sandbox user can execute it, so **a tool calling the absolute path as your user fails with "permission denied"** — it cannot start the real binary behind the wrapper's back. The wrapper is unaffected (`sudo -u opencode …` runs it as the sandbox user).
2. **Shell-start warning.** `install.sh` hooks the kit's `shell-warn.sh` into `~/.bashrc`, `~/.zshrc` and `~/.profile` (as a `[ -f … ] && source` line, harmless after uninstall), and `/etc/profile.d/opencode-permissions-kit-umask.sh` sources it for login shells. Whenever a real `~/.opencode/bin/opencode` exists (e.g. after the official installer re-run) — or `command -v opencode` resolves to anything but the kit wrapper — every new shell prints a loud warning with the fix. `update.sh` appends the same hook to existing installs (idempotent).
3. **Wrapper self-check.** Every wrapper start re-checks both conditions and prints the same warning. This fires even when a reinstall happened but `PATH` still resolves to the wrapper (e.g. you are in a shell that started before the reinstall).

The warning text:

```
  *** WARNING: opencode permissions kit — wrapper bypass ***
  'opencode' resolves to /home/<user>/.opencode/bin/opencode — not the kit wrapper.
  The real binary runs WITHOUT the kit's ACL protection and sandbox user.
  Fix:
      rm -rf ~/.opencode/bin
      sudo bash /usr/local/lib/opencode-permissions-kit/update.sh
```

The kit never auto-deletes the shadow binary — it warns and lets you decide. (`install.sh` still removes stray `.opencode/bin` lines from your shell rc files; a re-install after that re-adds them, which is exactly what the warning catches.)

### Project-Specific Config

Each project can have its own `opencode.jsonc` (or `opencode.json`) in its root directory. Project configs **extend** the global config — they add denies cumulatively, never weaken existing rules.

Example `/var/www/vhosts/my-project/opencode.jsonc`:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "read": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny",
            "dump*.sql": "deny"
        },
        "edit": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny",
            "dump*.sql": "deny"
        },
        "bash": {
            "yarn dev": "allow",
            "composer install*": "allow"
        }
    }
}
```

How it works:

- **`permission.read.deny` / `permission.edit.deny`**: Merged with global denies. `protect-projects.sh` applies ACLs scoped to this project only.
- **`permission.read.allow` / `permission.edit.allow`**: Removes global ACL denies **for this project only**. In the wrapper you'll see a warning listing the overridden patterns.
- **`permission.bash`**: Project rules override global bash rules (opencode standard).

A project without its own config gets only the global protection.

See `tests/fixtures/project-opencode.jsonc` for a full example (TYPO3 project).

### `.git/config` Hardening (Optional)

`.git/config` can contain remote URLs with embedded credentials. When blocked, opencode **cannot execute any git commands** — no commit, push, pull, status, diff, or log. The developer must handle all git operations themselves.

**Enable during install:**

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash -s -- --secure-git-config
```

Or answer "Yes" when prompted during interactive install.

**Toggle later (without re-running install):**

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config on     # block .git/config
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config off    # allow git access again
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh git-config status # show current state
```

**Enable manually** (add to global or project config):

```jsonc
"permission": {
    "read": {
        ".git/config": "deny",
        "**/.git/config": "deny"
    },
    "edit": {
        ".git/config": "deny",
        "**/.git/config": "deny"
    }
}
```

When to enable:
- Remote URLs contain embedded tokens (e.g. `https://user:ghp_xxx@github.com/...`)
- You don't want opencode to run git at all

When to leave open:
- You use SSH keys (no token in remote URL)
- You use a credential helper (Git Credential Manager)
- You want opencode to commit/push on your behalf

## Git Hooks

Global git hooks re-apply ACL denies automatically after:

- `git checkout` / `git switch` / `git pull` (fast-forward)
- `git merge`
- `git commit`

The hooks run `protect-projects.sh --force --cwd <dir>`, so the project-level `opencode.jsonc` is applied too — not just the global denies. The `--cwd` is the directory **where opencode was launched**, not the git worktree root: the wrapper stamps it into opencode's environment as `OPENCODE_LAUNCH_CWD` (preserved through `sudo -u opencode` via `Defaults env_keep` in the kit's sudoers), which propagates through opencode's shells to git and its hooks. This matters when the git repository lives in a subfolder of the project that opencode was started in. If git runs outside opencode (e.g. in your own terminal), the variable is absent and the hook falls back to the worktree root.

In both cases `protect-projects.sh` resolves the governing project config by walking **up** from `--cwd` to the nearest `opencode.json[c]` (matching where opencode resolves its own config). A config at the project root is therefore found even when the git command runs inside a nested worktree like `<project>/repo/` — the project's `allow` overrides (e.g. `README.md`) survive git operations instead of being overwritten by the global denies.

No per-repo setup required — `core.hooksPath` is set globally for both users.

## Verification

Run the test suite to confirm everything is working:

```bash
./tests/verify.sh
```

It checks users, groups, wrapper, hooks, sudoers, and that `opencode` truly cannot read sensitive files like `.env` and `settings.php`.

### Development Tests

These tests run without system dependencies and verify logic in isolation:

```bash
./tests/test-wrapper-validation.sh   # 17 tests: directory validation
./tests/test-project-config.sh       # 29 tests: project config parsing & matching
```

The end-to-end test (`make e2e`) builds an Ubuntu container, installs the kit, and verifies the full protection flow. It requires Docker and must be run manually from a terminal. The opencode binary is downloaded once per opencode version and cached in `tests/e2e/cache/` (gitignored), so repeated runs with the same version are fast and work offline; a new opencode version triggers a fresh download automatically.

## Management Scripts

The kit is system-level only — no opencode plugin, no npm package. Everything is managed from a regular terminal (the `sudo` password prompt needs a real TTY, not opencode):

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/status.sh       # show protection status
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh       # change settings (projects, .git/config, ACL refresh)
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh       # re-deploy the kit after an update
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh         # remove everything (no sudo prefix)
```

All of these scripts are deployed to `/usr/local/lib/opencode-permissions-kit/` by the installer, so there is nothing to fetch or configure afterwards.

`status.sh` shows the current protection state:

```
opencode permissions kit  v0.0.8
=============================================

Mode:       hardened (opencode runs as its own user)
User:       opencode exists
Wrapper:    /usr/local/bin/opencode -> /usr/local/lib/opencode-permissions-kit/wrapper
Library:    /usr/local/lib/opencode-permissions-kit
Config:     /home/opencode/.config/opencode/opencode.jsonc
Default user: info  group: www-data

Project roots (1):
  - /var/www/vhosts

.git/config hardening: OFF

Container tools (docker/ddev):
  backend:    docker-group  (docker group: present (gid 999))
  reachable via: opencode -g docker
  direct access: blocked (docker/ddev denied in opencode.jsonc)

ddev delegation shim:
  shim: active  /usr/local/bin/ddev -> /usr/local/lib/opencode-permissions-kit/bin/ddev
  real ddev: /usr/bin/ddev
  delegates to: info (the developer)
  ddev version: 1.24.3

Management (run in a terminal):
    sudo /usr/local/lib/opencode-permissions-kit/config.sh                 change settings
    sudo /usr/local/lib/opencode-permissions-kit/update.sh                 re-deploy kit after an update
    bash /usr/local/lib/opencode-permissions-kit/uninstall.sh              remove the kit
```

Before the kit is installed, `status.sh` still works and reports that hardening is **NOT active** — handy for checking any machine.

The **Container tools** block reports the configured **backend** (`docker-group` by default; `docker-rootless` / `podman-rootless` when an admin has opted in — see [Container backend](#container-backend)), how container access is granted (the docker group for `docker-group`, or the per-user socket reachability for the rootless backends), and whether the docker/ddev deny rules in `opencode.jsonc` are active. If it reports `direct access: NOT blocked`, the deny rules were removed from the config — re-run `install.sh` or restore the default template. The **ddev delegation shim** block reports whether the shim is active (shadowing `/usr/local/bin/ddev`), the real ddev path it delegates to, the developer user it runs ddev as, and the recorded ddev version (with a note when a rootless backend is selected but ddev < 1.25) — see [ddev delegation](#ddev-delegation-running-ddev-as-the-developer).

## Audit Log

Every kit script that changes the system writes a machine-readable audit trail:

- Location: `/var/log/opencode-permissions-kit/opencode-permissions-kit.log`
- Directory `root:<default-user-group>` mode `750`, file `root:<default-user-group>`
  mode `640`. The `opencode` user cannot read it — it documents the very
  restrictions applied against that user, so it must stay out of its reach.
  The default user (the kit admin) can read it without sudo via their primary
  group.
- One line per event: `<ISO-timestamp> [<script-name>] <message>`
- Size-based self-rotation: 1 MB → `.1` … `.5`. No external logrotate needed.
- Best-effort by design: if the log cannot be written (e.g. non-root preview),
  the kit scripts keep working silently. Logging never breaks the scripts.

What gets logged:

| Event | Example |
|---|---|
| Install / update / uninstall completion | `install complete (user=dev)` |
| ACL batch changes from `protect-projects.sh` | `setfacl deny u:opencode:--- on 42 file(s) under /var/www/vhosts/foo` |
| Ownership fixes | `chown dev:www-data on 12 file(s) under /var/www/vhosts/foo` |
| Protected path refusals | `REFUSED system path: /` |
| Missing configs (skipped runs) | `projects.conf not found — nothing to protect` |
| Early exits | `no global opencode config found — nothing to protect` |

During an interactive `uninstall.sh` run you are asked whether the audit log
should be deleted too (recommended, default yes). `uninstall.sh --yes` always
deletes the log directory and all rotation files along with the rest of the
kit. The final log entry is written before the directory is removed, so no new
log file is recreated by the uninstall itself.

## Updating the Kit

After `git pull` (or new changes merged to `master`) you can re-deploy the kit **without** re-answering the install-time questions:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/update.sh | sudo bash
```

Or run the deployed copy directly:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh
```

`update.sh` fetches the matching branch files (wrapper, hooks, `protect-projects.sh`, `jsonc-parser.py`, `sudoers` template, `umask` profile, `shell-warn.sh`, `config.sh`, `uninstall.sh`, `status.sh`) and refreshes the `install.conf` version stamp. It does **not** touch:

- `/etc/opencode-permissions-kit/projects.conf`
- `/etc/opencode-permissions-kit/install.conf` (except the `VERSION=` line)
- `/home/opencode/.config/opencode/opencode.jsonc`
- any ACLs or filesystem metadata

One exception: it **appends** the wrapper-bypass warning hook (a `[ -f … ] && source` line) to your `~/.bashrc`/`~/.zshrc`/`~/.profile` if missing, so existing installs get the [wrapper-bypass warning](#wrapper-bypass-guard-detect-a-bypass-warn-loudly) too. It never removes your lines — the hook is idempotent and harmless after uninstall.

### Upgrading the opencode binary

`opencode upgrade` and opencode's auto-updater **cannot** work behind the
wrapper: the binary at `/usr/local/lib/opencode-permissions-kit/bin/opencode` is root-owned
(executable only for `root` and the `opencode` sandbox user) and
opencode runs as the unprivileged `opencode` user, so a self-update would fail
(or land in a location the wrapper never uses). That is why `autoupdate: false`
is set in the kit config and `update.sh` is the upgrade entry point.

To also upgrade opencode to the **latest release**:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary
```

Or install a specific binary file (e.g. a pinned version) without downloading:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary-path /path/to/opencode
```

Binary upgrades are best-effort: a download or verification failure leaves the
current binary in place and logs a warning — the kit update still completes.
The previous binary is kept in `/tmp/opencode-upgrade-backup-*` until you
confirm the new version works.

Add `--refresh` to also re-run `protect-projects.sh --force` after the deploy:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --refresh
```

## Uninstalling

```bash
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh
```

Run it as your normal user (no `sudo` prefix — the script handles sudo itself). Options: `--yes`, `--dry-run`, `--debug`.

Removes the `opencode` user, the kit library, ACLs, hooks, and sudoers rules. Project files are untouched. Shell RC hook lines in `~/.bashrc` / `~/.zshrc` / `~/.profile` (tagged `# opencode permissions kit`) and the default-user config `~/.config/opencode/opencode.jsonc` (plus any `opencode.jsonc_BAK_*` backups) are left in place — they are harmless after uninstall (the `shell-warn.sh` hook is guarded by `[ -f … ]` and silently skips when the library is gone). The uninstall output ends with a `Manual cleanup remaining` notice listing exactly these and how to remove them by hand.

## File Overview

Grouped by base directory, paths within each group sorted alphabetically.

### /etc/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `/etc/opencode-permissions-kit/install.conf` | `DEFAULT_USER`, `OPENCODE_USER`, `WWW_GROUP`, `DDEV_BIN`, `DDEV_VERSION`, `CONTAINER_BACKEND`, `OPENCODE_DOCKER_HOST`, `OPENCODE_PODMAN_SOCKET`, `VERSION` |
| `/etc/opencode-permissions-kit/projects.conf` | Project roots (one per line) |

### /etc/sudoers.d/

| Path | Purpose |
|---|---|
| `/etc/sudoers.d/opencode-permissions-kit` | Sudo rules for wrapper, protect-projects.sh, the `opencode:docker` RunAs escalation, and the ddev delegation |

### /home/<default-user>/.config/opencode/

| Path | Purpose |
|---|---|
| `/home/<default-user>/.config/opencode/opencode.jsonc` | Deny-* lockout config against self-update PATH bypass (see "Self-Update Bypass Protection") |

### /home/opencode/.config/opencode/

| Path | Purpose |
|---|---|
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with deny patterns |

### /usr/local/bin/

| Path | Purpose |
|---|---|
| `/usr/local/bin/ddev` | Shadow symlink to the ddev shim (ahead of the real ddev in PATH) |
| `/usr/local/bin/opencode` | Wrapper (symlink to `/usr/local/lib/opencode-permissions-kit/wrapper`) |

### /usr/local/lib/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `/usr/local/lib/opencode-permissions-kit/bin/ddev` | ddev delegation shim (re-execs `ddev` as the developer for the opencode sandbox user) |
| `/usr/local/lib/opencode-permissions-kit/bin/opencode` | The actual opencode binary |
| `/usr/local/lib/opencode-permissions-kit/config.sh` | Change settings post-install (projects, git-config, refresh) |
| `/usr/local/lib/opencode-permissions-kit/hooks/` | Global git hooks (post-checkout, post-merge, post-commit) |
| `/usr/local/lib/opencode-permissions-kit/log.sh` | Shared audit-log helper (sourced by the scripts above) |
| `/usr/local/lib/opencode-permissions-kit/protect-projects.sh` | Applies ACL denies to sensitive files |
| `/usr/local/lib/opencode-permissions-kit/shell-warn.sh` | Wrapper-bypass warning for shell startup (sourced by profile.d + rc files, see "Wrapper-Bypass Guard") |
| `/usr/local/lib/opencode-permissions-kit/status.sh` | Show protection status (works even before install) |
| `/usr/local/lib/opencode-permissions-kit/uninstall.sh` | Uninstall script |
| `/usr/local/lib/opencode-permissions-kit/update.sh` | Re-deploy the kit after an update, no prompts (`--binary`/`--binary-path` also upgrade opencode) |
| `/usr/local/lib/opencode-permissions-kit/wrapper` | Validates directory, handles `-g docker` / container detection, refreshes ACLs, execs opencode |

### /var/log/opencode-permissions-kit/

| Path | Purpose |
|---|---|
| `/var/log/opencode-permissions-kit/` | Audit log (root + default-user group, mode 750/640, self-rotating) |
