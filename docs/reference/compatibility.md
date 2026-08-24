# Ecosystem compatibility

This page lists third-party tools that spawn or front opencode, how they
invoke it, and whether they work on a machine where the kit owns the
`opencode` command. Last verified: Aug 2026 (opencode v1.18.15).

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
| [OpenChamber](https://openchamber.dev) (web/desktop/VS Code) | UI | `opencode serve` | works (headless serve since 0.0.16) |
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

- **Absolute-path spawns.** A tool hardcoding `~/.opencode/bin/opencode`
  bypasses the wrapper — the kit's [bypass
  guards](../concepts/wrapper.md) detect and warn about that binary.
  Point the tool's binary setting at `/usr/local/bin/opencode`.
- **sudo-spawning tools.** Tools that spawn opencode under `sudo` run it
  as root — outside the kit's model. Report such a tool and we will take
  a look; the kit deliberately grants no root path.

## Keeping this page current

The ecosystem moves fast — if a tool breaks or a notable one is missing,
please open an issue at
[steffenmaechtel/opencode-permissions-kit](https://github.com/steffenmaechtel/opencode-permissions-kit/issues).
