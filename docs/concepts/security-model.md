# Security model

What the kit guarantees, what it deliberately does not, and which residual
gaps remain.

## The three hard guarantees

The kit's hard guarantees are UID-level — file permissions are opencode's own
**soft** layer (see below):

| Guarantee | Mechanism |
|---|---|
| Agent ≠ developer | wrapper execs `sudo -u opencode`; the developer's home is `750` and not group-shared |
| Containers ≠ root | rootless backend owned by `opencode` (per-user socket / daemonless podman) |
| No developer-RunAs | sudoers carry only `(opencode)` rules — kit binary, socket probe, cwd check, ddev helper |

Concretely:

- the agent's processes run as `opencode`, never as the developer — no
  credentials, SSH keys, or dotfiles in `/home/<developer>` are reachable,
- the agent-resources migration moves `~/.agents` whole but only
  `~/.claude/skills` — credentials such as `~/.claude/.credentials.json`
  never cross into the agent's home,
- containers run under the `opencode` host UID via a rootless backend —
  through the kit's backend the agent never reaches a root-equivalent
  docker socket (one env_keep exception lives in
  [Known residual gaps](#known-residual-gaps)),
- no code path executes as the developer (no RunAs-developer sudoers rule).

## The soft permission layer (deliberate trade-off)

File denies (`.env`, keys, `settings.php`, …) live in `opencode.jsonc` and
gate **opencode's own read/edit tools** plus lexical bash tripwires. They are
the "ddev must work" decision:

> Processes spawned outside opencode's tools (ddev, its containers, `cat` in
> bash) can read every project file — including `settings.php`, which ddev's
> web container needs to boot.

| Guarantee | Mechanism |
|---|---|
| File denies (`.env`, keys, …) | `opencode.jsonc` soft rules — opencode's tools + bash tripwires |
| Developer ↔ agent file sharing | the `opencode` usergroup: setgid + default group ACLs + umask 002 |
| ddev runs as one user | the `ddev()` function + the sudoers helper exec ddev as `opencode` |

One exception: **browser-opening commands** (`launch`, `mailpit`,
`phpmyadmin`, …) compute the URL as `opencode`, but the browser open runs as
the developer — it needs the Windows interop the agent must not have. See
[ddev integration](ddev-integration.md#browser-opening-commands).

A second, deliberate exception — **the `.git` heal** (issue
[#644](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/644),
wave #651): the sharing baseline above still shares `.git` wholesale (the
agent must be able to commit), but every baseline run *re-narrows the
execution-bearing metadata* OS-side, because the developer's git executes
from agent-writable surfaces there:

- `.git` itself (and the `worktrees` collections) get the sticky bit;
  `.git/config` and `.git/hooks` (and the `modules` containers with
  their gitdirs, and the worktree `commondir`/`gitdir` pointer files —
  top gitdir and submodule gitdirs alike) are pinned
  **developer-owned, no group write, no extended ACLs**. The project
  root and the `.git` ancestor directories deliberately carry **no**
  sticky bit (decision
  [#702](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/702),
  wave #703): the #655-era bits were removed again — measured on
  kit-managed hosts, their everyday costs (issues
  [#699](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/699),
  [#682](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/682),
  [#701](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/701),
  [#697](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/697))
  outweighed the wholesale-swap prevention, and a baseline run now
  strips any sticky it finds on those directories (migration —
  indiscriminate by necessity: the mechanism cannot tell a kit-era
  bit from an operator's, so an operator-set sticky on a scan root
  or `.git` ancestor goes with it at every baseline run). The strip
  covers registered roots and the ancestors of every `.git` found
  under them; one corner lingers — an ancestor stickied for a
  `.git` that has since been deleted is outside every current walk
  (strip those manually: `sudo chmod -t <dir>`). What that trade reopens
  — the wholesale `.git` / project-dir swap arms — is documented with
  the residuals below.
- Why that works: the sticky bit sits on the PARENT of whatever must
  not be replaced — renaming or unlinking an entry needs write on its
  parent directory, and a developer-owned entry in a sticky parent is
  untouchable for the agent. Git *reads* the config for plain
  commits/pushes but writes it through lock+rename — that rename dies
  on the sticky bit. Planted hooks, `core.fsmonitor`, `core.hooksPath`
  overrides, diff-driver registrations and repo-config
  `core.pager`/`core.editor` arms can no longer be placed or
  rewritten by the agent. The agent's commit/push workflow stays green
  on files the heal pinned; `index` and `HEAD` were deliberately left
  floating (the agent must stage and switch branches), which has its
  own cost — see the **git heal hooks** below.
- **The git heal hooks** (issue
  [#671](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/671),
  operand set widened in
  [#678](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/678)):
  git rewrites `.git/index` and `.git/HEAD` through lock+rename too, so
  their ownership floats with the last writer — and a sticky `.git`
  blocks the agent from renaming over a developer-owned entry ever
  again. The first developer checkout or pull after a merge therefore
  locks the agent's staging and branch operations (`git add`, `git
  switch`) out of the main checkout; a developer merge/pull/reset/rebase
  flips `ORIG_HEAD` the same way and kills the agent's merge and pull.
  The baseline cannot close that
  (every developer git operation re-flips the ownership, and lifecycle
  re-heals would only ping-pong). The closure is opt-in and
  maintainer-side: `opk git-heal on` points the developer's global
  `core.hooksPath` at the kit-owned hook directory
  (`git-heal/hooks/`), whose `post-merge`, `post-checkout`,
  `post-rewrite` and `post-index-change` bodies re-pin the measured
  operand set — `index`/`HEAD`/`ORIG_HEAD`/`REBASE_HEAD`/`packed-refs`
  plus the conflict pseudo-refs, each only when it exists —
  to the agent user after every developer git operation, via a narrow
  root heal (`git-heal/heal-index-head`) behind a sudoers grant. The
  carrier set is measured, not assumed: `post-index-change` fires on
  EVERY index write — mutating commands (`add`, `reset`, `read-tree`)
  and refreshing `git status` runs on a stale cache (IDE refreshes
  while the agent edits) alike — but not on a fresh-cache status that
  writes nothing, which is exactly the no-flip case; pull/merge
  (including fast-forward) rides `post-merge`, checkouts/switches ride
  `post-checkout` (there is no `post-reset` hook in git;
  `post-index-change` is that family's real carrier); the resolution
  `git add` fires `post-index-change` with the merge-state set
  present, and mid-rebase steps fire `post-checkout`/
  `post-index-change` with `REBASE_HEAD` present (`post-rewrite`
  also carries it, but only in a conflicted rebase concluded via
  `--continue` — the mid-rebase fires are the robust carrier). The
  global
  `core.hooksPath` doubles as defense in depth: repo hooks stop
  executing for the developer (the effect the `/dev/null` form in
  [secure git config](../how-to/secure-git-config.md) documents), and
  the kit's own hooks are the only ones left — root-owned, outside the
  agent's reach. See [the git heal hooks how-to](../how-to/git-heal-hooks.md).
- This is OS-level narrowing — the one place the kit deliberately steps
  out of the pure soft model, scoped to `.git` internals that ddev
  never touches. Workflow costs
  accepted with it: repo-scope `git config` and `git submodule add`
  fail for the agent (`submodule add` dies at the clone stage — the
  `modules` container accepts no agent writes; for `git config` the
  write IS the operation); a first `git push -u` and
  `git branch --set-upstream-to` fail at their tracking write while the
  push transfer itself completes (field-reported 2026-11-18, recorded
  in issue #644) — so agents push without `-u`
  (`git push origin <branch>`); agent-side `git gc` can
  hit the sticky bit on `packed-refs`; and a repo the agent cloned
  INTO a developer-owned project tree is healed to the root's owner —
  the agent loses repo-config writes in its own nested clone (work in
  the main checkout or an agent-owned root instead). A cost that is
  GONE again with #703: the agent once could not rename or delete
  developer-owned top-level entries (project-root sticky) — see the
  reopened-residual entries below for the flip side.
- What it does **not** close: the post-heal residual inventory —
  agent-controlled worktree gitdirs, agent-owned trees, the timing
  class between heal runs, content planted before the heal, the
  nuisance arms of the shared `.git`, and the pre-heal context with
  the one complete closure — lives in
  [Known residual gaps](#known-residual-gaps) below (documented with
  issue #652 after the heal was piloted).
- The heal survives `opk uninstall` where it matters: the revert walks
  never touch the sticky bit or the **uid** of developer-owned pinned
  entries (their *group* is reverted to the developer's login group by
  the gid-matched chown pass — protection unaffected either way: no
  group write in either group). On an agent-owned healed root the uid
  arm of the same walk flips the pinned entries to the developer — the
  desirable direction there. A healed `.git` keeps protecting the solo
  developer.

## Download integrity (SHA256SUMS)

The streamed installer and updater fetch every kit file from
`raw.githubusercontent.com`. Since issue #478 each fetched file is
verified against the repo's **`SHA256SUMS`** manifest (fetched from the
same ref) before it enters the staging tree: the digest must match
exactly, or the install/update aborts — nothing is deployed, temps are
cleaned, and the error names the file plus expected/actual digests. The
manifest itself is shape-gated line by line (an HTML error body never
becomes a "manifest"), and `opk update` additionally re-verifies the
whole staged tree before any deploy phase runs. That tree pass also
covers trees an older deployed updater fetched without verification —
for updaters that export their staging tree (vintage 0.0.40 and later).
Vintages 0.0.29–0.0.39 re-exec the new updater without the export
marker and are indistinguishable from a manifest-less checkout, so
their **first** update into the verified era deploys unverified; the
update after that verifies. (Vintages ≤ 0.0.28 never reach the re-exec:
they predate the current file layout and abort with a re-install hint.)

What this buys:

- **Corruption detection** — truncated transfers, a broken mirror, or a
  captive portal's HTML page masquerading as a 200 file body can no
  longer reach `/usr/local/lib` as root.

What it deliberately does **not** buy:

- **Origin-compromise protection.** The manifest rides the same origin
  and ref as the files: an attacker able to replace the files can
  replace the manifest too, with matching digests. Protecting against
  that requires signed manifests (a public key shipped independently of
  the streamed scripts) — a deliberate Phase 2 non-goal for now.

### The entry scripts themselves (verified install)

The manifest cannot cover the script you pipe into bash — it runs
before any verification code exists (the bootstrap gap). The stable
channel documents a verified-install variant for exactly that gap:
download `install.sh` as a file, check its sha256 — printed in the
README, in [Getting started](../getting-started.md#install) and on the
install page — then execute it. The install page's hash is rendered at
deploy time from the exact bytes the site serves; README and Getting
started carry the literal hash, rewritten only in the release PR
(`make release-sums`; `make release` refuses to cut from a stale
block).

What this adds over the manifest alone:

- **Entry-script corruption detection** — a captive portal, CDN fault
  or broken mirror serving garbage instead of `install.sh` fails the
  check as a clean named error instead of a cryptic bash syntax error
  (or worse, unverified execution).
- **Cross-channel visibility** — the README hash rides github.com
  while the checked bytes come from the Pages site; the two channels
  failing to agree is itself the tamper signal.

It inherits the manifest's honest limit: **no origin-compromise
protection** — README, Pages site and repository share the GitHub
account; an attacker with write access replaces both. Signed artifacts
remain the Phase 2 answer.

One local residual: the recipe checks and then runs a fixed
`/tmp/opk-install.sh`. On a sticky `/tmp` (the WSL2/Linux default) the
classic race is closed — a pre-planted file fails the download or is
truncated before the check, and a post-check swap needs control of a
file you own. On a shared host with a non-sticky `/tmp`, a co-located
user could swap the bytes between check and execution — use a
user-private download path there.

Operational notes:

- `KIT_SHA_VERIFY=0` disables the mechanism (break-glass for tag pins
  that predate the manifest and for odd mirrors; only the operator sets
  their own environment — an attacker on the wire cannot).
- A missing or unusable `sha256sum` binary aborts the fetch loudly —
  verification is never silently skipped on the fetch paths. The one
  documented carve-out: a checkout of a pre-manifest vintage (no
  `SHA256SUMS` in the tree) heals a missing file without verification
  and without a message — local trust, see the code comments in
  `management/update.sh`.
- Refs without a manifest (tags older than the mechanism) fail closed
  under new code with a named error. Streaming an *old* tag's own
  `install.sh` keeps working as before: that script predates the
  mechanism entirely.
- Maintainer side: the manifest is regenerated with `make sums` and
  committed; the unit suite's freshness pin reddens on a stale manifest
  and `make release` refuses to cut a release from one.
- Maintainer side, entry checksums (issue #492): README and Getting
  started carry the verified-install hash for the `stable` bytes. It is
  rewritten by `make release-sums` — **release PR only**: a mid-cycle
  regen would publish a hash for bytes `stable` does not serve yet
  (users' verification would fail falsely until the release). Mid-cycle
  waves touching `files/install.sh` owe nothing here; `make release`
  pre-flights the block's freshness and refuses a stale one.

## Known residual gaps

- **Bash-spawned reads** (`cat .env`) are only caught by the template's
  lexical ask-tripwires, never by the OS.
- **Git diff drivers render denied files:** `git diff *` and `git log *`
  are allowlisted, and the agent can write `.gitattributes` itself
  (`*.env diff=secret`). A planted `[diff "secret"] command = cat` driver
  then makes `git log -p` render denied file content, and the command
  text names no protected file, so no bash tripwire fires. The
  `.git/config`-planted arm is closed OS-side by the `.git` heal (above)
  — the agent can no longer write a local driver registration, whatever
  the git-config toggle says (a default install renders them active; `opk
  config git-config off` disables them — soft-only either way). The
  remaining arm is the agent's global gitconfig (kit-created
  for `safe.directory`, matched by no template rule): `git config
  --global diff.secret.command cat` hits no allow and no tripwire and
  persists across sessions for every repo — but it only affects the
  AGENT's own git runs, never the developer's.
- **Git execution in agent-controlled gitdirs (the `.git` heal's main
  residual):** the heal protects the developer's git in the shared
  main checkout; wherever the agent controls the gitdir, its
  protection is absent or moot:
  - an **agent-created worktree** keeps an agent-writable `.git`
    pointer *file* in its tree — delete+recreate repoints git at any
    gitdir the agent chooses, and the config and hooks there execute
    as whoever runs git in that worktree (the developer, if they cd
    into it; `opk git-heal on` bypasses those repo hooks for the
    developer via the global `core.hooksPath`, but the opt-in is off
    by default and the repointed gitdir's config arms stay armed).
    Rule: the developer works in the protected main checkout, not in
    agent worktrees (the agent's own worktree use is the designed
    fallback while the git heal hooks are off).
  - an **agent-owned tree as a whole** (a root the agent created):
    the heal pins to the tree's owner — it buys nothing there.
  - **state created between heal runs:** the heal re-runs with the
    group baseline (install, `opk config projects add`/`refresh`,
    `opk update --refresh`, and every stamp-invalidated plain
    `opk update`) — a worktree registration created after
    the last run keeps agent-owned `gitdir`/`commondir` pointer files
    until the next. The git heal hooks do not close this either:
    they re-pin only the measured operand set inside a validated
    gitdir; worktree registrations stay agent-manageable by design.
  - **content planted before the heal** survives metadata pinning (a
    planted hook keeps its exec bit and contents; the heal warns
    about non-sample entries in `hooks/` — removal stays a human
    decision), and a symlinked `modules` container is never followed
    (warned, not healed).

  What the heal closes repo-side can still be armed in the agent's
  own global gitconfig — scoped to the agent's own runs (the
  diff-driver bullet above). Issue
  [#653](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/653)
  tracks report-only detection (heal drift, planted hooks) for `opk
  status`/`opk doctor`; the first row of that surface shipped with
  #703 — both commands flag a project whose `.git` directory owner
  differs from the project directory's owner (the cheap
  wholesale-swap detector, see below).
- **Wholesale swap of `.git` or a whole project dir (W1/W2 — the
  #703 trade):** with the top-folder sticky bits removed (decision
  [#702](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/702)),
  the agent can again rename/unlink developer-owned TOP-LEVEL entries
  on the group-writable project root. The #644 execution impact
  returns with the stealth variants:
  - **W1 — stealth `.git` swap:** `cp -a .git .git.new`, edit the
    copy's `config`/`hooks` (agent-owned), `mv .git .git.old && mv
    .git.new .git`. The repo keeps working, so the developer's next
    `git status`/commit executes the planted hook or fsmonitor arm
    as the developer. The sticky never blocked the copy — only the
    final rename — and no pin inside `.git` survives the gitdir being
    swapped wholesale.
  - **W2 — project-dir swap at depth:** `mv <project> <project>.old &&
    mkdir <project>` (or the stealth copy variant) in a grouping dir
    — same class one level up.
  - **W3 — rename/unlink of developer-owned top-level entries** by
    the agent: marginal elevation only (the soft model already
    grants content overwrite via group write; git-tracked files are
    recoverable). Real loss surface: developer-owned *untracked*
    top-level files become silently deletable.
  Why the trade is still right: the sticky's documented costs were
  the dominant, everyday failure classes, each reproduced live
  (issues
  [#699](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/699),
  [#682](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/682),
  [#701](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/701),
  [#697](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/697)),
  while W1–W3 need a deliberately malicious agent. Compensating
  controls and dead ends:
  - **Detection (#703, shipped):** `opk status` and `opk doctor`
    flag `owner(.git) != owner(project dir)` per project. That
    catches the canonical W1 shape — the cp-a-copy-and-swap arm,
    where the swapped-in `.git` under a developer-owned project dir
    is owned by the swapper (a cross-project rename of a
    developer-owned `.git` evades the row: rename preserves
    ownership, owners stay equal). It does **not** catch the W2
    variants: the stealth project-dir swap leaves dir and `.git`
    both agent-owned (owners equal, row quiet), and the
    move-original variant keeps a developer-owned `.git` inside the
    renamed dir — for W2 the row is no control at all. Display-only,
    after the fact; run `opk status` regularly. (An agent-cloned
    repo under a developer-owned tree trips the same row — inspect,
    then trust.)
  - **`fs.protected_regular` is irrelevant here:** it gates
    O_CREAT opens, never renames — no sysctl value mitigates W1–W3.
    The kit ships at the Ubuntu/WSL default (`=2`); the `=1`
    hotfix once briefed for #699 is obsolete and may be reverted
    (remove `/etc/sysctl.d/99-protected-regular.conf` if you wrote
    it — the kit never writes it).
  - **A global `core.hooksPath = /dev/null` does NOT defend W1:**
    repo config overrides the global — `core.hooksPath` is not
    protected config (established in issue #644). Do not "fix" it
    this way.
  - **The complete closure remains a separate agent-owned clone**
    with developer-side fetch+review — a workflow change, out of
    scope for the kit's shared-tree model.
- **Nuisance arms of the shared `.git` (DoS-grade, no code
  execution):** the heal keeps `.git` itself group-writable — the
  agent's git must keep creating lockfiles, objects and refs — and
  the sticky bit blocks replacing developer-owned entries, not
  creating new ones. So the agent can still plant a stale
  `config.lock` (every config write then fails with `File exists`
  until it is removed) and junk top-level entries in `.git` (git
  ignores unknown names). Both are trivially removed by the directory
  owner; neither executes anything.
- **Git execution — pre-heal context and the complete closure:** the
  soft layer alone never closed this. Its tripwires match command
  text, so `cd .git && mv config-evil config` renamed a planted
  config into place naming nothing protected — and live probes (issue
  [#644](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/644))
  showed agent-planted hooks executing as the developer uid (groups
  including `sudo` and `docker`, `~/.ssh` readable). The heal — the
  baseline plus the opt-in git heal hooks — closes the shared-tree
  arms OS-side at accepted workflow costs (repo-scope `git config`
  and `git submodule add` fail for the agent, the first `push -u`
  tracking-write cost, the gc/packed-refs nuance; listed with the
  heal above). The one *complete* closure remains a separate agent
  clone — a workflow change, the conclusion of the upstream
  ddev.com discussion referenced in issue #644.
- **Bind-mounted containers** read the mounted tree freely (they run as the
  opencode host UID).
- **Renamed copies** of secrets are invisible to the name-based
  [leak scan](../how-to/customize-deny-list.md).
- **Handover symlink swaps:** the root-run `.ddev` handover and the ddev
  settings-dir pairs re-test every path component immediately before
  acting, but the gates are not atomic — a swap in the short window
  between a gate and its recursive pair stays undetected.
- **Dev-owned flag write (accepted race):** the dev-owned flag write into
  `.ddev/config.yaml` screens for symlinks but is not atomic — dev-owned
  mode's flag-write TOCTOU stays accepted. Its ceiling depends on the
  caller: the opencode-uid path (`ddev-as-opencode`) caps the effect at
  opencode privilege, while the root-run scan (install/update/
  `opk config` handovers) performs the same write as root, where that
  cap does not apply (see [ddev integration](ddev-integration.md)).
- **TMPDIR-rooted scratch re-open windows:** the root-run passes stage
  their work in `${TMPDIR:-/tmp}` and re-open staged files by name —
  the fs-baseline worker and uninstall's chown revert re-read their
  operand streams, the sudoers deploy installs a staged copy of the
  file visudo validated a moment earlier, and a streamed install later
  sources its whole verified fetch tree as the script directory. Under
  the defaults (sticky `/tmp`, `0600` temps, sudo `env_reset` — the
  sudoers template keeps no `TMPDIR`) those windows are benign; arming
  them takes an operator who points `TMPDIR` into an agent-writable,
  non-sticky directory before running the kit (`sudo -E`, `sudo env
  TMPDIR=…`). Uninstall's revert is the sharp edge: it runs as the
  developer with an inner `sudo`, so a dev-shell `TMPDIR` inside a
  group-writable project tree arms that site without `sudo -E`.
- The kit protects **locations, not information flows** — once content
  leaves the project roots, no scan recaptures it.
- **mkcert CA key in the agent's home (deliberate):** ddev signs its
  `*.ddev.site` certificates on the host, as the user running ddev — and
  that user is `opencode`. Install copies the CA (including the private
  key, mode `0600`) into `/home/opencode/.local/share/mkcert`; without a
  readable key ddev silently degrades to HTTP-only URLs. Residual risk: the
  agent user can mint leaf certificates your browsers trust (a TLS-MITM
  capability). The keyless alternative is ddev's `.ddev/custom_certs/`
  flow, at the cost of per-project manual provisioning.
- **Supply chain (trust assumption):** install and update stream kit files
  and the opencode binary over HTTPS. Kit files carry SHA256SUMS
  integrity verification ([above](#download-integrity-sha256sums)) —
  corruption detection, not origin-compromise protection. The opencode
  binary is still verified only by a liveness check (`opencode --version`
  runs, not an integrity check), and rootless backend provisioning runs
  get.docker.com as root. Installing means trusting GitHub, the opencode
  releases, the npm registry and `opencode.ai/v2/install` (2.x binary
  resolution and the optional root-run installer fallback), and
  get.docker.com at install time. The `KIT_BASE_URL` env
  override replaces the fetch target entirely — treat the install
  environment as trusted.
- **Developer-shell `DOCKER_HOST` rides env_keep:** the sudoers template
  keeps `DOCKER_HOST`/`XDG_RUNTIME_DIR` into the agent session, but the
  wrapper pins its own values only in the socket-resolving arms —
  docker-rootless, and podman-rootless with `OPENCODE_PODMAN_SOCKET`
  configured — while the podman-CLI, unreachable-socket and no-backend
  arms export nothing, so a `DOCKER_HOST` set in the developer's shell
  survives `env_reset` and overrides the socket pinning recorded in
  `install.conf`; one naming a root-equivalent socket quietly breaks
  "Containers ≠ root" for that session. Only the developer's own
  environment arms it — unset `DOCKER_HOST` before starting `opencode`
  if your shell carries one.
- **OpenChamber serve password in the agent env:** when the serve feature is
  configured, `OPENCODE_SERVER_PASSWORD` (and username) survive sudo's
  `env_reset` into the agent's environment. Not a privilege escalation — but
  pick a strong password.
- **Agent-authored container opt-in:** the per-project container-tools
  opt-in is designed as project-owner consent, but the wrapper's probe
  cannot tell an owner-written `./opencode.jsonc` from one the agent
  wrote itself (the template's edit rules allow `*`): a
  `"docker *": "allow"` entry the agent writes flips the probe to
  "enabled by this project" without any prompt — only a note prints.
  Bounded by the rootless, agent-UID backend: the opt-in changes which
  tools run, not whose privileges they run with.
- **Checkout-first `opk` runs checkout code as root:** `opk` resolves its
  library relative to its own path, so an `opk` (or management script)
  invoked from a checkout executes that checkout's code — with root
  privileges via internal sudo for the elevating subcommands (`opk
  config`, `opk update` run `exec sudo sh` when the caller is not
  root) or a leading `sudo` for direct script calls, while `opk
  status`, `opk doctor` and unsudoed direct calls stay the invoking
  uid (still checkout code). On kit-managed machines the checkout is
  agent-group-writable, so an agent session could have planted
  content in `files/`. Deliberate design ("checkout-first by
  construction" — the developer's own sudo password is the gate where
  root is involved); see the repository's CONTRIBUTING.md for the
  contributor-side warning.

## WSL2: the /mnt/c exposure

`C:` is mounted with the Windows session token — NTFS ACLs do not
distinguish WSL users, so with the default world-readable mount **every WSL
user (including the agent's) can read the whole Windows profile** (`.ssh/`,
`NTUSER.DAT`, browser data). The kit's UID separation only covers the Linux
side.

The kit reports the exposure in `opk status` and warns on every `opencode`
start until it is fixed. Manual fix via `/etc/wsl.conf` (the kit never edits
that file itself):

```ini
[automount]
enabled = true
options = "uid=1000,gid=1000,dmask=027,fmask=037"
```

Replace `uid`/`gid` with your default WSL user's values (check with
`id -u` / `id -g`): the goal is that the agent user ends up as "other", with
no bits.

> **After editing, restart WSL completely:** run `wsl --shutdown` from
> Windows, then reopen your WSL terminal — the mount options only take
> effect on a fresh WSL start.

## WSL2: the browser bridge

Device logins (`opencode console login` on 1.x, `opencode auth login` on 2.x)
open their verification URL through powershell.exe — which the `opencode`
user may not execute on a restricted mount. The kit keeps the login alive
without granting the agent anything:

- `sudo opk wsl-add-opencode-1-fix` — the only kit command that ever writes
  `/etc/wsl.conf` — places a kit-managed comment block at the top of the
  file. Its carrier line (a `#` comment) wins the bundled `open` package's
  scan, so the powershell lookup resolves into the kit library. Takes effect
  immediately; WSL itself only ever sees comments.
- There, `powershell.exe` is a harmless stand-in (`bin/browser-bridge`): it
  forwards to the real powershell.exe whenever the caller may execute it
  (you — the browser opens exactly as before) and exits 0 otherwise (the
  agent — the login keeps polling; open the printed URL in any browser).

Newer opencode versions (1.x ≥ 1.18.33, 2.x ≥ 2.0.18) bundle an opener that
access-checks powershell and falls back to `xdg-open` — no bridge needed.
Because WSL distros ship no `xdg-open` by default, the kit deploys a fallback
shim at `/usr/local/bin/xdg-open` (only while no real one exists;
`sudo apt install xdg-utils` works too) and only while the installed
opencode still needs it — opencode ≥ 2.0.32 opens without one itself, so
on current 2.x the kit withholds the shim (1.x never got the upstream fix
and always keeps it).

`opk status` reports the bridge state; the wrapper warns on every start while
the carrier is missing. `OPK_BROWSER_BRIDGE_DEBUG=1` before a direct
invocation traces the decision. Uninstall asks before removing the block and
always removes the stand-in tree and the shim symlink.

## Other root-equivalent surfaces (audit)

Docker is not the only tool whose daemon socket means root. `opk status`
ships a **report-only audit** ("Root-equivalent access" section) that checks
these surfaces for agent reachability — the kit never changes them; removing
access is an admin decision:

| Surface | Why it matters | Default on WSL2 |
|---|---|---|
| Rootful docker socket (`/var/run/docker.sock`) / `docker` group | full root, classic escape | common on dev hosts |
| Docker/Rancher Desktop sockets under `/mnt/wsl` | root-equivalent, world-usable | present when integration is on |
| `containerd` socket | full root | root-only by default |
| LXD/LXC, libvirt (`lxd`, `libvirt` groups + sockets) | full root (host VMs/mounts) | not installed by default |
| `sudo`/`admin`/`wheel`/`disk`/`snap` groups for the agent user | full root | never granted by the kit |
| `wireshark`/`adm`/`systemd-journal` groups | not root, but can leak credentials | not granted by the kit |
| Windows interop (executing `.exe` via `/mnt/c`) | runs code as Windows user | blocked via the `/mnt/c` restriction |

Deliberately **not** flagged: `snapd`'s socket (gated by peer credentials)
and `newuidmap`/`newgidmap` (setuid, but bounded to `/etc/subuid` ranges —
required by the rootless backends). The audit is stat math only — no
privileged probes. Override the socket list with `ROOT_EQUIV_SOCKS="…"`.
