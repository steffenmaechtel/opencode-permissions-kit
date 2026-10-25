<!-- review-meta
ID: pr-00244
Snapshot: e
Subject: issue-223 fix-wave 4 dispositions (wave review of the d-round fixes)
Scope: wave
Base: 0.0.56+65 @ 75b1aba (VERSION 0.0.56)
Diff: 75b1aba..bf4a76d
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/W/Q, glm-5.3-flash) — session E of the maintainer's snapshot-letter counting (fix commits f198fb2/bf4a76d authored by session D, closed before this pass)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review e — wave review of the fix wave (pr-00244)

Round e over the d-round fix diff `75b1aba..bf4a76d` (two commits:
`f198fb2` the dispositions — tui-plugin's unregister cleanup joins the
S3 class (`2>&1` dropped, stdout discard kept, absence guarded),
`command -v python3` guards at update resolve and ddev
`_opk_json_get`, the same-line double-assignment pin in
test-install-args, the site-scoped resolve needle in test-update-flags,
the two wave-3 ledger corrections (sleep content anchor, residual
bullet), docs sentences on sharing-group.md and cli.md; `bf4a76d`
bookkeeping — d-row SHA fills, wave-4 e2e discharge, sabotage record).
The wave answers review-d's 9 IDs; 7 implemented, 2 (S1/S2)
deliberately not done.

Rotation state (per the commission): the d-round session is closed;
this pass ran with fresh context over fixes authored by the closed
D-session — no rotation deviation, RM-0110 recovery not applicable.
Review-d left no open findings.

Tree `bf4a76d`, clean (`git status --porcelain` empty before and after
the fan-out; no mutation window — reviewers were readers only).

## Findings index (combined)

11 reported IDs, 9 unique findings (2 cross-axis duplicate pairs:
e W3 = e Q2 stale line citation, e S1 = e Q4 guard/sudo PATH
asymmetry). All 11 verified as reported; none retracted, none dropped.

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 (=Q4) | LOW | tui-plugin's `command -v python3` guard tests the caller's PATH while `_tp_sudo` resolves python3 under sudo (secure_path) — the two can disagree in both directions (stderr noise / silent skip of the best-effort cleanup) | wave-introduced |
| S2 | INFO | commit-message claim "(absence silent, rc unchanged)" is inaccurate for `_opk_json_get`: absence rc changed 127 → 0 (no caller observes it behaviorally; delta is fail-safe-direction) | wave-introduced |
| W1 | LOW | Wave-4 record's "enumeration completed" omits the two probe-gated tee python3 execution sites (fs-baseline.sh:161, status.sh:145) — both guarded + transparent, no behavior gap; also cites "tui-plugin.sh:68" into the comment block (code at :74-76) | delta-introduced |
| W2 | LOW | Same-line pin misses the `_py3_imports+=` append shape (probe: pin green, extraction reads `import os`, runtime executes `import os import sys`); its comment's "any line naming the assignment token twice goes red" is overstated | fix-induced |
| W3 (=Q2) | LOW | W4-corrected ledger bullet cites the resolve curl at `:1157` — stale on its own carrying commit (now :1162); the exact stale-citation class its sibling W3 correction replaced with a content anchor | delta-introduced |
| W4 | INFO | `\`-continuation with a `;`-led second line and eval-built assignments evade both the count pin and the same-line pin — the pin pair's threat-model boundary (deliberate concealment, not maintenance accident) | fix-induced |
| W5 | INFO | Absence-sweep sentence "every site above guards absence except uninstall:316 and the installer gate" — oao:444, listed in the same enumeration, is also unguarded (its redirect + rc contract handle absence instead) | delta-introduced |
| Q1 | LOW | cli.md's "once when the scan starts" is true only at the scan site; the same `opk status` run can print the broken interpreter's diagnostic at up to two more sites (advisory feed parse, leak-scan parser — presence-guarded, stderr passes) | wave-introduced |
| Q3 | LOW | healthy-no-op pin's label claims "prints nothing" but its `case` enumerates only `tui-register:` and `Traceback` — any other stderr shape stays green (latent, not live) | wave-introduced |

Provenance split: 4 wave-introduced, 3 delta-introduced (record gaps
against the reviewed tree), 2 fix-induced (blind shapes of the wave's
own new pins). No HIGH, no MED: the stop rule reads MED/HIGH for
severity, and any dispositioning round that touches review-relevant
code owes one more wave review regardless of severity — the loop state
is the next round's call, not this snapshot's.

---

## Axis S (security), verbatim

# Security review — wave diff `75b1aba..bf4a76d` (issue-223 fix-wave 4)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | `command -v python3` guard checks the caller's PATH while `_tp_sudo` resolves python3 under sudo (secure_path) — guard and execution can disagree in both directions (stderr noise / silent skip) | wave-introduced |
| S2 | INFO | Commit-message claim "(absence silent, **rc unchanged**)" is inaccurate for `_opk_json_get`: absence rc changed 127 → 0 (no caller observes it behaviorally; delta is fail-safe-direction) | wave-introduced |

## Detail

### S1 — LOW: guard-vs-execution PATH asymmetry at the tui unregister compound

`files/opencode-permissions-kit-lib/sh/tui-plugin.sh:74-76`:
```sh
command -v python3 >/dev/null 2>&1 \
    && _tp_sudo python3 "$_tp_libdir/py/tui-register.py" "$_tp_user_dir/cli.json" unregister \
        "$_tp_libdir/tui/kit-mode-2x.tsx" --drop "$_tp_libdir/tui/kit-mode.tsx" >/dev/null || true
