# Resolution — pr-00263 (release 0.0.57 full-scope review)

Chain: a (house full pass) -> b, c (external redundancy passes, GPT 6 Luna
medium/high) — 42 unique findings across the three snapshots — -> d
(wave review of the fix round, 2026-10-25: 13 findings, 1 MED / 6 LOW /
6 INFO; all dispositioned below as d Q1-Q4, d W1-W6, d S1-S3). This is
the second fix-wave attempt: attempt 1 (backed up at
`backup/pr-00263-fix-wave-1`, never pushed) was superseded when the
maintainer surfaced issue #252 — the ticket behind the #256 docs
shortening — whose ultra-legacy policy deliberately removed two of the
externals' findings' subjects; those are dispositioned deliberately not
done and marked in the snapshots. Deferred to backlog issues: #264-#267
new (code), #268-#273 new (docs — later implemented in-wave as one-line
corrections per the maintainer's commission, closing #268-#273 via the
release PR; brevity held, no bulk restores per #252/#256),
#245/#247 existing (#246 closed in the d round — site 7, see the a F3
evidence block).

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a F5 + c C8 (MED) | **implemented** | `dd87146` | prerequisite states the abort; claim-drift pin in test-docs.sh |
| a F1 (MED) | **deliberately not done** | — | deferred to #264 (code backlog: dump-operand symlink gate) |
| a F2(a) (LOW) | **deliberately not done** | — | deferred to #247 (projects.conf reader parity) |
| a F4 (MED) | **deliberately not done** | — | deferred to #266 (chown-R exec-time window) |
| a F14 (LOW) | **deliberately not done** | — | deferred to #245 (symlinked-root no-op passes) |
| a F15 (LOW) | **deliberately not done** | — | deferred to #267 (revert-loop exec-time recheck) |
| b B1 + c C7 (LOW) | **deliberately not done** | — | #252 names 0.0.x→0.0.y update paths as removable legacy |
| b B2 + c C1 (LOW) | **deliberately not done** | — | deferred to #265 (tee stderr-EPIPE arm, #223/#244 shape) |
| b B3 (MED) | **implemented** | `005590a` | tee-overwrite truth stated, merge-promise gone (#268) |
| b B4 (MED) | **deliberately not done** | — | #252/PR #256 name the 0.0.36 entry removal as policy |
| b B5 + b B6 (LOW) | **implemented** | `005590a` | probe-fallback caveat + hosts mapping x2 pages (#272) |
| c C2 (MED) | **implemented** | `092bcd6` | rc 1 propagates; arm pins A=1/B=0; ui_error sweep clean |
| a F2(b) (MED) | **implemented** | `ed372e2` | X1 mirror x3; sanitized WARN; sweep recorded below |
| a F3 (MED) | **implemented** | `656350e` | six run sites + 4 legacy siblings on un_rc_q; arms pinned |
| a F27 (INFO) | **implemented** | `65eac53` | chat-German quote removed from pr-00259's Status line |
| a F6 (LOW) | **implemented** | `c2cc5a0` | six backup copies loud; summary row degrades |
| a F8 (LOW) | **implemented** | `c2cc5a0` | both getfacl sites observe; fail arms warn |
| a F19 (INFO) | **implemented** | `c2cc5a0` | pipefail + kit error wrapper on the installer pipe |
| a F7 (LOW) | **implemented** | `54758f2` | both re-deploy skips terminal-loud; harness drives both arms |
| a F13 (LOW) | **implemented** | `54758f2` | daemon-start rc gates the ready message; socket var kept |
| a F11 (LOW) | **implemented** | `54758f2` | shape-invalid feed = silent unavailable; ids-only on lists |
| a F9 (LOW) | **implemented** | `6e406de` | sanitized gate WARN; newline arm pinned (one line, no raw bytes) |
| a F10 (LOW) | **implemented** | `6e406de` | getent homes at both refusal twins + install.sh parity copy |
| a F21 (INFO) | **implemented** | `6e406de` | failure message names key-or-value |
| a F25 (INFO) | **implemented** | `6e406de` | chmod before chown; order pinned by line compare |
| a F16 (LOW) | **implemented** | `049dd04` | bare skills-root file FAILs; fixture pin executes the branch |
| a F17 (LOW) | **implemented** | `049dd04` | 14 bare citations qualified (#189/#208/#211/#224/#235/#243/#244/#256) |
| a F18 (LOW) | **implemented** | `049dd04` | extraction collects all case arms; comment matches reality |
| a F26 (INFO) | **implemented** | `049dd04` | seq in check-host required list |
| a F20 (INFO) | **deliberately not done** | — | fail-closed broadening; loud skip; writer parity |
| a F22 (INFO) | **deliberately not done** | — | documented accepted residual (the .ddev shape) |
| a F23 (INFO) | **deliberately not done** | — | trigger needs parent write — outside threat model |
| a F24 (INFO) | **deliberately not done** | — | newline project name: pathological, bounded effect |
| c C3 + c C4 (MED/LOW) | **implemented** | `005590a` | per-component claim dropped, residual restored (#269) |
| c C5 (MED) | **implemented** | `005590a` | npm + opencode.ai named in the trust sentence (#270) |
| c C6 (MED) | **implemented** | `005590a` | export conditions + verify advice, pins both ways (#271) |
| c C9 + c C10 + c C11 (LOW) | **implemented** | `005590a` | three scoping clauses on the reference pages (#273) |
| d Q2 (LOW) | **implemented** | `116339b` | #246 site 7 converted; "zero" now true; pin = 0; evidence fixed |
| d W1 (LOW) | **implemented** | `755de9a` | branch-b backup observes the cp; announce degrades; feeds _bk_fail |
| d W2 (LOW) | **implemented** | `755de9a` | both existing-config sites observe; third sibling swept in (see detail) |
| d W3 (LOW) | **implemented** | `755de9a` | recorder driven REAL (extract-eval); count exact = 10; comment honest |
| d W4 (LOW) | **implemented** | `a51874b` | count pin exact = 5; deleting the capture now fails the pin |
| d Q1 (MED) | **implemented** | `054a39a` | e2e discharge recorded (RM-0113) — trees + counts in the detail block |
| d Q3 (LOW) | **implemented** | `054a39a` | ledger correction note added; commit messages are immutable history |
| d W5 (INFO) | **deliberately not done** | — | deletion discriminates; static presence pins are house practice |
| d W6 (INFO) | **deliberately not done** | — | tripwire fails loud on all three failure shapes; no hole |
| d S1 (INFO) | **deliberately not done** | — | trailing hyphen has no downstream harm; leading hyphen rejected |
| d S2 (INFO) | **deliberately not done** | — | in-file run/run_q convention + DRY banner; committed deliberate |
| d S3 (INFO) | **deliberately not done** | — | pre-existing sub-second window, non-setuid; comment scoped true |
| d Q4 (INFO) | **deliberately not done** | — | disambiguated in-string; F17 claimed 14 qualified, not zero-remain |
| e W2 (INFO) | **implemented** | `<SHA>` | harness drives a production-shaped label (DEFAULT_USER=opencode) |
| e W3 (INFO) | **implemented** | `<SHA>` | run() removed; run_q doc + 4 comments updated; def-count pin = 0 |

## Evidence detail

### a F5 + c C8 (MED) — getting-started python3 prerequisite

The bullet claimed "the installer probes `python3` missing or broken; the
baseline still applies without it" while both `_py3_health_probe` arms
exit 1 (install.sh:574-586 — missing → "required but not installed",
broken → "present but broken"). Fixed to state the hard gate; the component
degrade (baseline without live counters) stays, correctly scoped to an
installed kit. Pin (test-docs.sh, before the summary gate): the abort
claim must be present, the survival claim must be absent, and both
installer abort messages serve as code-side anchors. Found independently
by the house pass (a F5, E2 axis) and the external high pass (c C8, P3);
the severity divergence (house MED vs external P3) is recorded in
snapshot c's calibration.

### a F3 (MED) — six rc-blind `run` ops with unconditional success claims

The :745 comment claimed the #211 c W1 class sweep while six earlier
sections still ran rc-blind `run` rm ops into unconditional success
echoes/logs (sudoers, wrapper, cli dispatcher, xdg-open shim, library,
umask x2 — "sudoers removed." over a failed rm). Fix: all six route
through un_rc_q with per-section `_un_partial` reset and an immediate
conditional verdict (the per-root loop resets the pair, so early
failures must report at their own section, not defer to the closing
claim); DRY_RUN keeps the [DRY] echoes and success lines. Class sweep
(`grep 'run sudo rm'`): the legacy-shape siblings got the same
treatment (legacy sudoers symlink, legacy conf dir — where the partial
check now precedes the rmdir claim — legacy library, legacy helper
symlink). The plugins loop's two `run` ops stayed claim-less through
the a-wave (recorded then as "remaining by design", the silent-failure
class — no lie told); converted in the d round as issue **#246 site 7**
(the last of #246's 11 rc-blind sites): both ops through un_rc_q with
a per-iteration partial reset, failure WARNs + FAILED log, success
stays quiet (no success claim invented). Pins (test-uninstall): zero
`run sudo rm` left in the file — the count pin is exact `= 0` now (the
a-wave's `= 1` anchored the plugins residual the d wave removed, per
d Q2); the plugins loop extract-pinned (both ops un_rc_q, WARN anchor);
the sudoers section extracted and driven REAL with stubbed sudo both
directions — failure WARNs on stderr + FAILED log + no success echo,
success keeps the line; stale pre-state proves the section's own
reset. Closes the uninstall half of the #211 c W1 debt and, with site
7 converted, **closes #246 outright** (10 sites in the a-wave, this
one in the d round).

### a F2(b) (MED) — OPENCODE_USER unshaped at the conf-reading consumers

The #243 e/f X1 shape gate existed in uninstall.sh only; config.sh,
update.sh and status.sh consumed the hand-editable conf value unshaped —
worst site config.sh, where a shape-invalid value silently defangs the
agent-home refusal (`[ "$_pp" = "/home/$OPENCODE_USER" ]`, :351) and
feeds the fs-baseline/ddev-handover argv with no downstream id check.
Fix: the X1 case gate mirrored into all three (same charset, same
canonical fallback, loud WARN). Divergence from the uninstall shape: the
WARN echoes a sanitized form (`tr -c 'A-Za-z0-9_.-' '?'`) — the mirror
does not replicate the a F9 raw-echo class. Sweep (every OPENCODE_USER
consumer in files/): gated now config/update/status + uninstall (X1);
defused loudly by their own downstream id-check refusals — opk handover
(:479) and ensure-shared (:642), ddev-as-opencode (:42 mismatch exit);
install.sh is the charset-gated writer; bin/ddev-migrate is
tolerant-by-design (id -gn || echo fallback feeds deliberately
|| true-guarded chowns — the ddev-migrate hardening neighborhood, F1
backlog #264, not this class). Pins: the uninstall extract-and-eval
idiom mirrored per script (test-project-paths, test-update-flags,
test-status): passthrough silent (custom + canonical), trailing-slash
falls back loudly, newline-bearing value stays one sanitized WARN line.

### c C2 (MED) — opk settings-edit failure branch exits 0

The openchamber-secure settings-edit else branch printed two ui_error
lines and fell through to exit 0 — four rc-1 causes share the branch
(#244 h S3: no key removed, unparseable JSON, python3 missing, write
failure) and all failed closed except the rc itself; the #244 g-wave
(fd93fbe) had fixed only the python side. Fix: `exit 1` in the branch.
Class sweep: every ui_error site in opk re-checked — inline `exit 1`,
`_ho_rc` propagation, `exit "$_es_rc"` on the siblings; this was the
only rc-blind site. No internal caller consumes the rc (status, update
and install print advice text only); the e2e scenarios drive success,
idempotent, symlink and getent-skip paths, none flips. Pins: the
#244 f W2 asymmetry harness now asserts rc 1 on arm A (exec context
without python3) and rc 0 on arm B (functional, extracted compound);
extraction bound 33 -> 35 lines for the two added lines.

### b B1 + c C7 / b B4 — deliberately not done: deliberate removals per #252

Issue #252 and the PR #256 body name both removals as intended
ultra-legacy cleanup ("how to update from 0.0.x to 0.0.y … we can remove
old legacy stuff"; PR body: "remove ultra-legacy update paths: the
one-time >= 0.0.29 layout migration section, the kit-0.0.36 wsl.conf
parse-error entry"). Both findings are marked RETRACTED in
review-b.md / review-c.md (post-hoc, maintainer decision 2026-10-25 —
the sparse external setup could not see the recorded intent, and the
house verification initially restored them; attempt 1 is backed up at
`backup/pr-00263-fix-wave-1`, never pushed). The current-accuracy fixes
are unaffected: #252 wants brevity, not false claims.

### d W1 + d W2 (LOW) — the three backup sites the a F6/F8 sweep missed

Wave d found two same-shape siblings (W1 binary-menu branch `b`,
W2 existing-config replace) and the class re-sweep found a THIRD
(W2's re-render twin at the re-install branch) — all three the exact
F6/F8 shape: `2>/dev/null || true`-swallowed copy under an
unconditional "Backup saved." announce, invisible to `_bk_fail` and
the closing summary row. Fix: all three observe the copy now
(conditional), failure routes through `_bk_fail` (summary degrades to
INCOMPLETE) and degrades the site announce ("binary backup FAILED —
see Backup summary" / "config backup FAILED — see Backup summary"
x2); success keeps the original wording. Class sweep record (pattern:
every line writing to `$BACKUP_DIR` in install.sh, checked 11 sites):
gitconfig x2, sudoers, usr-local-bin, lib tree, remove_shadow_binary,
getfacl x2 (all observed in the a-wave) + the three swept here —
`grep 'BACKUP_DIR' | grep '|| true'` over install.sh is now empty.
Pins (test-install-args.sh, before the summary gate): the recorder
DRIVEN REAL (extract-eval: two failures accumulate to
"label-a, label-b"), exact call count `= 10` (was floor `>= 7`),
announce-degrade anchors (binary 1x, config 2x) — the d W3 lying
comment ("the e2e suites drive the arms") replaced by what the pins
actually do; e2e drives install success paths only.

### d Q1 (MED) — the e2e discharge record (RM-0113)

Both suites green on the final tree of each wave — the record the fix
round left missing:

- **Fix round** (maintainer-run, previously unrecorded): tree
  `701b867`, 2026-10-25 21:14–21:17Z — e2e 309/309,
  e2e-rootless 47/47 (../logs/e2e-20261025-221402.log and
  e2e-rootless-20261025-221402.log; local-time names, logs rotate via
  logs-cleanup.sh — hence this in-repo record).
- **d round** (this wave, tree `a51874b` porcelain-clean, opencode
  2.1.4 from the warm cache): e2e 309/309
  (../logs/e2e-20261025-225430.log), e2e-rootless 47/47
  (../logs/e2e-rootless-20261025-225900.log). install.sh changed in
  the d wave (d W1/W2), so both suites were owed and run in-wave
  (AGENTS.md Testing); zero skips observed in both tails.

### d Q3 (LOW) — correction of record for 049dd04's suite count

Commit 049dd04's message says "14 bare finding-ID references across
nine suites"; the snapshot-d recount (verified against the diff) is 14
sites across TEN suites — the 14th site is test-docs.sh's `a-W1` ->
`#256 a W1` qualification. The count 14 is correct; commit messages
are immutable, so this note is the correction of record (the pr-00259
b Q1 precedent: the mutable ledger corrects immutable history). The
a-F17 resolution row already carried the accurate claim.

### d-round residuals (d W5/W6, d S1-S3, d Q4) — recorded, not done

W5: the getent-twin pins discriminate full deletion; driving the
comparison arm REAL would mirror the F2(b) harness — backlog-quality,
not owed. W6: the 35-line bound is a documented tripwire that fails
loud on every identified failure shape. S1: the trailing-hyphen
admission has no downstream harm path (leading hyphen — the
argv-injection shape — is rejected); S2: DRY success lines are the
committed run/run_q convention; S3: the residual window is
pre-existing, sub-second, non-setuid, and the wave comment scopes it
truthfully. Q4: the surviving citations are disambiguated in-string;
F17's claim was "14 qualified", not "zero remain".

## Follow-ups

- The d round touched review-relevant code (uninstall.sh, install.sh,
  three test suites): the owed **micro-wave review** ran as snapshot e
  (2026-10-25, `5171eb3..054a39a`: 4 findings, 1 LOW / 3 INFO, no
  MED/HIGH) — dispositions owed; the loop's closure stays the
  maintainer's / next round's call (RM-0106/RM-0107, RM-0115).
- e2e debt discharged in the d wave (see d Q1): both suites green on
  the d-round tree, zero skips.


