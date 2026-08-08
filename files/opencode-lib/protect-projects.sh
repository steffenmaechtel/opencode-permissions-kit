#!/bin/sh
# opencode permissions kit — protect-projects.sh
# Applies hard Linux ACL denies (u:opencode:---) to sensitive files
# defined in /home/opencode/.config/opencode/opencode.json[c].
# Also scans each project root for <root>/opencode.json[c] and applies
# additional project-scoped denies (PLAN-STEP-2: cumulative, never weaker).
#
# Scope: ONLY within directories listed in /etc/opencode/projects.conf.
#         Never touches system paths (/, /etc, /boot, /usr, /root).
# Runs as root via sudo (idempotent, safe to call repeatedly).
set -e

FORCE=false
case "${1:-}" in
    --force) FORCE=true ;;
esac

PROJECTS_CONF="/etc/opencode/projects.conf"
SETUP_CONF="/etc/opencode/setup.conf"
CONFIG_DIR="/home/opencode/.config/opencode"
PARSER="/usr/local/lib/opencode/jsonc-parser.py"
CACHE_FILE="/usr/local/lib/opencode/.cache"

OPENCODE_USER="opencode"
WWW_GROUP="www-data"

TMP_PATTERNS=""
cleanup() { rm -f "$TMP_PATTERNS"; }
trap cleanup EXIT

# Read DEFAULT_USER from setup.conf
DEFAULT_USER=""
if [ -f "$SETUP_CONF" ]; then
    DEFAULT_USER=$(grep '^DEFAULT_USER=' "$SETUP_CONF" 2>/dev/null | cut -d= -f2)
fi
if [ -z "$DEFAULT_USER" ]; then
    echo "protect-projects: DEFAULT_USER not found in $SETUP_CONF — skipping chown step" >&2
fi

# Find active global config file (.jsonc or .json)
CONFIG_FILE=""
if [ -f "$CONFIG_DIR/opencode.jsonc" ]; then
    CONFIG_FILE="$CONFIG_DIR/opencode.jsonc"
elif [ -f "$CONFIG_DIR/opencode.json" ]; then
    CONFIG_FILE="$CONFIG_DIR/opencode.json"
else
    echo "protect-projects: No global opencode config — nothing to protect" >&2
    exit 0
fi

# Extract global deny patterns
GLOBAL_PATTERNS=$($PARSER "$CONFIG_FILE" 2>/dev/null || true)

# Read project roots (needed early for cache + project config scan)
if [ ! -f "$PROJECTS_CONF" ]; then
    echo "protect-projects: $PROJECTS_CONF not found — nothing to protect" >&2
    exit 0
fi

# Compute mtimes for cache (global config + projects.conf + all project configs)
CONFIG_MTIME=$(stat -c '%Y' "$CONFIG_FILE" 2>/dev/null || echo "0")
PROJECTS_MTIME=$(stat -c '%Y' "$PROJECTS_CONF" 2>/dev/null || echo "0")
PROJECT_CONFIGS_MTIME=0
while IFS= read -r root; do
    [ -z "$root" ] && continue
    [ ! -d "$root" ] && continue
    for ext in jsonc json; do
        pf="$root/opencode.$ext"
        if [ -f "$pf" ]; then
            pmtime=$(stat -c '%Y' "$pf" 2>/dev/null || echo "0")
            PROJECT_CONFIGS_MTIME=$((PROJECT_CONFIGS_MTIME + pmtime))
        fi
    done
done < "$PROJECTS_CONF"

# === Cache: skip full scan if nothing changed and not forced ===
if [ "$FORCE" != true ] && [ -f "$CACHE_FILE" ]; then
    CACHED_CONFIG=$(grep '^config_mtime=' "$CACHE_FILE" 2>/dev/null | cut -d= -f2)
    CACHED_PROJECTS=$(grep '^projects_mtime=' "$CACHE_FILE" 2>/dev/null | cut -d= -f2)
    CACHED_PROJECT_CONFIGS=$(grep '^project_configs_mtime=' "$CACHE_FILE" 2>/dev/null | cut -d= -f2)
    if [ "$CONFIG_MTIME" = "$CACHED_CONFIG" ] && \
       [ "$PROJECTS_MTIME" = "$CACHED_PROJECTS" ] && \
       [ "$PROJECT_CONFIGS_MTIME" = "$CACHED_PROJECT_CONFIGS" ]; then
        exit 0
    fi
