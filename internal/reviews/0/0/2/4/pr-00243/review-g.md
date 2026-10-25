<!-- review-meta
ID: pr-00243
Snapshot: g
Subject: micro-wave review of the f-wave fix wave — OPENCODE_USER gate tightening (leading dot/hyphen, trailing dot), pathological-corpus pin, screen() comment scoping, resolution record
Scope: wave
Base: 0.0.56 @ 7b37b2d
Diff: 7b37b2d..028ece4
Date: 2026-10-24
Reviewer: GLM-5.3 house session (opk-review-pass skill), single-agent pass — no reviewer subagents (USER instruction)
Skills: opk-review-pass
-->

> Resolution: [resolution.md](resolution.md)

# Review g — micro-wave review of the f-wave fix wave (pr-00243)

Round g over the diff 7b37b2d..028ece4 (2 commits: db702ac "fix(uninstall):
OPENCODE_USER gate tightened — leading dot/hyphen + trailing dot refused,
pathological corpus + boundary pins (#243 f X1; rides f S1 anchor correction
+ f S3 comment scoping)" — the fix wave; 028ece4 "resolution e2e/sabotage
record" touches resolution.md only, bookkeeping). Scope keyword **micro**
(USER commission; ≤ ~50-line fix shape, short run, no subagents — the
single axis below is the main session's own review plus its verification
duty). Shipped material: uninstall.sh (26 changed lines: the gate's arm
alternation extended from `''|*[!A-Za-z0-9_.-]*` to
`''|*[!A-Za-z0-9_.-]*|[.-]*|*[.]`, plus the rewritten gate comment
documenting the deliberate writer-parity divergence and the option-injection
rationale), test-uninstall.sh (48: the screen() helper comment re-scoped
from "mirrors the loop's gate order IN FULL" to the screening chain only —
f S3; and the new pathological-corpus pin — five spellings `. .. opencode.
-x --` must fall back LOUDLY with a WARN count of 5, `untest-x.9` must pass
through silently — with the four-arm sabotage plan in the comment),
resolution.md (120: f-wave disposition record incl. the e2e runs 309+47 and
the four sabotage spot-checks, follow-ups #245–#247 with published GitHub
issues, and the anchor-coordinate convention note).

**Result: 0 new effective findings** — every claim in the diff verified
against the code (table below). Two chain-open INFO items (f X3 dead `''`
arm, f X4 raw WARN embed) are carried forward, not re-reported; they are
untouched by this diff and their dispositions stay owed in the chain.

## Findings index

| ID | Severity | One-liner | Provenance |
|---|---|---|---|
| — | — | none — no new findings in this micro pass | — |

## Verification log (every diff-touched claim, main session)

| # | Claim in the diff | Verified how | Verdict |
|---|---|---|---|
| 1 | New arms refuse leading dot/hyphen and trailing dot | `case` alternation read in the shipped file (uninstall.sh:228-234): `[.-]*` anchors the leading class, `*[.]` the trailing; charset arm unchanged; all in ONE alternation so order cannot let a spelling through | LANDED |
| 2 | Pin tests the live gate, not a stale copy | `UN_OCU_GATE` extraction (test-uninstall.sh:395) is a `sed` range over `$UNINSTALL` — re-extracted per run; only `case "$OPENCODE_USER" in` site in the file (grep); sanity arm requires `falling back` in the extract | HOLDS |
| 3 | Corpus pin is loud AND discriminating | Five pathological values each WARN once (appended log, `grep -c` pinned to exactly 5) and each falls back to the literal; keep-case `untest-x.9` preserves value with empty stderr (`[ ! -s ]`) — refuses both the under- and over-refusal direction | HOLDS |
| 4 | "the writer never produces any of them" | install.sh:349 stamps the literal `OPENCODE_USER="opencode"`; the conf heredoc carries that literal (e-wave anchor, re-confirmed by grep — no other OPENCODE_USER producer in install.sh); a customized agent user arrives only by the documented hand-edit, which the gate is for | TRUE |
| 5 | "a leading `-` is also an option-injection shape into the id/userdel argv below" | `id -gn "$OPENCODE_USER"` (uninstall.sh:236) and the userdel path below pass the value as a bare argv token — quoted `-x` is option-shaped to getopt; no `--` guard at the site (the gate is the guard) | TRUE |
| 6 | screen() comment's re-scoped order claim (f S3 fix) | Shipped loop read (uninstall.sh:603-670): agent-home refusal → `[ ! -d ]` → absolute-path case → dot gate → one-slash strip → blocklist — exactly the "screening chain" the comment now claims to mirror, with the three earlier gates named as NOT mirrored | ACCURATE |
| 7 | Resolution anchor correction (f S1 fix) landed | resolution.md now states the coordinate convention explicitly (":228/:239-240 … pre-gate tree coordinates … (review f S1)"); spot-checked `:228` = the gate `case` and `:230` = the WARN line in the tree at 028ece4 | LANDED |
| 8 | Sabotage record matches the pin's design | resolution's four spot-checks (full revert RED on all five; `*[.]`-arm deletion RED via `opencode.`; `[.-]*`-arm deletion RED via `-x`/`--`; over-refusal RED via the `untest-x.9` boundary) are the four discrimination directions the test comment promises | CONSISTENT |
| 9 | Suite green at the diff endpoint | `sh tests/unit/test-uninstall.sh` run at 028ece4 (clean tree): all PASS, "All uninstall tests passed."; e2e counts (309+47) accepted as recorded runs, not re-run in this micro pass | GREEN |

## Retracted/ghost findings

None — no findings were reported in this pass, so none retracted. The
prior chain's retraction (f S2, env-inheritance trigger unreachable)
remains recorded in snapshot f.

## Carried forward (chain-open, NOT re-reported as new)

- f X3 (INFO): the gate's `''` arm stays unreachable in the shipped flow
  (top-level `:-` literal clobbers emptiness before conf sourcing) and
  stays unexercised by any pin — the diff rewrote the comment around it
  but not the arm. Disposition still owed in the chain.
- f X4 (INFO): the WARN line still embeds the raw corrupted value into a
  multi-line-capable stderr write — consistent with sibling echoes,
  unchanged by this diff. Disposition still owed in the chain.
- Follow-ups #245 (projects.conf symlink roots), #246 (uninstall.sh
  single-op rm sites), #247 (update.sh form gate + parity decision)
  remain scheduled as own waves; #244 (agent-name source of truth)
  recorded as accepted residual, not scheduled.

