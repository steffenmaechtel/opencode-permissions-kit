<!-- review-meta
ID: pr-00222
Snapshot: a
Subject: rules-meta phases 4-5 — revisit workflow + RM-0001 (feature wave)
Scope: wave
Base: master @ 14050d8
Diff: 14050d8..d7fe9b2
Date: 2026-10-22
Reviewer: GLM-5.3 main agent (verification duty held in-session) + 2x GLM-5.3-Flash reviewer subagents (axis S: scripts, axis T: unit tests)
-->

# Wave review — pr-00222 snapshot a — rules-meta phases 4–5

> Resolution: [resolution.md](resolution.md)

Maintainer brief: micro-wave over the branch, focus **unit tests and
scripts**, snapshot a. Two fresh-context reviewer subagents ran (S:
scripts, T: tests); the main agent re-verified every finding against
the code and ran the gates before anything entered this snapshot.
Axis-T file line numbers were re-anchored during verification (they
had been taken from the diff file, not the sources). No HIGH findings;
all headline behavior claims of the PR survived verification.

## Findings index

| ID | Sev | Location | One-line summary | Axis | Verified |
|---|---|---|---|---|---|
| W1 | MED | scripts/rules-revisit.sh:144-159 vs tests/unit/test-rules-revisit.sh | The rewrite's five validation arms (awk `END exit 3`, two `sed \| grep -qx` field checks, `tail -n 1` log check) have no pin executing their failure path — the script's core "no partial writes" safety net can rot silently | T | yes (code read + fixture grep) |
| W2 | LOW | tests/unit/test-rules-meta.sh (summary) vs PR body | "16 → 17 pins" understates: the suite prints **25** pins at head (pin 10 adds 8 printed pins, 5 of them per-scope-file loops); printed count drifts with `SCOPE_FILES` length | T | yes (suite run: 25 green) |
| W3 | LOW | scripts/rules-report.sh:90-104 vs tests/unit/test-rules-revisit.sh | The report's per-meta fail-loud arms (no id / bad status / bad interval / non-ISO next-revisit) and the missing-meta-tree die (:52) are unpinned — only env arms (bad HORIZON, bad date, missing python, empty tree) execute failure paths | T | yes (code read + fixture grep) |
| W4 | LOW | scripts/rules-revisit.sh:93-96 | A meta with missing/empty `status:` yields rc=1 + the misleading message "RM-NNNN is  -- retired metas…" — a corrupt-frontmatter env failure classified as a domain refusal (sibling bad-interval at :97-100 correctly dies rc=2) | S | yes (code read; rc observed by S sandbox) |
| W5 | INFO | scripts/rules-report.sh:96 vs scripts/gen-rules-index.py:125 | Approval-queue membership: report uses empty-value semantics, INDEX generator key-presence — a bare `reviewed:` line counts pending in the report but approved in the INDEX (audit-legal shape; contradicts the "same definition as INDEX.md" comment :9) | S | yes (code read, all three sites) |
| W6 | INFO | scripts/rules-report.sh:70 | `find … 2>/dev/null` swallows find errors; an unreadable subtree could silently truncate the worklist (pattern copied verbatim from rules-audit.sh:247; `[ -s ]` guard catches the total-empty case) | S | yes (code read) |
| W7 | INFO | tests/unit/test-rules-revisit.sh:103-111 (R0) | Real-tree pin freezes `FORCE_TODAY=2026-10-16`: immune to wall-clock lateness, but any future meta backdated before that date reddens the unit suite (arguably correct — it is labeled a living gate) | T | yes (code read) |
| W8 | INFO | tests/unit/test-rules-revisit.sh:125,143,153 (R1/R2) | Count needles are unanchored substrings (`"overdue: 1"` matches `"overdue: 12"`); the 6-meta fixture geometry makes a false green unreachable today | T | yes (code read) |
| W9 | INFO | tests/unit/test-rules-revisit.sh:386-392 (V10) | "Meta untouched" check counts `revisit-interval:` lines (grep -c), not content; the pinned scenario dies pre-mktemp, so belt-and-braces only | T | yes (code read) |

Severity counts: **0 HIGH, 1 MED, 3 LOW, 5 INFO** (9 findings).

## Key findings detail

### W1 (MED) — the rewrite validation cluster is unpinned

