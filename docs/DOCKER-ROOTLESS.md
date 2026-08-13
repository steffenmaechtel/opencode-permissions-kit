# Docker Rootless — Design & Implementation Plan

> Status: **Phase 1 + 2 + 3 (docker-rootless e2e) implemented; ddev-shim env pass-through pending.**
> This document is the design record for removing the root-equivalence of the
> kit's docker grant. The authoritative usage documentation for the *current*
> container-tools feature is `docs/CONTAINER-TOOLS.md` (design record) and
> `docs/MANUAL.md` (usage).
>
> **Phase 1 (done):** backend awareness — `CONTAINER_BACKEND` in `install.conf`,
> wrapper/status/sudoers react to it, `DDEV_VERSION` recorded.
>
> **Phase 2 (done):** install-time provisioning — `install.sh` detects the
> container situation and offers an interactive backend choice (or
> `--container-backend` for scripts). `config.sh container-backend` switches
> post-install. The shared `setup-container-backend.sh` installs packages
> (`uidmap`, `dbus-user-session`, `podman`/`docker-ce-rootless-extras`,
> `slirp4netns`), auto-allocates non-overlapping `/etc/subuid` + `/etc/subgid`
> ranges for `opencode`, and for `docker-rootless` runs
> `dockerd-rootless-setuptool.sh` + enables linger. `podman-rootless` is
> daemonless (no socket, no linger).
>
> **Phase 3 (partially done):** the `docker-rootless` daemon e2e is implemented
> (`tests/e2e/run-docker-rootless.sh`, systemd-in-container suite). Still
> pending: the ddev-shim `DOCKER_HOST`/`XDG_RUNTIME_DIR` pass-through.
>
> The §9.1 ACL-bind-mount proposition is **proven by e2e** for both rootless
> backends: podman via run.sh section 12i, docker via run-docker-rootless.sh.

## 1. The Problem (confirmed)

The kit's opt-in container feature grants the docker **group** to the sandbox:

```
sudo -u opencode -g docker /usr/local/lib/opencode-permissions-kit/bin/opencode "$@"
```

Anyone who can talk to the docker socket can escalate to root on the host — a
container with `-v /:/host --privileged` (or even without `--privileged` on a
bind mount) reads and rewrites the entire host filesystem. So **yes: with the
current grant, opencode has root-equivalent rights on the host for the whole
session**, and it can trivially read `settings.php`, `.env`, SSH keys, etc.
*inside a container* even though the same files are hard-denied on the host via
ACLs. That is the gap this plan closes.

The `ddev` path is different and deliberately less of a concern: `ddev` is
delegated to the developer (`DEFAULT_USER`) via the shim, and the developer is
a trusted human who owns those files anyway. The security problem is the raw
`docker` path running **as the `opencode` user**.

## 2. How Rootless Removes the Escalation

Docker Rootless and Podman both run containers in a **user namespace**: the
container's "root" (uid 0) maps to an *unprivileged* host UID (via the
`/etc/subuid`/`/etc/subgid` ranges of the user that runs the daemon). The daemon
itself runs unprivileged, so there is no setuid/root path.

The kit-specific payoff: **if the container backend runs as the `opencode`
user, then everything the container does on the host is done as `opencode`'s
host UID.** The kit's hard ACL denies (`u:opencode:---` on `*settings.php`,
`*.env*`, `*auth.json`, keys, …) therefore still hold *inside* bind-mounted
containers. `docker run -v "$PWD:/app" ... cat /app/config/system/settings.php`
and `ddev exec cat settings.php` would be denied, exactly like `cat` on the
host. Rootless turns the container sandbox into an extension of the existing
ACL sandbox instead of a hole through it.

Prerequisites (both options):

- `uidmap` + `dbus-user-session` installed.
- `/etc/subuid` + `/etc/subgid` entries for the user running the backend.
- `systemd --user` + `loginctl enable-linger` for a daemon that must survive
  logout (docker rootless daemon, podman socket for ddev).

