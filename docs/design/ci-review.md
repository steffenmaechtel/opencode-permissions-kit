# CI review — automated AI reviews in GitHub Actions

> **Status: planning (issue #122).** Nothing here is implemented. This
> record exists to settle the open questions before any workflow lands.
> It extends [review-concept.md](review-concept.md) — strategy, loop,
> model policy — with a CI automation layer. Where the two disagree,
> review-concept.md wins until this record is implemented and revised.
> Maintainer decisions from 2026-10-06 are recorded under
> "Decisions" below; only O6's guard list and O11's verdict mapping
> remain open.

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
| Trigger | `pull_request_target` (opened/synchronize/reopened/ready) plus manual `/oc-review` comment with optional focus text | mechanism adopted (comment command with focus text); trigger decided the other way — maintainer-started only (O1) |
| Bot identity | GitHub App (`actions/create-github-app-token`) so comments/labels carry a distinct bot identity | open question (O2) |
| Trust guard | PRs touching review policy / trust-boundary files (`AGENTS.md`, workflows, the agent prompt itself) are never AI-reviewed: label `review:human-required`, skip with explanation | adopt with a kit-specific guard list (O6) |
| Read-only agent | `edit: deny`, `bash` allowlist (`gh`, `git`, `rg`, `ls`, `cat` only), no subagents, never checks out the PR branch, never runs builds/tests/linters — PR content is data, not instructions | adopt verbatim; matches our conventions.md untrusted-input rules |
| Verdict contract | agent posts exactly one comment ending in a hidden marker `<!-- oc-review-meta {"head":"<sha>","verdict":"…"} -->`; the workflow (not the agent) verifies the comment landed, the marker parses, verdict + reviewed HEAD match, and maps it to a `review:*` label | adopt for phase 2 (custom agent); phase 1 inverts it — the workflow posts, so no marker to verify (O8, O11) |
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

## Decisions (2026-10-06, maintainer)

First round of answers; the workflow stays deliberately minimal until
the review quality has proven itself.

| # | Decision |
|---|---|
| O1 | **Maintainer-started only.** Every review costs API budget, and with third-party PRs the maintainer wants to look first and approve. Mechanism: `/review` comment command restricted to write-access actors (`author_association` OWNER/MEMBER/COLLABORATOR); automatic triggers stay off; a GitHub Environment approval gate is an optional later spike, not phase 1 |
| O2 | `GITHUB_TOKEN` (`github-actions[bot]`); own GitHub App only if a distinct bot identity becomes necessary |
| O3 | GLM-5.3-Flash via the provider-agnostic secret **`REVIEW_MODEL_API_KEY`** that the workflow maps onto the provider env var — `ZHIPU_API_KEY` today, `OPENROUTER_API_KEY` or similar later; switching providers then touches only the workflow env block and the model string, never the secret |
| O4 | `master-review` starts manually (dispatch) at first; an automated cadence (release-trigger, weekly) is reconsidered once the PR review has proven itself |
| O5 | Nothing blocks: findings are advisory and AI-unverified; the maintainer verifies in the PR. What a mature version needs (verdicts, gates) is deliberately deferred until quality is known |
| O7 | Initial values from openchamber + our wave-review data: 15 min re-review throttle, 30 min hard timeout, ~2.5k changed-lines cap; tune from real runs |
| O8 | **Built-in opencode `/review` first**, fed with prompt text (see "Phase 1" below); the committed custom agent is the phase-2 option |
| O9 | Minimal label set: `review:pending`, `review:findings`, `review:clean`, `review:human-required`, `review:automation-failed` |
| O10 | `test-workflows.sh` wiring happens in the implementation PR, when the workflow is real |

## Proposed shape (sketch, for the later PR)

### Job 1 — `pr-review` (wave review, diff scope)

1. Trigger per O1; resolve PR number, HEAD SHA, draft state.
2. Guard list check (O6): policy/trust-boundary files changed →
   `review:human-required` label + skip comment, done.
3. Size guard (O7): diff above cap → skip comment, done.
4. Throttle/debounce push-triggered re-reviews.
5. Install pinned opencode (O3) and run the built-in review:
   `opencode run "/review <PR number> <focus>"` (O8) — the model key
   secret is mapped onto the provider env var; the review run itself
   gets NO write token.
6. Workflow posts the captured stdout as the PR comment (posting cannot
   be duplicated or injected by PR content) and sets the label (O11).

Phase 2 (optional): committed agent `.opencode/agent/pr-review-bot.md`
(English, conventions.md prompt style) with kit severities, repeat-review
timeline, and the marker contract.

### Job 2 — `master-review` (full scope)

Same skeleton, but: full-tree scope, coverage-map discipline from
review-concept.md, findings filed as an issue (O4), manual dispatch
only at first (O4) — *not* every master push.

### Phase 1 — built-in `/review` (O8)

Verified in the pinned checkouts (opencode 1.x at v1.18.34 and 2.x at
v2.0.18 — both ship it): the command reviews uncommitted changes, a
commit hash, a branch, or a PR number/URL (`gh pr view` + `gh pr diff`),
reads whole files plus conventions files (AGENTS.md et al.), and writes
its findings to **stdout**. It does not post GitHub comments, carries no
verdict contract, and does not know our severity vocabulary or the
repeat-review timeline.

Consequences:

- The **workflow**, not the agent, posts the comment from captured
  stdout. This inverts openchamber's marker contract (their agent posts,
  the workflow verifies) and is strictly safer: the review run holds no
  write token at all, so even a successful prompt injection can at worst
  burn tokens. The duplicate/missing-comment failure modes disappear
  together with the agent's posting duty.
