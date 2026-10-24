<!-- review-meta
ID: pr-00243
Snapshot: c
Subject: wave review of the b-wave's fix wave — writer-parity blocklist, stale pre-state pin, un_rc_q rename
Scope: wave
Base: 0.0.56 @ f9ff0da
Diff: f9ff0da..e502c97
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/X/Q, fast tier GLM-5.3-Flash)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review c — wave review of the b-wave's fix wave (pr-00243)

Round c over the diff f9ff0da..e502c97 (2 commits: 1d07e2a "fix(uninstall):
blocklist writer parity, pinned section reset, un_rc_q rename (#243 b S1 S2
X1 Q1 Q2 Q4)" and e502c97's test-arm extension — the Q2 section-WARN pin the
post-commit spot-check surfaced — plus resolution bookkeeping). Shipped
material: uninstall.sh (55 changed lines: parity blocklist, rename, flag
gate, openchamber flag-set) and test-uninstall.sh (143: block-identity awk
extraction, parity pin, stale pre-state, behavioral blocklist arm, family
filter); docs untouched. All 6 implemented b-findings were audited as
LANDED by the S axis (mechanism + pin each) and spot-confirmed in
verification; this snapshot's findings are about the fix wave's own edges —
dominated by one theme: the writer-parity CLAIM has holes the parity pin
cannot see (normalization and non-case refusals).

## Findings index (combined)

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | INFO | b S1's awk machine has no pin of its own — on the shipped tree the deleted old extractor yields the identical token set; the hazard it guards is backstopped only transitively by the b X1 parity pin | wave-introduced |
| S2 | INFO | b Q1's `_unarm_show` family filter is unpinned by construction — no pin exercises the helper, dropping a family reds nothing | wave-introduced |
| X1 | HIGH (→ MED in verification) | Reader blocklist accepts `/var/` and `/home/` (trailing slash on the two bare arms) — writer-refused system trees reach the root-run ops | fix-induced |
| X2 | MED | Writer accepts `/var//` and `/home//` (single-slash strip) then cd/pwd-normalizes — root-run baseline runs over `/var`/`/home` | pre-existing (config.sh, outside diff; surfaced by the parity comparison) |
| X3 | LOW | Blocklist matches lexical text only — a symlinked conf root routes the root-run setfacl/chmod ops past it | pre-existing |
| X4 | INFO | Reader form gate lacks the writer's `*[[:space:]]*` arm (parity gap, defanged) — restates the recorded a X2 disposition | pre-existing (a-wave gate) |
| Q1 | MED | Blocklist comment claims "every system path project_path_sane refuses" but the writer's `/home/$OPENCODE_USER` refusal (outside the case blocklist) has no reader counterpart — and the parity pin is structurally blind to it | wave-introduced (comment); behavior gap pre-existing |
| Q2 | LOW | `_unarm_show`'s `tail -6` truncates the asserted discriminator on red in high-match arms (system-path, two-roots) | fix-induced (b Q1 residual) |
| Q3 | LOW | System-path behavioral arm feeds `/srv` `/media` calling them "host-existent"; on a host lacking them the arm false-REDs via the `[ ! -d ]` pre-gate | wave-introduced |
| Q4 | INFO | Config-dirs closing reordered: the WARN now prints *after* the PARTIALLY log line (was before) — user-visible output-order delta | fix-induced |
| Q5 | INFO | Temp-prefix divergence comment says the ops are "uid/gid-matched chown plus kit-gid ACL strip only" — omits the third bounded op, `chmod g-s` | wave-introduced |

Provenance split: 5 wave-introduced (S1, S2, Q1, Q3, Q5) + 2 fix-induced
(X1, Q2, Q4) + 3 pre-existing (X2, X3, X4) + 1 hybrid (Q1 counted above).
As reported: 1 HIGH, 2 MED, 3 LOW, 5 INFO; after verification X1 adjusts to
MED (rationale in the verification table) → 3 MED, 3 LOW, 5 INFO.

---

## Axis S (mechanical sweep), verbatim

# Mechanical sweep — pr-00243 b-wave (f9ff0da..e502c97, files/ tests/)

## Findings index

| ID | Severity | One-liner |
|----|----------|-----------|
| S1 | INFO | b S1's awk state machine has no pin of its own — on the shipped tree the deleted old extractor yields the identical token set; the hazard it guards is backstopped only transitively by the b X1 parity pin |
| S2 | INFO | b Q1's `_unarm_show` family filter is unpinned by construction — no pin exercises the helper, dropping a family reds nothing |

No MED/HIGH findings. All six claimed mechanisms verified present; all claimed pins verified discriminating (probes below); full `test-uninstall.sh` green on this tree.

## Detail

