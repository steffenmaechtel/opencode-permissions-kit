# Allow docker and ddev in a project

This guide shows how to give a project's agent access to docker and ddev
against the kit's rootless backend — and which rule order matters.

## The two states

Whether the session's **final** permission config enables container tools
decides what it gets — there is exactly one backend mode (rootless) either
way:

| | **no ddev/docker** | **with ddev/docker** |
|---|---|---|
| Enabled by | final config has no docker/ddev allow | final merged `permission.bash` allows `docker *` / `ddev *` (broadly, not subcommand-only) — from the project's `opencode.json[c]` or the opencode user's global config |
| opencode runs as | `opencode` user | `opencode` user, `DOCKER_HOST` → the user's rootless socket (docker-rootless), or the daemonless podman CLI |
| ddev | denied | runs as `opencode` — always (terminal and agent) |

The wrapper asks opencode itself for that final config (`opencode debug
config`, resolved as the `opencode` user from the project directory), so a
broad allow counts no matter which file declares it. If the probe is
unavailable (opencode too old for `debug config`, sudo denied), it falls
back to scanning the project config only.

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

The wrapper prints the detected tools and starts opencode with the backend
right away. The bundled global config denies `docker *` / `ddev *` (and
their `sudo` forms), so nothing is granted implicitly.

## Enable container tools for every project

The per-project opt-in above is the default recommendation. If you want
docker/ddev in **every** session — including projects without their own
`opencode.json[c]` — flip the broad denies to allows in the opencode user's
**global** config:

```bash
sudo sed -i 's/"docker \*": "deny"/"docker *": "allow"/; s/"ddev \*": "deny"/"ddev *": "allow"/' /home/opencode/.config/opencode/opencode.jsonc
```

Flip the values **where they are** — do not move or re-add rules: the
credential gates `"ddev auth ssh*": "deny"` and `"sudo ddev auth ssh*":
"deny"` sit **after** the allows in the bundled template and must stay
there (same last-match-wins logic as below). The wrapper detects global
allows because it evaluates the final merged config, and every session in
every project directory then starts with the rootless backend connected.
Treat this as a deliberate trust decision: it also enables container tools
for projects you never opted in individually.

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
