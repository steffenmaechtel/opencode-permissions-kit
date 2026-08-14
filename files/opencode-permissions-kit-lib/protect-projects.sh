#!/bin/sh
# opencode permissions kit — protect-projects.sh
# Applies hard Linux ACL denies (u:opencode:---) to sensitive files
# defined in /home/opencode/.config/opencode/opencode.json[c].
# Also scans each project root for <root>/opencode.json[c] and applies
# additional project-scoped denies (PLAN-STEP-2: cumulative, never weaker).
#
# Scope: ONLY within directories listed in /etc/opencode-permissions-kit/projects.conf.
#         Never touches system paths (/, /etc, /boot, /usr, /root).
# Runs as root via sudo (idempotent, safe to call repeatedly).
set -e

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). Logs every
# ACL change (batch + file count) so the protection history is inspectable.
log() { :; }
if [ -f "$(dirname "$0")/log.sh" ]; then
    . "$(dirname "$0")/log.sh"
fi

FORCE=false
CWD=""
while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=true ;;
        --cwd)   CWD="$2"; shift ;;
    esac
    shift
done

PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
[ -f "$PROJECTS_CONF" ] || PROJECTS_CONF="/etc/opencode/projects.conf"
# install.conf (preferred); fall back to legacy paths for upgrades
# (pre-0.0.10 /etc/opencode/, pre-0.0.9 setup.conf).
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode-permissions-kit/setup.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"
CONFIG_DIR="/home/opencode/.config/opencode"
PARSER="/usr/local/lib/opencode-permissions-kit/jsonc-parser.py"
CACHE_FILE="/usr/local/lib/opencode-permissions-kit/.cache"

OPENCODE_USER="opencode"
WWW_GROUP="www-data"

TMP_PATTERNS=""
TMP_DDEV=""
cleanup() { rm -f "$TMP_PATTERNS" "$TMP_DDEV"; }
trap cleanup EXIT

# Read DEFAULT_USER from install.conf (legacy: setup.conf)
DEFAULT_USER=""
if [ -f "$INSTALL_CONF" ]; then
    DEFAULT_USER=$(grep '^DEFAULT_USER=' "$INSTALL_CONF" 2>/dev/null | cut -d= -f2)
fi
if [ -z "$DEFAULT_USER" ]; then
    echo "protect-projects: DEFAULT_USER not found in $INSTALL_CONF — skipping chown step" >&2
    log "DEFAULT_USER missing from $INSTALL_CONF — chown step skipped"
fi

# Find active global config file (.jsonc or .json)
CONFIG_FILE=""
if [ -f "$CONFIG_DIR/opencode.jsonc" ]; then
    CONFIG_FILE="$CONFIG_DIR/opencode.jsonc"
elif [ -f "$CONFIG_DIR/opencode.json" ]; then
    CONFIG_FILE="$CONFIG_DIR/opencode.json"
else
    echo "protect-projects: No global opencode config — nothing to protect" >&2
    log "no global opencode config found — nothing to protect"
    exit 0
fi

# Extract global deny patterns
GLOBAL_PATTERNS=$($PARSER "$CONFIG_FILE" 2>/dev/null || true)

# Read project roots (needed early for cache + project config scan)
if [ ! -f "$PROJECTS_CONF" ]; then
    echo "protect-projects: $PROJECTS_CONF not found — nothing to protect" >&2
    log "$PROJECTS_CONF not found — nothing to protect"
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

# Find the governing opencode.json[c]: the NEAREST config walking UP from a
# start directory. Git worktrees are often nested repos (repo/ inside a
# project) and the git hooks pass the worktree root as --cwd; a config at the
# project root (where opencode was launched) must still be found from the
# nested worktree. Echoes the config path, or nothing if no ancestor carries
# a config.
find_cwd_config() {
    local walk="${1%/}"
    while :; do
        if [ -f "$walk/opencode.jsonc" ]; then
            echo "$walk/opencode.jsonc"
            return 0
        elif [ -f "$walk/opencode.json" ]; then
            echo "$walk/opencode.json"
            return 0
        fi
        [ "$walk" = "/" ] && return 0
        walk=$(dirname "$walk")
    done
}

