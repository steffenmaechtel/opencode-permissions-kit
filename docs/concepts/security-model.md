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
- containers run under the `opencode` host UID via a rootless backend —
  through the kit's backend the agent never reaches a root-equivalent
  docker socket (one env_keep exception lives in
  [Known residual gaps](#known-residual-gaps)),
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

## Download integrity (SHA256SUMS)

The streamed installer and updater fetch every kit file from
`raw.githubusercontent.com`. Since issue #478 each fetched file is
verified against the repo's **`SHA256SUMS`** manifest (fetched from the
same ref) before it enters the staging tree: the digest must match
exactly, or the install/update aborts — nothing is deployed, temps are
cleaned, and the error names the file plus expected/actual digests. The
manifest itself is shape-gated line by line (an HTML error body never
becomes a "manifest"), and `opk update` additionally re-verifies the
whole staged tree before any deploy phase runs. That tree pass also
covers trees an older deployed updater fetched without verification —
for updaters that export their staging tree (vintage 0.0.40 and later).
Vintages 0.0.29–0.0.39 re-exec the new updater without the export
marker and are indistinguishable from a manifest-less checkout, so
their **first** update into the verified era deploys unverified; the
update after that verifies. (Vintages ≤ 0.0.28 never reach the re-exec:
they predate the current file layout and abort with a re-install hint.)

What this buys:

- **Corruption detection** — truncated transfers, a broken mirror, or a
  captive portal's HTML page masquerading as a 200 file body can no
  longer reach `/usr/local/lib` as root.

What it deliberately does **not** buy:

- **Origin-compromise protection.** The manifest rides the same origin
  and ref as the files: an attacker able to replace the files can
  replace the manifest too, with matching digests. Protecting against
  that requires signed manifests (a public key shipped independently of
  the streamed scripts) — a deliberate Phase 2 non-goal for now.

Operational notes:

- `KIT_SHA_VERIFY=0` disables the mechanism (break-glass for tag pins
  that predate the manifest and for odd mirrors; only the operator sets
  their own environment — an attacker on the wire cannot).
- A missing or unusable `sha256sum` binary aborts the fetch loudly —
  verification is never silently skipped on the fetch paths. The one
  documented carve-out: a checkout of a pre-manifest vintage (no
  `SHA256SUMS` in the tree) heals a missing file without verification
  and without a message — local trust, see the code comments in
  `management/update.sh`.
- Refs without a manifest (tags older than the mechanism) fail closed
  under new code with a named error. Streaming an *old* tag's own
  `install.sh` keeps working as before: that script predates the
  mechanism entirely.
- Maintainer side: the manifest is regenerated with `make sums` and
  committed; the unit suite's freshness pin reddens on a stale manifest
  and `make release` refuses to cut a release from one.

## Known residual gaps

- **Bash-spawned reads** (`cat .env`) are only caught by the template's
  lexical ask-tripwires, never by the OS.
- **Git diff drivers render denied files:** `git diff *` and `git log *`
  are allowlisted, and the agent can write `.gitattributes` itself
  (`*.env diff=secret`). A planted `[diff "secret"] command = cat` driver
  then makes `git log -p` render denied file content, and the command
  text names no protected file, so no bash tripwire fires. The planting
  sites differ: `.git/config` is prompt-free only while its read/edit
  denies are off — a default install renders them active (the
  installer's recommended choice; `opk config git-config off` disables
  them) — while the agent's global gitconfig (kit-created for
  `safe.directory`, matched by no template rule) takes the same driver
  for one ask (`git config --global diff.secret.command cat` hits no
  allow and no tripwire) and then persists across sessions for every
  repo; the git-config toggle does not close that arm.
- **Bind-mounted containers** read the mounted tree freely (they run as the
  opencode host UID).
- **Renamed copies** of secrets are invisible to the name-based
  [leak scan](../how-to/customize-deny-list.md).
- **Handover symlink swaps:** the root-run `.ddev` handover and the ddev
  settings-dir pairs re-test every path component immediately before
  acting, but the gates are not atomic — a swap in the short window
  between a gate and its recursive pair stays undetected.
