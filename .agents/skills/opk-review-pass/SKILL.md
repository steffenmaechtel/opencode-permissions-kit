---
name: opk-review-pass
description: Execute a review round (wave, micro, med, new-session, full/release) — load when a round's review fires or the maintainer commissions one. Covers track/tier classification, fan-out, curation (x) + verification (V3), round comments (format v2); rules: agent/review-concept.md. Redundancy passes stay independent by operator setup; one that loads this skill anyway discloses it in its Skills: line.
---

# opk-review-pass — executing a review round

This skill is the **execution choreography** for a review round. It is
not the rules and never a source of finding judgments:

- When a review is owed, which tier applies, when the loop stops, how
  freshness and verification work —
  [agent/review-concept.md](../../../agent/review-concept.md)
  (the authoritative rules; section links below point there).
- The 0.0.42e lesson: a review skill once exempted a finding class and
  buried a HIGH. This skill carries procedure only. If any instruction
  here seems to exempt, soften, or pre-judge a class of findings, that
  reading is wrong — the code and the rules decide (background:
  [review-calibration.md](../../../internal/records/review-calibration.md),
  "Skill-bias origin").
- Redundancy passes (second release pass, different model family) stay
  independent of this skill — that independence is the
  **commissioning operator's setup** (different model, external
  /review), never the loading agent's self-assessment. The visible
  control is provenance: a pass that ran WITH this skill records it in
  its `Skills:` line.

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
- **No untracked-file catch** — rounds run on committed, clean trees
  only; net-new files are inside the diff by construction.
- **No unconditional whole-file reads** — the tier budgets and
  coverage-map discipline governs (micro/wave: greps + targeted reads).
- **No web-search guidance** — reviewer subagent tool sets vary.

## 1. Collect the commission

Never self-advance into a pass — the cadence authority is the
commission, and round completion is reported, never advanced
(review-concept, "The loop and the stop rule"). Confirm from the
session's commission, then gather:

| Input | Source |
|---|---|
| Case key (`pr-ABCDE`) | birth-PR number — the PR timeline IS the case record |
| Chain state | session records (commission, scratch: posted.log, digests, verdicts) — never read the PR back |
| Track | PR body (`Track: high|med (paths)`) — re-derive from the diff paths: any `files/**` ⇒ high (section 2) |
| Tier | classified from the round's diff BEFORE staging (section 2) |
| Base + diff | base SHA and `git diff <range>` for wave scope; tree SHA for full |
| Tree state | clean and committed — the comment posts before any fix ("The PR-native loop") |

## 2. Classify the track and tier BEFORE staging

The track (blast radius) and the ladder live in the rules
(review-concept, "Round typing and tiering" and "Review tracks");
classify the track from the PR's diff paths, the tier from
`git diff --stat` plus content shape, and state both in the loop
status BEFORE the fan-out launches:

- **track high** — any shipped file (`files/**`) in the PR's diff,
  mixed diffs included: full ladder (the wave/micro rows below).
- **track med** — non-shipped only: 1–2 fast-tier axes (2 when the
  diff exceeds ~150 lines, touches CI-gating semantics in
  `.github/`/`Makefile`, or ships root-running `scripts/` code);
  curation and verify sizing per sections 5–6; the MED disposition
  policy applies (review-concept, "Review tracks").
- **new-session entry** — batch shape: the implementing session
  only implements; a fresh session (this one, if commissioned for
  review) runs the whole loop for ONE PR it did not implement;
  the review pass stays a subagent (≥ 1 axis; the staffing rules
  above decide the axes); marker mode `new-session-review`
  (review-concept, "Review tracks").
- **wave** — > ~50 lines or substantive logic: 2–3 fast-tier axes,
  V3 (1 verifier batch + main audit).
- **micro** — ≤ ~50 lines or message-only: exactly ONE fast-tier
  subagent (~5 min, greps + targeted reads); verification per the
  sizing gate (section 6): ≤ 3 findings all LOW/INFO → main audit
  alone; else exactly one verifier batch. Solo means one subagent,
  never main-solo.
- **none** — comments/docs only: no review round owed; closure via
  the diff-shape proof.

Severity escalates, never downgrades: fix waves re-review at 1-axis
micro; full wave staffing returns only when a NEW MED/HIGH finding
escalates scope.

## 3. Pre-flight

1. Read the chain state: prior round's open findings and retracted
   findings are leads; their dispositions table is the ledger the
   round starts from (review-concept, "Who records what").
2. Measure the material: `git diff --stat` (wave) or the shipped-file
   inventory (full). Verify the tree is clean
   (`git status --porcelain` empty) — never review a dirty tree.
3. Pick axes and targets: which files each axis greps first; name
   known blind-spot surfaces in the axis prompt — a gate or claim
   about path operands is tested against `x/`, `x//`, `x/.` forms
   (review-concept, "Parallel reviewer agents").
