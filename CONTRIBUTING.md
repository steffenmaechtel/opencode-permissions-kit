# Contributing

Thanks for your interest in the opencode permissions kit. This page explains
how to work on the code. For what the kit does, see the
[README](README.md) and the [documentation index](docs/README.md).

## Workflow

1. Create a feature branch off `master`: `feature/<name>`.
2. Work there until stable.
3. Open a pull request against `master`. CI must be green before merge.
4. Never push directly to `master`: it is the development head — the
   install one-liner streams `files/install.sh` from the `stable`
   release mirror, which is fast-forwarded to `master` only on release
   (`KIT_CHANNEL` in `install.conf` records what an install tracks).

## Tests

First make sure your host has everything installed (shellcheck is part of
`make test` via `make lint`):

```bash
sh tests/check-host.sh  # prints install commands for anything missing
```

```bash
sh tests/unit/test-*.sh   # unit suite — always invoke via sh, never rely on exec bits
make check-version     # VERSION stamp + KIT_BRANCH consistency
make e2e               # Docker-based end-to-end suite (podman-rootless install)
make e2e-rootless      # docker-rootless daemon suite (needs systemd-in-container, skips otherwise)
```

- **Call test and helper scripts with `sh <script>`.** Executable bits are
  tracked in git, so a fresh Linux/macOS clone runs `make test` directly —
  but the bits are lost on Windows filesystems, WSL trees on `/mnt/c`, and
  by mode-stripping transfer channels (ZIP downloads, shared folders,
  `cp`/`scp` without `-p`). `sh <script>` works everywhere.
- After changes to `install.sh`, `update.sh`, the wrapper, or backend
  provisioning, **both** e2e suites are part of the definition of done — a
  green `make e2e` alone is not sufficient.
- The e2e suites may run **in parallel** on one Docker host: their
  scaffolding is disjoint (per-suite container names and images,
  `mktemp -d` project fixtures, no published host ports, no docker-wide
  cleanup — each suite removes only its own container). One
  precondition: the shared binary cache (`tests/e2e/cache/`) must be
  warm — after an opencode version bump run one suite alone first, or
  two suites download the same version into the same path concurrently.
  Each suite gets slower under the CPU contention of a parallel run;
  `e2e-ddev` is the heavyweight (golden image + inner rootless daemon).
  Define `TS` before the first `&` — in `A && B & C`, C runs before the
  backgrounded assignments take effect:

  ```bash
  TS=$(date +%Y%m%d-%H%M%S); make e2e > /tmp/e2e-$TS.log 2>&1 & P1=$!
  make e2e-rootless > /tmp/e2e-rootless-$TS.log 2>&1 & P2=$!
  wait $P1; R1=$?; wait $P2; R2=$?; echo "e2e=$R1 e2e-rootless=$R2"
  ```

  All three at once — the ddev suite dominates the wall clock, so the
  total barely exceeds a lone `make e2e-ddev`; watch RAM/CPU pressure on
  smaller hosts:

  ```bash
  TS=$(date +%Y%m%d-%H%M%S); make e2e > /tmp/e2e-$TS.log 2>&1 & P1=$!
  make e2e-rootless > /tmp/e2e-rootless-$TS.log 2>&1 & P2=$!
  make e2e-ddev > /tmp/e2e-ddev-$TS.log 2>&1 & P3=$!
  wait $P1; R1=$?; wait $P2; R2=$?; wait $P3; R3=$?
  echo "e2e=$R1 e2e-rootless=$R2 e2e-ddev=$R3"
  ```

