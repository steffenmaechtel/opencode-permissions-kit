<!-- review-meta
ID: pr-00209
Snapshot: c
Subject: b-wave fix diff — bridge pin shape gap + guard fail-safe pin (#209 b W1, b W2)
Scope: wave
Base: v0.0.53 @ 7f743e9
Diff: 7f743e9..c776ab2 (fix commit; 145570b is resolution bookkeeping)
Date: 2026-10-20
Reviewer: GLM-5.3 main agent (verification duty) + 2 GLM-5.3-Flash subagents (C1 pin fidelity, C2 regression/bookkeeping); checkpoints /tmp/opencode/review-pr-00209-c/
-->

# Micro-wave review — pr-00209 snapshot c — the b-wave fix diff

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Wave = `c776ab2`
(`7f743e9..c776ab2`, 1 file, +29/−4): the #201 bridge pin grew the
`2.0.19 → 1` assertion b W1 demanded (the 2.x arm's above shape), the
comment above the pin was rewritten to name its discriminators per arm,
and a new `w201_bridge_nocmp` pin evals the extracted block with no
comparator available (`unset -f` + empty `PATH`) asserting the carrier
verdict survives (b W2). `145570b` (resolution rows + b W3 amendment)
is bookkeeping, not review-relevant code, but its claims were audited
too — and are where this review's findings live.

## Findings index

| ID | Severity | Finding | Prov |
|---|---|---|---|
| W1 | LOW | b-wave sweep record overstates: "the other eval'd extracts carry no `command -v`" (resolution.md b W2 evidence; also the c776ab2 message) is literally false — the adv extract (eval'd, test-status.sh:1438) carries `command -v sudo` + `command -v timeout`, the capture extract (eval'd, :1439) carries `command -v timeout`. The substantive conclusion (no other `command -v advisories_version_cmp` site) verified true | delta-introduced |
| W2 | LOW | resolution b W2 evidence records the wrong wrapper mechanism: "it sources advisories.sh unconditionally" — sourcing is `[ -f ]`-guarded (opencode-as-opencode:186) and safety comes from `ADV_VERSION` being assigned only inside that block (:197), so the `[ -n ]` guard (:347) short-circuits when the lib is missing. Conclusion ("no sibling site") right, reason wrong | delta-introduced |
| W3 | INFO | wrapper inherited-env edge, pre-existing (ccebffb3, 2026-10-03): an exported `ADV_VERSION=1.*/2.*` plus missing advisories.sh makes the unguarded comparator an empty substitution → `!= lt` true → `_bridge_needed=0` → bridge warning suppressed (unsafe side; stderr "command not found" the only tell). Corrects C2's retracted "fails safe" sub-claim | pre-existing |
| W4 | INFO | wiring-pin citations overshoot by one line each: the version-wiring checks are 116–117 (wrapper) and 138–139 (status.sh), the resolution's "115–117 / 137–139" each drag in the preceding unrelated check's continuation line | delta-introduced |
| W5 | INFO | `unset -f advisories_version_cmp` in the nocmp pin is a defensive no-op today — the parent never defines the function (sourcing is confined to `w201_bridge`'s subshell); empty `PATH` is the operative mechanism. Deliberate hardening (becomes load-bearing if a harness ever sources advisories.sh); no action | wave-introduced |
| W6 | INFO | a version matching neither `1.*` nor `2.*` (future opencode 3.x) falls through the bridge `case` (status.sh:993–996) and keeps the carrier — safe side, no comment or pin claims that shape; owes a `3.*)` arm only when 3.x ships | pre-existing |

No MED/HIGH findings. All six are record-accuracy or backlog notes; the
wave's code itself verified clean (below).

## W1 (LOW) — sweep record: "no command -v" is false as written

The b W2 class-sweep sentence in resolution.md ("the other
extracted+eval'd blocks in test-status.sh (capture, render) carry no
`command -v`") and its commit-message twin ("the other eval'd extracts
carry no command -v") are literally false. Enumerated independently
(main agent, extracting each block with the suite's own sed ranges):

- `W48C_BLOCK_ADV` (defined test-status.sh:1270, **eval'd** at :1438)
  contains `elif command -v sudo >/dev/null 2>&1` and
  `if command -v timeout` — two availability guards;
- `W201_BLOCK_CAPTURE` (defined :1329, **eval'd** at :139 as
  `eval "${W201_BLOCK_CAPTURE:-}"`) contains
  `if command -v timeout >/dev/null 2>&1`;
- `W48D_BLOCK_RENDER` and `SUMMARY_BLOCK` (eval'd :1440/:965) are clean,
  so the parenthetical's "(capture, render)" mislabels the set on both
  counts: the one it names wrong (capture carries a guard) and the one
  it omits (adv, which carries two).

The substantive sweep conclusion survives verification — `grep -rn
"command -v advisories_version_cmp" files/` yields exactly one site
(status.sh:992), and the other extracts' guards guard sudo/timeout, not
the comparator — but the record overstates the sweep, the same error
class b W3 corrected one wave earlier. Fix: amend the resolution
sentence to what was actually swept ("no other extract carries a
`command -v advisories_version_cmp` guard"); the commit-message copy is
immutable history and stays as written.

## W2 (LOW) — wrapper mechanism recorded wrong, conclusion right

The resolution's b W2 evidence says the wrapper "uses the comparator
without an availability guard (it sources advisories.sh
unconditionally) — no sibling site". First half true
(opencode-as-opencode:349–350 call `advisories_version_cmp` with no
`command -v`), parenthetical false: the source at :188 sits inside
`if [ -f /usr/local/lib/opencode-permissions-kit/sh/advisories.sh ]`
(:186). The no-hazard conclusion still holds — but for the structural
reason the record should name: `ADV_VERSION` is assigned at exactly one
place (:197, verified by grep — no other assignment site), inside that
`[ -f ]` block, so a missing advisories.sh leaves it unset and the
`[ -n "${ADV_VERSION:-}" ]` guard at :347 short-circuits before the
comparator is ever called. The resolution is the ledger the next review
audits; fix: replace the parenthetical with the real mechanism
(conditional sourcing + `ADV_VERSION`-only-set-inside → `[ -n ]` guard
load-bearing). Bookkeeping only.

## W3 (INFO) — the wrapper's residual env-inheritance edge is unsafe, not safe

Recorded as a correction to this review's own C2 sub-claim (retracted
below): even with the W2 mechanism in place, one path to the unguarded
comparator remains — a caller-exported `ADV_VERSION` (nothing sanitizes
it) on a kit whose advisories.sh is missing. Then :347 passes, the case
arm runs, the undefined comparator yields an empty substitution, and
`[ "" != lt ]` is TRUE → the then-branch sets `_bridge_needed=0` → the
browser-bridge warning at :353–360 is suppressed. That is the unsafe
direction (a WSL host with restricted /mnt/c and an old opencode would
be told nothing), with stderr "command not found" noise as the only
tell. INFO because the preconditions are contrived (deliberately
exported uncommon variable + already-broken, loudly-warned kit) and the
block predates this chain's base (ccebffb3, 2026-10-03). Backlog note,
same family as review b's W2; no action owed this wave.

## W4 (INFO) — wiring-pin line citations overshoot by one line

The resolution's b W3 amendment cites "test-wsl-exposure.sh's wiring
pins (115–117 on the wrapper, 137–139 on status.sh)". The version-
wiring checks are exactly 116–117 (`wrapper skips the bridge warning
for open@11 versions` — the `grep -qF '1.18.33'/'2.0.18'` pair) and
138–139 (the status.sh twin). Cited line 115 is the `sh -c` continuation
of the unrelated "wrapper stays silent when the mount is restricted"
check (114–115); cited 137 likewise belongs to "status.sh points at the
opt-in bridge command" (136–137). No check is missed and the
drift-power conclusion is untouched — the ranges merely include one
neighboring line each. Fix alongside W1/W2 in the same amendment.

## W5 (INFO) — `unset -f` in the nocmp pin is presently a no-op

`w201_bridge_nocmp` (test-status.sh:1397–1405) runs
`unset -f advisories_version_cmp` although no code path defines that
function in the parent shell — the only sourcing site is inside
`w201_bridge`'s subshell (:1375), which cannot leak. The empty `PATH`
is therefore the sole operative mechanism making `command -v` fail.
Harmless and deliberate (it hardens the pin against a future harness
sourcing advisories.sh at top level — exactly the leak direction the
0.0.46a F2 class warns about); `unset -f` on a nonexistent function
returns 0 in dash and bash, so no `set -e` interaction. Recorded so the
next review reads the double lock correctly; no action.

## W6 (INFO) — 3.x fall-through keeps the carrier (safe side)

The production `case "$ADV_VER"` (status.sh:993–996) has only `1.*` and
`2.*` arms; any other shape (a future opencode 3.x, or 0.x) skips both
and `_st_bridge_unneeded` stays 0 → carrier verdict. Neither pin nor
either comment claims otherwise, so there is no claim gap; the behavior
is the safe side. A `3.*)` arm becomes owed only when upstream ships a
3.x with its own opener story. Pre-existing shape, not touched by this
wave.

## Verified clean (commit-vs-claim audit)

- **b W1's closure is real:** the `2.0.19 → 1` assertion is in the
  diff (test-status.sh:1382); M-b1 (`!= lt` → `= eq` on status.sh:995,
  the exact mutation that survived review b) now FAILs the suite —
  observed rc=1 with the extract dump; green restored after. Comment
  (:1362–1368), assertion set (:1381–1384: 1.19.0/1.18.33/2.0.19/
  2.0.18 → 1, 2.0.17/1.18.32/`""` → 0) and pass message (:1385) name
  exactly the same shapes — the b W1 overclaim class did not recur.
- **b W2's closure is real:** M-b2 (deleting
  `&& command -v advisories_version_cmp >/dev/null 2>&1` from
  status.sh:992) FAILs via the nocmp pin — observed rc=1, "bridge guard
  lost its fail-safe"; green restored after. Mechanism traced: with the
  guard gone, probes 1.19.0/2.0.18 enter their case arm, the undefined
  comparator + empty PATH yield an empty substitution, `"" != lt` is
  true → verdict 1 vs expected 0. The pinned production scenario is
  reachable (status.sh skips sourcing with a counted warn when the lib
  is missing; the version probe runs independently — C1, code-verified).
- **b W3's substance reproduced:** M2-style drift (1.18.33 → 1.18.34 at
  status.sh:994) leaves test-wsl-exposure.sh green (rc=0) while
  test-status.sh fails (rc=1) — the amended record's "wiring pins have
  no drift power" observation is real, not prose.
- **Pin mechanics sound:** sed anchor unique (extract = status.sh
  991–997 exactly; the case-line `fi ;;` are mid-line and cannot match
  `^        fi$`); the eval'd block uses only builtins, safe under the
  emptied PATH; `PATH=`/`unset -f` confined to the subshell (no leak to
  later pins or other suites); sandbox-compliant (creates/deletes
  nothing). Pin inputs (bare x.y.z triples) match the production
  normalization (`grep -oE` at status.sh:303–306).
- **Fix scope is exactly as committed:** c776ab2 touches only
  tests/unit/test-status.sh (+29/−4); 145570b only resolution.md
  (+69/−8). Dispositions table rows (SHAs, claims) match the diffs.
- **Bookkeeping:** INDEX row read "a–b | open" correctly before this
  snapshot (regenerated with it); the resolution's Status line
  ("micro-wave review c owed") is the correct stop-rule consequence of
  a test-code wave and this snapshot is that review.
- **Gates:** check-host ok; baseline `sh tests/unit/test-status.sh`
  green at `145570b`; `make lint` and `make check-version` green; full
  `make test` rc=0 (all 39 unit targets, incl. reviews lint, parity,
  line-length ratchet, sandbox policy); tree restored green after every
  mutation run.

## Retracted/ghost findings

- **C2's residual-edge sub-claim (inside its W2):** "Even the residual
  edge (inherited `ADV_VERSION` env + missing advisories.sh) fails
  safe: … `_bridge_needed` stays 1 → carrier warning kept" — retracted
  by main-agent verification: the then-branch at :349–350 sets
  `_bridge_needed=0` when the empty substitution satisfies `!= lt`, so
  that edge suppresses the warning (unsafe side). The edge itself is
  preserved as finding W3 above; only the direction claim was wrong.

## Provenance, gates, recommendation

- **Finding provenance:** W1/W2/W4 `delta-introduced` (the record texts
  are new in this chain's delta — the sentences live in `145570b`'s
  resolution, with W1's twin in the immutable `c776ab2` message; the
  W4 line ranges originate in review-b's finding text, repeated by the
  amendment). W5 `wave-introduced` (the `unset -f` line is new in
  `c776ab2`). W3/W6 `pre-existing` (wrapper block `ccebffb3`/
  `540666c`, 2026-10-03; bridge case shape predates the chain).
- **Gates run:** check-host; `sh tests/unit/test-status.sh` (baseline
  green + 3 observed mutations — M-b1, M-b2, M2-drift with the
  cross-suite wsl-exposure run — restored green after each); `make
  lint`; `make check-version`; full `make test` rc=0; reviews lint +
  parity + line-length ratchet re-run after this snapshot was written
  (see commit).
- **Reviewer mechanics:** 2 fresh-context GLM-5.3-Flash subagents
  (C1 pin fidelity, C2 regression/bookkeeping, ~5 min, checkpointed
  per section with timestamps at /tmp/opencode/review-pr-00209-c/);
  every finding re-verified by the main agent — W1 by independent
  sed-range extraction and eval-site enumeration, W2 by grep for the
  single `ADV_VERSION` assignment + blame, W3 by code reading of
  :346–352 (one C2 sub-claim retracted with evidence), W4 by reading
  the cited lines, W5/W6 by code reading; the mutation runs are the
  main agent's own observations.
- **Recommendation:** the b-wave's code is honest — both closures are
  real, the load-bearing mutations fail the suite, nothing shipped
  changed behavior, and the full suite is green. Every finding is a
  record-accuracy item in resolution.md (W1, W2, W4 — one amendment
  pass) or a backlog note (W3, W6) or needs no action (W5). Stop-rule
  note: a c-wave that only amends resolution.md touches no
  review-relevant code — after its dispositions, the loop closes
  without another review round.
