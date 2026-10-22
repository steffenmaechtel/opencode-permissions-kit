<!-- review-meta
ID: pr-00222
Snapshot: b
Subject: micro-wave review of the a-wave fixes (7e0e67b, W1-W4)
Scope: wave
Base: feature/rules-meta-phase-4 @ ee23858
Diff: ee23858..7e0e67b (code files only; resolution bookkeeping audited as claims)
Date: 2026-10-22
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 2x GLM-5.3-Flash reviewer subagents (axis S: scripts+claims, axis T: tests)
-->

# Micro-wave review — pr-00222 snapshot b — fix wave 7e0e67b

> Resolution: [resolution.md](resolution.md)

Scope: the a-wave fix commit 7e0e67b only (scripts/rules-revisit.sh,
tests/unit/test-rules-revisit.sh, tests/unit/test-rules-meta.sh; the
resolution created in the same commit audited as claims). Question per
review-concept: did the fixes break or lie? Both reviewer subagents ran
fresh-context; the main agent re-verified every finding (two by sabotage in
a tree copy) and ran the gates. All 12 new pins are real, discriminate
their arm's deletion (sabotage S1/S3/S6 reddened exactly V17/V12/R7), and
the pin-count and consolidation claims hold exactly (36/21 green, no
SCOPE_FILES drift, lane a now mirrors lanes b/c).

## Findings index

