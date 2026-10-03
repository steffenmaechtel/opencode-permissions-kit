#!/bin/sh
# Unit tests for sh/deploy-lib.sh (0.0.41d wave): the shared library
# deployment manifest that replaced install.sh's and update.sh's
# twin cp/chmod listings.
#   - happy path: every manifest entry lands in <libdir> with its mode
#     (440 sudoers.template, 755 commands, 644 sourced libs/tui)
#   - a bad tree-root is rejected before anything is written
#   - a partial tree fails LOUD on the first missing source (a broken
#     fetch cannot half-deploy silently)
#   - "-" entries (jsonc templates) deploy without an explicit chmod
# Runs as the CURRENT user (DL_SUDO="") against the real checkout —
# no root.
# Run: sh tests/unit/test-deploy-lib.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    _d="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}

mode_is() {
    [ "$(stat -c %a "$1")" = "$2" ]
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
LIBD="$WORK/libdir"

# --- 1. happy path ----------------------------------------------------------

_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    lib_deploy "$REPO/files" "$LIBD" 2>&1; echo "rc=$?"
)
case "$_dl_out" in *rc=0*) pass "happy: rc=0" ;; *) fail "happy: rc (got [$_dl_out])" ;; esac

_manifest_n=$(sed -n "/<<'DL_MANIFEST'/,/^DL_MANIFEST\$/p" "$LIB" \
    | sed -e '1d' -e '$d' | grep -v '^#' | awk 'NF' | wc -l)
_deployed_n=$(find "$LIBD" -type f | wc -l)
if [ "$_deployed_n" = "$_manifest_n" ]; then
    pass "happy: all $_manifest_n manifest entries deployed"
else
    fail "happy: entry count (manifest $_manifest_n vs deployed $_deployed_n)"
fi

check "mode: sudoers.template 440" mode_is "$LIBD/templates/sudoers.template" 440
check "mode: bin/opk 755" mode_is "$LIBD/bin/opk" 755
check "mode: bin/opencode-as-opencode 755" mode_is "$LIBD/bin/opencode-as-opencode" 755
check "mode: sh/staged-write.sh 644" mode_is "$LIBD/sh/staged-write.sh" 644
check "mode: sh/sudoers-deploy.sh 644" mode_is "$LIBD/sh/sudoers-deploy.sh" 644
check "mode: sh/deploy-lib.sh 644 (self-deploy)" mode_is "$LIBD/sh/deploy-lib.sh" 644
check "mode: sh/log.sh 755" mode_is "$LIBD/sh/log.sh" 755
check "mode: management/config.sh 755" mode_is "$LIBD/management/config.sh" 755
check "mode: tui/tui.json 644" mode_is "$LIBD/tui/tui.json" 644
check "mode: py/tui-register.py 755" mode_is "$LIBD/py/tui-register.py" 755
check '"-" entry: templates/opencode.jsonc deployed (mode follows source)' \
    test -f "$LIBD/templates/opencode.jsonc"

# --- 2. bad tree-root -------------------------------------------------------

_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    lib_deploy "$WORK" "$WORK/lib2" 2>&1; echo "rc=$?"
)
case "$_dl_out" in *rc=1*) pass "bad root: rc=1" ;; *) fail "bad root: rc (got [$_dl_out])" ;; esac
case "$_dl_out" in *"does not contain opencode-permissions-kit-lib"*) pass "bad root: loud message" ;; *) fail "bad root: message" ;; esac
check "bad root: nothing written" test ! -e "$WORK/lib2"

# --- 3. partial tree fails on the first missing source ----------------------

PART="$WORK/partial"
mkdir -p "$PART/opencode-permissions-kit-lib/management"
cp "$REPO/files/opencode-permissions-kit-lib/management/config.sh" "$PART/opencode-permissions-kit-lib/management/"
_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    lib_deploy "$PART" "$WORK/lib3" 2>&1; echo "rc=$?"
)
case "$_dl_out" in *rc=1*) pass "partial tree: rc=1" ;; *) fail "partial tree: rc (got [$_dl_out])" ;; esac
case "$_dl_out" in *"missing source"*) pass "partial tree: names the missing source" ;; *) fail "partial tree: message" ;; esac

# --- summary ----------------------------------------------------------------

echo ""
echo "===================================="
echo "  Passed: $passed  Failed: $failures"
[ "$failures" -eq 0 ] && echo "  All tests passed." || exit 1
exit 0
