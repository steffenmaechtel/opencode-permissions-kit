# CLI reference

This page lists the kit's commands and flags.

## wsl-add-opencode-1-fix

Write the WSL browser-bridge carrier into `/etc/wsl.conf` (sudo — the
command elevates itself):

```bash
sudo opk wsl-add-opencode-1-fix
```

Keeps opencode device logins (`console login` / `auth login`) alive on a
hardened `/mnt/c` for versions bundling `open` 10.x — 1.x **< 1.18.33**
and 2.x **< 2.0.18**: the carrier is a comment block at the top of your
`wsl.conf` whose `root =` line wins the bundled `open` package's scan,
redirecting its powershell.exe lookup to the kit stand-in (forwards for
you, exits 0 for the agent). Takes effect immediately — no
`wsl --shutdown` needed, WSL only ever sees comments. Newer versions
access-check powershell and fall back to xdg-open (the kit ships an
xdg-open fallback shim for that path), so device logins survive without
the bridge — the kit does not warn for those versions.

This is the **only** kit command that writes `/etc/wsl.conf` — install
and update never touch the file; they only deploy the stand-in tree and
tell you about this command ([why](../design/wsl-conf-consent.md)). The
command is idempotent and also cleans up the broken kit-0.0.36 section if
one is present. `opk uninstall` asks before removing the block again
(`--yes` assumes yes).

## The `opk` command

After installation, one command manages everything (works from anywhere in
your WSL/Linux system):

```bash
opk status
opk config projects add /var/www/vhosts/new-project
opk update --binary
opk upgrade-opencode   # just the opencode binary
opk fix-user-manager   # rescue the agent user manager (systemd cgroup bug)
opk ddev-hosts-add     # in a ddev project dir
opk handover me .gotmp # mixed-owner tree -> yours again
opk wsl-add-opencode-1-fix   # opt in to the WSL browser-bridge carrier
opk uninstall
opk help        # commands + arguments overview
opk --version   # the deployed kit version
```

Everything after the subcommand goes to the underlying script unchanged,
so all flags below work with both forms. `config`, `update`, `handover`
and `fix-user-manager` elevate via sudo automatically; `status` needs no
sudo; `uninstall` runs as
your user and asks for sudo itself; `ddev-hosts-*` run as your user (they
drive Windows-side elevation through ddev itself).

`opk --version` prints the deployed kit version in one line (`opk <x.y.z>`)
— the `VERSION` stamp from `install.conf`, the same value `opk status`
reports. Without an install (no `install.conf`) it answers `opk 0.0.0`
instead of failing.

