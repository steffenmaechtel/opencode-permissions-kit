<!-- review-meta
ID: pr-00241
Snapshot: b
Subject: micro-wave review of the fix wave — a-round dispositions (Q1/Q2/S1/Q4/Q3 sweep)
Scope: wave
Base: c8c7671 @ f461799 (VERSION 0.0.56)
Diff: f461799..8170a43
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill) + 2 fresh-context reviewer subagents (axes W/T) — in-session micro-wave, single-session chain = USER decision (maintainer commission 2026-10-24, review-concept "Session rotation")
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review b — micro-wave review of the fix wave (pr-00241)

Round b over the fix-wave diff (4 commits: 400ff20 fixes + resolution
+ pointer + reviews INDEX, 4711c82 SHA fill, 793b8e2 Q3 label sweep,
8170a43 Q3 SHA fill). Same in-session chain on maintainer commission
(rotation deviation recorded in the header and snapshot a).

## Findings index (combined)

| ID | Severity | One-liner |
|---|---|---|
| T1 | LOW | Resolution's Q2 evidence undercounts the grandfathered corpus: "eight pre-prescription lines" — two more post-legacy closed lines lack the named confirmer (pr-00189, pr-00202), and the snapshot's "of 16 resolutions" is itself off (15 measured) |
| W1 | INFO | Cited record path in the Q1 evidence block is a code span wrapped across two lines — renders with a space inside the path |
| T2 | INFO | Gates parenthetical "(rules INDEX regenerated with this commit)" describes an action that neither happened nor was needed — no rules INDEX in the wave's commits, and the generator reads frontmatter only |

Provenance: T1 fix-induced (restated from frozen snapshot without
re-measurement); W1, T2 fix-induced (wave-introduced prose defects).

---

## Axis W (quality — disposition/claim audit), verbatim

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| W1 | INFO | Cited record path in the Q1 evidence block is a code span wrapped across two lines — renders with a space inside the path | fix-introduced |

**No HIGH / MED / LOW findings.** Every disposition row in `resolution.md` verified against the commits and the tree; every checkable Gates claim re-run green.

## Detail

### W1 (INFO) — code-span path broken across a line wrap in the Q1 evidence block

`internal/reviews/0/0/2/4/pr-00241/resolution.md:29-30`:

```
This matches the b W1 record (`internal/reviews/0/0/2/3/pr-00234/
resolution.md`, "b W1 (MED) — ratchet + reviews-parity red at the
```

The backtick opens on line 29 and closes on line 30; CommonMark/GFM converts the line ending inside a code span to a space, so the rendered citation reads `…/pr-00234/ resolution.md` — a path that does not resolve. Realistic trigger: a later round or the maintainer copies the cited b W1 record path out of the rendered markdown to open or grep it. Cosmetic (the directory prefix is still greppable; the ratchet leaves no better option at this wrap width), hence INFO, not LOW. No house file forbids the pattern — flagged as an in-axis citation-fidelity artifact, not a rule violation.

## Verification record (what was checked, per row)

