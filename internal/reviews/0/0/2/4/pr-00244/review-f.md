<!-- review-meta
ID: pr-00244
Snapshot: f
Subject: issue-223 fix-wave 5 dispositions (wave review of the e-round fixes)
Scope: wave
Base: 0.0.56+68 @ cebe60f (VERSION 0.0.56)
Diff: cebe60f..345547d
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/W/Q, glm-5.3-flash) — session F of the maintainer's snapshot-letter counting (fix commits f49dadd/345547d authored by session E, closed before this pass)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review f — wave review of the fix wave (pr-00244)

Round f over the e-round fix diff `cebe60f..345547d` (two commits:
`f49dadd` the dispositions — tui-plugin's unregister-cleanup guard
moves INSIDE the `_tp_sudo` invocation (`sh -c 'command -v python3 …
&& exec python3 "$@"'`, one resolution PATH for guard and execution),
the `_opk_json_get` rc-contract comment (127→0 named at the guard),
the count/dup pin pair extended to `+=` append shapes, the
healthy-noop pin rebuilt as an empty-stderr-stream assertion
(`_tps_errfile` knob), cli.md's per-step diagnostic sentence, and the
four wave-4 ledger corrections; `345547d` bookkeeping — e-row SHA
fills, wave-5 e2e discharge, 4-construct sabotage record). The wave
answers review-e's 9 IDs; all 9 implemented, none not done.

Rotation state (per the commission): the e-round session is closed;
this pass ran with fresh context over fixes authored by the closed
E-session — no rotation deviation, RM-0110 recovery not applicable.
Review-e left no open findings.

Tree `345547d`, clean (`git status --porcelain` empty before and after
the fan-out; no mutation window — reviewers were readers only).

## Findings index (combined)

13 reported IDs, 12 unique findings (1 cross-axis duplicate pair:
f W6 = f Q2 — the "12 execution sites" count sentence). All 13
verified as reported; none retracted, none dropped.

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| W1 | MED | count-pin grep `grep -cE` is NOT empty-match-guarded while the new comment claims "Both greps are guarded" (:973) — under the suite's `set -e`, a deleted/renamed `_py3_imports` assignment aborts the whole suite instead of recording the FAIL (claim wave-introduced; unguarded shape pre-existing) | wave-introduced |
| W2 | MED | S1-class sibling left unswept: `opk:299-300` keeps the caller-side `command -v` guard + `sudo -u python3` execution asymmetry the wave fixed at tui-plugin.sh — no S1-class entry in the wave-5 L2 sweep record | pre-existing site; delta-introduced sweep gap |
| S1 | LOW | new `_opk_json_get` comment claims "no caller observes the function's rc (stdout-only `$( )` consumers)" — five call sites are `$()` assignments, which DO carry the substitution's rc (the true defenses — no caller acts on it, interactive `set -e` default off, 127→0 fail-safe direction — are not what the comment says) | wave-introduced |
| W3 | LOW | dup-pin reach overstated: a same-line double-append (`_py3_imports+='a'; _py3_imports+='b'`, first token `+=`) matches neither pin (caught only collaterally); the W4 residual enumeration does not name it | wave-introduced |
| W4 | LOW | dup pin false-reds on a trailing comment naming the token (`_py3_imports='…'  # was _py3_imports+='old'`) — no comment stripping; latent (install.sh clean today) | wave-introduced |
| W5 | LOW | healthy-noop errfile `TPSWERR` never removed in-block (the merged trap covers it); the same wave's arm-B block removes its marker in-block — sibling-discipline inconsistency | wave-introduced |
| Q1 | LOW | record + f49dadd message claim "legitimate self-append stays green (no false red)" — false in composition: base assignment + separate-line self-append counts 2 → pin RED (the red is correct drift-catching; the claim is the defect) | wave-introduced |
| Q2 (=W6) | LOW | "12 execution sites, every one now classified" is the guarded+transparent CLASS count but reads as a total — re-derivation yields 15 executing lines / 13 site units; no convention reproduces 12 as a total | wave-introduced (number pre-existing in review-e) |
| S2 | INFO | `uninstall.sh:316` runs `sudo python3 tui-register.py` with no interpreter guard — the absence-noise family the wave fixed elsewhere; already named as backlog in the wave-4 record | pre-existing |
| S3 | INFO | test farms exclude `python3` by basename only (`python3.11`, `python3-config` etc. are symlinked in) — inert: `command -v python3` is an exact-name lookup | wave-introduced (test-only) |
| Q3 | INFO | cli.md's "once when the first scan starts, and again …" implies scan-first order, but the advisory-feed parse (`status.sh:542`) systematically runs before the first scan call (`:827`) in a report run | wave-introduced |
| Q4 | INFO | count-pin label "exactly one `_py3_imports` assignment" is narrower than its `\+?=` semantics (counts assignment-OR-append lines); the four-line comment above states the true reach | wave-introduced |

Provenance split: 10 wave-introduced (one of them a pre-existing site
flagged as a delta sweep gap, one a pre-existing number restated), 2
pre-existing. Severity: 2 MED, 6 LOW, 4 INFO — the first MEDs since
snapshot b. The stop rule reads MED/HIGH for severity, and any
dispositioning round that touches review-relevant code owes one more
wave review regardless of severity — the loop state is the next
round's call, not this snapshot's.

