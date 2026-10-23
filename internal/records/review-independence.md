# Review independence — keeping redundancy contexts separate

> Status: **CURRENT.** Design record for the redundancy side of the
> review process: where house skills live, why an external review
> machine gets a sparse checkout, and which alternatives were weighed
> and rejected on 2026-10-23 (skills pilot, issue #178). The rules it
> operationalizes live in
> [agent/review-concept.md](../../agent/review-concept.md)
> ("Parallel reviewer agents"); the incident history lives in
> [review-calibration.md](review-calibration.md) ("Skill-bias
> origin").

## The problem

House skills moved into the repo (`.agents/skills/`, issue #178).
opencode auto-discovers `.agents/` walking UP from the session cwd —
every session in a normal clone therefore SEES the house skills, and
the router (AGENTS.md) points at the house process docs on top. The
second-snapshot redundancy rule ("a different context — a different
model family and/or an operator setup that keeps the house skills
out") had silently eroded: on any ordinary checkout there is no
session context without the house's eyes anymore. Redundancy pays
through context difference — shared framing is a shared blind spot
even when the shared content is honest (the 0.0.42e incident buried a
HIGH through a skill-exemption; nothing malicious is required).

## Options weighed

- **Skills only in the global dir (`~/.agents`)** — rejected:
  invisible in clones, but unmaintainable: not versioned with the
  process it choreographs, no contributors, no other machines.
- **In-repo, description asks "external" agents not to load** —
  rejected: no session can self-identify as external — an
  unenforceable claim (maintainer catch, 2026-10-23); nothing stops a
  session from reading the file anyway.
- **Opt-in deploy** (source in-repo, `.agents/` gitignored, `make`
  copies into place) — rejected: deployed copies go stale after every
  pull (per-pull redeploy burden), machinery for a problem the
  reviewer machine can solve once, and it special-cases every guard
  that walks `.agents/`.
- **Delete `agent/` + `.agents/` on the reviewer machine, hide via
  gitignore** — rejected mechanically: gitignore and
  `.git/info/exclude` hide only UNTRACKED paths; deletions of tracked
  files always surface in `git status`, and the reviewed tree would
  dishonestly differ from its claimed base.
- **Reviewer-side sparse checkout** — CHOSEN: the repo stays the
  single home; the redundancy machine carves the house memory out of
  its working tree per clone — clean status, stable across pulls,
  honest provenance.

## The canonical setup

On the external review machine:

```bash
cd <repo clone>
git sparse-checkout set --no-cone '/*' '!/agent/' '!/.agents/' '!/internal/'
git status --short   # must be empty (clean)
```

What each exclusion removes:

- `agent/` — the routing targets: process rules, the learnings corpus
  ("what to look for"), conventions. AGENTS.md stays loaded but its
  links into `agent/` dangle — the pointer is visible, the corpus is
  not followable.
- `.agents/` — the house skills.
- `internal/` — the house self-knowledge: design records ("this is
  deliberate" — the strongest exemption-bias source there is), the
  review corpus with prior snapshots, the rule-metas.

What deliberately STAYS: AGENTS.md (comprehension — what the repo is,
testing rules), `docs/` (the product explains itself, including
[docs/concepts/security-model.md](../../docs/concepts/security-model.md)),
`tests/`, `files/`. The reviewer understands the product; it just does
not inherit the house's conclusions.

## Duties and honest caveats

- **Provenance:** the reviewed tree is "HEAD minus house memory" — the
  snapshot's run provenance names the sparse shape (e.g.
  `Base: v0.0.57 @ <sha> (sparse: no agent/.agents/internal)`).
- The `.git` object database still contains everything. The goal is
  de-routing, not information denial — enough for redundancy.
- The test suites on that machine run partially red (several guards
  expect `agent/`): it is a review substrate, not a dev environment.
- The remaining AGENTS.md surface (rules, testing, the learnings
  summary block) is accepted bias: comprehension outweighs sterility,
  and nothing in it exempts finding classes.