- **Q1 (MED)** — `agent/review-concept.md:151-161`: the RM-0117 bullet now names both shapes — a-wave "gate claims that were false at its own HEAD (rows unwrapped past 120, pointer and INDEX red … the claims predated the resolution file)" and b-wave "ran its ratchet only AFTER the `<SHA>`-fill commit (benign…)". Matches the b W1 record at `internal/reviews/0/0/2/3/pr-00234/resolution.md:105-118` (rows 124–146 cols, missing pointer, stale INDEX "no-resolution", claims written before the resolution file existed; b-wave commit-then-check). Residue: `exactly this way` survives only in the frozen snapshot quote (`review-a.md:55`, immutable by rule) and an unrelated `tests/unit/test-docs.sh:157` comment. Meta log entry present (`RM-0117.md:40-44`); quote anchor "Bookkeeping edits to in-scope files" — the bullet's first five words — untouched (review-concept.md:151), rules-audit check 5 green on re-run.
- **Q2 (LOW)** — boundary stated identically in both sites: `internal/reviews/README.md:162-164` ("binds lines written from 2026-10-24 on — post-legacy lines already in the corpus stay as written") and `RM-0118.md:29-30` ("chains closing from 2026-10-24 on … earlier corpus lines stay as written"). Corpus classification verified exactly: pr-00179/196/198/222 carry bare `Status: closed` lines; pr-00199/200/208/209 carry `Status: closed — <evidence…>` with no confirmer — eight lines, all first-match `closed` under `gen-review-index.py:78`.
- **S1 (LOW)** — `tests/unit/test-reviews-parity.sh:88-92`: fixture 1 prose is `chain still running; nothing closed yet.` — "closed" present, fixture heredoc has no `Status:` line; comment at :92-93 marks it LOAD-BEARING with the failure direction (open direction). A substring regression would read `closed` on direction 1 while direction 2 still passes — the comment states precisely that. The sabotage red→green run is session history, not in git; the code side is fully consistent with it.
- **Q4 (INFO)** — `internal/reviews/README.md:155-157` ("the INDEX parser takes the FIRST `Status:` line … keep the line at the top") matches `scripts/gen-review-index.py:78` (`re.search` over the whole file, first match wins).
- **Q3 (INFO, amended)** — living tree: zero `[review/README.md]` outside the frozen corpus (surviving mentions only in pr-00115/pr-00133 records and pr-00241's own frozen snapshot + this resolution's prose describing the old label). `agent/review-concept.md` now has 5 `reviews/README.md` lines: the 4 swept sites (:5, :36, :40, :127 — three pre-existing + the wave's RM-0118 bullet) plus :228, which already had the correct form. Amendment provenance honest: old disposition, maintainer override, and the override quote all recorded (`resolution.md:66-76`); commit message `793b8e2` carries the finding ref.
- **S2 (INFO)** — rationale consistent with the code: `META_FIELDS` is an 8-field tuple (`gen-review-index.py:25-26`), `parse_meta` returns None on any missing field (:45-46), and `status()` returns `resolved` for meta-None + resolution-exists (:82-83) — both pin directions would FAIL with rc 1; only the FAIL message's triage hint would mislead. "Nothing silent" is accurate.
- **`<SHA>` fills + widths** — rows: Q1/Q2/S1/Q4 → `400ff20`, Q3 → `793b8e2`, S2 → `—` (correct per the commits). Post-fill content columns 107–117 (max: S1 row, line 14) — the Gates "trimmed to ≤ 118" claim is true and ≤ 120 holds. The 2 remaining `` `<SHA>` `` strings in the resolution are concept prose, not unfilled placeholders; no placeholder in any other resolution.
- **Gates re-run (this tree, by me)**: reviews parity OK (28 index rows, status directions pinned), line-length ratchet OK, reviews lint OK (28 cases) — both count claims match; `rules-audit.sh` → "0 blocking violations, 0 overdue", and `internal/rules-meta/INDEX.md` byte-identical after the run, confirming the "regenerated with this commit" claim. Tree left untouched (INDEX backed up to /tmp before the run, verified unchanged, backup retained).
- **Meta-log rules** — new entries (`RM-0117.md:40-44`, `RM-0118.md:44-46`) reference only finding IDs (`#241 a Q1/Q2`), no foreign RM ids; they do not match the approval-line pattern `^- DATE approved by maintainer` and no `reviewed:` field is set — rules-audit check 9 green. Quote anchors unchanged (check 5 green). Caveat recorded below on sourcing the "own RM id" rule.

## Coverage

Covered: the full fix-wave diff (8 files); all six disposition rows against `git show` content and current files; the 8-line corpus classification at file level; generator + fixture code paths for S1/S2/Q4; residue greps (`exactly this way`, `[review/README.md]`, `<SHA>` placeholders); row-width measurements; all four named gates re-run green; INDEX/regen freshness; meta log-rule compliance. Deferred (session history, not in git — code-consistent where checkable, not contradicted by anything in the tree): the 128–171-column first-draft claim, the sabotage run sequence, the maintainer override utterance. Unverified-and-marked: the "only own RM id in body" rule named in my axis — I could not locate it in `internal/rules-meta/*.md`, `agent/conventions.md`, or `scripts/rules-audit.sh`; the factual state is clean regardless, so nothing hinges on it.

---

## Axis T (security + fix mechanics), verbatim

## Findings index

| ID | Severity | One-liner |
|---|---|---|
| T1 | LOW | Resolution's Q2 evidence undercounts the grandfathered corpus: "eight pre-prescription lines" — two more post-legacy closed lines lack the named confirmer (pr-00189, pr-00202), and the snapshot's "of 16 resolutions" is itself off (15 measured) | fix-induced (restated from frozen snapshot without re-measurement) |
| T2 | INFO | Gates claim "rules INDEX regenerated with this commit" | fix-induced |

### Details

### T1 — LOW — Q2 corpus enumeration undercounts 8 → 10

`internal/reviews/0/0/2/4/pr-00241/resolution.md:43-45`:

> motivated the boundary (measured 2026-10-24, grep over resolutions):
> bare lines in pr-00179/196/198/222; evidence-without-confirmer in
> pr-00199/200/208/209 — eight pre-prescription lines, all still reading

Two additional post-legacy resolutions carry closed lines of the same evidence-without-named-confirmer shape:

- `internal/reviews/0/0/1/8/pr-00189/resolution.md:3` — `Status: closed — fix wave \`4fb7ebd\` (a W1, a W2) dispositioned; micro-` (no confirmer named anywhere in lines 3–8; review-meta header present, INDEX reads `closed`)
- `internal/reviews/0/0/2/0/pr-00202/resolution.md:3` — `Status: closed — chain a–e; stop rule met at the e-round disposition` (review-meta header present, INDEX reads `closed`)

The frozen snapshot has the same blind spot (`review-a.md` Q2 detail: "of 16 resolutions with `Status: closed`" — I measure **15** files with an anchored `^Status:` line, positions 3–15, exactly one per file). Since snapshots are immutable, the resolution was the one place the count could be corrected (README Rules 1); instead it restates the enumeration under a "measured 2026-10-24" claim. The fix itself is unaffected — all non-conforming lines predate the 2026-10-24 boundary (chain start dates ≤ 2026-10-22 in the INDEX), so README/RM-0118's binds-from wording stays correct for the real corpus too. Matters when RM-0118's Check is run as an audit (its stated purpose): the auditor finds 10 grandfathered lines where the ledger says 8.

### T2 — INFO — Gates claim "rules INDEX regenerated with this commit"

`internal/reviews/0/0/2/4/pr-00241/resolution.md:91`:

> (rules INDEX regenerated with this commit); `sh

The wave's four commits touch `internal/reviews/INDEX.md` (the reviews index) but no `internal/rules-meta/INDEX.md`, and none was needed: `scripts/gen-rules-index.py:163` builds rows from frontmatter only (`fm['id'], rel, desc(fm['quote']), fm['status'], …`), and the wave edited RM-0117/RM-0118 body/Review-log text with frontmatter untouched — so the committed rules INDEX is exactly what the generator produces (audit check 8 would not report it stale, and staleness there is a warning, not blocking). The tree is consistent; the parenthetical is inaccurate as a description of the commit.

## Verified clean (per axis, evidence walked)

- **S1 hardening, both directions** (simulated in `/tmp` scratch with the real generator — the parity suite was not run in-repo because its check 2 rewrites `INDEX.md` on mismatch): current `status()` (`scripts/gen-review-index.py:78`, `^Status:\s*(\w+)` + `re.M`) reads the new fixture prose (`chain still running; nothing closed yet.`) as `open` — no line starts with `Status:`; sabotaging the regex to a bare status-word search yields `| closed |`, which fails the pin's `*'| open |')` guard with the row echoed — matching the resolution's sabotage claim exactly. Direction 2 untouched and green. Fixture's review-meta heredoc untouched, all 8 `META_FIELDS` present; the fixture is runtime-scratch, so no other consumer exists.
- **README edits**: "takes the FIRST `Status:` line" matches `re.search` first-match semantics; "keep the line at the top" is the correct corollary; binds-from-2026-10-24 mirrors the legacy grandfathering bullet (README `Legacy resolutions (pr-00109…pr-00171) … binds everything written from here on`) — no overstatement. Corpus state: 15 anchored Status lines, lines 3–15, exactly one per file — the wave added none (pr-00241 open is correct per README while the chain runs).
- **RM-0117 bullet rewrite**: added lines max 86 content columns (bound 120); meta quote anchor `quote: "Bookkeeping edits to in-scope files"` (`RM-0117.md:6`) is the bullet's opening five words, sitting before the rewritten region — inv5 needle still findable (`rules-audit.sh:110,264`); exactly one `(RM-0117)` ref; `(#234 b W1)` citation format intact.
- **Label sweep 793b8e2**: exactly 4 label sites in `agent/review-concept.md` (lines 5, 36, 40, 127), link targets `../internal/reviews/README.md` unchanged, no broken links; tree-wide grep for `review/README.md` outside `internal/reviews/`: none; inside: only frozen pr-00115/pr-00133 mentions (correctly kept) and pr-00241's own snapshot/resolution quotes; the pre-existing differently-labeled link at line 228 untouched.
- **Resolution/INDEX/lint-parity interactions**: case folder holds exactly `review-a.md` + `resolution.md` (lint's no-stray-files rule); review-a.md carries exactly one `> Resolution:` line (the sanctioned post-hoc edit); committed INDEX row equals generator output (`open`); resolution max line 117 raw columns ≤ the claimed ≤118 (ratchet metric strips leading whitespace and counts bytes like my measurement); all disposition-row `<SHA>` placeholders filled at HEAD (400ff20 ×4, 793b8e2; `—` only for the deliberately-not-done S2) via the 4711c82/8170a43 fill commits, each with a pre-commit ratchet claim per the RM-0117 pattern; "28 cases" matches the 28 case folders.
- **No unintentional behavior changes**: diffstat over f461799..8170a43 — `agent/review-concept.md`, `internal/reviews/**` (4 files), `internal/rules-meta/0/1/1/RM-011{7,8}.md`, `tests/unit/test-reviews-parity.sh`. No `files/`, `Makefile`, workflows, or `scripts/` paths.

## Coverage

Covered: full diff read; S1 discrimination both ways by hand + scratch simulation; README/RM-0117/RM-0118 wording vs generator and corpus; label-sweep completeness tree-wide; resolution lint/pointer/INDEX/width/SHA-fill mechanics; shipped-file exclusion. Deferred: re-running the gate suites (`make test`/`lint`/`check-version`, reviews lint/parity) — the parity suite's check 2 writes `INDEX.md` in-repo on any mismatch, conflicting with the read-only mandate, and no shipped files changed so e2e is out of the definition of done; the resolution's recorded gate runs are accepted as claimed, with everything statically checkable about them verified above. Not verified (unverified, not flagged): the resolution's in-session sabotage run and the maintainer's in-session Q3 override quote — process history, not tree state.

---

## Main-agent verification (all findings re-verified against the code)

| Finding | Verdict | Evidence |
|---|---|---|
| T1 | **confirmed** | `grep -rl '^Status: closed' --include=resolution.md` → **15** files (snapshot a said "of 16"). pr-00189:3 and pr-00202:3 measured: both `Status: closed — <evidence>` with no confirmer named, both new-style (review-meta era) → 4 bare + 6 evidence-only = **10** grandfathered lines, not 8. The resolution's "measured 2026-10-24, grep over resolutions" framing restated snapshot a's enumeration instead of re-measuring — the exact L3 class (dated anchors must be measured, never restated). |
| W1 | **confirmed** | resolution.md lines 29–30: backtick span opens `internal/reviews/0/0/2/3/pr-00234/` and closes after `resolution.md` across the wrap — GFM renders the break as a space. |
| T2 | **confirmed** | `git show 400ff20 --stat`: internal/rules-meta/INDEX.md absent from the commit (8 files, none of them the rules INDEX); metas' frontmatter untouched in the wave, so the generated rules INDEX was byte-identical — regeneration ran, committed nothing. The parenthetical claims a commit content that does not exist. |

None retracted; no ghosts.

## Retracted/ghost findings

None — all three findings survived verification.

## Run provenance

- Commission: maintainer, in-session, 2026-10-24 ("mach Micro Wave
  review b in dieser Session") — same single-session chain as round a
  (USER decision per review-concept "Session rotation", recorded in
  both snapshot headers).
- Tree: 8170a43 (feature/237-238-review-process-docs), clean at
  fan-out (`git status --porcelain` empty). Material: fix-wave diff
  f461799..8170a43 (4 commits, 8 files, 146 insertions).
- Host timestamps (main session, UTC): fan-out start 2026-10-24T12:22:06Z,
  end 2026-10-24T12:35:33Z.
- Reviewer subagents: 2 (cap 5 respected), fast tier GLM-5.3-Flash,
  fresh contexts, axis prompts from `.agents/skills/opk-review-pass/axis-prompt.md`.
- Checkpoints: `/tmp/opencode/pr-00241-b/checkpoints/{dispositions,mechanics}.md`
  (outside the reviewed tree); windows normalized against host stamps
  (sandbox clocks ~2h ahead).
- Sabotage/mutation windows: none during the fan-out. The T-axis
  reviewer simulated the S1 discrimination on a `/tmp` scratch copy of
  the real generator (no repo writes); the W-axis reviewer re-ran the
  gate suites read-only-safe (rules INDEX backed up to /tmp, verified
  byte-identical, tree clean after) — both disclosed here.
- Gates at snapshot time: tree clean at 8170a43; the last full
  `make test`/`make lint` runs (this session) were green on 4711c82+
  content identical to 8170a43's tree for everything but this
  snapshot's own file.

## Recommendation

All three are ledger-truth fixes in the resolution file itself
(T1's count correction is the one that matters — an audit-grade
number in the chain's own control panel); none touch shipped or test
code. A c-round that fixes them is bookkeeping-only.
