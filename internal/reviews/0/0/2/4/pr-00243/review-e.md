<!-- review-meta
ID: pr-00243
Snapshot: e
Subject: micro-wave review of the d-wave's fix wave — comparator drop to stripped-only, scope comment, isolation/wiring/existence pins
Scope: wave
Base: 0.0.56 @ 5993cac
Diff: 5993cac..24a0274
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 2 fresh-context reviewer subagents (axes S/X, fast tier GLM-5.3-Flash)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review e — micro-wave review of the d-wave's fix wave (pr-00243)

Round e over the diff 5993cac..24a0274 (2 commits: 09206ab "fix(uninstall):
agent-home pin both spellings, isolated family pin, existence-filter +
wiring pins, anchored negatives (#243 d X2 S1 S2 X4 Q1 Q2 Q3 Q4 Q5)" —
the fix wave; 24a0274 touches resolution.md only, bookkeeping). Shipped
material: uninstall.sh (16 changed lines: the agent-home comparator
dropped to the once-stripped form only (d Q1) with its comment scoped,
plus the d X1 parity-scope paragraph on the blocklist comment) and
test-uninstall.sh (123: wiring pin for SCREEN_PATTERNS, screen() strip
mirror with `/etc/` `/var/` static forms, two isolating family-pin
fixture lines, `_un_exist_roots` helper + host-independent pin, anchored
ts find negatives, setfacl/chmod op negatives, agent-home arm feeding
both spellings). All 9 implemented d-findings were audited as LANDED by
the S axis (mechanism + pin each) and spot-confirmed in verification;
this snapshot's findings are one conditional non-equivalence of the
comparator drop (X1 — the raw arm was load-bearing under a corrupted
install.conf value), the resolution's overstated d Q1 precondition
justification and two overstated sweep/inventory sentences (X2, S1, S4),
and latent/edge notes on the new pins (S2, S3, S5, X3).

## Findings index (combined)

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | LOW | resolution d Q3 claims "find/chmod negatives for `/var/.` **and `.`**" — the `.` chmod negative did not land | delta-introduced (bookkeeping text) |
| S2 | INFO | d X2's raw-spelling skip-echo assertion is prefix-subsumed by the trailing-slash assertion — it cannot red on a raw-echo-only omission | wave-introduced |
| S3 | INFO | d X4's static `/etc/` form is non-discriminating: `/etc/` matches the `/etc/*` sibling arm with or without screen()'s strip | wave-introduced |
| S4 | INFO | resolution d Q4 sweep's invariant "no fed operand is a string-prefix of another" is false for the agent-home arm (raw IS a prefix of trailing) | delta-introduced (bookkeeping text) |
| S5 | INFO | ts-loop setfacl/chmod negatives are unanchored and overlap the same-arm-fed `/var//` operand — red-direction only, misattribution risk | wave-introduced |
| X1 | MED (conditional) | Dropping the raw agent-home compare is NOT equivalent under a hand-edited install.conf carrying a trailing-slash `OPENCODE_USER` — the dropped raw arm was load-bearing there; new code runs root-run revert ops over the agent home where the old skipped it | fix-induced |
| X2 | LOW | resolution.md d Q1's equivalence-precondition justification cites two mechanisms (`:-` default at :211, `id -u` lookups at :225) that do not enforce slash-freeness; the actual guarantee (writer-side charset gate) is uncited | fix-wave bookkeeping |
| X3 | INFO (latent) | `screen()` helper has no dot gate — for `//` forms it disagrees with the shipped loop (`screen /var//` → "allowed" vs loop dot-gate-skip); no current assertion feeds a `//` form, so nothing fires today | fix-induced (provenance corrected to pre-existing residual in verification) |

Provenance split: 5 wave-introduced/fix-induced on the wave's own
constructs (S2, S3, S5, X1, X3-as-reported) + 3 bookkeeping-text
findings against the d-wave's resolution (S1, S4, X2). As reported:
1 MED, 2 LOW, 5 INFO; verification confirms every severity as reported
(no adjustments) and corrects one provenance (X3: the `//` disagreement
predates the wave — see verification table).

---

## Axis S (mechanical sweep), verbatim

# Mechanical sweep — diff `5993cac..24a0274`, pr-00243 fix wave 4

Working tree verified byte-identical to `24a0274` for both shipped files (empty `git diff 24a0274 --` on them), so line cites are working-tree lines. `unsh` = `files/opencode-permissions-kit-lib/management/uninstall.sh`, `test` = `tests/unit/test-uninstall.sh`, `res` = `internal/reviews/0/0/2/4/pr-00243/resolution.md`.

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | LOW | res d Q3 row claims "find/chmod negatives for `/var/.` **and `.`**" — the `.` chmod negative did not land | delta-introduced (bookkeeping text) |
| S2 | INFO | d X2's raw-spelling skip-echo assertion is prefix-subsumed by the trailing-slash assertion — it cannot red on a raw-echo-only omission | wave-introduced |
| S3 | INFO | d X4's static `/etc/` form is non-discriminating: `/etc/` matches the `/etc/*` sibling arm with or without screen()'s strip | wave-introduced |
| S4 | INFO | res d Q4 sweep's invariant "no fed operand is a string-prefix of another" is false for the agent-home arm (raw IS a prefix of trailing) | delta-introduced (bookkeeping text) |
| S5 | INFO | ts-loop setfacl/chmod negatives are unanchored and overlap the same-arm-fed `/var//` operand — red-direction only, misattribution risk | wave-introduced |

No HIGH/MED. Held findings d S3/X3/Q6 untouched: full-range `diff --stat 5993cac..24a0274` lists only unsh, test, res; the three-ops comment (unsh:632-636) survives as unchanged context; no writer-side (config.sh) edits.

## Finding details

**S1 (LOW) — res claims a `.` chmod negative that does not exist.**
res:466-472 (d Q3 detail): "malformed-roots and agent-home arms (BOTH `-x` and `-d -x` spellings, plus find/chmod negatives for `/var/.` and `.` in the malformed arm that previously had none)". Landed negatives in the malformed arm (test:750-761): `sudo find //etc` (:754), both setfacl spellings for `//etc` (:755-756), `sudo chmod g-s //etc` (:757), `sudo find /var/.` (:758), `sudo chmod g-s /var/.` (:759), `sudo find . !` (:760). There is no `sudo chmod g-s .` and no setfacl negative for `/var/.` or `.` — the "BOTH spellings" scope is `//etc`-only. Why it matters: the audit record overstates the landed pin set; operationally the gap is minor — a malformed-gate regression that drops `.` still reds via :760, and an op-verb-specific dodge (chmod running before the gate for `.` only) has no realistic single-line revert shape. Conditions: matters only if the resolution text is later used as the pin inventory.

**S2 (INFO) — raw echo assertion subsumed.**
test:859 greps `-qF 'Skipping agent home (never a project root): /home/untest-agent'`, which is a strict prefix of the trailing-slash echo line asserted at :860 (`...: /home/untest-agent/`). So :859 stays green whenever :860's line is present; a regression that suppressed the echo for the raw spelling only would keep the arm green (the op negatives :861-864 don't assert the echo). No realistic trigger in the shipped code: the echo is one shared statement (unsh:580) printing the raw `$root` for both spellings, and printing the normalized form reds via :860 — producing the dodging shape requires conditionalizing the echo by slash presence. Flagged because d X2's claim is "asserts **each** skip echo verbatim" (res:393-394) and the raw half of that is not independently pinned.

