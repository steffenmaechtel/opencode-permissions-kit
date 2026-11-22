# Close the mv .git arm (git-protection pointer layout)

Convert your kit-managed projects to the nailed pointer layout that
stops the agent from swapping `.git` wholesale — without any
top-level sticky bit.

## The problem this solves

The [`.git` heal](../concepts/security-model.md) makes `.git` sticky
and pins its internals — but the directory entry `.git` itself sits in
the project root, which the agent can write: it can move `.git` away
and back (`mv .git .git.p && mv .git.p .git`), replace it via
rename-over, delete and recreate it as its own directory, or poison
the file behind it. That wholesale arm was measured open in the #702
research (W1/W2), closed only by `fs.protected_regular` in parts, and
it reopens whenever the project root itself is agent-writable. POSIX
offers no per-entry "may not rename" bit — which is the whole problem.

## The fix: .git becomes a nailed pointer file

`opk git-protection` converts each project's `.git` **directory** into
a pointer **file** — the worktree/submodule form, `gitdir:
/var/www/gitdirs/<name>.git` — into an external, developer-owned,
sticky storage outside every `projects.conf` root, and nails the
pointer with `chattr +i` (the ext4/xfs immutable inode flag: no
rename, no unlink, no replace, no append — for every actor, root
included, until `chattr -i`). The wholesale arm closes for good:
there is nothing left to move (issue
[#704](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/704),
Phase A measured green; the layout is native git — `repo-kasantra`
on the maintainer host lives this way).

```bash
sudo opk git-protection on      # storage init + persist + migrate ALL + nail
opk git-protection status       # per project: classic | nailed | unnailed (no sudo)
sudo opk git-protection adopt /var/www/vhosts/myproj   # migrate + nail ONE
sudo opk git-protection nail    # nail pending pointers (the root pass)
sudo opk git-protection revert --all   # walk back to the classic layout
sudo opk git-protection off     # revert --all + drop the storage config
```

`status` exits non-zero when an actionable row exists (a classic
`.git`, or an unnailed pointer) — cron-friendly without parsing.

### Consent: update asks once

`opk update` asks before configuring the storage the first time (the
kit never silently rewrites your trees). Declining persists
`GITDIR_STORAGE=none` in `install.conf` — the question never returns,
and `sudo opk git-protection on` stays one command away. Unattended
updates skip the question with a hint; set `KIT_GITDIR_STORAGE=none`
in the environment to silence that too, or to an absolute path to
configure non-interactively.

Once enabled, every `sudo opk update` runs the adopt + nail pass as
root: new classic `.git` layouts under your roots are migrated,
pending pointers get their nail. That recurring pass is the point —
the protection rides the update, no extra command.

### Where the storage lives

Default: a sibling of the first usable `projects.conf` root
(`/var/www/vhosts` → `/var/www/gitdirs`). Override with
`GITDIR_STORAGE=<path>` in `install.conf`. Constraints (measured in
Phase A): the storage is developer-owned, group `opencode`, mode
`3770`; its **parent** must not be group-writable (else the agent
could move the whole storage aside); the filesystem must support
`chattr` (ext4/xfs — not drvfs/9p, i.e. not `/mnt/c` on WSL).

## What the migration does

Per project, atomic with rollback: `.git` moves into the storage
(name collisions get `-2`, `-3`… suffixes), the relocated
[#651 heal](../concepts/security-model.md) normalizes it
(config/hooks developer-owned, operand set agent-owned — with
`COMMIT_EDITMSG` pinned developer-side, the Phase A finding: git only
rewrites it in place, and an agent-pinned one blocks the developer
commit under `fs.protected_regular=2`), the pointer file is written
and nailed, registered worktrees follow via `git worktree repair`,
and the result is verified (`git status`) before the next project
starts. A failed project rolls back to the classic layout and the
run continues; nothing is ever half-migrated.

New clones: git has no post-clone hook, so the kit's
[git-heal hooks](git-heal-hooks.md) print a two-line adopt hint when
you clone or check out inside a managed root with a classic `.git`
(echo only, never blocks; needs `opk git-heal on`; silenced once
adopted or declined). `opk git-protection status` detects the same
state without any hooks.

## Friction you should know about (measured)

- `chattr ±i` needs root: installing/nailing happens as root anyway;
  your own restructuring of `.git` itself needs the `sudo chattr -i`
  dance. Removing a project is `sudo opk git-protection revert
  <path>`.
- `git worktree remove` over a nailed pointer ends in a partial
  remove (the registration goes, the directory delete hits `EPERM`):
  finish with `sudo chattr -i <worktree>/.git && sudo rm -rf
  <worktree> && git worktree prune`. The next `opk git-protection
  status` run shows nothing pending.
- `+i` survives reboots (an inode flag). Removing nailed trees needs
  `chattr -i` first even for root.
- Under `fs.protected_regular=2` a foreign-owned `FETCH_HEAD` can
  block the other actor's first fetch (the `=` `O_CREAT` cell; the
  migration heal deletes `FETCH_HEAD`, whoever fetches first
  recreates it). Same class as the classic layout — documented
  residual, self-healing after one heal or removal.
- An unflagged developer `git status` can opportunistically rewrite
  `.git/index` and flip it developer-owned — the
  [#671 lockout](git-heal-hooks.md) over a read path. Run read-only
  statuses with `git --no-optional-locks status` (or keep the heal
  hooks on, which re-pin on the next write).

## Turn it off, inspect it

```bash
opk git-protection status        # storage + per-project layout state
sudo opk git-protection off      # revert every project + drop the config
```

`off` reverts first and drops `GITDIR_STORAGE` only when every
revert succeeded (orphaned pointers could never be recognized
again). The storage directory itself stays — remove it manually once
empty. `opk uninstall` offers the same revert before the library
goes; a declined revert lands in its manual-cleanup list (the
pointer layout keeps working without the kit — it is plain git).

## Limits

- The agent can still plant additional directories inside the storage
  (harmless — nothing discovers them; the kit walks pointers, not
  the storage).
- Filesystems without `chattr` support degrade loudly: migrations
  succeed, the nail warns and `status` reports `unnailed` — degraded,
  not protected.
- The operand heal stays the separate opt-in it is
  ([git-heal hooks](git-heal-hooks.md)); the two features compose
  (the heal hooks accept gitdirs under the storage) but neither
  requires the other.
