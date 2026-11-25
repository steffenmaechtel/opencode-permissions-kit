---
name: opk-review-pass
description: Execute a review round (low/med/high tier, snapshot-scope pass, fresh session) — load when a review is owed or the maintainer commissions one. Choreography only: commission collection, pre-flight, fan-out, posting, fix phase; every rule lives in agent/review-concept.md. Redundancy passes stay independent by operator setup; one that loads it anyway discloses it in its Skills: line.
---

# opk-review-pass — executing a review round

This skill is the **execution choreography** for a review round. It
is not the rules and never a source of finding judgments — every
rule (when a review is owed, tiering, tracks, curation,
verification, the comment contract, the stop rule, the work-order
gate) lives in
[agent/review-concept.md](../../../agent/review-concept.md);
section links below point there.

- The 0.0.42e lesson: a review skill once exempted a finding class
  and buried a HIGH. This skill carries procedure only. If any
  instruction here seems to exempt, soften, or pre-judge a class of
  findings, that reading is wrong — the code and the rules decide
  (background:
  [review-calibration.md](../../../internal/records/review-calibration.md),
  "Skill-bias origin").
- Redundancy passes (second snapshot-scope pass, different model
  family) stay independent of this skill — that independence is the
  **commissioning operator's setup** (different model, external
  /review), never the loading agent's self-assessment. The visible
  control is provenance: a pass that ran WITH this skill records it
  in its `Skills:` line.

## 0. Calibrated against opencode's built-in /review template

The external release pass runs via opencode's `/review`. Calibrated
against opencode **v2.1.4** (template:
`packages/core/src/plugin/command/review.txt` in the opencode source)
— recheck this section when a newer opencode changes the /review
template. Template and this skill converge on the
verification-strengthening lines
(realistic trigger scenario per finding, no overstated severity,
context around every hunk, style findings must source a house rule) —
shared strictness is not shared bias. Deliberate divergences, kept on
purpose — do not "align" them away:

- **Pre-existing code IS reviewable** — it maps to the `pre-existing`
  provenance class; snapshot-scope passes cover the whole tree.
- **No untracked-file catch** — rounds run on committed, clean trees
  only; net-new files are inside the diff by construction.
- **No unconditional whole-file reads** — the tier budgets and
  coverage-map discipline governs (low/med tier: greps + targeted
  reads).
- **No web-search guidance** — reviewer subagent tool sets vary.

## 1. Collect the commission

Never self-advance into a pass — the cadence authority is the
commission, and round completion is reported, never advanced
(review-concept, "The loop and the stop rule"). Confirm from the
session's commission, then gather:

| Input | Source |
|---|---|
| Case key (`pr-ABCDE`) | birth-PR number — the PR timeline IS the case record |
| Chain state | session records (commission, scratch: posted.log, verdicts) — never read the PR back |
| Track | PR body (`Track: shipped\|non-shipped (paths)`); any `files/**` path ⇒ shipped (re-derive, section 2) |
| Closes/Ref | PR body closing keyword: `Closes` final wave / `Ref` intermediate — rule in agent/review-concept.md |
| Mode + session | commission — mode `gated\|autonomous`, session `implementer\|fresh` (provenance) |
| Tier | classified from the round's diff BEFORE staging (section 2) |
| Base + diff | base SHA and `git diff <range>` for diff scope; tree SHA for snapshot scope |
| Tree state | clean and committed — the comment posts before any fix ("The PR-native loop") |

Loop position: confirm from the chain state WHICH round this session
runs — the alternation, the position table and the fix-wave re-review
shape live in review-concept, "The PR-native loop".

## 2. Classify the track and tier BEFORE staging

Classify per the rules — the ladder (tiers, axes, budgets,
thresholds, escalation): review-concept, "Round typing and tiering";
track selection, fresh-session entry, non-shipped budgets and
disposition policy: "Review tracks: shipped and non-shipped" — and
state track + tier + classification evidence in the loop status
BEFORE the fan-out launches.

