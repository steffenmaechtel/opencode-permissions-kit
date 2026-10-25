<!-- review-meta
ID: pr-00259
Snapshot: a
Subject: micro-shaped wave pass — pin-shape hardening in test-rules-revisit.sh (out_line_is anchoring, V10/V17 cp+cmp, R0 gate comment)
Scope: wave
Base: 0.0.56 @ 02782b9
Diff: 02782b9..886ada1
Date: 2026-10-25
Reviewer: GLM-5.3 house session (opk-review-pass skill) — 2 reviewer subagents (GLM-5.3-Flash, axes W/Q) + main-session verification
Skills: opk-review-pass
-->

# Review a — micro pass on the pin-shape hardening wave (pr-00259)

Round a over commit `886ada1` (branch `feature/231-rules-revisit-pin-shapes`,
base `02782b9` = master, VERSION 0.0.56) — the wave hardens pin shapes in
`tests/unit/test-rules-revisit.sh`: every count needle anchored via a new
`out_line_is` helper, V10/V17 untouched checks switched to `cp` + `cmp -s`,
R0's frozen `FORCE_TODAY` documented as the living gate. The wave implements
the shapes that #222 a W7/W8/W9 and #222 c W4 named (case pr-00222, closed —
this is a fresh strengthening wave under issue #231, born here as case
pr-00259). Commissioned by the maintainer: "Micro Wave Review, Snapshot a,
Pull Request ID: …/pull/259". Scope keyword **micro in shape** (diff =
1 file, +32/−14 = 46 changed lines; recorded as `Scope: wave` per the
header contract), ~5-minute budgets, 2 axes fanned out to fast-tier
reviewer subagents, main session on the strong tier owning verification.

**Result: 3 findings — 0 HIGH, 0 MED, 1 LOW, 2 INFO.** All wave claims
audited held; the two executed sabotage spot-checks (post-fan-out, window
(b)) witnessed the anchor discrimination and the R0 living gate live.

## Findings index

| ID | Severity | One-liner | Provenance | Verification |
|----|----------|-----------|------------|--------------|
| W1 | INFO | Line 522 `contains "$AOUT" "0 blocking"` is the only digit-bearing contains-on-OUT needle left; adjacent to the count class but not `: <digit>`-shaped and not realistically false-greenable | pre-existing | verified |
| Q1 | LOW | Citation sweep incomplete: 2 bare and 5 letter-only finding-ID references remain after the wave's `W4` → `#222 a W4` qualification | pre-existing | verified |
| Q2 | INFO | `out_line_is` (`grep -qxF`) vs sibling `line_is` (`grep -qx`): nominal parallel, divergent needle semantics (fixed string vs BRE) | wave-introduced | verified |

---

## Reviewer output — axis W, mechanical sweep (verbatim)

# Mechanical sweep — test-rules-revisit.sh pin shapes (diff 02782b9..886ada1)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| W1 | INFO | Line 522 `contains "$AOUT" "0 blocking"` is the only digit-bearing contains-on-OUT needle left; adjacent to the count class but not `: <digit>`-shaped and not realistically false-greenable | pre-existing |

All three wave claims verified mechanically. No HIGH/MED/LOW findings.

## Detail

**W1 — INFO — digit-bearing survivor outside the swept family** (pre-existing; untouched by this diff)
`tests/unit/test-rules-revisit.sh:522`:
```sh
if [ "$RC" -eq 0 ] && [ "$ARC" -eq 0 ] && contains "$AOUT" "0 blocking" \
```
The claim "38 contains-on-OUT needles remain, none count-shaped" is exact for the swept `: <digit>` family, but this needle carries a digit in count position (`<digit> <word>`): a hypothetical audit output of `10 blocking` would substring-match `0 blocking`. Why it does not fire: V11's fixture (`tests/unit/test-rules-revisit.sh:513-515`) contains exactly 2 metas, so a blocking count ≥ 10 — the only false-green trigger — cannot occur. Recorded so the claim's boundary is explicit in the snapshot; no realistic scenario, no fix implied.

## Claim verification (mechanical, recorded counts)

