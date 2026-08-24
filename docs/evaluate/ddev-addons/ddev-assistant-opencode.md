# Evaluate: e0ipso/ddev-assistant-opencode

> Evaluated: 2026-08-24 · Issue
> [#41](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/41)
> · Verdict: **Conflicting (collapses the agent into the app container
> — the opposite of the kit's separation goal)**
> · Source: <https://github.com/e0ipso/ddev-assistant-opencode>
> (README; last commit 2026-05-18, minimal docs)

## What it does

Installs opencode **into the web container image**
(`curl opencode.ai/install | bash` → `/usr/local/bin/opencode`); usage
is plain `ddev exec opencode` — agent and project stack share one
container. Bind-mounts the host `~/.config/opencode`,
`~/.cache/opencode`, `~/.local/share/opencode` into the web container
at identical paths; pre/post-start hooks chown them to the web user.

## Identity / secrets

- Runs as the web container's default user (ddev's host-uid mapping;
  under the kit's rootless backend = the `opencode` UID).
- **Weakest secret posture of the three addons:** the host user's
  entire opencode auth/config/cache is mounted inside the **application
  container** — arbitrary project code (vendor scripts, CMS plugins)
  can read the API keys and poison config.

## Lifecycle

ddev-bound: `ddev stop` kills the agent; the binary is baked into the
image (addon changes need a rebuild).

## Fit with the kit

- **Unique property:** because it mounts the host opencode home, the
  kit's `/home/opencode/.config/opencode/opencode.jsonc` **would be
  picked up — the soft-layer denies would still apply** (the kit runs
  ddev as `opencode`, so `~` resolves to the kit's config).
- **But the threat model inverts:** the kit separates the agent from
  the developer; this puts the agent *inside the attack surface* (the
  app container) — agent, PHP app, and any `composer install`
  post-install script share one filesystem and process user. State
  writes flow both ways (container agent mutates host config/cache).
- No agent-side containers (no DinD provided; a DinD addon inside the
  web container would be an untested combination).

## Verdict

**Conflicting.** Interesting proof that the kit's config layer is
portable into a container, but the containment direction is wrong for
the kit's guarantees.
