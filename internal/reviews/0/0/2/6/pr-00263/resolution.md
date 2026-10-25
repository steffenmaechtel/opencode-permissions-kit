# Resolution — pr-00263 (release 0.0.57 full-scope review)

Chain: a (house full pass) -> b, c (external redundancy passes, GPT 6 Luna
medium/high) — 42 unique findings across the three snapshots. This is the
second fix-wave attempt: attempt 1 (backed up at
`backup/pr-00263-fix-wave-1`, never pushed) was superseded when the
maintainer surfaced issue #252 — the ticket behind the #256 docs
shortening — whose ultra-legacy policy deliberately removed two of the
externals' findings' subjects; those are dispositioned deliberately not
done and marked in the snapshots. Deferred to backlog issues: #264-#267
new (code), #268-#273 new (docs: b B3; c C3+C4; c C5; c C6; b B5+B6;
c C9+C10+C11 — maintainer decision 2026-10-25: no docs changes ride this
wave; minimal corrections only when picked up, no bulk restores per
#252/#256), #245/#246/#247 existing.

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
| b B3 (MED) | **deliberately not done** | — | deferred to #268 with the docs backlog (#252/#256 policy) |
| b B4 (MED) | **deliberately not done** | — | #252/PR #256 name the 0.0.36 entry removal as policy |
| b B5 + b B6 (LOW) | **deliberately not done** | — | deferred to #272 with the docs backlog (#252/#256 policy) |
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
| a F16 (LOW) | **implemented** | `<SHA>` | bare skills-root file FAILs; fixture pin executes the branch |
| a F17 (LOW) | **implemented** | `<SHA>` | 14 bare citations qualified (#189/#208/#211/#224/#235/#243/#244/#256) |
| a F18 (LOW) | **implemented** | `<SHA>` | extraction collects all case arms; comment matches reality |
| a F26 (INFO) | **implemented** | `<SHA>` | seq in check-host required list |
| c C3 + c C4 (MED/LOW) | **deliberately not done** | — | deferred to #269 with the docs backlog (#252/#256 policy) |
| c C5 (MED) | **deliberately not done** | — | deferred to #270 with the docs backlog (#252/#256 policy) |
| c C6 (MED) | **deliberately not done** | — | deferred to #271 with the docs backlog (#252/#256 policy) |
| c C9 + c C10 + c C11 (LOW) | **deliberately not done** | — | deferred to #273 with the docs backlog (#252/#256) |

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
symlink); remaining by design: the plugins loop's two `run` ops
(:400-401) carry NO success claim (silent-failure class, not the
claim class — adjacent to the L1 ledger, no lie told). Pins
(test-uninstall): zero `run sudo rm` left in the file; the sudoers
section extracted and driven REAL with stubbed sudo both directions —
failure WARNs on stderr + FAILED log + no success echo, success keeps
the line; stale pre-state proves the section's own reset. Closes the
uninstall half of the #211 c W1 debt (issue #246's uninstall side).

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
