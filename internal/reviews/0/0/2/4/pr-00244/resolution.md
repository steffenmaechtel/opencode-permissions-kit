# Resolution — pr-00244 (issue #223 fs-baseline python3 health gate)

Chain: [review-a.md](review-a.md) (wave snapshot 2026-10-24, 16 IDs, 12
unique findings after 3 cross-axis duplicate pairs) → fix wave 1 →
[review-b.md](review-b.md) (fix-wave snapshot 2026-10-24, 9 IDs, 8
unique after 1 dup pair) → fix wave 2 → [review-c.md](review-c.md)
(wave snapshot 2026-10-24, 14 IDs, 11 unique after 3 dup pairs, 1
sub-claim retracted) → fix wave 3 → [review-d.md](review-d.md)
(wave snapshot 2026-10-24, 9 IDs, all unique — 3 LOW, 6 INFO, no
MED/HIGH) → fix wave 4 → [review-e.md](review-e.md) (wave snapshot
2026-10-24, 9 IDs unique after 2 dup pairs — 6 LOW, 3 INFO, no
MED/HIGH) → fix wave 5 (the e rows below) → [review-f.md](review-f.md)
(wave snapshot 2026-10-24, 13 IDs, 12 unique after 1 dup pair — 2 MED,
6 LOW, 4 INFO, no HIGH) → fix wave 6 (the f rows below). Birth PR
#244, branch `feature/223-fsb-tee-health-gate`.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a Q1 (MED) | **implemented** | `5333a03` | pipefail rc contract stated truly; §11c bash rider pins EPIPE-exit-0 |
| a W1 (MED) | **implemented** | `5333a03` | _py3_health_probe runs python3 isolated; matrix + wiring pins |
| a W2 (LOW) | **implemented** | `5333a03` | comment rewritten — baseline degrades (#223), not a hard-dep example |
| a S1 (LOW) | **implemented** | `5333a03` | -I on probe+tee; §11d pins hostile PYTHONPATH ignored (not fallback) |
| a S2/W3/Q4 (LOW) | **implemented** | `5333a03` | aborted flag; §11c+§11e assert no completion line |
| a W4 (LOW) | **implemented** | `5333a03` | §11e setsid+fifo+SIGINT executes the KI arm; no traceback |
| a Q2/W6 (LOW) | **implemented** | `5333a03` | docs + test header: still applies, one warn — not "silent" |
| a Q3/S4 (LOW) | **implemented** | `5333a03` | W23BPBIN removed; name grep: zero refs |
| a Q5 (INFO) | **implemented** | `5333a03` | dead rc assert removed; stderr greps discriminate |
| a S3 (INFO) | **deliberately not done** | — | fail-closed by design, commented; setfacl implies coreutils |
| a W5 (INFO) | **deliberately not done** | — | fail-closed; status.sh reports health; wrapper output contract |
| a Q6 (INFO) | **deliberately not done** | — | pre-existing numbering cosmetics; renumber buys no behavior |
| b Q1/W1 (MED) | **implemented** | `25f96f1` | probe imports the measured union; drift-pinned, sabotage red |
| b S1 (LOW) | **implemented** | `25f96f1` | -I claims scoped to PYTHON* env; loader/binary residual named |
| b S2 (LOW) | **implemented** | `25f96f1` | failed probe surfaces interpreter stderr; env class named; noisy pin |
| b S3 (INFO) | **implemented** | `25f96f1` | first root-exec moment named in the gate comment |
| b W2 (LOW) | **implemented** | `25f96f1` | §11e setsid guard + skip note (§11c bash-rider pattern) |
| b W3 (LOW) | **implemented** | `25f96f1` | drain-marker arm proof; never-armed fails red; fixed sleep removed |
| b W4 (INFO) | **implemented** | `25f96f1` | review README process: trailers qualify not-done IDs |
| b Q2 (INFO) | **implemented** | `25f96f1` | dead `_p3d` parameter removed; `_py3case` is 2-arg |
| c Q1/W2 (MED) | **implemented** | `58c2019` | find over whole lib root; fixture self-test pins the shapes |
| c S1 (LOW) | **implemented** | `58c2019` | CPython's real wording restored; grep literals indirected (scanner-safe) |
| c S2 (LOW) | **implemented** | `58c2019` | .pth/site-packages residual named in all three shipped comments |
| c S3 (LOW) | **implemented** | `58c2019` | stderr passthrough at 5 sibling sites + probe rerun; pins in 4 suites |
| c S4 (INFO) | **implemented** | `58c2019` | promise scoped to extracted shapes; residual named in the test comment |
| c W1 (LOW) | **implemented** | `58c2019` | tr ',;' split; fixture self-test (zmod_a..d) red on extraction break |
| c W3 (LOW) | **implemented** | `58c2019` | assignment-count pin: exactly one `_py3_imports=` |
| c W4/Q2 (LOW) | **implemented** | `58c2019` | sweep record corrected: test-ui.sh hard-requires setsid |
| c W5/Q4 (INFO) | **implemented** | `58c2019` | pipe-buffer wording in §11e comments + this ledger |
| c Q3 (LOW) | **implemented** | `58c2019` | integer sleep poll (10 × 1 s), same 10 s bound |
| c Q5 (INFO) | **implemented** | `58c2019` | dead `_p3f=""` removed; loop lives inside `_p3collect` |
| d S1 (INFO) | **deliberately not done** | — | designed; repetition fires only on an already-broken python3 |
| d S2 (INFO) | **deliberately not done** | — | warn never tty-gated (branch contract); gate would hide cron cause |
| d W1 (LOW) | **implemented** | `f198fb2` | 2>&1 dropped, stdout kept, absence guarded; tui-mode pins |
| d W2 (LOW) | **implemented** | `f198fb2` | same-line double-assignment pin; joined assignments go red |
| d W3 (INFO) | **implemented** | `f198fb2` | sweep record re-anchored by content, not stale line number |
| d W4 (INFO) | **implemented** | `f198fb2` | residual bullet rewritten to its grep's actual hits |
| d Q1 (LOW) | **implemented** | `f198fb2` | command -v guards at resolve + _opk_json_get; absence pins |
| d Q2 (INFO) | **implemented** | `f198fb2` | needle scoped to the resolve function |
| d Q3 (INFO) | **implemented** | `f198fb2` | one sentence each on sharing-group.md + cli.md |
| e S1 (LOW) | **implemented** | `f49dadd` | guard runs inside the sudo context (sh -c); asymmetry pins both arms |
| e S2 (INFO) | **implemented** | `f49dadd` | rc 127→0 contract named at the guard; message correction recorded |
| e W1 (LOW) | **implemented** | `f49dadd` | record completed: both tee sites + code-site anchor, correction marker |
| e W2 (LOW) | **implemented** | `f49dadd` | count+dup pins extended to `+=` shapes; comment promise trued |
| e W3 (LOW) | **implemented** | `f49dadd` | `:1157` replaced by a content anchor |
| e W4 (INFO) | **implemented** | `f49dadd` | concealment residual named in the pin comment (promise scoped) |
| e W5 (INFO) | **implemented** | `f49dadd` | absence sentence now names oao:444's redirect+rc handling |
| e Q1 (LOW) | **implemented** | `f49dadd` | cli.md sentence states the per-step truth |
| e Q3 (LOW) | **implemented** | `f49dadd` | healthy-noop pin asserts an empty stderr stream |
| f W1 (MED) | **implemented** | `<SHA>` | count grep `\|\| true`-guarded: zero-match FAIL observable, no set -e abort |
| f W2 (MED) | **implemented** | `<SHA>` | guard inside the sudo context (sh -c, e-S1 pattern); 4 kit-cli pins |
| f S1 (LOW) | **implemented** | `<SHA>` | comment states the true rc contract (no caller acts; set -e nuance) |
| f W3 (LOW) | **implemented** | `<SHA>` | first-token-`+=` double documented; both collateral catches named |
| f W4 (LOW) | **implemented** | `<SHA>` | dup span `[^#]*` cannot cross comments; `_p3old` comment-strip |
| f W5 (LOW) | **implemented** | `<SHA>` | TPSWERR removed in-block like its sibling marker |
| f Q1 (LOW) | **implemented** | `<SHA>` | record corrected by marker: self-append reds in composition, by design |
| f Q2 (LOW) | **implemented** | `<SHA>` | "12 sites" trued by marker: class count, not total (15 executing lines) |
| f S2 (INFO) | **deliberately not done** | — | already recorded backlog (the wave-4 record names uninstall:316) |
| f S3 (INFO) | **deliberately not done** | — | exact-name lookup — the basename exclusion is precisely scoped |
| f Q3 (INFO) | **implemented** | `<SHA>` | cli.md sentence ordered (advisory feed, first scan, leak scan) |
| f Q4 (INFO) | **implemented** | `<SHA>` | count-pin label says assignment/append line |

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
fs-baseline tee: os/sys; ddev describe: json/sys). (Correction, #244 b
Q1: that list was a strict subset, not the union — threading/time
(status.sh), pathlib (opk), importlib.util/stat/tempfile
(tui-register.py) were missing; fix wave 2 probes the true union and
pins it against drift.) Pins in
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
nor functional (module-shadowing) poison reaches them. (Correction,
#244 b S1: "entirely" overstated — the loader route
(LD_PRELOAD/LD_LIBRARY_PATH), the PATH-resolved binary and system
site-packages/.pth stay outside -I's scope; the shipped comments now
claim only the PYTHON* scope.) The `import os`
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

