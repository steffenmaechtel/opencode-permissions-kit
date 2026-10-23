<!-- review-meta
ID: pr-00235
Snapshot: b
Subject: a-wave fixes — skills pilot fix round (fix-wave review of 787c3b0, d77a446, b549a22)
Scope: wave
Base: ab0f771 (snapshot-a commit; a-wave tip 9cfef7f)
Diff: ab0f771..a234763
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (glm-5.3-flash; axes S/Q/X — X self-labeled B)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review b — a-wave fixes (fix-wave review)

Second snapshot of the case; commissioned by the maintainer over the
fix wave that implemented all 21 findings of review-a (commits
`787c3b0` tests, `d77a446` rules, `b549a22` skill/docs, plus the
resolution ledger at `a234763`). Wave scope per
agent/review-concept.md ("wave review — did the fixes break or lie?"),
three axes (mechanical sweep / quality / security+integration),
fan-out per "Parallel reviewer agents"; every reviewer finding
re-verified against the code by the main session before entering this
snapshot (verification marks below; one finding retracted as refuted).
Rotation: conformant — fresh session reviews the a-session's fixes
(session C per "Session rotation"; no deviation, so no CLEAN-verdict
re-verification mandate from RM-0110).

## Findings index (consolidated)

| ID | Severity | One-liner | Provenance | Verified |
|---|---|---|---|---|
| S1 | MED | Recorded class-sweep grep `grep 'RM-[0-9]{4}'` is inert (BRE `{4}` literal without `-E`) — the recorded sweep verifies nothing, and its recorded result doesn't match a corrected re-run | fix-induced | yes (sub-claim corrected) |
| S2 | LOW | Resolution claims "10 FAIL sites ↔ 14 pins"; code has 13 pin blocks (11 must-fire + 2 negative) — 14 not reproducible by any natural recount | fix-induced | yes (= Q1) |
| S3 | LOW | `opk-scan-err` fixture's own description text matches the workspace-`local/` pattern — the fixture trips the hit branch too, so the err path is never observed in isolation | fix-induced | yes |
| S4 | LOW | New `find … 2>/dev/null` in the `_scan` pipeline is a fail-soft spot with no pin executing find's failure path — an unreadable skill subdir silently drops out of the scan | wave-introduced | yes (= B2) |
| S5 | LOW | "(this README's peers)" in agent/conventions.md has no referent — no README exists in `agent/` | fix-induced | **RETRACTED — refuted** (agent/README.md exists) |
| Q1 | LOW | resolution.md claims 14 skills-lint pins; the suite has 13 | fix-induced | yes (= S2) |
| Q2 | LOW | RM-0116's new Check text overstates lane c: "greps the whole tree … exempting only" four items, but the helper also skips all scope files, four extensions only, and strips RM-9xxx | wave-introduced | yes (= B4) |
| Q3 | INFO | RM-0116 says the audit script "carries invariants 1–6 and 9" — the script also carries inv 7 (report-only) and inv 8 (INDEX regen) | wave-introduced | yes |
| Q4 | INFO | resolution Gates parenthetical "(tests, Makefile, workflows, markdown only)" — Makefile and workflows are not in the 15-file diff | fix-induced | yes |
| B1 | MED | Narrowed `local/` ERE misses `./local/`, `x/local/`, `x//local/`, `x/./local/`, absolute workspace paths — forbidden references pass silently | fix-induced | yes (probed) |
| B2 | LOW | `find`-stage failure is an unpinned fail-open: silenced stderr + unchecked rc ⇒ silent clean, contradicting the header's own "never a silent clean" | wave-introduced | yes (= S4) |
| B3 | LOW | Line-length frontmatter strip: any later `---` line "closes" the block — pseudo-close prose still stripped from the metric (S1 class half-fixed) | pre-existing, claim fix-induced | yes (probed) |
| B4 | LOW | RM-0116's new "greps the whole tree … exempting only …" overclaims: lane c's `--include` list is 4 types; real RM IDs sit in `internal/reviews-meta/**/*.json`, an unnamed de-facto exemption | fix-induced | yes (= Q2) |
| B5 | INFO | Lane-c shard regex exempts any living content under a shard-shaped path (subdirs, non-5-digit stems) — backstopped by reviews-lint rule 6 | wave-introduced | yes |
| B6 | INFO | `*hit:*`/`*err:*` sentinel globs can false-trigger on `:`-bearing paths; symlink-to-directory ⇒ "scan errored" collateral — both fail-loud only | wave-introduced | yes |

0 HIGH · 2 MED · 5 LOW · 4 INFO over 12 unique findings (15 reported;
S2↔Q1, S4↔B2, Q2↔B4 cross-corroborated pairs — dispositions may
merge; S5 retracted, see below). The X-axis prompt prescribed IDs
`X<NUMBER>`; the agent self-labeled `B1–B6` — preserved verbatim per
the immutability rule; this snapshot's scheme is S/Q/B, unique with no
collisions.

---

