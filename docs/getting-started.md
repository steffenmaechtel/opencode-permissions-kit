# Getting started

Install the kit on your machine and verify that the agent runs separated.

## Prerequisites

- WSL2 (or any Linux with ACL support and, for docker-rootless, systemd)
- a supported distro — see the [support matrix](#supported-distros)
- `sudo` access, `curl`, `python3`
- `git` ≥ 2.30 — older versions warn, the installer never aborts over git
- ddev ≥ 1.25, if ddev is installed (the installer aborts on older versions)

The kit installs the rootless container backend itself (packages,
subuid/subgid ranges, linger).

### Supported distros

| Distro / version | Supported | Automated tests | Field-tested |
|------------------|-----------|-----------------|--------------|
| Ubuntu 22.04     | yes       | no              | no           |
| Ubuntu 24.04     | yes       | yes             | yes          |
| Ubuntu 26.04     | no        | no              | no           |
| Debian 12+       | yes       | no              | no           |

Ubuntu 26.04 ships a default sudo that freezes streamed installs and a
systemd that sporadically refuses user managers — known upstream errors, so
new installs are blocked. Older Ubuntu LTS releases are ESM-only.
`install.sh --force-unsupported-distro` overrides the gate — at your own
risk. Existing installs on any distro keep updating via `opk update`.

## Install

Run the one-liner in a terminal on the target machine:

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh | sudo env KIT_BRANCH=stable bash
```

Run it from your **normal user account** via `sudo` — never from a root shell
(`wsl -u root` on Windows, `su -`, a root ssh session). A root shell has no
`SUDO_USER`, so the installer would register `root` as the developer; it
refuses such runs up front.

The installer prints a pre-flight inventory of what it found, then asks:

1. **Project directory** — the folder holding your projects, e.g.
   `/var/www/vhosts` (the default when it exists) or `~/dev`. The agent may
   only start inside this tree; system paths are rejected.
2. **Git access** — block `.git/config` for the agent (default) or allow git
   commands. Changeable later:
   [harden `.git/config`](how-to/secure-git-config.md).
3. **ddev settings** — dev-owned projects (default: everything outside
   `.ddev/` stays permanently yours) or ddev-managed settings — see
   [dev-owned projects](how-to/dev-owned-projects.md).
4. **Agent resources** (only when `~/.agents` or `~/.claude/skills` exist) —
   move them into `/home/opencode` (recommended), copy, or skip. Enter
   defaults to **skip** — move removes the developer-side sources after
   the copy, so it never rides on an empty Enter.

A fifth, conditional question — "Protect OpenChamber sessions too?" —
appears when OpenChamber is detected; see
[Use OpenChamber with the kit](how-to/openchamber.md). When podman is
detected you also choose the backend (podman-rootless is the default);
otherwise docker-rootless is used silently.

After the questions the installer shows a numbered plan — confirm with Enter.
Advanced mode exposes granular prompts for the steps Standard decides
silently. Non-interactive installs work too (see the
[CLI reference](reference/cli.md) for all flags):

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh \
  | sudo env KIT_BRANCH=stable bash -s -- --yes --projects /var/www/vhosts
```

## Restart your terminal

Open a **fresh terminal** (or log in again) before continuing:

- sharing-group membership only takes effect on your next login,
- the `ddev` shell function and the PATH/umask additions load in new sessions
  only,
- a shell that has run opencode before may still cache the old
  `~/.opencode/bin` binary — same-shell fix: `hash -r` and
  `export PATH="/usr/local/bin:$PATH"`.

## Verify the installation

```bash
opk status
```

It reports the protection mode, backend, ddev readiness, `/mnt/c` exposure
and a leak scan. Everything green means the kit is active. On WSL, the
`/mnt/c` exposure means your Windows profile (`.ssh`, `NTUSER.DAT`,
browser data) stays readable by the agent until you restrict the
automount — `opencode` warns on every start until it is fixed, and the
manual `/etc/wsl.conf` snippet is yours to apply (the kit never edits
that file; see [security model](concepts/security-model.md)).

## Start your first session

```bash
cd /var/www/vhosts/myproject/
opencode
```

The wrapper starts opencode as the `opencode` user. Ask the agent something
small — `.env` and friends are denied by the bundled config. If you see a
loud warning about `~/.opencode/bin` or a bypass, see
[Troubleshooting](troubleshooting.md).

## Optional: ddev smoke test

1. In your terminal: `ddev start` — the kit's `ddev()` shell function routes
   it through the opencode user.
2. In an opencode session in the same project (with the
   [ddev/docker allow](how-to/container-tools.md) active): `ddev list`.

The **first** `ddev start` is slow (mutagen download, image pulls); every
later start reuses that state.

If you had ddev projects before the kit, their databases were exported to
`/var/backups/opencode-permissions-kit/ddev-migration-*/`. Re-import when
ready:

```bash
sudo sh /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate import
# or per project:
ddev start <project> && ddev import-db <project> --file=<dump>.sql.gz
```

## Next steps

- [Allow docker/ddev in a project](how-to/container-tools.md)
- [Manage project directories](how-to/manage-projects.md)
- [Security model](concepts/security-model.md)
- [Troubleshooting](troubleshooting.md)