**S3 (INFO) — `/etc/` static form cannot red on strip deletion.**
test:289 feeds `/etc/` and `/var/` to screen(). The wired blocklist (unsh:638) contains `/etc|/etc/*` — in shell case, `*` matches empty, so `/etc/` matches `/etc/*` even if screen()'s strip (test:281-282) is deleted. `/var/` is the only discriminating form: the blocklist has no bare `/var/*` arm (unsh:641: `/var|/var/cache|/var/cache/*|...`), so strip deletion reds via `screening rejects /var/` — consistent with res spot-check 5, which used exactly that form. `/etc/` is belt-only redundancy; no coverage hole (strip-deletion is caught).

**S4 (INFO) — res d Q4 sweep invariant false as written.**
res:481-486: the remaining unanchored find negatives "(`//etc`, `/var/.`, `/home/untest-agent`) are prefix-unique among their arms' fed operands (no fed operand is a string-prefix of another)". The agent-home arm feeds `/home/untest-agent /home/untest-agent/` (test:858) — a strict prefix pair. The conclusion still holds because over-match there is the desired coverage (both spellings must be refused); the stated invariant is what's wrong. Verified prefix-unique at line level for the other two: `sudo find . !` (:760) does not substring-match `sudo find /var/. !` (the `.` follows `/var/`, not "find ").

**S5 (INFO) — unanchored ts-loop negatives overlap `/var//`.**
test:832-833 (`sudo setfacl -R -x g:60002 ${_un_ts%/}`, `sudo chmod g-s ${_un_ts%/}` for `_un_ts=/var/`) also substring-match op lines for `/var//`, which is fed in the same FOUT (test:826) and has its own negatives at :840-841. If the dot gate regressed and ops ran on `/var//`, the loop negative for `/var` would also fire — no false red is possible (ops on `/var//` must red anyway), but the arm's failure message would blame the trailing-slash spelling instead of the dot gate. The d Q4 ` !` anchoring treatment was applied to the find negatives only (:830-831, correctly anchored — `sudo find /var// !` does not contain `sudo find /var !`).

