---
name: opk-improve-docs
description: End-of-session docs-learning reflection: agent/review-concept.md.
---

# opk-improve-docs — the end-of-session docs-learning reflection

Any learnings we should capture better in our docs?
Did you stumble over anything?

If yes, every topic becomes its own issue in the feedback repo
`steffenmaechtel/opk-agent-feedback` (`gh … -R`), never in this
repository — the main tracker stays free of reflection volume. The
one carve-out is the skill-origin check's global-skill branch:
maintainer first, no issue. If the
reflection finds nothing real, say exactly that in chat and create
nothing.

## Search before filing

One topic, one issue — and a topic a later session can hit again has to
be findable twice. Before filing, search open AND closed issues with
2–3 keyword variants:

```sh
gh issue list -R steffenmaechtel/opk-agent-feedback --state all --search "<keywords>" --limit 10
```

- An OPEN match gets a confirming comment; nothing new is filed.
- A match CLOSED as not recurring gets the comment and is reopened
  (`gh issue reopen -R …`).
- A match that LANDED or was rejected is history, not a match: a rule
  that landed and still did not prevent the stumble is a different
  mechanism — file a new issue and link the old one (`Related: #N`).
- A near match (same area, other mechanism) is a new issue too, linking
  its neighbor.

## Skill-origin check

Before filing, consider whether the problem came from a SKILL the
session loaded (its instructions, its recipes, its blind spots):

- A skill in THIS repository (`.agents/skills/`) is repo content —
  file normally (`from-reflection` + priority label).
- A GLOBAL skill (`~/.agents/skills/` — opencode-db, the ddev/typo3
  procedures; their own versioned repository) is outside what a repo
  wave can fix: raise it with the maintainer in the reflection ask
  instead of filing — no feedback-repo issue first. The maintainer
  decides how it lands: fixed in the skills repo right away, or
  tracked where the maintainer chooses.
- A session that cannot tell whether a skill was involved files
  normally — the origin question is re-asked at triage
  (agent/docs-loop.md): a topic discovered there to live in a global
  skill is re-labeled `external-fix` and never rides a docs wave.

## Titles name the mechanism

Short and mechanism-named, without a `Docs:` prefix: the title is the
key the next session's search has to find. Name the gap, not the
incident ("Closing summary posted while CI still runs", not
"Learnings from pr-00760").

## Templates

Write the body to a file and post it with `--body-file` — narratives
carry backticks, `$` and quotes that an inline `--body` mangles. The
`Session:` lines hold a placeholder: put the value of
`printenv OPENCODE_SESSION_ID` in its place. A quoted heredoc leaves a
`$` variable literal, and a literal line matches no count.

Issue body:

```text
### Mechanism
<the documentation or rule gap, named so a session hitting it again finds it>

### Scenario
<what the session was doing>

### How it manifested
<step by step: what happened, in which order, the observable state
(session records, logs, opencode.db where useful) — a later session must
be able to re-derive the case without guessing (#620)>

Session: <the value of $OPENCODE_SESSION_ID>
Model: <the session's own model, e.g. GLM-5.4>
Ref: <PR, branch or round, if any>
```

Confirming comment:

```text
Confirmed — same mechanism.
<how it manifested here, 2–5 sentences>

Session: <the value of $OPENCODE_SESSION_ID>
Model: <the session's own model, e.g. GLM-5.4>
Ref: <PR, branch or round, if any>
```

The `Session:` line is the counting unit: promotion counts DISTINCT
session ids across an issue's body and comments, never its comment
count — a session confirming twice is one session.

The `Model:` line names the model of the session that files or
confirms, taken from the session's own context (the system prompt's
`# Your Model` block — `GLM-5.3`, `GLM-5.3-Flash`, `GLM-5.4`). A
session that cannot determine its own model asks the maintainer, who
can see it, instead of guessing. The line is informational — triage
reads it now and later metrics may; the count never does.

## Labels

- `from-reflection` + `prio:med` — the default.
- `from-reflection` + `prio:high` — rare but severe (data loss, security
  class): promoted without quorum, the maintainer decides directly; add
  a `Severity:` line saying why.
- `research-candidate` on its own (no `from-reflection`, no priority
  label) — not about this repository's docs or rules (general tool
  behavior, another project): file it with that label alone. It never
  counts toward a docs wave, and the trigger check does not list it.
  A topic from a LOADED skill is never research-candidate — the
  skill-origin check governs it (global skill: maintainer, no issue;
  repo skill: file normally).

## Before posting

No credentials, no environment dumps, no customer data; paths are
repo-relative unless the absolute form is the evidence. opencode.db and
the session logs are shared by every project of this user: quote your
own session's rows only, and only what the topic needs — no other
project's paths, no other session's content. The issue is
self-contained at creation — session scratch is gone tomorrow.

The consuming side — how topics reach quorum, are triaged and closed —
lives in agent/docs-loop.md.