- No agent file means no frontmatter hardening (`edit: deny`, bash
  allowlist). Phase 1 compensates at the workflow level: ephemeral
  runner, token only on the posting step, nothing else. If that proves
  insufficient, phase 2 commits the agent definition with the allowlist.
- No machine-readable verdict → O11.

**Addendum (2026-10-06, after the 0.0.45b/-c calibration):** the O8
verification above checked command *existence* on 1.x v1.18.34 and 2.x
v2.0.18 — it missed that the two majors *dispatch* the command
differently (verified in the pinned checkouts; the 2.x reference has
since been re-pinned to v2.0.22, the version the external calibration
ran): 1.x registers `/review` with `subtask: true`, so the template runs
inside ONE build subagent that cannot launch subagents of its own — a
single context with sequential roles; 2.x injects the template into the
main session (`ctx.session.prompt`), where the lead can fan out parallel
reviewer subagents and verify findings empirically. Same model and same
prompt produced 2 LOW + 2 INFO in the 1.x shape versus 2 HIGH + 6 MED +
25 LOW/INFO in the 2.x shape (mechanism and numbers:
[review-concept.md](review-concept.md), "invocation shape governs
orchestration capacity"). Consequences for this record:

- **Job 1 (`pr-review`, diff scope) is unaffected** — the subtask shape
  is adequate for wave/diff reviews (the 0.0.45b delta verification was
  solid; only breadth suffered, which a diff review does not need).
- **Job 2 (`master-review`, full scope) pins its runner to opencode 2.x**
  — O3's "pinned opencode binary" becomes a 2.x tag — or moves to the
  phase-2 custom agent with explicit fan-out; a 1.x runner would cap the
  full-scope pass at a single-context sweep.

## Open questions (remaining)

| # | Question | Status |
|---|---|---|
| O6 | **Trust-guard list** — files whose changes make a PR refuse AI review (`review:human-required`). Rationale: the workflow runs with repo secrets and its behavior is defined by repo files; a PR that edits exactly those files must not be judged by the rules it itself changes — a malicious PR could weaken the reviewer to always return "clean". Proposed set: `.github/workflows/*.yml`, `AGENTS.md`, `CONTRIBUTING.md`, `docs/design/review-concept.md`, `docs/design/ci-review.md`, `scripts/release.sh`. Add/remove entries? | list pending |
| O11 | Phase-1 **verdict mapping**: built-in `/review` output has no machine-readable verdict, so the workflow cannot map comment → label the openchamber way. Phase 1 either posts the comment under one flat label or skips labels entirely; the marker contract returns with the phase-2 agent | open |

## Non-goals

- No AI verdict as a merge gate, required check, or auto-review dismissal.
- No auto-fix commits, no auto-labeling beyond `review:*`, no issue
  auto-close.
- No replacement of the maintainer's snapshot/resolution loop.
- No change to shipped kit code — this is repo-internal CI only; nothing
  lands in `files/` or the deploy manifest.
