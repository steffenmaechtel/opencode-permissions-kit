<!-- review-meta
ID: pr-00235
Snapshot: d
Subject: micro-wave review of the c-wave's fixes — fix wave 3 (collapsed slash-run local/ alternative, probe4 sum pin, audit header sentence)
Scope: wave
Base: 5e55225 (snapshot-c commit; c-wave tip cb22965)
Diff: 5e55225..cb22965
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 2 fresh-context reviewer subagents (glm-5.3-flash; axes S/Q)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review d — c-wave fixes (micro-wave review of fix wave 3)

Fourth snapshot of the case; commissioned by the maintainer over fix
wave 3, which implemented review-c's findings (commit `9fcd197`
tests+rules, `cb22965` resolution ledger). Commissioned scope keyword:
**wave**; measured material 4 files, +142/−24 (the code fix itself
3 files, +41/−13 — at the ~50-line micro bound), so the pass ran the
wave floor of 2 axes (sweep / quality), batched greps + targeted
reads. Wave scope per agent/review-concept.md ("did the fixes break
or lie?"), fan-out per "Parallel reviewer agents"; every reviewer
finding re-verified against the code by the main session before
entering this snapshot (verification marks below; nothing retracted,
nothing unverified). Rotation: conformant — fresh session (E) reviews
the c-session's fixes; no deviation, so no CLEAN-verdict
re-verification mandate from RM-0110.

## Findings index (consolidated)

| ID | Severity | One-liner | Reported by | Provenance | Verified |
|---|---|---|---|---|---|
| W1 | LOW | Header shape table is silent on boundary shapes the ERE factually catches: dot-runs ≥ 3 (`.../local/` — repo-internal, pre-existing catch) and triple-slash spellings (`.///local/`, caught; the header word says only "doubled-slash") | S1, Q1 | detection pre-existing; table gap wave-introduced (the enumerating table is new) | yes (probed, exact pattern, old vs new) |
| W2 | INFO | Dot-terminated segments with slash-runs (`y.//local/x`, `x/y.//local/x`) are newly caught by this wave's collapsed alternative — repo-internal paths, absent from both header lists | S2 | fix-induced (single-slash `y./local/` was pre-existing caught) | yes (probed old vs new) |
| W3 | LOW | Ledger's c S1 sabotage quote transcribes the pin message with a wrap-introduced space (`.// local/`) — the quoted form does not grep against the code string at test-skills-lint.sh:345 | Q2 | fix-induced (this ledger commit) | yes (grep both forms) |

0 HIGH · 0 MED · 2 LOW · 1 INFO over 3 unique findings (4 reported,
4 verified, 0 retracted, 1 cross-corroborated duplicate folded into
W1).

---

## Axis S — mechanical sweep (verbatim)

# Mechanical sweep — fix wave 3, pr-00235 (diff `5e55225..cb22965`)

## Findings index

| ID | Severity | One-liner |
|----|----------|-----------|
| S1 | LOW | Header shape tables incomplete: 3+-dot runs (`.../local/x`) are caught though they resolve repo-internal — absent from both tables |
| S2 | INFO | Dot-terminated segment shapes (`y./local/x`, `y.//local/x`) are caught, undocumented; adjacent documented-exempt `foo.local/` invites the opposite inference |

## Detail

### S1 (LOW) — 3+-dot dot-runs caught, not enumerated in the rewritten header tables

Evidence: `tests/unit/test-skills-lint.sh:78`
```sh
LOCAL_SHAPES="(^|[^.[:alnum:]_/-])local/|\.{1,2}/+local/|$WS_LOCAL_ESC"
```
vs the header table at `tests/unit/test-skills-lint.sh:41-48` (caught
list names `.//local/`, `..//local/`, `x/.//local/`; NOT list names
`x/local/`, `x//local/`, `x///local/`, `//local/` — no 3+-dot entry).
Probed against the exact reconstructed pattern (scratch
`/tmp/opencode/pr-00235-d/scratch-S/probe.sh`): `.../local/x` →
**caught** (the unanchored `\.{1,2}/+local/` matches the substring
`../local/` inside it), same for `..../local/x`. A `...` dirname is
legal and repo-internal, so per the header's own exemption criterion
("none of those resolve into the disposable dir") these shapes should
be exempt — they are flagged instead.

Why it matters: the resolution's Class sweeps (c round) claim "The
header table matches the probes shape-for-shape (claimed == observed)"
— true for the 19 enumerated shapes, but the rewritten table is not
exhaustive against its own semantics. Realistic trigger: prose
ellipsis in a skill doc ("see .../local/notes") produces a
false-positive lint FAIL. Detection itself is pre-existing (the
b-round `\.\./local/` matched the same substring — verified old=1 in
my sweep); the gap is that the c-round table rewrite (the c S1
table-completeness fix) did not enumerate the shape.

### S2 (INFO) — dot-terminated segment family caught, undocumented

Evidence: same pattern, `tests/unit/test-skills-lint.sh:78`; NOT-table
line 46 ("identifier-embedded shapes (`opencode-local/`, `foo.local/`)")
. Probes: `y./local/x` → caught (old pattern too, via `\./local/`
substring); `y.//local/x` and `x/y.//local/` → **newly caught** by
this wave. Semantically `y./local/x` is a two-segment repo-internal
path (dir literally named `y.`), not a workspace ref.

Why it matters: same table-completeness class as S1 — the table
documents `foo.local/` as exempt while the adjacent `y.` family is
caught, and the new doubled-slash catch widens that undocumented
surface. Severity INFO because the realistic trigger is thin: it
requires a segment ending in a literal dot immediately before the
slash (`v1.2/local/` does *not* trigger — the dot is not adjacent to
the slash; verified missed).

## Sections 3–6: clean

- **Pin inventory** — claimed == observed exactly: 10 `echo "FAIL`
  sites inside `lint_skills` (test-skills-lint.sh:84-151); 17
  `case "$_out"` + 1 `case "$_out2"` = 18 (lines 290-364); all pins
  before the summary gate `if [ -s "$TMP" ]` at line 373. New pin
  (`:343-345`) matches `*"FAIL opk-dblslash-local: references
  local/"*` — fixture name embedded, so no other fixture line can
  satisfy it; the err-branch template (`local/ scan errored`) does
  not contain the substring, so the pin discriminates hit vs err.
- **Assertion strength** — fixture measured empirically: probe4 line
  2 = 130 (in-span), line 4 = 131 (post-close); real `measure_file`
  at LIMIT=120 (`test-line-length.sh:69`) emits `<path> 11 1`.
  Empty-output direction covered: `_p5=""` → `${_p5#*probe4.md }` =
  `""` ≠ `11 1` → PROBE BROKEN. Head-count mutant `10 1` rejected.
  Which-line pinning works as claimed (c S2).
- **Fail-soft inventory** — the diff adds no `|| true`, no stderr
  redirect, no pipes; only stderr redirect in the touched region is
  the pre-existing `grep -qE … 2>/dev/null` (`:133`) with its `err:`
  sentinel. New heredoc fixtures fail loud via their pins if the
  write failed. Clean.
- **Behavior scope** — `9fcd197` touches exactly the 3 intended
  files; `cb22965` is resolution.md only. c Q2 comment claim verified
  against `scripts/rules-audit.sh:302-307` (INDEX regen guarded by
  python3 + gen-rules-index.py present). Regression sweep: new
  pattern is a **strict superset** of old on all 37 probed shapes
  (19 claimed + 18 blind-spot) — no shape the b-round caught is lost;
  alternatives 1 and `$WS_LOCAL_ESC` are byte-identical between
  rounds. Resolution's "single code site" sweep record confirmed
  (only test-skills-lint.sh carries the ERE among living
  `.sh`/`.py`).

## Coverage

Covered: exact-pattern reconstruction + empirical 19-shape
verification (claimed == observed), 18 additional blind-spot shapes,
pin counts/placement/strength, probe4 assertion arithmetic +
empty-output direction, fail-soft diff inventory, hunk-to-finding
mapping with old-vs-new superset check. Deferred: re-running the
sabotage gates and `make test` (reader-only role; gates are the
wave's own recorded claim), busybox/non-GNU grep portability (suite
targets this host's GNU grep), the confined-TMPDIR environmental
attribution in the Gates section (environmental, out of axis).
Checkpoints at `/tmp/opencode/pr-00235-d/checkpoints/checkpoint-S.md`;
probes in `/tmp/opencode/pr-00235-d/scratch-S/` — nothing written to
the repo; working tree untouched at cb22965.

## Axis Q — quality (verbatim)

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| Q1 | LOW | Header shape table omits the dot-run>2 boundary the pattern catches: `.../local/` (and dot-terminated tokens like `y.//local/`) are caught but appear in neither list | pre-existing behavior / wave-introduced doc gap (the enumerating table is new) |
| Q2 | LOW | Ledger sabotage quote transcribes the c S1 pin message with a wrap-introduced space — quote ≠ code string | fix-introduced (this ledger commit) |

## Detail

**Q1 (LOW) — caught-shape enumeration misses dot-runs ≥ 3, which the
ERE also catches.**
Evidence: `tests/unit/test-skills-lint.sh:78` —
`LOCAL_SHAPES="(^|[^.[:alnum:]_/-])local/|\.{1,2}/+local/|$WS_LOCAL_ESC"`.
Against input `.../local/`, `\.{1,2}` suffix-matches the last two dots
(position 1: `..` + `/+` + `local/`), so it is caught — likewise any
dot-terminated token before the slash-run (`y.//local/`, `.//local/`
substring). The header table (`test-skills-lint.sh:35-47`) lists
neither in "Matched shapes" nor in the NOT-matched list, and the
ledger's 19-shape sweep (`internal/reviews/0/0/2/3/pr-00235/resolution.md:351-360`)
probes no dot-run > 2. Per the header's own resolution criterion
("none of those resolve into the disposable dir", :46-47), `.../local/`
resolves to a directory literally named `...` — so this is a caught
false-positive shape the rewritten table is silent on. Realistic
trigger: a SKILL.md containing an ASCII-ellipsis path abbreviation,
`.../local/notes`. Secondary, same boundary: the header says "its
doubled-slash spellings `.//local/`, `..//local/`, `x/.//local/`"
(:37-38) while the code also catches triple-slash spellings
(`.///local/`) — the code comment (:72-75, "one-or-more slashes") and
the ledger sweep (`resolution.md:353`) state this correctly; only the
header's "doubled-slash" word under-enumerates. Why it matters: c S1's
deliverable was precisely shape-table completeness; behavior itself is
pre-existing (the old `\.\./local/` matched `.../local/`
identically), so LOW.

**Q2 (LOW) — quoted sabotage message doesn't match the code string
char-for-char.**
Evidence: `resolution.md:379-380` quotes `"PIN BROKEN: .// local/ or
..//local/ reference not caught (c S1)"` (markdown wrap joined with a
space); the code string is `PIN BROKEN: .//local/ or ..//local/
reference not caught (c S1)` (`tests/unit/test-skills-lint.sh:345`).
Grepping the tree for the quoted form fails. Evidently a line-wrap
artifact and the meaning is clear, but quoted evidence is load-bearing
in this process — the c round itself (c S3) corrected an evidence
record for exactly this class. The other two sabotage quotes measure
exact (`tests/unit/test-skills-lint.sh:356`;
`test-line-length.sh:184` format).

## Verified clean

- **Commit-vs-claim:** 9fcd197's message names all three changes its
  diff makes (`scripts/rules-audit.sh` +1 comment line,
  `test-line-length.sh` probe4, `test-skills-lint.sh` shapes); stat =
  exactly those 3 files. cb22965 = `resolution.md` only, and its
  message ("5 findings dispositioned (5 implemented); b-ledger
  corrections (c S3 Q1)") matches the diff (5-row table; span-parser
  wording + b B3 fixture-shape corrections present).
- **Ledger accuracy:** all four claimed-caught slash-run shapes match
  `\.{1,2}/+local/`; all 8 NOT-matched claims verified against the
  ERE; "FAIL sites unchanged at 10" = the 10 `FAIL` emission sites in
  `lint_skills` (`test-skills-lint.sh:86,92,96,103,105,111,115,119,141,144`);
  "17 `case "$_out"` + 1 `case "$_out2"`" measured exact, all pins
  before the summary gate (:374); probe4 `130/131` matches the
  fixture (:170-172), `11 1` arithmetic exact under LIMIT=120 and
  measure_file's documented `<file> <sum-beyond-limit> <count>`
  format (`test-line-length.sh:106`, `:126`), head-count `10 1`
  arithmetic consistent; the c Q1 "load-bearing pre-close line" claim
  is arithmetically true (without it, count=1 with strip on and off);
  fm_get wording exact (`rules-audit.sh:124-127`, `sed -n
  '2,/^---$/p'`); e2e "not owed" reasoning holds — the rules-audit.sh
  hunk is comment-only (`:28` starts with `#`), no `files/` touched,
  matching the AGENTS.md comment-only carve-out; "quoted above" anchor
  for the collapsed alternatives exists (`resolution.md:187`).
- **probe4/measure_file comments:** probe header comment (:153-158)
  matches fixture and assertion; measure_file's comment block
  (:97-107) still describes pinned behavior accurately — the function
  was not modified.
- **rules-audit.sh sentence (:27-28):** complete and accurate — the
  block at :302-312 runs unconditionally in the main flow, guarded
  exactly by `command -v python3` + `-f scripts/gen-rules-index.py`
  (the parenthetical), regenerates with `FORCE_TODAY` and reports
  drift ("INDEX regenerated (was stale)").
- **Citations:** `internal/reviews/0/0/2/3/pr-00235/review-c.md:35-39`
  contains exactly S1 S2 S3 Q1 Q2; every `#235 c …` marker in the
  wave resolves.

## Coverage

Covered all six sections in order (2 and 3 deepest — ERE probed by
hand both directions against every claimed shape). Not re-executed:
the gates' run-claims (`make test`/`make lint` green, reviews
lint/parity green, rules-meta 23 pins, the 3 sabotage runs) —
read-only mandate plus the no-parity/audit-run instruction; verified
at code level instead, no contradictions found. Run-claim
verification is deferred to the main session. Nothing else deferred.

## Retracted / ghost findings

None this round — every reported finding verified against the tree at
`cb22965`; nothing was dropped, nothing marked `unverified`.

## Verification (main session)

Every finding re-verified against the tree at `cb22965` before
entering this snapshot; evidence highlights:

- **W1 (S1/Q1)** — ERE probes re-run by the main session against the
  exact `LOCAL_SHAPES` construction (WS_LOCAL computed from REPO_ROOT,
  sed escape, full 4-alternative pattern), old b-round pattern built
  identically for comparison: `.../local/x` and `..../local/x` CAUGHT
  under both new and old (detection pre-existing; the enumerating
  header table is new in this wave — the gap is wave-introduced);
  `see .../local/notes` (the realistic ellipsis trigger) CAUGHT under
  both; `.///local/x` CAUGHT new, missed old (triple-slash — the
  header's "doubled-slash spellings" wording at
  test-skills-lint.sh:37-38 under-enumerates what the code comment
  at :72-75 states correctly as "one-or-more slashes"); `v1.2/local/x`
  missed under both (dot not slash-adjacent — confirms the boundary
  is exactly the dot-run/dot-terminated family). The header's caught
  list (:35-38) and NOT-matched list (:43-48) name no dot-run ≥ 3 and
  no dot-terminated segment shape. LOW upheld: false-positive family
  with a realistic prose trigger, but pre-existing detection and
  lint-only blast radius.
- **W2 (S2)** — `y.//local/x` and `x/y.//local/x` CAUGHT new,
  missed old (measured, both patterns); `y./local/x` caught under
  both (pre-existing). Repo-internal resolution (dir literally named
  `y.`), absent from both header lists. INFO upheld per the reporter'
  s own trigger assessment: the shape requires a dot-terminated
  segment immediately before a slash-run — contrived in realistic
  skill prose; noted as the same table-completeness class as W1, one
  severity step down.
- **W3 (Q2)** — read at resolution.md:377-380: the quote breaks
  inside the pin string (`.//` end of line, `local/` on the next);
  the code string at tests/unit/test-skills-lint.sh:345 is one line,
  no space after `.//`; a tree-wide grep for the quoted one-line form
  finds nothing. The other two sabotage quotes in the same Gates
  block measure exact. LOW upheld: recorded-evidence accuracy is
  load-bearing (same class the c round itself corrected as c S3).
- **Clean-claim spot re-measurements (main session):** FAIL sites in
  `lint_skills` counted 10; pin case-blocks 17 × `case "$_out"` + 1 ×
  `case "$_out2"` = 18, all before the summary gate; both touched
  suites re-run green at HEAD (see gates below).
- **Pre-launch sabotage re-runs (main session, window closed before
  fan-out):** the resolution's three recorded mutation checks were
  re-executed against the committed tree, each restored immediately:
  (1) collapsed alternative reverted to the b-round two-alternative
  form → `PIN BROKEN: .//local/ or ..//local/ reference not caught
  (c S1)`, suite rc 1; (2) `\{1,2\}` widened to `\.*` (0+ dots) →
  `PIN BROKEN: legit /usr/local or ~/.local path flagged`, rc 1;
  (3) measure_file close-reset removed (skip kept — strip runs past
  the close) → `PROBE BROKEN: … prose='' pseudo=''`, rc 1. All three
  red as recorded; each restore followed by a `git status
  --porcelain` check (empty). Additionally measured in scratch
  (/tmp/opencode/pr-00235-d/scratch-s2, no tree contact): the
  tail-strip mutant's probe4 output is `probe4.md 10 1` — the value
  the old count-only assertion accepted and the new exact-tail
  `11 1` assertion rejects, confirming the c S2 strengthening
  discriminates as claimed.

## Run provenance

- Host: opencode kit-managed session (user `opencode`, uid 1001 —
  non-root), WSL2, checkout
  `/var/www/vhosts/opencode-permissions-kit/repo`, branch
  `feature/agents-skills-pilot`, tree `cb22965` clean; no opencode
  binary on the agent PATH (version unrecorded). Header date is the
  host-local date; timestamps below are host UTC.
- Commission: maintainer, keyword **wave** over diff
  `5e55225..cb22965`. Measured material 4 files, +142/−24 (code fix
  3 files, +41/−13 — at the ~50-line micro bound); the pass ran 2
  axes (wave floor) with batched greps and targeted reads, no
  whole-file reads beyond the material files.
- Fan-out: 2 reviewer subagents (fresh contexts, provider fast tier
  `zai-coding-plan/glm-5.3-flash`), launched concurrently ≤ 5-cap.
  HOST timestamps: fan-out start 2026-10-24T00:20:05Z, both returned
  by 2026-10-24T00:27:40Z.
- Per-agent windows (checkpoint files; sandbox clocks — observed skew
  ≈ +2 h vs host this round: S launch stamp 02:20:46, Q 02:20:41
  against host 00:20:05): both agents' final checkpoint writes
  immediately before return, ≤ 00:27:40Z host. Checkpoint side files:
  /tmp/opencode/pr-00235-d/checkpoints/checkpoint-{S,Q}.md (outside
  the case folder per skill choreography and reviews lint rule 6;
  content absorbed here and in the verbatim Coverage lines).
- Sabotage/mutation windows vs readers: none overlapping. All three
  sabotage re-runs happened BEFORE the fan-out launched, each
  followed by `git restore` and a porcelain check; `git status
  --porcelain` verified empty immediately before launch and the tree
  stayed clean throughout the fan-out (no writes into the repo;
  reviewer scratch confined to /tmp/opencode/pr-00235-d/). The
  main-session `rules-audit.sh` gate run regenerates INDEX.md
  in-tree by design (inv 8) — byte-identical no-op, porcelain stayed
  empty.
- Gates run at HEAD cb22965 by the main session (all green):
  test-skills-lint (18 pins incl. opk-dblslash-local), test-line-length
  (incl. probe4 sum pin), test-rules-meta (23 pins), test-reviews-lint
  (26 cases), test-reviews-parity (26 rows), scripts/rules-audit.sh
  (0 blocking, 0 overdue), make lint (ShellCheck), check-host
  pre-flight. Reviewer S deferred gate re-runs (reader-only role) and
  reviewer Q deferred them plus the run-claims — both covered by the
  main-session gates above and the three sabotage re-runs. E2e
  suites: not owed by this round (no `files/`, no root-run script
  semantics — tests, ledger text and one comment-only script line,
  matching the resolution's Gates reasoning and the AGENTS.md
  comment-only carve-out).
- Calibration: single snapshot (wave scope — no second-snapshot
  redundancy owed); skill-led house pass, `Skills: opk-review-pass`
  recorded in the header per RM-0083/reviews-README. Both axes ran
  under the same skill-choreographed session (collapsed axis: shared
  strictness, same model family main+fast); disclosed per the
  reviews-README `Skills:` contract.

## Recommendation

No HIGH and no MED findings. All three c-wave code fixes (c S1
collapsed `\.{1,2}/+local/` alternative + opk-dblslash-local pin, c S2
exact-tail `11 1` assertion, c Q2 completed audit-header sentence)
are present, green and discriminating at HEAD — corroborated by both
axes' clean lists, the strict-superset regression sweep (no b-round
catch lost over 37 shapes) and the three pre-launch sabotage re-runs.
The findings are table-completeness and evidence-hygiene residue of
exactly the class the c wave itself worked: W1/W2 name boundary
shapes (dot-runs ≥ 3, dot-terminated segments) the rewritten header
table is silent on — W1's detection is pre-existing with a realistic
prose-ellipsis trigger, W2's catch is newly introduced but contrived;
W3 is a wrap-artifact in a quoted sabotage message. All three are
cheap to disposition (one header-table sentence enumerating the
boundary families, one rewrapped quote in the live ledger). A round
disposing them touches test-doc/ledger text only — if it stays in
comments/docs/bookkeeping, the stop rule (RM-0064/0066) can close the
loop; any code/text change beyond that owes the next (likely micro)
wave review. The stop rule is checked by the next round or the
maintainer, not here. Dispositions are the maintainer's call.
