# Review calibration — history and evidence base

> Status: **CURRENT.** Design record for the review process: the
> development history, calibration data and incident evidence behind
> the operative rules in
> [agent/review-concept.md](../../agent/review-concept.md). Split out
> of that file on 2026-10-19 (rule-meta Phase 3) — the rule file
> carries the rules, this record carries the stories. Nothing here is
> required reading for running a review; rule-level rationale lives in
> the rule-metas (`internal/rules-meta/`, one per rule unit).

## Origin

The review concept was written after three review rounds on
0.0.38/0.0.39 (snapshots
[0.0.38](../reviews/0/0/1/0/pr-00109/review-a.md),
[a](../reviews/0/0/1/1/pr-00115/review-a.md)/
[b](../reviews/0/0/1/1/pr-00115/review-b.md)/
[c](../reviews/0/0/1/1/pr-00115/review-c.md)/
[d](../reviews/0/0/1/1/pr-00115/review-d.md))
— the numbers throughout this record are that history, not theory.

## Stop-rule evolution

The stop rule was revised 2026-10-11, from the 0.0.46a→0.0.46b and
0.0.47b→0.0.47c chains. The prior form, "stop when a full pass returns
no new MED/HIGH", closed chains whose LOW fixes then changed code.

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
"LOW/INFO do not extend the loop" precedent; under the revised rule
both converge: comment-only rounds close, code-touching rounds
continue.

The comment-only precedent: 0.0.45f's comment-only micro fix
(`014d5eb`) needed no successor pass — nothing review-relevant had
changed.

## Convergence data

Why a stop rule instead of a fixed number of rounds: the process
converges. The project's own history:

| Round | Findings | Character |
|---|---|---|
| 0.0.38 full | ~54, several HIGH/MED | deep, real problems |
| 0.0.39 a+b full (independent ×2) | 59 rows, ~2 MED bugs | rest LOW/doc drift; tail is high-variance noise |
| 0.0.39d wave (diff) | 3 MED | **all introduced by the fix wave itself** (set -e fallout) |
| expected next full pass | few | convergence |

Two consequences:

- A fixed "review 3–4 times" wastes the later rounds re-litigating
  accepted residuals — only 3 of the 59 a+b rows overlapped between
  the two independent snapshots, so the tail is high-variance noise.
  Round 3+ finds taste questions, not defects.
- The strongest argument **for** the loop is round d's result: fixes —
  especially robustness fixes — introduce their own bug class. Never
  skip the wave review after a semantics-changing wave.

## Hard-seam origin (0.0.42d)

The loop has a hard seam after verification: the snapshot is written
and committed BEFORE any fix starts. Codified in the 0.0.42d session
after the maintainer asked for the snapshot first, for two reasons:
the maintainer reads the committed snapshot to see what the review
found before the tree starts moving (findings must be inspectable
while nothing has been done about them yet), and a fix applied
mid-verification would change the very tree the remaining findings
are verified against.

## Session-rotation origin (pr-00189, 2026-10-17)

pr-00189 snapshot b reviewed its own fix wave inside the implementing
session — its header carried only the usual "house session" label,
identical in shape to snapshot a's; the same-session fact surfaced in
maintainer chat, never in the snapshot (#189 c C5). The author's
context carries its blind spots into the review of the fix. The
session-rotation default in the concept file dates from that case.

## Class-sweep provenance (0.0.44a)

Of 0.0.44a's 28 findings, six were **incomplete closures of earlier
fix waves** (0.0.44a V1, V2-claim, V8, V9, V11, V12), every one the
same shape — the *reported* site was fixed, the *class* and its
siblings were not: the 0.0.42e C5 tmp-name sweep fixed three of four
staging sites; the F1 dedup-hoist rationale applies verbatim to the
gh-dedup left in place; the hardcoded-home class was closed in four
files but not in the installer that itself contains the correct getent
pattern. 0.0.39g's `2db6517` had already done the sweep ad hoc ("full
-class sweep beyond the listed lines"); 0.0.44a made it the rule.

## Recording-role separation (the 0.0.41 chain)

The four recording places (snapshot, fix commit, resolution, index)
each have exactly one job — the 0.0.41 chain blurred them: dispositions
front-ran into index rows and snapshot prose, and the resolution became
a retroactive reconstruction; the role table in the concept file is
that learning codified.

## Provenance precedents

Finding-provenance recording (which release introduced each finding)
has two precedents: 0.0.39c (57/59 of the -a/-b rows pre-existing at
tag 0.0.38) and 0.0.44a (26/28 findings predate the fix waves; no MED
new at its core, but two waves falsely claimed closure of old bugs).
The split answers the two questions findings alone cannot: how many
defects the fix process *introduces or reshapes* (regression rate —
governs the fix process) versus how much old backlog each pass
*surfaces* (detection yield — governs the review budget).

## Ghost findings

Ghost findings are normal, not embarrassing: 0.0.39a retracted two,
0.0.39d retracted one (a grep that looked unguarded but sat behind a
counting branch). Keeping retractions visible in the snapshot
calibrates how much to trust the next unverified claim.

## Incidents behind the hard rules

- **Root-script behavior changes owe the e2e suites immediately:**
  a pipefail regression once downgraded 21 e2e checks to SKIP and the
  suite still reported green — only the skipped-counter betrayed it.
- **Record the environment in the snapshot:** an upstream release on
  the review day (opencode 1.18.33) changed login behavior under the
  suite; without the version in the snapshot, its results are
  uninterpretable afterwards.
- **Disposition claims owe behavioral tests:** two 0.0.43a/b closure
  claims were empirically false at first probe — F16's "TOCTOU closed"
  (0.0.44a V2: a trailing-slash operand defeats both the `[ -L ]` gate
  and `chown -R -h`, because path resolution goes through the link
  before lstat ever sees one) and W5's "any single failing entry
  aborts" (0.0.44a V9: only batch-final failures propagate through the
  xargs inner loop). Each would have fallen to one behavioral test at
  fix time.

