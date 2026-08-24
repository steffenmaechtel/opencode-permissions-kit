# Documentation

This page explains what the kit's documentation covers and where to find it.
The docs are written for developers who run opencode on a WSL2/Linux dev box
with ddev — see the [README](../README.md) whether the kit fits your setup.

## Getting started

- [Getting started](getting-started.md) — install the kit, answer the
  installer questions, and verify your first agent session

## Concepts (why it works this way)

- [Security model](concepts/security-model.md) — what the kit guarantees,
  the soft-only trade-off, and the known residual gaps
- [The wrapper](concepts/wrapper.md) — what happens on every `opencode`
  start, and how the bypass guards protect the wrapper
- [The sharing group](concepts/sharing-group.md) — how you and the agent
  edit the same files
- [ddev integration](concepts/ddev-integration.md) — ddev as the opencode
  user: handover, ports, mkcert, and the SSH-key trade-off

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
- [Ecosystem compatibility](reference/compatibility.md) — which tools that
  spawn opencode work with the kit, and how
- [Audit log](reference/audit-log.md)
- [Glossary](reference/glossary.md)

## Troubleshooting

- [Troubleshooting](troubleshooting.md) — symptom → cause → fix

## Design records (internal)

`design/` holds planning and analysis records for CURRENT behavior —
where wording differs from the code, the code wins. Superseded or purely
historical records live in [`_archive/`](_archive/) (same subfolder
structure: `_archive/design/`, `_archive/security/`) — they document how
the kit got here, not how it works today. One exception is living, not
historical: [conventions.md](design/conventions.md) — the binding style
guide for shipped code (prompts, output, language).