## Axis S — mechanical sweep (verbatim)

# Wave review — pr-00235 fix round, axis S (mechanical sweep: pin quality + class sweeps)

Material: `ab0f771..a234763` (15 files). All findings verified against HEAD; suites executed with TMPDIR confined to `/tmp/opencode/pr-00235-b/scratch-S/`.

## Findings index

| ID | Severity | Summary | Provenance |
|---|---|---|---|
| S1 | MED | Recorded class-sweep grep `grep 'RM-[0-9]{4}'` is inert (BRE `{4}` is literal without `-E`) — the sweep as recorded verifies nothing, and its recorded result doesn't match a corrected re-run | fix-induced |
| S2 | LOW | Resolution claims "10 FAIL sites ↔ 14 pins"; code has 13 pin blocks (11 must-fire + 2 negative) — the 14 is not reproducible by any natural recount | fix-induced |
| S3 | LOW | `opk-scan-err` fixture's own description text matches the workspace-`local/` pattern — the fixture trips the hit branch too, so the err path is never observed in isolation | fix-induced |
| S4 | LOW | New `find … 2>/dev/null` in the `_scan` pipeline is a fail-soft spot with no pin executing find's failure path — an unreadable skill subdir silently drops out of the scan (silent clean) | wave-introduced |
| S5 | LOW | "(this README's peers)" in agent/conventions.md has no referent — no README exists in `agent/` | fix-induced |

## Detail

**S1 — MED. Inert recorded class-sweep grep; recorded result not reproducible.**
`internal/reviews/0/0/2/3/pr-00235/resolution.md:166-167`:
```
- RM-ID citations in wave-added text: `git diff caeb9a8..9cfef7f |
  grep '^+' | grep 'RM-[0-9]{4}'` → only the two README lines (fixed);
```
`{4}` is a literal in POSIX BRE; only `\{4\}` or `-E` make it an interval. Verified: `printf 'RM-0044\n' | grep 'RM-[0-9]{4}'` → no match, rc 1; with `-E` it matches. So the recorded pipeline outputs nothing and cannot have produced the claimed "only the two README lines". A corrected re-run over the same range adds further hits the record omits: three ref-form IDs in `.agents/skills/opk-review-pass/SKILL.md` (`(RM-0116)`, `(RM-0078)`, `(RM-0083)` — since removed by this wave) plus meta-internal lines. Why it matters: `agent/learnings.md` requires sweeps to "record the grep pattern and sites checked" precisely so they are re-runnable; this record is both inert and inaccurate. Impact bounded — I re-ran the sweep with a working pattern and lane c is green at HEAD (SKILL.md ID-free, `internal/reviews/README.md` citations replaced by file+section refs), so the sweep's conclusion holds; the evidence line is what's broken.

**S2 — LOW. Pin count off by one against the code.**
`resolution.md:13` ("10 FAIL sites, 14 pins; fixtures for root/open/close/>400") and `resolution.md:163` ("10 sites ↔ 14 pins (incl. 2 negative)"). Recount at HEAD: `tests/unit/test-skills-lint.sh` has 10 `echo "FAIL` sites (lines 59, 65, 69, 76, 78, 84, 88, 92, 110, 113) — correct — but 13 pin case-blocks: 12 on `_out` (lines 216–263) plus the `_out2` missing-root invocation (264–268); 2 of the 13 are negative (256–259, 260–263). No natural count yields 14 (12 fixtures-with-SKILL.md + root-absent = 13 also fails). Coverage itself is complete — every one of the 10 sites has an executing fixture, all before the summary gate (line 274) — so this is ledger accuracy only.

**S3 — LOW. Scan-err fixture is not minimal: it also trips the hit branch.**
`tests/unit/test-skills-lint.sh:209` — `description: Fixture whose local/ scan hits an unreadable path.` The substring "whose local/ scan" matches the new pattern `(^|[^.[:alnum:]_/-])local/|\.\./local/` (line 104; space before `local/` — verified empirically). So during the pin run, `opk-scan-err` emits both `FAIL … references local/` and `FAIL … local/ scan errored`. The err pin (lines 252–255) still discriminates — it asserts the err string specifically, so an err→hit misclassification reddens it — but the fixture exercises two failure paths at once and the grep-rc-2 path is only ever observed co-occurring with a hit. Rename or reword the fixture text to avoid the self-match.

**S4 — LOW. Unpinned fail-soft: `find` errors silenced in the new scan.**
`tests/unit/test-skills-lint.sh:102`:
```
_scan=$(find "$_d" \( -type f -o -type l \) -print 2>/dev/null \
```
find's rc is never checked and its stderr is discarded. If a real-tree skill directory contains an unreadable subdirectory, find drops those entries (rc > 0, silently) and the scan reports clean — the exact "silent clean" class the X2 fix claims to close (`resolution.md` X2; header comment `test-skills-lint.sh:37-38`). The grep `2>/dev/null` on line 104 is pinned via the dangling-symlink fixture; find's failure path has no pin. Realistic trigger: a root-owned/0700 stray directory under `.agents/skills/<skill>/`. Per `agent/learnings.md` ("every new stderr redirect … gets a pin that executes the failure path"). Severity LOW because the tree is house-owned and the state is unusual; conditions named.

