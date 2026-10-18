# Resolution — pr-00200

Case: [pr-00200](review-a.md) · birth-PR #200 · snapshot a reviewed
eed9604 (99e3fd1..eed9604) on 2026-10-19; fix wave e563874.

Status: closed — snapshot b (`b1b7161`, micro-wave of `e563874`) found
no code findings; b-wave dispositions touch bookkeeping/docs only.

## Dispositions

| Finding | Disposition | Commit | Key evidence |
|---|---|---|---|
| a W1 (MED) | **implemented** | `e563874` | `stat -L` + dangling/no-x-target pins; sabotage red→green |
| a W2 (LOW) | **implemented** | `e563874` | 4400 pin + corrupt-007 compound pin; before the summary gate |
| a W3 (INFO) | **implemented** | `e563874` | cli.md parenthetical widened to the mode-bit rule |
| a W4 (INFO) | **deliberately not done** | — | pre-existing 0.0.48b-W3 cell; out of wave scope (backlog) |
| b W1 (INFO) | **implemented** | this file | stale pre-amend `88aad0d` → `e563874` in the stop-rule note |
| b W2 (INFO) | **deliberately not done** | — | no code change owed; full sweep enumeration in snapshot b |
| b W3 (INFO) | **implemented** | `41424f4` | whitespace-only rewrap; line-length/pages/update-flags green |

## Evidence detail

### a W1 (MED) — stat without -L defeated the re-scoped gate

Fix is the snapshot's own recommendation: one token, `stat -L`. With
`-L` a dangling link makes stat fail → empty → `ADV_BIN_ANYX=false` →
counted warn (the old `[ ! -x ]` verdict restored, and the comment's
"dangling symlink … empty stays false — the loud direction" claim
becomes true). A healthy symlink now feeds the TARGET's bits (root's
`[ -x ]` equivalence holds again — the "sudo resolves it" premise of
the unknown arm is valid for every shape that reaches it). Pins
(discriminating, root-run-safe — `stat -L` fails for every user on a
dangling link): `#200 a W1: dangling symlink counts the warn` and
`#200 a W1: symlink judged by its TARGET's bits`. Sabotage matrix:
deleting `-L` turns both pins red (verified post-commit); restored,
the suite is green again.

### a W2 (LOW) — pin deficit closed

New pins riding the same harness block: `4400 → counted warn` (the
comment's special-digit claim, pinned; root-safe — no x bit means even
root's `[ -x ]` is false) and the corrupt-content-behind-007 compound
pin (caller-denied arm is content-independent — the #163 classifier is
`[ -x ]`-gated and unreachable there; inside the existing root-skip
guard, same 0.0.46a-F2 honesty). The 4096-mode brute force over the
case patterns was re-run in snapshot a's verification (mismatches=0);
the patterns are untouched by the fix.

### Class sweep (L2, for the fix wave)

Pattern: `stat -[Lc]` / `stat --` across `files/`. Sites beyond the
fixed one: fs-baseline.sh:32,38 (`%A`/`%G` against the deploy
manifest — a symlink reads 777 and mismatches: loud, not a downgrade;
operands are kit-deployed regular files); ddev-handover.sh:290 (%A on
project dirs; :615 is explicitly `[ ! -L ]`-gated); status.sh:433,440
(`_st_ancestor_grants_x` — report-only, documented-loose-by-purpose);
update.sh:882 (`/mnt/c` DrvFs mount mode — fixed system path); the
remaining `%U`/`%G` reads are ownership checks on kit-managed paths.
No sibling repeats the wave's shape (a mode-bit any-x verdict silently
downgrading a counted broken-kit warn) — C1 is the only instance.

### b W1 (INFO) — stale pre-amend SHA in the stop-rule note

The fix commit went through reflog churn (`88aad0d` → amends → reset →
`e563874`, identical tree); the stop-rule section written mid-churn
still named `88aad0d` (dangling, on no branch) while the dispositions
table already carried `e563874`. Fixed by rewriting that section for
the post-b state (this file). Ledger-only: no code, no pins owed.

### b W2 (INFO) — class-sweep site list was a subset

The a-wave sweep pattern was right but the recorded site list omitted
`status.sh:477` (project-root setgid display) and `:1038`
(socket-reachability heuristic) — both pre-existing `stat` without
`-L` on variable paths, both landing in atten/info rows, neither
downgrading a counted warn. No code change owed (the wave's class was
any-x warn gates, and C1 is the only one); the complete enumeration
(22 sites, pattern recorded) lives in snapshot b's Class sweep — the
next sweep starts from there instead of this subset.

### b W3 (INFO) — unwrapped prose line

Rewrap only (`41424f4`); prose byte-identical, all lines ≤ ~80 cols.
`test-line-length`, `test-pages`, `test-update-flags` green after.

### Stop-rule status

Snapshot b (`b1b7161`) reviewed the fix wave `9e72ea3..e563874`: code
clean, 3 INFO (bookkeeping/docs). The b-wave dispositions above touch
only resolution bookkeeping and a docs rewrap — no review-relevant
code (review-concept: comments, docs, bookkeeping do not extend the
loop). Stop rule met; chain closed; no snapshot c owed. Release gate
remains: both e2e suites at baseline with zero skips before tagging.