## Evidence detail (fix wave 2 — b findings)

### b Q1/W1 — true import union, drift-pinned

The gate's import list is now `_py3_imports` (assignment inside
`_py3_health_probe`) carrying the measured union: fnmatch,
importlib.util, json, os, pathlib, re, stat, sys, tempfile,
threading, time — sources: jsonc-parser.py, the fs-baseline
probe+tee, ddev describe + update resolve + status feed (json/sys),
the status progress tee (sys/threading/time), the opk settings edit
(json/sys/pathlib), tui-register.py. Enforcement is a pin, not a
comment: the drift pin in tests/unit/test-install-args.sh extracts
every shipped python import (line-start imports minus comment lines,
plus inline `-c 'import …'` strings; a `from X import y` line must
carry the second keyword — a prose "from the …" line is not a
dependency) and fails naming any module missing from the gate list.
(Correction, #244 c W1/W2: the wave-2 globs covered only 4 of the
lib's 6 subdirs and dropped semicolon `-c` chains — fix wave 3
collects via find over the whole lib root and splits `;` like `,`.)
Sabotage: drop `threading` → red naming threading (status.sh); drop
`pathlib` → red naming pathlib (opk). The a-W1 evidence sentence
above was wrong about "union" — corrected in place, cited here.

### b S1 — claim scope

fs-baseline.sh's probe header and tee comment now claim exactly the
PYTHONHOME/PYTHONPATH scope and name the residual surface (loader
route LD_PRELOAD/LD_LIBRARY_PATH, the PATH-resolved binary,
root-owned trust) — install.sh's gate comment gains the same
scoping sentence. The a-S1 "closes the env route entirely" sentence
above overstated; corrected in place, cited here.

### b S2 — diagnostic passthrough + the env class named

