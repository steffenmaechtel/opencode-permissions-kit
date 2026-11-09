#!/bin/sh
# opencode permissions kit -- doctor.sh (issue #313, stage 1)
#
# Per-project deep diagnosis for the rootless ownership failure class
# (#312): container processes cannot futimes/chmod/chown files whose
# host uid is UNMAPPED in the daemon's user namespace -- data writes
# still succeed, builds abort with EPERM (gulp/vinyl-fs dest, rsync -t,
# cp -p, tar -xpf). doctor reads the project's opk.json policy (a file
# the project commits; format below and in docs/reference/cli.md) and
# classifies every entry in the declared container trees:
#   mapped-safe  owner is mapped into the daemon userns (the daemon uid
#                or one of its subuid ranges) -> container metadata ops
#                are allowed
#   at-risk      owner unmapped (usually the developer's uid) -> the
#                #312 EPERM class
#
# The mapped ranges come from the LIVE user namespaces, never from
# /etc/subuid -- on the #312 reference host the subuid database is
# empty although the mapping demonstrably exists. Every process carries
# its uid_map in /proc, world-readable; the daemon's own userns and the
# containers nested in it map onto the same host-uid set, so scanning
# the maps whose zero-row points at the daemon user is enough (and it
# needs no docker socket access at all -- #313 open question 2 stays
# open, this is the socket-free primary source). Fallback when no such
# namespace is found (daemon down): daemon-uid-only matching plus an
# explicit "range unverified" warn -- subuid-owned files may then read
# as at-risk until the backend runs again.
#
# The scan is read-only. No sudo: stat, /proc/<pid>/uid_map and
# install.conf are world-readable. Fix rows name the guided remedy
# ('opk doctor fix'); the scan itself never changes a thing.
#
# 'doctor fix' (issue #313, increment b) orchestrates exactly those
# existing remedies: it runs the scan, then offers ONE interactive
# [y/N] prompt (default n) per finding that has an unambiguous remedy --
# a declared, existing, non-symlink directory tree with at-risk entries
# (warnings like missing or symlinked trees have no fix and are never
# offered). A confirmed answer runs 'opk handover opencode <tree>'
# (--dry-run passes through, no prompts, nothing changed). doctor never
# wields sudo itself: the elevation happens inside handover, so no new
# sudoers surface exists. After any executed handover the trees are
# re-checked and the fresh verdict decides the summary.
#
# opk.json -- strict JSON (JSONC was rejected deliberately: jq and
# other tooling must keep reading it, and strict editor validation
# catches malformed policy files; documentation lives in "note"
# fields, not comments). Tolerant read: unknown keys are ignored,
# "version" is reserved for migrations (only 1 exists today).
#
# 'doctor detect' (issue #352 / #313 phase 3) proposes opk.json entries
# from OWNERSHIP EVIDENCE, never from name heuristics: container-written
# entries are the ones whose host uid only a container process can have
# -- mapped subuid twins (the #312 "nobody twin", case C/E) anywhere, and
# daemon-uid entries inside git-ignored (regenerable) paths. Purely
# human-owned trees carry no evidence (the #312 case-A blind spot is
# closed by the handover-me warning instead, not by detect). opk.json is
# a COMMITTED project file: every entry is written only after an
# explicit per-finding [y/N] consent (default n); without consent the
# snippet is printed to paste. Declined findings leave rc 1.
#
# 'doctor all' (#354 / #313 phase 5) runs the scan over EVERY project at
# once: opk.json doubles as the project registration marker -- every
# opk.json found (max 3 levels below a scan root) is one project, one
# FRESH doctor process per DISCOVERED PROJECT (duplicate hits -- a
# project under several scan roots -- spawn one child, the project list
# is deduped). No central registry, no project-name heuristics; 'opk
# status' integration is deliberately deferred (#313 Q3). The full
# contract lives in the all block below.
#
# CLI:  opk doctor [project-root]                 scan (default: cwd, walked
#                                                  up to the nearest opk.json)
#       opk doctor fix [project-root] [--dry-run]  orchestrate the fixes
#       opk doctor detect [project-root]           propose opk.json entries
#       opk doctor all [scan-root]                 one scan per project (the
#                                                  opk.json markers decide)
# Root resolution (#353 / #313 phase 4): without a positional (a plain
# '.' or './' counts as none -- other dot-spellings like './.' are
# explicit roots, #357 a A2) the root is DISCOVERED upward from the cwd
# like git locates .git -- nearest opk.json wins, the used root is
# reported; an explicit positional is authoritative, no discovery.
# Exit codes (the status.sh contract): 0 all declared trees healthy
#      (post-fix, for 'fix'), or detect found nothing / wrote every
#      proposed entry, 1 at-risk finding(s) remain -- declined,
#      dry-run, failed handover, or re-written-before-recheck -- or a
#      rejected policy / degraded-install error (all modes), or detect
#      candidates left undeclared (snippet printed), 2 warning(s) only,
#      64 usage error. 'doctor all' aggregates worst-of across the
#      scanned roots (any alert -> 1, else any warning or nothing
#      scanned -> 2, else 0; the all block owns the details).
#
# Run directly:
#   /usr/local/lib/opencode-permissions-kit/management/doctor.sh [path]
# or from a checkout:
#   files/opencode-permissions-kit-lib/management/doctor.sh [path]
# Deliberately set -u ONLY (no -e): a read-only report -- one failing
# tree must not kill the remaining verdicts (same fail-soft class as
# status.sh).
set -u

# --- shared UI helpers (checkout-first, status.sh pattern) ------------------------
# Caller-dir anchor (#405, review a A2): a streamed stdin run
# (curl ... | sudo sh) has no real $0 — the dirname-$0 lookups below
# (and DOCTOR_OPK's exec in fix mode) would resolve cwd-sibling files,
# unpinned, as root. Pin stdin runs to the deployed library's
# management dir on the FLAT layout; checkout and installed runs keep
# their own dir. A real script path resolves to an existing file, the
# interpreter name does not.
DR_CALL_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
if ! [ -f "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" ]; then
    DR_CALL_DIR="/usr/local/lib/opencode-permissions-kit/management"
fi
UI_LIB="$DR_CALL_DIR/../sh/ui.sh"
[ -f "$UI_LIB" ] || UI_LIB="/usr/local/lib/opencode-permissions-kit/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    # shellcheck disable=SC1090
    . "$UI_LIB"
else
    echo "error: ui.sh not found (expected it next to doctor.sh in a checkout, or in the kit library)" >&2
    exit 1
fi

# Walk-up opk.json discovery (#353 / #313 phase 4) lives in the shared
# leaf lib (the same resolution site bin/opk's handover-me warning
# uses — one implementation, not per-command copies; see path-sane.sh).
# Hard fail like ui.sh: a missing sibling means the deployment is
# broken, and the default root needs the walker.
PS_LIB="$DR_CALL_DIR/../sh/path-sane.sh"
[ -f "$PS_LIB" ] || PS_LIB="/usr/local/lib/opencode-permissions-kit/sh/path-sane.sh"
if [ -f "$PS_LIB" ]; then
    # shellcheck disable=SC1090
    . "$PS_LIB"
else
    ui_error "doctor: path-sane.sh not found (expected it next to doctor.sh in a checkout, or in the kit library)"
    exit 1
fi

# doctor_cntrl_bad <string> -> rc 0 when the string carries control
# CHARACTERS: C0, DEL, or the C1 range 0x80-0x9F -- the same set the
# python validator gates (#370 a C1; round a A1 closed the shell-side
# gap). Two tiers on purpose: a byte-level 0x80-0x9F bracket alone
# cannot tell a raw C1 byte from a UTF-8 TRAIL byte (U+00DC = 0xC3
# 0x9C -- the plain bracket pattern false-positives on legit UTF-8
# roots, measured), so the cheap grep is only the PREFILTER (ctrl or
# any 0x80-0xBF byte -- sufficient because every non-ASCII character
# carries a trail byte in that range; round b B4 sharpened the
# wording, the decision was always equivalent) and the python decoder
# decides at character level: valid UTF-8 passes, undecodable bytes
# fall back to latin-1, where a raw C1 byte stays a control character.
# -I (#249) on every decoder call in this lib: a poisoned
# PYTHONHOME/PYTHONPATH must not break the diagnostics — stdlib-only.
doctor_cntrl_bad() {
    if ! printf '%s' "$1" | LC_ALL=C grep -q "$(printf '[[:cntrl:]\200-\277]')"; then
        return 1
    fi
    printf '%s' "$1" | python3 -I -c '
import sys
data = sys.stdin.buffer.read()
try:
    text = data.decode("utf-8")
except UnicodeDecodeError:
    text = data.decode("latin-1")
sys.exit(0 if any(
    ord(c) < 32 or ord(c) == 127 or 0x80 <= ord(c) <= 0x9F
    for c in text) else 1)
'
}

# doctor_show_sanitize <string> -> display-safe copy on stdout: control
# CHARACTERS removed at character level (round b B1) -- valid UTF-8
# round-trips byte-identical (a byte-range tr strip mangles legit names:
# U+00DF = 0xC3 0x9F loses its trail byte), raw C1 bytes die in the
# decoder. Backslash strips separately where a site needs it.
doctor_show_sanitize() {
    printf '%s' "$1" | python3 -I -c '
import sys
data = sys.stdin.buffer.read()
try:
    text = data.decode("utf-8")
except UnicodeDecodeError:
    text = data.decode("latin-1")
clean = "".join(c for c in text
                if not (ord(c) < 32 or ord(c) == 127
                        or 0x80 <= ord(c) <= 0x9F))
sys.stdout.buffer.write(clean.encode("utf-8", "replace"))
'
}

# --- CLI --------------------------------------------------------------------------
# Strict grammar (#313 increment b): 'fix', 'detect' or 'all' as the FIRST
# token switches the mode; then at most one positional (the project root,
# or the scan root for 'all') plus --dry-run (fix-only -- the scan and
# 'all' are read-only, detect writes only on explicit consent, so a dry
# run of any other mode is a usage error, not a no-op). Everything else
# is rejected with 64.
_doctor_usage() {
    echo "usage: opk doctor [project-root]                   (read-only scan; root: cwd or the nearest opk.json above)" >&2
    echo "       opk doctor all [scan-root]                  (one scan per project: every opk.json below the root(s))" >&2
    echo "       opk doctor fix [project-root] [--dry-run]   (offer the handover fix per at-risk tree)" >&2
    echo "       opk doctor detect [project-root]            (propose opk.json entries from evidence)" >&2
}
DOCTOR_MODE=scan
if [ "${1:-}" = "fix" ] || [ "${1:-}" = "detect" ] || [ "${1:-}" = "all" ]; then
    DOCTOR_MODE="$1"
    shift
