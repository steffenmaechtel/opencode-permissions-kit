# Review concept — when, what scope, and when to stop

This record defines the review **strategy**: triggers, scope, loop cadence
and the stop rule. The file mechanics (snapshot immutability, resolution
format, naming) live in [review/README.md](review/README.md); the trigger
list for full reviews also lives in
[CONTRIBUTING.md](../../CONTRIBUTING.md#project-reviews). Finding-ID
referencing: [conventions.md](conventions.md#referencing-review-findings).

It was written after three review rounds on 0.0.38/0.0.39 (snapshots
[0.0.38](review/2026-09-26-v0.0.38.md),
[a](review/2026-09-27-v0.0.39-a.md)/[b](review/2026-09-27-v0.0.39-b.md)/[c](review/2026-09-27-v0.0.39-c.md)/[d](review/2026-09-28-v0.0.39-d.md))
— the numbers below are that history, not theory.

## Two review types, two jobs

| | Release review (full scope) | Wave review (diff scope) |
|---|---|---|
| Question | "What rotted sideways?" | "Did the fixes break or lie?" |
| Scope | whole working tree at a version | the fix-wave diff only |
| Catches | docs-vs-code drift, dead code, naming, undocumented decisions, systemic issues | fix-induced regressions, commit-vs-claim gaps, missed sibling sites |
| Cannot catch | (too broad to pin regressions on a change) | lateral drift outside the diff |
| Cadence | trigger-based (see CONTRIBUTING: version bump planned, ~500+ changed lines / 10+ PRs, high blast-radius area touched) | **after every fix wave, before its PR** — mandatory when the wave changes semantics of root-running scripts (`set -e`/pipefail, traps, sudoers, wrapper) |
| Snapshot form | 1–2 independent snapshots of the same tree | one snapshot over the diff |

Diff size guidance: a wave diff of ~2.5k lines (0.0.39d) is the upper bound
of what one review pass digests; smaller waves are better reviewed.

## The loop and the stop rule

```
review → fix → review the fixes (wave review) → fix → …
```

**Stop when a full pass returns no new MED/HIGH findings.** LOW/INFO
findings do not extend the loop — they get dispositioned (implemented, or
deliberately not done with rationale in the resolution) and that is the end
of them.

Why a stop rule instead of a fixed number of rounds: the process converges.
The project's own history:

| Round | Findings | Character |
|---|---|---|
| 0.0.38 full | ~54, several HIGH/MED | deep, real problems |
| 0.0.39 a+b full (independent ×2) | 59 rows, ~2 MED bugs | rest LOW/doc drift; only 3 rows overlapped between the two snapshots — the tail is high-variance noise |
| 0.0.39d wave (diff) | 3 MED | **all introduced by the fix wave itself** (set -e fallout) |
| expected next full pass | few | convergence |

Two consequences:

- A fixed "review 3–4 times" wastes the later rounds re-litigating accepted
  residuals. Round 3+ finds taste questions, not defects.
- The strongest argument **for** the loop is round d's result: fixes —
  especially robustness fixes — introduce their own bug class. Never skip
  the wave review after a semantics-changing wave.

## Who records what — snapshot, fix commit, resolution, index

Four places carry review knowledge, each with exactly one job (the 0.0.41
chain blurred them — dispositions front-ran into index rows and snapshot
prose, and the resolution became a retroactive reconstruction; the roles
below are the learning codified):

| Place | Records | Mutability |
|---|---|---|
| Snapshot (`YYYY-MM-DD-v<VERSION>.md`) | **what was found** — findings as reported, with IDs | immutable after the fact; only the `> Resolution:` pointer may be added |
| Fix commit (message) | **what was done** — the change itself, finding IDs referenced qualified (`0.0.41f C1`) | git history |
| Resolution (`…-resolution.md`) | **why + SHA** — the authoritative per-finding disposition (implemented / implemented differently / deliberately not done) and the rationale; grows one row per fix AS the chain runs | live during the chain, final at PR |
| README index row | one-line summary + links | may be updated anytime |

The resolution is the ledger the next review starts from — an index row
that carries SHAs is a summary, not a substitute (README rule 4).

## Verification duty (main agent)

Every reviewer-agent finding is re-verified against the code before it
enters a snapshot; unverifiable claims are dropped or marked `unverified`.
Ghost findings are normal, not embarrassing: 0.0.39a retracted two,
0.0.39d retracted one (a grep that looked unguarded but sat behind a
counting branch). Retractions stay visible in the snapshot's
"Retracted/ghost findings" section — they calibrate how much to trust the
next unverified claim.

## Suites are the standing review

Between reviews, the unit/e2e suites are the review. Every finding class
that can become a test, lint rule or consistency guard should become one in
the same wave that fixes it (history: log.sh coverage, run-step enforcement
for CI suites, charset gates, project-path policy tests). The next review
then spends its budget on what automation cannot see. See also
CONTRIBUTING's "shrink the next one" rule.

Two hard rules learned the hard way:

- **Root-script behavior changes owe the e2e suites immediately**, not
  "later": a pipefail regression once downgraded 21 e2e checks to SKIP and
  the suite still reported green — only the skipped-counter betrayed it.
- **Record the environment in the snapshot** (opencode binary version,
  host layout). An upstream release on the review day (opencode 1.18.33)
  changed login behavior under the suite; without the version in the
  snapshot, its results are uninterpretable afterwards.

## Parallel reviewer agents (mechanics)

When a review runs as parallel subagents:

- model policy (since 2026-09-29): the **main agent** runs the strong
  default model (GLM-5.3) and owns the verification duty; **every reviewer
  subagent runs on GLM-5.3-Flash** via pinned agent definitions
  (`agent/review-mechanical.md` sweep, `agent/review-security.md`,
  `agent/review-quality.md`) — cost over single-agent depth. Two
  compensations make that safe: every Flash finding is re-verified by the
  main agent before it enters a snapshot, and independent duplicate agents
  (the 0.0.39 a/b pattern) are cheap enough to run routinely — redundancy
  replaces depth. Higher-reasoning variants stay rejected (timeout-prone,
  2026-09-27); a single agent may be pinned up to the strong model for a
  release-critical pass (maintainer's call, recorded in the snapshot
  header). History: 0.0.38/a–c ran Flash end-to-end on the crashing
  opencode-go provider; d–g ran the judgment agents on GLM-5.3 (gateway
  default) before this policy made all-Flash explicit.
- enforce **checkpoint discipline**: each agent appends findings to a side
  file after every completed section (empty sections get a `clean` line) —
  end-synthesis turns are the primary failure mode, and checkpoints survive
  them,
- budget **by scope, not one flat number** (revised 2026-10-01 after the
  0.0.39 loop — the flat ~8 min was a heuristic, not a measurement):
  - *wave reviews (diff scope)*: **~8 minutes per agent** — validated by
    0.0.39 j/k: every in-scope finding was found within budget, no
    triage deferrals. Micro waves (≤ ~50-line diffs) run ~5. Batched
    greps, targeted reads, no whole-file reads of the big scripts;
    unclear after one follow-up read → mark `unverified`, move on.
  - *full-scope passes*: **~15 minutes per agent PLUS a coverage map**.
    0.0.39l showed ceiling pressure even on a converged tree (install.sh
    mid-sections "spot checks only", tui assets deferred) — and there is
    no all-Flash full-pass data on a *rotted* tree (the deep passes
    0.0.38/e/g ran on the strong model). The coverage map is the real
    budget, the minutes only its ceiling: every shipped file gets at
    least one grep-anchored look, and every deferral is recorded as one
    in the checkpoint (agents cannot watch clocks — they spend
    sections).
  - *release-critical full passes*: prefer a **second independent agent
    per axis** (the 1–2 snapshots cadence above) over a longer single
    agent — redundancy replaces depth at lower cost, and ghosts
    cross-cancel before they reach the main agent.
  The ceiling is a limiter, not a target: the loop's actual rate limiter
  is the **main agent's verification duty** — every extra agent-minute
  yields findings that cost verification minutes, and round 3+ agent
  time mostly re-litigates accepted residuals (see the convergence
  table above). When checkpoint files carry timestamps (cheap, optional),
  a future pass can A/B budgets against verified-finding yield and turn
  this grading into a measurement.
- final chat answers are status lists only (counters + top-3), never the
  file content.

## Release gate

Before cutting a release: the loop's stop condition must hold (last full
pass free of new MED/HIGH) **and** both e2e suites are at baseline level
with zero skips. Only then tag.