On a failed probe the gate reruns the import once WITHOUT the stderr
discard (rc guarded with `|| true` — the branch already failed; the
rerun exists for stderr) so an interpreter that prints its real
problem shows it above the verdict, and the ui_error names the third
class ("needs PYTHONHOME/PYTHONPATH?"). Pin: the matrix's noisy case
(a shim echoing "Could not find platform-independent libraries" to
stderr, exit 9) asserts rc 1, the diagnostic line AND
'present but broken' in the observed stderr. Acceptance cost named
here per the finding: hosts whose python3 works only via env now
fail the install gate — deliberate (a W1's hard-fail intent), with
the diagnostic surfaced for self-diagnosis.

### b S3 — root-exec moment recorded

One comment sentence in the gate block: running the probe is the
installer's first EXECUTION of python3 as root — same binary and
trust as every root python3 the installed kit runs, one moment
earlier.

### b W2 — setsid guard

§11e is wrapped in a `command -v setsid` guard with the §11c
bash-rider skip-note shape; a setsid-less host now prints one note
line instead of two vacuously green pins.

### b W3 — arm proof

The writer touches a ready marker after the 1 MiB stream write
returns — a fifo write blocks until the reader drains it, so the
marker proves the tee consumed the stream and sits blocked in read
(interpreter initialized, KI handler installed).
(Correction, #244 c W5/Q4: "consumed the stream" overstated by up to
one pipe buffer (~64 KiB may still be buffered when the blocking
write returns) — the load-bearing property (interpreter initialized,
read loop live) holds either way; and the retracted second clause
never applied: a dying writer python aborts the subshell under
set -e BEFORE the marker, so a broken writer fails the arm pin red.)
The poll replaces
the fixed `sleep 1`, and "no marker within 10 s" fails red by
itself instead of passing green with nothing executed. A wait-rc
discriminator was considered and rejected: the setsid'd sh wrapper
dies BY the group SIGINT (default disposition, rc 130) even on the
healthy path, so its rc cannot separate "KI caught" from "signal
won" — the drain marker is the only sound positive proof on a
surface that is silent by contract.

### b W4 — trailer qualification rule

internal/reviews/README.md Process step 5 now requires fix-commit
messages that enumerate finding IDs to qualify the
deliberately-not-done ones. This wave has no not-done dispositions —
its trailer is true full coverage.

### b Q2 — dead parameter

`_p3d` is gone; `_py3case` takes PATH and PYTHONPATH-or-empty.

### Class sweep record (L2, fix wave 2)

- The drift pin IS the enforced sweep for the import-union class —
  its extraction runs over py/, sh/, management/ and bin/ (glob), so
  a new consumer anywhere in the lib goes red without touching the
  pin (patterns documented in the test). (Correction, #244 c
  Q1/W2: "anywhere in the lib" was false — tui/ and templates/ sat
  outside the four globs. Fix wave 3 collects via find over the
  whole lib root, making the sentence true as written.)
- `grep -rn 'setsid' tests/unit/` — §11e is the only setsid user;
  the §11c bash rider was already guarded (the twin the finding
  cited). (Correction, #244 c W4/Q2: false as written — test-ui.sh
  hard-requires setsid at startup and uses it ~20 times, and
  test-uninstall.sh references it; the substantive conclusion holds
  (every tests/unit setsid use is guarded: §11e skip-with-note,
  test-ui hard-require), the record misstated its own grep.)
- `grep -nE 'rm( |$)' tests/unit/test-install-args.sh` — the new
  noisy-case operand rides the suite's guarded `:?` scratch pattern;
  one scanner false positive ("platform independent" chains into the
  raw-line rm-suffix grep) was fixed at the source by hyphenating
  the marker (comment at the shim), not by an allowlist entry.
  (Correction, #244 c S1: two-shaped truth — the mechanism is REAL
  for consuming grep lines quoting the literal before a quoted
  $VAR operand (proven live by the sandbox suite during fix wave 3:
  5 violations), and clean for the fixture-printf shape both
  reviews probed. Hyphenating was a working source-fix for its
  lines; fix wave 3 restores CPython's real wording and breaks the
  chain by variable indirection — see the c S1 evidence.)

### L1–L7 run (fix wave 2, before commit)

- L1: the diagnostic rerun's `|| true` is pinned by the noisy case
  (the failure path executes and its stderr is the asserted
  surface); the drift pin's guarded greps are pinned by the
  non-empty surface check.
- L2: sweep above.
- L3: every rewritten claim carries its pin (union → drift pin; -I
  scope → §11d + matrix; error classes → matrix greps; arm proof →
  the marker pass/fail pair).
- L4: all new pins sit before their suite's summary gate; sabotage
  run post-commit (recorded in Follow-ups).
- L5: no new root operations — the rerun is a second read-only
  interpreter execution inside an already-root gate.
- L6: fixes bring their own pins; the wave review of this fix diff
  (snapshot c) is owed per the loop.
- L7: no new shell files.

### Gates (fix wave 2, pre-commit)

make lint green; sh tests/unit/test-fs-baseline.sh 81/81; sh
tests/unit/test-install-args.sh green (4 new pins); full `make test`
rc 0, all suites green — sandbox policy included after one scanner
false positive was fixed at the source (hyphenated marker, not an
allowlist entry); line-length ratchet + reviews lint/parity green
(gates chained with `&&` this time). Log:
/tmp/opencode/maketest-pr244c.log on the session host. E2E (install.sh
behavior change → owed in-wave): runs on the committed tree, recorded
in Follow-ups by the bookkeeping commit.

## Evidence detail (fix wave 3 — c findings)

Maintainer decisions taken before the wave (recorded per the round's
questioning): S3 as a BEHAVIOR change (surface interpreter stderr at
the sibling consumers — e2e owed in-wave), Q1/W2 via find over the
lib root, Q3 via integer sleep.

### c Q1/W2 — whole-lib extraction

`_p3collect` runs `find <lib-root> -type f` — tui/ (tsx/json), 
templates/ (jsonc/sudoers) and any future subdir or lib-root file
included; tsx import lines fall through the module regex (not
python). The "anywhere in the lib" sentence above is true again
(corrected in place). Pin: the fixture self-test plants line-start
comma imports, a from-import, a prose from-line and an inline
`-c 'import zmod_d; zmod_d.run()'` one-liner in a scratch dir and
asserts the SAME collector/splitter yields exactly the four planted
modules — red on any extraction break, independent of the shipped
surface (sabotage post-commit, see Follow-ups).

### c S1 — wording fidelity + the scanner's two shapes

The noisy fixtures now echo CPython's real unhyphenated
"platform independent libraries"; every pin greps a per-suite
variable carrying that literal. The scanner mechanism has TWO
shapes, separated empirically during this wave (the sandbox suite
itself was the probe — 5 violations, all consuming grep lines): a
consuming line `grep -qF 'platform…' "$VAR/x"` chains into the
raw-line rm-suffix pattern (rm⊂platform + bare words incl. `'` +
the quoted $VAR operand), while the fixture-printf shape both
reviews probed stays clean. So the wave-2 hyphenation WAS a
working source-fix for its lines (its record's mechanism claim was
true for the grep shape), and snapshot-c S1's "does not reproduce"
held only for the fixture shape. The final fix keeps the real
wording everywhere and breaks the chain by indirection: the
definition line (`X='platform independent libraries'`) carries no
quoted $VAR operand after the bare words and probes clean. Pins
assert the mechanism (stderr passthrough), not the text.

### c S2 — third residual route named

install.sh's gate comment, fs-baseline.sh's probe header and the
tee comment now all name the system site-packages/.pth startup
route (-I implies -E -s -P, not -S) alongside the loader route and
the PATH-resolved binary — conceding exactly what b-S1/review-c S2
found, no more (user-site .pth stays closed by -s/-P).

### c S3 — stderr transparency at the siblings (behavior change)

Class sites and dispositions (sweep below): fs-baseline probe
(rerun-for-stderr on failure, absent-interpreter guarded off — the
installer gate's b-S2 shape; §11f pin), status progress probe
(stderr passes on the tty path; pty pin via `script -qec`, scan
bytes stay reference-identical), status advisory feed (redirect
dropped; extracted-program pin: garbage in → rc 1 SILENT), status
leak-scan parser (redirect dropped; pin: broken config prints the
parser's clean "Error ..." line, no traceback — the parser itself
prints diagnostics, not tracebacks), update.sh 2.x resolve (redirect
dropped; pin: noisy shim → diagnostic + rc 1, unparseable body →
silent rc 1), ddev-terminal `_opk_json_get` (redirect dropped;
pins: happy/unparseable/noisy — the empty-on-miss stdout contract
unchanged). Already transparent, no change: opk:300 settings edit
(runs the heredoc python3 without any stderr redirect; failure
already lands in a loud ui_error). Deliberately not changed:
opencode-as-opencode:444 (a W5's wrapper output contract, unchanged
disposition). Every expected-failure path stays SILENT (the except
arms swallow their failures by design) — the passthrough only
carries interpreter-level stderr. (Correction, #244 d Q1: "only
carries interpreter-level stderr" overstated at the two then-unguarded
sites — the SHELL's not-found notice passed too when python3 was
absent; fix wave 4 guards absence at update resolve and
`_opk_json_get`, making the sentence true as written.) Line-shape
pins in test-status + test-update-flags re-red if a `2>/dev/null`
returns on those sites.

### c S4 — promise scoped

The drift-pin comment now names the shapes it collects (line-start,
embedded python blocks, single-quoted inline `-c` including
semicolon chains) and the residual it does not (double-quoted -c,
mid-line imports, importlib/__import__, `as` aliases) — the promise
matches the enforcement.

### c W1 — semicolon chains

`_p3split` splits on `;` like `,` (tr ',;'), plus a second
import-prefix strip for `import a; import b` shapes the split
re-exposes (requires whitespace — the first draft's zero-space
strip turned `importlib.util` into `lib.util` and the pin caught it
red pre-commit). Fixture self-test above is the pin.

### c W3 — assignment count pinned

`grep -c "^[[:space:]]*_py3_imports=" install.sh` == 1, asserted
next to the extraction — a second assignment (union in the pin,
last-wins at runtime) goes red.

### c W4/Q2 + c W5/Q4 — ledger corrections

Both sweep-record sentences corrected in place above (setsid users;
pipe-buffer wording in the b-W3 evidence and the §11e comments).
The W5 retraction context is recorded with the correction: the
writer-death clause never applied (set -e aborts the subshell
before the marker — the arm pin fails red on a dead writer).

### c Q3 — integer poll

10 × `sleep 1` replaces 40 × 0.25 s — same 10 s bound, no
fractional-sleep portability assumption in the block the setsid
guard made portable. Worst-case latency cost: ~0.75 s per poll
tick; suites green.

### c Q5 — dead pre-declaration removed

`_p3f=""` is gone; the loop variable lives inside `_p3collect`.

### Class sweep record (L2, fix wave 3)

- `grep -rn "python3" files/` re-classified against stderr
  redirects (the S3 class): 6 fixed sites listed above; opk:300
  already transparent; opencode-as-opencode:444 stays not-done
  (a W5); fs-baseline tee's except-clause silence is the pinned
  #223 contract (no stderr redirect involved); update.sh 1.x
  branch uses sed (no interpreter).
- `grep -rn "sleep 0\." tests/unit/` — the §11e poll fixed; the
  test-status.sh §3b sender-fixture poll `sleep 0.05` is pre-existing
  (content-anchored; #244 d W3 correction: the stale `:2621` citation
  described the pre-wave tree — the wave's own +75 lines had already
  moved it to `:2690` when this record was committed; works on the
  supported coreutils baselines) — deliberately not done: out of this
  wave's diff, loud-failing class only.
- `grep -rn "2>/dev/null" files/` on python3 lines — (#244 d W4
  correction: this bullet misdescribed its own grep's output; the
  gate probes' `>/dev/null 2>&1` shapes cannot match the literal
  `2>/dev/null`.) The grep's actual hits: curl noise guards
  (update.sh:230, the resolve pipe's registry.npmjs.org curl
  (#244 e W3 correction: the ":1157" cite was stale on this
  record's own commit — the wave-4 guard lines moved the line;
  content anchor now), setup-container-backend:283 — network
  noise, not interpreter stderr) and one python3-line hit,
  opencode-as-opencode:444, dispositioned in the S3 bullet above
  (a W5, deliberately not changed). The fixed-gate probes keep
  their rc discards by design
  (`>/dev/null 2>&1` shapes — presence/probe rc; only the
  failure-path rerun/drop shapes changed).

### L1–L7 run (fix wave 3, before commit)

- L1: every dropped stderr redirect is pinned by executing the
  failure path — noisy-shim cases assert the diagnostic (fs-baseline
  §11f, status pty, ddev _opk_json_get, update resolve); expected-
  failure silence pinned (advisory garbage, unparseable registry
  body, _opk_json_get miss). The rerun's `|| true` is pinned by §11f
  (the failure path executes and its stderr is the asserted
  surface).
- L2: sweep above; patterns + sites recorded.
- L3: every rewritten comment claim carries its pin or was deleted
  (drift-pin comment names shapes + residual; probe comments cite
  the passthrough; §11e comments state the pipe-buffer truth).
- L4: new pins sit before their suites' summary gates; the
  probe-count pin updated to the new contract (2 = probe + rerun,
  cache still pinned: 8 would be the no-cache number) — caught red
  pre-commit and fixed with an explanatory comment; line-shape
  pins discriminate re-added redirects; the sandbox suite caught
  the grep-line scanner shape live (5 violations → variable
  indirection) — the falsification event that separated the
  scanner's two shapes (c S1). Sabotage post-commit (Follow-ups).
- L5: no new root operations — the fs-baseline rerun is a second
  read-only interpreter execution inside an already-root gate,
  absent-interpreter guarded (no not-found noise).
- L6: fixes bring their own pins (§11f, matrix/drift/status/ddev/
  update-flags additions); the wave review of this fix diff
  (snapshot d) is owed per the loop.
- L7: no new shell files; edits follow the existing skeletons.

### Gates (fix wave 3, pre-commit)

make lint green (ShellCheck — caught the adv-line paren loss red
before it could ship: the unit suites' extraction never parses that
region, the e2e would have); sh tests/unit/test-fs-baseline.sh
82/82; sh tests/unit/test-install-args.sh green; test-status.sh
172 PASS rc 0; test-ddev-as-opencode.sh rc 0; test-update-flags.sh
green; full `make test` rc 0 (log /tmp/opencode/maketest-pr244d.log
on the session host); line-length ratchet + reviews lint/parity
green before the commit that carries this file. E2E (root-run
script semantics change — the stderr passthroughs): owed in-wave,
runs on the committed tree, recorded in Follow-ups by the
bookkeeping commit.

## Evidence detail (fix wave 4 — d findings)

Maintainer decision (recorded per the round's questioning): full
implementation — W1/Q1 code-side (e2e owed in-wave), W2/Q2 test-side,
W3/W4 ledger corrections, Q3 docs, S1/S2 deliberately not done.

### d W1 — the unregister cleanup joins the S3 class

tui-plugin.sh's best-effort cleanup drops `2>&1` (the stdout discard
stays): tui-register.py is silent on the expected no-op (`if not
changed: return 0` — verified against the shipped py) and prints
clean `tui-register: …` error lines otherwise, so a present-but-broken
python3 now names itself instead of degrading attributelessly. Pins in
test-tui-mode: noisy shim → diagnostic + rc 0; absence (bin-farm PATH
minus python3) → silence + rc 0; healthy run → no tui-register line,
no traceback. (#244 e Q3 correction: the healthy-noop pin asserts an
empty stderr STREAM since fix wave 5 — the two-literal enumeration
sailed past any other stderr shape.)

### d S1 / d S2 — deliberately not done

S1: the per-call repetition on `_opk_json_get` (up to ~5×/run) fires
only on an already-broken interpreter; deduplicating would couple
independent lookups for no behavioral gain. S2: the fs-baseline
degradation warn was unconditional pre-wave (the branch's existing
contract); tty-gating only the rerun would hide the cause exactly in
cron mail — the one non-tty observer that cannot see a terminal.

### d Q1 — absence guards at the two unguarded sites

update.sh resolve wraps the pipe in a `command -v python3` guard (rc
identical: absence → empty `_rlov_ver` → return 1); ddev
`_opk_json_get` returns empty early. Both mirror fs-baseline's
"no not-found noise for a legitimate absence". Pins: resolve absence
(bin-farm PATH, rc 1 + empty stderr, test-update-flags 2c-3);
`_opk_json_get` absence (empty output + empty stderr, test-ddev
2b). The c-S3 evidence sentence is corrected in place above.

### d W2 — same-line double-assignment pin

`grep -nE "^[[:space:]]*_py3_imports=.*_py3_imports="` — any line
naming the assignment token twice goes red (guarded empty-match
grep); the line-count pin above stays for separate-line seconds.
Sabotage post-commit (Follow-ups).

### d W3 / d W4 — ledger corrections in place

W3: the wave-3 sweep bullet's `:2621` citation is replaced by the
content anchor (the §3b sender-fixture poll). W4: the residual bullet
now names its grep's actual hits (curl guards + the one python3-line
hit oao:444). Both corrected in the wave-3 record above with
correction markers.

### d Q2 — site-scoped needle

The forbidden shape `' 2>/dev/null || true)` is grepped inside the
sed-extracted resolve function only — the same extraction range the
suite's FUNCS file uses. A same-shape line elsewhere in update.sh can
no longer red this pin with a misleading "resolve:" message;
extraction failure fails loud by itself.

### d Q3 — docs

One sentence each on the two pages that describe the degrade paths:
sharing-group.md (a broken interpreter names itself above the warn;
a missing one stays silent) and cli.md (the diagnostic appears once
on the terminal when the scan starts; absence silent).

### Class sweep record (L2, fix wave 4)

- S3-class enumeration completed (#244 d W1): the python3 execution
  sites under files/ are now — guarded + transparent: the
  tui-plugin unregister cleanup (fixed this wave; #244 e W1
  correction: the ":68" cite pointed into the comment block —
  content-anchored now), fs-baseline probe + rerun + counter tee
  `_fsb_count_tee` and status probe/advisory/leak-scan/progress
  tee `_st_progress_tee` (#244 e W1 correction: the two probe-gated
  tee consumers were missing from this list as written — guarded +
  transparent, no behavior gap, enumeration only), update resolve,
  ddev `_opk_json_get`, opk:300, install.sh gate (b-S2 discard +
  rerun); deliberately not changed: oao:444 (a W5), update.sh 1.x
  (sed, no interpreter); transparent, no redirect involved:
  uninstall:316 — its absent-python3 not-found noise is
  pre-existing and outside this wave's diff, named here as backlog.
- Absence class (d Q1) swept with it: every site above guards
  absence except oao:444 (#244 e W5 correction: unguarded — its
  `2>/dev/null` + rc fallback silence absence instead of a guard),
  uninstall:316 (pre-existing, named) and the installer gate
  (absence is its loud "not installed" verdict by design).

### L1–L7 run (fix wave 4, before commit)

- L1: every new silence claim pinned by executing the path (noisy
  shim, absence farm, healthy no-op); the guards' skip paths are the
  asserted surfaces.
- L2: sweep above; patterns + sites recorded.
- L3: the new comments' claims carry their pins (tui-plugin no-op
  silence → healthy-noop pin; absence silence → absence pins;
  resolve rc equivalence → the absence pin asserts rc 1).
- L4: new pins sit before their suites' summary gates; sabotage
  post-commit (Follow-ups).
- L5: no new root operations — the guards are read-only lookups; the
  tui-plugin call keeps its sudo wrapper and operands unchanged.
- L6: fixes bring their own pins; the wave review of this fix diff
  (snapshot e) is owed per the loop.
- L7: no new shell files.

### Gates (fix wave 4, pre-commit)

make lint green; affected suites green (tui-mode, update-flags,
ddev-as-opencode, install-args; status + fs-baseline as regression);
full `make test` rc 0; line-length ratchet + reviews lint/parity
green before the commit that carries this file. E2E (root-run script
behavior changes — tui-plugin, update, ddev-terminal): owed in-wave,
runs on the committed tree, recorded in Follow-ups by the
bookkeeping commit.

## Evidence detail (fix wave 5 — e findings)

Maintainer decision (recorded per the commission): full
implementation of all 9 e-findings — S1/S2/Q1 code+docs, W2/W4/Q3
test-side, W1/W3/W5 ledger corrections in the wave-4 record above.
The wave review of this fix diff (snapshot f) runs in a FRESH
session afterwards, per the maintainer's plan.

### e S1 — the guard moves into the sudo context

The unregister cleanup's `command -v python3` guard now runs INSIDE
the `_tp_sudo` invocation: `_tp_sudo sh -c 'command -v python3
>/dev/null 2>&1 && exec python3 "$@"' tui-unregister <operands>` —
guard and execution resolve python3 in ONE PATH (sudo's
secure_path in production), so the caller/sudo disagreement closes:
arm A (caller has it, sudo doesn't) skips silently instead of
leaking sudo's not-found notice; arm B (caller lacks it, sudo has
it) runs the cleanup instead of skipping it. Operands pass as argv
to the inner sh; nothing is expanded inside the quoted script (L5
re-run below). Pins: both arms via `_tps_sudo` fixed-PATH stubs
(secure_path stand-ins over binary farms, chown still stubbed off
like the default): arm A asserts silence + rc 0 (no "not found", no
diagnostic), arm B asserts the recorder marker (execution proof) +
rc 0.

### e S2 — rc contract named at the guard

The ddev-terminal guard comment now states what f198fb2's message
omitted: absence returns 0 (pre-guard, the failed pipeline's rc 127
carried); no caller observes the function's rc (stdout-only `$( )`
consumers). The message itself is immutable history — this row is
the correction of record.

