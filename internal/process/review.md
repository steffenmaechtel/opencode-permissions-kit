# review.md — the maintainer's side of the review process

Your steering part only. The full process — loop mechanics, tiering,
curation and verification, stop-rule details, reviewer agents — lives
in [agent/review-concept.md](../../agent/review-concept.md); the
archived corpus of the repo-file era lives at tag `review-corpus`
([internal/reviews/README.md](../reviews/README.md) is the pointer).

## Commissioning a case (the PR-native loop)

- **The commission is the scope authority.** Paste the commission
  file as the FIRST prompt into a fresh session (Session MAIN); it
  names the case (issue), the variant, the deliverables/inventory
  (the scope brake's fixed inventory), the loop mechanics (cap,
  tiers, reviewers), and the metrics owed. Keep the file unchanged —
  it is the commission record.
- **Variants:** maintainer-gated variants fire each round on your go;
  **variant c** runs autonomous dispositions. In BOTH variants the
  agent pushes and creates the PR itself (AGENTS.md Rules (the never-commit-on-master rule): approvals
  only count when the agent is the author and last pusher — the
  opencode permission prompt you approve is the runtime gate; hand the
  initial push to the maintainer only on a `.github/workflows/`
  permission denial, and re-push follow-ups yourself). Loop closure
  (the merge) stays with you in every variant.
- **The birth-PR is the case key.** In variant c the agent opens it
  on your prompt approval (body: `Closes #<issue>` references); the
  PR timeline is the case's whole review record — round comments,
  pushes, CI runs. No case folders are created, nothing is committed
  under `internal/reviews/`.

## Commissioning the review tracks