```
`_tp_sudo` is `${TR_SUDO-sudo} "$@"` (tui-plugin.sh:22) — in production, real `sudo`, which resolves `python3` via its own PATH/`secure_path`, not the caller shell's. The guard tests the caller shell's PATH only.

Probe-verified both disagreement arms (`/tmp/opencode/pr-00244-e/s-probe/probe-asym.sh`, `TR_SUDO` shim simulating secure_path with a fixed PATH):

- **Arm A** (caller PATH has python3, execution context doesn't): guard passes, `sudo` fails to find python3 — post-wave the `2>&1` drop means the shell/sudo `python3: not found` notice surfaces to the user. This partially defeats the wave's own "absence is silent" intent for this site: the *intended* silence holds only when caller PATH and sudo PATH agree. Cosmetic only — rc stays 0 (best-effort `|| true` preserved), no operand touched.
- **Arm B** (caller PATH lacks python3, sudo's secure_path has it): guard fails, unregister silently skipped where pre-wave unguarded code executed it via sudo. Bounded consequence: this is the pre-0.0.35 inert-entry cleanup only; the silent skip matches the designed absence posture, and `rm`/`chown` arms of the function are unaffected.

Realistic trigger for either arm: python3 outside the distro paths (e.g. only `/usr/local/bin` or a custom prefix) combined with a sudoers `secure_path`/env config that differs from the root shell's PATH (run via `su -`, cron, or preserved-PATH sudo). Conditions named: **LOW** because both consequences land on one best-effort line, rc 0 either way, and the symlink/chown/rm security gates (tui-plugin.sh:44-64) are PATH-independent. Note the same asymmetry does NOT exist at the two other guard sites: update.sh:1161 and ddev-terminal.sh:77 guard and execute `python3` in the same shell context (no sudo).

### S2 — INFO: rc-contract delta on `_opk_json_get` absence vs the stated intent

`files/opencode-permissions-kit-lib/sh/ddev-terminal.sh:77`: `command -v python3 >/dev/null 2>&1 || return 0`. Pre-wave, absent python3 made the pipeline (line 78) exit 127 (with a not-found notice on stderr); post-wave the function returns 0. The commit message says "(absence silent, **rc unchanged**)" — true for update.sh resolve (empty → `case *` → `return 1`, identical refusal), false for this site.

Caller enumeration (`_opk_json_get` has no callers outside ddev-terminal.sh and the tests): every production call consumes **stdout only** — ddev-terminal.sh:95, 96, 97, 99, 100, 119, 123, 145, 169. The plain assignments (96/97/99/100/119/123) do carry the substitution's rc, and the file is sourced into the developer's interactive shell where a non-zero assignment rc is observable under `set -e` — but (a) interactive shells don't run `set -e` by default and the file's header contract is "never exit the parent shell", and (b) the delta direction (127 → 0) *removes* a theoretical parent-shell kill rather than adding one. `_opk_browser_url`/`_opk_scheme_url` end in `printf`/`return 0`, so their rc was 0 before and after. No behavioral consumer — reported for the record only because it is a silent rc-contract change on the sudoers-helper-adjacent path, and the intent statement misdescribes it.

## Coverage

**Covered:** all 10 diff files — tui-plugin.sh hunk + `_tp_sudo` walk + rc/stdout/argv comparison vs 75b1aba (operands byte-identical, all quoted; `|| true` last; stdout discard kept); update.sh resolve guard + sole caller (update.sh:1278 consumes rc, warns, binary left untouched — no fail-open/fail-closed delta; guard and interpreter share one PATH context); `_opk_json_get` early return + full caller enumeration; the three test suites' new pins — symlink farms write only inside scratch with read-only host links, `ln`/`sh -c` operands quoted, `TR_SUDO` stubbed by `_tps_run` (test-tui-mode.sh:264-266) so host sudo is unreachable even though the farms symlink it, PATH-after-source ordering in the `sh -c` pin verified correct (blind-spot c); the same-line double-assignment pin is a pure static grep, fail-closed only; blind-spot (d) slash-forms checked on the new `ln -sfn "$_tpb" "$TPSABS/${_tpb##*/}"` operands (clean). tui-register.py verified silent on no-op (py/tui-register.py:123-124), so the healthy-noop pin's claim holds; its `:156` symlink-refusal stderr now surfacing in production is failure-path passthrough, covered by the commit's stated S3-class intent. Docs hunks descriptive-only; resolution.md bookkeeping. Probe-verified the S1 asymmetry concretely in both directions.

**Deferred / not covered:** no full-file read of update.sh, install.sh, or status.sh (wave scope — only the hunks' surrounding sections); behavior of real `sudo` secure_path on specific distros not tested (probe simulates it — the asymmetry conclusion holds for any sudo PATH configuration that differs from the caller's, which is the general case secure_path exists for).

---

## Axis W (mechanical sweep), verbatim

# W-sweep report — pr-00244 wave diff `75b1aba..bf4a76d` (mechanical sweep axis)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | LOW | Wave-4 record's "enumeration completed" omits the two probe-gated tee python3 execution sites (fs-baseline.sh:161, status.sh:145) | delta-introduced |
| W2 | LOW | Same-line pin misses the `_py3_imports+=` append shape; its comment's "any line naming the assignment token twice goes red" is overstated | fix-induced |
| W3 | LOW | W4-corrected ledger bullet cites the resolve curl at ":1157" — stale on its own carrying commit (now :1162) | delta-introduced |
| W4 | INFO | `\`-continuation with `;`-led second line and eval-built assignments evade both the count pin and the same-line pin | fix-induced |
| W5 | INFO | Absence-sweep sentence "every site above guards absence except uninstall:316 and the installer gate" — oao:444, listed in the same enumeration, is also unguarded (handled by redirect + rc contract instead) | delta-introduced |

## Detail

**W1 (LOW)** — `internal/reviews/0/0/2/4/pr-00244/resolution.md:617-621` claims "the python3 execution sites under files/ are now —" followed by the site list. My independent enumeration (`grep -rn python3 files/ -I --exclude-dir=__pycache__`, extensionless bin/ included) finds 12 execution sites; the record lists 10 and omits the tee consumers:
- `files/opencode-permissions-kit-lib/sh/fs-baseline.sh:161` — `python3 -I -c '` inside `_fsb_count_tee` (probe-gated at :156-159, `cat` passthrough when unhealthy)
- `files/opencode-permissions-kit-lib/management/status.sh:145` — `python3 -c '` inside `_st_progress_tee` (single caller :225, probe-gated at :214-222)

