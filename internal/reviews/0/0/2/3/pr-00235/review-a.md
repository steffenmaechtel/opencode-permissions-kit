<!-- review-meta
ID: pr-00235
Snapshot: a
Subject: agent-skills pilot — opk-review-pass skill + lint/test wiring, issue #178 (feature wave)
Scope: wave
Base: master @ caeb9a8 (VERSION 0.0.56)
Diff: caeb9a8..9cfef7f
Date: 2026-10-23
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 3 fresh-context reviewer subagents (axes S1/Q1/X1)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review a — agent-skills pilot wave (issue #178)

First snapshot of the case; commissioned by the maintainer over PR
#235 (branch `feature/agents-skills-pilot`, 10 commits, 18 files,
~748 insertions over master @ caeb9a8). Wave scope, three axes
(mechanical sweep / quality / security+integration), fan-out per
agent/review-concept.md "Parallel reviewer agents"; every finding
re-verified against the code by the main session before entering this
snapshot (verification marks in the house section below).

## Findings index (consolidated)

| ID | Severity | One-liner | Provenance | Verified |
|---|---|---|---|---|
| S1 | MED | measure_file exempts the WHOLE file when frontmatter never closes — fail-soft, unprobed, unguarded | wave-introduced | yes |
| S2 | MED | 4 of 9 FAIL branches in test-skills-lint.sh never execute in any fixture, incl. the lint's core open/close checks | wave-introduced | yes (one sub-claim corrected) |
| S3 | LOW | `local/` grep over-matches legit `~/.local/` XDG paths → false FAIL | wave-introduced | yes |
| S4 | LOW | sed `2,20p` head-window: frontmatter >19 lines → false "never closes" FAIL | wave-introduced | yes |
| Q1 | MED | Skill's `micro` scope keyword has no legal snapshot `Scope:` value — mapping undefined anywhere; lint doesn't validate Scope | wave-introduced | yes |
| Q2 | MED | RM-0116 attributes the closed-world check to "scripts/rules-audit.sh, invariant 10" — no invariant 10 exists in that script or the documented list | wave-introduced | yes |
| Q3 | MED | RM-0116's own Check command fails as written on the shipped tree; "exactly twice in the living tree" overstates the enforced scope | wave-introduced | yes |
| Q4 | MED | Wave's own new text cites `(RM-0078)`/`(RM-0083)` by ID — the exact pattern RM-0116 forbids; audit-invisible only via an unnamed exclusion | wave-introduced | yes |
| Q5 | LOW | SKILL.md drops RM-0111's third sabotage window ("in a scratch worktree") | wave-introduced | yes |
| Q6 | LOW | test-skills-lint cites "the pinned opencode source" for 2.x-only artifacts; the 1.x pin has no `SkillFile`/`Skipped`/debug log | wave-introduced | yes |
| Q7 | LOW | Sparse-machine red list omits `test-reviews-meta-aggregate` (verified red empirically); all 8 claimed suites verified red, none stays green | wave-introduced | yes (re-run by main session) |
| Q8 | LOW | New rule-carrying conventions section not registered in `ACTIVE_SECTIONS` — every sibling rule section is; invariant 1 won't guard future units there | wave-introduced | yes |
| Q9 | INFO | Pre-existing: AGENTS.md says review cap is "5 per tier"; RM-0108 says 5 concurrent on ANY tier (account-wide) | pre-existing | yes |
| Q10 | INFO | `.agents/` added as tracked internal area but missing from AGENTS.md Layout and docs/README.md "Internal documentation" map | wave-introduced | yes |
| Q11 | INFO | line-length header claims "baseline was regenerated for the metric switches" — wave's baseline diff is empty (no-op regen) | wave-introduced | yes |
| X1 | LOW | `local/` lint pattern matches `/usr/local/…` and `~/.local/…` — false-positive direction; rule forbids only workspace `local/` references | wave-introduced | yes |
| X2 | INFO | `local/` probe grep: exit 2 (error) treated as "clean" and the failure path is unpinned; real-tree call fails loud only by accident of `2>&1` | wave-introduced | yes |
| X3 | LOW | `${#_desc}` counts BYTES under dash (CI) but CHARS under bash — "at most 400 chars" is enforced as ~400 bytes; semantics undocumented | wave-introduced | yes |
| X4 | LOW | name/description extracted from lines 2–20 unbounded by the frontmatter close — body text can satisfy frontmatter checks, missing the silent-skip class the lint exists for | wave-introduced | yes |
| X5 | LOW | SKILL.md checkpoint instruction "outside the case folder" leaves the location ambiguous; a repo-relative placement conflicts with the skill's own clean-tree and shared-substrate rules | wave-introduced | yes |
| X6 | INFO | line-length frontmatter strip: a .md starting `---` with no closing `---` is silently exempt from the whole ratchet; self-probe does not cover that direction | wave-introduced | yes |

0 HIGH · 6 MED · 10 LOW · 5 INFO. Overlapping constructs across axes
(cross-corroboration, dispositions may merge): S1 ↔ X6 (unclosed
frontmatter strip; severities differ MED vs INFO), S3 ↔ X1 (`local/`
over-match), S2 ⊃ X2/X4 (unpinned lint branches / unbounded extraction).

---

## Axis S1 — mechanical sweep (verbatim)

# S1 — mechanical sweep (pin quality + class sweeps)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| S1 | MED | measure_file exempts the WHOLE file when frontmatter never closes — fail-soft, unprobed, unguarded | wave-introduced |
| S2 | MED | 4 of 9 FAIL branches in test-skills-lint.sh never execute in any fixture, incl. the lint's core open/close checks | wave-introduced |
| S3 | LOW | `local/` grep over-matches legit `~/.local/` XDG paths → false FAIL | wave-introduced |
| S4 | LOW | sed `2,20p` head-window: frontmatter >19 lines → false "never closes" FAIL | wave-introduced |

## S1 — MED — unclosed frontmatter silently exempts the entire file from the ratchet
**File:** `tests/unit/test-line-length.sh:91-95` (measure_file awk body), probe block `:128-149`

