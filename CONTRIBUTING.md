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

First make sure your host has everything installed (shellcheck is part of
`make test` via `make lint`):

```bash
sh tests/check-host.sh  # prints install commands for anything missing
```

```bash
sh tests/test-*.sh     # unit suite — always invoke via sh, never rely on exec bits
make check-version     # VERSION stamp + KIT_BRANCH consistency
make e2e               # Docker-based end-to-end suite (podman-rootless install)
make e2e-rootless      # docker-rootless daemon suite (needs systemd-in-container, skips otherwise)
```

- **Call test and helper scripts with `sh <script>`.** Executable bits are
  tracked in git, so a fresh Linux/macOS clone runs `make test` directly —
  but the bits are lost on Windows filesystems, WSL trees on `/mnt/c`, and
  by mode-stripping transfer channels (ZIP downloads, shared folders,
  `cp`/`scp` without `-p`). `sh <script>` works everywhere; the CI
  `chmod +x` lists are the second safety net (kept complete by
  `tests/test-workflows.sh`).
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

An installed kit updates from a branch the same way (stream `update.sh`
instead of re-installing — your `projects.conf` and deny list survive):

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/feature/simplify-script-calls/files/update.sh \
  | sudo env KIT_BRANCH=feature/simplify-script-calls bash
```

Switching back to `master` later is the same call without `KIT_BRANCH`
(see the [update guide](docs/how-to/update.md)).

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

## Project reviews

Full reviews (security, bugs, quality, docs, CI) are **trigger-based**, not
on a calendar. Open a review issue from the `project_review` template when
any of these fires:

- a **version bump** is planned (before the release),
- roughly **500+ changed lines or 10+ merged PRs** have accumulated on
  `master` since the last review, or
- a PR touched a **high blast-radius area** (`sudoers.template`, the
  wrapper, backend provisioning, the security model).

Findings from a review become issues labeled `review` (actionable soon) or
`tech-debt` (deliberately deferred, with a reason). A review starts by
working the backlog, not by re-inventing itself: the checklist lives in
`.github/ISSUE_TEMPLATE/project_review.md` and doubles as the working
instructions for a coding agent doing the review locally.

After each review, try to shrink the next one: every finding that could be
turned into a lint rule, unit test, or consistency guard should be — the
remaining manual surface is what the checklist cannot automate.

## Version

Do not bump `VERSION` unless the maintainer asks for a release.
