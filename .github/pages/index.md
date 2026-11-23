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

Verified variant — the checksum is rendered at deploy time from the
exact bytes this site serves:

```bash
curl -fsSL -o /tmp/opk-install.sh https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh &&
echo "__OPK_INSTALL_SHA256__  /tmp/opk-install.sh" | sha256sum -c - &&
sudo env KIT_BRANCH=stable bash /tmp/opk-install.sh
```

The served `install.sh` is a copy of the `stable` release channel — the
release mirror branch, byte-identical to `master` at release points. The
script self-fetches its sibling files from the same channel
(`KIT_BRANCH=stable`).

## Update

```bash
sudo opk update
```

The command follows the channel your install tracks (`opk status`
shows it). Channel switches live in the
[update guide](https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/how-to/update.md);
streamed updates and version pins in
[Streamed install and update (advanced)](https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/advanced/streamed-install-update.md).

## Tell your agent about the kit

The kit changes a few git behaviors on purpose. Optional, and a
one-time step: copy this block into the agent's global `AGENTS.md`
(`/home/opencode/.config/opencode/AGENTS.md`) so the agent reads the
notes the kit ships:

<!-- opk-agents-snippet:start -->

```text
This host runs the opencode permissions kit. Before your first git
command or file-permission change in a project, read the host notes
and follow them — some git failures are expected here and must not
be "fixed":

/usr/local/lib/opencode-permissions-kit/templates/AGENTS-HOST.md

(No such file: this machine has no kit installed — ignore this note.)
```

<!-- opk-agents-snippet:end -->

What the notes cover: [Tell your agent about the kit](https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/how-to/agent-host-notes.md).

## Documentation

- [Getting started](https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/getting-started.md)
- [How-to guides](https://github.com/steffenmaechtel/opencode-permissions-kit/tree/master/docs/how-to)
- [Concepts](https://github.com/steffenmaechtel/opencode-permissions-kit/tree/master/docs/concepts)
- [Troubleshooting](https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/troubleshooting.md)