Both verified guarded + transparent (no stderr redirects), so the **class is fully covered — no behavior gap**; the record's enumeration-as-written is incomplete, which matters because a future sweep auditor following the record will not check these two sites (the round-d W1 finding was exactly this shape). Two further record imprecisions in the same bullet: "tui-plugin.sh:68" points into the comment block (code site is the guard :74 / call :75), and "oao:444" in the deliberately-unchanged bucket is correct. Everything else in the record's list matches site-for-site: fs-baseline probe :126-127 + rerun :136-137, status probe :217-218 / advisory :538,542 / leak-scan :1333,1341, update resolve :1161-1169, ddev :77-78, opk :299-300, install gate :574-583 (incl. :583 rerun), update 1.x :1176-1178 (sed, verified), uninstall:316 (verified transparent, no absence guard, honestly named backlog). No direct `py/*.py` shebang executions, no interpreter held in a variable, `_st_progress_tee` has exactly one gated caller.

**W2 (LOW)** — `tests/unit/test-install-args.sh:978` greps `^[[:space:]]*_py3_imports=.*_py3_imports=`. Probed (`/tmp/opencode/pr-00244-e/w-probe/w2-pin.sh`): `_py3_imports='import os'; _py3_imports+=' import sys'` on one line is **not red** — the regex requires a literal `=` after the token, and `+=` inserts `+`. The comment at :976-977 claims "Any line naming the assignment token twice goes red" — false for this shape. Realistic trigger: a maintainer appends a module with the `+=` idiom in a later edit; the extraction sed (:956) then reads the first list while the runtime executes first+append — the exact extraction/runtime drift the count+dup pin pair exists to prevent. Consequence is mild (drift mostly surfaces as loud false-reds in the collector check, or is benign), hence LOW. False-positive question answered: the legitimate self-append `_py3_imports="$_py3_imports, threading"` is **not** red (verified, no `=` after the inner reference); a same-line first+append combination is red, which is acceptable (it is a same-line double token line). The pin's target shape `_py3_imports='a'; _py3_imports='b'` is correctly red, and the sabotage record's claim about it checks out.

