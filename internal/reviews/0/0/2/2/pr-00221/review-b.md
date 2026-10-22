<!-- review-meta
ID: pr-00221
Snapshot: b
Subject: issue-210 live progress for the status project-root scans (feature wave)
Scope: wave
Base: v0.0.55 @ 14050d8
Diff: 6f9e226..eeac08c
Date: 2026-10-22
Reviewer: GLM-5.3 main agent — micro-wave pass (verification duty in-session, no subagents; RM-0087 micro shape)
-->

# Micro-wave review — pr-00221 snapshot b — the a-wave fixes

> Resolution: [resolution.md](resolution.md)

Wave pass ("did the fixes break or lie?") over the fix diff
`6f9e226..eeac08c`: `45aac0d` (status.sh fixes a W1/a W2/a W3/a W6 +
pins 3b/3c/4c/6/7/8 in test-status.sh) and `eeac08c` (resolution.md,
review-a pointer, INDEX row, one test-isolation line). The requested
range `45aac0d..eeac08c` is read INCLUSIVE of the fix commit — the
stop rule (RM-0067) owes this review the fixes themselves, not only
the resolution bookkeeping. Every a-wave disposition claim was
re-verified against the code; all five claimed sabotage reds were
re-executed on the committed tree (mutate → red → restore → green).

## Findings index

