# Rootless container backends — design reference

> Status: **CURRENT (reference).** How the kit provisions and runs its
> rootless container backends (docker-rootless, podman-rootless) for the
> `opencode` user. Successor of the current sections of the archived
> `docs/_archive/design/docker-rootless.md` (historical plan, ACL-era
> rationale); usage docs: [switch the container
> backend](../how-to/switch-container-backend.md); the security
> guarantee: [security model](../concepts/security-model.md).

## 1. Why rootless, and why per-user

Containers must never give the agent a root-equivalent path: whoever can
talk to a docker socket can escalate to root on the host (a container
with `-v /:/host` reads and rewrites everything). Rootless runtimes run
containers in a **user namespace** — the container's root maps to an
unprivileged host UID via the daemon user's `/etc/subuid`//`/etc/subgid`
ranges, and the daemon itself runs unprivileged.

The kit-specific payoff: **the backend is owned by the `opencode`
user**, so everything a container does on the host happens as the
`opencode` host UID — exactly what the agent itself could do, no more.
Pointing the agent at the *developer's* rootless socket would only
remove the root step, not the read-everything step; the legacy
`docker-group` backend (root-equivalent socket) is removed entirely.

In the soft-only model this is deliberately *not* a file-protection
mechanism: bind-mounted containers run as the `opencode` host UID and
can read every project file (ddev's web container needs that —
`settings.php`, `.env`). The guarantee is UID separation only; proven by
e2e: podman in `tests/e2e/run.sh` §12i, real dockerd in
`tests/e2e/run-docker-rootless.sh` (RL4 asserts the container uid_map
maps root to the opencode host UID).

| | docker-rootless | podman-rootless |
|---|---|---|
| Daemon | per-user `dockerd`, socket `unix:///run/user/<uid>/docker.sock` | none (daemonless CLI); optional `podman.socket` |
| Lifecycle | `systemctl --user` + `loginctl enable-linger opencode` | on-demand |
| CLI the agent uses | `docker` (familiar semantics) | `podman` (no `docker` CLI parity — see §5) |
| Prerequisites | `uidmap`, `dbus-user-session`, `docker-ce-rootless-extras` | `uidmap`, `dbus-user-session`, `podman`, `slirp4netns` |

ddev always runs as the `opencode` user against the SAME backend as the
agent (one daemon, one owner — see
[ddev-working](ddev-working.md)); the backend choice therefore only
governs which safe runtime the machine runs.

## 2. Backend selection & defaults

Decision flow at install time (auto-detect, priority order):

1. **docker-rootless already active for `opencode`** → reuse it, no change.
2. **else podman available** (`command -v podman`) → podman-rootless
   ("using your existing podman" — nothing new to install).
3. **else interactive choice**: `docker-rootless` (recommended),
   `podman-rootless`, or none. The legacy `docker-group` is no longer
   offered — the wrapper never falls back to a root-equivalent path.

**Default: docker-rootless.** The target audience (DDEV/WSL2)
overwhelmingly runs Docker, the kit's permission rules speak `docker *`,
and docker-rootless keeps that CLI behind a safer socket.
podman-rootless is the right choice when the developer already runs
podman.

**Non-interactive (`--yes`) safety:** provisioning installs packages and
edits `/etc/subuid` — never silently. `--yes` without an explicit
`--container-backend` asks nothing and provisions nothing; scripts pass
`--container-backend docker-rootless|podman-rootless` explicitly.

Post-install switch: `opencode-permissions-kit config container-backend
<backend>` (reversible, re-provisions via §3).

## 3. Provisioning reference (`setup-container-backend.sh`)

Runs as root, as the `opencode` user where noted. Idempotent — every
step is a no-op when already in place.

1. **Packages** (only if missing, via apt): `uidmap`,
   `dbus-user-session`, plus `docker-ce-rootless-extras` (docker) or
   `podman` + `slirp4netns` (podman). `docker-ce-rootless-extras` is the
   only Docker-related package ever added — it ships
   `dockerd-rootless-setuptool.sh`, not a second Docker.
2. **subuid/subgid auto-allocation:** a free contiguous range for
   `opencode` in `/etc/subuid` + `/etc/subgid` — starting at 100000,
   65536 entries per user, skipping any overlap with existing entries,
   never reusing another user's range. Existing entries for `opencode`
   are kept as-is.
3. **docker-rootless only:** enable linger (starts the `systemd --user`
   manager for a user that has no login session), then run
   `dockerd-rootless-setuptool.sh install` **as `opencode`** (rootless
   setup must never run as root), enable + start
   `systemctl --user docker.service`.
4. **Router ports:** rootless containers cannot bind <1024 unless
   `net.ipv4.ip_unprivileged_port_start <= 80` — applied before the
   daemon starts (the netns inherits the value at start) via
   `/etc/sysctl.d/99-ddev-rootless.conf` when needed, so a fresh install
   is ddev-ready out of the box.
5. **Socket path** is printed for the caller to record in
   `install.conf` (`OPENCODE_DOCKER_HOST`). podman-rootless prints
   nothing (daemonless).

The wrapper re-probes the socket on every start — from the `opencode`
user's own context via the `socket-check.sh` sudoers rule, because
`/run/user/<uid>` is mode 700 and a developer-running wrapper cannot
stat inside it. Unreachable socket → run WITHOUT container tools + loud
warning, never a downgrade to a root-equivalent path.

## 4. Host impact — what the kit touches

The kit does not reinstall or replace Docker and does not convert the
host to rootless. Rootless is per-user: opting in adds a backend for
`opencode` **alongside** whatever the developer runs. The developer's
docker (system daemon or Docker Desktop) is never stopped, disabled,
removed, or reconfigured.

| What | docker-rootless | podman-rootless |
|---|---|---|
| Packages installed (only if missing) | `uidmap`, `dbus-user-session`, `docker-ce-rootless-extras` (via Docker's apt repo / get.docker.com when the distro doesn't ship it) | `uidmap`, `dbus-user-session`, `podman`, `slirp4netns` |
| System files | `/etc/subuid` + `/etc/subgid`: one range for `opencode` | same |
| Per-user artifacts | systemd `--user` unit, storage under `~opencode/.local/share/docker`, socket in `/run/user/<uid>` | storage under `~opencode/.local/share/containers` |
| Linger | `loginctl enable-linger opencode` | not needed (daemonless) |
| Developer's docker / images / containers | untouched | untouched |

Tear-down on uninstall happens only for backends the kit created.

## 5. The podman-CLI path (no docker shim)

When podman is the backend, the agent uses `podman` — the kit never
installs a `docker` alias and never shadows a real `docker` binary. A
project's `docker *` permission rules therefore do NOT match on the
podman backend (documented asymmetry; use `podman *` rules). The
optional `OPENCODE_PODMAN_SOCKET` re-enables docker-CLI compatibility
(point a `docker` CLI at the podman socket); when set, the wrapper
verifies its reachability like the docker-rootless socket.

## 6. ddev version gate and ports

Docker Rootless and Podman require **ddev ≥ 1.25** (advisory, not an
install block — the agent's raw-container backend is independent of
ddev): install/update detect + record `DDEV_VERSION` in `install.conf`
(querying the real binary, never a PATH shim), `status.sh` flags a
< 1.25 ddev next to a rootless backend. Rootless router ports: either
the §3.4 sysctl (kit default) or ddev's documented high-port alternative
(`ddev config global --router-http-port 8080 --router-https-port 8443`).
