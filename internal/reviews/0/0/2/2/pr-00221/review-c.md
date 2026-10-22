<!-- review-meta
ID: pr-00221
Snapshot: c
Subject: issue-210 live progress for the status project-root scans (feature wave)
Scope: wave
Base: v0.0.55 @ 14050d8
Diff: d846ee8..d4bdb8e
Date: 2026-10-22
Reviewer: GLM-5.3 main agent + GLM-5.3-Flash fresh-context subagent — micro-wave pass, session C
-->

# Micro-wave review — pr-00221 snapshot c — the b-wave fixes

> Resolution: [resolution.md](resolution.md)

Wave pass ("did the fixes break or lie?") over `d846ee8..d4bdb8e`:
`c298b83` (pin 9 + the status.sh comment pointer + the opk:299 sweep
entry) and `d4bdb8e` (resolution rows for b W1/b W2). Both b-wave
disposition claims were re-verified against the code; the resolution's
claimed sabotage red was re-executed on the committed tree (mutate →
red → restore → green), following the snapshot-b precedent.

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified | Prov |
|---|---|---|---|---|---|---|
| c W1 | LOW | resolution.md (Class sweeps, W3 shape) | the record's line refs went stale inside the same wave that edited the bullet: `c298b83`'s +2 comment lines (status.sh:142-144) shift the recorded sites `status.sh:534`→536 and `1329`→1331, and `d4bdb8e` appended the opk:299 entry to that very bullet without refreshing them — an auditor chasing the record lands two lines off every ref. Correct when written (a-wave tree), stale in the tree the wave leaves behind | subagent1 | yes (grep on tree: 215/536/1331; `git show d846ee8` grep: 213/534/1329) | fix-induced |
| c W2 | LOW | resolution.md (Class sweeps, W3 shape + L2 addendum) | the record still does not reconcile against its own grep: `grep -rn 'command -v python3' files/` yields FIVE hits, the record lists four — status.sh:215 (the a-wave health probe at the fix site itself, pins 6/7) is unlisted, while the addendum claims the record was "completed with opk:299". Substance defensible (the fifth is in-diff code, not a silence sibling), but the bullet reads as a complete enumeration — the exact record-shape gap b W2 flagged (RM-0070) | main + subagent1 | yes (independent grep: 215/536/1331/688/opk:299) | fix-induced |

## Verified clean (both b-wave claims re-audited)

- **b W1 disposition — pin 9** (tests/unit/test-status.sh:2594-2645):
  mechanism code-read and live verified. No vacuous green: the tee runs
  FOREGROUND (default SIGINT; only the async sender inherits SIG_IGN,
  and it only sends); sender rc 0 requires a non-empty pid file AND a
  successful `kill -INT` (dead pid ⇒ kill fails ⇒ red); the kill cannot
  precede the try block — the sender polls until the tee has FORWARDED
  a byte (flush at status.sh:180, inside the try at 173-182); the
  PATH-first wrapper's `echo $$` + `exec` records the true python3 pid
  (exec preserves it). Tee behavior on SIGINT with non-tty stderr:
  `except (BrokenPipeError, KeyboardInterrupt): pass` (status.sh:181),
  draw() no-ops without a tty, thread joined in finally → exit 0,
  stderr empty — exactly what the pin asserts.
- **Sabotage re-execution** (claimed red of the b W1 fix): on the
  committed tree, `except (BrokenPipeError, KeyboardInterrupt)` →
  `except BrokenPipeError` (deletion form) — pin 9 reds ("KeyboardInterrupt
  must not print a traceback (b W1)") as the suite's ONLY failure;
  restore → full suite green (rc 0). The resolution's claim reproduces.
- **Sandbox policy**: pin 9 writes only under `$WORK` (`mktemp -d`) —
  sigbin wrapper, pid file, sender script, out/err/exp; `chmod` only on
  a `$WORK` file. No project/system trees touched.
- **Comment-vs-pin (status.sh:142-144)**: "kills the tee's python3
  mid-stream and asserts zero stderr and a clean exit" — matches the
  pin (`[ ! -s sig.err ]`, `_t210_wrc 0`; the pin additionally asserts
  byte-intact and sender rc — a subset claim, not a lie).
- **b W2 disposition — opk:299 entry**: verified against
  bin/opk:299-316 — `command -v python3 && sudo -u … python3 - <<PYEOF`
  in if/then/else; any chain failure (incl. broken interpreter) lands
  in the explicit else → `ui_error` with by-hand remediation.
  Fail-loud as recorded, not W3-class silence.
- **KeyboardInterrupt sweep claim**: independent grep → status.sh only
  (139 comment, 181 except); `sh/fs-baseline.sh`'s tee has no except
  clause, exactly as recorded (rides the recorded follow-up).
- **Sibling sweep beyond the record** (subagent axis C):
  `except Exception` heredocs (status.sh:543, update.sh:1158,
  ddev-terminal.sh:80) do not catch KeyboardInterrupt (BaseException) —
  not the swallow shape; tui-register.py:182 catches BaseException but
  re-raises after temp cleanup (fail-loud); pin 9 is the unit suite's
  only signal-sending site. No new siblings.
- **Bookkeeping**: b-wave rows use the allowed verbs, stay ≤ 120 cols,
  carry the fix SHA; L1–L7 addendum present; review-b.md untouched.

## Retracted / ghost findings

None — both subagent findings were re-verified by the main agent
against tree and history (independent grep re-run; `git show
d846ee8:…status.sh` line positions).

## Run provenance

- Tree: `d4bdb8e` (clean working tree), base `d846ee8` (snapshot b),
  branch `feature/status-scan-progress`.
- Reviewer: GLM-5.3 main agent (verification duty) + one GLM-5.3-Flash
  fresh-context subagent (axes: pin-9 correctness / claim-vs-code /
  siblings); checkpoint file with launch/checkpoint/return timestamps,
  ~3.5 min — inside the ~5-min micro budget (RM-0087).
- Gates: `sh tests/unit/test-status.sh` green (rc 0) before and after
  the sabotage cycle; sabotage red as above; `sh
  tests/unit/test-reviews-lint.sh` OK; `sh
  tests/unit/test-reviews-parity.sh` OK after INDEX regeneration for
  this snapshot.
- Environment: kit-managed checkout at /var/www/opencode-permissions-kit
  (agent user), Python 3.12.3.

## Recommendation

**No merge blocker.** Both findings are LOW bookkeeping on
resolution.md — not review-relevant code under the stop rule
(RM-0065). Closing them (refresh two line refs; one enumeration line
marking status.sh:215 as the wave's own in-diff probe, or an explicit
"4 pre-existing + 1 in-diff" count) stays in bookkeeping and closes
the loop without owing a wave d (RM-0066); deliberate-not-done
dispositions would close it too.