# CWD project config detection (for cache key, before cache check)
CWD_CONFIG=""
if [ -n "$CWD" ]; then
    CWD_CONFIG=$(find_cwd_config "$CWD")
fi
if [ -n "$CWD_CONFIG" ]; then
    CWD_MTIME=$(stat -c '%Y' "$CWD_CONFIG" 2>/dev/null || echo "0")
    PROJECT_CONFIGS_MTIME=$((PROJECT_CONFIGS_MTIME + CWD_MTIME))
fi

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

# Check if a given path is under any project root
is_under_root() {
    local path="$1"
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ ! -d "$root" ] && continue
        root_clean="${root%/}"
        if [ "$path" = "$root_clean" ] || [ "${path#$root_clean/}" != "$path" ]; then
            return 0
        fi
    done < "$PROJECTS_CONF"
    return 1
}

# Apply ACL denies + close ownership gap for a single project root
apply_acls() {
    local root="$1" find_args="$2"
    [ -z "$find_args" ] && return
    [ "$find_args" = "-type f" ] && return

    count=$(eval "find \"$root\" $find_args -exec setfacl -m \"u:$OPENCODE_USER:---\" {} + -print" 2>/dev/null | wc -l)
    if [ "${count:-0}" -gt 0 ]; then
        log "setfacl deny u:$OPENCODE_USER:--- on $count file(s) under $root"
    fi

    if [ -n "$DEFAULT_USER" ]; then
        chown_count=$(eval "find \"$root\" $find_args -user \"$OPENCODE_USER\" -exec chown \"$DEFAULT_USER:$WWW_GROUP\" {} + -print" 2>/dev/null | wc -l)
        if [ "${chown_count:-0}" -gt 0 ]; then
            log "chown $DEFAULT_USER:$WWW_GROUP on $chown_count file(s) under $root"
        fi
    fi
}

# Remove ACL denies (setfacl -x) — used for project-level allow patterns
# that override global denies within a single project root.
remove_acls() {
    local root="$1" find_args="$2"
    [ -z "$find_args" ] && return
    [ "$find_args" = "-type f" ] && return
    count=$(eval "find \"$root\" $find_args -exec setfacl -x \"u:$OPENCODE_USER\" {} + -print" 2>/dev/null | wc -l)
    if [ "${count:-0}" -gt 0 ]; then
        log "setfacl -x (allow override) on $count file(s) under $root"
    fi
}

