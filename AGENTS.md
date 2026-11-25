# AGENTS

Always-on rules for AI coding agents (and human contributors) working in
this repository — the router. Every session pays this file up front, so
it carries invariants and trigger lines only; the detail lives next to
its audience and is loaded on demand:

- [agent/conventions.md](agent/conventions.md) — **BINDING** style guide
  for shipped code: interactive prompts, output style, shell security,
  review-finding citations
- [agent/gates.md](agent/gates.md) — **BINDING** wave mechanics: gate
  chains, sabotage cycles, checksum/index ordering, e2e duties,
  exec-bit and staging rules. Load it before running gates for a wave
  or sabotaging a pin
- [agent/learnings.md](agent/learnings.md) — the L1–L7 checklist of
  recurring review error classes; run it before committing and again
  before declaring work done
- [agent/test-fidelity.md](agent/test-fidelity.md) — why bugs pass unit
  and e2e suites but still hit real terminals
- [agent/review-concept.md](agent/review-concept.md) — the review
  process: loop, stop rule, verification duty, reviewer mechanics
- [agent/docs-loop.md](agent/docs-loop.md) — the docs-improvement
  loop: how reflection topics (filed by the `opk-improve-docs` skill
  in the feedback repo) reach quorum, are triaged, batched into waves
  and closed — the consumer side of that skill
