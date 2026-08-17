# Glossary

Short definitions of the kit's terms — each entry links to the concept page
with the full picture.

**Backend (container backend)**
The rootless container runtime configured at install time: `docker-rootless`
(per-user daemon + socket) or `podman-rootless` (daemonless CLI). Never
root-equivalent. See [switch the container backend](../how-to/switch-container-backend.md).

**Deny-all config**
The lockout `opencode.jsonc` for the default user that denies everything —
the safety net against a self-updated binary bypassing the wrapper. See
[the wrapper](../concepts/wrapper.md).

**Handover (ddev handover)**
Transferring ownership of the directories ddev chmods (`.ddev/`, settings
dirs) to `opencode:opencode` so ddev stops hitting EPERM. See
[ddev integration](../concepts/ddev-integration.md).

**Leak scan**
The name-based, report-only sweep of scratch directories (`/tmp`, ...) that
`status.sh` runs — lists files matching the deny patterns. No remediation,
no guarantees. See [customize the deny list](../how-to/customize-deny-list.md).

**Rootless**
A container backend that runs without root: the daemon (or the daemonless
CLI) runs as a regular user, so containers never have a root-equivalent
socket or daemon. See [security model](../concepts/security-model.md).

**Sharing group**
The `opencode` user's own usergroup, used for developer ↔ agent file
sharing: setgid + default ACLs + umask 002. See
[the sharing group](../concepts/sharing-group.md).

**Soft deny**
A read/edit rule in `opencode.jsonc` that gates opencode's own tools — not
the OS. Bash-spawned processes are only caught by tripwires. See
[security model](../concepts/security-model.md).

**Tripwire**
A bash `ask` rule mirroring a deny pattern (with trailing `*`) so a command
that merely names a sensitive file still prompts. Lexical — variables and
globs evade it. See [customize the deny list](../how-to/customize-deny-list.md).

**Wrapper**
The script at `/usr/local/bin/opencode` that every invocation passes
through: validates the directory, detects container tools, probes the
backend, then execs opencode as the `opencode` user. See
[the wrapper](../concepts/wrapper.md).
