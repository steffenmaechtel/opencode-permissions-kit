# AGENTS

Always-on rules for AI coding agents (and human contributors) working in
this repository — the router. Detail lives next to its audience:

- [agent/conventions.md](agent/conventions.md) — **BINDING** style guide
  for shipped code: interactive prompts, output style, shell security,
  unit-test sandbox, review-finding citations
- [agent/learnings.md](agent/learnings.md) — the L1–L7 checklist of
  recurring review error classes; run it before committing and again
  before declaring work done
- [agent/test-fidelity.md](agent/test-fidelity.md) — why bugs pass unit
  and e2e suites but still hit real terminals
- [agent/review-concept.md](agent/review-concept.md) — the review
  process: loop, stop rule, verification duty, reviewer mechanics
- [internal/reviews/README.md](internal/reviews/README.md) — review
  mechanics: case folders (birth-PR key), snapshots/resolutions,
  citation format
- [internal/process/](internal/process/) — maintainer process: review
  triggers & gates (review.md), release handling, CI-review planning
- [CONTRIBUTING.md](CONTRIBUTING.md) — workflow, PR checklist, e2e
  invocation patterns; user docs: [docs index](docs/README.md)

## What this repo is

The **opencode permissions kit** runs [opencode](https://opencode.ai) as its
own Linux user (`opencode`) against a **rootless container backend**
(docker-rootless or podman-rootless), so the agent is UID-separated from the
developer while ddev keeps working. File permissions are opencode's **soft**
permission layer (`opencode.jsonc`) — there are no OS-level ACL denies. There
is no plugin, no npm package: developers stream `files/install.sh` from the
`stable` release mirror (`curl ... | sudo env KIT_BRANCH=stable bash`; the
docs' default), the script self-fetches its siblings from the same ref, and
everything is deployed to `/usr/local/lib/opencode-permissions-kit/`. The
used ref is stamped as `KIT_CHANNEL` in `install.conf` and followed by
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
- `tests/` — shell unit tests (`unit/`), host pre-flight (`check-host.sh`),
  fixtures (`fixtures/`), Docker e2e suites (`e2e/`),
  UX demos (`ux/`)
- `docs/` — user documentation only (concepts / how-to / reference)
- `agent/` — agent working rules: conventions, learnings, test fidelity
- `internal/` — project memory: maintainer process (`process/`), design
  records (`records/`, archive under `records/_archive/` incl.
  evaluations), review evidence (`reviews/`, one case folder per
  birth-PR + generated INDEX), review meta-analysis runs
  (`reviews-meta/`)

## Rules

- **Never commit on `master`.** Work on `feature/<name>` branches, merged via
  pull request with green CI. The agent commits its finished work on the
  feature branch; push/pull and PRs are the maintainer's job. (RM-0097)
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
  Releases are cut with `make release VERSION=x.y.z`
  (`scripts/release.sh` — bump lands via PR first, the script tags and
  mirrors). (RM-0102)
- The security model is deliberately **soft-only** — never re-introduce
  OS-level deny ACLs. Background: `internal/records/ddev-working.md`,
  current model: `docs/concepts/security-model.md`. (RM-0103)
- **The kit never edits user-owned system config on its own — above all
  `/etc/wsl.conf`.** Install/update only *show* snippets or name opt-in
  commands the user runs themselves; `opk wsl-add-opencode-1-fix` is the
  only command that writes wsl.conf, and only on explicit invocation.
  `opk uninstall` asks (or `--yes`) before removing kit-owned wsl.conf
  content. Sanctioned exception (0.0.42e S3, issue #100): install/update
  strip the broken legacy 0.0.36 hyphen section if present — removal of
  kit-owned bytes only, restoring WSL parseability; nothing is ever
  written into the file outside `opk wsl-add-opencode-1-fix`. Rationale:
  `internal/records/wsl-conf-consent.md`. (RM-0104)
- **Run the L1–L7 checklist before committing and again before declaring
  the work done** — every new feature is a new instance of a known error
  class; `agent/learnings.md` is authoritative. (RM-0105)

## Testing

**At session start, run `sh tests/check-host.sh`.** It verifies the host has
every tool the suite needs (git, make, python3, shellcheck, setsid —
see the script for the current list) and prints
install commands for anything missing — ask the user to install rather than
working around a missing tool.

```bash
sh tests/check-host.sh   # host pre-flight (required tools + install hints)
sh tests/unit/test-*.sh # unit suite — always via sh, never rely on exec bits
make lint                # ShellCheck over the shipped scripts
make check-version       # VERSION + KIT_BRANCH consistency
make e2e                 # e2e (Docker needed)
make e2e-rootless        # docker-rootless e2e (skips without systemd-in-container)
```

**Unit suites are sandboxed by policy** (0.0.42e C1): they create/delete
only inside their own scratch and `/tmp`, `/var/tmp` — never in real
project or system trees (`/var/www/vhosts`, `/home`, `/srv`, `/etc`, …),
not even in teardown. Enforced by
`tests/unit/test-sandbox-policy.sh`; the rule lives in
`agent/conventions.md` ("Test sandbox (unit suites)").

**Sabotage-verify only against secured work.** Before mutating the tree
to prove a pin fails (mutation verification), commit the finished work or
`git stash` it first — an in-place `sed` sabotage followed by a
`git restore` on a dirty tree resets to HEAD and silently wipes every
uncommitted change (learned the hard way, 2026-10). And sabotage by
*deleting* the construct, not commenting it out: grep-count pins still
count commented lines, so a commented-out sabotage can pass green. After
the sabotage run, restore the good state from the commit/stash (or a copy
kept outside the tree) and re-run the suite to confirm green.

Both e2e suites are part of the definition of done for changes to
`install.sh`, `update.sh`, the wrapper, or backend provisioning.
**Run them in parallel when the preconditions hold — not sequentially**
(the suites are disjoint: per-suite containers, images and fixtures;
sequential runs cost the other suite's full runtime for no benefit).
Preconditions: a warm `tests/e2e/cache/` and no opencode version bump
since the last suite run — after a version bump run one suite alone
first, or two suites download the same version into the same cache path
concurrently. The invocation pattern (including the three-suite variant
with `e2e-ddev`) lives in [CONTRIBUTING.md](CONTRIBUTING.md).
Executable bits live in the **git index** (issue #123): commit anything
CI or the kit execute by path with `git update-index --chmod=+x <path>`
(invariant: 755 <=> executed by path, 644 <=> sourced lib / interpreter
call / data; enforced by `tests/unit/test-workflows.sh`). Workflows
carry no `chmod +x` lines — `actions/checkout` preserves tracked modes.

## Review learnings (recurring error classes)

[agent/learnings.md](agent/learnings.md) is authoritative. The corpus
finding (meta-analysis 0.0.38–0.0.46): every new feature is a new
instance of a known error class — the checklist applies to features,
not only fix waves (running it is a Rules bullet above). Memory aid:

- **Class sweep** — a class fix counts only after all same-shape sibling
  sites are swept; record the grep pattern and sites checked.
- **Fail-loud pins** — every new `|| true`, stderr redirect, or probe
  pipe gets a pin that executes the failure path, observed the way
  production observes it.
- **Claim audit** — every behavior claim the wave touches carries a pin
  or is deleted/weakened.
- **Pins discriminate** and sit before the suite's summary gate.
- **Root ops on agent-writable trees** — `[ -L ]` on every path
  component, re-check the operand immediately before acting, chmod
  before chown.
- **Fix waves are first-class code** — every fix wave gets its
  micro-wave review; fixes bring their own pins.

## Checkout ownership on kit-managed installs

When this repo is worked on through the kit itself (the agent runs as the
`opencode` user), the checkout is owned by the human user with group write
for `opencode`: file CONTENTS are editable, but `chmod`/`chown` are not —
the agent is not the owner (`git update-index --chmod=…` still works; it
only touches the index). When a mode change is needed:

1. Stage the authoritative change yourself:
   `git update-index --chmod=+x <path>` (or `--chmod=-x`) — the index is
   what commits and what CI checks out.
2. **Tell the USER right away** and hand over the exact matching `chmod`
   commands so the working tree aligns with the index (e.g.
   `chmod +x tests/unit/test-foo.sh`). Until aligned, `make test` can
   fail locally on files whose disk mode lags the index (fresh clones
   always match — `sh tests/unit/test-*.sh` sidesteps the disk mode
   entirely). Never silently leave worktree and index out of sync.
