# Evaluate: trebormc/ddev-opencode

> Evaluated: 2026-08-24 · Issue
> [#41](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/41)
> · Verdict: **Conflicting (viable replacement only for Drupal-only
> workflows that accept no host tooling and no agent-side docker)**
> · Source: <https://addons.ddev.com/addons/trebormc/ddev-opencode>
> (README; last commit 2026-07-08, active, single maintainer)

## What it does

Dedicated sidecar service `ddev-<site>-opencode` (Ubuntu 24.04 +
Node 22, opencode via npm), `sleep infinity`, entrypoint hook with
optional self-update. The agent reaches the web container via SSH
(`ssh web` → drush/composer/phpunit helpers); Playwright-MCP and Beads
sidecars via HTTP; **deliberately no Docker socket** in the agent
container. Interaction: `ddev opencode` / `ddev oc` → TUI. Part of the
"DDEV AI Workspace" ecosystem (auto-installs ai-ssh, agents-sync,
beads, playwright-mcp); Drupal-centric (syncs 10 agents / 12 rules /
24 skills).

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