fi
DOCTOR_ROOT=""
DOCTOR_ROOT_ARG=""
DOCTOR_FIX_DRY=0
for _do_arg in "$@"; do
    case "$_do_arg" in
        --dry-run)
            if [ "$DOCTOR_MODE" != "fix" ]; then
                _doctor_usage
                echo "error: doctor: --dry-run needs 'fix' (the scan and 'all' are read-only; detect writes only on consent)" >&2
                exit 64
            fi
            DOCTOR_FIX_DRY=1
            ;;
        -*)
            _doctor_usage
            echo "error: doctor: unknown flag '$_do_arg'" >&2
            exit 64
            ;;
        *)
            if [ -z "$_do_arg" ]; then
                # (#370 a C6): an empty root argument is a usage error,
                # not walk-up discovery -- a scripted $ROOT-unset
                # invocation ("opk doctor \"\"") silently scanned the
                # wrong tree instead of failing its caller's contract.
                _doctor_usage
                echo "error: doctor: the project root must not be empty" >&2
                exit 64
            fi
            if [ -n "$DOCTOR_ROOT" ]; then
                _doctor_usage
                echo "error: doctor: only one project root allowed" >&2
                exit 64
            fi
            DOCTOR_ROOT="$_do_arg"
            DOCTOR_ROOT_ARG="$_do_arg"
            ;;
    esac
done
DOCTOR_ROOT="${DOCTOR_ROOT:-.}"
# (#370 a C7): command substitution strips a TRAILING newline off the
# root before every control-byte gate below -- doctor would silently
# operate on a DIFFERENT tree than the argument named (a directory
# "x\n" reads as "x"). A newline ANYWHERE in the operand refuses
# loudly instead; the wc -l probe counts complete lines, so any
# embedded newline trips it while plain spellings stay at 0.
if [ "$(printf '%s' "$DOCTOR_ROOT" | wc -l)" -gt 0 ]; then
    _doctor_usage
    echo "error: doctor: the project root must not contain newlines" >&2
    exit 64
