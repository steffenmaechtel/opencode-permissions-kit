# opencode permissions kit

Hardens [opencode](https://opencode.ai) via Linux ACLs — block `.env`, keys, settings, and more at the filesystem level.

**One step:** install the opencode plugin, then run `/permission-setup` — after that, `opencode` runs as a dedicated user with hard filesystem denies.

## How It Works

- **Linux ACL layer** — `setfacl` blocks the `opencode` user from reading sensitive files
- **Wrapper** — every `opencode` invocation validates the directory, refreshes ACLs, then execs as the `opencode` user
- **Git hooks** — ACLs are re-applied automatically after checkout, merge, and commit, including the project-level `opencode.jsonc` of the current worktree (not just the global denies)
- **Project-specific configs** — add or override deny rules per project
- **opencode plugin** — the npm package `@steffenmaechtel/opencode-permissions-kit` is the only thing you install; it bundles the setup/uninstall scripts and exposes them as TUI commands

Files protected by default: `.env*`, `settings.php`, `auth.json`, `*.pem`, `*id_rsa*`, `*id_ed25519*`, `wp-config.php`, `LocalConfiguration.php`, `README.md`, `*.sql.gz`, and more.

## Quick Start

Install the plugin:

```bash
opencode plugin @steffenmaechtel/opencode-permissions-kit -g
```

Start opencode in a project directory, type `/permission-setup`, and copy the printed command into a terminal (it needs `sudo`). The command points at the bundled `setup.sh` — no global npm install required.

After the setup completes, restart opencode:

```bash
opencode
```

## Plugin Installation

```bash
opencode plugin @steffenmaechtel/opencode-permissions-kit -g
```

Example output:

```
┌  Install plugin @steffenmaechtel/opencode-permissions-kit
│
◇  Plugin package ready
│
◇  Detected server target
│
◇  Plugin config updated
│
●  Added to ~/.config/opencode/opencode.json
│
◆  Installed @steffenmaechtel/opencode-permissions-kit
│
●  Scope: global (~/.config/opencode)
│
└  Done
```

The npm package is installed only as an opencode plugin. The setup and uninstall scripts are bundled inside it and run via `/permission-setup` and `/permission-uninstall`.

## Plugin Commands

| Command | Purpose |
|---|---|
| `/permission-setup` | Prints the `sudo` command to run the bundled `setup.sh` (or confirms hardening is active) |
| `/permission-status` | Shows user, wrapper, config, and protected projects |
| `/permission-uninstall` | Prints the command to run the bundled `uninstall.sh` |

## Uninstall

Run `/permission-uninstall` inside opencode, or directly:

```bash
bash /usr/local/lib/opencode/uninstall.sh
```

Removes the `opencode` user, all files, ACLs, hooks, and sudoers rules. Project files are untouched.

## Documentation

See [docs/MANUAL.md](docs/MANUAL.md) for:
- Managing project directories
- Customizing the deny list (global + per-project)
- Project-level allow/deny overrides
- `.git/config` hardening
- Wrapper behavior

## Requirements

- WSL2 (or any Linux with ACL support)
- `sudo` access

## License

MIT
