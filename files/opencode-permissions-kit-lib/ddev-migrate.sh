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
# Sourced (install.sh calls the ddev_migrate_* functions) AND executable
# standalone via `sh ddev-migrate.sh <mode>`. No ui.sh dependency —
# plain output, callers wrap with their own UI/log calls as needed.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/ddev-migrate.sh.

DDEV_MIG_BACKUP_ROOT="${DDEV_MIG_BACKUP_ROOT:-/var/backups/opencode-permissions-kit}"

# ddev_migrate_registry <ddev-home>
# Prints "name|approot" for every project in ddev's global registry
# (global_config.yaml). No ddev binary, no jq — pure awk over the YAML
# subset ddev actually writes:
#   project_info:
#     <name>:
#       approot: /path/to/project
ddev_migrate_registry() {
    dm_gc="${1:-}/global_config.yaml"
    [ -f "$dm_gc" ] || return 0
    awk '
        /^project_info:/ { inb = 1; next }
        inb && /^[^ \t#]/ { inb = 0 }
        inb {
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
    ' "$dm_gc"
    return 0
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
        dm_ar="${dm_ar%/}"
        for dm_r in "$@"; do
            dm_r="${dm_r%/}"
            case "$dm_ar" in
                "$dm_r"|"$dm_r"/*)
                    printf '%s|%s\n' "$dm_n" "$dm_ar"
                    break
                    ;;
            esac
        done
    done
    return 0
}

# ddev_migrate_done <opencode-user>
# True (0) when the opencode user already has registered ddev projects —
# the switch already happened, an export would find a broken dev side.
ddev_migrate_done() {
    dm_ocgc="/home/${1:-opencode}/.ddev/global_config.yaml"
    [ -f "$dm_ocgc" ] && grep -q '^project_info:' "$dm_ocgc" 2>/dev/null
}

# _ddev_migrate_run_as <user> <cmd...>
# Runs cmd as <user> with HOME/XDG_RUNTIME_DIR set (sudo's env_reset
# drops them; ddev needs HOME for its registry and XDG_RUNTIME_DIR for
# a rootless socket). Callers are root (install.sh / sudo standalone).
_ddev_migrate_run_as() {
    dm_u="$1"; shift
    dm_h=$(getent passwd "$dm_u" 2>/dev/null | cut -d: -f6)
    [ -n "$dm_h" ] || return 1
    dm_i=$(id -u "$dm_u" 2>/dev/null)
    dm_env="HOME=$dm_h"
    [ -n "$dm_i" ] && [ -d "/run/user/$dm_i" ] && dm_env="$dm_env XDG_RUNTIME_DIR=/run/user/$dm_i"
    # shellcheck disable=SC2086  # word splitting intended (env assignments)
    sudo -u "$dm_u" env $dm_env "$@"
}

# _ddev_migrate_bin [user]
# Resolves the real ddev binary: root's PATH, the standard locations,
# then (when <user> is given) that user's private install paths — ddev's
# installer offers a per-user install, and `sudo -u` does not inherit it.
_ddev_migrate_bin() {
    dmb_u="${1:-}"
    dmb_extra=""
    if [ -n "$dmb_u" ]; then
        dmb_h=$(getent passwd "$dmb_u" 2>/dev/null | cut -d: -f6)
        [ -n "$dmb_h" ] && dmb_extra="$dmb_h/.local/bin/ddev $dmb_h/bin/ddev $dmb_h/.ddev/bin/ddev"
    fi
    for dm_c in "$(command -v ddev 2>/dev/null || true)" /usr/local/bin/ddev /usr/bin/ddev $dmb_extra; do
        [ -n "$dm_c" ] && [ -x "$dm_c" ] && { echo "$dm_c"; return 0; }
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
    # The dev user's ddev home: real passwd entry (homes do not have to be
    # under /home), DDEV_MIG_DEV_HOME as an override (keeps the unit
    # tests hermetic — never read a real user's registry there).
    dm_home=$(getent passwd "$dm_dev" 2>/dev/null | cut -d: -f6)
    [ -n "$dm_home" ] || dm_home="/home/$dm_dev"
    dm_home="${DDEV_MIG_DEV_HOME:-$dm_home}"
    dm_list=$(ddev_migrate_projects "$dm_home/.ddev" "$@")
    [ -n "$dm_list" ] || { echo "  no ddev projects under the registered roots."; return 1; }

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
    # them group-readable; finalized below.
    chown "$dm_dev:$dm_ocg" "$DD_MIG_DUMP_DIR" 2>/dev/null || true
    chmod 2770 "$DD_MIG_DUMP_DIR" 2>/dev/null || true

    printf '%s\n' "$dm_list" | while IFS='|' read -r dm_n dm_ar; do
        echo "  exporting $dm_n ($dm_ar) ..."
        # Resume: intact dump + OK entry in THIS directory — skip the
        # start/export/stop cycle and keep the existing dump.
        if [ -s "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" ] && grep -q "^OK|$dm_n|" "$DD_MIG_DUMP_DIR/manifest.conf" 2>/dev/null; then
            echo "    already exported — skipping (resume)"
            continue
        fi
        # Drop stale entries for this project (a FAILED or SKIPped run is
        # being retried; the old line must not linger — the installer
        # counts FAIL entries and would re-ask the abort question).
        if [ -f "$DD_MIG_DUMP_DIR/manifest.conf" ]; then
            grep -vE "^(OK|FAIL|SKIP)\|$dm_n\|" "$DD_MIG_DUMP_DIR/manifest.conf" > "$DD_MIG_DUMP_DIR/manifest.conf.tmp" || true
            mv "$DD_MIG_DUMP_DIR/manifest.conf.tmp" "$DD_MIG_DUMP_DIR/manifest.conf"
        fi
        # Already handed over? dev-side ddev cannot start it anymore.
        if [ -d "$dm_ar/.ddev" ] && [ "$(stat -c %U "$dm_ar/.ddev" 2>/dev/null)" = "$dm_oc" ]; then
            echo "    SKIP: .ddev already owned by '$dm_oc' (handover done) — dev-side export"
            echo "    is impossible; see docs/troubleshooting.md"
            echo "SKIP|$dm_n|$dm_ar|handover-done" >> "$DD_MIG_DUMP_DIR/manifest.conf"
            continue
        fi
        # Projects without a db container (omit_containers: [db]) have
        # nothing to export — ddev export-db would just fail.
        if ! ddev_migrate_has_db "$dm_ar" "$dm_home"; then
            echo "    SKIP: no db container (omit_containers)"
            echo "SKIP|$dm_n|$dm_ar|no-db-container" >> "$DD_MIG_DUMP_DIR/manifest.conf"
            continue
        fi
        if ! _ddev_migrate_run_as "$dm_dev" "$dm_bin" start "$dm_n" >/dev/null 2>&1; then
            echo "    FAILED: ddev start — project left untouched, import this one manually"
            echo "FAIL|$dm_n|$dm_ar|" >> "$DD_MIG_DUMP_DIR/manifest.conf"
            continue
        fi
        dm_err="$DD_MIG_DUMP_DIR/.export-$dm_n.err"
        if _ddev_migrate_run_as "$dm_dev" "$dm_bin" export-db "$dm_n" --file="$DD_MIG_DUMP_DIR/$dm_n.sql.gz" >"$dm_err" 2>&1 \
           && [ -s "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" ]; then
            echo "    dump: $DD_MIG_DUMP_DIR/$dm_n.sql.gz"
            echo "OK|$dm_n|$dm_ar|$dm_n.sql.gz" >> "$DD_MIG_DUMP_DIR/manifest.conf"
        elif grep -q "service db does not exist" "$dm_err" 2>/dev/null; then
            # Runtime twin of omit_containers: the db service never came up
            # (state=doesnotexist) — nothing to export, not a failure.
            rm -f "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" 2>/dev/null || true
            echo "    SKIP: no running db service in this project"
            echo "SKIP|$dm_n|$dm_ar|no-db-service" >> "$DD_MIG_DUMP_DIR/manifest.conf"
        else
            rm -f "$DD_MIG_DUMP_DIR/$dm_n.sql.gz" 2>/dev/null || true
            echo "    FAILED: ddev export-db — no dump for $dm_n"
            echo "FAIL|$dm_n|$dm_ar|" >> "$DD_MIG_DUMP_DIR/manifest.conf"
        fi
        rm -f "$dm_err" 2>/dev/null || true
        # Stop this project before the next one starts: a production
        # machine may hold dozens of ddev projects — running them all at
        # once would exhaust RAM. Volumes are kept by plain `ddev stop`.
        _ddev_migrate_run_as "$dm_dev" "$dm_bin" stop "$dm_n" >/dev/null 2>&1 \
            || echo "    NOTE: ddev stop failed — stop $dm_n manually to free its resources"
    done

    # One poweroff stops every project AND the old ddev-router: the ports
    # are free for the opencode-side router later. Containers are removed
    # but database volumes stay — nothing is destroyed.
    _ddev_migrate_run_as "$dm_dev" "$dm_bin" poweroff >/dev/null 2>&1 \
        && echo "  old ddev powered off (database volumes kept)" \
        || echo "  NOTE: ddev poweroff failed — stop the old projects manually before the first opencode-side start"

    # Finalize: opencode owns the dumps (the importing side), the sharing
    # group keeps the developer's read access.
    chown -R "$dm_oc:$dm_ocg" "$DD_MIG_DUMP_DIR" 2>/dev/null || true
    chmod 750 "$DD_MIG_DUMP_DIR" 2>/dev/null || true
    chmod 640 "$DD_MIG_DUMP_DIR"/*.sql.gz 2>/dev/null || true
    chmod 640 "$DD_MIG_DUMP_DIR/manifest.conf" 2>/dev/null || true

    # grep -c always prints the count (0 on no match); || true keeps a
    # zero count from tripping set -e via the assignment's exit status.
    # Only a missing file yields an empty result, hence the :-0 defaults.
    DD_MIG_OK=$(grep -c '^OK|' "$DD_MIG_DUMP_DIR/manifest.conf" 2>/dev/null || true)
    DD_MIG_FAIL=$(grep -c '^FAIL|' "$DD_MIG_DUMP_DIR/manifest.conf" 2>/dev/null || true)
    DD_MIG_OK=${DD_MIG_OK:-0}
    DD_MIG_FAIL=${DD_MIG_FAIL:-0}
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

    dm_env="HOME=/home/$dm_oc XDG_RUNTIME_DIR=/run/user/$(id -u "$dm_oc")"
    case "$dm_be" in
        docker-rootless) [ -n "$dm_dh" ] && dm_env="$dm_env DOCKER_HOST=$dm_dh" ;;
        podman-rootless) [ -n "$dm_ps" ] && dm_env="$dm_env DOCKER_HOST=$dm_ps" ;;
    esac

    dm_ok=0; dm_failed=""
    while IFS='|' read -r dm_st dm_n dm_ar dm_f; do
        [ "$dm_st" = "OK" ] && [ -n "$dm_n" ] && [ -n "$dm_ar" ] && [ -n "$dm_f" ] || continue
        [ -f "$dm_dir/$dm_f" ] || { echo "  $dm_n: dump missing ($dm_dir/$dm_f)"; dm_failed="$dm_failed $dm_n"; continue; }
        echo "  importing $dm_n ($dm_ar) ..."
        # shellcheck disable=SC2086  # word splitting intended (env assignments)
        if sudo -u "$dm_oc" env $dm_env "$dm_bin" start "$dm_n" >/dev/null 2>&1 \
           && sudo -u "$dm_oc" env $dm_env "$dm_bin" import-db "$dm_n" --file="$dm_dir/$dm_f" >/dev/null 2>&1; then
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

# --- standalone entry (sourced callers never trigger this) ----------------------

_ddev_migrate_usage() {
    echo "Usage: sh ddev-migrate.sh <command> [args]"
    echo "  export <dev-user> <project-root> [root ...]   export ddev databases as <dev-user> (root)"
    echo "  import [dump-dir]                              import dumps as the opencode user (root)"
    echo "  list                                           show dump directories + contents"
}

case "${0##*/}" in
    ddev-migrate.sh)
        case "${1:-}" in
            list)
                dm_found=0
                for dm_d in "$DDEV_MIG_BACKUP_ROOT"/ddev-migration-*; do
                    [ -d "$dm_d" ] || continue
                    dm_found=1
                    echo "$dm_d:"
                    ls -1 "$dm_d" 2>/dev/null | sed 's/^/    /'
                done
                [ "$dm_found" = 0 ] && echo "no dump directories under $DDEV_MIG_BACKUP_ROOT"
                ;;
            export)
                [ "$(id -u)" = 0 ] || { echo "ddev-migrate: export must run as root"; exit 1; }
                [ $# -ge 3 ] || { _ddev_migrate_usage; exit 1; }
                dm_ocg=$(id -gn opencode 2>/dev/null || echo opencode)
                dm_dev="$2"; shift 2
                ddev_migrate_export "$dm_dev" opencode "$dm_ocg" "$@"
                exit $?
                ;;
            import)
                ddev_migrate_import "${2:-}"
                exit $?
                ;;
            *)
                _ddev_migrate_usage
                [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || exit 1
                ;;
        esac
        ;;
esac
