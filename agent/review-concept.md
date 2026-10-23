# Review concept — when, what scope, and when to stop

Operative rules for the reviewing agent: triggers, scope, loop cadence,
stop rule, reviewer mechanics. The file mechanics (snapshot immutability,
resolution format, naming) live in [review/README.md](../internal/reviews/README.md);
the trigger list for full reviews also lives in
[CONTRIBUTING.md](../CONTRIBUTING.md#project-reviews). Finding-ID
referencing: [conventions.md](conventions.md#referencing-review-findings).
The history, calibration data and incident evidence behind these rules
live in
[review-calibration.md](../internal/records/review-calibration.md).

## Two review types, two jobs

| | Release review (full scope) | Wave review (diff scope) |
|---|---|---|
| Question | "What rotted sideways?" | "Did the fixes break or lie?" |
| Scope | whole working tree at a version | the fix-wave diff only |
| Catches | docs-vs-code drift, dead code, naming, undocumented decisions, systemic issues | fix-induced regressions, commit-vs-claim gaps, missed sibling sites |
| Cannot catch | (too broad to pin regressions on a change) | lateral drift outside the diff |
| Cadence | trigger-based (see CONTRIBUTING: version bump planned, ~500+ changed lines / 10+ PRs, high blast-radius area touched) | **after every fix wave, before its PR** — mandatory when the wave changes semantics of root-running scripts (`set -e`/pipefail, traps, sudoers, wrapper) |
| Snapshot form | 1–2 independent snapshots of the same tree | one snapshot over the diff |

- A wave diff of ~2.5k lines is the upper bound one review pass digests;
  cut waves smaller. (RM-0057)

## The loop and the stop rule

```
review → fix → review the fixes (wave review) → fix → …
```

- Before the loop starts, the maintainer opens the (draft) birth-PR and
  tells the reviewer its number — that number is the case key
  (`internal/reviews/A/B/C/D/pr-ABCDE/`; mechanics:
  [review/README.md](../internal/reviews/README.md)). Opening the PR
  first keeps parallel features safe: GitHub allocates the number, so
  two features can never claim the same case folder. (RM-0058)
- The snapshot is written and committed BEFORE any fix starts (the hard
  seam; see [review/README.md](../internal/reviews/README.md), Process).
  Findings must be inspectable while nothing has been done about them
  yet, and a fix applied mid-verification would change the very tree
  the remaining findings are verified against. (RM-0059)
- A round's disposition covers ALL findings of its review — fixed or
  deliberately-not-done, each one. An instruction like "fix F1 first"
  sequences work INSIDE the round; it does not end the round. One wave
  review per round, batching all of the round's fixes — never one per
  finding or per ad-hoc slice. (RM-0106)
- The wave review fires on the maintainer's go once the round's
  dispositions are complete — it owes a go exactly like the fixes do.
  Round completion is reported (naming owed-but-not-run reviews),
  never self-advanced into the next pass. (RM-0107)

### Session rotation

Default unless the USER defines otherwise for a case. Inside a review
session, the reviewer mechanics below apply unchanged (fresh-context
reviewer subagents + main-agent verification):

```
Session A (implement):  build the feature/bugfix, commit
Session B (review 1):   fresh review → commit the report → [GO] →
                        apply the fixes in the SAME session
Session C (review 2):   fresh review (fix diff + any new scope) →
                        commit the report → [GO] → apply the fixes
                        in the SAME session
…                       until the stop rule holds
```

- The session that reviews also fixes — no handoff back, and not
  before the maintainer's go (the hard seam and the pause stay
  unchanged); what the rotation buys is that every review pass starts
  with fresh context: a round's author never reviews their own
  fixes. (RM-0060)
- Sessions do not chain themselves: each round's session ends with its
  commits; the maintainer starts the next one
  ([internal/process/review.md](../internal/process/review.md): "start
  a fresh session per review round"). The pauses between sessions are
  the maintainer's, not the agent's. (RM-0061)
- Rotation is measured in SESSIONS, not reviewer contexts: the
  fresh-context subagents below are the mechanics of a review pass
  INSIDE the rotating session — they do not allow the session that
  authored a round's fixes to review them. A single-session chain is
  a USER decision for the case (recorded in snapshot provenance),
  never an agent's self-declared mode. (RM-0109)
- The snapshot header's Reviewer line records which session ran the
  pass, so the rotation stays auditable after the fact. (RM-0063)
- A rotation violated anyway (a round ran in the authoring session)
  is recovered, not improvised: the round is recorded as
  non-authoritative — its findings' resolution status stays open and
  a Follow-ups entry names the deviation and instructs the successor.
  The successor's mandate has two mandatory parts: re-verify the prior
  snapshot's CLEAN verdicts (not only its findings) and run its own
  pass over the same range. The prior snapshot stays immutable
  evidence — its findings stand, its verdicts are leads. (RM-0110)

**Stop rule.** A round is a review plus the disposition of its
findings. A round with no findings at all, or with every finding
deliberately not done, is the degenerate case — nothing changed,
nothing to review.

- Stop when a round leaves review-relevant code untouched: the loop
  closes when that disposition changed no review-relevant code. (RM-0064)
- Review-relevant is everything that has or wires behavior: `files/`
  (including the sudoers/config templates), tests and their pins, the
  Makefile, workflows, `scripts/`. Comments, `docs/`, CHANGELOG and
  resolution/index bookkeeping are not. There is deliberately no
  "trivial" carve-out. (RM-0065)
- A round whose fixes stay in comments/docs/bookkeeping closes the
  loop. (RM-0066)
- Any round whose fixes touch production or test code — regardless of
  the findings' severity — owes one more review: a wave review of the
  fix diff, not a full pass. Severity prioritizes; only code change
  extends the loop. (RM-0067)
- A round's own commits never declare the loop closed — closure is
  confirmed by the NEXT round (or the maintainer) checking the stop
  rule against the round's dispositions. A fixing round may state the
  expectation only with the check cited ("this round's dispositions
  touched no review-relevant code: files touched = …"); a closure
  later retracted follows the rotation-deviation recovery above. (RM-0115)

## Fixes close classes, not sites

- A fix wave owes a class sweep: grep the anti-pattern across every
  shipped file — and the docs that claim the invariant — not just the
  finding's file. (RM-0069)
- The sweep result is recorded in the resolution (what it found beyond
  the listed lines), so the next review can audit it. (RM-0070)

## Who records what

Four places carry review knowledge, each with exactly one job:

| Place | Records | Mutability |
|---|---|---|
| Snapshot (`review-<l>.md`, case folder) | **what was found** — findings as reported, with IDs | immutable after the fact; only the `> Resolution:` pointer may be added |
| Fix commit (message) | **what was done**; finding IDs qualified (`#176 a W1`, legacy `0.0.41f C1`) | git history |
| Resolution (`resolution.md`) | **why + SHA** — the authoritative per-finding disposition (implemented / implemented differently / deliberately not done) and the rationale; grows one row per fix AS the chain runs | live during the chain, final at PR |
| INDEX row (generated) | per-case summary: key, subject, scope, dates, status | generated — hand edits fail the parity test |

- The resolution is the ledger the next review starts from — an index
  row that carries SHAs is a summary, not a substitute (README rule 4). (RM-0071)

## Finding provenance

- Every full-scope snapshot records which release introduced each
  finding: `git log -L`/`-S` to the oldest commit touching the
  offending code, then `git tag --contains` for the first release that
  shipped it. (RM-0072)
- Distinguish two dates in the table: *bug-form since* (the reported
  behavior first existed) and *code since* (the site's age — older
  where a fix reshaped an old bug without closing it). (RM-0073)

## Verification duty

- Every reviewer-agent finding is re-verified against the code by the
  main agent before it enters a snapshot; unverifiable claims are
  dropped or marked `unverified`. (RM-0074)
- Retractions stay visible in the snapshot's "Retracted/ghost findings"
  section — they calibrate how much to trust the next unverified
  claim. (RM-0075)
- A review round MAY run sabotage spot-checks — execute a failure
  path instead of reasoning about it: delete (never comment out) the
  construct on a committed, clean tree, observe the failure the way
  production would, restore, re-run green; reader-window conditions
  per "Parallel reviewer agents". When a prior snapshot's verdict was
  reached by reasoning alone, the successor executes at least one
  representative failure path of it. (RM-0112)

## Suites are the standing review

Between reviews, the unit/e2e suites are the review (see also
CONTRIBUTING's "shrink the next one" rule):

- Every finding class that can become a test, lint rule or consistency
  guard becomes one in the same wave that fixes it. (RM-0076)
- Root-script behavior changes owe the e2e suites immediately, not
  "later". (RM-0077)
- The debt's due date splits by change class: root-run script changes
  that alter SEMANTICS (rc contracts, traps, sudoers, provisioning,
  wrapper) owe both e2e suites in the wave itself; message- or
  comment-only changes to root-run scripts may ride to the release
  gate. Either way the debt is recorded once — and any later session
  that runs both suites green on a committed tree discharges it (tree
  SHA + counts into the ledger; that record doubles as the fresh
  comparator the next count claim needs). (RM-0113)
- Record the environment in the snapshot (opencode binary version,
  host layout). (RM-0078)
- A disposition claim ("closed", "never dereferences", "any … aborts")
  owes a behavioral test, not prose: every such claim in a resolution
  or code comment names its pinning test in the same wave — otherwise
  it is not a claim, it is a hope. (RM-0079)

## Parallel reviewer agents

Execution choreography (fan-out staging, axis-prompt construction,
checkpoint mechanics, snapshot writing): load the `review-pass` skill
(`.agents/skills/review-pass/`) — the rules below stay authoritative
here.

- The main agent runs a strong default model and owns the
  verification duty; every reviewer subagent runs the provider's
  cheaper fast tier (house instance: GLM-5.3 + GLM-5.3-Flash —
  substitute your provider's strong/fast pair). (RM-0080)
- Reviewer subagents get ad-hoc axis prompts per session (mechanical
  sweep, security, quality); the durable spec any reviewer prompt
  implements is the reviewer output contract
  ([README](../internal/reviews/README.md#snapshot-format)): stable
  finding IDs, house severities, findings index, provenance. (RM-0081)
- A coverage claim is NEVER verified via the mechanism that makes the
  claim — guards, manifests and checklists are themselves review
  objects: enumerate the executed commands / on-disk files
  independently before repeating what they report. (RM-0082)
- For release reviews, a second independent snapshot from a different
  context — a different model family and/or a setup without the house
  skills and their biases — is the strongest redundancy. Integration
  duties: full per-finding verification by the main agent, honest
  provenance in the snapshot header (model, tree, what ran on which
  host), findings recorded as reported with verification marks, and a
  calibration section naming what each side missed and why. (RM-0083)
- Invocation shape governs orchestration capacity: a fan-out-capable
  main session is the preferred shape for every review; a setup that
  cannot fan out subagents (the 1.x `/review` subtask shape) is
  merely adequate for diff/wave scope and never enough for
  full-scope/release reviews. (RM-0084)
- Fan-out is staged, never launched at once: the standard cap is 5
  concurrent reviewer subagents on ANY tier — the provider's burst
  limit is account-wide, not per-model (ten simultaneous flash
  launches cost three restarts in pr-00211) — backfilling one seat as
  each agent returns. An explicit USER-named cap for the case (10, 20,
  … bigger plans allow more) overrides the standard upward; the agent
  never raises the cap on its own. (RM-0108)
- Sabotage spot-checks mutate the tree the fan-out reads: they run
  only (a) before the fan-out launches, (b) after all reviewer agents
  returned, or (c) in a scratch worktree. A window that overlapped
  readers anyway is disclosed in run provenance (windows + mutated
  files), and every subagent report is then screened in BOTH
  directions: findings shaped like a sabotage artifact (false
  findings) and clean verdicts on mutated constructs citing no
  clean-tree anchor (false cleans). An unanchored verdict on a
  mutated construct is not evidence — re-verify or re-run that unit. (RM-0111)
- Reviewer prompts for recurring blind-spot surfaces name the class
  explicitly, not just the file; a gate or claim about path operands
  is tested against its slash forms (`x/`, `x//`, `x/.`). (RM-0085)
- Checkpoint discipline: each reviewer agent appends findings to a
  side file after every completed section (empty sections get a
  `clean` line) — end-synthesis turns are the primary failure mode,
  and checkpoints survive them. (RM-0086)
- Checkpoint files timestamp every subagent (one line at launch, one
  at return) — the minute budgets are guidance without enforcement;
  the timestamps are the evidence base that will validate or
  recalibrate them. (RM-0092)
- Agents stamp with their own (sandbox) clock — the main agent records
  one HOST timestamp at fan-out start and end so subagent windows can
  be normalized against it, and notes observed skew in run
  provenance. (RM-0114)
- Wave reviews (diff scope): ~8 minutes per agent; micro waves
  (≤ ~50-line diffs) run ~5 — batched greps, targeted reads, no
  whole-file reads of the big scripts; unclear after one follow-up
  read → mark `unverified`, move on. (RM-0087)
- Full-scope passes: ~15 minutes per agent PLUS a coverage map — every
  shipped file gets at least one grep-anchored look, every deferral is
  recorded as one in the checkpoint; the coverage map is the real
  budget, the minutes only its ceiling (agents cannot watch clocks —
  they spend sections). (RM-0088)
- Release-critical full passes: prefer a second independent agent per
  axis over a longer single agent — redundancy replaces depth, and
  ghosts cross-cancel before they reach the main agent. (RM-0089)
- Final chat answers are status lists only (counters + top-3), never
  the file content. (RM-0090)

## Release gate

- Before cutting a release: the loop's stop condition must hold (the
  last round's dispositions touched no review-relevant code) **and**
  both e2e suites are at baseline level with zero skips. Only then
  tag. (RM-0091)