## 3. Pre-flight

1. Read the chain state: prior round's open findings and retracted
   findings are leads; their dispositions table is the ledger the
   round starts from (review-concept, "Who records what").
2. Measure the material: `git diff --stat` (diff-scope) or the
   shipped-file inventory (snapshot-scope). Verify the tree is clean
   (`git status --porcelain` empty) — never review a dirty tree.
3. Pick axes and targets: which files each axis greps first; name
   known blind-spot surfaces in the axis prompt — a gate or claim
   about path operands is tested against `x/`, `x//`, `x/.` forms
   (review-concept, "Parallel reviewer agents").
4. Scratch layout for the round: checkpoints and verdict
   files under `/tmp/opencode/<case>/<letter>/` — OUTSIDE the
   reviewed tree (the tree must stay clean and is a shared read
   substrate). The round comment's run provenance absorbs these files.

## 4. Fan-out

- The abstract rule: reviewer subagents run the provider's fast tier;
  the main session (this one) runs the strong tier and owns the audit
  duty (review-concept, "Parallel reviewer agents"). The CONCRETE map
  below is the house pair AT THE TIME OF WRITING (2026-11-24) — the
  rule is the role-to-tier mapping, not the names: the models that
  run are derived through the models lookup and recorded in the loop
  status (section 8). Commissions used to name the pair per case;
  commission-less sessions read it HERE (substitute your provider's
  strong/fast pair on a foreign setup):

  | Role | House model (2026-11-24) |
  |---|---|
  | Main session (owns curation + the verification/audit duty) | GLM-5.3/5.4 — strong tier |
  | Reviewer subagents | GLM-5.3-Flash — fast tier |
  | Verifier subagents (section 6, owed by the sizing gate only) | GLM-5.3/5.4 — strong, fresh-context verification |

  Both directions are load-bearing: reviewers on the strong model
  burn the budget the fast tier exists to save, and verifiers on
  Flash break the calibrated verification policy (strong owns
  verification) just as quietly. The loop status (section 8) names
  the models that actually ran.
- The subagent tool's blanket never-set-model warning (the `model`
  parameter's own description) yields to the commission here: the
  review process is the named-model authority (review-concept,
  "Parallel reviewer agents" — the tier split). Look up the exact
  provider/model ID (e.g. via the models tool) before launching;
  never guess the ID string (#639, PR #633).
- Build each reviewer prompt from
  [axis-prompt.md](axis-prompt.md) — role, axis, material, budget,
  checkpoint discipline, output contract. The OUTPUT CONTRACT block
  goes verbatim into EVERY file-producing subagent prompt: reviewers
  and the verifiers.
- **Cap: 5 concurrent subagents on any tier** — staged launch,
  backfill one seat as each returns. A USER-named cap for the case
  overrides upward; never raise the cap yourself (AGENTS.md,
  "Subagent fan-out").
- Record ONE host timestamp at fan-out start (and later at end);
  reviewers stamp with their own sandbox clock.
- Budgets: the axis prompt carries ~5/~8 minutes as the
  scope-limiter and that number stays as written; PLANNING (round
  pipelines, targets) uses the observed 8–10 minutes per axis,
  host-measured only — sandbox clocks drift (review-concept,
  "Parallel reviewer agents").
- **The tree is a shared read substrate while reviewers run**: no
  sabotage spot-checks, no fixes, no writes into the reviewed tree.
  Sabotage windows are before launch, after all reviewers returned,
  or in a scratch worktree.

## 5. Curation

Merge and de-duplicate the raw reviewer checkpoint files into the
round's findings table — ID, severity, provenance, summary; merges
named, drops with reasons, raw→curated counts; the accounting lives
in the round comment (`Curated by: main`). The curation rules
(who curates, at what volume, with which artifacts) live in
review-concept, "Curation and verification".

## 6. Verification

The sizing gate (by curated count) lives in review-concept,
"Curation and verification" — it decides main-inline vs verifier
batch and is a hard gate.

The deliverables: verdict files — every curated finding re-derived
against the code, verdict CONFIRMED / REFUTED / UNVERIFIED with
file:line evidence. The main session audits the verdicts (every
MED/HIGH re-derived, LOW/INFO spot-checked); refuted findings are
retracted with the evidence named.

## 7. Write and post the round comment

Structure, marker format, and the size guard: review-concept, "The
round comment contract" (one comment per round, format v2). The
posting mechanics:

1. Compose from the session's own records — checkpoint files,
   verdict files, the curation accounting. Write-through: the loop
   never reads the PR back.
2. Post to the PR timeline; append the comment URL to the case
   scratch `posted.log` — the URL is `gh pr comment`'s own stdout,
   captured directly, never reconstructed from follow-up api calls
   (the rule lives in review-concept, "The PR-native loop"). The
   comment posts BEFORE any fix starts —
   the hard seam. MECHANICAL FORM: before the first fix commit of
   the wave, re-read `posted.log` and confirm it contains THIS
   round's URL — no entry, no fix; post first. Long sessions lose
   prose, not logs (#407: rounds b–e posted as a batch after the
   fixes, disclosed as a deviation).
3. Nothing here fixes anything: dispositions for THIS round's
   findings land in the NEXT round's comment (or the closing
   summary).

