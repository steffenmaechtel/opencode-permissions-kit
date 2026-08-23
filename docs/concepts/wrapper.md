# The wrapper

This page explains what happens on every `opencode` start and how the kit
protects the wrapper from being bypassed.

## The four steps

Every `opencode` invocation goes through the wrapper at
`/usr/local/bin/opencode`:

1. **Validate working directory** — the current directory must be inside a
   path listed in `projects.conf`. Otherwise opencode does not start.
2. **Detect container tools** — if the project's `opencode.jsonc` broadly
   allows docker/ddev, the wrapper attaches the configured rootless
   backend (no confirmation dialog — the state is visible in the TUI,
   see [mode display](#mode-display-in-the-tui)).
3. **Probe the backend** — docker-rootless: the per-user socket is verified
   reachable (as the `opencode` user, via the kit's `socket-check.sh`
   sudoers rule); podman-rootless: the `podman` CLI must be installed (an
   optional `OPENCODE_PODMAN_SOCKET` enables docker-CLI compat). An unknown
   backend value produces a loud warning and **no** container
   tools — never a silent fallback to a root-equivalent path.
4. **Execute** — `sudo -u opencode` with `DOCKER_HOST`/`XDG_RUNTIME_DIR`
   exported for the rootless socket (preserved across sudo via the kit's
   `env_keep`).

The wrapper prints its banner and starts opencode **immediately** — no
`Press Enter` pause and no `[Y/n]` container question (both removed in
0.0.21: the question was effectively always answered with yes, and the
kit's state is now visible inside the TUI at all times).

## The serve exception (headless start)

`opencode serve` does not go through these steps. Third-party UIs like
OpenChamber spawn the server non-interactively — stdin is `/dev/null` and
stdout is parsed for the `opencode server listening on <url>` line — so
any interactive prompt would break the startup (and `read` on a closed
stdin kills the wrapper before it execs). Since 0.0.21 the wrapper is
prompt-free everywhere; serve mode additionally:

- skips the project-directory check — the server accepts sessions per
  client request, and the soft permission layer (global + per-project
  `opencode.jsonc`) still applies to every session,
- prints nothing on stdout; diagnostics (shadow binary, backend
  warnings) go to stderr,
- resolves container tools silently — a server serves many projects, so
  there is no single opt-in to confirm; whether a session may actually
  use docker/ddev stays decided by the `opencode.jsonc` rules.

`OPENCODE_SERVER_PASSWORD` and `OPENCODE_SERVER_USERNAME` are preserved
across the `sudo -u opencode` exec, so the Basic-auth credentials a UI
passes to the server survive (see the
[OpenChamber how-to](../how-to/openchamber.md)). No other `OPENCODE_*`
variable crosses the sudo boundary: agent-side configuration
(`OPENCODE_CONFIG*`, `OPENCODE_AUTH_CONTENT`, `OPENCODE_PERMISSION`,
…) lives in the opencode user's own environment, and sudo's env reset
is what keeps the calling shell from overriding it per invocation.

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

The same HOME-keyed mechanism carries a visible marker for this case: the
kit installs a **red `opencode-danger` theme** for the default user
(`~/.config/opencode/tui.json` + `~/.config/opencode/themes/`). If the
original binary ever runs as your user, its TUI is red **and** shows a
warning row at the very bottom:

```
WARNING UNSECURE (bypass of opencode-permissions-kit detected)
```

The plugin detects the case by comparing the process user against the
kit's `OPENCODE_USER` stamp (the real uid — immune to environment
spoofing). The deny-all config still does the actual guarding; the red
look and the warning row are the visible amplifiers.

## Mode display in the TUI

The kit registers a small TUI plugin for the `opencode` user
(`/home/opencode/.config/opencode/tui.json` →
`/usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx`). It renders
one thin row at the very bottom of the TUI, on the home screen and
inside sessions:

```
opencode-permissions-kit (0.0.20) Mode: with ddev/docker
```

`with ddev/docker` when a rootless container backend is provisioned,
`no ddev/docker` otherwise — derived live from the kit's install.conf
(backend state **and** the installed kit version), so backend switches
show up without a restart. The text color follows
**your** opencode theme; the plugin never sets or changes the theme. If
you manage your own `~/.config/opencode/tui.json` (for the opencode
user), the kit leaves it alone — the file is only written when absent
or previously kit-written (marker key `_opencode_permissions_kit`).

Design background: [plan-ui-tui-opencode](../design/plan-ui-tui-opencode.md).

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
