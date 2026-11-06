# reviews-meta/ — recurring meta-analysis runs

One frozen folder per analysis run over the review corpus (all snapshots
and resolutions): error-class statistics, recurrence chains — and, from
the 2026-11-07 run, subagent staffing economics (reviewer/curator/
verifier cost and sizing-gate calibration) — the learnings distilled
into [agent/learnings.md](../../agent/learnings.md).

- Run identifier = run date (`YYYY-MM-DD`); each run's README names the
  exact corpus cutoff.
- Cadence: the maintainer commissions a run roughly monthly or after
  ~8–10 new review vorgänge (rule: `agent/review-concept.md`).
- A new run reuses the extraction recipe from the latest run folder;
  the aggregation tool for error-class runs is
  `scripts/reviews-meta-aggregate.py` (the 2026-11-07 staffing run
  carries its own `data/extract.py` instead).
- Every run updates `agent/learnings.md` — the checklist lives with the
  agent rules and is never duplicated into a run folder. (A run whose
  measurement is NOT an error class states that explicitly in its
  README instead — see 2026-11-07.)

| Run | Corpus |
|---|---|
| [2026-10-10/](2026-10-10/) | snapshots + resolutions 0.0.38–0.0.46: 54 snapshots, 9 resolutions, 620 finding rows |
| [2026-10-22/](2026-10-22/) | 0.0.47–0.0.49 + PR-keyed pr-00179–pr-00222: 49 snapshots, 15 resolutions, 325 rows |
| [2026-11-07/](2026-11-07/) | PR-native era #280–#407: 52 PRs, 132 rounds, 339 subagent sessions — staffing economics |
