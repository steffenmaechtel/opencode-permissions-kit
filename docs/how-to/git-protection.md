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
/var/www/gitdirs/<folder>-<name>.git` — into an external, developer-owned,
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
opk git-protection status       # per project: classic | nailed | unnailed |
                                #   foreign-pointer | worktree-reg, plus INFO
                                #   rows for unreferenced storage entries
sudo opk git-protection adopt /var/www/vhosts/myproj   # migrate + nail ONE
sudo opk git-protection nail    # nail pending pointers (the root pass)
sudo opk git-protection revert --all   # walk back to the classic layout
sudo opk git-protection off     # revert --all + drop the storage config
```

`status` exits non-zero when an actionable row exists (a classic
`.git`, or an unnailed pointer) — cron-friendly without parsing. Every
actionable row names the command that helps right now: a classic
project carries `sudo opk git-protection adopt <path>` (two or more
add the one-run hint `sudo opk git-protection on`; before the storage
is set up the rows name `on` instead — `adopt` refuses without one),
an unnailed pointer carries `sudo opk git-protection nail <path>`.
Paste the command as printed: a path that is not plain is
single-quoted there. A project path the migration gates refuse
(whitespace, a glob character, a dot segment) gets no command but the
rename hint — `adopt` would refuse it. The
remaining row kinds are informational: `foreign-pointer` (a
pointer to somewhere else — every linked worktree of a not-yet-migrated
project shows this shape) and `worktree-reg` (a `.git` directory
without the gitdir payload — a worktree registration or similar).
A project path carrying a control character renders its row key with
that byte masked (`a?b`) on every row kind — the raw byte never
reaches the terminal (#756).

The project enumeration itself is newline-safe (#756): a `.git`
under a path containing a newline is skipped with a loud stderr note
(its row could not be represented, and the form gates would refuse
the path anyway) — it never yields a garbage row, and it never
blocks enumeration of the other projects. The sweep requires
`python3` for this (the NUL-separated reader); a host without it
refuses to enumerate at all rather than degrade silently (on
`opk status --short` that note is muted with every other detail
line — run the full `opk git-protection status` to see it).

### Unreferenced storage entries

A storage entry that no pointer under your configured roots targets
any more — a project removed without `revert`, a leftover from an
earlier pilot — renders as an INFO row on both report surfaces naming
the entry and the manual removal: inspect it, then
`sudo rm -rf /var/www/gitdirs/<entry>` (a name that is not plain is
single-quoted in that command; a name carrying a control character
gets no command — inspect it by hand). INFO
on purpose: an unreferenced entry is harmless (nothing follows it) and
the removal is your call. "Unreferenced" is measured against the
configured roots only — a project adopted outside them, or under a
root you since removed from `projects.conf`, still uses its entry.

### Consent: update asks once

`opk update` asks before configuring the storage the first time (the
kit never silently rewrites your trees). Declining persists
`GITDIR_STORAGE=none` in `install.conf` — the question never returns,
and `sudo opk git-protection on` stays one command away: the command
replaces the decline marker (no default storage derivable from your
`projects.conf` roots, it names the line to edit instead). Unattended
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

Per project, atomic with rollback: `.git` moves into the storage under
a self-describing name — `<folder>-<name>.git`, so
`/var/www/vhosts/myorg/myproj` becomes `myorg-myproj.git` and two
checkouts that share a name (a project and a worktree of the same
repository) no longer collide. A project directly under a
`projects.conf` root keeps its plain basename (`documents.git`); a
composed name too long for the filesystem falls back to the basename
too. A name that is already taken gets `-2`, `-3`… — the belt for two
same-named projects in one folder. Projects migrated before this rule
keep their basename-only names: renaming a nailed pointer is the
`chattr -i` dance for no protection gain. The relocated
[#651 heal](../concepts/security-model.md) normalizes the stored gitdir
(config/hooks developer-owned, operand set agent-owned — with
`COMMIT_EDITMSG` pinned developer-side, the Phase A finding: git only
rewrites it in place, and an agent-pinned one blocks the developer
commit under `fs.protected_regular=2`), the pointer file is written
and nailed, registered worktrees follow via `git worktree repair`,
and the result is verified (`git status`) before the next project
starts. A failed project rolls back to the classic layout and the
run continues; nothing is ever half-migrated.

New clones: git runs no hook at clone time, so the kit's
[git-heal hooks](git-heal-hooks.md) print a two-line adopt hint on
your first checkout or switch inside a managed root with a classic
`.git` (echo only, never blocks; needs `opk git-heal on`; silenced
once adopted or declined — a clone you never check out in stays
unhinted until you do). `opk git-protection status` detects the same
state without any hooks.

## Friction you should know about (measured)

- `chattr ±i` needs root: installing/nailing happens as root anyway;
  your own restructuring of `.git` itself needs the `sudo chattr -i`
  dance. Removing a project is `sudo opk git-protection revert
  <path>`.
- The group baseline (install, `opk config refresh`, `opk update
  --refresh`) skips nailed pointers: `chattr +i` refuses `chgrp`/
  `chmod` even for root, which used to fail the whole refresh on
  pointer projects — and a pointer the kit sealed already ships
  `<developer>:opencode 664`, so the skip loses nothing there. A
  pointer re-nailed by hand or carried sealed from an older kit
  keeps its drifted state: the seal blocks `chgrp`/`chmod` for
  everyone, and nothing reports the drift (issue #758).
- `opk handover <me|opencode> <tree>` over a tree with a sealed
  pointer used to fail wholesale (`chown -R`/`chmod` hit `EPERM` on
  the sealed file, reason masked): both walks skip sealed pointers
  now and `--dry-run` announces them (issue #759). The pointer stays
  `<developer>:opencode 664` through any handover — by design.
- `git worktree remove` over a nailed pointer ends in a partial
  remove (the registration goes, the directory delete hits `EPERM`):
  finish with `sudo chattr -i <worktree>/.git && sudo rm -rf
  <worktree> && git worktree prune`. The next `opk git-protection
  status` run shows nothing pending. Worktree pointer files themselves
  are deliberately NEVER nailed by the kit's sweeps (a sealed pointer
  would block the main project's repair on revert) — hosts that ran a
  pre-fix `on` may still carry sealed worktree pointers: a one-time
  `sudo chattr -i <worktree>/.git` restores repairability.
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

`opk status` reports the state in its `Git protection` section, from
the same rows as `opk git-protection status`. While git-protection is
enabled, that is an `ON` state row — with the number of protected
projects, or saying that none is protected yet — plus one row per
deviation with its command: a classic project counts as an alert, an
unnailed pointer as a warning. Unreferenced storage entries are listed
here too, as INFO rows. If the storage directory is gone, a warning
replaces the state row and the rows name `on`. While it is not
enabled (never configured, or declined), the
section is one warning naming `sudo opk git-protection on`: the
wholesale swap stays possible for every project until the feature is
turned on, so — unlike an optional feature that is simply off — that
state counts.

`off` reverts first and drops `GITDIR_STORAGE` only when every
revert succeeded AND nothing was skipped as not kit-owned (orphaned
pointers could never be recognized again); when pointer projects
exist without a resolvable storage, or rows were skipped, it refuses
loudly and keeps the config as the locator. Linked worktrees of a
migrated project are repaired by their MAIN project's revert — a
worktree registration is never moved itself. The storage directory
itself stays — remove it manually once empty. `opk uninstall` offers
the same revert before the library goes; a declined revert lands in
its manual-cleanup list (the pointer layout keeps working without
the kit — it is plain git).

## Limits

- The agent can still plant additional directories inside the storage
  (harmless — nothing follows them: the kit walks pointers, not the
  storage). Both report surfaces list such entries as unreferenced
  (`opk git-protection status` and the `opk status` section).
- Filesystems without `chattr` support degrade loudly: migrations
  succeed, the nail warns and `status` reports `unnailed` — degraded,
  not protected.
- The operand heal stays the separate opt-in it is
  ([git-heal hooks](git-heal-hooks.md)); the two features compose
  (the heal hooks accept gitdirs under the storage) but neither
  requires the other.
