# Evaluate: trebormc/ddev-opencode

> Evaluated: 2026-08-24 · Issue
> [#41](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/41)
> · Verdict: **Conflicting (viable replacement only for Drupal-only
> workflows that accept no host tooling and no agent-side docker)**
> · Source: <https://addons.ddev.com/addons/trebormc/ddev-opencode> —
> verified against a local clone @ `b972091`
> (`docker-compose.opencode.yaml`, `opencode-build/Dockerfile.opencode`,
> `install.yaml`)

## What it does

Dedicated sidecar service `opencode` (container
`ddev-<site>-opencode`, `command: ["sleep", "infinity"]`, `restart:
"no"`, `depends_on` web + playwright-mcp + beads + agents-sync).
opencode is installed in the image via npm; an entrypoint hook does
optional self-update. The agent reaches the web container via SSH — the
sidecar image **vendors its own sshd** with an `ai-ssh-command.sh`
ForceCommand wrapper (same pattern as ddev-ai-ssh); Playwright-MCP and
Beads sidecars via HTTP; **deliberately no Docker socket** in the agent
container. Interaction: `ddev opencode` / `ddev oc` → TUI. Part of the
"DDEV AI Workspace" ecosystem (auto-installs ai-ssh, agents-sync,
beads, playwright-mcp); Drupal-centric (syncs 10 agents / 12 rules /
24 skills).

Source-verified details (@ `b972091`): `user:
"${DDEV_UID:-1000}:${DDEV_GID:-1000}"`; the Dockerfile writes a
sudoers line granting the container user passwordless ALL; only
`auth.json` is shared from the host ("only auth.json, not the full
directory"); the host config dir is mounted **read-only** and
deep-merged by the entrypoint (cascade: project `opencode.json` > host
`~/.ddev/opencode/config/` > synced agents volume > baked defaults);
agents/rules arrive via a read-only volume with subpath mounts.

## Identity / files / secrets

- Runs as `user: ${DDEV_UID:-1000}:${DDEV_GID:-1000}` — under the kit
  that would be the `opencode` UID, consistent file ownership on the
  bind-mounted `/var/www/html`.
- **But:** the image grants the container user `NOPASSWD:ALL` sudo
  inside the container — the agent is effectively root within its
  sidecar.
- Credentials: host `~/.ddev/opencode/auth.json` bind-mounted in —
  **one credential file shared across all ddev projects** on the host.

## Lifecycle

Fully ddev-bound: `ddev stop` kills the session, `ddev destroy`
removes containers/volumes. Config cascade deep-merged per start
(project `opencode.json` > host `~/.ddev/opencode/config/` > synced
agents volume > baked defaults).

## Fit with the kit

- **Would add:** zero agent footprint on the host outside
  `~/.ddev`; project-scoped agent.
- **What breaks:** a second opencode home inside the container — the
  kit's `/home/opencode/.config/opencode/opencode.jsonc` denies are not
  mounted, not applied (only `auth.json` is shared) → guaranteed
  permission-config drift between two agents. No Docker socket → the
  agent cannot run its own containers (the kit gives it a rootless
  daemon). No host tooling/git/IDE integration.

## Verdict

**Conflicting.** A parallel model, not an extension — adopting it means
abandoning the kit's single-agent, single-config, host-integrated
approach.
