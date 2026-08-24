# Evaluate: trebormc/ddev-ai-ssh

> Evaluated: 2026-08-24 · Issue
> [#41](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/41)
> · Verdict: **Not applicable (complement only for foreign-agent
> sidecar setups the kit does not have)**
> · Source: <https://github.com/trebormc/ddev-ai-ssh> (README; last
> commit 2026-07-09, active)

## What it does

Not an opencode runner — an infrastructure addon: installs
openssh-server into the **web container**, generates per-project
ed25519 keys in `.ddev/.agent-ssh-keys/` (gitignored), rewrites
`authorized_keys` on every `ddev start`, runs sshd under supervisord.
Consumers (opencode/claude-code sidecars) run `ssh web <cmd>`;
`ForceCommand` does `cd /var/www/html` + `eval
"$SSH_ORIGINAL_COMMAND"` — full arbitrary shell as the web user.

## Identity / secrets

- SSH sessions land as the ddev-mapped web user; `PermitRootLogin no`,
  key-only, no TCP/X11 forwarding.
- No API keys involved — but the per-project unpassphrased private key
  lives in the project tree, readable by anything that can read the
  project directory (including the agent itself).

## Lifecycle

sshd lives/dies with the web container; keys survive even addon
uninstall (documented).

## Fit with the kit

It exists so a **differently-owned agent container** can exec in the
web container without the Docker socket. The kit's one-owner model
(agent = ddev owner, direct wrapper handover) needs no indirection —
`ddev exec` already works for the agent. The `eval`-based
ForceCommand is deliberately full-access (soft-only at best), and the
addon adds a second network-reachable daemon (sshd) to the web
container.

## Verdict

**Not applicable.** Solves a problem the kit does not have; would only
matter if the kit ever shipped a sidecar-agent variant.
