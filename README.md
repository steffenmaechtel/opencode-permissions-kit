# opencode permissions kit

Hardens [opencode](https://opencode.ai) via Linux ACLs — block `.env`, keys, settings, and more at the filesystem level.

**One command:** `sudo opencode-permissions-kit-setup` — then `opencode` runs as a dedicated user with hard filesystem denies.

## How It Works

- **Linux ACL layer** — `setfacl` blocks the `opencode` user from reading sensitive files
- **Wrapper** — every `opencode` invocation validates the directory, refreshes ACLs, then execs as the `opencode` user
- **Git hooks** — ACLs are re-applied automatically after checkout, merge, and commit
- **Project-specific configs** — add or override deny rules per project
- **opencode plugin** — available as npm package `@steffenmaechtel/opencode-permissions-kit`

Files protected by default: `.env*`, `settings.php`, `auth.json`, `*.pem`, `*id_rsa*`, `*id_ed25519*`, `wp-config.php`, `LocalConfiguration.php`, `README.md`, `*.sql.gz`, and more.

## Quick Start

```bash
opencode plugin @steffenmaechtel/opencode-permissions-kit -g
sudo opencode-permissions-kit-setup
```

Follow the prompts. Then navigate to a project and run:

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

The plugin detects whether hardening is active and provides the `/permission-status` command.

## Uninstall

```bash
sudo opencode-permissions-kit-uninstall
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
