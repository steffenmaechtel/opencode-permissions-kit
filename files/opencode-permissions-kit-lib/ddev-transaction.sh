#!/bin/sh
# opencode permissions kit -- ddev-transaction.sh
#
# Root helper for SANDBOX ddev mode (docs/PLAN-DDEV-SANDBOX.md, PROOF-3 H3).
# Wraps a mutating ddev invocation in an OPEN -> RUN -> CLOSE transaction so
# ddev runs as the 'opencode' sandbox user (under the kit's ACL denies)
# instead of being delegated to the developer:
#
#   OPEN   chown .ddev trees to opencode, grant u:opencode access on the
#          admin-declared rewrite list (/etc/opencode-permissions-kit/
#          ddev-rewrites.conf — ROOT-OWNED, never writable by the agent)
#   RUN    runuser -u opencode ddev <subcommand> (clean env, rootless socket)
#   CLOSE  restore ACLs, chown .ddev back to the developer, re-run
#          protect-projects.sh --force (runs via EXIT trap on every path)
#
# Called by the ddev shim as:
#   sudo ddev-transaction.sh <project-root> <ddev-subcommand> [args...]
# The sudoers rule is only rendered in DDEV_MODE=sandbox. Every input that
# influences file operations is validated; nothing is ever eval'd (the
# PROOF-3 C1 lesson).

LIBDIR="/usr/local/lib/opencode-permissions-kit"
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
[ -f "$PROJECTS_CONF" ] || PROJECTS_CONF="/etc/opencode/projects.conf"
REWRITES_CONF="/etc/opencode-permissions-kit/ddev-rewrites.conf"
STAMP_DIR="/run/opencode-permissions-kit/ddev-txn"

OPENCODE_USER="opencode"
WWW_GROUP="www-data"
DEFAULT_USER=""
DDEV_MODE=""
DDEV_BIN=""
CONTAINER_BACKEND=""
OPENCODE_DOCKER_HOST=""
OPENCODE_PODMAN_SOCKET=""
[ -f "$INSTALL_CONF" ] && . "$INSTALL_CONF"
DDEV_BIN="${DDEV_BIN:-/usr/bin/ddev}"

log() { :; }
[ -f "$LIBDIR/log.sh" ] && . "$LIBDIR/log.sh"

die() {
    echo "ddev-transaction: $*" >&2
    log "ddev-transaction REFUSED: $*"
    exit 1
}

# --- input validation --------------------------------------------------------

[ $# -ge 2 ] || die "usage: ddev-transaction.sh <project-root> <ddev-subcommand> [args...]"

ROOT="${1%/}"
SUB="$2"
shift 2

[ "$DDEV_MODE" = "sandbox" ] || die "DDEV_MODE is not 'sandbox' — refusing"
[ -x "$DDEV_BIN" ] || die "ddev binary not executable: $DDEV_BIN"
command -v runuser >/dev/null 2>&1 || die "runuser not available"
command -v setfacl >/dev/null 2>&1 || die "setfacl not available"

# Root must be an EXACT entry of projects.conf (no globbing, no traversal).
case "$ROOT" in
    ""|"/"|*[!A-Za-z0-9._/-]*) die "invalid project root: '$ROOT'" ;;
esac
[ -d "$ROOT" ] || die "project root is not a directory: $ROOT"
grep -qx -- "$ROOT" "$PROJECTS_CONF" 2>/dev/null || die "project root not registered in projects.conf: $ROOT"

# Subcommand must be on the fixed mutating list; arguments are passed as argv
# only (never evaluated by a shell).
case "$SUB" in
    start|restart|stop|pause|poweroff|config|pull|push|snapshot|restore-snapshot|\
    import-db|export-db|import-files|delete|delete-images|share|debug|mutagen|\
    auth|clean) ;;
    *[!a-z0-9-]*|"") die "invalid ddev subcommand: '$SUB'" ;;
    *) die "subcommand '$SUB' is not on the mutating list (read-only subcommands do not need a transaction)" ;;
esac

[ -n "$DEFAULT_USER" ] || die "DEFAULT_USER missing from install.conf"

# --- load + validate the rewrite list (root-owned file, strict charset) ------