```awk
FNR == 1 && fm && $0 == "---" { infm = 1; next }
fm && infm { if ($0 == "---") infm = 0; next }
```

If an `.md` file's first line is `---` and no closing `---` ever appears, `infm` stays 1 and every remaining line hits `next` — the whole file leaves the ratchet with no warning and no baseline effect. Realistic triggers: (a) a hand-edited skill or rules-meta file that drops its closing fence; (b) any scoped doc opening with a `---` horizontal rule instead of frontmatter. The exposed population is large: I verified ~121 scoped `.md` files open with `---` (the entire `internal/rules-meta/` corpus, ~120 files, plus SKILL.md) — all close today (checked every one), so this is latent, not currently triggered. The lint that guards unclosed frontmatter (`test-skills-lint.sh:62`) only covers `.agents/skills/` — the rules-meta corpus and docs/ have no such guard. The probe pins three directions (frontmatter-not-counted via `_p1` empty, prose-after-close counted via `_p2`, non-md never stripped via `_p3`) but has no fixture for the unclosed direction, and the code has no EOF `infm==0` check — this is exactly the "strips too much" fail-soft spot the header comment itself names (`test-line-length.sh:118-120`), left without a pin, against agent/learnings.md's fail-loud-pins rule ("every new fail-soft spot gets a pin that executes the failure path").

## S2 — MED — four FAIL branches in the skills lint are never exercised by fixtures
**File:** `tests/unit/test-skills-lint.sh` — unpinned branches at `:45` (skills root missing), `:59-60` (frontmatter must open with `---`), `:62` (frontmatter never closes), `:72-73` (description > 400)

```sh
head -n 1 "$_f" | grep -qxF -- '---' || \
    echo "FAIL $_name: frontmatter must open with ---"
_close=$(sed -n '2,20p' "$_f" | grep -n -- '^---$' | head -1 | cut -d: -f1)
[ -n "$_close" ] || echo "FAIL $_name: frontmatter never closes"
...
[ -n "$_desc" ] && [ "${#_desc}" -gt 400 ] && \
    echo "FAIL $_name: description ${#_desc} chars > 400"
```

The six fixtures (`:89-126`) pin prefix, missing description, name mismatch, local/ ref, missing SKILL.md, and valid-passes-clean — all verified green and discriminating. But every fixture's SKILL.md opens and closes correctly with short descriptions, so the four branches above never execute. The open/close checks are the lint's stated core purpose (`:4-9`: opencode "silently SKIPS any file whose frontmatter does not parse") — a regression in those pipelines (grep flag typo, window off-by-one) leaves the lint green while catching nothing, which is the exact silent-skip failure class the lint exists to pin. The header at `:31-32` claims "the fixture pins below exercise the failure paths against scratch copies" — overstated for these four. Related: `test-line-length.sh` header (`:14-18`) delegates the description length bound to this suite ("the description bound lives where the data is validated: tests/unit/test-skills-lint.sh"), and the real SKILL.md:3 sits at exactly 400 raw bytes — the >400 branch that backs that claim never runs.

## S3 — LOW — `local/` grep matches `.local/` XDG paths (false FAIL)
**File:** `tests/unit/test-skills-lint.sh:75`

```sh
if grep -rn 'local/' "$_d" >/dev/null 2>&1; then
```

The substring match fires on any `local/` occurrence, including `~/.local/bin`, `~/.local/state/...` — legitimate Linux XDG paths a future skill could plausibly reference. False-positive direction (blocks clean content, fails loud — does not hide anything). Evasion shapes (path written to dodge the pattern) checked: none realistic found. Condition: only triggers when a skill actually references an XDG path; none does today.

## S4 — LOW — sed head-window `2,20p`: frontmatter longer than 19 lines → false "never closes"
**File:** `tests/unit/test-skills-lint.sh:61` (also `:64`, `:70` for name/description extraction)

```sh
_close=$(sed -n '2,20p' "$_f" | grep -n -- '^---$' | head -1 | cut -d: -f1)
```

A skill whose frontmatter closes after line 20 gets "FAIL ... frontmatter never closes" (and name:/description: lookups miss → cascading FAILs). Fail-loud direction, and the house shape is 4-line frontmatter, so the trigger is unrealistic today; flagged for completeness because measure_file (S1 counterpart) has no such window, so the two frontmatter parsers disagree on this input.

## Verified clean (no findings)

- **Baseline unchanged is consistent:** 35 entries at both revisions; the only scoped `.md` with a >120 frontmatter line is the NEW `.agents/skills/opk-review-pass/SKILL.md:3` (400 bytes, exempt by design); no pre-existing scoped `.md` carries >120 frontmatter lines, so no baseline sum could have shrunk — no hidden regen. `sh tests/unit/test-line-length.sh` → OK (662 over 120, trend 1280 over 100).
- **Probe placement:** probe check (line 193) sits before the rc summary gate (198); failure path prints and exits 1 — fail-loud.
- **Trend rewrite (xargs-awk → per-file loop):** sums the count field via `${_t##* }`; paths are space-free (and I confirmed none of the ~600 scoped paths contains a space). Old code had a latent multi-invocation partial-count bug under xargs splitting; new loop is strictly more robust. Only semantic delta is the intended frontmatter strip now applied to trend too.
- **Wiring:** Makefile `.PHONY`/help/`test`/`test-skills-lint` target and workflow step `./tests/unit/test-skills-lint.sh` all consistent; `test-docs.sh` `.agents` scope addition matches its updated header; both suites run green. Exec bit not re-checked per instructions.

## Coverage

Covered: full diff of test-line-length.sh (measure_file, probe, regen, growth/stale checks, trend), executed the suite; static sweep of every scoped `.md` opener/closer and >120 frontmatter lines; full read + execution of test-skills-lint.sh with per-branch pin audit; Makefile/workflow/test-docs.sh wiring diffs; baseline two-rev comparison. Deferred: RM-0116/RM-0083/INDEX.md content and rules-meta invariant suites (docs/rules axis, not mechanical — `make test-rules-meta` not run by me), e2e suites (out of axis), ShellCheck coverage of tests/ (pre-existing policy: lint covers files/+scripts/ only — not wave-introduced).