## Run provenance

- Pass type: micro (USER commission: "Wave-Review g (Mikro, Diff
  7b37b2d..028ece4) Keine Sub Agents, kurzer Laufer, 5 min").
- Reviewer agents: **0** — USER-named deviation from the standard fan-out
  (skill §4 default is fast-tier subagents); the main session ran the
  review and the verification duty itself. Concurrency cap therefore not
  exercised.
- Host timestamps: pass start not host-stamped — a USER connection
  interruption ("internet war kurz weg") severed the session between
  material collection and verification; collection re-ran after resumption
  and is fully covered by the verification table above. Pass end:
  2026-10-24T21:36:09Z (captured); the commit stamp is the authoritative
  end mark.
- Mutation/sabotage windows: none in this pass — no tree mutations were
  performed; the suite run wrote only to its scratch `$WORK` (sandbox
  policy). Tree verified clean (`git status --porcelain` empty) before
  material collection and again before this commit; the tree was a clean
  read substrate throughout.
- Budget: material = 74 code/test changed lines + 120 bookkeeping lines,
  fully read (no deferrals); wall-clock within the micro ceiling despite
  the interruption (verification is section-budgeted, not clock-budgeted).

## Recommendation

The fix wave lands as claimed; no findings to disposition. The loop's
open items are all carried in the chain (f X3, f X4, follow-ups
#245–#247) — the stop-rule check against this round's dispositions (zero
new, two carried INFO) belongs to the next round or the maintainer.