## 3. Options

| | A. Classic docker group *(status quo)* | B. Docker Rootless | C. Podman rootless |
|---|---|---|---|
| Daemon | root-owned `dockerd`, `/var/run/docker.sock` (group `docker`) | per-user `dockerd`, socket at `/run/user/<uid>/docker.sock` | none (podman); optional `podman.socket` |
| Container root maps to | host root | the daemon user's host UID | the invoking user's host UID |
| opencode escalation | **root on host** | confined to `opencode` UID → ACLs hold | confined to `opencode` UID → ACLs hold |
| Lifecycle for the sandbox user | n/a (system daemon) | `systemctl --user` + `loginctl enable-linger opencode` | on-demand (`podman` CLI); socket+linger only if ddev needs it |
| Privileged ports (<1024) | yes | **no** → ddev router must use 8080/8443 | **no** |
| ddev support | yes | yes (ddev ≥1.25) | yes (ddev ≥1.25, `podman-docker` or context) |
| Kit changes | none | moderate | moderate |

## 4. Security Analysis per Command Path

| Path | Backend | Effective host privilege |
|---|---|---|
| raw `docker` as `opencode` | classic group | **root** — the hole |
| raw `docker` as `opencode` | rootless daemon owned by `opencode` | `opencode` UID → ACL denies hold |
| raw `docker` as `opencode` | rootless daemon owned by developer | developer UID → ACL denies **bypassed**, but not root |
| `ddev` as developer (shim) | classic / developer rootless | developer (trusted human); unchanged by this plan |

The essential consequence: the strongest option is a **rootless backend owned by
the `opencode` user** for raw docker, because only that preserves the ACL denies.
Pointing opencode at the *developer's* rootless socket would remove only the
root step, not the "read everything" step, so it is not a substitute.

### 4.1 ddev cannot be closed on the ACL layer

The kit's ACL denies only ever target the `opencode` user (`u:opencode:---`).
`ddev` is delegated to the **developer**, and the developer *must* be able to
read the project's own secrets — the application itself reads `.env` /
`settings.php` at runtime. The only way to force ddev under those ACLs would be
to run ddev (and therefore its containers) as `opencode`, which is exactly what
failed during the original implementation (`CONTAINER-TOOLS.md` §4.3): `ddev
start` then rewrites host files as `opencode`, collides with the kit's
protections, and the app can no longer read its own secrets.

ddev is therefore **not securable on the OS/ACL layer**. The only protection is
the soft policy layer: the global template denies `"ddev *"`, a project must
opt in explicitly, and it should allow only harmless subcommands while denying
`ddev exec` / `ddev ssh` / `ddev composer` (anything that reaches the container
shell/filesystem). "ddev enabled" == "the agent inherits developer access" —
that is structural, not a missing feature.

### 4.2 Rootless reads exactly what `opencode` may read — only `deny` becomes an ACL

