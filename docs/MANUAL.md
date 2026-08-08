# opencode permissions kit — Manual

## What It Does

This kit secures [opencode](https://opencode.ai) by running it as a dedicated Linux user (`opencode`) with hard Linux-ACL denies on sensitive files (`.env`, `settings.php`, `auth.json`, SSH keys, etc.).

Once installed, a developer opens a terminal in a project directory and runs `opencode` — the wrapper validates the directory, refreshes ACLs, then starts opencode as the `opencode` user. Denied files are unreadable at the Linux level; not even `cat .env` works.

## Quick Start

```bash
npm install -g @steffenmaechtel/opencode-permissions-kit
sudo opencode-permissions-kit-setup
opencode plugin @steffenmaechtel/opencode-permissions-kit -g
```

Follow the prompts to select project directories. After setup, `cd` into a project and run:

```bash
opencode
```

## Managing Project Directories

Project roots are stored in `/etc/opencode/projects.conf` (one absolute path per line). The wrapper only allows `opencode` to start inside one of these directories or their subdirectories.

### Adding More Projects

**Option A — Re-run setup:**
```bash
sudo opencode-permissions-kit-setup --projects /var/www/vhosts/new-project
```

You can pass multiple paths:
```bash
sudo opencode-permissions-kit-setup --projects /var/www/vhosts/site-a /var/www/vhosts/site-b
```

**Option B — Edit the config directly:**
```bash
sudo nano /etc/opencode/projects.conf
```
Add one path per line, then apply ACLs to the new directory:
```bash
sudo /usr/local/lib/opencode/protect-projects.sh --force
```

### Listing Configured Directories

```bash
cat /etc/opencode/projects.conf
```

### Removing a Project Directory

Remove the line from `/etc/opencode/projects.conf`. ACLs on that directory remain in place but are no longer refreshed — use `getfacl` / `setfacl -x` to clean up manually or run `uninstall.sh`.

## How the Wrapper Works

Every `opencode` invocation goes through the wrapper at `/usr/local/bin/opencode`:

1. **Validate working directory** — the current directory must be inside a path listed in `/etc/opencode/projects.conf`. If not, an error is shown with the list of valid directories and opencode does not start.
2. **Refresh ACL denies** — runs `protect-projects.sh` to ensure sensitive files are blocked.
3. **Execute** — starts opencode as the `opencode` user.

## Customizing the Deny List

### Global Config

Edit the config file (as your default user, no `sudo` needed — the directory is group-writable):

```bash
nano /home/opencode/.config/opencode/opencode.jsonc
```

Add deny patterns under `permission.read.deny` and `permission.edit.deny`. Changes take effect on the next `opencode` start.

See `files/opencode.jsonc` for the default template.

### Project-Specific Config

Each project can have its own `opencode.jsonc` (or `opencode.json`) in its root directory. Project configs **extend** the global config — they add denies cumulatively, never weaken existing rules.

Example `/var/www/vhosts/my-project/opencode.jsonc`:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "read": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny",
            "dump*.sql": "deny"
        },
        "edit": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny",
            "dump*.sql": "deny"
        },
        "bash": {
            "yarn dev": "allow",
            "composer install*": "allow"
        }
    }
}
```

How it works:

- **`permission.read.deny` / `permission.edit.deny`**: Merged with global denies. `protect-projects.sh` applies ACLs scoped to this project only.
- **`permission.read.allow` / `permission.edit.allow`**: Removes global ACL denies **for this project only**. In the wrapper you'll see a warning listing the overridden patterns.
- **`permission.bash`**: Project rules override global bash rules (opencode standard).

A project without its own config gets only the global protection.

See `tests/fixtures/project-opencode.jsonc` for a full example (TYPO3 project).

### `.git/config` Hardening (Optional)

`.git/config` can contain remote URLs with embedded credentials. When blocked, opencode **cannot execute any git commands** — no commit, push, pull, status, diff, or log. The developer must handle all git operations themselves.

**Enable during setup:**

```bash
sudo opencode-permissions-kit-setup --secure-git-config
```

Or answer "Yes" when prompted during interactive setup.

**Enable manually** (add to global or project config):

```jsonc
"permission": {
    "read": {
        ".git/config": "deny",
        "**/.git/config": "deny"
    },
    "edit": {
        ".git/config": "deny",
        "**/.git/config": "deny"
    }
}
```

When to enable:
- Remote URLs contain embedded tokens (e.g. `https://user:ghp_xxx@github.com/...`)
- You don't want opencode to run git at all

When to leave open:
- You use SSH keys (no token in remote URL)
- You use a credential helper (Git Credential Manager)
- You want opencode to commit/push on your behalf

## Git Hooks

Global git hooks re-apply ACL denies automatically after:

- `git checkout` / `git switch` / `git pull` (fast-forward)
- `git merge`
- `git commit`

No per-repo setup required — `core.hooksPath` is set globally for both users.

## Verification

Run the test suite to confirm everything is working:

```bash
./tests/verify.sh
```

It checks users, groups, wrapper, hooks, sudoers, and that `opencode` truly cannot read sensitive files like `.env` and `settings.php`.

### Development Tests

These tests run without system dependencies and verify logic in isolation:

```bash
./tests/test-wrapper-validation.sh   # 17 tests: directory validation
./tests/test-project-config.sh       # 29 tests: project config parsing & matching
```

## opencode Plugin (alternative distribution)

The setup kit is also available as an opencode plugin. The plugin detects whether hardening is active and provides two modes:

- **Setup mode** (not hardened): Shows setup instructions and the `/permission-status` command
- **Hardened mode** (active): Sets `OPENCODE_HARDENED=1`, logs protection stats, provides `/permission-status` diagnostics

### Installation

```bash
opencode plugin @steffenmaechtel/opencode-permissions-kit -g
```

```
┌  Install plugin @steffenmaechtel/opencode-permissions-kit
│
◇  Plugin package ready
│
◇  Detected server target
│
◇  Plugin config updated
│
●  Added to /home/info/.config/opencode/opencode.json
│
◆  Installed @steffenmaechtel/opencode-permissions-kit
│
●  Scope: global (/home/info/.config/opencode)
│
└  Done
```

Or locally from the repo:

```bash
cp src/index.ts ~/.config/opencode/plugins/
```

### Commands

Type `/permission-status` in opencode to see:

```
Permission-Control v0.0.7 (hardened)
  User: opencode exists
  Wrapper: /usr/local/bin/opencode
  Config: /home/opencode/.config/opencode/opencode.jsonc
  Projects: 1 (/var/www/vhosts)
  Cache: active
```

## Uninstalling

```bash
sudo opencode-permissions-kit-uninstall
```

Removes the `opencode` user, all installed files, ACLs, hooks, and sudoers rules. Project files are untouched.

## File Overview

| Path | Purpose |
|---|---|
| `/usr/local/bin/opencode` | Wrapper (symlink to `/usr/local/lib/opencode/wrapper`) |
| `/usr/local/lib/opencode/wrapper` | Validates directory, refreshes ACLs, execs opencode |
| `/usr/local/lib/opencode/protect-projects.sh` | Applies ACL denies to sensitive files |
| `/usr/local/lib/opencode/bin/opencode` | The actual opencode binary |
| `/etc/opencode/projects.conf` | Project roots (one per line) |
| `/etc/opencode/setup.conf` | `DEFAULT_USER` setting |
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with deny patterns |
| `/etc/sudoers.d/opencode` | Sudo rules for wrapper and protect-projects.sh |
| `/usr/local/lib/opencode/hooks/` | Global git hooks (post-checkout, post-merge, post-commit) |
