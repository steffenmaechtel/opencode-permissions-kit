# The sharing group

How you and the agent edit the same files without fighting over ownership.

## One group: the opencode usergroup

The kit uses the `opencode` user's own primary usergroup as the sharing
group — no `www-data`, no extra group:

- the developer is added as a member (`usermod -aG opencode <dev>`),
- project roots carry setgid + default ACLs `g:opencode:rwx`,
- `umask 002` (via the kit's profile script) makes agent-created files
  group-writable for the developer.

Net effect: files the agent creates are group-writable for you, and files
you create are readable/writable for the agent — no chgrp chores.

## What the baseline covers

The group baseline is applied **recursively** over every project root
(install, `opk config projects add`, `opk config refresh`,
`opk update --refresh`):

| Operation | Scope |
|---|---|
| `chgrp -R opencode` | every file and directory |
| `chmod g+rwxs` (setgid + group rwx) | every directory |
| `chmod g+rw` | every existing file, so you and the agent can edit each other's pre-install files |
| default ACLs `g:opencode:rwx` | every directory (governs new files' access) |

First runs over large trees (hundreds of repos) take minutes per pass; the
helper prints a live per-pass entry counter.

**`.git/` directories are included**: they stay developer-owned but get the
same group access, so the agent's git can read the repository. Because git
refuses repositories owned by someone else ("detected dubious ownership"),
the kit sets `safe.directory '*'` in the opencode user's global git config on
install and update. `.git/config` (which can hold remote URLs with embedded
credentials) remains guarded by the soft deny — see
[harden `.git/config`](../how-to/secure-git-config.md).

## Consequences

- **Group changes need a fresh login shell.** After install (or after
  `projects add` added you to a group), open a new terminal before expecting
  group access.
- ddev does not care about the sharing group — the web server runs in the
  container. If you serve files with a **host-side** webserver (not ddev),
  add its user to the `opencode` group.
- Your group membership also grants execute on the kit's real binary
  (`root:opencode`, mode `750`) — see
  [the wrapper](wrapper.md#wrapper-bypass-guard-detect-then-warn-loudly)
  for why that is acceptable.

## Re-applying the baseline

If group bits drift (e.g. after unpacking an archive as root), re-apply:

```bash
opk update --refresh
```

A pass that fails wholesale aborts with a per-pass warning instead of
reporting success — a green "ACLs applied" always means the baseline actually
landed. A missing or broken `python3` never blocks the baseline: the passes
run without the live entry counters, one warning says so. A broken `python3`
names itself above that warning; a missing one stays silent.
