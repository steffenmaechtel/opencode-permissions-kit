# Update the kit and the binary

This guide shows how to update the kit's scripts and the opencode binary.

## Update the kit

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/update.sh | sudo bash
```

`update.sh` re-deploys the kit files and refreshes the `install.conf` version
stamp. It does **not** touch `projects.conf` or
`/home/opencode/.config/opencode/opencode.jsonc` — your project list and
deny-list customizations survive.

To re-apply the group baseline (chgrp/setgid/default ACLs) as well:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --refresh
```

## Upgrade the opencode binary

`opencode upgrade` and opencode's auto-updater cannot work behind the
wrapper (the binary is root-owned, opencode runs as an unprivileged user) —
the bundled config sets `autoupdate: false`, and `update.sh` is the upgrade
entry point:

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary                  # latest release
sudo bash /usr/local/lib/opencode-permissions-kit/update.sh --binary-path ./opencode  # a specific file
```

Binary upgrades are best-effort: a failure leaves the current binary in
place, the previous one is kept in `/tmp/opencode-upgrade-backup-*`.

## Verify

```bash
sudo bash /usr/local/lib/opencode-permissions-kit/status.sh
```

`status.sh` shows the deployed version and the backend state after the
update.