**S5 — LOW. Dangling referent in the rewritten rule unit.**
`agent/conventions.md:231-232` (b549a22):
```
  count; living files under `internal/reviews/` (this README's peers)
  do not. (RM-0116)
```
`agent/` contains no README; "this README" cannot resolve from conventions.md. The antecedent is the reviews README, which `internal/rules-meta/0/1/1/RM-0116.md` phrases correctly as "(the README)". The inv5 quote needle ("Every RM key appears exactly") is intact and the real-tree audit is green; this is a wording defect in the fix text only.

## Coverage

- **Executed**: all three touched suites green (`skills-lint`, `line-length` incl. probe, `rules-meta` "23 pins green"); sandbox-policy green; full 42-suite loop: 41 green, `tests/unit/test-status.sh` red (1 test, #221 area) — that file and its subject are untouched by the wave diff; attribution deferred (a pre-wave run would need a worktree, which would write into `repo/.git` — out of bounds for a reader).
- **Numeric claims recounted**: 10 FAIL sites ✓; 14 pins ✗ (13 — S2); 4 probe fixtures ✓; 35-entry baseline no-op ✓ (regen reproduced byte-identical in scratch); 117 scoped `.md` files open with `---`, 0 unclosed ✓; 23 pins / 21→23 ✓; 391-byte skill description ✓; "8 sabotage runs red" = narrative only — arithmetic of the listed breakdown (S1,S2,S3,X2,X4,Q8,Q4×2) is consistent, the runs themselves are not re-executable from code.
- **Verified clean otherwise**: every pin asserts lint/audit *output*, not fixture construction; all pins sit before their suite's summary gate; both negative pins can fire (sabotage-recorded directions match the code shapes); the runtime-concatenated demo ID (`test-rules-meta.sh:339`) is load-bearing and works (real-tree lane c green); ACTIVE_SECTIONS registration matches the n1c pin's slug; closure pre-check and strip logic agree in all edge cases probed; Q7's "9 of 42 red" is the documented fresh-clone state (`CONTRIBUTING.md:270-282`), not a contradiction of the green-gates claim.
- **Deferred, not hidden**: Q6's loader-source citations (v2.1.4 `skill-file.ts`, v1.18.x bare-continue) not re-verified — the workspace clone is pinned at v1.18.15 and the claim is header-comment only; e2e suites not run (no `files/` or root-run script semantics in the diff — agrees with the resolution's gate).

Checkpoints written to `/tmp/opencode/pr-00235-b/checkpoints/checkpoint-S.md` (one line per section, launch + return).

## Axis Q — quality (verbatim)

# Review Q — quality axis (claim-vs-behavior drift), wave `ab0f771..a234763`

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| Q1 | LOW | resolution.md claims 14 skills-lint pins; the suite has 13 | fix-induced |
| Q2 | LOW | RM-0116's new Check text overstates lane c: "greps the whole tree … exempting only" four items, but the helper also skips all scope files, four extensions only, and strips RM-9xxx | wave-introduced |
| Q3 | INFO | RM-0116 says the audit script "carries invariants 1–6 and 9" — the script also carries inv 7 (report-only) and inv 8 (INDEX regen) | wave-introduced |
| Q4 | INFO | resolution Gates parenthetical "(tests, Makefile, workflows, markdown only)" — Makefile and workflows are not in the 15-file diff | fix-induced |

## Details

### Q1 (LOW) — "14 pins" overstated; actual 13
`internal/reviews/0/0/2/3/pr-00235/resolution.md:13` — "10 FAIL sites, 14 pins; fixtures for root/open/close/>400" and `resolution.md:163` — "FAIL-site inventory (skills lint): 10 sites ↔ 14 pins (incl. 2 negative)".
Measured at HEAD: `grep -c 'PIN BROKEN' tests/unit/test-skills-lint.sh` = **13**; the suite run emits exactly 13 `pin ok` lines (11 positive + 2 negative: opk-legit-paths, opk-good-skill). The *10 FAIL sites* half of the claim is correct (10 `echo "FAIL` sites inside `lint_skills`, lines 59–113; the line-275 `FAIL skills lint:` is the summary gate). Only the pin count is off by one.
Why it matters: this is the ledger's own evidence for the S2 class sweep; a wave reviewer re-counting pins to verify the sweep finds 13, suspects a missing/mutated pin, and burns verification budget on a phantom discrepancy. No code impact.

