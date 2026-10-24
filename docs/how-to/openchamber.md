# Use OpenChamber with the kit

Run [OpenChamber](https://openchamber.dev) — a web/desktop UI for opencode —
on a machine where the kit owns the `opencode` command.

## Why it works

OpenChamber manages the opencode server itself: it spawns
`opencode serve --hostname 127.0.0.1 --port <port>` in the background and
waits for the `opencode server listening on …` line on stdout. The kit's
wrapper has a **headless mode** for exactly this spawn style: when the first
argument is `serve`, it prints nothing on stdout, asks nothing, and starts
the server as the `opencode` user directly. The permission rules (global and
per-project `opencode.jsonc`) still apply — see
[headless invocations](../concepts/wrapper.md#headless-invocations-serve-run-queries).

## OpenChamber 2.x requires opencode 2.0.20+

OpenChamber 2.x checks the opencode version (through the kit's wrapper)
before starting the managed server; with an older opencode you get an update
screen instead of the app. Keep the upgrade inside the kit:

```bash
sudo opk upgrade-opencode --major 2      # latest opencode 2.x
sudo opk upgrade-opencode --version 2.0.26
```

Do **not** use OpenChamber's own update affordances:

- The **"OpenCode update" toast** fails harmlessly (no install method for
  the kit's binary; nothing is written).
- The **one-click update screen** (below 2.0.20) is the dangerous one: it
  installs its *own* opencode to `~/.opencode/bin/opencode` and pins that
  path in `~/.config/openchamber/settings.json`. From then on the managed
  server runs **as you, outside the kit** — no UID separation, no permission
  layer, while terminal sessions stay secured.

If the one-click install already happened, recovery has **two steps** — the
settings pin must go too. `sudo opk openchamber-secure` does both; manually:

1. Delete `~/.opencode/bin/opencode` (and the `opencode2` shim next to it).
2. Remove the `opencodeBinary` line from
   `~/.config/openchamber/settings.json` (or set it to `""`), then restart
   OpenChamber.

Deleting the binaries alone is not enough: a pin pointing at a deleted
binary aborts the managed server start — the UI hangs loading and its API
answers `"OpenCode port is not available"`. The kit's wrapper warns on every
terminal session start while bypass files are present; `opk status` shows
the same state without starting a session.

## Prevent the bypass: the policy pin

OpenChamber honors an admin-owned policy file, `/etc/openchamber/policy.json`.
Pinned to the kit wrapper it makes every OpenChamber surface — web UI,
desktop app, VS Code extension — spawn `/usr/local/bin/opencode` regardless
of its settings pin, environment variables, or PATH, including
**retroactively**: an existing one-click pin is defused without anything to
clean up first. OpenChamber's own update affordances stop working; updates
go through `opk upgrade-opencode` exclusively.

The kit can own that file for you — **opt-in**, because it changes
third-party app behavior:

- **At install time**: answer *Yes* to "Protect OpenChamber sessions too?"
  (asked when OpenChamber is detected; `--openchamber-policy yes|no` for
  unattended installs — under `--yes` without the flag the pin stays off).
- **Any time later**:

  ```bash
  sudo opk openchamber-secure
  ```

  Writes the pin, removes leftover bypass binaries and the settings pin
  (asks first; `--yes` skips the question), and records the opt-in so
  `opk update` re-applies the pin after kit updates — a policy file with
  other content is never overwritten by an update. `opk uninstall` removes
  it only when it still pins the kit wrapper.

The manual equivalent of what the command writes:

```bash
sudo mkdir -p /etc/openchamber
printf '{ "opencodeBinary": "/usr/local/bin/opencode" }\n' \
    | sudo tee /etc/openchamber/policy.json
sudo chown root:root /etc/openchamber/policy.json
sudo chmod 644 /etc/openchamber/policy.json
```

Desktop note: an Electron desktop app running **inside** WSL reads this
file; a Windows-side desktop app reads Windows policy paths instead — run
the desktop app inside WSL or pin it in its Windows policy location.

## Just run it

```bash
openchamber
```

OpenChamber finds `opencode` on your `PATH` — the kit's wrapper — and starts
the managed server through it. Everything runs under the kit's UID
separation, exactly like a terminal session. With a UI password:

```bash
openchamber --ui-password be-creative-here
```

OpenChamber derives the server password from `--ui-password` and passes it
to the server as `OPENCODE_SERVER_PASSWORD`; the kit's sudoers rule
preserves that variable (and its Basic-auth counterpart) across the
`sudo -u opencode` exec.

## Container tools in OpenChamber sessions

In serve mode the wrapper attaches the configured rootless backend silently
— a server process serves many projects. Whether a session may actually run
`docker`/`ddev` is still decided per project by the `opencode.jsonc`
permission rules (see [allow docker and ddev](container-tools.md)). If no
backend is configured or its socket is not reachable, the server starts
without container tools and says so on stderr.

## Server working directory

OpenChamber starts the managed server with a working directory of its own
choosing — by default **your home directory**, which the `opencode` user
cannot read (that is the UID separation doing its job). The server still
boots, but every request that loads config for its working directory
answers HTTP 500. Point OpenChamber at a directory the `opencode` user can
read — your projects root — and persist it:

```bash
echo 'export OPENCHAMBER_OPENCODE_CWD=/var/www/vhosts' >> ~/.bashrc
```

OpenChamber reads the variable at startup only; restart it after changing
it. Directory-scoped requests follow the directory selected in the UI — pick
your actual project there. Without the variable, the wrapper still catches
the case at `serve` start: it warns on stderr and starts the server from a
readable fallback — but the web UI swallows server stderr, so setting the
variable is the reliable fix.

## Projectless chats

A chat that is not tied to a project directory still needs a worktree; by
default those live under `~/.config/openchamber/chats` in **your** home,
which the `opencode` user cannot reach — every projectless chat would answer
HTTP 500. OpenChamber ≥ 1.22.2 relocates the root via `OPENCHAMBER_CHATS_DIR`.
Prepare it like a project root so both users can work in it:

```bash
sudo install -d -o "$USER" -g opencode -m 2775 /var/www/vhosts/openchamber-chats
sudo setfacl -d -m g:opencode:rwx /var/www/vhosts/openchamber-chats
echo 'export OPENCHAMBER_CHATS_DIR=/var/www/vhosts/openchamber-chats' >> ~/.bashrc
```

(`opencode` here is the kit's sharing group; adjust if yours differs —
`opk status` shows it under *Sharing*.) Existing chats are not moved — new
chats go to the new root. The VS Code mode has no projectless chats.

## Troubleshooting

- **Update screen instead of the app (OpenChamber 2.x)** — upgrade through
  the kit: `sudo opk upgrade-opencode --major 2`. See
  [OpenChamber 2.x requires opencode 2.0.20+](#openchamber-2x-requires-opencode-2020).
- **"OpenCode update" toast fails (HTTP 500)** — expected on a kit install;
  upgrade with `sudo opk upgrade-opencode` instead.
- **Sessions run outside the kit after an in-app update** — run
  `sudo opk openchamber-secure`, or delete `~/.opencode/bin/opencode` **and**
  remove the `opencodeBinary` settings line, then restart OpenChamber.
- **UI hangs loading, API answers "OpenCode port is not available"** — a
  stale `opencodeBinary` pin pointing at a deleted binary. Remove the line
  and restart OpenChamber.
- **HTTP 500 on `/api/*` requests** — the server's working directory is not
  readable by the `opencode` user. Set `OPENCHAMBER_OPENCODE_CWD` — see
  [Server working directory](#server-working-directory).
- **Projectless chats fail (HTTP 500)** — relocate the chats root with
  `OPENCHAMBER_CHATS_DIR` — see [Projectless chats](#projectless-chats).
- **"OpenCode process exited before serving"** — usually a self-installed
  opencode shadowing the wrapper: check for `~/.opencode/bin/opencode`
  (remove it), or point OpenChamber at the wrapper explicitly:
  `OPENCODE_BINARY=/usr/local/bin/opencode openchamber`.
- **Connecting to your own server** — start it via the wrapper
  (`opencode serve --port 4096`) and point OpenChamber at it with
  `OPENCODE_SKIP_START=true` and `OPENCODE_HOST=http://127.0.0.1:4096`.
