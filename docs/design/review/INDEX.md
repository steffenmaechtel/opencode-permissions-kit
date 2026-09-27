# Review index

Every review restarts its finding IDs at S1/C1, so a bare ID (an `S1` in a
comment, a commit message, a chat log) is ambiguous across reviews. Resolve
it in two steps: take the review stem from the reference — `(0.0.38 S1)`
points at row 0.0.38 below — or, for a bare legacy ID, grep the candidate
snapshots (`grep -n "C13" 2026-09-26-v0.0.38.md`).

Reference rule: [conventions.md](../conventions.md#referencing-review-findings).

| Stem | Snapshot | IDs used | Resolution | Notes |
|---|---|---|---|---|
| 0.0.17 | — (pre-snapshot era) | — | — | findings summarized in `project-history-summary.md`; in-code references use the `review 0.0.x` prose form |
| 0.0.22 | — (pre-snapshot era) | — | — | referenced as `review 0.0.22` (`files/install.sh`, agents-migration scope) |
| 0.0.29 | — (pre-snapshot era) | — | — | referenced as `review 0.0.29` (`management/update.sh`, binary-path fetch guard) |
| 0.0.38 | [2026-09-26-v0.0.38.md](2026-09-26-v0.0.38.md) | S1–S6, C1–C23, D1–D25 | [2026-09-26-v0.0.38-resolution.md](2026-09-26-v0.0.38-resolution.md) | the bare IDs in shipped comments all date from this review's fix commits (C11, C12, C13, C14, C19, C22, C23, S1) — qualified in place as `0.0.38 …` |
| 0.0.39a | [2026-09-27-v0.0.39-a.md](2026-09-27-v0.0.39-a.md) | S1–S9, C1–C9, D1–D25 | — | same-day variant a |
| 0.0.39b | [2026-09-27-v0.0.39-b.md](2026-09-27-v0.0.39-b.md) | S1–S4, C1–C6, D1–D3, Q1–Q3 | — | same-day variant b; independent of -a (overlaps are confirmations) |