### Q2 (LOW) — lane-c description in RM-0116 promises more than lane c does
`internal/rules-meta/0/1/1/RM-0116.md:27-28` — "lane c greps the whole tree and fails on any real ID outside a rule unit's trailing ref, exempting only `internal/rules-meta/` itself, the generated review indexes …, the frozen case folders … and `internal/records/_archive/`".
The helper (`tests/unit/test-rules-meta.sh:303-314`) additionally: (a) skips every `SCOPE_FILES` entry outright (`case " $2 " in *" $_rel "*) continue ;;`, line 314) — those are lane a's jurisdiction; (b) greps only `*.md *.sh *.py *.yml` (line 305), not "the whole tree"; (c) strips `RM-9xxx` demo IDs. Realistic trigger: an agent writes a bare `RM-0108` mid-prose in `agent/conventions.md` (a scope file) and consults RM-0116's Check text — lane c stays green, contradicting the sentence; only lane a fires. Note the pre-wave rule text explicitly acknowledged "outside internal/rules-meta and the SCOPE_FILES"; the rewrite dropped that acknowledgment while asserting an exhaustive "exempting only" list. Enforcement overall is intact (lane a does catch scope files — verified in the lane-a block); the drift is in the rule's own description of which lane delivers it.

### Q3 (INFO) — "carries invariants 1–6 and 9" vs the script's actual inventory
`internal/rules-meta/0/1/1/RM-0116.md:16` — "the audit script itself carries invariants 1–6 and 9". `scripts/rules-audit.sh:213` — "(invariants 3b, 4, 5, 6, 7, 9 …)", `:244` — "# 7: overdue (report-only)", `:301` — "# 8: INDEX regeneration". The script carries 1–9; 1–6 and 9 is the *blocking* set, which is how the canonical file phrases it ("CI blocks on 1–6 and 9", `internal/records/rules-meta.md`). Given Q2's whole point was a precise enforcement citation, "carries" re-introduces a smaller version of the same imprecision. Conditions: matters only for a reader auditing the script's contents rather than its blocking behavior.

### Q4 (INFO) — Gates parenthetical names untouched file classes
`internal/reviews/0/0/2/3/pr-00235/resolution.md:183` — "the wave and its fixes touch no `files/` script and no root-run script semantics (tests, Makefile, workflows, markdown only)". The 15-file diff contains tests, markdown, and `scripts/rules-audit.sh` — no Makefile, no workflows. The e2e-not-owed conclusion itself stands (nothing in `files/`, no root-run semantics; rules-audit.sh is a repo tool, not root-run). Consequence-free prose slip in the ledger.

## Verified clean (claims that held)

- **S1/S4/X4**: closure pre-check in `measure_file`, awk `NR<c` field extraction, probe3 unclosed fixture, opk-body-field pin — all present and green at HEAD (`test-line-length.sh`, `test-skills-lint.sh` run green).
- **S2**: 10 FAIL sites confirmed; all exercised. S3: pattern and both-direction pins green.
- **Q2/Q3/Q8**: Check commands run as written — `sh scripts/rules-audit.sh` → "0 blocking violations" rc 0; `sh tests/unit/test-rules-meta.sh` → "OK (23 pins green)"; 21→23 pin claim exact; "21 pins" appears only under frozen case folders; ACTIVE_SECTIONS line registered and load-bearing (n1c present); RM-0116 quote needle "Every RM key appears exactly twice" still verbatim in the rewritten conventions bullet (audit green).
- **Consistency pairs**: Q1 (reviews/README "Snapshot format" micro bullet + SKILL.md 6.1; practice confirmed — pr-00222 review-b: "Subject: micro-wave review …" / "Scope: wave"); Q5 three sabotage windows on both sides; Q9 AGENTS.md ↔ review-concept.md ↔ RM-0108 all "5 / any tier / account-wide"; Q10 both maps updated, plain text; X5 checkpoint base in SKILL.md + review-concept, "reviews lint rule 6" exists (`test-reviews-lint.sh` "# 6. no stray files inside the case folder").
- **Header claims**: X3 `wc -c` + 391 B measured exactly; X2 per-file `find -type l` + rc>1→FAIL as documented; Q6 verified against the pinned clones — `github/opencode-1x` @ v1.18.35 `packages/core/src/skill.ts` bare `continue`, no log; `github/opencode-2x` @ v2.1.4 `skill-file.ts` `Skipped` tags; Q11 no-op re-verified by measurement (no scoped md file carries >120 frontmatter lines); Q7's nine names map to nine real suites; 42 suites total; INDEX row `open` is exactly what `gen-review-index.py status()` yields (resolution.md carries no `Status:` field).
- **Numbers re-measured, all matching**: 35 baseline entries, 117 scoped `.md` files opening with `---`, 26 INDEX cases, 23 rules-meta pins.
- **Gates re-run**: all six remaining named suites (docs, reviews-lint, reviews-parity, reviews-meta-aggregate, rules-index-parity, rules-revisit) plus `make lint` green.

## Coverage

