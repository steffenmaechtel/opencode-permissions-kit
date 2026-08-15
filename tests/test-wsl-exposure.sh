#!/bin/sh
# Unit tests for the status.sh WSL2 /mnt/c exposure warning.
#
# Background: WSL2 mounts C: via 9p/drvfs with the Windows session token —
# NTFS ACLs do NOT distinguish WSL users, the Linux mode bits are the only
# filter, and the default mount is world-readable. Every WSL user (including
# the agent's opencode user) can then read the whole Windows profile
# (.ssh/id_rsa, NTUSER.DAT, browser profiles). status.sh reports this
# report-only and prints the wsl.conf fix.
#
# Static asserts on the repo files + a POSIX-arithmetic check of the
# mode-mask logic. No root, no WSL required.
# Run: sh tests/test-wsl-exposure.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$SCRIPT_DIR/../files/status.sh"
INSTALL="$SCRIPT_DIR/../files/install.sh"
UPDATE="$SCRIPT_DIR/../files/update.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    local desc="$1"
    shift
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

echo ""
echo "WSL2 /mnt/c exposure Tests"
echo "=========================="
echo ""

# --- syntax -------------------------------------------------------------------
check "status.sh passes sh -n"  sh -n "$STATUS"
check "install.sh passes sh -n" sh -n "$INSTALL"
check "update.sh passes sh -n"  sh -n "$UPDATE"

# --- warning wiring -------------------------------------------------------------
check "status.sh gates the section on /mnt/c existing" \
    sh -c "grep -qF '[ -d /mnt/c ]' \"\$1\"" _ "$STATUS"
check "status.sh checks the world-readable (other) bit of the mount mode" \
    sh -c "grep -q '0004' \"\$1\"" _ "$STATUS"
check "status.sh prints a world-readable warning" \
    sh -c "grep -q 'world-readable' \"\$1\"" _ "$STATUS"
check "status.sh names the asset at risk (Windows profile)" \
    sh -c "grep -q 'Windows profile' \"\$1\"" _ "$STATUS"
check "status.sh shows the wsl.conf automount fix" \
    sh -c "grep -qF '[automount]' \"\$1\" && grep -q 'uid=1000,gid=1000,dmask=027,fmask=037' \"\$1\"" _ "$STATUS"
check "status.sh mentions 'wsl --shutdown'" \
    sh -c "grep -q 'wsl --shutdown' \"\$1\"" _ "$STATUS"
check "status.sh stays silent when the mount is restricted" \
    sh -c "grep -qF 'restricted' \"\$1\"" _ "$STATUS"
check "status.sh detects a configured-but-pending fix (wsl --shutdown)" \
    sh -c "grep -q 'pending' \"\$1\" && grep -q \"options *=.*dmask\" \"\$1\"" _ "$STATUS"

# --- install.sh interactive restriction ----------------------------------------
check "install.sh gates the restriction on /mnt/c existing" \
    sh -c "grep -qF '[ -d /mnt/c ]' \"\$1\"" _ "$INSTALL"
check "install.sh prompts before touching wsl.conf" \
    sh -c "grep -q 'Restrict /mnt/c to your user' \"\$1\"" _ "$INSTALL"
check "install.sh writes the [automount] section with dmask/fmask" \
    sh -c "grep -qF '[automount]' \"\$1\" && grep -q 'dmask=027,fmask=037' \"\$1\"" _ "$INSTALL"
check "install.sh derives uid/gid from the default user (not hardcoded)" \
    sh -c "grep -qF 'id -u \"\$DEFAULT_USER\"' \"\$1\" && grep -qF 'id -g \"\$DEFAULT_USER\"' \"\$1\"" _ "$INSTALL"
check "install.sh leaves a pre-existing [automount] section untouched" \
    sh -c "grep -q 'already has an \[automount\]' \"\$1\"" _ "$INSTALL"
check "install.sh names the activation step (wsl --shutdown)" \
    sh -c "grep -q 'wsl --shutdown' \"\$1\"" _ "$INSTALL"
check "install.sh skips silently when the mount is already restricted" \
    sh -c "grep -qF '/mnt/c already restricted' \"\$1\"" _ "$INSTALL"

# --- update.sh report-only hint -------------------------------------------------
check "update.sh hints at the world-readable /mnt/c (no prompt)" \
    sh -c "grep -q '/mnt/c is world-readable' \"\$1\" && ! grep -q 'prompt ' \"\$1\"" _ "$UPDATE"
check "update.sh prints the recommended wsl.conf options" \
    sh -c "grep -qF '[automount]' \"\$1\" && grep -q 'dmask=027' \"\$1\"" _ "$UPDATE"
check "update.sh reminds about a configured-but-pending restriction" \
    sh -c "grep -q \"pending 'wsl --shutdown'\" \"\$1\"" _ "$UPDATE"

# --- mode-mask arithmetic (the exact check status.sh performs) -----------------
mode_allows_other() {
    m=$(stat -c %a "$1" 2>/dev/null) || return 0
    [ $((0$m & 0004)) -ne 0 ]
}
mode_is_restricted() { ! mode_allows_other "$1"; }
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/open" "$TMPDIR/locked"
chmod 777 "$TMPDIR/open"
chmod 770 "$TMPDIR/locked"
check "mask logic: 777 counts as world-readable" \
    mode_allows_other "$TMPDIR/open"
check "mask logic: 770 counts as restricted" \
    mode_is_restricted "$TMPDIR/locked"

# --- Summary ---------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