# Clear ACL denies for files that no longer match any deny pattern.
# A deny pattern removed from the config leaves a hard u:OPENCODE_USER:---
# entry behind; this removes every u:OPENCODE_USER entry and the apply_acls
# calls right after re-add the ones still matching current patterns.
# (GNU find has no "-acl" predicate, so this walks once with getfacl -R.)
clear_stale_acls() {
    local root="$1"
    stale=$(getfacl -R -p "$root" 2>/dev/null | awk '
        /^# file: / { path = substr($0, 9); has = 0; next }
        /^user:opencode:/ { has = 1; next }
        /^$/ { if (path != "" && has) print path; path = ""; has = 0 }
    ')
    if [ -n "$stale" ]; then
        count=$(printf '%s\n' "$stale" | wc -l)
        printf '%s\n' "$stale" | xargs -d '\n' setfacl -x "u:$OPENCODE_USER" 2>/dev/null
        log "cleared u:$OPENCODE_USER ACL on $count stale file(s) under $root"
    fi
}

# ddev compat: ddev recreates the project's .ddev content as the launching
# developer user (chmod 755), which collapses the ACL mask to r-x and strips
# the www-data group write the opencode user relies on. ddev start then fails
# with "permission denied" even though the project opted in to docker/ddev.
# Re-assert the kit base bits (group www-data, rwx mask) on every .ddev tree
# found under the root — ddev projects are usually subdirectories of the
# registered root (e.g. /var/www/vhosts/<project>/.ddev).
#
# Additionally heals a KILLED sandbox ddev transaction (PLAN-DDEV-SANDBOX
# R2): if no transaction stamp is open for this root, hand .ddev content
# stranded in opencode ownership back to the developer.
fix_ddev_tree() {
    local root="$1" d
    find "$root" -type d -name .ddev -print 2>/dev/null > "$TMP_DDEV"
    while IFS= read -r d; do
        [ -z "$d" ] && continue

        if [ -n "$DEFAULT_USER" ]; then
            stamp_name=$(printf '%s' "$root" | tr -c 'A-Za-z0-9' '_')
            if [ ! -e "/run/opencode-permissions-kit/ddev-txn/${stamp_name}.open" ]; then
                oc_owned=$(find "$d" -user "$OPENCODE_USER" -print 2>/dev/null)
                if [ -n "$oc_owned" ]; then
                    printf '%s\n' "$oc_owned" | xargs -d '\n' chown "$DEFAULT_USER:$WWW_GROUP" 2>/dev/null
                    count=$(printf '%s\n' "$oc_owned" | wc -l)
                    log "ddev txn heal: chown $DEFAULT_USER:$WWW_GROUP on $count stranded .ddev file(s)/dir(s) under $d"
                fi
            fi
        fi

        notgroup=$(find "$d" ! -group "$WWW_GROUP" -print 2>/dev/null)
        if [ -n "$notgroup" ]; then
            printf '%s\n' "$notgroup" | xargs -d '\n' chgrp "$WWW_GROUP"
            count=$(printf '%s\n' "$notgroup" | wc -l)
            log "ddev compat: chgrp $WWW_GROUP on $count .ddev file(s)/dir(s) under $d"
        fi

        # Entries carrying the kit's www-data ACL entry but a mask tighter than
        # rwx (ddev chmod 755). Restore entry + mask so opencode can rewrite.
        capped=$(getfacl -R -p "$d" 2>/dev/null | awk '
            /^# file: / { path = substr($0, 9); has = 0; next }
            /^group:www-data:/ { has = 1; next }
            /^mask::/ { if (has && $0 != "mask::rwx") { print path; has = 0 } next }
            /^$/ { path = ""; has = 0 }
        ')
        if [ -n "$capped" ]; then
            printf '%s\n' "$capped" | xargs -d '\n' setfacl -m "g:$WWW_GROUP:rwx" -m mask::rwx 2>/dev/null
            count=$(printf '%s\n' "$capped" | wc -l)
            log "ddev compat: www-data rwx + mask rwx on $count .ddev file(s)/dir(s) under $d"
        fi
    done < "$TMP_DDEV"
}

# Build global find args
TMP_PATTERNS=$(mktemp)
TMP_DDEV=$(mktemp)
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
            log "REFUSED system path: $root"
            continue
            ;;
    esac

    # Clear stale ACLs from removed deny patterns, then re-apply current ones
    clear_stale_acls "$root"

    # ddev compat: keep .ddev group-writable for opted-in docker/ddev projects
    fix_ddev_tree "$root"

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

# === CWD project config (opencode started in this directory) ===
if [ -n "$CWD_CONFIG" ] && is_under_root "$CWD"; then
    # Apply CWD-specific denies (additional to global)
    CWD_PATTERNS=$($PARSER "$CWD_CONFIG" 2>/dev/null || true)
    if [ -n "$CWD_PATTERNS" ]; then
        echo "$CWD_PATTERNS" > "$TMP_PATTERNS"
        CWD_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")
        apply_acls "$CWD" "$CWD_FIND_ARGS"
    fi

    # Remove global denies for CWD-level allow patterns
    CWD_ALLOW=$($PARSER --allow "$CWD_CONFIG" 2>/dev/null || true)
    if [ -n "$CWD_ALLOW" ]; then
        echo "$CWD_ALLOW" > "$TMP_PATTERNS"
        ALLOW_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")
        remove_acls "$CWD" "$ALLOW_FIND_ARGS"
    fi
fi

# Update cache
printf 'config_mtime=%s\nprojects_mtime=%s\nproject_configs_mtime=%s\n' \
    "$CONFIG_MTIME" "$PROJECTS_MTIME" "$PROJECT_CONFIGS_MTIME" > "$CACHE_FILE"
log "protect-projects run complete (force=$FORCE, cwd=${CWD:-none})"