## Section 1 — Landing audit (9/9 implemented as claimed)

| d-finding | Mechanism (cite) | Pin that reds on deletion (cite) |
|---|---|---|
| X2 agent-home both spellings | unsh:579-581 (stripped compare, echo prints raw `$root`); test:858 feeds `/home/untest-agent /home/untest-agent/` | test:859-864 — comparator reverted to raw-only → trailing root falls to the silent `[ ! -d ]` skip (unsh:583) → :860 reds, host-independent (lexical, before `-d`) |
| S1 isolating fixture lines | test:635-636 | test:637-641 identity compare vs regex :617; all 9 alternatives singly matched — `log:`→:627, `WARN:`→:628, `PARTIALLY`→:635, `Removed\.`→:630, `\[DRY\]`→:631, `Skipping`→:632, `skipped`→:636, `unknown`→:633, `^sudo `→:634 (line :631 is indented, so it does not cover `^sudo `) |
| S2 `_un_exist_roots` | test:773-779 | test:780-784 — `$WORK` + `/opk-243d-nonexistent-root` identity; filter deleted or neutralized → mismatch → red, host-independent |
| X4 screen() mirrors strip | test:281-282 (`${1%/}`, empty→`/`) mirroring unsh:615-617 | test:289 static list — `/var/` reds on strip deletion (see S3 for the `/etc/` caveat); `/` static form pins the restore |
| Q1 single stripped compare | unsh:579 — dead raw arm gone, comment :573-578 scoped | equivalence pinned by the X2 arm: strip dropped → trailing root unrefused → :860 reds; whole compare dropped → :859/:860 + :861-864 red |
| Q2 env-pin comment | test:396-399 — names OPENCODE_USER, UN_DEV_GROUP, DEFAULT_USER (pins at :417-419, :423) | n/a — comment-only deliverable, no pin claimed (d S3 precedent) |
| Q3 setfacl negatives | op lines to negate exist: unsh:693-694 (both spellings), :696 (chmod) | test:755-756 (`//etc`, both spellings), :801 (sysroots, `-x`), :832+:840 (ts, `-x`), :862-863 (agent-home, both) — scope caveats in S1/S5 |
| Q4 anchored find negatives | unsh:663 op line carries literal ` ! -type l` continuation (sudo stub logs `sudo find <root> ! ...`) | test:830 (`sudo find ${_un_ts%/} !`), :831 (raw leak `${_un_ts%/}/ !`), :837, :839; old unanchored `sudo find $_un_ts` removed |
| Q5 wiring pin | test:225 (wiring); legit tokens dot/`//`-free verified against unsh:638-642 | test:264-271 — `case "$SCREEN_PATTERNS" in *.*|*//*)` |

## Sections 2–4 results

**(2a)** The only feed-side `[ -d ]` probe is the helper's (test:776); other `[ -d ]` hits (:421, :505, :513, :516, :524, :854) are comments and the W2 source-grep pin. Clean.
**(2b)** All remaining unanchored op negatives are prefix-unique at line level among their arms' fed operands, except: the intended agent-home raw/trailing pair (S4) and the ts-loop setfacl/chmod overlap (S5).
**(2c)** `grep -rn '] || \[ "\${[a-z_]*%/}" =' files/` → no matches (rc=1). No sibling dual-compare subsumption sites remain.
**(2d)** No arm feeds only the raw agent-home form (single call site, test:858, both spellings); every op-negation arm carries at least the `-R -x` setfacl negative — the `-d -x` spelling appears only in the agent-home and `//etc` negatives, consistent with res:468-469's own scoping.
**(3a)** Both new fixture lines match exactly one alternative each and are case-safe (`grep -E`, no `-i`, :617): `revert PARTIALLY completed (chmod g-s failed)` matches only `PARTIALLY`; `  skipped reverting ownership (not kit-owned)` matches only `skipped` (leading spaces defeat `^sudo `). Neither covers any other alternative's deletion.
**(3b)** Wiring pin (:264-271) and helper pin (:780-784) both sit before the summary gate (`failures` gate, test:1345-1348); `fail()` increments `failures` (:25).
**(3c)** The named shape is real but not a green hole: an EMPTY wired `SCREEN_PATTERNS` matches neither `*.*` nor `*//*` so the wiring pin stays green — but the pre-existing extractability pin reds (test:226-231 `[ -n "$SCREEN_PATTERNS" ]`), and absent that pin the first `screen()` eval would abort dash outright (empty-case syntax error; verified: `sh -c` exits rc=2, nothing after runs).
**(4)** No new `|| true` (the four `FOUT=$(...) || true` lines pre-existed in the diff context), no new stderr redirects, no new probe pipes. `_un_scr` (:281-283) used only inside `screen()`; `_un_er`/`_un_er_out` (:774-778) used only inside the helper, which is only invoked in command substitutions (:780, :795, :825) — no collisions, no use-after-consumer, no global leakage. Word-splitting: outputs are space-joined and consumed via the driver's documented space-free convention (:392-394); current inputs are literals plus `$WORK` = `mktemp -d` (:27) — no space-carrying operand can reach them today; the helper does not itself reject spaces (future-caller caveat only, no realistic trigger).