**W3 (LOW)** — `resolution.md:498` cites "the resolve pipe's curl at :1157". Verified correct on the parent tree 75b1aba, but the wave-4 commit carrying this correction itself adds the `_rlov_ver=""` and `if command -v` lines, moving the curl to `files/opencode-permissions-kit-lib/management/update.sh:1162` — the record is stale at its own commit, the exact failure shape its sibling W3 correction replaced with a content anchor ("the wave's own +75 lines had already moved it", resolution.md:490-491). The bullet's other three cites verified current: update.sh:230 ✓, `bin/setup-container-backend:283` ✓ (file is extensionless under `bin/`, sole match), oao:444 ✓. The re-run grep gives exactly those 4 python3/curl hits, so the corrected bullet's hit list is complete; the `>/dev/null 2>&1`-cannot-match parenthetical is accurate.

**W4 (INFO)** — probed bypass shapes that evade both pins: a `\`-continuation whose second physical line is led by `;` (`_py3_imports='a'; x=1 \` / `; _py3_imports='b'` — count pin stays 1, dup pin blind), and eval-built assignments (`_p3s="…"; eval "$_p3s"`). Both require deliberate concealment, not maintenance accident; an anchored continuation (second line starting with the token) **is** caught by the count pin (=2). Recorded for the pin's threat-model boundary, not actionable.

**W5 (INFO)** — `resolution.md:626-629`: "every site above guards absence except uninstall:316 … and the installer gate". The enumeration the sentence points at includes oao:444 (deliberately-unchanged bucket), which has no `command -v` guard — its `2>/dev/null` suppresses the not-found noise and its rc contract routes non-zero to the project-only-scan fallback, so absence is handled, just not by a guard. Wording imprecision only.

## Clean / verified

- **Sed-range needle (W3 axis)**: extraction of `resolve_latest_opencode_version` yields all 38 lines, no `}`-at-column-0 inside the body (function closes update.sh:1184), the needle's target pipe is inside the extraction, and the record's "same extraction range the suite's FUNCS file uses" is **verified byte-identical** (`test-update-flags.sh:114`). A partial future truncation would break FUNCS sourcing loudly via the sibling behavioral pins; only total failure is guarded, acceptable.
- **Sleep ledger bullet**: `grep -rn "sleep 0\." tests/unit/` → sole hit `tests/unit/test-status.sh:2690: sleep 0.05`, content anchor correct.
- **Docs**: both new sentences verified accurate against `fs-baseline.sh:129-138` and `status.sh:214-221`/`:1333-1345`; no same-shape stale statements elsewhere in docs/ (ddev-integration.md:46 "kit prerequisite" still true; cli.md:391 is about binaries; "best-effort" hits are unrelated features). Fractional-sleep residual re-checked in the W4 grep.
- **Behavior-change audit**: all three guarded sites preserve their rc contracts (resolve rc 1 either way, ddev miss = empty + rc 0, tui sync rc 0), each pin-asserted; the only delta beyond stderr/rc is that update resolve skips the curl request when python3 is absent — the guard's designed effect, not accidental.

## Coverage

Covered: W1 full independent python3-site enumeration vs the record (12 sites, all checked in context, including extensionless bin/, management/, shebang-route and variable-interpreter blind surfaces); W2 pin regex probed against 11 shapes; W3 sed range line-by-line + FUNCS claim; W4 both ledger greps re-run and every cited line number checked on both trees; W5 docs/ swept for stale same-shape statements + fractional-sleep residual; behavior-change audit of the full wave diff. Deferred: running the unit suites themselves (sandbox verification is the main session's to verify — my scope was static + probe); the e2e sabotage record's claims taken from resolution.md:668-683 rather than re-executed (out of a reader's budget, and the round's screening owns that). Checkpoints at `/tmp/opencode/pr-00244-e/checkpoints/w-sweep.md`, probes under `/tmp/opencode/pr-00244-e/w-probe/` — nothing in the repo was modified.

---

## Axis Q (quality), verbatim

## Quality axis — wave diff `75b1aba..bf4a76d` (pr-00244, fix wave 4)

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | LOW | cli.md's "once when the scan starts" is true only at the scan site; the same `opk status` run prints the broken interpreter's diagnostic at up to two more sites (advisory row, leak-scan) | wave-introduced |
| Q2 | LOW | W4 ledger correction cites the resolve curl at `:1157` — the pre-wave number; the wave's own edit moved it to `:1162` in the same commit (stale-on-arrival, the exact class W3 corrects) | wave-introduced |
| Q3 | LOW | healthy-no-op pin's label claims "prints nothing" but its `case` enumerates only `tui-register:` and `Traceback` — any other stderr shape stays green | wave-introduced |
| Q4 | INFO | new tui-plugin absence guard judges the *caller's* PATH while the guarded binary runs under sudo (secure_path) — the two can disagree | wave-introduced |

### Detail

**Q1 — cli.md "once" holds per-site, not per-run (LOW).**
`docs/reference/cli.md:358-360`: "A present-but-broken `python3` prints its own diagnostic to the terminal once when the scan starts; a missing one stays silent." At the scan site this is true: the probe is cached (`status.sh:214-219`, `_st_py_checked=1`) and both call sites (`status.sh:827`, `:1080`) run in the main shell (deliberate no-subshell design, "Main-shell loop via redirect (issue #158)"), so the diagnostic fires exactly once, when the first scan starts. But the page documents the whole command, and two further sites are only *presence*-guarded, so a broken interpreter passes `command -v` there too: the advisory feed parse (`status.sh:538-542`, no stderr redirect on the capture) and the leak-scan parser (`status.sh:1333-1341`, comment explicitly says stderr "passes through"). Realistic trigger: interactive `opk status`, online, installed kit, broken python3 → the same interpreter names itself ~3× per run. The sentence's count word promises a once-ness the command does not have; the wave's own S1 disposition accepts repetition on broken interpreters elsewhere (ddev site, up to ~5×/run), so the doc claim and the design stance also pull in opposite directions. Note the two new docs sentences do not collide with each other: sharing-group.md claims *order* only, not count.

**Q2 — W4 correction carries a stale line number (LOW).**
`internal/reviews/0/0/2/4/pr-00244/resolution.md` (residual bullet, f198fb2): "the resolve pipe's curl at `:1157`". Verified: at `75b1aba` the curl sits at `:1157`; at `f198fb2` (the commit carrying the correction) and in the final tree it sits at `:1162` — the guard's +6 lines pushed it down. A correction whose sibling (W3) exists precisely because a stale `:2621` citation "described the pre-wave tree" repeats that mistake on arrival. Consequence is mild: `update.sh:230`, `setup-container-backend:283`, and `opencode-as-opencode:444` all verify exactly, and the content anchor still identifies the line — but a reader grepping `:1157` lands on the Q1 comment, not the curl.

**Q3 — healthy-no-op pin under-discriminates vs its label (LOW).**
`tests/unit/test-tui-mode.sh` (healthy-noop block): the pattern is `*"tui-register:"*|*"Traceback"*` → `_tpcase=false`, while the pin and the tui-plugin.sh comment claim the cleanup "prints nothing". Any stderr line matching neither literal escapes: a future `DeprecationWarning` from tui-register.py's no-op path, a loader/libc warning, a renamed error prefix — the pin stays green while the "prints nothing" claim is false. Verified today's claim is true (tui-register.py:106-124 — `changed` accumulates silently, `if not changed: return 0`, all `print`s are on error paths; the success path prints nothing either), so this is latent, not live. The absence pin's patterns (`*"not found"*|*"Not found"*|*TPSDIAG*) are adequately discriminating: the sudo-stub does `exec "$@"` (`test-tui-mode.sh:252-257`), so a deleted guard yields a dash-shaped `python3: not found` line that reaches `_tps_out` via `_tps_run`'s `2>&1` — statically consistent with the bookkeeping's sabotage observation.

