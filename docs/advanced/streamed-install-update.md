# Streamed install and update (advanced)

Install and update paths that stream the entry scripts through `curl`
instead of using the regular surfaces — the
[install one-liner](../getting-started.md#install) and
`sudo opk update` ([update guide](../how-to/update.md)).

These paths serve special cases: testing a feature branch before it is
released, pinning an exact version, or reaching for the raw URLs when
`opk` is not available. Almost nobody needs them — the regular paths
are the documented default.

> **No baked-in checksums on advanced paths.** A checksum printed here
> would go stale with every push to a branch — there is no release
> moment that could keep it honest. If you want integrity on an
> advanced path, verify the entry script manually against the ref's
> `SHA256SUMS` manifest ([recipe below](#verify-manually-integrity)).

## Channels

The channel table and the `--channel` flag live in
[Update the kit](../how-to/update.md#channels). Every raw URL below
addresses the ref directly — the ref is part of the URL, so the same
recipe shape works for `stable`, `master`, any `feature/*` branch, or
an exact version tag (`0.0.61`).

## Streamed install from any ref

Define the raw prefix once, then pick the ref:

```bash
raw=https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit
# development channel
curl -fsSL "$raw/master/files/install.sh" | sudo env KIT_BRANCH=master bash
# a feature branch (testing a PR)
curl -fsSL "$raw/refs/heads/<branch>/files/install.sh" \
  | sudo env KIT_BRANCH=<branch> bash
# an exact version tag
curl -fsSL "$raw/0.0.61/files/install.sh" | sudo env KIT_BRANCH=0.0.61 bash
```

A streamed install fetches every sibling file from the same ref
(`KIT_BRANCH`) and stamps the channel into `install.conf`
(`KIT_CHANNEL`) — later `opk update` runs follow that stamp.

## Streamed update from any ref

A streamed update re-deploys the kit like `opk update` would; your
`projects.conf` and deny-list customizations survive. It re-stamps
`KIT_CHANNEL` in `install.conf`, so plain `opk update` runs afterwards
stay on the new channel:

```bash
raw=https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit
# stable channel
curl -fsSL "$raw/stable/files/opencode-permissions-kit-lib/management/update.sh" \
  | sudo env KIT_BRANCH=stable bash
# development channel
curl -fsSL "$raw/master/files/opencode-permissions-kit-lib/management/update.sh" \
  | sudo env KIT_BRANCH=master bash
# a feature branch (same shape for an exact version tag)
curl -fsSL "$raw/refs/heads/<branch>/files/opencode-permissions-kit-lib/management/update.sh" \
  | sudo env KIT_BRANCH=<branch> bash
```

Updates are supported from kit 0.0.14 onwards; on older installs the
streamed update aborts — re-run the installer instead.

## Verify manually (integrity)

Every file a streamed script **fetches** is verified against the ref's
`SHA256SUMS` manifest — but the entry script itself runs before that
verification exists (the bootstrap gap). On advanced paths, close it by
hand: fetch the script as a file, compare its digest against the
manifest line, and only then execute:

```bash
raw=https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit
curl -fsSL -o /tmp/opk-entry.sh "$raw/stable/files/install.sh"
sha256sum /tmp/opk-entry.sh
curl -fsSL "$raw/stable/SHA256SUMS" | grep -F 'files/install.sh'
# the two digests must match — only then:
sudo env KIT_BRANCH=stable bash /tmp/opk-entry.sh
```

Substitute the ref and path of the entry script you are streaming
(`files/install.sh` or
`files/opencode-permissions-kit-lib/management/update.sh`). Refs up to
and including `0.0.60` predate the manifest — the verify recipe needs
`0.0.61`, a newer tag, or a branch.

What this buys: corruption and mirror-fault detection. It does not
detect an origin compromise — the manifest rides the same ref as the
script ([security model](../concepts/security-model.md)).
