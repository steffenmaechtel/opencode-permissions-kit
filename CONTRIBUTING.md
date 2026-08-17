# Contributing

Thanks for your interest in the opencode permissions kit. This page explains
how to work on the code. For what the kit does, see the
[README](README.md) and the [documentation index](docs/README.md).

## Workflow

1. Create a feature branch off `master`: `feature/<name>`.
2. Work there until stable.
3. Open a pull request against `master`. CI must be green before merge.
4. Never push directly to `master`: it is the live install source — the
   one-liner streams `files/install.sh` from `master`.

## Tests

```bash
sh tests/test-*.sh     # unit suite — always invoke via sh, never rely on exec bits
make check-version     # VERSION stamp + KIT_BRANCH consistency
make e2e               # Docker-based end-to-end suite (podman-rootless install)
make e2e-rootless      # docker-rootless daemon suite (needs systemd-in-container, skips otherwise)
```

- **Never rely on repository mode bits.** Call test and helper scripts with
  `sh <script>` — checkouts lose the executable bit.
- After changes to `install.sh`, `update.sh`, the wrapper, or backend
  provisioning, **both** e2e suites are part of the definition of done — a
  green `make e2e` alone is not sufficient.
- When adding a new executable under `files/` or a new test script under
  `tests/`, add it to the `chmod +x` list in **both**
  `.github/workflows/test.yml` and `.github/workflows/e2e.yml`.

## Testing a branch on a real machine

CI covers the unit and e2e suites, but some changes deserve a real install.
Stream `install.sh` from any branch — `KIT_BRANCH` makes the installer
self-fetch its sibling files from the same branch:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/<branch>/files/install.sh \
  | sudo env KIT_BRANCH=<branch> bash
```

Example for this branch:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/feature/simplify-script-calls/files/install.sh \
  | sudo env KIT_BRANCH=feature/simplify-script-calls bash
```

(`make check-version` ensures `KIT_BRANCH` stays consistent for `master`.)
Use a throwaway WSL2/dev box — the kit is alpha software.

## Documentation

User-facing documentation lives in `docs/` and is organized by topic type
(concepts, how-to guides, reference — see `docs/README.md`):

- A PR that changes user-facing behavior updates the affected page **in the
  same PR**.
- One page = one topic type, with a first-line purpose statement.
- All shipped content (scripts, docs, messages) is in English.

Design records for larger decisions live in `docs/design/`, security analyses
in `docs/security/` — both are historical records; where wording differs from
the code, the code wins.

## Version

Do not bump `VERSION` unless the maintainer asks for a release.
