# Code reviews — archive (tag `review-corpus`)

The repo-file review process era (releases 0.0.38–0.0.57) is archived.
Its corpus — 33 cases (`pr-00109`…`pr-00263`), 141 snapshots and 33
resolutions — lives at the annotated tag `review-corpus`, which points
at the last master commit that carried `internal/reviews/` in full.
The tag is the **authoritative record**; nothing under this directory
is edited anymore.

Reviews of current cases (PR-native process, issue #278) live as
comments on the pull request they review — no case folders are created
and nothing is committed here. The process rules stay in
[agent/review-concept.md](../../agent/review-concept.md).

## How to read and cite the corpus

- **Cite the tag, not the comments.** A legacy citation such as
  `0.0.38 S1` resolves against the tag:
  `git grep "0.0.38 S1" review-corpus -- internal/reviews/`
  New-era citations (`(#176 a W1)`) resolve the same way:
  `git grep "#176 a W1" review-corpus -- internal/reviews/`
- **Case lookup:** the generated case map (INDEX) and every snapshot
  and resolution are readable at the tag, e.g.
  `git show review-corpus:internal/reviews/INDEX.md`, then
  `git show review-corpus:internal/reviews/<shard>/<case>/review-<l>.md`.
  Pre-restructure stems (`0.0.49b`) map to case folders via
  [legacy-index.md](legacy-index.md).
- **PR mirrors are readability copies:** each case's full chain is
  mirrored as one consolidated comment (split into parts where it
  exceeds the comment size limit) on its birth-PR timeline, marked
  `opk-review-legacy` (issue #290). They are for reading, not citing;
  timestamps and states inside are historical.

## Snapshot format

Historical: the format the archived snapshots follow (the review-meta
header contract, verbatim reviewer output, severity vocabulary) is
documented by the README as it was at the tag:

    git show review-corpus:internal/reviews/README.md

New reviews follow the PR-native comment format instead (issue #278).

## What retired with the corpus (issue #290)

The generated `INDEX.md`, its generator `scripts/gen-review-index.py`,
and the corpus-guarding suites (`test-reviews-lint.sh`,
`test-reviews-parity.sh`) were removed together with the corpus — they
guarded in-tree state that no longer exists. The frozen corpus itself
is untouched history at the tag.

## What still lives here

| File | Role |
|---|---|
| `README.md` | this archive pointer |
| `legacy-index.md` | frozen map: pre-restructure stems → case folders (read them at the tag) |
