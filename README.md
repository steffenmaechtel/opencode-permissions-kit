# opencode permissions kit

> ⚠️ **ALPHA — not for production use.** This kit is still in active development and has not been audited. The ACL rules, wrapper, and sudoers configuration may change in breaking ways between releases. Run it on a throwaway WSL2/dev box, not on a production server.

Hardens [opencode](https://opencode.ai) via Linux ACLs — block `.env`, keys, settings, and more at the filesystem level.

**One step:** install the opencode plugin, then run `/permission-install` — after that, `opencode` runs as a dedicated user with hard filesystem denies.

## How It Works

- **Linux ACL layer** — `setfacl` blocks the `opencode` user from reading sensitive files
- **Wrapper** — every `opencode` invocation validates the directory, refreshes ACLs, then execs as the `opencode` user
- **Git hooks** — ACLs are re-applied automatically after checkout, merge, and commit, including the project-level `opencode.jsonc` of the current worktree (not just the global denies)
- **Project-specific configs** — add or override deny rules per project
- **opencode plugin** — the npm package `@steffenmaechtel/opencode-permissions-kit` is the only thing you install; it bundles the install/config/update/uninstall scripts and exposes them as TUI commands

Files protected by default: `.env*`, `settings.php`, `auth.json`, `*.pem`, `*id_rsa*`, `*id_ed25519*`, `wp-config.php`, `LocalConfiguration.php`, `README.md`, `*.sql.gz`, and more.

## Quick Start

Install the plugin:

```bash
opencode plugin @steffenmaechtel/opencode-permissions-kit -g
```

Start opencode in a project directory, type `/permission-install`, and copy the printed command into a terminal (it needs `sudo`). The command points at the bundled `install.sh` — no global npm install required.

After the install completes, restart opencode:

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

The npm package is installed only as an opencode plugin. The install, config, update, and uninstall scripts are bundled inside it and run via `/permission-install`, `/permission-config`, `/permission-update`, and `/permission-uninstall`.

## Plugin Commands

| Command | Purpose |
|---|---|
| `/permission-install` | Prints the `sudo` command to run the bundled `install.sh` (or confirms hardening is active) |
| `/permission-config` | Change settings post-install: project roots, `.git/config` hardening, ACL refresh |
| `/permission-update` | Re-deploy the kit after `git pull` without re-asking install questions |
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
