# Manage project directories

Add, list, and remove the directories the agent may work in.

Project roots are stored in `/etc/opencode-permissions-kit/projects.conf`
(one absolute path per line; lines starting with `#` are comments). The
wrapper only allows opencode to start inside one of these directories or
their subdirectories.

## Add a project directory

```bash
opk config projects add /var/www/vhosts/new-project
```

Multiple paths at once are fine, and `~` works. System paths (`/`, `/usr`,
`/home`, `/tmp`, …) are rejected — use a dedicated folder like
`/var/www/vhosts` or `~/dev`. Adding a root applies the **group baseline**
(group `opencode`, setgid, default ACLs `g:opencode:rwx`) in one step.

A project root must be a **real directory** — a path that is itself a
symlink is refused (`projects add`, `handover`, `refresh`, `opk update`,
and the uninstaller all skip it with a warning). The baseline would
silently do nothing on a link while reporting success, so register the
link's target directory instead:

```bash
opk config projects add /var/www/vhosts/new-project   # a real directory, not a link
readlink -f /var/www/vhosts/my-link                   # resolve a link to its target first
```

Roots below your home directory (like `~/dev`) work too: adding or
refreshing a root also grants **traverse-only** ACLs (`g:opencode:--x`, no
listing/reading) on ancestors that would otherwise block the agent — a home
directory is `0750` on Ubuntu 24.04, and without `+x` on every component
above the root, opencode cannot reach it at all.

### Manual equivalent

The four sharing passes of `projects add` (the group baseline's order
in `files/opencode-permissions-kit-lib/sh/fs-baseline.sh` — group,
per-directory setgid + `g+rwx`, per-file `g+rw`, default ACLs):

```bash
echo /var/www/vhosts/new-project | sudo tee -a /etc/opencode-permissions-kit/projects.conf
sudo chgrp -R opencode /var/www/vhosts/new-project
sudo find /var/www/vhosts/new-project -type d -exec chmod g+rwxs {} +
sudo find /var/www/vhosts/new-project -type f -exec chmod g+rw {} +
sudo setfacl -R -d -m g:opencode:rwx /var/www/vhosts/new-project
```

Two more things `projects add` does after those passes, in the same
run: the **`.git` re-narrowing heal** (`.git/config` and
`.git/hooks` pinned developer-owned `644`/`755`, no group write, no
ACLs — the sharing passes just granted exactly that) and the baseline
stamp that lets later `opk update` runs skip an unchanged tree.
Without them a manually prepared tree still works — but the first
stamp-invalidated update re-runs the full baseline over it.

## List configured directories

```bash
opk config projects list
```

## Remove a project directory

```bash
opk config projects remove /var/www/vhosts/old-project
```

Only the `projects.conf` line is removed; files and their group bits stay as
they are.

## What happens to ddev paths

`projects add` also triggers the [ddev handover](../concepts/ddev-integration.md)
for known app types (typo3, drupal, …): the settings directories ddev chmods
are handed over to the `opencode` user, at any depth below the registered
root.
