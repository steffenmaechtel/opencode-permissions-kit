<!-- review-meta
ID: pr-00209
Snapshot: b
Subject: a-wave fix diff — bridge pin boundary assertions (#209 a W1, a W2)
Scope: wave
Base: v0.0.53 @ 9c4bf01
Diff: 9c4bf01..1dc553f (fix commit; 55513e1 is resolution/INDEX bookkeeping)
Date: 2026-10-20
Reviewer: GLM-5.3 main agent (verification duty) + 2 GLM-5.3-Flash subagents (B1 pin fidelity, B2 regression/bookkeeping); checkpoints /tmp/opencode/review-pr-00209-b/
-->

# Micro-wave review — pr-00209 snapshot b — the a-wave fix diff

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Wave = `1dc553f`
(`9c4bf01..1dc553f`, 1 file): the #201 bridge pin grew the two assertions
a W1 demanded — `[ "$(w201_bridge 1.18.33)" = 1 ]` (1.x eq boundary) and
`[ "$(w201_bridge 2.0.17)" = 0 ]` (2.x lt boundary) — and the comment
above the pin was rewritten to name the discriminated shapes; a W2's
typo fixed. `55513e1` (resolution + INDEX) is bookkeeping, not
review-relevant code, but its claims were audited too (b W3).

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | LOW | new comment/pass message overclaim: "discriminates every shape the verdict names … neither the comparator direction … can drift silently" — the 2.x arm has no above-boundary assertion, so `!= lt` → `= eq` on status.sh:995 survives the whole suite (observed rc=0); future 2.0.19+/2.1.x would get carrier verdicts | fix-induced |
| W2 | INFO | the `command -v advisories_version_cmp` guard (status.sh:992) is unpinned — the pin's helper always sources advisories.sh, so removing the guard stays green; on a broken kit (missing advisories.sh, loudly warned per #165) a successful probe would then yield a false "not needed" bridge row | pre-existing |
| W3 | LOW | resolution.md's class-sweep record (and the commit message's sweep sentence) under-enumerates: test-wsl-exposure.sh:115–117/137–139 are executable 1.18.33/2.0.18 wiring pins the recorded pattern matches but does not list; comparator citation "lines 65–68" covers only half the gate block (65–79) | delta-introduced |

No MED/HIGH findings.

## W1 (LOW) — "every shape" comment: 2.x-above is not asserted

The fix's comment (test-status.sh:1364–1367) claims the pin
"discriminates every shape the verdict names — both eq boundaries
(1.18.33, 2.0.18) asserted on their own arm, plus above/below/unknown —
so neither the comparator direction nor a boundary constant can drift
silently". The assertion set is: 1.19.0 (1.x above), 1.18.33 (1.x eq),
2.0.18 (2.x eq), 2.0.17 (2.x below), 1.18.32 (1.x below), `""`
(unknown). "Above" exists only on the 1.x arm — no assertion probes a
2.x version greater than 2.0.18, although the pass message names
"2.0.18+ unneeded".

Observed (main agent, tree committed at `55513e1`, restored green
after each run):

- `!= lt` → `= eq` on status.sh:995 (2.x arm): full `test-status.sh`
  **green (rc=0)** — the surviving mutation. Production effect if it
  ever regressed: an opencode 2.0.19+/2.1.x install falls through to
  the carrier rows although its opener is WSL-safe — a safe-side
  mislabel, same class and severity reasoning as a W1 (test-vacuous,
  not a shipped bug).
- The symmetric mutation on the 1.x arm (`= eq` at 994) FAILs via the
  1.19.0 assertion — the asymmetry is real, not theoretical.

All other enumerated mutations (B1 checkpoint lists 25) are caught:
every 1.x direction flip, all four boundary-constant drifts, arm
swaps/deletion, `_st_bridge_unneeded=1` init. Suggested fix, one
assertion inside the existing `if`:

```sh
… && [ "$(w201_bridge 2.0.19)" = 1 ] \
```

— or soften the comment to "each arm's eq boundary and below side, 1.x
above, unknown". Comment-softening alone closes the claim gap without
touching test semantics; the assertion closes the mutation gap.

## W2 (INFO) — the comparator-availability guard is unpinned (pre-existing)

The production guard `command -v advisories_version_cmp`
(status.sh:992, introduced in `540666c` — predates this case's base
`f07f2fb`) cannot be seen by the pin: `w201_bridge` sources the real
advisories.sh, so the function always exists at eval time and guard
removal stays green (B1, reasoned — not mutation-run). Mechanism
code-verified: the sourcing guard at status.sh:244–440 closes long
before the bridge block (991+), which renders whenever the WSL section
runs; with advisories.sh missing the script warns loudly (#165,
status.sh:240–243) but continues — without the `command -v` guard, a
successfully probed version would then hit an empty command
substitution → `[ "" != lt ]` → true → a false "not needed — ships a
WSL-safe opener" row on a broken kit.

