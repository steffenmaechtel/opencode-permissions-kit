<!-- review-meta
ID: pr-00211
Snapshot: f
Subject: wave review of the e-wave fixes (2 production strings, 2 pin lines, ledger)
Scope: wave
Base: v0.0.55 @ ad9467d (wave base: snapshot-e commit 031fa3e)
Diff: 031fa3e..750d4e7
Date: 2026-10-22
Reviewer: GLM-5.3 main agent, fresh session (verification duty held in-session) + 3x GLM-5.3-Flash reviewer subagents — P production, T pins/tests, L ledger (checkpoints under /tmp/opencode/pr-00211-review-f/checkpoints/, LAUNCH/RETURN per axis)
-->

# Wave review — pr-00211 snapshot f — the e-wave fixes

> Resolution: [resolution.md](resolution.md)

Fresh-session pass over `031fa3e..750d4e7` (4 commits, +46/-20 across 5
files): the two one-string production fixes review-e demanded (e W2 warn
enumeration in setup-container-backend, e W3 audit WARN naming in
uninstall.sh), one pin line each, the e W1 ledger-NB correction and the
e-rows/status bookkeeping. Question per the wave contract: did the fixes
break or lie? Three reviewer subagents ran axes P/T/L; the main agent
re-verified every reported finding against the code — all 7 survived,
none retracted — and executed the pin-discrimination probes (sabotage in
a scratch copy per ~TEMP/ISSUE.md item 2c; the repo tree the subagents
read was never mutated).

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified |
|---|---|---|---|---|---|
| W1 | LOW | test-uninstall.sh:726 vs uninstall.sh:653 | the e-wave also rewrote the audit LOG line ("FAILED for /var/log/… (rm)") but the only pin on it checks the unchanged prefix `*"log: audit log removal FAILED"*` — reverting just the changed tail stays GREEN (executed); the userdel sibling :687 pins its full changed wording | T1 | yes (scratch sabotage: log-tail revert → suite rc=0) |
| W2 | LOW | uninstall.sh:480-481 vs e W3 | missed sibling site of the fixed class: the agents-backup failure WARN arm still names no failing command while every fixed sibling does (gpasswd :440, userdel :515, audit :652) — and the e-wave recorded no class sweep for W3 (RM-0069/0070) | P1 | yes (arm read in context; e-rows carry no sweep record) |
| W3 | LOW | review-e.md:51 (W1 detail table) | the e-snapshot's own provenance table claims run_q count **15 at ce7cbc5**; measured **13** (13 − 2 converted calls + 4 fix-comment mentions = 15 at 47e07f9 — the LIVE corrected NB claims 15 only there and is right); snapshot is immutable, correction vehicle is a resolution NB | L1 | yes (grep -c run_q at ce7cbc5 = 13, main-agent run) |
| W4 | INFO | resolution.md status (750d4e7) | "both e2e suites re-run green at the e-wave HEAD (303/47)" carries no tree SHA and left no artifact — exactly the anchor discipline ~TEMP/ISSUE.md item 6 demands; the claim itself is TRUE (independently re-run by this session, see provenance) | L2 | yes (claim re-executed at 750d4e7: e2e 303, rootless 47, rc=0) |
| W5 | INFO | test-uninstall.sh:724-725 | the new e W3 arm rides the aggregate c W1 check — no `e W3` label ever appears in suite output (fail path dumps `$_out`, so traceable); the e W2 pin has its own label on both arms | T2 | yes (suite output read; grep 'e W3' → empty) |
| W6 | INFO | test-container-backend.sh:452-455 | the e W2 pin substring-matches whole `$_out`, not the warn line (contrast the line-scoped `_f16_warn` grep :436) — discriminating today only because the warn is the sole emitter of the token | T3 | yes (sole-emitter check: warn :169 + test are the only sources) |
| W7 | INFO | setup-container-backend:169 | the new enumeration is complete only via two subsumptions: ≥11-digit length-gate hits (:149/:153) are "above-u32-max" by value (every 11+ digit number > 4294967295), and the `""` empty-field valve is "non-numeric" only semantically — defensible, recorded so the mapping is not read as literal | P2 | yes (all five _bad valves read at :148-155) |

Severity counts: **0 HIGH, 0 MED, 3 LOW, 4 INFO** (7 findings).

## Key finding detail

