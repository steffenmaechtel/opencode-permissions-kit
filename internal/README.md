# internal/ — project memory (maintainer + agent)

Everything under this folder is internal working material for the
opencode permissions kit: how the project is run, why it is built the
way it is, and the evidence its reviews produce. It is not user
documentation — for that, see [docs/](../docs/README.md). Where wording
differs from the code, the code wins.

| Area | Content | Lifecycle |
|---|---|---|
| [process/](process/) | how the project is run: review concept, release handling, CI-review planning | living |
| [records/](records/) | design + decision records ("why is it built this way?") | frozen after implementation |
| [reviews-meta/](reviews-meta/) | recurring meta-analysis runs over the review corpus | one frozen folder per run |

`reviews/` (review evidence: per-vorgang snapshots and resolutions)
joins this folder with the review-system wave; until then the evidence
lives at `docs/design/review/`.
