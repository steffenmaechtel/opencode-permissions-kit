<!-- review-meta
ID: pr-00221
Snapshot: a
Subject: issue-210 live progress for the status project-root scans (feature wave)
Scope: wave
Base: v0.0.55 @ 14050d8
Diff: 14050d8..c059409
Date: 2026-10-22
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 3x GLM-5.3-Flash reviewer subagents — axes A (shell/scan parity), B (python tee internals), C (tests + docs claims)
-->

# Wave review — pr-00221 snapshot a — issue #210 scan progress

Micro/wave pass ("did the fixes break or lie?") over the feature diff
`14050d8..c059409`: `_st_progress_tee` + `_st_ddev_scan` in
management/status.sh, the two converted scan sites (ddev share, win
hosts), the #210 test block in tests/unit/test-status.sh, and the
docs paragraph in docs/reference/cli.md. Three reviewer subagents ran
the axes above (checkpoints: `/tmp/opencode/review-221/checkpoint-{A,B,C}.md`,
experiments under `/tmp/opencode/review-221/`); the main agent
re-verified every experiment-backed finding before it entered this
snapshot. Nothing was retracted.

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified | Prov |
|---|---|---|---|---|---|---|
| W1 | MED | management/status.sh:163 | `read(1<<20)` blocks until 1 MiB or EOF — the realistic scan stream is KB-scale, so every drawn frame says "0 found" for the whole walk: the found-counter half of the feature never engages | B1 | yes (pty repro: 3 records at t=0, frames 0:00–0:02 all "0 found") | wave-introduced |
| W2 | MED | management/status.sh:153-173 | bool-flag + `sleep(1)` ticker: `t.join()` waits out the in-flight sleep → up to +1 s dead time per scan on every terminal run (2 sites × N registered roots; measured 1014 ms vs 1 ms non-tty for an instant scan), frame also lingers ≤1 s after EOF | B2 | yes (timing, 5 runs) | wave-introduced |
| W3 | MED | management/status.sh:191 | `command -v python3` accepts a present-but-broken interpreter (pyenv shim to removed version, poisoned PYTHONHOME/PYTHONPATH): tee dies at startup, the scan list comes out 0 bytes, both project-root checks go blind and the report concludes green — the 0.0.48b W2 "all green over a dead scan" class, tty runs only; the only clue is one stderr line | A1+B3 | yes (pty repro: W3-OUT-BYTES=0, run proceeds to done) | wave-introduced |
| W4 | LOW | tests/unit/test-status.sh:2372-2382 | non-tty pin cannot catch inversion/removal of the `[ -t 2 ]` gate — python's own `isatty()` is the unpinned second gate keeping behavior correct today | C1 | yes (analysis + subagent experiment) | wave-introduced |
| W5 | LOW | management/status.sh:149-151,175 | erase math counts characters, the terminal counts columns: a CJK/emoji root path (legal under `/mnt/c/Users/…` on WSL) draws wider than 76 → line wraps, erase cleans only the last physical line, residue persists | B4 | analysis (rendering not re-tested) | wave-introduced |
| W6 | LOW | management/status.sh:161-175 | Ctrl-C mid-scan prints a `KeyboardInterrupt` traceback after the ≤1 s join wait (old bare find died silently); exit signaling stays correct — display noise only | B5 | subagent experiment (main-agent repro delivered SIGINT to the shell, not python) | wave-introduced |
| W7 | LOW | management/status.sh:174-175 | SIGTERM/SIGHUP kill without `finally` → the progress frame stays painted on the tty after a killed status run | B6 | yes (incidental: killed run left the frame as the last line) | wave-introduced |
| W8 | LOW | tests/unit/test-status.sh:82,2351-2357 | extraction pin is presence-only: sed over-capture (a re-indented closing `}`) escapes the anchor greps; pins 1–3 would still red via the empty-stderr check, pty pins could stay green | C2 | analysis | wave-introduced |
| W9 | INFO | management/status.sh:195,199 | outfile write errors now surface via tr's stderr (old writer find had `2>/dev/null`) — silent→loud on ENOSPC, fail-loud direction; acceptable | A2 | yes (code read) | delta-introduced |
| W10 | INFO | management/status.sh:130-132 | comment overstates the degradation: `encode("utf-8","replace")` never yields "?" for a LANG=C tty (that shows mojibake, self-healed by rewrite+erase); "?" happens only for undecodable argv bytes | B7 | yes (code read) | wave-introduced |
| W11 | INFO | tests/unit/test-status.sh:2406-2416 | verbatim passthrough pin uses 7 bytes — below the 1 MiB chunk size, so single-chunk corruption is caught, multi-chunk reorder/accumulation bugs are invisible | C3 | yes (inspection) | wave-introduced |
| W12 | INFO | tests/unit/test-status.sh:2340-2343 | the documented NOT-pinned rc exclusion (killed find = pre-#210 parity) is sound, but the new python-death trigger on the same surface is unpinned — ties to W3 | C4 | yes (code read) | wave-introduced |
| W13 | INFO | tests/unit/test-status.sh:2360-2364 | emitter sweep is textual (matches the old variable shape only); a re-implemented bare find under other names slips it — the positive call-string pins compensate | C5 | yes (inspection) | wave-introduced |
| W14 | INFO | sh/ddev-handover.sh:521 | third `.ddev` project-root walk unconverted — judged out of scope: active chown/handover tool (not the status report the docs claim covers), exact find form pinned elsewhere | A3 | yes (code read) | pre-existing |
| W15 | INFO | management/status.sh:1049 | transient label "win hosts" vs the report row "hosts (win)" — naming split on an erased line, cosmetic | A4 | yes (code read) | wave-introduced |

Verified clean (all three axes, main-agent spot checks): find-expression
equivalence old vs new (grouping/precedence, prune+print semantics —
fixture-verified); byte parity incl. newline-in-path and LC_ALL=C
(`-print` vs `-print0 | tr` identical, `od -c` compared); `_sts_*`
namespace collision-free vs the consuming loops, `set -u`-safe;
UI_SILENT/--short gate ordering (set at :33 before both scans, reset
at :1400 after); both call sites converted, labels match the docs
format; class sweep of `name .ddev` across files/; first-frame
determinism (draw before thread start, exactly one erase per run);
BrokenPipe-on-stdout exit (rc 0, no "Exception ignored"); erase-pin
discrimination (a 40-space or deleted erase reds ` {70,}`, draw
padding can never reach 70); python3-less fallback pin really breaks
`command -v python3`; #165 harness additions necessary (the eval'd
snippets now call `_st_ddev_scan`); sandbox compliance ($WORK is
mktemp'd scratch, nothing outside scratch+/tmp); every docs claim in
cli.md carries a pin or matches the code.

## Retracted / ghost findings

None — all 18 reported findings (15 above after merging A1=B3)
survived main-agent verification.

## Run provenance

- Tree: `c059409` (clean working tree), base `14050d8` (v0.0.55).
- Reviewers: 3x GLM-5.3-Flash subagents (axes A/B/C, ~6 min each,
  checkpoint discipline per checkpoint-{A,B,C}.md); main agent
  GLM-5.3 verified W1/W2/W3/W7 experimentally, the rest by code read
  or analysis as marked.
- Gates run: `sh tests/unit/test-status.sh` — all pass, exit 0
  (incl. the 9 new #210 pins); `shellcheck` on status.sh — 0 new
  findings vs base (9 pre-existing warnings unchanged, none in the
  new range); main-agent experiments in `/tmp/opencode/review-221/`
  (counter starvation, join timing, broken-python3 pty, kill residue).
- Environment: kit-managed checkout at /var/www/opencode-permissions-kit
  (agent user), Python 3.12.3, util-linux `script` for pty capture.

## Recommendation

**Fix first** (in-wave, before merge): W1 and W2 are one-liners in
the same function (`read1(1<<20)` or a 64 KiB chunk; an
`Event.wait(1)` for the done-flag) and W1 leaves the feature's
found-counter dead in its primary scenario. W3 wants a cheap
interpreter health probe (e.g. `python3 -c 'import sys, threading,
time'` once, falling back to the bare-find branch) — it is the only
finding that can affect the verdict, and only on tty runs with a
broken python3. W4–W8 are pin-hardening follow-ups; W9–W15 are
informational. Report bytes, verdict codes and all fallback paths
are otherwise unchanged and pinned — no merge blocker beyond W1–W3.
