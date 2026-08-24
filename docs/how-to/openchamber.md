# Use OpenChamber with the kit

This guide shows how to run [OpenChamber](https://openchamber.dev) — a
web/desktop UI for opencode — on a machine where the kit owns the
`opencode` command.

## Why it needs a headless server

OpenChamber can manage the opencode server itself: it spawns
`opencode serve --hostname 127.0.0.1 --port <port>` in the background and
connects to it. That spawn is non-interactive — stdin is closed and
OpenChamber waits for the `opencode server listening on …` line on stdout.

The kit's wrapper has a **headless mode** for exactly this spawn
style: when the first argument is `serve`, it prints nothing on stdout,
asks nothing, and starts the server as the `opencode` user directly.
(Since 0.0.21 the wrapper is prompt-free in general — no `Press Enter`,
no `[Y/n]` — but headless mode additionally keeps stdout clean for
parsers.) Project-directory checks do not apply to
`serve` — sessions still get the global and per-project `opencode.jsonc`
permission rules (see [the wrapper](../concepts/wrapper.md)). The same
headless contract covers other ecosystem tools — `opencode run`
orchestrators (cezar, CI runners) and `opencode acp` IDE agents — see
[headless invocations](../concepts/wrapper.md#headless-invocations-serve-run-queries).

## Just run it

```bash
openchamber
```

OpenChamber finds `opencode` on your `PATH` — which is the kit's wrapper
at `/usr/local/bin/opencode` — and starts the managed server through it.
Everything runs under the kit's UID separation, exactly like a terminal
session.

With a UI password:

```bash
openchamber --ui-password be-creative-here
```

OpenChamber derives the server password from `--ui-password` and passes
it to the server as `OPENCODE_SERVER_PASSWORD`. The kit's sudoers rule
preserves that variable (and `OPENCODE_SERVER_USERNAME`, its Basic-auth
counterpart) across the `sudo -u opencode` exec, so the server actually
comes up with the password applied.

## Container tools in OpenChamber sessions

In serve mode the wrapper attaches the configured rootless backend
silently — a server process serves many projects, so there is no
per-project question at spawn time. Whether a session may run
`docker`/`ddev` is still decided per
project by the `opencode.jsonc` permission rules (see
[allow docker and ddev](container-tools.md)): projects without the allow
rules keep the deny. If no backend is configured or its socket is not
reachable, the server starts without container tools and says so on
stderr.

## Troubleshooting

- **"OpenCode process exited before serving"** — usually a self-installed
  opencode shadowing the wrapper: check for `~/.opencode/bin/opencode`
  (remove it, see [the wrapper](../concepts/wrapper.md)) or point
  OpenChamber at the wrapper explicitly:
  `OPENCODE_BINARY=/usr/local/bin/opencode openchamber`
- **Connecting to your own server** — if you prefer running the server
  yourself, start it via the wrapper (`opencode serve --port 4096`) and
  point OpenChamber at it with `OPENCODE_SKIP_START=true` and
  `OPENCODE_HOST=http://127.0.0.1:4096`.