- Executable bits live in the **git index** (issue #123): commit anything
  executed by path with `git update-index --chmod=+x <path>` — a new test
  under `tests/unit/`, a new `bin/` command, or a new `scripts/` helper
  is enforced automatically by `tests/unit/test-workflows.sh`
  (755 <=> executed by path, 644 <=> sourced lib / interpreter call /
  data). Workflows carry no `chmod +x` lines; `actions/checkout`
  preserves the tracked modes.
- Besides PRs and `master` pushes, CI runs a **weekly scheduled** burn-in
  on `master` (Mondays ~03:00 UTC, issue #78): the e2e suites install the
  *latest* opencode/ddev releases at runtime, so the schedule catches
  environment drift on a "green" master even when nothing was pushed.
  Scheduled runs use their own concurrency group — they never cancel
  push/PR runs, and a red weekly run blocks the next release by design.
- One gate is **CI-only** on purpose: the `tui/*.tsx` parse gate
  (`tests/tsx-syntax-gate.sh`, issue #114). It needs node + typescript,
  which are not contributor-host requirements, so it never runs in
  `make test`. Its typescript install is supply-chain-hardened: the
  version is pinned exactly in `tests/fixtures/tsx-gate/package.json`
  and installed with `npm ci --ignore-scripts` from the committed
  lockfile — npm verifies the tarball's integrity hash, and package
  lifecycle hooks (pre/postinstall) never execute. (A tripwire package
  such as `@lavamoat/preinstall-always-fail` is only needed when a
  project must run *legitimate* postinstall scripts.) The wiring — run
  step, pin/lockfile sync — is guarded by
  `tests/unit/test-workflows.sh`, so the gate cannot be
  silently dropped or weakened.

## Testing a branch on a real machine

CI covers the unit and e2e suites, but some changes deserve a real install.
Stream `install.sh` from any branch — `KIT_BRANCH` makes the installer
self-fetch its sibling files from the same branch:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/<branch>/files/install.sh \
  | sudo env KIT_BRANCH=<branch> bash
```

Example (replace `<branch>` with your feature branch):

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/<branch>/files/install.sh \
  | sudo env KIT_BRANCH=<branch> bash
```

An installed kit updates from a branch the same way (stream `update.sh`
instead of re-installing — your `projects.conf` and deny list survive):

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/feature/simplify-script-calls/files/opencode-permissions-kit-lib/management/update.sh \
  | sudo env KIT_BRANCH=feature/simplify-script-calls bash
```

Switching back to a channel later is the same call with `stable` (or
`master`) as `KIT_BRANCH` — the switch re-stamps `KIT_CHANNEL` in
`install.conf`, so subsequent plain `opk update` runs stay there (see the
[update guide](docs/how-to/update.md#channels)).

(`make check-version` ensures `KIT_BRANCH` stays consistent for `master`.)
Use a throwaway WSL2/dev box — the kit is alpha software.

## Making a release

Releases are maintainer-only and fully scripted
([`scripts/release.sh`](scripts/release.sh), issue #38; model:
[release-handling](docs/design/release-handling.md) — a release is the
tag `x.y.z` on `master` plus a fast-forward of the `stable` mirror, which
must stay **byte-identical** to `master`).

Cheat sheet — copy the block, search & replace `0.0.36` with the new
version, run the lines one by one. The VERSION bump lands on `master`
**via PR** (never commit on master directly); `make release` then verifies
a clean tree, sync with origin, the VERSION stamp, a free tag and
`stable` fast-forwardability, runs the suite, and tags, mirrors and
pushes (never force-pushes):

```bash
git checkout -b release/0.0.36
make version VERSION=0.0.36
git commit -am "chore: bump VERSION to 0.0.36"
git push origin release/0.0.36

# On GitHub: open the PR for release/0.0.36 => merge => wait for green CI

git checkout master
git pull origin master
make release VERSION=0.0.36
gh release create 0.0.36 --generate-notes
```

`make release VERSION=0.0.36 ARGS=--dry-run` prints the steps without
changing anything.

Everything else (branch protection on `stable`, announcements) is set up
once, not per release.

## Documentation

User-facing documentation lives in `docs/` and is organized by topic type
(concepts, how-to guides, reference — see `docs/README.md`):

- A PR that changes user-facing behavior updates the affected page **in the
  same PR**.
- One page = one topic type, with a first-line purpose statement.
- All shipped content (scripts, docs, messages) is in English.

Design records for larger decisions live in `docs/design/`, historical
security analyses in `docs/_archive/security/` — both are historical
records; where wording differs from the code, the code wins.

## Project reviews

Full reviews (security, bugs, quality, docs, CI) are **trigger-based**, not
on a calendar. Run a review when any of these fires:

- a **version bump** is planned (before the release),
- roughly **500+ changed lines or 10+ merged PRs** have accumulated on
  `master` since the last review, or
- a PR touched a **high blast-radius area** (`sudoers.template`, the
  wrapper, backend provisioning, the security model).

Findings from a review become issues labeled `review` (actionable soon) or
`tech-debt` (deliberately deferred, with a reason). A review starts by
working the backlog, not by re-inventing itself: method, snapshot and
resolution mechanics, and the snapshot-format rule (external verbatim
embedding since 0.0.45d) live in
[docs/design/review/README.md](docs/design/review/README.md).

After each review, try to shrink the next one: every finding that could be
turned into a lint rule, unit test, or consistency guard should be — the
remaining manual surface is what the checklist cannot automate.

Scope and cadence follow the [review concept](docs/design/review-concept.md):
full reviews are this trigger-based gate; the fixes themselves get a
**wave review** (diff scope) before their PR — mandatory when a wave
changes the semantics of root-running scripts — and the review → fix →
review loop stops only when a full pass returns no new MED/HIGH findings.

## Version

Do not bump `VERSION` unless the maintainer asks for a release.