INFO because it needs a partially deployed kit that is already flagged
by the counted warn row, and the construct predates the reviewed waves.
A pin would need a helper variant that evals the block WITHOUT sourcing
advisories.sh and asserts `_st_bridge_unneeded` stays 0. Recorded as
backlog; not a claim the a-wave or its fix ever made.

## W3 (LOW) — class-sweep record under-enumerates (bookkeeping accuracy)

The resolution's Evidence paragraph (and the fix commit's sweep
sentence) states the sweep found "only this pin and the comparator pins
in test-security-advisories.sh". The recorded pattern
(`grep -rnE '1\.1[0-9]\.[0-9]+|2\.0\.[0-9]+' tests/unit/*.sh`) also
matches tests/unit/test-wsl-exposure.sh:115–117 (wrapper wiring) and
137–139 (status.sh wiring) — executable `check` assertions doing
`grep -qF '1.18.33'` / `grep -qF '2.0.18'`, not comments. The
"sites-checked" list in the record is therefore incomplete, and the
comparator citation "asserted at its lines 65–68" names only the
1.18.32/1.18.33 pins — the gate block spans 65–79 (2.0.17/2.0.18/empty
fail-safe included).

The record's CONCLUSION ("no sibling gap left") survives verification —
but for a corrected reason: the wsl-exposure checks are presence greps
over whole files, and status.sh carries the same literals in its
comment/detail prose (lines 985, 1000), so they do NOT discriminate
comparator-line constant drift (observed: M2-style drift 1.18.33 →
1.18.34 at status.sh:994 leaves test-wsl-exposure.sh green, rc=0).
They are wiring pins, not boundary pins; no sibling behavioral
boundary pin exists outside test-status.sh and
test-security-advisories.sh. B2's original sub-claim that those pins
"would have caught M2/M3-style drift cross-suite" is retracted by that
observation. Suggested fix: amend the resolution's class-sweep
paragraph (list the two wiring-pin sites, correct the line citation) —
bookkeeping only, no code change.

## Verified clean (commit-vs-claim audit)

- **All six assertions re-derived against the production block**
  (status.sh:991–997): 1.19.0→1, 1.18.33→1, 2.0.18→1, 2.0.17→0,
  1.18.32→0, `""`→0 via the `-n` guard; comparator is the sort -V
  relation (advisories.sh:44). The sed extraction anchor is unique at
  its indentation and the eval is self-contained.
- **a W1's closure is real:** M1 reproduced — 1.x arm `!= lt` → `= gt`
  now FAILs the suite (rc=1, "bridge ADV_VER keying drifted" with the
  extract dump); tree restored green after each mutation.
- **a W2's closure is real:** "strenghtens" gone; retired wording
  "discriminates all four shapes" absent repo-wide (B2 grep,
  spot-checked).
- **Fix scope is exactly as committed:** single hunk in
  test-status.sh (condition + comments); helper, extraction, pass/fail
  plumbing unchanged vs `9c4bf01`; POSIX sh continuations and `""`
  quoting well-formed under the suite's `set -e`.
- **No other consumer** of `w201_bridge` / `W201_BLOCK_BRIDGE`; no doc
  claims the bridge boundaries beyond what the code does (no docs
  change owed in this fix wave).
- **Bookkeeping:** resolution rows match the diff; review-a.md's only
  post-hoc edit is the `> Resolution:` pointer; INDEX.md row and the
  resolution's Status line correctly state this review (b) was owed.
- **Baseline:** tree clean at `55513e1`; `test-status.sh` green before
  and after all mutation runs; `make lint` and `make check-version`
  green.

## Provenance, gates, recommendation

- **Finding provenance:** W1 `fix-induced` (the overclaiming comment is
  new in `1dc553f`; the underlying 2.x-above gap predates it — a W1
  never named 2.x-above). W2 `pre-existing` (`540666c`). W3
  `delta-introduced` (the record text is new in this chain's delta).
- **Gates run:** check-host; `sh tests/unit/test-status.sh` (baseline
  green + 3 observed mutations + 1 cross-suite mutation, restored
  green after each); `make lint`; `make check-version`; full unit
  suite, reviews lint + parity, line-length ratchet after this
  snapshot was written (see commit).
- **Reviewer mechanics:** 2 fresh-context GLM-5.3-Flash subagents
  (B1/B2, ~5 min, checkpointed per section with timestamps at
  /tmp/opencode/review-pr-00209-b/); every finding re-verified by the
  main agent — W1 and W3 by observed runs, W2 by code reading; one B2
  sub-claim retracted with evidence (above).
- **Recommendation:** the a-wave dispositions are honest — a W1 and
  a W2 are implemented as claimed and the load-bearing mutation is now
  caught. A fix wave may start: address b W1 (one assertion, or soften
  the comment), amend the resolution per b W3; b W2 may be deliberately
  not done (backlog). Stop-rule note: a b-wave that only softens the
  comment and amends the resolution closes the loop (comments and
  bookkeeping are not review-relevant code); adding the 2.0.19
  assertion is test code and owes micro-wave review c.