Only `deny` rules become filesystem ACLs; `ask` and `allow` affect opencode's
prompts only and never produce an ACL (see `MANUAL.md` "Customizing the Deny
List"). Because a rootless container runs with the `opencode` host UID, it can
read exactly what `opencode` itself can read on the host — and no more:

| Template rule | ACL deny? | Rootless container access |
|---|---|---|
| `deny` (e.g. `.env`, `settings.php`, `README.md`, keys, `auth.json`) | yes (`u:opencode:---`) | **blocked** |
| `ask` (e.g. `README.txt`) | no | readable — the soft prompt does not apply inside a container |
| `allow` / no rule (normal source) | no | readable (intended) |

Rootless neither over- nor under-blocks relative to the sandbox: it is the host
ACL sandbox, extended into the container. A file that is only `ask` (e.g.
`README.txt`) therefore stays readable — that is not a rootless leak, but the
template's deliberate choice to keep ddev working (see `files/opencode.jsonc`).

## 5. Target Architecture

Introduce a **container backend** concept, recorded in `install.conf`, with the
wrapper/status aware of it. The backend only governs *how* container tools are
reached — it does **not** change the policy layer (docker/ddev stay denied in
`opencode.jsonc`; the wrapper remains the only path).

```
CONTAINER_BACKEND=  # docker-group (default/legacy) | docker-rootless | podman-rootless
OPENCODE_DOCKER_HOST=  # for docker-rootless: unix:///run/user/<opencode-uid>/docker.sock
OPENCODE_PODMAN_SOCKET= # for podman-rootless: unix:///run/user/<opencode-uid>/podman/podman.sock
```

**The two-daemon reality (important, and unavoidable):**

- `ddev` *must* keep running as the developer. The reason ddev is delegated
  today is host-file ownership: `ddev start` rewrites `settings.php` /
  `config/system/*.php` / `.ddev` build dirs with the launching user's
  ownership. If ddev ran under a backend owned by `opencode`, it would write
  those files as `opencode` and collide with the kit's own protections. ddev
  therefore keeps using the **developer's** docker/podman.
- raw `docker` *should* run against a backend owned by **`opencode`** so the
  ACL denies hold.

Consequence: `docker ps` inside the sandbox will **not** list ddev's containers
(different daemon/user). This is accepted — the agent drives ddev through
`ddev`, and raw `docker` is for its own one-off containers. This trade-off must
be documented in `MANUAL.md`.

## 6. Detailed Decisions

### 6.1 `-g docker` becomes "enable container tools"

The wrapper keeps accepting `-g docker` / `--gid docker` (and the auto-detect
path), but its *meaning* becomes backend-dependent:

- `docker-group` → current behaviour (`sudo -u opencode -g docker`).
- `docker-rootless` / `podman-rootless` → run **without** `-g`, and instead set
  `DOCKER_HOST` to `OPENCODE_DOCKER_HOST` / `OPENCODE_PODMAN_SOCKET` in the
  environment passed to opencode.

Before starting, the wrapper verifies the socket is reachable and, if not,
falls back to running without container tools and prints a loud warning
(never silently downgrade to `-g docker` — that would reintroduce the hole).

The probe runs from the **`opencode` user's own context**, not the developer's:
rootless sockets live in the `opencode` runtime dir (`/run/user/<uid>`, mode
`700` `opencode:opencode`), which a developer-running wrapper cannot stat —
`test -S` from the developer always fails even when the daemon is up. The
wrapper therefore tries the direct check first (works when it runs as root or
as `opencode` itself) and otherwise re-runs the kit's `bin/socket-check.sh`
(nothing but `test -S`) via the NOPASSWD sudoers rule
`DEFAULT_USER ALL=(opencode) NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/socket-check.sh *`.

### 6.2 Environment hand-off (`sudo` resets env)

The wrapper starts opencode via `sudo -u opencode`, which resets the
environment. `OPENCODE_LAUNCH_CWD` is already preserved via
`Defaults env_keep`. For rootless we must also preserve `DOCKER_HOST` (and
`XDG_RUNTIME_DIR` where the socket lives) in `sudoers.template`:

```
Defaults env_keep += "OPENCODE_LAUNCH_CWD DOCKER_HOST XDG_RUNTIME_DIR"
```

### 6.3 ddev shim — pass the developer's backend through

The ddev shim does `sudo -u <developer> <DDEV_BIN> "$@"`. With a classic
backend the developer reaches docker via the default socket, so nothing is
needed. With a **rootless developer backend**, the developer's `DOCKER_HOST`
is lost across `sudo -u`. The shim must re-export it, e.g.
`sudo -u <developer> --preserve-env=DOCKER_HOST,XDG_RUNTIME_DIR <DDEV_BIN> ...`
(subject to the sudoers rule permitting it), or `sudo -u <developer> env
DOCKER_HOST=... <DDEV_BIN> ...`. Open question §9.5.

### 6.4 install.sh

- Detect the container situation: classic docker (`/var/run/docker.sock` +
  `docker` group), docker rootless (`/run/user/*/docker.sock`), podman
  (`command -v podman`), or absent.
- Ask which backend to use; default to `docker-group` (no behaviour change for
  existing setups) unless the machine is already rootless-only.
- When `docker-rootless` or `podman-rootless` is chosen: ensure `uidmap` +
  `dbus-user-session`, add `subuid`/`subgid` ranges for **`opencode`** (and
  for the developer if they run rootless too), set up the backend as the
  `opencode` user (rootless setup **must** run as that user, not as root),
  and `loginctl enable-linger opencode`.
- Record `CONTAINER_BACKEND`, `OPENCODE_DOCKER_HOST` / `OPENCODE_PODMAN_SOCKET`
  in `install.conf`.

### 6.5 Other scripts

- `sudoers.template`: drop the `(opencode:docker)` RunAs line when the backend
  is not `docker-group`; add the env_keep entries above.
- `status.sh`: replace the "docker group / reachable via `-g docker`" block
  with a backend-aware block (backend, socket, reachability, linger state).
- `config.sh`: optional `container-backend` subcommand to switch backends
  post-install (mirrors the `git-config` subcommand).
- `uninstall.sh`: optionally tear down the opencode rootless backend
  (`systemctl --user` stop/disable, linger off, subuid/subgid cleanup) when
  the kit created it — never touch a backend the developer set up themselves.
- `update.sh`: deploy the new wrapper/sudoers; preserve the backend keys in
  `install.conf` (same pattern as `DDEV_BIN`).
- `opencode.jsonc` / `jsonc-parser.py`: **unchanged** — policy (deny) and
  detection (`--tools`) are independent of the backend.

### 6.6 Host-system impact — what actually changes

The kit does **not** reinstall or replace Docker, and it does **not** convert
the host to rootless. Rootless is *per-user* by design: opting in adds a
separate backend for the `opencode` user **alongside** whatever the developer
already uses. The developer's docker (system daemon or Docker Desktop) is
never stopped, disabled, removed, or reconfigured.

| What | docker-rootless | podman-rootless |
|---|---|---|
| Packages installed (only if missing) | `uidmap`, `dbus-user-session`, `docker-ce-rootless-extras` | `uidmap`, `dbus-user-session`, `podman` |
| Docker reinstalled / replaced? | **no** | n/a (podman is a new, separate program) |
| System files touched | `/etc/subuid` + `/etc/subgid`: a free range for `opencode` (and the developer, only if they opt in too) | same |
| Per-user artefacts | systemd `--user` unit, storage under `/home/opencode/.local/share/docker`, socket `/run/user/<opencode-uid>/docker.sock` | storage under `/home/opencode/.local/share/containers`; socket only if ddev needs it |
| Linger | `loginctl enable-linger opencode` | only if a socket is used |
| Developer's docker / images / containers | untouched | untouched |
| Project files / ACLs | untouched | untouched |

`docker-ce-rootless-extras` is the only Docker-related package that might be
added — it ships `dockerd-rootless-setuptool.sh` and `dockerd-rootless.sh`,
not a second Docker installation. The existing system `dockerd` keeps running
as before.

**Install-time flow (how it is triggered):** `install.sh` asks for the backend
to use for opencode, e.g. *"Container backend for opencode: docker-group
(default) / docker-rootless / podman / none"*. Only choosing `docker-rootless`
or `podman` triggers the provisioning above; the default `docker-group` makes
**no** host change. The chosen backend is recorded in `install.conf` and can be
changed later via `config.sh container-backend` (see §6.5). It is therefore an
explicit opt-in, not an automatic conversion of the machine.

### 6.7 Backend selection & defaults

**Why offer both docker-rootless and podman-rootless at all?** Because the goal
is *minimal host impact* (§6.6): take what the developer already runs instead of
forcing a second container runtime onto the machine. The opencode backend is
decoupled from ddev (ddev always uses the developer's backend), so the choice is
purely "which safe raw container CLI do we give the agent, and how little do we
install for it". Docker developers pay only for rootless-extras + subuid;
podman developers pay nothing.

**Default: docker-rootless.** The target audience (DDEV/WSL2) overwhelmingly
runs Docker; the kit already speaks "docker" everywhere (`-g docker`, `docker *`
deny/allow rules, `--tools` detection), and docker-rootless keeps that exact
CLI semantics behind a safer socket. podman-rootless is the right choice only
when the developer already runs podman (nothing new to install) — its cost is
lost `docker` CLI parity (the agent uses `podman`; `docker *` allow rules do
not apply, see §9.8).

**Decision flow at install time** (auto-detect, in priority order):

1. **docker-rootless already active for `opencode`** → use it and just tell the
   user ("rootless docker already running as opencode — using it"). No change.
2. **else podman available** (`command -v podman`) → use podman-rootless and
   tell the user ("using your existing podman").
3. **else neither is set up yet** → present an interactive choice:
   - `docker-rootless` **(Recommended)** — no root-equivalence, ACL denies hold
     inside containers.
   - `podman-rootless` — no root-equivalence, but no `docker` CLI parity.
   - `docker-group` (legacy) — **WARNING: opencode gets root-equivalent access
     on the host via docker** (only for machines where rootless cannot run).
   - `none` — no container access at all; opt-in projects simply get no
     container tools.

**Non-interactive (`--yes`) safety:** the default answer must not silently
provision rootless (that installs packages and edits `/etc/subuid` without
consent). `--yes` therefore keeps `docker-group` (status quo, zero host change);
explicit selection for scripting is done via a flag, e.g.
`--container-backend docker-rootless|podman-rootless|docker-group`.

### 6.8 ddev version gate (DDEV ≥ 1.25)

Docker Rootless and Podman are only supported by **DDEV ≥ 1.25** (see
[ddev.com/blog/podman-and-docker-rootless](https://ddev.com/blog/podman-and-docker-rootless/));
ddev auto-detects the runtime once installed. That gate applies to the
**developer's ddev** side — the kit's raw-docker rootless backend for `opencode`
is independent of the ddev version, and the ddev shim is version-agnostic.

Therefore the check is **detect + record + warn**, not a hard install block:

- **Detect at install/update:** query the *real* binary `"$DDEV_BIN" version`
  (never `command -v ddev` — that resolves to the shim), parse `vX.Y.Z`, and
  record `DDEV_VERSION=` in `install.conf` (like `DDEV_BIN`).
- **Warn when rootless is selected but ddev < 1.25:** "ddev delegation keeps
  using the developer's classic docker; Docker Rootless/Podman for ddev needs
  ddev ≥ 1.25 — upgrade ddev first". This is advisory because (a) the opencode
  raw-docker backend works regardless, and (b) the developer's runtime is their
  own choice.
- **`status.sh` reports the version** and flags a `< 1.25` ddev next to a
  rootless backend selection.
- ddev absent → skip the check and warn about ddev's absence (as install.sh
  already does).

## 7. Phased Rollout

1. **Phase 1 — backend awareness (DONE).** `CONTAINER_BACKEND` is recorded in
   `install.conf` (default `docker-group`); the wrapper maps `-g docker` /
   auto-detect to the configured backend (docker group for `docker-group`,
   `DOCKER_HOST` + socket reachability for the rootless backends, never silently
   downgrading to `-g docker`); `status.sh` reports the backend + socket + ddev
   version; the sudoers render keeps the `(opencode:docker)` grant for
   `docker-group` and strips it for the rootless backends
   (`env_keep` gains `DOCKER_HOST`/`XDG_RUNTIME_DIR`). `install.sh` also records
   `DDEV_VERSION`. Nothing changes for existing installs. An admin who already
   runs rootless for the `opencode` user can point the kit at it manually (edit
   `install.conf` + `update.sh`). Tests: `tests/test-container-backend.sh`.
2. **Phase 2 — setup helpers (DONE).** `install.sh` detects the container
   situation and offers an interactive backend choice (or `--container-backend`
   flag for scripts). `config.sh container-backend` switches post-install. The
   shared `setup-container-backend.sh` installs packages, auto-allocates
   subuid/subgid for `opencode`, and for `docker-rootless` runs
   `dockerd-rootless-setuptool.sh` + enables linger. `podman-rootless` is
   daemonless. E2E section 12i exercises provisioning + the §9.1 proof
   end-to-end via `config.sh`.
3. **Phase 3 — ddev shim env pass-through + docker-rootless e2e.** The
   ddev-shim `--preserve-env=DOCKER_HOST,XDG_RUNTIME_DIR` pass-through for the
   *developer's* rootless socket — only matters once a developer runs rootless
   too; and a `docker-rootless` daemon e2e (heavier setup than podman's
   daemonless path). **The docker-rootless daemon e2e is DONE** — the kit's
   real provisioning path (`config.sh container-backend docker-rootless` →
   `setup-container-backend.sh` → get.docker.com → subuid/subgid →
   `dockerd-rootless-setuptool.sh` → `systemctl --user` → linger) is exercised
   end-to-end in `tests/e2e/run-docker-rootless.sh`, a separate systemd-based
   e2e container (`Dockerfile.rootless`, `make e2e-rootless`). It covers the
   wrapper's socket-check sudoers fallback (the 0700 `/run/user/<uid>`
   scenario), proves the rootless daemon runs as the opencode UID (not root),
   and re-proves §9.1 with real dockerd. **ddev-shim env pass-through remains
   pending.**

## 8. Implementation Footprint

| File | Change |
|---|---|
| `files/install.sh` | detect backend, prompt for it, provision rootless for `opencode` (subuid/subgid, rootless setup as `opencode`, linger), record `CONTAINER_BACKEND`/socket in `install.conf`; detect + record `DDEV_VERSION` (warn if < 1.25 when rootless selected) |
| `files/update.sh` | deploy new files; preserve new `install.conf` keys (like `DDEV_BIN`) |
| `files/config.sh` | `container-backend` subcommand (on/off/status) |
| `files/status.sh` | backend-aware container block (backend, socket, reachability, linger) + ddev version gate |
| `files/uninstall.sh` | optionally tear down a kit-created opencode rootless backend |
| `files/sudoers.template` | env_keep for `DOCKER_HOST`/`XDG_RUNTIME_DIR`; drop `(opencode:docker)` when not docker-group |
| `files/opencode-permissions-kit-lib/wrapper` | map `-g docker`/auto-detect to the configured backend; set `DOCKER_HOST`; verify reachability; loud fallback |
| `files/opencode-permissions-kit-lib/bin/ddev` | preserve the developer's `DOCKER_HOST`/`XDG_RUNTIME_DIR` across `sudo -u` |
| `docs/MANUAL.md` | document backends, the two-daemon `docker ps` caveat, privileged-port caveat |
| `tests/` | wrapper backend mapping; sudoers rendering per backend; ddev shim env; e2e backend sections |

`opencode.jsonc`, `opencode-deny-all.jsonc`, `jsonc-parser.py`, the git hooks,
and `protect-projects.sh` are unchanged.

## 9. Open Questions / To Verify at Implement Time

> Decisions recorded here (Phase 1 retrospective) are the agreed direction for
> Phase 2 / 3. Items still marked "verify" need a real rootless environment.

1. **Does the ACL deny actually survive a rootless bind mount?** Verify that a
   container started by a daemon running as `opencode` accesses a
   `u:opencode:---` file as the opencode host UID (denied). This is the core
   value proposition and must be proven in e2e (Phase 3), not assumed.
   *Status: **PROVEN** — `tests/e2e/run.sh` section 12i runs a real rootless
   podman container as the `opencode` user (nested user namespaces in the
   `--privileged` e2e image, `opencode` subuid/subgid 100000–165535) that
   bind-mounts the project and asserts `cat /app/.env` is denied
   (`u:opencode:---` ACL survives the bind mount) while `cat /app/index.php`
   succeeds. Re-proven with **real dockerd** in `tests/e2e/run-docker-rootless.sh`
   section RL4, which additionally asserts the daemon runs as the opencode host
   UID (`docker run alpine id -u` == the opencode UID), i.e. the rootless
   daemon is not root-equivalent. Verified end-to-end.*
2. **Running `systemctl --user` / rootless setup as the `opencode` user.** The
   installer runs as root; rootless setup and linger must be executed as
   `opencode` (`sudo -u opencode …`, `loginctl enable-linger opencode`).
   Confirm this works headless under WSL2 (`dbus-user-session` required).
   *Phase 2.*
3. **subuid/subgid ranges.** **Decision: the kit allocates them automatically.**
   `install.sh`/`config.sh` (Phase 2) picks a free range for `opencode` (and for
   the developer only if they opt in too) and writes `/etc/subuid` + `/etc/subgid`.
   Non-overlapping with any existing entry; never reuses an existing range.
4. **Privileged ports.** Rootless cannot bind 80/443 → ddev's router must use
   8080/8443 (`ddev config global --router-http-port=8080 …`). **Decision:
   documentation-only** — record in `MANUAL.md` (and a `status.sh` hint) that
   rootless forces the high ports; the kit does not rewrite the developer's ddev
   config.
5. **ddev shim env pass-through.** `sudo -u <developer>` drops `DOCKER_HOST`.
   **Decision: `--preserve-env=DOCKER_HOST,XDG_RUNTIME_DIR`** in the ddev shim,
   backed by a matching `env_keep` for the developer's env in the sudoers rule
   (Phase 3). Fallback remains re-exporting a recorded developer socket from
   `install.conf` if `--preserve-env` proves unreliable on the target sudo.
6. **WSL2 / Docker Desktop vs. in-distro rootless.** Docker Desktop's daemon
   lives in a separate VM and is *not* what rootless-in-distro replaces.
   Recommend Docker Engine **rootless inside the distro** (not Docker Desktop)
   as the backend; verify DDEV works against it in WSL2. *Still to verify.*
7. **Overlay storage under `/home/opencode`.** The rootless backend stores
   images under `/home/opencode/.local/share/containers`; confirm the home-dir
   ownership/mode (`opencode:www-data 2750`) does not block it. *Phase 2.*
8. **`podman-docker` vs a real `docker` CLI.** **Decision: podman-CLI only, no
   `docker` shim.** When podman is the chosen backend, the agent uses `podman`; a
   project's `docker *` allow rules do **not** match, and that asymmetry is
   documented in `MANUAL.md`. Never shadow a real `docker` binary. The wrapper's
   `podman-rootless` branch is therefore daemonless: when `OPENCODE_PODMAN_SOCKET`
   is empty it verifies `command -v podman` and runs opencode **without** exporting
   `DOCKER_HOST` (no docker-CLI compat). The optional `OPENCODE_PODMAN_SOCKET`
   re-enables docker-CLI compat (verified like the docker-rootless socket).
 9. **e2e inside the test container.** Running rootless inside the e2e image
    needs nested user namespaces and subuid ranges configured in the test
    image; verify feasibility before Phase 3. *Status: **FEASIBLE & DONE** — the
    `--privileged` ubuntu:24.04 e2e image supports nested user namespaces;
    `tests/e2e/run.sh` section 12i installs `podman` + `uidmap` + `slirp4netns`,
    allocates the `opencode` subuid/subgid range, and runs the §9.1 proof. On a
    runner whose kernel disallows it, the section SKIPs (counts as skipped, not
    failed) so CI stays green. When the OUTER docker is rootless (dev hosts),
    the container runs in a nested user namespace and section 12i seeds an
    in-range subuid range (`opencode:4096:60000`) before provisioning — the
    kit's default 231072+ range lies outside the container's uid map and would
    make `newuidmap` EPERM (same adaptation as the docker-rootless suite).*
    *docker-rootless: **FEASIBLE & DONE** — `tests/e2e/run-docker-rootless.sh`
    uses a separate systemd-based e2e container (`Dockerfile.rootless`) so the
    kit's real provisioning path (which hard-requires `systemctl --user`) can run
    end-to-end. It SKIPs wholesale when systemd-in-container or nested user
    namespaces are unavailable.
    The container layout adapts to the OUTER docker daemon (auto-detected by
    `tests/e2e/lib.sh` `e2e_detect_host_layout` via a probe container's
    `/proc/self/uid_map`):
    - **Container cgroup mode is identical on both layouts**: the systemd
      container always runs with `--cgroupns=private` (Docker's own default) and
      **no** `/sys/fs/cgroup` bind. This is the only mode where the nested
      ROOTLESS inner dockerd's `/proc/self/cgroup` paths match its
      `/sys/fs/cgroup` view (its `user-<uid>.slice` resolves inside its own
      delegated subtree). The classic `cgroupns=host` + host cgroup bind makes
      systemd boot, but the inner daemon then looks for
      `user.slice/user-<uid>.slice` at the visible host-root tree where it does
      not exist, so every inner `docker run` fails with "no such file or
      directory".
    - **What the layout detection gates is the nested user namespace.** On a
      rootless host the e2e container itself runs in a nested userns, so the RL2
      prep seeds an in-range subuid/subgid (`opencode:4096:60000`, because the
      kit's default 100000+ range lies outside the container's uid map and would
      EPERM in `newuidmap`); on a rootful host the container has the full uid
      space and the seed is skipped. The `fuse-overlayfs` storage-driver pin
      applies on BOTH layouts (nested kernel overlay can never stack on the
      container's own overlay rootfs, `mount ... invalid argument`); on a real
      (non-nested) install the kit still uses the default native driver.*
10. **DDEV ≥ 1.25 gate (§6.8) parsing.** **Decision: parse a semver
   `vX.Y.Z` / `X.Y.Z` token from the real binary's `ddev version` output** (first
   semver match), recorded as `DDEV_VERSION` and surfaced by `status.sh`, which
   flags a `< 1.25` ddev next to a rootless backend. Advisory only — never a hard
   install block (the `opencode` raw-docker backend works regardless of ddev).
   *Already implemented in Phase 1 (detection + recording + status display);
   the warn fires once Phase 2 makes rootless selectable.*

## 10. Migration & Compatibility

- `CONTAINER_BACKEND` defaults to `docker-group`; existing installs behave
  exactly as today after `update.sh`.
- `update.sh` treats the new `install.conf` keys like `DDEV_BIN` (preserve,
  never clobber); `uninstall.sh` only tears down backends the kit created.
- Switching backends is a `config.sh` operation and reversible.

## 11. Non-Goals

- Not changing the default away from `docker-group` automatically — rootless
  is opt-in.
- Not sandboxing `ddev` beyond the developer (the developer is trusted; ddev's
  delegation is about host-file ownership, not the agent). ddev cannot be
  closed on the ACL layer — see §4.1.
- Not replacing the ACL denies — rootless is a complement, not a substitute;
  the deny rules in `opencode.jsonc` and the wrapper's single-path policy stay.
- Not supporting `bubblewrap`/`sbx`-style process sandboxes here (see
  `local/IDEA-BUBBLEWRAP+DDEV.md` / `local/IDEA-SBX+DDEV.md` for those
  explorations — out of scope for this doc).
