# Review meta-analysis — recurring error classes and learnings

> **Status: CURRENT (analysis run 2026-10-22).** Corpus: every review snapshot
> and resolution under [reviews/](../../reviews/README.md) for the stems
> **0.0.47–0.0.49** (legacy era, cases pr-00156/pr-00160/pr-00171) and the
> PR-keyed cases **pr-00179–pr-00222** (2026-10-10 → 2026-10-22): 49
> snapshots, 15 resolutions, 325 extracted finding rows (302 reported). The
> numbers in this folder are a **point-in-time measurement of that corpus**,
> not a live statistic — re-run the extraction to extend them (recipe at the
> bottom). Enforcement short-form: [learnings.md](../../../agent/learnings.md)
> — the per-wave checklist every agent gets (linked from AGENTS.md; no
> statistics reading required to apply it). Previous run:
> [2026-10-10/](../2026-10-10/) (corpus 0.0.38–0.0.46) — its numbers below
> appear as "previous" where a trend matters. Companion pages:
> [statistics.md](statistics.md) (full tables, as of this run),
> [further-analyses.md](further-analyses.md) (review precision, provenance,
> convergence, the restructure-era class candidates). Finding-level data,
> taxonomy spec and aggregation script: [data/](data/).

## Why this record exists

The review loop produces snapshots and resolutions per case, but nothing
aggregate: *do the same mistakes come back with every new feature?* This run
answers that for the corpus grown since 2026-10-10 and re-grounds the
per-wave checklist in [learnings.md](../../../agent/learnings.md). It is also
the follow-through for issue #175: the learnings pre-pass ("are L1–L7 still
the right classes? anything to add from the restructure wave?") is answered
from this run's numbers, not from memory.

## Headline results (as of 2026-10-22)

1. **`claim-drift` is rank 1 again — and its share doubled.** 89 findings
   (29.5 % of reported; previous run: 77, 13.9 %). Claims still age outside
   diffs; wave reviews still do not see them age. The L3 sharpening from
   #214 (history narratives are claims) landed mid-corpus (2026-10-22).
2. **`sibling-sweep` returned.** 25 findings, 6 MED, 9 of 15 groups —
   after the "→ 0 in 0.0.46" dip that the previous run read as a trend.
   It was not: the class needs the L2 discipline every single wave, and
   twice a *sweep claim itself* proved false (pr-00211 c W1, pr-00222 b W1
   — "sweep misses the site the sweep itself introduced").
3. **Fix-induced findings halved.** 28/302 = 9.3 % (previous: 112/553 =
   20.3 %). The micro-wave-review-per-round discipline (L6, binding since
   0.0.42) is measurable now. Fix-regression as a class: 9 findings, 2 MED.
4. **The corpus's only HIGH is an L5-class recurrence found by a full
   pass.** pr-00211 a F1: the group-baseline recheck gates `[ -L ]` on the
   leaf only — the exact `0.0.39h F2` class L5 inventories. Wave/micro
   passes missed it; the staged 10-subagent release full pass found it.
   `perm-model` proper left MED/HIGH entirely (6 findings, all INFO).
   Full passes remain the only reliable perm-model HIGH source — second
   datapoint after 0.0.42d/e.
5. **`tests-unit` is still hotspot #1** (85 findings; `test-vacuous` 45 +
   `test-gap` 13). The tests remain the least-verified code we ship — L4
   is not done.
6. **The restructure-era class candidates are NOT new classes** (issue
   #175 pre-pass): language violations = 1 finding (pr-00211 a F21,
   German step names — covered by the all-English rule, AGENTS.md ##
   Rules); exec-bit/ratchet gates =
   `wiring-gate` (6, incl. the line-length ratchet RED at a committed
   HEAD, pr-00208 b W1); sabotage-vs-uncommitted-tree = 0 findings (live
   incident; the rule lives in AGENTS.md Testing, no meta numbers needed).
7. **Release-scale reviews converge slowly.** pr-00211 (full scope, 360
   files) needed 7 snapshots, stop rule not met in 6 of them. Feature and
   fix waves close in 1–3 snapshots. The wave-review loop scales; the
   release full pass pays its cost in chain length.

## Recurring classes, with their chains

Chains below cite the corpus's own cross-references (40 backward edges;
`crossref_backward` in [data/stats.json](data/stats.json)). Snapshot IDs
use their era's citation format (legacy `0.0.48b W2`, PR-keyed
`pr-00211 a F1` — see the [reviews README](../../reviews/README.md)).

