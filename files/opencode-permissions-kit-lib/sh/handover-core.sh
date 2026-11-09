# shellcheck shell=sh
# opencode permissions kit -- handover-core.sh
#
# The opk handover subcommand's logic (issue #346 wave shape, #415
# ride-along): the former case arm of bin/opk, moved verbatim -- pure
# code movement, user-visible output byte-identical (proven by the
# test-kit-cli.sh behavioral matrix and an old-vs-new cmp drive; the
# dispatcher sources this lib and calls handover_core with the args
# after the subcommand). Sourced (never executed) by bin/opk through
# its $LIBDIR (SELF-resolved: the checkout copy when run from a
# checkout, the deployed tree otherwise -- bin/opk always has a real
# $0, no stdin-run anchor needed here), loud abort when the lib is
# missing (the #165 class: no silent arm drop); the pairing guard in
# the dispatcher refuses a version-skewed pairing.
#
# POSIX sh, no top-level side effects (definitions and comments only).
# The function runs in the CALLER's shell (bin/opk sets set -u only)
# and reads the globals the dispatcher sets before the call: LIBDIR,
# INSTALL_CONF, the ui_* helpers (or their dispatcher fallbacks),
# opk_policy_root + _OPK_POLICY_ROOT (sh/path-sane.sh, when present),
# OPK_HANDOVER_ROOT (sudo loop guard). It exits the script on usage
# errors and after the run (the arm did the same).
#
# The #215-era protection set (leaf [ -L ] refuse up front, [ ! -L ]
# recheck immediately before each executor, direction-dependent
# order, chown -R -h, find ! -type l) is extended by the exec-time
# component walk of #422: _ho_chain_sane re-tests every component of
# the operand's chain immediately before the executors -- a parent
# swapped for a symlink between validation and the executors resolves
# the operand through it while the leaf gates pass (the #266 class's
# last unswept sibling). Skip loud on a hit, mirroring the leaf
# gate's wording.

# Generic ownership switch between the two kit users, for
# mixed-owner trees (e.g. a checkout where BOTH the developer and
# the agent ran builds, like ddev's .gotmp cache): recursive chown
# to <user> + the kit's SHARING group, then g+w — the same
# semantics as the ddev handovers (ddev-handover.sh), applied to
# any path. The group never changes, so both sides keep group
# access; only the owner flips.
#   handover me <path>...        -> DEFAULT_USER:OPENCODE_GROUP
#   handover opencode <path>...  -> OPENCODE_USER:OPENCODE_GROUP
# --dry-run prints the plan and changes nothing (no sudo needed).
# System roots AND their subpaths, and whole home directories, are
# refused: hand over trees, not systems. Validation runs BEFORE
# the sudo hop, so argument errors and --dry-run work unprivileged.
# _ho_chain_sane <operand>: the #422 exec-time component walk. The
# validation gates and the leaf [ -L ] refuse above run up front and
# per-operand — a PARENT directory swapped for a symlink between them
# and the executors resolves the operand THROUGH it (the leaf inside
# the target is real, both leaf gates pass) and root find/chown -R
# walk the out-of-tree victim: the #266 class's last unswept sibling
# (chain-walker shape of _ddev_components_sane, ddev-handover.sh /
# agent_home_sane, staged-write.sh). Walks EVERY component of the
# operand's absolute lexical chain — realpath -s normalizes without
# ever resolving symlinks, so the walk sees the ORIGINAL names the
# executors act on; a relative operand is prefixed with $PWD first
# (validation refuses the dot/dotdot/slash forms, the normalizer only
# cleans the spelling). String ops only: spaced paths survive.
# Returns 1 on the FIRST link component.
_ho_chain_sane() {
    _hcs_path="$1"
    case "$_hcs_path" in
        /*) ;;
        *) _hcs_path="$PWD/$_hcs_path" ;;
    esac
    _hcs_path="$(realpath -s "$_hcs_path" 2>/dev/null || printf '%s' "$_hcs_path")"
    _hcs_rest="${_hcs_path#/}"
    _hcs_pre=""
    while [ -n "$_hcs_rest" ]; do
        case "$_hcs_rest" in
            */*)
                _hcs_pre="$_hcs_pre/${_hcs_rest%%/*}"
                _hcs_rest="${_hcs_rest#*/}"
                ;;
            *)
                _hcs_pre="$_hcs_path"
                _hcs_rest=""
                ;;
        esac
        [ -L "$_hcs_pre" ] && return 1
    done
    return 0
}

