<!-- review-meta
ID: pr-00263
Snapshot: d
Subject: wave review of the pr-00263 fix round (42-finding disposition wave)
Scope: wave
Base: 0.0.57 @ 0cff825 (snapshots a/b/c integrated; reviewed tree 4eacabb)
Diff: 0cff825..701b867 (16 commits; 31 review-relevant files, +685/-110)
Date: 2026-10-25
Reviewer: GLM-5.3 (house session, verification duty held in-session) + 3x GLM-5.3-Flash reviewer subagents (W mechanical sweep / S security / Q quality)
Skills: opk-review-pass
-->

# Wave review — pr-00263 snapshot d — the fix round

> Resolution: [resolution.md](resolution.md)

Wave pass ("did the fixes break or lie?") over the round that
dispositioned all 42 findings of snapshots a/b/c: nine fix commits
(docs a F5+c C8; opk c C2; management a F2(b); uninstall a F3; install
a F6+F8+F19; kit a F7+F13+F11; kit a F9+F10+F21+F25; tests
a F16+F17+F18+F26; docs #268-#273 one-liners) plus in-range resolution
bookkeeping. Three reviewer subagents ran three axes (mechanical sweep,
security, quality) on the provider's fast tier; the main session
re-verified every finding against the code and normalized all timeline
evidence (log filenames carry local time +0100, host clock UTC).

Severity counts: **1 MED, 6 LOW, 6 INFO** — no HIGH. The round's fixes
hold: no fix-induced regression, no rc-contract backflip, no lie in the
new comments (all 21 opk ui_error sites exit nonzero; every docs
one-liner verified true against its code site). The findings concentrate
exactly on the round's own disciplines: two same-shape siblings the
F6/F8 class sweep missed (W1/W2), pin-quality gaps in the wave's own new
pins (W3/W4/W5), and ledger/process accuracy (Q1/Q2/Q3).

## Findings index

| ID | Sev | Location | One-line summary | Verified |
|---|---|---|---|---|
| Q1 | MED | whole round (ledger/process) | Both e2e suites ran green on the final tree (309 + 47 passed, 21:14–21:17Z, after HEAD 701b867) but the run is recorded nowhere in-repo — no commit message, no resolution entry, no tree SHA + counts; the AGENTS discharge record is unmet and the evidence lives only in rotating ../logs/ | yes (logs + timeline normalized; PR body not checkable from this checkout) |
| W1 | LOW | install.sh:1975-1983 (branch b) | Binary-menu branch `b` still swallows its backup cp (`2>/dev/null \|\| true`) and prints "Backup saved." — the exact F6 shape; for /usr/bin/opencode this cp is the only backup attempt (remove_shadow_binary's case guard skips non-.opencode paths), and the site is invisible to `_bk_fail`/summary degrade | yes (code read; pre-existing site, F6 sweep gap) |
| W2 | LOW | install.sh:2459-2464 | Existing-config backup cp (`opencode.jsonc-existing`) swallowed + "Backup saved." unconditional — second F6-shape sibling outside the recorder, summary row never degrades for it | yes (code read; pre-existing site, F6 sweep gap) |
| W3 | LOW | tests/unit/test-install-args.sh:1121-1130 | The new F6/F8/F19 pin block comments "Functional runs need root — the e2e suites drive the arms" — no e2e scenario drives any backup-failure arm (grep over tests/e2e sources: nothing); all three pins are static, the recorder could regress with all green | yes (grep; only hit is a binary cache tar false-positive) |
| W4 | LOW | tests/unit/test-container-backend.sh:467 vs setup-container-backend:328-346 | `_dc_start_rc` floor pin `>= 3` faces 5 occurrences — deleting the capture+default lines (the F13 mechanism, :328-329) leaves exactly 3 and the pin stays green; the wave's own uninstall pin is exact (`= 1`) | yes (count + deletion arithmetic) |
| Q2 | LOW | resolution.md:88-91 | The a F3 evidence claims "zero `run sudo rm` left in the file" while the shipped pin asserts exactly 1 remains (the plugins loop) and the code carries 1 — the ledger contradicts its own pin; secondary drift: ":400-401" is now 403-404 | yes (grep + pin read; prose-only) |
| Q3 | LOW | commit 049dd04 (message) | The citation-sweep commit claims "14 bare finding-ID references across nine suites" — the 14 is correct but the sites span TEN suites (the 14th is test-docs.sh's `a-W1` → `#256 a W1` qualification); the resolution row carries the accurate count | yes (diff recount; severity per the pr-00259 b Q1/Q2 evidence-accuracy precedent) |
| W5 | INFO | test-project-paths.sh:242, test-uninstall.sh:1482 | F10 getent-twin pins are presence-greps: full deletion fails them (good), but dropping the comparison arm while keeping the assignment stays green — the relocated-home refusal behavior is never executed by a pin, unlike the F2(b) gate pins which drive eval REAL | yes (grep + arm read) |
| W6 | INFO | test-kit-cli.sh:891-893 | The OCW2 extraction bound widened 33→35 (c C2's two added lines): sound tripwire — unrelated growth fails loud, stray-fi truncation fails the functional arms below, marker rewording yields an empty extract caught by `[ -n ]`; recorded per the blind-spot line, no action implied | yes (mechanism read) |
| S1 | INFO | config.sh:115, update.sh:448, status.sh:82, uninstall.sh:229 | The X1 charset gate admits a trailing hyphen (`opencode-`); leading `.`/`-` (the argv-injection shape) are rejected, the value is quoted everywhere downstream and never option-positioned — no exploit path found, recorded for completeness | yes (pattern + downstream trace) |
| S2 | INFO | uninstall.sh:265-273 (+197-199, :544/:621/:826/:880) | DRY-run uninstall now prints six NEW unconditional success lines ("sudoers removed.") over ops that were only echoed — sanctioned by the in-file run/run_q convention and the DRY banner, committed as deliberate; transcript-honesty residual only | yes (convention comments + DRY arm read) |
| S3 | INFO | sh/secure-binary.sh:38-47 (+72-84) | F25's chmod-before-chown closes the window *between the two* (comment accurately scoped); the residual cp-natural-0755 window is the pre-existing `copy_binary_atomic` mv→secure_binary gap (no mode parameter), sub-second, non-setuid binary, no realistic privilege outcome | yes (code read; pre-existing residual) |
| Q4 | INFO | test-status.sh:2711/2713, test-docs.sh:272, test-install-args.sh:829 | Case-disambiguated but non-canonical finding-ID citations survive outside F17's swept paren shape — `#221: … (b W1)` (case in the prefix, not the canonical paren form), and test-install-args.sh:829's bare `f-W4` (no case qualifier; the reviewer's unverified residual — the line exists and IS bare); F17 claimed 14 qualified, not zero-remain, so no lie | yes (lines read at HEAD) |

Provenance: W1/W2 pre-existing sites (the finding is the wave's F6/F8
class-sweep gap); W3/W4/W5/W6 wave-introduced (the wave's own new pins);
S1 wave-introduced mirrors of a pre-existing pattern; S2 wave-introduced
(deliberate, convention-sanctioned); S3 pre-existing window, accurately
scoped by a wave-introduced comment; Q1/Q2/Q3 wave-introduced (ledger,
prose, commit message); Q4 wave-made-visible shapes that pre-date it.

## Findings (reviewer output, verbatim)

### Axis W — mechanical sweep (GLM-5.3-Flash)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | LOW | Branch-`b` binary backup cp still swallowed + "Backup saved." lie; `/usr/bin/opencode` path has no later observed re-copy | pre-existing (missed by the wave's F6 class sweep) |
| W2 | LOW | Existing-config backup cp (`opencode.jsonc-existing`) swallowed, announces "Backup saved.", and is invisible to `_BK_FAIL`/summary degrade | pre-existing (missed by the wave's F6 class sweep) |
| W3 | LOW | Backup-failure arms are static-pinned only; the pin comment claims "the e2e suites drive the arms" — no e2e driver exists | wave-introduced |
| W4 | LOW | `_dc_start_rc` count pin uses `>= 3` against 5 occurrences — deleting the capture+default lines keeps the pin green | wave-introduced |
| W5 | INFO | F10 getent-twin pins are static presence-greps: full deletion discriminated, comparison-arm regression is not | wave-introduced |
| W6 | INFO | kit-cli OCW2 extraction bound widened 33→35: documented tripwire, fails loud on unrelated growth | wave-introduced (bound widened; mechanism pre-existing) |

## Details

**W1 — LOW — branch-`b` binary backup cp swallowed + "Backup saved." lie.**
`files/install.sh:1975` (branch `b` of the binary-location menu):
```sh
cp "$loc" "$BACKUP_DIR/opencode-binary" 2>/dev/null || true
```
followed by `files/install.sh:1992`:
```sh
echo "Backup saved. Copied to $SYSTEM_BIN."
```
This is the exact F6/F8 lie shape (announce recovery material over a swallowed copy) one screen below the sites the wave fixed. Mitigation exists only partially: `remove_shadow_binary "$loc"` re-attempts the same cp with an observed failure (`files/install.sh:1951-1955`) — but its case guard (`files/install.sh:1941-1943`) returns early for anything not `*/.opencode/bin/opencode`, so for the loop's `/usr/bin/opencode` candidate (`files/install.sh:1968-1971`) the branch-`b` cp is the *only* backup attempt: a failed cp (realistic trigger: `/tmp` full — BACKUP_DIR is a mktemp under `/tmp`) leaves no backup and no warning while the run prints "Backup saved.". Trigger conditions: binary discovered at `/usr/bin/opencode` (or any non-`.opencode` path the menu offers), user answers `b`, cp fails. Pre-existing at 0cff825:1948/1954; the wave's F6 sweep claimed the backup-recovery material but left this sibling on `|| true`. Not recorded into `_bk_fail`, so the closing summary row (install.sh:2657-2661) never degrades for it either.

**W2 — LOW — existing-config backup cp swallowed and invisible to the recorder.**
`files/install.sh:2459`:
```sh
sudo cp /home/opencode/.config/opencode/opencode.jsonc "$BACKUP_DIR/opencode.jsonc-existing" 2>/dev/null || true
```
followed unconditionally by `files/install.sh:2462` / `:2464` ("… Backup saved." / "opencode.jsonc — backup saved"). Same-shape F6/F8 sibling as W1: the copy failure is silent, the success line claims a backup, and the site does not call `_bk_fail`, so `_BK_FAIL` stays empty and the summary row announces the dir as complete recovery material. Trigger: agent config exists, `_oc_install_agent_config` about to overwrite it, cp fails (disk-full on `/tmp`, source unreadable mid-run). Pre-existing (0cff825:2418 same shape); the class-sweep rule (agent/learnings.md L1: all same-shape sibling sites) makes this a sweep gap, not a new bug.

**W3 — LOW — backup-failure pins are static-only while claiming e2e coverage.**
`tests/unit/test-install-args.sh:1121-1123` (new pin block): "Functional runs need root — the e2e suites drive the arms." The pins added are: `grep -c '_bk_fail' >= 7` + `INCOMPLETE` text anchor, `grep -cF 'no ACL recovery material' = 2`, installer-wrapper text grep — none *executes* a failure path. Greps of `tests/e2e/` for `_bk_fail`, `INCOMPLETE`, `backup copy failed`, and `recovery material` return nothing, so no e2e suite drives any of: the `_bk_fail` arms (install.sh:723-736, 1954), both getfacl fail arms (:1396-1398, :1845-1847), or the F19 installer-pipe wrapper (:1996-1999). This contradicts agent/learnings.md's fail-loud-pins class ("a pin that executes the failure path, observed the way production observes it") for every new `2>/dev/null` the wave added in the backup neighborhood; the recorder could regress (e.g. recorder body emptied, arms inverted) with all three static pins green. The suite has the stub-drive idiom (as test-uninstall's F3 section proves) that could drive `remove_shadow_binary`/the recorder without root.

**W4 — LOW — `_dc_start_rc` floor pin survives construct deletion.**
`tests/unit/test-container-backend.sh` (new): `[ "$(grep -c "_dc_start_rc" "$1")" -ge 3 ]`. Actual occurrences in `files/opencode-permissions-kit-lib/bin/setup-container-backend`: :328 (`|| _dc_start_rc=$?`), :329 (`${_dc_start_rc:-0}`), :339, :344, :346 = 5. Deleting the capture + default lines (:328-329 — the mechanism the F13 fix added) leaves exactly 3 → the pin stays green with the rc gate gone; only the static WARN-text grep would then carry the pin, and it too survives if the message strings were kept. A `= 5` count or a per-site anchor would discriminate. Conditions: future refactor of the daemon-start block; same floor-not-exact weakness the axis blind-spot names (the uninstall count pin, by contrast, is exact at `= 1` and matches the residual line verbatim — verified).

**W5 — INFO — F10 getent-twin pins are presence-greps only.**
`tests/unit/test-project-paths.sh` (`grep -q '_pp_agent_home' "$CONFIG"`) and `tests/unit/test-uninstall.sh` (`grep -q '_un_agent_home' "$UNINSTALL"`): full deletion of the getent line fails the pin (good; no comment-line false-pass — both patterns match code only today, verified by grep). But dropping the *comparison* arm (`|| { [ -n "$_un_agent_home" ] && [ "${root%/}" = "$_un_agent_home" ]; }`, uninstall.sh:678, and the config.sh twin at :367) while keeping the assignment stays green — the relocated-home refusal behavior the F10 fix claims is never executed by a pin, unlike the F2b gate pins which drive the eval REAL in all three suites. Severity INFO because deletion IS discriminated and static presence-pins are house practice; the gap is partial regression only.

**W6 — INFO — kit-cli extraction bound 33→35.**
`tests/unit/test-kit-cli.sh:891-893`: `sed -n '/#244 f W2/,/^            fi$/p'` + `wc -l <= 35`, with a comment documenting "33 (the #244 f W2 compound) + 2 for pr-00263 c C2". The bound mechanism is sound as a tripwire: an unrelated edit growing the compound past 35 fails loud (maintenance cost, not a silent hole); a stray 12-space `fi` between marker and compound truncates the extract, which then fails the functional arms below (also loud); a marker rewording yields an empty extract, caught by `[ -n ]`. Recorded per the blind-spot line; no action implied.

## Verified clean (class-sweep checkpoints)

1. **uninstall `run sudo rm`**: exactly 1 site (`uninstall.sh:403`, plugins loop; sibling :404 tui-register also claim-less — matches the "two `run` ops" claim). Count pin anchors `= 1` AND the exact residual line (test-uninstall.sh); sudoers F3SEC extraction anchored on `^echo "--- Removing sudoers ---"$` (comment-safe); drive-REAL pins cover fail arm (WARN + FAILED log + no success echo), success arm, and stale pre-state reset. All before the summary gate.
2. **OPENCODE_USER consumers** (9 files): gates mirrored 1:1 in config.sh:114-119, update.sh:447-452, status.sh:81-86 (identical case pattern `''|*[!A-Za-z0-9_.-]*|[.-]*|*[.]`, sanitized `tr` WARN, canonical fallback), each before its first consumer (config: gate 114 vs use 134/366; update: 447 vs 589; status: 81 vs 90); uninstall.sh:228 pre-existing gate identical; opk handover :484 and ensure-shared :642 refuse via `id -u` on the conf value; setup-container-backend:89-90 same defuse (unnamed in the claim but holds); bin/ddev-migrate:50-51 tolerant (`id -gn … || echo`), sh/ddev-migrate.sh:599-602 actually id-*refuses* on import; install.sh:349 hardcodes the writer value.
3. **opk ui_error**: all 21 sites exit nonzero — inline `exit 1` (:198, :207, :233, :245, :333, :341, :360-361, :369, :352, :417, :424, :436, :683), `_ho_err` exits internally (:455-458), handover loop sets `_ho_rc=1` and ends `exit "$_ho_rc"` (:618), `_es_err` exits (:632-636), ensure-shared `exit "$_es_rc"` (:667). The C2 site (:330-333) carries `exit 1`; claim "only rc-blind site was settings-edit" verified.
4. **install.sh `_bk_fail`**: recorder :715-719; call sites :723, :726, :728, :732, :736, :1954 = 6 calls + 1 def = 7 grep hits (pin floor `>= 7` holds; no comment lines match the literal today). Both getfacl arms observe (:1394-1398, :1843-1847 — :1844 confirmed as the fixed then-arm). Summary degrades :2657-2661. Residual swallowed sites in the neighborhood: W1 and W2 above.
5. **secure-binary order**: chmod 750 → chown (:39-47). The atomic helpers' actual order is mode-before-live-name (`copy_file_atomic` cp→chmod→mv; `deploy-lib.sh:75` same) — no helper does chown-before-chmod, so parity holds; the handover/migrate chown-then-chmod sites (ddev-handover.sh:445/456/471/720/738, ddev-migrate.sh:355/527) are the commented directional re-own logic, and log.sh:44-45 operates on a root-created dir — neither is the F25 cp-natural-mode-window class. F25 pin is an awk line-number compare matching only `_sb_sudo` code lines, placed before the summary, fails on reorder.
6. **New swallows/pins**: F9 newline pins drive REAL in all four suites (exactly one WARN line + `oco?d`); F2b gate pins drive REAL in three suites (passthrough silent / fallback loud / newline sanitized); F7 harness executes the skip with a ui_detail stub + both-arms assertion; F11 drives the extracted parser both directions (dict → rc≠0 silent, scalar/null list → ids); F16 fixture executes the bare-file branch; **seq load-bearing confirmed in both named probes** (test-skills-lint.sh:227 `$(seq 1 401)`; test-line-length.sh:163-172, six `$(seq …)` uses). Every new pin sits before its suite's summary gate (verified in diff context for all eight touched suites). Remaining gaps: W3, W4, W5.

## Coverage

Covered: all six assigned sections across the full diff range (37 files; internal/reviews bookkeeping skipped except where claims intersected — the "e2e drives the arms" and "parity pin caught the first drift" claims were the ones audited). Deferred: (a) functional execution of the unit suites (read-only review; the wave's own gate log claims green runs); (b) the F16/F17/F18 citation-format sweep beyond spot-check of test-skills-lint (049dd04's 14-site citation sweep is bookkeeping-adjacent and outside the mechanical classes); (c) docs pin pairs in test-docs.sh (005590a) — content accuracy, not mechanical class; (d) `unverified` residue: none — every suspicion above was resolved with one follow-up read except the positive existence of *any* indirect e2e backup-arm driver, which I could not find and have reported as W3's evidence gap rather than asserted as definite.

### Axis S — security (GLM-5.3-Flash)

## Findings index

| ID | Severity | One-liner |
|----|----------|-----------|
| S1 | INFO | X1 charset gate admits a trailing hyphen (`opencode-`) — no exploit path found, recorded for completeness |
| S2 | INFO | DRY_RUN uninstall now prints six NEW unconditional success lines ("sudoers removed.") over ops that were only echoed — in-file-sanctioned convention, transcript-honesty only |
| S3 | INFO | F25's chmod-before-chown narrows but does not close the cp-natural-0755 window on the live name (residual mv→chmod gap in `copy_binary_atomic`) — pre-existing, comment's claim is accurately scoped |

No HIGH or MED findings. Every new construct was tested against the hunt list and held.

## Details

**S1 — INFO — trailing hyphen passes the X1 gate.**
Wave-introduced (gate mirrors; the pattern itself predates this wave in uninstall.sh).
Evidence: `files/opencode-permissions-kit-lib/management/config.sh:108`, `management/update.sh:445`, `management/status.sh:81`, `management/uninstall.sh:230` — all four use:
```sh
case "$OPENCODE_USER" in
    ''|*[!A-Za-z0-9_.-]*|[.-]*|*[.])
```
`opencode-` passes (leading `-`/`.` and trailing `.` are rejected, trailing `-` is not). Why it matters (marginally): I traced the downstream flows — `id -gn`, `getent passwd`, `sudo -u`, ddev-handover argv, `_bk_fail` labels, WARN echoes — the value is always quoted and never option-positioned after the gate (leading `-`, the actual argv-injection shape, *is* rejected). No realistic impact; leading-hyphen rejection is what closes the real hole.

**S2 — INFO — DRY run logs success for removals that did not happen.**
Wave-introduced (the six new verdict arms).
Evidence: `management/uninstall.sh:269-273` (and the five sibling sections): `un_rc_q` in DRY mode only echoes `  [DRY] …` (`uninstall.sh:197-199`), `_un_partial` stays empty, so the arm prints `echo "sudoers removed."` and `log "sudoers removed: …"`. Why it matters: the audit log records a removal that a dry run did not perform. Sanctioned by the in-file comment (`uninstall.sh:821-823`: "DRY_RUN keeps the [DRY] echoes and the success lines (the run/run_q convention)") and the DRY banner (`uninstall.sh:158`), so this is convention-conformant — recorded so the main session can dispose of it knowingly.

**S3 — INFO — residual 0755 window between `mv` and the new first-op `chmod` in `secure_binary`.**
Pre-existing (window); the wave comment is wave-introduced but accurate as scoped.
Evidence: `sh/secure-binary.sh:38-47` — the comment claims "no cp-natural-755 window on the live name **between the two**"; that is literally true (chown no longer delays the chmod). The window `copy_binary_atomic` (`secure-binary.sh:72-84`) leaves is `mv`→`secure_binary` entry: the tmp is moved with cp-natural 0755 and hardened only when `secure_binary` runs (all three update.sh call sites do this immediately: `update.sh:1004`, `1064`, `1345`). Why it matters (marginally): a local user polling the path could exec the unhardened binary for a sub-second window; the binary is non-setuid and meant to be group-executable, so no realistic privilege outcome. `copy_file_atomic` (`secure-binary.sh:101-118`) closes the analogous window by applying the mode before the rename; `copy_binary_atomic` takes no mode parameter. Deferred to the main session — pre-existing, not introduced by this wave.

## Per-construct verification (no finding)

- **X1 gates + tr sanitization (4 sites):** dangerous ASCII (newline/tab/quote/backslash/glob) can never fall inside `A-Za-z0-9_.-` under any locale, so they always hit `[!…]` → fallback. UTF-8 multi-byte bytes likewise always rejected. `tr -c 'A-Za-z0-9_.-' '?'` is byte-wise — no newline or quote survives into the WARN, so the sanitized echo cannot forge transcript lines (`config.sh:110`, `update.sh:447`, `status.sh:82`, `uninstall.sh:231`).
- **getent-home refusal (3 twins + per-root loop):** `getpwnam` returns the first match only (no multi-line variable); empty getent falls back to the literal compare (fail-safe). Slash forms: config/install strip one slash then reject `*//*`, `*/.`, `/./`, `*/./*`, `*..*` **before** the compare (`config.sh:346-351`); the uninstall refusal runs before its dot gates, and every non-canonical spelling (`//`, `/.`) is caught by those gates (`uninstall.sh:674-705`).
- **un_rc_q + six sections:** no eval, operands all literals or from fixed for-lists; per-root loop reset is inside the loop (`uninstall.sh:735-736`) with the verdict in the same iteration (~798); every early section resets immediately before its ops — no cross-section bleed; WARN/log text is fixed labels plus numeric gids.
- **install.sh recorder/pipe:** `OPENCODE_USER` is the constant literal (`install.sh:349`; conf is only sed-extracted per key, never sourced) and `DEFAULT_USER` is charset-gated at `install.sh:635` before any `_bk_fail` label interpolates them. pipefail is set at `install.sh:47` — load-bearing and present: with `-f`, a failed curl yields an empty body, bash exits 0, and only pipefail surfaces the rc to the `|| { …; exit 1; }` wrapper. The user-local-binary cp-failure leg keeps the file (`rm` not reached, `install.sh:1950-1956`). `_bk_fail` is defined in `do_plan_phase`, called in `do_deploy_phase` — phases run sequentially in one process (`install.sh:2633-2635`), so it is always in scope; the summary guards with `${_BK_FAIL:-}`. Both getfacl sites rc-observe and warn — fail-closed.
- **setup-container-backend rc gate:** `_dc_start_rc` is only touched at `bin/setup-container-backend:328-329`, one dispatch per process (lines 392-393) — no stale-rc path; `|| _dc_start_rc=$?` captures the true rc; failure WARNs on stderr, `OPENCODE_DOCKER_HOST` still prints per the stated contract, wrapper re-probes.
- **status.sh isinstance gate:** non-list feed → `sys.exit(1)` → `ADV_PARSE_OK` false → "unavailable" row — never a false "ok"; non-dict entries skipped. Residual info loss (an upstream dict-envelope feed would read as "offline/blocked", `status.sh:593`) is the fail-closed direction.
- **opk exit 1 (`bin/opk:329-334`):** converts a fall-through rc 0 into fail-closed. Correct.

## Coverage

Covered: all eight wave constructs across the five planned sections, with surrounding context read for each hunk (`project_path_sane` full function, `un_rc_q`/`run`/`run_q` definitions, per-root revert loop end-to-end, secure-binary.sh whole file, status.sh advisory feed block, setup-container-backend dispatch, install.sh phase layout and DEFAULT_USER gate). Deferred: (a) the DRY-success-line convention and (b) the `copy_binary_atomic` mode-before-rename parity — both recorded as S2/S3 rather than investigated further because neither is a realistic-impact hole; (c) trailing-whitespace home fields in a hand-edited `/etc/passwd` would defeat only the getent arm while the literal arm still applies — unrealistic precondition (passwd write access = game over), not flagged. Unverified: none — every suspicion raised during the pass was resolved with one follow-up read.

### Axis Q — quality (GLM-5.3-Flash)

## Findings index

| ID | Severity | One-liner |
|---|---|---|
| Q1 | MED | Both e2e suites ran green on the final tree, but the run is recorded nowhere in-repo — no commit message, no resolution entry, no tree SHA + counts |
| Q2 | LOW | resolution.md claims "zero `run sudo rm` left in the file" while the shipped pin asserts exactly 1 remains (the plugins loop) |
| Q3 | LOW | Commit 049dd04 claims the citation sweep hit "14 bare finding-ID references across nine suites" — it is 14 sites across ten suites |
| Q4 | INFO | A few case-disambiguated but non-canonical finding-ID citations survive at HEAD, outside the swept shape |

## Detail

### Q1 — MED — e2e runs happened but are unrecorded; commit gate lists and resolution ledger are silent on them
- **Provenance:** wave-introduced.
- **Evidence:** The wave changed semantics of root-run scripts — install.sh fail-loud recorder (c2cc5a0), update/config/status shape gates (ed372e2), uninstall rc routing (656350e), opk exit-1 rc contract (092bcd6), setup-container-backend rc gating (54758f2). AGENTS.md (Testing) owes both e2e suites in-wave for exactly this class. Every commit message in range claims gates as unit suites only, e.g. 701b867: "gates green before commit: full make test, reviews lint 33, parity 33, line-length, INDEX regenerated" — no commit in 0cff825..701b867 names `make e2e` or `e2e-rootless`. resolution.md (all 145 lines read) contains no e2e-run record and no tree SHA + counts. The runs did happen: `/var/www/vhosts/opencode-permissions-kit/logs/e2e-20261025-221402.log` ends "Passed: 309", `e2e-rootless-20261025-221402.log` ends "Passed: 47", started 22:14 — after the final commit 701b867 (22:13:55). An earlier parallel pair (21:43/21:46, also green) predates c2cc5a0/54758f2/6e406de, so only the 22:14 pair covers the shipped-script changes. The logs stamp no tree SHA, and `../logs/` is gitignored and pruned by `logs-cleanup.sh` (3 newest per suite).
- **Why it matters:** The substance of the definition-of-done appears satisfied, but the repo cannot prove it — the process's own record requirement (tree SHA + counts) is unmet, and the resolution ledger this review chain audits is unauditable on the e2e axis once the logs rotate away. Conditions: severity holds as long as no other in-repo record exists (PR body not checked from here — marked unverified for that one surface).

### Q2 — LOW — resolution.md's a F3 evidence contradicts the actual residual count
- **Provenance:** wave-introduced.
- **Evidence:** resolution.md:90-91: "Pins (test-uninstall): zero `run sudo rm` left in the file" — but uninstall.sh:403 retains `run sudo rm -rf "${_un_dir:?}/plugins/opencode-permissions-kit"`, and the pin itself asserts the one residual: test-uninstall.sh:1498-1499 `if [ "$(grep -c 'run sudo rm' "$UNINSTALL")" = 1 ] && grep -q 'run sudo rm -rf "${_un_dir:?}/plugins/opencode-permissions-kit"'`. The commit message (656350e) states it correctly ("the count pin anchors exactly that residual"); only the ledger prose is wrong. Secondary drift in the same passage: resolution.md:88 cites the plugins ops as "(:400-401)"; at HEAD they are lines 403-404.
- **Why it matters:** The ledger is the audit substrate; a reader trusting "zero left" would misread the pin's purpose (anchoring the one expected residual) and could flag the pin as broken or the sweep as incomplete. Code and pins are correct; the drift is prose-only, hence LOW.

### Q3 — LOW — "nine suites" in the F17 commit claim is actually ten
- **Provenance:** wave-introduced.
- **Evidence:** Recount over the range: 14 qualified sites — test-container-backend (c W9), test-ddev-as-opencode (b W7), test-e2e-sources (b W1), test-fs-baseline (b-S2 x2), test-git-config (a W1, b W3), test-kit-cli (e-S1), test-rules-meta (a W2), test-skills-lint (b S3, c S1, b S4/B2), test-uninstall (b-S1) = 13 sites in nine suites, plus test-docs.sh ("the addition direction of the a-W1 class" → "the #256 a W1 class") = the 14th site in a tenth suite. 049dd04's message: "14 bare finding-ID references across nine suites qualified". The resolution row (a F17) says only "14 bare citations qualified" — accurate; the suite count is wrong only in the commit message.
- **Why it matters:** Minor self-report inaccuracy of exactly the kind this axis audits; the count of 14 is correct, the suite cardinality is not.

### Q4 — INFO — residual non-canonical citations outside the swept shape
- **Provenance:** wave-introduced (the sweep made them visible; they predate it).
- **Evidence:** At HEAD, paren-shaped bare IDs that the sweep did not canonicalize, all case-disambiguated in-string so not ambiguous: test-status.sh:2711/2713 `pass "#221: SIGINT mid-stream: ... (b W1)"` / `fail "#221: KeyboardInterrupt ... (b W1)"` (case named via the `#221:` prefix, not the canonical `(#221 b W1)` form of agent/conventions.md "Referencing review findings"); test-docs.sh:272 `# --- pr-00263 a F5 (c C8): ...`; test-install-args.sh:829 "the two-step false-green the f-W4 sweep left bounded" (no paren, unqualified — unverified whether deliberately out of F17's scope; one follow-up read did not surface a qualification).
- **Why it matters:** Cosmetic-grepability gap only — disambiguation is achieved in each string, and F17's claim ("14 qualified") is not a "zero remain" claim, so no lie is told. Noted so the next sweep run records its grep pattern and these shapes explicitly (agent/learnings.md class-sweep discipline).

## Coverage

**Covered:** all seven docs one-liners verified sentence-by-sentence against named code sites — every new sentence TRUE (tee-overwrite vs the doc's own `sudo tee` heredoc; ensure-shared residual matching the ordered-pass comments at opk:562-608 and the deferred F4/F15 subjects; trust sentence vs install.sh:2002-2011 including the npm-registry comment; ddev export conditions vs install.sh:1737-1739 (Advanced confirm, decline sets SKIP_DDEV_MIGRATION) and Standard default-on (:361); probe-fallback vs opencode-as-opencode:414-425; hosts-mapping form in both pages; files.md never-overwritten scope vs opk's announce (:214-217) + `mv -f` replace; status missing-library scoping vs the five sh/-helper rows (status.sh:365, 789, 864, 1018, 1115); pre-install exit codes vs status.sh:104-118; python3 hard gate vs install.sh:574-586 with both abort messages at :575/:584). test-docs.sh pins verified both directions — every absent-anchor is verbatim OLD text confirmed against the base blobs (checked `git show 0cff825:` wording), not a paraphrase. Test-hygiene quartet: F16 fixture pin executes the new branch; F18 awk state walk collects the single current case arm (ddev-handover.sh:466) and the comment's "all arms" claim matches current reality; check-host seq entry matches real usage in both named suites. New comments all verified true at HEAD: un_rc_q header, userdel rc comment, opk C2 comment + `exit 1`, secure-binary chmod-before-chown, X1 gates (charset pattern byte-identical across config/update/status/uninstall), F7 (ui_detail has a working inline fallback at update.sh:321 while `log()` is the `:;` stub at :343), F13 (OPENCODE_DOCKER_HOST prints unconditionally), F6/F8/F19 (pipefail at install.sh:47, six `_bk_fail` sites, INCOMPLETE row). Dead code: none found. Ledger bookkeeping: all ten Commit-column SHAs real and in-range, no `<SHA>` placeholders, every deliberately-not-done row carries a reason.

**Deferred:** did not re-run `make test`/lint/reviews-lint myself (read-only session; commits claim green, no counter-evidence surfaced); "reviews lint 33, parity 33" counts not independently recomputed; the sharing-group degrade half of the getting-started python3 sentence accepted per the ledger's E2-axis review rather than deep-verified in fs-baseline.sh; resolution.md:129-130's "e2e scenarios ... none flips" claim verified empirically (green 309-scenario run post-dating the exit-1 change) rather than by reading scenario sources; PR-body surface for an e2e record not reachable from this checkout (noted under Q1).

## Verification notes (house, GLM-5.3)

Every finding was re-verified against the code at 701b867:

- **Q1 timeline normalized** (the reviewer read raw log-name timestamps):
  the log filenames carry LOCAL time (+0100), the host clock and commit
  timestamps compared here are UTC. Final-tree pair:
  `e2e-20261025-221402.log` (mtime 22:17:18+0100 = 21:17:18Z, ends
  "Passed: 309") and `e2e-rootless-20261025-221402.log` (mtime
  22:16:01+0100 = 21:16:01Z, "Passed: 47") — started 21:14:02Z, i.e.
  7 s after HEAD 701b867 (21:13:55Z) and BEFORE this pass's reader
  window (21:22:21Z). Earlier pair (21:43/21:46 local = 20:43–20:48Z)
  predates c2cc5a0 (20:56:47Z) — the reviewer's coverage split holds.
  Both suites green, no in-repo record anywhere (commit messages,
  resolution.md, no ledger file; `git log -S'e2e' 0cff825..HEAD` empty
  of run records). MED held: RM-0113's discharge record (tree SHA +
  counts) is the release gate's audit surface and it is unmet. The
  substance (green runs on the final tree) existed before this snapshot
  was written — the finding is the missing RECORD, not a missing run.
- **W1/W2**: confirmed by direct read — both sites match the fixed
  F6/F8 shape (`2>/dev/null || true` + unconditional success line), and
  neither routes through `_bk_fail` (grep of all `_bk_fail` sites:
  :723/:726/:728/:732/:736/:1954 only). The F6 resolution row's own
  words ("all six pre-install backup copies") enumerate six sites —
  these two are the siblings the L1 class sweep owed and missed.
- **W3**: the only e2e hit for the recorder/gacl anchors is a binary
  cache tar (`tests/e2e/cache/ddev-images-…tar`, random bytes) — no
  scenario source drives any arm. Comment-and-pin pair verified as
  quoted.
- **W4**: arithmetic verified — 5 occurrences (:328/:329/:339/:344/:346),
  `>= 3` floor survives deletion of :328-329. The wave's own exact-count
  precedent (`= 1` in test-uninstall) shows the intended discipline.
- **Q2**: grep count at HEAD = 1; pin asserts `= 1` plus the verbatim
  residual line; resolution prose says "zero". Prose-only drift (the
  commit message states it correctly) — LOW.
- **Q3**: the 14th site confirmed in the 049dd04 diff
  (test-docs.sh: `the a-W1 class` → `the #256 a W1 class`); ten suites
  carry the 14 sites. Severity kept LOW on the pr-00259 b Q1/Q2
  precedent (evidence-accuracy corrections, LOW, both fixed in-wave).
- **Q4**: the reviewer's one `unverified` residual resolved:
  test-install-args.sh:829 exists and IS a bare `f-W4` (no case
  qualifier) — outside F17's swept paren shape, in-string context
  disambiguates; INFO stands.
- **S1/S2/S3**: all three confirmed as scoped (pattern sites,
  convention comments at :544/:621/:826/:880, chmod→chown order +
  mode-less `copy_binary_atomic`). No severity change.

No finding retracted; no severity mapping changed any finding's band
(Q3 was weighed for INFO — kept LOW per the cited precedent).

## Retracted / ghost findings

None this pass — all 13 reported findings verified; the one reviewer
`unverified` residual (Q4's test-install-args.sh:829) was resolved by a
main-session read before entering the index.

## Calibration

Three axes, one fast-tier agent each (wave scope — no per-axis
redundancy; that is the full/release-shape budget). Yield concentrated
exactly on the round's own error classes: the two sweep gaps (W1/W2)
are the L1 class-sweep discipline applied to the wave's own F6/F8 fix;
the pin findings (W3/W4/W5) are the fail-loud/discriminate discipline
applied to the wave's own new pins; Q1–Q3 are ledger/commit-claim
accuracy — the class the quality axis was aimed at. The security axis
returned no MED/HIGH: consistent with the fixes being
hardening-shaped; its three INFOs are accurately-scoped residuals and a
convention-conformant DRY shape, not missed holes. No cross-axis
duplicates (unlike snapshot a's F2/F14/F23 merges) — the axes'
territories were disjoint by design this pass. The stop rule (MED/HIGH
reads) lands on Q1: its likely fix is a ledger record (bookkeeping, not
review-relevant code per RM-0065) — whether that closes the loop or a
micro-wave review is owed after W1/W2-style code fixes is the
maintainer's disposition call, not this snapshot's.

## Run provenance

- Host window (UTC): fan-out start **2026-10-25T21:22:21Z**, all
  reviewers returned by **21:36:59Z** (main-session wall clock).
- Reviewer agents: 3x `zai-coding-plan/glm-5.3-flash` (explore
  reader agents, read-only): W mechanical sweep
  (ses_e8b0dea06ffeFHJ3g5ivD3wnJY), S security
  (ses_e8b0dea04ffeWOhTbyBiG26W2w), Q quality
  (ses_e8b0dea02ffefFuKMoUK2TG14U). Checkpoint launch stamps (sandbox
  clocks, ~1 min after host start): W 22:23:13 local, S 22:23:12 local,
  Q 21:23Z — sandbox stamps mix local and UTC forms; skew ≤ ~1 min,
  normalized against the host window.
- Checkpoints: `/tmp/opencode/pr-00263-d/checkpoints/{W-sweep,
  S-security,Q-quality}.md` (session scratch outside the reviewed
  tree; absorbed here).
- Sabotage spot-check (window a — BEFORE fan-out, no readers running):
  the c C2 pin was executed against a deleted construct — `exit 1`
  removed from opk:332, `sh tests/unit/test-kit-cli.sh` FAILed exactly
  at "settings edit arm A (#244 f W2 + pr-00263 c C2, rc=0, …)",
  `git restore` (tree was committed-clean at HEAD), suite green again
  ("All CLI dispatcher tests passed"). No mutation window overlapped
  the fan-out; no two-direction screening owed (RM-0111).
- Concurrent host activity (disclosed): the maintainer ran both e2e
  suites twice during the round — pairs ending 20:46/20:48Z and
  21:16/21:17Z (log-name stamps are local +0100), both BEFORE the
  reader window (21:22:21Z–21:36:59Z); logs live outside the repo
  (`../logs/`), the tree stayed porcelain-clean throughout the fan-out
  (checked 21:36:59Z).
- Tree under review: `release/0.0.57 @ 701b867`, porcelain-clean
  before, during and after the pass.
- Gates run before this snapshot's commit: `sh
  tests/unit/test-reviews-lint.sh`, `sh
  tests/unit/test-reviews-parity.sh`, `sh
  tests/unit/test-line-length.sh`, INDEX regenerated via
  `python3 scripts/gen-review-index.py` (check-then-commit).
- Environment: opencode kit checkout at
  `/var/www/vhosts/opencode-permissions-kit/repo` (kit-managed
  install, agent user `opencode`); main session GLM-5.3.

## Recommendation

The round's fixes hold — no regression, no rc backflip, no lying
comment among the verified surfaces; the wave's classes closed where
they claimed to. Dispositions owed (maintainer's call): **Q1** (record
the e2e discharge — tree SHA + counts into the ledger; bookkeeping
only), **W1/W2** (route the two missed backup sites through `_bk_fail`
— shipped-code change, LOW), **W3/W4** (make the pins discriminate /
correct the pin comment — tests), **Q2/Q3** (ledger prose + a
correction note for the commit-message count — bookkeeping), W5/W6/
S1/S2/S3/Q4 (record-or-drop residuals). Fixes that touch production or
test code (W1/W2, W3/W4) owe a micro-wave review per the stop rule;
the bookkeeping-only items do not (RM-0065/66).
