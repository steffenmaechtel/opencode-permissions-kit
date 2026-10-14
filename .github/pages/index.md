---
layout: default
---

# opencode permissions kit

Run [opencode](https://opencode.ai) as its own Linux user (`opencode`)
against a rootless container backend (docker-rootless or podman-rootless),
so the agent is UID-separated from the developer while ddev keeps
working.

## Install

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh \
  | sudo env KIT_BRANCH=stable bash
```

The served `install.sh` is a copy of the `stable` release channel — the
release mirror branch, byte-identical to `master` at release points. The
script self-fetches its sibling files from the same channel
(`KIT_BRANCH=stable`).

## Update an installed kit

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/update.sh \
  | sudo env KIT_BRANCH=stable bash
```

Or, on an installed kit, the short form: `sudo opk update`.

## Other channels

This page always serves the **stable** channel. Development or pinned
installs address the raw refs directly (any branch or version tag):

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh \
  | sudo env KIT_BRANCH=master bash
```

## Documentation

- [Getting started](https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/getting-started.md)
- [How-to guides](https://github.com/steffenmaechtel/opencode-permissions-kit/tree/master/docs/how-to)
- [Concepts](https://github.com/steffenmaechtel/opencode-permissions-kit/tree/master/docs/concepts)
- [Troubleshooting](https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/troubleshooting.md)
