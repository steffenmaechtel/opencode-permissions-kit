# Keep the agent's git workflow green (git heal hooks)

Enable the heal hooks that stop developer git operations from locking
the agent out of the shared main checkout.

## The problem this solves

The [`.git` heal](../concepts/security-model.md) pins `.git/config` and
`.git/hooks` developer-owned under a sticky `.git` — but `.git/index`
and `.git/HEAD` must stay writable by both sides, and git rewrites both
files through lock+rename: whichever user last ran a rewriting git
operation owns them. After a developer checkout or pull the files are
developer-owned, and the sticky bit then blocks the agent from ever
writing them again — `git add` dies with `fatal: unable to write new
index file`, `git switch` with `error: couldn't set 'HEAD'`. The lockout
persists until someone with root re-owns the files (issue
[#671](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/671)).

## The fix: heal hooks on the developer side

```bash
sudo opk git-heal on
```

This is opt-in and idempotent; install and update never activate it.
`on` does three things:

1. Re-renders the sudoers file (the narrow root-heal grant ships in the
   kit's sudoers template — this also closes the gap on a kit installed
   before #671).
2. Sets **your** global `core.hooksPath` to the kit-owned hook
   directory (`/usr/local/lib/opencode-permissions-kit/git-heal/hooks`).
   Side effect, deliberate: repository hooks stop executing for your
   user everywhere — the same protective effect as the
   `core.hooksPath /dev/null` form documented in
   [secure git config](secure-git-config.md), plus the heal. Project
   hook tooling (husky, pre-commit) stops working for you; on a kit
   machine that trade is usually right.
3. Heals every kit-managed main checkout once, immediately.

From then on four identical hooks — `post-merge`, `post-checkout`,
`post-rewrite`, `post-index-change` — run after your git operations in
every repository your user touches, and for kit-managed roots they
re-pin `index`/`HEAD` to the agent user via the root heal. Outside
kit-managed roots they are silent no-ops (no sudo call, no output).
They never fail your git operation: if the heal cannot run (sudo
unavailable), you get one stderr line and the operation completes.

The carrier set is measured, not assumed: `post-index-change` fires on
every index write — mutating commands (`add`, `reset`, `read-tree`) and
refreshing `git status` runs on a stale cache (IDE refreshes while the
agent edits) alike — but not on a fresh-cache status that writes
nothing, which is exactly the case where nothing flipped. Pull/merge
(including fast-forward) rides `post-merge`; checkouts and switches
ride `post-checkout`. There is no `post-reset` hook in git;
`post-index-change` covers that whole family.

## Turn it off, inspect it

```bash
sudo opk git-heal off      # unsets core.hooksPath — only if it holds
                           # the kit's value; a foreign value is never
                           # touched
sudo opk git-heal status   # state, kit pieces, per-root lockout risks
```

`opk status` reports the same state as a `Git heal hooks` section, and
`opk doctor` shows a per-project `git-heal` row classifying the current
lockout risk. `opk uninstall` unsets the kit-owned `core.hooksPath`
before removing the library (a dangling path would break your git).

## What the root heal may and may not do

The heal script runs as root (the sudoers grant names exactly this one
path) but is narrow by construction: it only accepts a gitdir under a
kit-managed project root (`projects.conf`), re-checks the real path
after symlink resolution, verifies the gitdir shape (a worktree
registration is rejected), skips symlinked and hardlinked operands, and
changes nothing but the ownership of `index` and `HEAD`. Every run
appends one audit line to
`/usr/local/lib/opencode-permissions-kit/git-heal/heal.log`.

## Limits

- Worktrees the agent created are unaffected (their gitdirs stay
  agent-manageable by heal design) — worktree use stays optional, not
  required.
- The heal re-pins ownership only; it does not touch file contents.
- If you share the machine with more than one developer user, each who
  wants the protection runs `opk git-heal on` for their own global
  gitconfig.