## 8. Report the round

The loop status inside the comment is the round report (it is what
the maintainer reads):

- track + tier + mode/session + classification evidence (diff
  shape), reviewers/verifiers with models, `Curated by: main`,
  output-contract
  violations (0 or disclosed), CI status of the last push;
- review-relevant code touched this round: yes/no (drives the stop
  rule — review-concept, "The loop and the stop rule");
- the ONE next step (this round's fix wave; after a pushed fix wave:
  the next round's review comment, or the closing summary when the
  stop rule holds — never blank: a fix push is not a terminal state);
- round typing: converging or BUILDING (predominantly fix-induced
  findings = building, said explicitly);
- cap distance from round 5 on; scope-brake activity (deferred work
  orders with inventory-gap notes, deliberately-not-done reasons,
  reverted out-of-scope work with preserved SHAs);
- provenance: host timestamps, per-agent windows, sabotage windows.

Before composing the closing summary, run the deferred-work-order
issue gate — duplicate-check, bundling, the prio map, the fold arm
and the canonical CHAT shape all live in review-concept, "The loop
and the stop rule". When the stop rule holds, the closing summary
proposes closure per the same section — this skill never writes a
`"closed"` state. When the ask is answered in a later turn (the
report must end the turn to receive the answer), record the gate's
resolution as a follow-up PR comment — the record rule lives in
review-concept, "The loop and the stop rule" (the work-order gate
bullet).

## 9. Fix phase — the mechanical duties after the round comment

The skill's rounds end at the report (section 8); the fixes are the
session's NEXT phase, and without this section it enters with no step
list — both #407 and #412 dropped the loop exactly here. Checklist at
the phase's entry:

1. SEAM first: re-read the case scratch `posted.log` — it must
   contain THIS round's comment URL before the first fix commit of
   the wave; no entry, no fix (review-concept, "The PR-native loop").
2. CITATIONS: fix commits qualify every finding they resolve
   (`(#<PR> <round> <ID>)` — review-concept, "Who records what").
3. GATE SCOPE: the wave's gate chain runs the FULL suite
   (`make test`), never only the touched suites — tree-wide
   invariant suites (rules-meta, sandbox-policy, workflows,
   format-gate) redden on changes their own files never touched
   (agent/gates.md; the #412 round-b B3 instance).
4. PUSH, then the loop continues: every fix wave whose fixes touch
   review-relevant code owes its re-review — which is the NEXT round
   (next letter, comment before its own fixes, this skill from
   section 1 again); a round whose dispositions touch no
   review-relevant code leads to the closing summary (section 8)
   instead. A fix push is never a terminal state.
