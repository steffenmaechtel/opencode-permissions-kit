<!-- review-meta
ID: pr-00211
Snapshot: g
Subject: micro wave review of the f-wave fixes (backup-arm strings + pins, ledger)
Scope: wave
Base: v0.0.55 @ ad9467d (wave base: f-rows commit 79582d9)
Diff: 750d4e7..79582d9
Date: 2026-10-22
Reviewer: GLM-5.3 main agent, fresh session — solo pass, no fan-out (disclosed as g W4); verification duty held in-session; sabotage executed in scratch copies (ISSUE item 2c)
-->

# Wave review — pr-00211 snapshot g — the f-wave fixes (micro wave)

> Resolution: [resolution.md](resolution.md)

Diff reviewed: `750d4e7..79582d9` (5 commits; review-relevant code:
uninstall.sh +4/−2, test-uninstall.sh +41/−2 — 49 lines, micro scope;
the rest is ledger/INDEX bookkeeping). Question per the wave contract:
*did the fixes break or lie?* Axes carried the ~TEMP/ISSUE.md learnings
(items 2, 3, 4, 5, 6, 10 explicitly checked).

## Findings index

| ID | Sev | Location | One-line summary | Provenance |
|---|---|---|---|---|
| g W1 | LOW | resolution.md f W2 sweep (sites list) | sweep anchors stale by restatement: cites review-f's 750d4e7 numbers (:515/:652/:480) — the f-wave's own +2-line insertion moved them to :517/:654/:482-483 at the sweep's commit `2be6fc3` — exactly ISSUE item 4's class, in the same wave that corrected the e-table's identical error (f W3) | wave-introduced |
| g W2 | LOW | resolution.md f W2 sweep (pattern line) | the recorded pattern (`grep 'WARN'` over `management/*.sh` + `bin/*`) cannot re-derive its tree-wide result "zero unnamed rc-gated failure arms remain in the shipped tree": it sees neither the `ui_warn` emitter class (lowercase, ~50 sites in install.sh/management/sh) nor `files/install.sh` nor the `sh/` printf arms. Result independently confirmed TRUE (see clean verdicts) — the record, not the code, is the defect (RM-0070/0082) | wave-introduced |
| g W3 | INFO | test-uninstall.sh F2 harness | `F2DRY` is a dead knob (no drive sets it) and the loop's ok/dry arms are unpinned — fail-only scope is a defensible choice for a strings pin, but unlike the c W1 sibling harnesses (ok/fail/dry) it is not recorded as deliberate | wave-introduced |
| g W4 | INFO | run provenance | this g pass ran solo-main-agent, no reviewer fan-out — RM-0084 prefers fan-out for every review; disclosed rather than hidden (the f review used 3 subagents) | unstated (process) |

Severity counts: **0 HIGH, 0 MED, 2 LOW, 2 INFO**.

## Key finding detail

### g W1 (LOW) — the sweep's anchors describe the tree the fix changed