rewrites_loaded=""
rewrites=""
if [ -f "$REWRITES_CONF" ]; then
    while IFS= read -r entry; do
        case "$entry" in ""|\#*) continue ;; esac
        case "$entry" in
            /*|*/../*|../*|*/..) die "rewrite entry must be relative: '$entry'" ;;
            *[!A-Za-z0-9._/*-]*) die "rewrite entry has forbidden characters: '$entry'" ;;
        esac
        rewrites="$rewrites$entry
"
    done < "$REWRITES_CONF"
    rewrites_loaded=1
fi

# --- state stamp + lock ------------------------------------------------------

STAMP_NAME=$(printf '%s' "$ROOT" | tr -c 'A-Za-z0-9' '_')
STAMP="$STAMP_DIR/$STAMP_NAME.open"
mkdir -p "$STAMP_DIR" 2>/dev/null || die "cannot create $STAMP_DIR"
chmod 755 "$STAMP_DIR" 2>/dev/null || true

if command -v flock >/dev/null 2>&1; then
    exec 9>"$STAMP.lock"
    flock -n 9 || die "another ddev transaction is already running for $ROOT"
fi

# --- CLOSE: restore protections (idempotent, every exit path) ----------------

stamp_root_open() { [ -e "$STAMP" ]; }

close_transaction() {
    # 1. Remove the u:opencode grants from the rewrite-list matches. Deny
    #    patterns (settings.php etc.) get their u:opencode:--- re-asserted by
    #    protect-projects right after.
    if [ "$rewrites_loaded" = 1 ]; then
        printf '%s' "$rewrites" | while IFS= read -r entry; do
            [ -z "$entry" ] && continue
            find "$ROOT" -maxdepth 8 -path "$ROOT/$entry" -exec setfacl -x "u:$OPENCODE_USER" {} + 2>/dev/null
        done
    fi
    # 2. Hand the .ddev trees back to the developer (group kept for the kit).
    find "$ROOT" -maxdepth 8 -type d -name .ddev -exec chown -R "$DEFAULT_USER:$WWW_GROUP" {} + 2>/dev/null
    # 3. Remove the stamp, then re-assert the full protection state.
    rm -f "$STAMP" 2>/dev/null
    if [ -x "$LIBDIR/protect-projects.sh" ]; then
        "$LIBDIR/protect-projects.sh" --force --cwd "$ROOT" >/dev/null 2>&1
    fi
    log "ddev transaction CLOSED for $ROOT (subcommand=$SUB)"
}

trap 'rc=$?; close_transaction; exit $rc' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- OPEN: grant ddev the (temporary) access it needs ------------------------

oc_uid=$(id -u "$OPENCODE_USER" 2>/dev/null) || die "user $OPENCODE_USER does not exist"

find "$ROOT" -maxdepth 8 -type d -name .ddev -exec chown -R "$OPENCODE_USER:$WWW_GROUP" {} + 2>/dev/null
log "ddev transaction OPEN (chown .ddev -> $OPENCODE_USER) for $ROOT"

if [ "$rewrites_loaded" = 1 ]; then
    printf '%s' "$rewrites" | while IFS= read -r entry; do
        [ -z "$entry" ] && continue
        # Directories get rwx (ddev creates/replaces files inside); files rw.
        find "$ROOT" -maxdepth 8 -path "$ROOT/$entry" -type d -exec setfacl -m "u:$OPENCODE_USER:rwx" {} + 2>/dev/null
        find "$ROOT" -maxdepth 8 -path "$ROOT/$entry" -type f -exec setfacl -m "u:$OPENCODE_USER:rw-" {} + 2>/dev/null
    done
    log "ddev transaction OPEN (rewrite-list ACLs granted) for $ROOT"
fi

printf '%s\n' "$ROOT" > "$STAMP" 2>/dev/null || true
chmod 644 "$STAMP" 2>/dev/null || true

# --- RUN: ddev as the sandbox user, fully controlled environment -------------

XDG="/run/user/$oc_uid"
case "$CONTAINER_BACKEND" in
    docker-rootless)
        DH="${OPENCODE_DOCKER_HOST:-unix://$XDG/docker.sock}"
        ;;
    podman-rootless)
        DH="$OPENCODE_PODMAN_SOCKET"
        ;;
    *)
        DH=""
        ;;
esac

log "ddev transaction RUN (subcommand=$SUB) for $ROOT as $OPENCODE_USER"

if [ -n "$DH" ]; then
    runuser -u "$OPENCODE_USER" -- env -i \
        HOME="/home/$OPENCODE_USER" USER="$OPENCODE_USER" LOGNAME="$OPENCODE_USER" \
        PATH="/usr/local/bin:/usr/bin:/bin" TMPDIR="/tmp" \
        TERM="${TERM:-dumb}" XDG_RUNTIME_DIR="$XDG" DOCKER_HOST="$DH" \
        "$DDEV_BIN" "$SUB" "$@"
else
    runuser -u "$OPENCODE_USER" -- env -i \
        HOME="/home/$OPENCODE_USER" USER="$OPENCODE_USER" LOGNAME="$OPENCODE_USER" \
        PATH="/usr/local/bin:/usr/bin:/bin" TMPDIR="/tmp" \
        TERM="${TERM:-dumb}" XDG_RUNTIME_DIR="$XDG" \
        "$DDEV_BIN" "$SUB" "$@"
fi
run_rc=$?

# CLOSE runs via the EXIT trap; propagate ddev's exit code.
exit $run_rc
