# Getting started

This page walks you through installing the kit on your machine and verifying
that the agent runs separated — it is a linear tutorial; alternatives and
background are linked at the end.

## Prerequisites

- WSL2 (or any Linux with ACL support and, for docker-rootless, systemd)
- Ubuntu 22.04 LTS / Debian 12 or newer — the oldest baselines the kit is
  tested on (older Ubuntu LTS releases are ESM-only; no fixes are made for
  them)
- `sudo` access on that machine
- `curl`
- `python3` (used for JSON parsing, the baseline progress pipe and version
  resolution — default WSL2 images ship it; the installer probes for it)
- `git` ≥ 2.30 — what the oldest supported baseline distros ship (Debian 12 /
  Ubuntu 22.04); any newer git works (WSL Ubuntu 24.04 ships 2.43, the
  [git-core PPA](troubleshooting.md#git-is-below-the-tested-version-baseline)
  tracks the current release). The installer warns below that floor; it never
  aborts over git
- ddev ≥ 1.25, if ddev is installed (the installer aborts on older versions)

Nothing else — the kit installs the rootless container backend (packages,
subuid/subgid ranges, linger) itself.

## Install

Run the one-liner in a terminal on the target machine:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/stable/files/install.sh | sudo env KIT_BRANCH=stable bash
```

The script detects that it is streamed, fetches its sibling files from the
same `stable` release mirror, and first prints a **pre-flight inventory** of what it
found on your system (WSL2, curl/acl, ddev, docker/podman, an existing kit
installation, `/mnt/c` exposure, router ports).

It then asks only the essential questions (in this order — the agent
resources question comes much later in the run, right before the finish):

1. **Project directory** — the folder that holds your projects, e.g.
   `/var/www/vhosts`, `~/dev` or `~/projects` (default `/var/www/vhosts`
   when it exists). The agent may only start inside this tree. System
   paths (`/`, `/usr`, `/home`, …) are rejected — the installer would
   otherwise run its group baseline over them.
2. **Git access** — block `.git/config` for the agent (default) or allow git
   commands. You can change this later with
   [git-config](how-to/secure-git-config.md). Either way the agent's git can
   read your repositories: the group baseline covers `.git/`, and the kit
   sets `safe.directory` for the `opencode` user (no "dubious ownership"
   errors).
3. **ddev settings** — dev-owned projects (default): the kit writes
   `disable_settings_management: true` into each project's
   `.ddev/config.yaml`, so everything outside `.ddev/` stays permanently
   yours and `git checkout` never hits ownership errors. Choose `ddev` to
   keep ddev's settings management (handover model) instead. See
   [dev-owned projects](how-to/dev-owned-projects.md).
4. **Agent resources** (asked near the end, and only when `~/.agents` or
   `~/.claude/skills` actually exist) — bring the resources opencode
   auto-loads into `/home/opencode` so the agent can use them: `~/.agents`
   (**whole directory** — it is opencode's own namespace) and
   `~/.claude/skills` (**skills/ only** — the rest of `~/.claude` is
   Claude Code's home, so credentials like `.credentials.json` stay in
   your home). Choose **move** (recommended — one canonical copy; you
   keep read/write via the sharing group), **copy** (both sides keep
   their own, may drift) or **skip**. Non-interactive installs move;
   `--migrate-agents move|copy|skip` forces a choice.

One exception: when podman is detected, you choose between podman-rootless
(default) and docker-rootless. Otherwise docker-rootless is used silently.

After the questions the installer shows a numbered **plan** (user + sharing
group, backend provisioning, ACLs, binary + wrapper, `/mnt/c` hardening
snippet, port sysctl, deny-all config, library deploy) with `Confirm` /
`Switch to Advanced` / `Abort`. Confirm with Enter — everything not asked
runs with the recommended value.

**Advanced mode** exposes granular prompts for the steps Standard decides
silently (backend choice, project multi-select, port sysctl, ACL baseline,
binary handling, deny-all handling). The `/mnt/c` exposure is never a
prompt in either mode — the kit only *prints* the ready-to-run
restriction snippet (it never edits `/etc/wsl.conf` itself; see the
[security model](concepts/security-model.md)). Non-interactive installs
work too:
`install.sh --yes --container-backend podman-rootless --projects /var/www/vhosts`
— see the [CLI reference](reference/cli.md).

## Restart your terminal

Open a **fresh terminal** (or log in again) before continuing — for every
install, not only the special case below:

- **Sharing-group membership** is granted at install time
  (`usermod -aG`) but only takes effect on your next login — until then
  the current session cannot access your projects through the group.
- The **`ddev` shell function** is hooked into your rc files; an old
  terminal does not have it, and a `ddev` there would run as you, unable
  to see the rootless daemon.
- The **PATH and umask** additions from the profile script only load in
  new sessions.

Special case — a shell that has run opencode before also has the old
`~/.opencode/bin` binary cached (bash's command hash) and lists that
directory first in `$PATH`: until you open a new terminal, `opencode`
would resolve to the old binary and bypass the wrapper. Same-shell fix:
`hash -r` and `export PATH="/usr/local/bin:$PATH"`.

## Verify the installation

Run the status script:

```bash
opk status
```

It reports the protection mode, backend + socket reachability, ddev runtime
readiness, the `/mnt/c` exposure, the root-equivalent-access audit, and a
leak scan, followed by management hints. Everything green means the kit is
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
2. In an opencode session in the same project, if it is in the
   **with ddev/docker** state (see
   [allow docker and ddev](how-to/container-tools.md)): `ddev list`.

The **first** `ddev start` is slow (mutagen download, image pulls into the
rootless daemon); every later start reuses that state. Details:
[ddev integration](concepts/ddev-integration.md).

If you had ddev projects before the kit, the installer exported their
databases to `/var/backups/opencode-permissions-kit/ddev-migration-*/`
(Standard mode exports automatically after you confirm the plan; Advanced
mode asks first; `--skip-ddev-migration` opts out). Re-import
them when ready:

```bash
sudo sh /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate import
```

or per project with `ddev import-db <project> --file=<dump>.sql.gz` —
see [ddev integration](concepts/ddev-integration.md).

## Next steps

- Give a project access to docker/ddev: [Allow docker/ddev](how-to/container-tools.md)
- Add more project folders: [Manage project directories](how-to/manage-projects.md)
- Understand what the kit guarantees: [Security model](concepts/security-model.md)
- Something went wrong? [Troubleshooting](troubleshooting.md)
