#!/bin/sh
# Unit tests for the mkcert CA reuse (install.sh / update.sh) and the
# status.sh CA-mismatch warning.
#
# Background: the Windows user was detected via powershell.exe / cmd.exe,
# which are frequently not on a WSL PATH — the probe failed silently, the
# Windows CA (priority 1) was skipped, and an untrusted CA got reused
# (browsers showed ddev sites as "not secure"). Both scripts now scan
# /mnt/c/Users/*/AppData/Local/mkcert directly; update.sh also had the
# search priorities inverted (Linux before Windows) — now matches install.
# status.sh reports a fingerprint mismatch between the opencode CAROOT
# and a found Windows CA.
#
# Static asserts on the repo files (no root, no WSL required).
# Run: sh tests/test-mkcert-reuse.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../files/install.sh"
UPDATE="$SCRIPT_DIR/../files/update.sh"
STATUS="$SCRIPT_DIR/../files/status.sh"

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

line_of() { grep -nF "$2" "$1" | head -1 | cut -d: -f1; }

inst_win=$(line_of "$INSTALL" '/mnt/c/Users/*/AppData/Local/mkcert')
inst_linux=$(line_of "$INSTALL" '/home/$DEFAULT_USER/.local/share/mkcert/rootCA.pem')
upd_win=$(line_of "$UPDATE" '/mnt/c/Users/*/AppData/Local/mkcert')
upd_linux=$(line_of "$UPDATE" '/home/$DEFAULT_USER/.local/share/mkcert/rootCA.pem')

echo ""
echo "mkcert CA reuse Tests"
echo "====================="
echo ""

# --- syntax ----------------------------------------------------------------
check "install.sh passes sh -n"  sh -n "$INSTALL"
check "update.sh passes sh -n"   sh -n "$UPDATE"
check "status.sh passes sh -n"   sh -n "$STATUS"

# --- install.sh detection ----------------------------------------------------
check "install.sh scans /mnt/c/Users profiles directly (glob)" \
    sh -c "grep -qF '/mnt/c/Users/*/AppData/Local/mkcert' \"\$1\"" _ "$INSTALL"
check "install.sh no longer invokes powershell.exe" \
    sh -c "! grep -q 'powershell.exe -NoProfile' \"\$1\"" _ "$INSTALL"
check "install.sh no longer invokes cmd.exe" \
    sh -c "! grep -q 'cmd.exe /c' \"\$1\"" _ "$INSTALL"
check "install.sh requires the CA key too (signing needs it)" \
    sh -c "grep -qF '\"\$wca/rootCA-key.pem\"' \"\$1\"" _ "$INSTALL"
check "install.sh keeps the developer-Linux CAROOT fallback" \
    sh -c "grep -qF '/home/\$DEFAULT_USER/.local/share/mkcert/rootCA.pem' \"\$1\"" _ "$INSTALL"
check "install.sh: Windows scan comes before the Linux fallback" \
    test -n "$inst_win" -a -n "$inst_linux" -a "$inst_win" -lt "$inst_linux"

# --- update.sh detection -----------------------------------------------------
check "update.sh scans /mnt/c/Users profiles directly (glob)" \
    sh -c "grep -qF '/mnt/c/Users/*/AppData/Local/mkcert' \"\$1\"" _ "$UPDATE"
check "update.sh no longer invokes powershell.exe" \
    sh -c "! grep -q 'powershell.exe -NoProfile' \"\$1\"" _ "$UPDATE"
check "update.sh no longer invokes cmd.exe" \
    sh -c "! grep -q 'cmd.exe /c' \"\$1\"" _ "$UPDATE"
check "update.sh keeps the developer-Linux CAROOT fallback" \
    sh -c "grep -qF '/home/\$DEFAULT_USER/.local/share/mkcert/rootCA.pem' \"\$1\"" _ "$UPDATE"
check "update.sh: Windows scan comes before the Linux fallback" \
    test -n "$upd_win" -a -n "$upd_linux" -a "$upd_win" -lt "$upd_linux"

# --- status.sh mismatch warning ----------------------------------------------
check "status.sh compares CA fingerprints" \
    sh -c "grep -q 'fingerprint -sha256' \"\$1\"" _ "$STATUS"
check "status.sh prints a MISMATCH warning" \
    sh -c "grep -q 'MISMATCH' \"\$1\"" _ "$STATUS"
check "status.sh points at the Windows CA source" \
    sh -c "grep -qF '/mnt/c/Users/*/AppData/Local/mkcert/rootCA.pem' \"\$1\"" _ "$STATUS"
check "status.sh names the fix (clear traefik certs + restart)" \
    sh -c "grep -q 'traefik/certs' \"\$1\" && grep -q 'ddev restart' \"\$1\"" _ "$STATUS"

# --- functional: glob + label extraction --------------------------------------
# Simulate the install.sh scan logic against a fake profile tree (the same
# shell snippets, copied verbatim) — verifies user-dir skipping via the
# CA-file requirement and the label extraction.
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/Users/Public/AppData/Local/mkcert" \
         "$TMPDIR/Users/mail/AppData/Local/mkcert"
touch "$TMPDIR/Users/Public/AppData/Local/mkcert/rootCA.pem"          # no key -> skipped
touch "$TMPDIR/Users/mail/AppData/Local/mkcert/rootCA.pem" \
      "$TMPDIR/Users/mail/AppData/Local/mkcert/rootCA-key.pem"
src=""
src_label=""
for wca in "$TMPDIR"/Users/*/AppData/Local/mkcert; do
    if [ -f "$wca/rootCA.pem" ] && [ -f "$wca/rootCA-key.pem" ]; then
        src="$wca"
        wuser=${wca#"$TMPDIR"/Users/}
        src_label="Windows user '${wuser%%/*}'"
        break
    fi
done
check "scan picks the profile with a full CA (skips key-less ones)" \
    test "$src" = "$TMPDIR/Users/mail/AppData/Local/mkcert"
check "scan extracts the Windows user label" \
    test "$src_label" = "Windows user 'mail'"

# --- Summary -------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