fi
DOCTOR_ROOT="$(realpath -m "$DOCTOR_ROOT" 2>/dev/null || printf '%s' "$DOCTOR_ROOT")"
# (#357 a A1): the fallback arm re-feeds the RAW argument -- with
# realpath absent or failing (deleted cwd) that is a relative path, and
# the walk-up below must never receive one: the walker refuses
# slash-less input (its belt), but a relative path with slashes would
# silently walk the wrong chain. cd+pwd is the shell-native
# normalization for an existing directory (the -d gate below has not
# run yet -- a cd failure leaves the raw value to that gate; when even
# cd fails, the walker's belt ends the attempt without a hang).
case "$DOCTOR_ROOT" in
    /*) ;;
    *)
        _dr_norm="$(cd "$DOCTOR_ROOT" 2>/dev/null && pwd)" &&
            DOCTOR_ROOT="$_dr_norm"
        ;;
esac
if [ ! -d "$DOCTOR_ROOT" ]; then
    ui_error "doctor: no such directory: $DOCTOR_ROOT"
    exit 64
fi

# --- multi-project marker scan (#354 / #313 phase 5) ---------------------------------
# 'doctor all' scans EVERY project at once: opk.json doubles as the
# project registration marker, so projects are DISCOVERED, never
# configured --
#   find <scan-root> -maxdepth 3 -name opk.json   ->  one doctor per root
# (the /var/www/vhosts/<org>/<project> layout resolves itself: no
# opk.json, no project -- no central registry, no name heuristics; a
# marker nested deeper than 3 levels below a scan root is not a project
# here). A marker is a REGULAR FILE THROUGH SYMLINKS ([ -f ], the
# walk-up rule, #353): a directory or a dangling symlink named opk.json
# is not a marker (#360 a F12). Scan roots, first arm that applies:
#   - an explicit positional: exactly that tree (defaults stay out)
#   - $OPK_DOCTOR_SCAN_ROOTS (test seam, the OPK_INSTALL_CONF pattern):
#     a file with one root per line, replacing the whole default list;
#     SET (even to an empty value) selects this arm -- an empty value is
#     an empty root list, never a fall-back to the real default roots
#     (#360 a F6)
#   - /var/www/vhosts when it exists, plus every root registered in the
#     kit's own projects.conf (reading the EXISTING registry is not
#     building a new one; its entries are often parents of several
#     projects and get the same maxdepth walk)
# ORCHESTRATION: a thin loop here spawning a FRESH process per
# DISCOVERED PROJECT (sh "$0" <root>; the project list is deduped, so a
# project found under several roots spawns ONE child, #360 a F2) --
# doctor.sh is single-process-per-root by design (mktemp $WORK, EXIT
# trap, ui counters are per-run state), so 'all' never re-enters this
# process and never reaches that machinery below. Scan roots are
# NORMALIZED (the positional above via realpath, list roots in the loop
# below), which already resolves a symlinked root to its real tree; the
# finds run -H as the BELT for the realpath-absent fallback (#360 b S3).
# Nested symlinks are not descended -- a project directory that is
# itself a symlink gets a warn row instead (#360 a F11).
# fix/detect deliberately do not combine with 'all' (their per-finding
# prompts assume one project in focus): 'all' joins 'fix'/'detect' as a
# reserved first token, and the arg loop above keeps everything else
# away. Exit-code aggregation, worst-of in the status.sh severity
# order: any root alerting (rc 1) or failing outright (a child rc
# outside 0/1/2 -- counted as an alert with its own warn row) -> 1;
# otherwise any root warning-only, or nothing scanned at all (no usable
# scan root, or no markers under them) -> 2; otherwise 0.
INSTALL_CONF="${OPK_INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}"
if [ "$DOCTOR_MODE" = "all" ]; then
    # kit pre-flight (one loud error instead of one per child): children
    # re-check everything themselves -- this only keeps a degraded
    # install from printing its error once per discovered project.
    if [ ! -f "$INSTALL_CONF" ]; then
        ui_error "doctor: $INSTALL_CONF not found -- is the kit installed?"
        exit 1
    fi
    # a scan root of '/' would walk the whole filesystem's top levels --
    # refuse it like 'detect' does for its walk
    if [ "$DOCTOR_ROOT" = "/" ] && [ -n "$DOCTOR_ROOT_ARG" ]; then
        ui_error "doctor: refusing to scan the whole filesystem (scan root '/')"
        exit 64
    fi
    PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
    # shellcheck disable=SC2317  # invoked via trap only
    _doctor_all_cleanup() { rm -rf "$WORK_ALL"; }
    # fail loud on a dead workspace (#360 a F5): an empty WORK_ALL would
    # collapse every path below to root-level literals (/roots, /hits ...)
    WORK_ALL="$(mktemp -d)" || {
        ui_error "doctor: cannot create a temp dir (mktemp failed) -- is \$TMPDIR writable?"
        exit 1
    }
    trap _doctor_all_cleanup EXIT
    trap '_doctor_all_cleanup; exit 1' INT TERM

    # --- the scan-root list (positional > seam > defaults) ---------------------------
    : >"$WORK_ALL/roots"
    if [ -n "$DOCTOR_ROOT_ARG" ]; then
        printf '%s\n' "$DOCTOR_ROOT" >>"$WORK_ALL/roots"
    elif [ "${OPK_DOCTOR_SCAN_ROOTS+set}" = set ]; then
        # set (even empty) OWNS the list: never a silent fall-back to the
        # real /var/www/vhosts -- an empty value is an empty list (#360 a F6)
        if [ -z "$OPK_DOCTOR_SCAN_ROOTS" ]; then
            :
        elif [ ! -f "$OPK_DOCTOR_SCAN_ROOTS" ] || [ ! -r "$OPK_DOCTOR_SCAN_ROOTS" ]; then
            # -f, not just -r: a directory would pass -r and die later in
            # the grep (#360 a F7)
            ui_error "doctor: OPK_DOCTOR_SCAN_ROOTS is set but not a readable file: $OPK_DOCTOR_SCAN_ROOTS"
            exit 1
        else
            # -a (round a A1): a line carrying a raw C1 byte makes GNU
            # grep deem the whole list BINARY -- it then prints "binary
            # file matches" and delivers NO lines, so the per-root gate
            # below never sees the offending root. --text keeps the
            # line stream intact; the gate refuses it sanitized.
            grep -a -v '^[[:space:]]*$' "$OPK_DOCTOR_SCAN_ROOTS" >>"$WORK_ALL/roots" || true
        fi
    else
        [ -d /var/www/vhosts ] && printf '%s\n' /var/www/vhosts >>"$WORK_ALL/roots"
        if [ -f "$PROJECTS_CONF" ]; then
            if [ -r "$PROJECTS_CONF" ]; then
                grep -a -v '^[[:space:]]*$' "$PROJECTS_CONF" >>"$WORK_ALL/roots" || true
            else
                ui_kv_warn "scan root" "$PROJECTS_CONF unreadable -- its roots are not scanned"
            fi
        fi
    fi
    LC_ALL=C sort -u "$WORK_ALL/roots" >"$WORK_ALL/roots.s" && mv "$WORK_ALL/roots.s" "$WORK_ALL/roots"
    # (round b B2): a NUL byte in a list line is invisible to POSIX
    # read -- it drops the byte silently and the STRIPPED spelling would
    # flow through every gate with no warn row, contradicting the doc
    # (NUL is a control character). NUL cannot ride a shell variable,
    # so swap it for STX BEFORE the loop; the loop refuses STX-carrying
    # lines loudly (doctor_show_sanitize strips STX from the display).
    # (round c C2): the swap itself fails LOUD -- a silent skip would
    # return exactly the bug this closes (tr fails -> unswapped roots
    # -> read strips the NUL with no row).
    _da_stx="$(printf '\002')"
    if ! tr '\000' '\002' <"$WORK_ALL/roots" >"$WORK_ALL/roots.t"; then
        ui_error "doctor: cannot process the scan-root list (tr failed) -- refusing to scan"
        exit 1
    fi
    mv "$WORK_ALL/roots.t" "$WORK_ALL/roots"

    # --- marker discovery: one project root per opk.json found ----------------------
    ALL_ROOTS_N=0
    ALL_ROOTS_USED=0
    ALL_MARK_SKIP=0
    : >"$WORK_ALL/projects"
    while IFS= read -r _da_root; do
        [ -n "$_da_root" ] || continue
        ALL_ROOTS_N=$((ALL_ROOTS_N + 1))
        case "$_da_root" in
            *"$_da_stx"*)
                # (round c C3): after the NUL->STX swap a hit is either
                # a swapped NUL or a pre-existing literal STX (argv
                # roots join the same list) -- name both, the display
                # strips the byte either way
                _da_show="$(doctor_show_sanitize "$_da_root")"
                ui_kv_warn "scan root" "list line carries a NUL or STX byte -- skipped: '$_da_show'"
                continue
                ;;
        esac
        # RAW-line absolute gate FIRST (#370 a C3): the absolute check
        # must see the hand-edited line itself -- behind realpath -m a
        # relative spelling lands cwd-anchored and ABSOLUTE, so a gate
        # BELOW the normalization was near-unreachable (realpath-present
        # hosts silently scanned the cwd-anchored tree instead of
        # warning; only the realpath-absent fallback ever tripped).
        case "$_da_root" in
            /*) ;;
            *)
                ui_kv_warn "scan root" "'$_da_root' is not an absolute path -- skipped (list roots must be absolute)"
                continue
                ;;
        esac
        # normalization second (#360 b S1, c S1): '//' and '/./'
        # spellings hit the '/' belt below instead of walking the whole
        # filesystem, and the fragment gate's absolute-prefix assumption
        # holds. Every gate below sees the FINAL value: a clean line
        # resolving through a symlink to a cntrl/backslash-carrying
        # target is caught AFTER normalization too (#360 c S1 -- the
        # raw-line gate above screens the spelling, this one the
        # resolution).
        _da_root="$(realpath -m "$_da_root" 2>/dev/null || printf '%s' "$_da_root")"
        # root gate (#360 a F8, class completed round a A1): control
        # bytes or a backslash make the root unusable as a find operand
        # AND clobber the rows -- warn sanitized, skip
        if printf '%s' "$_da_root" | LC_ALL=C grep -qF '\' ||
            doctor_cntrl_bad "$_da_root"; then
            _da_show="$(doctor_show_sanitize "$_da_root" | tr -d '\\')"
            ui_kv_warn "scan root" "'$_da_show' carries control characters or backslashes -- skipped"
            continue
        fi
        # belt for list-sourced roots (the positional '/' is refused with
        # 64 above): one heavy misconfigured root must not kill the fleet.
        # The explicit spellings cover the direct '/'-aliases for the
        # realpath-absent fallback; deeper aliases ('/a/..') remain a
        # fallback-arm residual -- realpath-present hosts normalize them
        # onto the '/' arm (#360 c S3).
        case "$_da_root" in
            / | // | /// | /. | /./ | /.. | /../)
                ui_kv_warn "scan root" "'$_da_root' refused -- doctor all does not walk the whole filesystem"
                continue
                ;;
        esac
        if [ ! -d "$_da_root" ]; then
            if [ -e "$_da_root" ]; then
                # (#370 a C4): an existing NON-directory is not
                # "missing" -- the row must not lie about the tree
                ui_kv_warn "scan root" "'$_da_root' is not a directory -- skipped"
            else
                ui_kv_warn "scan root" "'$_da_root' is missing -- skipped"
            fi
            continue
        fi
        ALL_ROOTS_USED=$((ALL_ROOTS_USED + 1))
        # stderr is loud, not lost (the unreadable-subtree class): a
        # partially walked root must not read as "no markers here". Both
        # finds (markers + the symlink pass) feed the same error file.
        find -H "$_da_root" -maxdepth 3 -name opk.json -print \
            >"$WORK_ALL/hits" 2>"$WORK_ALL/ferr"
        find -H "$_da_root" -maxdepth 2 -type l -print >"$WORK_ALL/links" 2>>"$WORK_ALL/ferr"
        if [ -s "$WORK_ALL/ferr" ]; then
            _da_n="$(wc -l <"$WORK_ALL/ferr")"
            ui_kv_warn "scan root" "$_da_n unreadable entries under $_da_root -- marker list may be incomplete"
            ui_detail "run 'doctor all' as the tree owner (or with sudo) for a complete picture"
        fi
        # fragment integrity (#360 a F1): find -print and read share the
        # NEWLINE as their separator -- a newline inside a name splits the
        # hit BEFORE any gate, and the fragments would spawn phantom or
        # cwd-relative children. A genuine hit always carries the root
        # prefix and the /opk.json suffix; a fragment can never carry
        # both (the prefix lives at the path start, the suffix at its
        # end -- a split puts them on different fragments)
        _da_pfx="${_da_root%/}/"
        while IFS= read -r _da_hit; do
            [ -n "$_da_hit" ] || continue
            _da_corrupt=0
            case "$_da_hit" in
                "$_da_pfx"*) ;;
                *) _da_corrupt=1 ;;
            esac
            case "$_da_hit" in
                */opk.json) ;;
                *) _da_corrupt=1 ;;
            esac
            if [ "$_da_corrupt" = 1 ]; then
                _da_show="$(doctor_show_sanitize "$_da_hit")"
                ui_kv_warn "scan root" "corrupted marker path '$_da_show' skipped (a newline in a name under $_da_root?)"
                ALL_MARK_SKIP=$((ALL_MARK_SKIP + 1))
                continue
            fi
            # marker-type gate (#360 a F12): the walk-up rule -- a regular
            # file through symlinks; anything else (a directory, a
            # dangling symlink, a link to a directory) is not a marker
            if [ ! -f "$_da_hit" ]; then
                _da_show="$(doctor_show_sanitize "$_da_hit")"
                ui_kv_warn "scan root" "'$_da_show' is not a regular file through symlinks -- not a marker (the walk-up rule)"
                ALL_MARK_SKIP=$((ALL_MARK_SKIP + 1))
                continue
            fi
            _da_proj="$(dirname "$_da_hit")"
            # marker gate (detect's charset class, completed round a A1):
            # control characters or backslashes cannot round-trip child
            # argv, rows and prompts cleanly -- warn sanitized, skip,
            # never a silent drop
            if printf '%s' "$_da_proj" | LC_ALL=C grep -qF '\' ||
                doctor_cntrl_bad "$_da_proj"; then
                _da_show="$(doctor_show_sanitize "$_da_proj" | tr -d '\\')"
                ui_kv_warn "scan root" "marker at '$_da_show' skipped -- control characters or backslashes in the path"
                ALL_MARK_SKIP=$((ALL_MARK_SKIP + 1))
                continue
            fi
            printf '%s\n' "$_da_proj" >>"$WORK_ALL/projects"
        done <"$WORK_ALL/hits"
        # symlink pass (#360 a F11): -H follows only the ROOT operand, so
        # a project directory that is itself a symlink is never descended
        # -- find produced no hit and no error for it. Warn precisely: only
        # links that DO carry a marker ([ -f ] resolves through the link)
        while IFS= read -r _da_link; do
            [ -n "$_da_link" ] || continue
            [ -f "$_da_link/opk.json" ] || continue
            ui_kv_warn "scan root" "symlinked project '$_da_link' is not descended -- pass the real directory"
        done <"$WORK_ALL/links"
    done <"$WORK_ALL/roots"
    LC_ALL=C sort -u "$WORK_ALL/projects" >"$WORK_ALL/projects.s" &&
        mv "$WORK_ALL/projects.s" "$WORK_ALL/projects"

    # --- one fresh doctor per project -----------------------------------------------
    # Test seam (OPK_DOCTOR_SELF): production spawns THIS script ($0);
    # tests stub a failing child to pin the aggregation's error arm
    # (#360 a F4, the OPK_DOCTOR_OPK pattern)
    DOCTOR_ALL_SELF="${OPK_DOCTOR_SELF:-$0}"
    ALL_N=0
    ALL_GREEN=0
    ALL_WARN=0
    ALL_ALERT=0
    ALL_ERR=0
    if [ -s "$WORK_ALL/projects" ]; then
        ui_section "Doctor all -- one scan per project"
        while IFS= read -r _da_proj; do
            [ -n "$_da_proj" ] || continue
            ALL_N=$((ALL_N + 1))
            ui_kv "project" "$_da_proj"
            _da_rc=0
            sh "$DOCTOR_ALL_SELF" "$_da_proj" || _da_rc=$?
            case "$_da_rc" in
                0) ALL_GREEN=$((ALL_GREEN + 1)) ;;
                1) ALL_ALERT=$((ALL_ALERT + 1)) ;;
                2) ALL_WARN=$((ALL_WARN + 1)) ;;
                *)
                    ALL_ERR=$((ALL_ERR + 1))
                    ui_kv_warn "project" "doctor exited $_da_rc -- counted as an alert"
                    ;;
            esac
        done <"$WORK_ALL/projects"
    fi

    # --- aggregate summary (worst-of, the contract in the block comment) -------------
    ui_section "Doctor all -- summary"
    if [ "$ALL_N" -eq 0 ]; then
        if [ "$ALL_ROOTS_USED" -eq 0 ]; then
            if [ "$ALL_ROOTS_N" -eq 0 ]; then
                ui_kv_warn "result" "no scan roots available -- pass one, or use the /var/www/vhosts layout or projects.conf"
            else
                ui_kv_warn "result" "no scan root could be scanned -- every listed root is missing or unusable"
            fi
        elif [ "$ALL_MARK_SKIP" -gt 0 ]; then
            ui_kv_warn "result" "all $ALL_MARK_SKIP marker(s) skipped -- nothing to check"
        else
            ui_kv_warn "result" "no opk.json markers found under the scanned root(s) -- nothing to check"
        fi
        exit 2
    fi
    ui_kv "projects" "$ALL_N scanned under $ALL_ROOTS_USED scan root(s)"
    [ "$ALL_ERR" -gt 0 ] &&
        ui_kv_bad "failed" "$ALL_ERR scan(s) exited unexpectedly (counted as alerts)"
    [ "$ALL_ALERT" -gt 0 ] &&
        ui_kv_bad "findings" "$ALL_ALERT project(s) with at-risk findings"
    [ "$ALL_WARN" -gt 0 ] &&
        ui_kv_warn "warnings" "$ALL_WARN project(s) warnings only"
    [ "$ALL_GREEN" -gt 0 ] &&
        ui_kv_ok "healthy" "$ALL_GREEN project(s) all green"
    if [ $((ALL_ALERT + ALL_ERR)) -gt 0 ]; then
        exit 1
    fi
    if [ "$ALL_WARN" -gt 0 ]; then
        exit 2
    fi
    exit 0
fi

