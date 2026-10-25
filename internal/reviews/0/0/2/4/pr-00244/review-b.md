<!-- review-meta
ID: pr-00244
Snapshot: b
Subject: issue-223 fix-wave 1 dispositions (wave review of the a-round fixes)
Scope: wave
Base: 0.0.56+56 @ 888ab0e (VERSION 0.0.56)
Diff: 888ab0e..2a2f6aa
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/W/Q, glm-5.3-flash) — session C of the rotation (fix commits 5333a03/2a2f6aa authored by session B)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review b — wave review of the fix wave (pr-00244)

Round b over the fix-wave diff `888ab0e..2a2f6aa` (two commits:
`5333a03` the dispositions — installer `_py3_health_probe` with `-I`
health probing, `-I` isolation on the fs-baseline probe and counter
tee, the `aborted` flag, the rewritten pipefail rc-contract comment,
docs wording, pins §11c rework + §11d/§11e + the installer gate
matrix; `2a2f6aa` bookkeeping — SHA fills, e2e discharge record,
fixture stdout hygiene). The wave answers review-a's 16 IDs (12
unique findings); S3/W5/Q6 deliberately not done.

Tree `2a2f6aa`, clean (`git status --porcelain` empty before and after
the fan-out; no mutation window — reviewers were readers only).

## Findings index (combined)

