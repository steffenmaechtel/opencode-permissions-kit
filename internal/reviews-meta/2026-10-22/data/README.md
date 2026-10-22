# Data — extraction run 2026-10-22

This folder holds the **immutable output of one analysis run** (2026-10-22,
corpus: review snapshots + resolutions for stems 0.0.47–0.0.49 and PR-keyed
cases pr-00179–pr-00222, 2026-10-10 → 2026-10-22). Like the snapshots in
[reviews/](../../../reviews/README.md), run data is never edited after the
fact — the next run gets its own folder under
[reviews-meta/](../../README.md) (recipe in the
[run README](../README.md#recipe-re-run)).

## Contents

- `extraction-spec.md` — the taxonomy (17 error classes with decision
  rules — identical wording to run 2026-10-10), the JSON schema, batch
  assignments, and the PR-era stem/citation conventions.
- `b1.json` … `b8.json` — finding-level extraction, one file per agent
  batch: per snapshot (metadata, stop-rule, findings) and per resolution
  (disposition summary). 325 rows over 49 snapshots.
- `stats.json` — aggregates produced by
  `scripts/reviews-meta-aggregate.py`: totals, severity, class stats,
  class × group matrix (both stem eras), provenance, areas, reviewer
  groups, trend, and the 40 backward `crossref_backward` edges. Compat
  pin: regenerating run 2026-10-10 reproduces its frozen stats.json
  byte-for-byte (`tests/unit/test-reviews-meta-aggregate.sh`).

## Provenance

- 8 parallel extraction subagents, one JSON each (GLM-5.3), 49 snapshots +
  15 resolutions in batches of 4–8 snapshots (the full-scope case pr-00211
  alone in b7).
- The launch staged 8 agents at once; one seat (b8) hit the provider rate
  limit and was retried serially. The fan-out staging rule (max 5
  concurrent, backfill — review-concept.md) was violated by the parent
  agent and is recorded here, not smoothed over. Re-runs: stage at ≤ 5.
- Every agent read only its assigned snapshot files plus the spec; the
  JSONs are their verbatim output (validated as JSON, not hand-corrected).

## Known imperfections (do not "fix" in place — noted here instead)

- Same-case and `#NNN`-shaped references were normalized to
  `pr-NNNNN <letter> <ID>` per the spec; pr-00211 a F2's `#165/#199` were
  read as PR refs (ambiguous from 2026-10 on) — judgment call by b7.
- pr-00211 snapshot a's own provenance split sums to 39 over 37 findings
  (snapshot-internal inconsistency, preserved as extracted).
- Ghost/dissolved subagent findings are kept as `status: retracted` rows
  (23 corpus-wide; pr-00222 a/b carry synthetic IDs G1–G8 where the source
  listed them unlabeled).
- Resolution follow-ups are not uniformly in the
  `follow_ups_recorded` field (two batches put them in `notes`) — count
  follow-ups from the resolution files.
- pr-00171's conditional stop-rule statements were recorded as `not_met`
  with process notes (judgment call by b2).
