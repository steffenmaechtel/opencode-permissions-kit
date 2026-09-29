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
    # [ -d ] refuse (review 0.0.39h F3), immediately before the mv: `mv
    # -f` onto a DIRECTORY at the destination moves the staged file
    # INSIDE it and returns 0 — success would be a lie (the destination
    # path itself is never written, the staged file lands in the
    # agent-controlled tree). [ -d ] follows a link-to-directory, so
    # that variant is refused too; a link to a FILE is still replaced
    # (the S1 contract).
    if _sw_sudo [ -d "$_sw_dst" ]; then
        echo "error: staged_write: destination '$_sw_dst' is a directory — refusing (mv would move the staged file inside it)" >&2
        _sw_sudo rm -f "$_sw_tmp"
        return 1
    fi
    _sw_sudo mv -f "$_sw_tmp" "$_sw_dst" || { _sw_sudo rm -f "$_sw_tmp"; return 1; }
    return 0
}

# agent_home_sane <oc-user> <path>
# [ -L ] assertion for every component of <path> BELOW the agent home
# (reviews 0.0.39h F1/F2 — the 0.0.39g symlink safety secured only the
# FINAL path component):
#   - a replaced PARENT (~/.config, ~/.config/opencode, ~/.local/share,
#     ~/.agents, ...) passes `sudo mkdir -p` SILENTLY and redirects every
#     privileged write below it into the link target,
#   - chown -R/chmod/cp -a on an agent-home OPERAND dereference a
#     planted link (a linked ~/.config recursively hands an arbitrary
#     tree to the agent), and staged_write's mv lands inside a linked
#     parent directory.
# Walks every component of <path> below /home/<oc-user>, [ -L ] on each,
# the FINAL component included — pass the OPERAND itself for
# chown/chmod/cp gates, or the PARENT of a staged_write destination
# (whose leaf policy — skip as user-managed vs. replace by mv — belongs
# to the caller). Returns 0 silently when the chain is clean or <path>
# lies outside the agent home (nothing agent-replaceable there; the
# developer's home is trusted); on the FIRST link prints one loud
# user-managed-skip line to stderr and returns 1 — callers skip the
# privileged write (the g-wave's policy: a link is user structure, never
# written through). OPK_AGENT_HOME overrides the home base for tests.
agent_home_sane() {
    _ahs_user="$1"
    _ahs_path="$2"
    _ahs_base="${OPK_AGENT_HOME:-/home/$_ahs_user}"
    case "$_ahs_path" in
        "$_ahs_base"|"$_ahs_base"/*) ;;
        *) return 0 ;;
    esac
    [ "$_ahs_path" = "$_ahs_base" ] && return 0
    _ahs_rest="${_ahs_path#"$_ahs_base"/}"
    while :; do
        case "$_ahs_rest" in
            */*)
                _ahs_seg="${_ahs_rest%%/*}"
                _ahs_rest="${_ahs_rest#*/}"
                _ahs_base="$_ahs_base/$_ahs_seg"
                if [ -L "$_ahs_base" ]; then
                    printf '%s\n' "  WARNING: $_ahs_base is a symlink inside the agent home — the kit never follows it (user-managed); the affected write is skipped." >&2
                    return 1
                fi
                ;;
            *)
                if [ -L "$_ahs_path" ]; then
                    printf '%s\n' "  WARNING: $_ahs_path is a symlink inside the agent home — the kit never follows it (user-managed); the affected write is skipped." >&2
                    return 1
                fi
                return 0
                ;;
        esac
    done
}
