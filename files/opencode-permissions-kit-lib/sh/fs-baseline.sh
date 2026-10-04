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
# Deployed to /usr/local/lib/opencode-permissions-kit/sh/fs-baseline.sh.

_fsb_sudo() { ${FS_SUDO-sudo} "$@"; }

# _fsb_ancestor_traversable <dir> <group>
# True (0) when <dir> already lets the sharing group's members traverse
# it: other-x, the dir's own group is <group> with group-x, or a named
# group ACL entry grants x. Bit-level only (no probe user) — callers
# that know the agent user may prefer the exact probe in
# fs_ensure_traversable below.
_fsb_ancestor_traversable() {
    _fsba_mode=$(stat -c %A "$1" 2>/dev/null) || return 1
    # other x: the literal x OR the sticky-bit form t (/tmp); group x:
    # the literal x OR the setgid form s (the kit's own 2775 dirs).
    case "$_fsba_mode" in
        ?????????x|?????????t) return 0 ;;
    esac
    if [ "$(stat -c %G "$1" 2>/dev/null)" = "$2" ]; then
        case "$_fsba_mode" in ??????x???|??????s???) return 0 ;; esac
    fi
    getfacl -p "$1" 2>/dev/null | grep -q "^group:$2:..x"
}

# fs_ensure_traversable <root> <group> [user]
# Grants traverse-only access (x — never read, no listing) to every
# ANCESTOR of <root> that blocks the sharing group's members. The
# baseline below fixes <root> downwards only, but a root under the
# developer's home (Ubuntu 24.04 ships $HOME as 0750 dev:dev) would
# stay unreachable for the agent anyway: resolving the root's path from
# / needs +x on EVERY component, so opencode and ddev fail with EACCES
# on the project dir while the root's own bits look perfect. ddev then
# misreports that as "a project cannot be created in the DDEV source
# code" — its fileutil.FileExists() is fail-open and reads EACCES as
# "exists" (pkg/fileutil/file_exists.go).
# Allow-ACL only — g:<group>:X, capital X never adds x to files — fully
# in the soft model: no deny entries, owner/group/mode stay untouched.
# [user] switches the per-ancestor check to an exact probe
# (sudo -u <user> test -x); without it (or with FS_SUDO="", tests) the
# bit-level heuristic above applies. Best-effort: ancestors on ACL-less
# filesystems only warn and never abort the baseline.
fs_ensure_traversable() {
    fsb_root="$1"; fsb_group="$2"; fsb_probe="${3:-}"
    [ -n "$fsb_root" ] && [ -d "$fsb_root" ] || return 0
    fsb_d=$(dirname "$fsb_root")
    while [ -n "$fsb_d" ] && [ "$fsb_d" != "/" ]; do
        fsb_need=1
        if [ -n "$fsb_probe" ] && [ "${FS_SUDO-sudo}" != "" ]; then
            # shellcheck disable=SC2086  # FS_SUDO is one word by contract
            ${FS_SUDO-sudo} -u "$fsb_probe" test -x "$fsb_d" 2>/dev/null && fsb_need=0
        else
            _fsb_ancestor_traversable "$fsb_d" "$fsb_group" && fsb_need=0
        fi
        if [ "$fsb_need" = 1 ]; then
            if _fsb_sudo setfacl -m "g:$fsb_group:X" "$fsb_d" 2>/dev/null; then
                printf '%s\n' "  traverse ACL g:$fsb_group on $fsb_d (x only — dir stays non-listable)" >&2
            else
                printf '%s\n' "  WARNING: could not grant traversal on $fsb_d (setfacl failed — ACL support?)"\
" — the agent may not reach $fsb_root" >&2
            fi
        fi
        # Fixed-point guard: a relative root would make dirname spin on
        # "." forever (unreachable via project_path_sane, but a manually
        # edited projects.conf could carry one) — stop when dirname stops
        # making progress (0.0.38 C13).
        _fsb_next=$(dirname "$fsb_d")
        [ "$_fsb_next" = "$fsb_d" ] && break
        fsb_d=$_fsb_next
    done
    return 0
}

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
#
# The consumer is a recheck loop, NOT a direct xargs exec (0.0.39e S1):
# find classifies each entry at SCAN time, and the scanned trees are
# group-writable by the semi-trusted agent — a file swapped for a symlink
# in the scan->exec window would be dereferenced by chgrp/chmod/setfacl
# on the operand, reaching outside the tree (the old chgrp -R never did:
# its traversal skipped symlinks by default). Every path is re-tested
# with [ -L ] immediately before its command runs; anything that is a
# symlink NOW is skipped. The command words are kit-fixed and space-free
# by construction (same contract as the find expression above).
_fsb_pass() {
    _fsbp_label="$1"; _fsbp_root="$2"; shift 2
    _fsbp_expr=""
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        _fsbp_expr="$_fsbp_expr $1"
        shift
    done
    shift  # consume --
    [ $# -gt 0 ] || return 0
    _fsbp_rc=0
    _fsbp_nul="$(mktemp "${TMPDIR:-/tmp}/opk-fsb-pass.XXXXXXXX")"
    # find's own status must survive into the pass bookkeeping (0.0.43b
    # W4): POSIX sh has no pipefail, a pipeline's rc is the LAST
    # command's alone, and xargs -r no-ops GREEN on an empty stream — a
    # find that died wholesale mid-walk still printed "applied". Walk
    # into a temp file first and track find's rc; its stderr stays
    # visible (the why behind the rc below). Live counting is
    # unaffected: the counter streams from the file while xargs chews it.
    # shellcheck disable=SC2086  # find expression built word-wise above
    _fsb_sudo find "$_fsbp_root" $_fsbp_expr -print0 >"$_fsbp_nul" || _fsbp_rc=$?
    if [ "$_fsbp_rc" -eq 0 ]; then
        _fsb_count_tee "$_fsbp_label" <"$_fsbp_nul" \
            | _fsb_sudo xargs -0 -r sh -c '
                # $1 = arity of the fixed command, then the kit-fixed command
                # words, then the batch of NUL-separated paths xargs appended.
                _n=$1; shift
                _c=""
                while [ "$_n" -gt 0 ]; do _c="$_c $1"; shift; _n=$((_n - 1)); done
                for _p in "$@"; do
                    [ -L "$_p" ] && continue
                    # shellcheck disable=SC2086  # kit-fixed, space-free words
                    $_c "$_p"
                done
              ' xargs-sh "$#" "$@" || _fsbp_rc=$?
    fi
    rm -f "$_fsbp_nul"
    # Per-pass failure tracking (0.0.43a F10): without pipefail the old
    # unconditional `return 0` made a wholesale pass failure (rc 123 =
    # xargs had failing batches, 125/126/127 = xargs/interpreter trouble)
    # invisible — callers printed "applied" regardless. Counted here,
    # summarized and propagated by fs_baseline_root below.
    if [ "$_fsbp_rc" -ne 0 ]; then
        _FSB_ERRORS=$((_FSB_ERRORS + 1))
        printf '  warn: baseline pass "%s" hit errors (rc %s) under %s — see the messages above\n' \
            "$_fsbp_label" "$_fsbp_rc" "$_fsbp_root" >&2
    fi
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
# and `update.sh --refresh`. Ancestors come first (fs_ensure_traversable
# above): the passes below fix <root> down, but without traversable
# ancestors the agent cannot resolve paths into the tree at all.
# Issue #14: prints a heads-up for large trees and a live per-pass
# counter to stderr.
# The chgrp pass skips symlinks (! -type l): a bare `chgrp <link>`
# dereferences the TARGET — outside the tree — while `chgrp -R` (the
# code this replaces) never did (default -P). chmod passes are type-
# filtered anyway; setfacl touches dirs only.
fs_baseline_root() {
    fsb_root="$1"
    fsb_group="$2"
    [ -n "$fsb_root" ] && [ -d "$fsb_root" ] || return 0
    # Wholesale-failure detection part 1 (0.0.43a F10): a missing tool
    # used to die silently inside the pipeline (find's stderr is
    # redirected, xargs -r succeeds on empty input) and the passes
    # "completed" with nothing applied. Probe BEFORE walking.
    for _fsb_tool in find chgrp chmod setfacl; do
        if ! command -v "$_fsb_tool" >/dev/null 2>&1; then
            printf '  error: required tool missing for the group baseline: %s\n' "$_fsb_tool" >&2
            return 1
        fi
    done
    _FSB_ERRORS=0
    fs_ensure_traversable "$fsb_root" "$fsb_group" "${3:-}"
    printf '%s\n' "  group baseline on $fsb_root (group $fsb_group) — large trees can take several minutes;"\
" progress per pass:" >&2
    _fsb_pass "chgrp"        "$fsb_root" ! -type l          -- chgrp "$fsb_group"
    _fsb_pass "dirs g+rwxs"  "$fsb_root" -type d            -- chmod g+rwxs
    _fsb_pass "files g+rw"   "$fsb_root" -type f            -- chmod g+rw
    _fsb_pass "default ACLs" "$fsb_root" -type d            -- setfacl -d -m "g:$fsb_group:rwx"
    # Wholesale-failure detection part 2: propagate the per-pass error
    # count (0.0.43a F10). Fail-loud on purpose — the callers' success
    # lines ("group + setgid + default ACLs applied") must not print
    # over a baseline that did not fully apply; "agent cannot write
    # project files" weeks later is the worse failure mode.
    if [ "$_FSB_ERRORS" -gt 0 ]; then
        printf '  error: %s baseline pass(es) failed on %s — the group baseline may be incomplete\n' \
            "$_FSB_ERRORS" "$fsb_root" >&2
        return 1
    fi
    return 0
}
