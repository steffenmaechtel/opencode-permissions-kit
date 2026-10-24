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

### Clean rule-ID search (VS Code)

Frozen review evidence quotes RM keys verbatim, so a raw full-text
search for a key hits dozens of snapshot lines. To search only the
genuine sites, create a **local, uncommitted** `.vscode/settings.json`
in the repo root (`.vscode/` is gitignored):

```jsonc
{
    // Search-only excludes; Explorer and Quick Open stay unaffected.
    "search.exclude": {
        "**/internal/reviews": true,
        "**/internal/reviews-meta": true,
        "**/internal/records/_archive": true
    }
}
```

An active rule then reports four matches in three files — rule unit,
meta file, INDEX row; the row names the key twice (link label and
link target), so the count is matches, not sites. Escape hatch per
search: toggle "Use Exclude Settings and Ignore Files" in the search
panel's "files to exclude" field. VS Code loads the file only when
the repo folder is the opened workspace; if you open a parent folder,
put the same file in that folder's `.vscode/` — the `**/`-prefixed
patterns match either way.

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
- The e2e suites **should run in parallel** on one Docker host whenever
  the cache precondition below holds — sequential runs cost the other
  suite's full runtime for no benefit: their
  scaffolding is disjoint (per-suite container names and images,
  `mktemp -d` project fixtures, no published host ports, no docker-wide
  cleanup — each suite removes only its own container). One
  precondition: the suites resolve the opencode version at runtime
  (current latest unless `E2E_OC_VERSION` pins it), so a warm shared
  binary cache (`tests/e2e/cache/`) only covers the version the last
  run used — after any time gap, or on a first run, run one suite
  alone first and confirm it resolved and cached its version; parallel
  runs are safe from there.
  Each suite gets slower under the CPU contention of a parallel run;
  `e2e-ddev` is the heavyweight (golden image + inner rootless daemon).
  Define `TS` before the first `&` — in `A && B & C`, C runs before the
  backgrounded assignments take effect. The same precedence swallows a
  leading `cd … &&`: it joins the backgrounded chain too, so the
  foreground shell keeps the old cwd (and its variables) — relative log
  paths like `../logs/…` then resolve against the wrong directory and
  the redirect fails before the suite even starts. Run `cd` as its own
  statement first, never `cd … && make e2e … &`:

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
- Besides PRs and `master` pushes, CI runs a **daily scheduled** burn-in
  on `master` (05:07–05:27 UTC staggered; issue #78 ran it weekly until
  2026-10-23): the e2e suites install the *latest* opencode/ddev
  releases at runtime, so the schedule catches environment drift on a
  "green" master even when nothing was pushed. Scheduled runs use their
  own concurrency group — they never cancel push/PR runs, and a red
  scheduled run blocks the next release by design.
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
Use a throwaway WSL2/dev box for branch testing — this runs unreleased
development code, not the released `stable` channel (see the README
status note).

## Maintainer process

Releases, full project reviews, and the external review machines are
maintainer-only — their runbooks live in
[`internal/process/`](internal/process/): release handling with the
cheat sheet in
[release-handling.md](internal/process/release-handling.md), triggers,
gates and the external redundancy pass in
[review.md](internal/process/review.md). This page stays focused on what
a contributor needs (issue #236).

## Documentation

User-facing documentation lives in `docs/` and is organized by topic type
(concepts, how-to guides, reference — see `docs/README.md`):

- A PR that changes user-facing behavior updates the affected page **in the
  same PR**.
- One page = one topic type, with a first-line purpose statement.
- All shipped content (scripts, docs, messages) is in English.

Design records for larger decisions live in `internal/records/`, historical
security analyses in `internal/records/_archive/security/` — both are historical
records; where wording differs from the code, the code wins.

## Version

Do not bump `VERSION` unless the maintainer asks for a release.
