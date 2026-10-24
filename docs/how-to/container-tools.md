# Allow docker and ddev in a project

Give a project's agent access to docker and ddev against the kit's rootless
backend — and keep the rule order that matters.

## The two states

Whether the session's **final** permission config enables container tools
decides what it gets — there is exactly one backend mode (rootless) either
way:

| | **no ddev/docker** | **with ddev/docker** |
|---|---|---|
| Enabled by | final config has no docker/ddev allow | merged `permission.bash` allows `docker *` / `ddev *` |
| opencode runs as | `opencode` user | `opencode` user; `DOCKER_HOST` → rootless socket, or daemonless podman |
| ddev | denied | runs as `opencode` — always (terminal and agent) |

The wrapper asks opencode itself for that final config (`opencode debug
config`, resolved as the `opencode` user from the project directory), so a
broad allow counts no matter which file declares it. The allow must be
broad — `docker *` / `ddev *`, not subcommand-only — and may live in the
project's `opencode.json[c]` or in the opencode user's global config.

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
sudo sed -i 's/"docker \*": "deny"/"docker *": "allow"/; s/"ddev \*": "deny"/"ddev *": "allow"/' \
  /home/opencode/.config/opencode/opencode.jsonc
```

Flip the values **where they are** — do not move or re-add rules: the
credential gates `"ddev auth ssh*": "deny"` and `"sudo ddev auth ssh*":
"deny"` must stay **after** the allows. Treat this as a deliberate trust
decision: it also enables container tools for projects you never opted in
individually.

## Why the deny line comes AFTER the allow

Project rules merge **last** (last matching rule wins) — a broad
`"ddev *": "allow"` overrides the global denies, including the credential
gate. Keep a specific `"ddev auth ssh*": "deny"` **after** your allow rules
(as in the example), or the agent can import — and then read — private keys
(see the trade-off in [ddev integration](../concepts/ddev-integration.md#the-ssh-key-trade-off)).

## What to expect

- `docker ps` inside the session talks to the **opencode user's** daemon —
  containers you started in your own terminal (different daemon/user) are
  not listed. That is expected.
- ddev runs as the `opencode` user from both sides (your terminal uses the
  kit's `ddev()` function). The first `ddev start` is slow; later starts
  reuse the rootless daemon's state.
