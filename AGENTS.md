# AGENTS

This file gives AI coding agents (and human contributors) the essential rules
for working in this repository. It complements [CONTRIBUTING.md](CONTRIBUTING.md)
(workflow + tests) and the [docs index](docs/README.md).

## What this repo is

The **opencode permissions kit** runs [opencode](https://opencode.ai) as its
own Linux user (`opencode`) against a **rootless container backend**
(docker-rootless or podman-rootless), so the agent is UID-separated from the
developer while ddev keeps working. File permissions are opencode's **soft**
permission layer (`opencode.jsonc`) — there are no OS-level ACL denies. There
is no plugin, no npm package, no release tags: developers stream
`files/install.sh` from `master` (`curl ... | sudo bash`), the script
self-fetches its siblings from the same branch, and everything is deployed to
`/usr/local/lib/opencode-permissions-kit/`.

## Layout

- `files/` — the shipped scripts (`install.sh`, `config.sh`, `update.sh`,
  `status.sh`, `uninstall.sh`) and templates
- `files/opencode-permissions-kit-lib/` — shared helpers (wrapper, ui/log,
  jsonc parser, ddev handover, backend setup, sudoers helpers)
- `tests/` — shell unit tests (`test-*.sh`), Docker e2e suites (`e2e/`),
  UX demos (`ux/`)
- `docs/` — user documentation (concepts / how-to / reference), design
  records (`design/`), security analyses (`security/`)

## Rules

- **Never commit on `master`.** Work on `feature/<name>` branches, merged via
  pull request with green CI. Pushing and PRs are the maintainer's job.
- **All shipped content is English** — scripts, docs, prompts, messages.
- **Follow `docs/design/conventions.md`** for interactive prompts, output
  style, and other shipped-code conventions.
- **Docs change with the code:** a PR that changes user-facing behavior
  updates the affected page under `docs/` in the same PR. One page = one
  topic type; see `docs/README.md` for the structure.
- **Don't rename scripts** in `files/` — the Makefile, tests, docs, and the
  install/update deploy lists (`KIT_FILES`) reference them everywhere.
- **Don't bump `VERSION`** unless the maintainer asks. Release tags (when
  set at all) are the bare version stamp **without a `v` prefix** —
  `0.0.17`, not `v0.0.17` (matches the `VERSION` file; installs stream
  from `master`, the tag is purely informational).
- The security model is deliberately **soft-only** — never re-introduce
  OS-level deny ACLs. Background: `docs/design/ddev-working.md`,
  current model: `docs/concepts/security-model.md`.

## Testing

**At session start, run `sh tests/check-host.sh`.** It verifies the host has
every tool the suite needs (git, make, python3, shellcheck) and prints
install commands for anything missing — ask the user to install rather than
working around a missing tool.

```bash
sh tests/check-host.sh   # host pre-flight (required tools + install hints)
sh tests/test-*.sh       # unit suite — always via sh, never rely on exec bits
make lint                # ShellCheck over the shipped scripts
make check-version       # VERSION + KIT_BRANCH consistency
make e2e                 # e2e (Docker needed)
make e2e-rootless        # docker-rootless e2e (skips without systemd-in-container)
```

Both e2e suites are part of the definition of done for changes to
`install.sh`, `update.sh`, the wrapper, or backend provisioning. New
executable scripts go into the `chmod +x` lists of BOTH CI workflow files.
