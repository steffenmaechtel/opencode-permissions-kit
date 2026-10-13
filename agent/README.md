# agent/ — working rules for coding agents

Always-on reading for every agent session in this repo. AGENTS.md (repo
root) is the router; these pages are the rules themselves.

| Page | What it governs |
|---|---|
| [conventions.md](conventions.md) | binding style guide for shipped code — prompts, output, shell security, test sandbox, finding refs |
| [learnings.md](learnings.md) | the L1–L7 checklist from every review wave 0.0.38–0.0.46 — run before committing and again before done |
| [test-fidelity.md](test-fidelity.md) | why bugs pass unit/e2e but still hit real terminals; the patterns that close the gap |
| [review-concept.md](review-concept.md) | the review process: loop, stop rule, verification, reviewer mechanics |

Review mechanics (snapshot/resolution rules, index discipline) live in
[internal/reviews/README.md](../internal/reviews/README.md).
