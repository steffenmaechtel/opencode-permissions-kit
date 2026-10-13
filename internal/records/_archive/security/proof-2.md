# PROOF-2: Developer-Created `.env` in the IDE — Protection Timing

> **SUPERSEDED (DDEV-WORKING):** the hard ACL deny layer this document
> analyzes/proposes was **removed** — file permissions are now opencode's
> soft permission layer only. This document is kept as the historical
> analysis record; see `docs/design/ddev-working.md` for the current model
> and `docs/concepts/security-model.md` for the authoritative
> usage documentation. Where wording differs, the code and the docs win.

**Question under test.** A developer using the kit creates a `.env` file himself in his
IDE (no git involved yet). Is that file readable for the opencode user until the kit
reacts? There is no hook or listener watching developer-created files — would the file
only become protected at the next git action (when a hook fires)?

## Verdict

**Yes — the hypothesis is correct, and it is actually slightly worse:**

1. The new file is readable by opencode immediately (group-readable via `www-data`).
2. No hook, daemon, inotify/fanotify listener, or IDE integration watches file
   creation. The kit is purely *reactive* (scan on trigger).
3. Protection is NOT even guaranteed at the next opencode session start, because the
   wrapper's startup scan runs **without `--force`** and is skipped by the mtime cache.
   The file only becomes protected at the next `--force` trigger: a git hook
   (commit/merge/checkout), `config.sh` ACL refresh, or `update.sh --refresh`.

## Step-by-step analysis

### 1. Why the file is readable at creation time

- The IDE creates the file as `DEFAULT_USER` — **not** as `opencode`. A named ACL
  `u:opencode:---` would therefore apply (it is not the owner), but **none is set**:
  nothing in the kit reacts to file-creation events.
- Project trees are group `www-data`, directories are setgid (`drwxrwsr-x+`), and the
  kit's profile umask is `002` (`files/umask.sh`) — so a new file is typically
  `DEFAULT_USER:www-data` mode `664` → **group-readable**.
- opencode reaches project files precisely through that `www-data` group
  (`WWW_GROUP="www-data"`). Group read = readable by opencode.
- Since the developer already owns the file, only the `setfacl` deny is missing when
  protection does run (the `chown` fix-up from PROOF-1 is a no-op here — that fix-up
  exists for *opencode-created* files, e.g. via `git pull`).

### 2. What *does* trigger protection (and what does not)

| Event | Protects the new file? | Why |
|---|---|---|
| File created in IDE | — | No listener exists (no inotify/fanotify/daemon) |
| New opencode session (wrapper start) | **No** | `wrapper:265` runs protect-projects **without `--force`**; the mtime cache (`protect-projects.sh:131-140`) compares only config mtimes (global config, projects.conf, project configs) — a new file changes none of them → cache hit → scan skipped |
| `git commit` (by developer or agent) | Yes | `post-commit` hook runs `--force` (core.hooksPath is set for both users, `install.sh:634-635`) |
| `git pull` / `merge` / `checkout` | Yes | `post-merge` / `post-checkout` hooks run `--force` |
| `config.sh` → ACL refresh | Yes | Manual `sudo protect-projects.sh --force` |
| `update.sh --refresh` | Yes | Explicit `--force` at the end |
| `git add`, `git status`, IDE "stage" | No | No hook fires |

### 3. The mitigating layer: opencode's own permission rules

The exposure is smaller than raw filesystem readability suggests, because the
opencode.jsonc deny rules still apply at the *tool level*:

- `read` / `edit`: `"*.env*": "deny"` (`files/opencode.jsonc:36,69`) — opencode's own
  read/edit tools refuse the file regardless of ACLs.
- `bash`: `cat .env` is **not denied** — the template deliberately keeps `cat` at
  `ask` (see the comment at `files/opencode.jsonc:88-92`). So `cat .env` produces a
  user prompt, not a block.

**Consequence:** the unprotected file is exposed via the bash path if (a) the user
approves the `ask` prompt, or (b) the user has added any broader bash allow rule
(e.g. `cat *`). In those cases there is no OS-level backstop until the next
`--force` run.

## Candidate mitigations (not implemented)

1. **`--force` at wrapper session start** — closes the "restart doesn't help" gap
   (same fix as PROOF-1 case c). Cost: one full scan per opencode launch. This makes
   "next opencode session" the worst-case exposure window instead of "next git
   action".
2. **Filesystem watcher** (systemd path units / fanotify daemon) that re-runs
   protect-projects on `MOVED_TO`/`CREATE` in project roots. Closes the window to
   seconds, but adds a permanent system component — contrary to the kit's current
   "no daemon" design.
3. **Default ACLs on directories** are *not* viable: a default `u:opencode:---` on
   project dirs would deny opencode every newly created file — including its own
   work products (opencode writes via the `www-data` group, and the named-user deny
   would block it). Pattern-based inheritance does not exist in POSIX ACLs.
4. **Documented workflow**: tell developers (MANUAL.md) that hand-created sensitive
   files should be followed by `config.sh` → refresh, or simply committed — the
   `post-commit` hook closes the gap.

## Summary

The kit's protection model is **scan-based, not event-based**. Files that enter a
project outside of git (IDE, editor, `cp`, browser download, `ddev pull`) are
unprotected at the OS level until the next `--force` scan — and due to the mtime
cache, even a fresh opencode session does not force that scan. The tool-level
deny rules cover opencode's read/edit tools in the interim, leaving bash commands
(gated only by `ask`) as the residual risk channel.
