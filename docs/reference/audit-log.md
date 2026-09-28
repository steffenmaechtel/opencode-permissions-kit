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
- backend switches (`container backend switched: ...`)
- project roots added/removed (`project added: ...`, `project removed: ...`)
- the git-config toggle (`git-config hardening set to ...`)
- ddev handovers (`ddev handover: ...`, `ddev handover applied under ...`)
- ddev-settings changes (`ddev-settings set to ...`)
- the agents migration (`agents migration: moved|copied|skipped ...`)
- ddev database exports (skipped/result lines)
- binary upgrades
- leak-scan findings

## At uninstall

During an interactive `uninstall.sh` run you are asked whether the audit log
should be deleted too (recommended).
