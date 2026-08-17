# Update the kit and the binary

This guide shows how to update the kit's scripts and the opencode binary.

## Supported upgrade paths

Updates are supported from kit **0.0.14 onwards**. On older installs
`update.sh` aborts with instructions — re-run the installer instead; it
keeps your projects and deny list where possible:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash
```

## Update the kit

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/update.sh | sudo bash
```

`update.sh` re-deploys the kit files and refreshes the `install.conf` version
stamp. It does **not** touch `projects.conf` or
`/home/opencode/.config/opencode/opencode.jsonc` — your project list and
deny-list customizations survive. Since this update (kit 0.0.14) the
`opencode-permissions-kit` command (see [CLI](../reference/cli.md)) exists —
future updates work without the curl one-liner:

```bash
opencode-permissions-kit update
```

To re-apply the group baseline (chgrp/setgid/default ACLs) as well:

```bash
opencode-permissions-kit update --refresh
```

## Upgrade the opencode binary

`opencode upgrade` and opencode's auto-updater cannot work behind the
wrapper (the binary is root-owned, opencode runs as an unprivileged user) —
the bundled config sets `autoupdate: false`, and `update.sh` is the upgrade
entry point:

```bash
opencode-permissions-kit update --binary                  # latest release
opencode-permissions-kit update --binary-path ./opencode  # a specific file
```

Binary upgrades are best-effort: a failure leaves the current binary in
place, the previous one is kept in `/tmp/opencode-upgrade-backup-*`.

## Verify

```bash
opencode-permissions-kit status
```

`status.sh` shows the deployed version and the backend state after the
update.