**S1 — INFO — b S1 machine itself unpinned; parity pin is the backstop. Provenance: wave-introduced.**
Mechanism present: `tests/unit/test-uninstall.sh:205-220` is the awk state machine keyed to block identity (`if ($0 ~ /Skipping system path/) keep=1`, line 212). But the only pin on the extraction is non-emptiness (lines 221-225: `if [ -n "$SCREEN_PATTERNS" ]`). Probe (a): the deleted old shape-keyed chain run against shipped `uninstall.sh` yields the same 42 tokens (old joins with spaces, new with `|` — token sets identical), so reverting the awk reds nothing today. However the b S1 hazard is still dead: probe (b) simulated the exact /-leading dot-arm reorder under the old extractor — the parity pin (line 291) REDS (`/./`, `*/./*`, `./*`, `*/.`, `*//*`, `*..*` missing from writer set), while the new awk on the mutated file yields exactly the shipped set (immune). Why it matters: the landing claim "a pin exists that would go red if the mechanism were deleted" is false for the mechanism itself — only true for its failure consequence. If the backstop parity pin is ever deleted too, the machine's protection vanishes silently.

**S2 — INFO — `_unarm_show` filter unpinned. Provenance: wave-introduced.**
Mechanism present and matches the claim: `tests/unit/test-uninstall.sh:556` — `grep -E 'log:|WARN:|PARTIALLY|Removed\.|\[DRY\]|Skipping|skipped|unknown|^sudo '` with `tail -6`. No pin exercises `_unarm_show`; it appears only inside `fail "…(out=$(_unarm_show …))"` branches (e.g. lines 575, 695, 763). Deleting a family from the filter reds nothing — the arms grep `$FOUT`/`$COUT` directly. The resolution claim for b Q1 is mechanism-only and is honest, but the axis's "pin that would go red if deleted" cannot be satisfied for this helper without a dedicated pin that does not exist. Why it matters: the completed diagnostics can silently regress to the old blind `tail -N` behavior.

## Landing audit (mechanism + pin, verified)

