# Resolution — pr-00224 (issue #197 e2e default flip to 2.x)

Status: open — micro-wave review b committed ([review-b.md](review-b.md),
one INFO finding `b W1`: the L1 sentence below overstates — the
empty-cache FAIL exists but has no pin). Round b dispositions owed;
no fix applied before the maintainer's go (RM-0107).

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

## Addendum (2026-10-23) — learnings refresh 2026-10-22 applied

master picked up the 2026-10-22 meta run (#227: refreshed
agent/learnings.md; merged here as `3a33067`). Re-checked this wave's
output against the sharpened rules — code unchanged, this section is the
tightened evidence:

- **L2 (sweep claim is a claim — `pr-00211 c W1` / `pr-00222 b W2` shape):
  the sweep above reconciled with its own grep, enumerated.**
  `grep -rn 'sort -V | tail\|endpoint unreachable' tests/ files/ scripts/`
  on the post-fix tree yields SEVEN hits:
  `lib.sh:319` (the wave's own 2.x-prefer glob — listed so the record
  reconciles), `:321` (on-lane offline WARNING — on-lane by construction:
  fires only when the 2.x glob hit), `:323` (generic degrade glob — the
  deliberate off-major path), `:325` (the off-major WARNING, the fix),
  `test-e2e-sources.sh:72` (the pin's grep pattern, not a fallback site),
  `run-ddev.sh:88` (ddev fallback — no major contract claimed anywhere,
  not a sibling), `advisories.sh:48` (version comparison, not a
  fallback). 7/7 classified; three of the seven are the wave's own new
  lines — the exact false-sweep shape the new rule names.
  The same grep on master (`d72e620`, the merge target) yields only the
  three pre-fix sites — #226/#227 added no same-shape site.
- **L4 (right-mechanism discrimination — `pr-00198 a W3` shape):** each
  new pin's sabotage failed for the reason the pin exists: glob pin red
  via the vanished `opencode-2.*` text (not an rc fallthrough), warning
  pin via the vanished message, order pin via BOTH its failure branches
  ("missing" and "313 vs 305" — the order comparison itself).
- **L1 (unconditional-success-line shape):** the degrade path prints a
  named WARNING, never a success line; nothing to adjust.
- Full `make test` green on the merged tree (incl. master's new
  test-reviews-meta-aggregate.sh).

This addendum is bookkeeping only (RM-0066) — no review-relevant code
touched; the owed micro-wave review b covers `3956c70` + this record.
