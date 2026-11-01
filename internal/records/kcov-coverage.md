# kcov coverage over the unit suites — spike findings + runner design

> Status: **CURRENT** — line-coverage report over the unit suites
> (`make coverage`): runner rules, measured dead ends, digest-bump
> checklist. Issue #255 stage 0b, 2026-11-01.

`make coverage` (`scripts/coverage.sh`, CI job `coverage` in
`test-unit.yml`) runs every unit suite under kcov and publishes a merged
line-coverage report over `files/` + `scripts/` — the review surface. This
record holds what the spike measured, every dead end (so they are not
re-tried), and the rules the runner encodes.

## Verdict

Adopted. Coverage made "pins discriminate" (#255's goal) measurable and
immediately named real review hotspots: `management/update.sh` 20%,
`management/status.sh` 8%, `sh/ddev-terminal.sh` 51%, `sh/ddev-handover.sh`
82% vs `sh/ui.sh` 95%. The report is a review ARTIFACT — nothing gates on a
percentage (stage 0b explicitly; a ratchet would need its own decision).

## Baseline numbers (2026-11-01, 41/42 suites, host run)

27 reported files, 1870/3551 executed lines = 52.7%. Same tree under the
DEBUG method had reported 11 files / 41.8% — see "method" below for why
that number was an illusion. Numbers are environment-dependent per line:
`log.sh`'s install.conf branch is 100% on a kit-managed host (the file
exists), 93.75% in a container/CI (it does not). CI is the honest baseline.

Post-commit validation of the finished runner (same day, tree of d458095
plus the new pin suite in scope): full pass rc=0, 42 OK + 1 SKIP (#342),
non-empty merged summary — the report includes the runner's own pin
suite like any other.

## What was measured (all on the digest-pinned image, bash 5.2)

1. **Numbers are real and discriminate.** test-log.sh full suite: 93.75%
   (30/32 lines; red = exactly the two install.conf-gated lines). A
   minimal `log hello` driver: 75.0% — red grew by precisely the rotation
   loop and keep chain the driver never reaches. `--merge` unions runs.
2. **No stderr/xtrace pollution.** test-log.sh scenario 4 captures the
   child's combined output and requires it empty — stays green under kcov
   (BASH_XTRACEFD routes the trace to a dedicated fd, not stderr).
3. **The kit is bash-stable.** 41/42 suites pass with `sh` resolved to
   bash (no kcov involved). The one exception is dash-only test semantics,
   not kit code: #342 (prefix assignment before the `.` special builtin in
   the stamp-toggle pin).
4. **PS4-vs-`set -eu` collision.** kcov's default PS4 is
   `kcov@${BASH_SOURCE}@${LINENO}@`; under `set -u` inside a `bash -c`
   block the prompt expansion aborts with "unbound variable" (repro:
   scripts/coverage.sh-era spike, `internal/records/` — 3 blocks in
   tests/unit/test-install-args.sh). Fix: one shield line `PS4="+ "` as
   the block's first line — semantics unchanged, that block simply stops
   being attributed (fine for a report). Any future `bash -c 'set -eu'`
   test block needs the same shield; the failure is loud (suite red), and
   tests/unit/test-coverage.sh pins shields == bash -c blocks.

## Dead ends (do not re-try without new information)

- **`--bash-method=DEBUG`**: the trap helper does `unset BASH_ENV`, so
  child `sh -c` processes are never traced — sourced libs appear, child-
  executed SUTs silently do not (the 11-file illusion). Also: per-run
  cobertura output is empty in this build, and `--merge` emits nothing
  from a single source (identical binary names dedup away).
- **`--bash-handle-sh-invocation`** (LD_PRELOAD execve redirector):
  produces a green run with an EMPTY report, in-container and on-host.
  Upstream calls it "buggy on some systems"; it is buggy here.
- **Running the suites inside the kcov docker image**: the image is not a
  contributor host. 37/42 suites failed on environment alone (no git, no
  setfacl/shfmt/make, root reads through 000-perms, read-only INDEX
  regeneration, worktree `.git` pointing at a host path). Chasing that is
  permanent drift. The runner therefore runs suites ON the host, changing
  exactly one variable (kcov + sh->bash).
- **Versioned image tag `kcov/kcov:v42`**: Debian 11 base, apt pools
  archived — cannot even `apt-get install git`. That pins us to
  `latest@sha256:<digest>`; the digest is the pin (exact, like SHFMT_VERSION).
- **Absolute suite argv**: a green run with an empty report (kcov's bash
  engine traces only relative-path scripts; likely path normalization vs
  BASH_SOURCE). The runner always passes `tests/unit/...` from the repo
  root.

## Runner rules (encoded in scripts/coverage.sh)

- Suites run unmodified, one kcov process each; merge afterwards; ≥2
  suites required for the merge (single-suite filter: the per-run report
  IS the merged one; a companion-suite workaround for the merge bug was
  removed when PS4 per-run cobertura proved sufficient).
- A PATH shim resolves `sh` to bash (quoted-heredoc wrapper — a
  double-quoted printf variant once let the outer shell expand `"$@"`
  away, breaking every shimmed child).
- kcov is extracted ONCE from the digest-pinned image via
  `docker create` + `docker cp` into `~/.cache/opk-kcov/` — no sudo, no
  host installs. Fail loud if docker or the binary probe is missing.
- Exclusions need an open issue each; today exactly one (#342).
- Report surface: `--include-pattern=<repo>/files/,<repo>/scripts/`.
- Fail-loud: suite failures under the run redden the runner; an empty
  report (trace never attached) reddens the summary; percentages never do.

## Attribution limits (inherent, documented)

kcov attributes by executed file path. Scratch-tree copies the suites
make (test-kit-cli's opk copy) and eval'd block extractions cannot be
mapped back to the source tree — that part of the surface is covered by
the e2e suites, not by this report. Shebang-exec'd repo scripts ARE
covered wherever a suite runs them via `sh <path>` (uninstall.sh 58%,
ddev-as-opencode wrapper 83% in the baseline run).

## Bumping the pinned digest

Pull the newer `kcov/kcov` image, re-run `make coverage` end to end,
check: (a) the PS4 collision still shields (test-install-args green),
(b) the merge still emits from ≥2 sources, (c) test-log.sh reports
log.sh with line counts in the low 30s, (d) single-suite and full runs
both produce non-empty summaries. Then pin the new digest in
scripts/coverage.sh (KCOV_IMAGE) and update the baseline numbers above.
