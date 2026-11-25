# Review meta-analysis 2026-11-25 — M3 baseline (review efficiency)

> **Status: CURRENT.** First run of the M3 measure (the feedback repo's
> metrics README): review efficiency over the PR timelines — rounds per
> PR, findings per round, and the repeat-class share. Commissioned as
> wave 1 of the AGENTS.md surface split (issue #768): the baseline must
> exist BEFORE the split, because a rising repeat-class share afterwards
> is the "we moved too much off-surface" signal.
>
> Corrected 2026-11-25 per PR #780 round a (findings B4/B1/C3):
> closing-summary exclusion, ground-truth PR identity, named validation
> field set. The numbers below are the corrected ones; the pre-fix
> figures live in the round a comment.

## Corpus

- **Mechanical layer** — every merged PR of the PR-native era
  (#280–#776, 2026-10-26 → 2026-11-24): 217 merged PRs scanned, 398
  review rounds over 180 PRs. Closing summaries — dedicated closing
  comments in every era spelling (wave `z`, `closing`, `close`; state
  `closed`) — are excluded (#780 a B4); pilot-era round comments with
  state `closing-proposed` and a round-letter wave stay (their closing
  proposal rode the last round comment, their counts are round-level,
  and the frozen 2026-11-07 run includes them). PR identity is the
  ground-truth PR the comment lives on — a marker's `case` field never
  overrides it (#780 a B1: two markers on PR #563 claimed
  `"case":"pr-00562"`).
- **Classification layer** — a seeded sample (seed 768) of 25 rounds
  drawn from the last seven days before the split (2026-11-18 →
  2026-11-24; that window holds 50 PRs, 110 rounds, 603 raw findings on
  the corrected table — 158 rounds / 1183 raw on the pre-fix table the
  draw rode): 67 stated raw → 68 extracted findings over the 20 review
  rounds, the delta being the curation merges, drops and retracted
  entries the round comments themselves record (per-batch
  process_notes in data/b*.json). The draw's other 5 rows were wave-z
  closing summaries — excluded from the classification basis (their 56
  findings are case-aggregated re-listings, #780 a B4); the artifacts
  stay as the record of what was classified.

## Extraction

Fully scripted and re-runnable (gh + python3, read-only, no repo-tree
writes):

1. `data/extract.py 280` — merged-PR list + per-PR comments via gh;
   parses the multi-line `opk-review` JSON markers.
2. `data/normalize.py` — normalizes the two marker eras (old markers
   carry the curator in a `curated` string, new markers `curator` plus
   a numeric `curated`), drops closing summaries (dedicated closing
   comments: wave `z`/`closing`/`close`, state `closed` — #780 a B4)
   and later duplicate markers per (pr, wave), and keeps ground-truth
   PR identity (#780 a B1) → `data/rounds.jsonl`.
3. `data/sample.py` — the seeded 25-round draw → `data/sample.json`.
4. Parallel extraction agents per `data/spec.md` (batch format of the
   2026-10-22 run) → `data/b1.json` … `data/b5.json`.
5. `python3 scripts/reviews-meta-aggregate.py
   internal/reviews-meta/2026-11-25/data` → `data/stats.json`.

`sample.json`, `b*.json` and `stats.json` are the historical
classification artifacts of the pre-fix draw (5 of the 25 drawn rows
were wave-z closing summaries, #780 a B4): kept as the record of what
was classified, excluded from the share basis below. A re-run of
`sample.py` over the corrected rounds table draws differently — the
next M3 snapshot re-draws and re-classifies (the #781 follow-up's
first step).

Validation: the mechanical layer reproduces the frozen 2026-11-07
rounds.jsonl for #280–#407 on the round-metric fields — 132/132
rounds, zero diffs on raw/high/med/retracted/reviewers. The old-era
`curated` string maps to `curator` with `curated_count: null`: 13 rows
where the frozen run recorded `curated: 0` (#780 a C3 — the compared
field set is named, not implied).

## Headline numbers (mechanical, whole era)

Rounds/PR: median 2, mean 2.21, max 6 (distribution 1–6). Findings per
round (raw): median 3, mean 5.79, max 68. Era totals: 47 retracted, 296
MED, 21 HIGH.

| Week | PRs | Rounds | Raw findings | Rounds/PR | Findings/Round |
|---|---|---|---|---|---|
| 2026-W44 | 33 | 81 | 436 | 2.45 | 5.38 |
| 2026-W45 | 24 | 65 | 397 | 2.71 | 6.11 |
| 2026-W46 | 53 | 100 | 597 | 1.89 | 5.97 |
| 2026-W47 | 62 | 129 | 756 | 2.08 | 5.86 |
| 2026-W48 | 8 | 23 | 118 | 2.88 | 5.13 |

W48 is the cutover week and incomplete; W46→W47 is the docs-loop pilot
week (AGENTS.md +8,974 bytes in the same span — the co-movement is the
observation, not a verdict; the same caveat as the M1 reading).

## Repeat-class share (the baseline figure)

**54 of 68 findings (79.4 %; 95 % CI ±9.6 %) match a rule that already
existed when they were reported.** Basis: the 20 review rounds of the
seeded draw — the 5 wave-z closing-summary snapshots are excluded from
the basis (#780 a B4: their 56 findings are case-aggregated re-listings;
the point estimate moves 79.8 % → 79.4 %, the CI widens ±7.1 % →
±9.6 %). Basis split: pre-existing-rule 43, explicit cross-reference
11, new-class 14.

Per class (repeat / non-repeat):

| Class | Repeat | Non-repeat |
|---|---|---|
| claim-drift | 22 | 3 |
| test-gap | 7 | 1 |
| sibling-sweep | 7 | 1 |
| test-vacuous | 4 | 4 |
| silent-failure | 5 | 1 |
| shell-semantics | 4 | 0 |
| other | 2 | 2 |
| process | 0 | 2 |
| fix-regression | 1 | 0 |
| race-toctou | 1 | 0 |
| hardcoded-env | 1 | 0 |

Honesty caveats:

- **Sample, not census** — the 20-round corrected basis (of 110 rounds
  in the corrected window) buys a ±9.6 % confidence interval; a census
  costs ~10× the extraction effort.
- **Rater variance** — per-batch repeat rates over the corrected
  basis: b1 58 %, b2 75 %, b3 100 %, b4 100 % (n=1 finding), b5 93 %.
  The five extraction agents calibrated "new-class" differently (b1
  read recently-codified shapes more strictly). Future M3 snapshots
  MUST reuse data/spec.md verbatim and report their per-batch rates; a
  rater change is a method change, not a metric move.
- The classification layer covers the last seven days only — the
  immediate pre-split state, which is what the before/after comparison
  needs. The mechanical layer covers the whole era.
- M3 shows trend, not causality (the metrics README's own caveat):
  the repeat share can move with the change mix, not only with rule
  effectiveness.
- The draw rode the pre-fix rounds table (5 closing summaries among
  the 25); the next M3 snapshot re-draws over the corrected table —
  recorded as the #781 follow-up's first step.

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
