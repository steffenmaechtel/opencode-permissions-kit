# opencode permissions kit

Hardens [opencode](https://opencode.ai) via Linux ACLs — block `.env`, keys, settings, and more at the filesystem level.

**One command:** `sudo ./files/setup.sh` — then `opencode` runs as a dedicated user with hard filesystem denies.

## How It Works

- **Linux ACL layer** — `setfacl` blocks the `opencode` user from reading sensitive files
- **Wrapper** — every `opencode` invocation validates the directory, refreshes ACLs, then execs as the `opencode` user
- **Git hooks** — ACLs are re-applied automatically after checkout, merge, and commit
- **Project-specific configs** — add or override deny rules per project
- **opencode plugin** — available as npm package `@steffenmaechtel/opencode-permissions-kit`

Files protected by default: `.env*`, `settings.php`, `auth.json`, `*.pem`, `*id_rsa*`, `*id_ed25519*`, `wp-config.php`, `LocalConfiguration.php`, `README.md`, `*.sql.gz`, and more.

## Quick Start

```bash
git clone https://github.com/steffenmaechtel/opencode-permissions-kit
cd opencode-permissions-kit
sudo ./files/setup.sh
```

Follow the prompts. Then navigate to a project and run:

```bash
opencode
```

## Plugin Installation

Add to your `opencode.jsonc`:

```jsonc
{
    "plugin": ["@steffenmaechtel/opencode-permissions-kit"]
}
```

The plugin detects whether hardening is active and provides the `/permission-status` command.

## Uninstall

```bash
sudo ./files/uninstall.sh
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
