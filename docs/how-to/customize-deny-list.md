# Customize the deny list

Change which files the agent may read and edit — globally and per project.

All read/edit rules are **soft**: they gate opencode's own tools, not the OS
(see the [security model](../concepts/security-model.md)).

## Edit the global config

Open the config as your default user (no `sudo` — the directory is
group-writable):

```bash
nano /home/opencode/.config/opencode/opencode.jsonc
```

Add or remove deny patterns under `permission.read` / `permission.edit`.
Changes take effect on the next `opencode` start.

The bundled template additionally:

- runs `permission.bash` as **ask-by-default** (`"*": "ask"`) with a small
  allowlist of harmless read-only commands,
- hard-denies system-destructive and container commands,
- mirrors the read/edit deny patterns as **ask tripwires** with trailing `*`
  in bash — so `cat settings.php | grep DB` still prompts. The tripwire is
  lexical: variables (`F=.env; cat $F`), globs, and indirection evade it.

opencode applies the **last** matching rule — a narrow `allow` placed after
a broad `deny` exempts a file from an overmatching rule. The template uses
that carve-out itself: TYPO3's `ext_localconf.php` is re-allowed after the
broad `*conf.php` deny (it is code, not secrets).

### Bash rules match the whole command

A `permission.bash` rule is matched against the **entire command text**
(anchored at both ends, `*` matches any run — last matching rule wins), and
opencode evaluates the command **including its redirects**. A redirect deny
therefore needs a leading `*` and an operator-swallowing inner `*`:

```jsonc
"bash": {
    // DEAD: no command text starts with ">" — this never matches
    // "> /srv/backup/*": "deny",
    // Works: any command redirecting into the tree (>, >>, >|, 2>, &>),
    // spaced or glued ("> file", ">file")
    "*>*/srv/backup/*": "deny"
}
```

The same shape rule applies to every command you want to catch mid-line:
`sudo dd of=/dev/sda` never matches `"dd of=/dev/sd*"` (the command starts
with `sudo`) — use `"*dd*of=/dev/sd*"` (issue #391).

## Add a per-project config

Each project can have its own `opencode.jsonc` in its root. Project configs
**extend** the global config (opencode merges them; last matching rule
wins). Example `/var/www/vhosts/my-project/opencode.jsonc`:

```jsonc
{
    "$schema": "https://opencode.ai/config.json",
    "permission": {
        "read": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny"
        },
        "edit": {
            "secret-tokens.json": "deny",
            "**/secret-tokens.json": "deny",
            "deploy/keys/*.pem": "deny"
        },
        "bash": {
            "yarn dev": "allow",
            "composer install*": "allow"
        }
    }
}
```

A project without its own config gets only the global protection.

## Know the scope boundary

The kit protects **locations, not information flows**. Once content leaves
the project roots (`cp .env /tmp/backup`), no scan recaptures it. As a
visibility aid, `opk status` ends with a **leak scan**: a name-based,
report-only sweep of the scratch directories (`/tmp`, `/var/tmp`,
`/dev/shm`, overridable via `LEAK_SCAN_DIRS`) listing files matching the
deny patterns. Renamed copies stay invisible; false positives are expected.
When the scan cannot run, the verdict row distinguishes causes
(issue #217): no agent config at all is an uncounted *unknown* (nothing
to derive patterns from), while a missing parser/python3 or an
unparseable config stays a counted warning.

On the git side, prevent secrets from entering history in the first place
(pre-commit secret scanning, e.g. gitleaks).
