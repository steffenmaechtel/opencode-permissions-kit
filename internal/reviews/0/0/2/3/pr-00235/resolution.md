# Resolution — pr-00235 (agent-skills pilot, issue #178)

Chain: review-a (snapshot 2026-10-23, 21 findings) → fix wave
2026-10-24 (`787c3b0` tests, `d77a446` rules, `b549a22` skill/docs).
All 21 findings dispositioned **implemented**; none deliberately not
done (maintainer go 2026-10-24: "implement all").

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a S1 (MED) | **implemented** | `787c3b0` | strip conditional on closure; probe3 unclosed fixture; sabotage red→green |
| a S2 (MED) | **implemented** | `787c3b0` | 10 FAIL sites, 14 pins; fixtures for root/open/close/>400 |
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

## Class sweeps (recorded)

- Frontmatter-strip directions: 4 probe fixtures (closed-fm, prose,
  non-md, unclosed) — both failure directions pinned.
- FAIL-site inventory (skills lint): 10 sites ↔ 14 pins (incl. 2
  negative); grep pattern used for the sweep: `echo "FAIL` over
  lint_skills vs the pin case-block.
- RM-ID citations in wave-added text: `git diff caeb9a8..9cfef7f |
  grep '^+' | grep 'RM-[0-9]{4}'` → only the two README lines (fixed);
  lane c now enforces the living README going forward.
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
  script and no root-run script semantics (tests, Makefile, workflows,
  markdown only).

## Follow-ups

- **The fix wave owes its wave review** (diff `ab0f771..b549a22`,
  ~300 changed lines): fires on the maintainer's go, per the loop.
- The lane-c helper's case-folder regex pins the shard shape
  `A/B/C/D/pr-ABCDE` — if the shard rule ever deepens, the regex and
  its scratch pin must move together (the scratch pin's exempt-path
  fixture is the discriminator).
- Snapshot-a's run provenance names the workspace opencode pins as
  v1.18.35/v2.1.4; the workspace-level AGENTS.md (outside this repo)
  still says v1.18.15 — not a repo finding, noted for the maintainer.