- **Dev-owned flag write (accepted race):** the dev-owned flag write into
  `.ddev/config.yaml` screens for symlinks but is not atomic — dev-owned
  mode's flag-write TOCTOU stays accepted. Its ceiling depends on the
  caller: the opencode-uid path (`ddev-as-opencode`) caps the effect at
  opencode privilege, while the root-run scan (install/update/
  `opk config` handovers) performs the same write as root, where that
  cap does not apply (see [ddev integration](ddev-integration.md)).
- **TMPDIR-rooted scratch re-open windows:** the root-run passes stage
  their work in `${TMPDIR:-/tmp}` and re-open staged files by name —
  the fs-baseline worker and uninstall's chown revert re-read their
  operand streams, the sudoers deploy installs a staged copy of the
  file visudo validated a moment earlier, and a streamed install later
  sources its whole verified fetch tree as the script directory. Under
  the defaults (sticky `/tmp`, `0600` temps, sudo `env_reset` — the
  sudoers template keeps no `TMPDIR`) those windows are benign; arming
  them takes an operator who points `TMPDIR` into an agent-writable,
  non-sticky directory before running the kit (`sudo -E`, `sudo env
  TMPDIR=…`). Uninstall's revert is the sharp edge: it runs as the
  developer with an inner `sudo`, so a dev-shell `TMPDIR` inside a
  group-writable project tree arms that site without `sudo -E`.
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
  and the opencode binary over HTTPS. Kit files carry SHA256SUMS
  integrity verification ([above](#download-integrity-sha256sums)) —
  corruption detection, not origin-compromise protection. The opencode
  binary is still verified only by a liveness check (`opencode --version`
  runs, not an integrity check), and rootless backend provisioning runs
  get.docker.com as root. Installing means trusting GitHub, the opencode
  releases, the npm registry and `opencode.ai/v2/install` (2.x binary
  resolution and the optional root-run installer fallback), and
  get.docker.com at install time. The `KIT_BASE_URL` env
  override replaces the fetch target entirely — treat the install
  environment as trusted.
- **Developer-shell `DOCKER_HOST` rides env_keep:** the sudoers template
  keeps `DOCKER_HOST`/`XDG_RUNTIME_DIR` into the agent session, but the
  wrapper pins its own values only in the socket-resolving arms —
  docker-rootless, and podman-rootless with `OPENCODE_PODMAN_SOCKET`
  configured — while the podman-CLI, unreachable-socket and no-backend
  arms export nothing, so a `DOCKER_HOST` set in the developer's shell
  survives `env_reset` and overrides the socket pinning recorded in
  `install.conf`; one naming a root-equivalent socket quietly breaks
  "Containers ≠ root" for that session. Only the developer's own
  environment arms it — unset `DOCKER_HOST` before starting `opencode`
  if your shell carries one.
- **OpenChamber serve password in the agent env:** when the serve feature is
  configured, `OPENCODE_SERVER_PASSWORD` (and username) survive sudo's
  `env_reset` into the agent's environment. Not a privilege escalation — but
  pick a strong password.
- **Agent-authored container opt-in:** the per-project container-tools
  opt-in is designed as project-owner consent, but the wrapper's probe
  cannot tell an owner-written `./opencode.jsonc` from one the agent
  wrote itself (the template's edit rules allow `*`): a
  `"docker *": "allow"` entry the agent writes flips the probe to
  "enabled by this project" without any prompt — only a note prints.
  Bounded by the rootless, agent-UID backend: the opt-in changes which
  tools run, not whose privileges they run with.
- **Checkout-first `opk` runs checkout code as root:** `opk` resolves its
  library relative to its own path, so an `opk` (or management script)
  invoked from a checkout executes that checkout's code — with root
  privileges via internal sudo for the elevating subcommands (`opk
  config`, `opk update` run `exec sudo sh` when the caller is not
  root) or a leading `sudo` for direct script calls, while `opk
  status`, `opk doctor` and unsudoed direct calls stay the invoking
  uid (still checkout code). On kit-managed machines the checkout is
  agent-group-writable, so an agent session could have planted
  content in `files/`. Deliberate design ("checkout-first by
  construction" — the developer's own sudo password is the gate where
  root is involved); see the repository's CONTRIBUTING.md for the
  contributor-side warning.

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
`sudo apt install xdg-utils` works too) and only while the installed
opencode still needs it — opencode ≥ 2.0.32 opens without one itself, so
on current 2.x the kit withholds the shim (1.x never got the upstream fix
and always keeps it).

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
