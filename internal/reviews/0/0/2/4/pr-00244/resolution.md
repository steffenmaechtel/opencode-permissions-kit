# Resolution — pr-00244 (issue #223 fs-baseline python3 health gate)

Chain: [review-a.md](review-a.md) (wave snapshot 2026-10-24, 16 IDs, 12
unique findings after 3 cross-axis duplicate pairs) → fix wave 1 (this
file, created with the fix commit). Birth PR #244, branch
`feature/223-fsb-tee-health-gate`.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a Q1 (MED) | **implemented** | `<SHA>` | pipefail rc contract stated truly; §11c bash rider pins EPIPE-exit-0 |
| a W1 (MED) | **implemented** | `<SHA>` | _py3_health_probe runs python3 isolated; matrix + wiring pins |
| a W2 (LOW) | **implemented** | `<SHA>` | comment rewritten — baseline degrades (#223), not a hard-dep example |
| a S1 (LOW) | **implemented** | `<SHA>` | -I on probe+tee; §11d pins hostile PYTHONPATH ignored (not fallback) |
| a S2/W3/Q4 (LOW) | **implemented** | `<SHA>` | aborted flag; §11c+§11e assert no completion line |
| a W4 (LOW) | **implemented** | `<SHA>` | §11e setsid+fifo+SIGINT executes the KI arm; no traceback |
| a Q2/W6 (LOW) | **implemented** | `<SHA>` | docs + test header: still applies, one warn — not "silent" |
| a Q3/S4 (LOW) | **implemented** | `<SHA>` | W23BPBIN removed; name grep: zero refs |
| a Q5 (INFO) | **implemented** | `<SHA>` | dead rc assert removed; stderr greps discriminate |
| a S3 (INFO) | **deliberately not done** | — | fail-closed by design, commented; setfacl implies coreutils |
| a W5 (INFO) | **deliberately not done** | — | fail-closed; status.sh reports health; wrapper output contract |
| a Q6 (INFO) | **deliberately not done** | — | pre-existing numbering cosmetics; renumber buys no behavior |

## Evidence detail

### a Q1 — pipefail rc contract

The old comment claimed "the callers run without pipefail" — false for
every shipped caller: install.sh:46-48, config.sh:27-29, update.sh:38-40
all run `(set -o pipefail) 2>/dev/null && set -o pipefail || true`
(production runs bash via `curl | sudo bash`), and all three call
`fs_baseline_root` from the main shell (install.sh:1781, config.sh:384
and 729, update.sh:1516). The tee pipeline's rc lands in `_fsbp_rc`
(fs-baseline.sh, `|| _fsbp_rc=$?` capture), so the except clause is
behaviorally observable in production. The rewritten comment states the
true contract: exiting 0 on EPIPE is deliberate (a consumer that closed
early cannot fail the pass alone; a consumer that DIED leaves its own
rc and pipefail fails the pass through it). New pin: §11c bash rider
runs the dead-consumer shape under `bash -c 'set -o pipefail; …'` and
asserts rc 0 — pre-fix, the traceback rc 1 would have failed a green
pass through pipefail (environment-guarded with a skip note where bash
is absent, L4b). Unit-dash-vs-production-bash asymmetry documented in
the comment.

### a W1 — installer health gate

`_py3_health_probe` (new function in install.sh, called verbatim from
the pre-flight): two branches, two distinct ui_error classes — absent
("not installed") vs broken ("present but broken"). The health branch
RUNS `python3 -I -c 'import fnmatch, json, os, re, sys'` — the union of
the kit's shipped import surface (jsonc parser: fnmatch/json/re/sys;
fs-baseline tee: os/sys; ddev describe: json/sys). Pins in
tests/unit/test-install-args.sh (extraction + subshell pattern from
_distro_gate, 0.0.45a C1): healthy passes silently; absent aborts rc 1
naming the class; broken shim (exit 9) aborts rc 1 naming the OTHER
class; hostile PYTHONPATH is ignored (S1 pin at the installer gate);
verbatim call wiring pin; old presence-only gate count pin (exactly one
survivor, inside the function).

### a S1 — isolated interpreter

Design decision recorded here: the import-swap alternative (signal/os/
sys discussion) is a dead end — `signal` is a stdlib .py wrapper (as
PYTHONPATH-shadowable as `os`; neither is a CPython builtin on the
supported interpreters). `-I` closes the env route entirely: PYTHONHOME
and PYTHONPATH are ignored by both probe and tee, so neither breaking
nor functional (module-shadowing) poison reaches them. The `import os`
in the tee stays — it is load-bearing for the pr-00221 W2/W6
no-traceback fix (devnull dup2). Residual after -I: an attacker who
can write into the SYSTEM stdlib directory is root already.

Pin mechanics, corrected during the wave (vacuous-pin lesson): an
os.py PYTHONPATH shadow NEVER fires — os is preloaded in sys.modules
at -c startup, the import returns the cached module. The first §11d
and installer-matrix drafts used that dead vehicle and passed green
WITHOUT -I (caught by sabotage, not by the green run). Rebuilt on
firing mechanisms, verified red under sabotage for the named reason:
§11d drives PYTHONHOME poison at the fs-baseline gate (without -I:
startup breaks rc 1, probe degrades to fallback — the counters and
no-warn asserts go red); the installer matrix shadows json.py (not
preloaded; the probe imports it) — without -I the gate aborts
"present but broken", the poisoned-case pin goes red quoting it.

### a S2/W3/Q4 + a W4 — aborted pass + the KI arm pin

