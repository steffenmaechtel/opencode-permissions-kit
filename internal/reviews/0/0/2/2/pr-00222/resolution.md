# Resolution — pr-00222

Case: [pr-00222](../README.md) · birth-PR #222 · snapshot chain:
[a](review-a.md) · dispositions below grow as fixes land.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | see Evidence | V12 + V13 pins execute the count-guard failure path; sabotage red→green below |
| a W2 (LOW) | **implemented** | see Evidence | lane a one-verdict shape; count stable 25→21, no SCOPE_FILES drift; PR-text remainder handed to maintainer |
| a W3 (LOW) | **implemented** | see Evidence | R7–R12 + V14–V16 pin every fixture-triggerable die arm; sweep table below |
| a W4 (LOW) | **implemented** | see Evidence | case split retired/corrupt; V17 pins the new arm; V7 stays green |
| a W5–W9 (INFO) | **deliberately not done** | — | accepted as informational (rationale below) |

## Evidence detail

### General

Fix wave on `feature/rules-meta-phase-4`, driven by the maintainer's
"go W1-W4" (2026-10-22). Gates after the wave:
`test-rules-revisit.sh` 24 → **36 pins green** (12 new),
`test-rules-meta.sh` 25 → **21 pins green** (stabilized, see W2),
`make lint` clean, sandbox policy green, line-length ratchet green,
reviews lint/parity green. Sabotage runs (below) executed against the
committed tree, restored with `git restore`, suite re-confirmed green
after each restore.

### a W1 (MED) — rewrite-validation arms pinned

Two new pins execute the awk count-guard failure path in
`scripts/rules-revisit.sh:144-151`:

- **V12** — fixture with a duplicated `revisit-interval:` line (merge
  residue shape): expects rc=2 + "not found exactly once" AND the meta
  byte-identical before/after (`$(cat)` comparison — content, not line
  counts).
- **V13** — fixture with `next-revisit:` deleted: same die, the
  `c2=0` operand direction of the guard.

The three post-rewrite consistency checks (`sed | grep -qx` ×2,
`tail -n 1`) verify the awk output itself; no fixture can fail them
while the guard passes (they are internal consistency, not data
states) — covered by the W1 sabotage instead (deleting the guard makes
V12's fixture flow through to a silent swap, which the pin catches).
Sabotage: deleted `END { if (c1 != 1 || c2 != 1) exit 3 }` →
`test-rules-revisit.sh` FAILED at V12 (rc=0, meta rewritten);
restored → green.

### a W2 (LOW) — stable pin count + PR text

Code side: pin 10 lane a in `test-rules-meta.sh` consolidated from
one pass per scope file (5 at head) to a single verdict with per-file
detail in the failure output — the shape lanes b/c already use. The
printed count is now **21** and no longer drifts when `SCOPE_FILES`
grows. Sabotage: appended a prose `RM-0042` mention to
`agent/conventions.md` → suite FAILED naming the file and line;
restored → green (discrimination preserved through the consolidation).
PR-text remainder (maintainer's edit, cannot be done from the repo):
"16 → 17" → 16 → 21; the pin-10 feature and the revisit suite's
"24 pins" → 36 belong in the PR body.

### a W3 (LOW) — every fixture-triggerable die arm pinned

L2 class sweep: `grep -n 'die\|refuse' scripts/rules-report.sh
scripts/rules-revisit.sh` — every arm enumerated and dispositioned:

| Script | Arm | Pin |
|---|---|---|
| report | cannot enter RM_AUDIT_ROOT (:41) | R12 (new) |
| report | cannot locate repo root (:43) | skipped — untriggerable without moving the script |
| report | bad HORIZON (:50) | R3 (existing) |
| report | no meta tree (:52) | R11 (new) |
| report | missing python (:53) | R4 (existing) |
| report | horizon computation (:63) | R6 (existing) |
| report | mktemp (:65) | skipped — needs an unwritable /tmp, breaks the suite itself |
| report | no metas found (:72) | R5 (existing) |
| report | no id (:90) | R7 (new) |
| report | bad status (:93) | R8 (new) |
| report | bad interval (:102) | R9 (new) |
| report | non-ISO next-revisit (:104) | R10 (new) |
| revisit | cannot enter RM_AUDIT_ROOT (:48) | V14 (new) |
| revisit | cannot locate repo root (:50) | skipped — as above |
| revisit | usage argc (:57) | V15 (new) |
| revisit | bad id (:65) | V16 (new) |
| revisit | bad verdict (:69) | V8 (existing) |
| revisit | findings without note (:71) | V4 (existing) |
| revisit | multiline note (:77) | V5 (existing) |
| revisit | missing python (:79) | V10 (existing) |
| revisit | unknown meta (:88, refuse rc=1) | V6 (existing) |
| revisit | bad interval (:99) | V8b (existing) |
| revisit | no review log (:131) | V8c (existing) |
| revisit | count guard (:151) | V12/V13 (new, W1) |
| revisit | rewrite checks (:154-159) | internal consistency — see W1 |
| revisit | mktemp/mv (:142/:161) | skipped — an unwritable meta dir also breaks teardown; value judged marginal |

Sabotage spot-checks (one per new arm family): deleted the
`no id` die line → R7 FAILED; deleted the `[ -d … ] || die` tree
guard → R11 FAILED; deleted the usage `case` arm → V15 FAILED;
restored each → green.

### a W4 (LOW) — status taxonomy split

`scripts/rules-revisit.sh:93-100`: the single
`[ "$st" = active ] || refuse` became a three-way case — `active`
proceeds, `retired` refuses rc=1 (message unchanged in substance:
"$ID is retired -- retired metas are outside the revisit cycle";
V7's "retired" needle stays green), anything else (including the
empty missing-`status:` shape) dies rc=2
"$ID: bad status '$st' (run the audit)" — matching the sibling
bad-interval arm and the report's own per-meta die. Header rc
taxonomy extended with "corrupt frontmatter" (L3). New **V17** pins
the arm (status `paused` → rc=2 + "bad status 'paused'").
Sabotage: deleted the `*) die` arm → V17 FAILED (paused meta
proceeded to a rewrite, rc=0); restored → green.
Class sweep: `grep -n 'refuse' scripts/*.sh` — rules-revisit.sh is
the only refuse-site; rules-report.sh and rules-audit.sh already
die/block on bad status (report :93 rc=2, audit inv 6 blocking).

### a W5–W9 (INFO) — deliberately not done

- W5 (report/INDEX `reviewed:` semantics corner): reachable only via
  a hand-added bare `reviewed:` line; audit-legal but exotic. Left as
  documented divergence — the next person touching the approval-queue
  definition should unify (empty-value vs key-presence).
- W6 (swallowed `find` stderr): sibling-consistent with
  rules-audit.sh; no realistic trigger in a developer checkout.
- W7/W8/W9 (pin-shape observations): no false-green reachable today;
  recorded for the next suite touch.

### Follow-ups the implementation required

None beyond the maintainer-side PR-text correction (W2): pin counts
"24" → 36 (revisit suite) and "16 → 17" → 16 → 21 (meta suite), plus
naming pin 10 in the PR body. The wave touches test + script code →
micro-wave review b is owed before the PR merges (stop rule).
