# The wrapper

What happens on every `opencode` start, and how the kit protects the wrapper
from being bypassed.

## The four steps

Every `opencode` invocation goes through the wrapper at
`/usr/local/bin/opencode`:

1. **Validate working directory** — the current directory must be inside a
   path listed in `projects.conf`. Otherwise the interactive start is
   refused (headless invocations skip this — see
   [below](#headless-invocations-serve-run-queries)).
2. **Detect container tools** — if the project's final `opencode.jsonc` allows
   docker/ddev broadly, the wrapper attaches the configured rootless backend.
3. **Probe the backend** — docker-rootless: the per-user socket is verified
   reachable (as the `opencode` user, via the kit's `socket-check` sudoers
   rule); podman-rootless: the `podman` CLI must be installed. An unknown
   backend value produces a loud warning and **no** container tools — never
   a silent fallback to a root-equivalent path.
4. **Execute** — `sudo -u opencode` with `DOCKER_HOST`/`XDG_RUNTIME_DIR`
   exported for the rootless socket (preserved across sudo via the kit's
   `env_keep`).

The wrapper prints its banner and starts opencode immediately — no `Press
Enter` pause, no container question (the state is visible in the TUI, see
[mode display](#mode-display-in-the-tui)).

One exception runs before everything else: `opencode --version`, `-v`, `-h`
and `--help` exec straight to the real binary from **any** directory — no
banner, no checks. Scripts and the official installer parse that output
verbatim.

## Headless invocations (serve, run, queries)

`opencode serve` and the other non-interactive subcommands do not go through
the interactive path. Third-party tools spawn opencode non-interactively and
parse its stdout:

| Invocation | Who uses it | What is parsed |
|---|---|---|
| `opencode serve` | OpenChamber, cezar, CodeWalk, the VS Code extension | `opencode server listening on <url>` |
| `opencode run` | CI runners, kanban orchestrators, eval harnesses | `--format json` / stream-json events |
| `opencode acp` | IDE agents (Agent Client Protocol) | JSON-RPC over stdio |
| `opencode models`, `agent`, `providers`, `export`, … | scripts, model discovery | JSON/plain listings |

A banner or prompt on stdout would break those parsers — headless
invocations therefore:

- skip the project-directory check — the soft permission layer (global +
  per-project `opencode.jsonc`) still applies to every session,
- print nothing on stdout; diagnostics go to stderr,
- resolve container tools silently — `serve` always attaches them; `run` and
  queries attach them when the CWD's project config opts in. Whether a
  session may actually use docker/ddev stays decided by the `opencode.jsonc`
  rules.

What counts as headless: `serve`, `acp`, the query subcommands (`models`,
`agent`, `providers`, `session`, `export`, `import`, `stats`, `account`,
`console`, `github`, `pr`, `mcp`, `plug`, `db`, `generate`, `web`, `debug`,
`uninstall`, `upgrade`, plus the 2.x additions `api`, `auth`, `plugin`,
`service`, `pair`, `update`), and `run` when a message argument is given or
stdin is piped. `console login` (1.x) and `auth login` (2.x) are device
logins — they carry no project context and must work from any directory.
Interactive TUI starts keep the banner and the project-directory check.

Device logins get the same working-directory treatment as `serve`: when the
current directory is not readable by the `opencode` user (typically your
`$HOME`, mode 750), the wrapper moves the login to a readable directory (the
opencode home) before starting the binary.

`serve` additionally sanity-checks its working directory: UIs like OpenChamber
default it to the developer's `$HOME`, which the `opencode` user cannot read.
The wrapper probes readability from the opencode user's context (`cwd-check`),
warns on stderr and starts the server from a readable fallback (see the
[OpenChamber how-to](../how-to/openchamber.md#server-working-directory)).

`OPENCODE_SERVER_PASSWORD` and `OPENCODE_SERVER_USERNAME` are preserved
across the `sudo -u opencode` exec, so the Basic-auth credentials a UI passes
to the server survive. No other `OPENCODE_*` variable crosses the sudo
boundary — agent-side configuration lives in the opencode user's own
environment. Which tool uses which invocation is tracked in the
[compatibility matrix](../reference/compatibility.md); tools that are
opencode *plugins* load inside the agent process and never touch the wrapper.

## Self-update bypass protection (default-user deny-all)

opencode's installer and self-updater can re-add `~/.opencode/bin` to your
`PATH` — typing `opencode` would then run the real binary **as your user**,
outside the kit.

As a safety net, the kit installs a lockout config for the default user
(`~/.config/opencode/opencode.jsonc`) that denies **everything** — even if
the real binary takes over, it cannot read or modify anything.

- During `install.sh`, an existing file is renamed to
  `opencode.jsonc_BAK_<timestamp>` first.
- `update.sh` only installs the lockout config when no config exists yet.
- To use opencode normally as your own user, delete or rename that config.

`install.sh` also removes a self-installed binary from `~/.opencode/bin`
(after securing its copy under the kit). If the original binary ever runs as
your user anyway, its TUI turns **red** and shows a warning row at the very
bottom:

```text
WARNING UNSECURE (bypass of opencode-permissions-kit detected)
```

The deny-all config does the actual guarding; the red look and the warning
row are the visible amplifiers.

## Mode display in the TUI

The kit registers a small TUI plugin for the `opencode` user. It renders one
thin row at the very bottom of the TUI:

```text
opencode-permissions-kit (0.0.20) Mode: with ddev/docker
```

`with ddev/docker` when a rootless container backend is provisioned,
`no ddev/docker` otherwise — derived live from the kit's `install.conf`, so
backend switches show up without a restart. The registration differs by
opencode major (stamped as `OPENCODE_MAJOR`):

- **opencode 1.x**: `~/.config/opencode/tui.json` loads
  `/usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx`. A user-managed
  `tui.json` is left alone.
- **opencode 2.x**: the kit deploys the port `kit-mode-2x.tsx` and registers
  it as a discovered plugin dir —
  `~/.config/opencode/plugins/opencode-permissions-kit/tui.tsx`, symlinked
  into the kit's library. Remove that directory to opt out.

## Wrapper-bypass guard (detect, then warn loudly)

1. **Binary exec restricted to root + the opencode usergroup.** The real
   binary at `/usr/local/lib/opencode-permissions-kit/bin/opencode` is owned
   `root:opencode` with mode `750`. The developer is a member of the group,
   so the group bit grants them execution too — a run as your user is
   mitigated by the deny-all config above, not by the mode bits.
2. **Shell-start warning.** A hook in `~/.bashrc`, `~/.zshrc`, `~/.profile`
   and the profile.d script prints a loud warning when a real
   `~/.opencode/bin/opencode` exists or `command -v opencode` resolves to
   anything but the wrapper.
3. **Wrapper self-check.** Every wrapper start re-checks both conditions.
