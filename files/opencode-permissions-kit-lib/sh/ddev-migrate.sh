# shellcheck shell=sh
# opencode permissions kit -- ddev-migrate.sh
#
# Database bridge for the ddev switch that happens at install time
# (issue #15): pre-kit ddev projects live in the DEFAULT user's registry
# and run against the developer's daemon. After the kit takes over, ddev
# ALWAYS runs as the 'opencode' user against a fresh rootless daemon —
# the developer's containers and database volumes become unreachable.
# Containers cannot move between daemons; SQL dumps are the only
# portable copy. This helper exports them while the developer-side ddev
# still works (install.sh runs it BEFORE the .ddev handover, which
# chowns .ddev to opencode and breaks dev-side `ddev start`).
#
# Modes (see the usage block at the bottom):
#   export  run as root: per registered project (under the given roots)
#          `ddev start` + `ddev export-db` + `ddev stop` as the DEFAULT
#          user — ONE project at a time (a production machine may hold
#          dozens; running them all at once would exhaust RAM) — then one
#          final `ddev poweroff` to free the ports. Dumps land in
#          $DDEV_MIG_BACKUP_ROOT/ddev-migration-<timestamp>/.
#   import  run as root: post-install convenience — per dump `ddev start`
#          + `ddev import-db` as the opencode user. Importing manually
#          per project (`ddev import-db --file=...`) is always possible;
#          dumps are never deleted by the kit.
#   list    show dump directories and their contents.
#
# ddev commands address projects by NAME (the registry key), never by
# path. Projects without a db container (`omit_containers: [db]` in
# .ddev/config.yaml, or `omit_containers_global` in the global config —
# ddev only allows "db"/"ddev-ssh-agent" there) have nothing to export
# and are skipped with a manifest SKIP entry.
#
# Dumps are the safety net, the import is best-effort convenience: every
# per-project failure is non-fatal and reported. Only the DEFAULT
# database of each project is exported; extra named databases need a
# manual `ddev export-db --database=<name>`.
#
# Sourced (install.sh calls the ddev_migrate_* functions) — the CLI
# dispatch lives in bin/ddev-migrate. No ui.sh dependency — plain output,
# callers wrap with their own UI/log calls as needed.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/sh/ddev-migrate.sh.

DDEV_MIG_BACKUP_ROOT="${DDEV_MIG_BACKUP_ROOT:-/var/backups/opencode-permissions-kit}"

