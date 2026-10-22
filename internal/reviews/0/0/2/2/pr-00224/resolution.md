# Resolution — pr-00224 (issue #197 e2e default flip to 2.x)

Status: open — round a dispositions complete; micro-wave review b owed
(the fixes touched review-relevant code: tests/e2e/lib.sh +
tests/unit/test-e2e-sources.sh, RM-0067).

Chain: [review-a.md](review-a.md) → this wave. Dispositions refer to
`a W<n>` = finding W<n> of snapshot a. Commits on `feature/e2e-default-2x`
(birth PR #224).

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (LOW) | **implemented** | `3956c70` | fallback prefers cached 2.x; off-major named; 3 pins, sabotage-verified |
| a W2 (LOW) | **deliberately not done** | — | GitHub-side config, no in-repo consumer; merge checklist (Follow-ups) |
| a W3 (INFO) | **implemented** | `3956c70` | pin label names the api.github.com-calling steps + backstop note |
| a W4 (INFO) | **implemented** | `3956c70` | header names the behavioral probes next to the structural greps |
| a W5 (INFO) | **deliberately not done** | — | display-only summary label; the run stays unpinned by design |
| a W6 (INFO) | **implemented** | `3956c70` | order pin (assignment < resolve line); reorder sabotage reds |
| a W7 (INFO) | **deliberately not done** | — | suffixed npm packages unverified upstream; loud fail; watch item |

## Evidence detail

### a W1 (LOW) — offline fallback vs the lane's major

Mechanism: the fallback now globs `opencode-2.*` first (newest cached 2.x —
on-lane repeat runs offline); only a cache without any 2.x falls through to
the generic `opencode-*` glob, and that path prints a NAMED off-major
warning plus the `E2E_OC_VERSION` escape hatch — the resolve gate cannot
run offline, so the warning is the lane's only voice. Deliberately NOT a
hard fail: offline repeat runs on pre-flip caches keep working
(behavior-compatible with the pre-flip fallback), just loudly. The on-lane
branch keeps the exact `WARNING: version endpoint unreachable - using
cached opencode` string, so the pre-existing pin stays green untouched.

Pins (test-e2e-sources.sh): `OC_CACHE_DIR./opencode-2\.\* 2` (glob),
`no cached 2x, using cached opencode` (warning), `off the default lane's
2.x major` (escape hatch), plus the kept generic-warning pin. Sabotage:
glob → generic reds the glob pin; deleting the warning line reds the
warning pin. Structural pins, consistent with the file's lib.sh treatment
(the block is inline in e2e_resolve_cache, not an extractable function).

Process note (sabotage discipline): the FIRST sabotage ran pre-commit and
its `git restore` wiped the uncommitted fix — the exact AGENTS.md lesson;
fix re-applied and committed (`3956c70`), all subsequent sabotages ran on
the committed tree. Disclosed here for the b-review.

### a W6 (INFO) — pin ordering

`grep -n` line comparison: the first `OC_VERSION="$E2E_OC_VERSION"` line
must sit before the first `npm_dist_latest` call line. Sabotaged both ways
on the committed tree: assignment deleted → "pin line: missing"; assignment
moved below the resolve (313 vs 305) → "order violated". Both red,
restored green.

### a W3 / a W4 (INFO) — label accuracy

W3: the token pin's label now says "api.github.com-calling steps" with a
comment naming the -1x lanes + both ddev jobs; the per-job auth contract
itself lives in test-workflows.sh's lane pins (Bearer-header pattern per
1x job block). W4: the file header names the behavioral fake-curl probes
next to the structural greps.

### Class sweeps (L2)

- W1 shape — `grep -rn 'sort -V | tail\|endpoint unreachable' tests/ files/`:
  lib.sh OC fallback (fixed here); `run-ddev.sh:88` ddev fallback — no
  lane-major contract exists or is claimed for ddev versions (any cached
  ddev satisfies, no gate), not a sibling; `advisories.sh:48` is a version
  comparison, not a fallback. No further sites.

### L1–L7 walkthrough (this wave)

- L1: the off-major path is a deliberate warn-not-fail (offline compat
  kept); the warning's presence is pinned; the hard-fail path (empty cache)
  keeps its FAIL and its pin.
- L2: sweep above, recorded.
- L3: wave-touched claims re-audited — the lib.sh resolution comment, the
  record's fallback sentence, and the test header now match the code (all
  three updated in `3956c70`).
- L4: new pins sit mid-file, before the summary gate; every new pin
  sabotage-verified (glob, warning, presence, ordering).
- L5: no root operands touched.
- L6: fixes bring their own pins; micro-wave review b owed — reported,
  not self-advanced (RM-0107).
- L7: no new scripts; house form kept.

## Follow-ups

1. **a W2 (merge-time, maintainer):** update branch protection — require
   `e2e-1x` / `e2e-rootless-1x` / `e2e-ddev-1x`, drop the `-2x` names.
2. **a W7 (watch):** the first local default-lane run on a baseline/musl
   host answers whether suffixed `@opencode/cli-<target>` packages exist
   (loud failure if not; nothing to do until then).
3. **Birth-PR wave e2e debt (RM-0113):** the PR wave changed install.sh
   (bootstrap URL → v2 installer, root-run) and lib.sh resolution
   semantics — the PR's own CI runs the flipped lanes on the PR and the
   merge run re-verifies on master; an explicit discharge record (tree
   SHA + counts) may be noted here by a later session.
