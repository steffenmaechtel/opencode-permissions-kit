# Tell your agent about the kit

Point your AI agent at the notes the kit ships for it, so it knows
which git failures are expected on this host — and stops trying to
"fix" them.

## The problem this solves

The kit changes git behavior on purpose: the
[`.git` heal and its hooks](git-heal-hooks.md) and the
[git-protection pointer layout](git-protection.md). An agent that does
not know that debugs blind. It sees `Operation not permitted` on a
`git push -u` and may reach for `chown` or `chmod` to repair what is
working as designed.

## The host notes

The kit ships a short notes file for agents, the **host notes**:

```text
/usr/local/lib/opencode-permissions-kit/templates/AGENTS-HOST.md
```

It lists the expected git failures the kit documents for an agent's
main checkout, and what to do instead — nothing more: no script,
nothing that executes. It is not the full cost list of the `.git` heal
— that lives in the
[security model](../concepts/security-model.md). Read it yourself with
`cat` (it fits on one screen). `sudo opk update` keeps it current; on an
install that predates it, it appears with the first update that carries
it.

## Add the pointer

The kit never writes an `AGENTS.md` — placing the pointer is your step,
and a one-time one. opencode loads a global `AGENTS.md` from the agent's
config directory: `/home/opencode/.config/opencode/AGENTS.md` (create it
if it does not exist; you keep write access through the `opencode`
group). Copy the block verbatim:

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

The block carries the absolute path and nothing else, by design: a
copied block is yours, so the kit can never update it — it has to stay
valid for the life of the install. Everything that changes lives in
the notes file behind the path. **The path is a stability contract:**
the kit will not rename the file, and if it ever must, it leaves a
pointer behind at the old path.

A project's own `AGENTS.md` works the same way, but it is committed
with the project and travels to machines without a kit — keep the
pointer in the global file.

## What to expect

- The agent reads the notes before its first git command or
  file-permission change in a project — one small file per session.
- The notes file lies outside the project. With the kit's default agent
  config, opencode asks before any access outside the project
  (`external_directory` in the agent's `opencode.jsonc`): approve that
  request when it appears. A config you wrote yourself decides this on
  its own.
