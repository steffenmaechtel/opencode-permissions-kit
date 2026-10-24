<!-- review-meta
ID: pr-00243
Snapshot: d
Subject: wave review of the c-wave's fix wave — trailing-slash normalization, agent-home refusal, extraction+diagnostics pins
Scope: wave
Base: 0.0.56 @ 818b860
Diff: 818b860..3de7f94
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S/X/Q, fast tier GLM-5.3-Flash)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review d — wave review of the c-wave's fix wave (pr-00243)

Round d over the diff 818b860..3de7f94 (3 commits: 822e7a0 "fix(uninstall):
trailing-slash normalization, agent-home refusal, extraction+diagnostics pins
(#243 c S1 S2 X1 Q1 Q2 Q3 Q5)" — the fix wave; f10a533 and 3de7f94 touch
resolution.md only, bookkeeping). Shipped material: uninstall.sh (50 changed
lines: lexical agent-home refusal before `[ -d ]`, one-trailing-slash
normalization after the dot gate, rewritten parity comments naming all three
mirrors and all three bounded ops) and test-uninstall.sh (194: extractor as
a function with a decoy-fixture pin, `_unarm_show` family pin, existence-
filtered system-path arm, trailing-slash arm, agent-home arm); docs
untouched. All 7 implemented c-findings were audited as LANDED by the S axis
(mechanism + pin each) and spot-confirmed in verification; this snapshot's
findings are about the fix wave's own edges — one pin gap on the load-bearing
half of the new agent-home guard (X2, empirically confirmed by mutation),
dominated alternatives inside the family pin (S1), a dead comparator arm
(Q1), and the whitespace-parity residual the rewritten "completed" comment
invites (X1).

## Findings index (combined)

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| S1 | LOW | c S2 family pin cannot red deletion of 2 of its 9 regex alternatives (`skipped`, `PARTIALLY`) — "feeds every family" is overstated | fix-introduced |
| S2 | INFO | c Q3 existence-filter has no deletion-red pin on a host that has all six fed dirs — red condition is host-dependent | fix-introduced |
| S3 | INFO | c Q5 lands as comment-only with no pin (by nature); mechanism present, underlying op pinned behaviorally | fix-introduced |
| X1 | MED (→ LOW in verification) | Reader lacks the writer's whitespace refusal — whitespace conf paths reach the root-run revert ops (reader-wider-than-writer) | pre-existing (aggravated by wave comment's parity-"completed" claim) |
| X2 | MED | Pin gap: the once-stripped agent-home comparator (uninstall.sh:576) has no behavioral pin — dropping it keeps the suite green | fix-induced (gate wave-introduced, pin coverage incomplete) |
| X3 | INFO | Writer agent-home holes (`/home/opencode//`, `/home//`) unchanged by the wave — held #247 (c X2) class, extended shapes recorded | pre-existing (untouched, verified) |
| X4 | INFO | Static `screen()` helper is blind to the strip normalization; harmless today because no static assertion feeds it slash forms | fix-induced (harmless as asserted) |
| Q1 | LOW | Agent-home refusal's raw-form compare is functionally dead; comment presents both arms as load-bearing | fix-introduced |
| Q2 | LOW (→ INFO in verification) | Driver comment "OPENCODE_USER is the one env pin" is false as written — the driver fixes three env vars to literals and sets six | fix-introduced |
| Q3 | INFO | setfacl never asserted absent in the Q1/ts/system-path negative coverage (find+chmod only) — gap is effectively harmless | fix-introduced |
| Q4 | INFO | Trailing-slash arm's `sudo find /var/` negative is unanchored and over-matches longer `/var/…` operands | fix-introduced |
| Q5 | INFO | S1 block-identity pin binds the extractor function, not the SCREEN_PATTERNS wiring — a wiring-level shape-keyed bypass stays green | fix-introduced |
| Q6 | INFO | Writer accepts and stores `/home/<agent>//` (once-stripped, trailing slash) which the reader then refuses — reader stricter, writer side pre-existing | pre-existing |