`rules-revisit.sh` claims "the rewrite lands only after every field
change was validated (fail-loud, no partial writes)" (:29-30). That net
is five arms: the awk `END { if (c1 != 1 || c2 != 1) exit 3 }` guard →
die "frontmatter fields not found exactly once" (:150-151), the two
`sed | grep -qx` post-rewrite field checks (:154-157), and the
`tail -n 1` log-line check (:158-159). No pin in
`test-rules-revisit.sh` executes any of them: every fixture carries
well-formed single-occurrence frontmatter, so all green-path pins pass
even if the whole cluster were deleted. The nearest pin (V10, :383-396)
covers the pre-write missing-python arm and only counts lines. Realistic
trigger: a future "simplification" drops a verification grep — suite
stays green — and a meta with a duplicated `revisit-interval:` line
(hand-edit, merge residue) then gets a partial rewrite with nothing
reddening. This is the repo's fail-loud-pin class rule
(agent/learnings.md) applied to the new script's headline safety claim.
Feasible pin: a `write_meta` variant with a duplicated
`revisit-interval:` line → expect rc=2 + "not found exactly once".
The PR's *claimed* arm list (bad HORIZON/date/interval, missing
interpreter, empty tree, no review log) is fully pinned — the gap sits
beyond the claim, inside the same script.

### W2 (LOW) — pin-count claim understates, and the count is variable

PR body: "New pin 1b in test-rules-meta.sh (16 → 17)". Head prints
`OK (25 pins green)` (verified by running the suite; master printed 16).
The delta is not 1b alone: commit d7fe9b2 also added pin 10 (the
no-fake-findings ID-occurrence pin — setup + lane a per scope file (5
at head) + lane b + lane c). Two consequences: (a) the PR text
understates in the conservative direction (more real pins than
claimed), and (b) the printed count silently varies with
`SCOPE_FILES` length — a 6th scope file changes the reported number
with no test change. Fix options: correct the PR text, or stop
printing a bare count in the summary line.

### W3 (LOW) — report per-meta fail-loud arms unpinned

`rules-report.sh` dies per corrupt meta (:90 no id, :93 bad status,
:102 bad revisit-interval, :104 non-ISO next-revisit) and on a missing
meta tree (:52). The suite pins only the env arms (R3 bad HORIZON,
R4 missing python, R5 empty tree = "no metas found", R6 bad pinned
date). No fixture carries a corrupt meta, and R5 creates the tree dir,
so the missing-tree die arm never runs either. Same class shape as W1,
lower stakes: R1's lane pins catch mis-parsing of well-formed metas;
only corrupt-meta handling is unpinned. The PR's "every fail-loud arm
(bad HORIZON/date/interval, …)" is satisfied for the arms it names,
but the report owns four more die arms beyond that list.

### W4 (LOW) — statusless meta lands in the refusal branch

`[ "$st" = active ] || refuse "$ID is $st -- retired metas are outside
the revisit cycle"` (:95-96) fires for any non-active status, including
empty. A hand-edited meta missing `status:` (in a tree the audit has
not yet run on) exits rc=1 with the garbled message
"RM-NNNN is  — retired metas…". By the script's own taxonomy
(:32-34: rc=1 domain refusal, rc=2 usage/env) a corrupt meta is an
environment failure — the sibling bad-interval arm (:97-100) correctly
dies rc=2. Mitigation: the audit's invariant 6 blocks empty status
(rules-audit.sh:238-239), so an audit-green tree never reaches it.
One-line fix candidate for the fix wave.

### W5 (INFO) — approval-queue definition diverges from INDEX in one corner

Report: `[ -z "$(fm reviewed)" ]` (empty value ⇒ pending, :96) — same
semantics as the audit's invariant 9 (:273-283). INDEX generator:
`'reviewed' not in fm` (key presence, gen-rules-index.py:125; the
parser stores a bare `reviewed:` as a present key with empty value).
A bare `reviewed:` line therefore counts **pending** in the report but
**approved** in the INDEX — and that shape is audit-legal (invariant 9
blocks it only when an approval log line exists). The report's own
header claims "same definition as INDEX.md" (:9). Reachable only via a
hand-edit slip; cosmetic consistency gap.

### W6 (INFO) — swallowed find stderr

`find "$ROOT/$METAS" … 2>/dev/null` (:70) is copied verbatim from
rules-audit.sh:247. The `[ -s "$WORK/files" ]` guard catches total
emptiness; a partially unreadable subtree would silently shrink the
worklist. No realistic trigger in a developer-owned checkout; noted
because the header claims "never prints a partial worklist".

### W7–W9 (INFO) — pin-shape observations

As tabled. W7: R0's frozen date cannot trip on real-world lateness
(the report is non-blocking by design — the pin does not smuggle a
gate in); only data backdating before 2026-10-16 reddens it. W8: the
substring count needles are unanchored, but with 6 fixture metas the
"overdue: 1X" false-green space is unreachable (and :143's paired
`! contains "overdue: 2"` partially anchors the boundary pin). W9:
V10's count-based untouched check would not catch a wrong-value write
with unchanged line count; the pinned scenario dies before mktemp, so
this is belt-and-braces.

