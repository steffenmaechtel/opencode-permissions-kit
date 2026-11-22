# Uninstall

Remove the kit completely — and know what deliberately stays behind.

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
  `/usr/local/bin/opencode` wrapper (plus the `opk` /
  `opencode-permissions-kit` CLI names) — symlink removal is
  ownership-gated: a foreign file that replaced one of those names is
  detected and left untouched
- sudoers rules, profile scripts, project ACLs/setgid
- legacy kit artifacts, if present (the old `/etc/opencode/` conf dir, the
  `/usr/local/lib/opencode/` library, legacy sudoers and helper symlinks) —
  foreign content living under those names is detected and left untouched
- kit ownership inside the registered project roots: everything the kit
  handed to the `opencode` user (`.ddev/` trees, ddev settings directories,
  bootstrap project roots) and every file the agent/ddev created while
  running as `opencode` is chowned back to you — matched by uid/gid, so it
  also catches files whose owner became an orphaned id after the user
  removal
- `/run/opencode-permissions-kit` and the router-port sysctl file
  (`/etc/sysctl.d/99-ddev-rootless.conf` — removed only when it still
  holds the kit's exact one-line content; a file you maintain yourself
  at that name is detected and left untouched)

**Project file contents are untouched** — only owner and group revert. If
one of the revert operations cannot complete, the terminal prints a **WARN**
and the [audit log](../reference/audit-log.md) records the root as
**PARTIALLY completed** — never as a plain success. The uninstaller prints a
`setfacl` line to run by hand for orphaned group ids.

On WSL, the uninstaller also **asks** whether to remove the kit's
browser-bridge block from `/etc/wsl.conf` (kit-owned lines: the marked
comment block, plus the legacy `[opencode-permissions-kit]` section if
present; default: no). Decline and it prints the exact line range to
delete by hand.

Since #704 the uninstaller also asks whether to **revert the
[git-protection pointer layout](git-protection.md)** (default: yes —
the uninstall's contract is "all changes gone"): the revert moves
every stored gitdir back into its project (`chattr -i`, pointer out,
verify) and drops the storage config, before the library that performs
it is removed. Decline and the layout simply stays — pointer files
are plain git and keep working without the kit; the closing list then
names the per-project manual dance (`sudo chattr -i <project>/.git &&
sudo rm <project>/.git && sudo mv <storage>/<name>.git
<project>/.git`).

## What stays behind (harmless)

- A file at the kit's pre-0.0.10 umask name
  (`/etc/profile.d/opencode-umask.sh`) — the name is not kit-namespaced,
  so the uninstall treats any file there as foreign and leaves it for
  its owner to remove (kit-written profiles use the
  `opencode-permissions-kit-umask.sh` name, which IS removed).
- The **git-protection storage directory** (the `GITDIR_STORAGE` path,
  e.g. `/var/www/gitdirs`) stays even after a successful revert —
  empty once every project was reverted; remove it manually if you no
  longer want it.
- Shell RC hook lines (`~/.bashrc` / `~/.zshrc` / `~/.profile`, tagged
  `# opencode permissions kit`) — remove the tagged lines manually.
- Entries `opk ddev-hosts-add` wrote into the **Windows hosts file**
  (`C:\Windows\System32\drivers\etc\hosts`) — remove them manually if you
  no longer need them (`*.ddev.site` names were never added).
- The default-user `~/.config/opencode/opencode.jsonc` deny-all lockout
  config — delete or rename it to use opencode as your own user again (see
  [the wrapper](../concepts/wrapper.md)).
- The `opencode` user's home — the script **asks** whether to remove the
  user **and their home directory** (default: no).

During an interactive run you are asked whether the
[audit log](../reference/audit-log.md) should be deleted too (recommended).

After the uninstall, **restart your terminal (or log in again)**: the
running session still carries the kit's `ddev` shell function (its sudoers
helper is gone), the PATH/umask additions and your old membership in the
sharing group — a fresh session starts clean.

## Verify the removal

Check from a fresh checkout instead of the deleted library — `status.sh`
runs straight from the repository and works without an install (it reports
"NOT active" then):

```bash
sudo bash files/opencode-permissions-kit-lib/management/status.sh
```
