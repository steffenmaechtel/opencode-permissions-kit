# Harden .git/config

Block (or allow) the agent's access to `.git/config`.

`.git/config` can contain remote URLs with embedded credentials. The kit's
deny blocks opencode's **tools** (read/edit + a `*.git/config*` bash
tripwire) — a bash-spawned `cat .git/config` is not OS-blocked (soft-only,
see the [security model](../concepts/security-model.md)).

**What the toggle does not touch:** git itself. Plain commits, plain
pushes and branch operations only *read* `.git/config` — but the
exceptions are real and documented: a first `git push -u` and
`git branch --set-upstream-to` fail at their *tracking write* while the
push transfer itself completes; repo-scope `git config` fails outright
(the write IS the operation); `git submodule add` dies at the clone
stage (the `modules` container accepts no agent writes). All of these
fail with `Operation not permitted` under the `.git` heal (issue
[#644](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/644)).
Agents push without `-u`; the full cost list lives in the
[security model](../concepts/security-model.md).

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
     plain commits/pushes only read .git/config — the exceptions (push -u tracking write,
     repo-scope git config, submodule add) are the .git heal's documented costs
```

```text
  git-config     OFF — access allowed (agent tools may edit git config)
     /home/opencode/.config/opencode/opencode.jsonc
     plain commits/pushes only read .git/config — the exceptions (push -u tracking write,
     repo-scope git config, submodule add) are the .git heal's documented costs
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
from any repository — git-config(1) documents the redirect (framing it
as expert/per-command use; the standing global form below is our
deliberate recommendation — on a kit machine the trade is usually
right):

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