## Model-policy history

- 2026-09-27: higher-reasoning variants rejected (timeout-prone).
- 2026-09-29: the current policy date — main agent on the strong
  default model owning verification, every reviewer subagent on
  GLM-5.3-Flash.
- 0.0.38/a–c ran Flash end-to-end on the crashing opencode-go
  provider; d–g ran the judgment agents on GLM-5.3 (gateway default)
  before the policy made all-Flash explicit.
- The former pinned reviewer definition files (`review-mechanical.md`
  and siblings) were global session configs outside this repo and have
  since been removed; the durable spec any reviewer prompt implements
  is the reviewer output contract (reviews README).

## Ground-truth calibration (0.0.42d/-e)

A claim like "CI runs every suite" is never verified via the mechanism
that makes the claim: the 0.0.42d mechanical agent asserted "CI runs
all 33" by counting `.sh` tokens exactly the way the guard does, and
0.0.42e C2 then exposed that guard as token-blind (an argument-position
suite never executed).

## External-model passes

A different model family as the second snapshot of a release review is
the strongest form of "redundancy replaces depth" — the 0.0.42e
external pass (GPT-6 Luna, same tree) caught 16 findings the house
pass had missed (2 HIGH incl. the executed host-path `rm`), while the
house pass held findings the external one lacked. Integration
outcome: 25/26 findings confirmed by main-agent verification; even
retractions can be partially over-turned by the external reviewer's
counter-feedback (0.0.42e S3 → LOW carve-out).

## Invocation-shape calibration (0.0.45b/-c) and its correction

The opencode built-in `/review` command dispatches differently across
majors — verified in the pinned checkouts: 1.x (v1.18.34) registers it
`subtask: true`, so the template runs inside ONE build subagent that
cannot launch subagents of its own (single context, sequential roles),
while 2.x (v2.0.22) injects the template into the main session
(`ctx.session.prompt`), where the lead can fan out parallel reviewer
subagents and run empirical verification. Same model, same prompt,
same tree class: the 1.x shape produced 2 LOW + 2 INFO in ~8 minutes
(0.0.45b, delta focus solid but no breadth), the 2.x shape 2 HIGH +
6 MED + 25 LOW/INFO in ~55 minutes (0.0.45c, four fresh-context axis
subagents + lead verification). The templates themselves are
near-identical across majors (three cosmetic lines, v1.18.34 vs
v2.0.22).

Calibration correction (2026-10-07, maintainer challenge upheld): an
earlier revision of this note claimed house passes with full
orchestration reach comparable full-scope yields, citing 0.0.43a (19
findings) and 0.0.44a (28) — those snapshots were in fact **external
integrations** (0.0.42e = GPT-6 Luna; 0.0.43a, 0.0.44a, 0.0.45c =
external GLM-5.3 sessions in the v2 lead+fan-out shape, none with kit
skills or agent definitions installed; provenance folders in the dev
workspace). Corrected record: **every deep full-scope yield so far
came from an external pass**, and the only same-tree comparison —
0.0.42d (house, skill mechanics + Flash reviewer agents: 2 MED) vs
0.0.42e (external, same tree: 2 HIGH + 7 MED, 16 findings the house
pass missed) — favored the external pass (confounder: the house
reviewers ran GLM-5.3-Flash per the cost policy). Skills and pinned
agents keep a proven record only in **wave/diff scope** (0.0.45a,
0.0.44b–g, 0.0.42f–i repeatedly caught fix-induced bugs; 0.0.45b's
delta verification was solid even inside the v1 subtask shape). For
full scope their value is unproven, not exonerated — and the standing
rule (external v2-shape pass for release reviews) no longer relies on
them.

## Blind-spot classes

Three classes have each escaped at least one dedicated review
(0.0.44a): root-run file operations whose operands sit in
agent-group-writable directories (0.0.44a V3, alive since 0.0.18
despite four reviews touching the same function), producer/validator
pairs built in the same wave whose halves contradict each other (V4,
since 0.0.39: the builder joins with `", "`, the validator rejects
commas), and path-operand edge forms — trailing slashes — that slip
symlink gates (V2, since 0.0.40).

## Budget evolution

The flat ~8 min per agent was a heuristic, not a measurement — revised
2026-10-01 after the 0.0.39 loop into the per-scope budgets the
concept file carries. Wave-scope ~8 min validated by 0.0.39 j/k: every
in-scope finding was found within budget, no triage deferrals.
Full-scope: 0.0.39l showed ceiling pressure even on a converged tree
(install.sh mid-sections "spot checks only", tui assets deferred) —
and there is no all-Flash full-pass data on a *rotted* tree (the deep
passes 0.0.38/e/g ran on the strong model); hence the coverage map as
the real budget and the minutes only its ceiling. Agents cannot watch
clocks — they spend sections. When checkpoint files carry timestamps
(cheap, optional), a future pass can A/B budgets against
verified-finding yield and turn the grading into a measurement. The
ceiling is a limiter, not a target: the loop's actual rate limiter is
the main agent's verification duty — every extra agent-minute yields
findings that cost verification minutes, and round 3+ agent time
mostly re-litigates accepted residuals.
