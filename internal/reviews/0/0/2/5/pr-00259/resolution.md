# Resolution — pr-00259 (pin-shape hardening in test-rules-revisit.sh)

Case born in PR #259 (branch `feature/231-rules-revisit-pin-shapes`);
wave under review: 886ada1 (snapshot a, base 02782b9, VERSION 0.0.56).
Chain: a.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (INFO) | **implemented** | `<SHA>` | needle prefix-anchored `rules-audit: 0 blocking`; 10-violation probe reds |
| a Q1 (LOW) | **implemented** | `<SHA>` | all 7 refs qualified to `#222 …`; zero unqualified W-refs remain (grep) |
| a Q2 (INFO) | **implemented** | `<SHA>` | `line_is` gains `-F`; wildcard-dot probe flips match→no-match; suite green |

## Evidence detail

### a W1 (INFO) — digit-bearing survivor `0 blocking`

V11's needle (tests/unit/test-rules-revisit.sh:522) changed from
`contains "$AOUT" "0 blocking"` to
`contains "$AOUT" "rules-audit: 0 blocking"`. Why a prefix anchor and not
`out_line_is`: the audit's zero-violation line is
`rules-audit: 0 blocking violations, N overdue` (scripts/rules-audit.sh:328)
— a full-line anchor would couple the pin to the trailing overdue count,
another digit-bearing field; the literal prefix `rules-audit: 0 blocking`
kills the only false-green trigger W1 named (a 10-violation run printing
`rules-audit: 10 blocking violation(s) …`, :324, substring-matched the old
`"0 blocking"` needle). Probes: `printf 'rules-audit: 10 blocking
violation(s), 0 overdue' | grep -qF "rules-audit: 0 blocking"` → exit 1;
the 0-blocking line → exit 0. Suite green after the change (39 pins).

### a Q1 (LOW) — citation class sweep completed

All 7 sites qualified, each mapping verified against the case folders
BEFORE writing (a wrong qualifier would be worse than bare): :227 →
`#222 a W3` (review-a.md:30, per-meta die arms), :530 → `#222 a W1`
(review-a.md:28, rewrite validation arms), :668 → `#222 a W4`
(review-a.md:31, status split — same ID the wave qualified at :619),
:569 and :638 → `#222 b W2` (review-b.md:31, c2-operand shapes),
:655 → `#222 b W1` (review-b.md:30, computation-failed die arm),
:669 → `#222 b W3` (review-b.md:32, missing-status shape). Post-fix
sweep: `grep -nE 'W[0-9]' tests/unit/test-rules-revisit.sh` minus
`#2NN [ab] W<N>`-prefixed hits → zero remain (the `L1` refs at :191/:468
are learnings classes, out of scope by the finding's own text).
Comment-only change — not review-relevant on its own (RM-0065), but
implemented in the same round as W1/Q2, which are.

### a Q2 (INFO) — helper semantics aligned

`line_is` (tests/unit/test-rules-revisit.sh:53-55): `grep -qx` →
`grep -qxF`, inline comment updated to name the fixed-string needle
(`#259 a Q2`). All 15 call sites use literal needles (dates, dashes,
parens — enumerated at :309-:350, :462, :523); none relies on BRE
metacharacters, so `-F` is strictly correct: the wildcard-dot probe
(haystack `next-revisit: 2026X12Y15` vs needle `next-revisit: 2026-12-15`)
matched under the old BRE (`.` as any-char) and no longer does.
Suite green post-change (39 pins).

## Chain / follow-ups

- Round b owed: this fix wave touches test code (one needle, one helper
  flag — review-relevant, RM-0065), so one wave review of this diff is
  owed on the maintainer's go (RM-0106/RM-0107). Expectation, check cited
  (RM-0115): round b's own material is comment lines + the W1 needle +
  the Q2 flag; a round whose dispositions stay comment-only from there
  leaves review-relevant code untouched (RM-0066).
- `<SHA>` placeholders above are filled by the chain's next commit
  (check-then-commit on row width applies to that edit, issue #237).
- Gates run before this fix commit: affected suite (39 pins green),
  `make lint`, line-length ratchet, `gen-review-index.py`, reviews lint,
  reviews parity.
