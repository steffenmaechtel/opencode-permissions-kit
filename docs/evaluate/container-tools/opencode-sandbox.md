# Evaluate: opencode-sandbox (npm plugin)

> Evaluated: 2026-08-24 · Issue
> [#40](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/40)
> · Verdict: **Conflicting as a default; complementary only as a
> per-project opt-in network fence**
> · Source: <https://www.npmjs.com/package/opencode-sandbox> (v0.5.1;
> engine: Anthropic `@anthropic-ai/sandbox-runtime`)

## What it is

An opencode plugin wrapping every `bash` tool call via Anthropic's
`sandbox-runtime` (srt). On Linux: bubblewrap + bind mounts + seccomp
(AF_UNIX blocked by default) with the network namespace removed — all
traffic is forced through host HTTP/SOCKS proxies (over unix sockets via
`socat`) enforcing a **domain allowlist**. macOS uses Seatbelt; Windows
unsupported through opencode's hook. **Fail-open by design.**

Default policy: writes only to project + `/tmp`; deny-read `~/.ssh`,
`~/.docker/config.json`, `~/.npmrc`, `~/.env`; network allowlist (npmjs,
pypi, github, api.anthropic.com, …) — everything else blocked.
Configurable via `~/.config/opencode-sandbox/` (env / per-project /
global).

## Requirements

`bubblewrap`, `socat`, `ripgrep`; Ubuntu 24.04+ AppArmor fix (see the
bubblewrap record). First-class opencode integration
(`tool.execute.before/after` hooks; the UI hides the wrapper).

## Maturity

v0.5.1 (24 releases since Feb 2026), ~204 downloads/week, 44 stars,
single primary maintainer. The underlying srt engine has 5.1k stars but
is a self-described "Beta Research Preview".

## Fit with the kit

- **Would add:** per-command **network allowlisting** — the one layer
  the kit genuinely lacks (the kit confines files/UIDs, not network
  egress).
- **What breaks:** allow-write (project + `/tmp` only) kills `~/.ddev`,
  `~/.docker`, and rootless daemon state; the network allowlist blocks
  ddev image pulls and Packagist/Composer; seccomp AF_UNIX blocking
  cuts the `DOCKER_HOST` connection to the rootless daemon
  (re-enabling sockets = `allowAllUnixSockets`, which disables that
  layer).
- **Degradation:** fail-open means a broken setup silently falls back
  to the kit's existing soft model — no error signal.

## Verdict

**Not as a kit default** — it breaks the ddev workflow the kit exists
to keep working. **Possibly complementary** as a per-project opt-in for
non-ddev work that wants an egress fence (a project without container
tools could enable it independently of the kit; the kit does not need
to ship or configure it).
