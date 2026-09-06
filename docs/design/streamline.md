# PLAN-STREAMLINE: file/folder taxonomy and clean names

> Status: **PLANNED** — decisions locked with the maintainer, implementation
> pending on `feature/streamline`. Tracking issue: #54. Where wording here
> differs from the eventual code, the code wins.

## 1. Problem & goal

Issue #54: the library mixes binaries and sourced libraries at the same
level, names are unclear (`wrapper`, `kit`), extensions are inconsistent
(`bin/` holds `.sh` and extensionless files), and single-purpose files
(`jsonc-parser.py`) sit between shell libraries.

Goal: one taxonomy where **the file extension encodes the usage**, every
command has a self-explanatory name, and old installs have a documented
(one-command) migration path.

## 2. Decisions

| Decision | Result |
|---|---|
| Naming convention | **extension = usage**: extensionless = command (exec), `.sh` = sourced lib / `sh`-run script, `.py` = python, `.json`/`.tsx` = assets |
| `wrapper` rename | `bin/opencode-as-opencode` — symmetric with `bin/ddev-as-opencode` ("run X as the opencode user"); deployed as `/usr/local/bin/opencode` |
| `kit` rename | `bin/opk` — matches the user-facing command |
| `jsonc-parser.py` | `py/jsonc-parser.py` |
| `bin/socket-check.sh`, `bin/cwd-check.sh` | `bin/socket-check`, `bin/cwd-check` (no `.sh` in `bin/`) |
| `setup-container-backend.sh` | `bin/setup-container-backend` (executed via `sudo sh`, never sourced — it is a command) |
| Sourced libraries | `sh/` folder (name chosen over `sourced-lib/` for symmetry with `py/`) |
| `ddev-migrate.sh` (dual: sourced + run) | **split**: functions stay in `sh/ddev-migrate.sh`, new ~10-line `bin/ddev-migrate` shim sources the lib and dispatches `export\|import\|list`. No `hybrid/` folder — the shim dissolves the category |
| `ddev-as-opencode.sh` (rc hook) | renamed to **`sh/ddev-terminal.sh`** — decouples the hook from `bin/ddev-as-opencode` (the binary keeps the name issue #54 calls good). Free *now* because update.sh sed-rewrites the rc hook line's path anyway; a later rename would cost another rc-migration release |
| Deployed management scripts | `management/` folder |
| Deployed templates | `templates/` folder |
| Breaking change policy | accepted — no compatibility stubs; streamed one-liner is the migration path (§5) |
| `VERSION` | untouched by this branch; 0.0.29 is the maintainer's release chore |

Rejected alternatives (kept for context):

- **`.sh` stripped from sourced libs too** — would need rc-hook re-appends
  (dead lines in users' dotfiles), loses editor/shellcheck hints, no gain:
  users never type lib names.
- **`hybrid/` folder** — category of size one; the bin shim is cleaner.
- **`bin/sh/`** — the libs are not subprocesses of `bin/` files; `bin/sh`
  also reads as a shadow of the system shell.
- **Compatibility stubs at old repo paths** (the `migrate-denies.sh`
  pattern) — would mean ~14 stub files; dropped because breaking the old
  `opk update` path is acceptable (§5).
- **`opk-` prefix for all `bin/` commands** — unnecessary: `$LIBDIR/bin`
  is never on PATH (everything is invoked by absolute path — sudoers
  rules, kit scripts — or via the two `/usr/local/bin` symlinks
  `opencode`/`opk`, whose names are fixed by design). A prefix would only
  lengthen sudoers/log/doc paths; `bin/opencode` (the real binary) could
  not be prefixed anyway.

## 3. Final layout

### Repository

```
files/
├── install.sh update.sh config.sh status.sh uninstall.sh umask.sh
│      ← streamed entry points; MUST keep .sh (curl URL contract)
├── sudoers.template opencode.jsonc opencode-deny-all.jsonc
│      ← template sources (paths unchanged → no fetch-list impact)
└── opencode-permissions-kit-lib/
    ├── bin/    opencode-as-opencode  opk  ddev-as-opencode
    │           ddev-migrate (NEW shim)  setup-container-backend
    │           socket-check  cwd-check
    ├── sh/     ui.sh  log.sh  fs-baseline.sh  ddev-handover.sh
    │           ddev-hosts.sh  ddev-migrate.sh (lib part)
    │           shell-warn.sh  ddev-terminal.sh (was ddev-as-opencode.sh)
    ├── py/     jsonc-parser.py
    └── tui/    (unchanged)
```

`files/opencode-permissions-kit-lib/migrate-denies.sh` (compat stub) is
**deleted** — its only consumer was the pre-0.0.29 fetch lists we are
dropping.

### Deployed (`/usr/local/lib/opencode-permissions-kit/`)

```
├── bin/         + the real `opencode` binary (unchanged location)
├── sh/  py/  tui/
├── management/  config.sh  update.sh  status.sh  uninstall.sh
└── templates/   sudoers.template  opencode.jsonc  opencode-deny-all.jsonc
```

Symlinks: `/usr/local/bin/opencode` → `bin/opencode-as-opencode`,
`/usr/local/bin/opk` → `bin/opk` (unchanged link names).

## 4. `ddev-migrate` split

`sh/ddev-migrate.sh` keeps the function library (`ddev_migrate_*`),
sourced by `install.sh`. `bin/ddev-migrate` is a small dispatcher:

```sh
#!/bin/sh
# sources sh/ddev-migrate.sh, dispatches on $1 (export|import|list)
```

Documented retry commands improve from
`sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh export …`
to `sudo /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate export …`.

## 5. Update path for old installs (breaking, documented)

Current user base is the maintainer's three WSL installations — a
documented one-time migration is acceptable; permanent stub files are not.

| Path | Behaviour |
|---|---|
| **Streamed update (the migration path)** | `curl -fsSL …/master/files/update.sh \| sudo bash` fetches the NEW update.sh first, which fetches only new paths and runs the old-layout cleanup below. Preserves `projects.conf`, `install.conf` keys, opencode configs |
| Reinstall | `opk uninstall` + install.sh one-liner |
| `opk update` on ≤ 0.0.28 | Aborts with the raw curl 404 — unavoidable: the installed update.sh bakes in the old file list and fails before any new code can render a message. Release note + `docs/how-to/update.md` get a "migrating to ≥ 0.0.29" section naming the one-liner |

Cleanup in the new update.sh (idempotent `rm -f` of the union of
historical paths, after the new layout is deployed):

- `$LIBDIR/wrapper`, `$LIBDIR/kit`, `$LIBDIR/jsonc-parser.py`
- `$LIBDIR/bin/socket-check.sh`, `$LIBDIR/bin/cwd-check.sh`
- `$LIBDIR/{ui,log,shell-warn,setup-container-backend,ddev-as-opencode,ddev-handover,ddev-migrate,ddev-hosts,fs-baseline}.sh`
- `$LIBDIR/{config,update,status,uninstall}.sh` (now in `management/`)
- `$LIBDIR/{sudoers.template,opencode.jsonc,opencode-deny-all.jsonc}` (now in `templates/`)

The upgrade floor **stays 0.0.14**: the streamed update.sh handles any old
layout through the cleanup, so locking users into a reinstall is not
needed. Sudoers is re-rendered unconditionally by update.sh (covers the
renamed probe paths).

### rc-file hooks (the delicate spot)

`.bashrc`/`.zshrc`/`.profile` reference `shell-warn.sh` and
`ddev-as-opencode.sh` by absolute path. Moving them would leave the hook
line dead (its `[ -f ]` guard) and `ddev()` silently unwrapped. The new
update.sh must **sed-rewrite the kit-owned hook lines in place**
(`s|…/opencode-permissions-kit/ddev-as-opencode.sh|…/opencode-permissions-kit/sh/ddev-terminal.sh|`
and the analogous `shell-warn.sh` → `sh/shell-warn.sh` rewrite, each
restricted to the exact kit path) — no dead lines, no gap. The rewrite
covers path AND stem rename in one pass. Append only when no hook line
exists at all. `umask.sh` and the runtime sources inside
`ddev-terminal.sh` (`ddev-hosts.sh`, `ddev-handover.sh`) move to `sh/`
paths in the same release.

## 6. Touch points (same PR)

| Area | Change |
|---|---|
| `install.sh` | `fetch_kit` list + `mkdir` list (`bin sh py tui`), deploy `cp`/`chmod`/`mkdir`, symlinks, rc-hook lines (new paths), retry texts (`bin/ddev-migrate`) |
| `update.sh` | `KIT_FILES`, deploy section, symlink refresh, **old-layout cleanup**, rc-hook sed-rewrite |
| `sudoers.template` | probe rules → `bin/socket-check`, `bin/cwd-check` (comment updates for the wrapper) |
| `bin/opencode-as-opencode` (wrapper) | SHADOW self-check readlink target, `py/jsonc-parser.py` path, `bin/socket-check`/`bin/cwd-check` probe paths |
| `bin/opk` (kit) | dispatcher targets → `management/*.sh`, sources → `sh/`, usage text direct-call paths, handover re-exec self-path |
| `config.sh` / `status.sh` / `uninstall.sh` / `umask.sh` | lib source candidates → `sh/`, `bin/setup-container-backend`, `status.sh` wrapper check → `bin/opencode-as-opencode`, uninstall removal list |
| `sh/ddev-as-opencode.sh` | runtime sources → `sh/ddev-hosts.sh`, `sh/ddev-handover.sh` |
| `sh/*.sh` libs | internal sourcing (`ui.sh` consumers) against new layout |
| `Makefile` | source lists, test target scripts |
| `.github/workflows/test.yml`, `e2e.yml`, `e2e-ddev.yml` | chmod lists — **both** files, enforced by `tests/test-workflows.sh` |
| Tests (~16 files) + `tests/e2e/run*.sh` (3) | path references |
| Docs | `reference/files.md` (layout tables), `concepts/wrapper.md`, `reference/cli.md`, `how-to/update.md` (migration section), `troubleshooting.md`, `how-to/container-tools.md` path mentions |

Security model untouched: pure file-layout change, no permission semantics.

## 7. Verification

```bash
make lint                 # shellcheck over shipped scripts
sh tests/test-*.sh        # full unit suite
make check-version        # VERSION + KIT_BRANCH consistency
make e2e                  # Docker needed
make e2e-rootless
make e2e-ddev
```

Both e2e suites (plus e2e-ddev) are part of the definition of done for
install.sh/update.sh/wrapper changes (AGENTS.md).