Measured (this review, `git show <ref>:… | grep -n`): gpasswd WARN :440
at 750d4e7, 2be6fc3 **and** HEAD (above the insertion, correct); userdel
WARN :515 → **:517**; audit WARN :652 → **:654**; backup arm :480-481 →
**:482-483**. The resolution's sweep — written at/after `2be6fc3`, the
commit that inserted the two comment lines causing the shift — repeats
review-f's pre-fix numbers for three of four sites. Nothing downstream
cites these cells as anchors and the sweep's *verdicts* (✓/FIXED) are
all correct at every ref; the defect is record-accuracy only. A
correction NB (measured numbers, or content anchors — "WARN: could not
remove user", grep-able) closes it; bookkeeping-only per RM-0066. The
irony writes itself: f W3 corrected e's table for the identical
restatement class one commit earlier.

### g W2 (LOW) — the sweep's method doesn't cover its claim

RM-0070: the sweep is recorded "so the next review can audit it." A next
auditor re-running the recorded pattern gets the same four files and
misses: (a) all `ui_warn` call sites — `ui_warn` contains no uppercase
`WARN`, and the emitter classes split across raw `WARN`
(uninstall/setup-container-backend), `ui_warn` (install.sh +
management/*.sh + sh/git-check.sh), `note()` rows (opencode-as-opencode)
and bare `printf` WARNINGs (sh/ddev-handover.sh, sh/fs-baseline.sh,
sh/staged-write.sh, sh/ddev-migrate.sh); (b) `files/install.sh` (outside
the glob); (c) `sh/` entirely. My independent enumeration of all four
classes found **no unnamed rc-gated failure arm** — every ui_warn arm
names its operation or exact cause (e.g. install.sh:1460 "could not
write /etc/sysctl.d/99-ddev-rootless.conf", update.sh:1318-1319
explicitly designed around the class, fs-baseline.sh:77 "(setfacl failed
— ACL support?)"). So the shipped-tree claim stands; the record should
either name the full pattern set or scope the result to the pattern's
coverage.

## INFO findings

- **g W3** — the F2 harness stubs mkdir/cp to fail (L1 ✓, the changed
  strings' arm) but defines `F2DRY` that no drive ever sets, and neither
  the ok arm nor the block's `[DRY]` echo is pinned (the c W1 harnesses
  pin ok/fail/dry). Consistent with f W6's accepted sole-emitter/
  substring conventions otherwise. One disposition sentence ("fail-only
  by design") suffices, or drop the dead knob.
- **g W4** — solo shape. Micro scope (49 code lines, one production
  hunk, one pin block) plus execution-heavy verification made this
  defensible, but it is a deviation from the preferred shape and is
  disclosed here per the ISSUE item 1/7 honesty push; the maintainer may
  re-run an independent pass if redundancy is wanted before tag.

## Clean verdicts — the f-wave's own claims re-verified (executed, not trusted — RM-0082)

- **f W1 fix holds.** Pin :726 extended to the full changed wording
  (matches production :655 exactly). Sabotage re-executed in a fresh
  scratch copy: audit log tail reverted alone → suite **rc=1, red
  exactly at the aggregate CW1 arm** (log: /tmp/opencode/rev-g-s1/
  sab.log); committed baseline rc=0.
- **f W2 fix holds.** Production change verified message-only (2 strings
  + 2 comment lines — no rc, branch, or routing change); extraction
  anchor unique (1 hit, measured); stub coverage complete for every
  command the extracted block issues (test/ls/mkdir/cp; `id`
  unreachable in the else arm); pin sits before the summary gate (L4);
  **labeled** on both arms (unlike e W3's label gap, f W5). Sabotage
  re-executed: both `(mkdir/cp)` tails deleted → **rc=1, red exactly at
  the new f W2 check** (log: /tmp/opencode/rev-g-s2/sab.log).
- **f W3 accurate.** All three counts re-measured: `grep -c run_q` =
  **13** @ce7cbc5, **15** @47e07f9, **16** @HEAD — the NB's numbers and
  arithmetic hold.
- **f W4 in place.** Status line SHA-anchors the 303/47 claim at
  `750d4e7`; no new count claims without anchors appeared in-range.
- **ISSUE item 10:** no closure claim anywhere in-range — "status open —
  g owed (RM-0067)" is exactly right.
- **ISSUE item 6:** the e2e split decision is recorded in the f W2
  detail (message-only → release gate); the change qualifies. Not re-run
  this session (no production behavior change since `750d4e7`; any
  change before tagging re-owes both suites).
- **Process mechanics:** review-f.md touched by exactly one commit
  (snapshot immutability ✓, pointer line present ✓); snapshot committed
  before the fixes (hard seam ✓); branch `release/0.0.55`, tree clean
  before and after; f-rows in ID order, legal verbs, severities match
  review-f's index, cited SHAs exist and content-match, all rows ≤120
  cols; INDEX row `a–f | open`, parity green.

## Run provenance

- Tree: `79582d9` (branch `release/0.0.55`, clean before and after; all
  mutations in `/tmp/opencode/rev-g-*` scratch copies — ISSUE item 2
  route (c), solo session, no readers in flight).
- Reviewer: GLM-5.3 main agent, fresh session, verification duty held
  in-session, **no fan-out** (g W4). Host stamp at run end:
  2026-10-22T00:35:58Z (ISSUE item 7: solo pass, no subagent clocks to
  normalize).
- Gates at HEAD: `make test` rc=0 ("All shell tests passed" — includes
  reviews-lint/INDEX parity; first full-suite record at HEAD, the
  ledger's prior record was `750d4e7`), `sh tests/unit/test-uninstall.sh`
  rc=0, `make lint` rc=0, `make check-version` rc=0 (0.0.55).
- Finding provenance split: wave-introduced 3 (W1, W2, W3), unstated 1
  (W4), fix-induced 0, pre-existing 0.

## Recommendation

**No defect in what the f-wave shipped — both fixes hold under
execution.** The bill is two ledger records: g W1 (correction NB with
measured anchors — the exact move f W3 just made) and g W2 (record the
full pattern set or narrow the claim). Both are resolution-bookkeeping-
only: their disposition touches no review-relevant code, so after their
disposition the stop rule (RM-0064/0066) is for the maintainer/next
round to confirm — this review does not declare closure (ISSUE item 10).
g W3/W4 need no code action (one disposition sentence each). No e2e owed
in-wave (message-only changes, comparator 303/47 @ `750d4e7`); the
release gate re-runs both suites before tagging regardless (RM-0091).
