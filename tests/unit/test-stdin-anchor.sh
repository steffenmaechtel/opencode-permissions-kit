#!/bin/sh
# Unit tests for the stdin-run caller-dir anchors (issue #405), the
# #433 argv[0] hardening and the #434 readlink alignment.
#
# A streamed stdin run (curl ... | sudo bash / sudo sh) has no real $0:
# the interpreter name resolves against the INVOKING cwd, so every
# checkout-first lib lookup derived from $0 would source whatever
# sibling files the cwd happens to sit next to — as root, with no
# vintage pinning (the PR #404 review's S2 finding). The anchored
# entry scripts detect the shape once and pin their caller dir to the
# deployed library (update.sh additionally forces the fetch for
# non-binonly runs and refuses streamed --only-binary runs when
# nothing is installed).
#
# The #433 hardening: a regular FILE named like the interpreter
# ("bash"/"sh") in the invoking cwd satisfied the old file probe alone
# (readlink -f "$0" resolved to it) and re-opened the cwd trust. The
# discriminator now compares $0 against the interpreter's own argv[0]
# (/proc/$$/cmdline's first field) — exact for the stdin shape; the
# file probe remains as the /proc-less fallback.
#
# The #434 alignment: status.sh's ST_CALL_DIR and doctor.sh's
# DR_CALL_DIR resolve through readlink -f like uninstall.sh's
# UN_CALL_DIR — a user SYMLINK to a checkout entry keeps the
# checkout-first sibling lookup instead of the link's dir.
#
# This suite pins:
#   - behaviorally: status.sh (the one entry safe to drive end-to-end
#     — read-only, non-root) must not source a cwd-sibling lib under a
#     REAL stdin run (body piped to sh, $0 = argv[0] = "sh") with a
#     cwd file named "sh" planted — the #433 poison; and a symlinked
#     entry must keep the checkout-first lookup — the #434 shape
#   - the /proc-less fallback arm executes (the elif file probe)
#   - wiring: the anchors and their consequences in update.sh,
#     install.sh, config.sh, status.sh, uninstall.sh and doctor.sh
#     (comment-strip riders, needles passed as arguments — no
#     nested-quote grep bodies)
# Run: sh tests/unit/test-stdin-anchor.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
STATUS="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
UNINSTALL="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"
DOCTOR="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/doctor.sh"
INSTALL="$SCRIPT_DIR/../../files/install.sh"

# Shared harness (issue #394): pass/fail, counters + the work registry
# (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# strip <file>: comment-stripped copy of a shipped source (the
# source-counting rider idiom — commented-out anchors stop counting).
strip() { live_src "$1"; }
# has <haystack-string> <needle...>: fixed-string containment.
has() {
    _h="$1"
    shift
    printf '%s' "$_h" | grep -qF "$*"
}
# lacks <haystack-string> <needle...>: fixed-string absence.
lacks() { ! has "$@"; }

_UP="$(strip "$UPDATE")"
_ST="$(strip "$STATUS")"
_CF="$(strip "$CONFIG")"
_UN="$(strip "$UNINSTALL")"
_DR="$(strip "$DOCTOR")"
# doctor's section functions live in sh/doctor-core.sh since #448 (the
# #346 wave shape) -- the DOCTOR_OPK resolver moved with its section.
# DOCTOR_CORE follows the conventions.md "Unit-suite path variables"
# rule (entry + lib share the entry's name; #451 a Q6), the stripped
# copy keeps this suite's _XX idiom.
DOCTOR_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/doctor-core.sh"
_DR_CORE="$(strip "$DOCTOR_CORE")"
_IN="$(strip "$INSTALL")"