## Claim audit (commit vs claim)

Verified by subagent sandbox runs (S), static analysis (T), and the
main-agent gates — all of the PR's headline behavior claims hold:

- Lane ordering (most-overdue-first / earliest-first), due-today →
  horizon lane, T+30 in / T+31 out, overdue never changes rc (18
  overdue → rc=0 in S sandbox), rc=2 with empty stdout for bad
  HORIZON / missing python / bad RM_AUDIT_ROOT / corrupt frontmatter.
- Retired metas never in the revisit lanes (approval queue only).
- Ladder 1m→6m→1y→2y, 2y stays 2y; findings → 1m, note required;
  RM-0033 revisit-date basis (stale due 2026-01-01, revisited
  2026-10-22 → next 2027-10-22); Jan 31 + 1m → Feb 28; 2028-02-29 +
  2y → 2030-02-28.
- Exactly one review-log line, `reviewed:` untouched, log format never
  matches the audit's approval pattern (V11: revisited tree stays
  audit-green).
- Atomicity: temp file beside the target, validation before `mv`,
  byte-identical target on failure, zero tmp leftovers.
- "24 pins" for test-rules-revisit.sh: exact (suite prints 24 green).
- Wiring: Makefile `.PHONY`/help/`test:` aggregate/targets consistent;
  workflow step added; new files mode 100755 in the index; pin 1b is
  load-bearing (a ref-less unit under `## The main rule` reddens the
  audit when the ACTIVE_SECTIONS entry is lost).
- The RM-ID prose removals in rules-audit.sh comments,
  gen-rules-index.py docstring, RM-0006/22/46 meta bodies, the record,
  and the two comment lines in test-kit-cli.sh / test-update-flags.sh
  are all forced by pin 10 lane c (no real ID outside ref form) — not
  drive-bys; behavior untouched.
- Real tree at head: audit 0 blocking / 0 overdue, INDEX regen
  byte-identical (tree stays clean).

Not verified: CI greenness on GitHub (workflows not run here);
the ~100-metas-due heads-up number was not independently recomputed.

## Retracted/ghost findings

From axis S (dissolved during S's own verification): (1) apparent
`leap = y % 4 ==,0` syntax error — diff rendering artifact, repo file
valid; (2) 755-but-invoked-via-`sh` vs the 755⇔executed-by-path
invariant — same shape as the established rules-audit.sh on master;
(3) `date_ok` accepts Feb 30 — pre-existing same-shape from the audit,
lane comparisons don't crash; (4) log line could land outside the
review-log section — triggerless, every current meta ends with the
review log; (5) retired-count arithmetic — verified consistent.
From axis T: (6) R0 as a hidden CI gate on overdue work — retracted,
frozen FORCE_TODAY makes real-world lateness un-accumulable (kept as
W7); (7) retired-but-unapproved leak into the approval queue — by
design, INDEX parity; (8) `|| true` in pin-10 lane a — harness
plumbing, result checked via `-n`.

## Run provenance

- Reviewer subagents: 2× GLM-5.3-Flash (axis S scripts, axis T tests),
  fresh contexts, checkpoint files under /tmp/opencode/review-222/
  (launch/return timestamps, per-section appends). S ran sandboxed
  behavior probes (report A1–A8, revisit B1–B13, clamp/audit/parity
  checks) in /tmp scratch; T was static-only per the brief.
- Main agent (GLM-5.3): re-verified all 9 findings against the code;
  corrected axis-T location anchors; ran the gates.
- Gates run at head d7fe9b2, clean tree:
  `sh tests/unit/test-rules-revisit.sh` → 24 pins green;
  `sh tests/unit/test-rules-meta.sh` → 25 pins green;
  `sh tests/unit/test-kit-cli.sh` → pass;
  `sh tests/unit/test-update-flags.sh` → 130 passed;
  `sh tests/unit/test-rules-index-parity.sh` → OK (105 rows);
  `make lint` → ShellCheck clean;
  `sh scripts/rules-audit.sh` → 0 blocking, 0 overdue, tree clean.
- Host: WSL2 kit-managed checkout, `sh tests/check-host.sh` green at
  session start.

## Recommendation

**Proceed.** No HIGH; W1 is the only MED and is a test-gap (pin the
rewrite-validation failure path), not a shipped-code defect. W2 (PR
text pin count) and W4 (one-line rc/message fix) are cheap fix-wave
candidates; W3 optionally alongside W1 (same class). Any fix touching
test or script code owes the b micro-wave per the stop rule.
