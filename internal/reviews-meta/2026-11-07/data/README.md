# Data — 2026-11-07 staffing run

Frozen extraction outputs plus the recipe script. Regenerate with
`python3 extract.py [corpus-start-date]` (gh + sqlite, read-only) —
this run validated the script by byte-identical reproduction of
`rounds.jsonl` and `subagents.jsonl` (2026-11-07).

| File | Rows | Content |
|---|---|---|
| `rounds.jsonl` | 132 | one round per row (parts deduped, closings excluded): staffing, shape, tier/track/mode |
| `subagents.jsonl` | 339 | one subagent session per row: role (title-classified), model, tier, minutes, tokens |
| `markers-parsed.jsonl` | 171 | raw markers as parsed (incl. the pr-287 hand-fix, `_handfixed`) |
| `marker-comments.jsonl` | — | not frozen (raw gh dump; re-fetch via `extract.py`) |
| `extract.py` | — | full recipe; gotchas inline (verif-before-digest order, part dedup, closing exclusion) |

Role classification, era definitions and the gate simulation live in
[../statistics.md](../statistics.md); the commission, headline
results and the applied RM-0127 recalibration in
[../README.md](../README.md).