| ID | Sev | Location | One-line summary | Axis | Verified |
|---|---|---|---|---|---|
| b W1 | MED | resolution.md sweep table vs scripts/rules-revisit.sh:132 | "Pin every die arm" / "every arm enumerated" misses one arm: the revisit `next-revisit computation failed` die — triggerable (bad FORCE_TODAY / exec-failing RULES_PYTHON), unpinned (report's sibling :63 IS pinned as R6), absent from the L2 table | S+main | yes (probe rc=2 + independent enumeration 18/19) |
| b W2 | LOW | tests/unit/test-rules-revisit.sh:554-566 + resolution.md:37-39 | V13's fixture is derived from V12's file and keeps the duplicated interval (c1=2, c2=0) — the guard's c2 operand is not discriminated: suite stays green with `if (c1 != 1) exit 3`; resolution's "the c2=0 operand direction" holds only as "executes the die". The c2=2 shape (duplicated next-revisit) has no discriminating pin at all | T+main | yes (sabotage: c2-operand dropped → 36 pins green) |
| b W3 | LOW | tests/unit/test-rules-revisit.sh:19-21 | Wave-added header claims corrupt frontmatter "bad/missing status … dies loud with the meta untouched" — the missing-`status:` shape has no fixture (V17 pins `paused` only; behavior probed correct: rc=2 `bad status ''`), and "untouched" is asserted only by V12 | S+T | yes (code read + S probe) |
| b W4 | LOW | commit 7e0e67b message (W1 bullet) | "V12/V13 … assert the meta stays byte-identical" — only V12 carries the `$(cat)` before/after comparison; V13 checks rc + needle (the resolution scopes this correctly) | T+S | yes (code read :545-548 vs :561-566) |
| b W5 | INFO | tests/unit/test-rules-revisit.sh:545-548 | `dbefore=$(cat "$DM")` compares content modulo trailing newlines — "byte-identical" is overstated by exactly the trailing-newline delta; unrealistic in the die path (no mv happens) | main | yes (code read) |
| b W6 | INFO | resolution.md:32, :82-95 | Stale pre-wave line anchors: W1 evidence ":144-151" → :147-154; table rows bad interval :99→:102, review log :131→:134, count guard :151→:154, rewrite checks :154-159→:157-162, mktemp/mv :142/:161→:145/:164 (report rows current) | T+S | yes (grep vs table) |

Severity counts: **0 HIGH, 1 MED, 3 LOW, 2 INFO** (6 findings).
Provenance: b W1–b W5 wave-introduced, b W6 delta-introduced.

## Key findings detail

### b W1 (MED) — one die arm escaped the sweep

Independent enumeration (`grep -n 'die\|refuse'`, both scripts): report
12/12 arms tabled; revisit 18 of 19 — `:132
) || die "next-revisit computation failed for '$TODAY'"` (the python
heredoc's failure arm) is neither tabled nor pinned. Probe:
`FORCE_TODAY=2026-13-99` → rc=2 with that message (a raw python traceback
precedes it — pre-existing shape, same as the report's R6-pinned sibling
:63, which makes this an oversight rather than a judged skip). The
resolution's own stated method (`grep -n 'die\|refuse'`) matches the line,
so the enumeration, not the method, failed. Fix candidate: R6-style pin
(`run_revisit` with bad FORCE_TODAY) plus one table row — then the W3
disposition statement becomes true. Severity MED because "every arm
enumerated and dispositioned" is the wave's headline W3 deliverable and it
does not hold as written.

### b W2 (LOW) — V13 does not isolate the c2 direction

V13 builds its fixture with `sed '/^next-revisit: /d' "$DM"` from V12's
duplicated-interval file → guard state c1=2, c2=0; the die fires via c1.
Sabotage (tree copy): weakening the guard to `if (c1 != 1) exit 3` leaves
the suite at 36 pins green — the c2 operand is unpinned in discrimination
terms. Bounded impact: for c2=0 the post-rewrite `grep -qx` check still
fails loud (internal consistency); the genuinely unprotected shape under a
weakened guard is c2=2 (duplicated `next-revisit:`), which would be
silently normalized. Fix candidates: derive V13's fixture from a clean
single-interval meta (write_meta + delete the line), or add a c2=2
variant; and correct the resolution's "c2=0 operand direction" wording.

### b W3 (LOW) — header names a shape no pin executes

The in-wave header extension claims "bad/missing status … dies loud with
the meta untouched". Missing status rides the same `*)` arm V17 pins with
`paused` — probed correct (`bad status ''`, rc=2) — but a refactor
special-casing empty status would keep the suite green while the header
claim rots (L3 shape). "Untouched" is asserted only by V12. Fix: an
empty-status variant (one `sed '/^status: /d'` fixture) or weaken the
header's "missing"/"untouched" wording.

### b W4 (LOW) / b W5 (INFO) / b W6 (INFO)

As tabled. b W4: commit-message precision — commit messages are history;
disposition belongs in the resolution wording. b W5: `$(cat)` strips
trailing newlines; `cmp` against a saved copy would be exact — belt-and-
braces only, the die path performs no write. b W6: re-anchor the five
table rows + W1 evidence line to post-wave numbering in the next
bookkeeping touch.

## Claim audit (commit vs claim)

Holds (verified): W1 pins execute the count-guard failure path and V12
asserts the untouched meta (sabotage S3: guard deleted → V12 red);
W2 consolidation one-verdict, count stable 21, no SCOPE_FILES drift,
failure output names file:line (sabotage S5: injected `RM-0042` → red,
`agent/conventions.md:224:…`); W3 all 12 new pins trace to their arms,
needles verbatim, arm-deletion reddens (S6: R7 red on die deletion);
W4 retired rc=1 / corrupt rc=2 split, V7 stays green, header taxonomy
extended, refuse class-sweep holds (only revisit refuses), no consumer of
the old any-non-active-rc=1 semantics anywhere; gates 36/21/lint/sandbox/
line-length green (re-run by main agent on the clean tree).
Does not hold: "pin every die arm" (b W1), "c2=0 operand direction" and
"V12/V13 … byte-identical" (b W2/b W4), header "missing status"/"untouched"
coverage (b W3).

## Retracted/ghost findings

Axis S: stale-consumer suspicion (none exists), V7 breakage from reworded
retired message (needle matches), third-status misclassification
(vocabulary closed at active|retired), two probe artifacts (ROOT
resolution — re-confirmed the :88 refuse). Axis T: R7-R10 silent chain
break (every link fails loud on needle mismatch), lane-a red path losing
detail (per-line filename prefix preserved), meta count 21 wrong (run
confirmed), sandbox violation by `sed -i` (all targets under `$WORK`).

## Run provenance

- Reviewer subagents: 2× GLM-5.3-Flash (fresh contexts), checkpoints with
  launch/return timestamps under /tmp/opencode/review-222/ (b-S, b-T);
  both ran the suites green and sandbox probes under /tmp.
- Main agent (GLM-5.3): re-verified all 6 findings; sabotage runs in a
  tree copy (/tmp/opencode/review-222/sab, live tree untouched): guard
  deleted → V12 red; bad-status arm deleted → V17 red; no-id die deleted →
  R7 red; c2 operand dropped → suite green (b W2 evidence); fake-ID
  injection → lane a red naming file:line.
- Gates at head ea1137b, clean tree: test-rules-revisit.sh 36 pins,
  test-rules-meta.sh 21 pins, make lint, test-sandbox-policy.sh,
  test-line-length.sh all green (run provenance in b-state notes).
- Host: WSL2 kit-managed checkout, check-host.sh green at session start.

## Recommendation

**Proceed after a small b-wave.** No HIGH; b W1 (MED) is a one-pin +
one-table-row fix that makes the W3 claim true; b W2/b W3 are one-line
fixture fixes or one-line wording narrowings; b W4–b W6 are bookkeeping.
Any code-touching disposition owes micro-wave review c per the stop rule;
a wording-only b-wave (b W4–b W6 narrowings, no test/script change) would
close the chain.