## Section 5 — Suite

`sh tests/unit/test-uninstall.sh` → final line: **`All uninstall tests passed.`** (green).

## Coverage

Covered: landing audit 9/9 with mechanism+pin cites; all four sibling sweeps; pin-discrimination checks 3a/3b/3c (including the dash abort experiment); fail-open/hygiene sweep over exactly the diff hunks; held-finding non-resurrection via full-range stat; suite run. Deferred: re-executing the resolution's six sabotage spot-checks (read-only mandate — red-conditions verified by code reading; res records them executed in a scratch worktree on `09206ab`); e2e suites (not micro-scope; res:617-622 records both green). Unverified: none — every suspicion raised was resolved within one follow-up read.

---

## Axis X (security), verbatim

# Review e — security axis, diff `5993cac..24a0274` (fix wave 4, case pr-00243)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| X1 | MED (conditional) | Dropping the raw agent-home compare is NOT equivalent under a hand-edited install.conf carrying a trailing-slash `OPENCODE_USER` — the dropped raw arm was load-bearing there; new code runs root-run revert ops over the agent home where the old skipped it | fix-induced |
| X2 | LOW | resolution.md d Q1's equivalence-precondition justification cites two mechanisms (`:-` default at :211, `id -u` lookups at :225) that do not enforce slash-freeness; the actual guarantee (writer-side charset gate) is uncited | fix-wave bookkeeping |
| X3 | INFO (latent) | `screen()` helper has no dot gate — for `//` forms it disagrees with the shipped loop (`screen /var//` → "allowed" vs loop dot-gate-skip); no current assertion feeds a `//` form, so nothing fires today | fix-induced (latent) |

## Detail

### X1 — MED (conditional): comparator drop non-equivalent under trailing-slash `OPENCODE_USER`

**Trigger condition:** a hand-edited `/etc/opencode-permissions-kit/install.conf` containing `OPENCODE_USER=opencode/`. The writer can never produce this value, but nothing on the reader side prevents it (see trace below).

**Value trace** (all in `files/opencode-permissions-kit-lib/management/uninstall.sh`):
- `:88` — `OPENCODE_USER="opencode"` — literal; environment cannot survive it.
- `:207-212` — `. "$INSTALL_CONF"` sources `/etc/opencode-permissions-kit/install.conf` if present, **with no shape/charset validation of the sourced value** (unlike the writer, which gates `DEFAULT_USER` against `*[!A-Za-z0-9_.-]*` at `install.sh:587-592`; `install.sh:349` sets `OPENCODE_USER="opencode"` literal and the conf heredoc at `install.sh:1339` stamps that literal — writer-produced conf can never carry a trailing slash).
- `:211` — `OPENCODE_USER="${OPENCODE_USER:-opencode}"` — defaults on **empty/unset only**; a trailing-slash value passes through untouched.
- `:214`, `:225-226` — `id -gn`/`id -u`/`id -g` lookups each end in `|| true`; with `opencode/` they fail rc≠0 and yield empty — execution reaches the loop regardless.
- `:579` — the changed compare consumes the value.

**Delta (empirically confirmed by probe, `/tmp/opencode/pr-00243-e/probe-x/`):** with `OPENCODE_USER=opencode/`:

| conf root | OLD (`5993cac` dual compare) | NEW (`:579` single compare) |
|---|---|---|
| `/home/opencode/` | SKIP (raw arm `[ "$root" = "/home/$OPENCODE_USER" ]` matched) | **ROOT-RUN OPS** — strip gives `/home/opencode` ≠ `/home/opencode/`; blocklist has no `/home/*` arm; falls to `[ -d ]` :583 |
| `/home/opencode//` | SKIP (stripped arm) | SKIP (single compare matches stripped form) |
| `/home/opencode` (bare) | ROOT-RUN OPS | ROOT-RUN OPS (pre-existing gap under the corrupted conf, **not a delta**) |

Concrete new damage for the `/home/opencode/` root: `UN_OC_UID`/`UN_OC_GID` are empty (failed id lookups), so the chown branch is skipped loudly (`:661` guard), and the opencode setfacl pair is skipped (`:686-691`) — but the **dev-group pair and chmod still run**: `sudo setfacl -R -x g:<devgid> "/home/opencode/"`, `sudo setfacl -R -d -x g:<devgid> …` (`:692-693`), `sudo chmod g-s "/home/opencode/"` (`:695`) — recursive root-run operations over the agent's home. The old dual compare skipped that input entirely.

