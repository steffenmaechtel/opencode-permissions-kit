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
   lives in [INDEX.md](INDEX.md) and
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