- **Claim 1 — `out_line_is` anchors every count needle in this file.** VERIFIED. Helper at `tests/unit/test-rules-revisit.sh:57-59` is `printf '%s\n' "$1" | grep -qxF -- "$2"`. Probes with printf fixtures: line `overdue: 12` does **not** match needle `overdue: 1` (`-x` whole-line), exact lines match, pipeline exit status is grep's and propagates correctly through `if A && B` and `!`, empty haystack no-matches, `-F` makes the needle literal (the `(...)`/`..` in the horizon needles at lines 140/169 would otherwise be regex), `--` guards dash needles. All 6 call sites (lines 120, 138, 140, 145, 159, 169) are the count needles. The count strings are emitted as bare `echo` lines (`scripts/rules-report.sh:123,126,129`) — standalone, no trailing whitespace — so whole-line matching is viable. Strictly stronger than `contains` everywhere it replaced it; **no pin got weaker**.
- **Claim 2 — sweep pattern matches zero sites.** VERIFIED: `grep -nE 'contains "\$OUT" "[^"]*: [0-9]"' tests/unit/test-rules-revisit.sh` → 0 matches.
- **Claim 3 — 38 contains-on-OUT needles remain, none count-shaped.** VERIFIED: count = 38; all 38 enumerated; none ends in `: <digit>`. Sole digit-bearing survivor is W1.

## Sibling sweep (same shape, other sites)

- Cross-suite pattern `contains "\$[A-Za-z_]+" "[^"]*: [0-9]"` over `tests/unit/*.sh` → **0 matches**.
- Variable-digit variant (`: $VAR` needles) → 0 matches. Inline grep-pipeline idiom with `: <digit>` needles → 0; only hits are JSON fixture content in heredocs (`tests/unit/test-reviews-meta-aggregate.sh:58,75`), not assertion needles.
- Non-`$OUT` haystacks in this file: exactly one, `$AOUT` (line 522, W1). No `contains "$M"` / `contains "$WORK…"` calls exist — the other-haystack blind spot is empty.

## V10 / V17 behavior-change check

- **V10** (`tests/unit/test-rules-revisit.sh:470-478`): `cp "$M" "$WORK/v10.before"` at 472 **before** the mutating invocation (473-475); `cmp -s` inside the `if` at 478. **V17** (622-630): cp before `run_revisit`, cmp in the `if` at 630. Both byte-for-byte the V18 (cp 643 / cmp 648) and V20 (cp 674 / cmp 679) precedent shape. No staleness: each `.before` name is single-use per run and written immediately before the invocation; `cmp -s` reds if the meta vanished. The old V10 count-compare (`grep -c '^revisit-interval:'` before/after) was weaker — a content change preserving that count passed it; the new cmp catches it. V17 previously had no untouched assert at all; now symmetric with V20 on the same bad-status die arm. Both changes strictly strengthen.

## R1 boundary pair + R0 living gate

- Fixture (`:135-160`): RM-9002 due 2026-06-15 = T (due TODAY); `rules-report.sh` counts overdue strictly `$1 < t` (line 113) and horizon inclusively `$1 >= t` (line 114) → due-TODAY is horizon, overdue = 1. The anchored pair at `:159` is correct; the `! out_line_is … "overdue: 2"` negation is now redundant given anchoring (only one overdue line exists) but harmless and intentional per the diff comment. No realistic input satisfies the pair wrongly.
- R0: 116 active metas under `internal/rules-meta/`, zero with `next-revisit < 2026-10-16` → anchored `overdue: 0` is green on the current tree.
- Suite run from repo root: `rules-revisit pins: OK (39 pins green)`, rc=0 — matches the commit's "39 → 39".

## Coverage

Covered: helper correctness probes (anchoring, status propagation, -F/`--`, empty haystack); all three sweep claims with recorded counts; full enumeration of the 38 remaining needles + `$AOUT`; cross-suite sweeps (contains-based, variable-digit, inline-grep idioms); V10/V17 ordering vs V18/V20 precedent; R1 boundary semantics against `rules-report.sh` overdue logic; R0 real-tree state; live suite run. Deferred: none — the only shape adjacent to the class that I judged rather than flagged is W1, with the non-trigger reasoning recorded in the snapshot. Checkpoints at `/tmp/opencode/pr-00259-a/checkpoints/w-sweep.md`.

---

## Reviewer output — axis Q, quality/claim audit (verbatim)

# Quality axis review — diff 02782b9..886ada1 (`feature/231-rules-revisit-pin-shapes`)

## Findings index

