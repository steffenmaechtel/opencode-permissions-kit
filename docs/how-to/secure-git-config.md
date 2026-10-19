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
`opencode.jsonc.bak-*` next to it) — but note both states render from the
kit template, so manual edits to the file are always replaced.

`status` keeps the `ON`/`OFF` prefix (it mirrors the `on`/`off` commands)
and spells out what the state means — the same wording `opk status` shows:

```text
  git-config     ON — protected (soft-only — agent tools blocked)
     /home/opencode/.config/opencode/opencode.jsonc
```

```text
  git-config     OFF — access allowed (agent tools may edit git config)
     /home/opencode/.config/opencode/opencode.jsonc
```

A config left over from an older kit version (or hand-edited) may still
carry the `//SECURE_GIT` comment markers — rules present but inactive.
Both `status` and `opk status` report that state with the same hint on
the detail line; `on`/`off` re-render from the template and drop the
markers:

```text
  git-config     OFF — access allowed (agent tools may edit git config)
     /home/opencode/.config/opencode/opencode.jsonc (markers present, rules inactive)
```

## When to enable

- Remote URLs contain embedded tokens (`https://user:token@host/...`), or
- you don't want opencode to run git at all.

## When to leave it open

- SSH remotes or credential helpers, or
- you want opencode to commit/push on your behalf.