Provenance split: 9 fix-introduced/fix-induced (S1, S2, S3, X2, X4, Q1, Q2,
Q3, Q4, Q5 — ten counting Q5's wiring scope) + 3 pre-existing (X1, X3, Q6).
As reported: 2 MED, 3 LOW, 8 INFO; after verification X1 adjusts to LOW and
Q2 to INFO (rationale in the verification table) → 1 MED, 3 LOW, 9 INFO.

---

## Axis S (mechanical sweep), verbatim

# Mechanical sweep — wave `818b860..3de7f94`, case pr-00243, fix wave 3 (reviewer s)

## Findings index

| ID | Severity | One-liner |
|----|----------|-----------|
| S1 | LOW | c S2 family pin cannot red deletion of 2 of its 9 regex alternatives (`skipped`, `PARTIALLY`) — "feeds every family" is overstated |
| S2 | INFO | c Q3 existence-filter has no deletion-red pin on a host that has all six fed dirs — red condition is host-dependent |
| S3 | INFO | c Q5 lands as comment-only with no pin (by nature); mechanism present, underlying op pinned behaviorally |

## Landing audit — 7/7 mechanisms verified present

| Claim | Mechanism (shipped tree) | Pin that reds on deletion |
|-------|--------------------------|---------------------------|
| c S1 | `tests/unit/test-uninstall.sh:207-222` — extractor is `_un_blocklist_tokens()`, used at :225 | `:236-255` — decoy fixture (a `/*)` arm, dot-form arms, backslash continuation in a non-blocklist block); shape-keyed reversion splices decoy arms → identity mismatch → red |
| c S2 | `:597-613` — `_un_s2_in` feeds 8 family lines through `_unarm_show`, identity-compared | `:609-613` — any family line falling out (e.g. reintroduced `tail -6` drops lines 7–8) reds. **See S1: two alternatives are not actually covered** |
| c X1 | `files/opencode-permissions-kit-lib/management/uninstall.sh:612-614` — `${root%/}`, empty→`/` restore, after dot gate :594-599, before blocklist :627 | `test:766-788` — feeds `/var/ /home/ / /var//`; asserts stripped skip echoes (:775), no `sudo find /var/` (:776,:781), `Skipping system path: /$` (:778), no empty-operand `Reverting kit ownership in:` (:779), `//` stays the dot gate's catch (:784) |
| c Q1 | `uninstall.sh:576-579` — raw + once-stripped compare, before `[ ! -d ]` at :580 | `test:794-801` — driver pins `OPENCODE_USER=untest-agent` (:398-400, inside subshell); refusal deleted → silent `[ -d ]` skip → asserted skip echo absent → red |
| c Q2 | `test:585-595` — no `tail` in `_unarm_show` | The S2 identity pin (`:609`) — verified by resolution sabotage 6; only remaining `tail` in the file is :995 `tail -1` (version-line extraction, not a diagnostics window) |
| c Q3 | `test:740-743` — fed set built by `[ -d ]` | **None on a fully-equipped host** — see S2 |
| c Q5 | `uninstall.sh:622-626` + `test:293-296` — both comments name three ops incl. "chmod g-s" | **None (comment-only)** — see S3; the op itself is pinned at `test:645-651` |

## Finding details

### S1 (LOW) — S2 family pin: two regex alternatives are dominated, deleting them keeps the pin green

`test:595`: `grep -E 'log:|WARN:|PARTIALLY|Removed\.|\[DRY\]|Skipping|skipped|unknown|^sudo '`

The fixture (`test:601-608`) feeds 8 lines but no line matches `skipped` at all, and the only `PARTIALLY` line (:603) also matches `log:`. grep -E is line-level: dropping `PARTIALLY` or `skipped` from the regex leaves every fed line still matching via another alternative → identity compare stays green. Production confirms the domination is real, not just fixture-shaped: every `skipped` line in uninstall.sh also carries `log:` (:335) or `unknown` (:656-657), and every `PARTIALLY` line carries `log:`/`WARN:` (:694-698). Trigger: delete either alternative from `test:595` → `sh tests/unit/test-uninstall.sh` stays green. Matters because `test:598` ("Every family line fed here must surface") and resolution.md:39 ("family pin feeds every family") claim more than the pin delivers for exactly 2 of 9 alternatives — the resolution's own sabotage standard (drop a family → red, demonstrated for `^sudo `) does not hold for these two. Diagnostics-only; green path unaffected, hence LOW.

### S2 (INFO) — c Q3 mechanism unpinned on fully-equipped hosts

`test:740-743`: `[ -d "$_un_sys" ] && _un_sysroots=…`. On a host having `/var /home /opt /srv /media /mnt` (all six exist), deleting the filter produces the identical fed set and an identical green run; the pin only reds on hosts missing one of the FHS-optional dirs — which is exactly the host class the fix targets. The degradation is disclosed by design (comment `test:734-739`: "a missing dir degrades coverage, never truth"; pass line :754 prints the fed set) and the resolution claims no Q3 sabotage — recorded here because the landing-audit contract asks for a deletion-red pin and none exists by construction. The ts arm has the same shape (:768-770) but feeds `/ /var//` unconditionally — existence-safe (`[ -d / ]` always true, `/var//` resolves to `/var` at path-resolution level).

### S3 (INFO) — c Q5 is comment truth, no pin possible as shipped

Mechanism verified present (`uninstall.sh:622-626`, mirrored `test:293-296` — both now list "uid/gid-matched chown, kit-gid ACL strip and one setgid-bit clear (chmod g-s)"). No pin reds if the comment loses the third op; the suite never greps comment text. The op's behavior is separately pinned (`test:645-651` chmod-g-s failure arms), so the underlying honesty is guarded — only the comment-completeness claim is unguarded. Resolution lists no Q5 sabotage, consistently. Recorded, not actionable beyond noting the audit result.

## Verified clean (no finding)

- **X1 placement claim (blind-spot probe)**: extracted uninstall.sh:564-636 verbatim, fed 12 paths. `/var///` and `/var//` die at the dot gate (`*//*`) — never reach the strip, so "at most ONE trailing slash can remain" holds; `/` survives to the blocklist's `/` arm printing `/` (never empty); `/var/`→`/var`, `/home/`→`/home`, `/opt/`→`/opt` normalize onto bare arms; `/home/opencode` and `/home/opencode/` both refused by the Q1 compare; `/var/tmp/` processes (pinned divergence). The two non-outputs in the probe (`relative`, `/var/www/vhosts`) are the pre-existing `[ ! -d ]` silent skip at :580 — the Q3 premise, a-wave order, not this wave.
- **Q1 empty-user hazard**: `OPENCODE_USER` is hard-set at `uninstall.sh:88`, may be overridden by sourced install.conf, and `uninstall.sh:211` (`"${OPENCODE_USER:-opencode}"`) restores the default — it can never be empty at the :576 compare; derived before the loop at :564 in every case. Test-side pin is confined to the driver subshell (`test:398`), no escape.
- **Anchor drift**: `UN_RC_Q` range resolves (`un_rc_q() {` :195 → `^}$` :203); CFG_SECTION anchor resolves (`uninstall.sh:710`) and probe-extraction brackets the section reset (`_un_partial=""`/`_un_revert_failed=0` at range lines 8-9) plus both b-S2 markers; `PROJECT_LOOP` extraction contains the new Q1+X1 code; the block-identity awk keys correctly over the now-three `case "$root" in` blocks (only the blocklist body echoes "Skipping system path"). Parity pin probe (reader extractor vs writer extraction, tmp-family excluded): **PARITY-EQUAL** — `config.sh:342` does carry `/srv|/srv/*` (an earlier read of mine clipped it).
- **Fail-open sweep**: uninstall.sh diff adds no `|| true`, no stderr redirects, no probe pipes. Test diff reuses the pre-existing `FOUT=$(…) || true` driver idiom (now at :744, :772, :794) with assertions on FOUT catching driver failure — sibling-consistent.
- **One-strip siblings**: `config.sh:312` `_pp="${1%/}"` (writer) and the reader's :612 are both single strips and both exact — the reader's dot gate kills multi-slash forms first (probe-verified). `fs-baseline.sh:152`, `ddev-handover.sh:530` use strip-ALL while-loops — different sites without a dot-gate guarantee, not siblings of this mechanism.
- **Deliberately-not-done untouched**: diff touches only uninstall.sh, test-uninstall.sh, resolution.md; no writer-blocklist change (c X2), no symlink gate (c X3), no space arm (c X4 — writer's `*[[:space:]]*` at `config.sh:336` remains unmirrored), no WARN/log reorder (c Q4).
- **Variable hygiene**: `_un_root` (:612-614) no collision, no post-loop use; `_un_s1_fixture`/`_un_s2_in`/`_un_sysroots`/`_un_sys`/`_un_tsroots`/`_un_ts` each confined to their arm; loop vars not used after their loops; no subshell escapes.
- **Suite**: `sh tests/unit/test-uninstall.sh` → **green** ("All uninstall tests passed.").
- **ShellCheck delta**: `-S style` counts identical to the 818b860 baseline for both files — uninstall.sh 14=14 (4×SC1090, 1×SC2028, 7×SC2140, 2×SC3043), test 79=79 (same code distribution) — zero new findings.

## Coverage

Covered: landing audit 7/7 (mechanism + pin cites), all three named blind-spot surfaces (probe-simulated, not just read), anchor-drift resolution + CFG_SECTION bracketing, fail-open class sweep, one-strip sibling sweep, `tail`-window sweep, host-dependent-feed sweep, deliberately-not-done verification, variable hygiene, suite run, shellcheck delta. Deferred: e2e suites (not micro-scope; resolution records 309+47 green on `822e7a0` — taken on record, not independently verified); sabotage reproduction on the tree (read-only mandate — pin red-conditions verified by code reading and probes under `/tmp/opencode/pr-00243-d/probe-s/` instead; the resolution's 6 spot-check records were not re-executed).

---

## Axis X (security), verbatim

# Security review — wave `818b860..3de7f94` (pr-00243 fix wave 3), axis X

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| X1 | MED | Reader lacks the writer's whitespace refusal — whitespace conf paths reach the root-run revert ops (reader-wider-than-writer) | pre-existing (aggravated by wave comment's parity-"completed" claim) |
| X2 | MED | Pin gap: the once-stripped agent-home comparator (`uninstall.sh:576`) has no behavioral pin — dropping it keeps the suite green | fix-induced (gate wave-introduced, pin coverage incomplete) |
| X3 | INFO | Writer agent-home holes (`/home/opencode//`, `/home//`) unchanged by the wave — held #247 (c X2) class, extended shapes recorded | pre-existing (untouched, verified) |
| X4 | INFO | Static `screen()` helper is blind to the strip normalization; harmless today because no static assertion feeds it slash forms | fix-induced (harmless as asserted) |

The wave's core claims verified TRUE: every internal-`//` form is the dot gate's catch pre-strip (incl. `/var///`, `/var//x`, `/home//`); `/` never becomes an empty operand (blocklist `/` arm); no dotted/double-slashed agent-home spelling dodges both gates; only intended behavior flip is `/home/` OPS→screened; allowed classes (`/var/www/vhosts/extra-project`, `/tmp/x`, `/home/dev/x`) unaffected.

## Details

### X1 — MED — whitespace paths: reader processes what the writer refuses

Evidence — writer refuses (config.sh:336):
```sh
        *[[:space:]]*) return 1 ;;        # storage format is line-based and
```
Reader has no whitespace arm anywhere in its gates (uninstall.sh:576-630: agent-home, `-d`, absolute, dot/empty-segment, strip, blocklist). Verbatim-arm probe (`/tmp/opencode/pr-00243-d/probe-x/probe.sh`, patterns mechanically extracted and exact-string-checked against the shipped files), `EXISTS=1` (dir present): `/var www`, `/etc ` (trailing space), `/var/www/vhosts/my site` → **OPS** (would run `sudo find … -exec chown`, `setfacl -R -x` ×2, `chmod g-s`) while the writer returns 1 for all three.

Why it matters: the blocklist's stated threat model is the hand-edited conf (uninstall.sh:607-611), and this class sails through every gate when the directory exists (`[ ! -d "$root" ]` at 580 silently skips only nonexistent paths). The wave's rewritten comment claims parity "completed by the normalization and agent-home refusal above" (uninstall.sh:604-608) — the completion claim overreaches: the normalization fixed only the slash class; the writer's 0.0.39b C3 whitespace refusal was never mirrored (pre-wave reader at 818b860 has no whitespace arm; its only `space` hits are an unrelated comment and a grep pattern). Impact is bounded to the same op class as any processed root, so MED not HIGH. Mitigants found: leading-whitespace forms die at the absolute gate; whitespace under a blocklisted `prefix/*` arm is still screened (`/etc/nginx ` → BLOCKLIST, glob `*` eats the suffix including the space); the writer never stores such entries, so a hand-edit is the only feed.

### X2 — MED — stripped agent-home form is unpinned

Evidence — the gate (uninstall.sh:576):
```sh
        if [ "$root" = "/home/$OPENCODE_USER" ] || [ "${root%/}" = "/home/$OPENCODE_USER" ]; then
```
The behavioral arm feeds only the bare form (test-uninstall.sh:794):
```sh
FOUT=$(_un_loop_out "" false 60000 60002 60001 "/home/untest-agent") || true
```
No arm feeds `/home/untest-agent/`. Deleting the second comparator (`` [ "${root%/}" = … ] ``) keeps every pin green: the bare form still hits the raw compare, and on the test host the trailing-slash form dies silently at `-d` (gate order puts agent-home before `-d`, but nothing asserts the trailing-slash form at all). On a real host where the agent home exists, `/home/opencode/` would then pass agent-home → `-d` → dot gate → strip to `/home/opencode` → blocklist (which has a bare `/home` arm only, no `/home/*`) → **root-run revert ops over the agent home** — the exact hazard the comment at uninstall.sh:567-575 says the dual compare prevents ("a trailing slash must not dodge it"). The shipped code is correct (probe: both forms → AGENTHOME); this is a regression-watcher gap, and it is trivially closable since the gate precedes `-d` (no host dir needed). Secondary, lower: agent-home spellings routed to the dot gate (`/home/untest-agent//`, `/home/untest-agent/.`) are also unpinned in that spelling, though the dot gate itself is pinned generically (`//etc`, `/var/.`, `/var//`).

### X3 — INFO — writer holes unchanged (held #247 class); shapes extended

config.sh strips once (config.sh:312 `_pp="${1%/}"`) *before* its dot gate, and its agent-home refusal exact-matches the bare form only (config.sh:351). Probe: writer PASSES `/home/opencode//` (norm `/home/opencode/` — the agent home, storable with trailing slash), `/home//` (norm `/home/`), and `/var/x//` (norm `/var/x/` — trailing slash survives into storage). Reader refuses all three via its dot gate. `config.sh` is untouched in `818b860..3de7f94`, so the c X2 holding is unchanged. Recorded for #247: the writer's `/var//`-shape hole generalizes, and one variant lands on the agent home itself; today the reader covers the writer there (its compare takes the once-stripped form), so the residual risk is precisely a future reader regression — i.e. X2 is the pin that would catch it.

### X4 — INFO — `screen()` helper blind to the strip, unasserted

test-uninstall.sh:261-265 evals only `_un_blocklist_tokens` output, so `screen '/home/'` reports allowed (bare `/home` arm doesn't match `/home/`) — contradicting shipped behavior for stripped forms. No static loop feeds slash forms (test-uninstall.sh:268, 279 feed bare paths only), and the behavioral arm (test-uninstall.sh:768-789) covers `/var/ /home/ / /var//`, so there is no false green today. A future static slash-form assertion against `screen()` would pin the wrong, unnormalized semantics.

## Coverage

Covered: wave diff; full loop section (uninstall.sh:565-700); `OPENCODE_USER` derivation (uninstall.sh:88, 211 — `:-` default, top-level, non-empty at loop, so the `/home/`-as-agent-home degenerate case cannot arise); verbatim-arm probe over ~55 forms (full RM-0085 slash corpus, `///`, `/var//x`, `/var/./`, whitespace interior/trailing/leading, tilde, case variants, agent-home spellings, allowed classes) through reader gates in two `-d` modes and through the writer's `project_path_sane` verbatim; blocklist monotonicity under the strip (prefix-closed arms — no screened→processed flip exists; only `/home/` flipped OPS→screened, the intended fix; `/var/` was already screened pre-wave via `/var/*`+empty glob); `/` empty-strip restore; `-d`-on-raw equivalence (trailing slash semantically null for directory tests — no new symlink window vs c X3, which stays deferred to #245); pin coverage of both files; pre-wave provenance at 818b860. Deferred: e2e suites not run (read-only reviewer, no Docker) — behavioral conclusions rest on the verbatim probe plus reading the test driver; `install.sh`'s validator copy of `project_path_sane` not cross-checked against `config.sh` (pre-existing, outside wave material); root-run ops themselves never executed (gate classification only). Probe preserved at `/tmp/opencode/pr-00243-d/probe-x/probe.sh`; checkpoints at `/tmp/opencode/pr-00243-d/checkpoints/x.md`.

---

## Axis Q (quality), verbatim

# Quality-axis review — wave 818b860..3de7f94 (fix wave 3, case pr-00243)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | LOW | Agent-home refusal's raw-form compare is functionally dead; comment presents both arms as load-bearing | fix-introduced |
| Q2 | LOW | Driver comment "OPENCODE_USER is the one env pin" is false as written — the driver fixes three env vars to literals and sets six | fix-introduced |
| Q3 | INFO | setfacl never asserted absent in the Q1/ts/system-path negative coverage (find+chmod only) — gap is effectively harmless | fix-introduced |
| Q4 | INFO | Trailing-slash arm's `sudo find /var/` negative is unanchored and over-matches longer `/var/…` operands | fix-introduced |
| Q5 | INFO | S1 block-identity pin binds the extractor function, not the SCREEN_PATTERNS wiring — a wiring-level shape-keyed bypass stays green | fix-introduced |
| Q6 | INFO | Writer accepts and stores `/home/<agent>//` (once-stripped, trailing slash) which the reader then refuses — reader stricter, writer side pre-existing | pre-existing |

## Details

**Q1 — LOW — redundant raw compare in agent-home refusal.**
`files/opencode-permissions-kit-lib/management/uninstall.sh:575`:
```sh
if [ "$root" = "/home/$OPENCODE_USER" ] || [ "${root%/}" = "/home/$OPENCODE_USER" ]; then
```
`${root%/}` equals the target for exactly the inputs `$root` does (a raw match implies no trailing slash, so stripped is identical) *plus* the trailing-slash form — the stripped arm is a strict superset and the raw arm can never change the outcome. The comment at :573-574 ("The compare takes the raw and the once-stripped form (a trailing slash must not dodge it)") justifies only the stripped arm. No direction-of-strictness problem — the predicate is exactly equivalent to the writer's single stripped compare. Matters because the dead arm plus the comment imply both are needed, inviting cargo-cult copies.

**Q2 — LOW — "the one env pin" drift.**
`tests/unit/test-uninstall.sh:375-376`: "OPENCODE_USER is the one env pin: fixed to untest-agent (#243 c Q1) so the agent-home arm needs no host directory." The same driver sets six env vars (`:400-401`): `UN_OC_UID`, `UN_OC_GID`, `UN_DEV_GROUP=devgroup`, `UN_DEV_GID`, `DEFAULT_USER=devuser`, `OPENCODE_USER=untest-agent` — of which `UN_DEV_GROUP` and `DEFAULT_USER` are also fixed literals. The intended meaning ("the one pin the new Q1 arm requires") is recoverable from the `#243 c Q1` tag, but the literal claim is wrong. Comment-only, diagnostics unaffected.

**Q3 — INFO — setfacl negative-coverage gap.**
Q1 arm asserts find+chmod absent (`test:795-798`), ts loop skip+find (`:763-770`), system-path loop skip+find+chmod (`:750-756`); no arm asserts `! sudo setfacl … <refused root>`. Harmless in practice: `sudo chmod g-s "$root"` runs unconditionally for every processed root (`uninstall.sh:697`), so any regression that lets ops reach a refused root also emits a chmod line the negatives catch; a regression emitting setfacl but neither find nor chmod has no realistic path through the code.

**Q4 — INFO — unanchored `sudo find /var/` negative.**
`test:769` greps fixed-string `"sudo find $_un_ts"` where `$_un_ts=/var/` — demonstrated to also match `sudo find /var/www/vhosts/x ! -type l`. No false red is reachable in the current harness (the only other fed root is `$WORK/fakeproj` under `/tmp`), and the over-match errs red-ward; noting the asymmetry with the system-path arm's anchored `sudo find $_un_sys ` (trailing space, `:753`).

**Q5 — INFO — S1 pin scope is the function, not the wiring.**
Probe-verified: a shape-keyed reversion *inside* `_un_blocklist_tokens` reds the pin (decoy arms `/decoy|/decoy/*|/./|*..*|*/./*` leak into the extraction). But a reversion that bypasses the function — rebuilding `SCREEN_PATTERNS` (`test:224`) inline with a shape-keyed grep — stays green: the pin still tests the intact function, and the five behavioral screening paths (`:299`: `/var/www/vhosts /var/www /home/dev/x /tmp/x /var/tmp/x`) contain no `//`, `/.`, or `..` shapes, so leaked form-gate arms trip nothing. The comment's own first sentence (`:206-208`, "drives the SAME code, not a drifting copy") scopes the claim to the function; residual exposure is the one-line wiring assignment.

**Q6 — INFO — `//` agent-home asymmetry, reader stricter.**
Writer (`config.sh:311-351`, mirrored `install.sh:933-973`) strips once then compares once: `projects add /home/<agent>//` stores `/home/<agent>/` (passes the dot gate — no `//` remains). The reader refuses it (raw `*//*` dot-gate catch, `uninstall.sh:594`) — a writer-stored root skipped at revert. Reader-stricter is the safe direction and the writer looseness is pre-existing; no wave claim is falsified (the comment explicitly routes `//` forms to the dot gate, `:606-608`).

## Verified clean (probe-backed where noted)

- **Three-mirror parity claim** (`uninstall.sh:616-626`): **strip** — `/` kept as `/` hits the blocklist `/` arm, equivalent to the writer's refuse-on-empty; one strip exact after the dot gate (`/var//` caught by `*//*` — probe-confirmed); the comment's early-strip hazard claim is TRUE (probe ran the 818b860 loop: a bare `/var/` produced `Reverting kit ownership in: /var/` + ops — the exact hole shape). **Arm order** — mechanically compared: reader sequence is the writer's token-for-token, minus exactly the four documented-divergence scratch arms (`/tmp`, `/tmp/*`, `/var/tmp/*`, `/var/tmp`, disclosed in the same comment block). **Agent-home** — reader predicate ≡ writer's single stripped compare; `OPENCODE_USER` defaulting equivalent (`uninstall.sh:211` `${OPENCODE_USER:-opencode}` vs writer's inline default); the comment's "(/home, /var)" hole enumeration is accurate — the probe showed pre-fix ops ran over **both** `/var/` and `/home/` (my initial `/var/*` empty-match theory was wrong; the probe corrected it before flagging).
- **Skip-echo comment** (`:611`): true in the identifying sense — the normalized path (`/var` for conf `/var/`) identifies the entry; `/` prints as itself. No input normalizes to something that fails to name its entry.
- **S2 pin**: mutations family-drop, `tail -6` reintroduction, and reorder ALL red (probed against the 8-line fixture); fixture carries one line per alternation family; the order claim holds (grep preserves input order; string equality pins it).
- **X1 regex pins**: `Reverting kit ownership in: *$` matches the empty operand and never normal lines (probed); `sudo find / !` pins the `/`-arm's presence. Each ts leg discriminates a strip reversion independently (`/var/` emits ops pre-fix even on hosts without `/home`), so existence-degradation never fully defangs the arm.
- **Host-portability honesty**: both fed-set pass lines disclose the fed set including `${…:-none fed}`; Q1 host-independence verified (driver pins `OPENCODE_USER` before `eval`, refusal is lexical before `[ -d ]`).
- **Dead code/naming**: `_un_root` appears only at `:612-614`, no leak or collision; `_un_sysroots`/`_un_tsroots` consumed after their build loops; `_un_s1_fixture`/`_un_s2_in` match suite temp conventions.
- **Tail sweep**: single survivor `test:995` (`tail -1` in `py_ask`) — deliberate last-line PTY-transcript semantics on the green path; drift reds loudly via `py_pin`'s case. Not a Q2-class residual; no other `tail -` in the suite.
- **Docs**: no page under `docs/` describes the loop's skip/screen echoes — the new "Skipping agent home" and normalized "Skipping system path" messages stale nothing. Bounded-ops pair (`test:293-296` vs `uninstall.sh:623-626`) names the identical three ops and matches behavior (one uid/gid-matched chown, kit-gid setfacl strips, one non-recursive `chmod g-s` per root).

## Coverage

Covered: all five planned sections — (1) comment-claim audit of every new/changed claim in both shipped files, (2) pin discrimination walkthrough with live probes (S1 old-shape extractor, S2 mutations, X1 pre-fix-vs-post-fix loop over the trailing-slash feeds, regex pins) under `/tmp/opencode/pr-00243-d/probe-q/`, (3) host-portability and degradation honesty, (4) dead code/naming, tail sweep, docs check, (5) wrap-up. Checkpoints written to `/tmp/opencode/pr-00243-d/checkpoints/q.md` after each section. Deferred: nothing from the brief; e2e not re-run (out of unit scope, recorded green in the resolution — bookkeeping, not review material).

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| S1 | **confirmed — suite-level mutation** | Ran the pin logic verbatim in scratch (`/tmp/opencode/pr-00243-d/verify/s1-family.sh`): baseline regex → identity green; `PARTIALLY` dropped → STILL green (the `PARTIALLY` fixture line carries `log:`); `skipped` dropped → STILL green (fixture has ZERO lowercase-`skipped` lines — `grep -c` = 0). Then at suite level in a scratch worktree: deleted `\|PARTIALLY` from test:595, `sh tests/unit/test-uninstall.sh` → "All uninstall tests passed" — full suite green with the family silently weakened. Domination verified production-side too (grep: `skipped` lines carry `log:`/`unknown`, `PARTIALLY` lines carry `log:`/`WARN:`). LOW stands: diagnostics-only construct, but the resolution's "feeds every family" claim is overstated for 2 of 9 alternatives. |
| S2 | **confirmed** | By construction: on this host all six dirs exist, so deleting the `[ -d ]` filter at test:741-743 yields the identical fed set and run. The degradation is disclosed (comment test:734-739, pass line prints the fed set). INFO as reported — recorded pin-by-construction gap, no action demanded. |
| S3 | **confirmed** | Both comment sites verified (uninstall.sh:622-626, test:293-296 name three ops incl. `chmod g-s`); no pin can guard comment text without grepping comments — the op itself is behaviorally pinned (chmod-g-s failure arms). INFO as reported. |
| X1 | **confirmed — severity adjusted MED → LOW** | Reproduced the reviewer's probe myself with arms byte-checked against the shipped file (`verify/x1-whitespace.sh`): `/var www`, `/etc `, `/var/www/vhosts/my site` → OPS when the dir exists; SKIP-notdir when absent (`[ -d '/etc ' ]`=n, `[ -d '/var www' ]`=n on this host); `/etc/nginx ` → BLOCKLIST (glob eats the suffix); writer space arm present at config.sh:336. Mechanics fully confirmed. Severity LOW not MED because: (a) the reachable operand is a space-named directory that must physically exist — it is NOT the system tree it resembles (`/etc ` ≠ `/etc`; no system tree is reachable), so the comment's operative claim ("cannot drive the root-run revert ops over system trees") is not falsified; (b) the writer's refusal is a storage-format refusal (0.0.39b C3, quoted in config.sh:336), not a system-path refusal — mirroring it at the reader is a parity nicety, which is exactly the recorded deliberate a X2 / c X4 disposition ("space-forms stay ungated at the reader… a spaced path cannot lexically equal a system path"); (c) hand-edited conf (root-owned file) plus a hand-created space-named dir is the only feed. The finding's real delta is the rewritten comment's "completed by the normalization and agent-home refusal above" breadth — it invites the reading that ALL writer refusals are mirrored. LOW: scope the comment or mirror the arm (natural home: the #247 parity wave). |
| X2 | **confirmed — suite-level mutation (the round's one MED)** | Scratch worktree at 3de7f94: deleted the once-stripped comparator (uninstall.sh:576 `\|\| [ "${root%/}" = … ]`), ran `sh tests/unit/test-uninstall.sh` → "All uninstall tests passed", rc=0. The pin gap is real: the Q1 arm feeds only the bare form (test:794), the raw compare still catches it, and no arm anywhere feeds `/home/untest-agent/`. Hazard chain on a real host (agent home exists): trailing-slash conf entry → raw compare misses → `-d` passes → dot gate passes → strip → `/home/<agent>` → blocklist has no `/home/*` → root-run ops over the agent home — the exact hazard the dual compare was built to stop (c Q1). Trivially closable host-independently (refusal sits before `-d`; feeding `/home/untest-agent/` needs no dir). MED stands: a deletion-red pin is the house standard for every new construct, this one guards a MED-class security gate, and the resolution's c Q1 claim "each piece carries its own pin" is false at arm granularity. |
| X3 | **confirmed** | Writer arms re-verified from the untouched diff side: config.sh:312 (one strip before its gate) and :351 (bare-form compare only) — `/home/opencode//` → norm `/home/opencode/` passes the writer (no `//` remains) and would store the agent home with a trailing slash; reader refuses via dot gate. Pre-existing, held for #247 — extends that issue's shape list. INFO as reported. |
| X4 | **confirmed** | `screen()` (test:261-265) evals SCREEN_PATTERNS with no normalization — `screen '/home/'` reports allowed while the shipped loop refuses it. No static arm feeds slash forms today (test:268/279 feed bare paths); behavioral arm covers the forms. INFO as reported — future-risk note (a static slash-form assertion would pin wrong semantics). |
| Q1 | **confirmed** | Logic verified: `${root%/}` is the identity on any string without a trailing slash, so every raw-match is also a stripped-match — the raw arm is a strict subset and can never change the outcome (dead arm). Cross-checked with X2: the pinned half is the dead half, the load-bearing half is the unpinned half — together they mean the effective guard (`[ "${root%/}" = … ]` alone) is exactly the part no pin exercises. LOW as reported (dead code in a security gate + comment implying both arms are needed). |
| Q2 | **confirmed — severity adjusted LOW → INFO** | grep confirms three literal env pins in the driver (test:395 `UN_DEV_GROUP=devgroup`, :397 `DEFAULT_USER=devuser`, :401 `OPENCODE_USER=untest-agent`) plus three parameterized (`UN_OC_UID/UN_OC_GID/UN_DEV_GID`) — "the one env pin" is false as written. Comment-only inaccuracy with the intended meaning recoverable from the `#243 c Q1` tag — the same class as c Q5 (comment false by one item), which this chain rates INFO. Consistency: INFO. |
| Q3 | **confirmed** | Verified `un_rc_q "chmod g-s" sudo chmod g-s "$root"` runs per processed root (uninstall.sh:686, inside the loop) — any op-reach regression emits a `sudo chmod g-s <root>` line the negatives catch (Q1 arm asserts it absent at test:798). setfacl-specific escapes have no realistic path. INFO as reported. |
| Q4 | **confirmed** | Read the assertion (test:776): `grep -qF "sudo find $_un_ts"` with `$_un_ts=/var/` is an unanchored prefix match (`sudo find /var/www/...` would match). No false red reachable in today's harness (other fed root is `$WORK/fakeproj` under /tmp; `/` has its own anchored negatives) and the over-match errs red-ward. INFO as reported — asymmetry with the trailing-space anchor at test:753 noted. |
| Q5 | **confirmed** | The pin (test:236-255) calls `_un_blocklist_tokens` directly; the wiring (test:224-225) is a one-line assignment that could be reverted to an inline shape-keyed grep without the function or the pin noticing. Static screening arms (test:299) feed no dot/`//` shapes, so spliced arms trip nothing today. The c S1 resolution claim "a drifting second copy cannot exist" is true for the function, overstated for the wiring. INFO as reported (reviewer probe + construction; not independently re-mutated). |
| Q6 | **confirmed** | Same substrate as X3 — writer stores `/home/<agent>/`, reader's dot gate refuses the `//` spelling at read time. Reader-stricter direction, pre-existing writer looseness, no wave claim falsified. INFO as reported. |

Verification notes beyond the findings:

- **Reviewer coverage-note correction (X axis):** the X report's coverage
  line says `/var/` "was already screened pre-wave via `/var/*`+empty glob" —
  that is wrong (there is no `/var/*` arm, deliberately, so `/var/www`
  stays processable). My pre-wave probe (`verify/prevar.sh`, verbatim
  818b860 arms) and the Q axis's own probe both show pre-wave `/var/` →
  OPS, which is exactly what c X1 reported and this wave fixed. No finding
  depends on the wrong aside — the monotonicity conclusion itself holds by
  arm structure (every `X` arm has an `X/*` sibling except the two bare
  arms the strip now covers) — recorded here so the aside is not cited
  later as evidence.
- **Landing audit spot-checks:** S-axis mechanism+pin line cites for all 7
  implemented c-findings re-checked against the shipped tree (sed at the
  cited ranges); parity token sets re-confirmed equal by the suite's own
  green parity pin at baseline.

## Retracted/ghost findings

None — all 13 reported findings verified against the code; two severity
adjustments (X1 MED → LOW, Q2 LOW → INFO, rationale in the verification
table) and one reviewer coverage-note correction (X axis pre-wave `/var/`
aside, see verification notes), neither affecting a finding.

## Run provenance

- Commission: maintainer, 2026-10-24 ("@opk-review-pass Review Snapshot d
  der aktuellen Branch"). Fourth snapshot of the case; rotation normal
  (this fresh session authored neither the c-wave's fixes nor any prior
  snapshot of the chain).
- Tree: 3de7f94 (feature/218-uninstall-revert-log-honesty), clean at
  fan-out (`git status --porcelain` empty), re-verified clean after all
  reviewers returned, and again after every verification mutation (all
  mutations ran in a scratch worktree outside the tree).
- Material: fix diff 818b860..3de7f94, shipped files only in 822e7a0:
  uninstall.sh 50 changed lines, test-uninstall.sh 194 (incl. context);
  f10a533/3de7f94 resolution.md bytes are bookkeeping, not review
  material. Wave parameters (~244-line diff, above the ~50-line micro
  bound): ~8-minute budgets, 3 axes.
- Host timestamps (main session, UTC): fan-out start
  2026-10-24T19:11:59Z; last reviewer return 19:23:41Z (q sandbox clock);
  host re-check after verification 19:29:06Z. Sandbox clocks within the
  host window (x/q stamped 19:13:07Z at launch — no skew anomaly).
- Reviewer subagents: 3 (cap 5 respected), fast tier
  zai-coding-plan/glm-5.3-flash, fresh contexts, axis prompts built from
  `.agents/skills/opk-review-pass/axis-prompt.md`; the main session
  (GLM-5.3) owned verification and embedded the reports.
- Checkpoints: `/tmp/opencode/pr-00243-d/checkpoints/{s,x,q}.md` (outside
  the reviewed tree), all three with launch + section stamps + return
  lines.
- Sabotage/mutation windows: none on the repo tree while reviewers ran
  (tree clean at return). Post-return verification mutations — X2
  comparator deletion and S1 `PARTIALLY` regex drop — ran in a scratch
  worktree `/tmp/opencode/pr-00243-d/sabotage-wt` (removed after; both
  mutations observed GREEN = the pin gaps they prove); reviewer probes
  under `/tmp/opencode/pr-00243-d/probe-{s,x,q}/`; main-session probes
  under `/tmp/opencode/pr-00243-d/verify/`.
- Gates at snapshot time (main session, this tree, before the snapshot
  commit): `sh tests/unit/test-uninstall.sh` green (also run at baseline
  before fan-out); `make test` green; `make lint` green;
  `sh tests/unit/test-docs.sh` green; `sh tests/unit/test-line-length.sh`
  green (review-* snapshots exempt from the ratchet — verbatim over
  wrap); INDEX regenerated with this commit
  (`python3 scripts/gen-review-index.py`); `sh tests/unit/test-reviews-lint.sh`
  and `sh tests/unit/test-reviews-parity.sh` green before the commit
  carrying this file.
- e2e: no new debt — this snapshot changes no shipped code; the reviewed
  fix wave already ran both suites in-wave (resolution Gates: `make e2e`
  309, `make e2e-rootless` 47 on `822e7a0`).

## Recommendation

The c-wave's fixes all landed (7/7 mechanisms with pins, audited and
spot-confirmed), and the two MED-class holes snapshot c named are closed
and behaviorally pinned. The round's own findings are one pin gap and a
cluster of smaller edges:

- **d X2 (MED)** is the actionable one: the once-stripped comparator —
  the load-bearing half of the agent-home guard — has no pin (suite green
  with it deleted, demonstrated). Trivially closable host-independently:
  extend the c Q1 arm to feed `/home/untest-agent/` alongside the bare
  form. **d S1 (LOW)** rides the same one-arm fix: add a fixture line
  that matches only `skipped` (and de-dominate `PARTIALLY`, e.g. a bare
  `PARTIALLY removed` line) so the family pin's claim becomes true.
- **d Q1 (LOW)** is the same site's third edge: the raw comparator arm is
  dead — either drop it or fix the comment; folding it into the X2/S1
  wave keeps one review round for all three.
- **d X1 (LOW)** records the whitespace residual against the rewritten
  "completed" comment: the recorded a X2 disposition stands (storage-
  format refusal, not a system-path refusal; no system tree reachable);
  the natural home for a mirror-or-scope decision is the #247 parity
  wave. **d X3/Q6 (INFO)** extend #247's and #245's shape lists.
- The remaining INFO batch (S2, S3, X4, Q2, Q3, Q4, Q5) is record-only
  or ride-along material for the next test-touching wave.

Per the stop rule (RM-0064/RM-0067): a next round that fixes X2/S1/Q1
touches test code — review-relevant — and owes one more wave review; a
round that dispositions everything deliberately-not-done leaves
review-relevant code untouched and closes the loop. The loop's state is
the maintainer's call — this session records, it does not close.
