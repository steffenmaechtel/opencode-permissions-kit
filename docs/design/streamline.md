# PLAN-STREAMLINE: file/folder taxonomy and clean names

> Status: **IMPLEMENTED on `feature/streamline`** (issue #54) — unit suite
> + lint green; e2e verification pending. Where wording differs from the
> code, the code wins.

## 1. Problem & goal

Issue #54: the library mixed binaries and sourced libraries at the same
level, names were unclear (`wrapper`, `kit`), extensions were inconsistent
(`bin/` held `.sh` and extensionless files), and single-purpose files
(`jsonc-parser.py`) sat between shell libraries. The repo layout also
diverged from the deployed library.

Goal: one taxonomy where **the file extension encodes the usage**, every
command has a self-explanatory name, and the repo mirrors the deployed
library 1:1.

## 2. Decisions

| Decision | Result |
|---|---|
| Naming convention | **extension = usage**: extensionless = command (exec), `.sh` = sourced lib / `sh`-run script, `.py` = python, `.json`/`.tsx` = assets |
| Repo ↔ deployed | **`files/opencode-permissions-kit-lib/` ≡ `/usr/local/lib/opencode-permissions-kit/`, exception-free 1:1.** `files/` root holds only the non-library files: `install.sh` (streamed entry, never deployed) and `etc/` (deploys to `/etc`) |
| `wrapper` rename | `bin/opencode-as-opencode` — symmetric with `bin/ddev-as-opencode` ("run X as the opencode user"); deployed as `/usr/local/bin/opencode` |
| `kit` rename | `bin/opk` — matches the user-facing command |
| `jsonc-parser.py` | `py/jsonc-parser.py` |
| `bin/socket-check.sh`, `bin/cwd-check.sh` | `bin/socket-check`, `bin/cwd-check` (no `.sh` in `bin/`) |
| `setup-container-backend.sh` | `bin/setup-container-backend` (executed via `sudo sh`, never sourced — it is a command) |
| Sourced libraries | `sh/` folder (symmetry with `py/`) |
| `ddev-migrate.sh` (dual: sourced + run) | **split**: functions in `sh/ddev-migrate.sh`, new `bin/ddev-migrate` dispatcher shim. No `hybrid/` folder — the shim dissolves the category |
| `ddev-as-opencode.sh` (rc hook) | renamed to **`sh/ddev-terminal.sh`** — decouples the hook from `bin/ddev-as-opencode` (the binary keeps the name issue #54 calls good). Free *now* because update.sh sed-rewrites the rc hook line's path anyway |
| Management scripts | `management/` folder — **in the repo lib AND deployed** (mirror rule) |
| Templates | `templates/` folder — render sources that also live as working copies in the deployed library (`config.sh` re-renders sudoers, refreshes configs at runtime) |
| `umask.sh` | `files/etc/umask.sh` — the one file deploying outside the library (`/etc/profile.d/opencode-permissions-kit-umask.sh`); `files/etc/` can later hold further `/etc` sources (sysctl, wsl.conf snippets) |
| `opk-` prefix for bin/ | **no** — `$LIBDIR/bin` is never on PATH; everything runs by absolute path (sudoers, kit scripts) or via the `/usr/local/bin/{opencode,opk}` symlinks |
| Unit tests | moved to **`tests/unit/`** (completing the `e2e/` + `ux/` scheme); `test-wrapper-validation.sh` renamed to `unit/test-opencode-as-opencode.sh`; `check-host.sh` + `fixtures/` stay at `tests/` root |
| Breaking change policy | accepted — no compatibility stubs; streamed one-liner is the migration path (§5) |
| `VERSION` | untouched by this branch; 0.0.29 is the maintainer's release chore |

Rejected alternatives (kept for context):

- **`.sh` stripped from sourced libs too** — rc-hook re-appends (dead
  lines in users' dotfiles), no editor/shellcheck hints, no gain.
- **`hybrid/` folder** — category of size one; the bin shim is cleaner.
- **`bin/sh/`** — the libs are not subprocesses of `bin/` files; `bin/sh`
  reads as a shadow of the system shell.
- **`templates/` parallel to the lib** — 3 of 4 templates must also live
  in the deployed library (working copies for the installed `config.sh`),
  so the mirror would break from the other direction. Instead they live
  inside the lib, and only `umask.sh` (never in the library) sits in
  `files/etc/`.
- **`opk-` prefix** — impossible for `bin/opencode` anyway; no conflicts
  possible (absolute-path invocation only).
- **Compatibility stubs at old repo paths** (the `migrate-denies.sh`
  pattern) — would mean ~14 stub files; dropped because breaking the old
  `opk update` path is acceptable (§5). The `migrate-denies.sh` stub was
  deleted with the same stroke.

## 3. Final layout

### Repository

```
files/
├── install.sh                    ← the ONLY streamed entry
│                                   (curl .../files/install.sh | sudo bash — URL unchanged)
└── etc/
    └── umask.sh                  ← deploys to /etc/profile.d/, never into the library

files/opencode-permissions-kit-lib/   ← ≡ deployed library, 1:1
├── bin/       opencode-as-opencode  opk  ddev-as-opencode  ddev-migrate
│              setup-container-backend  socket-check  cwd-check
├── sh/        ui.sh  log.sh  fs-baseline.sh  ddev-handover.sh
│              ddev-hosts.sh  ddev-migrate.sh (functions)
│              shell-warn.sh  ddev-terminal.sh (was ddev-as-opencode.sh)
├── py/        jsonc-parser.py
├── tui/       kit-mode.tsx  opencode-danger.theme.json  tui.json  tui-danger.json
├── management/  config.sh  update.sh  status.sh  uninstall.sh
└── templates/   sudoers.template  opencode.jsonc  opencode-deny-all.jsonc
```

### Deployed (`/usr/local/lib/opencode-permissions-kit/`)

```
├── bin/         the repo bin/ + the real `opencode` binary (install-time download)
├── sh/  py/  tui/
├── management/  config.sh  update.sh  status.sh  uninstall.sh
└── templates/   sudoers.template  opencode.jsonc  opencode-deny-all.jsonc
```

Symlinks: `/usr/local/bin/opencode` → `bin/opencode-as-opencode`,
`/usr/local/bin/opk` → `bin/opk` (link names unchanged).

Render targets outside the library (from `templates/` and `tui/`):
`/etc/opencode-permissions-kit/sudoers`, `/etc/profile.d/opencode-permissions-kit-umask.sh`
(from `files/etc/umask.sh`), `/home/opencode/.config/opencode/opencode.jsonc`,
`/home/<dev>/.config/opencode/…`, TUI user files.

### Tests

```
tests/
├── unit/        test-*.sh (22 files; test-opencode-as-opencode.sh
│                was test-wrapper-validation.sh)
├── e2e/         run.sh  run-docker-rootless.sh  run-ddev.sh  lib.sh
├── ux/          install demos
├── fixtures/    shared test data
└── check-host.sh
```

## 4. `ddev-migrate` split

`sh/ddev-migrate.sh` keeps the function library (`ddev_migrate_*`),
sourced by `install.sh`. `bin/ddev-migrate` resolves its library root,
sources the lib and dispatches `export|import|list`. Documented retry
commands improved from
`sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh export …`
to `sudo /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate export …`.

## 5. Update path for old installs (breaking, documented)

Current user base is the maintainer's three WSL installations — a
documented one-time migration is acceptable; permanent stub files are not.

| Path | Behaviour |
|---|---|
| **Streamed update (the migration path)** | `curl -fsSL …/master/files/opencode-permissions-kit-lib/management/update.sh \| sudo bash` — note the LONGER URL (update.sh moved into the library; only `files/install.sh` keeps its root place). Fetches the NEW update.sh first, which fetches new paths and runs the old-layout cleanup. Preserves `projects.conf`, `install.conf` keys, opencode configs |
| Reinstall | `opk uninstall` + install.sh one-liner (URL unchanged) |
| `opk update` on ≤ 0.0.28 | Aborts with the raw curl 404 — unavoidable: the installed update.sh bakes in the old file list. Release note + `docs/how-to/update.md` get a "migrating to ≥ 0.0.29" section naming the one-liner |

Cleanup in the new update.sh (idempotent `rm -f` of the union of
historical paths, after the new layout is deployed): `$LIBDIR/wrapper`,
`$LIBDIR/kit`, `$LIBDIR/jsonc-parser.py`, `$LIBDIR/bin/*.sh`,
`$LIBDIR/{ui,log,shell-warn,setup-container-backend,ddev-as-opencode,ddev-handover,ddev-migrate,ddev-hosts,fs-baseline}.sh`,
`$LIBDIR/{config,update,status,uninstall}.sh`,
`$LIBDIR/{sudoers.template,opencode.jsonc,opencode-deny-all.jsonc}`,
`$LIBDIR/migrate-denies.sh`.

The upgrade floor **stays 0.0.14**: the streamed update.sh handles any old
layout through the cleanup. Sudoers is re-rendered unconditionally
(covers the renamed probe paths `bin/socket-check`, `bin/cwd-check`).

### rc-file hooks (the delicate spot)

`.bashrc`/`.zshrc`/`.profile` reference `shell-warn.sh` and
`ddev-as-opencode.sh` by absolute path. Moving them would leave the hook
line dead (its `[ -f ]` guard) and `ddev()` silently unwrapped. The new
update.sh **sed-rewrites the kit-owned hook lines in place** (path AND
stem rename in one pass, restricted to the exact kit path — user lines
are never touched) and appends only when no hook line exists at all.
`umask.sh` and the runtime sources inside `ddev-terminal.sh`
(`ddev-hosts.sh`, `ddev-handover.sh`) moved to their new paths in the
same release.

## 6. Touch points (all in this branch)

| Area | Change |
|---|---|
| `install.sh` | `fetch_kit` list + `mkdir` list (`bin sh py tui management templates`, `etc`), deploy `cp`/`chmod`, symlinks, rc-hook lines (new paths), retry texts (`bin/ddev-migrate`), template/umask sources |
| `update.sh` (→ `management/`) | `KIT_FILES`, deploy section, symlink refresh, **old-layout cleanup**, rc-hook sed-rewrite, one-liner URL in header |
| `templates/sudoers.template` | probe rules → `bin/socket-check`, `bin/cwd-check` |
| `bin/opencode-as-opencode` | SHADOW self-check readlink target, `py/jsonc-parser.py` path, probe paths |
| `bin/opk` | LIBDIR resolves one level up (bin/), dispatcher → `management/*.sh`, sources → `sh/`, usage text, handover re-exec self-path, error messages |
| `management/config.sh` | lib candidates → `../sh/`, `../bin/`, `../templates/` (checkout + deployed), setup script invocation |
| `management/status.sh` | lib/parser paths, wrapper check → `bin/opencode-as-opencode`, ddev-hook grep → `sh/ddev-terminal.sh`, management paths in hints |
| `management/uninstall.sh` | log.sh candidates → `../sh/` |
| `sh/ddev-terminal.sh` | runtime sources → `sh/ddev-hosts.sh`, `sh/ddev-handover.sh` |
| `sh/shell-warn.sh` | wrapper target path, update.sh hint |
| `etc/umask.sh` | sources `sh/shell-warn.sh` |
| `bin/ddev-migrate` | NEW dispatcher (sources `sh/ddev-migrate.sh`) |
| `Makefile` | lint list, test targets (`tests/unit/…`, `test-opencode-as-opencode`), `check-version` update.sh path |
| `.github/workflows/{test,e2e,e2e-ddev}.yml` | chmod lists (tests/unit + new file paths) |
| Unit tests | moved to `tests/unit/`, relative paths (`../../files`, `../fixtures`), expected-string updates |
| Docs | `reference/files.md`, `concepts/wrapper.md`, `reference/cli.md`, `how-to/update.md` (migration section), `troubleshooting.md`, AGENTS.md, CONTRIBUTING.md |

Security model untouched: pure file-layout change, no permission semantics.

## 7. Verification

```bash
make lint                 # shellcheck over the shipped scripts  ✓ green
sh tests/unit/test-*.sh   # full unit suite (make test)           ✓ green
make check-version        # VERSION + KIT_BRANCH consistency      ✓ green
make e2e                  # Docker needed                         pending
make e2e-rootless
make e2e-ddev
```

Both e2e suites (plus e2e-ddev) are part of the definition of done for
install.sh/update.sh/wrapper changes (AGENTS.md).
