# Harden .git/config

Block (or allow) the agent's access to `.git/config`.

`.git/config` can contain remote URLs with embedded credentials. The kit's
deny blocks opencode's **tools** (read/edit + a `*.git/config*` bash
tripwire) — a bash-spawned `cat .git/config` is not OS-blocked (soft-only,
see the [security model](../concepts/security-model.md)).

## Switch it on or off

At install time:

```bash
curl -fsSL https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh \
  | sudo env KIT_BRANCH=stable bash -s -- --secure-git-config
```

Later, at any time:

```bash
opk config git-config on
opk config git-config off
opk config git-config status
```

`on` re-renders the agent's `opencode.jsonc` with the deny rules; `off`
removes them. An existing file is backed up first (timestamped
`opencode.jsonc.bak-*` next to it) — both states render from the kit
template, so manual edits to the file are always replaced.

`status` spells out what the state means — the same wording `opk status`
shows:

```text
  git-config     ON — protected (soft-only — agent tools blocked)
     /home/opencode/.config/opencode/opencode.jsonc
```

```text
  git-config     OFF — access allowed (agent tools may edit git config)
     /home/opencode/.config/opencode/opencode.jsonc
```

## When to enable

- Remote URLs contain embedded tokens (`https://user:token@host/...`), or
- you don't want opencode to run git at all.

## When to leave it open

- SSH remotes or credential helpers, or
- you want opencode to commit/push on your behalf.