### e W1 — the enumeration record completed

Both corrections in the wave-4 S3-class bullet above (tee consumers
`_fsb_count_tee`/`_st_progress_tee` added; the ":68" cite
content-anchored). Sweep re-derived from
`grep -rn python3 files/ -I --exclude-dir=__pycache__` — 12
execution sites, every one now classified in the bullet.
(Correction, #244 f Q2: 12 is the guarded+transparent CLASS count,
not the total — the grep yields 15 executing lines / 13 site units;
the bullet's later clauses classify the remaining sites (oao:444,
update.sh 1.x sed route, uninstall:316). No site is unclassified;
the sentence read as a total.)

### e W2 — the pin pair catches append shapes

Count pin regex is now `^[[:space:]]*_py3_imports\+?=` (lines
carrying an assignment OR an append — a separate-line `_py3_imports+=`
reds the count), dup pin `^[[:space:]]*_py3_imports=.*_py3_imports(\+=|=)`
(a same-line `;`-joined append reds the dup). Probed in
/tmp/opencode/pr-00244-e/fix-probe/: base green (count 1, dup
empty), same-line append → dup RED, separate-line append → count 2
RED, same-line double → dup RED (unchanged), legitimate self-append
`_py3_imports="$_py3_imports, threading"` stays green (no false
red). (Correction, #244 f Q1: "stays green" held only for the
self-append probed in ISOLATION — next to the real assignment the
count pin counts it (2) and reds, which IS the pair's designed
drift catch for a separate-line append of any form; "no false red"
as worded was false.) The comment's "any line naming the assignment
token twice" promise is replaced by the trued enumeration.

