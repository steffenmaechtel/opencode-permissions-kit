# Data — extraction run 2026-10-10

This folder holds the **immutable output of one analysis run** (2026-10-10,
corpus: review snapshots 0.0.38–0.0.46, 2026-09-26 → 2026-10-09). Like the
snapshots in [design/review/](../../review/README.md), run data is never
edited after the fact — a later re-run archives this folder's files under
`data/<YYYY-MM-DD>/` and writes fresh ones (recipe in the
[record README](../README.md#re-running-this-analysis)).

## Contents

| File | Meaning |
|---|---|
| `extraction-spec.md` | The taxonomy (17 error classes with decision rules), the JSON schema, and the extraction instructions every agent batch received |
| `b1.json` … `b9.json` | Finding-level extraction, one file per agent batch: per snapshot (metadata, stop-rule, findings) and per resolution (disposition summary). 620 rows over 54 snapshots |
| `stats.json` | Aggregates produced by `aggregate.py`: totals, severity, class stats, class × version matrix, provenance, areas, reviewer groups, trend, and the 45 backward `crossref_backward` edges |
| `aggregate.py` | The aggregation script (stdlib only). Re-run: `cd docs/design/review-meta-analysis/data && python3 aggregate.py` |

## Provenance

- 9 parallel extraction subagents, one JSON each; 7 batches ran on GLM-5.3,
  2 (b5, b8) on GLM-5.3-Flash after provider rate-limit failures.
- Parallelism rule for re-runs: **at most 5 concurrent GLM-5.3 subagents**;
  larger batches (or rate-limit retries) run on GLM-5.3-Flash. Completed
  batches are never re-run.
- Every agent read only its assigned snapshot files plus the spec; the JSONs
  are their verbatim output (validated as JSON, not hand-corrected).

## Known imperfections (do not "fix" in place — noted here instead)

- Judgment calls are embedded (e.g. the version-parse family is classified
  `silent-failure` throughout for family consistency; acceptance-record rows
  are `other`). Anomalies per batch live in the agents' summaries; the spec's
  decision rules governed the common cases.
- Known duplicate rows where parallel in-review agents found the same defect
  twice (`0.0.42d S1=C1`, `0.0.39d C1=S3`, `0.0.41f C1/S1` dual rating).
- Severity partly inferred (Q-tier rows, ghost/retraction rows without a
  stated severity) — flagged per row as `severity_inferred: true`.
- The 0.0.39 resolution covers snapshots a–p while b1 only carried part of it;
  disposition counts there are whole-chain.

## Re-run checklist

1. Freeze and note the corpus cut (new snapshots since 2026-10-10).
2. Split into batches of ~8–10 files / ≤110 KB; one extraction agent per
   batch, spec verbatim (`extraction-spec.md` — change it only in a new run,
   and say so in the run notes; a changed taxonomy breaks comparability).
3. Aggregate (`python3 aggregate.py` inside this folder), archive the old run
   to `data/<old-date>/`, update the tables in
   [../statistics.md](../statistics.md) and [../README.md](../README.md)
   headers with the new run date, and check the learnings trends
   ([../learnings.md](../learnings.md), "When a rule fails").
