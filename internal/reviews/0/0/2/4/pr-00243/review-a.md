<!-- review-meta
ID: pr-00243
Snapshot: a
Subject: wave review of the #218 fix wave — uninstall revert-loop closing-log honesty
Scope: wave
Base: 0.0.56 @ e4952dd
Diff: e4952dd..f8a6c78
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/X/Q, fast tier GLM-5.3-Flash)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review a — wave review of the #218 fix wave (pr-00243)

Round a over the wave diff e4952dd..f8a6c78 (1 commit, f8a6c78:
`fix(uninstall): revert-loop closing log conditions on per-op rc (#218)`).
The wave replaces the per-root revert loop's rc-blind `run_q` ops
(find-chown, setfacl x2, chmod g-s) with an rc-observing `un_revert_q`
runner, folds the former `_un_acl_skipped` mechanism into one
`_un_partial` cause list, conditions the closing log on it (PARTIALLY
+ WARN + FAILED on failed ops), re-drives the unit pins through the
real runner with a per-command sudo stub, and documents the behavior
in docs/how-to/uninstall.md. First snapshot of the case (birth-PR
#243); no resolution exists yet.

## Findings index (combined)

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | MED | Config-dirs removal closing claim (`Removed.` + audit log) still fires unconditionally over non-rc-checked `run` rm ops — same c W1 shape the wave claims to sweep, left behind in the same file | pre-existing |
| S2 | LOW | Openchamber arm logs "policy pin removed" unconditionally after a non-rc-checked `rm -f policy.json` | pre-existing |
| S3 | LOW | Per-root `_un_partial` reset (uninstall.sh:577) has no discriminating pin — cross-root accumulation would pass the suite green | wave-introduced (pin gap) |
| X1 | LOW | Degraded closing-log line still asserts the "project ownership reverted" clause verbatim when find-chown itself is the failed op | wave-introduced |
| X2 | LOW | Reader-side projects.conf gate lacks the dot/empty-segment and `//` arms the writer-side validator enforces — `//etc` bypasses the system-path blocklist for root-run ops | pre-existing (unchanged by this wave) |
| Q1 | MED | Docs promise "the exact `setfacl` call to run by hand"; code prints a `<gid>` placeholder template | wave-introduced |
| Q2 | LOW | Docs say "the report says PARTIALLY removed" — that wording exists only in the audit log file, never on the terminal; the stderr WARN is undocumented | wave-introduced |
| Q3 | LOW | Test comment claims pins observe output "the way the user sees it"; real `log()` is file-only and the 2>&1 merge leaves the WARN's `>&2` unpinned | wave-introduced |
| Q4 | LOW | Red-arm fail messages (`tail -3`/`tail -4`) show only the appended sudo-call log, never the `log:`/`WARN:` lines the arms assert | wave-introduced |
| Q5 | INFO | Dry arm's "nothing executes" claim has no pin (sudo-log emptiness unchecked) | wave-introduced |
| Q6 | INFO | "the four ops above" counts call sites; a both-gids root issues six invocations | wave-introduced |

Provenance split: 8 wave-introduced, 3 pre-existing (S1, S2, X2 —
same-shape backlog the class sweep surfaces); no fix-induced, no
unstated.

---

## Axis S (mechanical sweep), verbatim

# Mechanical sweep — wave f8a6c78 (#218 revert-loop closing-log honesty)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | MED | Config-dirs removal closing claim (`Removed.` + audit log) still fires unconditionally over non-rc-checked `run` rm ops — same c W1 shape the wave claims to sweep, left behind in the same file | pre-existing |
| S2 | LOW | Openchamber arm logs "policy pin removed" unconditionally after a non-rc-checked `rm -f policy.json` | pre-existing |
| S3 | LOW | Per-root `_un_partial` reset (uninstall.sh:577) has no discriminating pin — cross-root accumulation would pass the suite green | wave-introduced (pin gap) |

## Details

### S1 — MED · config-dirs closing claim over rc-blind removals · pre-existing
`files/opencode-permissions-kit-lib/management/uninstall.sh:642-661`:
```bash
run sudo rm -rf /run/opencode-permissions-kit
run sudo rm -f /etc/sysctl.d/99-ddev-rootless.conf
...
run sudo rm -rf /etc/opencode-permissions-kit
echo "Removed."
log "config dirs + runtime artifacts removed (/etc/opencode-permissions-kit"\
", /run/opencode-permissions-kit, 99-ddev-rootless.conf)"
```
No rc capture, no `set -e` (uninstall.sh:163 — "no set -e here"), so a failed rm prints its stderr but execution continues into the unconditional `Removed.` and audit-log success claim. This is the exact "log the outcome, not the intent" class (c W1) that the sibling arms 20–90 lines away were already converted for: userdel (525-537), agents-backup (498-501), audit log (670-684 — comment at 666-668 names the class). The wave's own comment (621-623) frames this commit as closing "the deferred #211 c W1 class sweep"; the loop is done, but this same-shape site in the same file is not. Why MED not HIGH: unlike `run_q`, `run` does not silence the failure — the user sees the rm's stderr; the residual lie is the audit trail + summary line. Trigger: any failed rm (read-only `/etc` mount, immutable attr, restricted sudoers) during uninstall.

### S2 — LOW · openchamber success log over unchecked rm · pre-existing
`uninstall.sh:654-656`:
```bash
run sudo rm -f /etc/openchamber/policy.json
run sudo rmdir /etc/openchamber 2>/dev/null || true
log "openchamber policy pin removed (kit-owned content only)"
```
If the `rm -f` fails, the audit trail claims the pin removed. (The `rmdir` at 655 is `|| true`+silenced, but its failure does not falsify the log line — the pin is policy.json, not the dir; the exposure is line 654.) Same class as S1, lower stakes (cosmetic pin), same trigger family. Fix-shape sibling of the c W1 audit-log arm.

### S3 — LOW · unpinned per-root reset · wave-introduced (pin gap)
`uninstall.sh:577-578` resets `_un_partial=""` / `_un_revert_failed=0` inside the while-read loop — correct per-root semantics. But every new test arm (`tests/unit/test-uninstall.sh` 437-525) feeds `fakeproj` plus `/etc`, and `/etc` is screened out by the case at uninstall.sh:563-570 — so each driver run exercises exactly one real root. If the reset were ever moved above the loop (or dropped), causes would accumulate across roots and all six honesty arms would stay green. A second unscreened root in one `_un_loop_out` run would pin it. The mechanism is correct as shipped; the gap is only in pin coverage.

## Verified clean

- **Class sweep (loop):** all four revert ops go through `un_revert_q` (587, 617, 618, 620); closing log (628-636) conditioned on `_un_partial` with WARN/FAILED escalation — matches the c W1 arm shapes. No `run_q`/`un_revert_q` definitions or call sites anywhere else under `files/` (grep across the whole tree). The remaining `run_q` teardown sites (510-518: linger/stop/podman-reset/pkill) have no success-claiming closing log — their failure surfaces via the rc-observing userdel arm; not the class. `install.sh` `|| true` sites are probes/captures/backups with no success-claiming closing logs (checked the grep list).
- **Removed construct:** `_un_acl_skipped` fully gone from shipped code and tests; survivors are a historical comment (uninstall.sh:576, describes the fold-in) and a review record (`internal/reviews/0/0/1/3/pr-00133/review-i.md:28`) — both legitimate.
- **Pin quality:** all six arms sit before the summary gate (test-uninstall.sh:896-899). Quoted strings match the script verbatim (WARN 633, FAILED 634, PARTIALLY 631, both setfacl label forms with gids). Negatives discriminate: `'kit ACL entries removed:'` is not a substring of the PARTIALLY line, so a broken condition cannot pass the negative; the sole-cause pins (`(find-chown failed)` etc.) would go red if an additional op failed, since preceding causes shift the text. The driver uses the real runner + real loop with a per-command sudo stub logging to a file (correctly, since the runner silences stdout/stderr — test lines 284-293). The uid-unknown arm documents a real behavior improvement: previously an unknown uid degraded the chown but the closing log still claimed full success; now it says PARTIALLY — intentional, doc'd, pinned.
- **Extraction robustness:** `/^un_revert_q() {/,/^}$/` anchors match lines 190/198; no column-0 `}` inside the function. `while IFS= read -r root; do` is unique (line 559); the first `done < ` is line 637 (inner `for`'s `done` at 619 has no redirect, so the sed range does not terminate early); the `s|done < "$UNINSTALL_PROJECTS_CONF"|done|` replacement matches. Both extractions are complete and eval-able.

## Coverage / deferrals

Covered: full wave diff; loop + runner + all three remaining `run_q` sections with their closing-log context; repo-wide `_un_acl_skipped` grep; extraction anchors against actual function/loop text; pin wiring, discrimination, and gate position for all six new arms; docs added lines vs. shipped behavior (accurate); intentional-behavior-change audit of the diff (uid-unknown degradation, partial-message rewording, DRY_RUN convention — all deliberate and pinned). Deferred: a full rc-observing audit of every `|| true` in `install.sh`/`update.sh` beyond the pattern grep — out of wave scope; the grep showed probe/capture shapes, not success-claiming closers, but I did not read each surrounding function. No unverified suspicions remain.

---

## Axis X (security), verbatim

Review complete. Findings report follows.

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| X1 | LOW | Degraded closing-log line still asserts the "project ownership reverted" clause verbatim when find-chown itself is the failed op | wave-introduced |
| X2 | LOW | Uninstaller's reader-side projects.conf gate lacks the dot/empty-segment and `//` arms that the writer-side validator enforces — a hand-edited root entry in unusual form bypasses the system-path blocklist for root-run ops | pre-existing (unchanged by this wave) |

No HIGH/MED findings. All security-critical wiring of the rewrite checked clean (details below the findings).

## Detail

### X1 — LOW — degraded log still claims "ownership reverted" over a failed chown (wave-introduced)

`files/opencode-permissions-kit-lib/management/uninstall.sh:631`:
```sh
log "project ownership reverted + kit ACL entries PARTIALLY removed ($_un_partial): $root"
```
When the failed op is `find-chown` (line 587), the ownership revert is exactly what did *not* complete, yet the line's first clause still says "project ownership reverted". An audit-log grep for `ownership reverted` matches roots where the root-run chown failed. Mitigations in the same record: `$_un_partial` names `find-chown failed` in the same line, and line 634 writes a separate `log "project revert FAILED for: $root …"` — so the full truth is in the audit log, and the wording is pinned deliberately by the test (`tests/unit/test-uninstall.sh`, the find-chown arm asserts this exact line). Why it matters: the wave's purpose is closing-log honesty; the known-false clause survives inside the degraded line. Severity LOW because the FAILED line and the inline cause list carry the correction.

### X2 — LOW — reader-side path gate weaker than writer-side validation (pre-existing)

`files/opencode-permissions-kit-lib/management/uninstall.sh:563-571` gates roots only on `[ ! -d "$root" ]` plus a literal `case` blocklist (`/|/etc|/etc/*|…`). Unlike the writer (`project_path_sane`, `config.sh:308-343`, and the same arms in `install.sh:945-957` — which reject `*..*|/./|*/./*|./*|*/.|*///*` and relative paths), the uninstaller has no dot/empty-segment arms: a conf line written as `//etc` matches none of the case patterns (`/etc/*` does not match a leading `//`) while `[ -d //etc ]` is true, so `sudo find //etc … -exec chown`, `setfacl -R -x` and `chmod g-s` would run over `/etc`. Preconditions that keep this LOW: `projects.conf` lives in a root-owned dir and is written by `sudo tee` (`install.sh:1311-1317`) — only root can plant the bypass, and the sanctioned writer (`config.sh projects add`) validates the forms, so the trigger is an admin hand-editing the file with an unusual path form. Impact is bounded anyway (chown matches only the oc uid/gid; setfacl strips only the two kit gids). Same class, symlink variant: `[ -d ]` follows symlinks, so a symlinked root entry passes the literal gate; GNU `find` without `-L` does not follow a symlinked root operand and `! -type l` (line 587, survived the rewrite verbatim) excludes it from the chown — the `chmod g-s "$root"` operand would dereference it, but I could not verify `setfacl -R` symlink-operand semantics on this host (unverified; no file creation allowed in this review). Not wave-introduced; no line of this gate changed in `e4952dd..f8a6c78`.

## Checked clean (the wave's own delta)

- **Call-site argument order**: all four `un_revert_q` sites (uninstall.sh:587, 617, 618, 620) pass `<op label> sudo <cmd…>` — label first, `sudo` second; a shifted-command bug is not present. The `[DRY]` echo prints `$*` after the shift, so dry output is byte-identical to old `run_q` output.
- **Symlink guard**: `! -type l` on the root-run find-chown survived verbatim (line 587).
- **rc/exit contract**: no `set -e`/`pipefail` anywhere in uninstall.sh (explicit at line 163). `un_revert_q` returns 0 on all three paths — dry (`echo`), success (`if/elif` with no else branch taken → rc 0), fail (last command is the `_un_partial=` assignment → rc 0). Loop-abort behavior is identical to `run_q`; the loop continues after a failed op exactly as before. This is the deliberate partial semantics, now *observed* instead of swallowed.
- **`>/dev/null 2>&1`**: identical silencing to `run_q`; a sudo auth/binary failure now yields rc≠0 → `_un_partial` + stderr WARN (line 633) + FAILED audit line (634). Loud where it was silent — no security regression.
- **Injection surface**: `$_un_partial` (static labels + numeric gids from `id -g`) and `$root` flow into `log`, which formats via `printf '%s [%s] %s\n' "$ts" "$tag" "$*"` (`sh/log.sh:73`) — argument, not format string; the WARN uses bare `echo`. No eval anywhere in the new code.
- **State hygiene**: `_un_partial`/`_un_revert_failed` reset per root (577-578) inside the `while … done < projects.conf` loop; neither is read after the loop; the DRY_RUN branch never executes a command. The `_un_acl_skipped` fold-in left no dangling references (only a historical comment at line 576).
- **Test hermeticity**: `_un_loop_out` (`tests/unit/test-uninstall.sh:270-296`) runs the real extracted runner + real loop in a subshell; `sudo` is shadowed by a stub logging to `$WORK/unloop-sudo.log` (`WORK=$(mktemp -d)`, line 27 — /tmp scratch, sandbox-compliant). The stub's `case " $_unlo_fail " in *" $1 "*)` is space-delimited whole-token matching — `" find "` does not match a `find-chown` token, and the discrimination pins assert exactly that. The `/etc` fixture line exercises the system-path gate inside the extracted loop, so no real op can reach /etc.

## Coverage

Covered: full wave diff; uninstall.sh header/args, `run`/`run_q`/`un_revert_q` (160-199), id capture (215-228), the entire per-root loop (556-638), `log.sh` format discipline, `projects.conf` writer + validator (`install.sh:1311-1327`, `config.sh:300-360`), all new test arms in test-uninstall.sh (250-525 region). Deferred: empirical verification of `setfacl -R` / `chmod` symlink-operand dereference (X2 tail — no file creation permitted in this review; marked unverified rather than flagged as definite); e2e behavior of the loop under real sudo (unit-only scope per wave material).

---

## Axis Q (quality), verbatim

# Quality axis review — wave `e4952dd..f8a6c78` (#218)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | MED | Docs promise "the exact `setfacl` call to run by hand"; code prints a `<gid>` placeholder template | wave-introduced |
| Q2 | LOW | Docs say "the report says PARTIALLY removed" — that wording exists only in the audit log file, never on the terminal; the stderr WARN is undocumented | wave-introduced |
| Q3 | LOW | Test comment claims pins observe output "the way the user sees it"; real `log()` is file-only and the 2>&1 merge leaves the WARN's `>&2` unpinned | wave-introduced |
| Q4 | LOW | Red-arm fail messages (`tail -3`/`tail -4`) show only the appended sudo-call log, never the `log:`/`WARN:` lines the arms assert | wave-introduced |
| Q5 | INFO | Dry arm's "nothing executes" claim has no pin (sudo-log emptiness unchecked) | wave-introduced |
| Q6 | INFO | "the four ops above" counts call sites; a both-gids root issues six invocations | wave-introduced |

## Details

**Q1 — MED — docs overstate the setfacl hint as "exact".**
`docs/how-to/uninstall.md:41-42`:
> are reported the same way, with the exact `setfacl` call to run by hand.

`files/opencode-permissions-kit-lib/management/uninstall.sh:613-614`:
```sh
echo "    ${_un_acl_label} id unknown — its ACL entries left in place"\
" (remove manually: setfacl -R -x g:<gid> -d -x g:<gid>)"
```
The printed call contains the literal placeholder `<gid>` — not runnable as-is, and in this branch the kit *cannot* know the gid (that is why it skipped), so an exact call cannot exist. The user must discover the orphaned gid themselves and substitute; the doc/report gives no command for that. The parallel WSL sentence three lines down (`uninstall.md:46` "prints the exact line range to delete by hand") *is* exact, which sharpens the false promise by contrast. Trigger: any uninstall where `id -g` failed for a principal — the doc's own scenario. Fix-wording drift, not behavior drift; the mechanism (PARTIALLY + named cause + manual hint) is described correctly.

**Q2 — LOW — "the report says PARTIALLY removed" points at the wrong surface.**
`docs/how-to/uninstall.md:39-40`:
> If one of the revert operations cannot complete (a failed `chown`,
> `setfacl` or `chmod`), the report says **PARTIALLY removed** and names

`log()` is defined in `files/opencode-permissions-kit-lib/sh/log.sh:68-74` — it appends to `/var/log/opencode-permissions-kit/opencode-permissions-kit.log` and writes nothing to stdout. The terminal-visible failure signals are the stderr `WARN: could not fully revert $root (...)` (`uninstall.sh:633`, failed ops only) and the small per-skip echoes. A user watching the run never sees "PARTIALLY removed"; the doc also never mentions the stderr WARN or that the wording lives in the audit log (which the same doc, lines 65-66, frames as deletable). Severity conditioned on reading "report" as the terminal transcript — the natural reading; the outcome is not misrepresented (the WARN does name the failed ops), so LOW.

**Q3 — LOW — test comment mischaracterizes the channels it merges.**
`tests/unit/test-uninstall.sh:284-286`:
> \# Logs to a FILE: the real runner silences its command's stdout
> \# and stderr (the shipped behavior), so an echoing stub would
> \# be swallowed with them.

and the 4c header: "every arm asserts the closing log matches what happened, the way the user sees it (stdout log + stderr WARN merged, as in the c W1 pins)". Two drifts: (a) the user never sees the `log:` lines — the real `log()` is file-only; the stdout `log:` lines come from the harness stub at line 294 (`log() { echo "log: $*"; }`); (b) because the driver merges `2>&1` (line 296), no pin can detect the shipped `>&2` on `uninstall.sh:633` regressing to stdout — the WARN-channel claim is asserted nowhere. The pins themselves are right to check the `log()` *argument* content; the comment's justification is what lies. Same merge practice as the cited c W1 pins, so consistent with house precedent — LOW.

**Q4 — LOW — fail diagnostics never show the asserted lines.**
`_un_loop_out` appends `cat "$WORK/unloop-sudo.log"` after the subshell output (`tests/unit/test-uninstall.sh:296-297`); a full run logs 6 sudo calls (find + 4 setfacl + chmod), failed ops included — the stub logs before returning 1. Every 4c arm's assertions target `log:`/`WARN:` lines that print *before* that block, but the fail echoes capture `tail -3`/`tail -4` (e.g. line 315 `out=$(printf '%s' "$LOOP_OUT" | tail -3)`, lines 326/337/347/363/378/395/412/523 `tail -4`) — i.e. the last sudo-call lines. A red arm prints only which sudo commands ran, none of the closing-log/WARN content the arm actually checks; diagnosis needs a manual re-run. Detection is unaffected (pass/fail logic is sound); only diagnosability. A `grep -E 'log:|WARN'` in the fail echo would fix the gap.

**Q5 — INFO — dry arm claims non-execution but doesn't pin it.**
`tests/unit/test-uninstall.sh` (~508-510, diff): "Dry run: [DRY] echoes and the success lines despite failing ops — … nothing executes, so nothing can fail." The arm asserts `[DRY] sudo find`, the success log, and negatives on `PARTIALLY`/`WARN` — but never that the sudo log stayed empty (it is truncated per run at line 273 and would stay empty if nothing executed). Most degenerate shapes are caught indirectly (echo+execute-with-rc makes the stub fail ops → `PARTIALLY` appears → negative pin goes red); the surviving hole is a refactor that executes while dropping rc observation (`… || true` style), which stays green while a dry run mutates the system — on what the code itself calls the highest-blast-radius script (`uninstall.sh:29-32`). One-line pin closes it.

**Q6 — INFO — "the four ops" counts sites, not invocations.**
`uninstall.sh:622`: "the four ops above report their rc now". Four is the call-site count (587 find-chown, 617/618 setfacl inside the principal loop, 620 chmod); with both gids known the loop issues six `un_revert_q` invocations (both setfacl sites run per principal). Same site-count framing at lines 182-184 ("find-chown, setfacl x2, chmod g-s"). Comment precision only; the surrounding description is otherwise accurate.

## Clean (checked, no finding)

- **Dead code / sweep**: `_un_acl_skipped` fully removed from code — the only remnants are the intentional historical mention in the new comment (`uninstall.sh:576`) and an old internal review doc. 
- **Unintentional behavior changes**: none found. `un_revert_q` (`uninstall.sh:190-198`) preserves `run_q`'s execution semantics exactly (`>/dev/null 2>&1`, same `[DRY] $*` echo with the label shifted off, no execution in DRY); the rc is consumed by `if !` and the script has no `set -e` (`uninstall.sh:163`), so the failure path cannot abort the loop. `_un_partial`/`_un_revert_failed` reset per root (577-578) — no cross-root leakage. The uid-unknown chown skip now lands in the partial list, where pre-wave the closing log claimed full success — intended honesty fix, pinned by arm 6.
- **Downstream pins**: the unchanged LOOP_OUT pins (test-uninstall.sh:300-325) all still match the sudo-stub log format (`sudo find … ! -type l ( -uid 60000 …`); the `/etc` screening pin (321) still works via the screening `continue`. The negative pin `'kit ACL entries removed:'` correctly discriminates — the PARTIALLY line's parenthetical sits between "removed" and ":" so it is not a substring match.
- **Comment blocks vs code**: 182-189 and 572-576 match the implementation, including the "not attempted is not failed" rule (skip branch never sets `_un_revert_failed`) and the DRY semantics; the cited gpasswd/userdel WARN+FAILED precedent exists (`uninstall.sh:458-459`, `535-536`). Commit message accurate.
- **Dropped as suggestions (no house rule found)**: `_un_rq_label` global scratch vs `local` (`ask()` at `uninstall.sh:132` uses `local`, but `agent/conventions.md` has no local/global rule for functions); nested parens in the PARTIALLY message.

## Coverage

Covered: full wave diff; `uninstall.sh` lines 20-79 (arg parsing, `log`/helper sourcing), 150-229 (`run_q`, `un_revert_q`, id capture), 545-664 (the whole revert loop + closing log in context); `sh/log.sh` in full (decisive for Q2/Q3); `docs/how-to/uninstall.md` lines 1-81; `test-uninstall.sh` lines 225-339 (extraction, driver, downstream LOOP_OUT pins) plus the 4c arms from the diff; wave scope confirmed single-commit, 3 files. Deferred: did not execute the unit suite (read-only review; the driver's shell semantics were verified by inspection instead); did not audit the gpasswd/userdel arms' own pin quality (pre-wave code, outside the diff); `agent/test-fidelity.md` not consulted for Q3/Q4 severity calibration — both findings stand on the code's own claims.

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| S1 | **confirmed** | `run` defined uninstall.sh:162-169 (DRY echo else `"$@"` — no rc capture); "no set -e here" comment :157. Site measured: three `run sudo rm` ops (642, 643, 660) + grep-guarded openchamber rm (654) → unconditional `echo "Removed."` (661) + `log "config dirs + runtime artifacts removed …"` (662-663). The audit-log arm 5 lines below (666-684) carries the converted pattern with its own "Log the outcome, not the intent (#211 c W1)" comment — the class is real and un-swept at this site. |
| S2 | **confirmed** | 652-656 measured: `if sudo test -f … && sudo grep -q …` guard, then `run sudo rm -f /etc/openchamber/policy.json` (654) and `log "openchamber policy pin removed …"` (656) with no rc observation between them. |
| S3 | **confirmed** | Driver fixture hardcoded `printf '%s\n/etc\n' "$WORK/fakeproj"` (test:273); `/etc` screened by the case at uninstall.sh:563-570 (`/etc` arm → "Skipping system path"). All 7 driver runs (test:299, 459, 468, 478, 492, 505, 518) exercise exactly one real root — a reset regression is unpinnable by construction. |
| X1 | **confirmed** | Line 631 measured. With find-chown failed, the chown is the ownership revert — the first clause is false while `$_un_partial` names `find-chown failed` inline and :634 logs the FAILED line. The exact wording is deliberately pinned (test:462 asserts it) — a disposition may keep the wording, but the honesty gap is real as reported. |
| X2 | **confirmed (core; symlink tail unverified)** | Empirical: `case //etc in /|/etc|/etc/*)` → no match (passes) while `/etc` is blocked — run in a sandbox shell by the verifier. Writer-side arms measured at config.sh:333-334 (`*..*|/./|*/./*|./*|*/.|*//*` rejection, "leading `//`" named in its own comment); uninstaller reader case (563-570) has no such arms. Root-only write precondition verified: install.sh:1315 `sudo tee` into /etc/opencode-permissions-kit/projects.conf. The `setfacl -R`/`chmod` symlink-dereference tail stays **unverified** as reported (not executed on this host). |
| Q1 | **confirmed** | docs/how-to/uninstall.md:41-42 ("the exact `setfacl` call to run by hand") vs uninstall.sh:613-614 — the echo prints literal `<gid>` twice. Contrast confirmed: the WSL sentence at :46 ("prints the exact line range") is genuinely exact. |
| Q2 | **confirmed** | sh/log.sh:68-74: `log()` appends to `$LOG_FILE` only (`>> "$LOG_FILE" 2>/dev/null || true`) — nothing to stdout. The string "PARTIALLY removed" exists only inside `log` calls (631); terminal surfaces are the stderr WARN (633, failed ops only) and per-skip echoes (591, 613-614). docs:64-65 frame the audit log as deletable ("asked whether the audit log should be deleted too (recommended)"). |
| Q3 | **confirmed** | Stub at test:294 (`log() { echo "log: $*"; }`), merge `) 2>&1` at :296; the real `log()` is file-only (above) — the 4c header's "the way the user sees it (stdout log + stderr WARN merged…)" describes the harness, not the shipped channel layout; a `>&2`-to-stdout regression on :633 is invisible through the merge. |
| Q4 | **confirmed** | `cat "$WORK/unloop-sudo.log"` is the driver's last output (test:297); fail echoes measured at test:457 (`tail -3`) and 466/476/485/501/513/525 (`tail -4`) — a red arm shows only trailing sudo-call lines, never the asserted `log:`/`WARN:` content. |
| Q5 | **confirmed** | Dry arm (test:517-525) asserts `[DRY] sudo find` + success log + negatives on `PARTIALLY`/`WARN:`; the sudo log is truncated per run (:273) and its emptiness is never asserted. |
| Q6 | **confirmed** | Comment at uninstall.sh:621-622 measured; loop shape verified: `for _un_acl_pair in …` (2 principals) × 2 setfacl sites + find + chmod = 6 invocations with both gids known; the comment's "four ops" counts call sites. |

## Retracted/ghost findings

None — all 11 findings survived verification. One in-finding caveat
preserved as reported: X2's symlink-dereference tail remains
**unverified** (the core `//` bypass is empirically confirmed; the
`setfacl -R`/`chmod` symlink semantics were not executed).

## Run provenance

- Commission: maintainer, 2026-10-24 ("@opk-review-pass Wave Review
  (Snapshot a)", birth-PR #243). First snapshot of the case — no prior
  chain, no rotation deviation.
- Tree: f8a6c78 (feature/218-uninstall-revert-log-honesty), clean at
  fan-out (`git status --porcelain` empty) and re-verified clean after
  all reviewers returned — no mutation window opened while readers ran.
- Material: wave diff e4952dd..f8a6c78 (1 commit, 3 files,
  187 insertions / 39 deletions).
- Host timestamps (main session, UTC): fan-out start
  2026-10-24T16:41:29Z, end 2026-10-24T16:51:07Z.
- Reviewer subagents: 3 (cap 5 respected), fast tier
  zai-coding-plan/glm-5.3-Flash, fresh contexts, axis prompts built
  from `.agents/skills/opk-review-pass/axis-prompt.md`; the main
  session (GLM-5.3) owned verification and embedded the reports.
- Checkpoints: `/tmp/opencode/pr-00243-a/checkpoints/{s,x,q}.md`
  (outside the reviewed tree), all three written per section; sandbox
  stamps normalized against host — within ~1-2 min of host UTC; one
  malformed minute stamp in q.md ("16:5x"), launch/return lines intact.
- Sabotage/mutation windows: none during the fan-out; no reviewer wrote
  into the tree (verified `git status --porcelain` empty at return).
- Gates at snapshot time (main session, this tree, before the snapshot
  commit): `sh tests/unit/test-uninstall.sh` green; `make lint` green;
  `sh tests/unit/test-docs.sh` green; `sh tests/unit/test-line-length.sh`
  green (frozen `review-*.md` exempt from the ratchet — verbatim over
  wrap); reviews INDEX regenerated with this commit
  (`scripts/gen-review-index.py`); `sh tests/unit/test-reviews-lint.sh`
  and `sh tests/unit/test-reviews-parity.sh` run green before the
  commit carrying this file.
- e2e debt (recorded once, per the RM-0113 split): the wave changes
  uninstall.sh — a root-run script — but only its OBSERVATION layer:
  the executed ops, their order, silencing and rc behavior are
  unchanged (verified: `un_revert_q` is execution-identical to `run_q`;
  rc 0 on all paths; no set -e interactions). That is a message-level
  change class → both e2e suites may ride to the release gate; the
  debt is recorded here and belongs in the fix-wave resolution.

## Recommendation

The wave does what #218 promised and its pins drive the shipped wiring.
The dispositions owed: S1 is the only finding that extends the honesty
class itself (config-dirs closing claim — the same-shape site the class
sweep surfaces); Q1/Q2 are docs-wording corrections in sentences this
wave added; X1 is a wording decision to make consciously (the pinned
degraded line can stay if the round says so — it is pinned behavior);
S3/Q3/Q4/Q5/Q6 are pin/comment-level hardening inside this wave's own
test code; S2 and X2 are pre-existing backlog the sweep surfaced (X2's
fix touches the reader-side gate — root-run behavior, which would owe
both e2e suites in its wave under RM-0113's semantics branch). Any
round that fixes code here owes the next wave review; a docs-only
round would not (stop rule, review-concept RM-0065/RM-0067).
