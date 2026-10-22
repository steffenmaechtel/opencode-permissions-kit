<!-- review-meta
ID: pr-00222
Snapshot: c
Subject: micro-wave review of the b-wave fixes (54f2ce6, b W1-b W6)
Scope: wave
Base: feature/rules-meta-phase-4 @ bc893fa
Diff: bc893fa..54f2ce6
Date: 2026-10-22
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 1x GLM-5.3-Flash reviewer subagent (tests axis; single-agent micro pass per RM-0087)
-->

# Micro-wave review — pr-00222 snapshot c — b-wave fixes 54f2ce6

> Resolution: [resolution.md](resolution.md)

Scope: the b-wave fix commit 54f2ce6 (tests/unit/test-rules-revisit.sh +
resolution.md; no shipped script changed). The reviewer subagent ran
fresh-context; the main agent verified every finding. The fixes neither
break nor lie: all four pins (V13 rebuilt, V18, V19, V20) execute their
die arms with verbatim needles, fixtures derive correctly, cp+cmp -s
compares the corrupt state in the right direction, and the sabotage
claims were reproduced (guard → `c1 != 1` only: suite red at V13+V18
only, V18's output showing the exact silent normalization it exists
for). Suites 39/21, lint, sandbox, line-length green.

## Findings index

| ID | Sev | Location | One-line summary | Axis | Verified |
|---|---|---|---|---|---|
| c W1 | LOW | resolution.md:40-43 (a W1 evidence) | a W1 prose still describes V12's untouched check as "`$(cat)` comparison — content, not line counts" — the very mechanism the b-wave (b W5) replaced with cp+cmp; the a-wave paragraph was not swept when the mechanism changed (class-sweep miss inside the resolution) | C1 | yes (grep :42) |
| c W2 | INFO | resolution.md sweep table vs rules-revisit.sh:97/:98 | The table has no rows for the retired-refuse (:97) and bad-status die (:98) arms — both dispositioned only in the a W4 prose (V7/V17/V20); a table-only audit counts 17 of 19 revisit arms, so "19/19 dispositioned" (54f2ce6 message) holds only counting prose | C3 | yes (table read, 0 rows) |
| c W3 | INFO | resolution.md b-wave rows in 54f2ce6 | The six b-wave rows carried literal `SHA_b` placeholders in the audited commit (same-commit self-reference is impossible); follow-up b4a1ccf resolves them — house pattern, resolved at HEAD | C2 | yes (b4a1ccf diff) |
| c W4 | INFO | test-rules-revisit.sh:18-19 vs V17 | Header "bad or missing status … with the meta untouched": V17 (paused) carries no untouched assert of its own — the shared :98 die arm is cmp-asserted via V20 only; arm-level coverage real, per-shape asymmetric | C4 | yes (code read) |

Severity counts: **0 HIGH, 0 MED, 1 LOW, 3 INFO** (4 findings).
Provenance: c W1 fix-induced (b W5's output), c W2/c W3 wave-introduced,
c W4 wave-introduced.

## Key findings detail

### c W1 (LOW) — stale mechanism prose in the a W1 evidence

The resolution's a W1 block still explains V12's untouched check with
the `$(cat)` mechanism b W5 deleted. The resolution is the ledger the
next review starts from — the paragraph now describes a mechanism that
no longer exists. Fix: one sentence update in the a W1 evidence
(bookkeeping; the b-wave section already documents cp+cmp correctly).

### c W2–c W4 (INFO)

c W2: adding two table rows (:97 retired → V7 existing, :98 bad status →
V17/V20) makes the table self-contained and the "19/19" claim
table-checkable. c W3: process note, no action. c W4: candidate
disposition "deliberately not done" — the :98 die precedes any write and
V20 cmp-asserts untouched on the same arm; adding a V17 assert would
touch test code and extend the loop for an asymmetric belt-and-braces.

## Claim audit

Holds: every 54f2ce6 claim (V19/:132, V13 isolation, V18 c2=2 + the
c1-only sabotage red at V13+V18 — reproduced by the subagent in a tree
copy, V20 + empty-status discrimination verified by main-agent sabotage,
cp+cmp byte-exactness, re-anchoring all six anchors, 39/21 counts,
b W4 substance-closure). Does not hold: nothing in the commit's own
claims; c W1 is collateral staleness in pre-existing prose.

## Retracted/ghost findings

None (subagent checked and cleared: sed `p` duplication semantics,
needle collisions across arms, .before copy-order, meta_path drift,
c2=3 over-count, V19 early-die ordering).

## Run provenance

- Reviewer subagent: 1× GLM-5.3-Flash, fresh context, checkpoint file
  /tmp/opencode/review-222/c-T.checkpoint (launch/return timestamps);
  suites 39/21, sandbox, line-length green; sabotage (c1-only guard) in a
  git-archive copy under /tmp, tree untouched.
- Main agent (GLM-5.3): verified c W1 (grep), c W2 (table read), c W4
  (code read); ran sabotages (a) c1-only guard → V13+V18 red, (b)
  empty-status special-case → V20 only, (c) :132 die deleted → V19 red,
  before the b-wave commit.
- Gates at HEAD b4a1ccf, clean tree: revisit 39, meta 21, lint,
  sandbox, line-length green.

## Recommendation

**Proceed — bookkeeping-only disposition round closes the chain.**
c W1 (one sentence) and c W2 (two table rows) are resolution edits;
c W3 needs nothing; c W4 suggested as deliberately not done. No
production or test code change → per the stop rule (RM-0066) the loop
closes with that round.
