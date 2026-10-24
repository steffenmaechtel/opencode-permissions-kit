# Update the kit and the binary

Update the kit's scripts and the opencode binary.

## Channels

The kit ships from two refs; which one you use is stamped into
`install.conf` (`KIT_CHANNEL`) and shown by `opk status`:

| Channel | What it is | Who needs it |
|---|---|---|
| `stable` | Release mirror; byte-identical to `master`, moves only on releases | The default recommendation |
| `master` | Development channel — moves with every merged PR | Testing the newest changes |
| `<branch>` / `x.y.z` | Any feature branch, or an exact version tag (e.g. `0.0.29`) | Testing a PR, pinning a version |

`opk update` follows the stamped channel automatically. The easy switch is
the `--channel` flag — it updates from the given ref and re-stamps
`KIT_CHANNEL` in one go:

```bash
sudo opk update --channel stable    # release mirror (recommended default)
sudo opk update --channel master    # development channel
sudo opk update --channel feature/xyz   # test a branch
sudo opk update --channel 0.0.29    # pin an exact version
```

The `KIT_BRANCH` environment variable does the same for every entry point
(curl-streamed install or update, `opk update`):

```bash
# update from the stable release mirror (recommended default)
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/update.sh | sudo env KIT_BRANCH=stable bash

# switch to the development channel
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/opencode-permissions-kit-lib/management/update.sh | sudo env KIT_BRANCH=master bash

# test a feature branch / pin an exact version
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/<branch>/files/opencode-permissions-kit-lib/management/update.sh | sudo env KIT_BRANCH=<branch> bash
sudo env KIT_BRANCH=0.0.29 opk update
```

The Pages entry always serves the **stable** channel, so master/branch/tag
installs address the raw refs directly (the ref is part of the URL).

Updates are supported from kit **0.0.14 onwards**; on older installs
`update.sh` aborts — re-run the installer instead (it keeps your projects
and deny list where possible).

## Update the kit

From the stamped channel — for a stable install that is simply:

```bash
opk update
```

`update.sh` re-deploys the kit files and refreshes the version stamps. It
does **not** touch `projects.conf` or
`/home/opencode/.config/opencode/opencode.jsonc` — your project list and
deny-list customizations survive.

The ddev handover rescan over your project roots is skipped when nothing
changed since the last pass (a stamp under
`/etc/opencode-permissions-kit/handover/` records it). New or re-registered
roots, a group re-base, or a dev-owned toggle re-scan automatically. To
re-apply the group baseline **and** force the full rescan:

```bash
opk update --refresh
```

## Upgrade the opencode binary

`opencode upgrade` and opencode's auto-updater cannot work behind the
wrapper (the binary is root-owned) — the bundled config sets
`autoupdate: false`, and this is the upgrade entry point:

```bash
opk upgrade-opencode                   # latest release of the current major
opk upgrade-opencode --major 2         # switch to the latest opencode 2.x
opk upgrade-opencode --version 2.0.11  # pin an exact version
opk upgrade-opencode --binary-path ./opencode  # specific file
# equivalent long form:
opk update --only-binary
```

Upgrades never cross majors silently: without `--major` / `--version` the
latest release **of the installed major** is used (1.x resolves through
GitHub releases, 2.x through npm). Binary upgrades are best-effort: a
failure leaves the current binary in place, the previous one is kept in
`/tmp/opencode-upgrade-backup-*`.

## Security advisories

The kit ships a curated database of known opencode security advisories. On
every start the wrapper checks your installed version against it — locally,
offline; when your install is affected, the banner shows the advisory and
the fix:

```text
  WARNING: the installed opencode 1.0.100 is affected by a known security advisory:
  GHSA-vxw4-wv6m-9hhh (high): Unauthenticated HTTP server allows arbitrary command execution
  patched in opencode 1.0.216
  Please upgrade opencode with 'opk upgrade-opencode'.
```

```bash
opk upgrade-opencode
```

- Only advisories that can affect your install warn — the kit deploys the
  binary itself, so npm-only advisories do not match kit installs.
- Fresh advisory entries travel with kit releases: run `sudo opk update` to
  get them. `opk status` shows your install's verdict plus a live upstream
  check that flags advisories newer than your kit release.

## Verify

```bash
opk status
```

Shows the deployed version and the backend state after the update.
