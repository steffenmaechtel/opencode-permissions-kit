# Security model

What the kit guarantees, what it deliberately does not, and which residual
gaps remain.

## The three hard guarantees

The kit's hard guarantees are UID-level — file permissions are opencode's own
**soft** layer (see below):

| Guarantee | Mechanism |
|---|---|
| Agent ≠ developer | wrapper execs `sudo -u opencode`; the developer's home is `750` and not group-shared |
| Containers ≠ root | rootless backend owned by `opencode` (per-user socket / daemonless podman) |
| No developer-RunAs | sudoers carry only `(opencode)` rules — kit binary, socket probe, cwd check, ddev helper |

Concretely:

- the agent's processes run as `opencode`, never as the developer — no
  credentials, SSH keys, or dotfiles in `/home/<developer>` are reachable,
- the agent-resources migration moves `~/.agents` whole but only
  `~/.claude/skills` — credentials such as `~/.claude/.credentials.json`
  never cross into the agent's home,
- containers run under the `opencode` host UID via a rootless backend — the
  agent can never reach a root-equivalent docker socket,
- no code path executes as the developer (no RunAs-developer sudoers rule).

## The soft permission layer (deliberate trade-off)

File denies (`.env`, keys, `settings.php`, …) live in `opencode.jsonc` and
gate **opencode's own read/edit tools** plus lexical bash tripwires. They are
the "ddev must work" decision:

> Processes spawned outside opencode's tools (ddev, its containers, `cat` in
> bash) can read every project file — including `settings.php`, which ddev's
> web container needs to boot.

| Guarantee | Mechanism |
|---|---|
| File denies (`.env`, keys, …) | `opencode.jsonc` soft rules — opencode's tools + bash tripwires |
| Developer ↔ agent file sharing | the `opencode` usergroup: setgid + default group ACLs + umask 002 |
| ddev runs as one user | the `ddev()` function + the sudoers helper exec ddev as `opencode` |

One exception: **browser-opening commands** (`launch`, `mailpit`,
`phpmyadmin`, …) compute the URL as `opencode`, but the browser open runs as
the developer — it needs the Windows interop the agent must not have. See
[ddev integration](ddev-integration.md#browser-opening-commands).

## Known residual gaps

- **Bash-spawned reads** (`cat .env`) are only caught by the template's
  lexical ask-tripwires, never by the OS.
- **Bind-mounted containers** read the mounted tree freely (they run as the
  opencode host UID).
- **Renamed copies** of secrets are invisible to the name-based
  [leak scan](../how-to/customize-deny-list.md).
- **Handover symlink swaps:** the root-run `.ddev` handover re-tests every
  path component immediately before acting, but the gate is not atomic — a
  swap in the short window before the recursive pair stays undetected.
- The kit protects **locations, not information flows** — once content
  leaves the project roots, no scan recaptures it.
- **mkcert CA key in the agent's home (deliberate):** ddev signs its
  `*.ddev.site` certificates on the host, as the user running ddev — and
  that user is `opencode`. Install copies the CA (including the private
  key, mode `0600`) into `/home/opencode/.local/share/mkcert`; without a
  readable key ddev silently degrades to HTTP-only URLs. Residual risk: the
  agent user can mint leaf certificates your browsers trust (a TLS-MITM
  capability). The keyless alternative is ddev's `.ddev/custom_certs/`
  flow, at the cost of per-project manual provisioning.
- **Supply chain (trust assumption):** install and update stream kit files
  and the opencode binary over HTTPS without checksums or signatures, and
  rootless backend provisioning runs get.docker.com as root. Installing
  means trusting GitHub, the opencode releases, and get.docker.com at
  install time. The `KIT_BASE_URL` env override replaces the fetch target
  entirely — treat the install environment as trusted.
- **OpenChamber serve password in the agent env:** when the serve feature is
  configured, `OPENCODE_SERVER_PASSWORD` (and username) survive sudo's
  `env_reset` into the agent's environment. Not a privilege escalation — but
  pick a strong password.

## WSL2: the /mnt/c exposure

`C:` is mounted with the Windows session token — NTFS ACLs do not
distinguish WSL users, so with the default world-readable mount **every WSL
user (including the agent's) can read the whole Windows profile** (`.ssh/`,
`NTUSER.DAT`, browser data). The kit's UID separation only covers the Linux
side.

The kit reports the exposure in `opk status` and warns on every `opencode`
start until it is fixed. Manual fix via `/etc/wsl.conf` (the kit never edits
that file itself):

```ini
[automount]
enabled = true
options = "uid=1000,gid=1000,dmask=027,fmask=037"
```

Replace `uid`/`gid` with your default WSL user's values (check with
`id -u` / `id -g`): the goal is that the agent user ends up as "other", with
no bits.

