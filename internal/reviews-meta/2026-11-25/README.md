# Review meta-analysis 2026-11-25 — M3 baseline (review efficiency)

> **Status: CURRENT.** First run of the M3 measure (the feedback repo's
> metrics README): review efficiency over the PR timelines — rounds per
> PR, findings per round, and the repeat-class share. Commissioned as
> wave 1 of the AGENTS.md surface split (issue #768): the baseline must
> exist BEFORE the split, because a rising repeat-class share afterwards
> is the "we moved too much off-surface" signal.

## Corpus

- **Mechanical layer** — every merged PR of the PR-native era
  (#280–#776, 2026-10-26 → 2026-11-24): 217 merged PRs scanned, 475
  open review rounds over 180 PRs. Closing summaries (state `closed` or
  wave `close`) and their case-aggregated markers are excluded, the
  same rule as the 2026-11-07 run.
- **Classification layer** — a seeded sample (seed 768) of 25 rounds
  drawn from the last seven days before the split (2026-11-18 →
  2026-11-24; that window holds 50 PRs, 158 rounds, 1183 raw findings):
  141 raw → 124 extracted findings, the delta being the curation merges
  and drops the round comments themselves record (per-batch
  process_notes in data/b*.json).

## Extraction

Fully scripted and re-runnable (gh + python3, read-only, no repo-tree
writes):

1. `data/extract.py 280` — merged-PR list + per-PR comments via gh;
   parses the multi-line `opk-review` JSON markers.
2. `data/normalize.py` — normalizes the two marker eras (old markers
   carry the curator in a `curated` string, new markers `curator` plus
   a numeric `curated`), drops closing summaries and later duplicate
   markers per (pr, wave) → `data/rounds.jsonl`.
3. `data/sample.py` — the seeded 25-round draw → `data/sample.json`.
4. Parallel extraction agents per `data/spec.md` (batch format of the
   2026-10-22 run) → `data/b1.json` … `data/b5.json`.
5. `python3 scripts/reviews-meta-aggregate.py
   internal/reviews-meta/2026-11-25/data` → `data/stats.json`.

Validation: the mechanical layer reproduces the frozen 2026-11-07
rounds.jsonl for #280–#407 exactly — 132/132 rounds, zero numeric field
diffs.

## Headline numbers (mechanical, whole era)

Rounds/PR: median 2, mean 2.64, max 7 (distribution 1–7). Findings per
round (raw): median 4, mean 6.75, max 68. Era totals: 65 retracted, 439
MED, 33 HIGH.

| Week | PRs | Rounds | Raw findings | Rounds/PR | Findings/Round |
|---|---|---|---|---|---|
| 2026-W44 | 33 | 81 | 436 | 2.45 | 5.38 |
| 2026-W45 | 24 | 68 | 446 | 2.83 | 6.56 |
| 2026-W46 | 53 | 111 | 719 | 2.09 | 6.48 |
| 2026-W47 | 62 | 184 | 1362 | 2.97 | 7.40 |
| 2026-W48 | 8 | 31 | 236 | 3.88 | 7.61 |

W48 is the cutover week and incomplete; W46→W47 is the docs-loop pilot
week (AGENTS.md +8,974 bytes in the same span — the co-movement is the
observation, not a verdict; the same caveat as the M1 reading).

## Repeat-class share (the baseline figure)

**99 of 124 findings (79.8 %; 95 % CI ±7.1 %) match a rule that already
existed when they were reported.** Basis split: pre-existing-rule 85,
explicit cross-reference 14, new-class 25.

Per class (repeat / non-repeat):

| Class | Repeat | Non-repeat |
|---|---|---|
| claim-drift | 34 | 5 |
| test-gap | 13 | 2 |
| test-vacuous | 7 | 7 |
| sibling-sweep | 10 | 1 |
| shell-semantics | 8 | 1 |
| silent-failure | 5 | 2 |
| ux-output | 5 | 0 |
| process | 2 | 5 |
| other | 3 | 2 |
| fix-regression | 3 | 0 |
| perm-model | 3 | 0 |
| docs-policy | 3 | 0 |
| race-toctou | 2 | 0 |
| hardcoded-env | 1 | 0 |

Honesty caveats:

- **Sample, not census** — the 25-round sample (of 158 rounds in the
  window) buys a ±7.1 % confidence interval; a census costs ~10× the
  extraction effort.
- **Rater variance** — per-batch repeat rates: b1 58 %, b2 45 %,
  b3 100 %, b4 98 %, b5 93 %. The five extraction agents calibrated
  "new-class" differently (b1/b2 read recently-codified shapes more
  strictly). Future M3 snapshots MUST reuse data/spec.md verbatim and
  report their per-batch rates; a rater change is a method change, not
  a metric move.
- The classification layer covers the last seven days only — the
  immediate pre-split state, which is what the before/after comparison
  needs. The mechanical layer covers the whole era.
- M3 shows trend, not causality (the metrics README's own caveat):
  the repeat share can move with the change mix, not only with rule
  effectiveness.

## Why no learnings.md update

This run measures review efficiency (M3), not error classes; the class
statistics above are a byproduct of the repeat-class extraction. Same
exemption as the 2026-11-07 staffing run ("Why no learnings.md update").

## Recipe (re-run)

```sh
cd internal/reviews-meta/<new-run>/data
python3 extract.py 280 > rounds-raw.jsonl
python3 normalize.py
python3 sample.py            # new seed per run, recorded in sample.json
# fan-out: extraction agents per spec.md, max 5 concurrent, batch
# files b*.json
python3 ../../../../scripts/reviews-meta-aggregate.py .
```

Then recompute the tables above from stats.json and the repeat fields
(the aggregate script is class-aware but repeat-agnostic).
