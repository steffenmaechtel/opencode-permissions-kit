# The docs-improvement loop — from reflection topics to merged waves

Implementation sessions may end with the `opk-improve-docs` skill —
its contract lives in the skill alone; what it files are single-topic
reflection issues in the feedback repo
`steffenmaechtel/opk-agent-feedback`. That is the PRODUCER side. This
page is the CONSUMER side: how a topic proves that it recurs, gets
promoted, is triaged, batched into waves and closed with every item
dispositioned — nothing rots, nothing lands twice.

Two trackers, one loop. Topics filed before the cutover (the
implementation PR of issue #755) are the v1 corpus: bundled `Docs:`
issues in THIS repository, kept as the retro-labeled archive —
`label:"from-reflection"` stays their query key — and cited by rule
text as bare numbers. Their open tail never passes the gate: it is
commissioned by number (see Triage). A `Docs:` issue arriving here
after the cutover is a straggler from a checkout that still carries the
old skill: transfer it to the feedback repo and close it with a
pointer. From the cutover on, new topics live in the feedback repo
only, and new text cites them by its short name (conventions.md,
"Referencing reflection topics").

## Promotion — recurrence is the gate

Whether a topic is general is measured, not judged: the sorting
decision sat with the person holding the least evidence for it (a
one-off and a pattern read the same from the triage chair), so the
redesign moved it to the sessions that hit the topic (issue #755).

- A topic is PROMOTED at quorum: three distinct sessions — the filer
  plus two independent confirmations — counted by distinct `Session:`
  ids over the issue body and its comments, never by comment count.
  The count is taken at every trigger check and at the monthly sweep; a
  newly promoted issue gets the `promoted` label and a ledger comment
  naming the count. (RM-0211)
- Two overrides, both the maintainer's: an issue filed `prio:high`
  (rare but severe — data loss, security class) is promoted on filing,
  the quorum bypassed; and the maintainer may promote any issue by hand
  or reject one that reached quorum, at any time — the hand-applied
  `promoted` label or the closing comment is the record. (RM-0212)
- `research-candidate` issues are outside the loop's work: they wait
  for the monthly sweep, where the maintainer refiles keepers into this
  repository as research issues (the #715 pattern) and closes the rest.
  (RM-0213)

## When a docs wave runs

A docs wave is a commissioned case like any other — cadence is the
maintainer's
([internal/process/review.md](../internal/process/review.md)). The
agent PROPOSES one when the trigger crosses:

- The trigger counts PROMOTED issues, never open ones: 5+ promoted
  issues pending, or the oldest promoted one predating the last
  release. An unpromoted issue triggers nothing, however many are open
  — volume below quorum is the intake working, not a backlog. (RM-0214)

A proposal is a chat paragraph (issues + proposed wave cut), never a
self-started wave.

## Counting sessions — the trigger check

The check is one `gh issue view` per open reflection issue: the count
is the number of distinct session ids in the body plus the comments.
Run it and read the `#number [labels] sessions=N` lines:

```sh
REPO=steffenmaechtel/opk-agent-feedback
if ! issues=$(gh issue list -R "$REPO" --state open --label from-reflection --limit 300 \
        --json number,labels \
        -q '.[] | select(([.labels[].name] | index("promoted")) | not)
             | "\(.number) \([.labels[].name] | join(","))"'); then
    echo "TRIGGER CHECK FAILED: the issue list could not be read — no count was taken" >&2
elif [ -z "$issues" ]; then
    echo "no unpromoted reflection issue is open"
else
    printf '%s\n' "$issues" | while read -r n labels; do
        body=$(gh issue view -R "$REPO" "$n" --json body,comments \
            -q '[.body] + [.comments[].body] | .[]') ||
            { echo "#$n: FETCH FAILED — not counted" >&2; continue; }
        ids=$(printf '%s\n' "$body" |
            sed -n 's/^[[:space:]]*Session:[[:space:]]*\(ses_[A-Za-z0-9]\+\).*/\1/p' | sort -u)
        printf '#%s [%s] sessions=%s\n' "$n" "$labels" "$(printf '%s\n' "$ids" | grep -c .)"
    done
fi
```

Both failure paths say so instead of printing a result: a list that
cannot be read, an issue that cannot be fetched. The count includes the
filer (the body's own `Session:` line), so 1 means no other session has
hit the topic. A `Model:` line a body or comment may carry beside its
`Session:` line (the session's own model, per the skill's template) is
informational — triage and later metrics read it, the count never does.
Promote what reaches three, and every `prio:high` issue
whatever its count; `research-candidate` issues are not listed — they
never count toward a wave. A promotion is recorded, not just observed:
`gh issue edit -R … --add-label promoted`, plus the ledger comment
naming the count and the session ids.

## Triage — every item gets a disposition class

Promotion is the filter for the feedback repository's topics: triage
runs at wave time, on the commissioned PROMOTED issues only — nothing
below quorum is read, classified or closed before then. The v1 open
tail is the one backlog that never passes the gate: those bundles were
filed in THIS repository before the cutover, carry no `Session:` lines,
and are commissioned by number — the same pass decomposes them. A
promoted issue is one topic, but it may decompose
into items (a rule-text item and a code item for the same mechanism);
the v1 bundles decomposed the same way (#535 alone carried three items
across two rule files). One triage pass decomposes every commissioned
issue into items and classifies each:

| Class   | Meaning |
|---------|---------|
| apply   | prose lands in the named target file |
| code    | a script/test change — rides its own small PR; generated output stays with its code wave |
| dedup   | same fix already open or already in text — lands once, both issues cited |
| extract | not documentation — refiled as its own work order with proper labels (`from-reflection` stays on) |
| covered | existing text already says it — close citing the ref |
| reject  | deliberately not adopted — rationale recorded |
| external | the fix lives outside this repository (a global skill, user-level config) — re-label `external-fix` |

An `external` re-label takes both loop labels off — `promoted` and
`from-reflection` — leaving `external-fix` as the only loop label
(a priority label may remain; nothing in the loop keys on it): the
issue leaves the loop's counting and its listings (the trigger
check filters `from-reflection`, the trigger count `promoted`),
never rides a wave, and the monthly sweep dispositions it under its
anything-else arm — never the reflection stale-close — closing it
citing where the fix landed (a commit or issue in the skills' own
repository, a config change, whatever carries the landing), or
keeping it open with a note while it is worked there.

Triage reads the issue's full TIMELINE, never only the body — a
maintainer comment posted after filing is triage input (class
override or added demand): the 2026-11-18 batch triaged #620 from
its body and missed the overnight item-1 reject plus the issue-detail
demand, both sitting in comments (disclosed in PR #622's amendment).
An extracted work order lands in THIS repository and cites its topic
as `opk-agent-feedback#N`.

The ledger posts as one append-only comment per issue BEFORE waves
open, so the maintainer can veto class assignments cheaply. An issue
closes only when every item has a final disposition (the `Closes`/
`Ref` discipline is the birth-PR rule, review.md — the agent-side
bullet lives in review-concept, "Round typing and tiering"; a feedback
issue is referenced in the cross-repo form, the closure bullet below).

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

The founding backlog — #523, #524, #528, #530, #534, #535 and #538,
joined by #540 and #546 while the loop already ran — was worked in two pilot sessions
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
  wave itself consulted, every new clause is read against the
  sibling text of its whole adjacent unit — every leg of that unit,
  not only the clause's origin line — and an edit to an enumerated
  rule unit reconciles its mirror texts (the meta's Check line
  re-states the enumeration) against the full new enumeration, and
  every count comment about a list the wave grew or shrank is
  re-derived or count-freed: greps find
  drift in what exists; mirrors drift by omission — and every
  factual assertion in the wave's own new prose (provenance, version
  eras, SHAs, counts, per-site shape claims) is verified at its
  primary source AT DRAFT TIME, the claim-audit rule's own demand
  turned on the wave's own diff — counts additionally carry the
  dedicated count legs above: PR #716 wrote the added-prose rule
  and violated it in the same commit; its round a C1 and C6 were
  claim shapes no enumerated leg named, its A4 fell under the
  compression leg, which existed and was not executed on the claim.
  Scope
  models, phrasing, contradictions: two
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
  all caught by review, none by the wave itself, #632, #636, #641;
  pr-00643 round a Q2/Q1: the sweep's own second wave read a new
  clause at phrase depth (its origin line) and missed the adjacent
  unit's opposite answer, and an enumeration edit left the meta's
  Check line legs behind the bullet, #645). The list-adjacency arm
  came from that loop's own next reflection: a wave grew the audit's
  ACTIVE_SECTIONS list and the stale count comment about that list
  sat beside the sweep untouched (#685 a B1, #688).
  (RM-0182)
- The self-application sweep's sibling-read is section-scoped by
  wording; same-mechanism rule texts in OTHER files are the class
  sweep's job (learnings L2), and doc waves owe it tree-wide: grep
  the edited rule's distinctive vocabulary across the whole tree
  with no path filters, and record the grep pattern itself in the
  ledger, never
  only the site list — a filtered grep's silent exclusions are
  invisible in a site list (pr-00640 round a Q2/Q3: the root-run
  rename left the standing-review rule's unit and meta in
  review-concept.md split, and the SHA256SUMS sweep's internal/
  noise filter hid release-handling.md; both caught by review round
  a, fixed in its fix wave, #641). And a multi-word grep that
  returns EMPTY over house-wrapped text is evidence only after the
  single-word re-check (or a wrap-tolerant pattern): house wrapping
  splits phrases across lines, so the empty multi-word result is the
  no-collision FALSE negative — the ledger records BOTH patterns, or
  records the phrase as wrap-split and skips the multi-word form
  deliberately (pr-00668 round a Q2: the coined phrase
  "registration probe" existed line-wrapped in review-concept.md
  while the multi-word grep sat empty and the sweep record claimed
  the re-check, #669). (RM-0183)
- A landed topic's feedback issue closes through the wave, across
  repositories: the birth-PR body names every landed issue in the
  cross-repo form GitHub documents (`Closes
  steffenmaechtel/opk-agent-feedback#N`), and the wave does not rely on
  it — before the merge it posts the disposition comment on the issue
  (class, landing PR), and the next trigger check closes whatever that
  PR left open (`gh issue close -R … --reason completed`). A closing
  keyword across two repositories is platform behavior — observed
  once, and it worked: the cutover PR #769's merge (2026-11-23T23:36:04Z)
  closed its check issue opk-agent-feedback#1 seconds later, by
  the merge itself; the backstop above stays for any merge that does
  not. (RM-0215)

## Hygiene — the monthly sweep

The sweep shares its commission with the monthly metrics snapshot —
the maintainer's, like a wave
([internal/process/review.md](../internal/process/review.md)).
Candidates are every open issue without `promoted` — reflection topics
for the stale-close, `research-candidate` ones for the keep-or-close
decision, anything else for a disposition — with the date of their last
confirming comment, the last one carrying a `Session:` line (the
issue's creation when there is none):

```sh
gh issue list -R steffenmaechtel/opk-agent-feedback --state open --limit 300 \
    --json number,createdAt,comments,labels \
    -q '.[] | select(([.labels[].name] | index("promoted")) | not)
      | ([.comments[] | select(.body | test("(?m)^[[:space:]]*Session:[[:space:]]*ses_[A-Za-z0-9]+"))]
         | last.createdAt) as $last
      | "#\(.number) [\([.labels[].name] | join(","))] filed \(.createdAt) last-session \($last // .createdAt)"' ||
    echo "SWEEP FAILED: the candidate list could not be read" >&2
```

- Stale-close is a recorded disposition, never a silent rot: an
  unpromoted issue without a new confirming session for three months is
  closed as not planned (`gh issue close -R … --reason "not planned"`)
  with a ledger comment carrying its session count and the date of the
  last confirmation. The sweep's summary lists every issue it promoted
  or closed. Promoted issues are never stale-closed — they wait for a
  wave. (RM-0216)

## Metrics — measured, not assumed

Whether the loop helps is measured: the definitions (M1 boot context,
M2 corpus size, M3 review efficiency, M4 recurrence), the honesty
caveats and the cadence live with the snapshots in the feedback repo
(`steffenmaechtel/opk-agent-feedback`, `metrics/README.md`) — process
memory about the intake stays with the intake. The M1/M2 snapshot
script is `scripts/docs-loop-metrics.py` here: it reads this tree and
the local opencode.db and prints the snapshot's tables.

## Closure — and the next cycle

The loop stops by the ordinary stop rule; the closing summary lists
every item of every covered issue with its class and landing place, and
each covered feedback issue carries its disposition comment before the
merge. The session still ends with the `opk-improve-docs` ask — doc
waves are sessions too: a wave whose own rules prove wrong becomes the
next reflection topic, and the loop corrects itself.
