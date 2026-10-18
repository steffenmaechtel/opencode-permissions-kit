<!-- review-meta
ID: pr-00200
Snapshot: b
Subject: issue-166 fix wave — micro-wave review of the a-wave fix (stat -L, pins, cli.md wording)
Scope: wave
Base: v0.0.52 @ fc24e55
Diff: 9e72ea3..e563874 (fix commit; tree also carries fc24e55 — resolution/INDEX bookkeeping, outside the diff)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — fresh session per rotation; single-pass main agent, no subagents — micro wave ~74-line diff)
-->

# Review — pr-00200 snapshot b — micro-wave of the a-wave fix (e563874)

> Resolution: [resolution.md](resolution.md)

Wave question: did the fixes break or lie? Fix = e563874: status.sh
C1 gate `stat` → `stat -L` + rewritten comment; test-status.sh +4 pins
(dangling symlink, no-x-target symlink, 4400, corrupt-behind-007
compound); cli.md audience parenthetical widened. Result: **the code
fix is correct, pinned, and sabotage-discriminating; zero code
findings.** Three INFO rows below are bookkeeping/cosmetic only.

## Findings index

| ID | Severity | Site | Summary | Provenance |
|---|---|---|---|---|
| b W1 | INFO | resolution.md:58 | Stop-rule section cites the stale pre-amend SHA `88aad0d` (dangling commit, identical tree) for the fix; the dispositions table carries the correct `e563874` | delta-introduced |
| b W2 | INFO | resolution.md:43-54 | Class-sweep site list is a subset of the real `stat` population: two pre-existing no-`-L` mode reads (status.sh:477, :1038) and the `/mnt/c` family unnamed; the sweep's *conclusion* (no second any-x warn gate) holds | pre-existing |
| b W3 | INFO | docs/reference/cli.md:364 | Rewritten prose line left unwrapped (111 cols vs ~78 neighbors) — merge artifact of the 3-line replacement; pre-existing >100-col lines in the file are non-wrappable links/tables/code | delta-introduced |

No MED/HIGH. No code findings.

## Verification (main agent)

- Fix semantics, read: `stat -L -c '%a'` on the managed binary —
  regular file unchanged (deployed 750 shape: same verdicts as the
  a-wave); dangling link → stat fails → `|| true` → empty → ANYX=false
  → counted warn (old `[ ! -x ]` verdict restored); link to no-x target
  → target bits → warn; healthy link → target bits → the "sudo
  resolves it" premise of the unknown arm is valid again. Case patterns
  untouched (diff shows only the stat invocation + comments), so the
  a-wave's exhaustive 4096-mode brute force still covers them.
- Suite `sh tests/unit/test-status.sh`: green, rc=0. All 4 new pins
  PASS and execute (non-root suite user, uid 1001 — the compound pin's
  root-skip guard not hit). Harness extraction intact: the pins eval
  the sed-extracted block containing the NEW stat line (proven by the
  sabotage below, not by reading the markers).
- **Sabotage (deletion form, per AGENTS)**: `sed 's/stat -L -c/stat -c/'`
  → suite rc=1, both W1 pins FAIL printing exactly the a-W1 regression
  (`KV|opencode version|unknown — probe failed`) — the pins couple to
  the summary gate (fail-but-green excluded, L4a). Tree restored from
  the committed state, suite green again. Independently reproduces the
  resolution's red→green claim.
- Root-safety of the symlink pins, reasoned: `stat -L` on a dangling
  link fails for every user; the 644 target's no-x holds for root too —
  both W1 pins discriminate under a root-run suite (comment's claim
  checked, not just read).
- `make lint` green; `sh tests/check-host.sh` green at session start.
- e2e: not owed — render-only status.sh change, same scope call as
  snapshot a.

## Claim audit

