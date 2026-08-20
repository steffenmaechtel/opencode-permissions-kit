# The sharing group

This page explains how you and the agent edit the same files without
fighting over ownership.

## One group: the opencode usergroup

The kit uses the `opencode` user's own primary usergroup (created by
`useradd -m`) as the sharing group — no `www-data`, no extra group:

- the developer is added as a member (`usermod -aG opencode <dev>`),
- project roots carry setgid + default ACLs `g:opencode:rwx`,
- `umask 002` (via the kit's profile script) makes agent-created files
  group-writable for the developer.

Net effect: files the agent creates are group-writable for you, and files
you create are readable/writable for the agent — no chgrp chores.

## What the baseline covers

The group baseline is applied **recursively** over every project root
(install, `config.sh projects add`, `config.sh refresh`,
`update.sh --refresh`) — by a shared helper that prints a live per-pass
entry counter, because first runs over large trees (hundreds of repos)
take minutes per pass:

| Operation | Scope |
|---|---|
| `chgrp -R opencode` | every file and directory |
| `chmod g+rwxs` (setgid + group rwx) | every directory — the group can create entries in pre-existing directories, and new files anywhere in the tree inherit the sharing group, not just directly under the root |
| `chmod g+rw` | every existing file, so you and the agent can edit each other's pre-install files |
| default ACLs `g:opencode:rwx` | every directory (governs new files' access) |

**`.git/` directories are included** in the baseline (issue #17): they
stay developer-owned but get the same group access, so the agent's git
can read the repository at the filesystem level. Because git also
refuses to run in repositories owned by someone else ("detected dubious
ownership"), the kit sets `safe.directory '*'` in the opencode user's
global git config on install and update — the agent's `git log`, `git
diff` & co. work in your projects out of the box. `.git/config` (which
can hold remote URLs with embedded credentials) remains guarded by the
soft `.git/config` deny — see
[the security model](security-model.md).

## Consequences

- **Group changes need a fresh login shell.** After install (or after
  `projects add` added you to a group), open a new terminal before
  expecting group access.
- ddev does not care about the sharing group — the web server runs in the
  container. If you serve files with a **host-side** webserver (not ddev),
  add its user to the `opencode` group.
- The developer's group membership also grants execute on the kit's real
  binary (`root:opencode`, mode `750`) — see
  [the wrapper](wrapper.md#wrapper-bypass-guard-detect-then-warn-loudly)
  for why that is acceptable.

## Re-applying the baseline

If group bits drift (e.g. after unpacking an archive as root), re-apply:

```bash
opencode-permissions-kit update --refresh
```
