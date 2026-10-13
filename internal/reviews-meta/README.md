# reviews-meta/ — recurring meta-analysis runs

One frozen folder per analysis run over the review corpus (all snapshots
and resolutions): error-class statistics, recurrence chains, and the
learnings distilled into [agent/learnings.md](../../agent/learnings.md).

- Run identifier = run date (`YYYY-MM-DD`); each run's README names the
  exact corpus cutoff.
- Cadence: the maintainer commissions a run roughly monthly or after
  ~8–10 new review vorgänge (rule: `internal/process/review-concept.md`).
- A new run reuses the extraction recipe from the latest run folder; the
  aggregation tool is `scripts/reviews-meta-aggregate.py`.
- Every run updates `agent/learnings.md` — the checklist lives with the
  agent rules and is never duplicated into a run folder.

| Run | Corpus |
|---|---|
| [2026-10-10/](2026-10-10/) | snapshots + resolutions 0.0.38–0.0.46: 54 snapshots, 9 resolutions, 620 finding rows |
