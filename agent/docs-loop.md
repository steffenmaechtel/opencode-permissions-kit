# The docs-improvement loop — from `Docs:` issues to merged waves

Implementation sessions may end with the `opk-improve-docs` skill —
its contract lives in the skill alone; what lands on the tracker is
`Docs:` reflection issues. That is the PRODUCER side. This page is
the CONSUMER side: how the open `Docs:` backlog is triaged, batched
into waves and closed with every item dispositioned — nothing rots,
nothing lands twice. The founding backlog: the seven issues #523,
#524, #528, #530, #534, #535, #538, filed 2026-11-15 by the first
seven reflections.

## When a docs wave runs

A docs wave is a commissioned case like any other — cadence is the
maintainer's
([internal/process/review.md](../internal/process/review.md)). The
agent PROPOSES one when the backlog crosses a threshold: 5+ open
`Docs:` issues, or the oldest open one predates the last release. A
proposal is a chat paragraph (issues + proposed wave cut), never a
self-started wave.

## Triage — every item gets a disposition class

A `Docs:` issue is a bundle of items, not one change (#535 alone
carries three items across two rule files). Before the first wave opens,
one triage pass decomposes every open `Docs:` issue into items and
classifies each:

| Class   | Meaning |
|---------|---------|
| apply   | prose lands in the named target file |
| code    | a script/test change — rides its own small PR; generated output stays with its code wave |
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

The founding backlog — the seven issues above, joined by #540 and
#546 while the loop already ran — was worked in two pilot sessions
(2026-11-15, PRs #544, #545, #547 and #548): four and five issues,
two PRs each, loop wall times 27+8 and ~45+~7 minutes, triage gated
before the waves. Calibrated: the review loop dominates wall time,
not issue count — one session takes 4–5 issues as a batch, at most
two PRs (a code item rides its own small one). Each pilot session
ran its PRs' loops in-session — stacked single-case commissions, not
review.md's batch shape (a batch commission splits review into fresh
sessions, one per PR).

## What doc waves owe beyond the ordinary loop

- New rule bullets in audit-scope sections carry rule-metas — next
  free id, meta format per the rules-meta design record
  ([internal/records/rules-meta.md](../internal/records/rules-meta.md));
  a NEW conventions section joins the audit's ACTIVE_SECTIONS list,
  and the regenerated INDEX.md rides the same wave. (RM-0141)
- Run the rules-meta suite while editing agent/ rule files —
  `sh tests/unit/test-rules-meta.sh` completes in seconds and reds
  on misplaced rule refs before the full gate does. (RM-0142)
- New text cites its source (issue, PR, round) — referencing, not
  restating
  ([conventions.md](conventions.md#referencing-not-restating)).
  (RM-0143)
- learnings.md additions carry era-marked evidence (out of rule-meta
  scope by design, the record's decision 10). (RM-0144)
- Shipped content is English and never grows past 120 columns (the
  AGENTS.md language rule, the line-length ratchet). (RM-0145)

## Closure — and the next cycle

The loop stops by the ordinary stop rule; the closing summary lists
every item of every covered issue with its class and landing place.
The session still ends with the `opk-improve-docs` ask — doc waves are
sessions too: a wave whose own rules prove wrong becomes the next
`Docs:` issue, and the loop corrects itself.
