# Allow docker and ddev in a project

This guide shows how to give a project's agent access to docker and ddev
against the kit's rootless backend — and which rule order matters.

## The two states

Whether the project's `opencode.jsonc` enables container tools decides what
the session gets — there is exactly one backend mode (rootless) either way:

| | **no ddev/docker** | **with ddev/docker** |
|---|---|---|
| Enabled by | project has no docker/ddev allow | project `permission.bash` allows `docker *` / `ddev *` (broadly, not subcommand-only) |
| opencode runs as | `opencode` user | `opencode` user, `DOCKER_HOST` → the user's rootless socket (docker-rootless), or the daemonless podman CLI |
| ddev | denied | runs as `opencode` — always (terminal and agent) |

## Opt a project in

Create or edit `opencode.jsonc` in the **project root**:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "bash": {
            "ddev *": "allow",
            "docker *": "allow",
            // keep the credential gate even with ddev allowed (see below)
            "ddev auth ssh*": "deny",
            "sudo ddev auth ssh*": "deny"
        }
    }
}
```

Then start opencode in the project:

```bash
cd /var/www/vhosts/myproject/ && opencode
```

The wrapper prints the detected tools and asks `Y/n` before starting with the
backend. The bundled global config denies `docker *` / `ddev *` (and their
`sudo` forms), so nothing is granted implicitly.

## Why the deny line comes AFTER the allow

Project rules merge **last** (last matching rule wins) — a broad
`"ddev *": "allow"` overrides the global denies, including the credential
gate. Keep a specific `"ddev auth ssh*": "deny"` **after** your allow rules
(as in the example), or the agent can import — and then read — private keys
(see the trade-off in [ddev integration](../concepts/ddev-integration.md)).

## What to expect

- `docker ps` inside the session talks to the **opencode user's** daemon —
  containers you started in your own terminal (different daemon/user) are
  not listed. That is expected.
- ddev runs as the `opencode` user from both sides (your terminal uses the
  kit's `ddev()` function). The first `ddev start` is slow; later starts
  reuse the rootless daemon's state.
