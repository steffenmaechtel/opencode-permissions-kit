<!-- review-meta
ID: pr-00200
Snapshot: a
Subject: issue-166 fix wave — status advisory C1 gate reads mode bits, not the caller's [ -x ]
Scope: wave
Base: v0.0.52 @ 99e3fd1
Diff: 99e3fd1..eed9604 (wave commit; tree also carries docs-only f75a52f — shard-rule README clarification, not review-relevant)
Date: 2026-10-19
Reviewer: GLM-5.3 (house session — main agent + 2 GLM-5.3-Flash axis subagents: mechanical/claims/pins, edge-forms/logic; every finding main-agent-verified, empirical probes re-run by the main agent)
-->

# Review — pr-00200 snapshot a — issue-166 (status C1 gate: mode bits vs caller's [ -x ])

Wave question: did the fix break or lie? Wave = eed9604 (PR #200):
`files/opencode-permissions-kit-lib/management/status.sh` (C1 gate
re-scoped to mode bits + new render elif), `tests/unit/test-status.sh`
(two pins), `docs/reference/cli.md` (exception paragraph). Old gate:
`[ ! -x "$LIBDIR/bin/opencode" ]` → counted warn. New gate:
`stat -c '%a'` + case patterns → warn only when no execute bit exists
for anyone; caller-denied-but-audience-executable renders the
uncounted unknown row.

## Findings index

| ID | Severity | Site | Summary | Provenance |
|---|---|---|---|---|
| W1 | MED | status.sh:283-287, 360-370 | `stat` without `-L` never sees the target: a symlinked managed binary reports the link's constant `777` — dangling and no-x-target shapes regress from counted warn to uncounted dead-end unknown (root included); the in-code comment claims the loud direction | wave-introduced |
| W2 | LOW | tests/unit/test-status.sh:1353-1385 | Pin deficit: symlink shapes, 4-digit special modes, and the caller-denied+corrupt compound shape carry no pins — W1 passed the suite through exactly this gap | delta-introduced |
| W3 | INFO | docs/reference/cli.md:362-363 | Audience parenthetical ("root, the opencode group") enumerates fewer audiences than the code counts (any odd digit incl. other-class) | delta-introduced |
| W4 | INFO | status.sh:351-358 | Pre-existing: group member without sudo rights on a healthy 750 binary gets "run: sudo opk status" advice that cannot resolve — unchanged by the wave | pre-existing |

Severity note on W1: the edge-forms reviewer reported the symlink
defect as HIGH (E1); the main agent confirms the mechanism empirically
but scopes it MED — the kit itself deploys a regular file at
`bin/opencode` (install/update copy; the only kit-produced symlinks
point at `bin/opencode-as-opencode` from `/usr/local/bin/`, see the
class sweep), so the shape requires external/manual state. The stop
rule reads MED and HIGH identically; both severity readings are
recorded for the calibration file.

## Verification (main agent)

- W1: **confirmed empirically, twice independently.** The main agent
  probed the symlink shapes through the suite's own sed-extracted
  gate+render blocks BEFORE dispatching the reviewer subagents; the
  edge-forms subagent reproduced the same verdicts with its own
  harness. Convergent evidence, not a single-agent claim:

  ```
  stat -c '%a', no -L:  healthy symlink -> 777   dangling -> 777
                        with -L:        healthy -> 750, dangling -> stat error
  NEW code, dangling link, sudo refused: KV|opencode version|unknown — probe failed
  NEW code, link -> 644 target:          KV|opencode version|unknown — probe failed
  OLD gate shape (absent file control):  WARN|opencode binary|missing or not executable
  ```

  For both broken shapes the elif premise fails structurally: its
  condition (ANYX ∧ ¬ADV_VER ∧ ¬[ -x ]) holds for every caller
  including root, so `sudo opk status` renders the same unknown row —
  dead-end advice over a broken kit. Old `[ ! -x ]` followed the link
  and counted a warn.
- W2: confirmed by read (no such pins exist in the touched suite).
  Compensating probe re-run by the main agent in dash: all 4096 octal
  modes through the exact case patterns vs the reference
  `m & 0o111 != 0` → **checked=4096 mismatches=0** — the digit logic
  is exhaustively correct; the gap is pins, not the patterns.
- W3, W4: confirmed by read.

## Findings detail (consolidated to one ID scheme)

ID mapping to the subagent reports: W1 = E1+E2+E3, W2 = E4 +
mechanical-W2, W3 = mechanical-W1, W4 = E5.

### W1 (MED) — symlinked managed binary defeats the re-scoped gate

`ADV_BIN_MODE="$(stat -c '%a' "$LIBDIR/bin/opencode" …)"` does not
dereference: a symlink's own mode is always `777`, so ANYX=true for
every link regardless of target. Consequences: (a) dangling symlink —
the shape the comment at status.sh:274-282 explicitly names — renders
the uncounted unknown row with advice no privilege resolves; (b) link
to a no-x-for-anyone target likewise (nobody, not even root, can exec;
old gate counted a warn); (c) the gate never reads the target's real
mode bits, so the "mode bits, caller-independent" contract is void for
symlink installs even when the verdict coincides. Trigger scenario:
`$LIBDIR/bin/opencode` replaced by a symlink (manual version-store
setup, botched swap, half-removed restore). Kit tooling never produces
the shape (see class sweep) — hence MED, not HIGH. The comment's
"dangling symlink … empty stays false — the loud direction" is
empirically false; that prose describes `stat -L`, which is also the
one-token fix: dangling → stat error → empty → loud (old verdict
restored), healthy link → target bits → root `[ -x ]` equivalence
holds again.

### W2 (LOW) — unpinned claims on exactly the defective shapes

The wave's pins cover 007 and 644 regular files. Unpinned: dangling
and no-x-target symlinks (W1's shapes), 4-digit special modes (the
comment's "special digit … deliberately not counted" claim), and the
caller-denied+corrupt compound (falls to the W1-style unknown row by
design — per the elif comment root judges it — but nothing pins it).
The 007 root-skip guard is honest (root `[ -x ]` on 007 is true →
info+skip, no vacuous pass); a symlink pin would discriminate under
root too (`stat -L` on a dangling link fails for every user).

### W3 (INFO) — docs audience enumeration narrower than code

cli.md's "(root, the opencode group — per the mode bits)" does not
enumerate an other-class x bit (e.g. a 705 manual deploy), which the
code also counts as any-x. Governing clause "per the mode bits"
keeps it truthful for the deployed 750 shape.

### W4 (INFO) — pre-existing dead-end cell, out of scope

status.sh:351-358: developer-group member without sudo rights on a
healthy binary reads "unknown — probe failed (run: sudo opk status)"
that they cannot act on. W3-of-0.0.48b precedent, untouched by this
wave; recorded for the backlog, deliberately not a wave finding.

## Claim audit (mechanical axis)

| Claim (PR #200 body / comments) | Verdict |
|---|---|
| Pins sit before the summary gate | ✅ end at :1385; tally gate at :1979-1986 |
| 007 fixture = real caller-denied simulation; root notes the skip | ✅ real stat (never stubbed), owner-class `---` vs other `rwx`; guard reachable exactly when the pin cannot discriminate |
| 644 fixture → counted warn stays | ✅ holds under root and non-root (claimed as stays-guard, not discriminator) |
| Existing C1/D1/#163 pins green | ✅ anchors and arms intact; suite green under dash |
| Missing-binary pin covers the stat fail-soft path | ✅ absent file → empty → ANYX=false → warn, exercised |
| dash-safe, no base#n arithmetic | ✅ pure case patterns; suite ran green under /usr/bin/dash |
| "dangling symlink … empty stays false — the loud direction" | ❌ **empirically false — W1** |

## Class sweep

Patterns: `\[ !?-x "\$LIBDIR/bin/opencode"` and stale old-semantics
phrases ("missing or not executable", "non-executable") across
`files/` and `docs/`. Sites checked: status.sh:323 (#163 classifier —
intentional caller-relative reachability, consistent);
status.sh:85 (`opencode-as-opencode`, deployed 755 — no caller lie
possible); update.sh:1130 (npm candidate check, root-run — root's
`-x` ≡ any-x); update.sh:1187f/install.sh:2068/browser-bridge:71
(caller-scoped or user-supplied-path contexts, correctly worded);
docs/troubleshooting.md:477, docs/concepts/wrapper.md:82 (ld.so
secure-exec, unrelated). No sibling site repeats the #166 lie; no
other site repeats W1's stat-without--L read (status.sh:283 is the
only mode-bit gate on the managed binary).

## Gates

- `make lint` — green (main agent). ShellCheck delta on status.sh
  identical to origin/master (edge agent).
- `sh tests/unit/test-status.sh` under dash — green, both #166 pins
  PASS and execute (main agent; independently re-run rc 0 by the edge
  agent, non-root suite user, root-skip guard correctly not hit).
- Empirical probes: stat A/B with and without `-L` (GNU coreutils
  9.4, ext4); suite-verbatim extracted-block harness with symlink
  fixtures — run twice independently (main agent + edge agent);
  4096-mode brute force of the case patterns — agent and main agent.
- e2e: not owed — wave touches status.sh rendering only (unit-pinned,
  outside the install/update/wrapper/backend definition-of-done set).
- Environment: review host WSL2/Linux, GNU coreutils 9.4 stat,
  sh → dash, suite user non-root.

## Retracted/ghost findings

None.

## Provenance

W1 wave-introduced (the stat call is new in this wave; the old
`[ ! -x ]` gate handled the symlink shapes correctly). W2
delta-introduced (pin gap of this wave). W3 delta-introduced. W4
pre-existing. Run provenance: header.

## Recommendation

**GO-WITH-FIXES.** The re-scope itself is correct and completely
pinned for regular files — every claim audited holds except one: the
symlink shapes. W1's fix is one token (`stat -L -c '%a'`) plus a
dangling-symlink pin and a special-mode pin (e.g. `4400` → warn) —
which also turns the false comment claim true. W2 rides the same fix.
W3/W4 are informational. Code will change → the chain owes snapshot b
per the stop rule.
