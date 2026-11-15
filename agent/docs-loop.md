# The docs-improvement loop — from `Docs:` issues to merged waves

Implementation sessions end with the `opk-improve-docs` skill: a
docs-learning reflection that files `Docs:` issues (labels `prio:med` +
`internal workflow/tests`), one per session, each item evidence-cited.
That is the PRODUCER side. This page is the CONSUMER side: how the open
`Docs:` backlog is triaged, batched into waves and closed with every
item dispositioned — nothing rots, nothing lands twice. The founding
backlog: #523–#538, filed 2026-11-15 by the first seven reflections.

## When a docs wave runs

A docs wave is a commissioned case like any other — cadence is the
maintainer's
([internal/process/review.md](../internal/process/review.md)). The
agent PROPOSES one when the backlog crosses a threshold: 5+ open
`Docs:` issues, or the oldest open one predates the last release. A
proposal is a chat paragraph (issues + proposed wave cut), never a
self-started wave.

## Triage — every item gets a disposition class

A `Docs:` issue is a bundle of items, not one change (#535 alone spans
three target files). Before the first wave opens, one triage pass
decomposes every open `Docs:` issue into items and classifies each:

| Class   | Meaning |
|---------|---------|
| apply   | prose lands in the named target file |
| code    | a script/test change — rides its own small PR; generated output never rides a prose diff |
| dedup   | same fix already open or already in text — lands once, both issues cited |
| extract | not documentation — refiled as its own work order with proper labels |
| covered | existing text already says it — close citing the ref |
| reject  | deliberately not adopted — rationale recorded |

The ledger posts as one append-only comment per issue BEFORE waves
open, so the maintainer can veto class assignments cheaply. An issue
closes only when every item has a final disposition (the `Closes`/
`Ref` discipline is the birth-PR rule, review.md).

## Batching — the commission names the batch

The commission is the scope authority
([internal/process/review.md](../internal/process/review.md)): it
names the issues and whether they ride one PR or several. The default
proposal for a reflection backlog is the batch PR — most items are
one-to-three sentence sharpenings, so one session works several issues
into one coherent diff:

- items landing in the same file ride the same PR;
- a code item (script plus regenerated output) rides its own small PR;
- deduped items land in exactly one PR, both issues cited;
- docs-only diffs are non-shipped track: autonomous mode default,
  tier by size (review.md).

The founding batch (issues #523–#538, all seven) runs as a PILOT: one
session, and its closing summary records context size, wall time and
rounds per PR — those numbers calibrate the steady-state batch size.
Until calibrated: one session, one batch, at most two PRs.

## What doc waves owe beyond the ordinary loop

- New rule bullets in audit-scope sections carry rule-metas — next
  free id, meta format per the rules-meta design record
  ([internal/records/rules-meta.md](../internal/records/rules-meta.md));
  a NEW conventions section joins the audit's ACTIVE_SECTIONS list.
  (RM-0141)
- The rules-meta suite joins the fast-check rotation while agent/
  rule files are edited — `sh tests/unit/test-rules-meta.sh` runs in
  seconds and reds on misplaced rule refs before the full gate does.
  (RM-0142)
- New text cites its source (issue, PR, round) — referencing, not
  restating
  ([conventions.md](conventions.md)#referencing-not-restating).
  (RM-0143)
- learnings.md additions carry era-marked evidence (out of rule-meta
  scope by design, the record's decision 10). (RM-0144)
- Shipped content is English and stays under 120 columns (the
  AGENTS.md language rule, the line-length ratchet). (RM-0145)

## Closure — and the next cycle

The loop stops by the ordinary stop rule; the closing summary lists
every item of every covered issue with its class and landing place.
The session still ends with the `opk-improve-docs` ask — doc waves are
sessions too: a wave whose own rules prove wrong becomes the next
`Docs:` issue, and the loop corrects itself.