Track selection is mechanical (the blast-radius axis,
[agent/review-concept.md](../../agent/review-concept.md), "Round
typing and tiering" and "Review tracks"): any shipped file
(`files/**`) in the PR's diff means track high; a non-shipped-only
diff means track med. The implementing session states the track in
the PR body (`Track: high|med (paths)`); the review session
re-derives it from the diff before staging round a.

**Who runs the loop (the commission's scope decides):** a
**single-case commission** keeps the single-session shape — the
implementing session runs the loop itself, as before (the review
pass stays a subagent in every shape). A **batch commission**
splits the roles: the implementing session ONLY implements and
opens one birth-PR per case, and every PR of the batch is reviewed
by ONE fresh review session (the new-session entry) — commission
per PR as its PR opens, rolling, **max 2 parallel review
sessions** (their subagents stay within the 5-seat cap). In a batch
the implementing session may hand axis-prompt hints from its hot
build context into the PR body or the review commission — that is
where its review role ends.

- **Track high (shipped code in the diff)** — full weight,
  unchanged: the tier ladder, curation threshold and verify sizing
  per the review concept; who runs the loop per the paragraph
  above (single case: the implementing session; batch: the fresh
  review session).
- **Track med (non-shipped-only diff)** — variant c is the DEFAULT:
  autonomous dispositions, you approve PR create and merge only.
  1–2 fast-tier axes, main curation and verify sizing per the
  review concept; the MED disposition policy applies (LOW/INFO code
  findings deliberately-not-done, recorded); who runs the loop per
  the paragraph above.
- **New-session entry (the batch shape)** — commission a FRESH
  session (git worktree) per PR: it did not implement the code and
  runs the whole loop (curation, verification, dispositions, fixes,
  comments, closing summary). **One review session per PR — never
  two**: reviews land in fix work almost always, and the first
  case's fix waves would load and anchor the second, spending the
  freshness the entry exists to buy; session startup amortizes
  through parallelism, not stacked PRs. The review pass itself
  stays subagent-only in this entry too — the staffing rules of the
  PR's track decide 1 vs 2 axes.

### Batch triage (at commissioning)

- Only **full-scope non-shipped issues** go to a Track-MED batch.
- An issue with a **tiny shipped remainder** goes to track high as a
  WHOLE — splitting off the non-shipped part costs more review
  overhead per PR than the full ladder costs on a small diff (the
  #300 lesson).
- An issue with a **dominant non-shipped** part and a real shipped
  part is split EXPLICITLY at commissioning (the #322 pattern): name
  both cases, their tracks and their inventories in the commission.

## Prompt approvals (the ask-gates) and the merge gate

- The opencode config gates the authority operations — `git push`,
  `gh pr create`, `make release`, `gh api` — each fires a prompt to
  you. Approving a per-round push is also your CI checkpoint: CI runs
  on every push, so a red check surfaces at the next gate. Approving
  the prompt lets the AGENT run the command — do not push into the PR
  yourself: a GitHub approval only counts from someone who is neither
  the PR author nor its last pusher, and your push would invalidate
  your own approval (AGENTS.md Rules (the never-commit-on-master rule); the one exception is a
  `.github/workflows/` permission denial, where you run the initial
  push and the agent re-pushes follow-ups).
- **Required approvals = 1 on master** is the hard merge gate: the
  machine account cannot approve its own PRs, so only your approval
  unlocks a merge. Bot-authored PRs are safe by construction.

## Closure = merge

- The loop's closing summary only PROPOSES closure
  (`"state":"closing-proposed"` in its marker, stop-rule check cited,
  full disposition ledger visible). **Your final review + merge is
  the closure confirmation** — merging also closes the issue
  references in the PR body.
- The release gate reads the markers: no release while an unmerged PR
  carries an unresolved `opk-review` marker (see
  [agent/review-concept.md](../../agent/review-concept.md), "Release
  gate").

## Workflow-scope policy (CI-touching branches)

The machine token deliberately lacks the `workflow` scope: pushes
touching `.github/workflows/` fail and are **maintainer turns by
design** (first exercised in Case A, PR #293). The scope is never
granted; a CI-touching case simply has one more maintainer turn. The
gate firing is the design working, not a bug — do not "fix" it by
widening the token.

## Your non-transferable roles in autonomous cases

GO-less mode does not remove you: the two roles the loop cannot run
itself are **pattern-level catches** (defect classes no automated
gate sees — the Pilot 3 glue catch) and **scope authority** (steering
and freezing scope mid-case; the Pilot 3 scope freeze). Steering
lands in the case's next round comment as a standing disclosure.

## Full reviews — triggers, findings, aftermath

Full reviews (security, bugs, quality, docs, CI) are **trigger-based**,
not on a calendar — the trigger bullet above is the gate (moved here
from CONTRIBUTING, issue #236):

- **Trigger a full review** when a version bump is planned (before
  the release), ~500+ changed lines or 10+ merged PRs have
  accumulated on `master` since the last review, or a high
  blast-radius area changed (`sudoers.template`, the wrapper, backend
  provisioning, the security model, `set -e`/pipefail semantics,
  traps).
- Findings from a review become issues labeled `review` (actionable
  soon) or `tech-debt` (deliberately deferred, with a reason). A
  review starts by working the backlog, not by re-inventing itself.

After each review, try to shrink the next one: every finding that
could be turned into a lint rule, unit test, or consistency guard
should be — the remaining manual surface is what the checklist
cannot automate.

Scope and cadence follow the
[review concept](../../agent/review-concept.md): full reviews are
this trigger-based gate; the fixes themselves get a **wave review**
(diff scope) as rounds of their case's loop — mandatory when a wave
changes the semantics of root-running scripts — and the review → fix
→ review loop stops only when a round's dispositions touch no
review-relevant code: severity prioritizes, but any code-touching
round — LOW fixes included — owes its wave review before the loop
closes.

## External review machines (bias-reduced checkout)

The second, independent pass of a release review must come from a
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
   embedding under the release report's header (run provenance names
   the sparse shape), per-finding verification with verification
   marks, and the calibration section naming what each side missed
   ("Parallel reviewer agents" in
   [agent/review-concept.md](../../agent/review-concept.md)).

The reviewed tree is "HEAD minus house memory" — name the sparse shape
in the report's run provenance. The unit suite runs partially red on
that machine BY DESIGN: the guards over `agent/`, `.agents/` and
`internal/` correctly fail when their tracked inputs are absent
(docs dangling links, stale line-length baselines, reviews-meta
aggregate, rules-meta index/revisit, skills lint — the exact count
tracks the suite inventory; re-measure when setting up the machine).
Do not weaken the guards for this — the suite is a full-tree
instrument; that machine reviews, the house side runs it. What stays
visible (AGENTS.md, `docs/`, `tests/`) is deliberate — the reviewer
should understand the product without inheriting the house's
conclusions. The full trade-off analysis (including the rejected
alternatives) lives in
[internal/records/review-independence.md](../records/review-independence.md).
