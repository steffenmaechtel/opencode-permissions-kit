# shellcheck shell=sh
# opencode permissions kit -- staged-write.sh
#
# Symlink-safe privileged file install (review 0.0.39g S1): a direct
# `cp` + `chown`/`chmod` onto a destination inside the AGENT-owned home
# follows a pre-planted symlink as root — a dangling link passes the
# usual `[ ! -f ]` gates, and cp/chown/chmod dereference the operand
# (verified live on coreutils 9.4), so the write lands on the
# attacker-chosen path and the following chown hands the agent the
# file. Instead:
#
#   1. stage the content in a ROOT-OWNED staging dir (CONFDIR — the
#      agent can neither write the directory nor unlink the staged
#      file inside it),
#   2. apply owner and mode THERE (nothing path-based ever touches a
#      name the agent controls while it matters),
#   3. mv onto the destination — rename(2) REPLACES a planted link
#      instead of following it, same-device and cross-device alike
#      (mv's EXDEV fallback unlinks a non-directory destination first;
#      verified live).
#
# POSIX sh, SOURCED by install.sh, config.sh and update.sh (checkout
# copy first, deployed LIBDIR fallback — same rules as fs-baseline.sh).
# Never executed directly. SW_SUDO overrides the sudo prefix ("" in
# tests), SW_STAGE_DIR the staging directory. Note the plain "-":
# SW_SUDO="" must stay empty, a ":-" would re-substitute sudo.
# Deployed to /usr/local/lib/opencode-permissions-kit/sh/staged-write.sh.

_sw_sudo() { ${SW_SUDO-sudo} "$@"; }

# staged_write <mode> <owner> <src> <dst>
# Installs <src> as <dst> with <mode> and <owner> ("user:group" — the
# exact chown operand). Fails (non-zero, loud via the caller's set -e)
# when any step fails; the destination is only ever touched by the
# final mv, so a half-written destination cannot exist. Callers decide
# the POLICY for a symlinked destination (skip as user-managed vs.
# replace the link) BEFORE calling — this function always replaces.
staged_write() {
    _sw_mode="$1"; _sw_owner="$2"; _sw_src="$3"; _sw_dst="$4"
    _sw_stage="${SW_STAGE_DIR:-/etc/opencode-permissions-kit}"
    _sw_tmp=$(_sw_sudo mktemp "$_sw_stage/.opk-stage.XXXXXX") || return 1
    # Register for the caller's scratch-cleanup trap (0.0.39e C3): the
    # entry is gone after a successful mv, so the trap's rm is a no-op.
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_sw_tmp"
    fi
    # cp (not a redirect): the staged file is root-owned inside a
    # root-owned dir — no unprivileged shell ever opens it, and no
    # planted name can appear between mktemp and now.
    if ! _sw_sudo cp "$_sw_src" "$_sw_tmp" \
       || ! _sw_sudo chown "$_sw_owner" "$_sw_tmp" \
       || ! _sw_sudo chmod "$_sw_mode" "$_sw_tmp"; then
        _sw_sudo rm -f "$_sw_tmp"
        return 1
    fi
    _sw_sudo mv -f "$_sw_tmp" "$_sw_dst" || { _sw_sudo rm -f "$_sw_tmp"; return 1; }
    return 0
}
