# Handover scan-skip — fast `opk update` on large project trees

> Status: **CURRENT.** Decided after
> [issue #112](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/112)
> (every `opk update` re-ran the full `.ddev` handover scan over every
> registered project root — minutes on trees that were already fully
> handed over). Branch: `feature/112-handover-scan-performance`.

## 1. Problem

The ddev handover scan (`ddev_handover_root` in
`sh/ddev-handover.sh`) walked every registered project root with a full
`find` and then ran `chown -R` + `chmod -R g+w` over **every** found
`.ddev` tree and settings dir — unconditionally, on every
`opk update`, even when the previous pass had already conformed every
tree. On installs with many or large projects (`.ddev/db_snapshots`,
`typo3conf/ext`, …) the routine update spent minutes writing metadata
that ended up identical, and `opk status`'s Windows-hosts readiness scan
paid a similar full-tree walk per root.

The unconditional rescan was deliberate (it heals drift: fresh
developer-owned clones, wrapper bypasses, restores) — but it made
"nothing changed" the expensive common case.

## 2. Decision

Three optimizations, all preserving the repair story through explicit
paths:

1. **Scan-skip stamps** (`ddev_handover_stamp_valid` /
   `ddev_handover_stamp_write`): after a complete pass over a root, a
   one-line stamp under `/etc/opencode-permissions-kit/handover/`
   (one file per root, named by the root path's `cksum`) records
   `root|user|group|scan-rev|dev-owned-mode|dev-user`. A **plain**
   `opk update` skips roots whose stamp matches; anything doubtful
   (missing stamp, any field mismatch) falls back to the full scan —
   the stamp fails *closed* toward more scanning, never less.
   Invalidated by design on:
   - user/group/dev-user re-base (each is part of the compared shape),
   - dev-owned toggles (`opk config ddev-settings`),
   - scan-semantics changes (bump `DDEV_HANDOVER_STAMP_REV`),
   - new roots (no stamp yet).
   Re-registered roots cannot skip on a stale pass either:
   `projects remove` leaves the old stamp behind (an orphan that is
   never consulted while the root is unregistered), and `projects add`
   always scans and re-stamps.
   The explicit paths — install, `opk update --refresh`,
   `opk config refresh`, `opk config handover <path>`,
   `opk config projects add` — always scan and re-stamp.
2. **Top-inode fast path** (`_ddev_tree_conforms`): the recursive
   `chown -R`/`chmod -R g+w` pair is skipped when the tree's top
   directory already is `user:group` with group-write. The kit is the
   only actor that hands whole trees to the agent user, and everything
   ddev writes inside them later stays agent-owned — so a conforming
   top inode means the recursive pair would be a metadata no-op.
   Known limitation (accepted): **mid-tree drift** — developer-owned
   files *inside* an agent-owned tree (bypassing `git checkout`, manual
   restore into `.ddev/`) — is invisible to the probe. It stays covered
   by the explicit repair paths and the `ddev()` hook's ready-made
   `opk config handover` hint, which fires on the EPERM the drift
   eventually causes. Unreadable or unexpected `stat` answers never
   skip the walk (fail open toward scanning).
3. **`.git` pruned from the scans** (handover scan + status.sh's
   Windows-hosts scan): `.git` is the densest directory structure in a
   project, and a `.ddev` inside it is never a project — ddev locates
   `.ddev` by walking **up** from the working directory, and no ddev
   command runs from inside `.git/`. Same rationale as the
   vendor/node_modules/testdata pruning (issues #21/#29). The group
   baseline (`fs-baseline.sh`) deliberately still walks `.git` —
   group-accessibility there is part of the sharing model.

## 3. Security notes

- Stamps are **purely an optimization, never a security boundary**.
  They live root-owned under `/etc/opencode-permissions-kit/handover/`
  (the agent user cannot write them); a tampered or deleted stamp costs
  at most one extra scan.
- The stamp's file name is the root path's `cksum`; the root path is
  also the first field of the compared content, so a hash collision
  between two roots cannot skip a different root's scan.
- `opk status` is untouched in its reporting duties: it never ran the
  handover, and its hosts scan stays truthful for fresh projects (only
  the `.git` prune, which cannot hide a real project, was added).

## 4. Consequences

- A routine `opk update` on unchanged trees costs one `stat` per stamp
  instead of a full-tree walk per root — the issue's "takes a while"
  line disappears for the steady state.
- Fresh clones under an already-stamped root are no longer healed by a
  plain `opk update`. This is covered by design: `ddev config`/`start`
  run as the opencode user through the hooked `ddev()` function, which
  detects the fresh-clone EPERM case and prints the one-command fix
  (`sudo opk config handover <path>`); `projects add` and
  `update --refresh` remain the bulk repair paths.
- `uninstall.sh` removes the whole `/etc/opencode-permissions-kit/`
  directory — the stamps go with it; a re-install re-scans and
  re-stamps from scratch.
