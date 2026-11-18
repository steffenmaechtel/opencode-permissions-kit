# Harden .git/config

Block (or allow) the agent's access to `.git/config`.

`.git/config` can contain remote URLs with embedded credentials. The kit's
deny blocks opencode's **tools** (read/edit + a `*.git/config*` bash
tripwire) — a bash-spawned `cat .git/config` is not OS-blocked (soft-only,
see the [security model](../concepts/security-model.md)).

**Git operations are unaffected either way:** git only *reads*
`.git/config` — commits, pushes and branch operations never write it.
Turning the deny on does not stop the agent from committing or pushing
(a misconception worth heading off — the toggle gates opencode's own
tools, not the git binary). Since the `.git` heal (issue [#644](
https://github.com/steffenmaechtel/opencode-permissions-kit/issues/644))
the config file is additionally pinned developer-owned OS-side by every
group-baseline run — see the [security model](../concepts/security-model.md).

## Switch it on or off

At install time, pass `--secure-git-config` to the installer — the
one-liner lives in [Getting started](../getting-started.md#install),
all flags in [the CLI reference](../reference/cli.md).

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
     git operations are unaffected — git only reads .git/config; commits and pushes never write it
```

```text
  git-config     OFF — access allowed (agent tools may edit git config)
     /home/opencode/.config/opencode/opencode.jsonc
     git operations are unaffected — git only reads .git/config; commits and pushes never write it
```

## When to enable

- Remote URLs contain embedded tokens (`https://user:token@host/...`), or
- you don't want opencode to run git at all.

## When to leave it open

- SSH remotes or credential helpers, or
- you want opencode to commit/push on your behalf (with the deny on, the
  agent's own read/edit tools lose the file, but its git commands work
  the same).

## Disable all hooks for your user (defense in depth)

Independent of the kit, you can stop YOUR git from executing any hook
from any repository — git-config(1) endorses the redirect:

```bash
git config --global core.hooksPath /dev/null
```

This disables every hook type, in every repo of your user, including
fresh clones. Limits: a repository-level `core.hooksPath` overrides the
global one (`core.hooksPath` is not part of git's protected
configuration), and project hook tooling (husky, pre-commit) stops
working — on a kit machine that trade is usually right. The kit's
`.git` heal closes the repo-config arms OS-side; this global switch is
the belt to its suspenders for everything the heal cannot reach.
