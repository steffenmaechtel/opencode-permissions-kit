#!/bin/sh
# opencode permissions kit -- log.sh
# Shared audit log for every kit script that changes the system. Sourced
# (not executed) by install.sh / update.sh / config.sh / uninstall.sh /
# protect-projects.sh. Without it the kit still works — logging is
# best-effort and never breaks the calling script.
#
# Location:  /var/log/opencode-permissions-kit/opencode-permissions-kit.log
#   - dir root:root mode 700, file root:root mode 600 (the 'opencode' user
#     must NOT be able to read it — it documents the very restrictions that
#     are applied against that user)
#   - size-based self-rotation: 1 MB -> .1 .. .5, no external logrotate
#   - one line per event:  <ISO-timestamp> [<script-name>] <message>
#
# Usage (from a kit script):
#   . /usr/local/lib/opencode/log.sh
#   log "created user opencode"
#   log "setfacl deny on 42 files under /var/www/vhosts/foo"

LOG_DIR="/var/log/opencode-permissions-kit"
LOG_FILE="$LOG_DIR/opencode-permissions-kit.log"
LOG_MAX_BYTES=1048576
LOG_KEEP=5

log_init() {
    mkdir -p "$LOG_DIR" 2>/dev/null || return 1
    # Only attempt the file setup when we can actually write the directory.
    # Guards against the shell's own "Permission denied" noise on failed
    # redirects (e.g. uninstall running as the default user).
    [ -w "$LOG_DIR" ] || return 1
    chown root:root "$LOG_DIR" 2>/dev/null || true
    chmod 700 "$LOG_DIR" 2>/dev/null || true
    if [ ! -f "$LOG_FILE" ]; then
        : > "$LOG_FILE" 2>/dev/null || return 1
    fi
    chown root:root "$LOG_FILE" 2>/dev/null || true
    chmod 600 "$LOG_FILE" 2>/dev/null || true
}

log_rotate() {
    [ -f "$LOG_FILE" ] || return 0
    size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo "0")
    [ "${size:-0}" -lt "$LOG_MAX_BYTES" ] && return 0
    i=$LOG_KEEP
    while [ "$i" -gt 1 ]; do
        j=$((i - 1))
        [ -f "$LOG_FILE.$j" ] && mv -f "$LOG_FILE.$j" "$LOG_FILE.$i" 2>/dev/null
        i=$j
    done
    mv -f "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null || true
}

log() {
    log_init || return 0
    log_rotate
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
    tag=${0##*/}
    printf '%s [%s] %s\n' "$ts" "$tag" "$*" >> "$LOG_FILE" 2>/dev/null || true
}