9 reported IDs, 8 unique findings (one cross-axis duplicate pair:
W1=Q1 — kept verbatim per axis, dispositioned once).

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | LOW | `-I` isolation claims overstate the residual env surface: the loader route (LD_PRELOAD), the PATH-resolved binary, and system dist-packages/.pth execution all still reach the probe and tee | fix-introduced (new claims) |
| S2 | LOW | Installer gate hard-aborts on hosts whose python3 only works WITH env (`-I` health) while the shipped consumers it gates still run plain env-dependent `python3` — and the gate hides the probe's stderr and names only shim/corrupt classes | fix-induced |
| S3 | INFO | `_py3_health_probe` is the first root execution of python3 in install.sh (pre-wave it only stat'ed the PATH) — a new earlier root-exec moment, established trust surface | wave-introduced |
| W1 | LOW | Installer probe comment claims its imports are "the union of the kit's shipped import surface" — the shipped surface also includes `threading`/`time` (status.sh) and `importlib.util`/`stat`/`tempfile` (tui-register.py) which the probe never exercises (dup of Q1) | fix-induced |
| W2 | LOW | §11e pins go vacuously green on a host without `setsid` — no in-suite guard, asymmetric with §11c's `command -v bash` guard | fix-induced |
| W3 | LOW | §11e cannot positively verify the KeyboardInterrupt arm executed — a startup chain slower than `sleep 1` yields both asserts trivially green with the named path unexercised | fix-induced |
| W4 | INFO | Commit 5333a03's trailer "(#244 a S1-S4 W1-W6 Q1-Q6)" lists all 12 IDs without marking S3/W5/Q6 deliberately-not-done — readable as full coverage from git log alone | fix-induced |
| Q1 | MED | install.sh + resolution.md claim the gate's import list is "the union of the kit's shipped import surface" — it is a strict subset: status.sh (`threading`, `time`), opk (`pathlib`), tui-register.py (`importlib.util`, `stat`, `tempfile`) all import modules the gate never probes (dup of W1) | fix-induced |
| Q2 | INFO | Dead parameter in the new installer matrix helper: `_p3d="$1"` is assigned in `_py3case` and never used — all four call sites pass a description that goes nowhere | fix-induced |

Provenance split: 8 fix-induced/fix-introduced (the reviewed fix
wave's own output), 0 pre-existing, 0 delta-introduced. No HIGH; one
MED (Q1) — the stop rule reads MED/HIGH, so dispositions that touch
review-relevant code extend the loop.

---

## Axis S (security), verbatim

# Security review — pr-00244 fix wave `888ab0e..2a2f6aa`, axis S

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | `-I` isolation claims overstate the residual env surface: the loader route (LD_PRELOAD), the PATH-resolved binary, and system dist-packages/.pth execution all still reach the probe and tee | fix-introduced (new claims) |
| S2 | LOW | Installer gate hard-aborts on hosts whose python3 only works WITH env (`-I` health) while the shipped consumers it gates still run plain env-dependent `python3` — and the gate hides the probe's stderr and names only shim/corrupt classes | fix-induced |
| S3 | INFO | `_py3_health_probe` is the first root execution of python3 in install.sh (pre-wave it only stat'ed the PATH) — a new earlier root-exec moment, established trust surface | wave-introduced |

## Details

### S1 — LOW · `-I` claims overstate: "env poison cannot reach" names a guarantee `-I` does not make

Evidence — `files/opencode-permissions-kit-lib/sh/fs-baseline.sh:103-107`:
```
# also RUNS it — isolated: `python3 -I` ignores PYTHONHOME/PYTHONPATH
# (#244 a S1), so neither breaking nor functional (module-shadowing)
# env poison can reach the probe or the tee; the imports are exactly
# the tee's.
```
and `internal/reviews/0/0/2/4/pr-00244/resolution.md:66-68`: "`-I` closes the env route entirely: PYTHONHOME and PYTHONPATH are ignored by both probe and tee, so neither breaking nor functional (module-shadowing) poison reaches them."

The PYTHON\*-scoped part is correct (probed live: `PYTHONHOME=/nonexistent` breaks startup rc 1 without `-I`, ignored with; a hostile `json.py` on PYTHONPATH fires rc 9 without `-I`, rc 0 with; the `os.py` shadow is indeed vacuous even without `-I` — rc 0 both ways). But "env poison cannot reach the probe or the tee" reads broader than `-I`'s actual guarantee, and the resolution's "closes the env route entirely" is stronger still. Residual routes, verified in `/tmp`:

- **Loader env**: `env LD_PRELOAD=/nonexistent-poison.so python3 -I -c 'import os, sys'` still makes ld.so process the variable (`ERROR: ld.so: object '/nonexistent-poison.so' … cannot be preloaded`). A real hostile `.so` preloads and runs its constructors inside the root python3 process regardless of `-I`. Same class: `LD_LIBRARY_PATH`.
- **The binary itself**: both probe and tee run `python3` resolved from root's PATH — env-shaped, not covered by any `-I` flag.
- **System site dirs**: `python3 -I -c` on this host still carries `/usr/local/lib/python3.12/dist-packages` and `/usr/lib/python3/dist-packages` on `sys.path` — `.pth` files there execute at startup. Root-owned, so the resolution's own residual ("an attacker who can write into the SYSTEM stdlib directory is root already") covers the trust boundary, but the route is site-packages/.pth, not "stdlib directory" — they are different directories with different writers (distro packages vs. hand-installed modules).
- The env vars are ignored at startup but still **present**: `os.environ.get("PYTHONPATH")` inside the `-c` body returns the poison path. Harmless today (the tee script touches no env), but "cannot reach" is a code-shape claim a future edit could rely on.

Conditions, named: through the kit's own boundary none of these survive — `sudoers.template:29` env_keeps only `DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME` (no `PYTHON*`, no `LD_*`, no `secure_path` directive of its own), so the routes are reachable only via `sudo -E`/`sudo -s` installs, admin-added env_keep, or a root shell environment — the same residual trigger set review-a S1 recorded. The shipped install.sh comment (`files/install.sh:549-550`) scopes its claim correctly ("PYTHONHOME/PYTHONPATH poison cannot reach it"); it is the fs-baseline sentence and the resolution wording that overreach. Why it matters: the comment is the shipped rationale for the isolation design; a future maintainer reading "env poison cannot reach" has no reason to keep `env_keep` audits or think twice about `sudo -E` installs. Code itself strictly reduces surface — this is a claim-accuracy finding only.

### S2 — LOW · gate requires an env-independent python3 while the consumers it gates still accept env-dependent ones; failure class unnameable by the error

Evidence — `files/install.sh:558-561`:
```
    if ! python3 -I -c 'import fnmatch, json, os, re, sys' >/dev/null 2>&1; then
        ui_error "python3 is present but broken (a shim to a removed interpreter? a corrupt install?) — fix it, then re-run."
        exit 1
    fi
```
The gate tests health **under `-I`**. The consumers it gates do not run `-I`: the jsonc parser (`opencode-as-opencode:444` — plain `python3 …/jsonc-parser.py`), the ddev describe get (`ddev-terminal.sh:72`), update's version resolve (`update.sh:1154`) — all run with the environment intact, and a python3 that works only *via* env serves them fine. Kit-wide `-I` hardening is recorded as an optional future wave (`resolution.md:188-190`), so until it lands the gate is stricter than the runtime it gates. Realistic trigger: root PATH resolves to a relocated/embedded build that only works with `PYTHONHOME` set (classic moved `/usr/local/bin/python3`), or a wrapper earlier in root PATH that exports `PYTHONPATH` before exec. On such a host, pre-wave the install completed (and the pre-`-I` tee even worked *with* the env); post-wave install aborts rc 1. This is the intended W1 hard-fail — but the wave's disposition record does not name this acceptance cost, and two things aggravate it: the probe's stderr — which on exactly these hosts prints the real diagnostic ("Could not find platform independent libraries …") — is discarded (`>/dev/null 2>&1`), and the message names only "a shim to a removed interpreter? a corrupt install?", never env dependence, so the user cannot self-diagnose the actual cause. Severity LOW on the supported baselines (Debian 12/Ubuntu 22.04 system python3 is env-independent — the gate passes there); the class exists wherever an earlier-PATH exotic python3 does.

### S3 — INFO · first root execution of python3 in install.sh

Evidence — `files/install.sh:558` (`python3 -I -c 'import fnmatch, json, os, re, sys'`) vs the pre-wave gate (diff hunk at `files/install.sh:682-691` old side: `command -v python3` only — presence check, no execution). Review-a W1 recorded the old state as "install.sh … *runs* the interpreter nowhere". The wave makes the installer execute the PATH-resolved binary as root for the first time (curl|sudo bash context). Not a reachable hole: resolution under the documented invocation is sudo `secure_path` (root-managed dirs), the kit's sudoers grants only per-binary RunAs rules so the agent user cannot shape the probe's PATH, and the installed kit already runs python3 as root at every `opk update`/fs-baseline — the same binary, the same trust. Recorded because it is a new earlier root-exec moment (with the usual theoretical `command -v`→execution window) that neither the diff comment nor the resolution names; behavior change, not defect.

## Verified clean (checkpoint-backed)

- **Fail direction of both gates**: fs-baseline probe degrades counter-only (cat fallback, pass data intact via find's temp file, `fs-baseline.sh:244-246,270-284`); installer gate aborts rc 1 with two distinct ui_error classes. No new silent path.
- **rc-contract comment claims are true this time**: pipefail enablement confirmed at `install.sh:47`, `config.sh:28`, `update.sh:39`; `_fsbp_rc` capture at `fs-baseline.sh:284/296` folds the tee rc under pipefail callers; anchors resolve.
- **No vacuous pins among the new ones** (blind-spot sweep): §11d's `'entries — done'` grep goes red under sabotage (PYTHONHOME poison breaks startup without `-I` → fallback → no counters, warn present — probed: rc 1 without `-I`); the installer matrix's `json.py` vehicle fires without `-I` (rc 9, probed live) and the poisoned-case pin quotes the abort; §11c's no-completion-line assert discriminates exactly the `aborted` fix; the §11e kill-chain `|| true` cannot green-ify — a wholly failed kill leaves the tee blocked until the writer's `sleep 10` EOF, normal finish, completion line → the no-`'— done'` assert goes red; the §11e wrapper-execv restores SIGINT so the KI arm can actually fire (maintainer-terminal confirmation recorded in resolution.md:183-187).
- **Test sandbox**: §11d/§11e write only under `$WORK`; installer matrix writes only under `$_py3w` with the guarded `rm -f "${_py3w:?}/err"`; §11e's `setsid`/`execv`/`kill -INT -PID` targets only the suite's own child process group; no root, no tree writes.
- **`eval` of extracted function** (matrix) follows the pre-existing `_distro_gate` pattern on a repo-controlled file; truncation of the extraction range fails the pins loud.
- **`-I` also closes the cwd/script-dir route** for the `-c` scripts (isolated mode excludes them from `sys.path`), on top of the PYTHON\* route the wave claims.
- **Sibling classification spot-check** (resolution Follow-ups): `update.sh:1152-1160` resolve is rc-checked, fails to an announced warn, binary untouched, and `json.load` treats the curl'd registry body as data — no false-green, no code-exec route. The `opencode-as-opencode`/`status.sh` classifications accepted from review-a's verified snapshot W-report (not deep-read here — see coverage).

## Coverage

Covered: full fix-wave diff (install.sh, fs-baseline.sh, docs/getting-started.md, both test files) plus the bookkeeping commit's fixture redirects; probe/tee/`_fsb_pass` with surrounding context; the three rc-contract anchors verified verbatim; sudoers template env posture; §11c/§11d/§11e and the installer matrix read as code with firing-mechanism probes run in `/tmp/opencode/s-probe` (PYTHONHOME/PYTHONPATH/json.py/LD_PRELOAD/site-packages/environ-visibility); the resolution's "vacuous-pin correction" independently reproduced (os.py shadow never fires); update.sh resolve sibling verified at source; import-union claim verified against `jsonc-parser.py:19-22` and `ddev-terminal.sh:73-74`. Deferred: no suites or make targets run (forbidden — main session ran the gates); install.sh/config.sh/update.sh read only at call sites (wave-scope budget); `opencode-as-opencode`/`status.sh` sibling sites accepted from review-a's already-verified W-classification after citing-line spot-checks, not deep-read; Ubuntu 22.04's 3.10 `-P`/cwd exact behavior taken from documented isolated-mode semantics (3.4+), not probed on that interpreter. Checkpoints written after every section to `/tmp/opencode/pr-00244-b/checkpoints/s-security.md`.

---

## Axis W (mechanical sweep), verbatim

# Mechanical sweep — fix wave `888ab0e..2a2f6aa` (pr-00244 a), axis W

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | LOW | Installer probe comment claims its imports are "the union of the kit's shipped import surface" — the shipped surface also includes `threading`/`time` (status.sh) and `importlib.util`/`stat`/`tempfile` (tui-register.py) which the probe never exercises | fix-induced |
| W2 | LOW | §11e pins go vacuously green on a host without `setsid` — no in-suite guard, asymmetric with §11c's `command -v bash` guard | fix-induced |
| W3 | LOW | §11e cannot positively verify the KeyboardInterrupt arm executed — a startup chain slower than `sleep 1` yields both asserts trivially green with the named path unexercised | fix-induced |
| W4 | INFO | Commit 5333a03's trailer "(#244 a S1-S4 W1-W6 Q1-Q6)" lists all 12 IDs without marking S3/W5/Q6 deliberately-not-done — readable as full coverage from git log alone | fix-induced |

No HIGH/MED findings. The fix's code changes check out against the resolution's claims at every point I could execute a check against the tree.

## Details

**W1 — LOW — import-union claim overstated.**
`files/install.sh:551-553`:
```
+# isolated (`-I`): PYTHONHOME/PYTHONPATH poison cannot reach it
+# (#244 a S1), and the imports are the union of the kit's shipped
+# import surface (jsonc parser: fnmatch/json/re/sys, the fs-baseline
+# counter tee: os/sys, ddev describe JSON: json/sys).
```
The probe (`install.sh:560`: `python3 -I -c 'import fnmatch, json, os, re, sys'`) is not the union of the shipped import surface. Also shipped and root-run: `status.sh:146` `import sys, threading, time` (twice — also `:216`), and `tui-register.py:26-31` `import importlib.util / json / os / stat / sys / tempfile`, executed as root via `uninstall.sh:316` (`run sudo python3 …/tui-register.py`) and `tui-plugin.sh:68`. None of those modules is in the probe. Why it matters: this wave's own standard (a Q1) is that shipped comments state the true contract, and `agent/learnings.md` L3 requires comment claims to be pinned — a checkable claim that is false in the general case is exactly the Q1 class in miniature. Consequence is narrow: only a python3 whose stdlib is damaged for `threading`/`tempfile`/`importlib.util` but healthy for the probe's five modules passes the gate and fails later in uninstall/tui cleanup or the status live-scan — surfaces the resolution itself already classifies fail-loud/cosmetic. Hence LOW, not MED. The same overstatement appears verbatim in `resolution.md:52-53`. Fix is a one-word comment change ("union of the root path's shipped imports" or similar), not more imports.

**W2 — LOW — §11e has no `setsid` presence guard.**
`tests/unit/test-fs-baseline.sh:695-700`:
```sh
setsid python3 -c 'import os, signal, sys
...
    /bin/sh "$LIB" "$W23KIF" >/dev/null 2>"$W23KI/err" &
W23KITEE=$!
```
If `setsid` is absent, the background command fails with `setsid: not found` (rc 127), the error text lands in `$W23KI/err`, and both asserts at `:727-735` (`grep -q 'Traceback'` / `grep -q '— done'`) match nothing → two green pins that executed nothing — the same vacuous-green shape the wave itself fixed twice elsewhere (the os.py-shadow trap, the dash kill syntax). §11c guards its equivalent environment dependency with a skip note (`:635-642`, `if command -v bash >/dev/null 2>&1; … else note`), so the asymmetry is internal to this same diff. `tests/check-host.sh:77` does check `setsid`, but only helps when the pre-flight is run; a direct `sh tests/unit/test-fs-baseline.sh` on a stripped host skips it. Trigger: any setsid-less environment running the suite directly. A `[ -n "$(command -v setsid)" ]` guard with the §11c skip-note pattern closes it.

**W3 — LOW — §11e's green cannot distinguish "KI arm executed" from "tee never started".**
`tests/unit/test-fs-baseline.sh:702-706`:
```sh
sleep 1
# No "--" before the negative pid: dash's kill builtin rejects it
...
kill -INT "-$W23KITEE" 2>/dev/null \
```
The kill fires at a fixed 1 s. Between launch and the kill, the chain must complete: wrapper python startup → `execv` → sh sourcing `$LIB` → `_fsb_py_probe`'s `python3 -I` startup → tee python startup → read loop. On a heavily loaded machine where that exceeds ~1 s, the group SIGINT lands on the post-`execv` sh or pre-handler python; the tee never reaches the except clause, `$W23KI/err` stays empty, and both asserts are trivially green — the pin passes without executing the KeyboardInterrupt arm it exists for (a W4). Conditions named: interpreter-startup chain > ~1 s, i.e. serious load thrash, not normal operation. Severity stays LOW because (a) the contract the pin guards ("Ctrl-C ends the tee silently") genuinely holds in the race scenario too, and (b) both real regressions do turn the pins red under normal timing — the resolution's sabotage record (`resolution.md:147-148`: deleting `aborted = True` → red) confirms discrimination for the reachable path. There is no positive marker available on the production surface (the tee is silent by contract), so full closure would need a fixture-observable proxy, not an assert change.

**W4 — INFO — commit trailer implies all 12 IDs were implemented.**
`git log -1 5333a03 --format=%B` (verbatim, subject-only, no body):
```
fix(#244 a): wave-1 dispositions — installer health gate + isolated tee (-I), aborted-pass flag, pipefail-comment truth, docs wording; pins §11c-11e + installer matrix (#244 a S1-S4 W1-W6 Q1-Q6)
```
The done-work enumeration in the subject matches exactly the implemented set (gate, `-I`, aborted flag, comment, docs, pins) and excludes S3/W5/Q6, and `resolution.md:21-23` carries the authoritative "deliberately not done" rows — so no disposition is factually misstated. But the trailing ID range names all 12 findings with no "not done: S3/W5/Q6" note; a reader limited to git log could take the trailer as a completion claim. The task question "does the message misstate any disposition?" — answer: no, it is silent on dispositions rather than wrong; recorded as INFO ambiguity.

## Blind-spot questions from the brief, answered

- **§11e kill-chain ending in `|| true`:** if every kill variant fails, the tee stays blocked until the writer subshell's `sleep 10` ends (~t+10 s), sees EOF, finishes normally and prints "— done" — assert 2 (`:731-735`) then goes red. The failure path is executed and observed, slowly. No vacuous outcome exists: a never-signaled tee with counted > 0 always prints the completion line.
- **`wait` on the setsid'd process:** under the suite's non-interactive sh, a `&`-launched child shares the script's pgid, so `setsid` is not a process-group leader and execs directly without forking (documented util-linux behavior) — `$W23KITEE` is the shell's child and `wait` is sound; the greps cannot run before the tee writes stderr. Residual fork case is hypothetical only (code-read, not runtime-verified).
- **Bookkeeping `>/dev/null` silencing (2a2f6aa):** diff `5333a03..2a2f6aa` verified — three redirect changes in test-fs-baseline.sh plus resolution.md fills, nothing else. What was silenced: the tee's data passthrough stdout (1 MiB NULs), never an asserted surface — both §11c asserts read `$W23BP.err` (still captured), the bash rider asserts rc only, §11e asserts read `$W23KI/err` (still captured). No assert weakened or blinded; resolution's "no assertion or shipped-code change" (`resolution.md:181-182`) is exact.
- **§11e sleep-1 race:** see W3.
- **Installer matrix:** extraction range `/^_py3_health_probe() {/,/^}/p` is sane (function contains no column-0 `}`); `${_py3w:?}` guard present on the `rm -f`; all four cases discriminate — healthy (red on over-abort), absent/broken (red on fail-open or class-conflation — the two `ui_error` strings are greped distinctly), poisoned json.py (red when `-I` dropped: shadow fires → "present but broken" → rc 1); the wiring pin is required and correctly justified (matrix stays green if the call is dropped); the count pin (`== 1`) verified live against the tree (sole survivor `install.sh:556` inside the function). Matrix sits before the file's summary gate.
- **§11c rework:** rc assert removed with an honest explanatory comment (`:616-618`); the two stderr greps discriminate (traceback → assert 1; `aborted` sabotage → completion line → assert 2); the bash rider discriminates (pre-fix traceback rc 1 would fail `W23PFRC == 0` under pipefail); the enclosing-`sh -c` stderr capture comment is accurate. Numbering 11c/11d/11e unique, ordered, all before `# --- Summary` at `:735`; `W23BPBIN` zero refs verified across tests/ and files/ (resolution claim confirmed).

## Coverage

Covered: review-a.md + resolution.md in full; all three class sweeps (`command -v python3` — 6 sites, each classification spot-read against the resolution's record: `status.sh:536` fail-visible "unknown", `status.sh:1331` "unscannable", `opk:299` loud `ui_error` else — record accurate; `python3` — `-I` at exactly the claimed 3 code sites, every non-`-I` invocation site classified as recorded; `silent` — docs/, test header, files/: the two Q2/W6 sites fixed, `sharing-group.md:71-74` accurate, all residual "silent" hits are pre-#223 history or unrelated features, no contradiction survived); full diff hunks with surrounding context (fs-baseline.sh gate/tee/except, install.sh function + call site, getting-started.md — pipefail line refs in the new comment verified exact at install.sh:47, config.sh:28, update.sh:39; import list verified against jsonc-parser.py:19-22, ddev-terminal.sh:73, tee imports); §11c/§11d/§11e and installer-matrix pin audits with named regressions; bookkeeping-commit diff; commit message vs resolution dispositions; `__pycache__` hit is `.gitignore`d, not tracked/shipped. Deferred: suites, mutations, `make` targets (forbidden for this pass); e2e log claims in resolution.md accepted as recorded (logs live outside the repo); setsid fork semantics taken from documented util-linux behavior, code-read only; sections of test-install-args.sh and test-fs-baseline.sh outside the new material not swept. Checkpoints: `/tmp/opencode/pr-00244-b/checkpoints/w-sweep.md` (5 entries, one per section).

---

## Axis Q (quality), verbatim

# Quality review — fix wave `888ab0e..2a2f6aa` (pr-00244 dispositions), axis Q

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | MED | install.sh + resolution.md claim the gate's import list is "the union of the kit's shipped import surface" — it is a strict subset: status.sh (`threading`, `time`), opk (`pathlib`), tui-register.py (`importlib.util`, `stat`, `tempfile`) all import modules the gate never probes | fix-induced |
| Q2 | INFO | Dead parameter in the new installer matrix helper: `_p3d="$1"` is assigned in `_py3case` and never used — all four call sites pass a description that goes nowhere | fix-induced |

## Details

### Q1 · MED · "union of the kit's shipped import surface" is false — the probe imports a subset of it

Evidence — `files/install.sh:548-552` (new comment):
```
# isolated (`-I`): PYTHONHOME/PYTHONPATH poison cannot reach it
# (#244 a S1), and the imports are the union of the kit's shipped
# import surface (jsonc parser: fnmatch/json/re/sys, the fs-baseline
# counter tee: os/sys, ddev describe JSON: json/sys).
```
repeated as the W1 disposition evidence in `internal/reviews/0/0/2/4/pr-00244/resolution.md:50-53` ("the union of the kit's shipped import surface (jsonc parser: fnmatch/json/re/sys; fs-baseline tee: os/sys; ddev describe: json/sys)"), while the gate at `install.sh:560` runs `python3 -I -c 'import fnmatch, json, os, re, sys'`.

Full inventory of shipped python imports under `files/` (grep-verified, all `-c` strings and `.py` files):
- `py/tui-register.py:26-31`: `importlib.util, json, os, stat, sys, tempfile` — `importlib.util`, `stat`, `tempfile` **not in the probed set**
- `management/status.sh:146` and `:216` (progress tee + its probe): `import sys, threading, time` — `threading`, `time` **not in the probed set**
- `bin/opk:301` (settings-edit heredoc): `import json, sys, pathlib` — `pathlib` **not in the probed set**
- The three enumerated components plus update.sh:1154 and status.sh:540 (`json, sys`) are covered, yes.

So the enumerated parenthetical is real but not exhaustive, and the sentence asserts it is ("the union of the kit's shipped import surface"). The true union is `{importlib.util, fnmatch, json, os, pathlib, re, stat, sys, tempfile, threading, time}`.

Why it matters: this is the same defect class the wave just fixed (a shipped comment stating the opposite of the mechanics), and it sits in the resolution ledger the next review starts from — the W1 row's key-evidence cell repeats it. A maintainer adding a new python consumer (say one importing `ssl`) will read this comment, conclude the installer gate already covers every shipped import, and not extend the probe — the claim inoculates exactly the drift it describes. Functional exposure is conditional and rare: it needs a python3 that imports the probed five but fails on `threading`/`pathlib`/`tempfile`/`importlib.util`/`stat` (stripped or partially corrupt builds); post-install consequences land in fail-loud or cosmetic paths (opk settings edit aborts loud; status.sh degrades with its own probe/warn; tui-register is best-effort labeled) — the same classification resolution.md:119-125 itself records. Trivially repairable by probing the actual union. No house rule required to flag: this is claim-vs-behavior drift in shipped text plus an inaccurate resolution evidence row, both introduced by this fix.

### Q2 · INFO · dead `_p3d` parameter in the new `_py3case` helper

Evidence — `tests/unit/test-install-args.sh:861`:
```sh
    _py3case() {
        _p3d="$1" _p3p="$2" _p3e="$3"
```
grep: `_p3d` appears exactly once in the file — the assignment. The four call sites (`:871` `healthy`, `:877` `absent`, `:883` `broken`, `:889` `poisoned`) pass a description that nothing consumes (the pass/fail messages hardcode their own text). Same shape as the wave's own S4/Q3 dead-fixture finding, one level down: sandbox-clean, zero side effect, but it invites a reader to assume the desc feeds diagnostics. Fix-induced.

## Verified clean (claims audited and confirmed)

- **Resolution ledger (rows audited per brief)**: all 12 rows ≤ 115 cols (≤ 120 met, measured); disposition verbs only `implemented` / `deliberately not done`; all `<SHA>` placeholders filled with `5333a03` (diff-verified — the bookkeeping commit is exactly the fill); all 16 review-a IDs dispositioned across the 12 rows; spot-checked evidence claims: "W23BPBIN removed; name grep: zero refs" — grep count 0 ✓; "-I now at three sites" ✓ (fs-baseline.sh:120,143; install.sh:560); "exactly 1" presence-check survivor ✓ (install.sh:556, pinned at test-install-args.sh:906-912); "four passes" ✓ (fs-baseline.sh:353-356); "${_py3w:?}" sandbox fix ✓ (test-install-args.sh:862).
- **Pipefail rc-contract comment (fs-baseline.sh:169-177) — TRUE, mechanics verified end to end**: tee is a pipeline member with `|| _fsbp_rc=$?` (fs-baseline.sh:257-299), `_fsbp_rc -ne 0` → `_FSB_ERRORS` + warn (307-311) → `return 1` (362-365); the cited anchors `install.sh:47`, `config.sh:28`, `update.sh:39` all point at the actual `(set -o pipefail) … || true` lines in the current tree; the EPIPE-exit-0 rationale holds (a consumer exiting 0 after closing early is a completed read; a dead consumer's non-zero rc fails the pass under pipefail); the §11c bash rider (test-fs-baseline.sh:634-641) pins that shape with an honest L4b skip note.
- **Vacuous-pin mechanism claim (resolution.md:73-78, test-fs-baseline.sh:648-651, test-install-args.sh:851-854) — empirically TRUE**: ran a `PYTHONPATH`-shadowed `os.py` (also as cwd) against `python3 -c 'import os'` — the stdlib os.py loaded and the shadow never fired; `os` preloaded in sys.modules at `-c` startup = True, `json` = False, so the `json.py` matrix vehicle fires without `-I` exactly as claimed.
- **§11e fixture-bug narratives match the code**: `exec 3>` on the writer subshell (:694), the SIGINT-disposition-restoring execv wrapper (:705-708), and the dash kill fix (:716-719) — dash kill claims empirically confirmed (`kill -INT -- -PGID` → rc 2 "Illegal number" under dash, rc 1 under bash; the pid form parses under dash).
- **Docs**: getting-started.md:15-19 now says "one warning says so", matching sharing-group.md:73-74 and the actual warn (fs-baseline.sh:123) — Q2/W6 resolved; install.sh:708-713 rewritten comment names only real consumers and marks the baseline as degrading (#223) — W2 resolved; cli.md:358 and ddev-integration.md:46 remain accurate.
- **Test hygiene**: test-fs-baseline.sh header (9-15) no longer says "silent" and says "one warn line — not silent"; sections 11/11b/11c/11d/11e unique, ordered, all before the Summary gate (735); the pre-existing 7b/8 numbering disorder is untouched (consistent with the Q6 disposition); §11/11b marker-file and stderr observation surfaces match production as the L1 record claims.
- **Bookkeeping**: review-a.md's only post-hoc edit is the `> Resolution:` pointer line (diff-verified); INDEX.md row regenerated consistently — status `open` is correct at this moment (snapshot b in flight, closure line not yet settable); e2e discharge claims verified against the actual logs: `logs/e2e-20261024-193644.log` tail "Passed: 309", `logs/e2e-rootless-20261024-193644.log` tail "Passed: 47"; the maintainer terminal log exists at `/tmp/opencode/.trash/20261024-194006/.../~log.txt` with "Passed: 80" and both §11e ctrl-c PASS lines; `/tmp/opencode/maketest-pr244b.log` exists (the gates record); the bookkeeping commit's only code change is the three `>/dev/null` redirects — "no assertion or shipped-code change" is true; both commit messages' claims match their diffs.

## Coverage

Covered: full diff range (both commits, incl. the bookkeeping-only diff); the union claim swept across every python import site in shipped `files/`; the pipefail rc-contract comment against `_fsb_pass`/`fs_baseline_root`/all three callers' pipefail lines; every factual assertion in the fs-baseline.sh probe/tee/except comments and the install.sh gate comment; docs (getting-started, sharing-group, cli, ddev-integration) against the warn line; test files §11–§11e and the installer matrix incl. fixture variables, numbering, and narrative-vs-code agreement; resolution rows (width, verbs, SHAs, coverage, spot-checked evidence), review-a pointer diff, INDEX row, e2e log tails, terminal-log and maketest-log existence; two empirical checks (os-shadow startup behavior, dash kill syntax). Deferred: the `0.0.45a C1` citation (test-install-args.sh:841, resolution.md:55) — `unverified`: INDEX and a folder probe found no matching case folder; the pattern itself (sed-extract + eval + subshell runner) demonstrably mirrors the `_distro_gate` block in the same file (549-557), so only the historical attribution is unconfirmed. Suggestion, not a finding (no house rule covers shipped-comment anchors — internal/reviews/README.md:169-176 scopes its content-anchor preference to review documents): the shipped pipefail comment cites bare line numbers of three OTHER files (fs-baseline.sh:170); they are correct today but rot on any edit to those files — content anchors (`grep -c 'set -o pipefail'`) would age better. Did not run any suites or make targets (per instructions). Checkpoints written to `/tmp/opencode/pr-00244-b/checkpoints/q-quality.md` after every section.

---

## Retracted/ghost findings

None. All 9 reported IDs were re-verified against the code by the
main session (greps + targeted reads + one live ld.so probe, listed
in the verification section below); none dropped, none marked
`unverified`.

## Verification (main session)

Every finding re-verified against tree `2a2f6aa` before entering this
snapshot:

- **Q1/W1**: import inventory re-run by grep over `files/` —
  `tui-register.py:26-31` (importlib.util/stat/tempfile),
  `status.sh:146,216` (threading/time), `opk:301` (pathlib) all
  outside the probe's `fnmatch, json, os, re, sys`
  (install.sh:560); the enumerated three components ARE correctly
  described (jsonc-parser.py:19-22, fs-baseline.sh:144,
  ddev-terminal.sh:73) — the false word is "union". Claim repeated
  at resolution.md:50-53. Duplicate pair confirmed same site.
- **S1**: fs-baseline.sh:103-107 and resolution.md:66-68 quotes
  confirmed verbatim; the install.sh comment (549-550) scopes to
  PYTHONHOME/PYTHONPATH and stays accurate. Live probe by the main
  session: `env LD_PRELOAD=/nonexistent-x.so python3 -I -c 'import
  os, sys'` → ld.so error line, rc 0 — the loader processed the
  variable under `-I`; a real .so would load. PYTHON\*-scoped claims
  verified true by the S reviewer's probes.
- **S2**: gate shape at install.sh:558-561 confirmed (stderr
  discarded, message names shim/corrupt classes only); consumers
  verified plain `python3` (update.sh:1154, status.sh:540, opk:301,
  ddev-terminal.sh:72, and opencode-as-opencode:444 per review-a's
  verification); kit-wide `-I` hardening recorded as future wave at
  resolution.md:188-190.
- **S3**: pre-wave presence-only gate confirmed from the diff's old
  side (install.sh:682-691 pre-image); behavior-change record, no
  reachable hole through the kit's own sudo shape.
- **W2**: §11e's `setsid` launch (test-fs-baseline.sh:695-701) has
  no guard; §11c's bash rider guards with a skip note (635-642);
  check-host.sh:77 checks setsid (pre-flight only). The vacuous path
  reasoned end to end: `setsid` absent → shell's "not found" lands
  on the command's redirected stderr → `$W23KI/err` → both greps
  empty → two green pins, nothing executed. Confirmed.
- **W3**: `sleep 1` at :702 precedes the kill chain; startup chain
  order confirmed (wrapper python → execv sh → source lib → probe →
  tee); err-empty → both greps vacuously green. No positive marker
  exists on the production surface (tee silent by contract). LOW
  under the named load condition.
- **W4**: `git log -1 5333a03 --format=%B` re-run — subject-only,
  trailer lists all 12 IDs, no not-done qualifier; resolution rows
  authoritative. INFO confirmed.
- **Q2**: `_p3d` grep — exactly one occurrence (test-install-args.sh:861,
  the assignment). Confirmed dead.
- **Q's unverified deferral resolved**: the `0.0.45a C1` citation
  resolves via `internal/reviews/0/0/1/7/pr-00171/review-c.md:145`
  ("the 0.0.45a C1 class (call-site wiring unpinned)") — the
  historical attribution exists in the corpus; no finding.

Cross-axis duplicate (W1=Q1) verified as the same underlying site —
dispositioned once in the resolution.

## Run provenance

- Host timestamps (UTC): fan-out start 2026-10-24T17:46:50Z, all
  reviewers returned by 2026-10-24T18:03:39Z. Checkpoint files
  (sandbox clocks, local +0200: 19:48–20:00) normalize inside the
  host window; launch stamps trail host start by ~2 min (subagent
  startup), no anomalies.
- Reviewer subagents: 3, model `zai-coding-plan/glm-5.3-flash`
  (fast tier per review-concept "Parallel reviewer agents"), axes
  S (security) / W (mechanical sweep) / Q (quality); checkpoint side
  files /tmp/opencode/pr-00244-b/checkpoints/{s-security,w-sweep,
  q-quality}.md — one line per completed section in each (absorbed
  into this provenance).
- Main session: GLM-5.3 (zai-coding-plan), verification duty over the
  full fix diff; no findings added by the main session beyond the
  reviewers' reports.
- Mutation windows: none — the tree stayed clean and read-only for
  the whole fan-out (`git status --porcelain` empty before and
  after; no sabotage spot-checks run this round; the S reviewer's
  and Q reviewer's /tmp probes touched only session scratch).
- Gates run by the main session on tree `2a2f6aa` (before fan-out):
  `make lint` green (ShellCheck); `sh tests/unit/test-fs-baseline.sh`
  80/80 green; `sh tests/unit/test-install-args.sh` green.
- E2E: owed by the FIX wave (root-run installer semantics — new
  abort path) and discharged IN that wave by session B on tree
  `5333a03` (make e2e 309 passed, make e2e-rootless 47 passed,
  recorded in resolution Follow-ups; log tails re-verified by the
  Q reviewer this pass). Snapshot b's round changes no code — no
  new e2e debt.
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary not on the
  agent PATH this session (recorded per RM-0078).
- Snapshot written and committed before any fix of THIS round's
  findings (the hard seam); the resolution grows their rows only
  as the next fix wave lands.
