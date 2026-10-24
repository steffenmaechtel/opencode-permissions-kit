# Ecosystem compatibility

Third-party tools that spawn or front opencode, how they invoke it, and
whether they work on a machine where the kit owns the `opencode` command.
The kit supports both opencode majors; CI exercises the current releases of
both at run time, so the matrix tracks the latest versions without a manual
stamp.

## How the kit intercepts tools

Everything that spawns `opencode` through `PATH` gets the kit's wrapper at
`/usr/local/bin/opencode` automatically — no tool configuration needed.
Tools that take an explicit binary path (`OPENCODE_BINARY`,
`CEZ_OPENCODE_BIN`, …) must point at the wrapper, not at
`~/.opencode/bin/opencode`.

Non-interactive invocations (`serve`, `run`, `acp`, query subcommands) run
through the wrapper's [headless
contract](../concepts/wrapper.md#headless-invocations-serve-run-queries):
stdout stays machine-clean, no prompts, no project-directory refusal. The
soft permission layer applies to every session regardless of which tool
started it.

## Compatibility matrix

| Tool | Kind | Invocation | Status |
|---|---|---|---|
| [OpenChamber](https://openchamber.dev) (web/desktop/VS Code) | UI | `opencode serve` | works (see caveats) |
| CodeWalk | remote UI | user-run `opencode serve` | works |
| OpenCode Mobile, P4OC | mobile clients | user-run `opencode serve` | works |
| [cezar](https://github.com/lukaszuznanski/cezar) | orchestrator | `serve` + `models` | works |
| Vibe Kanban | kanban orchestrator | `opencode run` | works |
| eval-harness | skill testing | `opencode run` | works |
| opencode-actions | CI (GitHub Actions) | `opencode run` | works |
| Telegram/harness bots (kimaki, GolemBot, …) | chat bots | `opencode run` / `serve` | works |
| opencode.nvim, opencode-vim | editor frontends | `opencode run` / SDK | works |
| ACP-based IDE agents | IDE | `opencode acp` (JSON-RPC stdio) | works |
| awesome-opencode plugins | plugins | load inside the agent process | unaffected — the soft layer covers tool calls |
| [OpenHarness](https://github.com/HKUDS/OpenHarness) | own harness | does not invoke opencode | no kit interaction |

"Works" means: the tool's spawn pattern passes the wrapper and opencode runs
under the kit's UID separation with the soft permission layer enforced. It
does not mean the kit audits or endorses the tool itself. OpenHarness ships
its own auth and never invokes opencode, so it has no interaction with the
kit.

## Caveats

- **OpenChamber 2.x version gate and self-update.** OpenChamber 2.x
  requires opencode ≥ 2.0.20 (major 2) and shows an update screen on older
  versions. The in-app updates do not go through the kit: the update toast
  fails harmlessly, but the one-click update below 2.0.20 installs
  `~/.opencode/bin/opencode`, pins it in OpenChamber's settings, and runs
  the server as the developer — outside the kit's UID separation. Keep the
  kit's opencode at ≥ 2.0.20 via `opk upgrade-opencode`; prevent or repair
  the bypass with `opk openchamber-secure` — see
  [the how-to](../how-to/openchamber.md).
- **OpenChamber projectless chats.** The managed chats root defaults to a
  path under the developer's `$HOME` that the `opencode` user cannot reach.
  OpenChamber ≥ 1.22.2 relocates it via `OPENCHAMBER_CHATS_DIR` — see
  [Projectless chats](../how-to/openchamber.md#projectless-chats).
- **Absolute-path spawns.** A tool hardcoding `~/.opencode/bin/opencode`
  bypasses the wrapper — the kit's [bypass guards](../concepts/wrapper.md)
  detect and warn about that binary. Point the tool's binary setting at
  `/usr/local/bin/opencode`.
- **sudo-spawning tools.** Tools that spawn opencode under `sudo` run it as
  root — outside the kit's model. Report such a tool; the kit deliberately
  grants no root path.
- **opencode 2.x background service port.** opencode 2.x binds its
  background service per *channel*, not per user: running a bare 2.x
  opencode as the developer occupies the port the `opencode` user's service
  needs. Kit starts stay functional, but avoid running 2.x opencode outside
  the kit on the same machine.

## Keeping this page current

The ecosystem moves fast — if a tool breaks or a notable one is missing,
please [open an issue](https://github.com/steffenmaechtel/opencode-permissions-kit/issues).