| Claim (fix commit / resolution / comment) | Verdict |
|---|---|
| stat -L restores the loud direction for dangling/no-x-target symlinks | ✅ pinned, sabotage-verified |
| 4400: special digit grants nothing → counted warn | ✅ pin PASS |
| Corrupt content behind caller-denied mode keeps the unknown row (content-independence) | ✅ pin PASS, executed non-root |
| "4096-mode brute force re-verified … patterns unchanged" | ✅ patterns byte-identical in the diff |
| Resolution: "sabotage red→green verified post-commit" | ✅ independently reproduced |
| Resolution: "inside the existing root-skip guard" (compound pin) | ✅ sits in the 007 else-branch |
| cli.md parenthetical now matches the code's any-x rule | ✅ read-verified; "whoever the mode bits grant x" |
| Resolution: "No sibling repeats the wave's shape" | ✅ holds — but the site list was incomplete (b W2) |

## Class sweep (independent enumeration)

Pattern (ground-truth rule — not the resolution's own list):
`grep -rn 'stat ' files/ --include='*.sh'` filtered to invocations.
22 sites. Beyond the fixed status.sh:287: fs-baseline 32/38 (manifest
compare, kit-deployed regular files); ddev-handover 286/290/439/615
(%U/%A, :615 explicitly `[ ! -L ]`-gated); ddev-terminal 377/392/401
(%U probes); ddev-migrate 386/436 (%U); update.sh:882 + status.sh:944/
1100 + install.sh:909/1109/1474/2558 (fixed `/mnt/c`, `cmd.exe` paths —
never symlinks); status.sh:433/440 (ancestor report-only). Two sites
read *variable*-path modes without -L — status.sh:477 (project-root
setgid display: a symlinked root reads 777 → `& 02000` = 0 → false
"missing setgid" atten row) and status.sh:1038 (socket-reachability
heuristic: a symlink at the socket path reads world-writable →
optimistic "reachable"). Both pre-existing, both land in atten/info
rows, neither downgrades a counted warn → no code change owed in this
wave; recorded as b W2 so the next sweep starts from the full list.

## L1–L7

L1 no new fail-soft (the `|| true`/`2>/dev/null` predate; the new
failure path — stat -L on dangling — IS pinned). L2 sweep above. L3
every comment/docs claim of the wave carries a pin or survived read
audit. L4 pins discriminate (sabotage) and sit at :1373-1434, before
the summary gate; sabotage-rc=1 confirms the coupling. L5 no root
write op; the gate is a read; L5 inventory walked (trailing-slash /
parent-component forms irrelevant for a fixed kit-internal operand).
L6 this snapshot. L7 no new script.

## Gates

- `sh tests/unit/test-status.sh` — green rc=0; sabotage rc=1; restored
  rc=0 (all main agent, one machine).
- `make lint` — green. `sh tests/check-host.sh` — green.
- `sh tests/unit/test-reviews-lint.sh`, `test-reviews-parity.sh` —
  green with this snapshot + regenerated INDEX.
- Environment: WSL2/Linux review host, suite user uid 1001 non-root,
  GNU coreutils 9.4 stat, /bin/sh → dash, clean tree at fc24e55.

## Retracted/ghost findings

One, retracted during verification: "the compound pin's root-skip is
undocumented" — false on read: it rides the 007 else-branch whose
info line names the exact reason ("007 fixture cannot simulate a
caller outside the audience"); the compound pin IS a 007 shape, so the
note covers it. Not a finding.

## Provenance

b W1 delta-introduced (bookkeeping of this chain's resolution commit,
fc24e55 — outside the diff range, audited as the wave's claim record).
b W2 pre-existing sites / delta sweep-record. b W3 delta-introduced.
Run provenance: header.

## Recommendation

**GO.** The fix is exactly the snapshot-a recommendation, verified
red→green. All three INFO rows are dispositionable without touching
review-relevant code (W1: correct the SHA in resolution.md — bookkeeping;
W2: none owed, this snapshot is the record; W3: optional rewrap — docs
only). Under the stop rule a disposition round that changes only
bookkeeping/docs closes the chain: no snapshot c is owed unless code
changes.
