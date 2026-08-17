# Audit log

This page documents what the kit logs, where, and who can read it.

## Location and modes

Every kit script that changes the system writes to
`/var/log/opencode-permissions-kit/opencode-permissions-kit.log`:

- directory `750`, file `640`, root-owned, in the default user's primary
  group,
- self-rotating at 1 MB (best-effort),
- the `opencode` user **cannot** read it; the default user (the kit admin)
  can read it without `sudo`.

## Notable events

- install/update/uninstall completion
- backend switches
- the hard-deny migration (`hard-deny migration ...`)
- binary upgrades
- leak-scan findings

## At uninstall

During an interactive `uninstall.sh` run you are asked whether the audit log
should be deleted too (recommended).