**Q4 — guard/target resolution mismatch at the tui site (INFO).**
`files/opencode-permissions-kit-lib/sh/tui-plugin.sh:74-78`: `command -v python3 >/dev/null 2>&1 && _tp_sudo python3 …`. `command -v` resolves against the caller's PATH; the actual binary is resolved by sudo's secure_path. Realistic edge: agent PATH lacking python3's directory while root's secure_path has it → guard skips a cleanup a working interpreter could have run (benign — the entries are inert, best-effort by design); or a broken shim first in caller PATH with a healthy system python3 under sudo → the W1 "names itself" transparency never fires (also benign). Consequence-free today, but the class-sweep record's "every site above guards absence" glosses over that this one site's guard tests a different resolution context than the five direct-exec sites. The other guards (update resolve, `_opk_json_get`) run python3 directly and match exactly.

### Verified clean (no finding)

- **Q1 mapping**: all 9 d-IDs appear in the ledger; W1–W4/Q1–Q3 each map to real hunks (W1 → tui-plugin.sh + tui-mode pins; W2 → install-args pin; W3/W4 → the two corrected bullets; Q1 → update.sh/ddev-terminal.sh + two absence pins; Q2 → scoped needle; Q3 → both docs hunks); no hunk lacks an ID; "S1/S2 deliberately not done" is qualified in both the trailer and the ledger rows (house rule satisfied). bf4a76d's message claims (SHA fills ×7, e2e bullet, sabotage bullet with 5 constructs / 2 runs / the `|| true` fix) all have matching resolution.md content; the `|| true` is present on the gj-abs capture.
- **Q2 evidence**: resolve rc walk verified — absence and parse-failure both land on empty `_rlov_ver` → `return 1` (and `_rlov_ver=""` is load-bearing under `set -eu`, update.sh:38); the FUNCS claim is literally true (`test-update-flags.sh:113` uses the identical sed range as the new needle); the c-S3 correction sentence accurately describes the pre-wave not-found leak.
- **Q3 other docs**: no doc claims the tui cleanup is silent or that resolve/`_opk_json_get` noise on absence exists — the wave's behavior changes falsify no other sentence I could find. sharing-group.md's order claim verified in code (`fs-baseline.sh:135-139`: guarded rerun before the `printf` warn; absent interpreter fully silent).
- **Q4 placement**: all new pins sit before their suites' summary gates (tui block ends ~:380, summary at :386; the others are mid-file with summaries at EOF); the update/ddev absence pins interpolate the captured stderr into their FAIL messages, so a red run surfaces the actual noise.
- **Q5**: no dead code (`RLV_RC=0` reset and `_rlov_ver=""` both needed; the two-step `_tpcase` dance is deliberate — the rc case alone cannot discriminate because `|| true` masks the exec failure); no stale comment vs code drift beyond Q2/Q4 above.

