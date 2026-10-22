# Resolution — pr-00221 (issue #210 scan progress)

Chain: [review-a.md](review-a.md) → this wave. Dispositions below refer to
`a W<n>` = finding W<n> of snapshot a. All commits on
`feature/status-scan-progress` (birth PR #221).

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
- **W3 shape** `grep -rn 'command -v python3' files/` → status.sh:534
  (advisories: probe failure renders a loud row, not silence),
  status.sh:1329 (parser guarded by `-x` too, fail-soft display),
  install.sh:688 (install-time hard check). **Sibling found (pre-
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
