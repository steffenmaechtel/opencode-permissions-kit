# Review concept — when, what scope, and when to stop

Operative rules for the reviewing agent: the PR-native loop, lettering,
review tracks and tiering, curation and verification, stop rule,
reviewer mechanics.
**Process operational since 2026-10-26 (Pilot 1); these rules codify
what the cases ran** (#260→PR #280, #261→PR #284, #283→PR #287,
#290→PR #293) — the pilot directives they formalize (comment format v2,
subagent output contract, wave tiering, scope brake) were adopted
mid-series and are normative text here, not workspace material. The
review corpus of the archived repo-file era (releases 0.0.38–0.0.57)
lives at tag `review-corpus`;
[internal/reviews/README.md](../internal/reviews/README.md) is the
archive pointer. The maintainer's side (triggers, commissioning, gates):
[process/review.md](../internal/process/review.md). Finding-ID
referencing: [conventions.md](conventions.md#referencing-review-findings).
The history, calibration data and incident evidence behind these rules
live in
[review-calibration.md](../internal/records/review-calibration.md).

## Two review types, two jobs

| | Release review (full scope) | Wave review (diff scope) |
|---|---|---|
| Question | "What rotted sideways?" | "Did the fixes break or lie?" |
| Scope | whole working tree at a version | the round's diff only |
| Catches | docs-vs-code drift, dead code, naming, undocumented decisions, systemic issues | fix-induced regressions, commit-vs-claim gaps, missed sibling sites |
| Cannot catch | (too broad to pin regressions on a change) | lateral drift outside the diff |
| Cadence | trigger-based (see process/review.md: version bump planned, ~500+ changed lines / 10+ PRs, high blast-radius touched) | **every round of the PR-native loop** — mandatory when root-running script semantics change (`set -e`/pipefail, traps, sudoers, wrapper) |
| Record form | 1–2 independent passes, integrated by the house session | one round comment over the diff |

- A wave diff of ~2.5k lines is the upper bound one review pass digests;
  cut waves smaller. (RM-0057)

## The PR-native loop

The loop runs in the pull request's timeline — there is no case folder
and nothing is committed to `internal/reviews/`:

```
commission → Session MAIN implements → birth-PR →
loop owner (single case: MAIN · batch: handover to a fresh review session) →
round a: review (comment) → fixes →
round b: review (comment) → fixes → … → closing summary → merge
```

- Before the first review round runs, the birth-PR exists — its number
  is the case key (citations, comment markers, the PR timeline itself).
  The agent creates the PR itself in every variant (AGENTS.md Rules (the never-commit-on-master rule) —
  approval validity needs the agent as author and last pusher; the
  opencode permission prompt is the runtime gate), and in every variant
  the PR is open before review rounds run, keeping parallel features
  safe (GitHub allocates the number at creation). (RM-0058)
- The round comment is posted BEFORE any fix starts (the hard seam).
  Findings must be inspectable on the PR timeline while nothing has
  been done about them yet, and a fix applied mid-verification would
  change the very tree the remaining findings are verified against.
  (RM-0059)
- Lettering: one letter per round, and the review and its fix wave
  SHARE it (round a's review is comment "Review a", its fixes are
  dispositioned in round a's wake). Letters run sequentially from a,
  never reused, never renumbered; a skipped letter stays burned — a
  chain a, c, d records that b was lost, it does not renumber. Gaps
  burn letters; start at a and spend them in order. (RM-0119)
- Write-through: the loop never reads the PR back. Comments are
  composed from the session's own records (checkpoint files, digests,
  verdict files) and posted; the posted comment URLs are logged to
  session scratch (`posted.log`). Reading the timeline back would
  re-import the whole case into context at every round. (RM-0121)
- The loop cap (default 6) is a hard brake, not a target: from round 5
  on, the loop status reports the distance to the cap; reaching the cap
  hands the case to the maintainer instead of starting another round.
  Reaching the cap is a failure state — it means the scope brake or the
  convergence duty was applied too late. (RM-0120)
- Scope brake (binding in autonomous-disposition modes): implement only
  (1) what the case's inventory/commission names and (2) defects in
  what the case's own changes built. Everything else — however found,
  whatever severity — becomes `deliberately not done (recorded)` or a
  deferred work order; no new hardening, no in-passing improvements, no
  cleverness. Two channels for out-of-scope findings: a foreign-topic
  finding (improvement, taste, different class) is a hard stop —
  deliberately-not-done with the reason recorded, or a deferred issue;
  a same-class-beyond-inventory finding is a deferred work order WITH
  an inventory-gap note, never silently dropped. The brake does not
  fight the class-sweep duty — it channels the sweep's
  beyond-inventory findings into work orders. Finished out-of-scope
  work is relocated, never discarded: revert it from the branch, and
  the deferred issue carries the exact pre-revert commit SHAs and the
  pin verbatim, so its own (usually micro) case can reapply directly.
  (RM-0122)
- Scope budget (autonomous commissions): the case's diff stays within a
  small multiple of its inventory; guard or test growth beyond the
  inventory's shape needs a one-line justification in the loop status
  of the round that adds it. (RM-0123)

## The loop and the stop rule

```
review → fix → review the fixes (wave review) → fix → …
```

- A round's disposition covers ALL findings of its review — fixed or
  deliberately-not-done, each one. An instruction like "fix F1 first"
  sequences work INSIDE the round; it does not end the round. One wave
  review per round, batching all of the round's fixes — never one per
  finding or per ad-hoc slice. (RM-0106)
- The cadence authority is the commission: maintainer-gated variants
  fire each round on the maintainer's go; autonomous commissions run
  rounds back to back inside the loop cap. Pushes and PR creation are
  the agent's job in every variant (AGENTS.md Rules (the never-commit-on-master rule): approvals only
  count when the agent is the PR author and last pusher — the opencode
  permission prompts stay the runtime gate), with the
  `.github/workflows/` permission-denied exception handed to the
  maintainer. In both shapes round completion is reported (naming
  owed-but-not-run reviews), never self-advanced past a gate. (RM-0107)