### `claim-drift` — 89 findings, 7 MED/HIGH, 14 of 15 groups

Rank 1 by count in both runs. New-corpus shapes: sabotage-ledger numbers
that do not match the recorded rows (0.0.48d D2), "swept ×4" claims the
wave's own matrix does not prove (pr-00196 c C10), stale SHAs in stop-rule
sections (pr-00200 b W1), gate lines that do not reproduce (pr-00202 d W1),
`Vorgang` step names breaking the English-only rule (pr-00211 a F21,
ux-shaped but claim-class at heart: the repo promises English).

### `test-vacuous` — 45 findings, 4 MED/HIGH, 12 groups

Rank 2 now (was 6.7 % share, now 14.9 % — partly corpus composition: fan-out
reviews record subagent ghosts and coverage notes as INFO rows). MED shapes:
sabotage pins that discriminate through the wrong mechanism (pr-00198 a W3),
undiscriminated pin operands (pr-00222 b W2), suite aborts before the tally
(pr-00211 b W13, c W5 — the fail-but-green shape L4(b) already names).

### `sibling-sweep` — 25 findings, 6 MED/HIGH, 9 groups

The return of the class the previous run declared collapsed. MED chains:
the V14 trailing-slash pin family one file short (pr-00196 b B1), the
sudoers symlink-gate authority split unswept (pr-00198 a W1), the
ddev-handover "covered" disposition hollow (pr-00199 a W1), sweeps missing
their own file or their own new site (pr-00211 b W3 → c W1, pr-00222 b W1).

### `silent-failure` — 23 findings, 6 MED/HIGH, 8 groups

Still the deepest-MED class after claim-drift/sibling-sweep ties. Chains:
the `mktemp || /dev/null` fallback that made root `rm -f /dev/null`
(0.0.48b W2) → silent-noop scans printing "All green" (pr-00211 a F2,
missing-lib fallbacks) → the live-progress reader that never engages on
KB-scale streams (pr-00221 a W1) and the python3 gate that reports green
over a dead scan list (pr-00221 a W3). The unconditional-success-line shape
recurs in every era (0.0.47 a F1 policy.json overwrite, 0.0.48 a F2).

### L5 neighborhood: `perm-model` 6 (0 MED/HIGH) + `race-toctou` 3 (1 HIGH)

`perm-model` findings are all INFO in this corpus — probes audited benign,
transient mode windows recorded as behavior. The one HIGH is race-toctou:
pr-00211 a F1, leaf-only `[ -L ]` recheck gate (the `0.0.39h F2` parent-
component class), found by the release full pass only. L5's inventory
questions remain the right checklist; the enforcement gap is pass scope,
not rule wording.

### The rest

`ux-output` 19 (0 MED), `test-gap` 13 (2 MED), `process` 11 (0 MED —
snapshot ordering, dangling session-local labels pr-00196 c C4, placeholder
SHAs pr-00222 c W3), `shell-semantics` 7 (1 MED — down from 46/14 MED/HIGH:
the skeleton keeps working), `wiring-gate` 6 (2 MED), `docs-policy` 6
(nonzero again after 25→0: same-PR docs rule needs the same vigilance as
L2), `hardcoded-env` 6, `deploy-shape` 2, `perf` 1 (MED), `other` 31
(mostly INFO hygiene: unregistered temp traps, single-hop readlink,
non-atomic writes — no rule candidate).

## Recipe (re-run)

1. Freeze nothing manually: the corpus is the case folders under
   `internal/reviews/` (INDEX.md lists them). Cut off at a date; this run:
   stems 0.0.47+ and cases pr-00179+.
2. Split into batches (~5–8 snapshots per batch; heavy cases alone),
   spawn parallel extraction agents per
   [data/extraction-spec.md](data/extraction-spec.md) — **stage the fan-out
   at max 5 concurrent agents with backfill** (review-concept.md fan-out
   rule; this run launched 8 at once and lost one seat to a rate limit).
3. Aggregate: `python3 scripts/reviews-meta-aggregate.py
   internal/reviews-meta/<run>/data` → `stats.json`.
4. Compat pin: regenerating the previous run's data must reproduce its
   frozen `stats.json` byte-for-byte (pinned by
   `tests/unit/test-reviews-meta-aggregate.sh`).
5. Update [learnings.md](../../../agent/learnings.md) — the checklist is
   the deliverable, never the run folder alone.
