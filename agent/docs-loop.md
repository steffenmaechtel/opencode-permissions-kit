# The docs-improvement loop — from `Docs:` issues to merged waves

Implementation sessions may end with the `opk-improve-docs` skill —
its contract lives in the skill alone; what lands on the tracker is
`Docs:` reflection issues carrying the `from-reflection` label. That
is the PRODUCER side. This page is the CONSUMER side: how the open
`Docs:` backlog is triaged, batched into waves and closed with every
item dispositioned — nothing rots, nothing lands twice. The label is
the corpus's query key: `label:"from-reflection"` finds every issue
born of a reflection — the `Docs:` issues plus the work orders refiled
out of their triage (class extract; the first three were #541–#543),
the whole population retro-labeled 2026-11-16 when the label was
introduced. The `Docs:` title prefix stays the docs-class
discriminator inside that query. The founding backlog: the seven
issues #523, #524, #528, #530, #534, #535, #538, filed 2026-11-15 by
the first seven reflections.

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
| extract | not documentation — refiled as its own work order with proper labels (`from-reflection` stays on) |
| covered | existing text already says it — close citing the ref |
| reject  | deliberately not adopted — rationale recorded |

Triage reads the issue's full TIMELINE, never only the body — a
maintainer comment posted after filing is triage input (class
override or added demand): the 2026-11-18 batch triaged #620 from
its body and missed the overnight item-1 reject plus the issue-detail
demand, both sitting in comments (disclosed in PR #622's amendment).

The ledger posts as one append-only comment per issue BEFORE waves
open, so the maintainer can veto class assignments cheaply. An issue
closes only when every item has a final disposition (the `Closes`/
`Ref` discipline is the birth-PR rule, review.md — the agent-side
bullet lives in review-concept, "Round typing and tiering").

## Batching — the commission names the batch, or the wave infers and discloses

The commission is the scope authority
([internal/process/review.md](../internal/process/review.md)): it
names the issues and whether they ride one PR or several. A commission
that names the issues but not the cut still authorizes the loop: the
session takes the default collection-PR cut and names the inference
in the ledger's Commission line as a disclosed default — the veto
points are the ledger comment and the PR review (#627 item 2). The
default
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
  and the regenerated INDEX.md rides the same wave; a meta crossing a
  bucket boundary (the ref's first three ID digits change, 017x →
  018x) creates its new bucket directory — the audit resolves every
  ref by those digits, and a meta copied from its id-neighbors into
  the old bucket reddens with a no-meta-at path (#623 item 2, one
  gate cycle). (RM-0141)
- Run the rules-meta suite while editing agent/ rule files —
  `sh tests/unit/test-rules-meta.sh` completes in seconds and reds
  on misplaced rule refs before the full gate does. (RM-0142)
- New text cites its source (issue, PR, round) — referencing, not
  restating
  ([conventions.md](conventions.md#referencing-not-restating)).
  (RM-0143)
- A wave codifying a reflection issue's mechanism claims re-probes
  them in scratch before writing them into rule text — the issue is
  evidence, not verified truth: #578 §3's `sh -n` narrative was
  codified unprobed, and the pr-00586 round-a probes showed it
  conditional (the balanced apostrophe pair is the silent no-op) —
  the verification duty's probe-before-verdict discipline, applied on
  the rule-writing side. (RM-0167)
- learnings.md additions carry era-marked evidence (out of rule-meta
  scope by design, the record's decision 10). (RM-0144)
- Shipped content is English and never grows past 120 columns (the
  AGENTS.md language rule, the line-length ratchet). (RM-0145)
- The wave's own new prose is subject to the wave's own new rules:
  before the gate, a self-application sweep — every pointer name the
  new text coins greps in its target, every new name is
  collision-checked against the target file's existing headings and
  leads, every count is reconciled with the cited source's full
  body, every incident compression is re-read against the record the
  wave itself consulted, and every new clause is read against the
  sibling text of the
  section it lands in — scope models, phrasing, contradictions: two
  half-true descriptions of one mechanism give a reader opposite
  answers (pr-00629 round a A1–A3: a grep-dead pointer written into the
  citation rule's own item, a name collision in the very file being
  edited, a count its cited source contradicts; pr-00634 round a A1:
  the same wave's amended check-3 bullet in conventions.md carried
  two opposite scope models unreconciled — the fresh sweep's
  enumeration covered names, pointers and counts, not phrase-level
  consistency, so it could not catch its own wave's sibling edit;
  pr-00640 round a Q1: the pr-00634 A1 evidence had been verified at
  its ref and still drifted in the compression — naming the sweep's
  own fresh bullet instead of the wave's amended check-3 bullet —
  all caught by review, none by the wave itself, #632, #636, #641).
  (RM-0182)
- The self-application sweep is section-scoped by wording;
  same-mechanism rule texts in OTHER files are the class sweep's job
  (learnings L2), and doc waves owe it tree-wide: grep the edited
  rule's distinctive vocabulary across the whole tree with no path
  filters, and record the grep pattern itself in the ledger, never
  only the site list — a filtered grep's silent exclusions are
  invisible in a site list (pr-00640 round a Q2/Q3: the root-run
  rename left the standing-review rule's unit and meta in
  review-concept.md split, and the SHA256SUMS sweep's internal/
  noise filter hid release-handling.md; both caught by review round
  a, fixed in its fix wave, #641). (RM-0183)

## Closure — and the next cycle

The loop stops by the ordinary stop rule; the closing summary lists
every item of every covered issue with its class and landing place.
The session still ends with the `opk-improve-docs` ask — doc waves are
sessions too: a wave whose own rules prove wrong becomes the next
`Docs:` issue, and the loop corrects itself.