Code: `aborted = False` … `except (BrokenPipeError, KeyboardInterrupt):
aborted = True` … `if counted and not aborted:` — an aborted pass
(counted is bytes READ, not entries applied) prints no completion line.
Pins: §11c asserts "— done" absent after the dead-consumer EPIPE;
§11e executes the KeyboardInterrupt arm via setsid process group +
held-open fifo + SIGINT.

§11e engineering record (three fixture bugs the pin itself caught — the
L4 discipline working, each documented in the test):
1. Write-end lifetime: `> "$fifo"` on the writer's python alone closes
   the fifo when python exits → tee sees EOF, finishes normally, prints
   the completion line before the signal arrives. Fix: `exec 3>` on the
   writer SUBSHELL holds the write end through the sleep.
2. POSIX async-list SIGINT rule: a background command of a
   non-interactive shell starts with SIGINT IGNORED; CPython then never
   installs its KeyboardInterrupt handler — kill -INT would have been a
   silent no-op and the pin VACUOUS in every environment. Fix: wrapper
   python restores the disposition (a caught signal resets to default
   across exec) and execv's the real sh+tee.
3. dash kill syntax: `kill -INT -- -PGID` is a usage error (rc 2) under
   dash while bash accepts it — the group kill silently never happened
   when the suite ran under `sh` (the debug session ran bash and looked
   green). Fix: `kill -INT "-$pid"` with `/bin/kill` fallback; the
   divergence is commented at the call site.

### Class sweep record (L2)

- `grep -rn 'command -v python3' files/` — health-claiming sites:
  install.sh pre-flight (fixed: now runs it isolated), fs-baseline
  probe (fixed: `-I`). update.sh timeout probes are presence-legitimate
  (no interpreter, no data pipeline — W-report deferred them, out of
  class).
- `grep -rn 'python3' files/` — `-I` now at three sites (fs-baseline
  probe + tee, installer gate). Remaining sites fail-loud or cosmetic,
  none false-green: update.sh resolve (attributeless warn, binary left
  untouched), ddev-terminal.sh JSON get (silent cosmetic degrade),
  opk settings edit (loud ui_error else), status.sh (fail-visible),
  uninstall/tui (best-effort, labeled), opencode-as-opencode:444
  (W5, deliberately not done).
- `grep -rn 'silent' docs/ tests/unit/test-fs-baseline.sh` — two
  wording sites fixed (getting-started bullet, test header); the
  owning page sharing-group.md was already accurate ("one warning says
  so").
- `grep -cF 'if ! command -v python3 >/dev/null 2>&1; then'
  files/install.sh` — exactly 1 (inside `_py3_health_probe`); pinned.

### L1–L7 run (before commit)

- L1: new fail-soft spots pinned by executing the path — broken shim
  (§11), absent (§11b), missing cat (§11b), dead consumer (§11c),
  hostile env (§11d), SIGINT (§11e), installer absent/broken/poisoned
  (matrix). Observation surfaces match production (marker file where
  production discards stderr; stderr where stderr is the observable).
- L2: sweep above, patterns + sites recorded.
- L3: every rewritten comment claim carries its pin (pipefail → bash
  rider; -I isolation → §11d + matrix; once-per-run cache → §11 probe
  count; "four passes" verified by count). Docs claims re-worded to
  match the warn line.
- L4: pins sit before the summary gate (suite tallies); §11c rc assert
  REMOVED as vacuous (a Q5); bash rider environment-guarded (L4b).
  Sabotage run on the committed tree: deleting `aborted = True` → both
  no-completion-line pins RED; removing -I → first run exposed §11d +
  the installer poisoned case as VACUOUS (os.py shadow never loads),
  pins rebuilt on firing mechanisms (PYTHONHOME, json.py) and
  re-sabotaged RED for the named reason; restores verified green.
- L5: no new root operations; except-clause rewrite is in-process
  python, no path operands touched; the existing component walk is
  unchanged.
- L6: fixes bring their own pins (this wave's new sections); micro-wave
  review (snapshot b) owed on the fix diff per the loop.
- L7: no new shell files; edits follow the existing skeleton idioms.

### Gates (pre-commit)

make lint green; sh tests/unit/test-fs-baseline.sh 80/80; full
`make test` rc 0 (17 suites "All tests passed", 1355 pins total — log
/tmp/opencode/maketest-pr244b.log on the session host); sandbox policy
caught and fixed one unguarded `rm "$var/suffix"` in the new installer
matrix (now `${_py3w:?}`); line-length ratchet + reviews lint/parity
green before the commit that carries this file. Process near-miss,
recorded: the first wave commit briefly went in with the ratchet RED
(the gate ran but was chained with `;`, not `&&` — the pr-00234
shape); caught within the minute, rows shortened, commit amended
before any push; the amended HEAD is gate-green.

## Follow-ups

- E2E: root-run semantics changes (fs-baseline tee rc contract,
  installer gate) owe both suites in-wave — run on the committed tree,
  discharge recorded in the bookkeeping commit (tree SHA + counts).
- Kit-wide `-I` hardening candidate: update.sh resolve, ddev-terminal,
  wrapper tools_from_config, status.sh remain env-sensitive but
  fail-loud/cosmetic — optional future wave, out of scope here.
- §11e external-terminal confirmation: the agent sandbox is not a
  developer terminal (the dash/bash kill divergence was found live);
  maintainer invited to run the fs-baseline suite in a real terminal —
  result to be noted here.
