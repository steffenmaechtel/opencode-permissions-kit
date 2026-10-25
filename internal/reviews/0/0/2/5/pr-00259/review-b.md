<!-- review-meta
ID: pr-00259
Snapshot: b
Subject: micro pass — a-wave dispositions fix in 370ccd8 (7-ref citation sweep, W1 needle prefix-anchor, line_is -F)
Scope: wave
Base: 0.0.56 @ de3a50b
Diff: de3a50b..370ccd8
Date: 2026-10-25
Reviewer: GLM-5.3 house session (opk-review-pass skill) — single-session pass, no subagents (USER commission)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review b — micro pass on the a-wave dispositions fix (pr-00259)

Round b over the fix commit `370ccd8` (snapshot a's three dispositions:
a W1 needle prefix-anchor, a Q1 citation sweep, a Q2 `line_is` `-F`; plus
resolution.md creation, review-a's Resolution pointer, INDEX regen).
Commissioned by the maintainer: "Snapshot b Review, max 5 minuten, keine
Sub Agents, alles selbst reviewen, mini review" — single-session micro
pass, no reviewer subagents, ~5-minute budget, hunt and verify in this
session (the collapsed axis is disclosed under Calibration). Diff =
4 files, +84/−11, of which 71 lines are the new resolution.md.

**Result: 2 findings — 0 HIGH, 0 MED, 2 LOW, 0 INFO.** Both are
evidence-accuracy defects in the fix wave's own record (fix-induced);
the shipped code changes themselves verified correct. All six fix-commit
claims audited: four held, two are the findings.

## Findings index

| ID | Severity | One-liner | Provenance | Verification |
|----|----------|-----------|------------|--------------|
| Q1 | LOW | The a-Q2 "wildcard-dot probe" evidence is impossible as described: the needle's wildcard positions are hyphens (literal in BRE) — `2026-12-15` never matched `2026X12Y15` under any grep semantics; the real BRE→`-F` delta is the two trailing-dot log-line needles | fix-induced | verified |
| Q2 | LOW | "All 15 call sites literal" miscounts: the tree has 12 `line_is` call sites (13 `\bline_is\b` hits minus the definition); the enumeration `:309-:350, :462, :523` is right, only the total is wrong | fix-induced | verified |

---

## Findings detail

### Q1 — LOW · impossible probe evidence · fix-induced

resolution.md:54-56 (and, immutably, the fix-commit message) record:

> the wildcard-dot probe (haystack `next-revisit: 2026X12Y15` vs needle
> `next-revisit: 2026-12-15`) matched under the old BRE (`.` as
> any-char) and no longer does.

The needle contains **hyphens**, not dots — no regex metacharacter sits
at any position of the pair, so old `grep -qx` behaved identically to
`grep -qxF` for exactly this haystack/needle combination. Reproduced on
this host: `printf 'next-revisit: 2026X12Y15\n' | grep -qx
'next-revisit: 2026-12-15'` → rc=1, and under `-F` → rc=1 — no flip
exists. (Sanity that BRE dots do work here: `grep -qx 'a.c'` matches
`abc`, rc=0.) The **real**, reproducible BRE→`-F` delta in this file is
at the two log-line needles ending `).` (`:313`, `:351`): under BRE the
trailing `.` matched any final character — witnessed live: needle
`ok).` matches haystack `ok)!` under `grep -qx` (rc=0), exits 1 under
`grep -qxF`; same shape for the full log-line needle against an `X`
tail. So the `-F` change is correct and mildly strengthening, but the
recorded discriminating evidence never discriminated. The disposition
(implemented) stands; the evidence text does not.

### Q2 — LOW · call-site miscount · fix-induced

resolution.md:52-53 (and the fix-commit message): "All 15 call sites
use literal needles (… enumerated at :309-:350, :462, :523)". The tree
has **12** `line_is` call sites: `grep -cE '\bline_is\b'` = 13, minus
the definition at `:53` — enumerated `:309`, `:310`, `:311`, `:312`
(needle on `:313`), `:318`, `:335`, `:336`, `:348`, `:349`, `:350`
(needle on `:351`), `:462`, `:523`. The enumeration ranges in the claim
are correct; only the total is off by three. The load-bearing part —
every call site's needle is literal, none relies on BRE semantics —
was re-verified needle by needle and holds for all 12. Why it matters:
the count is the sweep's completeness evidence in the case's control
panel; a future round auditing "15 sites" against the tree will find
12 and burn time doubting its own grep. Correctable in resolution.md
(the commit message is immutable).

## Verified clean (claims audited, no finding)

- **a W1 prefix anchor — correct and discriminating.** The audit emits
  exactly the claimed shapes (`scripts/rules-audit.sh:324` violations
  variant, `:328` zero variant). Live probes on this host:
  `rules-audit: 10 blocking …` vs needle `rules-audit: 0 blocking` →
  rc=1; `100 blocking` → rc=1 (kills every ≥10 count, not just 10);
  `rules-audit: 0 blocking violations, 3 overdue` → rc=0. The pin's
  leading `[ "$ARC" -eq 0 ]` guard already excludes the violation-list
  path, so no violation-detail substring can false-green it.
- **a Q1 citation sweep — complete and correctly mapped.** All 7
  requalified sites verified **semantically** against the #222 case
  folders, not just syntactically: `:227`→`#222 a W3` (report per-meta
  die arms ✓), `:530`→`#222 a W1` (rewrite validation arms ✓), `:668`→
  `#222 a W4` (status split, must-die-rc=2 ✓), `:569`/`:638`→`#222 b W2`
  (c2 operand shapes, both the c2=0 and c2=2 directions ✓), `:655`→
  `#222 b W1` (computation-failed die; even the "R6 counterpart"
  phrasing aligns with b W1's text ✓), `:669`→`#222 b W3` (missing-status
  shape ✓). Post-fix sweep: `grep -nE 'W[0-9]'` → 8 hits, every one
  `#222 [ab] W<n>`-qualified (incl. the wave's own `:619`); zero
  unqualified remain; `L1` refs are learnings classes, out of scope per
  the finding's own text.
- **a Q2 `-F` flag — shipped change correct.** All 12 needles read
  literally; none relies on BRE metacharacters; `-F` additionally pins
  the trailing-dot needles that BRE underanchored (see Q1). Suite green.
- **Bookkeeping.** review-a.md's +2 lines are exactly the
  `> Resolution:` pointer (the one allowed post-hoc edit, README
  rule 1); INDEX row `no-resolution` → `open` matches the absent
  `Status:` line contract; the three `<SHA>` placeholders follow the
  documented mechanism (README "The `<SHA>` placeholder") and are
  filled by this snapshot commit; the new `#259 a Q2` citation in the
  helper comment is properly qualified.
- **Gates re-run on this tree** (clean at 370ccd8): affected suite
  "rules-revisit pins: OK (39 pins green)", `make lint`,
  line-length ratchet, reviews lint (31 cases), reviews parity
  (31 rows) — all green, matching the fix commit's gate claims.
- **Security axis:** diff touches one test file + `internal/reviews/`
  docs only — no root ops, no untrusted-input surface, nothing to flag.

## Retracted/ghost findings

Two process ghosts from this session's own hunt, recorded for the
trail: (1) the first wildcard-probe run was invalid — the output
redirect failed before the scratch directory existed, so the "old BRE"
grep of the first attempt ran against a missing file; the clean re-run
(mkdir first, file verified via `cat` + `od -c`) produced the stable
rc=1/rc=1 result. (2) The transient suspicion "old BRE does not match
dots on this host" was disproven by the minimal probe (`a.c` matches
`abc`, rc=0) and resolved into finding Q1's actual mechanism
(hyphens-vs-dots). Neither ghost survived into the index.

## Run provenance

- **Commission:** USER (maintainer), in-session — "Snapshot b Review,
  max 5 minuten, keine Sub Agents, alles selbst reviewen, mini review",
  followed by "falls es was zu fixen gibt, fix es" (fix wave
  commissioned in advance; the snapshot still commits first — hard seam).
- **Pass shape:** single session (GLM-5.3, strong tier), **no reviewer
  subagents** — the USER explicitly commissioned a no-fan-out pass;
  hunt, verification, and screening all ran in this session. No
  checkpoints (nothing to synchronize), no `/tmp` case scratch beyond
  probe fixtures at `/tmp/opencode/pr-00259-b/` (grep probes only).
- **Host timestamps:** review start `2026-10-25T00:51:35Z`, review end
  `2026-10-25T00:56:32Z` (~5 min, on budget).
- **Mutation/sabotage windows:** none — the tree stayed a clean read
  substrate for the entire pass (`git status --porcelain` empty at
  pre-flight and at snapshot write); every probe ran on `/tmp` fixtures
  or pure pipes, zero repo bytes touched before this snapshot.
- **Environment:** checkout at `/var/www/opencode-permissions-kit`,
  branch `feature/231-rules-revisit-pin-shapes`, clean at `370ccd8`
  (base `de3a50b` = snapshot a, VERSION 0.0.56); host pre-flight
  `sh tests/check-host.sh` green at session start.
- **Row-width note:** filling the three `<SHA>` placeholders (this
  commit) grows the a-W1 and a-Q2 rows past the 120-column bound
  (119→121, 120→122) — both rows were mechanically shortened to fit
  before commit, per README "check-then-commit" (the pr-00234 lesson,
  applied live).

## Gates

Run before this snapshot commit (check-then-commit, RM-0117): affected
suite (39 pins green), `make lint`, `sh tests/unit/test-line-length.sh`
(after the SHA fills + row trims), `sh tests/unit/test-reviews-lint.sh`,
`sh tests/unit/test-reviews-parity.sh`, `python3
scripts/gen-review-index.py` (INDEX: pr-00259 snapshots a–b, open).

## Calibration

Micro shape — no second independent snapshot owed (release scope only).
This pass collapsed the hunt/verify separation: single session, no
subagents, USER-commissioned; mitigations were mechanical re-measurement
of every load-bearing claim (own greps with recorded counts, live grep
probes on /tmp fixtures, all gates re-run) and verification of both
findings against primary sources (the #222 snapshots, the audit script's
emission lines, host grep behavior via minimal probes). Ran WITH the
opk-review-pass skill (see `Skills:`); no external no-skill pass exists
for this case — that axis is collapsed by commissioning and disclosed
here.

## Recommendation

Dispositions owed from round b: **Q1, Q2 (both LOW)** — both fixable in
resolution.md alone (correct the a-Q2 evidence block: replace the
impossible probe with the real trailing-dot delta, fix the 12-count).
The fix wave's own material is then evidence prose only — not
review-relevant code (RM-0065/RM-0066) — so the stop-rule expectation
(RM-0115) is: no round c auto-owed; closure is the maintainer's call
(a fixing round never closes its own loop). The fix is commissioned and
follows this commit directly.
