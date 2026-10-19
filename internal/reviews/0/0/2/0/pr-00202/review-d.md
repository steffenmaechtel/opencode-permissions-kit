<!-- review-meta
ID: pr-00202
Snapshot: d
Subject: c-wave fix — canary discrimination pins extended from 7 to 14 scratch lines (test-status.sh only)
Scope: wave
Base: v0.0.52 @ d3b7afc
Diff: d19919c (single fix commit, tests/unit/test-status.sh +26/-10; e516be7 is resolution bookkeeping, not review-relevant)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — fresh session per the rotation rule; single-pass main agent, no subagents — maintainer-requested micro pass)
-->

# Review — pr-00202 snapshot d — c-wave fix (canary 7→14 lines)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Wave = `d19919c` (c W1):
the canary scratch file below the W2 class sweep grows from 7 to 14
lines — six offending shapes (assignment, muffled in-substitution,
brace-assign fixed path, quoted `/tmp`, sudo-prefixed `/var/tmp`,
un-muffled shape B) asserted via `^1:`/`^2:`/`^3:`/`^8:`/`^9:`/`^11:`,
eight non-match lines (return/exit, `X=""`, warn-only brace, bare
`2>/dev/null`, three-line multi-line fallback) asserted absent via
`^4:`–`^7:`/`^10:`/`^12:`–`^14:` — and both the canary comment and the
pass message now claim 6-match / 8-spared.

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | INFO | snapshot c's gate line "165 PASS" does not reproduce — the same metric on the same tree (d3b7afc) yields 138 (137 passes + 1 summary line); correction belongs in the resolution, no code change | pre-existing |

## W1 (INFO) — snapshot c gate count does not reproduce

review-c.md's gates section records `sh tests/unit/test-status.sh` as
"green rc=0, 165 PASS". Re-run this session on the exact tree c
reviewed (`git checkout d3b7afc -- tests/unit/test-status.sh`,
suite otherwise at HEAD): **138** lines containing PASS (137 test
passes + the closing "All status tests passed." summary), 0 FAIL,
0 SKIP — identical to HEAD after the c-wave fix. The suite is
deterministic here: the `W2_BLOCK_*` blocks are self-extracted
fixtures (sed out of status.sh, lines 1041–1043), not env-gated, and
no `id -u` gate drops blocks for non-root (the hits at 1778/1842 are
string assertions). No tests were lost by the c-wave — the count was
already 138 at c's tree; the "165" appears to be a counting artifact
of that session (the source has 140 static `pass` call sites including
conditionals never reached). Shipped code is unaffected; the error
sits in an immutable snapshot, so the correction is a resolution note
(bookkeeping only — closes the chain without touching review-relevant
code).

## Verified claims (commit/resolution audit)

- "canary grew from 7 to 14 scratch lines … still the SAME
  `$W2_FIXPATH_A|$W2_FIXPATH_B` expression" (resolution c W1) —
  holds: the wave touches no pattern variable, only scratch lines,
  assertions, comment and pass message (`+26/-10`).
- "six offending asserted via `^8:`/`^9:`/`^11:` [plus 1–3], eight
  non-match asserted absent" — holds; the scratch file is exactly 14
  deterministic `echo` lines, colon-anchored line prefixes do not
  collide (`^1:` cannot match `14:`).
- Claim-map audit (the c W1 core): every discrimination sentence in
  the sweep comment now has a canary line — literals /dev/null, /tmp,
  /var/tmp (1, 8, 9); quoted-or-not (8 quoted, rest unquoted — the
  `[^/]?` quote-eating pinned once); sudo prefix (9); shape B muffled
  (2) and un-muffled (11); sanctioned return/exit/`X=""`/warn-brace
  (4–7); brace-assign fixed path matches by design (3); bare
  `2>/dev/null` without `||` spared (10); multi-line fallback spared
  (12–14). The "every discrimination claim" sentence is now true as
  written.
- Ground truth (independent of the suite's own mechanism): the two
  pattern variables extracted verbatim and run against a replica of
  the 14 lines match exactly `1 2 3 8 9 11`.
- Mutation evidence re-verified this session (work committed at
  `e516be7`, tree clean before each mutation, restored + re-green
  after):
  - alternation narrowed `(dev/null|tmp|var/tmp)` → `(dev/null)` in
    BOTH shapes (python literal-replace with count assert = 2): canary
    FAIL "blind or over-broad" with got `1:`/`2:`/`3:` — precisely the
    three new offending lines uncaught; suite rc=1, "1 test(s)
    failed". Matches the resolution's first sabotage claim.
  - shape A stripped to `'/dev/null|/tmp|/var/tmp'`: canary FAIL
    over-broad with got 1,2,3,8,9,10,11,13 — the new negatives `^10:`
    (bare `2>/dev/null`) and `^13:` (multi-line middle line) fire;
    suite rc=1 ("2 test(s) failed" — the real sweep over files/ goes
    red too). Matches the resolution's second sabotage claim.
- No new `|| true`, stderr redirect or probe pipe in the wave (L1):
  the canary grep's `|| true` is a-wave heritage, re-observed red this
  session via both sabotages.
- Sandbox (policy): canary writes only `$WORK/w2-canary.sh`; the
  scratch lines are grepped, never executed — the `sudo mktemp`,
  `exit 1` and multi-line lines cannot run.
- L4: the pin sits mid-suite before the summary gate — both sabotages
  end rc=1 with the failed counter, not fail-but-green.
- Stale references: no occurrence of the old pass message
  ("all three offending shapes" / "spares all four") outside
  `internal/reviews` (immutable history).

## Gates

- `sh tests/unit/test-status.sh` — green rc=0, 137 passes + summary,
  0 FAIL / 0 SKIP, incl. "W2 sweep canary: catches all six offending
  lines (incl. quoted, prefixed, un-muffled), spares all eight
  non-match lines"; re-green after both sabotage restores.
- `make lint`, `make check-version` — green (VERSION 0.0.52, matches
  the chain base).
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` —
  green with this snapshot + regenerated INDEX.
- Environment: WSL2/GNU/Linux review host, GNU grep 3.11, /bin/sh →
  dash; clean tree at `e516be7` before each mutation; sabotages
  applied via python literal-replace with occurrence-count asserts,
  restored via `git restore` / `git checkout HEAD`.

## Retracted/ghost findings

None filed. Explicitly considered and dropped: further literal
parameterizations (quoted `/dev/null`, quoted `/var/tmp`, sudo-prefixed
shape B, a fixed-file form of the bare `2>/dev/null` claim) — same
class snapshot c already litigated; one representative per axis is
pinned and the structural `||` requirement covers the rest. Filing
combinatorial variants would be the taste ping-pong the five-round
stop rule exists to prevent.

## Provenance

W1 pre-existing (bookkeeping): the "165 PASS" line entered the record
with review-c.md at `d3b7afc`; the wave under review neither
introduced nor touched it. Run provenance: header.

## Recommendation

**GO.** The c-wave fix does what the resolution claims — every
discrimination sentence of the sweep comment has a pin, ground truth
and both sabotage directions re-verified red this session, suite/lint/
version gates green. W1 is a resolution-note correction (bookkeeping
only). Once its disposition lands, the round touches no
review-relevant code and the chain closes under the stop rule.