**Stop rule.** A round is a review plus the disposition of its
findings. A round with no findings at all, or with every finding
deliberately not done, is the degenerate case — nothing changed,
nothing to review.

- Stop when a round leaves review-relevant code untouched: the loop
  closes when that disposition changed no review-relevant code. (RM-0064)
- Review-relevant is everything that has or wires behavior: `files/`
  (including the sudoers/config templates), tests and their pins, the
  Makefile, workflows, `scripts/`. Comments, `docs/`, CHANGELOG and
  bookkeeping are not. There is deliberately no "trivial" carve-out.
  (RM-0065)
- A round whose fixes stay in comments/docs/bookkeeping closes the
  loop. (RM-0066)
- On Track MED, a deliberate-not-done disposition of a LOW/INFO code
  finding opens no follow-on round: the disposition changes no code,
  so the loop closes on it like any no-code round — stated
  explicitly for the MED disposition policy, where the recording IS
  the whole disposition. (RM-0134)
- Any round whose fixes touch production or test code — regardless of
  the findings' severity — owes one more review: a diff-scope review
  of the fix diff at 1-axis micro staffing, not a full pass. Severity
  prioritizes; only code change extends the loop. (RM-0067)
- A round never declares the loop closed: the closing summary PROPOSES
  closure (the marker's `"state":"closing-proposed"`) with the
  stop-rule check cited ("this round's dispositions touched no
  review-relevant code: files touched = …"), and the MERGED PR is the
  confirmation — the maintainer's merge, not the loop's own words.
  (RM-0115)
- Closure is a recorded step, not only a verdict: the recorded closure
  IS the closing summary's marker — `"state":"closing-proposed"` — and
  the vocabulary never contains `"closed"`, which only the merged PR
  expresses. A closure proposal later retracted (a finding reopened the
  loop) is disclosed in the reopening round's comment; the proposed
  marker stays as history on the timeline. (RM-0118)

## Round typing and tiering

Classify the round's TRACK, then its TIER — both BEFORE staging a
round (never after the fan-out ran) — and state both in the loop
status before the fan-out launches. The tier comes from the round's
diff (`git diff --stat` plus content shape); the track from the PR's
diff PATHS — the blast-radius axis. Shipped means any file under
`files/**` (a mixed diff is track high); non-shipped means `tests/`,
`scripts/`, `.github/`, `Makefile`, `docs/`, `agent/`, `.agents/`,
`internal/`.

| Track | Round's diff | Tier | Review staffing | Verification |
|---|---|---|---|---|
| high | > ~50 lines or substantive logic | **wave** | 2–3 fast-tier axes | V3 (verifier batches + main audit) |
| high | ≤ ~50 lines, message-only | **micro** | exactly 1 fast-tier axis (~5 min) | main audit alone; else 1 batch |
| med | any (non-shipped only) | **med** | 1–2 fast-tier axes (triggers below) | main curation + verify sizing |
| either | comments / docs only | **none** | no review round owed | closure via the diff-shape proof |

- Track selection is mechanical and checked, not taken on trust: the
  implementing session states it in the PR body (`Track: high|med
  (paths)`), the review session re-derives it from the diff — a
  shipped path anywhere means track high, mixed diffs included (the
  full ladder is the price of touching shipped code) — and the
  marker records it (`"track":"high"|"med"`, a permanent field in
  every round's marker). A shipped diff misclassified as med is a
  process finding. CI-visible but non-shipped surfaces (`.github/`,
  `Makefile`, `scripts/`) run MED at full MED staffing, never
  lighter — CI breakage is still breakage. Let the ladder overrule
  predictions: it measures diff shape, not intent — a deletion-only
  round carrying +84 prose lines IS a wave. Solo means ONE subagent,
  never a main-solo review — the no-solo rule survives every tier
  and track. Severity can upgrade staffing, never downgrade it, and
  the escalation is precise: fix waves re-review at 1-axis micro;
  full wave staffing returns only when a NEW MED/HIGH finding
  escalates scope beyond the fix. Tier and track travel in the
  marker (`"tier":"wave"|"micro"|"med"`) and in the loop status
  prose. (RM-0124)
- Round typing names what a round's findings say about the loop: a
  round whose findings are predominantly fix-induced is BUILDING, not
  converging — new defects in the case's own fixes mean the built
  surface is still growing — and its loop status must say so
  explicitly, before the maintainer has to. A converging round's
  findings shrink in count and severity; rounds must shrink with the
  diff, and review weight shrinks with them. (RM-0125)

## Review tracks: HIGH and MED

Track HIGH (shipped code in the diff) keeps the full ladder — the
weight is justified where defects reach user machines via
`curl | sudo bash`. Track MED covers everything else. The
new-session entry changes WHO runs the loop, never how the review
pass works.

- Track MED staffing: 1–2 fast-tier axes in round a — a single axis
  for small diffs, 2 when the diff exceeds ~150 lines, touches
  CI-gating semantics (`.github/`, `Makefile`) or ships root-running
  `scripts/` code. Wave staffing (3 axes, curator, verifier batches)
  is an ESCALATION, never a starting point: it returns when round
  a's own findings produce a MED/HIGH. Round budgets for Track MED:
  ≤ 2 round comments and ≤ 1 fix push for chains without MED/HIGH
  findings — a MED/HIGH chain scales with its findings instead (the
  budgets describe the common case, not a cap on fixing).
  (RM-0131)
- New-session entry (the batch shape): a BATCH commission splits
  the roles — the implementing session ONLY implements and opens one
  birth-PR per case; it never runs the review loop of its batch's
  PRs (its context compounds across cases — 303k after six, versus
  83–110k flat for fresh review sessions). Each PR's loop
  (curation, verification, dispositions, fixes, comments, closing
  summary) runs in ONE fresh review session commissioned per PR —
  never two: reviews land in fix work almost always, and the first
  case's fix waves would load and anchor the second, spending the
  freshness the entry exists to buy; session startup amortizes
  through PARALLEL sessions, not stacked PRs (rolling, max 2
  parallel review sessions under the 5-seat subagent cap). A
  single-case commission keeps the single-session shape: Session
  MAIN implements and runs the loop itself, the review pass staying
  a subagent as everywhere. In EVERY shape the review pass is
  ALWAYS a subagent — round a runs ≥ 1 fast-tier axis (2 under the
  Track-MED triggers; any shipped file runs Track HIGH staffing from
  the start), so the contamination rule holds automatically: every
  round reads the tree through fresh subagent eyes that never saw
  the session's reasoning, and a session that fixed something in
  round X still gets an unbiased round X+1 with no freshness
  bookkeeping. Marker mode `"new-session-review"`; a main-direct
  review pass (a `reviewers:0` marker) stays a disclosed deviation,
  never a template. (RM-0132)
- Disposition policy on non-shipped (MED) diffs: MED/HIGH code
  findings are fixed with their class sweep, like every track.
  LOW/INFO code findings are deliberately not done, RECORDED in the
  round comment — no fix, no follow-on round, and no new LOW issue
  from a non-shipped diff (deferred issues remain a MED/HIGH
  channel). Two in-round exceptions close claims without opening fix
  rounds: LOW/INFO findings on comments/docs-only content may be
  fixed in the same round, and a pin completion of ≤ ~3 lines that
  closes a behavioral claim of the case's own wave may be fixed
  in-round — a true-but-unpinned claim is a claim-audit gap, not
  polish. (RM-0133)

## Curation and verification

- Curation (x): a fast-tier curator subagent merges and de-duplicates
  the raw reviewer checkpoint files into ONE digest file — findings
  table, merges named, drops with reasons — and the main session
  reads only the digest, never the raw files. The curator deploys
  only when the round ran ≥ 3 reviewers AND produced > 10 raw
  findings; at lower volumes the digest is one screen and the main
  session curates directly, disclosed in the comment's provenance.
  (RM-0126)
- Verification (V3): every curated finding is re-verified against the
  code — and the verification is SIZED: at ≤ 3 curated findings, all
  LOW/INFO, the main session verifies inline (no verifier
  subagents); above that, or at any MED/HIGH finding, exactly ONE
  fresh strong-tier verifier batch runs (verdict files per batch) —
  a hard gate: skipping an owed batch is a process deviation only a
  maintainer disclosure can carry, never a time-pressure call. The
  main session audits the verdicts — re-deriving every MED/HIGH
  itself, spot-checking LOW/INFO; refuted findings are retracted with
  the refuting evidence named. Subagent freshness replaces session
  rotation as the bias-reduction mechanism: the author's loaded
  context never verifies its own claims. (RM-0127)

## Reviewer freshness

The PR-native process runs a single-case loop in ONE session
(Session MAIN implements and runs the loop — the review pass stays a
subagent); a batch commission splits the roles: Session MAIN
implements, and each PR's loop runs in a fresh single-PR review
session ("Review tracks"). The freshness the old session rotation
bought comes from subagents instead:

- The session that runs the case also applies the fixes — no handoff
  back; what the substitution preserves is the rotation's core: a
  round's author never reviews their own fixes. Review passes run
  fresh-context reviewer subagents, verification runs fresh verifier
  subagents (V3 above). (RM-0060)
- Rounds chain inside Session MAIN — the pauses that remain are the
  ask-gates (push, PR creation), the maintainer steerings, and the
  loop cap. An autonomous round never consumes the maintainer's
  visibility window silently: round completion is reported (findings,
  dispositions, owed-but-not-run reviews) in the round comment on the
  PR timeline. (RM-0061)
- The round comment's metadata records who ran the pass — reviewers
  (model + axes), curator, verifiers, tier — so freshness stays
  auditable from the PR timeline after the fact, not from memory.
  (RM-0063)
- Freshness is measured in subagent contexts, not sessions: every
  reviewer and verifier starts fresh by construction; Session MAIN
  never reviews its own wave solo — main-solo is banned at every tier,
  micro included — and the single-session case is the normal shape,
  not a self-declared exception needing sanction. (RM-0109)
- A freshness violation anyway (a pass ran main-solo, or the author's
  loaded context reviewed its own fixes) is recovered, not improvised:
  the round comment records the deviation, the affected verdicts are
  marked non-authoritative (their resolution status stays open), and
  the next round's mandate has two mandatory parts — re-verify the
  deviant round's CLEAN verdicts, not only its findings, and run its
  own pass over the same range. (RM-0110)

## The round comment contract

One comment per review round, format v2 (nested details):

```markdown
## Review <letter> — <case subject> (round N)

**Round N · <count> findings (<sev breakdown>) · <state> · CI <status>**

<details><summary>Round <letter> — metadata · findings · dispositions · loop status</summary>

Base: <tag> @ <sha> · Diff: <range>
Reviewers: N × <fast-tier model> (axes) · Curated by: <flash|main>
Verified by: N × <strong-tier model> (V3) + main audit (MED/HIGH all, LOW/INFO spot)
CI on last push: <status + check names>
Curator accounting: raw N → curated N (merges named) · dropped 0

### Findings
| ID | Sev | Provenance | Verifier verdict | Summary |
|---|---|---|---|---|

<details><summary>finding details</summary>
…MED/HIGH full mechanism; LOW/INFO one line + anchor…
</details>

### Dispositions (from round <prev letter>)
| ID | Disposition | Commit / Issue | Key evidence |

### Loop status
Review-relevant code touched this round: yes/no → …

</details>

<!-- opk-review {"case":"<pr>","wave":"<letter>","raw":N,"curated":N,"posted":N,
     "retracted":N,"dropped":N,"med":N,"high":N,"state":"…","mode":"…",
     "track":"high|med","tier":"wave|micro|med","reviewers":N,
     "curator":"<flash|main>","verifiers":N} -->
```

- One comment per review round, format v2: visible at level 0 ONLY the
  headline and ONE status line (round, finding count + severity
  breakdown, state, CI status) — notification mails strip details
  content, the status line is what survives. The outer details block
  (level 1) carries metadata, curator accounting, findings and
  dispositions tables, loop status. Per-finding detail prose nests one
  level deeper; TWO levels maximum (deeper nesting renders
  unreliably), and a blank line follows every `<summary>` tag (tables
  and headings inside details render only with it). The `opk-review`
  marker is the LAST line of the comment body, OUTSIDE the details —
  "last line of the comment" is the tooling invariant, not "somewhere
  in a details block". State vocabulary: `"open"` for round comments,
  `"closing-proposed"` for the closing summary — `"closed"` is never
  written by the loop itself; the MERGED PR is the confirmation. The
  closing summary is the one exception to nesting: it keeps the
  disposition ledger table and the stop-rule check visible at top
  level (the one-view chain record) and nests only per-finding
  evidence. (RM-0128)
- Size guard: GitHub caps one comment at ~64k characters; a comment
  that would exceed ~60k is SPLIT into part 1/2 (each part with its
  own marker and a `"part":1|2` field) — content is NEVER trimmed to
  fit. Preferred over splitting: per-unit comments (one per
  file/round) when the process shape allows them. (RM-0129)

## Fixes close classes, not sites

- A fix wave owes a class sweep: grep the anti-pattern across every
  shipped file — and the docs that claim the invariant — not just the
  finding's file. (RM-0069)
- The sweep result is recorded in the round comment's dispositions
  (what it found beyond the listed lines), so the next review can
  audit it. (RM-0070)

## Who records what

Four places carry review knowledge, each with exactly one job:

| Place | Records | Mutability |
|---|---|---|
| Round comment (PR timeline) | **what was found + how dispositioned** — findings with IDs, verifier verdicts, dispositions, loop status | append-only: never edited; corrections land in later rounds or the closing summary |
| Fix commit (message) | **what was done**; finding IDs qualified (`(#293 a S1)`, legacy `(0.0.41f C1)`) | git history |
| Birth-PR (the case key) | the chain itself — comments in letter order, pushes, CI runs; the loop writes it, never reads it back | the timeline is the case's ledger |
| Corpus at tag `review-corpus` | the archived repo-file era (0.0.38–0.0.57) | frozen history — cite the tag |

- The disposition ledger in each round comment is the record the next
  round starts from — the timeline as a whole is the case's ledger,
  and any summary of it is a summary, not a substitute: per-finding
  dispositions with rationale live in the comments' disposition
  tables. (RM-0071)

## Finding provenance

- Every release review records which release introduced each finding:
  `git log -L`/`-S` to the oldest commit touching the offending code,
  then `git tag --contains` for the first release that shipped it.
  (RM-0072)
- Distinguish two dates in the table: *bug-form since* (the reported
  behavior first existed) and *code since* (the site's age — older
  where a fix reshaped an old bug without closing it). (RM-0073)

## Verification duty

- Every reviewer-agent finding is re-verified against the code before
  it enters the round comment — by the fresh verifier subagents, with
  the main session auditing (V3 above); unverifiable claims are
  dropped or marked `unverified`. (RM-0074)
- Retractions stay visible in the round comment's "Retracted/ghost
  findings" section — they calibrate how much to trust the next
  unverified claim. (RM-0075)
- A review round MAY run sabotage spot-checks — execute a failure
  path instead of reasoning about it: delete (never comment out) the
  construct on a committed, clean tree, observe the failure the way
  production would, restore, re-run green; reader-window conditions
  per "Parallel reviewer agents". When a prior round's verdict was
  reached by reasoning alone, the successor executes at least one
  representative failure path of it. (RM-0112)

## Suites are the standing review

Between reviews, the unit/e2e suites are the review (see also the
"shrink the next one" rule in
[process/review.md](../internal/process/review.md)):

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
- Record the environment in the round comment (opencode binary version,
  host layout). (RM-0078)
- A disposition claim ("closed", "never dereferences", "any … aborts")
  owes a behavioral test, not prose: every such claim in a round
  comment or code comment names its pinning test in the same wave —
  otherwise it is not a claim, it is a hope. (RM-0079)

## Review focus: shipped code first, pins at a floor

- **Shipped code is the primary scrutiny target; a pin's quality bar is
  a floor, not a ceiling.** The code that runs on user machines —
  `files/` including the sudoers/config templates, the Makefile,
  workflows, `scripts/` — must be very good, and review waves spend
  their attention there first. A pin's full quality bar is what
  [learnings.md](learnings.md) L4 names: it discriminates
  (sabotage-verified — it fails when its behavior breaks) and it sits
  before the suite's summary gate. A clunky pin that fails loudly is
  DONE. Fixture elegance, wording polish and structural beauty beyond
  the floor are foreign-topic taste findings — the scope brake's
  channel applies: deliberately-not-done with the reason recorded, or a
  deferred issue, never a fix wave. Polishing a WORKING pin inside a
  round (reviewer finding or fix-wave "improvement" alike) is exactly
  that in-passing improvement, and the process is the safety net that
  makes stopping early safe: rounds re-review every fix wave, sabotage
  spot-checks execute failure paths, the standing suites re-run every
  wave — a pin that works today can still be improved later, when a
  real defect shows the need. Sibling rule on the writing side:
  [conventions.md](conventions.md#pin-cost-budget-unit-suites).
  (RM-0130)

## Parallel reviewer agents

Execution choreography (fan-out staging, axis-prompt construction,
checkpoint mechanics, comment writing): load the `opk-review-pass` skill
(`.agents/skills/opk-review-pass/`) — the rules below stay authoritative
here.

- The main agent runs a strong default model and owns the
  verification duty; every reviewer subagent runs the provider's
  cheaper fast tier (house instance: GLM-5.3 + GLM-5.3-Flash —
  substitute your provider's strong/fast pair). (RM-0080)
- Reviewer subagents get ad-hoc axis prompts per session (mechanical
  sweep, security, quality); the durable spec any reviewer prompt
  implements is the subagent output contract (the final-chat-answers
  rule below) plus the finding vocabulary: stable finding IDs, house
  severities, findings index, provenance. (RM-0081)
- A coverage claim is NEVER verified via the mechanism that makes
  the claim — guards, manifests and checklists are themselves review
  objects: enumerate the executed commands / on-disk files
  independently before repeating what they report. (RM-0082)
- For release reviews, a second independent pass from a different
  context — a different model family and/or an operator setup that
  keeps the house skills out — is the strongest redundancy. Repo-level
  skills are visible to every session in the checkout, so that
  independence is the commissioning operator's doing, not the loading
  agent's self-restraint; a redundancy pass that loaded a house skill
  anyway discloses it in its report's `Skills:` provenance line.
  Integration duties: full per-finding verification by the main
  session, honest provenance in the report header (model, tree, what
  ran on which host), findings recorded as reported with verification
  marks, and a calibration section naming what each side missed and
  why. (RM-0083)
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
  and checkpoints survive them. Side files live under session scratch
  OUTSIDE the reviewed tree; the round comment's run provenance
  absorbs them. (RM-0086)
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
  read → mark `unverified`, move on. The tier ladder above fixes the
  budgets. The numbers in the axis PROMPT are scope-limiters and
  stay there as written; PLANNING (round pipelines, targets) uses
  the observed 8–10 minutes per axis, measured by host timestamps
  only — sandbox clocks drift, so budgets and overrun targets are
  never enforced against them (the percentage-overrun target was
  dropped 2026-10-31, issue #324). (RM-0087)
- Full-scope passes: ~15 minutes per agent PLUS a coverage map — every
  shipped file gets at least one grep-anchored look, every deferral is
  recorded as one in the checkpoint; the coverage map is the real
  budget, the minutes only its ceiling (agents cannot watch clocks —
  they spend sections). (RM-0088)
- Release-critical full passes: prefer a second independent agent per
  axis over a longer single agent — redundancy replaces depth, and
  ghosts cross-cancel before they reach the main agent. (RM-0089)
- Final chat answers are EXACTLY one status line plus the file
  path(s) — no findings, no excerpts, no file content (the subagent
  output contract): the checkpoint/digest/verdict FILE is the
  deliverable; a response beyond the status line enters the lead's
  context and is ignored, and the violation is disclosed in the next
  comment's run provenance. A subagent's final message lands in the
  parent session's context — that IS the bloat path; the file is the
  transport, the response only the pointer. (RM-0090)

## Release gate

- Before cutting a release: the loop's stop condition must hold (the
  last round's dispositions touched no review-relevant code) **and**
  no unmerged PR carries an unresolved `opk-review` marker **and**
  both e2e suites are at baseline level with zero skips. Only then
  tag. (RM-0091)
