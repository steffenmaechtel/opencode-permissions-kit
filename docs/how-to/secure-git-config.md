# Harden .git/config

This guide shows how to block (or allow) the agent's access to
`.git/config` — and when each choice is right.

`.git/config` can contain remote URLs with embedded credentials. The kit's
deny blocks opencode's **tools** (read/edit + a `*.git/config*` bash
tripwire) — a bash-spawned `cat .git/config` is not OS-blocked (soft-only,
see the [security model](../concepts/security-model.md)).

## Switch it on or off

At install time:

```bash
curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash -s -- --secure-git-config
```

Later, at any time:

```bash
opk config git-config on
opk config git-config off
opk config git-config status
```

`on` re-renders the agent's `opencode.jsonc` with the deny rules (the
previous file is backed up); `off` removes them.

## When to enable

- Remote URLs contain embedded tokens (`https://user:token@host/...`), or
- you don't want opencode to run git at all.

## When to leave it open

- SSH remotes or credential helpers, or
- you want opencode to commit/push on your behalf.