### e W3 — content anchor

The wave-3 residual bullet's `:1157` cite is replaced by the
registry.npmjs.org content anchor (correction marker in place); the
other three cites verified current at this tree by the e-pass
(round e W-verification) and re-checked after this wave's edits.

### e W4 — residual scoped

The pin comment names what the pair does NOT catch (backslash
continuation with a `;`-led second line, eval-built assignments) —
deliberate concealment shapes, outside the maintenance-accident
threat model. The c-S4 promise-scoping pattern.

### e W5 — sentence trued

The wave-4 absence bullet names oao:444's redirect+rc handling for
what it is (silencing without a guard) — correction marker in place.

### e Q1 — docs sentence states the per-step truth

cli.md no longer promises once-ness per run: "names itself on the
terminal — once when the first scan starts, and again wherever a
python-backed step parses input (advisory feed, leak scan); a
missing one stays silent." sharing-group.md's order-only sentence
needed no change (verified by the e-pass).

### e Q3 — the healthy-noop pin asserts an empty stream

The pin now asserts the whole stderr stream is empty on the healthy
no-op (`_tps_errfile` knob on `_tps_run`, default path unchanged):
any future warning shape — deprecation, loader notice, renamed
prefix — reds the pin instead of sailing past the two fixed
literals. The d-W1 evidence sentence above carries the correction
marker.

