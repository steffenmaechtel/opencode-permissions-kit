# reviews-meta/ — recurring meta-analysis runs

One frozen folder per analysis run over the review corpus (all snapshots
and resolutions): error-class statistics, recurrence chains, and the
learnings distilled into [agent/learnings.md](../../agent/learnings.md).

- Run identifier = run date (`YYYY-MM-DD`); each run's README names the
  exact corpus cutoff.
- Cadence: the maintainer commissions a run roughly monthly or after
  ~8–10 new review vorgänge (rule: `internal/agent/review-concept.md`).
- A new run reuses the extraction recipe from the latest run folder; the
  aggregation tool is `scripts/reviews-meta-aggregate.py`.
- Every run updates `agent/learnings.md` — the checklist lives with the
  agent rules and is never duplicated into a run folder.

| Run | Corpus |
|---|---|
| [2026-10-10/](2026-10-10/) | snapshots + resolutions 0.0.38–0.0.46: 54 snapshots, 9 resolutions, 620 finding rows |
| [2026-10-22/](2026-10-22/) | 0.0.47–0.0.49 + PR-keyed pr-00179–pr-00222: 49 snapshots, 15 resolutions, 325 rows |
