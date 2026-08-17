# Migrate from a hard-ACL install

This guide is for installs from before the soft-only model (DDEV-WORKING
change): the kit mirrors deny rules into Linux ACLs and uses git hooks plus
a ddev delegation shim.

## What happens automatically

`update.sh` performs a one-time migration, gated by `HARD_DENY_REMOVED` in
`install.conf`:

1. Removes every `u:opencode:---` ACL deny from the registered project
   roots (via `migrate-denies.sh`).
2. Re-bases the sharing group to the `opencode` usergroup (chgrp + setgid +
   default ACLs), hands over every project's `.ddev` to `opencode`, and adds
   the developer to the group.
3. Removes the legacy artifacts: git hooks, `protect-projects.sh`,
   `ddev-transaction.sh`, the ddev delegation shim, the rewrite list.
4. Unsets `core.hooksPath`, provisions `/home/opencode/.ddev` + mkcert,
   re-renders the sudoers (now incl. the ddev-as-opencode rule), hooks the
   `ddev()` terminal function into your rc files, stamps
   `HARD_DENY_REMOVED=1`.

So in most cases the only step is:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/update.sh | sudo bash
```

## The docker-group exception

A legacy `docker-group` install **aborts with instructions** — rootless is
mandatory now. Re-run the installer with a rootless backend:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash -s -- --container-backend docker-rootless
```

(or `podman-rootless`).

## After the migration

- **Fresh login shell required** — group membership changes apply only to
  new sessions.
- Check the migration state and leftover denies:

  ```bash
  sudo bash /usr/local/lib/opencode-permissions-kit/status.sh
  ```

- Design background: `docs/design/ddev-working.md` (the migration's design
  record).
