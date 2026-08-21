# opencode permissions kit

> ⚠️ **ALPHA — not for production use.** This kit is still in active development and has not been audited. The scripts and sudoers configuration may change in breaking ways between releases. Run it on a throwaway WSL2/dev box, not on a production server.

Runs [opencode](https://opencode.ai) as its own Linux user against a **rootless container backend**, so the agent is UID-separated from you while ddev keeps working. File permissions are opencode's own **soft** permission layer (`opencode.jsonc`).

## What It Does

- **Dedicated user** — the wrapper at `/usr/local/bin/opencode` validates the project directory, then execs opencode as `opencode` (never as you)
- **Rootless containers only** — docker-rootless or podman-rootless, owned by the `opencode` user; no root-equivalent docker socket is ever granted
- **ddev keeps working** — ddev runs as the `opencode` user in the agent and in your terminal; the kit hands over the paths ddev chmods

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
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

The installer asks a few questions and shows a plan before touching anything.
The full walkthrough (including verification) lives in
[Getting Started](docs/getting-started.md).

## Requirements

- WSL2 (or any Linux with ACL support and, for docker-rootless, systemd)
- `sudo` access
- `curl`
- ddev ≥ 1.25 (when ddev is installed)

## Documentation

The docs are structured by need — start at the [documentation index](docs/README.md):

- [Getting started](docs/getting-started.md) — install, configure, verify
- [Security model](docs/concepts/security-model.md) and the other [concepts](docs/README.md#concepts-why-it-works-this-way)
- [How-to guides](docs/README.md#how-to-guides-solve-a-task) — manage projects, allow ddev, update, uninstall
- [Reference](docs/README.md#reference-look-it-up) — CLI, files, audit log, glossary
- [Troubleshooting](docs/troubleshooting.md) — symptom → cause → fix

## License

MIT

## Disclaimer

Community project — not affiliated with, endorsed by, or officially supported by OpenCode or Anomaly Innovations, Inc.
This project is an independent community tool for configuring permissions for OpenCode.
