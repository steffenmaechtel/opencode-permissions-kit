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
| [reviews/](reviews/) | review evidence: one vorgang folder per birth-PR (snapshots frozen, resolutions grow), generated index | snapshots frozen, resolutions living |
| [reviews-meta/](reviews-meta/) | recurring meta-analysis runs over the review corpus | one frozen folder per run |
