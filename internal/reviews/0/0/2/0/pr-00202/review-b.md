<!-- review-meta
ID: pr-00202
Snapshot: b
Subject: a-wave fixes — W2 sweep canary + sanctioned-fallback comment precision (test-status.sh only)
Scope: wave
Base: v0.0.52 @ 9d913a6
Diff: 119b122 (single fix commit, tests/unit/test-status.sh +23/-1; 9d913a6 is resolution/INDEX bookkeeping, not review-relevant)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — fresh session per the rotation rule; single-pass main agent, no subagents — maintainer-requested micro pass)
-->

# Review — pr-00202 snapshot b — a-wave fixes (canary + comment)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Wave = `119b122` (a W1 + a W2):
adds a canary below the widened W2 class sweep in `tests/unit/test-status.sh`
(three scratch lines — shape-A assignment, shape-B in-substitution, one
sanctioned `|| return 1` — grepped with the SAME `$W2_FIXPATH_A|$W2_FIXPATH_B`
expression, asserting `^1:`/`^2:` present, `^3:` absent) and tightens the
sweep comment's sanctioned-fallback sentence (brace-assign fixed path DOES
match shape (a) by design; warn-only braces do not).

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | LOW | the a-W2 comment's brace-form claims carry no pin — the canary built in the same commit covers none of them | wave-introduced |

## W1 (LOW) — brace-form discrimination claims unpinned

The new comment sentence (a W2 fix) makes two behavior claims about the
pattern: a brace that ASSIGNS a fixed path (`X=$(mktemp) || { X=/dev/null; }`)
DOES match shape (a), and warn-only `|| { ... }` braces do not. The canary
added in the same commit pins neither — its three lines cover assignment
fallback, in-substitution fallback, and `|| return 1` only; no brace line
exists in the scratch file. Both claims are empirically TRUE today
(verified this session, scratch under /tmp/opencode: brace-assign matches
via shape (a); warn-only braces, `|| { …; return 1; }` and `|| { X=""; }`
are all spared). Drift risk, not a live lie: a future regex edit that
loses the brace-assign sub-shape stays green in both the sweep (no live
brace-assign site exists — the only `|| {` site, ddev-migrate.sh:579, is
warn-only) and the canary — the exact blinding class a W1 was fixing, for
a sub-shape. L3: a claim carries a pin or is deleted/weakened.

Fix shape (test-only, ~3 lines): extend the canary scratch file with
`_w2_can_c=$(mktemp) || { _w2_can_c=/dev/null; }` and
`_w2_can_ok2=$(mktemp) || { echo warn >&2; }`, assert `^4:` present and
`^5:` absent. Alternative disposition (deliberately not done) is
defensible: the comment is accurate prose verified above, and the canary's
own stated purpose ("prove both alternations still trip") is fully met.

## Verified claims (commit/resolution audit)

- "canary beside the sweep, SAME expression" (resolution a W1) — holds:
  the canary greps with `$W2_FIXPATH_A|$W2_FIXPATH_B` directly, no
  re-implementation; only the grep flags differ (`-nE` vs the sweep's
  `-rnE`), not the pattern.
- "sabotage A → canary FAIL with got: 2:…" (resolution a W1 mutation
  evidence) — re-verified this session, both directions, tree restored
  green after each (work committed at HEAD, tree clean):
  - blind shape A (`mktemp`→`mktempXX` in `W2_FIXPATH_A`): canary FAIL,
    "got: 2:_w2_can_b=…" — precisely the shape-A line going uncaught;
    suite reports 1 test failed.
  - over-broad (`W2_FIXPATH_A=''`): suite rc=1 — the sweep itself FAILS
    first (empty alternation matches every line in files/) AND the canary
    FAILs "over-broad" with all three lines incl. the sanctioned `^3:`.
    Both guards independently catch the degradation.
- "comment now states brace-assign … matches shape (a) by design"
  (resolution a W2) — holds, empirically (see W1).
- New `|| true` on the canary grep (L1): its failure path (empty hits)
  flows into the FAIL branch — executed and observed via the blind
  sabotage above, the way the suite observes it.
- Pin sits before the summary gate (L4a): `fail` increments the counter,
  sabotaged runs end rc=1 with "1 test(s) failed".
- Class sweep (L2): no sibling zero-match pattern sweeps over `files/`
  exist elsewhere in tests/unit — the W2 sweep is the only one; nothing
  else needs a canary from this wave.
- Sandbox: canary writes only `$WORK/w2-canary.sh` — inside the suite
  scratch, policy-conform.

## Gates

- `sh tests/unit/test-status.sh` — green rc=0, 165 PASS incl. "W2 sweep
  canary: pattern catches both offending shapes, spares the sanctioned";
  0 FAIL after restore.
- `make lint`, `make check-version` — green.
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` — green
  with this snapshot + regenerated INDEX.
- Environment: WSL2/GNU/Linux review host, GNU grep 3.11, /bin/sh → dash,
  clean tree at 9d913a6; sabotage runs restored via `git restore` (work
  committed, tree clean before each mutation).

## Retracted/ghost findings

None this pass.

## Provenance

W1 wave-introduced (the comment sentence and the canary are both new in
`119b122`; the gap between them is the fix wave's own). Run provenance:
header.

## Recommendation

**GO.** The a-wave fixes do what the resolution claims — the canary
discriminates in both directions, the comment no longer over-claims, and
every resolution claim re-verified. W1 is a 3-line test-only tightening
or a documented deliberate skip; if implemented it owes one final micro
pass (c) under the stop rule, if skipped the chain closes here.
