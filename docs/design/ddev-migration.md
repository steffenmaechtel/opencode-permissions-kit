# DDEV-MIGRATION: database bridge for the daemon switch at install time

> Status: **IMPLEMENTED.** Design record for issue #15 ("First install move
> user ddev into opencode ddev"). Where this plan conflicts with the code,
> the code wins.

## 1. Problem

Pre-kit, ddev runs as the **default user** against *their* daemon (rootful
socket or a dev-rootless one). After the kit takes over, ddev always runs as
the `opencode` user against a **fresh rootless daemon**
(docs/design/ddev-working.md §11). Two consequences:

- The developer's containers and **database volumes become unreachable**
  (every `ddev start` from now on talks to the new, empty daemon).
- Containers cannot move between daemons — there is no `docker export`
  path that carries a ddev project's DB volume across daemons. **SQL dumps
  are the only portable copy.**

File data (code, uploads in bind mounts) is unaffected: the project
directories themselves stay in place and are shared via the group baseline.

## 2. Decision

**Export during install, import as a separate user-driven step.**

1. **Export (automated, install.sh Step 4b):** while the dev-side ddev
   still works — i.e. BEFORE the `.ddev` handover at the end of Step 5
   chowns `.ddev` to `opencode` and breaks dev-side `ddev start` — run per
   project: `ddev start <name>` → `ddev export-db <name> --file=...` →
   `ddev stop <name>`. One project at a time (a production WSL box may
   hold dozens — running them all at once would exhaust RAM). One final
   `ddev poweroff` stops the old router and frees 80/443 for the
   opencode-side router. Containers are removed but database volumes stay;
   nothing is destroyed.
2. **Dumps land in** `/var/backups/opencode-permissions-kit/ddev-migration-<ts>/`
   (`opencode:opencode`, dir 750, files 640 — the developer stays in the
   sharing group and can read them). A `manifest.conf`
   (`OK|name|approot|file`, `FAIL|name|approot|`, `SKIP|name|approot|reason`)
   records the outcome. Dumps are the safety net — the kit never deletes
   them.
3. **Import (manual, post-install):** the import is deliberately NOT part
   of the install. The first opencode-side `ddev start` pulls images
   (~minutes); that must not block or fail the installation. The install
   summary and `opencode-permissions-kit status` show waiting dumps with
   the commands:
   - batch: `sudo sh /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh import`
   - per project: `ddev start <name> && ddev import-db <name> --file=<dump>.sql.gz`
     (the `ddev()` shell function already runs as `opencode` — no sudo, no
     chown round-trip).
   Worst case = dumps exist + documented manual import. That is strictly
   better than the issue's hotfix (a chown round-trip as the dev user to
   make dev-side `export-db` work again).

### Details that came out of the ddev source (github.com/ddev/ddev)

- ddev commands address projects by **NAME** (the registry key in
  `global_config.yaml` → `project_info.<name>.approot`), never by path —
  `getRequestedProjects()` looks names up in the docker/registry maps.
- `omit_containers` (project config) and `omit_containers_global` (global
  config) accept only `db` and `ddev-ssh-agent`
  (pkg/nodeps/values.go `ValidOmitContainers`). Projects omitting `db`
  have **no database to export** — skipped with a manifest SKIP entry.
- Only the **default database** is dumped per project; extra named
  databases need a manual `ddev export-db --database=<name>`.

## 3. Implementation

- `files/opencode-permissions-kit-lib/ddev-migrate.sh` — sourced by
  install.sh (`ddev_migrate_*` functions) AND standalone
  (`sh ddev-migrate.sh export <dev-user> <roots>... | import | list`).
  Parsing is jq-free (awk over the YAML subset ddev writes); running as
  the dev user goes through `sudo -u` with `HOME`/`XDG_RUNTIME_DIR`
  re-set (same env discipline as `bin/ddev-as-opencode`).
- `install.sh`:
  - `--skip-ddev-migration` flag (opt-out for scripted installs);
  - inventory line + plan line when the dev registry has projects;
  - Step 4b before the handover; idempotence via the `DDEV_EXPORTED=1`
    stamp in `install.conf` and via "opencode already has projects";
  - summary: dumps + import hint.
- `status.sh`: "db dumps … waiting for import" (warn) until the opencode
  registry is populated, informational afterwards.
- Failures are **never fatal to the export**: a project whose `ddev start`
  fails (old production projects that no longer boot) is recorded as a
  FAIL manifest entry and the loop continues — the other projects still
  get their dumps. Afterwards the installer lists the failed projects and
  asks **interactively**: continue anyway (their databases become
  unreachable after the handover) or abort — default **abort**, because
  aborting is the safe side: the `.ddev` handover has not run yet, the
  dev side still works, the user can fix the broken project and re-run.
  Non-interactive installs (`--yes`) print the list + warning and
  continue. The `DDEV_EXPORTED` stamp is only written when **zero**
  exports failed, so a re-run retries.

## 4. Tests / CI

- `tests/test-ddev-migrate.sh`: registry parser (quoted/unquoted approots),
  root filter, omit_containers detection (inline + block, project +
  global), fake-ddev export run (per-project start→export→stop by NAME,
  single poweroff, db-less SKIP, manifest bookkeeping), static wiring
  (install Step 4b ordering before the handover, stamp, update.sh,
  status.sh, Makefile, both workflow chmod lists).
- `tests/test-install-args.sh`: `--skip-ddev-migration` parsing, default
  ON.
- Kit file lists (fetch_kit / KIT_FILES) covered by test-kit-files.sh.

## 5. Open questions

- Import a dump automatically right after the first successful
  opencode-side `ddev start`? Rejected for now — the user decides when
  the image-pull cost happens (this issue's reporter explicitly wanted
  export-Only with manual import as the fallback).
- Export extra named databases (`--database=` loop)? Deferred; documented
  as manual.