**Why it matters:** the d Q1 drop is safe against every value the kit can write, but the guard it weakened is precisely the one protecting the agent home from root-run ops, and its reader-side enforcement (a one-line case-pattern on the conf-sourced value) does not exist. Severity MED under the named trigger only; the corpus under a canonical value is byte-identical (see coverage).

### X2 — LOW: resolution d Q1's precondition justification is inaccurate

`internal/reviews/0/0/2/4/pr-00243/resolution.md:448-454`: "precondition: `OPENCODE_USER` never ends in `/`, it feeds `id -u` lookups at uninstall.sh:225 and is defaulted at :211". Neither cited mechanism enforces slash-freeness: the `:211` `${OPENCODE_USER:-opencode}` default replaces only empty/unset values, and the `:225` lookups are `|| true`-swallowed (`uninstall.sh:225-226`) so a garbage value degrades trace data without stopping the run. The load-bearing guarantee is the **writer-side** charset gate (`install.sh:587-592`) plus the literal `OPENCODE_USER` (`install.sh:349`), which the resolution does not cite. A future reader treating the precondition as reader-enforced would repeat the X1 mistake. Provenance: fix-wave bookkeeping (resolution text).

### X3 — INFO (latent): `screen()` strip disagrees with the loop on `//` forms

`tests/unit/test-uninstall.sh:280-285`: the helper applies only the strip (`_un_scr="${1%/}"`, empty→`/`) — it has **no dot gate**. `screen "/var//"` → strip → `/var/` → blocklist miss → returns 1 ("allowed"), while the shipped loop catches `/var//` at the dot gate (`uninstall.sh:597-603`) and skips it. No current assertion feeds a `//` form (fed sets at `:289`, `:301`, `:319` contain none), so nothing fires today; if a future *rejects*-style assertion feeds one, the helper returns "allowed" and the assertion reds loudly (safe direction). The silent direction would require a future *allows*-style assertion on a `//` form. Latent only; the comment (`:273-279`) claims strip parity, not dot-gate parity, so the code matches its stated scope.

## Coverage output

**Section 1 — precondition trace:** full chain above. Verdict: the resolution's d Q1 precondition holds for every writer-producible value (literal `install.sh:349` + charset gate `install.sh:587-592` + heredoc `install.sh:1339`) and fails only under hand-edited conf → X1/X2.

**Section 2 — slash-form corpus (classification, shipped gates extracted to `/tmp/opencode/pr-00243-e/probe-x/probe.sh`; `[ -d ]` stubbed to exists=true for tree comparability — that gate is unchanged in the diff):**

| input | classification |
|---|---|
| `/home/untest-agent` | agent-home skip (echo raw) |
| `/home/untest-agent/` | agent-home skip (echo raw) |
| `/home/untest-agent//` | dot gate |
| `/home/untest-agent/.` | dot gate |
| `/home//` | dot gate |
| `//home/x` | dot gate |
| `/var/` | blocklist (echo normalized `/var`) |
| `/var//` | dot gate |
| `/var/.` | dot gate |
| `/` | blocklist `/` arm |
| `relative` | non-absolute gate |
| `/var www` | held whitespace class: passes all lexical gates; on a real host `[ ! -d ]` (`:583`) skips it unless a literally space-named directory exists — exactly the recorded a X2 disposition |

