# The wrapper

This page explains what happens on every `opencode` start and how the kit
protects the wrapper from being bypassed.

## The four steps

Every `opencode` invocation goes through the wrapper at
`/usr/local/bin/opencode`:

1. **Validate working directory** — the current directory must be inside a
   path listed in `projects.conf`. Otherwise opencode does not start.
2. **Detect container tools** — if the project's `opencode.jsonc` broadly
   allows docker/ddev, the wrapper proposes running with the configured
   rootless backend and asks for confirmation.
3. **Probe the backend** — docker-rootless: the per-user socket is verified
   reachable (as the `opencode` user, via the kit's `socket-check.sh`
   sudoers rule); podman-rootless: the `podman` CLI must be installed (an
   optional `OPENCODE_PODMAN_SOCKET` enables docker-CLI compat). An unknown
   backend value produces a loud warning and **no** container
   tools — never a silent fallback to a root-equivalent path.
4. **Execute** — `sudo -u opencode` with `DOCKER_HOST`/`XDG_RUNTIME_DIR`
   exported for the rootless socket (preserved across sudo via the kit's
   `env_keep`).

## The serve exception (headless start)

`opencode serve` does not go through these steps. Third-party UIs like
OpenChamber spawn the server non-interactively — stdin is `/dev/null` and
stdout is parsed for the `opencode server listening on <url>` line — so
banner, `Press Enter`, and the `[Y/n]` container question would break the
startup (and `read` on a closed stdin kills the wrapper before it execs).

In serve mode the wrapper therefore:

- skips the project-directory check — the server accepts sessions per
  client request, and the soft permission layer (global + per-project
  `opencode.jsonc`) still applies to every session,
- prints nothing on stdout; diagnostics (shadow binary, backend
  warnings) go to stderr,
- resolves container tools silently — a server serves many projects, so
  there is no single opt-in to confirm; whether a session may actually
  use docker/ddev stays decided by the `opencode.jsonc` rules.

`OPENCODE_SERVER_PASSWORD` is preserved across the `sudo -u opencode`
exec, so a password a UI passes to the server survives (see the
[OpenChamber how-to](../how-to/openchamber.md)).

## Self-update bypass protection (default-user deny-all)

opencode's installer and self-updater can re-add `~/.opencode/bin` to your
`PATH`. If that happens, typing `opencode` would run the real binary **as
your user** instead of the wrapper.

As a safety net, the kit installs a lockout config for the default user
(`~/.config/opencode/opencode.jsonc`) that denies **everything** — even if
the real binary takes over, it cannot read or modify anything. Template:
`files/opencode-deny-all.jsonc`.

- During `install.sh`, an existing file is renamed to
  `opencode.jsonc_BAK_<timestamp>` before the deny-all config is installed.
- `update.sh` only installs the lockout config when no config exists yet.
- To use opencode normally as your own user, delete or rename that config.

`install.sh` also removes a self-installed binary from `~/.opencode/bin`
(after securing its copy under the kit), so the wrapper starts without the
bypass warning.

## Wrapper-bypass guard (detect, then warn loudly)

1. **Binary exec restricted to root + the opencode usergroup.** The real
   binary at `/usr/local/lib/opencode-permissions-kit/bin/opencode` is owned
   `root:opencode` with mode `750`. Note: the developer is a member of the
   `opencode` group (file sharing), so the group bit grants them execution
   too — running the real binary as your user is mitigated by the deny-all
   config above, not by the mode bits.
2. **Shell-start warning.** `shell-warn.sh` is hooked into `~/.bashrc`,
   `~/.zshrc`, `~/.profile` and the profile.d script; every new shell prints
   a loud warning when a real `~/.opencode/bin/opencode` exists or
   `command -v opencode` resolves to anything but the wrapper.
3. **Wrapper self-check.** Every wrapper start re-checks both conditions.
