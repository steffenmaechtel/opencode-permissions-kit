# Review concept — when, what scope, and when to stop

This record defines the review **strategy**: triggers, scope, loop cadence
and the stop rule. The file mechanics (snapshot immutability, resolution
format, naming) live in [review/README.md](../internal/reviews/README.md); the trigger
list for full reviews also lives in
[CONTRIBUTING.md](../CONTRIBUTING.md#project-reviews). Finding-ID
referencing: [conventions.md](conventions.md#referencing-review-findings).

It was written after three review rounds on 0.0.38/0.0.39 (snapshots
[0.0.38](../internal/reviews/0/0/1/0/pr-00109/review-a.md),
[a](../internal/reviews/0/0/1/1/pr-00115/review-a.md)/
[b](../internal/reviews/0/0/1/1/pr-00115/review-b.md)/
[c](../internal/reviews/0/0/1/1/pr-00115/review-c.md)/
[d](../internal/reviews/0/0/1/1/pr-00115/review-d.md))
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

Before the loop starts: **the maintainer opens the (draft) birth-PR**
and tells the reviewer its number — that number is the case key
(`internal/reviews/A/B/C/D/pr-ABCDE/`; mechanics:
[review/README.md](../internal/reviews/README.md)). Opening the PR first keeps
parallel features safe: GitHub allocates the number, so two features
can never claim the same case folder.

The loop has a hard seam after verification: the snapshot is written and
committed BEFORE any fix starts (see [review/README.md](../internal/reviews/README.md),
Process). Two reasons: the maintainer reads the committed snapshot to see
what the review found before the tree starts moving — findings must be
inspectable while nothing has been done about them yet — and a fix applied
mid-verification would change the very tree the remaining findings are
verified against. The 0.0.42d session codified this after the maintainer
asked for the snapshot first.

### Session rotation (added 2026-10-17, from pr-00189)

pr-00189 snapshot b reviewed its own fix wave inside the implementing
session — its header carried only the usual "house session" label,
identical in shape to snapshot a's; the same-session fact surfaced
in maintainer chat, never in the snapshot (#189 c C5). The author's
context carries its blind spots into the review of the fix. Default
since then, unless the USER defines otherwise for a case:

```
Session A (implement):  build the feature/bugfix, commit
Session B (review 1):   fresh review → commit the report → [GO] →
                        apply the fixes in the SAME session
Session C (review 2):   fresh review (fix diff + any new scope) →
                        commit the report → [GO] → apply the fixes
                        in the SAME session
…                       until the stop rule holds
```

- The session that reviews also fixes — no handoff back; what the
  rotation buys is that every review pass starts with fresh context
  (a round's author never reviews their own fixes).
- Sessions don't chain themselves: each round's session ends with its
  commits; the maintainer starts the next one
  ([internal/process/review.md](../internal/process/review.md):
  "start a fresh session per review round") — the pauses between
  sessions are the maintainer's, not the agent's.
- Inside a review session, the mechanics below apply unchanged
  (fresh-context Flash subagents + main-agent verification).
- The hard seam above is unchanged, and so is the maintainer pause
  (README Process: the fix wave starts on their go) — the session
  that reviewed applies the fixes itself once the go is given.
- The snapshot header's Reviewer line records which session ran the
  pass, so the rotation stays auditable after the fact.

**Stop when a round leaves review-relevant code untouched** (revised
2026-10-11, from the 0.0.46a→0.0.46b and 0.0.47b→0.0.47c chains — the
prior form, "stop when a full pass returns no new MED/HIGH", closed
chains whose LOW fixes then changed code). A round is a review plus the
disposition of its findings; the loop closes when that disposition
changed no review-relevant code.

Review-relevant is everything that has or wires behavior: `files/`
(including the sudoers/config templates), tests and their pins, the
Makefile, workflows, `scripts/`. Comments, `docs/`, CHANGELOG and
resolution/index bookkeeping are not. There is deliberately no
"trivial" carve-out. Three consequences:

- "No findings at all" and "every finding deliberately not done" are
  special cases — nothing changed, nothing to review.
- A round whose fixes stay in comments/docs/bookkeeping closes the loop
  (0.0.45f precedent: the comment-only micro fix `014d5eb` needed no
  successor pass).
- **Any round whose fixes touch production or test code — regardless of
  the findings' severity — owes one more review: a wave review of the
  fix diff, not a full pass** ("did the fixes break or lie?" is the
  right question for LOW fixes too). Severity prioritizes; only code
  change extends the loop.

Why the revision: "no new MED/HIGH" measures what the reviewer found,
not what the fix wave then did to the tree — but the loop's own
strongest argument (below: round d, fixes introduce their own bug
class) is severity-independent, and the record kept disproving the
severity gate from below. 0.0.46a closed with the stop rule MET on
7 LOW; the LOW fixes (F1/F2/F4/F6/F7) went in, and 0.0.46b found
W1 MED caused by exactly those fixes (superseding the -a loop's
closure claim). 0.0.47b (MET on 4 LOW) → fixes → 0.0.47c found the
W2 fix itself statically pinned only, without functional coverage.
L6 agrees across the whole corpus: 20 % of all findings are
fix-induced, 11 of them MED/HIGH. The 0.0.47c snapshot records the
dual reading this revision resolves — its maintainer-commissioned pass
followed the L6/cadence reading against the 0.0.45f/0.0.46c
"LOW/INFO do not extend the loop" precedent; under this rule both
converge: comment-only rounds close, code-touching rounds continue.

If a chain still has not converged after five rounds, stop and hand
the call to the maintainer — the recorded chains converge within
2–7 snapshots; a longer tail is taste ping-pong, not defect removal.

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

### Fixes close classes, not sites (added 2026-10-05, from 0.0.44a)

A third consequence, from 0.0.44a's provenance analysis: of 28 findings,
six were **incomplete closures of earlier fix waves** (0.0.44a V1, V2-claim,
V8, V9, V11, V12), every one the same shape — the *reported* site was fixed,
the *class* and its siblings were not: the 0.0.42e C5 tmp-name sweep fixed
three of four staging sites; the F1 dedup-hoist rationale applies verbatim
to the gh-dedup left in place; the hardcoded-home class was closed in four
files but not in the installer that itself contains the correct getent
pattern. A fix wave therefore owes a **class sweep**: grep the
anti-pattern across every shipped file (and the docs that claim the
invariant), not just the finding's file. 0.0.39g's `2db6517` already did
this ad hoc ("full-class sweep beyond the listed lines"); 0.0.44a makes it
the rule. The sweep result is recorded in the resolution (what it found
beyond the listed lines), so the next review can audit it.

## Who records what — snapshot, fix commit, resolution, index

Four places carry review knowledge, each with exactly one job (the 0.0.41
chain blurred them — dispositions front-ran into index rows and snapshot
prose, and the resolution became a retroactive reconstruction; the roles
below are the learning codified):

| Place | Records | Mutability |
|---|---|---|
| Snapshot (`review-<l>.md`, case folder) | **what was found** — findings as reported, with IDs | immutable after the fact; only the `> Resolution:` pointer may be added |
| Fix commit (message) | **what was done**; finding IDs qualified (`#176 a W1`, legacy `0.0.41f C1`) | git history |
| Resolution (`resolution.md`) | **why + SHA** — the authoritative per-finding disposition (implemented / implemented differently / deliberately not done) and the rationale; grows one row per fix AS the chain runs | live during the chain, final at PR |
| INDEX row (generated) | per-case summary: key, subject, scope, dates, status | generated — hand edits fail the parity test |

The resolution is the ledger the next review starts from — an index row
that carries SHAs is a summary, not a substitute (README rule 4).

### Finding provenance (added 2026-10-05)

Every full-scope snapshot records **which release introduced each finding**
— `git log -L`/`-S` to the oldest commit touching the offending code, then
`git tag --contains` for the first release that shipped it. Precedents:
0.0.39c (57/59 of the -a/-b rows pre-existing at tag 0.0.38), 0.0.44a
(26/28 findings predate the fix waves; no MED new at its core, but two
waves falsely claimed closure of old bugs). The split answers the two
questions findings alone cannot: how many defects the fix process
*introduces or reshapes* (regression rate — governs the fix process, see
"Fixes close classes, not sites") versus how much old backlog each pass
*surfaces* (detection yield — governs the review budget). Distinguish two
dates in the table: *bug-form since* (the reported behavior first existed)
and *code since* (the site's age — older where a fix reshaped an old bug
without closing it).

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

Two hard rules learned the hard way, plus one from 0.0.44a:

- **Root-script behavior changes owe the e2e suites immediately**, not
  "later": a pipefail regression once downgraded 21 e2e checks to SKIP and
  the suite still reported green — only the skipped-counter betrayed it.
- **Record the environment in the snapshot** (opencode binary version,
  host layout). An upstream release on the review day (opencode 1.18.33)
  changed login behavior under the suite; without the version in the
  snapshot, its results are uninterpretable afterwards.
- **A disposition claim ("closed", "never dereferences", "any … aborts")
  owes a behavioral test, not prose** (added 2026-10-05, from 0.0.44a):
  two 0.0.43a/b closure claims were empirically false at first probe —
  F16's "TOCTOU closed" (0.0.44a V2: a trailing-slash operand defeats both
  the `[ -L ]` gate and `chown -R -h`, because path resolution goes through
  the link before lstat ever sees one) and W5's "any single failing entry
  aborts" (0.0.44a V9: only batch-final failures propagate through the
  xargs inner loop). Each would have fallen to one behavioral test at fix
  time. Rule: every such claim in a resolution or code comment names its
  pinning test in the same wave — otherwise it is not a claim, it is a
  hope.

## Parallel reviewer agents (mechanics)

When a review runs as parallel subagents:

- model policy (since 2026-09-29): the **main agent** runs the strong
  default model (GLM-5.3) and owns the verification duty; **every reviewer
  subagent runs on GLM-5.3-Flash** — reviewer subagents get ad-hoc axis
  prompts per session (mechanical sweep, security, quality); the former
  pinned definition files (`review-mechanical.md` and siblings) were
  global session configs outside this repo and have since been removed.
  The durable spec any reviewer prompt implements: [reviewer output
  contract](../internal/reviews/README.md#snapshot-format) — stable
  finding IDs, house severities, findings index, provenance.
  Cost over single-agent depth. Two
  compensations make that safe: every Flash finding is re-verified by the
  main agent before it enters a snapshot, and independent duplicate agents
  (the 0.0.39 a/b pattern) are cheap enough to run routinely — redundancy
  replaces depth. Higher-reasoning variants stay rejected (timeout-prone,
  2026-09-27); a single agent may be pinned up to the strong model for a
  release-critical pass (maintainer's call, recorded in the snapshot
  header). History: 0.0.38/a–c ran Flash end-to-end on the crashing
  opencode-go provider; d–g ran the judgment agents on GLM-5.3 (gateway
  default) before this policy made all-Flash explicit.
- ground-truth rule for coverage claims (added 2026-10-04, from the
  0.0.42d/-e calibration): a claim like "CI runs every suite" is NEVER
  verified via the mechanism that makes the claim — the -d mechanical
  agent asserted "CI runs all 33" by counting `.sh` tokens exactly the
  way the guard does, and 0.0.42e C2 then exposed that guard as
  token-blind (an argument-position suite never executed). Guards,
  manifests and checklists are themselves review objects: enumerate the
  executed commands / on-disk files independently before repeating what
  they report.
- external-model passes (added 2026-10-04): a different model family as
  the second snapshot of a release review is the strongest form of
  "redundancy replaces depth" — the 0.0.42e external pass (GPT-6 Luna,
  same tree) caught 16 findings the house pass had missed (2 HIGH incl.
  the executed host-path `rm`), while the house pass held findings the
  external one lacked. Integration duties: full per-finding verification
  by the main agent (25/26 confirmed there), honest provenance in the
  snapshot header (model, tree, what ran on which host), findings
  recorded as reported with verification marks, and a calibration
  section naming what each side missed and why — even retractions can
  be partially over-turned by the external reviewer's counter-feedback
  (0.0.42e S3 → LOW carve-out).
- **invocation shape governs orchestration capacity** (added 2026-10-06,
  from the 0.0.45b/-c calibration): the opencode built-in `/review`
  command dispatches differently across majors — verified in the pinned
  checkouts: 1.x (v1.18.34) registers it `subtask: true`, so the template
  runs inside ONE build subagent that cannot launch subagents of its own
  (single context, sequential roles — adequate for wave/diff reviews,
  structurally underpowered for full scope), while 2.x (v2.0.22) injects
  the template into the main session (`ctx.session.prompt`), where the
  lead can fan out parallel reviewer subagents and run empirical
  verification. Same model, same prompt, same tree class: the 1.x shape
  produced 2 LOW + 2 INFO in ~8 minutes (0.0.45b, delta focus solid but
  no breadth), the 2.x shape 2 HIGH + 6 MED + 25 LOW/INFO in ~55 minutes
  (0.0.45c, four fresh-context axis subagents + lead verification). Rule:
  full-scope/release reviews run in a main session with fan-out (2.x-style
  invocation or the house flow directly); the 1.x `/review` subtask form
  is reserved for diff/wave reviews. The templates themselves are
  near-identical across majors (three cosmetic lines, v1.18.34 vs
  v2.0.22).
  Calibration correction (2026-10-07, maintainer challenge upheld): an
  earlier revision of this note claimed house passes with full
  orchestration reach comparable full-scope yields, citing 0.0.43a (19
  findings) and 0.0.44a (28) — those snapshots were in fact **external
  integrations** (0.0.42e = GPT-6 Luna; 0.0.43a, 0.0.44a, 0.0.45c =
  external GLM-5.3 sessions in the v2 lead+fan-out shape, none with kit
  skills or agent definitions installed; provenance folders in the dev
  workspace). Corrected record: **every deep full-scope yield so far came
  from an external pass**, and the only same-tree comparison — 0.0.42d
  (house, skill mechanics + Flash reviewer agents: 2 MED) vs 0.0.42e
  (external, same tree: 2 HIGH + 7 MED, 16 findings the house pass
  missed) — favored the external pass (confounder: the house reviewers
  ran GLM-5.3-Flash per the cost policy). Skills and pinned agents keep
  a proven record only in **wave/diff scope** (0.0.45a, 0.0.44b–g,
  0.0.42f–i repeatedly caught fix-induced bugs; 0.0.45b's delta
  verification was solid even inside the v1 subtask shape). For full
  scope their value is unproven, not exonerated — and the standing rule
  above (external v2-shape pass for release reviews) no longer relies
  on them.
- recurring **blind-spot classes** (added 2026-10-05, from 0.0.44a): three
  classes have each escaped at least one dedicated review — root-run file
  operations whose operands sit in agent-group-writable directories
  (0.0.44a V3, alive since 0.0.18 despite four reviews touching the same
  function), producer/validator pairs built in the same wave whose halves
  contradict each other (V4, since 0.0.39: the builder joins with `", "`,
  the validator rejects commas), and path-operand edge forms — trailing
  slashes — that slip symlink gates (V2, since 0.0.40). Reviewer prompts
  for these surfaces name the class explicitly, not just the file; a
  gate/claim about path operands is tested against its slash forms
  (`x/`, `x//`, `x/.`).
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

Before cutting a release: the loop's stop condition must hold (the last
round's dispositions touched no review-relevant code — see "The loop and
the stop rule") **and** both e2e suites are at baseline level with zero
skips. Only then tag.
