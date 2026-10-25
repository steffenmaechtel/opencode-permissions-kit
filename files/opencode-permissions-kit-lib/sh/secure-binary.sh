# shellcheck shell=sh
# opencode permissions kit -- secure-binary.sh
#
# Shared binary hardening + atomic deploys — ONE implementation for
# install.sh and update.sh (both carried their own copy of the
# chown/chmod pair, in three divergent flavors: fail-loud in
# install.sh (0.0.39e C4), a silent re-assert and a fail-loud path
# inside update.sh; issue #163 then moved the atomic binary
# replacement here for the same one-implementation reason).
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
    # pr-00263 a F25: chmod before chown — no cp-natural-755 window on
    # the live name between the two (the atomic helpers' order).
    if ! _sb_sudo chmod 750 "$_sb_bin" 2>/dev/null; then
        echo "error: cannot chmod 750 $_sb_bin — aborting." >&2
        if command -v log >/dev/null 2>&1; then
            log "secure_binary FAILED: chmod 750 on $_sb_bin"
        fi
        return 1
    fi
    _sb_sudo chown "root:$_sb_group" "$_sb_bin" 2>/dev/null || true
    return 0
}

# copy_binary_atomic <src> <dst>
# Atomic binary replacement (issue #163): copy to a sibling temp file
# next to the target, then mv into place. A plain in-place cp that
# dies mid-write (Ctrl-C, OOM, power loss) leaves a truncated binary
# with intact mode bits — present and executable, dead at the first
# agent session, and before issue #163 exactly the shape opk status
# papered over with an uncounted "unknown" row and an "All green"
# verdict. The mv renames within the same directory (same filesystem),
# so the target is always the complete old or the complete new file,
# never half of either. Riding benefit: the rename swaps the inode, so
# a running 2.x service keeps its old mapping instead of watching cp
# truncate the file under it (issue #80 context). Sweeps every
# binary-writing site: update.sh's deploy, its pre-upgrade backup (a
# half-written backup is a poisoned restore source) and its fallback
# restore, plus install.sh's four first-install copies.
# A run killed between the two legs leaves one root-owned temp behind
# ($$-suffixed, inert to status/wrapper, never colliding with a later
# run); sweeping stale temps with a root glob rm would be the bigger
# footgun — the rare litter is the accepted trade-off. L5 note: every
# operand lives on root-owned trees (kit bin dir, root mktemp backup
# dir), never on agent-writable paths.
copy_binary_atomic() {
    _cba_src="$1"
    _cba_dst="$2"
    _cba_tmp="${_cba_dst}.tmp.$$"
    if ! _sb_sudo cp "$_cba_src" "$_cba_tmp"; then
        _sb_sudo rm -f "$_cba_tmp"
        return 1
    fi
    if ! _sb_sudo mv -f "$_cba_tmp" "$_cba_dst"; then
        _sb_sudo rm -f "$_cba_tmp"
        return 1
    fi
}

# copy_file_atomic <src> <dst> <mode>
# Atomic file replacement with an explicit mode (0.0.49b C1): the umask
# profile's deploy shape, same construction as copy_binary_atomic above
# and lib_deploy's per-entry loop (0.0.49a W2) — sibling temp next to
# the target (same directory = same filesystem, so the mv renames; the
# cross-device unlink+copy fallback cannot reopen the truncate window),
# mode applied BEFORE the rename so content and mode appear together.
# Needed because /etc/profile.d/ is sourced by every user's login
# shell: a cp killed mid-write over the profile leaves a truncated
# script with intact mode bits (the #163 class on a protection layer),
# and a cp-natural mode under a stricter root umask (077) would deploy
# an unreadable profile that non-root shells silently skip. rm -f
# cleanup on every failure leg keeps the old entry byte-identical.
# L5 note: targets sit on root-owned trees (/etc/profile.d), never on
# agent-writable paths — the pid-suffixed temp cannot be pre-created.
copy_file_atomic() {
    _cfa_src="$1"
    _cfa_dst="$2"
    _cfa_mode="$3"
    _cfa_tmp="${_cfa_dst}.tmp.$$"
    if ! _sb_sudo cp "$_cfa_src" "$_cfa_tmp"; then
        _sb_sudo rm -f "$_cfa_tmp"
        return 1
    fi
    if ! _sb_sudo chmod "$_cfa_mode" "$_cfa_tmp"; then
        _sb_sudo rm -f "$_cfa_tmp"
        return 1
    fi
    if ! _sb_sudo mv -f "$_cfa_tmp" "$_cfa_dst"; then
        _sb_sudo rm -f "$_cfa_tmp"
        return 1
    fi
}
