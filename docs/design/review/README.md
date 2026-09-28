# Code reviews (design/review/)

Model-generated code reviews of the kit live in this folder. The convention
keeps two things separate: **what the review found** (immutable) and **what
the maintainers did about it** (the resolution).

## File naming

| File | Meaning |
|---|---|
| `template.md` | The skeleton a new review snapshot starts from (header fields, table shapes, finding-ID scheme) |
| `YYYY-MM-DD-v<VERSION>.md` | The review snapshot — findings as reported, never edited after the fact. Several snapshots of the same date-version get variant suffixes `-a`, `-b`, … in review order |
| `YYYY-MM-DD-v<VERSION>-resolution.md` | The disposition of every finding (same date-version stem) |

## Rules

1. **The review file is a snapshot.** Findings are referenced by ID (S1, C15,
   …) from commit messages and the resolution — later edits would blur what
   the reviewer found versus what was fixed. Corrections happen in the
   resolution, not by rewriting history. (The review's own "Retracted/ghost
   findings" section is part of the snapshot: retractions stay visible.)
   Outside the snapshot, IDs always carry the review stem — `0.0.38 S1`,
   never a bare `S1` — because every review restarts at S1/C1; the mapping
   lives in the [index](#index) below and
   [conventions.md](../conventions.md#referencing-review-findings).
2. **The snapshot carries one pointer line** at the top — `> Resolution:
   <file>` — once a resolution exists. That is the only edit allowed.
3. **The resolution dispositiones every finding**, one of:
   - *implemented* — with the commit SHA that carries it
   - *implemented differently* — with what changed on the way and why
   - *deliberately not done* — with the rationale
4. **Follow-ups the implementation itself required** (a fix that regressed
   something the review could not see, and its fix) are recorded in the
   resolution — they are expected reading for the next review.
5. Resolutions reference commits, not branch names or issue numbers alone —
   the SHA survives rebases of everything else.

## Process

Reviews are run by a model against a clean working tree of the version under
review (see a review's header for model, scope, and verification state). The
review report is committed first, fixes follow on a feature branch with the
finding IDs in the commit messages, then the resolution closes the loop.

## Index

Every review restarts its finding IDs at S1/C1, so a bare ID (an `S1` in a
comment, a commit message, a chat log) is ambiguous across reviews. Resolve
it in two steps: take the review stem from the reference — `(0.0.38 S1)`
points at row 0.0.38 below — or, for a bare legacy ID, grep the candidate
snapshots (`grep -n "C13" 2026-09-26-v0.0.38.md`).

| Stem | Snapshot | IDs used | Resolution | Notes |
|---|---|---|---|---|
| 0.0.17 | — (pre-snapshot era) | — | — | findings summarized in `project-history-summary.md`; in-code references use the `review 0.0.x` prose form |
| 0.0.22 | — (pre-snapshot era) | — | — | referenced as `review 0.0.22` (`files/install.sh`, agents-migration scope) |
| 0.0.29 | — (pre-snapshot era) | — | — | referenced as `review 0.0.29` (`management/update.sh`, binary-path fetch guard) |
| 0.0.38 | [2026-09-26-v0.0.38.md](2026-09-26-v0.0.38.md) | S1–S6, C1–C23, D1–D25 | [2026-09-26-v0.0.38-resolution.md](2026-09-26-v0.0.38-resolution.md) | the bare IDs in shipped comments all date from this review's fix commits (C11, C12, C13, C14, C19, C22, C23, S1) — qualified in place as `0.0.38 …` |
| 0.0.39a | [2026-09-27-v0.0.39-a.md](2026-09-27-v0.0.39-a.md) | S1–S9, C1–C9, D1–D25 | — | same-day variant a |
| 0.0.39b | [2026-09-27-v0.0.39-b.md](2026-09-27-v0.0.39-b.md) | S1–S4, C1–C6, D1–D3, Q1–Q3 | — | same-day variant b; independent of -a (overlaps are confirmations) |
| 0.0.39c | [2026-09-27-v0.0.39-c.md](2026-09-27-v0.0.39-c.md) | — (no new findings) | — | provenance analysis of the -a/-b rows vs. tag `0.0.38`: 57/59 pre-existing, 1 fix-wave regression (0.0.39a D12, cosmetic), 1 post-tag feature nit (0.0.39a S9) |
