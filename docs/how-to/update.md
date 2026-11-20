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

The `KIT_BRANCH` environment variable does the same for every entry
point. For `opk update` it must ride the sudo invocation:

```bash
sudo env KIT_BRANCH=0.0.29 opk update
```

A bare `KIT_BRANCH=0.0.29 opk update` (without `sudo env`) drops the
variable at opk's sudo boundary — the update then follows the stamped
channel instead (the banner names the effective channel, but nothing
warns about the dropped override). The streamed install/update variants
for any channel (master, a feature branch, an exact version tag) live
in
[Streamed install and update (advanced)](../advanced/streamed-install-update.md).

Updates are supported from kit **0.0.14 onwards**; on older installs
`update.sh` aborts — re-run the installer instead (it keeps your projects
and deny list where possible).

## Know when an update is available

Two places tell you a newer kit exists — no extra command needed:

- **The wrapper banner**: the first interactive `opencode` start of the day
  checks the tracking channel's `VERSION` file (one bounded request — 3 s
  worst case with a dead network) and caches the verdict per user in
  `~/.cache/opencode-permissions-kit/update-check`; every later start that
  day replays the cache. An available update prints a `NOTE:` line under
  the banner with the update command. Headless invocations (`serve`, `run`
  with a message argument or piped stdin, queries) never run the check.
- **`opk status`**: the `kit update` row in the Core section compares live
  on every run. An available update counts as a warning (`opk status
  --short` exits 2 — cron sees an outdated security kit); offline or
  blocked stays an uncounted "unknown".

Pinned installs (`KIT_CHANNEL=x.y.z`) skip the check — a pin is deliberate
and the tag never moves. Set `OPK_UPDATE_CHECK=0` in the environment to
disable every update probe (air-gapped hosts, scripted runs).

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

Plain `opk update` runs print a migration note (on every such run —
there is no once-only state): the project-root sticky bits of earlier
heals are removed in the #703 era, and `opk update --refresh` (or
`sudo opk config refresh`) applies the strip — a plain `opk update`
never re-runs the group baseline, so the legacy bits stay until one of
those commands runs. `.git` itself and its pinned internals keep the
heal unchanged. The strip covers registered roots and the ancestors of
every `.git` found under them; one corner lingers — an ancestor
stickied for a `.git` that has since been deleted is outside every
current walk (strip those manually: `sudo chmod -t <dir>`).

### Update integrity (SHA256SUMS)

Every `opk update` verifies each fetched kit file against the
`SHA256SUMS` manifest that rides the same ref — nothing deploys over a
mismatch. Two aborts can surface on release day:

- `fetched kit tree failed the SHA256SUMS verification` — the channel
  moved mid-fetch (the `stable` mirror fast-forwards when a release is
  cut); re-run the update.
- `cannot establish the SHA256SUMS verification context` — the pinned
  ref carries no manifest. Every tag up to and including `0.0.60`
  predates the mechanism (it first ships with `0.0.61`), so the
  `--channel 0.0.29`-style pins above fail closed with this error: pin
  `0.0.61` or newer, or a branch.

`KIT_SHA_VERIFY=0` in the environment disables the gate (break-glass
for upstream outages). The trust model — what the manifest does and
does not protect against — lives in
[the security model](../concepts/security-model.md).

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
`/var/backups/opencode-permissions-kit/update-*/bin/`.

Every **full** update run (not `--only-binary`, which touches only the
binary) also writes its other recovery material under
`/var/backups/opencode-permissions-kit/update-<timestamp>/`: a copy of the
rc files before the shell-hook rewrites are applied, and — before the
library is re-deployed — a full copy of the previous library tree. A
failed library deploy is rolled back from that copy automatically; the
directories accumulate (like the install backups) and are safe to delete
once an update has proven itself.

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