# --- walk-up opk.json discovery (#353 / #313 phase 4) ------------------------------
# Without a root argument (a plain '.' counts as none), doctor works
# from anywhere INSIDE the project: search upward from the invocation
# dir for the nearest opk.json -- like git locates .git, first hit
# wins, filesystem root is the stop (opk.json is the project marker,
# #313 phase 5; no .git boundary -- the policy is deliberately
# git-independent). The discovered root governs EVERYTHING below
# (policy read, tree paths, detect's write) and is reported: the
# header names it plus the dir the walk started from, so the used root
# stays visible in every mode's output. An EXPLICIT positional stays
# authoritative -- no discovery: a named root with no opk.json keeps
# the v1 warning (scripting predictability; the tree paths you
# declared resolve against exactly the root you named).
# DOCTOR_WALKED marks that a walk was ATTEMPTED -- set before the walk
# runs and regardless of its outcome (#357 a C2 comment truth); its
# only consumer sits inside the no-policy branch below, so it matters
# exactly when the walk found nothing, and the warning then says what
# was searched.
DOCTOR_START_DIR=""
DOCTOR_DISCOVERED=0
DOCTOR_WALKED=0
case "$DOCTOR_ROOT_ARG" in
    "" | . | ./)
        DOCTOR_START_DIR="$DOCTOR_ROOT"
        DOCTOR_WALKED=1
        if _dr_root="$(opk_policy_root "$DOCTOR_ROOT")"; then
            if [ "$_dr_root" != "$DOCTOR_ROOT" ]; then
                DOCTOR_ROOT="$_dr_root"
                DOCTOR_DISCOVERED=1
            fi
        fi
        ;;
esac

# detect walks the WHOLE project from the root (scan/fix walk declared
# trees only, bounded by the policy) -- the filesystem root is never a
# project; refuse it loudly like the ddev handover walks do
if [ "$DOCTOR_MODE" = "detect" ] && [ "$DOCTOR_ROOT" = "/" ]; then
    ui_error "doctor: refusing to walk the whole filesystem (detect on '/')"
    exit 64
fi
# (#356 a B4; class completed round a A1 via doctor_cntrl_bad): a
# detect root carrying control characters or a backslash
# classifies NOTHING -- the boundary awk's root-prefix match never hits
# (a TAB root splits find rows, a backslash root is mangled by awk -v
# escape processing) -- and the run reads "no evidence found", the
# fail-absent shape this block refuses loudly everywhere else. The fix
# gate above (#348 a C3) covers the same class for the TSV round-trip;
# detect needs it for the walk itself.
if [ "$DOCTOR_MODE" = "detect" ] &&
    { printf '%s' "$DOCTOR_ROOT" | LC_ALL=C grep -qF '\' || doctor_cntrl_bad "$DOCTOR_ROOT"; }; then
    ui_error "doctor: project root contains control characters or backslashes -- unusable for 'detect'"
    exit 64
fi
# Fix-mode only (#348 a C3): the candidate round-trip ($WORK/fixcand) is
# TAB/LF-separated TSV, and $DOCTOR_TREE embeds DOCTOR_ROOT -- a control
# byte in the root would truncate the handover operand away from the
# tree the [y/N] prompt named. The opk.json fields are gated by the
# python validator; the root comes from the CLI/cwd and is gated here.
# Scan mode needs no OPERAND round-trip: the counts pass feeds find's
# uid-only output, and the examples pass (a TAB TSV) degrades display
# rows only -- verdict and rc stay intact (#344 a S1/S2 class).
if [ "$DOCTOR_MODE" = "fix" ] &&
    doctor_cntrl_bad "$DOCTOR_ROOT"; then
    ui_error "doctor: project root contains control characters -- unusable for 'fix' (candidate round-trip)"
    exit 64
fi

# --- the opk dispatcher for fix mode ----------------------------------------------
# doctor fix orchestrates the EXISTING remedy and never elevates itself:
# each confirmed fix runs 'opk handover opencode <tree>' and handover
# does its own sudo hop -- no new sudoers surface (#313 increment b).
# Resolved like ui.sh: checkout-first, then the deployed library.
# OPK_DOCTOR_OPK overrides for tests only (same seam pattern as
# OPK_INSTALL_CONF / OPK_DOCTOR_PROC_ROOT).
DOCTOR_OPK="${OPK_DOCTOR_OPK:-}"
if [ "$DOCTOR_MODE" = "fix" ] && [ -z "$DOCTOR_OPK" ]; then
    DOCTOR_OPK="$DR_CALL_DIR/../bin/opk"
    [ -f "$DOCTOR_OPK" ] || DOCTOR_OPK="/usr/local/lib/opencode-permissions-kit/bin/opk"
fi
if [ "$DOCTOR_MODE" = "fix" ] && [ ! -f "$DOCTOR_OPK" ]; then
    ui_error "doctor: cannot find the opk dispatcher (needed for 'fix')"
    ui_detail "expected it next to doctor.sh in a checkout, or in the kit library; set OPK_DOCTOR_OPK to override"
    exit 1
fi

# --- the daemon user (the rootless backend runs as this user) --------------------
# INSTALL_CONF resolves above (the 'all' block shares it)
if [ ! -f "$INSTALL_CONF" ]; then
    ui_error "doctor: $INSTALL_CONF not found -- is the kit installed?"
    exit 1
fi
# sed, not source: doctor needs one key, and a sourced conf must not be
# able to shadow the script's own variables. Quotes are stripped in case
# a future writer quotes the value (handover reads it unquoted today).
DOCTOR_USER="$(sed -n 's/^OPENCODE_USER=//p' "$INSTALL_CONF" | tail -1 | sed 's/^"//;s/"$//')"
if [ -z "$DOCTOR_USER" ]; then
    ui_error "doctor: install.conf has no OPENCODE_USER -- is the kit installed?"
    exit 1
fi
DOCTOR_DAEMON_UID="$(id -u "$DOCTOR_USER" 2>/dev/null || true)"
if [ -z "$DOCTOR_DAEMON_UID" ]; then
    ui_error "doctor: user '$DOCTOR_USER' (OPENCODE_USER) does not exist"
    exit 1
fi

# --- resolve the mapped host-uid set ----------------------------------------------
# Test seam (unit tests fixture the pid tree; production always reads
# the live /proc -- same override pattern as OPK_INSTALL_CONF).
DOCTOR_PROC="${OPK_DOCTOR_PROC_ROOT:-/proc}"

# fail loud on a dead workspace (#361): this script is set -u ONLY (no
# -e -- one failing tree must not kill the remaining verdicts), so an
# empty WORK from a failed mktemp would NOT abort here but collapse
# every path below to a root-level literal (/ranges, /trees, /uids ...)
# -- the #360 a F5 class, sibling of the all-block guard above
WORK="$(mktemp -d)" || {
    ui_error "doctor: cannot create a temp dir (mktemp failed) -- is \$TMPDIR writable?"
    exit 1
}
# Signal handlers EXIT (#344 a C1): a non-exiting INT/TERM handler runs the
# cleanup and dash RESUMES the script — with $WORK already deleted, every
# later redirect fails and the remaining trees render cascade garbage. The
# house shape (install.sh, update.sh, config.sh): cleanup on EXIT, cleanup
# PLUS exit on the signals.
# shellcheck disable=SC2317  # invoked via trap only
_doctor_cleanup() { rm -rf "$WORK"; }
trap _doctor_cleanup EXIT
trap '_doctor_cleanup; exit 1' INT TERM

# doctor_userns_ranges <proc_root> <daemon_uid>
# Prints one "start:count" line per mapped host-uid range found in any
# live user namespace whose zero row maps to the daemon user. Shape
# rules (validated per row, the whole file is dropped on any violation):
#   - rows are three integers: ns-uid, host-uid, count
#   - the FIRST row must map ns-uid 0 to the daemon uid (the daemon's
#     own userns and its containers do; a foreign user's namespace does
#     not -- its 0 maps to THEIR uid)
#   - the full map (count 4294967295) is the init namespace: skipped
# Buffer-then-emit: rows of a file that violates later must not leak.
doctor_userns_ranges() {
    _du_root="$1"
    _du_uid="$2"
    for _du_map in "$_du_root"/[0-9]*/uid_map; do
        [ -f "$_du_map" ] || continue
        _du_ok=1
        _du_row0=0
        _du_buf=""
        while read -r _du_in _du_out _du_cnt _du_extra; do
            [ -n "$_du_in" ] || continue
            # kernel writes these files; still, only digits ever reach
            # the buffer (the ranges feed awk as data)
            case "${_du_in}${_du_out}${_du_cnt}" in
                *[!0-9]*)
                    _du_ok=0
                    break
                    ;;
            esac
            if [ -z "$_du_out" ] || [ -z "$_du_cnt" ] || [ -n "$_du_extra" ]; then
                _du_ok=0
                break
            fi
            if [ "$_du_row0" = 0 ]; then
                if [ "$_du_in" != 0 ] || [ "$_du_out" != "$_du_uid" ]; then
                    _du_ok=0
                    break
                fi
                # the init namespace maps everything -- not a daemon userns
                [ "$_du_cnt" = 4294967295 ] && _du_ok=0
                _du_row0=1
            fi
            _du_buf="$_du_buf $_du_out:$_du_cnt"
        done <"$_du_map" 2>/dev/null || continue
        if [ "$_du_ok" = 1 ] && [ -n "$_du_buf" ]; then
            # shellcheck disable=SC2086  # buffer charset: [0-9: ] only, validated above
            printf '%s\n' $_du_buf
        fi
    done
}

doctor_userns_ranges "$DOCTOR_PROC" "$DOCTOR_DAEMON_UID" | sort -u >"$WORK/ranges.raw"
DOCTOR_RANGE_VERIFIED=0
[ -s "$WORK/ranges.raw" ] && DOCTOR_RANGE_VERIFIED=1
# The daemon uid itself is always mapped (container root is the daemon
# user host-side) -- the fallback floor when no namespace was found.
# Appended only when no live range already starts at the daemon uid
# (#344 a C5): a daemon namespace mapping count>1 there would otherwise
# survive sort -u next to the floor row and display the uid twice.
if ! awk -F: -v u="$DOCTOR_DAEMON_UID" '$1 == u { found = 1 } END { exit !found }' "$WORK/ranges.raw"; then
    printf '%s:1\n' "$DOCTOR_DAEMON_UID" >>"$WORK/ranges.raw"
fi
sort -u "$WORK/ranges.raw" >"$WORK/ranges"
# one "start count" pair list for awk ("1001 1 165536 65536")
DOCTOR_RANGES="$(awk -F: '{ printf "%s %s ", $1, $2 }' "$WORK/ranges")"

# --- report header ----------------------------------------------------------------
ui_section "Doctor -- container-tree ownership (#312 class)"
ui_kv "project root" "$DOCTOR_ROOT"
if [ "$DOCTOR_DISCOVERED" = 1 ]; then
    ui_kv "root via" "walk-up from $DOCTOR_START_DIR (nearest opk.json)"