---

## Axis S (security), verbatim

# Security review — wave `cebe60f..345547d` (fix wave 5, pr-00244 / issue #223), axis S

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | Added `_opk_json_get` comment claims "no caller observes the function's rc (stdout-only `$()` consumers)" — five call sites are rc-carrying assignments | wave-introduced (f49dadd, comment-only) |
| S2 | INFO | `uninstall.sh:316` runs `sudo python3 tui-register.py` with no interpreter guard — same Q1 noise family the wave fixed elsewhere, left unswept | pre-existing (untouched by wave) |
| S3 | INFO | Test farms exclude `python3` by basename only — `python3.11`, `python3-config` etc. are symlinked in; inert for exact-name lookup | wave-introduced (test-only) |

## Details

### S1 — LOW: comment misdescribes consumer call-shape (wave-introduced)

`files/opencode-permissions-kit-lib/sh/ddev-terminal.sh:73-76` (added by this wave):

```
# diagnostic event. Absence returns 0 — pre-guard, the failed
# pipeline's rc 127 carried (#244 e S2); no caller observes the
# function's rc (stdout-only $( ) consumers; this file never exits
# the parent shell).
```

But the consumers include assignments, whose status **is** the substitution's rc: `ddev-terminal.sh:99`, `:100`, `:102`, `:103` (`_opk_su="$(_opk_json_get "$1" "$2")"` etc.) and `:122` (`_opk_bl_base="$(_opk_json_get "$_opk_bj" primary_url)"`). Only `:98`, `:148`, `:172` are truly rc-discarding (`case $(…)` / `[ "$(…)" ]`). Why it matters: the claim as worded is false; the defensible claim is "no caller *acts* on it" — which does hold (no `|| die`, no `set -e` in the rc-file context; interactive shells ignore errexit; the file has no `exit`). Comment-only, zero runtime delta, hence LOW. The other claims in the same comment verified accurate (`|| return 0` at `:80`; rc 127 pre-guard plausible for a `printf | python3` pipeline).

### S2 — INFO: unguarded sibling `sudo python3` (pre-existing, recorded as sweep residue)

`files/opencode-permissions-kit-lib/management/uninstall.sh:316-318`:

```
        run sudo python3 /usr/local/lib/opencode-permissions-kit/py/tui-register.py "$_un_dir/cli.json" \
            unregister /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx \
```