### Coverage & deferrals

Covered: both commit messages ID-by-ID against every hunk; all five wave-4 evidence claims against shipped code; both docs sentences plus a sweep for falsified docs; pin discrimination, placement, and the `|| true` fix; dead-code/naming sweep over the diff hunks; line-number audit of every citation in the W3/W4 corrections. Deferred/unverified: the e2e counts (309+47) and the sabotage runs' observed output in `../logs/` are outside the repo — recorded as claimed, not verified (only the record's presence and internal consistency checked); suites were not executed (reader-only role; static discrimination checks sufficed for every construct the sabotage record names); the sudo secure_path divergence (Q4) is a static POSIX fact, not empirically reproduced.

---

## Retracted/ghost findings

None this round. All 11 reported IDs survived main-session verification
unchanged (no retraction, no drop, nothing newly marked `unverified`;
the W and Q reviewers' deferred items — e2e counts, sabotage
re-execution — were discharged or anchored by the main session, see
below).

## Verification (main session)

Every finding re-verified against tree `bf4a76d` before entering this
snapshot (11 of 11 reported IDs confirmed as reported; 9 unique after
the two duplicate pairs):

- **S1 (=Q4)**: `_tp_sudo() { ${TR_SUDO-sudo} "$@"; }` confirmed at
  tui-plugin.sh:22; the guard/call compound confirmed at :74-77
  (quoted in the finding). The asymmetry is structural: `command -v`
  resolves in the caller shell, the `_tp_sudo`-wrapped python3 under
  sudo. The reviewer's probe executed both disagreement arms
  (/tmp/opencode/pr-00244-e/s-probe/) — I re-read the probe script and
  the two output arms; the mechanism reproduces. The two other guard
  sites (update.sh resolve, ddev `_opk_json_get`) guard and execute in
  one shell context — confirmed by my own reads of both hunks.
  Confirmed LOW (best-effort line, rc 0 either way).
