# Uninstall

This guide shows how to remove the kit completely — and what deliberately
stays behind.

## Run the uninstall

```bash
opk uninstall
```

Run it as your default user (it asks for `sudo` where needed). Options:
`--yes` (skip prompts), `--dry-run` (show what would be removed),
`--debug` (trace execution).

## What is removed

- the `opencode` user (and its usergroup)
- the kit library under `/usr/local/lib/opencode-permissions-kit/` and the
  `/usr/local/bin/opencode` wrapper
- sudoers rules, profile scripts, project ACLs/setgid
- kit ownership inside the registered project roots: everything the kit
  handed to the `opencode` user (`.ddev/` trees, ddev settings
  directories, bootstrap project roots) and every file the agent/ddev
  created while running as `opencode` is chowned back to you — matched by
  uid/gid, so it also catches files whose owner became an orphaned id
  after the user removal
- `/run/opencode-permissions-kit` and the router-port sysctl file

**Project file contents are untouched** — only owner and group revert.

## What stays behind (harmless)

- Shell RC hook lines (`~/.bashrc` / `~/.zshrc` / `~/.profile`, tagged
  `# opencode permissions kit`) — remove the tagged lines manually.
- The default-user `~/.config/opencode/opencode.jsonc` deny-all lockout
  config — delete or rename it if you want to use opencode as your own user
  again (see [the wrapper](../concepts/wrapper.md)).
- The `opencode` user's home — the script **asks** whether to remove the
  user **and their home directory** (default: no). Answer `y` for a full
  cleanup; answer `n` to keep `/home/opencode` (ddev homes, imported keys).

During an interactive run you are asked whether the
[audit log](../reference/audit-log.md) should be deleted too (recommended).

## Verify the removal

Check from a fresh checkout instead of the deleted library — `status.sh`
also runs straight from the repository (it works without an install; it
reports "NOT active" then):

```bash
sudo bash files/status.sh
```