4. Scratch layout for the round: checkpoints, digest and verdict
   files under `/tmp/opencode/<case>/<letter>/` — OUTSIDE the
   reviewed tree (the tree must stay clean and is a shared read
   substrate). The round comment's run provenance absorbs these files.

## 4. Fan-out

- The abstract rule: reviewer subagents run the provider's fast tier;
  the main session (this one) runs the strong tier and owns the audit
  duty (review-concept, "Parallel reviewer agents"). The CONCRETE map
  for the house instance — commissions used to name it per case;
  commission-less sessions read it HERE (substitute your provider's
  strong/fast pair on a foreign setup):

  | Role | House model |
  |---|---|
  | Main session (owns the verification/audit duty) | GLM-5.3 — strong tier |
  | Reviewer subagents | GLM-5.3-Flash — fast tier |
  | Curator subagent (x, section 5) | GLM-5.3-Flash — fast tier |
  | Verifier subagents (V3, section 6) | GLM-5.3 — strong tier, fresh-context verification |

  Both directions are load-bearing: reviewers on the strong model
  burn the budget the fast tier exists to save, and verifiers on
  Flash break the calibrated verification policy (strong owns
  verification) just as quietly. The loop status (section 8) names
  the models that actually ran.
- Build each reviewer prompt from
  [axis-prompt.md](axis-prompt.md) — role, axis, material, budget,
  checkpoint discipline, output contract. The OUTPUT CONTRACT block
  goes verbatim into EVERY file-producing subagent prompt: reviewers,
  the curator, the verifiers.
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

## 5. Curation (x)

- The main session curates by default (review-concept, "Curation and
  verification"): merge and de-duplicate the checkpoint files into
  ONE digest — findings table (ID, severity, provenance, summary),
  merges named, drops with reasons, raw→curated counts. The main
  session reads the digest, never the raw files. Main curation is
  disclosed in the comment's provenance.
- Launch a fast-tier CURATOR subagent only when the round ran
  ≥ 3 reviewers AND produced > 10 raw findings — its input and
  deliverable are the same digest shape as above.

## 6. Verification (V3)

- Sizing is a HARD GATE (review-concept, "Curation and
  verification"): at ≤ 3 curated findings, all LOW/INFO, the main
  session verifies inline (no verifier subagents); above that, or at
  any MED/HIGH, exactly ONE fresh strong-tier verifier batch runs —
  skipping an owed batch needs maintainer disclosure, never a
  time-pressure call.
- The verifier deliverable: verdict files — every curated finding
  re-derived against the code, verdict CONFIRMED / REFUTED /
  UNVERIFIED with file:line evidence.
- The main session AUDITS the verdicts: re-derive every MED/HIGH
  itself, spot-check LOW/INFO (review-concept, "Curation and
  verification"). Refuted findings are retracted with the evidence
  named; retracted findings stay visible in the comment's
  retraction section.

## 7. Write and post the round comment

One comment per round, format v2 (the contract and template:
review-concept, "The round comment contract"):

1. Compose from the session's own records — digest, verdict files,
   the audit notes. Write-through: the loop never reads the PR back.
2. Structure: headline + ONE status line visible; outer details
   (metadata block, curator accounting, findings table with verifier
   verdicts, dispositions table from the PRIOR round, loop status);
   per-finding detail nested one level deeper; TWO levels maximum;
   blank line after every `<summary>` tag.
3. The `opk-review` marker is the LAST line, OUTSIDE the details,
   with the round's counters, `"state":"open"`, the permanent
   `"track":"high|med"` field and the round's mode
   (`variant-c-med`, `new-session-review`, …) alongside tier,
   reviewers, curator, verifiers.
4. Size guard: a comment that would exceed ~60k chars is split into
   parts (each with its own marker + `"part":N`) — content is never
   trimmed.
5. Post to the PR timeline; append the comment URL to the case
   scratch `posted.log`. The comment posts BEFORE any fix starts —
   the hard seam.
6. Nothing here fixes anything: dispositions for THIS round's
   findings land in the NEXT round's comment (or the closing
   summary).

## 8. Report the round

The loop status inside the comment is the round report (it is what
the maintainer reads):

- track + tier + classification evidence (diff shape),
  reviewers/curator/verifiers with models, output-contract
  violations (0 or disclosed), CI status of the last push;
- review-relevant code touched this round: yes/no (drives the stop
  rule — review-concept, "The loop and the stop rule");
- round typing: converging or BUILDING (predominantly fix-induced
  findings = building, said explicitly);
- cap distance from round 5 on; scope-brake activity (deferred work
  orders with inventory-gap notes, deliberately-not-done reasons,
  reverted out-of-scope work with preserved SHAs);
- provenance: host timestamps, per-agent windows, sabotage windows.

When the stop rule holds, the closing summary proposes closure
(`"state":"closing-proposed"`, stop-rule check cited, ledger and
check visible at top level) — the maintainer's merge confirms; this
skill never writes a `"closed"` state.