# The hardened discriminator's argv[0] read (#433; A2 fix: 2>/dev/null
# precedes the < read — redirections apply left-to-right, the reversed
# order leaked the open error on /proc-less hosts) — one shape, six
# anchors. Assembled to keep the single-quote needle readable.
_ARGV0='_opk_argv0="$(tr '\''\0'\'' '\''\n'\'' 2>/dev/null </proc/$$/cmdline | head -n 1)"'
# no_standalone_probe <haystack>: rc 0 when the pre-#433 STANDALONE
# file-probe condition is ABSENT. Line-anchored on purpose: the elif
# fallback line ("elif ! [ -f ...") legitimately carries the same
# probe expression and must not count as a hit.
no_standalone_probe() {
    ! printf '%s' "$1" | grep -q '^if ! \[ -f "$(readlink -f "\$0'
}
# The /proc-less fallback arm every anchor carries (#433) — the
# behavioral drive below exercises status.sh's copy; the other five
# anchors pin their arm's presence (comment-stripped).
_ELIF='elif ! [ -f "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")" ]; then'
# The SCRIPT_DIR derivations carry the readlink fallback too (#437 a
# B1: config.sh/update.sh/install.sh previously lacked it — a degraded
# readlink resolved the dir to the invoking cwd).
_SDIR='SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")")" && pwd)"'

# --- 1. behavioral: a stdin run cannot source a cwd sibling (#405, #433) -----------
# A REAL stdin run (the curl | sh shape): the body is piped to the
# interpreter, so $0 IS the interpreter's own argv[0] — AND a regular
# file named "sh" sits in the invoking cwd: the #433 poison that
# defeated the old file probe alone (readlink -f "sh" resolved to it).
# The anchor must still pin the run to the deployed library: the cwd
# sits next to poison sh/ui.sh, sh/update-check.sh and
# sh/ddev-handover.sh siblings — the pre-#405 lookups at $cwd/../sh/<lib>,
# INCLUDING the two resolvers inside the SOURCED status-core.sh
# (review a A1/C1: those re-derived from $0 and would have sourced the
# siblings into the same root shell). None may ever be sourced.
mkdir -p "$WORK/cwd" "$WORK/sh"
printf 'echo UI-POISON-SOURCED >&2\n' >"$WORK/sh/ui.sh"
printf 'echo UPC-POISON-SOURCED >&2\n' >"$WORK/sh/update-check.sh"
printf 'echo DHO-POISON-SOURCED >&2\n' >"$WORK/sh/ddev-handover.sh"
printf '#!/bin/sh\n' >"$WORK/cwd/sh"
_st_rc=0
_st_out=$(cd "$WORK/cwd" && printf 'set -- --short\n. "%s"\n' "$STATUS" |
    timeout 30 sh 2>&1) || _st_rc=$?
case "$_st_out" in
    *UI-POISON-SOURCED* | *UPC-POISON-SOURCED* | *DHO-POISON-SOURCED*)
        fail "stdin-run status.sh must not source cwd-sibling libs (#405/#433)"
        ;;
    *usage*)
        fail "status.sh run aborted at the arg loop — pin vacuous (out=$_st_out) (#405)"
        ;;
    *)
        pass "stdin-run status.sh sources no cwd-sibling lib despite the interpreter-named cwd file (rc=${_st_rc:-0}) (#433)"
        ;;
esac

# Control arm: the siblings ARE reachable at the paths the old
# derivations built (proves the fixture placement — without this the
# pin above would pass vacuously on misplaced fixtures).
_ctrl_ok=0
for _plib in ui.sh update-check.sh ddev-handover.sh; do
    if (cd "$WORK/cwd" && [ -f "../sh/$_plib" ]); then
        _ctrl_ok=$((_ctrl_ok + 1))
    fi
done
if [ "$_ctrl_ok" -eq 3 ]; then
    pass "control arm: all three poison siblings sit at the pre-#405 lookup paths"
else
    fail "control arm: poison siblings misplaced (found $_ctrl_ok of 3 — vacuous #405 pin)"
fi
# Control arm for the #433 poison itself: the interpreter-named file
# really sits in the invoking cwd (without it the hardening pin above
# would not exercise the discriminator's argv[0] arm at all).
check "control arm: the invoking cwd carries the interpreter-named file (#433)" \
    test -f "$WORK/cwd/sh"

