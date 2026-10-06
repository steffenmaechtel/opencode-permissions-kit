# CI review — automated AI reviews in GitHub Actions

> **Status: planning (issue #122).** Nothing here is implemented. This
> record exists to settle the open questions before any workflow lands.
> It extends [review-concept.md](review-concept.md) — strategy, loop,
> model policy — with a CI automation layer. Where the two disagree,
> review-concept.md wins until this record is implemented and revised.

## What issue #122 asks, mapped to the review types

| Issue ask | Review type (review-concept.md) | Output |
|---|---|---|
| Small commit review on pull requests | **wave review** (diff scope) — the mandatory pre-PR review, automated and run from a different vantage than the authoring agent | one comment on the PR |
| Full project review on commits to master | **release review** (full scope) | an issue carrying the findings (issue #122's open question mark) |

The CI layer automates the *finding* half of the loop only. The
verification duty ("every reviewer-agent finding is re-verified before it
counts") and the fix loop stay with the maintainer — CI findings are
advisory drafts until a human verifies them.

## Reference: openchamber

Inspected at tag **v2.1.1** (read-only clone in the dev workspace,
`github/openchamber`). Relevant files:

- `.github/workflows/pr-review.yml` — the review automation
- `.opencode/agent/pr-review-bot.md` — the reviewer agent definition
- `.github/workflows/pr-intake.yml` — size triage that parks large PRs

### Mechanics worth adopting

| Element | What openchamber does | Transfer |
|---|---|---|
| Trigger | `pull_request_target` (opened/synchronize/reopened/ready) plus manual `/oc-review` comment with optional focus text | adopt; trigger *model* is an open question below |
| Bot identity | GitHub App (`actions/create-github-app-token`) so comments/labels carry a distinct bot identity | open question (O2) |
| Trust guard | PRs touching review policy / trust-boundary files (`AGENTS.md`, workflows, the agent prompt itself) are never AI-reviewed: label `review:human-required`, skip with explanation | adopt with a kit-specific guard list (O6) |
| Read-only agent | `edit: deny`, `bash` allowlist (`gh`, `git`, `rg`, `ls`, `cat` only), no subagents, never checks out the PR branch, never runs builds/tests/linters — PR content is data, not instructions | adopt verbatim; matches our conventions.md untrusted-input rules |
| Verdict contract | agent posts exactly one comment ending in a hidden marker `<!-- oc-review-meta {"head":"<sha>","verdict":"…"} -->`; the workflow (not the agent) verifies the comment landed, the marker parses, verdict + reviewed HEAD match, and maps it to a `review:*` label | adopt — the workflow-side verification step is what makes a rogue/failed agent run visible |
| HEAD pinning | review targets one resolved `headRefOid`; if HEAD moved during the run, the run fails rather than labeling a stale review | adopt |
| Cost control | 15 min throttle on push-triggered re-reviews (manual command always runs), 30 s debounce on `synchronize`, 30 min hard timeout, install retries with backoff | adopt; plus a diff-size cap (O7) |
| Draft handling | draft PRs clear `review:*` labels instead of reviewing | adopt if we use labels |
| Advisory only | the AI verdict never fails a check and must not be a required status | adopt as a fixed principle |

Their reviewer agent runs on `zai-coding-plan/glm-5.3-flash` via a
`ZHIPU_API_KEY` secret — the same model policy as our reviewer subagents
(review-concept.md), which makes the reference a good fit.

### What does not transfer as-is

- Their verdict taxonomy (`pass` / `needs-evidence` / `blocked` /
  `human-review-required`) encodes OpenChamber's evidence rules
  (screenshots, live-run statements). We have no equivalent contract;
  findings should use the snapshot severity vocabulary
  (HIGH/MED/LOW/INFO) and the verdict question reduces to "findings:
  yes/no".
- Their PR template/enforceable handoff sections do not exist here.
- Their `pr-intake` size parking is heavier than we need; a simple
  changed-lines cap with a skip comment covers it.

## Fixed principles (not open for debate)

1. **Advisory only.** The AI review never blocks a merge, is never a
   required check, and never fails the workflow on findings. Only
   automation *failures* (timeout, missing/malformed comment) may fail
   the run — visibly.
2. **Read-only, untrusted input.** The reviewer agent runs against the
   base checkout, never checks out or executes PR code, and treats PR
   title/body/comments/diff as data (conventions.md). Bash allowlist:
   `gh`, `git`, `rg`, `ls`, `cat`.
3. **Suites stay the standing review.** The CI review does not run
   unit/e2e suites (e2e needs Docker anyway); it reads code the way the
   manual wave review does. Test coverage questions remain with the
   existing workflows.
4. **Snapshots stay human-owned.** CI never commits to
   `docs/design/review/` and never writes resolutions. Full-scope CI
   output goes to an issue; promoting findings into the snapshot/resolution
   loop is the maintainer's call (review-concept.md, "Who records what").
5. **English only** (AGENTS.md) — comments, labels, agent definition.
6. **Soft on the repo, hardened in the workflow** — the agent's
   permissions are narrowed in its definition file, and the workflow
   independently verifies the output contract; neither trusts the other.

## Proposed shape (sketch, for the later PR)

### Job 1 — `pr-review` (wave review, diff scope)

1. Trigger per O1; resolve PR number, HEAD SHA, draft state.
2. Guard list check (O6): policy/trust-boundary files changed →
   `review:human-required` label + skip comment, done.
3. Size guard (O7): diff above cap → skip comment, done.
4. Throttle/debounce push-triggered re-reviews.
5. Install pinned opencode (O3), run
   `opencode run --agent pr-review-bot` with the model key secret and a
   `GH_TOKEN` scoped to comment+label. Prompt carries PR URL, number,
   HEAD SHA, base/head refs.
6. Verify output contract (comment present, marker parses, HEAD matches),
   set label, fail loudly on contract violations.

Agent definition committed in-repo (`.opencode/agent/pr-review-bot.md`,
English, conventions.md prompt style) — see O8.

### Job 2 — `master-review` (full scope)

Same skeleton, but: full-tree scope, coverage-map discipline from
review-concept.md, findings filed as an issue (O4), cadence per O4 —
*not* every master push.

## Open questions

| # | Question | Current leaning |
|---|---|---|
| O1 | **Trigger model for the PR review.** (a) automatic like openchamber, (b) `/review` comment command, (c) `workflow_dispatch` with PR number, (d) GitHub Environment with required reviewer — the literal "maintainer approves, then it runs" gate from issue #122 | start with (b): cheapest, re-review with focus text included, no extra infra; validate (d) in a spike if the approval UX matters. Restrict the command to write-access actors (openchamber lets any commenter trigger — a cost vector we need not copy) |
| O2 | **Identity/token.** Own GitHub App (distinct bot identity, openchamber model) vs `GITHUB_TOKEN` (`github-actions[bot]`) | `GITHUB_TOKEN` first — solo-maintainer repo, one App fewer to register and rotate; reconsider an App only if the identity needs to stand apart (labels, notifications) |
| O3 | **Model + opencode pin in CI.** Which provider key/secret, which model, and whether the opencode binary is pinned (like e2e pins) or floating latest | GLM-5.3-Flash via `ZHIPU_API_KEY` (house policy); pin the opencode version and bump it deliberately — reproducibility over novelty |
| O4 | **Master full review: cadence and artifact.** Every push (issue #122's literal wording) vs release-triggered (VERSION file changed) vs weekly drift review vs dispatch-only; issue vs PR comment vs auto-snapshot | release-triggered (VERSION change) + manual dispatch; findings as a labeled issue; every-push full reviews would burn cost re-litigating accepted residuals (review-concept convergence table) |
| O5 | **Verification duty in CI.** Post findings marked AI-unverified and stop, or add a second verifying agent pass in the same run | mark unverified, stop — verification is the maintainer's (or the dev agent's, in-PR); a second pass doubles cost for judgment a human still has to own |
| O6 | **Guard list.** Which files make a PR `review:human-required`: `.github/workflows/`, `AGENTS.md`, `CONTRIBUTING.md`, `.opencode/agent/pr-review-bot.md`, `docs/design/review-concept.md`, `scripts/release.sh` — what else? | the list above as the starting set; the workflow file and agent definition must be on it (self-reference) |
| O7 | **Cost/size caps.** Throttle window, hard timeout, changed-lines cap before skipping (review-concept: ~2.5k diff lines is one pass's digest limit) | 15 min / 30 min / ~2.5k lines, oriented on openchamber + our own wave-review data; tune from the first runs |
| O8 | **Agent definition home.** Committed in-repo (needed: CI checks out only the repo; the current reviewer agents live in the maintainer's user config and are German) | `.opencode/agent/pr-review-bot.md` in-repo, English, not shipped in `KIT_FILES`; decide whether the manual review agents move in-repo too (consistency) or stay personal |
| O9 | **Labels.** openchamber's six `review:*` labels vs a minimal set | minimal: `review:pending`, `review:findings`, `review:clean`, `review:human-required`, `review:automation-failed` |
| O10 | **Workflow-test wiring.** `tests/unit/test-workflows.sh` guards a fixed workflow list; a new workflow is invisible to it until added | extend the guard list in the same PR; consider a guard that the review workflow itself keeps its allowlist-only agent permissions (drift here is a security regression, not a style issue) |

## Non-goals

- No AI verdict as a merge gate, required check, or auto-review dismissal.
- No auto-fix commits, no auto-labeling beyond `review:*`, no issue
  auto-close.
- No replacement of the maintainer's snapshot/resolution loop.
- No change to shipped kit code — this is repo-internal CI only; nothing
  lands in `files/` or the deploy manifest.
