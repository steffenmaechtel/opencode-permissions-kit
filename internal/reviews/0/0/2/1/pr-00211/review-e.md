<!-- review-meta
ID: pr-00211
Snapshot: e
Subject: wave review of the c-wave fixes + d-round bookkeeping (rotation-deviation catch-up, fresh session)
Scope: wave
Base: v0.0.55 @ ad9467d (wave base: snapshot-c commit ce7cbc5; range includes the d-round through a6f2705)
Diff: ce7cbc5..a6f2705
Date: 2026-10-22
Reviewer: GLM-5.3 main agent, fresh session per the rotation-deviation follow-up (verification duty held in-session) + 3x GLM-5.3-Flash reviewer subagents — P production, T pins/tests, L ledger/bookkeeping (checkpoints under /tmp/opencode/pr-00211-review-e/checkpoints/, LAUNCH/RETURN per axis)
-->

# Wave review — pr-00211 snapshot e — c-wave fixes + d-round bookkeeping

> Resolution: [resolution.md](resolution.md)

Fresh-session pass over `ce7cbc5..a6f2705` (14 commits, +493/-28 across 15
files: 5 production, 6 test suites, ledger/snapshots/INDEX), executing the
resolution's rotation-deviation instruction: snapshot d ran in the c-wave's
own session (RM-0060/0061), so d is treated here as a lead — its clean
verdicts (P/T/L axes) were re-verified independently, not taken as done.
Three reviewer subagents ran axes P/T/L; the main agent re-verified every
reported finding against the code before it entered this snapshot — all 7
survived, none retracted.

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified |
|---|---|---|---|---|---|
| W1 | MED | resolution.md:226-230 (d W2 NB) | the d W2 dating note misstates the history it polices: :500/:615 are the PRE-fix positions (at `47e07f9` the calls already sit at :509/:637), the in-code note sits ABOVE the closing log (only thus can shift it :598→:605), userdel's :509 predates the note, and audit-rm :615→:644 is a two-step jump compressed into one note-attributed hop — every HEAD-facing value is correct, the provenance narrative is false: the exact "claim true, history false" shape d W1 policed | L1 | yes (git show at ce7cbc5 / 47e07f9 / 0885c9f / HEAD, all four anchors re-measured) |
| W2 | LOW | setup-container-backend:166-167 | the malformed-skip warn still enumerates only "(non-numeric or leading-zero ranges)" — a line skipped by the new c W9 value cap (e.g. `u:5000000000:1000`) is neither, so the diagnostic misdescribes the skipped line to the admin auditing /etc/subuid | P1 | yes (message byte-identical to wave base; caps added in-range) |
| W3 | INFO | uninstall.sh:515 vs :650 | wording asymmetry between the two new WARN arms: the userdel arm names the failing program (`(userdel failed)`, gpasswd precedent), the audit arm gives only the path without naming the command | P2 | yes (both arms read in context) |
| W4 | INFO | test-update-flags.sh:1034-1040 | the c W3 order pin's multi-match loudness surfaces as a test-builtin "integer expression" error inside the if-condition (rc 2 → fail branch), not a formatted assert — loud, cosmetic | T1 | yes (mechanism reproduced live) |
| W5 | INFO | test-uninstall.sh extractable gates | d's "truncation fails loud at the extractable gate" is imprecise: a de-indented inner fi yields a non-empty PARTIAL extract that passes the `[ -n ]` gate — loudness comes from the downstream drive asserts (unterminated if → eval syntax error → empty output → ok-drive red). Net red-not-silent holds | T2 | yes (both extract/eval paths traced) |
| W6 | INFO | test-uninstall.sh DRY-arm asserts | the two "dry run: [DRY] echo + success lines" asserts cannot distinguish fixed from reverted rc-blind production (both print success in DRY) — they are convention pins by design; the c W1 discrimination rests on the rc=1 fail drives, which do discriminate (verified + executed, see provenance) | T3 | yes (both shapes traced in DRY mode) |
| W7 | INFO | commit c8069f7 (subject) | the d-round's "loop closes in bookkeeping (RM-0066)" subject survives in immutable history next to its own retraction (a6f2705) — retraction reasoning is recorded consistently in all three loci (commit body, status paragraph, Follow-ups); audit-trail note only, no live-text lie | L2 | yes (all three loci compared; no closure claim in live text, INDEX open) |

Severity counts: **0 HIGH, 1 MED, 1 LOW, 5 INFO** (7 findings).

## Key finding detail

### W1 (MED) — the d W2 fix text is wrong about the history it documents

The d-round corrected d W2 (aged anchors) by dating the c W1 sweep
evidence "as of the fix commit `47e07f9`". Measured at all refs:

| anchor | ce7cbc5 (pre-fix) | 47e07f9 (fix) | 0885c9f→HEAD (note) | NB text claims |
|---|---|---|---|---|
| userdel call | :500 | **:509** | :509 (unmoved — note sits ~85 lines below) | ":500 … note shifted userdel to :509" |
| audit rm | :615 | **:637** | :644 (note IS above it: +7) | ":615 … note shifted audit rm to :644" |
| closing log | :598 | :598 | :605 (note above it) | ":598→:605" (this one holds) |
| run_q count | 15 | 15 | 16 | "15 at fix commit, 16 at HEAD" (holds) |

So: the two op-line anchors the NB dates to the fix commit are the
PRE-fix positions review-c cited (the wave-introduced staleness d W2
was fixing); at `47e07f9` they already sit where HEAD has them. The
note's placement is misstated too — it is inserted after `chmod g-s`
(:593), ABOVE the closing log (that is precisely why the log moves
:598→:605; a note below it could not), and it cannot shift userdel at
all. What survives: every HEAD-facing value, the :560/:590-591/:593
op anchors at both refs, both counts, single-file. No reader is
misled about today's file — the false part is the provenance
narrative in the live resolution (fixable there; review-d.md is an
immutable snapshot and stays as history). Provenance: fix-induced
(introduced by the d-round's own fix `35d5549`, propagating
review-d.md's W2 wording; the underlying staleness wave-introduced
by `0885c9f`). Direction: correct the NB paragraph in resolution.md.

## LOW/INFO findings (compact)

