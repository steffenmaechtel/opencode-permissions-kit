#!/bin/sh
# opencode permissions kit — migrate-denies.sh
# One-time migration from the hard-ACL model to the soft-only model
# (docs/design/DDEV-WORKING.md §4). Called by update.sh (as root); usable
# standalone against fixture trees — every path is parameterized.
#
# What it does:
#   1. REFUSES a legacy CONTAINER_BACKEND=docker-group install (exit 3) —
#      the admin must re-run install.sh with a rootless backend instead of
#      silently downgrading security.
#   2. Removes every hard deny entry (u:<opencode-user>:---) from all
#      registered project roots (getfacl | awk | setfacl -x) so ddev (and
#      its containers) can read settings.php & friends again.
#   3. Re-bases the sharing group on every root: chgrp -R <group>, setgid,
#      default group ACLs (g:<group>:rwx).
#   4. Removes pre-DDEV-WORKING artifacts: hooks dir, protect-projects.sh,
#      ddev-transaction.sh, ddev shim, rewrite list, /run transaction dir,
#      the sbin protect-projects symlink.
#
# Usage:
#   migrate-denies.sh --projects <projects.conf> --conf-dir <dir> --lib-dir <dir> \
#                     [--opencode-user <u>] [--group <g>] [--run-dir <dir>]
#
# Exit codes: 0 success (idempotent), 3 docker-group refusal, 1 usage error.
set -u

# === Audit log (best-effort) ===
log() { :; }
if [ -f "$(dirname "$0")/log.sh" ]; then
    . "$(dirname "$0")/log.sh"
fi

OPENCODE_USER="opencode"
GROUP=""
PROJECTS_FILE=""
CONF_DIR=""
LIB_DIR=""
RUN_DIR="/run/opencode-permissions-kit"

while [ $# -gt 0 ]; do
    case "$1" in
        --projects)       PROJECTS_FILE="$2"; shift 2 ;;
        --conf-dir)       CONF_DIR="$2"; shift 2 ;;
        --lib-dir)        LIB_DIR="$2"; shift 2 ;;
        --run-dir)        RUN_DIR="$2"; shift 2 ;;
        --opencode-user)  OPENCODE_USER="$2"; shift 2 ;;
        --group)          GROUP="$2"; shift 2 ;;
        *) echo "migrate-denies: unknown arg '$1'" >&2; exit 1 ;;
    esac
done

[ -n "$PROJECTS_FILE" ] || { echo "migrate-denies: --projects is required" >&2; exit 1; }
[ -n "$CONF_DIR" ] || { echo "migrate-denies: --conf-dir is required" >&2; exit 1; }
[ -n "$LIB_DIR" ] || { echo "migrate-denies: --lib-dir is required" >&2; exit 1; }
[ -n "$GROUP" ] || GROUP="$OPENCODE_USER"

# --- 1. backend gate: docker-group installs must re-install -----------------
INSTALL_CONF="$CONF_DIR/install.conf"
if [ -f "$INSTALL_CONF" ]; then
    _be=$(sed -n 's/^CONTAINER_BACKEND=//p' "$INSTALL_CONF" 2>/dev/null | tail -1)
    case "$_be" in
        docker-group)
            echo "migrate-denies: REFUSED — this install uses the removed docker-group backend (root-equivalent)." >&2
            echo "  Re-run install.sh with a rootless backend instead:" >&2
            echo "    sudo bash files/install.sh --container-backend docker-rootless" >&2
            echo "    sudo bash files/install.sh --container-backend podman-rootless" >&2
            log "migration REFUSED: legacy docker-group backend"
            exit 3
            ;;
    esac
fi

# --- 2. remove hard deny entries from every root -----------------------------
command -v getfacl >/dev/null 2>&1 || { echo "migrate-denies: getfacl not available" >&2; exit 1; }
command -v setfacl >/dev/null 2>&1 || { echo "migrate-denies: setfacl not available" >&2; exit 1; }

deny_count=0
if [ -f "$PROJECTS_FILE" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ -d "$root" ] || continue
        stale=$(getfacl -R -p "$root" 2>/dev/null | awk -v u="$OPENCODE_USER" '
            /^# file: / { path = substr($0, 9); has = 0; next }
            index($0, "user:" u ":") == 1 { has = 1; next }
            /^user:/ { next }
            /^$/ { if (path != "" && has) print path; path = ""; has = 0 }
        ')
        if [ -n "$stale" ]; then
            n=$(printf '%s\n' "$stale" | wc -l)
            printf '%s\n' "$stale" | xargs -d '\n' setfacl -x "u:$OPENCODE_USER" 2>/dev/null || true
            deny_count=$((deny_count + n))
        fi
    done < "$PROJECTS_FILE"
fi
echo "  removed hard deny entries (u:$OPENCODE_USER) on $deny_count file(s)"
log "hard-deny migration: removed u:$OPENCODE_USER denies on $deny_count file(s)"

# --- 3. re-base the sharing group on every root ------------------------------
if getent group "$GROUP" >/dev/null 2>&1; then
    if [ -f "$PROJECTS_FILE" ]; then
        while IFS= read -r root; do
            [ -z "$root" ] && continue
            [ -d "$root" ] || continue
            chgrp -R "$GROUP" "$root" 2>/dev/null || true
            chmod g+s "$root" 2>/dev/null || true
            setfacl -R -d -m "g:$GROUP:rwx" "$root" 2>/dev/null || true
            # .ddev handover: ddev always runs as the opencode user, so an
            # existing .ddev must belong to them (otherwise `ddev start` fails
            # with "chmod .ddev/.webimageBuild: operation not permitted").
            if [ -d "$root/.ddev" ]; then
                chown -R "$OPENCODE_USER:$GROUP" "$root/.ddev" 2>/dev/null || true
                chmod -R g+w "$root/.ddev" 2>/dev/null || true
            fi
        done < "$PROJECTS_FILE"
    fi
    echo "  sharing group re-based to '$GROUP' (chgrp + setgid + default ACLs)"
    log "hard-deny migration: sharing group re-based to $GROUP"
else
    echo "  WARNING: group '$GROUP' does not exist — skipped group re-base" >&2
fi

# --- 4. remove pre-DDEV-WORKING artifacts -------------------------------------
rm -rf "$LIB_DIR/hooks" 2>/dev/null || true
rm -f "$LIB_DIR/protect-projects.sh" "$LIB_DIR/ddev-transaction.sh" "$LIB_DIR/bin/ddev" 2>/dev/null || true
rm -f "$CONF_DIR/ddev-rewrites.conf" 2>/dev/null || true
rm -rf "$RUN_DIR" 2>/dev/null || true
rm -f /usr/local/sbin/protect-projects.sh 2>/dev/null || true
echo "  removed legacy artifacts (hooks, protect-projects, ddev shim, transaction helper, rewrite list)"
log "hard-deny migration: legacy artifacts removed"

echo "migrate-denies: done"
exit 0
