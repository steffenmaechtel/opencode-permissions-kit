# DDEV addons — evaluations

> Issue
> [#41](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/41):
> do DDEV plugins that run opencode INSIDE the project's containers
> provide additional security or a viable alternative to the kit's
> host-UID model?

Context for all records here: the kit separates agent and developer by
OS UID on the host, and ddev runs **as the agent user** (one-owner
model, soft permission layer in the agent's `opencode.jsonc`). The
addons below invert that: the agent lives inside ddev's containers.

| Addon | Record | Verdict |
|---|---|---|
| trebormc/ddev-opencode | [ddev-opencode.md](ddev-opencode.md) | Conflicting (parallel model) |
| trebormc/ddev-ai-ssh | [ddev-ai-ssh.md](ddev-ai-ssh.md) | Not applicable (solves a foreign-agent sidecar problem the kit does not have) |
| e0ipso/ddev-assistant-opencode | [ddev-assistant-opencode.md](ddev-assistant-opencode.md) | Conflicting (collapses agent into the app container) |

Cross-cutting: none of the addons isolates agent-from-project — the
kit's actual boundary. They isolate agent-from-host, at the cost of a
second opencode home (config drift), no host tooling/git/IDE, and no
agent-side container runtime. Ideas worth stealing regardless:
per-project credential isolation, a read-only agents/skills volume, the
socket-less exec pattern.