### Class sweep record (L2, fix wave 5)

- W2 class (pin blind to a sibling form of its shape): the other
  exactness pins in the same block swept — `_p3old` presence-gate
  count (grep -cF on a full-line `if ! …` literal: no append form
  exists for that shape) and the extraction sed (single-quote
  anchored; an append after the closing quote no longer matters —
  the count/dup pair reds it first). Sites checked: the gate-pin
  block, tests/unit/test-install-args.sh:930-1000.
- W1/W5 class (record enumerations): re-derived as above (12
  sites); the corrected bullet is the complete list. (Correction,
  #244 f Q2: the 12 is the guarded+transparent class count — see the
  e W1 marker above for the full-line total.)
- W3 class (line-number cites): every numeric cite this record now
  carries was measured at this tree after the edits; the record
  prefers content anchors for anything this wave itself moved.

### L1–L7 run (fix wave 5, before commit)

- L1: the S1 shape keeps `|| true` — pinned by EXECUTING both
  asymmetry arms (silence arm + execution-marker arm); the
  `_tps_errfile` knob's default path is unchanged (the noisy cases
  still assert the merged stream).
- L2: sweep above; patterns + sites recorded.
- L3: every rewritten claim carries its pin or is trued (inner-guard
  silence → arm A pin; execution → arm B marker; stderr-empty → Q3
  pin; append reds → W2 pair, probe-verified; cli.md sentence →
  matches the three-site behavior the e-pass verified).
- L4: new pins sit before the suite's summary gate (the asymmetry
  block ends before the merged trap + summary); sabotage
  post-commit (Follow-ups).
- L5: no new root operations — the sh -c wrapper changes the sudo
  argv, not the operands; re-check done (no path-operand change,
  no chmod/chown change, the `[ -L ]` gates untouched).
- L6: fixes bring their own pins (2 asymmetry arms, stderr-empty,
  extended count/dup pair); the wave review of this fix diff
  (snapshot f) is owed per the loop — commissioned to a FRESH
  session by the maintainer.
- L7: no new shell files; the fixed-PATH stubs follow the suite's
  existing heredoc + farm idioms.

### Gates (fix wave 5, pre-commit)

make lint green (ShellCheck); sh tests/unit/test-tui-mode.sh green
(5 new/rebuilt pins); sh tests/unit/test-install-args.sh green
(extended count/dup pair); full `make lint && make test` rc 0 (all
suites, sandbox policy included, rules index parity OK 118 rows);
line-length ratchet + reviews lint/parity green before the commit
that carries this file. E2E (root-run script semantics change — the
tui-plugin guard moves into the sudo context): owed in-wave, runs
on the committed tree, recorded in Follow-ups by the bookkeeping
commit.

## Evidence detail (fix wave 6 — f findings)

