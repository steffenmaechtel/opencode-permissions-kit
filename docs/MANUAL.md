# opencode permissions kit — Manual

## What It Does

This kit secures [opencode](https://opencode.ai) by running it as a dedicated Linux user (`opencode`) with hard Linux-ACL denies on sensitive files (`.env`, `settings.php`, `auth.json`, SSH keys, etc.).

Once installed, a developer opens a terminal in a project directory and runs `opencode` — the wrapper validates the directory, refreshes ACLs, then starts opencode as the `opencode` user. Denied files are unreadable at the Linux level; not even `cat .env` works.

## Quick Start

Install the plugin:

```bash
opencode plugin @steffenmaechtel/opencode-permissions-kit -g
```

Start opencode, type `/permission-install`, and run the printed command in a terminal (it needs `sudo`). Follow the prompts to select project directories. After the install, `cd` into a project and run:

```bash
opencode
```

## Managing Project Directories

Project roots are stored in `/etc/opencode/projects.conf` (one absolute path per line). The wrapper only allows `opencode` to start inside one of these directories or their subdirectories.

### Adding More Projects

**Option A — Use `config.sh` (recommended after install):**

Run `/permission-config` in opencode and run the printed command, then append the subcommand:

```bash
sudo bash /usr/local/lib/opencode/config.sh projects add /var/www/vhosts/new-project
```

You can pass multiple paths:

```bash
sudo bash /usr/local/lib/opencode/config.sh projects add /var/www/vhosts/site-a /var/www/vhosts/site-b
```

`config.sh` updates `projects.conf`, applies the base filesystem bits (group `www-data`, setgid, default ACL), and re-runs `protect-projects.sh --force` in one step. It is non-interactive when you pass `--yes`.

**Option B — Re-run `install.sh` (during initial setup):**
Run `/permission-install` in opencode and append the flag to the printed command:
```bash
sudo bash <path-to-install.sh> --projects /var/www/vhosts/new-project
```
You can pass multiple paths:
```bash
sudo bash <path-to-install.sh> --projects /var/www/vhosts/site-a /var/www/vhosts/site-b
```

**Option C — Edit the config directly:**
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

**Option A — Use `config.sh`:**

```bash
sudo bash /usr/local/lib/opencode/config.sh projects remove /var/www/vhosts/old-project
```

Removes the line from `/etc/opencode/projects.conf`. ACL denies on that directory remain on disk until you clear them manually.

**Option B — Edit the config directly:**

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

**Enable during install:**

Run `/permission-install` in opencode and append the flag to the printed command:
```bash
sudo bash <path-to-install.sh> --secure-git-config
```

Or answer "Yes" when prompted during interactive install.

**Toggle later (without re-running install):**

```bash
sudo bash /usr/local/lib/opencode/config.sh git-config on     # block .git/config
sudo bash /usr/local/lib/opencode/config.sh git-config off    # allow git access again
sudo bash /usr/local/lib/opencode/config.sh git-config status # show current state
```

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

The hooks run `protect-projects.sh --force --cwd "$(pwd)"` from the worktree root, so the project-level `opencode.jsonc` of the repository you are working in is applied too — not just the global denies.

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

## opencode Plugin

The kit is distributed as an opencode plugin — this is the only install step. The plugin detects whether hardening is active and provides two modes:

- **Install mode** (not hardened): Shows an install banner and exposes the `/permission-install` command
- **Hardened mode** (active): Sets `OPENCODE_HARDENED=1`, logs protection stats, provides status / config / update / uninstall commands

The plugin resolves the bundled `files/install.sh`, `files/config.sh`, `files/update.sh`, and `files/uninstall.sh` from its own install directory, so no global npm install or PATH setup is needed.

The `/permission-*` commands are registered by the plugin's `config` hook (so they are real, typeable slash commands) and answered deterministically by the `command.execute.before` hook — the printed command/status text appears in the chat, and the assistant relays it. No LLM-generated commands are ever proposed.

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

| Command | Purpose |
|---|---|
| `/permission-install` | Prints the `sudo bash <install.sh>` command to run in a terminal; in hardened mode confirms the protection is active |
| `/permission-config` | Prints the `sudo bash <config.sh>` command — change project roots, toggle .git/config hardening, refresh ACLs |
| `/permission-update` | Prints the `sudo bash <update.sh>` command — re-deploys the kit after a `git pull` without re-asking install questions |
| `/permission-status` | Shows user, wrapper, config, and protected projects |
| `/permission-uninstall` | Prints the `bash <uninstall.sh>` command to run in a terminal |

The scripts must run in a regular terminal (not inside opencode): the `sudo` password prompt and the interactive project selection need a real TTY. After install/update, restart opencode.

Type `/permission-status` in opencode to see:

```
Permission-Control v0.0.8 (hardened)
  User: opencode exists
  Wrapper: /usr/local/bin/opencode
  Config: /home/opencode/.config/opencode/opencode.jsonc
  Projects: 1 (/var/www/vhosts)
  Cache: active
```

## Updating the Kit

After `git pull` (or a new plugin install) you can re-deploy the kit **without** re-answering the install-time questions:

```bash
sudo bash /usr/local/lib/opencode/update.sh
```

`update.sh` copies the current wrapper, hooks, `protect-projects.sh`, `jsonc-parser.py`, `sudoers` template, `umask` profile, `config.sh`, `uninstall.sh`, and refreshes the `install.conf` version stamp. It does **not** touch:

- `/etc/opencode/projects.conf`
- `/etc/opencode/install.conf` (except the `VERSION=` line)
- `/home/opencode/.config/opencode/opencode.jsonc`
- the opencode binary at `/usr/local/lib/opencode/bin/opencode`
- any ACLs or filesystem metadata

Add `--refresh` to also re-run `protect-projects.sh --force` after the deploy:

```bash
sudo bash /usr/local/lib/opencode/update.sh --refresh
```

## Uninstalling

Run `/permission-uninstall` inside opencode, or directly:

```bash
bash /usr/local/lib/opencode/uninstall.sh
```

Run it as your normal user (no `sudo` prefix — the script handles sudo itself). Options: `--yes`, `--dry-run`, `--debug`.

Removes the `opencode` user, all installed files, ACLs, hooks, and sudoers rules. Project files are untouched.

## File Overview

| Path | Purpose |
|---|---|
| `/usr/local/bin/opencode` | Wrapper (symlink to `/usr/local/lib/opencode/wrapper`) |
| `/usr/local/lib/opencode/wrapper` | Validates directory, refreshes ACLs, execs opencode |
| `/usr/local/lib/opencode/protect-projects.sh` | Applies ACL denies to sensitive files |
| `/usr/local/lib/opencode/config.sh` | Change settings post-install (projects, git-config, refresh) |
| `/usr/local/lib/opencode/update.sh` | Re-deploy the kit after an update, no prompts |
| `/usr/local/lib/opencode/uninstall.sh` | Uninstall script (deployed by install, also bundled in the plugin) |
| `/usr/local/lib/opencode/bin/opencode` | The actual opencode binary |
| `/etc/opencode/projects.conf` | Project roots (one per line) |
| `/etc/opencode/install.conf` | `DEFAULT_USER`, `OPENCODE_USER`, `WWW_GROUP`, `VERSION` |
| `/home/opencode/.config/opencode/opencode.jsonc` | opencode config with deny patterns |
| `/etc/sudoers.d/opencode` | Sudo rules for wrapper and protect-projects.sh |
| `/usr/local/lib/opencode/hooks/` | Global git hooks (post-checkout, post-merge, post-commit) |