| ID | Severity | One-liner | Provenance |
|----|----------|-----------|------------|
| Q1 | LOW | Citation sweep incomplete: 2 bare and 5 letter-only finding-ID references remain after the wave's `W4` → `#222 a W4` qualification | pre-existing |
| Q2 | INFO | `out_line_is` (`grep -qxF`) vs sibling `line_is` (`grep -qx`): nominal parallel, divergent needle semantics (fixed string vs BRE) | wave-introduced |

No HIGH/MED findings. All checkable commit-message claims verified against the tree; no unintentional behavior changes found.

## Detail

### Q1 — LOW · Citation sweep incomplete · pre-existing

`agent/conventions.md:204-210`: "Always qualify the ID — two citation eras: … `(#176 a W1)` — PR number, snapshot letter, finding ID." The wave qualified one reference (test file `:619`, `(#222 a W4: …)`) but the file still contains:

- `tests/unit/test-rules-revisit.sh:530` — `#      the rewrite validates each field occurs exactly once (W1 pin:` — **bare**, zero qualification (V12 comment)
- `tests/unit/test-rules-revisit.sh:668` — `#      W4 split -- it must die rc=2 (run the audit), never fall into a` — **bare** `W4`, 49 lines below the wave's own qualified `#222 a W4` at `:619`; a grep for `W4` now returns both a compliant and a non-compliant hit for the same ID
- Letter-only, missing the PR number: `:227` `(a W3 pin:`, `:569` `(b W2: built from a`, `:638` `(b W2)`, `:655` `-- b W1: this die arm was`, `:669` `(b W3: pinned shape`

Why it matters: the PR number is the disambiguator the rule exists for ("parallel features can never collide"); `b W2` forces the reader to guess the birth case. `review-b.md` exists under `internal/reviews/0/0/2/2/pr-00222/`, but other cases have b snapshots too, so the reference is not resolvable from the file alone. The commit message claims only the singular qualification ("its bare 'W4' comment reference is qualified") — accurate about its scope — but the file as a whole does not comply with the house rule. (`L1` refs at `:191`, `:468` are learnings classes, not finding IDs — out of scope.) All flagged lines are untouched by this diff.

### Q2 — INFO · helper asymmetry · wave-introduced

`tests/unit/test-rules-revisit.sh:53-59`:
```sh
line_is() {  # $1 file, $2 exact line -> pass/fail on first match
    grep -qx -- "$2" "$1"
}

out_line_is() {  # $1 haystack string, $2 exact line -> anchored needle
    printf '%s\n' "$1" | grep -qxF -- "$2"
}
```
The names, arg order, and doc-comment style are parallel, but the matching semantics differ: `line_is` treats the needle as a BRE, `out_line_is` as a fixed string (`-F`). `-F` is the correct choice for `out_line_is` (its needles contain `(` and `.`); the observation is only that the parallel naming does not signal the semantic difference — a needle with regex metacharacters behaves differently depending on which helper receives it. No house rule governs helper symmetry (checked `agent/conventions.md`; nothing found), so this is suggestion-grade.

## Verified clean (claims audited, no finding)

