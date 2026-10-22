# Resolution — pr-00221 (issue #210 scan progress)

Status: closed (maintainer, 2026-10-22) — confirmed the stop rule: the
c-round's dispositions (c W1/c W2, `9005338`) stayed in bookkeeping
(resolution.md only — no review-relevant code), so RM-0064/0066 hold.
Chain a–c: a W1..a W15 (3 MED, 5 LOW, 7 INFO), b W1/b W2, c W1/c W2 —
all dispositioned below. Recorded follow-up for a NEW case: the
fs-baseline W3-class sibling (Class sweeps below).

Chain: [review-a.md](review-a.md) → [review-b.md](review-b.md) →
[review-c.md](review-c.md) → this wave. Dispositions refer to
`a W<n>`/`b W<n>`/`c W<n>` = finding W<n> of snapshot a/b/c.
All commits on `feature/status-scan-progress` (birth PR #221).

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `45aac0d` | `read1`; pty pin "3 found, 0:01"; sabotage reds (detail) |
| a W2 (MED) | **implemented** | `45aac0d` | `Event.wait(1)`; pin min 25 ms < 700 ms, broken floor ≥ 1 s |
| a W3 (MED) | **implemented** | `45aac0d` | health probe cached in gate; pin: probe once, fallback, scans full |
| a W4 (LOW) | **implemented** | `45aac0d` | pin 6: non-tty never starts python3 (marker FILE, L1) |
| a W5 (LOW) | **deliberately not done** | — | cosmetic residue; width math disproportionate (detail) |
| a W6 (LOW) | **implemented** | `45aac0d` | `except (BrokenPipeError, KeyboardInterrupt)` (detail) |
| a W7 (LOW) | **deliberately not done** | — | signal handler in a pipeline member: cost > cosmetic gain |
| a W8 (LOW) | **implemented** | `45aac0d` | pin: `sh -n` + body markers; truncation reds (verified) |
| a W9 (INFO) | **deliberately not done** | — | tr write errors visible = fail-loud; accepted |
| a W10 (INFO) | **implemented** | `45aac0d` | comment reworded: mojibake self-heals, "?" only for bad argv |
| a W11 (INFO) | **implemented** | `45aac0d` | pin: 2.5 MB multi-chunk stream cmp-verbatim (guards read1) |
| a W12 (INFO) | **implemented** | `45aac0d` | covered by pin 7: death path executed, fallback asserted |
| a W13 (INFO) | **deliberately not done** | — | positive pins compensate; semantic pin would duplicate |
| a W14 (INFO) | **deliberately not done** | — | out of scope: active chown walk (see sweeps) |
| a W15 (INFO) | **deliberately not done** | — | transient-label cosmetic; churn not worth it |
| b W1 (LOW) | **implemented** | `c298b83` | pin 9: foreground tee + async SIGINT sender — zero stderr, byte intact, rc 0; sabotage reds (detail) |
| b W2 (LOW) | **implemented** | `c298b83` | opk:299 recorded in the W3-shape sweep above (fail-loud, benign) |
| c W1 (LOW) | **implemented** | `9005338` | refs refreshed +2 (536/1331); record re-reconciled vs grep (detail) |
| c W2 (LOW) | **implemented** | `9005338` | fifth hit listed (status.sh:215, in-diff probe); 5/5 enumerated |

## Evidence detail

### a W1 (MED) — counter starvation

`sys.stdin.buffer.read(1 << 20)` on a BufferedReader blocks until the full
1 MiB or EOF; real scans stream kilobytes, so every frame read "0 found"
for the whole walk (main-agent pty repro: 3 records at t=0, frames
0:00–0:02 all "0 found"). Fix: `read1(1 << 20)` — one call on the raw
stream, returns what is available. Pin `3c`: `( printf 'a\0b\0c\0'; sleep 2 )
| _st_progress_tee` under `script -qec`; the 0:01 frame must carry
`w1pin — 3 found, 0:01` — 1 s margin on both sides, deterministic.
Sabotage `read1`→`read` reds it (verified after commit).

### a W2 (MED) — join latency

`done` bool + `sleep(1)`: `t.join()` waited out the in-flight sleep —
measured 1014 ms for an instant scan (non-tty 1 ms), ≤ +1 s per scan on
every terminal run (2 sites × N roots). Fix: `threading.Event`; the
ticker loops `while not done.is_set(): draw(); done.wait(1)` — `set()`
wakes the wait, join returns immediately. Pin `4c`: min-of-3 instant
pty scans < 700 ms (post-fix: 25 ms; pre-fix floor ≥ 1000 ms — the full
sleep is unconditional). Marked TIMING-SENSITIVE in the test (L4b).

### a W3 (MED) — broken python3 silently blinds the scans

`command -v python3` accepts a findable-but-broken interpreter; the tee
died at startup and the consumer loop read a 0-byte list — false-green
over a dead scan (main-agent pty repro: W3-OUT-BYTES=0, run proceeded).
Fix: the tty path probes health once per run
(`_st_py_checked` caches, `_st_py_ok` carries the verdict;
`python3 -c 'import sys, threading, time'`) and takes the bare-find
branch on any doubt. Probe sits AFTER the `-t 2`/UI_SILENT checks, so
piped/--short runs never start python3 at all. Pin `7`: marker-file
shim on a pty, two scans — exactly one probe invocation, both lists
byte-identical to the reference, no live line, run finishes.

### a W6 (LOW) — Ctrl-C traceback noise

`except (BrokenPipeError, KeyboardInterrupt): pass` — SIGINT arrives in
the main thread during the blocking read; the catch routes it through
`finally` (erase happens), no traceback. Exit-status note: the tee's rc
was 130 on interrupt, now 0 — invisible to callers either way, because
status.sh runs without pipefail (a pipeline's rc is the LAST member's
alone) and the helper ends with an explicit `return 0` regardless.

### Smaller dispositions — notes that did not fit the rows

- **a W4**: the shim writes a marker FILE because the production probe
  discards its own stderr (`>/dev/null 2>&1`) — an stderr-observing
  pin proved nothing (L1: observe the way production does). Pin 7 got
  its own `rm -f "$T210_PROBE"` after sabotage-4 showed pin 6's gate
  drift seeding pin 7's invocation count (cross-pin contamination).
- **a W5 / a W7**: both cosmetic residue classes on a transient,
  erased display line; fixes (east_asian_width math / a SIGTERM
  handler in a pipeline member) add failure surface out of proportion.
- **a W8**: verified standalone — a col-0 `}` injected into the python
  block truncates the sed range; `sh -n` on the extraction exits 2,
  body markers gone → pin reds when reached (the suite also reds
  earlier via the #165 harness evals of the same broken extraction).
- **a W10 / a W13 / a W14 / a W15**: comment/pin polish and scope
  calls, fully covered by the rows above and the sweeps below.

### b W1 (LOW) — SIGINT silence pinned

Snapshot b flagged the a W6 mechanism as claimed-but-unpinned
(RM-0079). Pin 9 avoids the two known aim problems: no pty (the a W6
repro delivered SIGINT to the shell, not python) and no backgrounded
pipeline — POSIX starts async commands with SIGINT on SIG_IGN, a
non-interactive shell cannot reset an inherited-ignored signal, and
python keeps it. The first draft ran the pipeline async anyway and
passed GREEN under sabotage: the kill landed, nothing happened
(experiment-verified before the restructure — the vacuous-green
draft is the documented lesson in the pin's comment). Final shape:
the tee runs FOREGROUND with stderr to a file, a PATH-first python3
wrapper records its pid and execs the real interpreter (same pid),
and an async sender polls for the forwarded byte (the tee then sits
in read1) and kill -INTs that pid. Asserts: sender rc 0 (signal
delivered — no vacuous green), pipeline rc 0, stderr file empty (no
traceback — the claim's exact words), forwarded byte byte-equal.
Sabotage after commit: `except (BrokenPipeError, KeyboardInterrupt)`
→ `except BrokenPipeError` reds pin 9 (the traceback lands in the
asserted-empty stderr); restored, suite green. Boundary, unchanged
from snapshot b: the pty choreography of a real Ctrl-C (signal to
the foreground process group) stays unpinned — the pinned claim is
the mechanism, not the terminal dance. Sweep (L2):
`grep -rn KeyboardInterrupt files/` → only the status tee;
fs-baseline's tee has no except clause at all — rides the recorded
fs-baseline follow-up.

### c W1 / c W2 (LOW) — sweep record reconciled with its own grep

Snapshot c flagged that the W3-shape record did not reconcile:
`grep -rn 'command -v python3' files/` yields FIVE hits on the
post-`c298b83` tree — status.sh:215 (the wave's own a-W3 probe),
:536, :1331, install.sh:688, bin/opk:299 — while the record listed
four and carried the a-wave positions 534/1329 (correct when
written at `eeac08c`, shifted +2 by the b-wave's comment lines).
Fix (`9005338`): refs refreshed, the in-diff probe listed as such.
Verified by re-running the grep against the edited record — every
hit has exactly one matching ref, 5/5.

### Class sweeps (L2)

- **W1 shape** `grep -rn 'read(1 << 20)' files/` → 2 sites.
  status.sh fixed. `sh/fs-baseline.sh:105` (`_fsb_count_tee`): reads
  from a COMPLETED temp file (`<"$_fsbp_nul"`), display throttled at
  ≥ 2000 entries, final count computed at EOF — full-buffer reads only
  coarsen intermediate frames on > 1 MiB streams; forwarded bytes and
  the "— done" line are unaffected. No defect vs its contract → left
  as-is.
- **W2/W6 shapes** (`time.sleep`-ticker, `except BrokenPipeError`) →
  only the new tee. `_fsb_count_tee` has NO except clause: if the
  downstream xargs dies first, the tee ends in a traceback (pre-
  existing, cosmetic) — rides the fs-baseline follow-up below.
- **W3 shape** `grep -rn 'command -v python3' files/` → FIVE hits:
  status.sh:215 (the a-W3 health probe itself — IN-DIFF fix site,
  exercised by pins 6/7, not a pre-existing sibling; listed so the
  record reconciles with the grep, #221 c W2), status.sh:536
  (advisories: probe failure renders a loud row, not silence),
  status.sh:1331 (parser guarded by `-x` too, fail-soft display),
  install.sh:688 (install-time hard check), bin/opk:299 (openchamber
  settings-pin removal: a broken interpreter fails the `&&` chain
  into the explicit else → `ui_error` with by-hand remediation —
  fail-loud, not the W3 silence; missed on this record's first
  pass, caught by #221 b W2; refs here shifted +2 by the b-wave
  comment and refreshed, #221 c W1). **Sibling found (pre-
  existing, follow-up recommended):** `sh/fs-baseline.sh:186-189` puts
  `_fsb_count_tee` in the DATA pipeline of a MUTATING pass
  (`tee < nul | sudo xargs -0 -r sh -c 'chgrp/chmod/setfacl …'`) with
  NO python3 gate — a missing OR broken python3 kills the tee, xargs
  `-r` no-ops green, and the baseline is silently not applied (W3
  class at a root-run mutating site, higher impact than a W3). Out of
  this wave's diff and e2e-owned territory (root scripts, RM-0077) →
  recorded here for its own wave; not silently "noticed and dropped".

### L1–L7 walkthrough (this wave)

- **L1**: the new failure paths (probe miss, tee death) are executed by
  pins 2/6/7; the marker-file lesson is documented in pin 6's comment.
  Sabotage note: the probe discards its own stderr by design — a
  stderr-observing shim proved nothing until it wrote a marker FILE
  (found the hard way while verifying pin 7).
- **L2**: sweeps above; sibling recorded, not orphaned.
- **L3**: wave-touched claims re-audited — tee comment reworded (W10);
  docs/reference/cli.md claims all still true ("identical without
  python3" now covers broken python3 too — stronger, not weaker).
- **L4**: new pins sit before the summary gate; 4c marked
  timing-sensitive; every pin sabotage-verified after commit.
- **L5**: no root operands touched — the tee is unprivileged display
  code; `_st_ddev_scan`'s find semantics unchanged from snapshot a.
- **L6**: fixes bring their own pins (3b, 3c, 4c, 6, 7, 8); micro-wave
  review b owed and scheduled for the NEXT session (stop rule,
  maintainer instruction 2026-10-22).
- **L7**: no new script files; both touched files keep house form.

### L1–L7 addendum (b-wave `c298b83`)

- **L1/L4**: pin 9's failure path is executed under sabotage (the
  except-tuple red above); the wave's own vacuous-green draft became
  the documented lesson (async SIG_IGN) instead of a shipped hole.
- **L2**: `KeyboardInterrupt` sweep — no other shipped site (b W1
  detail); the W3-shape sweep record completed with opk:299 (b W2).
- **L3**: the status.sh comment claim now names its pin (b W1).
- **L5/L7**: test + comment only; no root operands, no new scripts.

### L1–L7 addendum (c-wave `9005338` — bookkeeping-only)

- **L2**: the W3-shape record now reconciles with its grep (5/5,
  refs current); the b-wave addendum's "completed" claim above is
  superseded by this reconciliation (c W2 detail).
- **L5/L7**: resolution record only — no shipped code, no root
  operands, no scripts.
- **Loop closes with this round** (RM-0066): both dispositions
  stayed in bookkeeping; no wave d owed.