handover_core() {
    _ho_err() {
        ui_error "$1"
        echo "  usage: opk handover <me|opencode> <path>... [--dry-run]" >&2
        exit 1
    }
    [ "$#" -ge 2 ] || _ho_err "handover: need a target (me or opencode) and at least one path"
    _ho_target="$1"
    shift
    _ho_dry=0
    _ho_npaths=0
    for _ho_a in "$@"; do
        if [ "$_ho_a" = "--dry-run" ]; then
            _ho_dry=1
        else
            _ho_npaths=$((_ho_npaths + 1))
        fi
    done
    # (#370 a E2): `handover me --dry-run` (a forgotten path) passed
    # the $#-ge-2 gate above, every consumer loop skipped the flag,
    # and the dry run exited 0 printing NOTHING -- a forgotten path
    # read as a clean dry run. Flags are not operands; refuse.
    if [ "$_ho_npaths" -lt 1 ]; then
        _ho_err "handover: need at least one path (--dry-run only previews real paths)"
    fi
    # Usage errors first: a wrong target must not be masked by a
    # missing install.conf (e.g. dev checkouts without an install).
    case "$_ho_target" in
        me | opencode) ;;
        *) _ho_err "handover: unknown target '$_ho_target' (me or opencode)" ;;
    esac
    [ -f "$INSTALL_CONF" ] || _ho_err "handover: $INSTALL_CONF not found — is the kit installed?"
    _ho_getconf() { sed -n "s/^$1=//p" "$INSTALL_CONF" 2>/dev/null | tail -1; }
    _ho_group=$(_ho_getconf OPENCODE_GROUP)
    [ -n "$_ho_group" ] || _ho_err "handover: install.conf has no OPENCODE_GROUP"
    case "$_ho_target" in
        me) _ho_user=$(_ho_getconf DEFAULT_USER) ;;
        opencode) _ho_user=$(_ho_getconf OPENCODE_USER) ;;
    esac
    [ -n "$_ho_user" ] || _ho_err "handover: install.conf has no user for '$_ho_target'"
    id -u "$_ho_user" >/dev/null 2>&1 || _ho_err "handover: user '$_ho_user' does not exist"
    for _ho_a in "$@"; do
        [ "$_ho_a" = "--dry-run" ] && continue
        _ho_np=$(realpath -m "$_ho_a" 2>/dev/null || printf '%s' "$_ho_a")
        # Same policy shape as project_path_sane: system roots AND
        # their subpaths are refused — /etc/apache2 or /usr/local/foo
        # must not pass just because they are not the exact root
        # (review 0.0.39b S2). One deliberate difference: /tmp
        # subpaths stay allowed — handing over a temp build tree is
        # a legitimate ops action, and the baseline's reason to
        # refuse /tmp/* (project roots) does not apply here.
        case "$_ho_np" in
            # #377 (review #370 a O1) + pr-00429 a A1: FHS-complete
            # /var families — path-sane.sh parity.
            / | /bin | /bin/* | /boot | /boot/* | /dev | /dev/* | /etc | /etc/* | /home | /lib* | \
                /media | /media/* | /mnt | /mnt/* | /opt | /opt/* | /proc | /proc/* | /root | /root/* | \
                /run | /run/* | /sbin | /sbin/* | /srv | /srv/* | /sys | /sys/* | /tmp | /var/tmp/* | \
                /usr | /usr/* | /var | /var/tmp | /var/account | /var/account/* | /var/backups | \
                /var/backups/* | /var/cache | /var/cache/* | /var/crash | /var/crash/* | \
                /var/games | /var/games/* | /var/lib | /var/lib/* | /var/local | /var/local/* | \
                /var/lock | /var/lock/* | /var/log | /var/log/* | /var/mail | /var/mail/* | \
                /var/opt | /var/opt/* | /var/run | /var/run/* | /var/spool | /var/spool/* | /var/yp | /var/yp/*)
                _ho_err "handover: refusing system path '$_ho_np'""\
 — hand over project trees, not system (sub)paths"
                ;;
        esac
        case "$_ho_np" in
            /home/*) [ "$(dirname "$_ho_np")" = "/home" ] &&
                _ho_err "handover: refusing whole home directory '$_ho_np' — hand over subpaths" ;;
        esac
        # Slash-terminated operands are symlink-gate-blind (0.0.44a
        # V2; dotdot final/mid components added 0.0.44b W3 — same
        # class; the MID single-dot form joined 0.0.45c S7): path
        # resolution goes through the link before lstat ever sees
        # one — [ -L "x/" ], [ -L "x/.." ] and [ -L "x/./y" ] are
        # FALSE while chown -R -h and find act on the resolved
        # TARGET (a trailing slash: the link itself; "..": the link
        # target's PARENT; "./": through an intermediate link).
        # Checked on the RAW operand, after the path policy above
        # (which sees the resolved form): "/" is a system root, not
        # a form error, but "x/", "x/..", "a/../b" and "x/./y" into
        # a project tree are exactly the bypasses.
        case "$_ho_a" in
            */ | */. | *//* | */./* | */.. | */../*)
                _ho_err "handover: '$_ho_a' carries a slash/dotdot path form — pass the path itself""\
 (symlink gates cannot see through trailing slashes or .. components)"
                ;;
        esac
        [ -e "$_ho_np" ] || _ho_err "handover: no such path: $_ho_a"
    done
    # Declared container-tree warning (#352 / #313 phase 3): when a
    # 'me' takeover covers -- or sits inside -- a tree the project
    # declares in its opk.json, the re-own destroys exactly the
    # ownership state doctor classifies (#312: 'handover me' over
    # the whole project re-poisons container-written outputs; a
    # partial takeover inside a declared tree does the same).
    # Resolution is walk-up discovery since phase 4 (#353): the
    # policy is found the way doctor finds it by default -- from
    # the cwd upward, the NEAREST opk.json wins (a nested project
    # shadows any parent's) -- through the ONE shared leaf lib
    # (sh/path-sane.sh), not a per-command copy. No hit anywhere:
    # nothing to compare, no row (v1 shape). Advisory only: it
    # never blocks, and fires in --dry-run too (the dry run
    # previews what the real run does, 0.0.39i F4 class). The root
    # re-entry skips it -- the unprivileged pass showed it already.
    if [ "$_ho_target" = me ] && [ "${OPK_HANDOVER_ROOT:-}" != 1 ]; then
        _ho_policy_dir="$(realpath -m . 2>/dev/null || printf '%s' "$PWD")"
        # (#357 a A1, same class as doctor.sh's arm): the fallback
        # re-feeds raw input -- normalize a non-absolute result with
        # cd+pwd so the walker never receives a relative path (its
        # own belt refuses those; when even cd fails the attempt
        # ends without a hang). A logical $PWD with ".." components
        # can still walk ancestors in non-physical order when
        # realpath is absent -- accepted residual, recorded in the
        # round-a comment.
        case "$_ho_policy_dir" in
            /*) ;;
            *)
                _ho_norm="$(cd . 2>/dev/null && pwd)" &&
                    _ho_policy_dir="$_ho_norm"
                ;;
        esac
        if [ "$_OPK_POLICY_ROOT" = 1 ]; then
            if _ho_found="$(opk_policy_root "$_ho_policy_dir")"; then
                _ho_policy_dir="$_ho_found"
            fi
        fi
        if [ -f "$_ho_policy_dir/opk.json" ]; then
            # tolerant advisory read (doctor's strict validation is
            # deliberately not duplicated -- but the policy shapes
            # this reader CHECKS that doctor's validator rejects
            # take the same arm as broken JSON: exit 1 -> the warn
            # row below, the takeover proceeds. Covers top level
            # not an object, containerTrees not an array, and
            # control characters inside a declared path (#356 a
            # A3/B3) -- newline-split fragments can never reach the
            # matching loop this way. Note-field shapes are
            # deliberately tolerated (notes never affect matching).
            _ho_trc=0
            _ho_trees="$(
                python3 -I - "$_ho_policy_dir/opk.json" 2>/dev/null <<'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        doc = json.load(f)
except Exception:
    sys.exit(1)
if not isinstance(doc, dict):
    sys.exit(1)
trees = doc.get("containerTrees", [])


def _cntrl(c):
    # Same set as doctor's validator (#370 a C1 sweep): DEL (0x7F) and
    # C1 (0x80-0x9F) reach the warning text below as display injection.
    o = ord(c)
    return o < 32 or o == 127 or 0x80 <= o <= 0x9F


if not isinstance(trees, list):
    sys.exit(1)
for e in trees:
    p = e.get("path") if isinstance(e, dict) else e
    if not isinstance(p, str) or not p or any(_cntrl(c) for c in p):
        sys.exit(1)
    sys.stdout.write(p + "\n")
PYEOF
            )" || _ho_trc=$?
            if [ "$_ho_trc" -ne 0 ]; then
                ui_warn "opk.json at $_ho_policy_dir is unreadable -- declared-tree warning skipped"
            else
                printf '%s\n' "$_ho_trees" | while IFS= read -r _ho_decl; do
                    [ -n "$_ho_decl" ] || continue
                    # belt: only comparable relative path forms can
                    # be matched -- a STRICTER structural+shell set
                    # than doctor's path_error (which also rejects
                    # globs but TOLERATES non-ASCII; this belt
                    # additionally drops |&<> so fragments of a
                    # mangled policy cannot even reach the warning
                    # TEXT, #356 a A8/B3). A skip is never silent:
                    # the detail row names the declaration that
                    # forfeits the warning (#356 a C7).
                    _ho_badform=0
                    case "$_ho_decl" in
                        /* | */ | . | ./* | .. | ../* | */. | */./* | */.. | */../* | *//* | *\\*) _ho_badform=1 ;;
                    esac
                    case "$_ho_decl" in
                        *"'"* | *'"'* | *'`'* | *'$'* | *';'* | *"|"* | *"&"* | *"<"* | *">"*) _ho_badform=1 ;;
                    esac
                    if [ "$_ho_badform" = 1 ]; then
                        ui_detail "declared path '$_ho_decl' skipped -- unusable form (doctor rejects it too)"
                        continue
                    fi
                    _ho_tree="$(realpath -m "$_ho_policy_dir/$_ho_decl" 2>/dev/null ||
                        printf '%s' "$_ho_policy_dir/$_ho_decl")"
                    for _ho_a in "$@"; do
                        [ "$_ho_a" = "--dry-run" ] && continue
                        _ho_op="$(realpath -m "$_ho_a" 2>/dev/null || printf '%s' "$_ho_a")"
                        case "$_ho_op" in
                            "$_ho_tree" | "$_ho_tree"/*) ;; # operand covers/equals the tree
                            *)
                                case "$_ho_tree" in
                                    "$_ho_op"/*) ;; # operand inside the tree
                                    *) continue ;;
                                esac
                                ;;
                        esac
                        ui_warn "handover me: '$_ho_a' takes back the declared container tree '$_ho_decl'"
                        ui_detail "you are taking back a declared container tree -- expect a clean rebuild of its outputs"
                        ui_detail "'opk doctor' reports the state after; re-declare nothing, rebuild the outputs (#312)"
                        break
                    done
                done
            fi
        fi
    fi
    if [ "$_ho_dry" = 1 ]; then
        for _ho_a in "$@"; do
            [ "$_ho_a" = "--dry-run" ] && continue
            # 0.0.39i F4: the dry run previews the symlink refuse too —
            # what --dry-run announces must match what the real run does
            # (cli.md documents the refusal without a dry-run carve-out).
            # Slash-terminated operands never reach here: validation
            # above refuses them loudly BEFORE the dry-run branch, so
            # --dry-run previews exactly what the real run would hit
            # (0.0.44a V2).
            # The #422 chain walk previews with the leaf refuse (same
            # 0.0.39i F4 class: the real run's component-walk refuse
            # must not surprise a dry run that announced a handover).
            if [ -L "$_ho_a" ]; then
                echo "  would refuse: '$_ho_a' is a symlink (chown -R/chmod -R follow it)"
            elif ! _ho_chain_sane "$_ho_a"; then
                echo "  would refuse: '$_ho_a' crosses a symlinked path component (chown -R/chmod -R would follow it)"
            else
                echo "  would hand over: $_ho_a -> $_ho_user:$_ho_group (recursive, g+w)"
            fi
        done
        exit 0
    fi
    if [ "$(id -u)" -ne 0 ]; then
        # Loop guard: sudo must actually elevate (fake/broken sudo
        # would re-enter this branch forever).
        [ "${OPK_HANDOVER_ROOT:-}" = "1" ] && _ho_err "handover: sudo did not elevate — giving up"
        exec sudo env OPK_INSTALL_CONF="$INSTALL_CONF" OPK_HANDOVER_ROOT=1 \
            sh "$LIBDIR/bin/opk" handover "$_ho_target" "$@"
    fi
    _ho_rc=0
    ui_info "handing over to $_ho_user:$_ho_group (recursive, g+w) ..."
    for _ho_a in "$@"; do
        [ "$_ho_a" = "--dry-run" ] && continue
        # [ -L ] refuse + race-aware executors (review 0.0.39h F10;
        # TOCTOU window closed 0.0.43a F16; slash-form bypass closed
        # 0.0.44a V2, mid-dot 0.0.45c S7 — validation refuses x/,
        # x//, x/., x/./y before this loop, so both executors below
        # only ever see slash-free operands). ORDER is DIRECTION-
        # DEPENDENT (0.0.45c S4 dev->agent; 0.0.45d W1 restored the
        # reverse for agent->dev — the S4 reorder had closed the
        # dev->agent window but re-opened scan-then-act for `me`):
        #   handover opencode (dev->agent): the tree is dev-owned and
        #   not agent-writable — the find+chmod pass runs FIRST, the
        #   agent cannot swap what it cannot write; chown -R -h runs
        #   LAST, race-free by construction (lchown never
        #   dereferences — a link planted after the scan is re-owned
        #   as the agent's own link, nothing outside the tree,
        #   0.0.44a V24).
        #   handover me (agent->dev): the reclaimed tree is
        #   agent-owned or mixed — chmod FIRST would run while the
        #   agent can still swap a scanned file for a symlink (root
        #   chmod g+w through the link on out-of-tree targets).
        #   chown -R -h to the dev runs FIRST instead: after it no
        #   entry is agent-owned, and on a tree the agent owned
        #   without group write no agent write path remains — the
        #   chmod pass races no one.
        # Inherent residual in EITHER order: any mode-based write
        # path the agent pre-arranged — g+w granted by an earlier
        # handover, or o+w entries it created while it owned the
        # tree (modes on owned entries are owner-controlled) —
        # survives the re-own and keeps those subtrees
        # agent-writable through the run; pre-existing, accepted,
        # not closed by ordering (wording broadened 0.0.45e W2:
        # it was never only the previous-handover g+w case).
        # Plain chmod WOULD follow an operand link — the [ ! -L ]
        # recheck below plus the validation gates are load-bearing
        # for the chmod half's operand; find -P itself skips a link
        # operand (! -type l).
        if [ -L "$_ho_a" ]; then
            ui_error "handover: '$_ho_a' is a symlink — refusing (recursive chown/chmod follow it)"
            _ho_rc=1
            continue
        fi
        # Exec-time component walk (#422): the leaf gates cannot see
        # a PARENT swapped for a symlink since validation — skip loud
        # like the leaf refuse (a skip counts as a failed path, the
        # run continues with the remaining operands).
        if ! _ho_chain_sane "$_ho_a"; then
            ui_error "handover: '$_ho_a' crosses a symlinked path component — refusing (recursive chown/chmod would follow it)"
            _ho_rc=1
            continue
        fi
        if [ "$_ho_target" = opencode ]; then
            # dev->agent: group write while dev-owned, hand over last
            if [ ! -L "$_ho_a" ] &&
                find "$_ho_a" ! -type l -exec chmod g+w {} + 2>/dev/null &&
                chown -R -h "$_ho_user:$_ho_group" "$_ho_a" 2>/dev/null; then
                echo "  handover: $_ho_a -> $_ho_user:$_ho_group"
            else
                ui_error "handover failed: $_ho_a"
                _ho_rc=1
            fi
        else
            # agent->dev: re-own FIRST (no agent write path once
            # every entry is dev's), then grant group write
            if [ ! -L "$_ho_a" ] &&
                chown -R -h "$_ho_user:$_ho_group" "$_ho_a" 2>/dev/null &&
                find "$_ho_a" ! -type l -exec chmod g+w {} + 2>/dev/null; then
                echo "  handover: $_ho_a -> $_ho_user:$_ho_group"
            else
                ui_error "handover failed: $_ho_a"
                _ho_rc=1
            fi
        fi
    done
    [ "$_ho_rc" = 0 ] && ui_success "handover complete"
    exit "$_ho_rc"
}