---

## Axis Q1 — quality (verbatim)

# Q-axis report — quality: claim-vs-behavior drift, docs that lie, wave rule compliance

Wave `caeb9a8..9cfef7f` @ 9cfef7f, branch feature/agents-skills-pilot. All paths relative to `/var/www/vhosts/opencode-permissions-kit/repo` unless prefixed.

## Findings index

| ID | Sev | Summary |
|---|---|---|
| Q1 | MED | Skill's `micro` scope keyword has no legal snapshot `Scope:` value — mapping undefined anywhere; lint doesn't validate Scope |
| Q2 | MED | RM-0116 attributes the closed-world check to "scripts/rules-audit.sh, invariant 10" — no invariant 10 exists in that script or the documented list |
| Q3 | MED | RM-0116's own Check command fails as written on the shipped tree; "exactly twice in the living tree" overstates the enforced scope |
| Q4 | MED | Wave's own new text cites `(RM-0078)`/`(RM-0083)` by ID — the exact pattern RM-0116 forbids; audit-invisible only via an unnamed exclusion |
| Q5 | LOW | SKILL.md drops RM-0111's third sabotage window ("in a scratch worktree") |
| Q6 | LOW | test-skills-lint cites "the pinned opencode source" for 2.x-only artifacts; the 1.x pin has no `SkillFile`/`Skipped`/debug log |
| Q7 | LOW | Sparse-machine red list omits `test-reviews-meta-aggregate` (verified red empirically); all 8 claimed suites verified red, none stays green |
| Q8 | LOW | New rule-carrying conventions section not registered in `ACTIVE_SECTIONS` — every sibling rule section is; invariant 1 won't guard future units there |
| Q9 | INFO | Pre-existing: AGENTS.md says review cap is "5 per tier"; RM-0108 says 5 concurrent on ANY tier (account-wide) |
| Q10 | INFO | `.agents/` added as tracked internal area but missing from AGENTS.md Layout and docs/README.md "Internal documentation" map |
| Q11 | INFO | line-length header claims "baseline was regenerated for the metric switches" — wave's baseline diff is empty (no-op regen) |

## Detail

### Q1 (MED) — `micro` scope keyword has no legal `Scope:` header value; mapping defined nowhere
- Evidence: `.agents/skills/opk-review-pass/SKILL.md:65` `| Scope keyword | **micro** (≤ ~50-line fix diff) · **wave** (round's diff) · **full** (whole tree, release) |` and `:71` `| | micro | wave | full / release |`; `internal/reviews/README.md:56` `Scope: wave            (full | wave | gate | analysis)`. SKILL.md:135-143 instructs updating `Scope` in the header without naming a value for a micro pass. `tests/unit/test-reviews-lint.sh:97-103` pins only `ID:` and `Snapshot:` — a `Scope: micro` header passes all guards.
- De-facto practice (not written as a rule anywhere): micro snapshots record `Scope: wave` with "micro" in the Subject — `internal/reviews/0/0/2/2/pr-00222/review-b.md:4-5`, `internal/reviews/0/0/2/2/pr-00224/review-b.md:4-5`, `internal/reviews/0/0/2/0/pr-00208/review-b.md:4-5`. README:72-76 defines only the catch-up case ("Scope stays `wave`"), never the micro case.
- Why it matters: the commission's named blind spot, confirmed. A session executing the skill for a micro pass must guess; writing `Scope: micro` produces an out-of-enum snapshot nothing catches; writing `wave` relies on unwritten convention. README (authoritative for snapshot format) wins; the skill's taxonomy and the enum need a stated mapping. Provenance: wave-introduced.

### Q2 (MED) — "invariant 10" attributed to rules-audit.sh, which has no invariant 10
- Evidence: `internal/rules-meta/0/1/1/RM-0116.md:12-15` "The rules audit enforces a closed world: a real RM ID occurs exactly twice … (scripts/rules-audit.sh, invariant 10 / tests/unit/test-rules-meta.sh pin 10, lanes a–c)." But `scripts/rules-audit.sh` implements invariants 1–6 and 9 only (header `:4-39`; `block` calls at `:191,202,208,224,…`; zero occurrences of `block 10`/`inv10`), and the documented invariant list `internal/records/rules-meta.md:123-138` numbers 1–9. The closed-world check is `tests/unit/test-rules-meta.sh:3` "the no-fake-findings pin 10" (lanes a–c at `:247-309`).
- Why it matters: the rule that governs citation accuracy cites the wrong enforcement tool; an agent or maintainer verifying the claim in rules-audit.sh finds nothing there. The test-file half of the citation is correct, which makes the wrong half easy to trust. Provenance: wave-introduced.