fi
if [ "$DOCTOR_MODE" = "fix" ]; then
    if [ "$DOCTOR_FIX_DRY" = 1 ]; then
        ui_kv "mode" "fix --dry-run (show the handover plan, change nothing)"
    else
        ui_kv "mode" "fix (offer handover per at-risk tree, [y/N] each)"
    fi
elif [ "$DOCTOR_MODE" = "detect" ]; then
    ui_kv "mode" "detect (propose opk.json entries from ownership evidence)"
fi
ui_kv "daemon user" "$DOCTOR_USER (uid $DOCTOR_DAEMON_UID)"
if [ "$DOCTOR_RANGE_VERIFIED" = 1 ]; then
    ui_kv "mapped range" "$(awk -F: '
        { if ($2 == 1) printf "%s%s", sep, $1
          else printf "%s%s-%s", sep, $1, $1 + $2 - 1
          sep = ", " }' "$WORK/ranges") -- live uid_map"
else
    ui_kv_warn "mapped range" "unverified -- no user namespace of '$DOCTOR_USER' found (backend down?)"
    ui_detail "matching the daemon uid only; subuid-owned files may classify at-risk"
    ui_detail "until the backend runs -- re-run doctor with the containers up"
fi

# --- load the policy ---------------------------------------------------------------
# Scan/fix REQUIRE a policy (nothing to check without one -- exit 2 with
# the detect hint, #352 maintainer comment). Detect works WITHOUT one (a
# fresh project is its use case): an absent file is normal there and the
# declared set is simply empty.
DOCTOR_POLICY_PRESENT=1
if [ ! -f "$DOCTOR_ROOT/opk.json" ]; then
    DOCTOR_POLICY_PRESENT=0
    if [ "$DOCTOR_MODE" != "detect" ]; then
        # A walk ran and found nothing (default invocation): say what was
        # searched -- "strict-cwd" would be a lie since phase 4. Explicit
        # roots keep the plain v1 text (nothing was searched above them).
        if [ "$DOCTOR_WALKED" = 1 ]; then
            ui_warn "no opk.json found in $DOCTOR_ROOT (searched upward to /) -- nothing to check"
        else
            ui_warn "no opk.json found in $DOCTOR_ROOT -- nothing to check"
        fi
        ui_detail "declare the trees your container builds write to (docs/reference/cli.md, 'doctor')"
        ui_detail "or run 'opk doctor detect' to propose entries from ownership evidence"
        exit 2
    fi
    # detect without a policy is normal (fresh project): the declared
    # set is simply empty and every finding is new
    ui_kv "policy" "none yet -- detect will propose one (entries are written only on consent)"
else
    ui_kv "policy" "$DOCTOR_ROOT/opk.json"
fi

# doctor_load_policy <root>
# Validates opk.json (strict JSON) and prints one "path<TAB>note" line
# per declared container tree. python3 does shape validation -- the
# paths reach find as argv below, so they are allowlisted here, not
# just read (shell-security convention). Failures print "opk.json: ..."
# to stderr and exit non-zero.
doctor_load_policy() {
    python3 -I - "$1/opk.json" <<'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        doc = json.load(f)
except OSError as e:
    sys.stderr.write("opk.json: unreadable: %s\n" % e)
    sys.exit(1)
except ValueError as e:
    sys.stderr.write("opk.json: not valid JSON: %s\n" % e)
    sys.exit(1)

def bad(msg):
    sys.stderr.write("opk.json: %s\n" % msg)
    sys.exit(1)

if not isinstance(doc, dict):
    bad("top level must be a JSON object")
# Strict version typing (#344 a C4): Python coerces True == 1 and 1.0 == 1,
# so a bare != would accept JSON true/1.0 as "version 1"
version = doc.get("version", 1)
if isinstance(version, bool) or not isinstance(version, int) or version != 1:
    bad("unsupported version %r -- this kit reads version 1" % (version,))
trees = doc.get("containerTrees", [])
if not isinstance(trees, list):
    bad("containerTrees must be an array")

def _cntrl(c):
    # C0 AND the 8-bit control sets (#370 a C1): DEL (0x7F) and the C1
    # range (0x80-0x9F) carry the same display-injection class (8-bit
    # CSI sequences reach ui rows and prompts) as the C0 range -- the
    # message says "control characters", the gate must mean it.
    o = ord(c)
    return o < 32 or o == 127 or 0x80 <= o <= 0x9F


def path_error(p):
    if not isinstance(p, str) or not p:
        return "tree path must be a non-empty string"
    if p.startswith("/") or p == ".":
        return "tree path %r must be relative to the project root" % p
    if "\\" in p:
        return "tree path %r must not contain backslashes" % p
    if any(_cntrl(ch) for ch in p):
        return "tree path %r must not contain control characters" % p
    # Shell-significant characters (#344 a S3; rationale updated #356 a
    # A5 -- the copy-paste sudo hint is gone, but policy paths still
    # flow into fix-mode prompts and the 'would run:'/'running:' rows):
    # a committed opk.json must never be able to steer those
    if any(c in p for c in "'\"`$;"):
        return "tree path %r must not contain shell-significant characters: quotes, backtick, dollar, semicolon" % p
    for comp in p.split("/"):
        if comp in ("", ".", ".."):
            return "tree path %r must not contain empty, '.' or '..' components" % p
        if any(c in comp for c in "*?["):
            return "tree path %r must not contain glob characters (no wildcards)" % p
    return None

for i, entry in enumerate(trees):
    if isinstance(entry, str):
        rel, note = entry, ""
    elif isinstance(entry, dict):
        rel, note = entry.get("path"), entry.get("note", "")
        if rel is None:
            bad('containerTrees[%d]: missing "path"' % i)
    else:
        bad("containerTrees[%d]: must be a string or an object" % i)
    err = path_error(rel)
    if err:
        bad("containerTrees[%d]: %s" % (i, err))
    if not isinstance(note, str):
        bad('containerTrees[%d]: "note" must be a string' % i)
    # Collapse first (tabs/newlines would break the TSV round-trip), then
    # gate control characters (#344 a S4): the surviving non-whitespace
    # control chars (ESC, BEL, ...) reach the terminal via ui_detail —
    # the same gate the path has, now on both fields
    note = " ".join(note.split())
    if any(_cntrl(ch) for ch in note):
        bad('containerTrees[%d]: "note" must not contain control characters' % i)
    sys.stdout.write("%s\t%s\n" % (rel, note))
PYEOF
}

if [ "$DOCTOR_POLICY_PRESENT" = 1 ]; then
    if ! doctor_load_policy "$DOCTOR_ROOT" >"$WORK/trees"; then
        ui_error "doctor: the policy file was rejected -- fix opk.json (format: docs/reference/cli.md)"
        exit 1
    fi
else
    : >"$WORK/trees"
fi

# --- scan each declared tree --------------------------------------------------------
# doctor_classify <uids-file> <daemon-uid> <ranges>
# Counts owners from a UID-ONLY stream (find -printf '%U\n'): exactly one
# numeric line per entry, so a filename containing a newline cannot
# corrupt the counts or invent uids (#344 a S1). Emits
# "SUM<TAB>safe<TAB>risk" and one "UID<TAB>uid<TAB>count" per unmapped uid.
doctor_classify() {
    awk -v daemon="$2" -v ranges="$3" '
        BEGIN {
            n = split(ranges, r, " ")
            for (i = 1; i + 1 <= n; i += 2) {
                rs[++m] = r[i] + 0
                rc[m] = r[i + 1] + 0
            }
        }
        {
            uid = $1 + 0
            if (uid == daemon + 0) { safe++; next }
            ok = 0
            for (j = 1; j <= m; j++)
                if (uid >= rs[j] && uid < rs[j] + rc[j]) { ok = 1; break }
            if (ok) { safe++; next }
            risk++
            uids[uid]++
        }
        END {
            print "SUM\t" safe + 0 "\t" risk + 0
            for (u in uids) print "UID\t" u "\t" uids[u]
        }
    ' "$1"
}

# doctor_examples <tsv-file> <daemon-uid> <ranges>
# Display-only companion pass over "uid<TAB>path" lines: prints the
# paths of the first three at-risk entries. Paths render truncated at
# the first whitespace run (awk default FS) -- deliberate and harmless:
# examples point a human at the tree; the counts come from the
# newline-safe uid stream (#344 a S1/S2).
doctor_examples() {
    awk -v daemon="$2" -v ranges="$3" '
        BEGIN {
            n = split(ranges, r, " ")
            for (i = 1; i + 1 <= n; i += 2) {
                rs[++m] = r[i] + 0
                rc[m] = r[i + 1] + 0
            }
        }
        {
            uid = $1 + 0
            if (uid == daemon + 0) next
            ok = 0
            for (j = 1; j <= m; j++)
                if (uid >= rs[j] && uid < rs[j] + rc[j]) { ok = 1; break }
            if (ok) next
            if (exn < 3) { exn++; print $2 }
            if (exn >= 3) exit
        }
    ' "$1"
}

DOCTOR_TAB="$(printf '\t')"

