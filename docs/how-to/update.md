# Update the kit and the binary

This guide shows how to update the kit's scripts and the opencode binary.

## Supported upgrade paths

Updates are supported from kit **0.0.14 onwards**. On older installs
`update.sh` aborts with instructions — re-run the installer instead; it
keeps your projects and deny list where possible:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

## Migrating to ≥ 0.0.29 (one-time, layout change)

0.0.29 reorganized the deployed library (`bin/`, `sh/`, `py/`,
`management/`, `templates/`) and renamed several files. The installed
`update.sh` of an older kit still fetches the old file list and aborts
with a curl 404 — **`opk update` cannot perform this particular hop**.
Migrate once with the streamed one-liner (it deploys the new layout,
removes the old files, and rewrites the kit-owned shell-hook lines in
your `.bashrc`/`.zshrc`/`.profile` in place):

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/opencode-permissions-kit-lib/management/update.sh | sudo bash
```

Then open a new terminal (so the rewritten `ddev()` hook loads) and
verify with `opk status`. From 0.0.29 onwards, `opk update` works again
as usual. A fresh install via the `install.sh` one-liner works too —
your `projects.conf` and opencode configs are preserved either way.
Background: [streamline design record](../design/streamline.md).

## Update the kit

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/opencode-permissions-kit-lib/management/update.sh | sudo bash
```

`update.sh` re-deploys the kit files and refreshes the `install.conf` version
stamp. It does **not** touch `projects.conf` or
`/home/opencode/.config/opencode/opencode.jsonc` — your project list and
deny-list customizations survive. Since kit 0.0.14 the
`opk` command (see [CLI](../reference/cli.md)) exists —
future updates work without the curl one-liner:

```bash
opk update
```

To re-apply the group baseline (chgrp/setgid/default ACLs) as well:

```bash
opk update --refresh
```

## Upgrade the opencode binary

`opencode upgrade` and opencode's auto-updater cannot work behind the
wrapper (the binary is root-owned, opencode runs as an unprivileged user) —
the bundled config sets `autoupdate: false`, and `update.sh` is the upgrade
entry point:

```bash
opk upgrade-opencode                 # latest release
opk upgrade-opencode --binary-path ./opencode  # specific file
# equivalent long form:
opk update --only-binary
```

Binary upgrades are best-effort: a failure leaves the current binary in
place, the previous one is kept in `/tmp/opencode-upgrade-backup-*`.

## Verify

```bash
opk status
```

`status.sh` shows the deployed version and the backend state after the
update.
