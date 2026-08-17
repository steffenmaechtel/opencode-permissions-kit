# CLI reference

This page lists every kit script with its flags. Management scripts live in
`/usr/local/lib/opencode-permissions-kit/` after installation.

## install.sh

Installs the kit. Stream it from GitHub or run it from a checkout; when
streamed, it self-fetches its sibling files from the same branch.

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

| Flag | Meaning |
|---|---|
| `--yes` | Skip all prompts, assume Yes (Standard mode with defaults) |
| `--projects <path...>` | Pre-define project roots, skip interactive selection |
| `--container-backend <docker-rootless\|podman-rootless>` | Non-interactive backend choice — must come **before** `--projects` (the projects flag consumes the rest of the command line) |
| `--secure-git-config` | Enable `.git/config` hardening up front |

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
| `--binary-path <file>` | Install a specific binary file instead |

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
