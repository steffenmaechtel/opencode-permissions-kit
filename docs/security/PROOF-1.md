# PROOF-1: Timing of ACL Protection vs. `git pull && cat .env`

> **SUPERSEDED (DDEV-WORKING):** the hard ACL deny layer this document
> analyzes/proposes was **removed** — file permissions are now opencode's
> soft permission layer only. This document is kept as the historical
> analysis record; see `docs/design/DDEV-WORKING.md` for the current model
> and `docs/concepts/security-model.md` for the authoritative
> usage documentation. Where wording differs, the code and the docs win.

**Question under test.** A project repo initially contains no `.env` file. `.env` is a
deny pattern in the kit's `opencode.jsonc` read/edit rules. A second developer commits
a `.env` to the repo. If the AI then runs `git pull && cat .env` inside opencode on the
first developer's machine, could the git hook that re-applies permissions afterwards be
"too late" — i.e. could `cat .env` succeed because the ACL update on the new file takes
time?

## Verdict

For the exact chain `git pull && cat .env`: **no, there is no timing window.**
The hook is synchronous and blocking within `git pull`. However, related scenarios
(see "Real gaps" below) do have windows — most notably hook-less git operations
combined with the mtime cache, and the git object database.

## Why `git pull && cat .env` is safe

1. **The hook runs synchronously *inside* `git pull`.** Git executes `post-merge` as
   the last step of a pull and *waits* for it
   (`files/opencode-permissions-kit-lib/hooks/post-merge:8`).
   `&&` guarantees that `cat` only starts after the pull — including the hook —
   has fully completed. The `sudo` call in the hook is blocking, so "the ACL update
   takes time" does not create a window: nothing else runs concurrently in this
   chain.

2. **The ownership gap is closed inside the hook.** The new `.env` is written by the
   git process running as the `opencode` user, so immediately after the merge it is
   *owned by opencode*. A named ACL entry `u:opencode:---` does **not** apply to the
   file owner (POSIX ACLs: the owner maps to `ACL_USER_OBJ`; named user entries are
   ignored for the owner). This is why `apply_acls()` performs a `chown
   DEFAULT_USER:www-data` after the `setfacl`
   (`files/opencode-permissions-kit-lib/protect-projects.sh:196-201`). Both the deny
   ACL and the ownership transfer happen before `cat` can open the file.

3. **Hook failure aborts the chain.** If sudo or protect-projects fails, the hook
   exits non-zero, the pull exits non-zero, and `cat` never runs (`&&` semantics).

## Real gaps

### a) Background pull (a true race)

```bash
git pull & while [ ! -f .env ]; do :; done; cat .env
```

The file exists as soon as the merge writes it; the hook only runs after the
*complete* worktree update. In that window the file is opencode-owned and readable —
`cat` wins the race. Mitigation would require a pre-operation barrier, which git
hooks cannot provide (there is no per-file post-write hook).

### b) Git object database (large gap, no race needed)

`git show origin/main:.env`, `git cat-file`, `git log -p -- .env` read from
`.git/objects`, not from the worktree. The kit's ACLs protect only the worktree —
and `.git` must remain readable for `opencode` because opencode performs the pulls.
After a fetch, the secret content is in the object database no matter what the hook
does. This cannot be fixed with ACLs; the only real defenses are never committing
secrets (pre-commit hooks on the human side, server-side secret scanning). This
limitation is documented as a boundary of the kit's threat model.

### c) Hook-less git operations + mtime cache

`git reset --hard`, `git restore`, `git stash pop`, and path-scoped
`git checkout -- <paths>` (which does not trigger `post-checkout`) write files
**without any hook running**. The wrapper does invoke protect-projects at session
start (`files/opencode-permissions-kit-lib/wrapper:265`), but **without `--force`** —
and the cache (`files/opencode-permissions-kit-lib/protect-projects.sh:131-140`)
compares only config mtimes (global config, projects.conf, project configs). A newly
appeared `.env` does not change any of those mtimes → cache hit → the file stays
unprotected until the next `--force` trigger happens to run.

**Candidate fix:** pass `--force` at wrapper session start (cost: one full scan per
opencode launch), or extend the cache key with a worktree-level signal.

### d) Threat model side note

The `opencode.jsonc` read/edit deny rules only constrain opencode's own read/edit
*tools*. `cat`, `head`, `python open()` etc. are shell commands — there the OS ACL is
the only line of defense. The kit's placement of hard ACLs is therefore correct, but
gaps a–c mark the spots where that line is thin.

## Summary table

| Scenario | Window? | Covered by kit? |
|---|---|---|
| `git pull && cat .env` (foreground) | No — hook is synchronous, `&&` orders execution | Yes |
| `git pull & ... cat` (background) | Yes — between merge write and hook run | No (unfixable via hooks) |
| `git show` / `cat-file` / `log -p` | Always — reads `.git/objects`, not worktree | No (out of scope; don't commit secrets) |
| `git reset --hard` / `restore` / `stash pop` + cache | Yes — no hook runs, mtime cache skips scan | Partially — fix available (force at session start) |