### Q3 (MED) — RM-0116's Check command fails as written; "exactly twice in the living tree" overstates scope
- Evidence: `internal/rules-meta/0/1/1/RM-0116.md:24-26` "grep for `RM-[0-9]{4}` outside internal/rules-meta and the SCOPE_FILES finds nothing." Executed literally, it hits 60+ lines under `internal/reviews/` (including the wave's own `internal/reviews/README.md:67,71` — see Q4), because pin 10 lane c silently excludes two more trees: `tests/unit/test-rules-meta.sh:290-292` `grep -v "/internal/reviews/"` and `grep -v "/internal/records/_archive/"`. Likewise `agent/conventions.md:222-226` "Every RM key appears exactly twice in the living tree" — false as stated: `internal/rules-meta/INDEX.md` carries every ID a third time (e.g. INDEX row `[RM-0116](0/1/1/RM-0116.md)`), and the reviews corpus carries many IDs in snapshots/resolutions.
- Why it matters: the rule's own verification recipe goes red on a green tree — a maintainer executing the documented check gets failures the audit deliberately ignores, and the two unnamed exclusions are exactly where the wave's own violation (Q4) hides. Provenance: wave-introduced.

### Q4 (MED) — the wave's own new text cites RM IDs, the pattern RM-0116 forbids
- Evidence: `internal/reviews/README.md:67` "`Skills:` is part of the environment record (RM-0078)" and `:71` "axis visible (RM-0083)" — added by commit 4628be6 (22:20), one minute before RM-0116 was created in 9378431 (22:21, per `git log` timestamps), and never reworked afterwards. `agent/conventions.md:222-226` (RM-0116) forbids exactly this: "new text (files, skills, comments, cross-references) cites a rule by file and section, never by its ID." The citations survive the audit only because lane c excludes `/internal/reviews/` (test-rules-meta.sh:291).
- Why it matters: rule-compliance drift in the wave's own text — the wave that introduces the citation rule ships forbidden citations in an audit-blind file. RM-0116's narrative says such citations required "rework of already-written content"; these weren't reworked. If lane c's exclusion is ever narrowed, the tree goes red with no guilty change. Provenance: wave-introduced.

### Q5 (LOW) — SKILL.md drops RM-0111's scratch-worktree sabotage window
- Evidence: `.agents/skills/opk-review-pass/SKILL.md:115` "Sabotage windows are before launch or after all return" vs `agent/review-concept.md:238-241` "they run only (a) before the fan-out launches, (b) after all reviewer agents returned, or (c) in a scratch worktree."
- Why it matters: restrictive drift — a session following the skill forgoes a legal option the authoritative rule grants (mid-fan-out sabotage in a scratch worktree); no error is induced, but the skill claims the rules stay authoritative and links to them. review-concept.md wins. Provenance: wave-introduced.

### Q6 (LOW) — "verified against the pinned opencode source" names 2.x-only artifacts
- Evidence: `tests/unit/test-skills-lint.sh:5-7` "SkillFile.parse -> 'Skipped', debug log only — verified against the pinned opencode source". True for the 2.x pin: `github/opencode-2x` @ v2.1.4, `packages/core/src/config/plugin/skill-file.ts:20-21,38-42` and `config/plugin/skill.ts:129-136` (`Effect.logDebug("skill file skipped")`). False as named for the 1.x pin: `github/opencode-1x` @ v1.18.35 has no `SkillFile` class, no `Skipped` tag, and no log at all — `packages/core/src/skill.ts:84-90` skips via bare `continue` (even more silently; keyed by name, not id, at `:117-122`). The header names no version, and the kit maintains both lanes (`.github/workflows/test-e2e.yml:26` e2e-1x lanes).
- Why it matters: a reader verifying the claim against the 1.x clone cannot find any of the named artifacts; the substantive behavior (fail-silent skip) does hold there, so this is citation precision, not a false behavior claim. SKILL.md:36-37, by contrast, names its version (v2.1.4) explicitly and every calibration claim in its section 0 checked out against `packages/core/src/plugin/command/review.txt` at that tag. Provenance: wave-introduced. (Commission premise note: there is no v1.18.15 clone in this workspace; the pins are opencode-1x @ v1.18.35 and opencode-2x @ v2.1.4.)

### Q7 (LOW) — sparse-machine red list is incomplete by one suite
- Evidence: `CONTRIBUTING.md:270-274` "The unit suite runs partially red on that machine BY DESIGN … (measured 2026-10-23: line-length stale baselines, skills lint, rules-meta/index/revisit, reviews lint/parity, docs dangling links …)". Empirical run (clone @ 9cfef7f, sparse-checkout set exactly as documented — recipe verified: `git status --short` empty, agent/ .agents/ internal/ absent): 9 of 42 suites red. All 8 claimed suites are red, including line-length (stale baseline entries do fail: "FAIL agent/README.md: stale baseline entry (file gone or now clean)" — vanished entries are NOT silently allowed at runtime) and docs (first failure: `CONTRIBUTING.md -> internal/process/release-handling.md`). But `test-reviews-meta-aggregate` is also red ("2026-10-10 regeneration differs from the frozen stats.json") and is covered by no reading of "rules-meta/index/revisit" or "reviews lint/parity".
- Why it matters: the parenthetical is presented as the measurement and is the operator's only by-design-vs-regression discriminator on that machine; an unlisted ninth red invites either false alarm or habituation. The umbrella sentence ("guards over agent/, .agents/ and internal/ correctly fail") remains true. Provenance: wave-introduced.

### Q8 (LOW) — new rule section not registered in ACTIVE_SECTIONS
- Evidence: `agent/conventions.md:220` `## Referencing house rules (RM keys)` carries the rule unit `(RM-0116)` at `:227`, but `scripts/rules-audit.sh:55-59` registers the five sibling conventions sections (interactive-prompts-yn, script-output-style, shell-security-untrusted-input, test-sandbox-unit-suites, referencing-review-findings) — not the new one (grep: zero hits for "Referencing house rules" in rules-audit.sh).
- Why it matters: invariant 1 (ref-less units in active sections block) won't guard future bullets added under the new section — a unit without an `(RM-NNNN)` ref there passes silently, breaking the pattern every other rule-bearing conventions section follows. The existing meta/refs resolve fine (suite green, 21 pins), so the gap is prospective only. Provenance: wave-introduced.

### Q9 (INFO, pre-existing) — AGENTS.md "5 per tier" vs RM-0108 "5 on any tier"
- Evidence: AGENTS.md "Subagent fan-out" bullet 2: "today the review process caps at 5 per tier" vs `agent/review-concept.md:231-237` "the standard cap is 5 concurrent reviewer subagents on ANY tier — the provider's burst limit is account-wide, not per-model." The "per tier" reading would permit 5 fast + 5 strong concurrently, which RM-0108's account-wide rationale explicitly rejects. The wave's SKILL.md:112-115 matches RM-0108 (and thus contradicts the AGENTS.md phrasing). Untouched by this wave; flagging because the wave's cap text forces the comparison. Provenance: pre-existing.

### Q10 (INFO) — `.agents/` missing from both canonical internal-docs maps
- Evidence: AGENTS.md router bullet at `:16` lists `.agents/skills/`, but `## Layout` (files/, tests/, docs/, agent/, internal/ — no `.agents/`) and `docs/README.md:52-56` "Internal documentation … `agent/` … `internal/`" both omit it.
- Why it matters: minor discoverability drift — the wave added a tracked top-level directory and updated the router but neither map of where internal documentation lives. No rule (RM-0100) is violated: files/ is untouched, so no user-docs page is owed; the skills area is contributor-facing and is documented in AGENTS.md/CONTRIBUTING. Provenance: wave-introduced omission.

### Q11 (INFO) — "baseline was regenerated" claim has an empty diff behind it
- Evidence: `tests/unit/test-line-length.sh:40-43` "the baseline was regenerated for the metric switches (deliberate, diff-reviewed -- entries can only shrink or vanish, never grow)" — `git diff caeb9a8..9cfef7f -- tests/unit/line-length-baseline.txt` is empty and the baseline contains zero `.agents` entries. The frontmatter-strip regen was a no-op (no baselined file had >120-char frontmatter lines; the new skill files carry no excess outside frontmatter; suite green, 662 lines all at baseline, probe ok).
- Why it matters: "diff-reviewed" implies a diff existed to review; for this wave's switch it didn't. No operational drift — the ratchet holds — and the sentence is pluralized inheritance from the earlier whitespace-strip regen, so this is a precision nit, not a lie. Provenance: wave-introduced (comment edit only).

## Coverage

Covered: full wave diff (1061 lines); SKILL.md + axis-prompt.md checked number-by-number and keyword-by-keyword against review-concept.md (all sections) and internal/reviews/README.md — cap 5/USER-override, budgets 5/8/15 + ≤~50-line micro, axes vocabulary, checkpoint launch/return/clean/host-timestamp mechanics, both-direction screening, verification duty, retracted/ghosts, final-answer rule, hard seam, never-self-advance/never-declare-closed, path-form blind spots, provenance vocabulary, severities, header fields incl. the new `Skills:` line — all consistent except Q1/Q5/Q9; RM-0116 self-compliance sweep incl. commit-order archaeology and empirical Check-grep; rules-audit.sh + test-rules-meta.sh pin-10 lanes read end-to-end; version claims verified against both pinned clones (v2.1.4 review.txt calibration fully confirmed; walk-up discovery, ID-by-directory, same-ID overwrite, bare-.md loading confirmed); sparse-checkout recipe reproduced empirically with all 42 unit suites run in the sparse clone (read-only clone under /tmp/opencode/pr-00235-a/sparse); both new suites + line-length run green on the full tree; AGENTS.md/docs/README.md/CONTRIBUTING coverage checked for the docs-with-code rule.

Deferred: "stable across pulls" for the sparse checkout accepted from git's documented non-cone semantics (not re-tested with synthetic commits — no operational doubt); openchamber-1x/2x clones not consulted (not referenced by any wave claim); e2e suites not run (no files/ or root-run script changes in the wave — tests/, Makefile, workflows, markdown only, so no e2e debt triggered per AGENTS.md); severity of Q7 kept LOW on the grounds that the umbrella by-design claim is accurate and no workflow instructs running the suite on the external machine — the maintainer may judge MED if that list becomes the machine's ignore-list in practice.

Checkpoint file: /tmp/opencode/pr-00235-a/checkpoint-Q1.md (all six sections recorded, launch + return lines).

---

## Axis X1 — security & integration (verbatim)

# Reviewer X1 — security & integration axis (wave caeb9a8..9cfef7f)

## Findings index

| ID | Severity | Summary |
|---|---|---|
| X1 | LOW | `local/` lint pattern matches `/usr/local/…` and `~/.local/…` — false-positive direction; rule forbids only workspace `local/` references |
| X2 | INFO | `local/` probe grep: exit 2 (error) treated as "clean" and the failure path is unpinned; real-tree call fails loud only by accident of `2>&1` |
| X3 | LOW | `${#_desc}` counts BYTES under dash (CI) but CHARS under bash — "at most 400 chars" is enforced as ~400 bytes; semantics undocumented |
| X4 | LOW | name/description extracted from lines 2–20 unbounded by the frontmatter close — body text can satisfy frontmatter checks, missing the silent-skip class the lint exists for |
| X5 | LOW | SKILL.md checkpoint instruction "outside the case folder" leaves the location ambiguous; a repo-relative placement conflicts with the skill's own clean-tree and shared-substrate rules |
| X6 | INFO | line-length frontmatter strip: a .md starting `---` with no closing `---` is silently exempt from the whole ratchet; self-probe does not cover that direction |

No HIGH/MED findings. No injection path found: `_name`, `_nm`, `_desc` (file-content derived) flow only into quoted `echo`/`case`/`[ ]` expansions; the `case` pattern `"$_name"` at tests/unit/test-skills-lint.sh:66 is quoted, hence literal; `grep -qxF -- '---'` (line 59) and `grep -n -- '^---$'` (line 61) are the safe forms. Temp-file hygiene, sandbox compliance, exec-bit/CI wiring, and Makefile parity all verified clean (details in coverage line).

## Detail

### X1 — LOW — `local/` lint matches `/usr/local/…` and `~/.local/…` (too strict; latent false positive)
Provenance: wave-introduced.

tests/unit/test-skills-lint.sh:74-77:
```sh
        # no local/ references anywhere in the skill directory
        if grep -rn 'local/' "$_d" >/dev/null 2>&1; then
            echo "FAIL $_name: references local/ (disposable workspace)"
        fi
```
The pattern `local/` is a raw substring: it matches `/usr/local/lib/opencode-permissions-kit/` — the kit's own deploy prefix, core vocabulary for any future maintainer skill (repo AGENTS.md "What this repo is") — and `~/.local/share/opencode` (opencode's state dir, plausible in a skill about opencode behavior). The rule's source (workspace AGENTS.md: "Never reference `local/` from inside `repo/`") forbids only references to the disposable workspace directory. Today's real tree is clean (verified: `grep -rn 'local' .agents/` → none), so the mismatch is latent; the trigger is the first future skill that legitimately names the installed-kit path or an XDG path — CI goes red on content the rule permits. Note also the enforced rule lives in the *workspace* (unshipped) AGENTS.md while the enforcement ships in the repo. Fail-loud direction (blocks, doesn't miss), hence LOW. Evasion shapes (`LOCAL/`, `local\/`) exist but this lint guards accidents, not adversaries — not findings. `locale/` correctly does not match.

### X2 — INFO — grep error (exit 2) reads as "clean"; failure path unpinned
Provenance: wave-introduced.

tests/unit/test-skills-lint.sh:75 — `if grep -rn 'local/' "$_d" >/dev/null 2>&1; then` — grep exit codes: 0 = match → FAIL printed; 1 = no match → clean; **2 = error (unreadable file, broken symlink — git stores symlinks) → condition false → clean**, even when other files in the dir contain matches. AGENTS.md "Review learnings" requires: "every new `|| true`, stderr redirect, or probe pipe gets a pin that executes the failure path" — this stderr redirect has no error-path pin. Mitigating, and why this is only INFO: the real-tree call at line 156 (`lint_skills .agents/skills >> "$TMP" 2>&1`) folds stderr into `$TMP`, so a grep error makes `$TMP` non-empty → exit 1 — loud by accident, with a confusing message. The fixture call at line 128 (`_out=$(lint_skills ...)`) does not capture stderr, so on a grep error the `opk-local-ref` discrimination pin would silently pass — but the fixtures are freshly created and cannot error. Net: unreachable today, class rule violated.

### X3 — LOW — description limit enforced as bytes under dash, chars under bash; header says "chars"
Provenance: wave-introduced.

tests/unit/test-skills-lint.sh:24-25:
```
#   - frontmatter carries a non-empty single-line `description:` of at
#     most 400 chars
```
tests/unit/test-skills-lint.sh:72-73:
```sh
        [ -n "$_desc" ] && [ "${#_desc}" -gt 400 ] && \
            echo "FAIL $_name: description ${#_desc} chars > 400"
```
The suite runs under `/bin/sh`: the new CI step executes it by path (`.github/workflows/test-unit.yml` — `run: ./tests/unit/test-skills-lint.sh`) and the Makefile target likewise (`@./tests/unit/test-skills-lint.sh`), so the shebang `#!/bin/sh` → dash on CI runners; AGENTS.md's documented local invocation `sh tests/unit/test-*.sh` → dash on Debian/Ubuntu hosts. dash `${#var}` counts **bytes**; bash counts **chars** in a UTF-8 locale. Measured on the real skill: description = 387 chars / 391 bytes (2 em-dashes, verified with dash, bash, `wc -c`, `wc -m`) — passes both semantics with a 9-byte margin, so no current trigger. Realistic trigger: a future 399-char description with one em-dash = 401 bytes → CI red while the file is "399 chars"; the same tree passes for a developer running it under bash — local-green/CI-red drift. The sibling test documents its byte semantics explicitly (tests/unit/test-line-length.sh:38-39, "Metric note: awk's length() counts bytes"); this one has no such note. LOW: latent, margin known, fail direction loud.

### X4 — LOW — frontmatter fields read from lines 2–20 regardless of the computed close
Provenance: wave-introduced.

tests/unit/test-skills-lint.sh:61-70:
```sh
        _close=$(sed -n '2,20p' "$_f" | grep -n -- '^---$' | head -1 | cut -d: -f1)
        [ -n "$_close" ] || echo "FAIL $_name: frontmatter never closes"
        # name: non-empty, equals directory
        _nm=$(sed -n '2,20p' "$_f" | sed -n 's/^name:[[:space:]]*//p' | head -1)
        ...
        _desc=$(sed -n '2,20p' "$_f" | sed -n 's/^description:[[:space:]]*//p' | head -1)
```
`_close` is computed but never bounds the name/description extraction: any body line starting `name:` or `description:` within the first 20 lines satisfies the checks. A SKILL.md whose frontmatter genuinely lacks `description:` (→ opencode's parser skips the skill silently, the exact failure class this lint is the fail-loud pin for, per its own header lines 4-9) passes the lint if its body documents its own frontmatter shape (e.g. a line `description: max 400 chars` — plausible in a self-describing skill). Symmetrically, a frontmatter field beyond line 20 is missed (fail-loud there, fine). The fixture set (lines 89-126) has no pin for the body-embedded-field shape. LOW: plausible trigger, weakens a discriminator, wrong direction (false clean) but bounded to lint coverage.

### X5 — LOW — checkpoint location instruction ambiguous; repo-relative placement self-conflicts
Provenance: wave-introduced (the ambiguity is inherited from review-concept.md:250, which says only "side file" — the new skill concretizes without closing the gap).

.agents/skills/opk-review-pass/SKILL.md:95-96:
```
4. Checkpoint locations: one side file per reviewer agent, outside the
   case folder until the snapshot takes them over.
```
axis-prompt.md:51-52 leaves the slot to the filler: `checkpoint file <CHECKPOINT PATH>`. No base location is ever named — the only self-consistent reading (outside the repo, e.g. /tmp) is unstated. A literal-minded session reading "outside the case folder" as a repo-relative sibling (the case parent shard `internal/reviews/A/B/C/D/`, or anywhere in-tree) produces: (a) a dirty tree, contradicting SKILL.md:89-90 "Verify the tree is clean (`git status --porcelain` empty)" and SKILL.md:113-114 "The tree is a shared read substrate … no writes into the reviewed tree"; (b) inside the case folder itself it trips test-reviews-lint.sh rule 6 ("no stray files inside the case folder", tests/unit/test-reviews-lint.sh:87-90). The pass then blocks on its own pre-flight. LOW: instruction underspecification with a realistic mis-execution shape and named conflicts; no unsafe *host* location is named anywhere (no writes outside the repo are instructed).

### X6 — INFO — ratchet frontmatter strip: unclosed leading `---` exempts the whole file
Provenance: wave-introduced.

tests/unit/test-line-length.sh:104-105:
```awk
        FNR == 1 && fm && $0 == "---" { infm = 1; next }
        fm && infm { if ($0 == "---") infm = 0; next }
```
If a .md's first line is `---` and no closing `---` ever appears, `infm` stays 1 and every line is `next`-skipped — the file is fully invisible to the ratchet. The self-probe (lines 127-149) pins md-frontmatter, md-prose, and non-md, but not the unclosed case. Partial mitigation: a previously-baselined file losing its entry trips the stale-baseline check (lines 177-182); only a *new* file starting with a bare unclosed `---` (atypical — that is frontmatter shape) is silently exempt. INFO.

## Verified clean (for the record)

- **Injection surfaces** in tests/unit/test-skills-lint.sh: every file-content-derived variable (`_name`, `_nm`, `_desc`, `_close`) is expanded quoted; no `eval`, no unquoted command substitution into command position; glob-`*` in a name would be literal in the quoted `case` subject; a leading `-` cannot reach an option position (all operands follow `--` guards or quoted path args). `grep -qxF -- '---'` (line 59) and `grep -n -- '^---$'` (line 61) are the safe forms.
- **Temp hygiene**: test-skills-lint.sh — `TMP` (mktemp, trap), `WORK` (mktemp -d, trap replaced with `rm -rf "${WORK:?}" "$TMP"`, guarded against empty); test-line-length.sh — `TMP_CUR`/`TMP_PROBE`/`PROBE_DIR` all mktemp, traps guarded with `:?`, trap extended-not-lost on replacement. No leaks, no unquoted `rm -rf`, no TOCTOU (scratch is self-written). `--regen` writes into the repo tree, but that is pre-existing, deliberate, and header-documented (test-line-length.sh:111-112) — not wave-introduced.
- **Sandbox compliance**: `sh tests/unit/test-sandbox-policy.sh` → PASS over the tree including both touched tests; scratch lives only under mktemp/`/tmp`.
- **CI/Makefile surface**: exec bit verified `100755` in the git index for all three touched tests (invariant 755 ⇔ executed-by-path, repo AGENTS.md); test-workflows.sh's orphan check ("every unit suite on disk has a run: step", tests/unit/test-workflows.sh:11,135) is dynamic — ran green with the new file+step; step insertion between reviews-lint and reviews-parity has no ordering dependency; the new step reads only repo content, executes no file content, creates only /tmp scratch.
- **Live runs** (all green): test-skills-lint.sh, test-line-length.sh, test-docs.sh, test-workflows.sh, test-sandbox-policy.sh.
- **Skill link targets** resolve (agent/review-concept.md, internal/reviews/README.md, internal/records/review-calibration.md all exist; test-docs.sh with the new `.agents` scope passes).

## Coverage

Covered: full data-flow trace of the new lint (section-by-section), empirical byte/char measurement of the real description under dash and bash, both `local/` directions with real-tree verification, temp/trap audit of both touched tests plus sandbox-policy live run, CI workflow + Makefile wiring with exec-bit and parity verification (live), skill instruction integration including link-target existence and conflict check against review-concept.md, reviews-lint rules, and the trash/wsl.conf rules. Deferred: CONTRIBUTING.md / internal/records/review-independence.md / RM-0083 / RM-0116 / review-concept.md prose changes were skimmed for integration conflicts only (docs axis owns their content review); the opencode v2.1.4 `/review` calibration claim (SKILL.md:35-39) was not verified against the upstream binary — outside this axis and read-only scope (unverified, not flagged). No HIGH/MED findings; nothing here blocks, X1/X3/X4 are quality-of-enforcement gaps in the new lint, X5 is an instruction-ambiguity hazard, X2/X6 are informational.

---

## Retracted / ghost findings

None. All 21 reported findings were verifiable against the code; no
finding was dropped or retracted during main-agent verification. One
intra-report numeric contradiction was resolved by measurement (see
verification marks) — it corrects a sub-claim, not a finding.

## Verification (main session)

Every finding re-verified against the tree at 9cfef7f before entering
this snapshot; evidence highlights:

- **S1/X6** — awk body re-read; probe block confirmed to carry only
  probe.md/probe2.md/probe.yml (no unclosed-frontmatter fixture);
  117 scoped `.md` files open with `---` (reviewer said ~121);
  learnings L4 ("Pins must discriminate, and sit before the summary
  gate") + AGENTS.md "Fail-loud pins" bullet are the rule homes.
- **S2** — the 9 FAIL echo sites counted at :45, :51, :55, :60, :62,
  :67, :71, :73, :76; fixtures pin 5 failure shapes + valid-clean; the
  4 unpinned branches confirmed (root missing, must-open, never-closes,
  >400). **Correction:** the sub-claim "SKILL.md:3 sits at exactly 400
  raw bytes" is wrong — the lint measures the description VALUE after
  stripping `description: ` = **391 bytes / 387 chars** (dash/bash
  measured; full raw line 404 bytes / 400 chars, never seen by the
  check). The conclusion (the >400 branch never runs against the real
  skill, margin 9 bytes) holds and aligns with X3.
- **S3/X1** — substring match confirmed; `/usr/local/…` and
  `~/.local/…` shapes both match; real tree clean today.
- **S4** — `sed -n '2,20p'` window confirmed at :61/:64/:70.
- **Q1** — README Scope enum `full|wave|gate|analysis` vs skill
  taxonomy micro|wave|full confirmed; test-reviews-lint.sh:97-103 pins
  only ID↔folder and Snapshot↔letter; the pr-00222/pr-00224/pr-00208
  review-b headers carry `Scope: wave` with micro Subjects (convention,
  unwritten).
- **Q2** — scripts/rules-audit.sh exit line "1 on blocking violations
  (1-6, 9)"; block calls 1-6 and 9 only; test-rules-meta.sh:2-3
  "invariants 1-9 plus the no-fake-findings pin 10";
  internal/records/rules-meta.md "Audit invariants" list = 1-9.
- **Q3** — the Check grep as written re-run: 96 hits outside
  internal/rules-meta and SCOPE_FILES (74 in test-rules-revisit.sh, 22
  in test-rules-meta.sh, dozens under internal/reviews/); SCOPE_FILES
  is real (rules-audit.sh:53) but lane c additionally excludes
  /internal/reviews/ and /internal/records/_archive/
  (test-rules-meta.sh:290-292) — neither named in the rule text;
  INDEX.md carries every ID a third time.
- **Q4** — `git show master:internal/reviews/README.md | grep -c "RM-0"`
  = 0; HEAD has exactly the two new refs (:67, :71); lane c's
  /internal/reviews/ exclusion confirmed → the citations are
  audit-invisible.
- **Q5** — SKILL.md:115 names two windows; review-concept.md RM-0111
  names three (incl. scratch worktree).
- **Q6** — workspace pins re-checked: opencode-1x @ v1.18.35
  (bare `continue` skip, no log, skill.ts:84-90), opencode-2x @ v2.1.4
  (SkillFile "Skipped" tags, skill-file.ts:20-42). The upstream clones
  live in the workspace (github/, outside this repo) at those tags.
- **Q7** — independently re-run by the main session in the reviewer's
  sparse clone (clean status, HEAD 9cfef7f): test-reviews-meta-aggregate
  rc=1, test-skills-lint rc=1 ("skills root missing"); full result set
  = 9 red / 42, matching the reviewer's list exactly; all 8 suites
  named in CONTRIBUTING are red; the unlisted ninth is
  test-reviews-meta-aggregate.
- **Q8** — ACTIVE_SECTIONS enumerated (rules-audit.sh:54-62): five
  conventions sections + AGENTS.md#rules + three rules-meta.md
  sections; "Referencing house rules" zero hits.
- **Q9** — AGENTS.md:177 "caps at 5 per tier" confirmed; pre-existing
  (wave's AGENTS.md diff touches only the router bullet).
- **Q10** — AGENTS.md Layout (lines 50-68) has no `.agents` mention;
  docs/README.md "Internal documentation" maps agent/ + internal/ only.
- **Q11** — regen re-run by the main session pre-fan-out: 35 entries,
  `git status --porcelain` stayed empty (no-op) — "diff-reviewed" had
  no diff to review for this switch.
- **X2** — grep exit semantics and the accidental `2>&1` loudness at
  :156 confirmed by code read; fixtures freshly created, error path
  unreachable today.
- **X3** — measured: value = 391 bytes / 387 chars (see S2
  correction); dash-vs-bash semantics as reported.
- **X4** — `_close` never bounds the :64/:70 extractions; body-line
  shape confirmed by code read.
- **X5** — SKILL.md "outside the case folder" carries no base
  location; test-reviews-lint.sh:87-92 rule 6 confirmed (only
  review-*.md / resolution.md allowed in a case folder).

## Run provenance

- Host: opencode kit-managed session (user `opencode`), WSL2,
  checkout `/var/www/vhosts/opencode-permissions-kit/repo`, branch
  `feature/agents-skills-pilot`, tree `9cfef7f` clean; no opencode
  binary on the agent PATH (version unrecorded).
- Fan-out: 3 reviewer subagents (fresh contexts, provider fast tier),
  launched concurrently ≤ 5-cap. HOST timestamps: fan-out start
  2026-10-23T21:54:22Z, all returned by 2026-10-23T22:08:12Z.
- Per-agent windows (checkpoint launch/return lines, sandbox clocks —
  observed skew ≈ +2h vs host UTC, normalized):
  S1 launch 2026-10-23 ~21:55Z / return ~21:59Z (file mtimes);
  Q1 launch 2026-10-23T21:55:23Z / return 2026-10-23T22:05:52Z;
  X1 launch ~21:55Z / return ~22:05Z. Checkpoint side files:
  /tmp/opencode/pr-00235-a/checkpoint-{S1,Q1,X1}.md (outside the case
  folder per skill choreography; content absorbed here — stray files
  in the case folder would trip test-reviews-lint rule 6).
- Sabotage/mutation windows vs readers: none overlapped. Pre-launch
  mutations by the main session only: baseline `--regen` no-op check
  (21:53Z, tree stayed clean) and read-only unit-suite runs. The
  reviewer-built sparse clone and the main-session re-runs wrote only
  under /tmp/opencode/pr-00235-a/.
- Gates run at HEAD 9cfef7f (all green): test-skills-lint,
  test-line-length (+ regen no-op), test-docs, test-workflows,
  test-sandbox-policy, test-reviews-lint, test-rules-meta,
  scripts/rules-audit.sh (0 blocking violations), check-host pre-flight.
  E2e suites: not owed by this wave (no files/, no root-run script
  semantics — tests/, Makefile, workflows, markdown only).
- Environment note: the reviewer Q6 text references the workspace
  upstream clones (github/opencode-1x @ v1.18.35, github/opencode-2x
  @ v2.1.4) — read-only reference clones outside this repo, pinned at
  the named tags (the workspace's own AGENTS.md mentions an older
  1.18.15 pin; the clones on disk are as stated in the finding).
- Calibration: single snapshot (wave scope — no second-snapshot
  redundancy owed); skill-led house pass, `Skills: opk-review-pass`
  recorded in the header per RM-0083/reviews-README.

## Recommendation

No HIGH findings; the wave's core mechanisms (skill files, lint,
ratchet metric, wiring) work as shipped and the full local gate set is
green. The 6 MED findings cluster into three fix groups for the next
wave: (1) the ratchet's unclosed-frontmatter fail-soft direction plus
the skills-lint's four unexercised FAIL branches are one class —
fail-loud pin coverage (S1/S2, with X2/X4 riding along); (2) RM-0116's
citation accuracy, its unwritable Check command, and the wave's own
RM-ID citations in internal/reviews/README.md are one class — rule
text vs enforcement reality (Q2/Q3/Q4, with Q8 the prospective guard);
(3) the micro→Scope mapping gap in the skill/README pair (Q1, with
Q5/Q9 adjacent consistency nits). LOW/INFO findings are quality
hardening, several latent-only; Q7's list should be completed whenever
the sparse machine recipe is next touched. Nothing here blocks the PR
from the review side; dispositions are the maintainer's call.