# status-core.sh's own resolvers ride the entry's anchor (review a
# A1/C1): a bare dirname-$0 derivation inside the sourced lib would
# reopen the hole the entry's anchor closes.
check "status-core resolvers ride ST_CALL_DIR (review a A1/C1)" \
    sh -c 'printf "%s" "$1" | grep -qF "_ku_lib=\"\${ST_CALL_DIR:-" &&
        printf "%s" "$1" | grep -qF "_st_dhl=\"\${ST_CALL_DIR:-"' \
    _ "$(live_src "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh")"

# --- 1b. behavioral: a symlink to a checkout entry keeps the checkout (#434) -------
# ST_CALL_DIR resolves through readlink -f (uninstall.sh's UN_CALL_DIR
# template): a user symlink (kstatus -> a checkout's status.sh) must
# keep the CHECKOUT-first sibling lookup. The poison sits at the
# SYMLINK's neighbor dir ($WORK/sh — exactly where the pre-#434
# cd+dirname derivation looked); the scratch checkout's own sh/ holds
# the real libs.
CKPT="$WORK/checkout"
mkdir -p "$CKPT"
cp -r "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management" "$CKPT/management"
cp -r "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh" "$CKPT/sh"
ln -s "$CKPT/management/status.sh" "$WORK/cwd/kstatus"
_kst_rc=0
_kst_out=$(cd "$WORK/cwd" && timeout 30 sh "$WORK/cwd/kstatus" --short 2>&1) || _kst_rc=$?
case "$_kst_out" in
    *UI-POISON-SOURCED* | *UPC-POISON-SOURCED* | *DHO-POISON-SOURCED*)
        fail "a symlinked status.sh must keep the checkout-first lookup, not the link dir's neighbors (#434)"
        ;;
    *usage*)
        fail "symlinked status.sh run aborted at the arg loop — pin vacuous (out=$_kst_out) (#434)"
        ;;
    *)
        pass "symlinked status.sh resolves its caller dir through the checkout (#434, rc=${_kst_rc:-0})"
        ;;
esac
# The checkout copy (not the link's neighbor) served the libs: the
# run stayed green AND the real ui.sh (checkout-first) was reachable —
# the neighbor poison exists by section 1's control arm above.

# --- 1c. the /proc-less fallback arm executes (#433) -------------------------------
# The discriminator's elif (the #405 file probe) is the only arm left
# when /proc/$$/cmdline is unreadable. Drive the REAL block from
# status.sh with the proc path swapped for a missing file, from a
# clean cwd (no interpreter-named file): a stdin-shaped $0 must still
# pin. The second drive, from the poisoned cwd, documents the
# accepted fallback residual: the /proc-less probe cannot see the
# argv[0] shape and stays defeatable — the pre-#433 surface, never
# wider.
_FBBIN="$WORK/fb-bin"
_SH_BIN="$(command -v sh)"
mkdir -p "$_FBBIN" "$WORK/clean"
for _fbtool in tr head readlink; do
    ln -s "$(command -v "$_fbtool")" "$_FBBIN/$_fbtool"
done
_fbk="$(sed -n '/^_opk_stdin=false$/,/^fi$/p' "$STATUS" |
    sed 's#/proc/$$/cmdline#/proc/$$/cmdline-absent#g')"
_fall() { # <dir> — drive the /proc-less discriminator from <dir>, print the verdict
    (
        cd "$1" &&
            PATH="$_FBBIN" "$_SH_BIN" -c 'eval "$1";
                if [ "$_opk_stdin" = true ]; then echo SET; else echo UNSET; fi' \
                sh "$2" 2>/dev/null
    )
}
assert_eq "fallback arm: /proc-less stdin shape still pins from a clean cwd (#433)" \
    "SET" "$(_fall "$WORK/clean" "$_fbk")"
assert_eq "fallback residual: the /proc-less probe stays defeatable by the interpreter-named cwd file (accepted, #433)" \
    "UNSET" "$(_fall "$WORK/cwd" "$_fbk")"
