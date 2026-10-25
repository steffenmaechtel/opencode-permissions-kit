# Resolution — pr-00259 (pin-shape hardening in test-rules-revisit.sh)

Status: closed 2026-10-25 — confirmed by the maintainer in-session (round b report: "ok dann fixen und close
  machen"); stop-rule check: round b ([review-b.md](review-b.md), `c93f202`) found 2 LOW evidence-accuracy
  findings, both dispositioned implemented in `cc8e5d3` — files touched = resolution.md only (evidence prose +
  bookkeeping, RM-0065, loop closed per RM-0066); round-a findings were already dispositioned in `370ccd8`;
  no reviews owed-but-not-run (single-session pass per USER commission, disclosed in review-b's Calibration).

Case born in PR #259 (branch `feature/231-rules-revisit-pin-shapes`);
wave under review: 886ada1 (snapshot a, base 02782b9, VERSION 0.0.56).
Chain: a, b.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (INFO) | **implemented** | `370ccd8` | prefix-anchored `rules-audit: 0 blocking`; 10-violation probe reds |
| a Q1 (LOW) | **implemented** | `370ccd8` | all 7 refs qualified to `#222 …`; zero unqualified W-refs remain (grep) |
| a Q2 (INFO) | **implemented** | `370ccd8` | `line_is` gains `-F`; all 12 call sites literal; suite green |
| b Q1 (LOW) | **implemented** | `cc8e5d3` | impossible probe replaced by the real trailing-dot delta (#259 b Q1) |
| b Q2 (LOW) | **implemented** | `cc8e5d3` | call-site count corrected 15 -> 12 (grep-pinned enumeration) |

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
(`#259 a Q2`). All 12 call sites use literal needles (dates, dashes,
parens — enumerated :309-:350, ten sites with the :312/:350 needles on
the following line, plus :462 and :523); none relies on BRE semantics,
so `-F` is strictly correct. Suite green post-change (39 pins).
Evidence corrected in round b (#259 b Q1/#259 b Q2, detail blocks
below): this block originally claimed a "wildcard-dot probe" flip
(`2026X12Y15` vs `2026-12-15`) that cannot exist — the needle's
variable positions are hyphens, literal in BRE, so rc=1 under both
old and new semantics. The real BRE→`-F` delta: the two log-line
needles ending `).` (:313, :351) — under BRE the trailing `.` matched
any final char; `-F` pins it literal.

### b Q1 (LOW) — impossible wildcard-dot probe claim corrected

The fix wave's evidence for a Q2 (370ccd8 commit message + this
file's a-Q2 block) described a probe that cannot discriminate:
haystack `next-revisit: 2026X12Y15` vs needle
`next-revisit: 2026-12-15` puts hyphens — not regex metacharacters —
at the wildcard positions. Reproduced on the review host: `grep -qx`
rc=1 AND `grep -qxF` rc=1; sanity probe `grep -qx 'a.c'` matches
`abc` (rc=0) proves BRE dots work there, so the mismatch is the
needle's shape, not the host. The reproducible delta the probe meant
to show: needle `ok).` matches haystack `ok)!` under BRE (rc=0),
exits 1 under `-F` — exactly the trailing-dot shape of the log-line
needles at :313/:351. Fix: a-Q2 row and block rewritten to the real
delta (this commit); the 370ccd8 message is immutable — this block
and review-b.md (b Q1) are the correction of record.

### b Q2 (LOW) — call-site count corrected

"All 15 call sites" (370ccd8 message + a-Q2 block) miscounts:
`grep -cE '\bline_is\b'` on the file returns 13 including the
definition at :53 → **12** call sites (:309, :310, :311, :312,
:318, :335, :336, :348, :349, :350, :462, :523; the :312/:350
needles sit on the line after their call). The claim's ranges
(:309-:350, :462, :523) were right; only the total was off by
three. Every needle re-verified literal in round b — the
load-bearing part ("none relies on BRE semantics") holds for all
12. Fix: count corrected in the a-Q2 row and block (this commit).

## Chain / follow-ups

- Round b done (snapshot `c93f202` reviewed fix `370ccd8`,
  single-session micro pass per USER commission): 2 LOW findings,
  both disposed above — the round-b fixes touch only this file's
  evidence prose, not review-relevant code (RM-0065/RM-0066), so no
  round c is auto-owed; closure confirmed by the maintainer
  in-session 2026-10-25 — Status line set, both Commit-column
  placeholders filled, INDEX regenerated in the same commit (the
  closure edit this bullet announced).
- Gates run before this fix commit: affected suite (39 pins green),
  `make lint`, line-length ratchet, `gen-review-index.py`, reviews lint,
  reviews parity.
