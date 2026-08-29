# Manage project directories

This guide shows how to add, list, and remove the directories the agent may
work in.

Project roots are stored in `/etc/opencode-permissions-kit/projects.conf`
(one absolute path per line). The wrapper only allows opencode to start
inside one of these directories or their subdirectories.

## Add a project directory

```bash
opk config projects add /var/www/vhosts/new-project
```

Multiple paths at once are fine, and `~` works. System paths (`/`, `/usr`,
`/home`, `/tmp`, …) are rejected — the group baseline (`chgrp -R`,
`setfacl -R`) must never run over them; use a dedicated folder like
`/var/www/vhosts` or `~/dev`. `config.sh` appends the path to
`projects.conf` and applies the **group baseline** (group `opencode`, setgid,
default ACLs `g:opencode:rwx`) in one step — no extra step needed.

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
