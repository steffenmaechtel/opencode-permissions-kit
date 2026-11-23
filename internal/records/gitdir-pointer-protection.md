# .git as a nailed pointer file — closing the wholesale arm without sticky (O4)

> Status: **IMPLEMENTED** (the #704 implementation wave, PR #754;
> follow-ups to date PR #760, PR #761 and PR #765; shipped behavior:
> [the how-to](../../docs/how-to/git-protection.md); record upkeep
> tracked in #722). Phase A measured green 2026-11-21; a prototype soak
> on the maintainer host (branch `feature/tmp-git-protection`)
> preceded the wave. This record is
> the durable in-repo summary of the O4 mechanics, the measured facts
> and the agreed design; the full timeline (phase-A verdict, design
> record, harness artifact, final run log) lives in issue #704. It
> builds directly on [root-sticky-removal.md](root-sticky-removal.md)
> (the #702 decision whose reopened W1/W2 arms this closes) and
> relocates the [git-heal contract](../../docs/how-to/git-heal-hooks.md)
> (#651/#671/#678) onto the storage gitdirs.

## 1. The question

The #702 decision removed the project-root/ancestor stickies (their
everyday failure classes dominated) and accepted the reopened wholesale
arms: with group-write on the project top and no sticky, the agent can
`mv .git` away, replace it (`mv own-copy .git`), or run the full
`rm + mkdir` chain — W1/W2 in #702's evaluation. POSIX offers no
per-entry rename protection (sticky is always whole-directory; the
option research in #702 ruled out sysctls, AppArmor, BPF-LSM on this
host). The two remaining per-entry "nails" are a mountpoint (EBUSY)
and the **immutable inode flag** — and the flag only works on a FILE,
because `chattr +i` on a directory freezes its entry list (no git
writes inside → git dies). Hence O4: make `.git` a file worth nailing.

## 2. The mechanism (three parts)

1. **`.git` becomes a pointer file** — one line, `gitdir:
   /abs/storage/path`, the native worktree/submodule form (the
   `repo-kasantra` checkout already lives this way). Git resolves it
   transparently; **git never writes the pointer** in any normal
   operation (measured: inode+content+attr identical across
   commit/switch/fetch/merge/push batteries in all states).
2. **The real gitdir moves into an external storage** — dev-owned,
   group `opencode` rwx, mode 3770 (sticky+setgid), OUTSIDE every
   shared tree. Sticky there costs nothing: no daily workflow renames
   anything in the storage (git only creates files and renames its
   OWN lockfiles — always allowed). Constraint: the storage's PARENT
   must not be group-writable, else the agent moves the whole storage
   aside (measured w11). Default location: sibling of the first
   projects.conf scan root (`/var/www/vhosts` → `/var/www/gitdirs`),
   overridable via `GITDIR_STORAGE` in install.conf.
3. **The pointer is nailed with `chattr +i`** (ext4 inode attribute,
   NOT a POSIX permission): no write-open (O_TRUNC/O_APPEND), no
   unlink, no rename, no rename-over-target, no hardlink — for EVERY
   actor (file owner, dir owner, group, even root without a prior
   `chattr -i`). Only CAP_LINUX_IMMUTABLE (root) can set or clear the
   flag; `chattr` as a non-root user is EPERM (measured p10 — the
   install-time requirement). The flag lives in the inode: survives
   reboots, but is filesystem-dependent (ext4/xfs yes; drvfs/9p no —
   Leg P's fstype gate) and NOT recursive.

Key contrast to rwx/sticky: those regulate *who* may act (ownership
logic, always a dir-owner exemption); immutable switches off the
*what* — category-level, ownership-blind. That is exactly the nail
POSIX does not otherwise offer, applied to the one file nobody ever
needs to write.

## 3. Measured facts (Phase A, harness `local/o4-gitdir-storage-704/`)

v3 final run `run-20261121-194042.log`: **283 PASS / 0 UNEXPECTED /
10 SKIP** across sysctl 1/2 × immutable on/off, expectations DERIVED
from the kernel rules (the run co-verifies them). Fixture: shared-tree
surrogate (no top sticky — the #702 target state), external sticky
storage, three project shapes (dev-owned migration form, bare+
worktree fresh form, root-migrated agent-owned form).

- **W1/W2 closed under imm=on in BOTH sysctl values**: `mv .git`,
  rename-over, `rm`, append, `sed -i`, the full rm+mkdir chain,
  hardlink — all EPERM, including in the agent-owned project top (the
  old a6 always-open case) and against root's own `rm`. The agent
  cannot `chattr -i` (no CAP). imm=off contrast: every attack
  succeeds — the #702 reopening measurement reproduced 1:1.
- **Storage dicht**: gitdir-entry mv, `config` mv, whole-storage mv
  all blocked (sticky + non-group-write parent); planting an extra
  dir in the storage is possible and harmless (discovery walks
  pointers).
- **Functionality**: both actors commit/switch/checkout/fetch/merge/
  push in all states; tooling smoke (npm, rev-parse, project-top mv
  with an immutable file inside — parent rename is NOT blocked —
  absolute pointer keeps working) green.

## 4. Findings beyond the questions (each rule-conform, all PASS)

1. **dev `git status` steals the index — unhookable.** An unflagged
   dev status opportunistically rewrites the index (racy-clean/ctime)
   and flips it dev-owned; the next agent write op fails. The #671
   class over a READ path — there is no post-status hook. Applies to
   the CURRENT in-tree design as well. Mitigation: read-only statuses
   run with `--no-optional-locks` / `GIT_OPTIONAL_LOCKS=0`.
2. **COMMIT_EDITMSG is config-class, not operand.** git never chowns
   it (O_TRUNC writes in place); dev-owned, the dir-owner exemption
   opens it for BOTH actors under `fs.protected_regular=2`, while an
   agent-created one blocks the dev commit under `=2`. The relocated
   heal pins it dev (like `config`/`hooks`), never agent.
3. **`git worktree remove` over a nailed pointer is a partial
   remove**: the registration is deleted first, the dir delete EPERMs
   at the pointer, a second attempt says "is not a working tree".
   Remedy: `sudo chattr -i` + `rm -rf <wt>` + `git worktree prune`.

## 5. The agreed design (for the implementation wave)

- Command surface `opk git-protection on|off|status|adopt <path>|
  nail|revert` (umbrella like `opk git-heal`); status unprivileged.
- Consent question at first `opk update` (nothing silent on user
  trees); per-project ATOMIC migration with verify + rollback and a
  `worktree repair` pass; `revert` is a mandatory escape hatch.
- Layout conversion (root, feature-gated) and operand heal (git-heal
  hooks, opt-in) stay separate; without hooks the agent locks out
  after dev commits — same as today, no regression.
- New-clone adoption: echo hint inside the kit's git-heal post-*
  hooks (they already run per dev checkout/clone via core.hooksPath,
  already read projects.conf; the hint self-silences once `.git` is a
  pointer) — NOT a git template hook (no post-clone hook exists; the
  post-checkout template trick is global for every user and cannot
  `chattr +i` at clone time anyway).
- git-heal integration: hook fast path and `heal-index-head`'s reader
  gate accept gitdirs under the storage root (through the same
  `_gh_root_ok` discipline); no sudoers change (the grant stays
  path-gated to the heal script).
- Nail before sealing re-checks the pointer target (inside storage +
  dev-owned) — a hand-planted pointer never gets sealed.

## 6. Where the artifacts live

- Issue #704: phase-A verdict comment, design record comment, harness
  artifact (README + run.sh v3), final v3 run log.
- Maintainer-local scratch (disposable): `local/o4-gitdir-storage-704/`
  (v1→v3 logs included).
- Prototype branch `feature/tmp-git-protection` (no PR, the #702
  tmp-branch pattern): `sh/git-protection-core.sh`, git-heal hook
  fast-path + hint, `heal-index-head` storage gate, deploy lists —
  deliberately without pins/tests; the follow-up wave owns them.