fi

# Build find predicates from patterns
# Reads patterns from a temp file (parameter $1) to avoid subshell/pipeline issues.
# Rules:
#   "**/foo" or "foo"          -> -name "foo"
#   "**/path/to/file"          -> -path "*/path/to/file"
#   "*.ext"                    -> -name "*.ext"
build_find_args() {
    args="-type f"
    first=true
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        clean="${pattern#\*\*\/}"
        if [ "$first" = true ]; then
            args="$args \("
            first=false
        else
            args="$args -o"
        fi
        case "$clean" in
            */*) args="$args -path \"*/$clean\"" ;;
            *)   args="$args -name \"$clean\"" ;;
        esac
    done < "$1"
    if [ "$first" = false ]; then
        args="$args \)"
    fi
    echo "$args"
}

# Apply ACL denies + close ownership gap for a single project root
apply_acls() {
    local root="$1" find_args="$2"
    [ -z "$find_args" ] && return
    [ "$find_args" = "-type f" ] && return

    eval "find \"$root\" $find_args -exec setfacl -m \"u:$OPENCODE_USER:---\" {} +" 2>/dev/null || true

    if [ -n "$DEFAULT_USER" ]; then
        eval "find \"$root\" $find_args -user \"$OPENCODE_USER\" -exec chown \"$DEFAULT_USER:$WWW_GROUP\" {} +" 2>/dev/null || true
    fi
}

# Remove ACL denies (setfacl -x) — used for project-level allow patterns
# that override global denies within a single project root.
remove_acls() {
    local root="$1" find_args="$2"
    [ -z "$find_args" ] && return
    [ "$find_args" = "-type f" ] && return
    eval "find \"$root\" $find_args -exec setfacl -x \"u:$OPENCODE_USER\" {} +" 2>/dev/null || true
}

# Build global find args
TMP_PATTERNS=$(mktemp)
GLOBAL_FIND_ARGS=""
if [ -n "$GLOBAL_PATTERNS" ]; then
    echo "$GLOBAL_PATTERNS" > "$TMP_PATTERNS"
    GLOBAL_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")
fi

# Iterate over all project roots
while IFS= read -r root; do
    [ -z "$root" ] && continue
    [ ! -d "$root" ] && continue

    # HARD GUARD: never touch system paths
    case "$root" in
        /|/etc|/etc/*|/boot|/boot/*|/usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*|/lib|/lib/*|\
        /lib64|/lib64/*|/sys|/sys/*|/proc|/proc/*|/dev|/dev/*|/run|/run/*|/root|/root/*)
            echo "protect-projects: REFUSING to touch system path: $root" >&2
            continue
            ;;
    esac

    # Apply global ACL denies (all projects)
    apply_acls "$root" "$GLOBAL_FIND_ARGS"

    # Apply project-specific ACL denies if project config exists
    PROJECT_CONFIG=""
    if [ -f "$root/opencode.jsonc" ]; then
        PROJECT_CONFIG="$root/opencode.jsonc"
    elif [ -f "$root/opencode.json" ]; then
        PROJECT_CONFIG="$root/opencode.json"
    fi

    if [ -n "$PROJECT_CONFIG" ]; then
        # Apply additional project denies (cumulative with global)
        PROJECT_PATTERNS=$($PARSER "$PROJECT_CONFIG" 2>/dev/null || true)
        if [ -n "$PROJECT_PATTERNS" ]; then
            echo "$PROJECT_PATTERNS" > "$TMP_PATTERNS"
            PROJECT_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")
            apply_acls "$root" "$PROJECT_FIND_ARGS"
        fi

        # Remove global denies for project-level allow patterns
        PROJECT_ALLOW=$($PARSER --allow "$PROJECT_CONFIG" 2>/dev/null || true)
        if [ -n "$PROJECT_ALLOW" ]; then
            echo "$PROJECT_ALLOW" > "$TMP_PATTERNS"
            ALLOW_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")
            remove_acls "$root" "$ALLOW_FIND_ARGS"
        fi
    fi
done < "$PROJECTS_CONF"

# Update cache
printf 'config_mtime=%s\nprojects_mtime=%s\nproject_configs_mtime=%s\n' \
    "$CONFIG_MTIME" "$PROJECTS_MTIME" "$PROJECT_CONFIGS_MTIME" > "$CACHE_FILE"