- **S2**: ddev-terminal.sh:77 `command -v python3 … || return 0`
  confirmed; pre-wave absence made the `printf | python3` pipeline the
  function's last command (rc 127), post-wave the function returns 0.
  f198fb2's message says "(absence silent, rc unchanged)" — read back
  verbatim from `git log`. My own caller enumeration
  (`grep -n '_opk_json_get' ddev-terminal.sh`): def :74, calls :95,
  :96, :97, :99, :100, :119, :145, :169 — every call inside `$( )`
  (the reviewer's list matches except :123, which my grep does not
  show; the discrepancy changes nothing — no caller observes the rc
  behaviorally). Confirmed INFO.
- **W1**: fs-baseline.sh:156-161 `_fsb_count_tee` confirmed
  (`_fsb_py_probe` gate → `cat` fallback, then `python3 -I -c '` at
  :161); status.sh:141-146 `_st_progress_tee` python3 confirmed
  (probe-gated at :214-222). The wave-4 record's list
  (resolution.md:617-625) names neither tee — read back in full. Both
  sites guarded + transparent: no behavior gap, record gap only.
  Confirmed LOW (the round-d W1 shape, without a live swallow this
  time).
- **W2**: comment at test-install-args.sh:973-977 read back verbatim
  ("Any line naming the assignment token twice goes red"). My own
  probe in /tmp/opencode/pr-00244-e/verify/: the append line
  `_py3_imports='import os'; _py3_imports+=' import sys'` → dup-pin
  regex **0 matches**, count pin 1, extraction reads `import os`,
  runtime value `import os import sys` — extraction/runtime divergence
  with both pins green, exactly as reported. Confirmed LOW.
- **W3 (=Q2)**: `grep -n 'curl -fsSL' update.sh` → the resolve pipe's
  curl at **:1162**; resolution.md:498 cites `:1157`; `git show
  75b1aba:…update.sh` puts it at :1157 (reviewer-verified; the guard's
  added lines moved it). The other three cites (:230,
  setup-container-backend:283, oao:444) verified. Confirmed LOW.