No `command -v python3` guard; with python3 absent, sudo prints `python3: command not found` to stderr — the exact "absence is legitimate mid-lifecycle" noise class (#244 d Q1) the wave's sibling sites guard against (`tui-plugin.sh:80`, `ddev-terminal.sh:80`, `update.sh:1164`). Not part of the 9 wave dispositions and not S1-shaped (it has no guard/exec split at all), so recorded as class-sweep residue, not a wave defect.

### S3 — INFO: farm loops exclude python3 by basename only (wave-introduced, test hygiene)

`tests/unit/test-tui-mode.sh` (both farm loops, arm A and arm B):

```
        [ "${_tpb##*/}" = python3 ] && continue
```

`python3.11`, `python3-config`, etc. land in `$TPSFIXA`/`$TPSABS2`. Inert: `command -v python3` is an exact-name lookup and the pins depend only on basename `python3` being absent/present, so test integrity is unaffected. The `[ -e "$_tpb" ]` guard correctly skips dangling host symlinks and unmatched globs (absent `/usr/local/bin`). No host file is ever an `ln` target; every `rm -rf` operand is a non-empty mktemp-derived scratch var. Minor: `$TPSFIXA`/`$TPSFIXB`/`$TPSMARK` are removed only in arm B's cleanup line — a mid-arm abort leaks scratch until the suite's merged EXIT trap.

## Headline change — clean on this axis (no finding)

The `sudo sh -c` compound at `tui-plugin.sh:80-82` audited in full-function context (lines 1-84) against the pre-wave shape (`bf4a76d`):

- **Quoting**: the script string is fully literal single-quoted source — no `_tp_*` expansion inside the quotes; the seven operands pass as quoted argv into `$@` (`exec python3 "$@"`, correct `$@` not `$*`), producing byte-identical python3 argv to pre-wave. `$0=tui-unregister` is cosmetic.
- **Root shell**: `sudo sh -c` as root adds no power — the same function already root-runs `mkdir`/`ln`/`chown`/`rm -rf` via `_tp_sudo` (lines 53-64). No sudoers boundary is crossed: `templates/sudoers.template:32-56` only gates Runas-**opencode** kit helpers for the developer user; install/update run as root (`install.sh:9-10,609`), whose sudo is unrestricted. If a hardened install ever ran this as the opencode user, both pre- and post-wave shapes are denied identically and swallowed by `|| true` — no delta.
- **Binary selection**: pre-wave `sudo python3` resolved via sudo's secure_path; post-wave `sudo sh` resolves via secure_path and the inner guard+exec resolve python3 in that same PATH — the executed binary is unchanged; the *guard's* view is what changed (the intended fix). The command-`-v`→`exec` micro-window exists only within one root sh reading the same PATH and requires attacker write access to a secure_path directory (already root-equivalent) — no realistic trigger.
- **Contract parity**: both shapes end `|| true`, stdout `>/dev/null`, stderr passes, absent-python3 = silent rc-1 skip. New unconditional sudo invocation (absent-python3 case) prompts nothing new — the same function's earlier sudo calls have already authenticated on every path reaching line 80.
- **Pattern consistency**: not first-of-its-kind — `install.sh:768` already uses the identical guard-inside-sudo'd-`sh -c` shape; `opk:362` (0.0.38 C23 note) and `fs-baseline.sh:276` are the other sanctioned `sh -c` sites.
- **Pins discriminate**: arm A reds under the pre-wave shape (caller guard passes → exec-context python3 missing → "not found" noise), arm B reds under any caller-side guard (marker unwritten). Stub dispatch on `$1` is correct for every sudo call the function makes (`mkdir`/`ln`/`chown`/`chown -h` stubbed or farm-exec'd, new `sh` falls through to the fixed-PATH exec).

`cli.md` sentence verified consistent with the code (absent silent at both guarded sites; broken-interpreter stderr passes at `tui-plugin.sh:82` — only stdout is discarded; `fs-baseline.sh:133` names broken python3). The `ddev-terminal.sh` hunk is comment-only; `resolution.md` is bookkeeping.

## Coverage

Covered: tui-plugin.sh full function + pre-wave comparison, operand/quoting/rc-contract map; sudoers template + wrapper route (`_tp_sudo` = plain sudo as root, no rule boundary); `sh -c`/guard class sweep across `files/` (4 `sh -c` sites; 3 guard+exec sites, only tui-plugin was sudo-split); uninstall.sh:316 and update.sh:1164 sibling verification; both farm loops, both stubs, shim, marker, errfile, all `rm -rf` operands, TUIWORK provenance (mktemp); ddev-terminal.sh comment-claims vs code; cli.md sentence vs behavior; resolution.md confirmed code-free. Deferred: runtime execution of the asymmetry pins (reader-only mandate — pin logic verified by trace, not by run); fs-baseline tee internals (out of wave diff, reviewed in earlier waves); interactive-shell errexit semantics taken from documented bash behavior, not empirically tested here (`unverified` at the empirical level only; the file-context claim stands on the absence of `exit` and `set -e` in ddev-terminal.sh).

---

## Axis W (mechanical sweep), verbatim

# Mechanical sweep — wave diff `cebe60f..345547d` (pr-00244, fix wave 5)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | MED | New comment claims both pin greps are empty-match-guarded; the count grep is not — under the suite's `set -e` a deleted assignment kills the whole suite instead of recording the FAIL | Claim wave-introduced; unguarded shape pre-existing |
| W2 | MED | S1-class sibling left unswept: opk:299-300 keeps the caller-guard + sudo-exec asymmetry the wave fixed at tui-plugin.sh:80; no S1-class entry in the wave-5 L2 sweep record | Pre-existing site; sweep gap delta-introduced |
| W3 | LOW | Dup-pin reach overstated: a same-line double-append (first token `+=`) matches neither pin; not named in the W4 residual enumeration | Wave-introduced comment |
| W4 | LOW | Dup pin false-reds on a trailing comment naming the token (`+=`/`=`); no comment stripping in the regex | Wave-introduced widening |
| W5 | LOW | Healthy-noop errfile `TPSWERR` never rm'd in-block, unlike the sibling marker `TPSMARK` in the same wave | Wave-introduced |
| W6 | INFO | "12 execution sites" is class-scoped; total distinct sites under files/ is 14 by re-derivation | Wave-introduced wording |

## Details

**W1 (MED) — unguarded count grep under `set -e`, false guard claim.**
`tests/unit/test-install-args.sh:973-974`:
```sh
    # Both greps are guarded against the empty match (L7).
    _p3asn="$(grep -cE "^[[:space:]]*_py3_imports\+?=" "$INSTALL")"
```
The suite runs `set -e` (`tests/unit/test-install-args.sh:30`), and this suite's own comments codify the `||` guard for exactly this reason (`:292` "|| captures the rc: this suite runs set -e"). `grep -c` exits 1 on zero matches; the sibling greps carry the guard (`_p3old` :932, dup :980) — the count grep does not. Empirically verified: `sh -c 'set -e; _p3asn="$(grep -cE "^[[:space:]]*_py3_imports\+?=" ./empty.txt)"; echo survived'` → rc 1, "survived" never printed. Trigger: the exact maintenance accident the pin exists to catch — the `_py3_imports` assignment deleted/renamed (count 0) — aborts the suite mid-run; the `found 0, want 1` FAIL and every downstream pin plus the tally never happen. The wave-5 sabotage (separate-line append, found 2) exercised the count=2 path, where grep exits 0 — the empty-match path was never executed. The comment asserting the guard exists is the wave-introduced defect; the unguarded shape itself predates the wave (the old `grep -c` was equally unguarded).

**W2 (MED) — S1-shape sibling at opk:299-300, unswept and undispositioned.**
`files/opencode-permissions-kit-lib/bin/opk:299-300`:
```sh
            if command -v python3 >/dev/null 2>&1 \
                && sudo -u "$_oc_duser" python3 - "$_oc_settings" <<'PYEOF'
```
This is the exact shape e S1 fixed at tui-plugin.sh:80 — the guard resolves python3 in the caller's PATH, the exec resolves in sudo's secure_path. Arms: (A) caller has python3, secure_path lacks it → sudo's not-found notice hits stderr (no redirect) and the branch falls to `ui_error "could not update $_oc_settings — remove the \"opencodeBinary\""` (:314) — a misleading diagnostic blaming the settings file; (B) caller lacks python3, secure_path has it → the guard skips an edit sudo could have performed, same ui_error. The wave-5 L2 sweep record (`internal/reviews/0/0/2/4/pr-00244/resolution.md:770-783`) lists only W2/W1/W5/W3 classes — no S1-class sweep — and no disposition (changed / deliberately-not-changed) exists for this site anywhere in the record. My `grep -rn "command -v python3" files/` sweep found no other guard+sudo-exec sibling (all other sites exec in caller context; uninstall:316 has no guard at all and is already dispositioned). Severity conditions: the failure shape is a loud-but-misleading error on the openchamber-uninstall branch, not silent corruption — MED as a declared-class sweep gap, not as a behavior regression.

**W3 (LOW) — dup-pin coverage claim overbroad; W4 residual list incomplete.**
`tests/unit/test-install-args.sh:970-972`: "The dup pin catches same-line doubles including the `+=` form". Verified by probe: `_py3_imports+='a'; _py3_imports+='b'` → count=1 (grep -c counts LINES), dup=0 — the dup regex's first token requires a bare `=` (`^[[:space:]]*_py3_imports=.*_py3_imports(\+=|=)`, :980). The shape is still caught collaterally — extractability pin reds when it is the sole line (the sed :956 extracts nothing from it), count reds (=2) when the normal assignment coexists — so no silent-divergence path exists (all 16 probed shapes checked). But the `:986-989` W4 residual enumeration names only backslash-continuation and eval-built shapes, not the first-token-`+=` double, so the stated blind-spot list is itself incomplete relative to the regexes' actual reach.

**W4 (LOW) — trailing-comment false-red on the dup pin.**
The dup regex (:980) has no comment stripping: `_py3_imports='a'  # was _py3_imports+='old'` matches `.*_py3_imports(\+=|=)` and reds the pin. Direction-safe (loud false red, trivially diagnosed). The blind-spot's stronger concern — a commented line colliding with the count pin — does not materialize: the count regex is `^`-anchored, so a full-line comment cannot match, and the pinned file is currently clean (`files/install.sh:573` is the only matching line; no trailing-comment token mentions anywhere).

**W5 (LOW) — errfile cleanup inconsistency.**
`tests/unit/test-tui-mode.sh:381` creates `TPSWERR="$TUIWORK/tps/w4.err"`; `:387` removes only `rm -rf "$TPSW"` (= `w4`), leaving `w4.err` until the suite trap (:467). The same wave's arm-B block removes its marker in-block (`rm -rf ... "$TPSMARK"` :463). Impact confined to the suite run (trap covers); flagged because the block's own sibling sets the in-block discipline.

**W6 (INFO) — "12 execution sites" reads wrong as a total.**
`resolution.md:718-719`: "12 execution sites, every one now classified in the bullet" (repeated :779-780). Re-derivation from `grep -rn python3 files/ -I`: 14 distinct execution sites — the guarded+transparent class is exactly the 12 bullet items (tui:80; fsb probe/rerun/count-tee; status probe/advisory/leak-scan/progress-tee; update:1163; ddev:81; opk:300; install:578+583), plus oao:444 and uninstall:316, which the same bullet also classifies in its later clauses. Class-scoped reading is defensible; total reading is off by two. The classification itself is complete — no site found outside the bullet (update.sh:618 is an old-layout `rm -f` list, not an invocation; remaining hits are shebangs and .py-internal strings). Both tee anchors verified genuinely probe-gated (`_fsb_count_tee` internally, fs-baseline.sh:156-159; `_st_progress_tee` at call site, status.sh:216-225).

## Verified clean (no finding)

- **Knob discipline (axis b):** `_tps_sudo` set/unset at :415/:417 and :458/:460, `_tps_errfile` at :382/:384 — unset precedes the assertion blocks, so a red pin cannot leak a knob into later blocks; default contracts preserved (`:264` `TR_SUDO="${_tps_sudo:-...}"`, merged `2>&1` at :278 for every non-healthy case).
- **Q3 pin vs old pin:** the old two-literal enumeration was replaced by rc pin (:385) + whole-stream emptiness (:386) — strictly stronger, no assertion lost. 5 new/rebuilt pins counted = the record's claim.
- **W2 claims at their sites (axis §2):** `_p3old` "no append form exists for that shape" — sound (`if ! command -v` literal has no append variant; count=1 at HEAD, guard present); extraction-sed "append after the closing quote … the count/dup pair reds it first" — sound for every probed shape.
- **Ledger anchors:** all resolve at HEAD — registry.npmjs.org curl update.sh:1162; update.sh:230; `setup-container-backend:283` (file is extensionless `bin/setup-container-backend`); opk:300; oao:444 (`2>/dev/null` :444, rc fallback per its own comment :442-443); uninstall:316; §3b sender-fixture `sleep 0.05` test-status.sh:2690.
- **Diff-wide behavior (axis §5):** tui-plugin.sh `sh -c` — operands identical to pre-wave, rc semantics preserved via `exec`, `|| true` retained, nothing expanded inside the quoted script; the only behavior change is the intended asymmetry closure. ddev-terminal.sh hunk is comment-only and its rc-contract claims verify (absence `return 0` :80; every consumer is a stdout-only `$( )` — :98-103, :122, :148, :172). cli.md per-step sentence matches the code shapes (advisory :538-542 and leak-scan :1333-1341 pass broken-interpreter stderr through presence-only guards); sharing-group.md :73-77 is order-only, correctly left unchanged.

## Coverage

Covered: all five budgeted sections — regex shape matrix (16 shapes, statically + empirically probed in `/tmp/opencode/pr-00244-f/w-probe/`), sibling-exactness claims at their sites, both new test-tui-mode blocks (knobs, farms, cleanups, pin placement), full ledger re-derivation and every anchor, and the three non-test files plus the `command -v python3` site sweep. Deferred, recorded: e2e discharge numbers (309/47, logs `20261024-231534`) — log files live outside `repo/` and were not read per scope; sabotage-restore claims — post-commit actions not re-executable from the tree, checked for text-consistency only; runtime execution of the suites — reader role, not run. Checkpoints at `/tmp/opencode/pr-00244-f/checkpoints/w-sweep.md` (one line per section, all six sections logged).

---

## Axis Q (quality), verbatim

# Quality review — wave `cebe60f..345547d` (fix wave 5, case pr-00244)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | LOW | Resolution + f49dadd message claim "legitimate self-append stays green (no false red)" — false: the new count regex matches the self-append line, so base+append reds the pin (found 2, want 1) | wave-introduced |
| Q2 | LOW | Wave-5 record restates "12 execution sites, every one now classified" — the count does not reconcile with the corrected bullet's own list (13 site units / 15 executing lines by the same grep); the classification itself is complete | wave-introduced (number pre-existing in review-e) |
| Q3 | INFO | cli.md's "once when the first scan starts, and again wherever …" implies scan-first order, but the advisory-feed diagnostic systematically fires before the first scan in a report run | wave-introduced |
| Q4 | INFO | Count-pin label "exactly one `_py3_imports` assignment" now counts assignment-OR-append lines — label narrower than the assertion it summaries | wave-introduced |

## Detail

### Q1 — LOW: "legit self-append green" probe claim contradicted by the pin's actual regex

`internal/reviews/0/0/2/4/pr-00244/resolution.md:729-731` (e W2 bullet):

> same-line double → dup RED (unchanged), legitimate self-append
> `_py3_imports="$_py3_imports, threading"` stays green (no false
> red)

Same claim in the f49dadd commit message: "(probe: same-line dup RED, separate-line count RED, legit self-append green; concealment residual scoped)", and echoed in the L1–L7 run ("append reds → W2 pair, probe-verified", resolution.md:794).

Verified in sandbox against the shipped regex (`tests/unit/test-install-args.sh:966`, `grep -cE "^[[:space:]]*_py3_imports\+?="`): the self-append line `_py3_imports="$_py3_imports, threading"` starts with `_py3_imports=` and **matches the count regex**. A file carrying the real assignment (`files/install.sh:573`) plus a separate-line self-append counts 2 → the pin fails with "found 2, want 1". Green holds only for the dup pin, or for the self-append probed in isolation (count 1) — so the recorded probe, as described, cannot have exercised the shape against a base-carrying file.

Why it matters: the pin's red here is *correct* per the pair's own documented contract (a separate-line self-append is real extraction/runtime drift — the extraction sed at :956 reads only the single-quoted first list, while the runtime executes first+self-append, and the lib-coverage pin would false-alarm on the unextracted module). But the record promises "no false red" for exactly this shape; a maintainer who later appends a module with the self-append idiom gets a red the disposition record explicitly ruled out. The realistic trigger is ordinary maintenance (appending a module to the gate list). The claim, not the code, is the defect — the same drift class (claim vs probe behavior) the e-round's W2 was raised for.

### Q2 — LOW: the "12 execution sites" count doesn't reconcile with its own corrected list

`internal/reviews/0/0/2/4/pr-00244/resolution.md` (e W1 bullet, wave-5 section): "Sweep re-derived from `grep -rn python3 files/ -I --exclude-dir=__pycache__` — 12 execution sites, every one now classified in the bullet."

Re-running that grep at tree `345547d` and counting lines that actually execute python3 (excluding comments, guards, and string/usage mentions) yields **15**: tui-plugin.sh (the `exec python3` inside the sh -c script), fs-baseline.sh:127/:137/:161, ddev-terminal.sh:81, update.sh:1163, uninstall.sh:316, status.sh:145/:218/:542/:1341, opencode-as-opencode:444, opk:300, install.sh:578/:583. Merging each probe with its rerun the way the bullet phrases them ("fs-baseline probe + rerun", "install.sh gate (b-S2 discard + rerun)") gives **13 site units**; no convention I tried (with/without the two deliberately-not-changed sites, merged or split reruns) produces 12 without silently dropping a site the bullet itself names.

Why it matters: the classification claim ("every one now classified") is true — every executing line at HEAD maps to a bucket in the corrected bullet, and I found no unclassified site. But W1's whole point was that a future sweep auditor follows the record's numbers; an auditor re-deriving 13/15 against a stated 12 cannot tell whether a site went missing again. The number originates in review-e (pre-existing there); the wave-5 restatement repeats it rather than truing it — on the wave whose disposition row says "record completed".

### Q3 — INFO: cli.md sentence's "and again" ordering implication

`docs/reference/cli.md:359-361`:

> present-but-broken `python3` names itself on the terminal — once when
> the first scan starts, and again wherever a python-backed step parses
> input (advisory feed, leak scan); a missing one stays silent.

The site enumeration is complete and per-site accurate (verified at HEAD: health probe `status.sh:216-219` cached once per run via `_st_py_checked`; advisory feed `:538/:542`; leak scan `:1333/:1341`; `_st_progress_tee` `:145` is count-only, not input parsing, and never runs a broken python3 because the probe gates it — the parenthetical's scoping is right; `advisories_ids` is only reached after the feed already parsed). The nuance: the advisory-feed block runs **before** the first scan in report order (`:542` vs the first `_st_ddev_scan` call at `:827`), so on a networked terminal run the run's first diagnostic typically comes from the advisory feed, while the sentence lists the scan site first with "again". The project tracks order claims as claims (the e-Q1 disposition explicitly treats sharing-group.md's sentence as "order-only"), so a reader inferring sequence is mildly misled — severity stays INFO because every stated site-truth is correct and the sentence does not literally assert chronology.

### Q4 — INFO: count-pin label narrower than its semantics

`tests/unit/test-install-args.sh:976/978`:

> pass "gate: exactly one _py3_imports assignment (#244 c W3, #244 e W2)"
> fail "gate: exactly one _py3_imports assignment (found $_p3asn, want 1)"

Since this wave the pin counts lines carrying an assignment **or an append** (`\+?=` extension); a red on a separate-line append reports under a label that says "assignment". The e-Q3 class was a label promising more than the assertion — this is the inverse (label describing less than the assertion checks), so the failure mode is milder: the four-line comment directly above (:962-965) states the true semantics and the "found N, want 1" output is accurate. INFO for the record; no behavior defect.

## Verified clean (no finding)

- **tui-plugin.sh comment, clause-by-clause**: "ONE resolution context" — guard (`command -v python3`) and execution (`exec python3`) both run inside the sudo'd inner sh, one PATH; "guard runs inside the sudo environment" — true; the arm descriptions match old/new behavior exactly (old arm A = not-found noise via caller-guard-pass + sudo-miss; old arm B = silent skip); "Operands pass as argv … nothing is expanded inside the quoted script" — the script text is single-quoted literals + `"$@"` only, operands byte-identical to the pre-wave argv. No accidental behavior delta: rc path (…→`|| true`→0), stdout discard, and stderr passthrough are unchanged.
- **ddev-terminal.sh comment**: `return 0` explicit (:78); caller sweep at HEAD — ddev-terminal.sh :98, :99, :100, :102, :103, :122, :148, :172 plus test-ddev-as-opencode.sh :328, :335, :349, :360, :443, :445 — every consumer is a `$()` stdout consumer, none branches on the rc; the file contains no `exit` (header contract :14-15, "never exit the parent shell", holds); "pre-guard … rc 127 carried" confirmed at `75b1aba` (bare `printf | python3` pipeline, no guard).
- **Commit trailer truth**: f49dadd's "S1-S2 W1-W5 Q1-Q3 — all implemented, none not done" is true — review-e.md's combined index lists exactly 9 unique findings (Q2 = dup of W3, Q4 = dup of S1) and all 9 have implemented rows naming f49dadd; 345547d's message matches its diff (SHA fills, Follow-ups e2e + 4-construct sabotage bullets) and its timestamps follow the wave-4 precedent exactly (log ~30 s after the fix commit; wave-4: 22:34:26 commit / 22:34:58 log).
- **Wave-4 record corrections**: the `:1157` cite is replaced by a real content anchor (registry.npmjs.org curl at update.sh:1162); update.sh:230 and setup-container-backend:283 verified current at this tree; the `:68` cite is content-anchored with correction marker.
- **Test-hunk hygiene**: `_tps_errfile`/`_tps_sudo` unset after each use; `TPSWERR` removed by the merged trap (`rm -rf "$T2X" "${TUIWORK:-}"`, :467); fixed-PATH farm loops replicate the pre-existing TPSABS idiom (:354-359); stub heredocs escape `\$1`/`\$*` correctly while baking the intended paths; both asymmetry arms discriminate in the sabotage-recorded directions; all new pins sit before their suites' trap+summary gates; no unused variables, no leftover scaffolding; the extraction-sed "FIRST list only" parenthetical is accurate in its append-shape context (the sed matches only the single-quoted assignment form).

## Coverage

**Covered:** the full wave diff (6 files) — tui-plugin.sh hunk + comment clause-verified against the surrounding function; ddev-terminal.sh comment verified against a full `_opk_json_get`/`_opk_scheme_url` caller enumeration at HEAD (including test-side and `&&`-shapes) plus the 75b1aba pre-guard source; cli.md sentence verified against every python3 site in a status run at HEAD (probe/tee/advisory/leak-scan, incl. the tee-parses-input blind spot and the sharing-group.md cross-check); both commit messages hunk-by-hunk against the diff, review-e.md's index, and the resolution's Follow-ups; dead-code/naming/placement sweep over both test hunks with sandbox probes of the new regexes. **Deferred:** the e2e (309+47) and sabotage-run claims in the Follow-ups cite `../logs/` artifacts outside my read scope (`repo/` only) — internally consistent and pattern-matching wave-4, but the runs themselves are unverified here; the "Gates" bullet's run claims (lint/make test/parity 118 rows) are likewise record-only, unverifiable from the tree.

---

## Retracted/ghost findings

None this round. All 13 reported IDs survived main-session verification
unchanged (no retraction, no drop, nothing newly marked `unverified`;
the W and Q reviewers' deferred items — e2e counts — were discharged
by the main session: log tails re-read, see run provenance).

## Verification (main session)

Every finding re-verified against tree `345547d` before entering this
snapshot (13 of 13 reported IDs confirmed as reported; 12 unique after
the one duplicate pair):

- **W1**: `set -e` confirmed at test-install-args.sh:30; the count
  grep at :974 has no `|| true` while the dup grep (:980) and the
  sibling `_p3old` grep (:933) do; the comment at :973 ("Both greps
  are guarded against the empty match (L7)") read back verbatim. My
  own probe (/tmp/opencode/pr-00244-f/verify/): `sh -c 'set -e;
  _p3asn="$(grep -cE … ./novar.txt)"; echo survived'` → rc 1,
  "survived" never printed — the abort shape reproduces exactly. The
  suite's own :83 comment codifies the class. Confirmed MED (the pin's
  failure path breaks the suite's failure observability for the exact
  maintenance accident it targets; the false guard claim is
  wave-introduced).
- **W2**: opk:299-300 read back in context (`if command -v python3 …
  && sudo -u "$_oc_duser" python3 - "$_oc_settings" <<'PYEOF'`) —
  guard resolves in the caller shell, execution via sudo's own
  command resolution; both arms land on the misleading ui_error at
  :314-315 as reported. The wave-5 L2 sweep record
  (resolution.md:770-783) lists the W2/W1-W5/W3 classes — no S1-class
  sweep; review-e's S1 analysis ("the two other guard sites:
  update.sh:1161 and ddev-terminal.sh:77") itself missed this site —
  the blind spot predates the fix and the fix repeated it. My own
  `grep -rn "command -v python3" files/` agrees: no other
  guard+sudo-exec sibling. Confirmed MED (declared-class sweep gap,
  RM-0069; failure shape a misleading ui_error, not silent
  corruption).
- **S1**: the comment confirmed verbatim at ddev-terminal.sh:73-76;
  the five assignment consumers confirmed by my own read (:99, :100,
  :102, :103, :122 — `$()` assignments carry the substitution's rc
  under `set -e`). The defensible claims (no caller acts on the rc;
  interactive shells don't run `set -e` by default; the file never
  exits the parent shell; 127→0 is the fail-safe direction — the
  e-round's S2 verification made exactly this nuance) are not what
  the comment says. Note: the Q reviewer's clean verdict on the same
  comment verified the caller-ENUMERATION facet (all `$()`-shaped,
  none branches on rc) — both true; S1's rc-observability facet is
  the finding. Confirmed LOW.
- **W3**: my probe: `_py3_imports+='a'; _py3_imports+='b'` → count
  pin 1, dup pin empty (both green); the collateral catches verified
  (sole line → extraction sed :956 yields nothing → extractability
  pin reds; base + line → count 2). The comment at :970-971 ("The
  dup pin catches same-line doubles including the `+=` form") and the
  residual at :986-989 read back — the first-token-`+=` double is
  unnamed. Confirmed LOW.
- **W4**: my probe: `_py3_imports='import os'  # was
  _py3_imports+='old' …` → dup pin RED (false positive,
  direction-safe). install.sh:573 read back — the sole assignment
  line, no trailing comment; no collision today. Latent. Confirmed
  LOW.
- **W5**: TPSWERR lifecycle confirmed (created :381, asserted :386,
  never removed in-block; the merged trap at :467 removes
  `${TUIWORK:-}`); the arm-B marker IS removed in-block. Confirmed
  LOW (trap-covered consistency gap).
- **Q1**: my probe: base + separate-line self-append
  (`_py3_imports='import os, sys'` +
  `_py3_imports="$_py3_imports, threading"`) → count pin 2 → RED;
  the isolated self-append → count 1, dup empty — green. The
  composition red is CORRECT per the pair's documented drift
  contract; the defect is the record's "no false red" claim
  (resolution.md:729-731, the f49dadd message, and the L1-L7 echo).
  Confirmed LOW.
- **Q2 (=W6)**: my own re-derivation
  (grep -rn python3 files/ -I --exclude-dir=__pycache__, classified
  line-by-line): 15 executing lines — the 12 guarded+transparent
  class sites + the tui `exec python3` inside the sh -c script +
  oao:444 + uninstall:316 (13 site units when probe/rerun pairs are
  merged the way the bullet phrases them). The "12" is the class-list
  count; the sentence reads as a total, and neither reviewer's
  convention (W6: 14 sites; Q2: 15 lines / 13 units) nor mine
  reproduces 12 as a total. One sentence, one defect — merged.
  Confirmed LOW.
- **S2**: uninstall.sh:316-318 read back (`run sudo python3
  …/tui-register.py … unregister …`), no guard. The wave-4 record
  already names this site as backlog (resolution.md:644-646:
  "transparent, no redirect involved: uninstall:316 — its
  absent-python3 not-found noise is pre-existing and outside this
  wave's diff, named here as backlog") — the finding corroborates the
  record rather than adding a site; recorded as reported.
  Confirmed INFO.
- **S3**: both farm loops confirmed in the diff and tree (basename
  exclusion `[ "${_tpb##*/}" = python3 ] && continue`); inert for the
  exact-name `command -v python3` lookup the inner script performs.
  Confirmed INFO.
- **Q3**: report order verified at HEAD — the advisories section
  (parse at status.sh:542, inside the block starting :358/:387)
  precedes the first `_st_ddev_scan` call (:827; the probe cache
  `_st_py_checked` is set at :214-215 inside `_st_ddev_scan`). On a
  networked report run with a broken interpreter, the advisory
  diagnostic is the run's first. The sentence's site enumeration is
  complete and per-site true (Q reviewer verified; I spot-checked the
  four sites). Confirmed INFO.
- **Q4**: the pass/fail labels at :976/:978 read back; the `\+?=`
  regex counts appends; the comment above (:965-968) states the true
  semantics. Confirmed INFO.

Cross-axis duplicate: 1 pair, exact-same-defect merge — W6/Q2 (the
"12 execution sites" sentence; one site one defect, both severities
carried — LOW taken per Q2, the record-gap class the chain has
consistently rated LOW). Distinct findings kept apart: W1 (false
guard claim + set -e abort) vs W4 (false-red shape) — different
defects of the same pin pair; W3 (blind shape, residual list gap) vs
W4 (false red) — different defects; S1 (rc observability) vs the Q
reviewer's clean caller enumeration — different facets, the finding
stands.

## Run provenance

- Host timestamps (UTC): fan-out start 2026-10-24T21:26:09Z, all
  reviewers returned by 2026-10-24T21:44:58Z. Checkpoint files
  (sandbox clocks): s-security.md 24 lines, w-sweep.md 7 lines,
  q-quality.md 7 lines — all three reviewers appended per section
  (launch + per-section + return lines); no checkpoint deviation to
  disclose this round.
- Reviewer subagents: 3, model `zai-coding-plan/glm-5.3-flash`
  (fast tier per review-concept "Parallel reviewer agents"), axes
  S (security) / W (mechanical sweep) / Q (quality); 3 concurrent
  seats (cap 5, staged single wave). Checkpoint side files
  /tmp/opencode/pr-00244-f/checkpoints/{s-security,w-sweep,
  q-quality}.md (absorbed into this provenance); reviewer probes
  under /tmp/opencode/pr-00244-f/w-probe/, main-session
  verification probes under /tmp/opencode/pr-00244-f/verify/.
- Main session: GLM-5.3 (zai-coding-plan), verification duty over
  the full fix diff; 13 of 13 reported IDs confirmed, none
  retracted, none dropped, none newly marked `unverified` (the W and
  Q reviewers' out-of-tree deferrals — the e2e log tails — were
  discharged by the main session: ../logs/e2e-20261024-231534.log
  "Passed: 309" and
  ../logs/e2e-rootless-20261024-231534.log "Passed: 47" re-read this
  pass, matching the resolution's Follow-ups record).
- Mutation windows: none — the tree stayed clean and read-only for
  the whole fan-out (`git status --porcelain` empty before and
  after; no sabotage spot-checks run this round; all probes touched
  only session scratch outside the tree). No sabotage-artifact
  screening owed. RM-0112 check: the prior snapshot's verdicts were
  reached empirically (round-e verification probes), and the e-wave's
  constructs were sabotage-verified by the E-session on the
  committed tree (resolution Follow-ups: 4 constructs red) — no
  reasoning-only verdict owed a representative execution. This
  pass's own findings were verified with executed probes in /tmp
  scratch (W1/W3/W4/Q1) and direct reads (the rest).
- Gates run by the main session on tree `345547d` (before fan-out):
  `make lint && make test` green — full suite, all suites passed,
  rules index parity OK (118 index rows). Affected suites included:
  test-tui-mode, test-install-args, test-ddev-as-opencode,
  test-status, test-update-flags, test-fs-baseline.
- E2E: owed and discharged by the e-round ITSELF on tree `f49dadd`
  (make e2e 309 passed, make e2e-rootless 47 passed, TS
  20261024-231534 — log tails re-read this pass, see above).
  Snapshot f's round changes no code — no new e2e debt.
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary at
  /usr/local/bin/opencode this session (recorded per RM-0078).
- Rotation: the e-round session was closed before this pass; this
  fresh session (F in the maintainer's snapshot-letter counting)
  reviewed the closed E-session's fixes — no deviation, RM-0110
  recovery not applicable.
- Snapshot written and committed before any fix of THIS round's
  findings (the hard seam); the resolution grows their rows only
  as the next fix wave lands.
