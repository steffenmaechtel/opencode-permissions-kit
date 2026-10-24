<!-- review-meta
ID: pr-00244
Snapshot: a
Subject: issue-223 fs-baseline python3 health gate (feature wave)
Scope: wave
Base: 0.0.56+54 @ e4952dd (VERSION 0.0.56)
Diff: e4952dd..b6d9b4c
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/W/Q, glm-5.3-flash) — session B of the rotation (wave commit b6d9b4c authored by a prior session)
Skills: opk-review-pass
-->

# Review a — wave review (pr-00244)

Round a over the feature-wave diff `e4952dd..b6d9b4c` (one commit,
branch `feature/223-fsb-tee-health-gate`, birth PR #244): fs-baseline
python3 health gate for the counter tee (issue #223) — a missing or
broken interpreter degrades the tee of a MUTATING root pass to a plain
passthrough instead of killing it (xargs -r then no-oped green and the
baseline was silently not applied); BrokenPipeError/KeyboardInterrupt
clause; `cat` added to the required-tool probe; docs updates; unit
pins §11/11b/11c in tests/unit/test-fs-baseline.sh.

Tree `b6d9b4c`, clean (`git status --porcelain` empty before and after
the fan-out; no mutation window — reviewers were readers only).

## Findings index (combined)

16 reported IDs, 12 unique findings (three cross-axis duplicate pairs:
S2=W3=Q4, S4=Q3, W6=Q2 — kept verbatim per axis, dispositioned once).

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | LOW | Gate fails open on functional PYTHONPATH poison its own comment names; the new `import os` (probe + tee) is a PYTHONPATH-shadowable import where pre-wave imported only builtin `sys` | wave-introduced (surface pre-existing) |
| S2 | LOW | After a KeyboardInterrupt abort the tee still prints "N entries — done", logging a truncated pass as completed (dup of W3/Q4) | wave-introduced |
| S3 | INFO | `cat` becomes an unconditional hard dependency of every baseline run even when python3 is healthy and `cat` would never execute | wave-introduced (intentional, commented) |
| S4 | INFO | Test §11c creates and removes `W23BPBIN` without ever using it — dead fixture (dup of Q3) | wave-introduced |
| W1 | MED | install.sh's python3 "hard runtime dependency" gate is presence-only (`command -v`) — the exact findable-but-broken hole the wave's comment names; left un-gated while the runtime consequence got a gate | pre-existing |
| W2 | LOW | install.sh:685 pre-flight comment still lists "fs-baseline progress pipe" as a hard python3 dependency — stale after this wave | wave-introduced (staleness) |
| W3 | LOW | The new except clause swallows KeyboardInterrupt to completion, so a Ctrl-C'd pass logs "N entries — done" (dup of S2/Q4) | delta-introduced |
| W4 | LOW | KeyboardInterrupt is a new failure path of the except clause with no pin executing it (11c pins BrokenPipeError only) | wave-introduced |
| W5 | INFO | Broken python3 silently disables global-config container tools in `opencode-as-opencode` (fail-closed, zero signal) | pre-existing |
| W6 | INFO | getting-started.md says the baseline "degrades to silent passes", sharing-group.md says "one warning says so" — the two new doc claims disagree (dup of Q2) | wave-introduced |
| Q1 | MED | Shipped comment "the callers run without pipefail" is false: all three shipped callers enable pipefail, so the tee's rc folds into `_fsbp_rc` and the except-clause is behaviorally observable in production | wave-introduced |
| Q2 | LOW | "silent passes" (getting-started.md) and "silent-but-applied" (test header) contradict the warn line the same wave adds and pins (dup of W6) | wave-introduced |
| Q3 | LOW | `W23BPBIN` is mkdir'd and rm -rf'd but never used inside §11c — dead fixture (dup of S4) | wave-introduced |
| Q4 | INFO | The "— done" stderr line still prints after the except clause fires, reporting entries *read* (not applied) after a consumer death or Ctrl-C (dup of S2/W3) | wave-introduced |
| Q5 | INFO | §11c's rc assert ("pipeline stays green (reader rc)") cannot fail even pre-fix — the stderr grep is the only discriminator | wave-introduced |
| Q6 | INFO | Pre-existing duplicate section numbers in test-fs-baseline.sh (two "7b", two "8"); the new 11/11b/11c are unique and follow the letter-suffix precedent | pre-existing |

Provenance split: 11 wave-introduced (incl. one staleness, one
delta-introduced), 3 pre-existing (W1, W5, Q6), 1 wave-introduced with
pre-existing surface (S1).

---

## Axis S (security), verbatim

# Security review — pr-00244 wave `e4952dd..b6d9b4c`, axis S

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | python3 health gate fails OPEN on the PYTHONPATH poison class its own comment names: a functional hostile `os.py` passes the probe, and the new `import os` (probe + tee) is a PYTHONPATH-shadowable import where pre-wave imported only the builtin `sys` | wave-introduced (surface pre-existing) |
| S2 | LOW | After a `KeyboardInterrupt` abort the tee still prints "N entries — done", logging a truncated mutating pass as completed | wave-introduced |
| S3 | INFO | `cat` becomes an unconditional hard dependency of every baseline run even when python3 is healthy and `cat` would never execute | wave-introduced (intentional, commented) |
| S4 | INFO | Test §11c creates and removes `W23BPBIN` without ever using it — dead fixture code | wave-introduced |

No HIGH/MED findings. The gate's fail direction is correct, the sudo-boundary PATH/env posture checks out, and no new branch masks a pass failure's rc.

## Details

### S1 — LOW · probe fails open on functional PYTHONPATH poison; `import os` widens the shadowable surface

Evidence — `files/opencode-permissions-kit-lib/sh/fs-baseline.sh:101-118`:
```sh
# (pyenv shim to a removed version, poisoned PYTHONHOME/PYTHONPATH), so
# the probe also RUNS it (importing what the tee imports). Probed once
...
        command -v python3 >/dev/null 2>&1 \
            && python3 -c 'import os, sys' >/dev/null 2>&1 \
            && _fsb_py_ok=1
```
and the same `import os` added to the tee at `fs-baseline.sh:139-140`.

Two parts:

1. **Claim gap (fail-open).** `python3 -c 'import os, sys'` only catches PYTHONPATH poison that *breaks* the import. A PYTHONPATH entry holding a functional hostile `os.py` executes it during the probe, exits 0, and is pronounced **healthy** — the tee then imports the same module for real. The comment (line 101-102) names PYTHONPATH as a caught class; it is caught only in its non-functional form.
2. **Delta vs pre-wave.** The old tee script was `import sys` only — `sys` is compiled into the interpreter and cannot be shadowed via PYTHONPATH. The wave adds `import os` in both probe and tee; `os` resolves from `sys.path` with PYTHONPATH entries ahead of stdlib, so `os.py` shadowing is now a conventional root code-exec vector at two new sites. Interpreter-startup poisoning (PYTHONHOME/encodings) could already reach the pre-wave tee, so the fundamental surface is pre-existing; the probe adds one more root execution of it.

Trigger conditions, named: PYTHONPATH must survive into the root process that sources fs-baseline.sh. At the kit's own boundary it does not — the shipped template `files/opencode-permissions-kit-lib/templates/sudoers.template:29` env_keeps only `DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME` (no `PYTHON*`), and distro-default `secure_path` replaces the invoking user's PATH, so a hostile shim dir cannot be injected either. The residual triggers are `sudo -E`/`sudo -s` install invocations, admin-added `env_keep`, or a root shell whose environment already carries PYTHONPATH pointing at an agent-writable directory. LOW under those conditions; the realistic defect is the overstated comment plus the new shadowable import, not a reachable hole through the kit's own sudo shape.

Verified non-findings on the same axis: the probe resolves python3 from the MAIN root process (all three callers invoke `fs_baseline_root` in-process, not via per-command sudo — `install.sh:1781`, `config.sh:384,729`, `update.sh:1516`), and python3-from-PATH-as-root is not new surface (the tee executed it ungated pre-wave). The kit grants the agent only per-binary RunAs rules (`sudoers.template:32,39,48,56`), never a root shell, so the opencode user cannot shape the probe's PATH.

### S2 — LOW · truncated mutating pass logs "— done"

Evidence — `fs-baseline.sh:156-167`:
```python
except (BrokenPipeError, KeyboardInterrupt):
    ...
    os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
if counted:
    sys.stderr.write("\r    %-16s %d entries — done\n" % (label, counted))
```
A `KeyboardInterrupt` mid-pass (Ctrl-C on a large tree) exits the except clause and falls into the `if counted:` finalizer: the log shows e.g. `chgrp 5231 entries — done` for a pass that stopped at 5231 of 20000. No data-loss masking — the same SIGINT kills `sudo xargs`, whose death status the pipeline captures at `fs-baseline.sh:284` (`|| _fsbp_rc=$?`), producing the "pass hit errors" warn at 292-295, and the tee reads from find's temp file (`fs-baseline.sh:240-242`) so no read-side truncation exists — but the "— done" line contradicts the warn in anything grepping the log. Pre-wave the same abort produced a traceback instead, which was at least visibly abnormal. Cosmetic progress-fidelity regression; LOW.

### S3 — INFO · cat is now required even on the healthy-python3 path

Evidence — `fs-baseline.sh:328-333`: `for _fsb_tool in find cat chgrp chmod setfacl` with `return 1` on a miss. When python3 is healthy the fallback `cat` (`fs-baseline.sh:136`) never runs, yet a system with python3+find+chgrp+chmod+setfacl but no `cat` — which baselined fine before this wave — now aborts wholesale before walking. Intentional per the comment at 324-327 and strictly fail-closed; realistic occurrence is near-nil (`setfacl` present implies coreutils present). Recorded as a behavior change, not a defect.

### S4 — INFO · dead fixture in test §11c

Evidence — `tests/unit/test-fs-baseline.sh:611-612,623`:
```sh
W23BPBIN="$WORK/issue223-bp-bin"
mkdir -p "$W23BPBIN"
...
rm -rf "$W23BP" "$W23BPBIN"
```
The directory is created and removed but nothing ever uses it (the §11c pipeline spawns plain `sh -c "exit 0"`, not a binary from that dir). Test hygiene only.

## Verified clean (checkpoint-backed)

- **cat as data path**: byte-transparent, NUL-safe; the fallback cannot rebuild the empty-stream false-green because the stream comes from find's temp file with find's rc checked first (`fs-baseline.sh:240-241`). `xargs -r` semantics unchanged in both shapes.
- **Probe rc under `set -e`**: `_fsb_py_probe` returns 0 on every path (printf / false-condition `if`), the `&&` chain is set -e-exempt; callers update.sh/install.sh run under `set -e` — safe.
- **Warn printf**: constant literal, no `%` and no interpolation (`fs-baseline.sh:120`); the required-tool error uses `%s` with a fixed variable (`:330`). No format-string exposure.
- **devnull dup2**: affects only the tee's own fd 1 inside its fork; fd from `os.open` leaks until exit (immediate); no main-shell fd side effects.
- **No new silent-failure masking**: BrokenPipeError means the consumer is already dead, and the consumer's death status still reaches `_fsbp_rc` via the pipeline tail.
- **Test sandbox**: §11/11b/11c operate only under `$WORK` (`mktemp -d`, pure-variable `rm -rf "$WORK"`, exempt per `agent/conventions.md:150`); the fake python3 shim writes only its marker file and runs as the current user (`FS_SUDO=""`); the §11b restricted PATH consists of symlinks created inside scratch — adheres to the policy at `agent/conventions.md:122-151`.
- **Pre-existing, not worsened (not flagged)**: `install.sh:250` replaces a failed lib source with a silent `fs_baseline_root() { :; }` stub (false-green theme adjacent to this fix); the `$TMPDIR` mktemp at `fs-baseline.sh:224` — the diff adds lines above it without touching its behavior.

## Coverage

Covered: the full wave diff; `_fsb_py_probe`, `_fsb_count_tee`, `_fsb_pass`, `fs_baseline_root` in `fs-baseline.sh` with surrounding context; all sourcing call sites (install.sh, config.sh ×2, update.sh) and their invocation context (main root process, no subshell); sudoers template env posture; install.sh python3 pre-flight; status.sh sibling gate shape; tests §11/11b/11c incl. sandbox policy. Deferred: e2e suites and `make` targets (forbidden for this pass); full-file reads of install.sh/config.sh/update.sh (out of wave scope — only the touched call sites read); runtime confirmation of distro `secure_path` defaults (cited as distro-default behavior, not verified in this tree — the kit ships no sudoers `secure_path` directive of its own, `sudoers.template` read in full).

---

## Axis W (mechanical sweep), verbatim

# Mechanical sweep — wave `e4952dd..b6d9b4c` (python3 health gate, #223)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | MED | install.sh's python3 "hard runtime dependency" gate is presence-only (`command -v`) — the exact findable-but-broken hole the wave's comment names; it was left un-gated while the runtime consequence got a gate | pre-existing |
| W2 | LOW | install.sh:685 pre-flight comment still lists "fs-baseline progress pipe" as a hard python3 dependency — stale after this wave | wave-introduced (staleness) |
| W3 | LOW | The new except clause swallows KeyboardInterrupt to completion, so a Ctrl-C'd pass logs "N entries — done" | delta-introduced |
| W4 | LOW | KeyboardInterrupt is a new failure path of the except clause with no pin executing it (11c pins BrokenPipeError only) | wave-introduced |
| W5 | INFO | Broken python3 silently disables global-config container tools in `opencode-as-opencode` (fail-closed, zero signal) | pre-existing |
| W6 | INFO | getting-started.md says the baseline "degrades to silent passes", sharing-group.md says "one warning says so" — the two new doc claims disagree | wave-introduced |

## Details

**W1 — MED — presence-only python3 gate at install time.**
Evidence: `files/install.sh:685-691`:
```
    # python3 is a hard runtime dependency (fs-baseline progress pipe, ddev
    # describe JSON parsing, 2.x version resolution, status checks) — probe
    # it up front instead of failing mid-install (review 0.0.39a D8).
    if ! command -v python3 >/dev/null 2>&1; then
        ui_error "python3 is required but not installed (apt install python3)."
```
The wave's own gate comment (`files/opencode-permissions-kit-lib/sh/fs-baseline.sh:101-102`) says "`command -v` alone accepts a findable-but-broken interpreter (pyenv shim to a removed version, poisoned PYTHONHOME/PYTHONPATH)" — install.sh still relies on exactly that shape and then *runs* the interpreter nowhere. Trigger: a host with a pyenv shim or broken env installs green; the consequences surface later and are not named as python3: `update.sh:1154` `curl … | python3 -c … 2>/dev/null || true` → rc 1 → `update.sh:1269` "could not resolve the latest opencode 2.x release — binary left untouched" (attributeless warning; updates silently never upgrade until diagnosed); `ddev-terminal.sh:72` `_opk_json_get` returns empty → `opk ddev` URL opening silently degrades to plain runs, justified by a comment claiming health via the installer (`ddev-terminal.sh:67-68` "python3 is a kit prerequisite (the installer already depends on it…)", same claim in `docs/concepts/ddev-integration.md:46`). The fs-baseline false-green (the wave's target) is closed at runtime, so this is not a false-green anymore — but the installer gate is the class-2 sibling that still claims health from existence. Conditions: broken-but-present python3 at install time.

**W2 — LOW — stale hard-dependency comment.**
Evidence: `files/install.sh:685` "(fs-baseline progress pipe, ddev describe JSON parsing, …)". This wave removed fs-baseline's dependence on python3 (degrades with one warn, `fs-baseline.sh:119-121`) and updated `docs/concepts/sharing-group.md` + `docs/getting-started.md`, but this pre-flight comment still asserts the baseline pipe as a hard dependency. Comment-only, but it is the justification text for the gate flagged in W1.

**W3 — LOW — "— done" printed for an aborted pass.**
Evidence: `files/opencode-permissions-kit-lib/sh/fs-baseline.sh:154-162` — the finalize block sits OUTSIDE the try/except:
```python
except (BrokenPipeError, KeyboardInterrupt):
    ...
    os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
if counted:
    sys.stderr.write("\r    %-16s %d entries — done\n" % (label, counted))
```
Trigger: Ctrl-C on a large tree (a scenario the file itself treats as real — the #211 a F12 scratch comment, `fs-baseline.sh:224-227`). SIGINT hits the tee, KeyboardInterrupt lands in the new clause, is swallowed (no re-raise), control falls through to `if counted:` and the tee prints its completion line for a pass that was aborted mid-stream. Pre-wave this path ended in a traceback and no "done" line. Log-cosmetic only (the comment itself notes pipeline-member rc is discarded), hence LOW.

**W4 — LOW — unpinned KeyboardInterrupt path.**
Evidence: the clause at `fs-baseline.sh:154-158` catches `(BrokenPipeError, KeyboardInterrupt)`; `tests/unit/test-fs-baseline.sh` §11c (dead-consumer) executes the BrokenPipeError arm only. Per `agent/learnings.md` ("Fail-loud pins — every new `|| true`, stderr redirect, or probe pipe gets a pin that executes the failure path"), the KI arm — a distinct exception type through the same clause — has no pin (e.g. SIGINT the tee mid-stream and assert no traceback). Pin ordering itself is correct: §11/11b/11c all sit before the `# --- Summary ---` gate.

**W5 — INFO — silent fail-closed tool loss in the wrapper.**
Evidence: `files/opencode-permissions-kit-lib/bin/opencode-as-opencode:444` (`tools_from_config`: `python3 …/jsonc-parser.py --tools "$1" 2>/dev/null`) and `:464-475` — on failure the else branch rebuilds `PROJECT_TOOLS` from the project file only, with no message naming the cause; a broken python3 means global-config container tools quietly do not apply for the session. Fail-closed (fewer tools, never more), documented fallback (pre-#81), so INFO.

**W6 — INFO — contradictory new doc claims.**
Evidence: `docs/getting-started.md:16-17` "the group baseline itself degrades to silent passes without it" vs `docs/concepts/sharing-group.md:73-74` "the passes then run without the live entry counters (one warning says so)". The code prints one warning (`fs-baseline.sh:119-121`); "silent passes" reads as no output at all. Same behavior, two wordings, both added by this wave.

## Coverage

- **C1 (interpreter data paths)** — `grep -n python3 files/` (~25 hits): fs-baseline tee gated (clean); `update.sh:1154` fails via rc 1 → announced warn, binary untouched (fail-loud, clean); `status.sh:145/536/1331` cosmetic, fail-visible ("unknown"/"unscannable" branches, rc-checked); `opk:299-300` mutating settings edit has a loud `ui_error` else (clean); `uninstall.sh:316` / `tui-plugin.sh:68` best-effort cosmetic cleanup (`|| true` labeled as such); `opencode-as-opencode:444` → W5.
- **C2 (command -v)** — ~100 hits, classified: function-stub and find-only resolutions (ddev candidates, `command -v log`, timeout gating) legitimate; health-claiming: install.sh:688 (W1) plus the two comments/docs riding on it (folded into W1). status.sh:215-216 already health-probes (#221 W3 shape) — consistent twin.
- **C3 (probe lists)** — one required-tool loop exists (`fs-baseline.sh:328`); unprobed pass tools verified: xargs/mktemp-missing fail loud by rc (fs-baseline.sh:285-292), `stat`/`getfacl`/`grep` (fs-baseline.sh:40-45) degrade to redundant re-application — safe direction. No other `cat` pipeline in `files/`.
- **C4 (pins)** — all four enumerated paths pinned and before the summary gate; probe imports exactly what the tee imports (`import os, sys`) so the probe/tee coverage is equivalent; deferred as hypothetical (no realistic trigger, coverage note only): probe-passes-then-tee-dies TOCTOU.
- **C5 (docs)** — sharing-group.md and cli.md:358 accurate; ddev-integration.md:46 folded into W1; getting-started.md → W6.
- **Deferred**: `update.sh:1021/1030` presence-only `command -v timeout` (no interpreter, no data-pipeline false-green; unbounded-probe hang risk only, pre-existing, out of this wave's classes). Nothing was `unverified` — every flag above was traced to source in this pass.

---

## Axis Q (quality), verbatim

# Quality review — wave `e4952dd..b6d9b4c` (fs-baseline python3 health gate, #223)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | MED | Shipped comment "rc of a pipeline member is discarded either way — the callers run without pipefail" is false: all three shipped callers enable pipefail, so the tee's rc folds into `_fsbp_rc` and the except-clause is behaviorally observable in production | wave-introduced |
| Q2 | LOW | "silent passes" (getting-started.md) and "silent-but-applied" (test header) contradict the warn line the same wave adds and pins | wave-introduced |
| Q3 | LOW | `W23BPBIN` is mkdir'd and rm -rf'd but never used inside §11c — dead fixture | wave-introduced |
| Q4 | INFO | The "— done" stderr line still prints after the except clause fires, reporting entries *read* (not applied) after a consumer death or Ctrl-C | wave-introduced |
| Q5 | INFO | §11c's rc assert ("pipeline stays green (reader rc)") cannot fail even pre-fix — the stderr grep is the only discriminator; the message admits what it does | wave-introduced |
| Q6 | INFO | Pre-existing duplicate section numbers in test-fs-baseline.sh (two "7b", two "8"); the new 11/11b/11c are unique and follow the letter-suffix precedent | pre-existing |

## Details

**Q1 · MED · pipefail comment claim is false for every shipped caller** — `files/opencode-permissions-kit-lib/sh/fs-baseline.sh:162-163`:
```
    # anyway, so point stdout at devnull before exiting (the CPython
    # SIGPIPE idiom); rc of a pipeline member is discarded either way
    # — the callers run without pipefail.
```
Counted and read: `install.sh:47`, `config.sh:28`, `update.sh:39` all run `(set -o pipefail) 2>/dev/null && set -o pipefail || true`, and all three call `fs_baseline_root` in their **main shell** (`install.sh:1781` inside the roots loop, `config.sh:384` and `:729`, `update.sh:1516`) — no subshell anywhere. Inside `_fsb_pass` the tee pipeline is captured with `|| _fsbp_rc=$?` (fs-baseline.sh:284), so under a pipefail caller the tee's rc lands in `_fsbp_rc` → `_FSB_ERRORS` (fs-baseline.sh:292-293) → `return 1` (fs-baseline.sh:347-350) → `set -e` aborts install/update. Consequence: the except clause is **not** rc-neutral in production — pre-fix, a tee BrokenPipeError rc would have flagged the pass as failed (and aborted the driver script); post-fix it exits 0. The code change is right (xargs' rc still propagates; the removed rc was spurious), but the documented rationale is the opposite of the actual mechanics, and a future edit relying on "rc is discarded" would be misled. Unit pins observe dash (no pipefail) while production runs bash+pipefail — the test-fidelity asymmetry that let the false claim stand. Trigger: any run of install/update/config with a tee EPIPE (e.g. xargs dying early, Ctrl-C) — the exact scenario the clause was written for.

**Q2 · LOW · "silent" wording vs the warn line the wave itself adds** — `docs/getting-started.md:17`:
```
  group baseline itself degrades to silent passes without it, see
```
vs the warn the gate prints (`fs-baseline.sh:122-124`: `warn: live progress unavailable (python3 missing or broken) — passes apply without entry counters`) and the owning page's accurate phrasing (`docs/concepts/sharing-group.md:74`: "one warning says so"). A user told to expect *silent* passes will meet an unexpected warn line. Same drift in the test header, `tests/unit/test-fs-baseline.sh:10` ("silent-but-applied fallback"), which contradicts the section's own pins asserting `grep -c 'live progress unavailable'` == 1.

**Q3 · LOW · dead fixture in §11c** — `tests/unit/test-fs-baseline.sh:611,612,623`:
```sh
W23BPBIN="$WORK/issue223-bp-bin"
mkdir -p "$W23BPBIN"
...
rm -rf "$W23BP" "$W23BPBIN"
```
No other reference to `W23BPBIN` in the section (grep-verified: only these three lines). Sandbox-clean, so no side effect — pure dead code suggesting a copied fixture block.

**Q4 · INFO · done-line after the except fires** — `fs-baseline.sh:164-167`: after `os.dup2(...devnull...)`, execution falls through to `if counted:` which writes `"%d entries — done"` to **stderr** (not redirected to devnull; only stdout is). That stderr write itself cannot hit the broken pipe (only stdout was), so it doesn't contradict "must not end the tee in a traceback" — the comment's scope holds. Cosmetic residue only: after Ctrl-C or an early xargs death, logs get a "N entries — done" line where N counts bytes *read*, not entries applied. The pass still fails loudly upstream (`_fsbp_rc` from find's SIGINT rc / xargs rc), so this is log noise, not a false signal.

**Q5 · INFO · §11c rc pin cannot discriminate** — `tests/unit/test-fs-baseline.sh:614-615`: `W23BPRC` captures `... | sh -c "exit 0"` under dash (no pipefail), so it is 0 regardless of tee behavior — even the pre-fix traceback rc never surfaces. The message honestly says "(reader rc)", and the grep pin at :618 is the real discriminator (sabotage drops a Traceback into the captured `.err`), so the section does pin the failure path — the rc assert is just dead weight that can never fail.

**Q6 · INFO · pre-existing numbering disorder** — `tests/unit/test-fs-baseline.sh:227/240` both headed "# --- 8." and `:170/271` both "# --- 7b." (7b appearing *after* 8). Not this wave; noted because the wave adds 11b/11c, which are unique, ordered, and consistent with the 7b/7c letter-suffix precedent.

## Verified clean (claims audited and confirmed)

- **"four passes"**: exactly four `_fsb_pass` call sites in `fs_baseline_root` (fs-baseline.sh:338-341) — the once-per-run cache claim and the §11 "probe ran exactly once" pin are correctly shaped.
- **Probe imports match tee imports**: probe runs `python3 -c 'import os, sys'`; the tee's script (post-diff) imports `os, sys` — the "probe also RUNS it (importing what the tee imports)" claim is exact.
- **Fork claim**: every `_fsb_count_tee` call site is a pipeline member (fs-baseline.sh:242; §11c test; the header usage example) — "a cache written inside the fork dies with it" holds for all callers; `_fsb_pass`'s main-shell probe at :223 is what makes the cache stick.
- **set -e safety of the probe's AND-list**: the failing member is never the command following the final `&&` (the assignment can't fail), so no spurious abort in the callers' `set -eu` shells.
- **cat probe**: justified and placed before the walk (fs-baseline.sh:324-333); the fallback `cat` path would otherwise rebuild the empty-stream false-green, as the comment says.
- **Docs anchor**: `## Re-applying the baseline` exists at `docs/concepts/sharing-group.md:62` → the getting-started anchor resolves. RM-0100 satisfied: the owning page (sharing-group.md) changed in the same commit; `cli.md:358` describes the #221 status-scan surface and remains accurate; no stale "hard dependency" claims left anywhere (`grep 'hard dependency' docs/ files/` is empty — the wave removed the last one from fs-baseline.sh's header).
- **Citations resolve**: pr-00221 exists (`internal/reviews/0/0/2/2/pr-00221/`); W3 = `review-a.md:32` (broken python shim → 0-byte scan → false green, `_st_ddev_scan` — exactly the shape the wave imports); W6 = `review-a.md:35` (KeyboardInterrupt traceback); "W2/W6 shapes" = `resolution.md:149` (`except BrokenPipeError`); `#211 a F12` resolves via reviews-meta refs (pre-existing comment in fs-baseline.sh). `W23*` prefix is consistent across §11/11b/11c.
- **Marker discipline (L1)**: uniform — the probe pin observes via marker FILE because the production probe discards its own stderr (`>/dev/null 2>&1`), while the warn and traceback pins observe stderr because that is the production-observable surface.
- **No unintentional behavior changes** beyond Q1's misdescription: the diff's code paths (gate, cat fallback, except clause, tool list) each match their comments except where flagged.

## Coverage

Covered: full wave diff; comment-claim audit of all five named claims (one false → Q1); caller audit of install.sh/config.sh/update.sh sourcing + invocation + pipefail grep across files/ and tests/e2e (e2e hits are ddev provider fixtures and run.sh's install tee — not fs-baseline callers); docs audit incl. anchor, ownership, staleness; §11/11b/11c hygiene (fixtures, vars, numbering, messages, marker discipline); citation resolution; set -e/`set -u` interaction of the new probe. Deferred: did not run suites or `make lint` (forbidden for this review); did not read install.sh/config.sh/update.sh beyond their sourcing and call sites (wave-scope budget — the sourcing lines and call contexts read were sufficient to close Q1); CPython shutdown-flush behavior taken from the known SIGPIPE idiom, not experimentally reproduced (marked as code-read verification). Checkpoints written to /tmp/opencode/pr-00244-a/checkpoints/q-quality.md after every section.

---

## Retracted/ghost findings

None. All 16 reported IDs were re-verified against the code by the
main session (greps + targeted reads listed in the verification
section below); none dropped, none marked `unverified`.

## Verification (main session)

Every finding re-verified against tree `b6d9b4c` before entering this
snapshot:

- **Q1**: pipefail enablement confirmed at install.sh:46-48,
  config.sh:27-29, update.sh:38-40 (production runs bash via
  `curl | sudo bash`; unit tests run `sh`/dash — no pipefail there);
  main-shell call sites confirmed at install.sh:1781, config.sh:384
  and 729, update.sh:1516; the `|| _fsbp_rc=$?` capture and the
  `_FSB_ERRORS` propagation read in full (fs-baseline.sh:242-295).
- **W1/W2**: install.sh:685-691 read verbatim; consequences traced at
  update.sh:1152-1157 (curl | python3 -c … 2>/dev/null) and
  update.sh:1269-1270 (attributeless warn), ddev-terminal.sh:63-72,
  opencode-as-opencode:440-475. Pre-existing status confirmed (the
  diff touches none of these lines).
- **S1**: probe/tee import lists confirmed (old tee `import sys` only,
  new `import os, sys` at both sites); sudoers.template:29 env_keep
  list confirmed — no `PYTHON*`.
- **S2/W3/Q4**: the `if counted:` block confirmed outside the
  try/except (diff + file read); rc capture path confirmed so the
  "no data-loss masking" qualifier holds.
- **W4**: §11/11b/11c read — BrokenPipeError arm pinned (lines
  600-623), no SIGINT/KI pin anywhere in the file.
- **S4/Q3**: grep confirmed — `W23BPBIN` appears only at lines
  610-612 and 623 (create + remove, no use).
- **Q5**: pipeline shape at lines 614-617 confirmed (`| sh -c "exit
  0"` under dash → rc always 0).
- **Q6**: duplicate section headers confirmed by grep (two "7b" at
  lines 170 and 271; two "8" at 227 and 240).
- **S3, W5, W6/Q2**: code/doc quotes confirmed verbatim.

Cross-axis duplicates (S2=W3=Q4, S4=Q3, W6=Q2) verified as the same
underlying sites — dispositioned once each in the resolution.

## Run provenance

- Host timestamps (UTC): fan-out start 2026-10-24T16:49:52Z, all
  reviewers returned by 2026-10-24T17:02:19Z. Checkpoint files
  (sandbox clocks, local +0200: 18:49-19:00) normalize inside the
  host window; observed skew ≤ 2 min, no anomalies.
- Reviewer subagents: 3, model `zai-coding-plan/glm-5.3-flash`
  (fast tier per review-concept "Parallel reviewer agents"), axes
  S (security) / W (mechanical sweep) / Q (quality); checkpoint side
  files /tmp/opencode/pr-00244-a/checkpoints/{s-security,w-sweep,
  q-quality}.md — one line per completed section in each.
- Main session: GLM-5.3 (zai-coding-plan), verification duty over the
  full diff; no findings added by the main session beyond the
  reviewers' reports.
- Mutation windows: none — the tree stayed clean and read-only for
  the whole fan-out (`git status --porcelain` empty before and
  after; no sabotage spot-checks run this round).
- Gates run by the main session on tree `b6d9b4c` (before fan-out):
  `make lint` green (ShellCheck); `sh tests/unit/test-fs-baseline.sh`
  73/73 green.
- E2E (root-run semantics change → owed in-wave per AGENTS.md):
  both suites green on 2026-10-24, started after the wave commit
  (18:35 local): `make e2e` 309 passed
  (../logs/e2e-20261024-183808.log), `make e2e-rootless` 47 passed
  (../logs/e2e-rootless-20261024-184122.log) — run by the authoring
  session on this branch; log tails verified by this session.
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary not on the
  agent PATH this session (recorded per RM-0078).
- Snapshot written and committed before any fix (the hard seam); no
  resolution exists yet — the chain's first fix commit creates it.
