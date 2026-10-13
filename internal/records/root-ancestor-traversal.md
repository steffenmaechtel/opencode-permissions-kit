# Root ancestor traversal + versioned no-bind-mounts

Date: 2026-09-09
Status: accepted

## Context

A first-time install on a production WSL2 machine (projects under
`/home/<dev>/www/vhosts`) reported, in one run:

1. `fatal: failed to stat '<root>': Permission denied` during install,
2. `opencode` failing with `EACCES: permission denied, lstat '<project>'`,
3. `ddev start` failing with `a project cannot be created in the DDEV
   source code (<project>)`.

Root cause: the group baseline fixes the registered root **downwards**
only. Resolving the root's path from `/` needs `+x` on **every**
ancestor — and Ubuntu 24.04 home directories are `0750 <dev>:<dev>`. The
agent user therefore could not reach the root at all while the root's
own bits looked perfect. ddev's `fileutil.FileExists()` is fail-open
(`os.Stat` EACCES reads as "exists", pkg/fileutil/file_exists.go), which
turns the same EACCES into the misleading "DDEV source code" error.

Separately, the same machine then hit `bind mounts can't be used with
Docker Rootless` on the first `ddev start`: ddev 1.25.0–1.25.2 requires
the global `no-bind-mounts` switch against a rootless Docker daemon;
upstream fixed rootless bind mounts in v1.25.3.

## Decision

- `fs_baseline_root` (sh/fs-baseline.sh) gains `fs_ensure_traversable`:
  for every ancestor of a root (up to, excluding, `/`), grant
  `setfacl -m g:<sharing-group>:X` when that ancestor blocks the group.
  Capital `X` adds `x` to directories only; the entries are allow-ACLs
  (soft model — never deny), leave owner/group/mode untouched, and give
  no listing (no `r`). With the agent user known (install, config,
  update), the check is an exact per-ancestor probe
  (`sudo -u <agent> test -x`); the bit-level heuristic applies
  otherwise (tests run without sudo).
- One helper, called from inside `fs_baseline_root`, covers every
  consumer: install Step 5, `config.sh projects add` / `refresh`,
  `update.sh --refresh`.
- `opk status` warns per root whose ancestor chain still blocks (looser,
  report-only check — any named ACL `x` entry counts as granted).
- `ddev_rootless_bindmounts` (sh/ddev-handover.sh) sets
  `ddev config global --no-bind-mounts` ONLY for `docker-rootless` with
  ddev < 1.25.3 — wired into install (probed version/binary from the
  1.25 gate) and the `config.sh container-backend docker-rootless`
  switch. Modern ddevs keep bind mounts (no needless Mutagen sync).

## Alternatives considered

- chgrp ancestors to the sharing group + `g+x`: changes the primary
  group of the developer's home — visible side effects for tooling that
  keys on it. Rejected for the surgical ACL.
- `u:<agent>:X` named-user ACL instead of `g:<group>:X`: equivalent
  effect; the group entry matches the kit's sharing model and needs no
  extra user plumbing inside the baseline helper.
- Always setting `no-bind-mounts` on docker-rootless: needlessly forces
  Mutagen sync on ddev >= 1.25.3.

## Consequences

- First installs under `~/...` work without manual `setfacl` (the
  reporter's workaround becomes the kit's automatic behavior).
- `/home/<dev>` gains a `group:opencode:--x` ACL entry (traversal only —
  the directory stays non-listable and unreadable for the agent).
- The old ddev bind-mount failure no longer surfaces on fresh
  docker-rootless installs; the flag persists in the agent user's ddev
  global config, so `opk update` does not re-apply it.
