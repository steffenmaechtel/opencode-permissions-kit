# shellcheck shell=sh
# opencode permissions kit -- secure-binary.sh
#
# Shared binary hardening — ONE implementation for install.sh and
# update.sh (both carried their own copy of the chown/chmod pair, in
# three divergent flavors: fail-loud in install.sh (0.0.39e C4), a
# silent re-assert and a fail-loud path inside update.sh).
#
# root:<sharing-group> mode 750 lets the opencode user (a group member)
# run the binary and keeps unrelated users out. It is NOT a
# developer-side bypass guard: the developer is in the sharing group
# too and CAN exec this path directly — the soft layer (deny-all
# config + red theme + warnings) is what deters that, per the kit's
# declared model.
#
# POSIX sh, SOURCED by install.sh and update.sh (checkout copy first,
# deployed LIBDIR fallback — same rules as staged-write.sh). Never
# executed directly. SB_SUDO overrides the sudo prefix ("" in tests).
# Note the plain "-": SB_SUDO="" must stay empty, a ":-" would
# re-substitute sudo. Deployed to
# /usr/local/lib/opencode-permissions-kit/sh/secure-binary.sh.

_sb_sudo() { ${SB_SUDO-sudo} "$@"; }

# secure_binary <bin-path> <group>
# chown root:<group> is best-effort (2>/dev/null || true — a missing
# group must not block the load-bearing step), the chmod 750 FAILS
# LOUD: the mode scopes execution to root + the sharing group, and a
# silent best-effort chmod once reported the binary as secured while
# it was not (0.0.39e C4). Returns 1 (stderr message + audit-log line
# when the caller has a log()) when the chmod fails; callers abort on
# that under set -e or their own die/exit.
secure_binary() {
    _sb_bin="$1"
    _sb_group="$2"
    _sb_sudo chown "root:$_sb_group" "$_sb_bin" 2>/dev/null || true
    if ! _sb_sudo chmod 750 "$_sb_bin" 2>/dev/null; then
        echo "error: cannot chmod 750 $_sb_bin — aborting." >&2
        if command -v log >/dev/null 2>&1; then
            log "secure_binary FAILED: chmod 750 on $_sb_bin"
        fi
        return 1
    fi
    return 0
}