> **After editing, restart WSL completely:** run `wsl --shutdown` from
> Windows, then reopen your WSL terminal — the mount options only take
> effect on a fresh WSL start.

## WSL2: the browser bridge

Device logins (`opencode console login` on 1.x, `opencode auth login` on 2.x)
open their verification URL through powershell.exe — which the `opencode`
user may not execute on a restricted mount. The kit keeps the login alive
without granting the agent anything:

- `sudo opk wsl-add-opencode-1-fix` — the only kit command that ever writes
  `/etc/wsl.conf` — places a kit-managed comment block at the top of the
  file. Its carrier line (a `#` comment) wins the bundled `open` package's
  scan, so the powershell lookup resolves into the kit library. Takes effect
  immediately; WSL itself only ever sees comments.
- There, `powershell.exe` is a harmless stand-in (`bin/browser-bridge`): it
  forwards to the real powershell.exe whenever the caller may execute it
  (you — the browser opens exactly as before) and exits 0 otherwise (the
  agent — the login keeps polling; open the printed URL in any browser).

Newer opencode versions (1.x ≥ 1.18.33, 2.x ≥ 2.0.18) bundle an opener that
access-checks powershell and falls back to `xdg-open` — no bridge needed.
Because WSL distros ship no `xdg-open` by default, the kit deploys a fallback
shim at `/usr/local/bin/xdg-open` (only while no real one exists;
`sudo apt install xdg-utils` works too).

`opk status` reports the bridge state; the wrapper warns on every start while
the carrier is missing. `OPK_BROWSER_BRIDGE_DEBUG=1` before a direct
invocation traces the decision. Uninstall asks before removing the block and
always removes the stand-in tree and the shim symlink.

## Other root-equivalent surfaces (audit)

Docker is not the only tool whose daemon socket means root. `opk status`
ships a **report-only audit** ("Root-equivalent access" section) that checks
these surfaces for agent reachability — the kit never changes them; removing
access is an admin decision:

| Surface | Why it matters | Default on WSL2 |
|---|---|---|
| Rootful docker socket (`/var/run/docker.sock`) / `docker` group | full root, classic escape | common on dev hosts |
| Docker/Rancher Desktop sockets under `/mnt/wsl` | root-equivalent, world-usable | present when integration is on |
| `containerd` socket | full root | root-only by default |
| LXD/LXC, libvirt (`lxd`, `libvirt` groups + sockets) | full root (host VMs/mounts) | not installed by default |
| `sudo`/`admin`/`wheel`/`disk`/`snap` groups for the agent user | full root | never granted by the kit |
| `wireshark`/`adm`/`systemd-journal` groups | not root, but can leak credentials | not granted by the kit |
| Windows interop (executing `.exe` via `/mnt/c`) | runs code as Windows user | blocked via the `/mnt/c` restriction |

Deliberately **not** flagged: `snapd`'s socket (gated by peer credentials)
and `newuidmap`/`newgidmap` (setuid, but bounded to `/etc/subuid` ranges —
required by the rootless backends). The audit is stat math only — no
privileged probes. Override the socket list with `ROOT_EQUIV_SOCKS="…"`.
