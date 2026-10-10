# Ecosystem compatibility

This page lists third-party tools that spawn or front opencode, how they
invoke it, and whether they work on a machine where the kit owns the
`opencode` command. The kit supports both majors; CI exercises them
continuously against the **current** releases at run time (the e2e jobs
resolve opencode 1.x from GitHub releases/latest and 2.x from the npm
dist-tag `latest`, plus a weekly scheduled burn-in on `master`) — so the
matrix tracks the latest versions without a manual stamp. Last manual
verification: Sep 2026, opencode 1.18.31 / 2.0.6 (internals:
[design/opencode-2x.md](../design/opencode-2x.md)); Oct 2026,
OpenChamber 2.x with kit-managed opencode 2.0.26 / 2.0.20 (works,
including the version probe through the wrapper) and 2.0.19 (update
screen, one-click bypass verified — see the caveats below; the bypass's
stale settings pin additionally blocks the managed server start after
the binaries are removed, until the `opencodeBinary` settings line is
deleted too).

## How the kit intercepts tools

Everything that spawns `opencode` through `PATH` gets the kit's wrapper
at `/usr/local/bin/opencode` automatically — no tool configuration
needed. Tools that take an explicit binary path (`OPENCODE_BINARY`,
`CEZ_OPENCODE_BIN`, …) must point at the wrapper, not at
`~/.opencode/bin/opencode`.

Non-interactive invocations (`serve`, `run`, `acp`, query subcommands)
run through the wrapper's [headless
contract](../concepts/wrapper.md#headless-invocations-serve-run-queries):
stdout stays machine-clean, no prompts, no project-directory refusal.
The soft permission layer (global + per-project `opencode.jsonc`) applies
to every session regardless of which tool started it.

## Compatibility matrix

| Tool | Kind | Invocation | Status |
|---|---|---|---|
| [OpenChamber](https://openchamber.dev) (web/desktop/VS Code) | UI | `opencode serve` | works (headless serve since 0.0.16; OpenChamber 2.x additionally requires opencode ≥ 2.0.20 managed by the kit — and its self-update bypasses the kit unless you pin it via `opk openchamber-secure`, see below; projectless chats need OpenChamber ≥ 1.22.2, see [the how-to](../how-to/openchamber.md#projectless-chats)) |
| CodeWalk | remote UI | user-run `opencode serve` | works |
| OpenCode Mobile, P4OC | mobile clients | user-run `opencode serve` | works |
| [cezar](https://github.com/lukaszuznanski/cezar) | orchestrator | `opencode serve` + `opencode models` | works (headless queries since 0.0.22) |
| Vibe Kanban | kanban orchestrator | `opencode run` | works (headless run since 0.0.22) |
| eval-harness | skill testing | `opencode run` | works (headless run since 0.0.22) |
| opencode-actions | CI (GitHub Actions) | `opencode run` | works (headless run since 0.0.22) |
| Telegram/harness bots (kimaki, GolemBot, …) | chat bots | `opencode run` / `serve` | works |
| opencode.nvim, opencode-vim | editor frontends | `opencode run` / SDK | works |
| ACP-based IDE agents | IDE | `opencode acp` (JSON-RPC stdio) | works (headless acp since 0.0.22) |
| awesome-opencode plugins | plugins | load inside the agent process | unaffected — the soft layer applies to their tool calls |
| [OpenHarness](https://github.com/HKUDS/OpenHarness) | own harness | does not invoke opencode (own auth: `~/.claude/.credentials.json`, `~/.codex/auth.json`) | no interaction with the kit |

"Works" means: the tool's spawn pattern passes the wrapper and opencode
runs under the kit's UID separation with the soft permission layer
enforced. It does not mean the kit audits or endorses the tool itself.

## Caveats

- **OpenChamber 2.x version gate and self-update.** OpenChamber 2.x
  requires opencode ≥ 2.0.20 (major 2) and refuses to open on older
  versions, showing its own update screen instead. The in-app updates
  do not go through the kit: the harmless "update available" toast
  fails cleanly (no install method for the kit binary), but the
  one-click update below 2.0.20 installs `~/.opencode/bin/opencode`,
  pins it in OpenChamber's settings, and runs the server as the
  developer — outside the kit's UID separation. Keep the kit's opencode
  at ≥ 2.0.20 via `opk upgrade-opencode`; prevent or repair the bypass
  with the policy pin (`opk openchamber-secure`) and recovery steps in
  [the how-to](../how-to/openchamber.md#prevent-the-bypass-the-policy-pin).
- **OpenChamber projectless chats.** The managed chats root defaults to
  a path under the developer's `$HOME` that the `opencode` user cannot
  reach. OpenChamber ≥ 1.22.2 relocates it via `OPENCHAMBER_CHATS_DIR`;
  on older versions projectless chats fail with HTTP 500 — see
  [Projectless chats](../how-to/openchamber.md#projectless-chats).
- **Absolute-path spawns.** A tool hardcoding `~/.opencode/bin/opencode`
  bypasses the wrapper — the kit's [bypass
  guards](../concepts/wrapper.md) detect and warn about that binary.
  Point the tool's binary setting at `/usr/local/bin/opencode`.
- **sudo-spawning tools.** Tools that spawn opencode under `sudo` run it
  as root — outside the kit's model. Report such a tool and we will take
  a look; the kit deliberately grants no root path.
- **opencode 2.x background service port.** opencode 2.x (the npm `latest`
  channel) binds its background service per *channel*, not per user: running
  a bare 2.x opencode as the developer occupies the port the `opencode`
  user's service needs. Kit starts stay functional (their config probe
  is time-bounded), but bare runs print a load/wait notice. Avoid
  running 2.x opencode outside the kit on the same machine. OpenChamber
  2.x's one-click self-install (see above) is exactly such a bare run —
  it starts the background service in the developer's user context
  (verified Oct 2026).

## Keeping this page current

The ecosystem moves fast — if a tool breaks or a notable one is missing,
please open an issue at
[steffenmaechtel/opencode-permissions-kit](https://github.com/steffenmaechtel/opencode-permissions-kit/issues).