| ID | Sev | Location | One-line summary | Reported by | Verified | Prov |
|---|---|---|---|---|---|---|
| b W1 | LOW | resolution.md (a W6 row) / status.sh:139-142 | the a W6 mechanism (KeyboardInterrupt swallow, "Ctrl-C stays silent like the bare find") is dispositioned implemented with NO behavioral pin — no suite test executes any SIGINT path; RM-0079/L6 (0.0.44d F4 class: the wave's own mechanism unpinned). A `kill -INT` on the tee's python3 pid mid-`read1` (non-pty) pins the traceback half cheaply | main | yes (pins 3b–8 enumerated: none signal the tee; mechanism itself code-read verified) | fix-induced |
| b W2 | LOW | resolution.md (L2 sweep, W3 shape) | the recorded sweep is incomplete: `grep -rn 'command -v python3' files/` has FOUR pre-existing sites, the resolution lists three — `bin/opk:299` (openchamber settings-pin removal) is missing from the record. Site itself verified BENIGN: a broken python3 lands in the explicit else → `ui_error` with by-hand remediation (fail-loud, not W3-class silence) — an audit-trail gap (RM-0070), not a shipped defect | main | yes (grep + opk:290-310 read) | fix-induced |

## Verified clean (all a-wave claims re-audited)

- **a W1** `read1(1<<20)` present (status.sh:173); pin 3c green;
  sabotage `read1`→`read` re-executed → pin 3c reds ("counter
  starved"). Claim "3 found, 0:01" frame repros deterministically.
- **a W2** `threading.Event` + `done.wait(1)` (164-166); pin 4c green
  at min 23 ms of 3 (claimed ~25); sabotage `wait(1)`→`sleep(1)`
  re-executed → pin 4c reds at min 1026 ms (claimed floor ≥ 1 s).
  TIMING-SENSITIVE marker present (L4b).
- **a W3** health probe cached in the gate (`_st_py_checked`/
  `_st_py_ok`, 210-217), probe after the UI_SILENT/`-t 2` checks —
  piped/--short runs never start python3 (pin 6 green, marker FILE
  per L1); pin 7 green: probe exactly once across both scans, both
  lists byte-identical, no live line. Two sabotages re-executed:
  probe neutered → pin 7 reds; gate-1 `-t 2` dropped → pin 6 reds.
- **a W6** mechanism present: `except (BrokenPipeError,
  KeyboardInterrupt)` (179), `finally` erase (181-185); all three
  supporting facts code-read verified — status.sh is `set -u` ONLY
  (no pipefail), `_st_ddev_scan` ends `return 0` (228), so the tee's
  rc is invisible either way. Only the missing pin is flagged (b W1).
- **a W8** pin 8 (sh -n + `def draw`/`def ticker`/`read1` markers)
  green; col-0 `}` injected before `def ticker` re-executed → the
  suite reds via the #165 harness evals of the truncated extraction,
  exactly as the resolution records ("pin reds when reached … reds
  earlier").
- **a W11/a W12** pin 3b (2.5 MB > 2×1 MiB chunks, cmp verbatim +
  empty stderr) green; pin 7 executes a python death (the shim probe,
  exit 9) and asserts the fallback — the W12 disposition holds.
- **Class sweeps**: W1 shape — `read(1 << 20)` now only
  fs-baseline.sh:105, reading a COMPLETED temp file (`<"$_fsbp_nul"`),
  display-only coarsening — left-as-is rationale verified accurate.
  W3 shape at fs-baseline.sh:186-189 verified real and as described:
  `_fsb_count_tee` feeds `sudo xargs -0 -r` in a mutating pass with
  no python3 gate — the recorded follow-up wave is justified (it is
  the higher-impact W3 sibling; pre-existing, out of this wave's
  diff). Ungated python3 uses elsewhere (ddev-terminal.sh:72,
  tui-plugin.sh:68, uninstall.sh:316, update.sh:1154) are documented
  kit-prerequisite sites that fail loud — no further siblings.
- **eeac08c test line** `rm -f "$T210_PROBE"` — correctly placed
  between pins 6 and 7, removes pin 6's sabotage-induced marker so
  pin 7's invocation count stays attributable; `$T210_PROBE` defined
  at pin 6.
- **Bookkeeping**: review-a.md edit is exactly the one pointer line
  (rule 1); resolution dispositions use the three allowed verbs, rows
  ≤ 120 cols, carry SHAs; INDEX parity test green after regeneration
  for this snapshot; `script` (pty) is check-host required, so the
  new pty pins inherit the managed environment dependence.
- **L3** docs/reference/cli.md:356-358 ("scans run identically
  without python3") remains true and is strengthened by the probe —
  no drift. **L4a** all six new pins sit before the summary gate.
  **L5** no root operands touched (display code only; find semantics
  unchanged from snapshot a). **L7** no new scripts; probe gate
  follows the `_st_` prefix family, `set -u`-safe (`${_st_py_ok:-0}`).

## Retracted / ghost findings

None — no subagent findings to cross-cancel; both findings above are
main-agent-reported and re-verified against the code.

## Run provenance

- Tree: `eeac08c` (clean working tree), base `6f9e226` (snapshot a).
- Gates: `sh tests/unit/test-status.sh` — all pass, exit 0, 2.9 s
  (incl. the 6 new #221 pins); `sh tests/unit/test-reviews-lint.sh`
  OK (23 cases); `sh tests/unit/test-reviews-parity.sh` OK;
  `shellcheck` on status.sh — zero findings in the touched range
  (125–229), pre-existing warnings unchanged.
- Sabotage re-verification (committed tree first, restore + green
  after each): read1→read, wait→sleep, probe neutered, gate `-t 2`
  dropped, col-0 `}` injected — five reds, five restores, final
  suite run green.
- Environment: kit-managed checkout at /var/www/opencode-permissions-kit
  (agent user), Python 3.12.3, util-linux `script`, shellcheck 0.9+.

## Recommendation

**No merge blocker.** Both findings are LOW process items, not
shipped defects: b W1 closes by adding the SIGINT pin (test code —
would owe micro wave c per the stop rule) or by an explicit
deliberately-not-done disposition (the pty SIGINT delivery problem is
real, but the suggested `kill -INT` shape avoids it); b W2 closes
with one resolution-record line (bookkeeping — loop-closing). If both
are dispositioned deliberately-not-done, the loop closes now.
