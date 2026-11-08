#!/bin/sh
# Unit tests for the stdin-run caller-dir anchors (issue #405).
#
# A streamed stdin run (curl ... | sudo bash / sudo sh) has no real $0:
# the interpreter name resolves against the INVOKING cwd, so every
# checkout-first lib lookup derived from $0 would source whatever
# sibling files the cwd happens to sit next to — as root, with no
# vintage pinning (the PR #404 review's S2 finding). The anchored
# entry scripts detect the shape once ($0 does not resolve to an
# existing file) and pin their caller dir to the deployed library
# (update.sh additionally forces the fetch for non-binonly runs and
# refuses streamed --only-binary runs when nothing is installed).
#
# This suite pins:
#   - behaviorally: status.sh (the one entry safe to drive end-to-end
#     — read-only, non-root) must not source a cwd-sibling lib under a
#     stdin-shaped invocation, on ANY host (poison probe)
#   - wiring: the anchors and their consequences in update.sh,
#     install.sh, config.sh and uninstall.sh (comment-strip riders,
#     needles passed as arguments — no nested-quote grep bodies)
# Run: sh tests/unit/test-stdin-anchor.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
STATUS="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
UNINSTALL="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"
INSTALL="$SCRIPT_DIR/../../files/install.sh"

# Shared harness (issue #394): pass/fail, counters + the work registry
# (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# strip <file>: comment-stripped copy of a shipped source (the
# source-counting rider idiom — commented-out anchors stop counting).
strip() { sed 's/^[[:space:]]*#.*$//' "$1"; }
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
_IN="$(strip "$INSTALL")"

# --- 1. behavioral: a stdin-shaped status.sh run cannot source a cwd sibling ------
# $0 is forced to "bash" (the interpreter-name shape of curl | sh);
# dash's `.` passes no arguments, so the positionals are set BEFORE the
# dot. The cwd sits NEXT TO poison sh/ui.sh, sh/update-check.sh and
# sh/ddev-handover.sh siblings — the pre-#405 lookups at
# $cwd/../sh/<lib>, INCLUDING the two resolvers inside the SOURCED
# status-core.sh (review a A1/C1: those re-derived from $0 and would
# have sourced the siblings into the same root shell). None may ever
# be sourced: the entry's anchor pins ST_CALL_DIR and the lib's
# resolvers ride it; the deployed library decides from there (missing
# → loud abort; present → the real libs and a read-only report).
# Sabotage: delete an anchor → the matching POISON line prints.
mkdir -p "$WORK/cwd" "$WORK/sh"
printf 'echo UI-POISON-SOURCED >&2\n' >"$WORK/sh/ui.sh"
printf 'echo UPC-POISON-SOURCED >&2\n' >"$WORK/sh/update-check.sh"
printf 'echo DHO-POISON-SOURCED >&2\n' >"$WORK/sh/ddev-handover.sh"
_st_out=$(cd "$WORK/cwd" && timeout 30 sh -c '_sa="$1"; set -- --short; . "$_sa"' \
    bash "$STATUS" 2>&1) || _st_rc=$?
case "$_st_out" in
    *UI-POISON-SOURCED* | *UPC-POISON-SOURCED* | *DHO-POISON-SOURCED*)
        fail "stdin-run status.sh must not source cwd-sibling libs (#405)"
        ;;
    *usage*)
        fail "status.sh run aborted at the arg loop — pin vacuous (out=$_st_out) (#405)"
        ;;
    *)
        pass "stdin-run status.sh sources no cwd-sibling lib (rc=${_st_rc:-0}) (#405)"
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

# status-core.sh's own resolvers ride the entry's anchor (review a
# A1/C1): a bare dirname-$0 derivation inside the sourced lib would
# reopen the hole the entry's anchor closes.
check "status-core resolvers ride ST_CALL_DIR (review a A1/C1)" \
    sh -c 'printf "%s" "$1" | grep -qF "_ku_lib=\"\${ST_CALL_DIR:-" &&
        printf "%s" "$1" | grep -qF "_st_dhl=\"\${ST_CALL_DIR:-"' \
    _ "$(sed 's/^[[:space:]]*#.*$//' "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh")"

# --- 2. wiring: update.sh ----------------------------------------------------------
# The stdin flag, the forced fetch (a cwd-adjacent checkout can no
# longer pass the VERSION test spuriously), the binonly anchor and its
# loud refusal.
check "update.sh derives the stdin-run flag (#405)" \
    has "$_UP" '_opk_stdin_run=false'
check "update.sh stdin detection resolves \$0 to a file (#405)" \
    has "$_UP" 'if ! [ -f "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")" ]; then'
check "update.sh forces the fetch for stdin runs (#405)" \
    has "$_UP" '[ "$_opk_stdin_run" = true ] ||'
check "update.sh pins streamed --only-binary runs to the deployed library (#405)" \
    sh -c 'printf "%s" "$1" | grep -qF "if [ \"\$_opk_stdin_run\" = true ] && [ \"\$_opk_binonly\" = true ]; then" &&
        printf "%s" "$1" | grep -qF "SCRIPT_DIR=\"/usr/local/lib/opencode-permissions-kit/management\""' \
    _ "$_UP"
check "update.sh refuses streamed --only-binary without an installed library (#405)" \
    has "$_UP" 'streamed --only-binary run found no installed kit library'

# --- 3. wiring: install.sh ---------------------------------------------------------
check "install.sh streams (fetches) on stdin runs (#405)" \
    sh -c 'printf "%s" "$1" | grep -qF "if ! [ -f \"\$(readlink -f \"\$0\" 2>/dev/null || printf '"'"'%s'"'"' \"\$0\")\" ] ||"' \
    _ "$_IN"

# --- 4. wiring: config.sh ----------------------------------------------------------
check "config.sh pins stdin runs to the deployed library (#405)" \
    has "$_CF" 'SCRIPT_DIR="/usr/local/lib/opencode-permissions-kit/management"'
check "config.sh anchors on the same stdin detection (#405)" \
    has "$_CF" 'if ! [ -f "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")" ]; then'

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
check "uninstall.sh resolvers ride UN_CALL_DIR (#405)" \
    sh -c 'printf "%s" "$1" | grep -qF "UNINSTALL_CORE=\"\$UN_CALL_DIR/../sh/uninstall-core.sh\"" &&
        printf "%s" "$1" | grep -qF "\"\$UN_CALL_DIR/../sh/log.sh\""' _ "$_UN"
check "uninstall.sh keeps no inline dirname-\$0 resolver (#405)" \
    lacks "$_UN" 'for cand in "$(dirname "$0")/../sh/log.sh"'
check "uninstall.sh keeps symlink resolution in its caller dir (review a B1)" \
    has "$_UN" 'UN_CALL_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || printf '"'"'%s'"'"' "$0")")"'

# --- 6. wiring: doctor.sh rides the same anchor (review a A2) ----------------------
_DR="$(strip "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/doctor.sh")"
check "doctor.sh anchors stdin runs to the deployed library (review a A2)" \
    sh -c 'printf "%s" "$1" | grep -qF "DR_CALL_DIR=\"/usr/local/lib/opencode-permissions-kit/management\"" &&
        printf "%s" "$1" | grep -qF "UI_LIB=\"\$DR_CALL_DIR/../sh/ui.sh\"" &&
        printf "%s" "$1" | grep -qF "DOCTOR_OPK=\"\$DR_CALL_DIR/../bin/opk\""' _ "$_DR"

suite_done "tests"
