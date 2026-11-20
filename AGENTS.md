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
- [agent/docs-loop.md](agent/docs-loop.md) — the docs-improvement
  loop: how `Docs:` reflection issues (from the `opk-improve-docs`
  skill) are triaged, batched into waves and closed — the consumer
  side of that skill
- `.agents/skills/` — loadable procedures for on-demand workflows
  (opencode loads them by description match): the session EXECUTING a
  review pass loads the `opk-review-pass` skill first — rules stay in
  agent/, the skill carries the choreography only (issue #178)
- [internal/reviews/README.md](internal/reviews/README.md) — review
  corpus archive: tag `review-corpus` is the authoritative record
  (citation resolution); the archived corpus's birth-PR timelines carry
  readability mirrors (era-marked — for live cases the birth-PR timeline
  IS the primary record)
- [internal/process/](internal/process/) — maintainer process: review
  triggers & gates (review.md), release handling
- [CONTRIBUTING.md](CONTRIBUTING.md) — workflow, tests, e2e
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
- `agent/` — agent working rules: conventions, learnings, test
  fidelity, docs loop
- `.agents/skills/` — loadable agent procedures for on-demand
  workflows (see the router entry above)
- `internal/` — project memory: maintainer process (`process/`), design
  records (`records/`, archive under `records/_archive/` incl.
  evaluations), review evidence (`reviews/` — corpus archived at tag
  `review-corpus`; the archive pointer and legacy citation map remain
  in-tree), review meta-analysis runs
  (`reviews-meta/`)

## Rules

- **Never commit on `master`.** Work on `feature/<name>` branches, merged via
  pull request with green CI. The agent commits its finished work on the
  feature branch, pushes it and creates the PR — the agent is the PR author
  and makes the PR's last push: a GitHub approval only counts from someone
  who is neither, so a maintainer push would invalidate the maintainer's
  own review approval (the review process's merge gate). The opencode
  permission prompt on `git push` / `gh pr create` is the runtime gate.
  One exception: a push touching `.github/workflows/` can be rejected by
  GitHub with permission denied (workflow files need elevated rights) —
  then the agent hands the maintainer the exact initial push command and
  re-pushes follow-ups itself, so the last push is the agent's again
  before approvals. The PR body carries the `Track:` line at PR
  creation (review-concept.md, "Round typing and tiering") — the
  review re-derives it; a missing line is a disclosed deviation.
  Merging the PR and closing the review loop stay with the
  maintainer. Push **without `-u`** (`git push origin <branch>`): the
  `.git` heal pins `.git/config` developer-owned (issue #651), so the
  tracking write a first `git push -u` performs fails with
  `Operation not permitted` — the push itself transfers fine. The
  agent's main-checkout staging/branching (`git add`, `git switch`)
  and merging (`git merge`/`git pull`, #678) depend on the
  maintainer-side git heal hooks being on (`opk
  git-heal on`, issue #671): developer git operations flip the heal's
  operand metadata (`.git/index`, `.git/HEAD` and the widened #678
  carriers — ORIG_HEAD, REBASE_HEAD, packed-refs, the conflict
  pseudo-refs), and without the hooks the sticky `.git`
  locks the agent out until healed — `opk status` shows the lockout
  risk; agent worktrees are the self-sufficient fallback. (RM-0097)
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
  current model: `docs/concepts/security-model.md`. Sanctioned exception
  (#651, PR #655): the `.git` heal — sticky bits on `.git` and its
  metadata containers (the #655-era project-root/ancestor stickies were
  REMOVED again by #702/#703; a baseline run strips legacy bits as
  migration) plus developer-ownership narrowing on `.git` metadata that
  the group baseline would otherwise leave agent-writable
  (`fs-baseline.sh`); no deny ACLs involved, and the stickied
  directories keep their sharing modes (sticky gates only rename/unlink
  of foreign entries). Follow-up (#671): the git heal hooks —
  opt-in maintainer-side git hooks (`opk git-heal on`) that re-pin
  the measured operand set (`.git/index`, `.git/HEAD` and the widened
  #678 carriers, each only when present) to the agent user after
  developer git operations via a narrow root heal behind a sudoers
  grant; still no deny ACLs, ownership-only. (RM-0103)
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
make lint                # ShellCheck + shfmt format gate over the kit shell
make check-version       # VERSION + KIT_BRANCH consistency
make e2e                 # e2e (Docker needed)
make e2e-rootless        # docker-rootless e2e (skips without systemd-in-container)
```

**Line-length ratchet:** a red `test-line-length.sh` means a scoped line
grew past 120 content columns. Shorten it; a deliberate exception goes
through `sh tests/unit/test-line-length.sh --regen` with the baseline
diff reviewed.

**gh auth:** where the context may lack gh auth (e2e containers, foreign
hosts), probe `gh auth status` before gh-dependent steps; for read-only
lookups, `curl` against api.github.com replaces failing gh calls.

**Unit suites are sandboxed by policy** (0.0.42e C1): they create/delete
only inside their own scratch and `/tmp`, `/var/tmp` — never in real
project or system trees (`/var/www/vhosts`, `/home`, `/srv`, `/etc`, …),
not even in teardown. Enforced by
`tests/unit/test-sandbox-policy.sh`; the rule lives in
`agent/conventions.md` ("Test sandbox (unit suites)").

**Sabotage-verify only against secured work.** Before mutating the tree
to prove a pin fails (mutation verification), commit the finished work or
`git stash` it first — a sabotage restore (`git checkout --` /
`git restore`) resets the file to its INDEX state and silently wipes
every edit since the last commit or stage (learned the hard way,
2026-10; recurred 2026-11 in PR #441 round b D1 — that wave pushed a
pin whose recursion-break marker had been silently wiped). The securing check is
a PER-CYCLE invariant, not one-time phase preparation: every single
sabotage cycle starts from a verified-clean tree (`git status
--porcelain` empty for the target file) — the PR-#441 loss happened in
the SECOND cycle, after a fresh edit had landed uncommitted between two
cycles. **Quick fix between cycles (worst case: pin and sabotaged
construct share one file).** A cycle that stays green on the sabotaged
pin (the pin is unsound) invites a quick fix in the working tree
mid-cycle — and in that state neither securing move applies: committing
bakes the sabotage into the commit, and `git stash` mixes fix and
sabotage in one stash (recurred 2026-11-16 in PR #568 round c Z3: a
`git restore` wiped an uncommitted canary-leg fix in the same test
file). Sanctioned move: before EVERY sabotage restore (`git checkout
--` / `git restore`), copy the file out of the tree — `cp -- "$S"
/tmp/opencode/<case>/pre-restore.$(basename "$S")` (unconditional —
never assess whether you are in quick-fix mode; the latest copy wins by
design). If the post-restore content verification finds the fix gone
(grep the fix's construct alongside the pin's), recover by re-applying
ONLY the fix hunks from the `diff` of the copy against the restored
file — never copy the whole file back (it re-imports the sabotage). The
copy is the securing step: no mid-cycle gate + commit is owed; the fix
rides the wave's regular gate chain (#577 option 2.a). And sabotage by
*deleting* the construct, not commenting it out: un-ridden grep-count
pins (absence pins, bare control arms) still count commented lines, so
a commented-out sabotage can pass green. And the sabotage must keep
the script parseable: a deletion that would empty a shell branch (the
construct is its only command) replaces it with a no-op (`: #
sabotaged`) instead — a syntax-error red fails every pin
indiscriminately and proves nothing; the red must come from the pin's
own assertion over a still-running script (pr-00581 fix wave,
2026-11-17). After
the sabotage run, restore the good state from the commit/stash (or a copy
kept outside the tree) and re-run the suite to confirm green — and
verify the restore CONTENT-based, never rc-based: grep the construct
the fix introduced (marker, guard line); rc 0 holds for the pre-fix and
post-fix version alike in the restored state, so rc cannot see the wipe
by construction. Corollary: an `--amend` that commits nothing new after
an edit you believe you made means the edit was already wiped — grep
before amending. During a
review fan-out the tree is a shared read substrate: sabotage only (a)
before the reviewers launch, (b) after all returned, or (c) in a scratch
worktree — the window and screening rules live in
[review-concept.md](agent/review-concept.md#parallel-reviewer-agents).
A background e2e suite is the same class of reader (it installs from
the checkout): sabotage on the CHECKOUT must precede its start too —
a scratch-worktree cycle (arm c above) stays sanctioned alongside a
running suite (#524 §5).
**Gate runs are one unbroken `&&` chain ending in the commit.** No
`| tail` or any pipe on a gate command (the pipeline returns the last
member's rc — a red gate goes green through it), no `;` separator after
a gate (the chain breaks; whatever follows runs on red), `set -o
pipefail` when wrapping is needed anyway; redirect gate output to log
files instead of piping it away. Two live instances on 2026-10-25, both
in pr-00263: the fix wave committed through a red line-length ratchet
behind a piped gate, and the d wave's `; echo` separator let a
121-char resolution row slip past the gate (caught by amending the
still-unpushed commit). The redirect must bind to the WHOLE chain,
never the last member: a redirect after the final command belongs to
that command alone (shell precedence), so when an earlier gate reds
the log is never written and the full output floods the session
context instead (three live floods in pr-00621's gate runs, one more
in its pilot session, one in the docs-loop-623 first chain run;
#624, dedup #627 item 1). House form —
per-command logs, rc and a three-line tail echoed AFTER the chain
(diagnostics, not gate members):

```sh
make sums >/tmp/opencode/<case>/sums.log 2>&1 &&
make lint >/tmp/opencode/<case>/lint.log 2>&1 &&
make test >/tmp/opencode/<case>/test.log 2>&1 &&
git add <paths> && git commit -m "…" && echo "GATE-OK"
rc=$?; tail -3 /tmp/opencode/<case>/test.log; echo "RC=$rc"
```

Diagnosis only on red: `tail -40 /tmp/opencode/<case>/<offender>.log`.
Check-then-commit is only protection if the
check can fail the chain. A RUNNING chain freezes the tree it
reads: while a gate chain runs — a background chain above all — no
file its suites read is edited; pin-block additions, literal fixes
and every other edit wait for the chain's completion or land before
its start. A green `make test` over a tree that changed mid-run
covered a MIXED state — some suites before the edit, some after, and
a suite hitting the file inside an edit window can red on a
half-written file or pass without seeing the final pins — so
an edit that slipped
in anyway voids the green for the edited files' suites — the full
gate re-runs over the final state before the commit rides it
(mandatory re-run, not a remembered favor; #692, PR #689 session —
the tell was 0 pin-marker hits in the chain's log, ambiguous
because passing pins grep silently). The chain's SCOPE for fix waves is the full
gate (`make test`), never only the touched suites: tree-wide invariant
suites (rules-meta, sandbox-policy, workflows, format-gate) redden on
changes their own files never touched — #412's round-b B3 (bare
rule-ID citations in new comment text) was locally invisible and red
in CI exactly through that gap. A change to a shared list consumed by
tests (the rules audit's `SCOPE_FILES`, `KIT_FILES`, suite
inventories) greps every consumer suite BEFORE the gate run — the
gate stops at the first red and masks later same-cause suites behind
it (issue #540 §1: the rules-meta fixture mirror surfaced only after
rules-revisit's was fixed and the chain re-ran, in PR #539's session).
A new function in a section lib (`sh/status-core.sh`,
`sh/doctor-core.sh`) has THREE registration points: the pairing-guard
list in the sourcing entry script (`status_pairing_guard` /
`doctor_pairing_guard`), the `_defs` sourcing list in the lib's unit
suite (with an in-place comment when a list is deliberately
non-exhaustive), and the suite's count message — derive that count
from the list (`_ndefs` from `_defs`, as test-as-opencode-core.sh
does), never hardcode it. Missed points have cost a mid-wave red gate
and review findings (#595, PR #590 rounds a–b).
A wave whose diff touches `files/`
also owes `make sums` IN the chain, first — `make sums && make test &&
git add && git commit`: the freshness pin inside `make test` reddens on
a stale `SHA256SUMS` (issue #478), so the regeneration must land in
the log before the suite reads it (#524 §1 paid one red gate for the
order); `make sums` itself is idempotent (no-op output when the
manifest is already fresh). When the wave stages by explicit path
(the co-edit-safe form below), the **repo-root** `SHA256SUMS` must be
named in the same `git add` — the manifest lives at the repository
root, not under `files/` (a guessed `files/SHA256SUMS` pathspec-kills
the chain at the add, exit 128, after the gates already ran green;
#637, PR #633), and the chain regenerates the file, which the path
list does not know (twice amended in one session, pr-00599 commits
8f7cae87 and c09f13f2; issue #602). The POST-REBASE shape inverts
that order duty: after rebasing a branch whose per-commit
`SHA256SUMS` conflicted (any rebase onto a master that touched
`files/` — resolve the conflicts `--theirs` per commit), the final
regenerated manifest needs its OWN commit BEFORE `make test` runs.
The fetch-integrity committed-manifest leg compares the manifest at
HEAD against HEAD's tree, and the post-rebase state is exactly
inputs-clean-plus-manifest-stale — the documented
`sums && test && add && commit` order cannot complete there,
because the check that must gate the commit reads a commit that has
not happened yet. Working sequence (probed 2026-11-20; one red
cycle paid for it in the #687 session): `make sums && git add
SHA256SUMS && git commit -m "…" && make test` — from there the
normal chain order applies again. The entry-checksum blocks in README and
`docs/getting-started.md` are the ONE checksum artifact mid-cycle
waves never touch: `make release-sums` rewrites them from the tree's
`files/install.sh` **release PR only** (issue #492) — a mid-cycle
regen would publish a hash for bytes `stable` does not serve yet;
`make release` step 2.6 refuses a stale block, and the release PR's
chain is `make version VERSION=x && make sums && make release-sums &&
make test`. The same ordering duty holds for the
rules-meta INDEX: a wave that adds or amends metas regenerates
`internal/rules-meta/INDEX.md` inside the chain BEFORE the suite
reads it (`sh scripts/rules-audit.sh`, or
`python3 scripts/gen-rules-index.py`) — the parity suite's freshness
pin reds on a stale INDEX AND restores the stale bytes on red, so the
red persists until the explicit regen runs (issue #549 §1: a fix wave
paid one red gate for the order).
An evidence probe rides the same chain discipline — a probe whose
output feeds a verdict is a gate over that verdict: one unbroken `&&`
chain, absolute paths, no `;` separator. A half-run probe's output is
not evidence: pr-00586's A2 re-verification probe ran
`cd <scratch> && … ; echo rc; …`, the cd failed before the dir
existed, the `;` segments still ran — files landed in an unintended
cwd, the printed rc was the failed cd's — and the output counted only
after a deterministic re-run (#588 §1).
While the maintainer co-edits the working
tree (interactive iteration), stage explicitly by path — `git add -A`
is for solo phases with a verified-clean tree (a `git add -A` chain
once swept the maintainer's template file into a commit, #528 §2).

Both e2e suites are part of the definition of done for changes to
`install.sh`, `update.sh`, the wrapper, or backend provisioning — and for
semantics changes (rc contracts, traps, sudoers, provisioning) and
behavioral changes (new refusal/skip/abort arms, changed control
flow) to any other root-run code (`uninstall.sh`, `opk`,
`fs-baseline.sh`, the `sh/*.sh` libs the installer sources — they run
as root during install, `ddev-migrate.sh` being the worked example,
PR #633): those owe both suites in the wave itself. Message- or
comment-only changes to root-run code may ride to the release
gate; a later session that runs both suites
green on a committed tree discharges the debt (record tree SHA + counts).
Suite per class: `run.sh`'s fake-ddev tier drives the sourced-lib
install path; `run-ddev.sh`'s DD15 leg is the real-ddev tier for
`ddev-migrate` (its loop registers normal-shaped names only — a
name-shape gate is invisible to it and stays unit-pinned; #638,
PR #633).
**Run them in parallel when the precondition holds — not sequentially**
(the suites are disjoint: per-suite containers, images and fixtures;
sequential runs cost the other suite's full runtime for no benefit).
Precondition: the suites resolve the opencode version at runtime
(current latest — `E2E_OC_VERSION` pins it), so a "warm"
`tests/e2e/cache/` only covers the version the last run used. After any
time gap — or on a first run — run one suite alone first, confirm it
resolved and cached its version; parallel runs are safe from there. The
invocation pattern (including the three-suite variant with `e2e-ddev`)
lives in [CONTRIBUTING.md](CONTRIBUTING.md).
Executable bits live in the **git index** (issue #123): commit anything
CI or the kit execute by path with `git update-index --chmod=+x <path>`
(invariant: 755 <=> executed by path, 644 <=> sourced lib / interpreter
call / data; enforced by `tests/unit/test-workflows.sh`). Workflows
carry no `chmod +x` lines — `actions/checkout` preserves tracked modes.
An index-only mode does not survive a later `git add` of the same
path: the add re-stages the mode from the DISK file, silently
resetting a verified `update-index` entry when the disk lags — every
gate that ran before the add stays green, the commit ships 644, CI
reds (pr-00600 round a A1). For agent-CREATED scripts, `chmod 755`
the disk file first (the agent owns files it created) so the add
stages the mode naturally; for pre-existing files the handover
procedure under "Checkout ownership" applies. And a gate check that
reads the INDEX (the exec-bit consistency suite) runs in a
stage-first chain — `git add … && make test && git commit` — so the
check sees the state the commit will carry; the check-then-add order
stays right for content gates (issue #603).

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
aid:

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
  low-tier re-review; fixes bring their own pins.

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
