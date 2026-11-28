# opencode permissions kit

> **BETA — ready for real-use testing.** The kit is field-tested on
> production systems. The security model is deliberately soft-only (see
> [Security Model](docs/concepts/security-model.md)). Run it on your
> real dev machine, not just a throwaway WSL2 box — and when something
> breaks, [open an issue](https://github.com/steffenmaechtel/opencode-permissions-kit/issues)
> so it gets fixed.

Runs [opencode](https://opencode.ai) as its own Linux user against a
**rootless container backend**, so the agent is UID-separated from you
while ddev keeps working. File permissions are opencode's own **soft**
permission layer (`opencode.jsonc`).

## What It Does

- **Dedicated user** — the wrapper at `/usr/local/bin/opencode` validates
  the project directory, then execs opencode as `opencode` (never as you)
- **Rootless containers only** — docker-rootless or podman-rootless, owned
  by the `opencode` user; no root-equivalent docker socket is ever granted
- **ddev keeps working** — ddev runs as the `opencode` user in the agent
  and in your terminal; the kit hands over the paths ddev chmods

Read how the security model works (and its deliberate trade-offs) in
[Security Model](docs/concepts/security-model.md).

## Is This for Me?

**Yes**, if you run opencode on WSL2 or a Linux dev box, use ddev (or plain
rootless docker/podman) for PHP/web projects, and want the agent UID-separated
without breaking your daily workflow.

**No**, if you are on macOS or Windows (without WSL2), need the agent to share
your own docker daemon, or expect OS-level file denies — file permissions here
are opencode's soft layer only (see [Security Model](docs/concepts/security-model.md)).

## Quick Start

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh | sudo env KIT_BRANCH=stable bash
```

Optional verified variant — download, check the checksum, then run
(the `&&` chain skips the execution when the check fails):

<!-- opk-checksum:start -->

```bash
curl -fsSL -o /tmp/opk-install.sh https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh &&
echo "530dce107a9293ffa5e630c99befa71b5aff8b5f045f7137a05294f8984b8efc  /tmp/opk-install.sh" | sha256sum -c - &&
sudo env KIT_BRANCH=stable bash /tmp/opk-install.sh
```

<!-- opk-checksum:end -->

The checksum describes the `stable` bytes the URL serves and moves with
every release that touches `install.sh` — right after such a release the
check can fail until the Pages site has redeployed (usually minutes; if
it keeps failing, retry later)
([integrity details](docs/concepts/security-model.md#download-integrity-sha256sums)).

The `stable` ref is the release mirror (recommended); `master` is the
development channel — see [Update channels](docs/how-to/update.md#channels).

Update an installed kit with `sudo opk update`.

The installer asks a few questions and shows a plan before touching anything.
The full walkthrough (including verification) lives in
[Getting Started](docs/getting-started.md).

## Tell Your Agent About the Kit

The kit changes a few git behaviors on purpose — an AI agent working on
an installed kit does not know that. Point it at the notes the kit
ships for exactly this case. Optional, and a one-time step: the pointer
stays valid across updates. Copy the block into the agent's global
`AGENTS.md` (`/home/opencode/.config/opencode/AGENTS.md`):

<!-- opk-agents-snippet:start -->

```text
This host runs the opencode permissions kit. Before your first git
command or file-permission change in a project, read the host notes
and follow them — some git failures are expected here and must not
be "fixed":

/usr/local/lib/opencode-permissions-kit/templates/AGENTS-HOST.md

(No such file: this machine has no kit installed — ignore this note.)
```

<!-- opk-agents-snippet:end -->

The notes live at the path above and are kept current by `sudo opk update`.
What they cover and how the pointer works:
[Tell your agent about the kit](docs/how-to/agent-host-notes.md).

## Requirements

- WSL2 (or any Linux with ACL support and, for docker-rootless, systemd)
- Ubuntu 22.04 LTS / Debian 12 or newer — the support floor; only
  Ubuntu 24.04 passes automated tests and is field-tested today (see the
  [support matrix](docs/getting-started.md#supported-distros)). Older
  Ubuntu LTS releases are ESM-only; no fixes are made for them
- `sudo` access
- `curl`
- `python3` (shipped with default WSL2 images)
- ddev ≥ 1.25 (when ddev is installed)

## Documentation

The docs are structured by need — start at the [documentation index](docs/README.md):

- [Getting started](docs/getting-started.md) — install, configure, verify
- [Security model](docs/concepts/security-model.md) and the other
  [concepts](docs/README.md#concepts-why-it-works-this-way)
- [How-to guides](docs/README.md#how-to-guides-solve-a-task) — manage projects, allow ddev, update, uninstall
- [Reference](docs/README.md#reference-look-it-up) — CLI, files, audit log, glossary
- [Troubleshooting](docs/troubleshooting.md) — symptom → cause → fix

## License

MIT

## Disclaimer

Community project — not affiliated with, endorsed by, or officially supported by OpenCode or Anomaly Innovations, Inc.
This project is an independent community tool for configuring permissions for OpenCode.