Covered: all 21 resolution rows against the tree at HEAD; both RM-0116 Check commands run verbatim; all five test/header-claim numbers re-measured; all five consistency pairs on both sides; every new factual sentence in the seven non-test doc files plus resolution.md Evidence/Class-sweeps/Gates; full diffs read for unintentional behavior changes (none found beyond the intended Q4 lane-c narrowing and S1/S3 metric changes). Deferred, recorded: (1) Q7's claim that exactly those nine suites run red on the sparse machine — verifying requires stripping house files, forbidden under my read-only mandate; suite existence and the 9/42 counts are verified, the red property is not; (2) the ledger's 8 sabotage runs not re-executed (shared read substrate; verified instead that every named pin exists and runs green); (3) X2's "uid-independent" is reasoned from the per-file operand shape, not tested under a second uid. Workspace-side observation, not a repo finding: the on-disk clone is `github/opencode-1x` at v1.18.35 while the workspace AGENTS.md names `opencode`/v1.18.15 — already flagged in the resolution's own Follow-ups for the maintainer.

## Axis B — security & integration (verbatim; axis self-labeled B)

Workspace AGENTS.md change noted (read-only reference rename, outside the reviewed tree — no impact on findings). Synthesis follows; checkpoints are already on disk.

# Review b — security/robustness axis, wave `ab0f771..a234763`

## Findings index

| ID | Sev | One-liner | Provenance |
|---|---|---|---|
| B1 | MED | Narrowed `local/` ERE misses `./local/`, `x/local/`, `x//local/`, `x/./local/`, absolute workspace paths — forbidden references pass silently | fix-induced |
| B2 | LOW | `find`-stage failure is an unpinned fail-open: silenced stderr + unchecked rc ⇒ silent clean, contradicting the header's own "never a silent clean" | wave-introduced |
| B3 | LOW | Line-length frontmatter strip: any later `---` line "closes" the block — pseudo-close prose still stripped from the metric (S1 class half-fixed) | pre-existing, claim fix-induced |
| B4 | LOW | RM-0116's new "greps the whole tree … exempting only …" overclaims: lane c's `--include` list is 4 types; real RM IDs sit in `internal/reviews-meta/**/*.json`, an unnamed de-facto exemption | fix-induced |
| B5 | INFO | Lane-c shard regex exempts any living content under a shard-shaped path (subdirs, non-5-digit stems) — backstopped by reviews-lint rule 6 | wave-introduced |
| B6 | INFO | `*hit:*`/`*err:*` sentinel globs can false-trigger on `:`-bearing paths; symlink-to-directory ⇒ "scan errored" collateral — both fail-loud only | wave-introduced |

## Detail

### B1 (MED) — `local/` ERE soft-miss shapes
`tests/unit/test-skills-lint.sh:104`:
```sh
grep -qE '(^|[^.[:alnum:]_/-])local/|\.\./local/' "$_p" 2>/dev/null
```
The excluded-predecessor class bars `.` and `/`, and the only alternative is the literal `\.\./local/`. Probed with GNU grep -E against the exact pattern — **missed**: `./local/`, `x/local/`, `x//local/`, `x/./local/`, `.././local/`, `x/local//y`, and the absolute workspace path `/var/www/vhosts/opencode-permissions-kit/local/notes.md`. **Caught**: line-start `local/`, `../local/`, backtick/paren/space-prefixed; intended exemptions (`~/.local/`, `/usr/local/`, `opencode-local/`, `.local/`, `foo.local/`) hold. Realistic trigger: prose writing `./local/foo` (session CWD is the workspace root) or an absolute path into the disposable workspace. The fixtures (`opk-local-ref`, `opk-legit-paths`, test-skills-lint.sh:159, 194–195) pin only the two caught shapes; the house blind-spot rule (agent/review-concept.md "Parallel reviewer agents": path gates tested against `x/`, `x//`, `x/.` forms, applied via SKILL.md step 3) is not satisfied for this gate — `x//local/` and `x/./local/` both escape. The old plain `local/` pattern caught all of these; the narrowing traded them away without a compensating alternative.

### B2 (LOW) — unpinned find-stage fail-open
`tests/unit/test-skills-lint.sh:102–108`:
```sh
_scan=$(find "$_d" \( -type f -o -type l \) -print 2>/dev/null \
    | while IFS= read -r _p; do
          grep -qE '...' "$_p" 2>/dev/null
```
The X2 fix pins grep rc>1 (`err:` → FAIL, fixture `opk-scan-err`), but `find`'s stderr is discarded and its rc is never observed: an unreadable subdirectory under a skill dir makes its files invisible to `find`, `_scan` comes back without `hit:`/`err:`, and the local/ scan passes clean. Header lines 37–38 promise "a scan ERROR (grep rc 2, e.g. a dangling or unreadable path) is a FAIL too, never a silent clean" — true for the grep stage, false for the find stage, and no fixture executes the find-error path. Trigger: a mode-000 subdir under a skill run as non-root (CI is non-root). Bounded: the same skill's frontmatter checks usually still FAIL loudly, so the suite rarely stays fully green. Severity LOW because the trigger needs unusual modes; the failure direction is exactly the silent-clean class X2 claimed closed.

