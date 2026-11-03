# Use JetBrains IDEs

PhpStorm, IntelliJ IDEA and the other JetBrains IDEs run on Windows while the
project lives in WSL2 — and how you open the project decides whether the
kit's [sharing group](../concepts/sharing-group.md) is visible to the IDE.

## The short version

Open the project through **Remote Development → WSL**: the IDE backend then
runs inside WSL and every permission check happens kernel-side. The two
other opening modes report agent-created folders as read-only — an upstream
bug in the IDEs' writability check, not a kit misconfiguration.

## Why local and Native mode fail

The kit grants you write access to agent-created files through your
supplementary membership in the `opencode` group — group-write on
`opencode:opencode` folders. JetBrains IDEs on Windows compute their
read-only verdict from the file's owner, primary group and "other" bits:
supplementary groups and ACLs are not considered
([WI-82942](https://youtrack.jetbrains.com/issue/WI-82942)).

The verdict is wrong, but the IDE refuses to even try the write: creating a
file in an agent-owned folder fails with `Cannot modify a read-only
directory`, while writes from inside WSL, from PowerShell over
`\\wsl.localhost`, and from editors that write without a pre-check (e.g.
Notepad++) all succeed on the very same folder.

## The three opening modes

| Mode | How to recognize it | Agent-created folders |
|---|---|---|
| Local project | folder opened via the `\\wsl.localhost\<distro>\...` path | read-only error |
| Native mode (2026.2+) | recommended default; the IJent agent runs inside WSL | read-only error |
| **Remote Development** | Welcome screen → Remote Development → WSL; a JetBrains Client window opens | **works** |

Verified with PhpStorm 2026.2.4 in all three modes (November 2026). Native
mode arrived with the 2026.2 releases and carries the same check as the
local mode.

## Setting up Remote Development

1. In the IDE, open **Settings → Advanced Settings → Gateway WSL** and
   uncheck *Open WSL projects natively as local projects (without Remote
   Development)*. The setting name is misleading: checked means the classic
   local project over the 9P filesystem — the kit needs it off.
2. On the welcome screen, pick **Remote Development → WSL**.
3. Point it at your project, for example
   `\\wsl.localhost\<distro>\var\www\vhosts\<project>`.
4. Wait for the first connect — it downloads the JetBrains Client and the
   IDE backend into WSL (about 2 GB, one time).
5. The window that opens is the thin JetBrains Client. Indexing, terminal,
   run configurations and file operations all run inside WSL as your WSL
   user, with your full group membership — the sharing group counts.

Verify from inside WSL that the backend runs as your user:

```bash
ps aux | grep RemoteDev
```

## Trade-offs

- a one-time ~2 GB download (client plus backend inside WSL) and the
  thin-client UI;
- Remote Development needs a JetBrains license;
- JetBrains labels Remote Development "no longer recommended" — they
  recommend Native mode, which is exactly the mode whose writability check
  breaks with the kit's group model.

## Alternatives

- **VS Code with the WSL extension** is unaffected: its server runs inside
  WSL and writes through the kernel.
- Editors that write without a read-only pre-check (e.g. Notepad++) work
  over `\\wsl.localhost` — slowly on large trees, but without permission
  surprises.
- A manual `sudo chgrp -R <you> <project>` makes local mode work, but the
  next baseline run (`opk config refresh`, `opk update --refresh`) re-groups
  the tree to the `opencode` sharing group. Treat it as a stopgap.
- Track or vote for
  [WI-82942](https://youtrack.jetbrains.com/issue/WI-82942): once JetBrains
  honor supplementary groups, local and Native mode work with the kit
  unchanged.