### W1 (LOW) — half of the e W3 change is unpinned

The e-wave changed TWO strings in the audit failure arm: the WARN line
(now "(rm failed)" — pinned by the new arm :725, proven discriminating)
and the log line ("audit log removal FAILED **for** /var/log/… **(rm)**"
— was "FAILED (path)"). The pin at :726 predates the wave and checks only
the prefix that both wordings share. Scratch-copy sabotage, log tail
reverted to the old wording, everything else at HEAD: suite rc=0 — the
changed tail is unobserved. The userdel harness pins its analogous log
tailing at :687 (`*"log: user removal FAILED for oc (userdel)"*`), so the
asymmetry is against the wave's own sibling. Claim-audit rule: a changed
behavior claim rides a pin or gets deleted; this one rode half a pin.
One-line fix: extend :726 to the full changed wording.

### W2 (LOW) — the e W3 class sweep is owed, not recorded

RM-0069: a fix wave sweeps the class. The class here (ISSUE item 5's
generalization): failure arms that tell the admin WHICH command failed.
The e-wave fixed the audit arm and wrote the row ("names the failing
command like its siblings") without recording a sweep. The sweep (axis
P, re-verified) finds one live sibling still unnamed: the agents-backup
arm at :480-481 — `WARNING: could not back up $_un_ag_src — its content
will be deleted with the user.` + `log "agents backup FAILED before
userdel: …"` — a compound `sudo mkdir && sudo cp` whose rc-gating exists
(:475) but whose failure text names neither command. Every other WARN
arm in the shipped tree names its command or its exact cause (linger
:198-204 retry hint, wsl arms :346/:368, teardown best-effort run_q ops
disclosed in-code). Site is pre-existing (b-wave-era), the missing sweep
is the e-wave's own output. Fix is one string + sweep record + (option)
a labeled pin; alternatively deliberately-not-done with the sweep result
recorded — then this closes as the wording wave's follow-up.

### W3 (LOW) — one wrong cell in the e-snapshot's W1 table

Review-e policed stale anchors (its W1) and its own evidence table then
miscounts the pre-fix column: run_q at ce7cbc5 is 13, the table says 15.
All four anchors the LIVE resolution's corrected NB dates are measured
true (this review re-measured at ce7cbc5/47e07f9/0885c9f/HEAD: userdel
:500→:509 unmoved by the note, audit :615→:637→:644, closing log
:598→:605 with the note :594-600 ABOVE it, counts 15@47e07f9/16@HEAD) —
the wrong cell is comparison-only, in an immutable snapshot, and nothing
downstream cites it as an anchor. Resolution-side NB is the correction
vehicle (snapshot stays as history); the irony (the anchor-police table
has a wrong anchor cell) is exactly ISSUE item 4's recurring class.

## INFO findings (compact)

- **W4** — the 303/47 status claim is true but was an unanchored
  assertion until this session re-ran both suites at 750d4e7 (rc=0 both;
  see provenance). Record tree SHA + counts when writing count claims
  (ISSUE item 6); this snapshot's provenance is now that record.
- **W5** — label asymmetry between the two new pins (e W2 labeled both
  arms, e W3 unlabeled): a future regression surfaces as a c W1-labeled
  fail with `$_out` dumped — traceable but misattributed on first read.
- **W6** — anchor-style note for the next pin author: match the token to
  the emitting line, not the whole capture; today's discrimination rests
  on an emitter count of one (verified: `above-u32-max` exists only at
  setup-container-backend:169 and in the test itself).
- **W7** — the enumeration reads as literal cause-listing; two of five
  valves map by subsumption (length→value, empty→non-numeric). Hold as
  shipped; the comment at :166-168 already names the value-cap intent.

## Retracted / ghost findings

None — all 7 reported findings survived main-agent verification. One
interim suspicion retracted during verification: the scratch-copy
baseline of `test-container-backend.sh` returned rc=1 — traced to the
two `git 100755` index-mode checks a `git archive` tree cannot satisfy
(AGENTS: exec bits live in the git index), not to any wave defect; the
real-tree run is green ("All tests passed", axis T, rc=0). Sabotage
verdicts below use base→mutation deltas, both logs on record.

## Clean verdicts — the e-wave's own claims re-verified

