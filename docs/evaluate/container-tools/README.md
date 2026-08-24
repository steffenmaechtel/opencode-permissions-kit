# Container tools / sandboxes — evaluations

> Issue [#40](https://github.com/steffenmaechtel/opencode-permissions-kit/issues/40):
> can a container sandbox tool add hard OS-level security to the kit's
> deliberately soft model?

Context for all records here: the kit's boundary is UID separation (agent
≠ developer) + a rootless backend owned by the agent user. The soft layer
exists **because ddev's containers must read project files**
(`settings.php`, `.env`) through bind mounts — any sandbox that hides
files from the agent also hides them from ddev.

| Tool | Record | Verdict |
|---|---|---|
| bubblewrap | [bubblewrap.md](bubblewrap.md) | Conflicting |
| opencode-sandbox (npm) | [opencode-sandbox.md](opencode-sandbox.md) | Conflicting as default; complementary as opt-in network fence |
| Docker `sbx` | [docker-sbx.md](docker-sbx.md) | Not applicable (alternative model, replaces the kit) |

Cross-cutting conclusion: all three draw their hard boundary at exactly
the layer the kit deliberately leaves soft — the shared,
daemon-visible project filesystem that ddev requires.
