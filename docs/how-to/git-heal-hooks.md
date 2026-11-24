# Keep the agent's git workflow green (git heal hooks)

Enable the heal hooks that stop developer git operations from locking
the agent out of the shared main checkout.

## The problem this solves

The [`.git` heal](../concepts/security-model.md) pins `.git/config` and
`.git/hooks` developer-owned under a sticky `.git` — but the agent's
workflow metadata must stay writable by both sides, and git rewrites
those files through lock+rename: whichever user last ran a rewriting git
operation owns them. After a developer checkout or pull `.git/index`
and `.git/HEAD` are developer-owned, and the sticky bit then blocks the
agent from ever writing them again — `git add` dies with `fatal: unable
to write new index file`, `git switch` with `error: couldn't set 'HEAD'`
— and after a developer merge/pull/reset/rebase `.git/ORIG_HEAD` is
developer-owned too, killing the agent's merge and pull with
`fatal: update_ref failed for ref 'ORIG_HEAD'` (issue
[#671](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/671),
widened in
[#678](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/678)).
The lockout persists until someone with root re-owns the files.

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
3. Heals every kit-managed main checkout once, immediately. The
   sweep enumerates both `.git` shapes under the configured roots:
   classic directories and pointer files (`gitdir: …`, the
   [pointer layout](git-protection.md)) — a pointer resolves to the
   storage gitdir its operands live in, a linked worktree's pointer
   to its common gitdir (the same target the hooks resolve), and a
   relative (submodule-form) pointer is skipped with a note:
   `.git/modules` is developer-pinned by the baseline and never
   healed. `opk git-heal status` scans the same universe for its
   lockout rows, and so do the `opk status` git-heal section and
   `opk doctor`'s per-project row — they resolve pointer checkouts
   through the same gate and name the resolved storage paths
   (issue
   [#777](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/777)).

From then on four identical hooks — `post-merge`, `post-checkout`,
`post-rewrite`, `post-index-change` — run after your git operations in
every repository your user touches, and for kit-managed roots they
re-pin the measured operand set to the agent user via the root heal.
Outside kit-managed roots they are silent no-ops (no sudo call, no
output). They never fail your git operation: if the heal cannot run
(sudo unavailable), you get one stderr line and the operation completes.

The carrier set is measured, not assumed: `post-index-change` fires on
every index write — mutating commands (`add`, `reset`, `read-tree`) and
refreshing `git status` runs on a stale cache (IDE refreshes while the
agent edits) alike — but not on a fresh-cache status that writes
nothing, which is exactly the case where nothing flipped. Pull/merge
(including fast-forward) rides `post-merge`; checkouts and switches
ride `post-checkout`. There is no `post-reset` hook in git;
`post-index-change` covers that whole family. The #678 measurement
added the conflict-state carriers: the resolution `git add` fires
`post-index-change` with the merge-state set present
(`MERGE_HEAD`/`MERGE_MSG`/`MERGE_MODE`/`AUTO_MERGE`; the per-operation
`CHERRY_PICK_HEAD`/`REVERT_HEAD` ride their own operations' adds),
and mid-rebase steps fire `post-checkout`/`post-index-change` with
`REBASE_HEAD` present. (`post-rewrite` also carries `REBASE_HEAD`,
but only in a conflicted rebase concluded via `--continue` — an
interactive clean rewrite deletes it first, so the mid-rebase fires
are the robust carrier.)

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
kit-managed project root (`projects.conf`), re-validates every conf
line reader-side (a hand-edited system path, scratch prefix or agent
home never authorizes a heal), re-checks the real path
after symlink resolution, verifies the gitdir shape (a worktree
registration is rejected), skips symlinked and hardlinked operands, and
changes nothing but the ownership of the measured operand set —
`index`, `HEAD`, `ORIG_HEAD`, `REBASE_HEAD`, `packed-refs` and the
conflict pseudo-refs (`MERGE_HEAD`, `MERGE_MSG`, `MERGE_MODE`,
`AUTO_MERGE`, `CHERRY_PICK_HEAD`, `REVERT_HEAD`), each only when it
exists. Every healed file appends one audit line to
`/usr/local/lib/opencode-permissions-kit/git-heal/heal.log` — one
line per operand that existed and healed, so a full heal of a
conflict-state repository writes up to eleven.

Deliberately NOT healed (measured in #678, not assumed):
`FETCH_HEAD` and `COMMIT_EDITMSG` are written in place and never flip
ownership; reflogs under `logs/` append into a non-sticky directory;
loose refs live in the non-sticky `refs/` tree; `.git/config` stays
developer-owned as the deliberate #651 pin; and the `rebase-merge/` /
`rebase-apply/` directories are left alone — the agent can always
empty them, only their final `rmdir` needs the sticky `.git`, so an
aborted rebase can leave an empty directory behind (cosmetic litter,
removable by the developer with a plain `rmdir`).

Two timing residuals of the widened set, both bounded by "the next
developer git operation": a conflict state your developer abandons
without staging a resolution is only healed when the next
index-writing developer operation fires a hook (a mere refreshing
`git status` qualifies), and a `packed-refs` flip heals on the same
cadence — agent `gc` in between exits rc 0 with a pack-refs failure
on stderr and no packing done (the exit status stays silent about
the no-pack; no lockout).

## Limits

- Worktrees the agent created are unaffected (their gitdirs stay
  agent-manageable by heal design) — worktree use stays optional, not
  required.
- The heal re-pins ownership only; it does not touch file contents.
- If you share the machine with more than one developer user, each who
  wants the protection runs `opk git-heal on` for their own global
  gitconfig.

## The git-protection companion (#704)

The same hooks carry the adopt hint for the
[pointer layout](git-protection.md): a kit-managed tree whose `.git`
is still a classic directory gets a two-line hint (`run: sudo opk
git-protection adopt <toplevel>`) on checkout — echo only, never
blocking, self-silencing once adopted or declined. The toplevel path
in that command is paste-safe: a path that is not plain (a space, a
shell metacharacter) is single-quoted with `'\''` escaping — paste
the line exactly as printed (#766). A toplevel carrying a control
character gets no command at all, just the rename hint (no quoting
makes such a byte safe on a pasted line).
And when a project
HAS been adopted, its common gitdir lives in the external storage,
outside every `projects.conf` root — the hooks' fast path accepts
gitdirs under the configured storage by plain prefix match (the root
heal's allowlist then re-validates that value through the same reader
gate as conf roots before authorizing anything), so the heal keeps
working unchanged after adoption. The `opk git-heal on` sweep and the
`status` lockout scan reach adopted checkouts the same way: their
`.git` pointer files resolve to the storage gitdirs, and the rows and
audit lines name those resolved paths (issue
[#777](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/777)
— before, both sweeps matched only directory-shaped `.git` and were
blind on a fully adopted host).
