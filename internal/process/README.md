# process/ — how the project is run

Maintainer steering documents: when work is reviewed and when the review
loop stops, how releases are cut, how CI reviews are planned. The agent
executes these processes; the cadence decisions are the maintainer's.
The full review process itself (loop, stop-rule mechanics, reviewer
agents — ~85% agent reading) lives in
[agent/review-concept.md](../../agent/review-concept.md).

| Page | Governs |
|---|---|
| [review.md](review.md) | commissioning, ask-gates, merge gate = closure, snapshot-scope triggers, external machines |
| [release-handling.md](release-handling.md) | channels, the `stable` mirror, tagging, `make release`, cheat sheet |
