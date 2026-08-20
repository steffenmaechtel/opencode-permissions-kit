# shellcheck shell=sh
# opencode permissions kit -- fs-baseline.sh
#
# Group baseline with live progress (issue #14): chgrp -R + setgid +
# group rw + default ACLs over a project root. First installs on large
# trees (hundreds of repos) take minutes per pass — each pass streams a
# running entry count to stderr so the user sees movement instead of a
# frozen prompt. Paths flow as a NUL stream:
#
#   sudo find <root> <expr> -print0 | _fsb_count_tee <label> | sudo xargs -0 -r <cmd>
#
# _fsb_count_tee (python3 — a kit hard dependency, same as the jsonc
# parser) forwards the bytes untouched and only COUNTS the NUL bytes, so
# the overhead per entry is a memcmp, not a process or a line parser.
#
# POSIX sh, SOURCED by install.sh, config.sh and update.sh (checkout
# copy first, deployed LIBDIR fallback — same rules as ddev-handover.sh).
# Never executed directly. FS_SUDO overrides the sudo prefix ("" in
# tests; plain find/chgrp/chmod/setfacl for a same-user run). Note the
# plain "-": FS_SUDO="" must stay empty, a ":-" would re-substitute sudo.
# Deployed to /usr/local/lib/opencode-permissions-kit/fs-baseline.sh.

_fsb_sudo() { ${FS_SUDO-sudo} "$@"; }

# _fsb_count_tee <label>: stdin NUL-separated stream -> stdout (verbatim)
# + a "label: N entries" line on stderr, rewritten every 2000 entries
# and finalized with "— done" (a plain line, not a carriage return, so
# logs stay grep-able). Script via -c, NOT a heredoc: `python3 -` with a
# heredoc would consume stdin for the script itself and the tee would
# read nothing.
_fsb_count_tee() {
    python3 -c '
import sys
label = sys.argv[1]
counted = 0
shown = 0
while True:
    chunk = sys.stdin.buffer.read(1 << 20)
    if not chunk:
        break
    counted += chunk.count(b"\0")
    sys.stdout.buffer.write(chunk)
    sys.stdout.buffer.flush()
    if counted - shown >= 2000:
        shown = counted
        sys.stderr.write("\r    %-16s %d entries" % (label, counted))
        sys.stderr.flush()
if counted:
    sys.stderr.write("\r    %-16s %d entries — done\n" % (label, counted))
    sys.stderr.flush()
' "$1"
}

# _fsb_pass <label> <root> <find-expr...> -- <cmd...>: one baseline pass
# over the NUL stream. The find expression comes through verbatim, the
# command after "--" receives the paths via xargs -0 (-r: no empty run).
_fsb_pass() {
    _fsbp_label="$1"; _fsbp_root="$2"; shift 2
    _fsbp_expr=""
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        _fsbp_expr="$_fsbp_expr $1"
        shift
    done
    shift  # consume --
    [ $# -gt 0 ] || return 0
    # shellcheck disable=SC2086  # find expression built word-wise above
    _fsb_sudo find "$_fsbp_root" $_fsbp_expr -print0 2>/dev/null \
        | _fsb_count_tee "$_fsbp_label" \
        | _fsb_sudo xargs -0 -r "$@"
    return 0
}

# fs_baseline_root <root> <group>: the full recursive baseline —
#   1. chgrp every entry to the sharing group
#   2. setgid + group rwx on every directory (new files anywhere in the
#      tree inherit the group; both sides can create entries)
#   3. group rw on every file (developer and agent edit each other's
#      pre-install files; .git included, issue #17)
#   4. default ACLs g:<group>:rwx on every directory (governs new files)
# Idempotent; re-runs on install, `config.sh projects add` / `refresh`
# and `update.sh --refresh`. Issue #14: prints a heads-up for large
# trees and a live per-pass counter to stderr.
# The chgrp pass skips symlinks (! -type l): a bare `chgrp <link>`
# dereferences the TARGET — outside the tree — while `chgrp -R` (the
# code this replaces) never did (default -P). chmod passes are type-
# filtered anyway; setfacl touches dirs only.
fs_baseline_root() {
    fsb_root="$1"
    fsb_group="$2"
    [ -n "$fsb_root" ] && [ -d "$fsb_root" ] || return 0
    printf '%s\n' "  group baseline on $fsb_root (group $fsb_group) — large trees can take several minutes; progress per pass:" >&2
    _fsb_pass "chgrp"        "$fsb_root" ! -type l          -- chgrp "$fsb_group"
    _fsb_pass "dirs g+rwxs"  "$fsb_root" -type d            -- chmod g+rwxs
    _fsb_pass "files g+rw"   "$fsb_root" -type f            -- chmod g+rw
    _fsb_pass "default ACLs" "$fsb_root" -type d            -- setfacl -d -m "g:$fsb_group:rwx"
    return 0
}