**Corpus-classification result:** outputs byte-identical between `5993cac` and `24a0274` under a canonical `OPENCODE_USER` (probe-old.sh dual compare vs probe.sh, `diff` clean) — the dropped raw arm was logically dead for the entire corpus under the precondition. The whitespace-held class was neither narrowed nor widened (diff's only production change is the `:579` compare; surrounding gates untouched).

**Section 3 — wiring pin + helper:** (a) an EMPTY wired `SCREEN_PATTERNS` passes the wiring pin (`case … in *.*|*//*) … *) pass`) but the eval'd case becomes `… in ) return 0 ;; …` — a syntax error under both dash and bash (verified) → `screen()` returns rc2 for every input → the static reject loop (`:289-294`) reds. The suite cannot stay green with functionally-dead wiring; the catch is accidental (parse error), not designed — noted, no live hole. (b) strip disagreement only on `//` forms → X3; on the fed forms (`/`, `/etc/`, `/var/`) helper and loop agree exactly. (c) no other static assertion feeds a form the helper normalizes differently; the behavioral arms drive the real loop, not `screen()`.

**Section 4 — anchors + spellings:** (a) the real op line `uninstall.sh:664-665` is `un_rc_q "find-chown" sudo find "$root" ! -type l \( -uid … -o -gid … \) -exec chown …`; the driver's stubbed `sudo()` logs `sudo %s` with space-joined `$*` (`test-uninstall.sh:428-430`), so a leak spells `sudo find /var ! -type l ( …` — the ` !`-anchored negatives bind to a real leak, and the normalized/raw negative pair is genuinely complementary (a `sudo find /var/ !` line is reachable only via strip deletion, where the normalized negative does not match). (b) No false-red: `WORK="$(mktemp -d)"` (`:27`) sits under `/tmp`, and an anchored negative requires the exact operand immediately before ` !` — `sudo find /tmp/tmp.XXX/fakeproj !` contains none of them. (c) setfacl op lines `:692-693` log as `sudo setfacl -R -x g:60002 <root>` / `sudo setfacl -R -d -x g:60002 <root>` — the negatives' `-R -x g:60002` and `-R -d -x g:60002` spellings match exactly, non-vacuous. The 60001 (dev-gid) spelling is unpinned, but 60002 is a sufficient canary since both pairs run unconditionally together once a gate regresses.

**Section 5 — scope-comment truth:** all three citations resolve. `config.sh:336` `*[[:space:]]*) return 1 ;;` with the `0.0.39b C3` comment at `:336-337`; `resolution.md:133-141` is the a X2 disposition row with the same reasoning (space forms ungated at reader, `[ ! -d ]` + quoting, no lexical bypass shape); `#247` named at `resolution.md:16`, `:56`, `:656`. The comment's "[ ! -d ] plus full quoting" claim verified against `:583`, `:664-665`, `:692-695` (all operands quoted). Clean.

**Coverage line:** covered — all 5 sections (precondition trace with old/new probes; 12-input corpus with old-tree byte-comparison; empty-wiring + strip-parity trace; anchor binding, false-red direction, setfacl spellings; scope-comment citations). Deferred — did not run the unit suite itself (probe-level verification only, per micro scope); did not verify `#247`'s existence on GitHub (citation resolves in-repo at `resolution.md:656`, which records the issue draft as published 2026-10-24); did not audit the writer-side whitespace refusal beyond the cited arm. Checkpoints written to `/tmp/opencode/pr-00243-e/checkpoints/x.md` after every section.

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| S1 | **confirmed** | Read the malformed arm (test:750-761): landed negatives are find+setfacl×2+chmod for `//etc`, find+chmod for `/var/.`, find only for `.` (`sudo find . !` :760). `grep -n 'sudo chmod g-s \.' test` → exactly one hit, the `/var/.` line — no bare-`.` chmod negative exists. Resolution d Q3 text (res:466-472) says "find/chmod negatives for `/var/.` and `.`" — overstated for `.`'s chmod half. LOW stands: the resolution is the ledger the next review audits against; the operational gap is minor (a `.`-gate regression still reds via :760). |
| S2 | **confirmed** | String logic verified: test:859's fixed-string pattern is a strict prefix of :860's line, so grep -qF :859 matches the trailing-slash echo line too — a raw-echo-only omission stays green. Realistic trigger examined: the echo is one statement (unsh:580) printing raw `$root`; a spelling-conditional echo has no single-line revert shape. INFO as reported — the resolution's "asserts each skip echo verbatim" (res:393-394) is stronger than the pin delivers for the raw half. |
| S3 | **confirmed — probed** | `sh -c 'case /etc/ in /etc/*) …'` → matches without any strip (`*` matches the empty string and `/`), so `/etc/` is caught by the `/etc/*` arm (unsh:638) regardless of screen()'s strip; `/var/` probed against the `/var`-family arms (unsh:641) → no match (discriminating). Strip-deletion reds via `screening rejects /var/` — the exact form resolution spot-check 5 used. INFO as reported: belt-only redundancy, no coverage hole. |
| S4 | **confirmed** | test:858 feeds `/home/untest-agent /home/untest-agent/` — a strict prefix pair, falsifying res:481-486's "no fed operand is a string-prefix of another" for the agent-home arm. The conclusion it supports (no false red; over-match is desired there) verified by the same logic: the unanchored `sudo find /home/untest-agent` negative (:861) must catch both spellings. INFO as reported — invariant text wrong, outcome right. |
| S5 | **confirmed** | Read the ts loop (test:826-841): `/var//` is fed in the same FOUT as `/var/`, and the unanchored `sudo setfacl -R -x g:60002 /var` / `sudo chmod g-s /var` negatives (:832-833) substring-match the `/var//` op lines — double-fire misattributes the failure message to the trailing-slash spelling when the dot gate regressed. No false-red direction exists (both operands must stay op-free). INFO as reported. |
| X1 | **confirmed — probed (the round's one MED)** | Re-ran the compare both ways in scratch (`/tmp/opencode/pr-00243-e/verify/x1-compare.sh`): under `OPENCODE_USER=opencode/`, `/home/opencode/` → OLD SKIP (raw arm) / NEW OPS; `/home/opencode//` → SKIP/SKIP; bare `/home/opencode` → OPS/OPS (pre-existing under corruption, not a delta); under canonical `opencode`, all three inputs agree old-vs-new. Value trace code-verified: unsh:88 literal → :207-210 sources install.conf AFTER it (conf wins) → :211 defaults empty/unset only → :225-226 lookups `\|\| true`-swallowed → :579 compare. OPS tail code-verified: empty `UN_OC_UID/GID` skips chown loudly (:656-668) and the opencode ACL pair (:687-691), but `UN_DEV_GID` derives from `DEFAULT_USER` (:231, unaffected) so the dev setfacl pair (:693-694) runs and `chmod g-s` is unconditional (:696) — recursive root-run ops over `/home/opencode/`. MED conditional stands: trigger needs a hand-edited root-owned install.conf AND a hand-edited projects.conf entry (the writer refuses the agent home), i.e. two root edits — but both files are inside the blocklist's stated threat model (unsh:585-588, :622-624), the protected object is the agent home itself, and the raw arm being dropped was load-bearing for exactly this input. |
| X2 | **confirmed** | res:448-454 text verified as quoted; unsh:211 (`${OPENCODE_USER:-opencode}` — emptiness only) and :225-226 (`\|\| true`) verified to not enforce slash-freeness; the real guarantee verified writer-side: install.sh:349 literal `OPENCODE_USER="opencode"`, :589-592 charset gate — on `DEFAULT_USER`, and :1339 conf-heredoc stamps the literal. LOW stands: an inaccurate justification on a MED-class guard invites the next equivalence mistake (X1 is that mistake realized). |
| X3 | **confirmed — provenance corrected** | Probed the strip-only helper against the wired `/var`-family arms: `/var//` → ALLOWED (helper) vs dot-gate skip (loop, unsh:597-603). Latent-only verified: no fed static set contains a `//` form (test:289, :301, :319). Provenance correction: the disagreement predates the wave — the pre-d-X4 helper had neither strip nor dot gate and disagreed on `/var/` too; d X4 NARROWED the disagreement to `//` forms (fixed the strip class, did not add the dot gate). Recorded as pre-existing residual, severity INFO unchanged, safe direction (a future rejects-style `//` assertion reds loudly). |

Verification notes beyond the findings:

- **Landing-audit spot-checks:** S-axis mechanism+pin cites for
  all 9 implemented d-findings re-checked against the shipped tree (the
  agent-home arm, family-pin fixture, `_un_exist_roots` helper + pin,
  wiring pin, screen() strip, static forms, anchored negatives read
  directly; the d Q2 comment read in the diff). Held findings d S3/X3/Q6
  verified untouched (full-range `diff --stat` = uninstall.sh,
  test-uninstall.sh, resolution.md only).
- **Dual-compare sweep re-run:** `grep -rn '] || \[ "\${[a-z_]*%/}" ='`
  over files/ → no matches (rc=1), confirming the S axis's 2c result.
- **Pin placement (L4):** summary gate located at test:1345-1348
  (`failures` counter, `exit 1`); wiring pin (:264-271), helper pin
  (:780-784) and every new assertion sit before it.
- **Feed-side `[ -d ]` sweep re-run:** `grep -n '\[ -d '
  tests/unit/test-uninstall.sh` — line 776 (the helper) is the only
  feed-side probe; remaining hits are comments and the W2 source-grep
  pin.

## Retracted/ghost findings

None — all 8 reported findings verified against the code; no severity
adjustments; one provenance correction (X3 fix-induced → pre-existing
residual, rationale in the verification table) and no reviewer coverage
corrections this round.

## Run provenance

- Commission: maintainer, 2026-10-24 ("@opk-review-pass Micro Wave e
  über die aktuelle branch"). Fifth snapshot of the case; rotation
  normal (this fresh session authored neither the d-wave's fixes nor
  any prior snapshot of the chain).
- Tree: 24a0274 (feature/218-uninstall-revert-log-honesty), clean at
  fan-out (`git status --porcelain` empty), re-verified clean after all
  reviewers returned (no mutations ran on the repo tree at any point —
  verification probes lived under `/tmp/opencode/pr-00243-e/`).
- Material: fix diff 5993cac..24a0274; shipped files only in 09206ab:
  uninstall.sh 16 changed lines, test-uninstall.sh 123; 24a0274
  resolution.md bytes are bookkeeping (and became review material only
  as the X2/S1/S4 finding targets). Scope commissioned as **micro**;
  measured shipped diff is 139 changed lines (16 production + 123 test
  pins) — above the ~50-line micro bound on raw count, dominated by
  pin blocks over one 16-line production change. Run at micro
  parameters per the commission: 2 axes (S sweep/landing-audit, X
  security), ~5-minute budgets, batched greps + targeted reads, no
  whole-file reads.
- Host timestamps (main session, UTC): fan-out start
  2026-10-24T20:00:19Z; both reviewers returned by 20:14:10Z (host
  re-check; both subagent completions landed in the same tool batch).
  Sandbox clocks inside the host window after normalization: x stamped
  2026-10-24T22:01:32+02:00 (= 20:01:32Z) at launch; s stamped
  22:01:34 (same local clock, no TZ in stamp) — no skew anomaly.
- Reviewer subagents: 2 (cap 5 respected), fast tier
  zai-coding-plan/glm-5.3-flash, fresh contexts, axis prompts built
  from `.agents/skills/opk-review-pass/axis-prompt.md`; the main
  session (GLM-5.3) owned verification and embedded the reports.
- Checkpoints: `/tmp/opencode/pr-00243-e/checkpoints/{s,x}.md` (outside
  the reviewed tree), both with launch + per-section stamps + return
  lines. Reviewer probes under `/tmp/opencode/pr-00243-e/probe-x/`;
  main-session verification probes under
  `/tmp/opencode/pr-00243-e/verify/`.
- Sabotage/mutation windows: none — no tree mutations at any point
  (read-only reviewers; main-session verification by probes and code
  reads only). No screening in either direction required.
- Gates at snapshot time (main session, this tree, before the snapshot
  commit): `sh tests/unit/test-uninstall.sh` green (run at baseline
  before fan-out and again at verification); `make test` green; `make
  lint` green; `sh tests/unit/test-line-length.sh` green (review-*
  snapshots exempt from the ratchet — verbatim over wrap); INDEX
  regenerated with this commit (`python3 scripts/gen-review-index.py`);
  `sh tests/unit/test-reviews-lint.sh` and
  `sh tests/unit/test-reviews-parity.sh` green before the commit
  carrying this file.
- e2e: no new debt — this snapshot changes no shipped code; the
  reviewed fix wave already ran both suites in-wave (resolution Gates:
  `make e2e` 309, `make e2e-rootless` 47 on `09206ab`; the
  comparator-drop equivalence is the only production-semantics touch,
  and its non-equivalence surface (X1) is a corrupted-conf corner the
  e2e suites do not model — recorded here so the release gate knows
  the X1 disposition, not an e2e run, closes it).

## Recommendation

The d-wave's fixes all landed (9/9 mechanisms with pins, audited and
spot-confirmed), and the pin gaps snapshot d named are closed: the
agent-home guard's load-bearing half is pinned on both spellings, the
family pin reds on any alternative drop, the existence filter reds
host-independently, and the wiring is pinned beside the function. The
round's own findings:

- **e X1 (MED, conditional)** is the actionable one: the comparator
  drop is non-equivalent under a trailing-slash `OPENCODE_USER` from a
  hand-edited install.conf — the one input class where the dropped raw
  arm was load-bearing, and the failure mode is root-run revert ops
  over the agent home. Two disposition shapes close it: a one-line
  reader-side shape gate on the sourced `OPENCODE_USER` (charset case
  after :211, fail-loud or fallback-to-default), or a
  deliberately-not-done row naming the two-root-edits trigger as
  accepted residual. A fix touches uninstall.sh → review-relevant →
  owes one more micro round.
- **e X2 (LOW)** rides X1 either way: the resolution's d Q1
  precondition justification cites non-enforcing mechanisms — correct
  the text in the e-wave's resolution bookkeeping (the actual guarantee
  is writer-side: install.sh:349 literal + :589-592 charset gate +
  :1339 heredoc), so the next equivalence claim starts from the true
  anchor.
- **e S1/S4 (LOW/INFO)** are the same bookkeeping class: two
  overstated sentences in the d-wave's resolution detail (the `.`
  chmod negative that did not land; the prefix-uniqueness invariant
  that is false for the agent-home arm) — correct them in the same
  resolution edit; no code change implied.
- **e S2/S3/S5/X3 (INFO)** are record-only or ride-along material: the
  subsumed raw-echo pin half (S2) and the belt-only `/etc/` form (S3)
  could ride the next test-touching wave; S5 (misattribution-only) and
  X3 (latent, safe direction) need nothing.

Per the stop rule (RM-0064/RM-0067): a next round that fixes X1 with
the reader-side gate touches production code — review-relevant — and
owes one more wave review; a round that dispositions X1
deliberately-not-done and corrects only the resolution text (X2, S1,
S4) stays in bookkeeping and leaves review-relevant code untouched —
stop-rule eligible. The loop's state is the maintainer's call — this
session records, it does not close.