# _ddev_migrate_scan_registry <yaml-file>
# Prints "name|approot" pairs from a ddev project-list YAML. No ddev
# binary, no jq — pure awk over the YAML subset ddev actually writes
# (name -> approot map; leading indentation is stripped, so one scanner
# covers both the standalone top-level map and the project_info:-nested
# variant):
#   <name>:
#     approot: /path/to/project
_ddev_migrate_scan_registry() {
    [ -f "${1:-}" ] || return 0
    awk '
        {
            line = $0
            sub(/^[ \t]+/, "", line)
            if (line ~ /^#/) next
            if (line ~ /^[^ \t:]+:[[:space:]]*$/) {
                name = line; sub(/:.*/, "", name)
            } else if (line ~ /^approot:/) {
                sub(/^approot:[[:space:]]*/, "", line)
                gsub(/"/, "", line)
                if (name != "" && line != "") printf "%s|%s\n", name, line
            }
        }
    ' "$1"
    return 0
}

# ddev_migrate_registry <ddev-home>
# Prints "name|approot" for every project in ddev's global registry —
# from BOTH registry layouts ddev has used: project_list.yaml (ddev >=
# 1.23.0 moved the list into its own file, commit 94d77509a) and the
# legacy project_info: block inside global_config.yaml (ddev < 1.23 and
# not-yet-migrated homes — ddev clears it on first run of a newer
# version). A name present in both (mid-migration) is printed twice —
# harmless: callers filter by approot and the export resume logic skips
# projects whose dump is already in the manifest.
ddev_migrate_registry() {
    dm_rh="${1:-}"
    [ -n "$dm_rh" ] || return 0
    _ddev_migrate_scan_registry "$dm_rh/project_list.yaml"
    _ddev_migrate_scan_registry "$dm_rh/global_config.yaml"
    return 0
}

# ddev_migrate_under_roots <approot> <root> [root ...]
# True (0) when <approot> lies under one of the roots (or equals one).
ddev_migrate_under_roots() {
    dmur_p="${1%/}"
    shift
    for dmur_r in "$@"; do
        case "$dmur_p" in "${dmur_r%/}"|"${dmur_r%/}"/*) return 0 ;; esac
    done
    return 1
}

# ddev_migrate_home <user>
# The user's home via getent, DDEV_MIG_DEV_HOME as override (keeps the
# unit tests hermetic — never read a real user's registry there).
ddev_migrate_home() {
    dmh_h=$(getent passwd "$1" 2>/dev/null | cut -d: -f6 || true)
    [ -n "$dmh_h" ] || dmh_h="/home/$1"
    printf '%s\n' "${DDEV_MIG_DEV_HOME:-$dmh_h}"
}

# ddev_migrate_projects <ddev-home> <root> [root ...]
# Like ddev_migrate_registry, but only projects whose approot lies under
# one of the registered roots (those are the projects the kit takes over)
# and whose directory still exists.
ddev_migrate_projects() {
    dm_ph="${1:-}"; shift
    [ -n "$dm_ph" ] || return 0
    ddev_migrate_registry "$dm_ph" | while IFS='|' read -r dm_n dm_ar; do
        [ -n "$dm_ar" ] || continue
        [ -d "$dm_ar" ] || continue
        if ddev_migrate_under_roots "$dm_ar" "$@"; then
            printf '%s|%s\n' "$dm_n" "${dm_ar%/}"
        fi
    done
    return 0
}

# ddev_migrate_outside <ddev-home> <root> [root ...]
# Names of registry projects whose approot is NOT under any of the given
# roots — BEFORE the dir-existence filter: the point is to expose what
# the root filter silently drops (production finding: one of twelve
# projects exported, no hint why).
ddev_migrate_outside() {
    dmo_ph="${1:-}"; shift
    [ -n "$dmo_ph" ] || return 0
    ddev_migrate_registry "$dmo_ph" | while IFS='|' read -r dmo_n dmo_ar; do
        [ -n "$dmo_ar" ] || continue
        ddev_migrate_under_roots "$dmo_ar" "$@" || printf '%s\n' "$dmo_n"
    done
    return 0
}

# ddev_migrate_gap <dev-user> <root> [root ...]
# Partial-export detector: prints "<recorded> <registered> <dump-dir>"
# when the CURRENT registry under the roots lists MORE projects than
# the newest manifest ever ATTEMPTED (OK, SKIP and FAIL entries count —
# a project that failed export-db for real, e.g. it never had a
# database, must not nag forever), exit 0; exit 1 when there is no
# manifest, no registry, or no gap. Production finding: a
# legacy-registry install exported 1 of 12 databases, stamped
# DDEV_EXPORTED=1, and every retry silently skipped while eleven
# databases stayed behind in the old daemon.
ddev_migrate_gap() {
    dmg_dev="$1"; shift
    dmg_dir=$(ddev_migrate_latest_dir)
    [ -n "$dmg_dir" ] && [ -f "$dmg_dir/manifest.conf" ] || return 1
    dmg_have=$(grep -cE '^(OK|SKIP|FAIL)\|' "$dmg_dir/manifest.conf" 2>/dev/null || true)
    dmg_have=${dmg_have:-0}
    dmg_now=$(ddev_migrate_projects "$(ddev_migrate_home "$dmg_dev")/.ddev" "$@" 2>/dev/null | grep -c . || true)
    dmg_now=${dmg_now:-0}
    [ "$dmg_now" -gt "$dmg_have" ] || return 1
    printf '%s %s %s\n' "$dmg_have" "$dmg_now" "$dmg_dir"
    return 0
}

# ddev_migrate_done <opencode-user>
# True (0) when the opencode user already has registered ddev projects —
# the switch already happened, an export would find a broken dev side.
# Both registry layouts count (see ddev_migrate_registry): modern
# project_list.yaml and the legacy project_info: block. DDEV_MIG_OC_HOME
# overrides the home base (keeps unit tests hermetic — the real path is
# always /home/<opencode-user>).
ddev_migrate_done() {
    dm_ocd="${DDEV_MIG_OC_HOME:-/home/${1:-opencode}}/.ddev"
    { [ -f "$dm_ocd/project_list.yaml" ] && grep -q 'approot:' "$dm_ocd/project_list.yaml" 2>/dev/null; } && return 0
    [ -f "$dm_ocd/global_config.yaml" ] && grep -q '^project_info:' "$dm_ocd/global_config.yaml" 2>/dev/null
}

# _ddev_migrate_run_as <user> <cmd...>
# Runs cmd as <user> with HOME/XDG_RUNTIME_DIR set (sudo's env_reset
# drops them; ddev needs HOME for its registry and XDG_RUNTIME_DIR for
# a rootless socket). Callers are root (install.sh / sudo standalone).
_ddev_migrate_run_as() {
    dm_u="$1"; shift
    dm_h=$(getent passwd "$dm_u" 2>/dev/null | cut -d: -f6 || true)
    [ -n "$dm_h" ] || return 1
    dm_i=$(id -u "$dm_u" 2>/dev/null)
    # Each env assignment is ONE argument (0.0.43a F6): a home path with
    # whitespace must never split into a bogus env word. Positional
    # parameters are per-function scope — `set --` rebuilds the command
    # with the caller's "$@" APPENDED (the e2e caught an intermediate
    # draft that dropped them: every helper call degenerated into a
    # command-less `env` print with rc 0 — start "succeeded", no dump).
    if [ -n "$dm_i" ] && [ -d "/run/user/$dm_i" ]; then
        set -- env "HOME=$dm_h" "XDG_RUNTIME_DIR=/run/user/$dm_i" "$@"
    else
        set -- env "HOME=$dm_h" "$@"
    fi
    sudo -u "$dm_u" "$@"
}

# _ddev_migrate_bin [user]
# Resolves the real ddev binary: root's PATH, the standard locations,
# then (when <user> is given) that user's private install paths — ddev's
# installer offers a per-user install, and `sudo -u` does not inherit it.
_ddev_migrate_bin() {
    dmb_u="${1:-}"
    dmb_h=""
    if [ -n "$dmb_u" ]; then
        dmb_h=$(getent passwd "$dmb_u" 2>/dev/null | cut -d: -f6 || true)
    fi
    # The per-user candidates are separate quoted words (0.0.43a F6): a
    # home with whitespace used to re-split a string list, and the bare
    # directory prefix passed [ -x ] — emitting a DIRECTORY as the ddev
    # binary. ${dmb_h:+...} expands to nothing (no word) when unset.
    for dm_c in "$(command -v ddev 2>/dev/null || true)" /usr/local/bin/ddev /usr/bin/ddev \
        "${dmb_h:+$dmb_h/.local/bin/ddev}" "${dmb_h:+$dmb_h/bin/ddev}" "${dmb_h:+$dmb_h/.ddev/bin/ddev}"; do
        # -f besides -x: a traversable directory must never qualify.
        [ -n "$dm_c" ] && [ -f "$dm_c" ] && [ -x "$dm_c" ] && { echo "$dm_c"; return 0; }
    done
    return 1
}

# _ddev_migrate_list_has_db <yaml-file> <key>
# Prints yes/no: does the YAML scalar-list <key> (omit_containers,
# omit_containers_global) in <file> contain the item "db"? Handles both
# ddev-written forms — inline ("[db, ddev-ssh-agent]") and block
# ("- db" items on following lines). A missing file is "no".
_ddev_migrate_list_has_db() {
    [ -f "$1" ] || { echo no; return 0; }
    # NOTE: awk `exit` still runs the END block — decide there, once.
    awk -v key="$2" '
        # CRLF guard (issue #46): Windows-edited config.yaml — block-list
        # items would keep their \r and "- db\r" would miss the comparison.
        { gsub(/\r/, "") }
        $0 ~ "^[[:space:]]*" key ":" {
            line = $0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            sub(/^#.*$/, "", line)
            if (line ~ /^\[/) {
                sub(/^\[/, "", line); sub(/\].*$/, "", line)
                gsub(/"/, "", line)
                if (line ~ /(^|[^A-Za-z0-9_-])db([^A-Za-z0-9_-]|$)/) found = 1
                done = 1; exit
            }
            if (line != "" && line != "{}") { done = 1; exit }
            inlist = 1; next
        }
        inlist {
            if ($0 ~ /^[[:space:]]*-[[:space:]]/) {
                line = $0
                sub(/^[[:space:]]*-[[:space:]]*/, "", line)
                sub(/[[:space:]]+#.*$/, "", line)
                gsub(/"/, "", line)
                if (line == "db") found = 1
            } else if ($0 ~ /^[^[:space:]]/) {
                inlist = 0
            }
            next
        }
        END { if (found) print "yes"; else print "no" }
    ' "$1"
}

# ddev_migrate_has_db <approot> <dev-ddev-home>
# True (0) when the project at <approot> HAS a db container — only those
# are exportable. False when `omit_containers: [db]` (project config) or
# `omit_containers_global: [db]` (global config) omits it — ddev only
# ever allows "db" and "ddev-ssh-agent" there (pkg/nodeps/values.go).
ddev_migrate_has_db() {
    dm_root="${1:-}"; dm_home="${2:-}"
    [ -n "$dm_root" ] || return 1
    [ "$(_ddev_migrate_list_has_db "$dm_root/.ddev/config.yaml" omit_containers)" = "yes" ] && return 1
    [ "$(_ddev_migrate_list_has_db "$dm_home/global_config.yaml" omit_containers_global)" = "yes" ] && return 1
    return 0
}

# ddev_migrate_export <dev-user> <opencode-user> <opencode-group> <root> [root ...]
# Creates a fresh dump directory, exports every eligible project's
# database as the dev user, powers the old daemon down, then hands the
# dumps to the opencode user (group-readable for the developer). Sets
# DD_MIG_DUMP_DIR / DD_MIG_OK / DD_MIG_FAIL for the caller. Returns 0
# when at least one dump was written.
ddev_migrate_export() {
    dm_dev="$1"; dm_oc="$2"; dm_ocg="$3"; shift 3
    DD_MIG_DUMP_DIR=""; DD_MIG_OK=0; DD_MIG_FAIL=0
    dm_bin=$(_ddev_migrate_bin "$dm_dev") || {
        echo "  ddev not found — cannot export databases."
        return 1
    }
    # The dev user's ddev home (DDEV_MIG_DEV_HOME override keeps the
    # unit tests hermetic — never read a real user's registry there).
    dm_home=$(ddev_migrate_home "$dm_dev")
    dm_list=$(ddev_migrate_projects "$dm_home/.ddev" "$@")
    [ -n "$dm_list" ] || { echo "  no ddev projects under the registered roots."; return 1; }
    # Registry entries outside the given roots are legal by design (the
    # kit only takes over registered roots) — but a silently shrinking
    # dump set is the #1 migration surprise. Say it loudly, with names.
    dm_outside=$(ddev_migrate_outside "$dm_home/.ddev" "$@")
    if [ -n "$dm_outside" ]; then
        echo "  WARNING: $(printf '%s\n' "$dm_outside" | grep -c .) registered ddev project(s)"\
" are OUTSIDE the given roots — NOT exported:"
        printf '%s\n' "$dm_outside" | sed 's/^/    /'
    fi

    dm_stamp=$(date +%Y%m%d-%H%M%S)
    # Resume: an interrupted install (Ctrl-C mid-export, or the
    # failed-projects abort question) may have left a dump directory
    # behind. Re-use the newest one instead of starting a fresh wave:
    # already-exported projects are skipped, only missing/failed ones are
    # retried — and there is exactly ONE self-contained directory per
    # migration wave (import always reads the newest).
    DD_MIG_DUMP_DIR=$(ddev_migrate_latest_dir)
    if [ -n "$DD_MIG_DUMP_DIR" ] && [ -f "$DD_MIG_DUMP_DIR/manifest.conf" ]; then
        echo "  resuming dump directory: $DD_MIG_DUMP_DIR"
    else
        DD_MIG_DUMP_DIR="$DDEV_MIG_BACKUP_ROOT/ddev-migration-$dm_stamp"
    fi
    mkdir -p "$DD_MIG_DUMP_DIR" || return 1
    # dev writes the dumps, the opencode group (dev is a member) keeps
    # them group-readable; finalized below. Mode 3770 (0.0.44b W1):
    # setgid AND sticky — the sticky bit is the load-bearing half. In a
    # plain 2770 dir any group member (the AGENT — the wave's own threat
    # premise) could RENAME root's stage/manifest aside by parent write
    # alone and plant their own; with sticky, rename/unlink of an entry
    # is limited to the entry's owner (root for stage + published
    # manifest; dev keeps full reign over their own dumps). The dir
    # OWNER (dev) stays above sticky by POSIX — accepted: dev is the
    # cooperating principal, the agent is the contained one.
    chown "$dm_dev:$dm_ocg" "$DD_MIG_DUMP_DIR" 2>/dev/null || true
    chmod 3770 "$DD_MIG_DUMP_DIR" 2>/dev/null || true
    # Root-owned staging (0.0.44a V3, hardened 0.0.44b W1/W2): the dump
    # dir is agent-writable at group level for the whole (minutes-long)
    # export loop, so root must never open a path inside it for writing
    # OR reading (a planted symlink would be truncated/appended THROUGH;
    # reading one copies its target into the agent-readable manifest —
    # a disclosure, not merely content). Three layers:
    #   1. .root-stage (mkdir -m 700: no default-mode window) is a NAME
    #      the agent cannot take or replace — sticky (above) protects
    #      root-owned entries from group rename, and mkdir fails EEXIST
    #      on the taken name;
    #   2. the AUTHORITATIVE manifest lives at $DM_STAGE/manifest.auth —
    #      root reads/writes only there; the dump-dir manifest.conf is a
    #      published COPY (build-new + mv: rename replaces a planted
    #      link itself, never opens its target);
    #   3. the one-time seed reads the dump-dir manifest.conf only when
    #      it is not a symlink (a link there means tampering — abort
    #      loudly); after the first publish it is root-owned and sticky-
    #      protected, so the check cannot be raced by the agent.
    # The stage is removed before finalize so chown -R never hands it
    # to the agent.
    DM_STAGE="$DD_MIG_DUMP_DIR/.root-stage"
    rm -rf "$DM_STAGE" 2>/dev/null || true   # stale stage from an aborted run
    mkdir -m 700 "$DM_STAGE" || return 1
    # Seed (0.0.44b W2, hardened 0.0.44c C3): trust only a REGULAR file
    # owned by root or the dev — an agent-owned entry (regular or link)
    # is tampering: a forged OK|<project>| line makes the loop silently
    # skip real exports, and wave-a-era resume dirs were non-sticky for
    # the whole inter-run gap, so planting needs no race there.
    if [ -e "$DD_MIG_DUMP_DIR/manifest.conf" ]; then
        _seed_owner=$(stat -c %U "$DD_MIG_DUMP_DIR/manifest.conf" 2>/dev/null || true)
        if [ -L "$DD_MIG_DUMP_DIR/manifest.conf" ] \
           || { [ "$_seed_owner" != root ] && [ "$_seed_owner" != "$dm_dev" ]; }; then
            echo "  REFUSED: $DD_MIG_DUMP_DIR/manifest.conf is a symlink or not root/dev-owned — tampering?" >&2
            rm -rf "$DM_STAGE"
            return 1
        fi
        cat "$DD_MIG_DUMP_DIR/manifest.conf" > "$DM_STAGE/manifest.auth" 2>/dev/null || true
    fi
    [ -f "$DM_STAGE/manifest.auth" ] || : > "$DM_STAGE/manifest.auth"
    # _dm_manifest_add <line>: append to the AUTHORITATIVE copy inside
    # the root-only stage, then publish a fresh copy via atomic rename.
    _dm_manifest_add() {
        printf '%s\n' "$1" >> "$DM_STAGE/manifest.auth"
        _dma_pub="$DM_STAGE/manifest.$$"
        cat "$DM_STAGE/manifest.auth" > "$_dma_pub"
        mv -f "$_dma_pub" "$DD_MIG_DUMP_DIR/manifest.conf"
    }

    # NOTE on loop hygiene: this loop's stdin IS the project list (the
    # printf pipe), and ddev reads stdin (prompt/TUI probing) — without
    # the explicit </dev/null on every ddev invocation below, the first
    # ddev call consumed the remaining list and the loop silently ended
    # after ONE project per run (production finding: 12 databases, one
    # dump per export invocation, resume picked up the next each time).
    printf '%s\n' "$dm_list" | while IFS='|' read -r dm_n dm_ar; do
        echo "  exporting $dm_n ($dm_ar) ..."
        # Resume: intact dump + OK entry in THIS directory — skip the
        # start/export/stop cycle and keep the existing dump. Reads the
        # AUTHORITATIVE stage copy (0.0.44b W2), never the dump-dir file.
        # (Fixed-string match, 0.0.44a V23: a project name must never be
        # interpolated as a BRE/ERE — "sh.p" cross-matched "shop".)
        if [ -s "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" ] \
           && grep -qF "OK|$dm_n|" "$DM_STAGE/manifest.auth" 2>/dev/null; then
            echo "    already exported — skipping (resume)"
            continue
        fi
        # Drop stale entries for this project (a FAILED or SKIPped run is
        # being retried; the old line must not linger — the installer
        # counts FAIL entries and would re-ask the abort question).
        # Same authoritative-copy discipline (0.0.44b W2) and fixed
        # strings (V23): rewrite auth, publish via rename.
        grep -v -F -e "OK|$dm_n|" -e "FAIL|$dm_n|" -e "SKIP|$dm_n|" \
            "$DM_STAGE/manifest.auth" > "$DM_STAGE/manifest.next" || true
        mv -f "$DM_STAGE/manifest.next" "$DM_STAGE/manifest.auth"
        # publish the rewrite (same build-new + rename as _dm_manifest_add)
        _dma_pub="$DM_STAGE/manifest.$$"
        cat "$DM_STAGE/manifest.auth" > "$_dma_pub"
        mv -f "$_dma_pub" "$DD_MIG_DUMP_DIR/manifest.conf"
        # Already handed over? dev-side ddev cannot start it anymore.
        if [ -d "$dm_ar/.ddev" ] && [ "$(stat -c %U "$dm_ar/.ddev" 2>/dev/null)" = "$dm_oc" ]; then
            echo "    SKIP: .ddev already owned by '$dm_oc' (handover done) — dev-side export"
            echo "    is impossible; see docs/troubleshooting.md"
            _dm_manifest_add "SKIP|$dm_n|$dm_ar|handover-done"
            continue
        fi
        # Projects without a db container (omit_containers: [db]) have
        # nothing to export — ddev export-db would just fail.
        if ! ddev_migrate_has_db "$dm_ar" "$dm_home"; then
            echo "    SKIP: no db container (omit_containers)"
            _dm_manifest_add "SKIP|$dm_n|$dm_ar|no-db-container"
            continue
        fi
        if ! _ddev_migrate_run_as "$dm_dev" "$dm_bin" start "$dm_n" </dev/null >/dev/null 2>&1; then
            echo "    FAILED: ddev start — project left untouched, import this one manually"
            _dm_manifest_add "FAIL|$dm_n|$dm_ar|"
            continue
        fi
        # err file inside the root-owned stage (0.0.44a V3): the dump dir
        # itself is agent-writable — a planted .export-<name>.err link
        # there would be truncated THROUGH by this very redirect.
        dm_err="$DM_STAGE/export-$dm_n.err"
        if _ddev_migrate_run_as "$dm_dev" "$dm_bin" export-db "$dm_n" \
           --file="$DD_MIG_DUMP_DIR/$dm_n.sql.gz" </dev/null >"$dm_err" 2>&1 \
           && [ -s "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" ]; then
            echo "    dump: $DD_MIG_DUMP_DIR/$dm_n.sql.gz"
            _dm_manifest_add "OK|$dm_n|$dm_ar|$dm_n.sql.gz"
        elif grep -q "service db does not exist" "$dm_err" 2>/dev/null; then
            # Runtime twin of omit_containers: the db service never came up
            # (state=doesnotexist) — nothing to export, not a failure.
            rm -f "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" 2>/dev/null || true
            echo "    SKIP: no running db service in this project"
            _dm_manifest_add "SKIP|$dm_n|$dm_ar|no-db-service"
        else
            rm -f "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" 2>/dev/null || true
            echo "    FAILED: ddev export-db — no dump for $dm_n"
            _dm_manifest_add "FAIL|$dm_n|$dm_ar|"
        fi
        rm -f "$dm_err" 2>/dev/null || true
        # Stop this project before the next one starts: a production
        # machine may hold dozens of ddev projects — running them all at
        # once would exhaust RAM. Volumes are kept by plain `ddev stop`.
        _ddev_migrate_run_as "$dm_dev" "$dm_bin" stop "$dm_n" </dev/null >/dev/null 2>&1 \
            || echo "    NOTE: ddev stop failed — stop $dm_n manually to free its resources"
    done

    # One poweroff stops every project AND the old ddev-router: the ports
    # are free for the opencode-side router later. Containers are removed
    # but database volumes stay — nothing is destroyed.
    _ddev_migrate_run_as "$dm_dev" "$dm_bin" poweroff </dev/null >/dev/null 2>&1 \
        && echo "  old ddev powered off (database volumes kept)" \
        || echo "  NOTE: ddev poweroff failed — stop the old projects manually before the first opencode-side start"

    # Accounting reads the AUTHORITATIVE stage copy (0.0.44c C2): the old
    # finalize grep -c opened the dump-dir manifest AFTER chown -R handed
    # dir and file to the agent — a replaced FIFO there would hang root's
    # grep (and the installer) forever. The stage copy is root-only until
    # removed right below. The FAIL project list rides the same copy
    # (0.0.44d F1): the installer's abort question prints it — re-greping
    # the agent-owned manifest there was the sibling site C2's class
    # sweep missed.
    # grep -c always prints the count (0 on no match); || true keeps a
    # zero count from tripping set -e via the assignment's exit status.
    # Only a missing file yields an empty result, hence the :-0 defaults.
    DD_MIG_OK=$(grep -c '^OK|' "$DM_STAGE/manifest.auth" 2>/dev/null || true)
    DD_MIG_FAIL=$(grep -c '^FAIL|' "$DM_STAGE/manifest.auth" 2>/dev/null || true)
    DD_MIG_OK=${DD_MIG_OK:-0}
    DD_MIG_FAIL=${DD_MIG_FAIL:-0}
    DD_MIG_FAILLIST=$(grep '^FAIL|' "$DM_STAGE/manifest.auth" 2>/dev/null | cut -d'|' -f2 || true)

    # Finalize: opencode owns the dumps (the importing side), the sharing
    # group keeps the developer's read access. The root stage goes FIRST —
    # chown -R must never hand it to the agent (0.0.44a V3). The chmod
    # pass rides find ! -type l: the dump dir is agent-writable until this
    # very chmod 750, and plain `chmod 640 dumpdir/*.sql.gz` dereferences
    # a planted symlink operand (mode strip on an arbitrary path).
    rm -rf "$DM_STAGE" 2>/dev/null || true
    chown -R "$dm_oc:$dm_ocg" "$DD_MIG_DUMP_DIR" 2>/dev/null || true
    chmod 750 "$DD_MIG_DUMP_DIR" 2>/dev/null || true
    find "$DD_MIG_DUMP_DIR" -maxdepth 1 ! -type l -name '*.sql.gz' \
        -exec chmod 640 {} + 2>/dev/null || true
    find "$DD_MIG_DUMP_DIR" -maxdepth 1 ! -type l -name 'manifest.conf' \
        -exec chmod 640 {} + 2>/dev/null || true
    # The manifest stays ROOT-owned (0.0.44d F2): the chown -R above hands
    # the DUMPS to the agent (import reads them as the agent), but an
    # agent-owned manifest would be refused by the resume seed's owner
    # check (0.0.44c C3) — the documented fix-and-re-run path would
    # dead-end on the kit's own finalize output. root:<sharing-group>
    # 0640: sticky-protected name, group-readable for dev/import/status,
    # unwritable for the agent.
    chown "root:$dm_ocg" "$DD_MIG_DUMP_DIR/manifest.conf" 2>/dev/null || true
    [ "${DD_MIG_OK:-0}" -gt 0 ]
}

# ddev_migrate_latest_dir
# Newest ddev-migration-* dump directory (or empty).
ddev_migrate_latest_dir() {
    ls -1d "$DDEV_MIG_BACKUP_ROOT"/ddev-migration-* 2>/dev/null | sort | tail -1
}

# ddev_migrate_import [dump-dir]
# Root-only post-install convenience: imports every dump in the (newest)
# dump directory as the opencode user. `ddev start` per project
# registers it in the opencode registry and pulls images on first run.
ddev_migrate_import() {
    [ "$(id -u)" = 0 ] || { echo "ddev-migrate: import must run as root (sudo sh ddev-migrate.sh import)"; return 1; }
    dm_dir="${1:-$(ddev_migrate_latest_dir)}"
    [ -n "$dm_dir" ] && [ -f "$dm_dir/manifest.conf" ] || {
        echo "ddev-migrate: no dump directory with a manifest found under $DDEV_MIG_BACKUP_ROOT"
        return 1
    }

    dm_conf="/etc/opencode-permissions-kit/install.conf"
    dm_oc="opencode"; dm_be=""; dm_dh=""; dm_ps=""
    [ -f "$dm_conf" ] && . "$dm_conf"
    dm_oc="${OPENCODE_USER:-$dm_oc}"
    dm_be="${CONTAINER_BACKEND:-$dm_be}"
    dm_dh="${OPENCODE_DOCKER_HOST:-$dm_dh}"
    dm_ps="${OPENCODE_PODMAN_SOCKET:-$dm_ps}"
    id "$dm_oc" >/dev/null 2>&1 || { echo "ddev-migrate: user '$dm_oc' does not exist"; return 1; }
    dm_bin=$(_ddev_migrate_bin "$dm_oc") || { echo "ddev-migrate: ddev is not installed"; return 1; }

    # Home via getent, not /home/<user> (0.0.43a F12); every env assignment
    # is ONE quoted argument — a spaced HOME or DOCKER_HOST must not split
    # (0.0.43a F6). The conditional backend assignment rides
    # ${dm_extra:+"$dm_extra"} (empty when the backend needs none).
    dm_oc_h=$(getent passwd "$dm_oc" 2>/dev/null | cut -d: -f6 || true)
    [ -n "$dm_oc_h" ] || dm_oc_h="/home/$dm_oc"
    dm_oc_i=$(id -u "$dm_oc")
    dm_extra=""
    case "$dm_be" in
        docker-rootless) [ -n "$dm_dh" ] && dm_extra="DOCKER_HOST=$dm_dh" ;;
        podman-rootless) [ -n "$dm_ps" ] && dm_extra="DOCKER_HOST=$dm_ps" ;;
    esac

    dm_ok=0; dm_failed=""
    while IFS='|' read -r dm_st dm_n dm_ar dm_f; do
        [ "$dm_st" = "OK" ] && [ -n "$dm_n" ] && [ -n "$dm_ar" ] && [ -n "$dm_f" ] || continue
        [ -f "$dm_dir/$dm_f" ] \
           || { echo "  $dm_n: dump missing ($dm_dir/$dm_f)"; dm_failed="$dm_failed $dm_n"; continue; }
        echo "  importing $dm_n ($dm_ar) ..."
        # </dev/null: this loop's stdin IS manifest.conf — ddev reads
        # stdin and would consume the manifest mid-iteration (same class
        # as the export-loop finding).
        if sudo -u "$dm_oc" env "HOME=$dm_oc_h" "XDG_RUNTIME_DIR=/run/user/$dm_oc_i" \
               ${dm_extra:+"$dm_extra"} "$dm_bin" start "$dm_n" </dev/null >/dev/null 2>&1 \
           && sudo -u "$dm_oc" env "HOME=$dm_oc_h" "XDG_RUNTIME_DIR=/run/user/$dm_oc_i" \
               ${dm_extra:+"$dm_extra"} "$dm_bin" import-db "$dm_n" --file="$dm_dir/$dm_f" \
              </dev/null >/dev/null 2>&1; then
            echo "    imported: $dm_f"
            dm_ok=$((dm_ok + 1))
        else
            echo "    FAILED — import manually: ddev start $dm_n && ddev import-db $dm_n --file=$dm_dir/$dm_f"
            dm_failed="$dm_failed $dm_n"
        fi
    done < "$dm_dir/manifest.conf"

    echo ""
    echo "  imported $dm_ok database(s) from $dm_dir"
    [ -n "$dm_failed" ] && echo "  failed:$dm_failed — dumps stay in $dm_dir (retry anytime)"
    echo "  old containers/volumes remain in the dev daemon; remove them with:"
    echo "    sudo -u <dev-user> $dm_bin delete --omit-snapshot <project>"
    [ -z "$dm_failed" ]
}

# --- usage (printed by bin/ddev-migrate, the CLI dispatcher) ---------------------

_ddev_migrate_usage() {
    echo "Usage: ddev-migrate <command> [args]"
    echo "  export <dev-user> <project-root> [root ...]   export ddev databases as <dev-user> (root)"
    echo "  import [dump-dir]                              import dumps as the opencode user (root)"
    echo "  list                                           show dump directories + contents"
    echo "  registry <dev-user> [root ...]                 print the dev user's ddev registry; with"
    echo "                                                 roots: which projects an export would"
    echo "                                                 take and which fall outside (read-only)"
}