Maintainer decision (recorded per the commission): full
implementation — W2 with the tui-plugin `sh -c` pattern (the
maintainer's pick), W1/S1/W3/W4/W5/Q1/Q2/Q3/Q4 code-, test- or
record-side; S2/S3 deliberately not done. Session F (the snapshot-f
author) applies the fixes in the same session per the rotation.

### f W2 — the opk settings edit joins the e-S1 class

The openchamber-secure settings edit moves its guard INSIDE the
sudo context, the identical shape tui-plugin.sh got in wave 5:
`sudo -u "$_oc_duser" sh -c 'command -v python3 >/dev/null 2>&1 &&
exec python3 "$@"' opk-settings-edit - "$_oc_settings"` with the
PYEOF heredoc attached to the sudo command — sh passes its stdin
through to the exec'd python3, so the `-` operand reads the same
script and the argv is byte-identical to the pre-wave shape
(`python3 - "$_oc_settings"`; `$0=opk-settings-edit` is cosmetic).
Both asymmetry arms close: arm A (caller PATH has python3, sudo
context lacks it) now skips silently instead of leaking sudo's
not-found notice into the ui_error; arm B (caller lacks it, sudo
has it) now runs the edit instead of falling to the ui_error that
told the user to hand-edit the file. Pins (test-kit-cli, before the
tally): two static shape pins (the guard-inside-sudo literal
extractable; no caller-side `if command -v python3` line in the
extracted block) and two functional arms on the F24 extraction
idiom — the compound is eval'd under a whole-PATH binary farm
(test-tui-mode's farm idiom) with PATH-fixing sudo shims as the
secure_path stand-ins: arm A (noisy caller python3, empty exec
farm) asserts the error path, NO "not found"/noisy marker, file
unchanged; arm B (caller farm without python3, exec farm with the
REAL interpreter symlinked in) asserts ui_success and the settings
file itself edited (opencodeBinary gone, "port" preserved — the
real heredoc script ran through the new path). E2E: the suites'
openchamber-secure flow exercises the new path end-to-end (the e2e
run.sh:1206 settings-pin-gone assert); owed in-wave, see Follow-ups.

### f W1 — the count grep joins the guarded set

`_p3asn="$(grep -cE … "$INSTALL" || true)"`: grep -c prints 0 AND
exits 1 on zero matches — unguarded under the suite's `set -e`, a
deleted/renamed `_py3_imports` assignment aborted the whole suite
mid-run instead of recording the FAIL (the wave-5 sabotage ran the
count=2 path, where grep exits 0 — the zero path never executed).
With the guard, the failure path is observable as designed:
"found 0, want 1" FAIL plus the suite tally. The comment now states
the mechanism it used to overclaim ("Both greps are guarded" was
false for this one). Sabotage post-commit: delete the assignment →
FAIL recorded, suite tallies (Follow-ups).

### f S1 / f Q3 — the two claim fixes

ddev-terminal's guard comment states the true contract: no caller
ACTS on the rc; the plain `$()` assignments among the consumers do
carry the substitution's rc, but only under `set -e`, which the
interactive rc-file context does not run — and the 127→0 delta is
the fail-safe direction (the e-round's S2 verification nuance, now
in the shipped comment instead of the overstated "no caller
observes"). cli.md's sentence names the three sites in report
order (advisory feed :542 runs before the first scan's probe :827,
leak scan :1341 last) instead of implying scan-first chronology.

### f W3 / f W4 / f Q4 — the pin pair's exactness

W3: the comment's dup-pin promise is trued — it catches same-line
doubles whose FIRST token is a plain assignment; a first-token-`+=`
double (`_py3_imports+='a'; _py3_imports+='b'`) matches neither
pin but cannot sail (sole line → extraction starves → the
extractability pin reds; next to the real assignment → count 2),
both collateral catches named at the site. W4: the dup span is
`[^#]*` — it cannot cross a comment start, so a trailing comment
naming the token stays green; probe: old regex false-red on the
comment shape, new regex green, true same-line double still red,
legitimate self-append still green. Sibling sweep of the
comment-blind class: `_p3old`'s `-cF` counts substrings anywhere —
a commented-out gate line counted as the surviving gate (the
commented-sabotage pass-green trap) — it now strips comment lines
before counting (sed 's/^[[:space:]]*#.*$//' upstream of the grep);
the other `grep -c` in the file (:827, v2-install URL hits) is
`|| true`-guarded and counts a URL literal whose comment-shadow
cannot keep a deleted real call red (a maintainer deleting the
call and leaving a commented URL would false-green — bounded to
that deliberate two-step, named here rather than fixed: the URL
also lives in docs and usage text, a comment-strip would need the
same sed rider for no observed defect). Q4: the count pin's
pass/fail labels say "assignment/append line", matching the
`\+?=` semantics.

### f W5 / f Q1 / f Q2 / not-done

W5: `TPSWERR` joins the in-block `rm -rf` (the merged trap stays
the backstop). Q1/Q2: the two wave-5 record claims carry correction
markers in place (see the e W2 and e W1 bullets above) — the
correction-of-record pattern; the immutable commit message stays as
history. S2 (uninstall:316 unguarded sudo python3): deliberately
not done — pre-existing, outside this chain's diffs, already named
as backlog by the wave-4 record's S3-class bullet. S3 (farm
basename-only python3 exclusion): deliberately not done —
`command -v python3` is an exact-name lookup; excluding precisely
the basename `python3` is the correctly scoped build, and the
f-arm farms now document their purpose in the test.

### Class sweep record (L2, fix wave 6)

- W2 class (guard vs execution resolution context):
  `grep -rn "command -v python3" files/` — 10 sites: fs-baseline
  :126/:136, ddev-terminal :83, update :1161, status :217/:538/:1333,
  install :574 all guard and execute python3 in ONE shell context;
  tui-plugin :80 and opk :305 run the guard INSIDE the sudo context
  (the sh -c pattern). No caller-guard + different-context-exec
  site remains; uninstall:316 has no guard at all (S2, backlog).
- Comment-blind count class (the W4 sibling shape): `grep -n
  "grep -c" tests/unit/test-install-args.sh` — :827 (URL literal,
  disposition above), :937 (`_p3old`, fixed with comment-strip),
  :988 (the count pin itself, `^`-anchored — full-line comments
  cannot match). Sites checked: all three.
- In-block-cleanup class (W5): test-tui-mode scratch inventory —
  every block removes what it creates (TPSW/TPSABS/TPSNZ,
  TPSW/TPSWERR, TPSNZ2, TPSABS2/TPSFIXA/TPSFIXB/TPSMARK); the trap
  remains the backstop. The new kit-cli ocw2 block removes its farm
  dir in-block.

### L1–L7 run (fix wave 6, before commit)

- L1: the new `|| true` (W1) is pinned by executing the zero-match
  path (sabotage post-commit: FAIL + tally observed); the W2 arms
  execute both asymmetry paths with the failure surfaces asserted
  (silence in A, marker-file edit in B).
- L2: sweeps above; patterns + sites recorded.
- L3: every rewritten claim carries its evidence — the W1 comment ↔
  the zero-path sabotage; W3's collateral-catch claims ↔ the f-pass
  probes (verified there); W4's comment ↔ the recorded probe
  (old red/new green); S1's comment ↔ the f-pass caller
  enumeration; cli.md ↔ the f-pass order verification; the record
  corrections carry markers.
- L4: the four new kit-cli pins sit before the tally; the arms
  discriminate in both directions (sabotage: guard revert → arm A
  noise back, arm B edit skipped — Follow-ups); the arms hard-require
  python3 (FAIL else), consistent with check-host's make-test
  contract; the block-extraction bound (≤ 32 lines) fails loud on
  anchor drift (the F24 lesson).
- L5: no new root operations — the W2 change alters the sudo argv
  (sh -c wrapper), not the operands; no path operands, no
  chmod/chown changes; the unit arms run entirely unprivileged
  (sudo shimmed, farms under suite scratch).
- L6: fixes bring their own pins (2 static + 2 functional W2 pins;
  the W1 zero path via sabotage; `_p3old`'s comment-strip rides the
  existing count pin — its sabotage shape is the commented gate).
  The wave review of this fix diff (snapshot g) is owed per the
  loop — commissioned to a FRESH session by the maintainer.
- L7: no new shell files; the arms follow the F24-extraction and
  tui-farm idioms; heredoc shims escape runtime vars.

### Gates (fix wave 6, pre-commit)

make lint green (ShellCheck, the opk heredoc shape included); sh
tests/unit/test-kit-cli.sh green (4 new pins); sh
tests/unit/test-install-args.sh green; sh tests/unit/test-tui-mode.sh
green; full `make test` rc 0 (log
/tmp/opencode/pr-00244-f6-maketest.log on the session host — the
first run red on the line-length ratchet, five resolution rows;
shortened before any commit, the ratchet's protection shape);
line-length ratchet + reviews lint/parity green before the commit
that carries this file. E2E (root-run script semantics change —
opk's settings-edit guard moves into the sudo context): owed
in-wave, runs on the committed tree, recorded in Follow-ups by the
bookkeeping commit.

## Follow-ups

- Wave-5 e2e discharged in-wave on tree `f49dadd`: `make e2e`
  **309 passed** (../logs/e2e-20261024-231534.log), `make
  e2e-rootless` **47 passed**
  (../logs/e2e-rootless-20261024-231534.log), both rc 0, parallel
  run (root-run script semantics changed: the tui-plugin guard
  moved into the sudo context; opencode cache warm from the same
  day's 22:34 run — no version gap).
- Wave-5 sabotage on the committed tree (delete-the-construct,
  observe red, restore, re-green): caller-side guard shape restored
  (the sh -c wrapper deleted) → BOTH asymmetry pins red (arm A
  noise back, arm B marker absent); `echo internal-noise >&2`
  injected before the healthy exec → the stderr-empty pin red;
  separate-line `_py3_imports+=` append → count pin red (found 2,
  want 1; the healthy probe redded collaterally — the probe now
  runs the doubled assignment); same-line joined append → dup pin
  red quoting the offending line. Restores verified green
  (test-tui-mode + test-install-args rc 0 on the restored tree).
- Wave-4 e2e discharged in-wave on tree `f198fb2`: `make e2e`
  **309 passed** (../logs/e2e-20261024-223458.log), `make
  e2e-rootless` **47 passed**
  (../logs/e2e-rootless-20261024-223458.log), both rc 0, run after a
  version-gap check (the first suite ran alone and confirmed the
  cached opencode v2.1.4 still resolves) — root-run script behavior
  changed (tui-plugin/update/ddev-terminal absence guards + the W1
  passthrough).
- Wave-4 sabotage on the committed tree (delete-the-construct,
  observe red, restore, re-green): a joined
  `_py3_imports='a'; _py3_imports='b'` line → same-line pin red;
  re-added resolve `2>/dev/null` → scoped needle + c-S3 behavioral
  pin red; re-added tui `2>&1` → W1 pin red; deleted
  resolve/`_opk_json_get` guards → both absence pins red ("python3:
  not found" in the asserted stderr). Two runs: the first combined
  the update-guard deletion with the redirect re-add — the redirect
  suppresses exactly the not-found noise (a confounded observation),
  so the Q1 guards were re-sabotaged alone. The first run also
  exposed a bug in the new ddev absence pin itself (missing
  `|| true` on the capture: rc 127 aborted the suite before its
  fail() — the pr-00211 b W13 abort-vs-count shape); fixed in the
  amended wave commit. Restores verified green (update-flags, ddev,
  tui-mode, install-args, sandbox-policy all rc 0 on the restored
  tree).
- Session bookkeeping (maintainer clarification, recorded per the
  c-round handover): the maintainer counts sessions by the snapshot
  letter they file — THIS session ("Session C" in that counting)
  filed snapshot c and applies the c-fixes. Snapshot b's header
  called the b-round session "session C of the rotation"
  (rotation-count letters) — a label collision only. The load-bearing
  fact holds under both counts: the b-round session was closed before
  this fresh session started, so no rotation deviation occurred
  (RM-0110 recovery not applicable); the c-pass ran with fresh
  context over fixes authored by a different, closed session.
- Wave-3 e2e discharged in-wave on tree `58c2019`: `make e2e`
  **309 passed** (../logs/e2e-20261024-212945.log), `make
  e2e-rootless` **47 passed**
  (../logs/e2e-rootless-20261024-212945.log), both rc 0, parallel
  run (root-run script semantics changed: the interpreter-stderr
  passthroughs in fs-baseline/status/update/ddev-terminal).
- Wave-3 sabotage on the committed tree (delete-the-construct,
  observe red, restore, re-green): dropping the `;` from the drift
  pin's `tr ',;'` → fixture self-test red (zmod_d missing); a second
  `_py3_imports=` line → count pin red (found 2); deleting the
  fs-baseline probe rerun → §11f red AND the four-pass count pin red
  (1 = probe only, no rerun); re-adding the resolve pipe's
  `2>/dev/null` → line-shape pin + behavioral passthrough pin red.
  Restores verified green (fs-baseline, install-args, update-flags,
  sandbox-policy all rc 0 on the restored tree).
- Pre-commit accidental reds (observed, each fixed in the same
  wave): the coverage pin caught the zero-space import-strip bug
  (`importlib.util` → `lib.util`); the probe-count pin caught the
  rerun's second execution; the sandbox scanner caught the
  grep-line literal shape (5 violations → variable indirection) —
  the falsification event that separated the scanner's two shapes
  (c S1) and proved the wave-2 mechanism record true for grep lines.

- E2E discharged in-wave on tree `5333a03` (bookkeeping commit after
  the runs): `make e2e` **309 passed**
  (../logs/e2e-20261024-193644.log), `make e2e-rootless` **47 passed**
  (../logs/e2e-rootless-20261024-193644.log), both rc 0, run in
  parallel after the wave commit. Test-only follow-up in the
  bookkeeping commit: the §11c/§11e fixtures' 1 MiB NUL streams
  spilled onto the suite's stdout (spotted live by the maintainer's
  terminal run) — silenced with `>/dev/null` redirects; no assertion
  or shipped-code change.
- External-terminal confirmation: the maintainer ran the fs-baseline
  suite in a real developer terminal (the sandbox-vs-terminal axis the
  dash/bash kill divergence made relevant): **Passed: 80, zero FAILs**,
  including both §11e ctrl-c pins — log archived at
  /tmp/opencode/.trash/20261024-194006/…/~log.txt on the session host.
- Wave-2 e2e discharged on tree `25f96f1`: `make e2e` **309 passed**
  (../logs/e2e-20261024-202817.log), `make e2e-rootless` **47
  passed** (../logs/e2e-rootless-20261024-202817.log), both rc 0,
  parallel run after the wave commit (install.sh gate behavior
  change — the union probe and the diagnostic passthrough). Sabotage
  on the committed tree: dropping `threading` or `pathlib` from
  `_py3_imports` turns the drift pin red naming the module;
  restored, suites green.
- Maintainer issues filed from this chain (refs recorded per the
  a-wave handover note): #248 update.sh timeout presence probes,
  #249 kit-wide `-I` hardening (a W5 scope), #250 install.sh's silent
  `fs_baseline_root` stub on incomplete lib source (pre-existing,
  snapshot-a coverage), #251 test-fs-baseline 7b/8 renumbering
  (a Q6).
- Kit-wide `-I` hardening candidate: update.sh resolve, ddev-terminal,
  wrapper tools_from_config, status.sh remain env-sensitive but
  fail-loud/cosmetic — optional future wave, out of scope here.