### B3 (LOW) — pseudo-close still strips prose from the line-length metric
`tests/unit/test-line-length.sh:113–115`:
```awk
ok && $0 == "---" { found = 1; exit }
END { exit !found }' "$_mf" && _strip=1
```
Closure is "some later line equals `---`" — no YAML validity. A markdown file opening with a horizontal rule (line 1 `---`) that contains another `---` line before a >120-char line (second hr, or `---` inside a fenced code block) has the whole span stripped from the metric as "frontmatter". S1's unclosed direction is fixed (probe3 verifies it); the pseudo-close direction — the same "strips too much" fail-soft class S1 flagged — has no probe fixture. Trigger needs the specific layout, and the frozen baseline limits drift; hence LOW. The shape itself is pre-existing (the old unconditional strip had the same pseudo-close behavior); what is new is the resolution's class-sweep claim ("Frontmatter-strip directions … both failure directions pinned") while only the unclosed half is pinned.

### B4 (LOW) — RM-0116 Check text overclaims lane-c coverage
`internal/rules-meta/0/1/1/RM-0116.md:27–31`: "Pin 10 lane c greps the whole tree and fails on any real ID outside a rule unit's trailing ref, exempting only …". But `tests/unit/test-rules-meta.sh:304–305`:
```sh
grep -rn "RM-[0-9][0-9][0-9][0-9][0-9]" \
    --include="*.md" --include="*.sh" --include="*.py" --include="*.yml" \
```
`*.json` is not included, and real RM IDs exist outside the four named exemptions: `internal/reviews-meta/2026-10-22/data/b7.json` carries RM-0060, RM-0064, RM-0077, RM-0084 (verified). So lane c neither greps "the whole tree" nor exempts "only" the named sets — the frozen reviews-meta JSON corpus is an unnamed fifth exemption, and any future RM ID in `json`/`jsonc`/`txt` is invisible. This sentence was rewritten in this wave as the Q2–Q4 accuracy fix and re-introduces the exact rule-text-vs-enforcement-mismatch class it was fixing. The enforcement shape is pre-existing (the include list is carried over verbatim into the new helper); the inaccurate claim is fix-induced.

### B5 (INFO) — lane-c shard exemption is substring-wide; backstops hold
`tests/unit/test-rules-meta.sh:311`: `grep -v -E "/internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-[0-9]+/"` exempts any line whose path contains a shard prefix — including living files under `pr-00235/<extra>/` and non-5-digit stems (`pr-9/`). Probed both directions: `pr-00235x/` is correctly NOT exempt (loud), living `internal/reviews/README.md` caught, frozen snapshots exempt. The false-exempt shapes are backstopped: reviews-lint rule 6 (`test-reviews-lint.sh:88–93`, `for f in "$d"/*`) flags any non-`review-*.md`/`resolution.md` entry including directories, and the shard-naming pin enforces `pr-NNNNN`. `resolution.md` Follow-ups already records the regex↔shard-rule coupling. Defense-in-depth note only.

### B6 (INFO) — sentinel globs and symlink collateral (fail-loud only)
`tests/unit/test-skills-lint.sh:106–113`: `case "$_scan" in *hit:*)` matches the sentinel anywhere in concatenated path text — a listed path containing `hit:`/`err:` (colon is legal in filenames) false-triggers a FAIL. Also, a symlink-to-directory inside a skill dir is listed by `-type l` and grep returns rc 2 on it → "local/ scan errored" FAIL, though the header frames `err:` as "dangling or unreadable path". Both directions are fail-LOUD (false positives, never silent passes); no realistic trigger in the current single-skill tree.

## Coverage

**Covered**: full 921-line diff read; `lint_skills` and its 14 pins at HEAD (find precedence — no third predicate joins the disjunction, rc propagation to the `[ -s "$TMP" ]` gate, stderr capture at line 272); `local/` ERE probed both directions with the exact pattern; awk close/extraction edge shapes probed (CRLF, trailing-space `---`, `----`, empty frontmatter, double spaces, tab-prefixed keys, literal/duplicate `description:` — all fail loud or harmless); `wc -c` bound and POSIX portability of the new constructs (`seq` is the only non-POSIX construct, pre-existing pattern, Linux-only CI consistent with house practice); lane-c helper probed for false-exempt and false-catch shapes incl. `x/`-style shard forms; reviews-lint rule 6 read as the backstop; RM-0116 invariant claim verified against `scripts/rules-audit.sh` header (1–6+9 blocking, 7/8 report-only — accurate); all five touched suites executed green at `a234763` in-sandbox (TMPDIR confined to my scratch). **Deferred**: the sparse-machine "9 of 42 red" claim (42 verified; the red state is not reproducible on this full tree); the line-length baseline-regen "no-op" claim (would require `--regen`, a repo write); duplicate-`description:` loader semantics (unverified against the pinned opencode loader — hypothetical); pre-existing and unchanged lane-c `2>/dev/null` and binary-file grep drop (inherited verbatim into the helper, no wave behavior change); INDEX status `open` for pr-00235 (generator-produced, parity green, no house rule sets the expected value).