- **e W2 fix holds.** Every `_bad` valve maps into the new enumeration
  (valves :148-155 read; mapping via W7's subsumptions); printf
  mechanics unchanged (2× `%s`, `>&2`, same gate); the F16 fixture
  truly drives the value cap (`u32max:9999999999`, count pin = 6 forces
  the skip); the new pin executes and discriminates (warn enumeration
  reverted → the e W2 check flips PASS→FAIL, suite rc=1).
- **e W3 fix holds.** rc-gating, stderr routing and the success arm
  untouched; WARN now symmetric with the userdel/gpasswd precedent; the
  WARN pin discriminates (old wording → rc=1 at the aggregate arm). The
  log-line half is W1.
- **e W1 correction accurate.** All anchors in the corrected NB measured
  at all four refs (this review, independently of L): the narrative
  review-e demanded is now the one the ledger tells. Residual: W3's
  table cell in the immutable snapshot.
- **Ledger mechanics clean.** 7 e-rows in ID order, verbs legal, max row
  119 cols, severities match review-e's index, cited SHAs exist and
  content-match, citations `#211 e W<n>` on all three fix commits, no
  snapshot touched in-range, INDEX row `a–e | open` matches the folder
  (parity holds for f once regenerated).

## Run provenance

- Tree: working tree at 750d4e7 (branch release/0.0.55, clean before
  and after — verified); wave base 031fa3e (snapshot-e commit) over
  v0.0.55 @ ad9467d.
- Reviewer fan-out: 3 subagents (glm-5.3-flash), axes P/T/L,
  checkpoints with LAUNCH/RETURN + per-section findings under
  /tmp/opencode/pr-00211-review-f/checkpoints/ (L stamped 00:11:34Z →
  00:15:55Z sandbox clock; host-stamp at fan-out start was not captured
  — noted per ISSUE item 7, collection host-stamp below). Main agent
  (GLM-5.3) re-verified all 7 findings: in-context reads of both
  production sites + both harnesses; anchor re-measurement via
  `git show <ref>:file | grep -n/-c` at all four refs; both unit-suite
  runs cross-checked (T real-tree rc=0 ×2; scratch-copy baselines).
- **Sabotage probes EXECUTED by the main agent** (ISSUE item 2 route
  (c): scratch copy `git archive 750d4e7` under /tmp/opencode/rev-f-sab,
  repo tree never mutated while readers were in flight; restore verified
  byte-identical): (1) e W2 warn reverted to the old two-cause text →
  suite rc=1 exactly at the new pin (delta-proof; base carries only the
  two archive-artifact mode FAILs); (2) e W3 WARN reverted → rc=1 at the
  aggregate arm; (3) e W3 log-tail reverted alone → rc=0 = W1 executed.
- **E2e — the ledger claim independently re-run, not trusted**
  (RM-0082): `make e2e` **303 passed, rc=0** and `make e2e-rootless`
  **47 passed, rc=0**, both at 750d4e7 in this session, parallel,
  warm cache, opencode 1.19.3. The 303/47 status claim is TRUE and now
  carries the SHA anchor it lacked (W4). Release-gate e2e precondition
  (RM-0091) holds for this tree; any further production change before
  tagging re-owes both suites.
- Other gates at HEAD: `sh tests/unit/test-container-backend.sh` rc=0,
  `sh tests/unit/test-uninstall.sh` rc=0 (real tree), `make lint` rc=0,
  `make check-version` rc=0 (stamp 0.0.55), reviews lint green after
  the f-INDEX regen; `make test` rc=0.
- Finding provenance split: fix-induced 1 (W1), wave-introduced 5 (W2
  sweep debt, W3 in e's snapshot output, W5, W6, W7), delta-introduced 1
  (W4's unanchored status claim), pre-existing 0, unstated 0.

## Recommendation

**No defect in what the e-wave fixed — the bill is one half-pinned
string, one unswept sibling, two ledger notes.** W1 (extend pin :726 to
the full changed log wording) and W2 (name the backup arm's commands +
record the sweep, or deliberately-not-done with the sweep result) touch
test/production code — implementing either owes wave review g
(RM-0067); both are again one-string/one-pin micro waves, and per ISSUE
item 6's split (message-only changes) they gate e2e at the release
gate, not in-wave — the 750d4e7 anchor above is the comparator. W3/W4
are bookkeeping (resolution NB + SHA anchor) and close under RM-0066;
W5–W7 need no action. Severity prioritizes; only code change extends
the loop.
