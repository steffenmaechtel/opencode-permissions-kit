# Getting started

This page walks you through installing the kit on your machine and verifying
that the agent runs separated — it is a linear tutorial; alternatives and
background are linked at the end.

## Prerequisites

- WSL2 (or any Linux with ACL support and, for docker-rootless, systemd)
- `sudo` access on that machine
- `curl`
- ddev ≥ 1.25, if ddev is installed (the installer aborts on older versions)

Nothing else — the kit installs the rootless container backend (packages,
subuid/subgid ranges, linger) itself.

## Install

Run the one-liner in a terminal on the target machine:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

The script detects that it is streamed, fetches its sibling files from the
same `master` branch, and first prints a **pre-flight inventory** of what it
found on your system (WSL2, curl/acl, ddev, docker/podman, an existing kit
installation, `/mnt/c` exposure, router ports).

It then asks only two questions:

1. **Project directory** — the folder that holds your projects, e.g.
   `/var/www/vhosts`, `~/dev` or `~/projects` (default `/var/www/vhosts`
   when it exists). The agent may only start inside this tree. System
   paths (`/`, `/usr`, `/home`, …) are rejected — the installer would
   otherwise run its group baseline over them.
2. **Git access** — block `.git/config` for the agent (default) or allow git
   commands. You can change this later with
   [git-config](how-to/secure-git-config.md).

One exception: when podman is detected, you choose between podman-rootless
(default) and docker-rootless. Otherwise docker-rootless is used silently.

After the questions the installer shows a numbered **plan** (user + sharing
group, backend provisioning, ACLs, binary + wrapper, `/mnt/c` restriction,
port sysctl, deny-all config, library deploy) with `Confirm` / `Switch to
Advanced` / `Abort`. Confirm with Enter — everything not asked runs with the
recommended value.

**Advanced mode** exposes granular prompts for every step (backend choice,
project multi-select, port sysctl, `/mnt/c` restriction, ACL baseline, binary
handling, deny-all handling). Non-interactive installs work too:
`install.sh --yes --container-backend podman-rootless --projects /var/www/vhosts`
— see the [CLI reference](reference/cli.md).

## Restart your terminal

Open a **fresh terminal** before running opencode. A shell that has run
opencode before still has the old `~/.opencode/bin` binary cached (bash's
command hash) and lists that directory first in `$PATH` — until you open a
new terminal, `opencode` would resolve to the old binary and bypass the
wrapper. Same-shell fix: `hash -r` and
`export PATH="/usr/local/bin:$PATH"`.

## Verify the installation

Run the status script:

```bash
opencode-permissions-kit status
```

It reports the protection mode, backend + socket reachability, ddev runtime
readiness, and ends with a leak scan. Everything green means the kit is
active.

## Start your first session

`cd` into a project below your registered project directory and start
opencode:

```bash
cd /var/www/vhosts/myproject/
opencode
```

You should see the wrapper start opencode as the `opencode` user. Ask the
agent something small — for example to list the files in the project root and
explain what it may not read (`.env` and friends are denied by the bundled
config).

If you see a loud warning about `~/.opencode/bin` or a bypass, see
[Troubleshooting](troubleshooting.md).

## Optional: ddev smoke test

If you use ddev, verify that it runs as the `opencode` user from both sides:

1. In your terminal: `ddev start` (the kit's `ddev()` shell function routes
   it through the opencode user — open a fresh terminal first).
2. In an opencode session in the same project, if it opted into container
   tools: `ddev list`.

The **first** `ddev start` is slow (mutagen download, image pulls into the
rootless daemon); every later start reuses that state. Details:
[ddev integration](concepts/ddev-integration.md).

If you had ddev projects before the kit, the installer exported their
databases to `/var/backups/opencode-permissions-kit/ddev-migration-*/`
(asked before the switch; `--skip-ddev-migration` opts out). Re-import
them when ready:

```bash
sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh import
```

or per project with `ddev import-db <project> --file=<dump>.sql.gz` —
see [ddev integration](concepts/ddev-integration.md).

## Next steps

- Give a project access to docker/ddev: [Allow docker/ddev](how-to/container-tools.md)
- Add more project folders: [Manage project directories](how-to/manage-projects.md)
- Understand what the kit guarantees: [Security model](concepts/security-model.md)
- Something went wrong? [Troubleshooting](troubleshooting.md)