- **W2** — the value cap was added without sweeping the one message
  that enumerates rejection causes (the L2 message-class sweep the
  house runs on gates). The skip itself is correct (u32-over entries
  are broken anyway — c W9's rationale holds); only the diagnostic
  lags. One-line fix in the printf enumeration, or disposition
  deliberately-not-done with a follow-up note. Wave-introduced.
- **W3** — cosmetic drift between sibling arms added in the same
  commit; both fire on the same triggers (stderr WARN + FAILED log,
  gated on rc). Naming `rm` in the audit arm would match the
  precedent. Wave-introduced.
- **W4** — the pin cannot silently pass on ambiguity (zero-match is
  `-n`-guarded; multi-match errors the test builtin → false → fail
  branch records). Recording so the next pin author knows the loud
  path is an error message, not an assert. Wave-introduced.
- **W5** — the extractable gates check non-emptiness, not
  completeness; completeness is enforced de facto by the drive
  asserts. d's snapshot phrasing overstates the gate's role — noted
  so the phrasing is not cited as precedent. Pre-existing extraction
  pattern, wave-extended.
- **W6** — DRY asserts pin the file's run/run_q DRY convention
  (reported-intent semantics); the regression discrimination lives in
  the rc=1 fail drives. Not vacuous (a broken DRY branch trips them).
  Wave-introduced, by design.
- **W7** — history cannot be rewritten and need not be; the retraction
  is complete and mutually consistent. Recorded so a future
  `git log --grep RM-0066` reader finds the pairing. Wave-introduced
  (the d-round's own output).

## Retracted / ghost findings

None — all 7 reported findings survived main-agent verification. (One
main-agent interim doubt — d's "gate deleted → residue 1" W7 trace,
initially assessed as wrong — was resolved IN d's favor: the shell
performs the redirection before calling the stubbed printf, so the
temp is created even on a stubbed write failure; the executed
sabotage confirmed rc 0 / residue 1 / no UIERR exactly as d reasoned.)

## Clean verdicts — d's verdicts re-verified under the rotation mandate

- **P axis — ALL HOLDING.** c W1: rc capture in plain assignments in
  `||` lists, abort-proof (no `set -e` in the file); arms byte-shaped
  like the gpasswd precedent (:429-446); DRY arms byte-match run_q's
  `[DRY]` rendering; the in-code NB note matches the Follow-ups
  record; no new unconditional success claim. c W2: capture on the
  prologue line (:143), consumed only at the refusal (:159),
  normalization loop untouched. c W3: pure reorder; `_tmp_track`
  (:56) is a registry append; the trap's `rm -f` tolerates absent
  paths. c W7: `ui_error` unconditional at :37; main-shell case body
  so `exit 1` is correct; gate catches redirect AND write failures;
  chown/chmod/mv only reachable on write success. c W9/W10: caps
  reachable only for digit-only ≤10-digit fields; live dash matrix —
  0/65536/100000/4294967295 accept, 4294967296/9999999999
  cap-reject, 01000/11-digit/empty pattern-reject; `start+count` ≤
  8589934590, no overflow; zero-start acceptance predates the wave
  (b-wave gate; c W10 is documentation-only — accurate).
- **T axis — ALL HOLDING.** Extraction anchors unique (userdel anchor
  1 match, extract :444-523, first col-0 fi terminates; audit anchor
  1 match, :635-656); run_q stub byte-equivalent to the real contract
  (:174-180); fail drives assert WARN + FAILED log + absence of the
  false claim (three-case shape both drives); W3 order pin
  zero/multi-match loud (W4's cosmetics aside); W7 pin not vacuous —
  now EXECUTED, see provenance; W4 tripwire effective (summary gate
  `[ -s "$TMP" ]` → exit 1; mirrors the W28 sibling); W5 `|| true`
  contains the substitution rc under `set -e`, state read in-subshell;
  sandbox clean throughout; all pins before their summary gates; dash
  `VAR=val func` sequencing live-checked.
- **L axis — ALL HOLDING** (with W1 above as the new, corrected
  record). 11 c-rows + 3 d-rows, ID order, ≤120 cols (max 120); all
  cited SHAs exist in-range and content-match (c W6→`0885c9f` carries
  the wording fix; d W1→`35d5549` flips bc56a17→0885c9f; c W9/W10→
  `9ac107c` carries caps + comment + fixture); d-round commits touched
  only internal/reviews/ ("stayed in bookkeeping" holds including the
  snapshot commit); `git diff aac8d67..HEAD -- files/` non-empty (5
  files) — the e2e-debt claim held; snapshot immutability intact
  (review-c.md +2 pointer only; review-d.md committed once, never
  edited; review-a/b untouched); every fix/test commit cites its
  `#211 c W<n>`/`d W<n>`; not-done rationales consistent with the
  snapshots; `grep 'if run_q' files/` = 0; INDEX row matches the
  folder, generator idempotent at HEAD (main-agent run, tree clean).

## Run provenance

- Tree: working tree at a6f2705 (branch release/0.0.55, clean); wave
  base ce7cbc5 (snapshot-c commit) over v0.0.55 @ ad9467d; d-round
  bookkeeping commits (edb6fcb, 35d5549, c8069f7, a6f2705) inside the
  reviewed range and themselves reviewed here.
- Reviewer fan-out: 3 subagents (glm-5.3-flash), axes P/T/L,
  checkpoint side files with per-section findings + LAUNCH/RETURN
  lines under /tmp/opencode/pr-00211-review-e/checkpoints/ (windows as
  stamped by the agents: P 23:43-23:48, L 23:43-23:51, T 23:43-23:52
  UTC; host file mtimes run ~2h ahead of the sandbox clock — noted,
  the checkpoints are the evidence base either way). Main agent
  (GLM-5.3) re-verified all 7 findings (git show at four refs for W1;
  boundary matrix + message text for W2; in-context reads for W3/W5/
  W6; live multi-match probe for W4; three-loci comparison for W7);
  0 retractions.
- **Sabotage spot-checks EXECUTED by the main agent** (RM-0082 — d
  had reasoned W7 through without executing): (1) opk staging gate
  deleted in-place → `sh tests/unit/test-update-flags.sh` RED at the
  c W7 pin with rc=0/residue=1/no-UIERR — exactly d's traced
  expectation; (2) both uninstall rc-captures deleted →
  `sh tests/unit/test-uninstall.sh` RED at both c W1 failure pins;
  restored → green both. Tree verified clean at a6f2705 before and
  after.
- **Contamination screen (process note):** the two sabotage windows
  ran while the subagents were in flight — a shared-read substrate
  hazard the AGENTS.md sabotage procedure does not cover. Screen
  applied to all three reports: L read no production code at all; P
  and T's verdicts on the mutated constructs are text-anchored to
  lines that existed only in the clean tree (the gate + its comment,
  the `|| _rc=$?` captures); no finding matches a sabotage shape.
  Host mtimes additionally suggest the reader windows began after the
  restore. No re-run needed; recorded for the audit trail.
- Gates run on this host during this review: `make test` rc=0
  (incl. reviews parity), `make lint` rc=0, `make check-version` rc=0
  (stamp 0.0.55), **`make e2e` 303 passed rc=0 and `make e2e-rootless`
  47 passed rc=0** at a6f2705 — the standing e2e debt the status line
  carried (RM-0077/0091, named by c W11 and d's provenance) is
  discharged in this session; both counts now carry a fresh external
  anchor. The release gate's e2e precondition holds for this tree;
  any further production change before tagging re-owes both suites.
- Finding provenance split: wave-introduced 5 (W2, W3, W4, W6, W7),
  fix-induced 1 (W1 — the d-round's own fix output), pre-existing-
  pattern-wave-extended 1 (W5), unstated 0.

## Recommendation

**Ledger-only round closes the loop; two production strings are the
maintainer's call.** No production or test mechanism defect: every
c-wave fix held up under re-verification, all of d's clean verdicts
survived the fresh-session mandate (d's substance was right — what
the rotation missed was in d's own fix text, W1, and one unswept
message, W2). Disposition W1 as a resolution-text correction
(bookkeeping; the loop-closing round per RM-0066 if nothing else
touches code); W4-W7 need no action. W2 and W3 are one-string
production edits: fixing them owes a micro-wave (snapshot f) and,
per RM-0077's letter, re-runs the e2e suites after a just-discharged
baseline — the corpus precedent (c W2 fixed in-wave) argues for
fixing, the release-calendar cost argues for a recorded follow-up
riding the next code wave. Severity prioritizes; only code change
extends the loop.
