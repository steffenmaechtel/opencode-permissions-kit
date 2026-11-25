# Gates — wave mechanics, sabotage cycles, checksum ordering

> Status: **BINDING** — on-demand detail archive for the AGENTS.md
> Testing section (issue #768): the root file carries one invariant
> sentence per topic plus a trigger line; the narrative, rationale and
> incident history live here. Loaded when a wave runs gates, sabotages
> pins, or ships a diff that touches `files/`.

## Gate chains (one unbroken `&&` chain ending in the commit)

No `| tail` or any pipe on a gate command (the pipeline returns the
last member's rc — a red gate goes green through it), no `;` separator
after a gate (the chain breaks; whatever follows runs on red), `set -o
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
in its pilot session, one in the docs-loop-623 first chain run; #624,
dedup #627 item 1). House form — per-command logs, rc and a three-line
tail echoed AFTER the chain (diagnostics, not gate members):

```sh
make sums >/tmp/opencode/<case>/sums.log 2>&1 &&
make lint >/tmp/opencode/<case>/lint.log 2>&1 &&
make test >/tmp/opencode/<case>/test.log 2>&1 &&
git add <paths> && git commit -m "…" && echo "GATE-OK"
rc=$?; tail -3 /tmp/opencode/<case>/test.log; echo "RC=$rc"
```

Diagnosis only on red: `tail -40 /tmp/opencode/<case>/<offender>.log`.
Check-then-commit is only protection if the check can fail the chain.

### Chain scope: the full gate, mid-run edits, shared lists

The chain's SCOPE for fix waves is the full gate (`make test`), never
only the touched suites: tree-wide invariant suites (rules-meta,
sandbox-policy, workflows, format-gate) redden on changes their own
files never touched — #412's round-b B3 (bare rule-ID citations in new
comment text) was locally invisible and red in CI exactly through that
gap.

A RUNNING chain freezes the tree it reads: while a gate chain runs — a
background chain above all — no file its suites read is edited;
pin-block additions, literal fixes and every other edit wait for the
chain's completion or land before its start. A green `make test` over
a tree that changed mid-run covered a MIXED state — some suites before
the edit, some after, and a suite hitting the file inside an edit
window can red on a half-written file or pass without seeing the final
pins — so an edit that slipped in anyway voids the green for the
edited files' suites — the full gate re-runs over the final state
before the commit rides it (mandatory re-run, not a remembered favor;
#692, PR #689 session — the tell was 0 pin-marker hits in the chain's
log, ambiguous because passing pins grep silently).

A change to a shared list consumed by tests (the rules audit's
`SCOPE_FILES`, `KIT_FILES`, suite inventories) greps every consumer
suite BEFORE the gate run — the gate stops at the first red and masks
later same-cause suites behind it (issue #540 §1: the rules-meta
fixture mirror surfaced only after rules-revisit's was fixed and the
chain re-ran, in PR #539's session).

### Registration points (section libs)

A new function in a section lib (`sh/status-core.sh`,
`sh/doctor-core.sh`) has THREE registration points: the pairing-guard
list in the sourcing entry script (`status_pairing_guard` /
`doctor_pairing_guard`), the `_defs` sourcing list in the lib's unit
suite (with an in-place comment when a list is deliberately
non-exhaustive), and the suite's count message — derive that count
from the list (`_ndefs` from `_defs`, as test-as-opencode-core.sh
does), never hardcode it. Missed points have cost a mid-wave red gate
and review findings (#595, PR #590 rounds a–b).

## Checksums and generated indexes (ordering duties)

A wave whose diff touches `files/` also owes `make sums` IN the chain,
first — `make sums && make test && git add && git commit`: the
freshness pin inside `make test` reddens on a stale `SHA256SUMS`
(issue #478), so the regeneration must land in the log before the
suite reads it (#524 §1 paid one red gate for the order); `make sums`
itself is idempotent (no-op output when the manifest is already
fresh). When the wave stages by explicit path (the co-edit-safe form
below), the **repo-root** `SHA256SUMS` must be named in the same
`git add` — the manifest lives at the repository root, not under
`files/` (a guessed `files/SHA256SUMS` pathspec-kills the chain at the
add, exit 128, after the gates already ran green; #637, PR #633), and
the chain regenerates the file, which the path list does not know
(twice amended in one session, pr-00599 commits 8f7cae87 and c09f13f2;
issue #602).

The POST-REBASE shape inverts that order duty: after rebasing a branch
whose per-commit `SHA256SUMS` conflicted (any rebase onto a master that
touched `files/` — resolve the conflicts `--theirs` per commit), the
final regenerated manifest needs its OWN commit BEFORE `make test`
runs. The fetch-integrity committed-manifest leg compares the manifest
at HEAD against HEAD's tree, and the post-rebase state is exactly
inputs-clean-plus-manifest-stale — the documented
`sums && test && add && commit` order cannot complete there, because
the check that must gate the commit reads a commit that has not
happened yet. Working sequence (probed 2026-11-20; one red cycle paid
for it in the #687 session): `make sums && git add SHA256SUMS && git
commit -m "…" && make test` — from there the normal chain order
applies again.

The entry-checksum blocks in README and `docs/getting-started.md` are
the ONE checksum artifact mid-cycle waves never touch: `make
release-sums` rewrites them from the tree's `files/install.sh`
**release PR only** (issue #492) — a mid-cycle regen would publish a
hash for bytes `stable` does not serve yet; `make release` step 2.6
refuses a stale block, and the release PR's chain is `make version
VERSION=x && make sums && make release-sums && make test`.

The same ordering duty holds for the rules-meta INDEX: a wave that
adds or amends metas regenerates `internal/rules-meta/INDEX.md` inside
the chain BEFORE the suite reads it (`sh scripts/rules-audit.sh`, or
`python3 scripts/gen-rules-index.py`) — the parity suite's freshness
pin reds on a stale INDEX AND restores the stale bytes on red, so the
red persists until the explicit regen runs (issue #549 §1: a fix wave
paid one red gate for the order).

## Sabotage verification (mutation proofs)

Sabotage-verify only against secured work. Before mutating the tree to
prove a pin fails (mutation verification), commit the finished work or
`git stash` it first — a sabotage restore (`git checkout --` /
`git restore`) resets the file to its INDEX state and silently wipes
every edit since the last commit or stage (learned the hard way,
2026-10; recurred 2026-11 in PR #441 round b D1 — that wave pushed a
pin whose recursion-break marker had been silently wiped). The securing
check is a PER-CYCLE invariant, not one-time phase preparation: every
single sabotage cycle starts from a verified-clean tree (`git status
--porcelain` empty for the target file) — the PR-#441 loss happened in
the SECOND cycle, after a fresh edit had landed uncommitted between two
cycles.

**Quick fix between cycles (worst case: pin and sabotaged construct
share one file).** A cycle that stays green on the sabotaged pin (the
pin is unsound) invites a quick fix in the working tree mid-cycle —
and in that state neither securing move applies: committing bakes the
sabotage into the commit, and `git stash` mixes fix and sabotage in one
stash (recurred 2026-11-16 in PR #568 round c Z3: a `git restore`
wiped an uncommitted canary-leg fix in the same test file). Sanctioned
move: before EVERY sabotage restore (`git checkout --` /
`git restore`), copy the file out of the tree — `cp -- "$S"
/tmp/opencode/<case>/pre-restore.$(basename "$S")` (unconditional —
never assess whether you are in quick-fix mode; the latest copy wins
by design). If the post-restore content verification finds the fix gone
(grep the fix's construct alongside the pin's), recover by re-applying
ONLY the fix hunks from the `diff` of the copy against the restored
file — never copy the whole file back (it re-imports the sabotage). The
copy is the securing step: no mid-cycle gate + commit is owed; the fix
rides the wave's regular gate chain (#577 option 2.a).

Sabotage by *deleting* the construct, not commenting it out:
un-ridden grep-count pins (absence pins, bare control arms) still count
commented lines, so a commented-out sabotage can pass green. And the
sabotage must keep the script parseable: a deletion that would empty a
shell branch (the construct is its only command) replaces it with a
no-op (`: # sabotaged`) instead — a syntax-error red fails every pin
indiscriminately and proves nothing; the red must come from the pin's
own assertion over a still-running script (pr-00581 fix wave,
2026-11-17).

After the sabotage run, restore the good state from the commit/stash
(or a copy kept outside the tree) and re-run the suite to confirm
green — and verify the restore CONTENT-based, never rc-based: grep the
construct the fix introduced (marker, guard line); rc 0 holds for the
pre-fix and post-fix version alike in the restored state, so rc cannot
see the wipe by construction. Corollary: an `--amend` that commits
nothing new after an edit you believe you made means the edit was
already wiped — grep before amending.

### Sabotage windows (readers of the shared tree)

During a review fan-out the tree is a shared read substrate: sabotage
only (a) before the reviewers launch, (b) after all returned, or (c) in
a scratch worktree — the window and screening rules live in
[review-concept.md](review-concept.md#parallel-reviewer-agents). A
background e2e suite is the same class of reader (it installs from the
checkout): sabotage on the CHECKOUT must precede its start too — a
scratch-worktree cycle (arm c above) stays sanctioned alongside a
running suite (#524 §5).

## Evidence probes (chain discipline)

An evidence probe rides the same chain discipline — a probe whose
output feeds a verdict is a gate over that verdict: one unbroken `&&`
chain, absolute paths, no `;` separator. A half-run probe's output is
not evidence: pr-00586's A2 re-verification probe ran
`cd <scratch> && … ; echo rc; …`, the cd failed before the dir
existed, the `;` segments still ran — files landed in an unintended
cwd, the printed rc was the failed cd's — and the output counted only
after a deterministic re-run (#588 §1).

## E2E suites (definition of done, parallel runs)

Both e2e suites are part of the definition of done for changes to
`install.sh`, `update.sh`, the wrapper, or backend provisioning — and
for semantics changes (rc contracts, traps, sudoers, provisioning) and
behavioral changes (new refusal/skip/abort arms, changed control
flow) to any other root-run code (`uninstall.sh`, `opk`,
`fs-baseline.sh`, the `sh/*.sh` libs the installer sources — they run
as root during install, `ddev-migrate.sh` being the worked example,
PR #633): those owe both suites in the wave itself. Message- or
comment-only changes to root-run code may ride to the release gate; a
later session that runs both suites green on a committed tree
discharges the debt (record tree SHA + counts). Suite per class:
`run.sh`'s fake-ddev tier drives the sourced-lib install path;
`run-ddev.sh`'s DD15 leg is the real-ddev tier for `ddev-migrate`
(its loop registers normal-shaped names only — a name-shape gate is
invisible to it and stays unit-pinned; #638, PR #633).

Run them in parallel when the precondition holds — not sequentially
(the suites are disjoint: per-suite containers, images and fixtures;
sequential runs cost the other suite's full runtime for no benefit).
Precondition: the suites resolve the opencode version at runtime
(current latest — `E2E_OC_VERSION` pins it), so a "warm"
`tests/e2e/cache/` only covers the version the last run used. After any
time gap — or on a first run — run one suite alone first, confirm it
resolved and cached its version; parallel runs are safe from there.
The invocation pattern (including the three-suite variant with
`e2e-ddev`) lives in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Executable bits, index modes, staging

Executable bits live in the **git index** (issue #123): commit anything
CI or the kit execute by path with `git update-index --chmod=+x <path>`
(invariant: 755 <=> executed by path, 644 <=> sourced lib / interpreter
call / data; enforced by `tests/unit/test-workflows.sh`). Workflows
carry no `chmod +x` lines — `actions/checkout` preserves tracked modes.
An index-only mode does not survive a later `git add` of the same path:
the add re-stages the mode from the DISK file, silently resetting a
verified `update-index` entry when the disk lags — every gate that ran
before the add stays green, the commit ships 644, CI reds (pr-00600
round a A1). For agent-CREATED scripts, `chmod 755` the disk file first
(the agent owns files it created) so the add stages the mode naturally;
for pre-existing files the handover procedure under AGENTS.md
"Checkout ownership" applies. And a gate check that reads the INDEX
(the exec-bit consistency suite) runs in a stage-first chain —
`git add … && make test && git commit` — so the check sees the state
the commit will carry; the check-then-add order stays right for content
gates (issue #603).

While the maintainer co-edits the working tree (interactive
iteration), stage explicitly by path — `git add -A` is for solo phases
with a verified-clean tree (a `git add -A` chain once swept the
maintainer's template file into a commit, #528 §2).
