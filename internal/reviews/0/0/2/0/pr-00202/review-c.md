<!-- review-meta
ID: pr-00202
Snapshot: c
Subject: b-wave fix — canary discrimination pins extended from 3 to 7 scratch lines (test-status.sh only)
Scope: wave
Base: v0.0.52 @ 139cfbd
Diff: dd25de8 (single fix commit, tests/unit/test-status.sh +18/-7; 139cfbd is resolution bookkeeping, not review-relevant)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — fresh session per the rotation rule; single-pass main agent, no subagents — maintainer-requested micro pass)
-->

# Review — pr-00202 snapshot c — b-wave fix (canary 3→7 lines)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Wave = `dd25de8` (b W1):
the canary scratch file below the W2 class sweep grows from 3 to 7 lines —
three offending shapes (assignment, in-substitution, brace-assign fixed
path, asserted via `^1:`/`^2:`/`^3:`) and four sanctioned forms
(`|| return 1`, `|| exit 1`, `|| X=""`, warn-only brace, asserted absent
via `^4:`–`^7:`) — and the canary comment now claims to pin "every
discrimination claim the comment above makes".

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | LOW | the canary comment's "every discrimination claim" sentence over-claims — the sweep comment's literal-variant claims (/tmp, /var/tmp, quoted, sudo-prefix, bare `2>/dev/null` non-match) stay unpinned | wave-introduced |

## W1 (LOW) — completeness claim exceeds the canary's coverage

The new comment sentence (dd25de8) says the canary pins "every
discrimination claim the comment above makes". The sweep comment above
makes further discrimination claims the 7-line canary does not cover:

- shape (a): "any /dev/null, **/tmp, /var/tmp** literal, **quoted or not**
  (`[^/]?` eats one leading quote)" — every canary line uses an unquoted
  `/dev/null`; no `/tmp`, no `/var/tmp`, no quoted literal.
- shape (a): "an optional **prefix (sudo mktemp)** is allowed" — no
  prefixed line in the canary.
- shape (b) is pinned only in its muffled form (`mktemp 2>/dev/null ||
  echo /dev/null`); the un-muffled `$(mktemp || echo /tmp)` is not.
- "Deliberately NOT swept … a bare `2>/dev/null` … with no `||` fallback"
  — the claimed non-match for a bare `X=$(mktemp 2>/dev/null)` is not
  pinned either (line 4 of the canary combines `2>/dev/null` WITH the
  `|| echo`).

All of these claims are empirically TRUE today (verified this session
against the SAME `$W2_FIXPATH_A|$W2_FIXPATH_B` extracted from the file:
`|| X=/tmp`, `|| X="/var/tmp"`, `sudo mktemp` prefix, un-muffled shape B
with `/tmp` all match; bare `X=$(mktemp 2>/dev/null)` and plain
`X=$(mktemp)` are spared) — drift risk, not a live lie. Realistic drift:
narrowing the fixed-path alternation `(dev/null|tmp|var/tmp)` to
`(dev/null)` leaves both the sweep (no live site) and the canary (no
`/tmp` line) green while blinding the sweep to `/tmp` fallbacks — the
exact blinding class a W1/b W1 were fixing, one granularity down. The
resolution row mirrors the claim ("canary pins all 7 comment claims",
"pinning every claim the comment makes").

A weaker reading is defensible: the colon enumerates the claim set
(three shapes + four sanctioned forms), and the unpinned items are
literal parameterizations of pinned shapes, not separate shapes. Under
that reading the sentence is self-consistent. L3 still applies to the
words as written: "every … claim the comment above makes" promises more
than the 7 lines deliver.

Fix shape (choose one): (a) weaken the sentence — "Pin the shape
discrimination the comment above makes" or drop "every" — comment-only,
closes the chain under the stop rule; (b) extend the canary by ~4 lines
(`|| X="/tmp"`, `sudo mktemp` prefix, bare `X=$(mktemp 2>/dev/null)`
negative, un-muffled shape B) — test code, owes one more micro pass (d);
(c) deliberately not done with the weaker-reading rationale recorded —
closes the chain.

## Verified claims (commit/resolution audit)

- "canary grew from 3 to 7 scratch lines … SAME
  `$W2_FIXPATH_A|$W2_FIXPATH_B` expression, no re-implementation"
  (resolution b W1) — holds: the canary greps the sweep's two pattern
  variables directly (`grep -nE` vs the sweep's `-rnE`, flags only).
- "three offending shapes asserted via `^1:`/`^2:`/`^3:`, four
  sanctioned absent via `^4:`–`^7:`" (resolution b W1) — holds; the
  scratch file is exactly 7 deterministic `echo` lines, so the
  line-number anchors are stable.
- Mutation evidence re-verified this session (work committed at
  `139cfbd`, tree clean before each mutation, restored green after):
  - brace sub-shape blinded (`\|\|[^|]*=` → `\|\|[^{|]*[[:space:]]*=`
    in W2_FIXPATH_A only, applied via literal-replace with a uniqueness
    assert): canary FAIL "blind or over-broad (got: 1:…)" — line 3
    goes uncaught exactly as claimed; suite rc=1, "1 test(s) failed".
  - fixed-path tail dropped from shape A: sanctioned `X=""` line
    matches → FAIL via the `^6:` negative ("got:" lists 1,2,3,6); suite
    rc=1. Both directions discriminate.
- Class sweep beyond the finding's named lines (L2): the fix pinned
  `|| exit 1` and `|| X=""` although b W1 named only the brace forms —
  recorded in the resolution; confirmed in the diff.
- No stale references to the old pass message "catches both offending
  shapes" outside review-b.md (immutable history). Pass/fail messages
  match the new 3+4 reality.
- Sandbox (policy): canary writes only `$WORK/w2-canary.sh`, never
  executed, only grepped — the `exit 1` scratch line cannot abort
  anything. `$WORK` is suite scratch.
- L1: no NEW `|| true` in the wave (the canary grep's is a-wave,
  reviewed in b; its empty-hits failure path re-observed this session
  via both sabotages, the way the suite observes it).
- L4: pin sits mid-suite before the summary gate — sabotages end rc=1
  with the failed counter, not fail-but-green.

## Gates

- `sh tests/unit/test-status.sh` — green rc=0, 165 PASS incl. "W2 sweep
  canary: catches all three offending shapes (incl. brace-assign),
  spares all four sanctioned"; re-green after both sabotage restores.
- `make lint`, `make check-version` — green. `sh tests/check-host.sh`
  green.
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` — green
  with this snapshot + regenerated INDEX.
- Environment: WSL2/GNU/Linux review host, GNU grep 3.11, /bin/sh →
  dash; clean tree at `139cfbd`; sabotage mutations applied and
  restored via `git restore` (work committed, tree clean before each).

## Retracted/ghost findings

None this pass. (One sabotage initially no-op'd — uniqueness assert
aborted the mutation before any run — that suite run was green because
nothing changed, and was discarded, not counted as a discrimination
proof; the corrected mutation is the one recorded above.)

## Provenance

W1 wave-introduced: the "every discrimination claim" sentence is new in
`dd25de8`; the unpinned sub-claims it exposes pre-date the wave
(`63c9f02`). Run provenance: header.

## Recommendation

**GO.** The b-wave fix does what the resolution claims — all enumerated
discriminations are pinned, both sabotage directions re-verified red,
suite/lint/version gates green, no sibling sites missed. W1 is a
one-word comment weakening (closes the chain), a ~4-line canary
extension (owes snapshot d), or a documented deliberate skip (closes
the chain). Nothing blocks the PR on W1.