# The A2 noise pin (#437 a A2, hardened b D1): the reordered
# redirections (2>/dev/null BEFORE the < read) must silence the open
# error on /proc-less hosts. The needle is the swapped PATH fragment —
# both dash ("cannot open /proc/.../cmdline-absent") and bash-as-sh
# (".../cmdline-absent: No such file or directory") print it, so the
# pin discriminates the old spelling under either shell.
_fbn="$(cd "$WORK/clean" && PATH="$_FBBIN" "$_SH_BIN" -c 'eval "$1" >/dev/null' sh "$_fbk" 2>&1)"
case "$_fbn" in
    *cmdline-absent*)
        fail "fallback arm stays silent on /proc-less hosts (#437 a A2)"
        ;;
    *)
        pass "fallback arm stays silent on /proc-less hosts (#437 a A2)"
        ;;
esac

# --- 2. wiring: update.sh ----------------------------------------------------------
# The stdin flag, the forced fetch (a cwd-adjacent checkout can no
# longer pass the VERSION test spuriously), the binonly anchor and its
# loud refusal.
check "update.sh derives the stdin flag via the argv[0] compare (#433)" \
    has "$_UP" "$_ARGV0"
check "update.sh keeps no standalone #405 file-probe condition (#433)" \
    no_standalone_probe "$_UP"
check "update.sh keeps the /proc-less fallback arm (#433)" \
    has "$_UP" "$_ELIF"
check "update.sh SCRIPT_DIR derivation carries the readlink fallback (#437 a B1)" \
    has "$_UP" "$_SDIR"
check "update.sh forces the fetch for stdin runs (#405)" \
    has "$_UP" '[ "$_opk_stdin" = true ] ||'
check "update.sh pins streamed --only-binary runs to the deployed library (#405)" \
    sh -c 'printf "%s" "$1" | grep -qF "if [ \"\$_opk_stdin\" = true ] && [ \"\$_opk_binonly\" = true ]; then" &&
        printf "%s" "$1" | grep -qF "SCRIPT_DIR=\"/usr/local/lib/opencode-permissions-kit/management\""' \
    _ "$_UP"
check "update.sh refuses streamed --only-binary without an installed library (#405)" \
    has "$_UP" 'streamed --only-binary run found no installed kit library'

# --- 3. wiring: install.sh ---------------------------------------------------------
check "install.sh carries the argv[0] discriminator (#433)" \
    has "$_IN" "$_ARGV0"
check "install.sh keeps no standalone #405 file-probe condition (#433)" \
    no_standalone_probe "$_IN"
check "install.sh keeps the /proc-less fallback arm (#433)" \
    has "$_IN" "$_ELIF"
check "install.sh SCRIPT_DIR derivation carries the readlink fallback (#437 a B1)" \
    has "$_IN" "$_SDIR"
check "install.sh streams (fetches) on stdin runs (#405, #433)" \
    has "$_IN" 'if [ "$_opk_stdin" = true ] || [ ! -f "$SCRIPT_DIR/../VERSION" ]; then'

# --- 4. wiring: config.sh ----------------------------------------------------------
check "config.sh carries the argv[0] discriminator (#433)" \
    has "$_CF" "$_ARGV0"
check "config.sh keeps no standalone #405 file-probe condition (#433)" \
    no_standalone_probe "$_CF"
check "config.sh keeps the /proc-less fallback arm (#433)" \
    has "$_CF" "$_ELIF"
check "config.sh SCRIPT_DIR derivation carries the readlink fallback (#437 a B1)" \
    has "$_CF" "$_SDIR"
check "config.sh pins stdin runs to the deployed library (#405)" \
    sh -c 'printf "%s" "$1" | grep -qF "if [ \"\$_opk_stdin\" = true ]; then" &&
        printf "%s" "$1" | grep -qF "SCRIPT_DIR=\"/usr/local/lib/opencode-permissions-kit/management\""' \
    _ "$_CF"

# --- 5. wiring: status.sh + uninstall.sh resolvers ride the anchored dir -----------
# The pre-#405 resolver shapes (inline cd+dirname lookups) must be gone;
# the anchor itself still legitimately derives the caller dir for REAL
# script runs — so the absence pins name the OLD resolver lines.
check "status.sh resolvers ride ST_CALL_DIR (#405)" \
    sh -c 'printf "%s" "$1" | grep -qF "UI_LIB=\"\$ST_CALL_DIR/../sh/ui.sh\"" &&
        printf "%s" "$1" | grep -qF "STATUS_CORE=\"\$ST_CALL_DIR/../sh/status-core.sh\""' _ "$_ST"