The command is a symlink (`/usr/local/bin/opk`) into
the kit library — deployed since kit 0.0.14 as `opencode-permissions-kit`
and renamed to `opk` (issue #48). On older installs, run
[update](../how-to/update.md) once to switch to the new name — it creates
`opk` and removes the old long-name symlink. The direct script calls below
keep working everywhere.

## handover

Switch file ownership between the two kit users — you and the agent:

```bash
# You and the agent both ran builds in the same checkout; ddev's .gotmp
# cache now contains files of both users and every build complains
# ("chmod ... Operation not permitted"). Make the whole tree yours again:
cd /var/www/vhosts/ddev
opk handover me .gotmp

# Same idea the other way — give a folder to the agent user:
opk handover opencode /var/www/vhosts/some-project

# Not sure yet? Show what would happen, without sudo:
opk handover me .gotmp --dry-run
```

`me` and `opencode` resolve to your default user and the agent user from
the kit's install configuration — no usernames to remember, no root shell.
Plain `chown -R` would need both.

System roots and their subpaths (`/etc`, `/etc/apache2`, `/usr/local/...`)
and whole home directories are refused — hand over project trees, not
systems. `/tmp` subpaths are allowed (temp build trees are legitimate
handover targets). Symlinked paths are refused too: the kit never hands a
tree over through a link (`--dry-run` lists the refusals it would make).
Operands must be slash- and dotdot-free — `x/`, `x//`, `x/.`, `x/..` and
mid-path `a/../b` are refused with a usage error: a trailing slash or a
`..` component resolves through a link before the symlink gate can see
it, so both the gate and the recursive pair would act on the resolved
target (the link itself, or its parent). The recursive pair itself cannot be steered through a
planted link either: the ownership change rides `chown -R -h` (lchown on
a planted operand re-owns the attacker's own link, nothing outside), and
the group-write pass only ever sees non-symlinks (`find ! -type l` feeds
it) — a link swapped between the check and the run touches nothing
outside the tree.

The change is recursive and only flips the **owner** — the group stays the
kit's sharing group and group-write access is re-applied, so both sides
keep their group access to the tree (the same semantics as the ddev
handovers, see [ddev integration](../concepts/ddev-integration.md)).
System roots (`/`, `/usr`, `/var`, ...) and whole home directories are
refused — hand over trees, not systems. The command elevates via sudo
itself; `--dry-run` validates and prints the plan without sudo.

## ddev-hosts-add / ddev-hosts-check

Windows hosts bridge (WSL2): ddev runs as `opencode` and cannot manage
the Windows hosts file — your Windows browser cannot resolve custom-
`project_tld` domains. These commands stay on the developer side; the
agent never gets hosts-file access.

```bash
opk ddev-hosts-check   # what is missing?
opk ddev-hosts-add     # add it (Windows asks permission)
```

`ddev-hosts-add` runs `ddev hostname <name> 127.0.0.1` as your user for
every hostname missing from `C:\Windows\System32\drivers\etc\hosts`
(project name + TLD, `additional_hostnames`, non-wildcard
`additional_fqdns`); ddev elevates via `ddev-hostname.exe` and Windows
shows its confirmation dialog (needs working WSL interop). Both take an
optional project directory argument (default: the current directory).

Hostnames under the default `*.ddev.site` TLD are never reported or
added — ddev's public wildcard DNS already resolves them, no hosts
entry is needed (the per-hostname commands the status and the `ddev()`
hook print include the name, so you add exactly what was reported:

```bash
opk ddev-hosts-add my-fancy-project.local
```

works from anywhere). The status scan also skips `vendor/`,
`node_modules/`, and `testdata/`: composer/npm packages ship their own
`.ddev` dirs (package development checkouts) which are not your projects.

## fix-user-manager

Rescue command for the systemd cgroup-reuse bug
([systemd#41278](https://github.com/systemd/systemd/issues/41278),
affects systemd ≤ 260 — Ubuntu 26.04 ships 259): on some boots every
attempt to start a user manager fails with
`Failed to spawn executor: Device or resource busy`, which WSL surfaces
at login as `wsl: Failed to start the systemd user session for '<you>'`.
The agent backend dies with it (`docker-rootless`: no daemon;
`podman-rootless`: no docker-API socket for ddev).

```bash
sudo opk fix-user-manager
```

The command un-wedges the agent user's `user@<uid>.service` cgroup
without a WSL restart: it kills the dead manager's orphaned processes
(strictly UID-gated to the agent user), clears the leftover cgroup
controllers bottom-up and restarts the unit — a procedure
field-validated on Ubuntu 26.04 WSL2. Backend units enabled earlier
(docker.service, podman.socket) come up with the manager. The installer
attempts the same rescue automatically when provisioning hits the bug;
this command is the on-demand variant for later boots. If it does not
succeed, the remaining way out is a WSL restart from Windows
(`wsl --shutdown` or `wsl -t <distro>`). Background and the manual
procedure: [troubleshooting](../troubleshooting.md).

## install.sh

Installs the kit. Stream it from GitHub or run it from a checkout; when
streamed, it self-fetches its sibling files from the same ref. The docs
one-liner uses the `stable` release mirror:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/stable/files/install.sh | sudo env KIT_BRANCH=stable bash
```

| Flag | Meaning |
|---|---|
| `--yes` | Skip all prompts, assume Yes (Standard mode with defaults) |
| `--projects <path...>` | Pre-define project roots, skip interactive selection (consumes every following non-flag argument) |
| `--container-backend <docker-rootless\|podman-rootless>` | Non-interactive backend choice |
| `--skip-ddev-migration` | Do not export the dev user's ddev databases (no `Step 4b` dumps) |
| `--ddev-settings <dev-owned\|ddev>` | Pre-decide the settings mode: `dev-owned` writes `disable_settings_management: true` (recommended), `ddev` keeps ddev managing settings |
| `--secure-git-config` | Enable `.git/config` hardening up front |
| `--migrate-agents <move\|copy\|skip>` | Bring the developer's agent resources into `/home/opencode`: `~/.agents` **whole** (opencode's own namespace) + `~/.claude/skills` **skills/ only** (credentials like `~/.claude/.credentials.json` stay in your home) — move (recommended), copy, or skip; default: ask (`--yes` = move) |

Flags may appear in any order; unknown options abort the install.

Environment: `KIT_BRANCH` (default `master`) selects the ref to fetch
siblings from — any branch or version tag works (`stable` release mirror,
`master` dev channel, `feature/...`, `0.0.29`; see
[update channels](../how-to/update.md#channels)). The value is stamped as
`KIT_CHANNEL` in `install.conf`, which later `opk update` runs follow.
Refs are limited to `A-Z a-z 0-9 . _ / -` (a git-ref charset) — anything
else is refused before anything runs.

## config.sh

Change settings on an installed kit.

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/management/config.sh <command>
```

| Command | Meaning |
|---|---|
| `status` | Quick overview: git-config state + configured project roots |
| `projects list` | Show configured project roots |
| `projects add <path...>` | Register roots + apply group baseline + ddev handover |
| `projects remove <path...>` | Remove the `projects.conf` lines (files untouched) |
| `git-config on\|off\|status` | Manage the `.git/config` deny (see [harden .git/config](../how-to/secure-git-config.md)) |
| `container-backend docker-rootless\|podman-rootless` | Switch the backend (see [switch the backend](../how-to/switch-container-backend.md)) |
| `container-backend status` | Show the configured backend + socket state |
| `refresh` | Re-apply the group baseline (chgrp/setgid/default ACLs) |
| `handover <path...>` | Re-run the ddev handover for one project — the fresh-clone EPERM repair (see [ddev integration](../concepts/ddev-integration.md)) |
| `ddev-settings on\|off\|status` | Dev-owned projects: kit writes `disable_settings_management: true` (see [dev-owned projects](../how-to/dev-owned-projects.md)) |

## update.sh

Re-deploy the kit after an update; upgrades the opencode binary.

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/stable/files/opencode-permissions-kit-lib/management/update.sh | sudo env KIT_BRANCH=stable bash
```

Without `KIT_BRANCH` set, the deployed `update.sh` follows the channel
stamped in `install.conf` (`KIT_CHANNEL`, shown by `opk status`). Switch
channels without editing `install.conf`:

```bash
sudo opk update --channel stable   # or master, a feature branch, or a tag
```

| Flag | Meaning |
|---|---|
| `--yes` | Skip the confirmation prompt |
| `--refresh` | Also re-apply the group baseline |
| `--binary` | Also upgrade the opencode binary to the latest release **of the current major** |
| `--only-binary` | Skip every kit step, only upgrade the opencode binary |
| `--binary-path <file>` | Install a specific binary file instead |
| `--channel <ref>` | Switch the tracking ref for this and every future update (re-stamps `KIT_CHANNEL`) |
| `--major 1\|2` | Switch the opencode major (TUI registration flips with it) |
| `--version <ver>` | Upgrade to exactly this opencode version (channel by prefix: `2.*` from npm, `1.x` from GitHub) |

Upgrades never cross majors silently (issue #99): without `--major` /
`--version` the latest release **of the installed major** is used — 1.x
resolves through GitHub releases, 2.x through the npm dist-tag `latest`
(the channel the official v2 installer uses). `opk upgrade-opencode` is
the shorthand for `update --yes --only-binary` — extra flags (e.g.
`--binary-path`, `--major 2`, `--version 2.0.11`) pass through:

```bash
sudo opk upgrade-opencode                 # latest of the current major
sudo opk upgrade-opencode --major 2       # switch 1.x -> 2.x (latest 2.x)
sudo opk upgrade-opencode --major 1       # switch back to latest 1.x
sudo opk upgrade-opencode --version 2.0.11
```

Never touches `projects.conf` or the agent's `opencode.jsonc`. See
[update](../how-to/update.md).

## status.sh

Show the protection status: mode, backend + socket reachability, the
host git against the tested floor, project roots, ddev runtime readiness
(`~opencode/.ddev`, router ports, mkcert CA), migration state, the
security-advisory check (see
[security advisories](../how-to/update.md#security-advisories)), the WSL2
`/mnt/c` exposure (including the browser-bridge state), the
root-equivalent-access audit, and the leak scan — followed by management
hints (`opk update`, `opk config`, ...).

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/management/status.sh
```

Runs from a checkout too (`sudo bash files/opencode-permissions-kit-lib/management/status.sh`) and works **before**
an install or after an uninstall — it reports "NOT active" when the kit is
not installed. Use it to check whether hardening is active from any machine.

## uninstall.sh

Remove everything the kit installed (see [uninstall](../how-to/uninstall.md)).

```bash
bash /usr/local/lib/opencode-permissions-kit/management/uninstall.sh
```

| Flag | Meaning |
|---|---|
| `--yes` | Skip all prompts |
| `--dry-run` | Show what would be removed, change nothing |
| `--debug` | Trace execution (`set -x`) |