- **W4**: my continuation probe (`\` + `;`-led second line) → 0
  matches on either pin's regex. Confirmed INFO (concealment shapes,
  named for the threat-model boundary).
- **W5**: oao:442-445 read back — `python3 …/jsonc-parser.py --tools
  "$1" 2>/dev/null`, no `command -v` guard; the record's "every site
  above guards absence except …" sentence quoted verbatim from
  resolution.md:626-629. Confirmed INFO (absence handled by redirect +
  rc fallback, not by a guard — wording only).
- **Q1**: cli.md:358-360 sentence read back; status probe cache
  confirmed at status.sh:214-221 (`_st_py_checked=1`); advisory parse
  at :536-543 (presence-guarded, python3 stderr unredirected) and
  leak-scan parser at :1333-1341 (presence-guarded, stderr passes per
  the c-S3 change) — a present-but-broken python3 can name itself at
  three sites in one `opk status` run. Confirmed LOW (docs claim
  drift; realistic trigger named).
- **Q3**: the healthy-noop case pattern
  (`*"tui-register:"*|*"Traceback"*`) confirmed in the diff and the
  tree; the pin label says "prints nothing". Latent discrimination
  gap — today's claim is true (tui-register.py verified silent on the
  no-op by both the S reviewer and my read of :106-124). Confirmed
  LOW.

Cross-axis duplicates: 2 pairs, both exact-same-defect merges —
W3/Q2 (the stale `:1157` citation, one site one defect) and S1/Q4
(the guard/sudo PATH asymmetry, one mechanism; Q4's record-gloss
facet folds into the merge). Distinct findings kept apart: W1
(record enumeration gap) vs W5 (absence-sentence wording) — different
sentences, different defects; S2 (rc-contract/commit-message delta)
vs S1 (PATH asymmetry) — different mechanisms.

## Run provenance

- Host timestamps (UTC): fan-out start 2026-10-24T20:45:28Z, all
  reviewers returned by 2026-10-24T21:00:18Z. Checkpoint files
  (sandbox clocks): s-security.md 7 lines, w-sweep.md 8 lines,
  q-quality.md 6 lines — all three reviewers appended per section
  (launch + per-section + return lines); no checkpoint deviation to
  disclose this round.
- Reviewer subagents: 3, model `zai-coding-plan/glm-5.3-flash`
  (fast tier per review-concept "Parallel reviewer agents"), axes
  S (security) / W (mechanical sweep) / Q (quality); 3 concurrent
  seats (cap 5, staged single wave). Checkpoint side files
  /tmp/opencode/pr-00244-e/checkpoints/{s-security,w-sweep,
  q-quality}.md (absorbed into this provenance); reviewer probes
  under /tmp/opencode/pr-00244-e/{s,w,q}-probe/, main-session
  verification probes under /tmp/opencode/pr-00244-e/verify/.
- Main session: GLM-5.3 (zai-coding-plan), verification duty over
  the full fix diff; 11 of 11 reported IDs confirmed, none retracted,
  none dropped, none newly marked `unverified` (the W/Q reviewers'
  out-of-tree deferrals — e2e counts — were discharged by the main
  session: log tails re-read, see below).
- Mutation windows: none — the tree stayed clean and read-only for
  the whole fan-out (`git status --porcelain` empty before and
  after; no sabotage spot-checks run this round; all probes touched
  only session scratch outside the tree). No sabotage-artifact
  screening owed. RM-0112 check: the prior snapshot's verdicts were
  reached empirically (round-d verification probes), and the
  d-wave's constructs were sabotage-verified by the D-session on
  the committed tree (resolution Follow-ups) — no reasoning-only
  verdict owed a representative execution.
- Gates run by the main session on tree `bf4a76d` (before fan-out):
  `make lint && make test` green — full suite, all suites passed,
  rules index parity OK (118 index rows). Affected suites
  included: test-tui-mode, test-update-flags (134 passed),
  test-ddev-as-opencode, test-install-args, test-status,
  test-fs-baseline.
- E2E: owed and discharged by the d-round ITSELF on tree `f198fb2`
  (make e2e 309 passed, make e2e-rootless 47 passed, TS
  20261024-223458 — log tails re-read this pass:
  ../logs/e2e-20261024-223458.log "Passed: 309",
  ../logs/e2e-rootless-20261024-223458.log "Passed: 47"). Snapshot
  e's round changes no code — no new e2e debt.
- Environment: WSL2 kit-managed workspace, agent user `opencode`,
  checkout /var/www/vhosts/opencode-permissions-kit/repo on branch
  `feature/223-fsb-tee-health-gate`; opencode binary at
  /usr/local/bin/opencode this session (recorded per RM-0078).
- Rotation: the d-round session was closed before this pass; this
  fresh session (E in the maintainer's snapshot-letter counting)
  reviewed the closed D-session's fixes — no deviation, RM-0110
  recovery not applicable.
- Snapshot written and committed before any fix of THIS round's
  findings (the hard seam); the resolution grows their rows only
  as the next fix wave lands.
