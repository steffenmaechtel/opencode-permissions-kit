# review.md — the maintainer's side of the review process

Your steering part only. The full process — loop mechanics, stop-rule
details, verification duty, reviewer agents — lives in
[agent/review-concept.md](../../agent/review-concept.md); file mechanics
(snapshots, resolutions, cases) in
[internal/reviews/README.md](../reviews/README.md).

- **Open the birth-PR before the review runs** (draft is fine) and tell
  the reviewer its number — that number is the case key
  (`internal/reviews/A/B/C/D/pr-ABCDE/`). PR-first keeps parallel features safe.
- **Trigger a full review** when a version bump is planned (before the
  release), ~500+ changed lines or 10+ merged PRs have accumulated on
  `master` since the last review, or a high blast-radius area changed
  (`sudoers.template`, the wrapper, backend provisioning, the security
  model, `set -e`/pipefail semantics, traps).
- **Your go gates the wave review too:** the agent owes one after
  every fix wave, reports round completion (including owed-but-not-run
  reviews) and waits — fix waves and their wave reviews both start on
  your go, never self-advanced.
- **New session when?** Implement runs in one session; every review
  round runs in a NEW session, and that session also applies its fixes
  (report committed first, then the fixes — default since 2026-10-17,
  pr-00189; full rule in
  [agent/review-concept.md](../../agent/review-concept.md), "Session
  rotation"). Your part: start a fresh session per review round.
- **Pause point:** the committed snapshot is your visibility window.
  The fix wave starts on your go, not before.
- **Stop-rule call:** the loop closes when a round leaves
  review-relevant code untouched. When only LOW/INFO findings remain,
  closing the chain is your call — the agent proposes, you decide.
  Your confirmation is also the signal to record the closure: the
  agent sets `Status: closed …` in the resolution and regenerates the
  INDEX ([review README](../reviews/README.md), "Resolution format").
- **Release gate:** no release while a review chain is open.
- **External redundancy pass:** the second snapshot of a release review
  runs on a bias-reduced checkout — setup in
  [the section below](#external-review-machines-bias-reduced-checkout),
  background and rejected alternatives in
  [internal/records/review-independence.md](../records/review-independence.md).

## Full reviews — triggers, findings, aftermath

Full reviews (security, bugs, quality, docs, CI) are **trigger-based**,
not on a calendar — the trigger bullet above is the gate (moved here
from CONTRIBUTING, issue #236). Findings from a review become issues
labeled `review` (actionable soon) or `tech-debt` (deliberately
deferred, with a reason). A review starts by working the backlog, not
by re-inventing itself: method, snapshot and resolution mechanics, and
the snapshot-format rule (external verbatim embedding since 0.0.45d)
live in [internal/reviews/README.md](../reviews/README.md).

After each review, try to shrink the next one: every finding that could
be turned into a lint rule, unit test, or consistency guard should be —
the remaining manual surface is what the checklist cannot automate.

Scope and cadence follow the
[review concept](../../agent/review-concept.md): full reviews are this
trigger-based gate; the fixes themselves get a **wave review** (diff
scope) before their PR — mandatory when a wave changes the semantics of
root-running scripts — and the review → fix → review loop stops only
when a round's dispositions touch no production/test code: severity
prioritizes, but any code-touching round — LOW fixes included — owes
its wave review before the loop closes.

## External review machines (bias-reduced checkout)

The second, independent snapshot of a release review must come from a
genuinely different context — a different model family on a checkout
without the house's review memory. A normal clone carries that memory
(`agent/`, `.agents/`, `internal/`), so the external machine carves it
out with a sparse checkout; `git status` stays clean, no tracked-file
deletion, stable across pulls:

```bash
cd <repo clone>
git sparse-checkout set --no-cone '/*' '!/agent/' '!/.agents/' '!/internal/'
git status --short   # must be empty (clean)
```

How a pass runs in practice (maintainer recipe):

1. **Fresh second WSL installation** — no global skills, no opencode
   configuration: nothing of the house context exists on that machine
   by construction. Clone the repo and set up the sparse checkout as
   above.
2. **Commission the pass** with opencode's built-in `/review`, naming
   the environment, the scope and where to write:

   ```
   /review You are reviewing a sparse checkout at <tag or SHA>: the
   directories agent/, .agents/ and internal/ are deliberately
   excluded (bias-reduced setup) — links into them dangle by design,
   their absence is not a finding. Full project review of the shipped
   code and docs; do not run the test suite (the house side runs it
   on the full tree). Write the report and all findings to
   /tmp/opencode/review-<topic>/ (create the directory).
   ```

   Use a different model family than the house pass when available —
   the redundancy axis is "and/or", every added difference pays.
   `/tmp` is volatile: hand the result over before a reboot.
3. **Hand over to the house agent:** copy the result directory to the
   house machine and let the house session integrate it — verbatim
   embedding under the house snapshot header (run provenance names the
   sparse shape), per-finding verification with verification marks,
   and the calibration section naming what each side missed
   ("Parallel reviewer agents" in
   [agent/review-concept.md](../../agent/review-concept.md)).

The reviewed tree is "HEAD minus house memory" — name the sparse shape
in the snapshot's run provenance. The unit suite runs partially red on
that machine BY DESIGN: the guards over `agent/`, `.agents/` and
`internal/` correctly fail when their tracked inputs are absent
(measured 2026-10-24: docs dangling links, line-length stale
baselines, reviews lint/parity, reviews-meta-aggregate,
rules-meta/index/revisit, skills lint — 9 of 42 suites). Do not weaken
the guards for this — the suite is a full-tree instrument; that
machine reviews, the house side runs it. What stays visible (AGENTS.md,
`docs/`, `tests/`) is deliberate — the reviewer should understand the
product without inheriting the house's conclusions. The full trade-off
analysis (including the rejected alternatives) lives in
[internal/records/review-independence.md](../records/review-independence.md).
