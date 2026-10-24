# Documentation

The user documentation for the kit — written for developers who run opencode
on a WSL2/Linux dev box with ddev. See the [README](../README.md) whether the
kit fits your setup.

## Getting started

- [Getting started](getting-started.md) — install, answer the installer
  questions, verify the first agent session

## Concepts (why it works this way)

- [Security model](concepts/security-model.md) — guarantees, the soft-only
  trade-off, residual gaps
- [The wrapper](concepts/wrapper.md) — what happens on every `opencode` start
- [The sharing group](concepts/sharing-group.md) — how you and the agent edit
  the same files
- [ddev integration](concepts/ddev-integration.md) — ddev as the opencode
  user: handover, ports, mkcert, SSH keys

## How-to guides (solve a task)

- [Manage project directories](how-to/manage-projects.md)
- [Allow docker/ddev in a project](how-to/container-tools.md)
- [Use OpenChamber with the kit](how-to/openchamber.md)
- [Switch the container backend](how-to/switch-container-backend.md)
- [Customize the deny list](how-to/customize-deny-list.md)
- [Use dev-owned projects](how-to/dev-owned-projects.md)
- [Harden `.git/config`](how-to/secure-git-config.md)
- [Update the kit and the binary](how-to/update.md)
- [Uninstall](how-to/uninstall.md)

## Reference (look it up)

- [CLI — scripts and flags](reference/cli.md)
- [Files and paths](reference/files.md)
- [Ecosystem compatibility](reference/compatibility.md)
- [Audit log](reference/audit-log.md)
- [Glossary](reference/glossary.md)

## Troubleshooting

- [Troubleshooting](troubleshooting.md) — symptom → cause → fix

## Internal documentation

Everything that is not user documentation lives outside this folder:

- [`agent/`](../agent/README.md) — working rules for coding agents
- `.agents/skills/` — loadable agent procedures
- [`internal/`](../internal/README.md) — maintainer process, design records,
  review evidence
