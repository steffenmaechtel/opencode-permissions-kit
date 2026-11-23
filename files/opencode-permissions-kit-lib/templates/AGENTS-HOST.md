# Host notes for AI agents — opencode permissions kit

This host runs the **opencode permissions kit**. An agent session works
as the Linux user `opencode`, separate from the developer, and shares
each project with the developer through the group `opencode`. The kit
deliberately changes a few git behaviors. Everything below is expected —
none of it is a defect to repair, so never reach for `chown`, `chmod`
or `sudo` to "fix" it.

These notes are written for a session running as `opencode` (check
with `whoami`).

## First stop

`opk status` (no sudo) reports the kit's state. Run it before you
diagnose a git failure. Kit management (`sudo opk …`) is the
developer's job: when a note below says so, report what you did and
what failed instead of working around it.

## Git failures and what to do instead

**A command reports `could not write config file … Operation not
permitted`** — after `git push -u`, `git branch --set-upstream-to`,
`git switch -c <new> <origin/branch>` (it sets up tracking) or a
repo-scope `git config`. The repository's config is developer-owned by
design. Nothing else broke: with `git push -u` the push itself went
through, only the tracking entry is missing.
Push without `-u`: `git push origin <branch>`. Branch off a
remote-tracking branch with `--no-track`. Keep your settings in
`git config --global`.

**`git add`, `git switch`, `git merge` or `git pull` fails with
`unable to write new index file`, `couldn't set 'HEAD'` or
`update_ref failed`** — a developer git operation in the same checkout
flipped the owner of the metadata these commands rewrite.
Do not repair ownership. Work in a worktree of your own (below) and ask
the developer for `sudo opk git-heal on`: its hooks hand the metadata
back to you after every developer git operation.

**Moving, deleting or replacing a project's `.git` fails with
`Operation not permitted`** — `opk git-protection` seals a project's
`.git` into a pointer file: no longer a directory.
Leave it as it is: plain git commands work unchanged. Never write into
`.git/` by hand.

## Fallback: a worktree of your own

A worktree you created is yours alone — no developer operation can lock
you out there:

```sh
git worktree add <dir> -b <branch>
```

Commit and push from it as usual (without `-u`).

Background, and the developer's manual:
https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/how-to/agent-host-notes.md
