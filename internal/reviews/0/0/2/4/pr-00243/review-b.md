<!-- review-meta
ID: pr-00243
Snapshot: b
Subject: wave review of the a-wave's fix wave — rc-observed closers, form gate, docs surfaces
Scope: wave
Base: 0.0.56 @ 0410036
Diff: 0410036..a31e62b
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/X/Q, fast tier GLM-5.3-Flash)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review b — wave review of the a-wave's fix wave (pr-00243)

Round b over the fix diff 0410036..a31e62b (1 commit, a31e62b: "fix(uninstall):
rc-observed closers, projects.conf form gate, docs surfaces (#243 a S1 S2
S3 X1 X2 Q1 Q2 Q3 Q4 Q5 Q6)") — the fix wave implementing all 11 findings
of snapshot a. Shipped material: uninstall.sh (rc-observing config-dirs +
openchamber arms, reader-side form gate, degraded wording, comment
rewrites), test-uninstall.sh (stream-split driver, extra roots, cfg-dirs
driver, _unarm_show, new arms), docs/how-to/uninstall.md (surfaces
rewrite). The same commit carried the resolution ledger and INDEX row —
bookkeeping, not review material. All 11 landing claims were audited as
LANDED by the S axis (mechanism + pin each) and spot-confirmed in
verification; this snapshot's findings are about the fix wave's own edges.

## Findings index (combined)

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | LOW | SCREEN_PATTERNS filter excludes the new dot-form pattern line only incidentally — the filter is shape-keyed to `/*)`; a `/`-leading reorder of the parity-locked pattern line silently pulls dot-form patterns into the screening case | fix-induced |
| S2 | LOW | Pin gap: the config-dirs section reset (`_un_partial`/`_un_revert_failed`) is unpinned — deleting it leaves the suite green (sabotage-proven); loop→cfg cause leakage would go undetected | fix-induced |
| X1 | INFO | Reader-side blocklist is narrower than the writer's — `/var`, `/opt/*`, `/srv/*`, `/tmp/*`, `/home`, `/libexec/*` pass gate+blocklist and reach root-run revert ops from a hand-edited conf | pre-existing (unchanged by this wave) |
| X2 | INFO | Recorded follow-up verified TRUE: update.sh ddev-handover and `--refresh` loops consume projects.conf with no form gate at all | pre-existing (already recorded by the resolution as follow-up) |
| Q1 | LOW | `_unarm_show` filter misses four asserted line families; its comment overstates "skips" coverage | fix-induced |
| Q2 | LOW | `_un_revert_failed` is write-only in the config-dirs section (dead code, latent trap) | fix-induced |
| Q3 | INFO | Openchamber DRY echo for `rmdir` silently changed wording vs what `run` used to print | fix-induced — **RETRACTED (ghost, see below)** |
| Q4 | INFO | `un_revert_q` name under-describes its new config-dir rm role | fix-induced |

Provenance split: 5 fix-induced + 1 fix-induced ghost (Q3, retracted in
verification — the old and new DRY echoes are byte-identical), 2
pre-existing (X1, X2). No HIGH/MED.

---

## Axis S (mechanical sweep), verbatim

# Mechanical sweep — fix wave `0410036..a31e62b` (case pr-00243, snapshot a)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | `SCREEN_PATTERNS` filter excludes the new dot-form pattern line only incidentally — the filter is shape-keyed to `/*)`; a `/`-leading reorder of the parity-locked pattern line silently pulls dot-form patterns into the screening case | fix-induced |
| S2 | LOW | Pin gap: the config-dirs section reset (`_un_partial`/`_un_revert_failed` at uninstall.sh:672–673) is unpinned — deleting it leaves the suite green (sabotage-proven); loop→cfg cause leakage would go undetected | fix-induced |

No HIGH/MED findings.

## Detail

### S1 — LOW — extraction filter excludes the dot-form line by accident, not by design (fix-induced)

Evidence — `tests/unit/test-uninstall.sh:200-202`:

```sh
SCREEN_PATTERNS="$(sed -n '/case "\$root" in/,/^        esac/p' "$UNINSTALL" \
    | grep -E '^[[:space:]]*/' | grep -vE '^[[:space:]]*/\*\)' \
```

and the two new pattern lines this wave added (`uninstall.sh:572`, `uninstall.sh:577`):

```sh
            /*) ;;
            *..*|/./|*/./*|./*|*/.|//*)
```

I ran the exact extraction pipeline against the shipped script: it yields exactly the three blocklist lines (`/|/etc|…|/run|/run/*|/root|/root/*`) — correct today. But the two new lines are excluded by *different mechanisms*: the `/*)` line by the new `grep -vE` filter, the dot-form line only because it happens to start with `*` and so never matches the keep-grep `^[[:space:]]*/`. If the dot-form line is ever reordered to lead with a `/`-pattern (realistic: this exact line was rewritten in 0.0.45c S1, and the writer/reader pair is parity-locked by the X2 design — a config.sh reorder gets copied here), the keep-grep silently includes it in `SCREEN_PATTERNS` and the `/*)` filter does not remove it. Today's effect is nil — no screening representative matches the dot set (checked all 16) — so this is a silent latent weakening of the extraction, not a wrong assertion. The class-3 hazard is that the filter's correctness depends on line *shape*, not on which block a line belongs to.

### S2 — LOW — section reset between the two `_un_partial` reuses is unpinned; deletion is invisible to the suite (fix-induced pin gap)

Evidence — `uninstall.sh:672-673`:

```sh
_un_partial=""
_un_revert_failed=0
```

The loop-side reset (uninstall.sh:598-599) *is* pinned — the two-roots arm (test `two-roots isolation arms`, #243 a S3) went red when I deleted it in a sandbox copy. The section-side reset is not: `_un_cfg_out` pre-initializes both variables to the same values before `eval "$CFG_SECTION"` (test-uninstall.sh, the cfg driver: `_un_partial=""` / `_un_revert_failed=0`), so when I deleted lines 672-673 in the sandbox copy, **the entire suite stayed green**. Realistic scenario: a future refactor drops the section reset as "redundant with the loop reset"; no pin fires; on a real run, a degraded project root leaves `_un_partial` set, and a fully successful config-dirs removal then prints `WARN: could not fully remove config dirs + runtime artifacts (find-chown failed: /path)` and suppresses `Removed.` — the exact cross-section leak (loop → cfg) this wave's two-section reuse of `_un_partial` created. Failure direction is false-degraded, never false-success, hence LOW. The shipped code is correct; the gap is that no pin guards it.

## Landing audit (all 11 verified as landed, mechanism + pin)

S1 ✓ (674/675/701 via `un_revert_q`, degraded closer 702-709, four cfg arms) · S2 ✓ (elif rc-observed rm 689-697, WARN+FAILED 695-697) · S3 ✓ (reset 598-599 in-loop; pin sabotage-proven) · X1 ✓ (line 655, asserts neither "reverted" nor "removed"; negatives pinned) · X2 ✓ (gate 571-586 before blocklist; pin sabotage-proven — without it `//etc` closes as full success) · Q1 ✓ (`<gid>` template at 635, pinned verbatim; docs sentence landed) · Q2 ✓ (docs surfaces match code wordings verbatim) · Q3 ✓ (stdout/stderr split; channel pin sabotage-proven) · Q4 ✓ (`_unarm_show` surfaces asserted line families — observed in live red-arm output) · Q5 ✓ (both dry pins sabotage-proven) · Q6 ✓ (comment arithmetic counted: call sites 608/638/639/641 = 4; invocations 1+4+1 = 6 with both gids known).

## Class sweep and coverage

- **Deferred sites untouched**: all `run sudo rm` sites (uninstall.sh:240, 259, 275, 290, 296, 307, 336-337, 397, 409, 419, 431, 434) are byte-identical to the pre-wave state; no diff hunk reaches them; no new unconditional success log was added next to any. The `run_q sudo` best-effort teardown sites (513-521) are unchanged, carry justification comments, and feed the rc-observed `userdel`.
- **No new rc-blind closer in any changed hunk**: every changed closer is rc-conditioned; the openchamber DRY-arm success log is the sanctioned dry convention (#211 b W1), and `run` → `un_revert_q` is byte-identical in dry output (`  [DRY] $*` in both, lines 166 and 196) — no unintentional behavior change found. The `rmdir` staying best-effort is documented and unclaimed by the success log.
- **Gate position**: all new arms sit before the summary gate (`exit 1` at test file end, ~1079-1084).
- **Extraction anchors**: CFG_SECTION (47 lines, closing `fi` inside) terminates at the first `^echo ""$`; I checked truncation at every plausible insertion point — each fails loud (canary grep at 578-579 or the all-ok arm), never silent. Covered-clean.
- **Leakage, both directions**: loop→cfg blocked by 672-673 (unpinned = S2); cfg→loop impossible by ordering; nothing after line 708 reads `_un_partial` (audit-log uses `_al_rc`).
- **Writer/reader parity**: dot-arm sets identical (config.sh:329 vs uninstall.sh:577), absolute-first order matches. The reader lacks the writer's whitespace arm (config.sh:334) — no bypass (blocklist still gates; ops quote `"$root"`); the X2 pins are form-enumerative (3 forms), not parity-enumerative, so writer/reader drift has no tripwire — recorded as a coverage note, not a finding (the code comment claims arm-order parity, which holds).
- **Stale wording**: no `PARTIALLY removed` stragglers outside the intentional config-dirs wording; no `Removed.` references in docs.
- **Deferred, not covered**: full-file reads of the big scripts (budget discipline); e2e suites; verification of the resolution's deferred-list *count* (11 vs the 12 `rm` lines + 1 `python3` line found — count bookkeeping is a review-artifact question, not a code question).

Checkpoint trail: `/tmp/opencode/pr-00243-b/checkpoints/s.md`. Sandbox probes ran only in `/tmp/opencode/pr-00243-b/probe` (pristine copy + 7 sabotage/restore cycles, baseline green); the repo tree was not modified.

---

## Axis X (security), verbatim

# Security review — pr-00243 fix wave `0410036..a31e62b` (axis: security)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| X1 | INFO | Reader-side blocklist is narrower than the writer's — `/var`, `/opt/*`, `/srv/*`, `/tmp/*`, `/home`, `/libexec/*` pass gate+blocklist and reach root-run revert ops from a hand-edited conf | pre-existing (unchanged by this wave) |
| X2 | INFO | Recorded follow-up verified TRUE: update.sh ddev-handover and `--refresh` loops consume projects.conf with no form gate at all | pre-existing (already recorded by the resolution as follow-up) |

No fix-induced or wave-introduced findings. The wave's own surfaces (form gate, rc-observing arms, DRY branch, state resets, test harness hermeticity) came back clean; claims verified below.

## Details

### X1 — INFO (pre-existing): reader blocklist ≠ writer blocklist

`files/opencode-permissions-kit-lib/management/uninstall.sh:584-587`:
```
        case "$root" in
            /|/etc|/etc/*|/boot|/boot/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|\
            /lib|/lib/*|/lib64|/lib64/*|/sys|/sys/*|/proc|/proc/*|/dev|/dev/*|\
            /run|/run/*|/root|/root/*)
```
vs writer `files/opencode-permissions-kit-lib/management/config.sh:340-343` (also refuses `/home`, `/media|/media/*`, `/mnt|/mnt/*`, `/opt|/opt/*`, `/srv|/srv/*`, `/tmp|/tmp/*`, `/var`, `/var/tmp*`, `/var/cache*`, `/var/lib*`, `/var/log*`, `/var/mail`, `/var/spool`, and `/lib*` which catches `/libexec`).

Empirical probe (verbatim arm logic, 27 forms): `/var`, `/opt/x`, `/srv/x`, `/tmp/x`, `/home`, `/libexec/x` all reach `REACHES-OPS` on the reader side while the writer rejects them. Why it matters: a hand-edited projects.conf line `/var` drives `sudo find /var ! -type l \( -uid … \) -exec chown …` + `setfacl -R -x` over all of `/var` (uninstall.sh:608-641). Conditions: requires a hand-edited conf — neither writer can store these forms — and the effect is a revert-chown/ACL-strip, not privilege gain; the `Reverting kit ownership in: …` echo makes it visible. **Unchanged by this wave**: the diff inserts only the two form-gate cases before this untouched blocklist; every form newly rejected by the gate was previously reachable, so the wave strictly shrinks the reachable set.

### X2 — INFO (pre-existing, verification of recorded follow-up): update.sh loops ungated

Both resolution statements verified TRUE against the code:

- `files/opencode-permissions-kit-lib/management/update.sh:1513-1519` (`--refresh` baseline loop): `while IFS= read -r root; do [ -z "$root" ] && continue; [ -d "$root" ] || continue; fs_baseline_root "$root" …` — no form gate, no blocklist.
- `files/opencode-permissions-kit-lib/management/update.sh:889-906` (ddev-handover loop): same shape — `[ -d "$root" ] || continue` then `ddev_handover_root "$root" …`.

A hand-edited `//etc` or `/var/.` entry feeds the recursive baseline/handover ops directly. Already recorded as a follow-up by the resolution — listed for traceability, not as a new demand.

## Verified security-critical claims (resolution claims checked, all TRUE)

- **a X2 gate mirror**: arm order and arm set are identical to the writer — absolute check first (uninstall.sh:571-577 ≡ config.sh:324-327), then the byte-identical dot/empty set `*..*|/./|*/./*|./*|*/.|*//*` (uninstall.sh:579 ≡ config.sh:335), blocklist last. Probed blind-spot list: `/`→blocklist, `//`/`//etc`/`/etc//`/`/./etc`/`/etc/./x`/`/etc/../lib`/`/var/.`/`/var/..`/`/var/./`/`x-home-with-..`→malformed, `..`/`.`/`./x`/`x/`/`x//`/`x/.`→non-absolute, `/etc/`→blocklist, empty→pre-gate `[ -z ]` skip. **No probed form reaches a root-run op over a system path.** Without the gate, `//etc` would pass the blocklist lexically (`/etc/*` needs the single-slash prefix) and `[ -d //etc ]` is true — the fix closes a real hole, and the test pin (`! grep -qF 'sudo find //etc'` against the stub log) has teeth.
- **Space-forms deliberately ungated**: TRUE and safe. `*[[:space:]]*` exists only writer-side; every `$root` use in the loop is quoted (`[ ! -d "$root" ]`:564, `sudo find "$root"`:608, `sudo setfacl … "$root"`:638-639, `sudo chmod g-s "$root"`:641) — no argv split, no second-path injection. Space paths cannot come from sanctioned writers (validator rejects; install.sh stores space-split).
- **Legit-root regression**: none. config.sh stores only `cd && pwd` canonical forms (no trailing slash, no `//`, dot forms rejected pre-store; `~` expanded from getent); install.sh stores validator-passed verbatim forms (trailing-slash forms pass the reader gate anyway — probed `/srv/proj/` reaches only the blocklist/no-match path, never a skip). `*..*` over-matches `my..proj` but the writer rejects the same form, so nothing sanctioned is ever stored in that shape — no fail-closed gap.
- **State leakage between sections**: clean. `_un_partial`/`_un_revert_failed` reset inside the per-root loop (598-599) and at config-dirs section start (672-673) before the first op; grep maps all sites (198-199, 611, 633, 652-658, 696, 702-708) — no read after 709, no stale-cause path in either direction. (`_un_revert_failed` is set but never read in the config-dirs section — harmless dead init, the closing branches only on `_un_partial`.)
- **Openchamber DRY branch**: executes nothing — two `[DRY]` echoes + the intended-outcome log (688-691); the guard probes (`sudo test -f`/`sudo grep -q`, 685-687) are pre-existing reads outside the branch. Failure path cannot fake success: the success log lives in the `elif sudo rm …` branch only (692-694); the else arm (695-698) appends the partial cause, WARNs on stderr, and logs FAILED — and the section closing then refuses `Removed.` (702-709).
- **Harness hermeticity**: the driver iterates `<extra-roots>` unquoted (`for _unlo_x in $_unlo_extra`) — glob chars in a future value would expand against the test CWD, but current arms (`//etc /var/. .`) are literal, and hermeticity holds for *any* value regardless: every privileged op in the extracted loop goes through the stubbed `sudo()` function and the loop body has no non-sudo side effect. Stub boundary matching `*"$WORK/fakeproj "*|*"$WORK/fakeproj"` is correct — `fakeproj2` matches neither arm (space/EOL required after `fakeproj`); the two-root isolation pin exercises exactly this. Stream split makes the WARN channel pinnable; `_unarm_show` surfaces asserted lines on red. Unit suite runs green on the work tree.

## Unintentional-behavior-change check

None found. DRY echo format `  [DRY] $*` identical to `run`/`run_q`; success-path terminal lines byte-identical to pre-wave; `rmdir` stays deliberately unobserved with `|| true` (only-when-empty policy, pre-existing); the only behavior deltas are the intended fail-loud ones (conditional `Removed.`, degraded wording, openchamber failure arm). No stale references to the dropped `kit ACL entries PARTIALLY removed` wording anywhere in files/, tests/, docs/; docs hunk claims match code (`<gid>` template at uninstall.sh:634-635, WARN on stderr at 657).

## Coverage

Covered: full fix diff, all hunks (uninstall.sh, docs, test harness); 27-form empirical gate probe vs writer arms (config.sh + install.sh:935-960 validator, identical form arms); legit-root regression via writer storage analysis; all `_un_partial`/`_un_revert_failed` sites grepped and mapped; openchamber DRY/rm arms and runner body (193-201); harness driver wiring, stub boundary patterns, SCREEN_PATTERNS extraction (filter correctly drops only the form gate's `/*)` arm from the now-three-block sed range); unit suite executed green; stale-wording grep; docs-vs-code claims.

Deferred / not verified: root-operand symlink dereference (`[ -d ]` + `chmod`/`setfacl` following a symlink whose *text* is clean, e.g. a writer-stored logical symlink path) — pre-existing, unchanged by the wave (the new gate arms are purely lexical and only shrink the accepted set, so no new exposure), and the dereference semantics of `find`/`setfacl`/`chmod` on the root operand were not probed empirically; newline-in-path is impossible by storage format (line-based `read -r`) and was not probed.

---

## Axis Q (quality), verbatim

# Quality review — fix wave a31e62b (pr-00243 snapshot a, 11 findings)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | LOW | `_unarm_show` filter misses four asserted line families; its comment overstates "skips" coverage | fix-induced |
| Q2 | LOW | `_un_revert_failed` is write-only in the config-dirs section (dead code, latent trap) | fix-induced |
| Q3 | INFO | Openchamber DRY echo for `rmdir` silently changed wording vs what `run` used to print | fix-induced |
| Q4 | INFO | `un_revert_q` name under-describes its new config-dir rm role | fix-induced |

## Details

### Q1 — LOW — `_unarm_show` filter misses asserted line families; comment overstates coverage

`tests/unit/test-uninstall.sh:492-495`:
```sh
    # Red-arm diagnostics (#243 a Q4): surface the ASSERTED line
    # families (log wording / WARN / skips) — the old tail -N showed
    # only the appended sudo-call log, never the lines an arm checks.
    printf '%s' "$1" | grep -E 'log:|WARN:|PARTIALLY|Skipping' | tail -4
```
The filter `log:|WARN:|PARTIALLY|Skipping` does not match several strings the arms actually assert:
- `Removed.` — asserted at :664 and :692 (`grep -qF 'Removed.'`). A red cfg all-ok arm whose failure is precisely a missing `Removed.` shows log lines but never the missing echo.
- `[DRY]` echoes — asserted at :575, :576, :701-702. A dry arm red because the `[DRY]` echoes vanished (e.g. a revert to silent execution) never shows them.
- sudo-log lines — asserted at :591 (`grep -qF "sudo chmod g-s $WORK/fakeproj2"`) and by the Q5 emptiness pin at :578 (`grep -q '^sudo '`); the `sudo ` family is absent from the filter.
- the lowercase skip echoes — asserted at :556 and :565-567 (`opencode user unknown — skipped (chown manually if files are locked)`, `opencode group id unknown — its ACL entries left in place (remove manually: setfacl -R -x g:<gid> ...)`). These match none of the four families (`Skipping` is case-sensitive and they say "skipped"/"unknown"); a red gid-unknown arm shows the PARTIALLY closing log but never the newly-pinned `<gid>` hint the arm checks (:556).

Why it matters: the whole point of Q4 was diagnostics that show what an arm checked; on red, the operator still has to re-run by hand for these families. The comment's "(log wording / WARN / skips)" claims skip coverage the filter does not deliver. Diagnostics-only — no pin is weakened. (Line numbers are from the shipped test at a31e62b.)

### Q2 — LOW — `_un_revert_failed` is write-only in the config-dirs section

`files/opencode-permissions-kit-lib/management/uninstall.sh:672-673` initializes it:
```sh
_un_partial=""
_un_revert_failed=0
```
`un_revert_q` sets it to 1 on rm failure, but the section's closing (:703-709) branches only on `_un_partial`:
```sh
    echo "WARN: could not fully remove config dirs + runtime artifacts ($_un_partial)" >&2
    log "config dirs + runtime artifacts PARTIALLY removed ($_un_partial)"
```
The openchamber failure branch (:694-698) also appends to `_un_partial` without setting `_un_revert_failed=1`. Today this is harmless — every cfg cause is a failure, so the unconditional WARN is correct, unlike the project loop where the `_un_revert_failed` gate keeps pure skips from WARNing. But the variable is initialized, mutated, and never read in this section: dead code now, and a trap later — anyone adding a project-loop-style `if [ "$_un_revert_failed" -eq 1 ]` gate to the cfg closing would silently swallow the openchamber cause's failure status. Why it matters: my axis names dead code, and this dead write-only state encodes a false symmetry with the loop section it was copied from.

### Q3 — INFO — Openchamber DRY `rmdir` echo wording drift

Old code (`run sudo rmdir /etc/openchamber 2>/dev/null || true`) printed in DRY mode, via `run`'s `echo "  [DRY] $*"` (uninstall.sh:167-168):
`  [DRY] sudo rmdir /etc/openchamber 2>/dev/null || true`
New hand-rolled DRY branch (:691) prints:
`  [DRY] sudo rmdir /etc/openchamber`
A dry-output-only cosmetic change in the intended direction (shows the semantic command); no pin or doc depends on the old wording, and the branch is obviously hand-authored, so this reads as deliberate. Recorded because it is an unintentional-looking output delta in a wave whose headline class is accidental behavior changes.

### Q4 — INFO — `un_revert_q` naming vs its config-dir rm role

uninstall.sh:186-193: the runner is introduced as the "rc-observing runner for the per-root revert loop (#218) and the config-dirs removal" and is now called for `rm /run/opencode-permissions-kit`, `rm 99-ddev-rootless.conf`, `rm /etc/opencode-permissions-kit` (:674-675, :701) — operations with nothing to do with "revert". The comment compensates by naming both uses, so behavior claims stay accurate; renaming would churn call sites and the extraction pins (`sed -n '/^un_revert_q() {/,/^}$/p'`, test :258). Naming drift only; a generic name (`un_rc_q`-family) would describe it better.

## Verified clean (no finding)

- **Docs claims (blind-spot line) — every clause checked against behavior**: WARN naming the failed op fires on real failures (:657, cause list names e.g. `find-chown failed`); the audit log records `project revert PARTIALLY completed (...)` (:655) and **never plain success on the pure-skip path too** — unknown uid/gid populate `_un_partial` (:611, :633) with `_un_revert_failed` staying 0, so no WARN fires (docs claim a WARN only for failed operations — accurate) while the log still degrades; unknown gids reported "as a partial cause" ✓; the `setfacl -R -x g:<gid> -d -x g:<gid>` line with `<gid>` placeholder prints at skip time (:634-635) ✓; docs are silent on dry runs, where ops cannot fail, so no clause breaks there. `../reference/audit-log.md` exists.
- **Section markers**: both drivers emit `--- stdout ---`, `--- stderr ---`, `--- sudo log ---` unconditionally, in that order, exact spelling matching every sed range used (:509-510, :578, :679). No content line can equal a marker. Clean.
- **Runner comment**: "four call sites, six invocations when both gids are known" — exact (find-chown ×1, setfacl −x/−d−x ×2 pairs = 4, chmod ×1). "Same [DRY] echo and same silence as run_q" verified against both bodies (:167-202).
- **Closing-log comment** "never asserts the clause that failed": the degraded line (:655) asserts neither clause ✓.
- **SCREEN_PATTERNS**: the `grep -vE '^[[:space:]]*/\*\)'` filter (:201) removes exactly the form-gate `/*)` arm; the dots-gate pattern line (`*..*|/./|*/./*|./*|*/.|//*)`) starts with `*` and never enters the leading-`/` grep. The malformed-roots arm drives the **shipped** gate — `PROJECT_LOOP` is sed-extracted from `$UNINSTALL` (:252), gate included.
- **Stub boundary matching (resolution claim)**: empirically probed with the shipped op argument shapes — with `find` in the fail list, `find …/fakeproj` fails, `find …/fakeproj2` passes, and setfacl/chmod on fakeproj2 pass (quoted-literal boundary patterns can't match `fakeproj2` either way).
- **X1 wording sweep**: no stale reference to `kit ACL entries PARTIALLY removed` anywhere in files/ tests/ docs/; the surviving `config dirs + runtime artifacts PARTIALLY removed` (:708) is a different subject and matches its own new pin.
- **Q5 dry emptiness pin**: valid as placed — the loop dry arm has no guard probes, so the sudo log must be empty; the cfg dry arm correctly omits the pin and its comment ("guard probes legitimately execute as reads") is accurate.
- **Driver log-claim**: real `log()` is file-only (sh/log.sh:68-74) — the stub-echoes-argument justification is correct.
- Gate arm semantics (`//etc` bypasses the blocklist lexically, `/var/.` hits `*\.`, `.` hits the non-absolute arm) and the writer-order claim ("absolute first, then dots") match `project_path_sane` (management/config.sh:311-326). No `set -e` hazard from the new gates.

## Coverage

Covered: full diff of all three files; every blind-spot line (docs clauses incl. pure-skip and dry paths; `_unarm_show` families; marker order/spelling vs all sed ranges; rewritten comments quoted-vs-behavior; resolution claims — stub boundary probed live, SCREEN_PATTERNS behavioral pinning confirmed); dead-code/naming/drift sweep over the diff; grep sweeps for stale wording. Deferred: `make lint`/suite execution (reviewer is read-only; pins were verified by reading and targeted probes, not by running the suite); the rest of test-uninstall.sh outside the diff hunks (only surrounding context of each hunk read, per budget discipline).

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| S1 | **confirmed** | Ran the exact extraction pipeline (test:200-203) against the shipped script myself: output is exactly the blocklist arms, nothing else. The dot-form line (`*..*|/./|*/./*|./*|*/.|//*)`, uninstall.sh:579) starts with `*` and never enters the keep-grep `^[[:space:]]*/`; only the `/*)` line (uninstall.sh:572) is removed by the new `grep -vE '^[[:space:]]*/\*\)'` filter. The exclusion of the dot line is positional, not by identity — the latent reorder hazard is real as reported. No today-effect: the 16 screening representatives were enumerated by the reviewer; the suite is green. |
| S2 | **confirmed** | Reset at uninstall.sh:672-673 measured; the cfg driver `_un_cfg_out` (test:632-660) sets `_un_partial=""` and `_un_revert_failed=0` inside its subshell before `eval "$CFG_SECTION"` — the shipped reset is masked in every cfg arm by construction, so deleting it cannot redden the suite (the reviewer additionally proved it by sabotage in a scratch copy, tree untouched). Leak shape verified: the project loop's `_un_partial` would survive into the section closing (702-709) and falsely degrade a clean removal. |
| X1 | **confirmed** | Reader blocklist measured (uninstall.sh:586-591): `/var`, `/home`, `/opt`, `/srv`, `/tmp`, `/libexec` (and their subtrees) absent; writer blocklist (config.sh:338-345) refuses all of them (`/home`, `/lib*`, `/opt|/opt/*`, `/srv|/srv/*`, `/tmp|/tmp/*`, `/var` + `/var/*` family). Preconditions as reported: root-only hand-edit; impact is revert-chown/ACL-strip, visible echo, no privilege gain. Blocklist untouched by the diff — pre-existing backlog. |
| X2 | **confirmed** | update.sh:1513-1519 (`--refresh` baseline, `fs_baseline_root`) and :889-906 (ddev-handover, `ddev_handover_root`) measured: `[ -z ]`/`[ -d ]` gates only, no form gate, no blocklist. Resolution Follow-ups entry 1 verified TRUE — no new demand. |
| Q1 | **confirmed** | `_unarm_show` filter (test:491-495) is `log:|WARN:|PARTIALLY|Skipping`; asserted strings outside those families measured: `Removed.` (test:664, :692, :703), `[DRY] sudo …` (:574, :701-702), `sudo chmod g-s $WORK/fakeproj2` (:593), `remove manually: setfacl -R -x g:<gid> …` (:546) plus the lowercase skip echoes. None can appear in a red arm's fail echo. Diagnostics-only; no pin weakened. |
| Q2 | **confirmed** | `un_revert_q` sets `_un_revert_failed=1` (uninstall.sh:197); the cfg closing (702-709) branches only on `_un_partial`; the openchamber else arm (695-698) appends a cause without the flag; grep over the post-section script shows no reader (audit-log section uses `_al_rc`). Cross-confirmed independently by the X axis ("harmless dead init" note). |
| Q3 | **retracted — ghost** | The premise is false. Old line (0410036:655): `run sudo rmdir /etc/openchamber 2>/dev/null || true`; old `run()` (0410036:164-170) DRY-echoes `"  [DRY] $*"`. In that command, `2>/dev/null` is a redirection applied to the `run` invocation and `|| true` is a list separator — neither is in `$*`. The old DRY output was `  [DRY] sudo rmdir /etc/openchamber`, byte-identical to the new echo (uninstall.sh:691). No wording drift exists; the old test pinned only static presence (`grep -q 'rmdir /etc/openchamber'`, 0410036:580). |
| Q4 | **confirmed (suggestion-class)** | Accurate as an observation: the runner (uninstall.sh:186-201) is called for rm ops (:674, :675, :701) and its comment names both uses. No house rule governs the naming (agent/conventions.md has none) — per the axis contract this is a suggestion, not a rule violation; kept as INFO for the disposition to decide. |

## Retracted/ghost findings

- **Q3 (INFO, openchamber DRY rmdir echo wording drift) — RETRACTED**: ghost.
  The reviewer's claimed old output (`  [DRY] sudo rmdir /etc/openchamber
  2>/dev/null || true`) misreads shell parsing of the old line — the
  redirection and `|| true` were never part of `run`'s arguments, so old
  and new DRY echoes are byte-identical (evidence in the verification
  table). No behavior delta, no pin dependency, no finding.

## Run provenance

- Commission: maintainer, 2026-10-24 ("@opk-review-pass Wave/Micro-Überprüfung
  dieses Fix-Diffs (Snapshot b)"). Second snapshot of the case; rotation
  normal (this session did not author the a-wave's fixes).
- Tree: 5d2e3cf (feature/218-uninstall-revert-log-honesty), clean at
  fan-out (`git status --porcelain` empty) and re-verified clean after all
  reviewers returned. Shipped content at HEAD is identical to the reviewed
  fix commit a31e62b — the intervening commit 5d2e3cf touched
  resolution.md only.
- Material: fix diff 0410036..a31e62b, shipped files only
  (`git diff 0410036..a31e62b -- files/ tests/ docs/`): 3 files,
  292 insertions / 57 deletions (uninstall.sh 94, test-uninstall.sh 245,
  docs/how-to/uninstall.md 10). Review artifacts riding the same commit
  (resolution.md, review-a pointer line, INDEX row) are bookkeeping, not
  review material. Scope ran at wave parameters (diff well above the
  ~50-line micro bound): ~8-minute budgets, 3 axes.
- Host timestamps (main session, UTC): fan-out start
  2026-10-24T17:29:19Z, end 2026-10-24T17:42:50Z.
- Reviewer subagents: 3 (cap 5 respected), fast tier
  zai-coding-plan/glm-5.3-flash, fresh contexts, axis prompts built from
  `.agents/skills/opk-review-pass/axis-prompt.md`; the main session
  (GLM-5.3) owned verification and embedded the reports.
- Checkpoints: `/tmp/opencode/pr-00243-b/checkpoints/{s,x,q}.md` (outside
  the reviewed tree). s.md and q.md carry launch + return lines; q.md has
  one literal unexpanded `$(date …)` in a mid-run line (launch/return
  intact); s.md's sandbox stamps run up to ~31 min past the host window
  end (sandbox clock skew — host window authoritative); x.md has 4 lines
  (launch + 3 section stamps, last 17:37:58Z carrying the findings
  summary) but no explicit return line — the report itself arrived
  complete; noted, not re-run.
- Sabotage/mutation windows: none on the repo tree. The S reviewer ran
  its probe/sabotage cycles on a pristine copy under
  `/tmp/opencode/pr-00243-b/probe` (outside the tree, all reviewers
  read-only on the repo); `git status --porcelain` empty at return
  confirms no reader wrote.
- Gates at snapshot time (main session, this tree, before the snapshot
  commit): `sh tests/unit/test-uninstall.sh` green; `make lint` green;
  `sh tests/unit/test-docs.sh` green; `sh tests/unit/test-line-length.sh`
  green (review-* snapshots exempt from the ratchet — verbatim over
  wrap); INDEX regenerated with this commit
  (`python3 scripts/gen-review-index.py`); `sh tests/unit/test-reviews-lint.sh`
  and `sh tests/unit/test-reviews-parity.sh` run green before the commit
  carrying this file.
- e2e: no new debt — the reviewed fix wave already ran both suites
  in-wave (resolution Gates: `make e2e` 309, `make e2e-rootless` 47);
  this snapshot changes no shipped code.

## Recommendation

The a-wave's fixes all landed and drive real behavior (landing audit +
the resolution's four red-for-the-right-reason sabotage spot-checks).
The b findings are edges of the fix wave itself, none above LOW:

- **S2 and Q1/Q2** are pin/diagnostic hardening inside this round's own
  constructs (test code + one write-only variable) — the natural next
  fix round; implementing any of them touches test code (S2/Q1) or
  production code (Q2), which owes snapshot c under RM-0067.
- **S1** is the same class (extraction-filter hardening in test code).
- **X1** joins the resolution's follow-up list — reader/writer
  blocklist parity belongs with Follow-up 1's parity decision (its own
  wave, both e2e suites: root-run semantics).
- **X2** verifies Follow-up 1 TRUE; no new action.
- **Q4** is naming-only (suggestion-class) — a deliberate not-done is a
  legitimate disposition.
- **Q3** is retracted (ghost).

Per the stop rule (RM-0064/RM-0067): a next round that implements the
LOW findings touches review-relevant code and owes one more wave review;
a round that dispositions all of them deliberately-not-done would leave
review-relevant code untouched. The loop's state is the maintainer's
call — this session records, it does not close.
