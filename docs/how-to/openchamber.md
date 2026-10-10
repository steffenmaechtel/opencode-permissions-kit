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

## OpenChamber 2.x requires opencode 2.0.20+

OpenChamber 2.x gates on the opencode version: it requires **opencode
2.0.20 or newer (major 2)** and checks that *before* starting the managed
server. With an older opencode — 1.x or an early 2.0 — the web UI never
opens; you get an update screen instead. The check runs through the kit's
wrapper (`opencode --version`), so the version OpenChamber sees is the
one the kit manages.

Keep the upgrade inside the kit:

```bash
sudo opk upgrade-opencode --major 2      # latest opencode 2.x
sudo opk upgrade-opencode --version 2.0.26
```

Do **not** use OpenChamber's own update affordances:

- **The "OpenCode update" toast** (shown when npm has a newer release)
  fails harmlessly on a kit install: the update button runs
  `opencode upgrade` through the wrapper, and opencode cannot detect an
  install method for the kit's standalone binary. OpenChamber reports
  the failed upgrade; nothing is written. `opk upgrade-opencode` remains
  the only working update path.
- **The one-click update screen** (below 2.0.20) is the dangerous one:
  it installs its *own* opencode to `~/.opencode/bin/opencode` and pins
  that path in `~/.config/openchamber/settings.json`. From then on the
  managed server runs **as you, outside the kit** — no UID separation,
  no permission layer for every OpenChamber session, while terminal
  sessions stay secured. It also starts opencode 2.x's background
  service in your user context (see the [background-service
  caveat](../reference/compatibility.md#caveats)).

If the one-click install already happened, recovery has **two steps** —
the settings pin must go too. `sudo opk openchamber-secure` does both
(and pins OpenChamber to the kit wrapper so it cannot happen again —
see [below](#prevent-the-bypass-the-policy-pin)); manually:

1. Delete `~/.opencode/bin/opencode` (and the `opencode2` shim next to
   it).
2. Remove the `opencodeBinary` line from
   `~/.config/openchamber/settings.json` (or set it to `""`), then
   restart OpenChamber.

Deleting the binaries alone is not enough: OpenChamber starts its
managed server with strict validation of the pinned path, and a pin
pointing at a deleted binary aborts the start — the UI hangs loading
and its API answers `"OpenCode port is not available"` (verified Oct
2026, survives a reboot). The stale pin stays silent as long as the
kit's opencode is below 2.0.20, because then the compatibility check
(which does fall back to the kit's wrapper) shows the update screen
before a start is ever attempted — the pin only strikes once the kit
reaches a compatible version again.

The kit's wrapper warns about all of this on every terminal session
start while bypass files are present (binaries and/or settings pin,
with state-specific fix advice) — `opk status` shows the same state
without starting a session.

## Prevent the bypass: the policy pin

OpenChamber honors an admin-owned policy file,
`/etc/openchamber/policy.json`. Pinned to the kit wrapper it makes every
OpenChamber surface — web UI, desktop app, VS Code extension — spawn
`/usr/local/bin/opencode` regardless of its settings pin, environment
variables, or PATH, including **retroactively**: an existing one-click
pin is defused without anything to clean up first (live-verified against
OpenChamber 2.2.0). OpenChamber's own update affordances stop working;
updates go through `opk upgrade-opencode` exclusively.

The kit can own that file for you — **opt-in**, because it changes
third-party app behavior:

- **At install time**: answer *Yes* to "Protect OpenChamber sessions
  too?" (asked when OpenChamber is detected; `--openchamber-policy
  yes|no` for unattended installs — under `--yes` without the flag the
  pin stays off).
- **Any time later**:

  ```bash
  sudo opk openchamber-secure
  ```

  Writes the pin, removes leftover bypass binaries and the settings pin
  (asks first; `--yes` skips the question), and records the opt-in so
  `opk update` re-applies the pin after kit updates. `opk uninstall`
  removes it again. `opk status` shows the OpenChamber state: *secured
  via policy pin*, *BYPASSED*, or the advice line when OpenChamber is
  present but unpinned.

The manual equivalent of what the command writes:

```bash
sudo mkdir -p /etc/openchamber
printf '{ "opencodeBinary": "/usr/local/bin/opencode" }\n' \
    | sudo tee /etc/openchamber/policy.json
sudo chown root:root /etc/openchamber/policy.json
sudo chmod 644 /etc/openchamber/policy.json
```

Desktop note: an Electron desktop app running **inside** WSL reads this
file; a Windows-side desktop app reads Windows policy paths instead —
run the desktop app inside WSL or pin it in its Windows policy location
yourself.

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

## Server working directory

OpenChamber starts the managed server with a working directory of its
own choosing — by default **your home directory**. Under the kit the
server runs as the `opencode` user, which usually cannot read your
`$HOME` (that is the UID separation doing its job). The server still
boots, but every request that loads config for its working directory —
`/session`, `/config`, `/project` — answers HTTP 500
(`Unexpected server error`): accessing `$HOME/opencode.jsonc` fails with
`EACCES`, and opencode treats that as a hard error instead of "no config
file".

Point OpenChamber at a directory the `opencode` user can read — your
projects root (the parent of the paths in `projects.conf`) — and persist
it in your shell:

```bash
echo 'export OPENCHAMBER_OPENCODE_CWD=/var/www/vhosts' >> ~/.bashrc
```

OpenChamber reads the variable at startup only; restart it after
changing it. Note that directory-scoped requests follow the directory
selected in the UI — pick your actual project there, otherwise they
fall back to the home directory and hit the same wall.

If you don't set the variable, the wrapper still catches the case at
`serve` start: it probes the server working directory from the
`opencode` user's context (`cwd-check`) and, when unreadable, warns
on **stderr** and starts the server from a readable fallback — the
projects root containing the directory, else the first readable
configured root, else the `opencode` user's home. The 500s disappear,
but the warning only reaches the terminal OpenChamber was started
from (its web UI swallows server stderr) — setting
`OPENCHAMBER_OPENCODE_CWD` keeps the server directory deterministic
and silences the warning.

## Projectless chats

A chat that is not tied to a project directory still needs a worktree —
OpenChamber creates one directory per chat and the opencode server
works inside it. By default those worktrees live under
`~/.config/openchamber/chats` in **your** home, which the `opencode`
user cannot reach under the kit's UID separation — every projectless
chat answered HTTP 500
([openchamber#3130](https://github.com/openchamber/openchamber/issues/3130)).

Since **OpenChamber 1.22.2** the chats root is relocatable: set
`OPENCHAMBER_CHATS_DIR` to a directory both users can work in. Prepare
it like a project root — sharing group, setgid, and default ACLs, so
directories created by OpenChamber (running as you) stay writable by
the `opencode` server user:

```bash
sudo install -d -o "$USER" -g opencode -m 2775 /var/www/vhosts/openchamber-chats
sudo setfacl -d -m g:opencode:rwx /var/www/vhosts/openchamber-chats
echo 'export OPENCHAMBER_CHATS_DIR=/var/www/vhosts/openchamber-chats' >> ~/.bashrc
```

(`opencode` here is the kit's sharing group; adjust if yours differs —
`opk status` shows it under *Sharing*.) OpenChamber reads the variable
at startup only; restart it after changing it. Existing chats are not
moved — new chats go to the new root, legacy chats under the old root
stay listed and deletable; unsetting the variable returns new chats to
the default root. Managed chats are a web/desktop feature — the VS Code
mode has no projectless chats.

## Troubleshooting

- **Update screen instead of the app (OpenChamber 2.x)** — the
  kit-managed opencode is older than OpenChamber 2.x's minimum
  (2.0.20, major 2). Upgrade through the kit
  (`sudo opk upgrade-opencode --major 2`), not through the in-app
  button — see
  [OpenChamber 2.x requires opencode 2.0.20+](#openchamber-2x-requires-opencode-2020).

- **"OpenCode update" toast, clicking Update fails (HTTP 500, "OpenCode
  CLI upgrade failed")** — expected on a kit install: the button runs
  `opencode upgrade` through the wrapper, which finds no install method
  for the kit's standalone binary. Nothing is written; upgrade with
  `sudo opk upgrade-opencode` instead.

- **OpenChamber sessions run outside the kit after an in-app update** —
  the one-click update installed its own opencode to
  `~/.opencode/bin/opencode` and pinned it in
  `~/.config/openchamber/settings.json`; the managed server now runs as
  you without the kit's UID separation. Run `sudo opk openchamber-secure`
  (pins OpenChamber to the kit wrapper and cleans both) or delete the
  binaries **and** remove the `opencodeBinary` settings line, then
  restart OpenChamber — see
  [OpenChamber 2.x requires opencode 2.0.20+](#openchamber-2x-requires-opencode-2020).

- **UI hangs loading, API answers "OpenCode port is not available"** —
  a stale `opencodeBinary` pin in
  `~/.config/openchamber/settings.json` pointing at a deleted binary
  aborts the managed server start. Typical after removing a
  self-installed opencode without clearing the pin, and it bites only
  once the kit's opencode is ≥ 2.0.20 again (below that the update
  screen masks it). Remove the line and restart OpenChamber — see
  [OpenChamber 2.x requires opencode 2.0.20+](#openchamber-2x-requires-opencode-2020).

- **HTTP 500 on `/api/*` requests (Unexpected server error)** — the
  managed server's working directory (your `$HOME`) is not readable by
  the `opencode` user. Set `OPENCHAMBER_OPENCODE_CWD` to a readable
  projects root — see
  [Server working directory](#server-working-directory). (The wrapper's
  automatic fallback covers this only when the kit's `cwd-check`
  sudoers rule is present — run `update.sh` if the warning stays away
  but the 500s don't.)

- **Projectless chats fail (HTTP 500 on `/api/session` with a
  `…/.config/openchamber/chats/…` directory)** — the chats root under
  your `$HOME` is unreachable for the `opencode` user (UID separation).
  OpenChamber 1.22.2 fixed this upstream: relocate the root with
  `OPENCHAMBER_CHATS_DIR` — see
  [Projectless chats](#projectless-chats). On older OpenChamber, work
  in project directories
  ([openchamber#3130](https://github.com/openchamber/openchamber/issues/3130)).

- **"OpenCode process exited before serving"** — usually a self-installed
  opencode shadowing the wrapper: check for `~/.opencode/bin/opencode`
  (remove it, see [the wrapper](../concepts/wrapper.md)) or point
  OpenChamber at the wrapper explicitly:
  `OPENCODE_BINARY=/usr/local/bin/opencode openchamber`
- **Connecting to your own server** — if you prefer running the server
  yourself, start it via the wrapper (`opencode serve --port 4096`) and
  point OpenChamber at it with `OPENCODE_SKIP_START=true` and
  `OPENCODE_HOST=http://127.0.0.1:4096`.