# doctor_scan_trees
# One report pass over "$WORK/trees": prints the verdict rows (identical
# in scan and fix mode -- fix mode is the scan plus orchestration) and,
# in fix mode, collects the actionable findings as
# "rel<TAB>abs<TAB>risk<TAB>total" lines in "$WORK/fixcand": declared,
# existing, non-symlink DIRECTORY trees with at-risk entries -- the one
# finding class with an unambiguous remedy (#313: handover opencode).
# Warning classes (rejected path form, missing, symlink, not a directory)
# have no fix and are never collected. Callers that re-run this function
# (fix mode's re-check) reset UI_ROWS_* first: the counters accumulate
# across passes otherwise.
doctor_scan_trees() {
    : >"$WORK/fixcand"
    while IFS="$DOCTOR_TAB" read -r DOCTOR_PATH DOCTOR_NOTE; do
        # Belt over the python allowlist: the forms that must never reach
        # find as an operand (absolute, trailing slash, dot/dotdot
        # components in every position, interior empty components,
        # backslash) are re-checked in shell -- defense in depth, not the
        # primary gate (#344 a S5, b R3).
        case "$DOCTOR_PATH" in
            /* | */ | . | ./* | .. | ../* | */. | */./* | */.. | */../* | *//* | *\\*)
                ui_kv_warn "container tree" "$DOCTOR_PATH -- rejected path form, skipped"
                continue
                ;;
        esac
        DOCTOR_TREE="$DOCTOR_ROOT/$DOCTOR_PATH"
        if [ ! -e "$DOCTOR_TREE" ]; then
            ui_kv_warn "container tree" "$DOCTOR_PATH -- declared but missing (fresh clone? build or create it first)"
            continue
        fi
        if [ -L "$DOCTOR_TREE" ]; then
            ui_kv_warn "container tree" "$DOCTOR_PATH -- a symlink, skipped (declare the real tree)"
            continue
        fi
        if [ ! -d "$DOCTOR_TREE" ]; then
            ui_kv_warn "container tree" "$DOCTOR_PATH -- not a directory, skipped"
            continue
        fi

        # Pass 1 (authoritative counts): the uid-only stream is newline-safe
        # by construction -- a filename containing a newline cannot split a
        # numeric uid line (#344 a S1).
        find "$DOCTOR_TREE" -printf '%U\n' >"$WORK/uids" 2>"$WORK/scan.err"
        if [ -s "$WORK/scan.err" ]; then
            # fail loud, not fail absent: unreadable entries would silently
            # shrink the tree and could turn a red verdict green (#312 class
            # feeds on exactly such partial views)
            ui_kv_warn "container tree" "$DOCTOR_PATH -- scan incomplete: $(wc -l <"$WORK/scan.err") unreadable entries"
            ui_detail "run doctor as the tree owner (or with sudo) to get a complete verdict"
        fi
        doctor_classify "$WORK/uids" "$DOCTOR_DAEMON_UID" "$DOCTOR_RANGES" >"$WORK/cls"

        _cl_safe=0
        _cl_risk=0
        _cl_uids=""
        _cl_uidn=0
        while IFS="$DOCTOR_TAB" read -r _cl_tag _cl_a _cl_b; do
            case "$_cl_tag" in
                SUM)
                    _cl_safe="$_cl_a"
                    _cl_risk="$_cl_b"
                    ;;
                UID)
                    _cl_uidn=$((_cl_uidn + 1))
                    [ "$_cl_uidn" -le 4 ] && _cl_uids="$_cl_uids$_cl_a ($_cl_b), "
                    ;;
            esac
        done <"$WORK/cls"
        _cl_total=$((_cl_safe + _cl_risk))

        # Pass 2 (examples): display-only, run just when there is something
        # to show -- see doctor_examples for the truncation contract.
        # stderr deliberately NOT suppressed (#344 b R4): a tree that turns
        # unreadable between the passes degrades the examples, and the raw
        # find error on the terminal is that degradation's visibility (the
        # counts stay authoritative -- pass 1 warns loudly). A deterministic
        # failure-path pin would need mid-scan timing injection (~30+ lines
        # for a LOW) -- declined per the pin-cost budget, recorded as an
        # accepted residual in round b.
        _cl_ex=""
        if [ "$_cl_risk" -gt 0 ]; then
            find "$DOCTOR_TREE" -printf '%U\t%p\n' >"$WORK/extsv"
            : >"$WORK/ex"
            doctor_examples "$WORK/extsv" "$DOCTOR_DAEMON_UID" "$DOCTOR_RANGES" >>"$WORK/ex"
            while IFS= read -r _ex_p; do
                [ -n "$_ex_p" ] || continue
                [ -n "$_cl_ex" ] && _cl_ex="$_cl_ex, "
                _cl_ex="$_cl_ex${_ex_p#"$DOCTOR_ROOT"/}"
            done <"$WORK/ex"
        fi

        if [ "$_cl_risk" -gt 0 ]; then
            ui_kv_bad "container tree" "$DOCTOR_PATH -- $_cl_risk of $_cl_total entries at-risk (unmapped owners)"
            [ -n "$_cl_uids" ] && ui_detail "at-risk owners: uid ${_cl_uids%, }"
            [ -n "$_cl_ex" ] && ui_detail "examples: $_cl_ex"
            ui_detail "container metadata ops (futimes/chmod/chown) EPERM on these -- the #312 build-breaker class"
            ui_detail "fix: opk doctor fix"
            ui_detail "or rebuild the affected outputs clean (docs/troubleshooting.md, EPERM entry)"
            if [ "$DOCTOR_MODE" = "fix" ]; then
                printf '%s\t%s\t%s\t%s\n' "$DOCTOR_PATH" "$DOCTOR_TREE" "$_cl_risk" "$_cl_total" \
                    >>"$WORK/fixcand"
            fi
        elif [ "$_cl_total" -gt 0 ]; then
            ui_kv_ok "container tree" "$DOCTOR_PATH -- $_cl_total entries mapped-safe"
        else
            ui_kv "container tree" "$DOCTOR_PATH -- empty (nothing classified)"
        fi
        # the policy note is the tree's own documentation -- surface it so
        # the verdict row carries its context (SC2034 drove the decision to
        # display rather than drop it)
        [ -n "$DOCTOR_NOTE" ] && ui_detail "declared: $DOCTOR_NOTE"
    done <"$WORK/trees"
}

# --- detect (issue #352 / #313 phase 3) --------------------------------------------
# Evidence-based candidate discovery. Proposes opk.json entries from
# ownership evidence ONLY -- never from path-name heuristics (#312
# section 6: which trees a container writes is project knowledge, and
# Resources/Public also holds hand-maintained files):
#   S evidence   entries owned by a mapped uid != daemon (subuid twins,
#                #312 cases C/E) -- no host process creates those; the
#                container wrote them, wherever they sit
#   D evidence   daemon-uid entries on git-ignored (regenerable) paths
#                -- agent session edits are TRACKED content and never
#                count; only ignored paths are build outputs
# The proposed boundary per evidence entry is its directory, extended up
# through the ignored chain (gitignore already defines the regenerable
# region; an ignored FILE in a tracked dir proposes its parent -- the
# #312 rule: inputs and outputs share one tree). Nested boundaries merge
# into the outermost. A boundary that also contains unmapped entries is
# MIXED (the build-breaker class: both worlds write one tree) and the
# proposed note says so. Without git (no repo, dubious ownership, git
# absent) only S evidence works -- a warn row says so.
# opk.json is a COMMITTED project file: nothing is written without an
# explicit [y/N] consent per finding (default n); declined findings
# print the snippet to paste and leave rc 1.
_doctor_detect_path_ok() {
    # shell belt over the classify-time gate (the writer re-checks a
    # third time): evidence paths come from find output and can carry
    # anything. DELIBERATELY STRICTER than doctor_load_policy's
    # path_error (#356 a A8): an ASCII whitelist keeps every proposal,
    # prompt and snippet byte-predictable; path_error's blacklist
    # tolerates non-ASCII and |<> that this belt rejects (non-ASCII
    # evidence is dropped with a warn row, see the classify block).
    # The character half runs through grep, not a case pattern -- `(`/`&`
    # in a bracket class are unparseable as a dash case pattern.
    case "$1" in
        "" | /* | */ | . | ./* | .. | ../* | */. | */./* | */.. | */../* | *//* | *\\*) return 1 ;;
    esac
    if printf '%s' "$1" | LC_ALL=C grep -q '[^A-Za-z0-9._/,+@=:&%~ ^!(){}#-]'; then
        return 1
    fi
    return 0
}

if [ "$DOCTOR_MODE" = "detect" ]; then
    find "$DOCTOR_ROOT" -name .git -prune -o -printf '%U\t%y\t%p\n' >"$WORK/dwalk" 2>"$WORK/dwalk.err"
    if [ -s "$WORK/dwalk.err" ]; then
        # fail loud, not fail absent (same class as the scan's unreadable
        # subtree warn): missing evidence must not read as "no evidence"
        ui_kv_warn "scan" "$(wc -l <"$WORK/dwalk.err") unreadable entries -- evidence may be incomplete"
        ui_detail "run detect as the tree owner (or with sudo) for a complete picture"
    fi

    # classify every walked entry through the map (never through the
    # displayed numbers -- the #312 nobody(65534) collision). The
    # character gate is a STRICTER ASCII WHITELIST than
    # doctor_load_policy's blacklist (path_error tolerates non-ASCII
    # and |<>) -- proposals, prompts and the snippet printf stay
    # ASCII-safe; the price is that non-ASCII filenames (umlauts) are
    # not usable as evidence and land in the drop count below --
    # declare such trees manually (#356 a A1/A8).
    # TSV split shapes (#344 a S1 class; #356 a A2, truth-fixed): a
    # filename with a NEWLINE splits into rows -- the FIRST fragment
    # (numeric uid, three fields) is classified under a truncated path,
    # only the tail lands in the drop count; a TAB truncates the path
    # in-row and drops nothing at all. Truncated paths can name entries
    # that do not exist (directory evidence proposes its own truncated
    # prefix) -- a consented dead declaration at worst: consent-gated,
    # charset-belted, and the next 'opk doctor' scan surfaces it as
    # "declared but missing". Hostile bytes beyond the whitelist never
    # reach a row, a prompt or the snippet printf.
    awk -F'\t' -v daemon="$DOCTOR_DAEMON_UID" -v ranges="$DOCTOR_RANGES" \
        -v root="$DOCTOR_ROOT" -v dropf="$WORK/ddrop" '
        BEGIN {
            n = split(ranges, r, " ")
            for (i = 1; i + 1 <= n; i += 2) { rs[++m] = r[i] + 0; rc[m] = r[i + 1] + 0 }
        }
        {
            if ($1 !~ /^[0-9]+$/ || NF < 3) { drop++; next }
            p = $3
            if (index(p, root "/") != 1) next
            p = substr(p, length(root) + 2)
            if (p == "") next
            if (p ~ /[^A-Za-z0-9._\/,+@=:&%~ ^!(){}#-]/) { drop++; next }
            uid = $1 + 0
            cls = "H"
            if (uid == daemon + 0) cls = "D"
            else {
                for (j = 1; j <= m; j++)
                    if (uid >= rs[j] && uid < rs[j] + rc[j]) { cls = "S"; break }
            }
            print cls "\t" uid "\t" $2 "\t" p
        }
        END { if (drop + 0 > 0) printf "%d\n", drop >dropf }
    ' "$WORK/dwalk" >"$WORK/dcls"
    if [ -f "$WORK/ddrop" ]; then
        ui_kv_warn "scan" "$(cat "$WORK/ddrop") entries dropped -- unusable path forms"
        ui_detail "non-ASCII, control or shell-significant characters -- declare such trees manually (#356 a A1)"
        rm -f "${WORK:?}/ddrop"
    fi

    # --- evidence + the git-ignore probe -------------------------------------------
    # probe list: every D-owned path (its own ignore answer decides CE)
    # plus every ancestor directory of every D/S path (the boundary
    # chains need to know where the ignored region starts)
    awk -F'\t' '
        $1 == "D" { print $4 }
        $1 == "D" || $1 == "S" {
            p = $4
            while ((i = match(p, /\/[^\/]+$/)) > 1) {
                p = substr(p, 1, i - 1)
                print p
            }
        }
    ' "$WORK/dcls" | sort -u >"$WORK/ignprobe"
    DOCTOR_IG=0
    if [ -s "$WORK/ignprobe" ] && command -v git >/dev/null 2>&1; then
        _dt_grc=0
        git -C "$DOCTOR_ROOT" check-ignore --stdin <"$WORK/ignprobe" >"$WORK/ign" 2>"$WORK/ign.err" ||
            _dt_grc=$?
        if [ "$_dt_grc" -eq 0 ] || [ "$_dt_grc" -eq 1 ]; then
            # rc 1 is a VALID answer: none of the probed paths is ignored
            DOCTOR_IG=1
        fi
    fi
    if [ -s "$WORK/ignprobe" ] && [ "$DOCTOR_IG" != 1 ]; then
        # not a repository / dubious ownership / broken or absent git:
        # the ignore answers are unavailable, D evidence cannot be
        # verified as regenerable -- S evidence still works (L1: the
        # fallback is a warn row in EVERY arm of it, never silence)
        ui_kv_warn "detect" "git ignore answers unavailable -- daemon-owned entries need them and do not count"
        ui_detail "only subuid-owner evidence is used; run detect inside the repo for full evidence"
        # (#370 a C2): a REAL git failure (rc > 1) wrote its diagnosis
        # to ign.err -- dubious ownership names its safe.directory
        # remedy there, and the row above never showed it. Surface the
        # first stderr line, C0/DEL/C1-stripped: the repo path inside
        # the message is root-argument-influenced, and 8-bit CSI bytes
        # must not ride it into the ui row (the #370 a C1 class).
        if [ "${_dt_grc:-0}" -gt 1 ] && [ -s "$WORK/ign.err" ]; then
            _dt_igmsg="$(head -n 1 "$WORK/ign.err" | tr -d '\000-\037\177\200-\237')"
            [ -n "$_dt_igmsg" ] && ui_detail "git said: $_dt_igmsg"
        fi
    fi
    [ "$DOCTOR_IG" = 1 ] || : >"$WORK/ign"
    # (#356 a D1): the two-file FNR==NR idiom below mis-consumes the
    # ENTIRE dcls stream when the first file is EMPTY -- NR stays in
    # lockstep with FNR through a single file, so every classified row
    # took the ign[$0] branch and detect read "no evidence" in every
    # repo without ignored paths and in every no-git fallback run. A
    # sentinel line carrying a TAB can never equal a classify-surviving
    # path (the charset gate drops tabs at classify time): an empty
    # ignore set is represented by an unmatchable key, not an empty file.
    [ -s "$WORK/ign" ] || printf '.\t.\n' >"$WORK/ign"

    # --- boundaries: compute, merge, aggregate --------------------------------------
    # output per boundary: rel<TAB>count<TAB>owners<TAB>mixed<TAB>examples
    # (owners "uid N (c)" capped at 4, examples capped at 3, like the
    # scan rows). Pure awk over the two prepared streams.
    awk -F'\t' -v rootf="$WORK/droot" '
        FNR == NR { ign[$0] = 1; next }
        {
            cls = $1; uid = $2; typ = $3; p = $4
            if (cls == "H") { hn[++nh] = p; next }
            isce = (cls == "S") || ign[p]
            if (!isce) next
            b = (typ == "d") ? p : dirname(p)
            while ((pp = dirname(b)) != "" && ign[pp]) b = pp
            if (b == "") { rootskip++; next }
            bnd[b] = 1
            evn[++ne] = p; evu[ne] = uid
        }
        function dirname(x) { i = match(x, /\/[^\/]+$/); return (i > 1) ? substr(x, 1, i - 1) : "" }
        END {
            # merge: drop every boundary that sits under another -- the
            # outer boundary keeps ALL evidence (the reassignment below
            # counts every CE entry into its outermost survivor, so
            # nothing is lost by dropping the inner row)
            for (b in bnd) {
                for (b2 in bnd) {
                    if (b != b2 && index(b, b2 "/") == 1) { delete bnd[b]; break }
                }
            }
            for (i = 1; i <= ne; i++) {
                b = ""
                for (c in bnd)
                    if (evn[i] == c || index(evn[i], c "/") == 1) { b = c; break }
                if (b == "") continue
                cnt[b]++
                key = b ":" evu[i]
                if (!(key in useen)) { uids[b] = uids[b] evu[i] ","; useen[key] = 1 }
                oc[key]++
                if (exn[b] < 3) { exn[b]++; ex[b] = (ex[b] == "" ? "" : ex[b] ", ") evn[i] }
            }
            for (i = 1; i <= nh; i++)
                for (c in bnd)
                    if (hn[i] == c || index(hn[i], c "/") == 1) { mixed[c] = 1; break }
            for (b in bnd) {
                o = ""
                split(uids[b], ua, ",")
                for (j = 1; j in ua; j++) {
                    if (ua[j] == "") continue
                    if (++un > 4) { o = o "..., "; break }
                    o = o "uid " ua[j] " (" oc[b ":" ua[j]] "), "
                }
                un = 0
                sub(/, $/, "", o)
                printf "%s\t%d\t%s\t%d\t%s\n", b, cnt[b] + 0, o, (b in mixed) ? 1 : 0, ex[b]
            }
            if (rootskip + 0 > 0) printf "%d\n", rootskip >rootf
        }
    ' "$WORK/ign" "$WORK/dcls" >"$WORK/dcand" || {
        ui_error "detect: the candidate aggregation failed"
        exit 1
    }
    LC_ALL=C sort -t"$DOCTOR_TAB" -k1,1 -o "$WORK/dcand" "$WORK/dcand"
    if [ -s "$WORK/droot" ]; then
        ui_kv_warn "detect" "$(cat "$WORK/droot") evidence entries sit directly in the project root"
        ui_detail "detect never proposes the project root itself -- declare such subtrees manually"
        rm -f "${WORK:?}/droot"
    fi

    DET_N=0
    DET_DECLARED=0
    DET_SKIPPED=0
    DET_NCOVERED=0
    : >"$WORK/dnew"
    ui_section "Doctor detect -- container-tree candidates (ownership evidence)"
    while IFS="$DOCTOR_TAB" read -r DET_B DET_CNT DET_OWN DET_MIXED DET_EX _det_extra <&3; do
        [ -n "$DET_B" ] || continue
        # belt over the classify-time character gate (the writer re-checks
        # a third time): nothing unusable ever reaches a row, a prompt or
        # the snippet printf
        if ! _doctor_detect_path_ok "$DET_B"; then
            DET_SKIPPED=$((DET_SKIPPED + 1))
            continue
        fi
        # already declared (this boundary or an ancestor of it): the
        # policy already covers the tree -- visible, but not a candidate
        DET_COVERED=""
        while IFS="$DOCTOR_TAB" read -r DET_DECL _det_dnote; do
            [ -n "$DET_DECL" ] || continue
            case "$DET_B" in
                "$DET_DECL" | "$DET_DECL"/*)
                    DET_COVERED="$DET_DECL"
                    break
                    ;;
            esac
        done <"$WORK/trees"
        if [ -n "$DET_COVERED" ]; then
            DET_NCOVERED=$((DET_NCOVERED + 1))
            ui_kv "candidate" "$DET_B -- already declared (via $DET_COVERED)"
            continue
        fi
        DET_N=$((DET_N + 1))
        if [ "$DET_MIXED" = 1 ]; then
            _det_mixrow="mixed with human-owned files"
            DET_NOTE="detect: container-written entries mixed with human-owned files -- one owner for both (#312)"
        else
            _det_mixrow="container-written only"
            DET_NOTE="detect: $DET_CNT container-written entries ($DET_OWN) -- declare the whole build tree (#312)"
        fi
        ui_kv "candidate" "$DET_B -- $DET_CNT container-written entries ($DET_OWN), $_det_mixrow"
        [ -n "$DET_EX" ] && ui_detail "examples: $DET_EX"
        ui_detail "evidence: mapped owners only containers create (subuid twins) / daemon-owned on gitignored paths"
        # consent per finding: opk.json is a COMMITTED project file --
        # default n (conventions: writing a committed file changes the
        # project), the loop reads fd 3 so the prompt keeps stdin (the
        # fix-mode discipline)
        if ui_confirm "Declare '$DET_B' in $DOCTOR_ROOT/opk.json (a committed project file)?" n; then
            printf '%s\t%s\n' "$DET_B" "$DET_NOTE" >>"$WORK/dnew"
            DET_DECLARED=$((DET_DECLARED + 1))
            ui_detail "queued -- opk.json is written after the last candidate"
        else
            # declined: the snippet to paste (L1: never a silent decline)
            ui_detail "declined -- paste this into $DOCTOR_ROOT/opk.json (containerTrees):"
            printf '    {"path": "%s", "note": "%s"}\n' "$DET_B" "$DET_NOTE" | while IFS= read -r _det_line; do
                ui_detail "$_det_line"
            done
        fi
    done 3<"$WORK/dcand"
    if [ "$DET_SKIPPED" -gt 0 ]; then
        ui_kv_warn "detect" "$DET_SKIPPED candidate(s) skipped -- unusable path forms"
        ui_detail "non-ASCII, control or shell-significant characters (see the drop rows above)"
    fi

    DET_LEFT=$((DET_N - DET_DECLARED))

    # --- the write (only with consented entries) ------------------------------------
    DET_WROTE=0
    if [ -s "$WORK/dnew" ]; then
        if [ -L "$DOCTOR_ROOT/opk.json" ]; then
            # the 0.0.39g S2 class: never write at/through a linked
            # policy file -- the mv below would replace the link, and
            # the committed file the project carries is not what we saw
            ui_error "detect: $DOCTOR_ROOT/opk.json is a symlink -- not writing; edit the real file"
            exit 1
        fi
        # atomic: temp in the same dir (same fs), then rename. The temp
        # re-checks [ -L ] at exec time (fs-baseline pattern); an
        # existing file keeps its mode, a new one takes the kit's 664
        # group baseline
        _dt_mode=664
        if [ -f "$DOCTOR_ROOT/opk.json" ]; then
            # (#370 a C8): a stat failure (the file vanished or locked
            # down between the -f probe and here) used to leave
            # _dt_mode EMPTY -- chmod "" failed warn-only and opk.json
            # landed with the mktemp default 0600. Fail loud instead:
            # the candidates stay valid, re-run after fixing access.
            _dt_mode="$(stat -c %a "$DOCTOR_ROOT/opk.json" 2>/dev/null)" || {
                ui_error "detect: cannot read the mode of the existing opk.json -- not writing over it"
                ui_detail "the candidates above stay valid -- fix access to opk.json, then re-run detect"
                exit 1
            }
        fi
        _dt_tmp=$(mktemp "$DOCTOR_ROOT/opk.json.opk.XXXXXX") || {
            ui_error "detect: cannot create a temp file in $DOCTOR_ROOT (not writable?)"
            ui_detail "the candidates above stay valid -- paste the snippets, or re-run with permissions fixed"
            exit 1
        }
        if python3 -I - "$DOCTOR_ROOT" "$WORK/dnew" <<'PYEOF' >"$_dt_tmp"
import json
import sys

root, newfile = sys.argv[1], sys.argv[2]


def _cntrl(c):
    # Same set as the validator's gate (#370 a C1): the write-side
    # re-validation must not accept bytes the reader rejects.
    o = ord(c)
    return o < 32 or o == 127 or 0x80 <= o <= 0x9F


path = root + "/opk.json"
doc = {}
try:
    with open(path, "r", encoding="utf-8") as f:
        doc = json.load(f)
except FileNotFoundError:
    pass
except OSError as e:
    sys.stderr.write("opk.json: unreadable: %s\n" % e)
    sys.exit(1)
except ValueError as e:
    sys.stderr.write("opk.json: not valid JSON: %s\n" % e)
    sys.exit(1)

if "version" not in doc:
    # version leads the file (the documented layout) without disturbing
    # the insertion order of the surviving keys
    old = doc
    doc = {"version": 1}
    doc.update(old)
trees = doc.get("containerTrees", [])
if not isinstance(trees, list):
    sys.stderr.write("opk.json: containerTrees must be an array\n")
    sys.exit(1)

with open(newfile, "r", encoding="utf-8") as f:
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        rel, _, note = line.partition("\t")
        if not rel or any(c in rel for c in "'\"`$;\\") or any(_cntrl(c) for c in rel):
            sys.stderr.write("opk.json: refusing to write an unvalidated path\n")
            sys.exit(1)
        trees.append({"path": rel, "note": note})

doc["containerTrees"] = trees
sys.stdout.write(json.dumps(doc, indent=2) + "\n")
PYEOF
        then
            :
        else
            rm -f "${_dt_tmp:?}"
            ui_error "detect: writing opk.json failed (rejected content -- see the errors above)"
            exit 1
        fi
        # (#356 a B1): chmod resolves the NAME and follows a swapped
        # symlink, and the project dir is agent-group-writable -- the
        # temp name can be swapped for a link during the python run
        # (mktemp->chmod spans the whole interpreter startup). Re-check
        # immediately before acting (the learnings root-ops order) and
        # refuse loudly: the mode change on an arbitrary dev-owned file
        # must never happen. rm removes the LINK only (rm never
        # follows); the remaining window is gate->op, the house shape.
        if [ -L "$_dt_tmp" ]; then
            rm -f "${_dt_tmp:?}"
            ui_error "detect: the temp changed to a symlink mid-write -- not writing (chmod refused)"
            exit 1
        fi
        chmod "$_dt_mode" "$_dt_tmp" ||
            ui_kv_warn "detect" "could not set mode $_dt_mode on opk.json (mktemp default remains)"
        # (#356 a B2): a DIRECTORY swapped onto the opk.json name makes
        # mv succeed by moving the temp INSIDE it (POSIX rename) -- the
        # -d conjunct refuses that loudly instead of letting the success
        # row claim a declaration that never happened
        if [ ! -L "$_dt_tmp" ] && [ ! -L "$DOCTOR_ROOT/opk.json" ] && [ ! -d "$DOCTOR_ROOT/opk.json" ]; then
            if mv "$_dt_tmp" "$DOCTOR_ROOT/opk.json"; then
                DET_WROTE=1
            else
                rm -f "${_dt_tmp:?}"
                ui_error "detect: renaming opk.json into place failed"
                exit 1
            fi
        else
            rm -f "${_dt_tmp:?}"
            ui_error "detect: opk.json (or its temp) changed to a symlink or directory mid-write -- not writing"
            exit 1
        fi
    fi

    # --- detect summary (own rc contract, documented in cli.md) ----------------------
    if [ "$DET_WROTE" = 1 ]; then
        ui_kv_ok "result" "$DET_DECLARED of $DET_N candidate(s) declared in opk.json -- commit it (team policy)"
        ui_detail "next: 'opk doctor' classifies the declared trees, 'opk doctor fix' offers the handover remedy"
    elif [ "$DET_N" -gt 0 ]; then
        ui_kv_ok "result" "$DET_DECLARED of $DET_N candidate(s) declared"
    elif [ "$DET_NCOVERED" -gt 0 ]; then
        ui_kv_ok "result" "all evidence already declared ($DET_NCOVERED tree(s) covered) -- nothing new to propose"
    else
        ui_kv_ok "result" "no container-write evidence found -- nothing to declare"
    fi
    if [ "$DET_LEFT" -gt 0 ]; then
        ui_kv_bad "result" "$DET_LEFT candidate(s) left undeclared -- snippets above; re-run detect any time"
        exit 1
    fi
    if [ "$UI_ROWS_WARN" -gt 0 ]; then
        exit 2
    fi
    exit 0
fi

doctor_scan_trees

# --- fix orchestration (issue #313, increment b) ------------------------------------
# Offers the handover per collected candidate. Reads the candidates via
# fd 3 on purpose: the loop body calls ui_confirm, whose answer stream is
# stdin (or /dev/tty) -- a plain '< file' redirect on the loop would feed
# candidate lines to the prompt as answers in the stdin-fallback case
# (tests, CI). DOCTOR_FIX_RAN marks that a handover EXECUTED (success or
# failure): the first scan's counts are stale then and the re-check below
# decides the summary. Note the loop is redirect-fed, not pipeline-fed --
# DOCTOR_FIX_RAN survives it in the main shell (ui.sh counter rule).
DOCTOR_FIX_RAN=0
DOCTOR_FIX_FAILED=0
if [ "$DOCTOR_MODE" = "fix" ] && [ -s "$WORK/fixcand" ]; then
    if [ "$DOCTOR_FIX_DRY" = 1 ]; then
        ui_section "Doctor fix -- dry run (nothing is changed)"
        while IFS="$DOCTOR_TAB" read -r _fx_rel _fx_abs _fx_risk _fx_total <&3; do
            ui_kv "candidate" "$_fx_rel -- $_fx_risk of $_fx_total entries at-risk (unmapped owners)"
            ui_detail "would run: opk handover opencode '$_fx_abs' --dry-run"
            # handover's own dry run prints the plan (and previews its
            # refuses); its rc is observed, not assumed (fail loud)
            if ! sh "$DOCTOR_OPK" handover opencode "$_fx_abs" --dry-run; then
                ui_error "fix: dry run failed for '$_fx_rel' (handover exited non-zero)"
            fi
        done 3<"$WORK/fixcand"
    else
        ui_section "Doctor fix -- hand at-risk trees over to opencode"
        while IFS="$DOCTOR_TAB" read -r _fx_rel _fx_abs _fx_risk _fx_total <&3; do
            ui_kv "candidate" "$_fx_rel -- $_fx_risk of $_fx_total entries at-risk (unmapped owners)"
            # [y/N] default n (conventions: a system-changing step defaults
            # to no); ui_confirm reads /dev/tty when one exists, stdin
            # otherwise (the loop itself reads fd 3 -- see above)
            if ui_confirm "Hand over '$_fx_rel' to opencode (recursive, g+w)?" n; then
                ui_detail "running: opk handover opencode '$_fx_abs'"
                if sh "$DOCTOR_OPK" handover opencode "$_fx_abs"; then
                    DOCTOR_FIX_RAN=1
                else
                    ui_error "fix: handover failed for '$_fx_rel' -- see the errors above"
                    DOCTOR_FIX_RAN=1
                    DOCTOR_FIX_FAILED=1
                fi
            else
                ui_detail "skipped '$_fx_rel' -- 'opk doctor fix' re-offers it any time"
            fi
        done 3<"$WORK/fixcand"
    fi
    if [ "$DOCTOR_FIX_RAN" = 1 ]; then
        ui_section "Doctor fix -- re-check after handover"
        # Counter reset (ui.sh issue #158): the first pass's rows must not
        # survive into the post-fix verdict. The mapped-uid set is
        # deliberately NOT re-resolved: a handover changes ownership, not
        # the daemon's user namespace -- re-reading /proc would only race
        # a backend restart mid-session and smear the header's range row.
        UI_ROWS_OK=0
        UI_ROWS_WARN=0
        UI_ROWS_BAD=0
        doctor_scan_trees
        if [ "$DOCTOR_FIX_FAILED" = 1 ]; then
            # (#370 a C5): the header's rc contract promises rc 1 on a
            # failed handover -- without this row a failure AFTER the
            # ownership change re-verified green and the summary exited
            # 0 over it (the counter reset above wiped every trace of
            # the failure). The bad row feeds the shared verdict gate.
            ui_kv_bad "fix" "a handover failed this run -- the rows above reflect the post-failure state; re-run 'opk doctor fix'"
        fi
    fi
fi
if [ "$DOCTOR_MODE" = "fix" ] && [ "$DOCTOR_FIX_RAN" = 0 ] && [ ! -s "$WORK/fixcand" ]; then
    # no actionable finding at all (healthy trees, or warnings without a
    # remedy). After executed fixes (DOCTOR_FIX_RAN=1) the re-check's own
    # verdict rows above speak instead -- "nothing to fix" would read as
    # if there never had been anything to do.
    ui_info "nothing to fix -- no at-risk finding with a known remedy (handover opencode)"
fi

# --- summary (status.sh contract) ---------------------------------------------------
# Counts snapshot BEFORE the verdict row prints, so the row itself
# never counts. Exit code: 0 all green, 1 alert(s), 2 warning(s) only.
if [ "$UI_ROWS_BAD" -gt 0 ]; then
    ui_kv_bad "result" "$UI_ROWS_BAD alert(s), $UI_ROWS_WARN warning(s) -- fix with 'opk doctor fix'"
    exit 1
fi
if [ "$UI_ROWS_WARN" -gt 0 ]; then
    ui_kv_warn "result" "$UI_ROWS_WARN warning(s), no at-risk findings"
    exit 2
fi
ui_kv_ok "result" "all declared container trees mapped-safe"
exit 0
