# CLI reference

This page lists the kit's commands and flags.

## The `opencode-permissions-kit` command

After installation, one command manages everything (works from anywhere in
your WSL/Linux system):

```bash
opencode-permissions-kit status
opencode-permissions-kit config projects add /var/www/vhosts/new-project
opencode-permissions-kit update --binary
opencode-permissions-kit upgrade-opencode   # just the opencode binary
opencode-permissions-kit ddev-hosts-add     # in a ddev project dir
opencode-permissions-kit handover me .gotmp # mixed-owner tree -> yours
opencode-permissions-kit uninstall
opencode-permissions-kit help        # commands + arguments overview
```

Everything after the subcommand goes to the underlying script unchanged,
so all flags below work with both forms. `config`, `update` and `handover`
elevate via sudo automatically; `status` needs no sudo; `uninstall` runs as
your user and asks for sudo itself; `ddev-hosts-*` run as your user (they
drive Windows-side elevation through ddev itself).

The command is a symlink (`/usr/local/bin/opencode-permissions-kit`) into
the kit library — deployed since kit 0.0.14. On older installs, run
[update](../how-to/update.md) once to get it. The direct script calls below
keep working everywhere.

## handover

Switch file ownership between the two kit users — you and the agent:

```bash
opencode-permissions-kit handover me <path>...        # -> your user
opencode-permissions-kit handover opencode <path>...  # -> the agent user
opencode-permissions-kit handover me .gotmp --dry-run # show the plan only
```

For mixed-owner trees: when both you and the agent built or worked in the
same checkout (for example ddev's `.gotmp` build cache after tests ran as
both users), plain `chown` needs root and the exact usernames. `handover`
does the recursive `chown` for you — `me` resolves to your default user,
`opencode` to the agent user, both from the kit's install configuration.

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
opencode-permissions-kit ddev-hosts-check   # what is missing?
opencode-permissions-kit ddev-hosts-add     # add it (Windows asks permission)
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
opencode-permissions-kit ddev-hosts-add my-fancy-project.local
```

works from anywhere). The status scan also skips `vendor/` and
`node_modules/`: composer/npm packages ship their own `.ddev` dirs
(package development checkouts) which are not your projects.

## install.sh

Installs the kit. Stream it from GitHub or run it from a checkout; when
streamed, it self-fetches its sibling files from the same branch.

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

| Flag | Meaning |
|---|---|
| `--yes` | Skip all prompts, assume Yes (Standard mode with defaults) |
| `--projects <path...>` | Pre-define project roots, skip interactive selection (consumes every following non-flag argument) |
| `--container-backend <docker-rootless\|podman-rootless>` | Non-interactive backend choice |
| `--secure-git-config` | Enable `.git/config` hardening up front |
| `--migrate-agents <move\|copy\|skip>` | Bring the developer's agent resources into `/home/opencode`: `~/.agents` **whole** (opencode's own namespace) + `~/.claude/skills` **skills/ only** (credentials like `~/.claude/.credentials.json` stay in your home) — move (recommended), copy, or skip; default: ask (`--yes` = move) |

Flags may appear in any order; unknown options abort the install.

Environment: `KIT_BRANCH` (default `master`) selects the branch to fetch
siblings from — used for testing feature branches.

## config.sh

Change settings on an installed kit.

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/config.sh <command>
```

| Command | Meaning |
|---|---|
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
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/update.sh | sudo bash
```

| Flag | Meaning |
|---|---|
| `--yes` | Skip the confirmation prompt |
| `--refresh` | Also re-apply the group baseline |
| `--binary` | Also upgrade the opencode binary to the latest release |
| `--only-binary` | Skip every kit step, only upgrade the opencode binary |
| `--binary-path <file>` | Install a specific binary file instead |

`opencode-permissions-kit upgrade-opencode` is the shorthand for
`update --yes --only-binary` — extra flags (e.g. `--binary-path`) pass
through.

Never touches `projects.conf` or the agent's `opencode.jsonc`. See
[update](../how-to/update.md).

## status.sh

Show the protection status: mode, backend + socket reachability, ddev
runtime readiness (`~opencode/.ddev`, router ports, mkcert CA), migration
state, and the leak scan.

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/status.sh
```

Runs from a checkout too (`sudo bash files/status.sh`) and works **before**
an install or after an uninstall — it reports "NOT active" when the kit is
not installed. Use it to check whether hardening is active from any machine.

## uninstall.sh

Remove everything the kit installed (see [uninstall](../how-to/uninstall.md)).

```bash
bash /usr/local/lib/opencode-permissions-kit/uninstall.sh
```

| Flag | Meaning |
|---|---|
| `--yes` | Skip all prompts |
| `--dry-run` | Show what would be removed, change nothing |
| `--debug` | Trace execution (`set -x`) |