- **Suite count 39 → 39**: `grep -cE '^\s*(pass|fail) '` = 39 at base and HEAD; live run at 886ada1 (worktree == HEAD, clean): `rules-revisit pins: OK (39 pins green)`.
- **"All four changes"**: the commit's grouping (anchor sweep / V10 / V17 / R0 comment) covers exactly what the diff contains — 7 anchored needles (R0 `:120`, R1 `:138-145` + boundary pair `:159`, R2 `:169`), V10 `cp`+`cmp -s` (`:472-478`), V17 `cp`+`cmp -s` + qualification (`:619-630`), R0 comment (`:112-116`). No miscount, no misname.
- **"Tests only"**: `git diff --stat` = 1 file, `tests/unit/test-rules-revisit.sh`.
- **R0 comment mechanics**: unset `RM_AUDIT_ROOT` → `rules-report.sh:43` resolves ROOT to the repo; `awk '$1 < t'` (`:113`) puts any active meta with next-revisit < 2026-10-16 into overdue; `:123` prints `overdue: N` (N≥1), which fails the exact-line needle `overdue: 0` → pin red, while RC stays 0 (`:15-17`). Backdated and revisit-left-undone both land pre-freeze. "Maintain the tree, never the date" is consistent — the comment scopes itself to "falls before 2026-10-16" and does not overpromise about future neglect. Live: 118 metas, 116 active (matches the commit's "116 real active").
- **"38 contains-on-OUT needles remain, none count-shaped"** and **"sweep pattern matches zero sites"**: count = 38; verbatim pattern `contains "$OUT" "[^"]*: [0-9]"` → zero matches, reproduced twice (an initial contradicting hit was my own variant pattern, not the tree).
- **V10/V17 comment truthfulness**: interpreter die at `rules-revisit.sh:79-81` and bad-status die at `:98` both precede the only write path (`:145-164`); "dies before any write" holds in both arms. V17 (paused) and V20 (missing status) both die at `:98` — "same die arm" is exact. Old V10 check (frontmatter `revisit-interval:` line count) missed value mutations and outside-frontmatter changes; `cmp` is a strict superset — "strengthen" loses no coverage. V12/V13/V18/V20 already used the `cp` + `cmp -s` + `<pin>.before` pattern (`:559/:575/:643/:674`) — provenance and scratch-naming claims true.
- **Boundary-pair claim**: count 12 satisfies the old substring positive (`"overdue: 1"` ⊂ `"overdue: 12"`) and dodges the old negation — the new comment's arithmetic is exact; the anchored pair reds it.
- **Attributions real**: `#222 a W4`/`W8`/`W9` verified at `internal/reviews/0/0/2/2/pr-00222/review-a.md:31,35,36` with matching semantics; no dead helpers, no dead variable (`before` removed with its sole use).

## Coverage

Covered: all five budgeted sections plus a live suite run at the reviewed commit, real-tree counts, `#222` case-folder verification of the wave's citations, both die-arm mechanics, the cmp-superset analysis, and reproduction of the commit's sweep-pattern claim. Deferred: the six sabotage-matrix rows are historical and were not re-run (per instructions); their described pinned shapes were verified present as described (R1 boundary pair `:159`, V17 paused cmp `:623-630`, V20 untouched `:674-679`). Not resolved: which birth case the pre-existing letter-only refs (`b W1/W2/W3`, `a W3`, bare `W1`) map to — inherent to their being under-qualified; recorded in Q1 rather than chased. Nothing remains `unverified`.

---

## Main-session verification log (strong tier)

| # | Item | Verified how | Verdict |
|---|---|---|---|
| 1 | Sweep claims (38 remains / 0 count-shaped sites) | own greps at pre-flight, independent of both reviewers: `grep -c 'contains "$OUT"'` = 38; sweep pattern → 0 matches | HOLDS |
| 2 | Suite count 39 → 39 | `grep -cE '^\s*(pass|fail) '` = 39 at HEAD; suite prints "39 pins green" (run 3× this session, incl. post-restore) | HOLDS |
| 3 | W1 no-trigger reasoning | read V11 fixture (`:513-527`): exactly 2 metas in `$GSCRATCH`; blocking ≥ 10 unreachable; needle shape is `<digit> <word>`, outside the swept `: <digit>` family | HOLDS (INFO) |
| 4 | Q1 inventory + rule source | own grep re-found all 7 sites (`:227`, `:530`, `:569`, `:638`, `:655`, `:668`, `:669`); rule read at `agent/conventions.md:202-213`; every site outside the diff hunks → pre-existing | HOLDS (LOW) |
| 5 | Q2 helper asymmetry | read both helper bodies in the diff (`:53-59`): `grep -qx` (BRE) vs `grep -qxF` (fixed) | HOLDS (INFO) |
| 6 | Anchor discrimination (SC1, live) | /tmp fixture root with 12 overdue metas → real `rules-report.sh` output `overdue: 12`; anchored needle `overdue: 1` exits 1 (pin reds), old contains shape exits 0 (false green), anchored `overdue: 12` exits 0 — the commit's sabotage row (1) mechanism reproduced on production output | WITNESSED |
| 7 | R0 living gate (SC2, live) | tree sabotage (post-fan-out, window (b)): `:117` FORCE_TODAY 2026-10-16 → 2026-11-25 ⇒ report `overdue: 116` (rc=0) ⇒ R0 lane RED, suite rc=1; `git restore`; re-run → "OK (39 pins)", tree clean — commit's sabotage row (4) reproduced; also confirms the new R0 comment's semantics ("the report stays rc=0; the pin reds via the needle") | WITNESSED |

No reviewer claim required retraction or an `unverified` mark; every
finding entered the index above after independent verification.

## Retracted/ghost findings

None — no finding retracted, no claim dropped. Two candidates were
evaluated by the reviewers and consciously kept at INFO with their
non-trigger reasoning recorded (W1) or sourced to no house rule (Q2).

## Run provenance

- **Commission:** USER (maintainer), in-session — "Micro Wave Review,
  Snapshot a, Pull Request ID:
  github.com/steffenmaechtel/opencode-permissions-kit/pull/259".
- **Pass shape:** fan-out capable main session (GLM-5.3, strong tier,
  verification duty) + 2 reviewer subagents on the fast tier
  (`zai-coding-plan/glm-5.3-flash`, agent `general`): axis W (mechanical
  sweep), axis Q (quality/claim audit). Staged launch, 2 of ≤ 5 seats.
  Both axes ran under the `opk-review-pass` choreography (see `Skills:`).
- **Host timestamps:** fan-out start `2026-10-25T00:21:36Z`, end
  `2026-10-25T00:33:32Z` (716 s window, both agents returned inside it).
- **Agent windows (sandbox stamps, unnormalized):** W launch
  1792887768.89 → return 1792889060.00; Q launch 1792887770 → return
  1792890100. Observed skew: both sandbox-claimed durations (≈1292 s,
  ≈2330 s) exceed the host window — the sandbox clocks drift, so the
  host window is the authoritative concurrency record; sandbox stamps
  are recorded as reported.
- **Checkpoints:** `/tmp/opencode/pr-00259-a/checkpoints/w-sweep.md`,
  `q-quality.md` — both agents stamped launch/return and appended per
  section (absorbed into this snapshot; scratch lives outside the tree).
- **Mutation/sabotage windows:** none during the fan-out — the tree was
  a clean read substrate (`git status --porcelain` empty before launch
  and after return). Post-return spot-checks (window (b)): SC1 ran
  entirely on a `/tmp/opencode/pr-00259-a/sc1` copy (no repo bytes
  touched); SC2 mutated `tests/unit/test-rules-revisit.sh:117` only,
  observed R0 RED, restored via `git restore` (tree committed at
  886ada1, clean — restore resets to HEAD), re-ran the suite green.
  No readers existed during either window → no bidirectional screening
  owed.
- **Environment:** checkout at `/var/www/opencode-permissions-kit`,
  branch `feature/231-rules-revisit-pin-shapes`, clean at 886ada1
  (base 02782b9 = master, VERSION 0.0.56); host pre-flight
  `sh tests/check-host.sh` green at session start.

## Gates

Run before this snapshot commit (check-then-commit, RM-0117):

- `sh tests/unit/test-rules-revisit.sh` — PASS ("rules-revisit pins:
  OK (39 pins green)", post-restore re-run).
- `make lint` — PASS (ShellCheck).
- `sh tests/unit/test-line-length.sh` — PASS (snapshot files exempt by
  design: `internal/reviews/*/pr-*/review-*`, "verbatim > wrap").
- `python3 scripts/gen-review-index.py` — INDEX regenerated (new case
  pr-00259 row).
- `sh tests/unit/test-reviews-lint.sh` — PASS.
- `sh tests/unit/test-reviews-parity.sh` — PASS.

## Calibration

Micro shape — no second independent snapshot owed (release scope only).
Redundancy here: two independent fast-tier axes (sweep + claim audit)
whose outputs were cross-checked against each other and against the
main session's own pre-flight counts (38/0/39 measured before the
fan-out launched), plus strong-tier verification of every finding and
two live sabotage re-enactments. Hunt and verify stayed separated
(subagents hunted, main session verified). Both axes ran WITH this
skill's choreography — no external no-skill pass ran for this case;
that axis is collapsed by commissioning, disclosed here and via the
`Skills:` header line.

## Recommendation

Dispositions owed from round a: **Q1 (LOW)** — actionable; a fix wave
qualifying the 7 named references is a comment-only change in a test
file. **W1/Q2 (INFO)** — no code change implied; natural disposition
"deliberately not done" with the recorded reasoning, or ride the same
comment-only wave if the maintainer prefers. Stop-rule expectation,
check cited (RM-0115): a fix round touching only comment bytes in
`tests/unit/test-rules-revisit.sh` leaves review-relevant code
untouched (comments are not review-relevant, RM-0065/RM-0066) — closure
is the maintainer's or the next round's call, not this round's. No
resolution exists yet; it is created with the first fix commit. No
reviews owed-but-not-run: both commissioned axes ran.