- `.agents/skills/` — loadable procedures for on-demand workflows
  (opencode loads them by description match): the session EXECUTING a
  review pass loads the `opk-review-pass` skill first — rules stay in
  agent/, the skill carries the choreography only (issue #178)
- [internal/reviews/README.md](internal/reviews/README.md) — review
  corpus archive: tag `review-corpus` is the authoritative record
  (citation resolution); for live cases the birth-PR timeline IS the
  primary record
- [internal/process/](internal/process/) — maintainer process: review
  triggers & gates (review.md), release handling
- [CONTRIBUTING.md](CONTRIBUTING.md) — workflow, tests, e2e
  invocation patterns; user docs: [docs index](docs/README.md)

## Rules

- **Never commit on `master`.** Work on `feature/<name>` branches,
  merged via pull request with green CI. The agent commits its finished
  work on the feature branch, pushes it (without `-u` — the `.git`
  heal pins `.git/config` developer-owned, issue #651) and creates the
  PR — the agent is the PR author and makes the PR's last push: a
  GitHub approval only counts from someone who is neither. Exception: a
  push touching `.github/workflows/` can be rejected with permission
  denied — then the agent hands the maintainer the exact initial push
  command and re-pushes follow-ups itself. The PR body carries the
  `Track:` line at PR creation (review-concept.md, "Round typing and
  tiering"); merging and closing the review loop stay with the
  maintainer. Agent-side `git add`/`git switch`/`git merge` depend on
  the maintainer-side git heal hooks being on (`opk git-heal on`,
  issue #671); agent worktrees are the self-sufficient fallback.
  (RM-0097)
- **All shipped content is English** — scripts, docs, prompts, messages. (RM-0098)
- **Follow `agent/conventions.md`** for interactive prompts, output
  style, shell security (untrusted input), and other shipped-code
  conventions. (RM-0099)
- **Docs change with the code:** a PR that changes user-facing behavior
  updates the affected page under `docs/` in the same PR. One page = one
  topic type; see `docs/README.md` for the structure. (RM-0100)
- **Don't rename scripts** in `files/` — the Makefile, tests, docs, and the
  install/update deploy lists (`KIT_FILES`) reference them everywhere. (RM-0101)
- **Don't bump `VERSION`** unless the maintainer asks. Release tags (when
  set at all) are the bare version stamp **without a `v` prefix** —
  `0.0.17`, not `v0.0.17` (matches the `VERSION` file). Tags are also
  installable pins (`KIT_BRANCH=0.0.17`); the stable channel is the
  `stable` mirror branch, fast-forwarded to `master` on release.
  Releases are cut with `make release VERSION=x.y.z`. (RM-0102)
- The security model is deliberately **soft-only** — never re-introduce
  OS-level deny ACLs. Sanctioned exceptions, both ownership/sticky-bit
  only, no deny ACLs: the `.git` heal (issues #651/#671, PR #655) and
  its opt-in maintainer-side hooks; the #655-era project-root stickies
  were REMOVED again by #702/#703. Background:
  `internal/records/ddev-working.md`, current model:
  `docs/concepts/security-model.md`. (RM-0103)
- **The kit never edits user-owned system config on its own — above all
  `/etc/wsl.conf`.** Install/update only *show* snippets or name opt-in
  commands the user runs themselves; `opk wsl-add-opencode-1-fix` is the
  only command that writes wsl.conf, and only on explicit invocation.
  Sanctioned exception (issue #100): install/update strip the broken
  legacy 0.0.36 hyphen section — removal of kit-owned bytes only.
  Rationale: `internal/records/wsl-conf-consent.md`. (RM-0104)
- **Run the L1–L7 checklist before committing and again before declaring
  the work done** — every new feature is a new instance of a known error
  class; `agent/learnings.md` is authoritative. (RM-0105)
- **`AGENTS.md` does not grow past its byte cap** — 27 KiB, pinned by
  `tests/unit/test-docs-loop.sh`: every session pays this file up
  front, and the docs-loop pilot grew it by half in a week. New detail
  routes into an `agent/` on-demand file; overflow means compress or
  move. The cap is a first stop, not the target — the size question
  beyond it is tracked in #768. (RM-0218)

## What this repo is

The **opencode permissions kit** runs [opencode](https://opencode.ai) as its
own Linux user (`opencode`) against a **rootless container backend**
(docker-rootless or podman-rootless), so the agent is UID-separated from the
developer while ddev keeps working. File permissions are opencode's **soft**
permission layer (`opencode.jsonc`) — there are no OS-level ACL denies. There
is no plugin, no npm package: developers stream `files/install.sh` from the
`stable` release mirror, the script self-fetches its siblings from the same
ref, and everything is deployed to `/usr/local/lib/opencode-permissions-kit/`.
The used ref is stamped as `KIT_CHANNEL` in `install.conf` and followed by
`opk update`; `master` stays the development channel. Channels and the
`stable` mirror discipline: `internal/process/release-handling.md`.

## Issue reports from other installations

GitHub issue links the USER sends (issues in this repo) come from machines
running an INSTALLED kit: reported paths, logs, versions and failure modes
describe that machine, not this checkout. Reproduce and fix here; don't
expect the reported paths to exist locally.

## Layout

- `files/` — the streamed entry point (`install.sh`) and templates
- `files/opencode-permissions-kit-lib/` — the shipped library: management
  scripts (`config.sh`, `update.sh`, `status.sh`, `uninstall.sh` under
  `management/`), wrapper + helpers (`bin/`, `sh/`), `py/`, `tui/`
- `tests/` — shell unit tests (`unit/`), host pre-flight
  (`check-host.sh`), fixtures (`fixtures/`), Docker e2e suites (`e2e/`),
  UX demos (`ux/`)
- `docs/` — user documentation only (concepts / how-to / reference)
- `agent/` — agent working rules: conventions, gates, learnings, test
  fidelity, docs loop
- `.agents/skills/` — loadable agent procedures for on-demand
  workflows (see the router entry above)
- `internal/` — project memory: maintainer process (`process/`), design
  records (`records/`, archive under `records/_archive/` incl.
  evaluations), review evidence (`reviews/`, `reviews-meta/`)

## Testing

**At session start, run `sh tests/check-host.sh`.** It verifies the host has
every tool the suite needs and prints install commands for anything
missing — ask the user to install rather than working around a missing
tool.

```bash
sh tests/check-host.sh   # host pre-flight (required tools + install hints)
sh tests/unit/test-*.sh # unit suite — always via sh, never rely on exec bits
make lint                # ShellCheck + shfmt format gate over the kit shell
make check-version       # VERSION + KIT_BRANCH consistency
make e2e                 # e2e (Docker needed)
make e2e-rootless        # docker-rootless e2e (skips without systemd-in-container)
```

- **Gate runs are one unbroken `&&` chain ending in the commit** — no
  pipe or `;` on a gate command; redirect the WHOLE chain to log files.
  House form, chain scope, mid-run-edit and shared-list rules:
  [agent/gates.md](agent/gates.md) (load before running a wave's gates).
- **Sabotage-verify only against secured work** — before ANY sabotage
  restore, copy the file out of the tree (unconditional); sabotage by
  deleting, never commenting out; verify restores CONTENT-based. Full
  cycle: [agent/gates.md](agent/gates.md).
- **A diff touching `files/` owes `make sums` first in the chain**, and
  the repo-root `SHA256SUMS` in the same `git add`; post-rebase and
  release-PR shapes, rules-meta INDEX regen: [agent/gates.md](agent/gates.md).
- **Root-run code semantics/behavior changes owe both e2e suites in the
  wave itself** (parallel-run precondition included):
  [agent/gates.md](agent/gates.md).
- **Executable bits live in the git index** (`git update-index
  --chmod=+x`); stage-first chains and the co-edit staging rule:
  [agent/gates.md](agent/gates.md).
- **Line-length ratchet:** a red `test-line-length.sh` means a scoped line
  grew past 120 content columns. Shorten it; a deliberate exception goes
  through `sh tests/unit/test-line-length.sh --regen` with the baseline
  diff reviewed.
- **Unit suites are sandboxed by policy** (0.0.42e C1): they create/delete
  only inside their own scratch and `/tmp`, `/var/tmp` — never in real
  project or system trees, not even in teardown. Enforced by
  `tests/unit/test-sandbox-policy.sh`; the rule lives in
  `tests/AGENTS.md` ("Test sandbox (unit suites)" — auto-loads on
  reads under `tests/`).
- **gh auth:** where the context may lack gh auth (e2e containers, foreign
  hosts), probe `gh auth status` before gh-dependent steps; for read-only
  lookups, `curl` against api.github.com replaces failing gh calls.

## Subagent fan-out (concurrency cap)

**Default: at most 5 concurrent subagents.** Stage a larger fan-out in
waves of ≤ 5 and backfill as seats free up — an over-wide launch hits
provider rate limits (the 2026-10-22 meta run lost 1 of 8 seats that
way). Exceptions, in order of precedence:

1. The USER explicitly raises or lowers the limit for a task.
2. A dedicated process defines its own cap for its fan-out — that cap
   applies within the process's scope only (today the review process
   caps at 5 concurrent reviewers on any tier — the provider's burst
   limit is account-wide, [review-concept.md](agent/review-concept.md);
   no process defines a higher cap yet).

## Review learnings (recurring error classes)

[agent/learnings.md](agent/learnings.md) is authoritative. The corpus
finding (meta-analyses 0.0.38–0.0.46 and 0.0.47–0.0.55): every new feature
is a new instance of a known error class — the checklist applies to
features, not only fix waves (running it is a Rules bullet above). Memory
aid: **class sweep** (same-shape siblings before "implemented") ·
**fail-loud pins** (execute the failure path) · **claim audit** (every
behavior claim carries a pin or is deleted) · **pins discriminate** (and
sit before the summary gate) · **root ops on agent-writable trees**
(`[ -L ]` on every component, chmod before chown) · **fix waves are
first-class code** (own re-review, own pins).

## Checkout ownership on kit-managed installs

When this repo is worked on through the kit itself (the agent runs as the
`opencode` user), the checkout is owned by the human user with group write
for `opencode`: file CONTENTS are editable, but `chmod`/`chown` are not —
the agent is not the owner of the pre-existing tree
(`git update-index --chmod=…` still works; it only touches the index).
Files the agent itself creates are the exception: the agent IS their
owner and may `chmod` them (verified 2026-10-25). When a mode change is
needed:

1. Stage the authoritative change yourself:
   `git update-index --chmod=+x <path>` (or `--chmod=-x`) — the index is
   what commits and what CI checks out.
2. **Tell the USER right away** and hand over the exact matching `chmod`
   commands so the working tree aligns with the index (e.g.
   `chmod +x tests/unit/test-foo.sh`). Until aligned, `make test` can
   fail locally on files whose disk mode lags the index (fresh clones
   always match — `sh tests/unit/test-*.sh` sidesteps the disk mode
   entirely). Never silently leave worktree and index out of sync.
