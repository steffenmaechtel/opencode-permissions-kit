<!-- review-meta
ID: pr-00235
Snapshot: c
Subject: micro-wave review of the b-wave's fixes — fix wave 2 (skills-lint local/ shapes + find-rc, line-length probe4, RM-0116 text)
Scope: wave
Base: 17a3092 (snapshot-b commit; b-wave tip 606cc26)
Diff: 17a3092..606cc26
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 2 fresh-context reviewer subagents (glm-5.3-flash; axes S/Q)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review c — b-wave fixes (micro-wave review of fix wave 2)

Third snapshot of the case; commissioned by the maintainer over fix
wave 2, which implemented review-b's findings (commits `9cb41b8`
tests+rules, `606cc26` resolution ledger). Commissioned scope keyword:
**micro**; measured material 5 files, +272/−52 (~172 code/doc lines +
ledger) — above the ~50-line micro bound, so the pass ran the micro
ceiling of 2 axes (sweep / quality), batched greps + targeted reads.
Wave scope per agent/review-concept.md ("did the fixes break or
lie?"), fan-out per "Parallel reviewer agents"; every reviewer finding
re-verified against the code by the main session before entering this
snapshot (verification marks below; nothing retracted, nothing
unverified). Rotation: conformant — fresh session (D) reviews the
b-session's fixes; no deviation, so no CLEAN-verdict re-verification
mandate from RM-0110.

## Findings index (consolidated)

| ID | Severity | One-liner | Provenance | Verified |
|---|---|---|---|---|
| S1 | MED | Doubled-slash spellings of caught shapes (`.//local/`, `..//local/`, `x/.//local/`) fall through the `local/` guard while their canonical spellings are caught and claimed in the header shape table | pre-existing shapes, fix-induced incompleteness (L2 remainder of b B1) | yes (probed, exact pattern) |
| S2 | LOW | probe4 pins only the offending-line count, not which line was counted — p and q are both 130 chars, so the sum is identical either way | wave-introduced | yes (narrowed: probe2 backstops the named mutant) |
| S3 | LOW | b-round sweep record "measure_file is the only span-parser" is false as written — `rules-audit.sh:124` (`fm_get`) and the lint's own close-scan awk are span parsers too | wave-introduced (record); parsers pre-existing | yes |
| Q1 | LOW | Ledger's b B3 evidence block misdescribes probe4's fixture shape, omitting the pre-close >120 line that makes the pin discriminate | fix-induced (wave's own evidence text) | yes (measured: described shape is vacuous) |
| Q2 | INFO | rules-audit.sh header sentence for invariant 8 is truncated mid-sentence — pre-existing, but RM-0116 now sends readers to that header | pre-existing | yes |

1 HIGH-would-be · 0 · 0 MED besides S1 — count: **0 HIGH · 1 MED ·
3 LOW · 1 INFO** over 5 unique findings (5 reported, 5 verified, 0
retracted, 0 cross-corroborated duplicates).

---

## Axis S — mechanical sweep (verbatim)

# Review S — mechanical sweep (pin quality + class sweeps), pr-00235 fix wave 2 (`17a3092..606cc26`)

Both suites ran green in the scratch sandbox (`TMPDIR=/tmp/opencode/pr-00235-c/scratch-S`, no `--regen`); all 17 skills-lint pins fired live, probe4 fired live.

## Findings index

| ID | Severity | Summary |
|---|---|---|
| S1 | MED | Doubled-slash spellings of caught shapes (`.//local/`, `..//local/`, `x/.//local/`) fall through the `local/` guard while their canonical spellings are caught and claimed in the header shape table |
| S2 | LOW | probe4 pins only the offending-line count, not which line was counted — a tail-strip regression produces the identical output and passes |
| S3 | LOW | b-round sweep record "measure_file is the only span-parser" is false as written — `rules-audit.sh:124` and the lint's own field awk are span parsers too |

## Detail

### S1 — MED — doubled-slash shapes miss the `local/` guard (soft-miss; L2 remainder of b B1)

**Provenance: pre-existing shapes** (the a-round pattern missed them too), **surfaced as fix-induced incompleteness** — the b B1 fix extended the dot-slash family without sweeping slash-run siblings.

Evidence — probes with the exact `grep -qE "$LOCAL_SHAPES"` pattern at [tests/unit/test-skills-lint.sh:70](repo/tests/unit/test-skills-lint.sh):
- MISS: `.//local/x`, `..//local/x`, `x/.//local/x` — each is POSIX-equivalent (redundant slashes collapse) to a shape the header claims to catch: `./local/`, `../local/`, `x/./local/`.
- Header claims, lines 35–37: "Matched shapes: `local/…` and `../local/…` (relative from workspace root / repo), the dot-slash family `./local/…` (incl. `x/./local/`, `.././local/`)". The "NOT matched, deliberately" list (lines 39–42) does not include any doubled-slash form, so these are not documented exemptions.

Why it matters: `..//local/x` resolves to exactly the workspace path that the caught spelling `../local/x` resolves to — under the wave's own semantics (the opk-dot-local fixture asserts `./local/` and `.././local/` "resolve into the disposable workspace"), these are the same targets silently passing the guard. Same class the wave rated b B1 MED; the L2 rule (`agent/learnings.md`: "a class fix counts only after all same-shape sibling sites are swept") makes the unswept slash-run siblings a class-sweep gap. Trigger condition: any shipped skill doc spelling a workspace path with a doubled slash (typo/plausibly from concatenating `../` + `/local/`).

Classified, not flagged: `x///local/` ≡ `x/local/` (repo-internal, deliberate-exempt family consistent with the ledger) and `//local/` → root-level `/local` (resolves elsewhere, not the workspace) — both genuine exemptions, though the header enumerates neither; folding that table-completeness note into this finding. Everything else probed matched the header exactly: all 10 should-catch shapes catch (incl. space/backtick/paren/tab-prefixed, WS_LOCAL absolute), all 6 claimed-exempt shapes miss.

### S2 — LOW — probe4 cannot discriminate which long line was counted

**Provenance: wave-introduced** (probe4 is new in this diff).

Evidence — [tests/unit/test-line-length.sh:168-170](repo/tests/unit/test-line-length.sh): both fixture lines are exactly 130 chars:
```
printf -- '---\n%s\n---\n%s\n' \
    "$(printf 'p%.0s' $(seq 1 130))" \
    "$(printf 'q%.0s' $(seq 1 130))" > "$PROBE_DIR/probe4.md"
```
and the assertion at line 179 is `[ "${_p5##* }" = "1" ]` — count only.

Why it matters: the span line (p) and prose line (q) have identical length, so `sum` is 10 either way; a regression that strips the tail span (last `---` to EOF) and counts the head span yields the identical `…/probe4.md 10 1` and passes. The probe header's claim "stripped with only post-close prose counted" (line 155–156) is therefore pinned only as "exactly one long line counted", not as which one. Not vacuous (empty `_p5` fails the prefix check), and the resolution's documented sabotage direction (strip runs past the close → empty output) is caught; the gap is the inverted-anchor direction only.

### S3 — LOW — b-round sweep record: "measure_file is the only span-parser" is inaccurate

**Provenance: wave-introduced** (the record, resolution.md is part of this diff); the additional parsers are pre-existing.

Evidence — [internal/reviews/0/0/2/3/pr-00235/resolution.md:286-288](repo/internal/reviews/0/0/2/3/pr-00235/resolution.md): "measure_file is the only span-parser, now probe4-pinned." But:
- `scripts/rules-audit.sh:124`: `sed -n '2,/^---$/p' "$1" | …` — a `---`-span parser (meta-field reader; on an unclosed block it reads to EOF, same fail-soft direction class).
- `tests/unit/test-skills-lint.sh:96`: `_close=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' …)` — the lint's own frontmatter span, which the ledger even names in the same sentence before claiming exclusivity for measure_file.

Why it matters: practical impact is nil — both additional parsers take the FIRST close, so neither carries the pseudo-close ambiguity probe4 addresses — but the recorded sweep conclusion is false as written. Recorded class-sweep conclusions are load-bearing in this process (this same wave corrected the a-round's inert grep record under b S1 and a miscount under b S2/Q1); an inaccurate sweep record is the wave's own error class.

## Coverage

**Covered (all 7 sections, in order):** (1) fail-soft inventory over the fix diff — both `2>/dev/null` redirects are rc-checked and fixture-pinned, no new `|| true`, WS_LOCAL/sed degenerates probed fail-loud in all directions (incl. `/local` collapse, empty escape, `{` in path → escape-set gap is fail-loud, recorded clean, not flagged); (2) ERE probed both directions with the exact pattern — caught and claimed-exempt families match the header table exactly, blind-spot slash forms probed; (3) all four new pins sit before the summary gate (:348), match full reason strings, discriminate both directions where negative (scan-err :305–313), mechanism-faithfulness proven by alternative-deletion sabotage probes in scratch, uid guard honest; (4) rc plumbing verified correct POSIX semantics, empty-line guard explained, no silent find-error path found across five failure scenarios; (5) probe4 run live, not vacuous, wrong-mechanism gap = S2; (6) all three recorded sweeps re-run — sweeps 1–2 hold exactly, sweep 3 = S3, sweep counts verified (10 FAIL sites / 17 pins), RM-0116's revised Check text verified claim-by-claim against lane c and rules-audit invariants, `a234763` exists; (7) no unintentional behavior changes in either suite — every hunk maps to an intended fix.

**Deferred:** none. **Not re-reported per instructions:** the documented b B6 `:`-path collateral (header :46–48) and the pre-existing `|| true` at `test-rules-meta.sh:271` (outside the diff, loud by `-s` check). **Could not fully verify:** nothing — every suspicion raised was resolved with one follow-up read or probe.

Checkpoints: `/tmp/opencode/pr-00235-c/checkpoints/checkpoint-S.md` (all sections recorded as completed).

## Axis Q — quality (verbatim)

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| Q1 | LOW | Ledger's b B3 evidence block misdescribes probe4's fixture shape, omitting the pre-close >120 line that makes the pin discriminate | fix-introduced (wave's own evidence text) |
| Q2 | INFO | rules-audit.sh header sentence for invariant 8 is truncated mid-sentence — pre-existing, but RM-0116 now sends readers to that header | pre-existing |

## Detail

**Q1 (LOW) — probe4 evidence block understates the fixture's discriminating construction.**
`internal/reviews/0/0/2/3/pr-00235/resolution.md:216-218`: "probe4 (hr-opened prose with a second `---` before a >120 line) asserts the offending-line count is exactly 1". The actual fixture (`tests/unit/test-line-length.sh:168-170`) is `---` / 130×`p` / `---` / 130×`q` — it contains a >120 line *before* the second `---` too. That pre-close long line is load-bearing: I ran the real `measure_file` on both shapes — actual shape → `probe4.md 10 1`; the ledger-described shape (long line only after the close) → also `10 1`, meaning a pin built exactly as the ledger describes would report count=1 even with the strip disabled and so would not discriminate. The code and the pin assertion (`:179 [ "${_p5##* }" = "1" ]`) are correct and discriminating; the ledger's description of the fixture is wrong in the one detail that matters. Trigger: a future maintainer reconstructs or "simplifies" probe4 from the ledger text and silently loses mutation coverage for the b B3 pin. The sibling claim "the offending-line count is exactly 1" and the probe header (`test-line-length.sh:149-156`) are accurate.

**Q2 (INFO) — truncated header sentence in rules-audit.sh (pre-existing).**
`scripts/rules-audit.sh:27-28`: "# 7. overdue list sorted by lateness; 8. INDEX.md regenerated on every" — followed directly by "# The Phase-2 pending-unit parking valve …"; the sentence never completes ("run." is missing). Cosmetic doc defect; the script is untouched by this wave (the 17a3092..606cc26 diff is 5 files, not including it), and the wave's citation of it (RM-0116.md:16 "blocks on invariants 1–6 and 9 — 7–8 are report-only") is accurate against the code (`block N` → violations → `exit 1` at :325; inv 7 → overdue report-only; inv 8 → regen + echo). Flagged only because RM-0116's rewritten Check paragraph now directs readers to this script.

## Verified-clean highlights (claims measured, not trusted)

- **Counts:** 17 `PIN BROKEN` at HEAD / 13 at `787c3b0` and `17a3092` — "17 pin blocks" (resolution.md:249-250), "14 was a miscount" (:16), and "2 pattern alternatives + 2 miss pins" (:166; `\./local/` + `$WS_LOCAL_ESC` at test-skills-lint.sh:70, pins at :315/:319) all measure true. 10 FAIL sites in `lint_skills` (11th `echo "FAIL` is the :349 summary gate).
- **b S3/S4/B2:** err-isolation negative pin :309-313 exists; find rc captured at :121-122 → `err:find-rc=` sentinel :130-131; opk-find-err fixture scratch-only (`WORK=mktemp -d` :148, `chmod 000` :266), uid guard :322-329; current uid 1001 — "executed as non-root here" true.
- **RM-0116 Check vs enforcement:** extension set exactly `*.md *.sh *.py *.yml` (test-rules-meta.sh:305); SCOPE_FILES skip (:314-315); RM-9xxx strip (:317); the four corpus exclusions match (:307-310); living README in scope, both scratch-pin directions present (:342-353).
- **"Living peers":** README.md is the only living file under `internal/reviews/` (INDEX generated, legacy-index frozen, case folders frozen) — the set is empty today but the enforcement claim matches lane c for present and future files; not a finding.
- **Gates:** INDEX.md:33 carries the current pr-00235 row; tree clean; sabotage-count arithmetic checks out (8 = 1+1+1+1+1+1+2; 4 = 2+1+1); no fixture writes into the real tree (real-tree check :346 is a read-only grep).
- **Commit-vs-claim:** 9cb41b8's message IDs = exactly its diff (2 suites + conventions.md + RM-0116.md); 606cc26 = resolution.md only, and all three "this ledger" corrections are present with #235 b markers where 17a3092 carried the old texts. The corrected a-Gates parenthetical is exact: `ab0f771..a234763` = 15 files, all markdown/tests/`rules-audit.sh` (+1 ACTIVE_SECTIONS line), no Makefile/workflows/`files/`.

## Coverage

Covered: all 6 numbered sections; both wave commits, both test suites, RM-0116, the conventions hunk, the full resolution ledger, lane-c helper, rules-audit block/report structure; three L3 history spot-checks (BRE-form narrative, 14-miscount, a-wave file-class claim) each verified against `git show`/measured counts. Deferred: (1) behavioral re-runs of `rules-audit.sh` (regenerates INDEX.md in-tree — conflicts with read-only mandate) and `test-rules-meta.sh` (its `mktemp -d /tmp/test-rules-meta.XXXXXX` template hardcodes `/tmp`, conflicting with the scratch-only constraint) — enforcement verified at code level instead; (2) reviews lint/parity not re-run (parity regenerates INDEX.md); (3) the a-round "Suite count 21 → 23 pins" claim (unchanged by this diff) and the recorded sabotage-run inventories not re-executed — the pins they reference exist and were discrimination-checked by reading; (4) the 21 a-round disposition rows beyond the b-corrected cells were not individually re-verified (b-round focus per brief). Checkpoints at `/tmp/opencode/pr-00235-c/checkpoints/checkpoint-Q.md`.

## Retracted / ghost findings

None this round — every reported finding verified against the tree at
`606cc26`; nothing was dropped, nothing marked `unverified`.

## Verification (main session)

Every finding re-verified against the tree at `606cc26` before
entering this snapshot; evidence highlights:

- **S1** — ERE probes re-run by the main session against the exact
  `LOCAL_SHAPES` construction (WS_LOCAL computed from REPO_ROOT, sed
  escape, full 4-alternative pattern): CAUGHT `./local/x`,
  `../local/x`, `x/./local/x`, `.././local/x`, `see local/x`, the
  absolute workspace path; MISSED `.//local/x`, `..//local/x`,
  `x/.//local/x` (soft-miss family — `.//local/` and `..//local/`
  resolve into the disposable workspace from the natural CWDs;
  `x/.//local/` ≡ the header-claimed `x/./local/` family), and
  `x//local/y`, `x///local/y`, `//local/x` (≡ `x/local/` / root
  `/local` — exemption territory, header enumerates neither).
  Intended exemptions hold (`~/.local/`, `/usr/local/`, `x/local/`,
  `opencode-local/`, `foo.local/`). The header's NOT-matched list
  (test-skills-lint.sh:39-42) names no doubled-slash form — the
  misses are undocumented, so soft-miss, not deliberate exemption.
  MED upheld: same guard, same soft-miss direction as b B1 (rated
  MED), and the b B1 family claim ("the dot-slash family … incl.
  `x/./local/`") over-states what the ERE delivers.
- **S2** — both fixture lines measured at exactly 130 chars (seq 1
  130 for p and q, test-line-length.sh:168-170); assertion at :179 is
  count-only. Re-ran the named tail-strip mutant (strip from LAST
  `---` to EOF) against the real `measure_file`: probe4 output
  `probe4.md 10 1` — passes probe4's asserts exactly as reported;
  **narrowing:** probe2 under the same mutant outputs EMPTY, so the
  probe FAMILY catches that mutant via probe2 (`_p2` prefix check at
  :177) — the gap is probe4-local assertion strength (which line,
  not how many), not an uncovered mutant direction in the family.
  LOW as reported.
- **S3** — `fm_get()` read at scripts/rules-audit.sh:123-126:
  `sed -n '2,/^---$/p' "$1" | …` is a `---`-span parser (first close;
  unclosed → reads to EOF); test-skills-lint.sh:96 is the close-scan
  span. "measure_file is the only span-parser" (resolution.md:288)
  false as written; both other parsers take the first close, so no
  pseudo-close ambiguity migrates — record-accuracy finding, LOW.
- **Q1** — measured with the real `measure_file` extracted verbatim:
  actual fixture `10 1` stock vs `20 2` with strip disabled
  (discriminates); the ledger-described shape (no pre-close long
  line) `10 1` under BOTH strip on and off — a pin rebuilt from the
  ledger text would be vacuous. The ledger sentence
  (resolution.md:216-218) omits the load-bearing pre-close >120
  line. LOW as reported.
- **Q2** — scripts/rules-audit.sh:27-28 read: the invariant-8
  sentence ends "INDEX.md regenerated on every" and the next comment
  line starts a new sentence. Pre-existing (file untouched by the
  diff), INFO; RM-0116's own citation of the script verified accurate.
- **Pre-launch sabotage re-runs (main session, window closed before
  fan-out):** the resolution's four recorded mutation checks were
  re-executed against the committed tree, each restored immediately:
  `\./local/` alternative deleted → "PIN BROKEN: ./local/ reference
  not caught (b B1)"; `$WS_LOCAL_ESC` alternative deleted → "PIN
  BROKEN: absolute workspace-local reference not caught (b B1)";
  err-append deleted → "PIN BROKEN: find error silently clean (b
  S4/B2)"; strip-runs-past-the-close (line 123 close-reset removed,
  keeping the skip) → "PROBE BROKEN … prose='' pseudo=''" — the exact
  recorded shape (a first variant that removed the skip entirely also
  went red, via the all-counted direction). All four red as recorded;
  tree restored and porcelain-verified empty afterwards.

## Run provenance

- Host: opencode kit-managed session (user `opencode`, uid 1001 —
  non-root, so the uid-guarded find-err pin executed), WSL2, checkout
  `/var/www/vhosts/opencode-permissions-kit/repo`, branch
  `feature/agents-skills-pilot`, tree `606cc26` clean; no opencode
  binary on the agent PATH (version unrecorded). Header date is the
  host-local date; timestamps below are host UTC.
- Commission: maintainer, keyword **micro** over diff
  `17a3092..606cc26`. Measured material 5 files, +272/−52 — above the
  ~50-line micro bound; the pass ran 2 axes (micro ceiling = wave
  floor) with batched greps and targeted reads, no whole-file reads
  beyond the material files. Disclosed here per the scope-parameter
  discipline (review-concept "Parallel reviewer agents").
- Fan-out: 2 reviewer subagents (fresh contexts, provider fast tier
  `zai-coding-plan/glm-5.3-flash`), launched concurrently ≤ 5-cap.
  HOST timestamps: fan-out start 2026-10-23T23:45:29Z, all returned
  by 2026-10-23T23:59:36Z.
- Per-agent windows (checkpoint files; sandbox clocks — observed skew
  ≈ +1 min vs host this round, unlike the +2 h of snapshots a/b):
  both agents' launch stamps 23:46:19Z; final checkpoint writes
  immediately before return, ≤ 23:59:36Z host. Checkpoint side files:
  /tmp/opencode/pr-00235-c/checkpoints/checkpoint-{S,Q}.md (outside
  the case folder per skill choreography and reviews lint rule 6;
  content absorbed here and in the verbatim Coverage lines).
- Sabotage/mutation windows vs readers: none overlapping. All four
  sabotage re-runs happened BEFORE the fan-out launched, each
  followed by `git restore` and a porcelain check; `git status
  --porcelain` verified empty immediately before launch and the tree
  stayed clean throughout the fan-out (no writes into the repo;
  reviewer scratch confined to /tmp/opencode/pr-00235-c/). The
  pre-launch `rules-audit.sh` gate run regenerates INDEX.md in-tree
  by design (inv 8) — byte-identical no-op, porcelain stayed empty.
- Gates run at HEAD 606cc26 by the main session (all green):
  test-skills-lint (17 pins incl. the four new), test-line-length
  (incl. probe4), test-rules-meta (23 pins), test-reviews-lint
  (26 cases), test-reviews-parity (26 rows), scripts/rules-audit.sh
  (0 blocking, 0 overdue), make lint (ShellCheck), check-host
  pre-flight. Reviewer S independently re-ran both touched suites
  green in scratch; reviewer Q deferred behavioral rules-audit /
  test-rules-meta runs (read-only mandate) — both covered by the
  main-session gates above. E2e suites: not owed by this round (no
  `files/`, no root-run script semantics — tests and markdown only,
  agreeing with the resolution's Gates).
- Calibration: single snapshot (wave scope — no second-snapshot
  redundancy owed); skill-led house pass, `Skills: opk-review-pass`
  recorded in the header per RM-0083/reviews-README. Both axes ran
  under the same skill-choreographed session (collapsed axis:
  shared strictness, same model family main+fast); disclosed per the
  reviews-README `Skills:` contract.

## Recommendation

No HIGH findings. The wave's core deliverables verified sound: all
five b-wave code fixes (B1 alternatives, S3 isolation, S4/B2 find-rc
sentinel, B3 probe4, RM-0116 text) are present, green and
discriminating at HEAD — corroborated by both axes' clean lists and
the four sabotage re-runs. The one MED (**S1**) is a remainder of the
same b B1 class: the doubled-slash spellings of exactly the shapes
the fix claims to catch still fall through — cheap to disposition
(one more ERE alternative covering slash-runs of the caught families,
or an explicit exemption line in the header table plus a pinned
fixture for whichever is chosen). The LOW cluster is ledger/pin
hygiene: probe4's count-only assertion (S2, with the probe2 backstop
named), the ledger's probe4 description omitting the load-bearing
pre-close long line (Q1), and the "only span-parser" sweep-record
wording (S3); Q2 is a pre-existing cosmetic truncation now that
RM-0116 points readers at that header. Expectation, not closure:
fixes for S1 (and any pin added for S2) touch test code —
review-relevant per RM-0065 — so a round disposing them owes another
(likely micro) wave review; the stop rule is checked by the next
round or the maintainer, not here. Dispositions are the maintainer's
call.
