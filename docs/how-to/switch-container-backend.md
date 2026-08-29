# Switch the container backend

This guide shows how to switch between docker-rootless and podman-rootless
on an installed kit.

The backend is configured at install time (`--container-backend
docker-rootless|podman-rootless`) and can be switched at any time:

```bash
opk config container-backend podman-rootless
```

Check the current backend and socket state:

```bash
opk config container-backend status
```

## What the switch does

Rootless provisioning (packages, subuid/subgid auto-allocation, linger) is
handled by `setup-container-backend.sh`:

- **docker-rootless** — per-user daemon, started via
  `dockerd-rootless-setuptool.sh`, linger enabled so the socket exists
  without a login; the socket path lands in `OPENCODE_DOCKER_HOST`.
- **podman-rootless** — daemonless (no socket, no linger); an optional
  `OPENCODE_PODMAN_SOCKET` enables docker-CLI compatibility.

An unknown backend value produces a loud warning and **no** container
tools — there is no silent fallback to a root-equivalent path. Re-run
`install.sh --container-backend docker-rootless|podman-rootless` to fix
the configuration.

## After the switch

- Containers/images pulled into the old backend do not carry over — the
  next `ddev start` re-pulls into the new backend (slow once).
- Verify with `status.sh` that the new socket (docker-rootless) or CLI
  (podman-rootless) is reachable before starting a session.
