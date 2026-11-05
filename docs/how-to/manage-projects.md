# Manage project directories

Add, list, and remove the directories the agent may work in.

Project roots are stored in `/etc/opencode-permissions-kit/projects.conf`
(one absolute path per line). The wrapper only allows opencode to start
inside one of these directories or their subdirectories.

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

```bash
echo /var/www/vhosts/new-project | sudo tee -a /etc/opencode-permissions-kit/projects.conf
sudo chgrp -R opencode /var/www/vhosts/new-project
sudo chmod g+s /var/www/vhosts/new-project
sudo setfacl -R -d -m g:opencode:rwx /var/www/vhosts/new-project
```

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