## Retracted / ghost findings

- **S5 (LOW) — RETRACTED, refuted during main-session verification.**
  The claim "`agent/` contains no README; 'this README' cannot resolve"
  is false: `agent/README.md` exists and is tracked since commit
  `1e1fdc3` (restructure wave, well before this case) —
  `git ls-files agent/` lists README.md alongside the four rule files.
  The phrase "this README's peers" occurs exactly once in the tree
  (conventions.md:232); the intended referent (the reviews README,
  phrased "(the README)" in RM-0116's own text) is inferable. A
  residual demonstrative ambiguity ("this" from conventions.md could
  misbind to agent/README.md) is a wording suggestion, not a finding —
  no house rule forbids the phrasing (axis contract: unsourced style
  observations are suggestions). Recorded here so the next unverified
  "no referent" claim is read with this calibration in mind.

## Verification (main session)

Every finding re-verified against the tree at `a234763` before
entering this snapshot; evidence highlights:

- **B1** — ERE probes re-run against the exact pattern: caught
  `local/x`, `../local/x`, space/paren/backtick-prefixed; missed
  `./local/x`, `x/local/y`, `x//local/y`, `x/./local/y`, and
  `/var/www/vhosts/opencode-permissions-kit/local/notes.md`;
  exemptions hold (`/usr/local/`, `~/.local/`, `opencode-local/`,
  `.local/`, `foo.local/`). Fixtures at test-skills-lint.sh:159
  (caught shapes) and :194-195 (exempt shapes) pin no miss-direction
  shape. MED upheld: soft-miss direction in the guard whose sole job
  is the workspace-`local/` rule, with two realistic shapes
  (`./local/` from a workspace-root CWD; an absolute path into the
  workspace's `local/`). The header at :35-36 documents exactly the
  two matched shapes — honest doc, incomplete guard.
- **S1** — BRE inertness confirmed: `printf 'RM-0044\n' | grep
  'RM-[0-9]{4}'` → rc 1 (no match); the recorded pipeline re-run over
  `caeb9a8..9cfef7f` outputs 0 lines — it cannot have produced the
  recorded "only the two README lines". **Sub-claim corrected:** the
  reviewer attributes the extra `-E` hits to SKILL.md ("since removed
  by this wave") — wrong locus: SKILL.md carried 0 RM IDs already at
  `9cfef7f` (`git show 9cfef7f:.agents/skills/opk-review-pass/SKILL.md
  | grep -oE 'RM-[0-9]{4}'` → empty). The corrected `-E` re-run
  yields exactly the two reviews-README lines (snapshot a's Q4:
  `(RM-0116)` at :67, `(RM-0078)`/`(RM-0083)` at :71) plus
  meta-internal diff noise (`+++ b/…RM-*.md`, `id: RM-0116`, INDEX
  row). The finding's core (inert recorded pattern; record not
  re-runnable as written) stands.
- **S2/Q1** — recounted two ways: `grep -c 'PIN BROKEN'
  tests/unit/test-skills-lint.sh` = 13; a live suite run emits 13
  `pin ok` lines; the 13 case-blocks enumerated at :217, :221, :225,
  :229, :233, :237, :241, :245, :249, :253, :257, :261, :266 (the two
  negative at :257/:261). Resolution's "14 pins" appears at :13 and
  :163. Coverage complete (all 10 FAIL sites executed), so the delta
  is ledger accuracy, as reported.
- **S3** — fixture description at :209 self-matches the pattern
  (probe: `grep -cE` on the exact description string → 1); the two
  separate `case` statements at :109-111/:112-114 confirm both FAILs
  co-fire; the err pin at :253 asserts the err string specifically —
  discriminates, fixture non-minimal, as reported.
- **S4/B2** — `find … -print 2>/dev/null` at :102 confirmed; rc
  unobserved; the only error fixture is the dangling symlink (:213),
  which pins the grep stage. Header :37-38 promise scoped to grep
  rc 2. No find-stage pin exists.
- **Q2/B4** — helper read at test-rules-meta.sh:303-321: include
  list `*.md *.sh *.py *.yml` (:305), SCOPE_FILES skip (:314-316),
  RM-9xxx strip (:317); the four named exemptions otherwise match the
  rule text. json invisibility confirmed:
  `internal/reviews-meta/2026-10-22/data/b7.json` carries RM-0060,
  RM-0064, RM-0077, RM-0084. RM-0116:27-32 sentence verified
  verbatim. Same finding from two axes — merged.
- **Q3** — rules-audit.sh header :27 names invariants 7 and 8; :244
  "# 7: overdue (report-only)". RM-0116:16 says "carries invariants
  1–6 and 9". Script carries 1–9, blocks on 1–6+9 — imprecision
  confirmed (INFO).
- **Q4** — the 15-file diff contains tests, markdown, and
  scripts/rules-audit.sh; no Makefile, no workflows. resolution.md:183
  parenthetical wrong; the e2e-not-owed conclusion stands.
- **B3** — probed with the real `measure_file` (extracted verbatim)
  on `---` / >120 prose / `---` / >120 prose: output `pseudo.md 10 1`
  — the first >120 line is silently stripped while the second counts:
  the pseudo-close direction is real and unpinned; the probe header
  (:141-148) claims both fail-soft directions covered.
- **B5** — shard regex :309 confirmed substring-wide; reviews-lint
  rule 6 (`for f in "$d"/*` + allowlist) flags any stray entry
  including directories — backstop holds.
- **B6** — sentinel printf/case shapes confirmed at :106-113; both
  directions fail-loud; no realistic trigger today.
- **S5** — refuted; see Retracted/ghost above.
- **Reviewer-S environmental note** — S's full-suite loop reported
  `test-status.sh` red; main-session re-run at HEAD: rc 0, all status
  tests pass (log kept at /tmp/opencode/pr-00235-b/gates/). Attributed
  to the reviewer's TMPDIR-confined sandbox, not the tree — recorded
  so no unexplained red suite stands.

## Run provenance

- Host: opencode kit-managed session (user `opencode`), WSL2,
  checkout `/var/www/vhosts/opencode-permissions-kit/repo`, branch
  `feature/agents-skills-pilot`, tree `a234763` clean; no opencode
  binary on the agent PATH (version unrecorded). Header date is the
  host-local date; all timestamps below are host UTC.
- Fan-out: 3 reviewer subagents (fresh contexts, provider fast tier
  `zai-coding-plan/glm-5.3-flash`), launched concurrently ≤ 5-cap.
  HOST timestamps: fan-out start 2026-10-23T22:55:38Z, all returned
  by 2026-10-23T23:09:11Z.
- Per-agent windows (checkpoint files; sandbox clocks — observed skew
  ≈ +2h vs host UTC, same as snapshot a, normalized): final
  checkpoint writes at sandbox 01:05–01:06 ≈ 23:05–23:06Z host.
  Checkpoint side files:
  /tmp/opencode/pr-00235-b/checkpoints/checkpoint-{S,Q,X}.md (outside
  the case folder per skill choreography and reviews lint rule 6;
  content absorbed here).
- Sabotage/mutation windows vs readers: none. Main-session actions
  pre-launch and during the fan-out were read-only (suite runs with
  scratch output under /tmp/opencode/pr-00235-b/, git reads, ERE/BRE
  probes in /tmp scratch); `git status --porcelain` verified empty
  before launch, after the pre-launch gates, and after all readers
  returned. Reviewers wrote only under /tmp/opencode/pr-00235-b/.
- Gates run at HEAD a234763 by the main session (all green):
  test-skills-lint, test-line-length, test-rules-meta,
  test-reviews-lint, test-reviews-parity, test-docs,
  test-status (re-run), scripts/rules-audit.sh (0 blocking
  violations), check-host pre-flight. Reviewer S and Q independently
  re-ran the touched suites plus the remaining named suites green
  (Q additionally `make lint`). E2e suites: not owed by this round
  (no `files/`, no root-run script semantics — the Q4 parenthetical
  aside).
- Calibration: single snapshot (wave scope — no second-snapshot
  redundancy owed); skill-led house pass, `Skills: opk-review-pass`
  recorded in the header per RM-0083/reviews-README. Axis-letter
  deviation (X self-labeled B) disclosed in the findings index.
- Environment note: reviewer Q re-verified the loader-lane claims
  against the workspace upstream clones (github/opencode-1x @
  v1.18.35, github/opencode-2x @ v2.1.4) — read-only reference clones
  outside this repo; the workspace-level AGENTS.md 1.18.15 pin
  mismatch stays a maintainer follow-up (resolution, Follow-ups).

## Recommendation

No HIGH findings. The wave's core deliverables verified sound: all 21
a-findings' mechanisms are present and green at HEAD (both quality-
and sweep-axis clean lists corroborate; every pin discriminates and
sits before its summary gate; both RM-0116 Check commands run green
as written). The 2 MED findings are new and both fix-induced, cheap
to disposition: **B1** — the narrowed `local/` ERE traded away
`./`-relative and absolute workspace shapes (soft-miss direction,
unpinned; the a-S3/X1 fix over-corrected), and **S1** — the
resolution's recorded RM-ID sweep grep is inert as written (BRE),
so the class-sweep evidence is not re-runnable. The LOW cluster is
ledger/fixture hygiene (S2/Q1 pin count, S3 fixture minimality,
S4/B2 find-stage pin) plus one rule sentence (Q2/B4: RM-0116's
"whole tree … exempting only" should lose both overstatements) and
one unpinned probe direction (B3 pseudo-close). INFO items are
record-keeping. Expectation, not closure: fixes for B1 and S4/B2
will touch test code — review-relevant per RM-0065 — so the next
round owes a (likely micro) wave review; the stop rule is checked by
the next round or the maintainer, not here. Dispositions are the
maintainer's call.
