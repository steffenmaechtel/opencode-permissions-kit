---
name: opk-review-pass
description: Execute a house review pass (micro, wave, or full/release scope) — load when a round's wave review fires or the maintainer commissions one. Covers fan-out staging, axis prompts, checkpoints, screening, verification, snapshot writing; rules: agent/review-concept.md. Redundancy passes stay independent by operator setup — one that loads this skill anyway discloses it in its Skills: line.
---

# opk-review-pass — executing a review pass

This skill is the **execution choreography** for a review pass. It is not
the rules and never a source of finding judgments:

- When a review is owed, which scope applies, when the loop stops, who
  rotates — [agent/review-concept.md](../../../agent/review-concept.md)
  (the authoritative rules; section links below point there).
- Snapshot format, output contract, case-folder mechanics —
  [internal/reviews/README.md](../../../internal/reviews/README.md).
- The 0.0.42e lesson: a review skill once exempted a finding class and
  buried a HIGH. This skill carries procedure only. If any instruction
  here seems to exempt, soften, or pre-judge a class of findings, that
  reading is wrong — the code and the rules decide (background:
  [review-calibration.md](../../../internal/records/review-calibration.md),
  "Skill-bias origin").
- Redundancy passes (second release snapshot, different model family)
  stay independent of this skill — that independence is the
  **commissioning operator's setup** (different model, external
  /review), never the loading agent's self-assessment: no session can
  know it is "the external one", and nothing technically stops a
  session from reading this file anyway. The visible control is
  provenance: a pass that ran WITH this skill records it in its
  `Skills:` line — the calibration section then names the collapsed
  axis honestly (shared strictness is not shared bias, but shared
  context must be disclosed).

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
  provenance class; full passes cover the whole tree.
- **No untracked-file catch** — snapshots run on committed, clean
  trees only; net-new files are inside the diff by construction.
- **No unconditional whole-file reads** — the budget and coverage-map
  discipline governs (micro/wave: greps + targeted reads).
- **No web-search guidance** — reviewer subagent tool sets vary.

## 1. Collect the commission

Never self-advance into a pass — the wave review fires on the
maintainer's go, and round completion is reported, never advanced
(review-concept, "The loop and the stop rule"). Confirm from the
session's commission, then gather:

| Input | Source |
|---|---|
| Case key (`pr-ABCDE`) and case folder | birth-PR number; folder under `internal/reviews/A/B/C/D/` |
| Chain state | latest `review-<letter>.md` + `resolution.md` in the case folder |
| Scope keyword | **micro** (≤ ~50-line fix diff) · **wave** (round's diff) · **full** (whole tree, release) |
| Base + diff | version/SHA and `git diff <range>` for wave scope; tree SHA for full |
| Tree state | clean and committed — snapshot before any fix ("The loop and the stop rule") |

## 2. Scope parameters

| | micro | wave | full / release |
|---|---|---|---|
| Material | the fix diff only | the round's whole diff | every shipped file |
| Budget per agent | ~5 min | ~8 min | ~15 min + coverage map |
| Axes | 1–2 | 2–3 (sweep / security / quality) | 3+, second agent per axis when release-critical |
| Reads | batched greps, no whole-file reads | greps + targeted reads | every file grep-anchored; deferrals recorded |
| Second snapshot | no | no | release: yes, different model family, without this skill |

Agents cannot watch clocks — they spend sections; the coverage map is
the real budget, the minutes only its ceiling ("Parallel reviewer
agents").

## 3. Pre-flight

1. Read the chain: prior snapshot's findings, retracted/ghost section,
   and the resolution rows — open findings and prior CLEAN verdicts are
   leads after a rotation deviation ("Session rotation").
2. Measure the material: `git diff --stat` (wave) or the shipped-file
   inventory (full). Verify the tree is clean
   (`git status --porcelain` empty) — never snapshot a dirty tree.
3. Pick axes and targets: which files each axis greps first; name
   known blind-spot surfaces in the axis prompt — a gate or claim about
   path operands is tested against `x/`, `x//`, `x/.` forms
   ("Parallel reviewer agents").
4. Checkpoint locations: one side file per reviewer agent under
   session scratch OUTSIDE the reviewed tree (e.g.
   `/tmp/opencode/<case>-<letter>/checkpoints/`) — never inside the
   repo: the tree must stay clean and is a shared read substrate, and
   case folders take no stray files (reviews lint rule 6). The
   snapshot's run provenance absorbs the checkpoint lines.

## 4. Fan-out

- Reviewer subagents run the provider's fast tier; the main session
  (this one) runs the strong tier and owns the verification duty
  ("Parallel reviewer agents").
- Build each reviewer prompt from
  [axis-prompt.md](axis-prompt.md) — role, axis, material, budget,
  checkpoint discipline, output contract.
- **Cap: 5 concurrent reviewer agents on any tier** — staged launch,
  backfill one seat as each returns. A USER-named cap for the case
  overrides upward; never raise the cap yourself ("Parallel reviewer
  agents" + AGENTS.md, "Subagent fan-out").
- Record ONE host timestamp at fan-out start (and later at end);
  reviewers stamp with their own sandbox clock ("Parallel reviewer
  agents").
- **The tree is a shared read substrate while reviewers run**: no
  sabotage spot-checks, no fixes, no writes into the reviewed tree.
  Sabotage windows are before launch, after all reviewers returned, or
  in a scratch worktree ("Parallel reviewer agents").

## 5. Screening and verification

- Every reviewer finding is re-verified against the code by this
  session before it enters the snapshot; unverifiable claims are
  dropped or marked `unverified` ("Verification duty").
- Retracted findings stay visible in the snapshot's
  "Retracted/ghost findings" section.
- If a mutation window overlapped readers anyway (disclose it in run
  provenance), screen BOTH directions: findings shaped like a sabotage
  artifact, and clean verdicts on mutated constructs citing no
  clean-tree anchor.
- Final chat answer: status list only (counters + top-3), never the
  file content.

## 6. Write and commit the snapshot

1. Copy the header block from the chain's latest snapshot (the freshest
   template is always the previous file) and update: Snapshot letter
   (next in sequence), Scope, Base, Diff, Date, Reviewer, and a
   `Skills: opk-review-pass` provenance line (environment record; the
   header contract: internal/reviews/README.md, "Snapshot format").
   A `micro` pass records `Scope: wave` and names the micro shape in
   the Subject — there is no `micro` header value (README, "Snapshot
   format").
2. Body: the reviewers' findings **verbatim**, plus house sections per
   the contract (findings index, retracted/ghosts, run provenance with
   the host timestamps and per-agent windows, calibration when a second
   snapshot ran).
3. Commit the snapshot BEFORE any fix starts — the hard seam ("The
   loop and the stop rule").
4. Update `resolution.md` only as fixes land later; nothing here fixes
   anything.

## 7. Report the round

Report round completion: findings count by severity, dispositions owed,
and any reviews owed-but-not-run, named explicitly. The maintainer
decides the next step; the loop's stop rule is checked against the
round's dispositions by the NEXT round or the maintainer — this session
never declares the loop closed in its own commits ("The loop and the
stop rule").
