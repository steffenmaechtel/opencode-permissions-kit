# Resolution — pr-00235 (agent-skills pilot, issue #178)

Status: closed (maintainer, 2026-10-24) — fix wave 4 (`2b71a69` +
this ledger) stayed comment/ledger-only: no review-relevant code
touched (RM-0065), loop closed per RM-0066; check cited in
Gates (fix wave 4).

Chain: review-a (snapshot 2026-10-23, 21 findings) → fix wave
2026-10-24 (`787c3b0` tests, `d77a446` rules, `b549a22` skill/docs)
→ review-b (snapshot 2026-10-24, 15 reported / 12 unique findings,
1 retracted) → fix wave 2 (`9cb41b8` tests+rules) → review-c
(snapshot 2026-10-24, 5 findings) → fix wave 3 (`9fcd197`
tests+rules) → review-d (snapshot 2026-10-24, 3 findings) → fix
wave 4 (`2b71a69` comment-only + this ledger) — loop closed
(RM-0066; check cited in Gates, fix wave 4).
a-round: all 21 dispositioned **implemented**; none deliberately not
done (maintainer go 2026-10-24: "implement all"). b-, c- and
d-round: one dispositions table each below.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a S1 (MED) | **implemented** | `787c3b0` | strip conditional on closure; probe3 unclosed fixture; sabotage red→green |
| a S2 (MED) | **implemented** | `787c3b0` | 10 FAIL sites, 13 pins — 14 was a miscount (#235 b S2/Q1) |
| a S3 (LOW) | **implemented** | `787c3b0` | pattern `(^|[^.[:alnum:]_/-])local/|\.\./local/`; both-direction pins |
| a S4 (LOW) | **implemented** | `787c3b0` | close via awk NR scan, no head window; S4-sabotage (19-line fm) moot |
| a Q1 (MED) | **implemented** | `b549a22` | mapping written in reviews README + SKILL.md; matches recorded practice |
| a Q2 (MED) | **implemented** | `d77a446` | meta cites pin 10 (test suite) not audit invariant; audit = inv 1–6, 9 |
| a Q3 (MED) | **implemented** | `d77a446` | Check is the two runnable suites; exemptions named; closed world scoped |
| a Q4 (MED) | **implemented** | `d77a446` | README cites file+section; lane c narrowed to frozen corpus; pins + Sab C |
| a Q5 (LOW) | **implemented** | `b549a22` | SKILL.md names all three windows incl. scratch worktree |
| a Q6 (LOW) | **implemented** | `787c3b0` | header names 2.x v2.1.4 artifacts + 1.x bare-continue lane |
| a Q7 (LOW) | **implemented** | `b549a22` | list completed + re-measured 2026-10-24: 9/42 red, all nine named |
| a Q8 (LOW) | **implemented** | `d77a446` | ACTIVE_SECTIONS line + bullet unit shape + n1c pin; Sab A red |
| a Q9 (INFO) | **implemented** | `b549a22` | AGENTS.md: "5 concurrent reviewers on any tier — account-wide" |
| a Q10 (INFO) | **implemented** | `b549a22` | Layout bullet + docs/README.md internal map entry |
| a Q11 (INFO) | **implemented** | `787c3b0` | header states the frontmatter-switch regen measured a no-op |
| a X1 (LOW) | **implemented** | `787c3b0` | same fix as a S3 (merged disposition) |
| a X2 (INFO) | **implemented** | `787c3b0` | per-file grep, rc>1 → FAIL; dangling-symlink pin uid-independent |
| a X3 (LOW) | **implemented** | `787c3b0` | wc -c measurement; header documents byte semantics; real skill 391 B |
| a X4 (LOW) | **implemented** | `787c3b0` | fields read only between fences; body-field fixture + sabotage |
| a X5 (LOW) | **implemented** | `b549a22` | base location named in SKILL.md + review-concept checkpoint unit |
| a X6 (INFO) | **implemented** | `787c3b0` | same fix as a S1 (merged disposition) |

## Evidence detail

### a S1 / a X6 — unclosed frontmatter exempted the whole file

measure_file now pre-checks closure (awk, exit-status form): the
frontmatter strip applies only when a closing `---` exists; an
unclosed leading `---` (horizontal rule or broken fence) counts in
full. Probe grew a fourth fixture (probe3.md: `---` + >120 line,
never closed → must produce output); the probe message asserts all
four directions. Sabotage (strip made unconditional — the exact old
behavior): `PROBE BROKEN: ... unclosed=''`, rc 1; restored green.
Class sweep: all 117 scoped `.md` files that open with `---` were
verified to close at fix time; the 35-entry baseline regen stayed a
no-op before and after the metric change (the stale-baseline check
keeps previously-baselined files pinned regardless).

### a S2 — unexercised FAIL branches

All 10 FAIL sites now have executing fixtures: root missing
(`_out2` call), must-open (opk-broken-open), never-closes
(opk-unclosed), >400 description (opk-long-desc, 401 bytes asserted),
plus the pre-existing five. Negative pins: opk-legit-paths (system/
XDG paths not flagged), opk-good-skill clean. Sabotages red:
fixture-file deletion → "PIN BROKEN: missing opening --- not caught";
err-line deletion → "scan error silently clean".

### a S3 / a X1 — `local/` over-match

Pattern narrowed to `(^|[^.[:alnum:]_/-])local/|\.\./local/`: matches
workspace shapes (`local/x`, `../local/x`, backtick/paren/space-
prefixed), excludes `~/.local/…`, `/usr/local/…`, `opencode-local/`
(hyphenated identifiers). Fixture opk-legit-paths carries both legit
shapes and must stay unflagged; opk-local-ref carries both forbidden
shapes. Sabotage (pattern widened to plain `local/`): "PIN BROKEN:
legit /usr/local or ~/.local path flagged".

### a S4 / a X4 — head window + unbounded extraction

Close detection: `awk 'NR > 1 && $0 == "---" { print NR; exit }'` — no
20-line window. name:/description: extraction runs only for
`NR > 1 && NR < close`, so body lines cannot satisfy frontmatter
checks (fixture opk-body-field: body lines `name: anything` /
`description: max 400 bytes` → still FAILs empty description).
Sabotage (both `NR < c` bounds deleted): "PIN BROKEN: body-field
extraction leak (X4)". Field checks are gated on a closing fence
existing (an unclosed file reports its primary defect without
cascading).

### a X2 — grep error read as clean

The scan is per-file (`find -type f -o -type l` + grep operand) so a
dangling symlink reports rc 2 deterministically regardless of uid
(direct `grep -r` on a dir-internal symlink skips it silently — found
red while pinning, exactly the L1 class). rc>1 → `FAIL … scan errored`;
fixture opk-scan-err carries a dangling symlink; error output stderr-
redirected (pinned per the fail-loud rule).

### a X3 — byte/char semantics

`_dlen=$(printf '%s' "$_desc" | wc -c)` — deterministic bytes on
dash/bash/CI; header documents the choice and why (sibling test
documents its awk byte metric the same way). Real skill description:
391 bytes (snapshot-a corrected the reviewer's 400 figure). The
no-local-green/CI-red drift is gone because the metric no longer
depends on the shell.

### a Q2 / a Q3 / a Q4 / a Q8 — rule text vs enforcement reality

- RM-0116 meta: enforcement citation now "tests/unit/test-rules-meta.sh
  pin 10, lanes a–c; the audit script itself carries invariants 1–6
  and 9" (verified: rules-audit.sh header + block calls; rules-meta.md
  documents 1–9; the test header says "invariants 1-9 plus the
  no-fake-findings pin 10"). Check = the two runnable suites; lane c's
  exemptions named (rules-meta itself, generated review indexes, frozen
  case folders, records archive) and the README's in-scope status
  stated. Review log carries the revision with case citation.
- conventions rule unit: bullet shape (consistent with siblings),
  states the closed world's scope; RM-0116 quote needle ("Every RM key
  appears exactly") untouched — audit green.
- internal/reviews/README.md: the two ID citations replaced by
  file+section references ("Suites are the standing review", "Parallel
  reviewer agents" in agent/review-concept.md).
- Lane c narrowed via shared helper `p10_lane_c_hits` (real tree +
  scratch pins use the same code, so pins cannot drift): exclusion set
  is `/internal/rules-meta/`, `INDEX|legacy-index` at the reviews
  root, the case-folder shard pattern, `_archive`. Scratch pins both
  directions: living README citing an ID → caught; frozen snapshot in
  a case folder → exempt. The demo ID is runtime-concatenated so the
  test source carries no literal token (first run went red on exactly
  that self-match). Sabotages red: registration line deleted →
  "inv1 RM-keys section enforced: audit exited 0"; exemption widened
  to the whole reviews dir → "lane c scratch: README citation not
  caught"; a real RM ID appended to the README → suite rc 1 naming
  file+line.
- ACTIVE_SECTIONS registers `agent/conventions.md#referencing-house-
  rules-rm-keys` (n1c pins it load-bearing, mirroring n1b).
- Suite count 21 → 23 pins ("21 pins" appears only in frozen snapshots).

### a Q1 / a Q5 / a X5 / a Q9 / a Q10 / a Q7 / a Q6 / a Q11 — consistency pairs

- Q1: micro→Scope mapping defined on both sides — reviews README
  "Snapshot format" (authoritative) + SKILL.md step 6.1; wording
  matches the existing practice (pr-00208/pr-00222/pr-00224 review-b
  headers carry `Scope: wave` with micro Subjects).
- Q5: SKILL.md sabotage windows restored to three (before launch /
  after all return / scratch worktree) — matches review-concept.
- X5: checkpoint base location named in SKILL.md pre-flight (session
  scratch outside the reviewed tree, e.g. /tmp/opencode/<case>-
  <letter>/) AND in the review-concept checkpoint unit (RM-0086 quote
  needle untouched); conflicts named (clean tree, reviews lint rule 6).
- Q9: AGENTS.md cap phrasing aligned to review-concept ("5 concurrent
  reviewers on any tier — the provider's burst limit is account-wide").
- Q10: `.agents/skills/` added to AGENTS.md Layout and docs/README.md
  "Internal documentation" map (plain text, no dangling link).
- Q7: list completed and re-measured 2026-10-24 twice (d77a446 and
  final b549a22, fresh clones each, all 42 suites): 9 red — docs,
  line-length, reviews-lint, reviews-meta-aggregate, reviews-parity,
  rules-index-parity, rules-meta, rules-revisit, skills-lint; 33
  green. The claim now names all nine.
- Q6: loader-behavior claim names its lane (2.x v2.1.4 SkillFile/
  Skipped artifacts; 1.x bare continue) — both verified against the
  pinned clones during snapshot-a verification.
- Q11: header now states the frontmatter-switch regen measured a no-op
  (35 entries, unchanged) instead of implying a reviewed diff.

## Dispositions — review b (fix wave 2, 2026-10-24)

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| b B1 (MED) | **implemented** | `9cb41b8` | 2 pattern alternatives + 2 miss pins (sabotage-red); x/-family exempt |
| b S1 (MED) | **implemented** | this ledger | sweep grep corrected to `-E` form; result re-measured (Class sweeps) |
| b S2/Q1 (LOW) | **implemented** | this ledger | 14→13 pin count corrected in a-row + Class sweeps |
| b S3 (LOW) | **implemented** | `9cb41b8` | fixture description no longer self-matches; err-isolation negative pin |
| b S4/B2 (LOW) | **implemented** | `9cb41b8` | find rc observed → err: sentinel; opk-find-err pin (uid-guarded, L4) |
| b Q2/B4 (LOW) | **implemented** | `9cb41b8` | Check text names extension set + SCOPE_FILES/RM-9xxx exemptions |
| b Q3 (INFO) | **implemented** | `9cb41b8` | "blocks on 1–6 and 9 (7–8 report-only)" replaces "carries" |
| b Q4 (INFO) | **implemented** | this ledger | Gates parenthetical names the real file classes |
| b B3 (LOW) | **implemented** | `9cb41b8` | probe4 pins pseudo-close semantics; probe header claims corrected |
| b B5 (INFO) | **deliberately not done** | — | rule-6 + shard pins backstop; coupling already in Follow-ups |
| b B6 (INFO) | **deliberately not done** | — | fail-loud direction only; acceptance documented in the header |

Beyond findings (maintainer directive 2026-10-24): conventions.md
"(this README's peers)" → "— `internal/reviews/README.md` and its
living peers —" (explicit path; b S5 was retracted in the snapshot,
the wording improved anyway).

### b B1 — local/ guard soft-miss shapes

Pattern now `(^|[^.[:alnum:]_/-])local/|\.\./local/|\./local/|…` plus
this checkout's absolute workspace-local path (`WS_LOCAL`, computed
from REPO_ROOT at runtime, escaped for ERE — the opk-abs-local
fixture derives its reference from the same variable, so pattern and
pin relocate together). The dot-slash family (`./local/`,
`x/./local/`, `.././local/`) is caught by the new `\./local/`
alternative. New fixtures opk-dot-local + opk-abs-local pin the miss
direction; both sabotage-red (alternative deleted → "PIN BROKEN").
Deliberately out of scope, pinned as such via opk-legit-paths:
repo-internal segments (`x/local/`, `x//local/`) and
identifier-embedded shapes — none of them resolve into the disposable
workspace dir; the suite header documents the full shape table.
(#235 c S1 supersedes the two dot alternatives quoted above: they
are collapsed into `\.{1,2}/+local/`, which also catches their
doubled-slash spellings — see the c-round table.) L1
note: if REPO_ROOT resolution ever degenerated, WS_LOCAL would
collapse to "/local" and false-FAIL `/usr/local` paths — fail-loud,
not silent.

### b S3 / b S4/B2 — scan stages isolated and loud

opk-scan-err's description no longer contains a ` local/ ` substring
(the old text tripped the hit branch alongside err); a negative pin
asserts the err path now fires alone. The find stage got its own rc
check: `_flist` capture preserves find's exit status and rc > 0
appends an `err:find-rc=…` sentinel → the existing "scan errored"
FAIL. New fixture opk-find-err (valid frontmatter + mode-000 subdir)
pins it; the pin is uid-guarded (root reads through 000 — skip line
per L4 environment-dependent marking); executed as non-root here.
Sabotage-red: err append deleted → "PIN BROKEN: find error silently
clean".

### b B3 — pseudo-close semantics pinned

probe4 (fixture: `---` / 130-char line / `---` / 131-char line —
the >120 line BEFORE the close is load-bearing: without it the
count is 1 with the strip on AND off, i.e. non-discriminating;
description corrected #235 c Q1) asserts the offending-line count
is exactly 1: the span up to the
next `---` counts as frontmatter, post-close prose does not. That
pins the documented semantics (closure = next `---` line anywhere;
YAML validity not assessed) in place of the overstated "both
directions" claim; measure_file's comment and the probe header state
it. Sabotage (strip runs past the close) → PROBE BROKEN with
prose=''/pseudo=''. (#235 c S2 strengthens the assertion to the
exact tail `11 1` — the sum now pins WHICH line was counted.)

### b Q2/B4, b Q3 — RM-0116 Check text vs enforcement

The Check paragraph now names the scanned extension set (md/sh/py/yml
— e.g. the frozen JSON corpus under `internal/reviews-meta/` is not
scanned), the two non-obvious exemptions (SCOPE_FILES → lane a;
RM-9xxx demo IDs) alongside the four corpus sets; the invariant
citation reads "blocks on invariants 1–6 and 9 (7–8 are
report-only)". Review log carries the revision; test-rules-meta and
rules-audit green (inv5 needle, inv9 unaffected).

### b S1 / b S2/Q1 / b Q4 — ledger corrections

Corrected in place with #235 b markers: the a S2 row (13 pins), the
Class sweeps section (`-E` grep + re-measured result, pseudo-close
claim, 17-pin growth), the a-Gates parenthetical (real file classes).

## Class sweeps (a round, recorded)

- Frontmatter-strip directions: 4 probe fixtures at the time
  (closed-fm, prose, non-md, unclosed) — the "both failure
  directions pinned" claim was overstated: the pseudo-close variant
  (strip through a LATER `---` line) stayed unpinned until the b
  round's probe4 (#235 b B3).
- FAIL-site inventory (skills lint): 10 sites ↔ 13 pins at the time
  (14 was a miscount, #235 b S2/Q1; the b round grows the suite to
  17 pin blocks); grep pattern used for the sweep: `echo "FAIL` over
  lint_skills vs the pin case-block.
- RM-ID citations in wave-added text: `git diff caeb9a8..9cfef7f |
  grep '^+' | grep -E 'RM-[0-9]{4}'` (`-E` added 2026-10-24, #235
  b S1 — the recorded BRE form `grep 'RM-[0-9]{4}'` was inert: `{4}`
  is a literal in BRE and the pipeline matched nothing) → the two
  reviews-README ref lines (fixed by this wave) plus meta-internal
  diff noise (`+++ b/…RM-*.md`, `id:`, INDEX row); lane c now
  enforces the living README going forward.
- Scope-keyword consistency: skill scope table ↔ README Scope enum —
  both sides now define micro→wave.
- Sabotage windows: 3 windows consistent across skill and rules.

## Gates (fix wave)

- `make test` green at `b549a22` (full unit suite).
- `make lint` (ShellCheck, shipped scripts) green; `sh
  scripts/rules-audit.sh` 0 blocking; reviews lint/parity green (26
  cases); line-length green incl. no-op regen; sandbox policy green.
- Sabotage runs: 8 mutation checks red against the intended pins
  (S1×1, S2×1, S3×1, X2×1, X4×1, Q8×1, Q4×2), each restored and
  re-verified green.
- e2e suites: not owed — the wave and its fixes touch no `files/`
  script and no root-run script semantics (the diff is tests,
  markdown and `scripts/rules-audit.sh` only — no Makefile or
  workflows; corrected #235 b Q4).

## Class sweeps (b round)

- Fail-soft inventory over the fix diff: the only stderr redirects
  are find (rc now checked and pinned) and the per-file grep (pinned
  via opk-scan-err); `WS_LOCAL` escape pipeline assessed under b B1
  (fail-loud direction); no new `|| true`.
- `local/` pattern sites: single code site
  (`tests/unit/test-skills-lint.sh:70`); documentation sites are the
  suite header and this ledger — both updated.
- Frontmatter parsers: skills-lint's awk takes the FIRST later `---`
  (frontmatter must be the leading block — no pseudo-close ambiguity
  there — and so does `fm_get` in `scripts/rules-audit.sh`, which
  reads line 2 to the first close, to EOF when unclosed); measure_file
  is the only span parser with post-close prose still counted — the
  pseudo-close surface — now probe4-pinned. (Wording corrected
  #235 c S3: "the only span-parser" was false as written.)

## Gates (fix wave 2)

- `make test` green (full unit suite), `make lint` green,
  `sh scripts/rules-audit.sh` 0 blocking; reviews lint/parity green
  after INDEX regen; sandbox policy green (mode-000 fixture lives in
  mktemp scratch only).
- Sabotage runs: 4 mutation checks red against the intended pins
  (b B1×2, b S4/B2×1, b B3×1), each restored and re-verified green.
- e2e suites: not owed — tests, markdown and rule text only; no
  `files/`, no root-run script semantics.

## Dispositions — review c (fix wave 3, 2026-10-24)

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| c S1 (MED) | **implemented** | `9fcd197` | slash-runs caught via `\.{1,2}/+local/`; pin + negatives (detail: c S1) |
| c S2 (LOW) | **implemented** | `9fcd197` | probe4 130/131; exact-tail `11 1` assertion (detail: c S2) |
| c S3 (LOW) | **implemented** | this ledger | sweep record corrected with #235 c marker (detail: Class sweeps b) |
| c Q1 (LOW) | **implemented** | this ledger | b B3 evidence corrected: the pre-close >120 line named as load-bearing |
| c Q2 (INFO) | **implemented** | `9fcd197` | rules-audit.sh:27 sentence completed ("on every audit run") |

### c S1 — slash-run shapes of the caught families

The b-round dot alternatives `\.\./local/|\./local/` are collapsed
into one, `\.{1,2}/+local/` (one-or-two dots, one-or-more slashes):
`.//local/`, `..//local/`, `x/.//local/`, `.///local/` are now
caught — POSIX collapses the redundant slashes, so these resolve to
exactly the targets the canonical spellings resolve to. Dot-less
slash-runs stay exempt (`x//local/`, `x///local/` ≡ repo-internal
`x/local/`; `//local/` resolves at root) and the header's
NOT-matched list now enumerates them (the c S1 table-completeness
note). New fixture opk-dblslash-local pins the miss direction;
opk-legit-paths grew the exempt slash-run shapes
(cache//local/notes, cache///local/x, //local/elsewhere) as the
negative. Both directions sabotage-red (Gates below); the full
19-shape probe table is recorded under Class sweeps (c round).

### c S2 — probe4 pins the counted line, not just the count

The two probe4 long lines now differ (130 in-span, 131 post-close)
and the assertion is the exact tail `11 1`: only the post-close
line being counted yields that sum. The head-count value (`10 1`) —
which the b-round count-only assertion accepted — is now rejected;
the value was measured on the real measure_file during review-phase
verification (tail-strip behavior → probe4 `10 1`, count 1, passing
the old assertion). probe2 stays the family-level backstop for
whole-direction strip mutants (tail-strip empties probe2 — measured).

## Class sweeps (c round)

- Slash-run shape sweep over the exact pattern (19 shapes, both
  directions): caught — `./`, `.//`, `.///`, `../`, `..//`, `x/./`,
  `x/.//`, `.././`, `.././/` (each + `local/`), the absolute
  workspace path, space-prefixed; deliberately missed — `~/.local/`,
  `/usr/local/`, `x/local/`, `x//local/`, `x///local/`, `//local/`,
  `opencode-local/`, `foo.local/`. The header table matches the
  probes shape-for-shape (claimed == observed).
- `local/` pattern sites re-swept (`local/` over living `.sh/.py/
  .yml`, case folders and archive excluded): still a single code
  site — tests/unit/test-skills-lint.sh:78; every other hit is that
  same file's header, fixtures and pins, i.e. documentation sites
  updated in the same commit.
- Pin inventory recounted: FAIL sites unchanged at 10; pin
  case-blocks 17 → 18 (opk-dblslash-local; 17 `case "$_out"` + 1
  `case "$_out2"`), all before the summary gate.

## Gates (fix wave 3)

- `make test` green (full unit suite, default TMPDIR; the
  confined-TMPDIR test-status red re-confirmed environmental — red
  under /tmp/opencode scratch, green under default /tmp, same
  attribution as the b round), `make lint` green, `sh
  scripts/rules-audit.sh` 0 blocking; reviews lint/parity green;
  rules-meta 23 pins green; line-length green incl. probe4.
- Sabotage runs: 3 mutation checks red, each restored and
  re-verified green — (1) c S1 miss direction (collapsed alternative
  reverted to the b-round two-alternative form → "PIN BROKEN:
  .//local/ or ..//local/ reference not caught (c S1)" — quote
  rewrapped #235 d W3: the wrap had split the token `.//local/`);
  (2) c S1
  exemption boundary (`\{1,2\}` widened to `*`, catching x//local/ →
  "PIN BROKEN: legit /usr/local or ~/.local path flagged"); (3) c S2
  direction (strip-runs-past-the-close mutant → PROBE BROKEN with
  prose=''/pseudo=''; the sum assertion additionally rejects the
  measured head-count value `10 1` that the count-only form
  accepted — see c S2 evidence).
- e2e suites: not owed — test code, ledger text and one comment-only
  script line (rules-audit.sh header); no `files/`, no root-run
  script semantics.

## Dispositions — review d (fix wave 4, 2026-10-24)

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| d W1 (LOW) | **implemented** | `2b71a69` | slash-run spellings + collateral dot families enumerated (detail: d W1) |
| d W2 (INFO) | **implemented** | `2b71a69` | same hunk — `y.//local/` named newly caught collateral (detail: d W1) |
| d W3 (LOW) | **implemented** | this ledger | quote rewrapped; rendered text equals the code string (detail: d W3) |

### d W1 / d W2 — shape-table completeness (comment-only)

One comment hunk in the skills-lint header
(tests/unit/test-skills-lint.sh:33-53) extends the matched-shapes
list: the slash-run spellings now name `.///local/` and say "one or
more slashes" (was: "doubled-slash" only), and a new sentence
documents the collateral families of the left-unanchored dot
alternative — dot-runs ≥ 3 (`.../local/…`) and dot-terminated
segments (`y.//local/…`) — as accepted lint-only false positives,
repo-internal both. History claims measured at their refs (L3):
`.../local/x` CAUGHT at all three rounds (a `787c3b0` inline grep
`(^|[^.[:alnum:]_/-])local/|\.\./local/`, b, c); `y.//local/x` and
`.///local/x` missed at a and b, CAUGHT at c — "already caught
pre-c" and "newly caught by the collapse" are measured, not
narrated. No new pin (deliberate, L3 reasoning): the substring
mechanism is pinned by opk-dblslash-local's `sub/.//local/x` line,
the alternative is pinned in both directions (miss:
opk-dblslash-local; over-catch: opk-legit-paths + the
`\{1,2\}`→`\*` sabotage), and the documented shapes are consequences
of that pinned alternative — recorded here as measured evidence
instead, keeping the round comment-only for the stop rule (RM-0066).

### d W3 — sabotage quote rewrap (ledger-only)

The Gates (fix wave 3) quote broke the pin string mid-token
(`.//` + newline + `local/`, rendering `.// local/`); the wrap now
breaks after "PIN BROKEN:" — a whitespace position of the code
string — so the rendered quote equals
`PIN BROKEN: .//local/ or ..//local/ reference not caught (c S1)`
(tests/unit/test-skills-lint.sh:345) char-for-char.

## Class sweeps (d round)

- Shape-table description sites: `grep -rn "doubled-slash"` over
  living files → tests/unit/test-skills-lint.sh:79 (mechanics
  comment: "one-or-more slashes … so the doubled-slash spellings …
  cannot slip through" — true, under-enumerating only, and the same
  sentence already states the one-or-more semantics), :270 and :350
  (fixture description + pin text — describe the doubled-slash
  fixture correctly, no drift). Frozen snapshots and this ledger's
  history sections carry the older wording (10 sites) — immutable
  evidence, not doc sites.
- Boundary shapes re-probed against the exact LOCAL_SHAPES
  construction at HEAD: `.../local/x`, `..../local/x`, `y.//local/x`,
  `x/y.//local/x`, `.///local/x` CAUGHT; `v1.2/local/x` missed (dot
  not slash-adjacent) — the new header text matches the probes
  claim-for-claim.

## Gates (fix wave 4)

- test-skills-lint green (18 pins unchanged — the diff is
  comment-only, 11+/5−, no code line touched); line-length ratchet
  green (662 over 120, unchanged); reviews lint/parity green;
  rules-audit 0 blocking; make lint green.
- Sabotage runs: none owed — no pin, code path or assertion changed
  (comment-only hunk; the pins' sabotage cover stands from waves b/c,
  re-executed red during review d's pre-launch window).
- e2e suites: not owed — comment-only test hunk + ledger text; no
  `files/`, no root-run script semantics, no executable line changed.
- Stop rule (RM-0115 expectation, check cited): this round's
  dispositions touched tests/unit/test-skills-lint.sh as a
  COMMENT-ONLY hunk (11 comment insertions, 5 comment deletions, no
  code line) plus this ledger — no review-relevant code per RM-0065
  (comments and resolution bookkeeping are not review-relevant), so
  the loop closes under RM-0066; the maintainer commissioned the
  closure with the go ("schleife schließen", 2026-10-24).

## Follow-ups

- review-d (snapshot `fff6b14` over diff `5e55225..cb22965`)
  discharged fix wave 3's owed review; its fix wave 4 (`2b71a69` +
  this ledger) stayed comment/ledger-only, so the loop CLOSES with
  this round (RM-0064/RM-0066; check cited in Gates, fix wave 4) —
  maintainer go 2026-10-24 ("schleife schließen").
- The skills-lint workspace-absolute alternative is computed from
  REPO_ROOT at runtime (`WS_LOCAL`); the opk-abs-local fixture
  derives its reference from the same variable, so pattern and pin
  relocate together across checkouts (#235 b B1).
- The lane-c helper's case-folder regex pins the shard shape
  `A/B/C/D/pr-ABCDE` — if the shard rule ever deepens, the regex and
  its scratch pin must move together (the scratch pin's exempt-path
  fixture is the discriminator).
- Snapshot-a's run provenance names the workspace opencode pins as
  v1.18.35/v2.1.4; the workspace-level AGENTS.md (outside this repo)
  still says v1.18.15 — not a repo finding, noted for the maintainer.