check "status.sh keeps no inline dirname-\$0 resolver (#405)" \
    sh -c '! printf "%s" "$1" | grep -qF "UI_LIB=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)/../sh/ui.sh\"" &&
        ! printf "%s" "$1" | grep -qF "STATUS_CORE=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)/../sh/status-core.sh\""' _ "$_ST"
check "status.sh carries the argv[0] discriminator (#433)" \
    has "$_ST" "$_ARGV0"
check "status.sh keeps no standalone #405 file-probe condition (#433)" \
    no_standalone_probe "$_ST"
check "status.sh keeps the /proc-less fallback arm (#433)" \
    has "$_ST" "$_ELIF"
check "status.sh pins stdin runs to the deployed library (#433)" \
    sh -c 'printf "%s" "$1" | grep -qF "if [ \"\$_opk_stdin\" = true ]; then" &&
        printf "%s" "$1" | grep -qF "ST_CALL_DIR=\"/usr/local/lib/opencode-permissions-kit/management\""' _ "$_ST"
check "status.sh resolves ST_CALL_DIR through readlink (#434)" \
    has "$_ST" 'ST_CALL_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")")"'
check "status.sh keeps no cd+dirname caller-dir derivation (#434)" \
    lacks "$_ST" 'ST_CALL_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"'
check "uninstall.sh resolvers ride UN_CALL_DIR (#405)" \
    sh -c 'printf "%s" "$1" | grep -qF "UNINSTALL_CORE=\"\$UN_CALL_DIR/../sh/uninstall-core.sh\"" &&
        printf "%s" "$1" | grep -qF "\"\$UN_CALL_DIR/../sh/log.sh\""' _ "$_UN"
check "uninstall.sh keeps no inline dirname-\$0 resolver (#405)" \
    lacks "$_UN" 'for cand in "$(dirname "$0")/../sh/log.sh"'
check "uninstall.sh keeps symlink resolution in its caller dir (review a B1)" \
    has "$_UN" 'UN_CALL_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")")"'
check "uninstall.sh carries the argv[0] discriminator (#433)" \
    has "$_UN" "$_ARGV0"
check "uninstall.sh keeps no standalone #405 file-probe condition (#433)" \
    no_standalone_probe "$_UN"
check "uninstall.sh keeps the /proc-less fallback arm (#433)" \
    has "$_UN" "$_ELIF"

# --- 6. wiring: doctor.sh rides the same anchor (review a A2, #433/#434) -----------
# (#448: the entry keeps the anchor and the ui.sh resolution; the
# DOCTOR_OPK resolver rides its section in sh/doctor-core.sh -- its
# conjunct reads the stripped lib.)
check "doctor.sh anchors stdin runs to the deployed library (review a A2)" \
    sh -c 'printf "%s" "$1" | grep -qF "DR_CALL_DIR=\"/usr/local/lib/opencode-permissions-kit/management\"" &&
        printf "%s" "$1" | grep -qF "UI_LIB=\"\$DR_CALL_DIR/../sh/ui.sh\"" &&
        printf "%s" "$2" | grep -qF "DOCTOR_OPK=\"\$DR_CALL_DIR/../bin/opk\""' _ "$_DR" "$_DR_CORE"
check "doctor.sh carries the argv[0] discriminator (#433)" \
    has "$_DR" "$_ARGV0"
check "doctor.sh keeps no standalone #405 file-probe condition (#433)" \
    no_standalone_probe "$_DR"
check "doctor.sh keeps the /proc-less fallback arm (#433)" \
    has "$_DR" "$_ELIF"
check "doctor.sh resolves DR_CALL_DIR through readlink (#434)" \
    has "$_DR" 'DR_CALL_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")")"'
check "doctor.sh keeps no cd+dirname caller-dir derivation (#434)" \
    lacks "$_DR" 'DR_CALL_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"'

suite_done "tests"