- **b S1** — mechanism ✓ (test:205-220); pin: extraction pin (221-225) + transitive backstop, see S1.
- **b S2** — mechanism ✓: stale pre-state planted at test:730-731 (`_un_partial="find-chown failed (stale from the project loop)"`, `_un_revert_failed=1`); shipped reset at uninstall.sh:685-686 is INSIDE the extracted CFG_SECTION range (anchor `^echo "--- Removing kit config directories` = line 678, first `^echo ""$` = line 732). Pins ✓: all-ok arm reds four ways without the reset (test:755 `Removed.`, 758 `!WARN:`, 759 `!PARTIALLY`, 760 direct stale grep); dry arm discriminates indirectly (stale leak prints the PARTIALLY log line and suppresses `Removed.` → test:796/798 red). Claim wording "all-ok/dry arms assert the stale string absent" is loose for the dry arm (it greps `PARTIALLY`/`Removed.`, not the stale string) but the pin reds either way — verified logically, not a gap.
- **b X1** — mechanism ✓ (uninstall.sh:596-600, writer arm order). Pins ✓, all four families: static rejected reps (test:249-255, incl. `/libexec/x`), allowed reps incl. `/tmp/x /var/tmp/x` (test:267-273), parity pin (test:283-295), behavioral arm (test:681-696). Executed both pipelines verbatim: reader awk = exactly the 42 shipped blocklist tokens; writer sed = 46 tokens, minus exactly `/tmp /tmp/* /var/tmp /var/tmp/*` = 42; sets equal — token FORMS match byte-for-byte (`/var/cache/*` style both sides). Writer fail-loud probes: literal /-leading stray line in `project_path_sane` → parity reds; writer arm addition → parity reds; a comment-style stray (`_PP_NORM="…" # /stray`) is not picked up (line does not start with `/`) — claim "fail-loud by construction" holds for every realistic shape. Reader `/lib*` breadth matches writer `/lib*` (config.sh:340) — no hidden divergence.
- **b Q2** — mechanism ✓: openchamber branch sets `_un_revert_failed=1` (uninstall.sh:710); section WARN gated on the flag (uninstall.sh:727-728). Pins ✓ both sides: two-rm arm asserts the gated WARN (test:783 — reds if the RUNNER's flag-set at uninstall.sh:200 were deleted); openchamber arm asserts the exact gated section WARN on the stderr channel (test:772 — reds if uninstall.sh:710 were deleted).
- **b Q4** — rename ✓: def at uninstall.sh:195 (`un_rc_q()`), `_un_rc_label` (201), exactly 7 call sites (621, 651, 652, 654, 687, 688, 715). Test side ✓: anchor (test:318), both evals (365 loop driver, 732 cfg driver), cfg canary (710). Archaeology claim verified by grep: exactly ONE hit for `un_revert_q|UN_REVERT_Q|_un_rq_label` across files/ tests/ docs/ — uninstall.sh:192, self-labeled "Renamed from un_revert_q (#243 b Q4)"; 0 unlabeled.

## Class sweep

- **Anchors resolve**: `un_rc_q` extraction 195→203 (whole function); CFG_SECTION 678→732; `case "$root"` blocks at 573/580/595 (exactly three; only 595 echoes "Skipping system path"); `project_path_sane` 311→359. No inline `esac` anywhere in uninstall.sh — no state-machine bleed risk in shipped code.
- **New fail-open constructs in this diff**: one new `|| true` (test:681 capture), matching 13 pre-existing sibling captures in the same suite — consistent convention, not flagged. No new stderr redirects; uninstall.sh:700/705/706 (`2>/dev/null`, `rmdir … || true`) are pre-existing and justified by the policy comment at 689-695.
- **Unconditional success closers**: none next to changed ops — loop closing (uninstall.sh:665-673) and section closing (716-729) both conditioned; openchamber success log fires only in the success branch (707).
- **Sibling sites**: no other shape-keyed case-pattern extractor in tests/ (other `sed -n` anchors extract whole function blocks — different hazard class, pre-existing, out of scope); `test-project-paths.sh:59` tests the writer behaviorally and is unaffected by the reader change; no docs pin the reader list.

## Coverage

Covered: full wave diff; shipped context of every hunk; both extraction pipelines executed verbatim against shipped files plus four mutation probes; rename/anchor/sibling greps; full `sh tests/unit/test-uninstall.sh` run (green, "All uninstall tests passed"); shellcheck warning count identical pre/post (16/16 — no new findings). Deferred: e2e suites (not in this diff's file scope — no changes to install/update/wrapper); the behavioral blocklist arm's host-dependence on `/media /mnt /srv /opt /home /var` (all exist on this host; a host lacking one would red the suite LOUDLY by design, documented at test:678-680 — recorded, not flagged); the awk's hypothetical future-shape bleed (inline `esac` in a root block — no realistic trigger in shipped code, would fail loud via changed yield). Checkpoints at /tmp/opencode/pr-00243-c/checkpoints/s.md; probes under /tmp/opencode/pr-00243-c/probe-s/ (repo tree untouched).

---

## Axis X (security), verbatim

# Security review — pr-00243-c, wave diff `f9ff0da..e502c97` (files/, tests/)

### Findings index

| ID | Severity | Summary | Provenance |
|----|----------|---------|------------|
| X1 | HIGH | Reader blocklist accepts `/var/` and `/home/` (trailing slash on the two bare arms) — writer-refused system trees reach the root-run ops | fix-induced (wave-introduced class) |
| X2 | MED | Writer accepts `/var//` and `/home//` (single-slash strip) then cd/pwd-normalizes — root-run baseline runs over `/var`/`/home` | pre-existing (config.sh, outside diff; surfaced by the parity comparison) |
| X3 | LOW | Blocklist matches lexical text only — a symlinked conf root routes the root-run setfacl/chmod ops past it | pre-existing |
| X4 | INFO | Reader form gate lacks the writer's `*[[:space:]]*` arm (parity gap, defanged) | pre-existing (a-wave gate) |

### Details

**X1 — HIGH — `/var/` and `/home/` pass gate+blocklist; writer refuses both.** Verified empirically with the shipped arms extracted verbatim (probe: `/tmp/opencode/pr-00243-c/probe-x/probe.sh`, gate THEN blocklist in shipped order): both forms yield READER=PASS / WRITER=REFUSED. Evidence: the reader never normalizes before matching (uninstall.sh:564-604), while the writer strips a trailing slash first (config.sh:312 `_pp="${1%/}"` → `/var/` becomes `/var`, refused by its arm). The new blocklist's bare arms have no `/*` siblings — exactly two, and exactly the two that break:
```
uninstall.sh:596: /|/bin|/bin/*|/boot|/boot/*|/dev|/dev/*|/etc|/etc/*|/home|/lib*|\
uninstall.sh:599: /var|/var/cache|/var/cache/*|/var/lib|/var/lib/*|/var/log|/var/log/*|\
```
`/home/` matches no arm (no `/home/*` exists); `/var/` matches no arm (no `/var/*` exists — deliberate for `/var/www`, but it leaves the bare arm unpaired). `/etc/`, `/usr/`, `/bin/`, `/var/cache/`, `/libexec/` etc. are all blocked because their `/*` arms match via `*`=empty — confirmed by probe. The gate's `*//*` arm catches only the double-slash spellings, not the single trailing slash. Trigger: a hand-edited `projects.conf` line `/home/` or `/var/` (the wave's own threat model at uninstall.sh:568-571 treats hand-edits as the threat; both dirs exist on every host so `[ ! -d ]` at line 566 passes). Reaching ops: `sudo find /var/ ! -type l \( -uid … \) -exec chown …` (621-622), `sudo setfacl -R -x g:<gid> /var/` ×2 (651-652), `sudo chmod g-s /var/` (654) — over the entire /var or /home tree. Ops stay id/gid-bounded (same bound as the pinned /tmp divergence) but over a system tree the writer explicitly refuses — the exact class the blocklist exists to stop, contradicting the wave's parity claim. The new parity pin (tests/unit/test-uninstall.sh:283-292) compares extracted pattern TOKEN SETS, which are identical on both sides; the divergence lives in normalization, so the pin is blind to it, and the behavioral arm (test:681) feeds only bare `/var /home`. Note the OLD blocklist had no `/home`/`/var` arms at all and every old bare arm had a `/*` sibling, so this bypass class is created by this wave's arm additions. The writer's own comment (config.sh:330-334) confirms the bare arms + form gate were the intended complete defense.

**X2 — MED — writer's own double-trailing-slash hole (comparison baseline).** Probe: `/var//` and `/home//` are READER-refused (gate `*//*`) but WRITER-PASS. Cause: config.sh:312 strips exactly one trailing slash (`/var//` → `/var/`, which contains no `//` and matches no arm — no `/var/*`, no `/home/*`). Downstream, `projects_add` normalizes and runs the baseline: config.sh:369-370 `p="${_PP_NORM:-$p}"; if _p_abs=$(cd "$p" …&& pwd); then p="$_p_abs"` → `/var`, then config.sh:384 `fs_baseline_root "$p" …` — root-run chgrp/setfacl baseline over all of `/var` (the refusal message at config.sh:366 names those ops). Same shape at config.sh:401 (handover). Pre-existing, untouched by this diff; reported because it weakens the parity premise in the reverse direction (reader stricter) and because a writer-stored `/var//` root would be silently skipped by the reader at uninstall. Realism: requires a double-trailing-slash input to the writer, hence MED rather than HIGH.

**X3 — LOW — lexical-only screening; symlinked conf root.** The blocklist (uninstall.sh:595-604) matches conf TEXT; `[ -d "$root" ]` (566) follows symlinks and the kernel resolves symlinked intermediate components. A conf root that is, or resolves through, a symlink (e.g. `/var/www/vhosts/l/x` with `l → /etc/pki`) passes both gates lexically and routes `sudo setfacl -R -x g:<gid> …` (651-652) and `sudo chmod g-s` (654) onto the target tree; find-chown is guarded only on its operand by `! -type l` (621). Requires a planted symlink plus a hand-edit — LOW. Pre-existing shape (the a-wave gate and this blocklist both text-match; the writer text-matches too), not introduced here.

**X4 — INFO — missing space arm in the reader form gate.** Writer refuses `*[[:space:]]*` (config.sh:336); the reader gate (uninstall.sh:580) has no such arm, so e.g. `/var ` passes gate+blocklist. Defanged: `[ ! -d "/var " ]` (566) skips it unless a space-named directory exists, and every op quotes `"$root"` (621, 651-654), so no argv splitting. Parity-cosmetic, no root-op escape.

### Coverage

Covered: full diff plus surrounding sections of every hunk; verbatim-arm probe (61 forms) of gate→blocklist in shipped order against the sourced `project_path_sane` — all RM-0085 bypass forms from the brief plus extensions (case variants, `/./`, `/..`, `///`, whitespace noted via X4, `/lib*` prefix forms, `/var/.hidden`-class dotfiles — parity-consistent on both sides, allowed like `/var/www` by the deliberate no-`/var/*` design); op enumeration on an accepted root — find-chown is uid/gid-matched with `! -type l`, setfacl ops remove only the two numeric kit gids, `chmod g-s` is non-recursive on the root dir, so the pinned `/tmp`/`/var/tmp` divergence bound HOLDS (including trailing-slash spellings `/tmp/`, `/var/tmp/`, subsumed by the pinned class); test-side stub safety (sudo stub defined inside the subshell after the `UN_RC_Q` definition-only eval, before the `PROJECT_LOOP` eval, body never execs sudo) and the `[ ! -d ]`-before-blocklist ordering claim (uninstall.sh:566 < 595, confirmed; a missing host dir makes the arm go RED via the positive greps, not silently pass); `un_rc_q` rename semantics (DRY echo-only, failure arm intact, no leftover call sites); unquoted-expansion sweep (none introduced). Deferred: TOCTOU window between find's lstat and the batched chown (pre-existing, semantics untouched by this diff — line 621 changed name only); setfacl's internal `-R` symlink-follow behavior not verified against the man page (X3 stands on operand-resolution alone, marked accordingly); full unit suite not executed (extraction pins verified by reading plus the verbatim probe). `/VAR` case difference checked: both sides allow, `-d` defangs — not a finding. Probe artifacts: `/tmp/opencode/pr-00243-c/probe-x/` (repo tree untouched); checkpoints in `/tmp/opencode/pr-00243-c/checkpoints/x.md`.

---

## Axis Q (quality), verbatim

# Quality review — pr-00243 b-wave (`f9ff0da..e502c97`, files/ tests/)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | MED | Blocklist comment claims "every system path project_path_sane refuses" but the writer's `/home/$OPENCODE_USER` refusal (outside the case blocklist) has no reader counterpart — and the parity pin is structurally blind to it | wave-introduced (comment); behavior gap pre-existing |
| Q2 | LOW | `_unarm_show`'s `tail -6` truncates the asserted discriminator on red in high-match arms (system-path, two-roots) | fix-induced (b Q1 residual) |
| Q3 | LOW | System-path behavioral arm feeds `/srv` `/media` calling them "host-existent"; on a host lacking them the arm false-REDs via the `[ ! -d ]` pre-gate | wave-introduced |
| Q4 | INFO | Config-dirs closing reordered: the WARN now prints *after* the PARTIALLY log line (was before) — user-visible output-order delta | fix-induced |
| Q5 | INFO | Temp-prefix divergence comment says the ops are "uid/gid-matched chown plus kit-gid ACL strip only" — omits the third bounded op, `chmod g-s` | wave-introduced |

## Details

**Q1 — MED — blocklist comment over-claims writer parity; realized reader gap for the agent home.**
Evidence — `uninstall.sh:590-592`: "every system path project_path_sane refuses (config.sh), in the writer's arm order, so a hand-edited conf cannot drive the root-run revert ops over system trees the sanctioned writer would never store." But `config.sh:348-351` refuses one more path *outside* the case blocklist:
```bash
    # The agent user's own home is never a valid project root: the group
    [ "$_pp" = "/home/${OPENCODE_USER:-opencode}" ] && return 1
```
The reader blocklist (`uninstall.sh:594-600`) has bare `/home` only — `/home/opencode` matches nothing, passes the form gates, exists on every install (so `[ ! -d ]` at `uninstall.sh:566` doesn't skip it), and the root-run ops (`sudo find /home/opencode … -exec chown …`, `setfacl -R -x`, `chmod g-s`) run over the agent's config/state home — exactly the tree the comment says can't be reached. The parity pin cannot catch it: the writer-side extraction (`test:264-266`) greps only `/-leading` case-pattern lines; the agent-home refusal is a `[ … ] && return 1` line. I ran both pipelines in the probe dir: pin GREEN today, sets equal — so the suite stays green while the comment's completeness claim is false. Trigger: hand-edited projects.conf containing `/home/opencode` — the precise threat model the comment invokes. The pin's own comment ("it can never silently pass", `test:261-262`) is scoped to /-leading lines and is technically true, but together the two comments manufacture false confidence. I checked for other non-case-line writer refusals in `project_path_sane` — this is the only one (the rest are form checks the reader's form gate mirrors).

**Q2 — LOW — `_unarm_show` shows the right families but `tail -6` can hide the discriminator.**
Evidence — `test:556-557`: `| grep -E 'log:|WARN:|…|^sudo ' | tail -6`. The family regex covers every 4c/4d asserted string (audited — see coverage), but the sudo log is appended LAST in both drivers (`test:393-396`, `test:745-748`), so `tail -6` is dominated by `^sudo ` lines in high-match arms. Concrete arithmetic: the system-path arm (`test:681-695`) has 12 matching lines today (7 `Skipping` echoes incl. the always-fed `/etc`, 1 success log, 4 sudo lines); on a deleted-blocklist red, 8 roots × 4 ops = 32 sudo lines — `sudo find /var` (line ~5) and the missing `Skipping` echoes never appear in the shown tail. Same shape for the two-roots arm (`test:648-658`): 8 sudo lines push both asserted `log:` closings out of the window. Diagnostics-only; suite correctness unaffected; the fail message still names the arm.

**Q3 — LOW — "host-existent dirs" claim doesn't hold for `/srv`/`/media` on all hosts.**
Evidence — `test:682-685`: "Only host-existent dirs feed the driver: [ ! -d ] runs BEFORE the blocklist and would skip a nonexistent path silently, defanging the arm." then `"/var /home /opt /srv /media /mnt"`. `/srv` and `/media` are not created by every minimal distro/chroot. On a host without either, `[ ! -d "$root" ] && continue` (`uninstall.sh:566`) skips silently, the `grep -qF 'Skipping system path: /srv'` assertion fails, and the whole arm goes red — a host-dependent false RED (loud, self-diagnosing; the opposite of the defang the comment guards against). Severity conditioned on exotic host layouts; standard Ubuntu/Debian/CI images have both dirs.

**Q4 — INFO — output-order delta in the config-dirs closing.**
Evidence — the diff moves the WARN: before, `echo "WARN: could not fully remove config dirs …" >&2` preceded `log "config dirs + runtime artifacts PARTIALLY removed …"`; now (`uninstall.sh:719-726`) the log line prints first and the WARN is gated after it. Behavior-neutral today (all current causes set `_un_revert_failed`), and the new order matches the project loop's closing (`uninstall.sh:666-671`: PARTIALLY log → WARN → FAILED log), so it looks deliberate — flagged because it is a user-visible ordering change riding along with the flag-gate fix.

**Q5 — INFO — divergence rationale enumerates 2 of the 3 bounded ops.**
Evidence — `uninstall.sh:596-598`: "a temp-prefix entry is bounded — uid/gid-matched chown plus kit-gid ACL strip only" (the test's mirror comment, `test:250-252`, same wording). The loop also runs `sudo chmod g-s "$root"` (`uninstall.sh:654`) on every processed root, including temp-prefix ones — a mode change, not an ACL strip. The "only" claim is false by one bounded, minor op; a reader auditing the safety argument from the comment alone misses it.

## Coverage

- **Comment clusters**: b Q2 gate comment verified accurate — exactly four partial-cause sites in the cfg section (three `un_rc_q` calls + the openchamber arm, `uninstall.sh:687-688, 709, 715`), all FAILED ops, no skip causes; the openchamber arm now sets the flag so the flag is never write-only. Extraction awk verified to implement its comment exactly (block-start reset `test:206`, keep-by-body `test:213`, per-block buf, flush gated on `keep` `test:207-210` — form-gate blocks are skipped whole, including their `/*) ;;` line, which I confirmed lands in `buf` but is never flushed). `_un_cfg_out` stale-pre-state: **all four** cfg arms discriminate a leaked stale state — all-ok/dry via `!PARTIALLY`/`!stale`; openchamber-fail and two-rm-fail via exact cause-list substrings (`test:758, 770, 782`) that mismatch when the stale cause prepends — the comment's "every cfg arm discriminate" holds and even understates.
- **Assertion-family audit**: every 4c/4d asserted string (positive and negative, ~40 across 10 arms) maps to the new regex. Indirect visibility, marked as such: the `stale from the project loop` absence surfaces only inside a `PARTIALLY` log line; `revert FAILED`/`ownership reverted`/`kit ACL entries removed` negatives surface via `log:` lines; sudo negatives via `^sudo ` — the last subject to Q2 truncation.
- **Parity**: ran both extraction pipelines read-only against copies in the probe dir — sets equal after the four pinned temp tokens; reader arm order matches the writer's; `/srv` present on both sides (my first read of config.sh missed it; corrected by direct re-read of `config.sh:342`). `/tmp,/var/tmp` rationale checked against `agent/conventions.md:130-131` ("sanctioned temp prefixes") — accurate.
- **Dead code/naming**: no `un_revert_q`/`UN_REVERT_Q`/`_un_rq_label` remnants anywhere in files/, tests/, docs/ (only the intentional history note at `uninstall.sh:192`); `UN_RC_Q`, `_un_rc_label`, `_un_parity_tokens` all read; no new write-only state in the changed hunks.
- **Docs**: `docs/how-to/uninstall.md` makes no screening/blocklist claims; its WARN/PARTIALLY/manual-hint description (lines 38-46) matches behavior including the `<gid>` template pin. No drift. Clean.
- **Duplication asymmetry**: covered under Q1 — the shape-keyed writer extraction is the mechanism that makes the realized gap pin-invisible; no other non-case-line writer refusal exists today, so no second wrong-but-green scenario is live. Coverage note, not a separate finding.
- **Deferred**: did not run the unit suite (scratch restricted to probe-q; all probes were read-only extractions against copies); did not audit 4a/4b/section-5 arms — only hunks in the wave diff plus their full surrounding functions (`_un_loop_out`, `_unarm_show`, `_un_cfg_out`, the loop and cfg sections) were in scope.

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| S1 | **confirmed** | Ran all three probes myself in scratch: (a) old shape-keyed extractor on the shipped uninstall.sh yields a token set IDENTICAL to the awk's (42 tokens, `cmp` on sorted sets); (b) on a scratch copy with the dot-arm line reordered to lead with `/./`, the OLD extractor pulls `/./` into the set — the b-S1 hazard is live under the old extractor; (c) the awk on the same mutated copy yields the shipped set byte-for-byte (immune), and the mutation would redden the shipped parity pin under the old extractor (transitive backstop real). The awk mechanism's only direct pin is non-emptiness (test:221-225) — as reported. |
| S2 | **confirmed** | grep over test-uninstall.sh: all 15 `_unarm_show` occurrences (565, 577, 587, 596, 615, 627, 643, 658, 673, 695, 763, 777, 788, 801 + the def at 548) sit inside `fail "…"` strings — the helper never executes on a green run and no arm greps its output; dropping a family from the filter reds nothing. |
| X1 | **confirmed — severity adjusted HIGH → MED** | Empirically reproduced with the verbatim shipped arms in shipped order: READER `/var/`=PASS, `/home/`=PASS; WRITER (`project_path_sane`, extracted verbatim) REFUSES both (`${1%/}` strip at config.sh:312). `/etc/`, `/var/cache/`, `/libexec/` blocked via their `/*` arms — exactly the two bare arms without `/*` siblings are open. Ops reached: the loop's revert ops only (uid/gid-matched find-chown with `! -type l`, kit-gid setfacl strip ×2, non-recursive chmod g-s on the root dir) — no rm, no arbitrary chown; concrete damage bounded (over `/home/`: re-own of opencode-uid files — the agent's own home — plus setgid-bit loss on the root dir; over `/var/`: near no-op beyond the chmod). Trigger realistic (trailing-slash hand-edit — the wave's own threat model). MED not HIGH because the blast is id-bounded and strictly smaller than the pre-wave state (pre-wave `/var` AND `/var/` both passed — snapshot b X1, INFO); the actionable defect is the false parity claim plus the two reachable trees. The wave-introduced part is the arm pair without `/*` siblings — pre-wave, every bare arm except `/` had one, so the trailing-slash shape bypasses nothing pre-wave; the finding is fix-induced as reported. Parity pin blindness confirmed: it compares token SETS (identical on both sides); the divergence is normalization, outside its sight. |
| X2 | **confirmed** | Empirically: `project_path_sane /var//` and `/home//` return 0 with `_PP_NORM=/var/` and `/home/` (single `${1%/}` strip; the result contains no `//` and no arm matches — writer has no `/var/*`, `/home/*`). projects_add then canonicalizes via `cd && pwd` (config.sh:369-370) → `/var`, `/home` and runs `fs_baseline_root` (config.sh:384) + `ddev_handover_root` (:390) — root-run chgrp -R/setfacl -R over the system tree. Reader side refuses `/var//`, `/home//` at the gate (`*//*` arm — line 581 verified `*..*|/./|*/./*|./*|*/.|/*//*`), so a writer-stored `/var` root would later be skipped loudly at uninstall. Pre-existing (config.sh untouched by this diff), surfaced by the parity comparison — MED as reported: heavier ops than X1's (group baseline grants agent group-write), less realistic trigger (double-slash input to the sanctioned writer). |
| X3 | **confirmed** | Gate (573-584) and blocklist (595-604) match conf text lexically; `[ -d "$root" ]` at 566 resolves symlinks. Verified nuance the reviewer stood on: find-chown's `! -type l` (621) also excludes a symlinked ROOT operand (find -P does not follow the command-line operand), so the concrete reach is chmod g-s on a symlink-resolved operand (chmod follows) and setfacl paths through symlinked components — bounded, pre-existing, matches snapshot b's recorded deferral ("root-operand symlink dereference — pre-existing, unchanged"), now verified as a finding. LOW stands. |
| X4 | **confirmed (duplicate of a recorded disposition)** | Reader gate arms verified (580-581): no `*[[:space:]]*` arm; writer has it (config.sh:336). Defanged exactly as snapshot b's verified-clean note recorded (`[ ! -d ]` skip + full quoting; a X2 disposition row: "Space-forms stay ungated at the reader"). Kept for traceability like snapshot b's X2 — restates a deliberate, recorded decision; no new demand. |
| Q1 | **confirmed** | config.sh:351 refuses `/home/${OPENCODE_USER:-opencode}` outside the case block (verified in the read; the writer comment cites review 0.0.39a S4). My verbatim-arm probe: READER `/home/opencode`=PASS — no `/home/*` arm, gate clean. Parity pin structurally blind confirmed: writer-side extraction (test:264-266) greps `/-leading` case-pattern lines only; a `[ … ] && return 1` line can never enter its set. The comment at uninstall.sh:590-592 claims completeness ("every system path … refuses") — false for the one tree the writer guards by name. MED stands: claim-vs-behavior on the wave's own comment, reachable bounded ops, realistic trigger inside the stated threat model. |
| Q2 | **confirmed** | Driver structure verified: both `_un_loop_out` and `_un_cfg_out` cat the sudo log LAST after stdout/stderr sections; `^sudo ` matches every sudo-log line. In a deleted-blocklist red the extra roots would produce 5 roots × 4 ops = 20+ sudo lines after the skip echoes and closing logs — `tail -6` shows only the final sudo lines, hiding the missing `Skipping system path:` echoes and `log:` closings. Diagnostics-only; suite correctness unaffected. |
| Q3 | **confirmed** | Code path verified: `[ ! -d "$root" ] && continue` (uninstall.sh:566) precedes the blocklist; a missing `/srv` or `/media` silently skips, the positive `grep -qF 'Skipping system path: /srv'` then fails → false RED on hosts lacking the dir. Loud, not silent; standard distro images carry both. LOW as reported. |
| Q4 | **confirmed** | Diff-verified: the `log "… PARTIALLY removed"` line moved before the gated WARN echo (now uninstall.sh:719-726); the pre-wave order was WARN then log. Matches the project loop's closing order (666-671) — deliberate-looking alignment riding with the Q2 gate fix; user-visible ordering delta recorded as INFO. |
| Q5 | **confirmed** | Comment at uninstall.sh:596-598 (and test:250-252) says "uid/gid-matched chown plus kit-gid ACL strip only"; `un_rc_q "chmod g-s" sudo chmod g-s "$root"` runs on every processed root (uninstall.sh:654). "Only" is false by that one bounded op. INFO stands. |

## Retracted/ghost findings

None — all 11 reported findings verified against the code; one severity
adjustment (X1 HIGH → MED, rationale in the verification table).

## Run provenance

- Commission: maintainer, 2026-10-24 ("@opk-review-pass Wave Review c").
  Third snapshot of the case; rotation normal (this fresh session authored
  neither the b-wave's fixes nor any prior snapshot of the chain).
- Tree: e502c97 (feature/218-uninstall-revert-log-honesty), clean at
  fan-out (`git status --porcelain` empty) and re-verified clean after all
  reviewers returned.
- Material: fix diff f9ff0da..e502c97, shipped files only: 2 files, 153
  insertions / 40 deletions in 1d07e2a (uninstall.sh 55, test-uninstall.sh
  138) plus the test-arm extension in e502c97 (test-uninstall.sh +5/−1,
  the Q2 section-WARN pin); e502c97's resolution.md bytes are bookkeeping,
  not review material. Wave parameters (~193-line diff, above the ~50-line
  micro bound): ~8-minute budgets, 3 axes.
- Host timestamps (main session, UTC): fan-out start
  2026-10-24T18:20:32Z, end 2026-10-24T18:35:34Z.
- Reviewer subagents: 3 (cap 5 respected), fast tier
  zai-coding-plan/glm-5.3-flash, fresh contexts, axis prompts built from
  `.agents/skills/opk-review-pass/axis-prompt.md`; the main session
  (GLM-5.3) owned verification and embedded the reports.
- Checkpoints: `/tmp/opencode/pr-00243-c/checkpoints/{s,x,q}.md` (outside
  the reviewed tree), all three with launch + section stamps + return
  lines; sandbox clocks within the host window (s.md stamps in local
  +02:00, x.md/q.md relative-elapsed — no skew anomaly this round).
- Sabotage/mutation windows: none on the repo tree. Reviewer probes ran
  under `/tmp/opencode/pr-00243-c/probe-{s,x,q}/`; the main session's
  verification probes (verbatim-arm probe, extraction pipelines, the S1
  reorder mutation on a scratch copy) ran under
  `/tmp/opencode/pr-00243-c/verify/` AFTER all reviewers had returned;
  `git status --porcelain` empty at return and after verification confirms
  no reader or verifier wrote to the tree.
- Gates at snapshot time (main session, this tree, before the snapshot
  commit): `sh tests/unit/test-uninstall.sh` green (also run at baseline
  before fan-out); `make test` green; `make lint` green;
  `sh tests/unit/test-docs.sh` green; `sh tests/unit/test-line-length.sh`
  green (review-* snapshots exempt from the ratchet — verbatim over
  wrap); INDEX regenerated with this commit
  (`python3 scripts/gen-review-index.py`); `sh tests/unit/test-reviews-lint.sh`
  and `sh tests/unit/test-reviews-parity.sh` green before the commit
  carrying this file.
- e2e: no new debt — the reviewed fix wave already ran both suites in-wave
  (resolution Gates: `make e2e` 309, `make e2e-rootless` 47); this
  snapshot changes no shipped code. X2 (config.sh, pre-existing) is
  outside this round's diff; any fix wave for it owes both suites under
  RM-0113 (root-run baseline semantics).

## Recommendation

The b-wave's fixes all landed with real pins (landing audit + the
resolution's five red-for-the-right-reason sabotage spot-checks), and the
suite's own constructs held up under the reviewers' probes. The round's
findings cluster around one theme — **the writer-parity claim is narrower
than the code and comments assert**:

- **c X1 (MED) and c Q1 (MED)** are the actionable pair: reader
  normalization gaps (`/var/`, `/home/`) and the agent-home refusal the
  reader never mirrored, both invisible to the token-set parity pin. A fix
  wave (reader-side trailing-slash handling + the `/home/<agent>` arm or a
  reader-side normalization, plus probes for both) touches production code
  and owes snapshot d under RM-0067.
- **c X2 (MED)** is pre-existing writer-side (config.sh `/var//`,
  `/home//` → cd/pwd canonicalization defeats its own blocklist) — outside
  this round's diff; the natural home is Follow-up 1's update.sh/config.sh
  parity wave (gate + blocklist parity decision, both e2e suites).
- **c X3 (LOW)** joins the same follow-up family (lexical screening vs
  symlink resolution); **c X4 (INFO)** restates the recorded deliberate
  a-X2 disposition — no action.
- **c S1/S2 (INFO)** are pin-the-pin gaps (extraction and diagnostics
  helpers unpinned); **c Q2/Q3 (LOW)** are test-diagnostic hardening
  (tail window, host-portability); **c Q4/Q5 (INFO)** are wording/order
  nits in the wave's own comments and output.

Per the stop rule (RM-0064/RM-0067): a next round that fixes X1/Q1 (or
any of the LOW test findings) touches review-relevant code and owes one
more wave review; a round that dispositions everything
deliberately-not-done leaves review-relevant code untouched and closes
the loop. The loop's state is the maintainer's call — this session
records, it does not close.
