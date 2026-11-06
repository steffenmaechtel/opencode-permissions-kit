#!/bin/sh
# Unit tests for the mkcert CA reuse (install.sh / update.sh) and the
# status.sh CA-mismatch warning.
#
# Background: the Windows user was detected via powershell.exe / cmd.exe,
# which are frequently not on a WSL PATH — the probe failed silently, the
# Windows CA (priority 1) was skipped, and an untrusted CA got reused
# (browsers showed ddev sites as "not secure"). install.sh now scans
# /mnt/c/Users/*/AppData/Local/mkcert directly; update.sh carries no CA
# provisioning at all anymore (legacy cleanup — pinned by the absence
# check below). status.sh reports a fingerprint mismatch between the
# opencode CAROOT and a found Windows CA.
#
# Static asserts on the repo files (no root, no WSL required).
# Run: sh tests/unit/test-mkcert-reuse.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../../files/install.sh"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
UPDATE_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/update-core.sh"
STATUS="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"
STATUS_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh"

# Shared harness (issue #394 adoption): pass/fail, colors, counters
# and the summary gate live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

# line_of: first line (in the comment-stripped file, #385) containing $2.
# The strip substitutes (never deletes), so the numbers stay real lines.
line_of() { sed 's/^[[:space:]]*#.*$//' "$1" | grep -nF "$2" | head -1 | cut -d: -f1; }

inst_win=$(line_of "$INSTALL" '/mnt/c/Users/*/AppData/Local/mkcert')
inst_linux=$(line_of "$INSTALL" '$DEV_HOME/.local/share/mkcert/rootCA.pem')

echo ""
echo "mkcert CA reuse Tests"
echo "====================="
echo ""

# --- syntax ----------------------------------------------------------------
check "install.sh passes sh -n" sh -n "$INSTALL"
check "update.sh passes sh -n" sh -n "$UPDATE"
check "status.sh passes sh -n" sh -n "$STATUS"

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
    sh -c "grep -qF '\$DEV_HOME/.local/share/mkcert/rootCA.pem' \"\$1\"" _ "$INSTALL"
check "install.sh: Windows scan comes before the Linux fallback" \
    test -n "$inst_win" -a -n "$inst_linux" -a "$inst_win" -lt "$inst_linux"

# --- update.sh detection -----------------------------------------------------
# (update.sh no longer provisions the CA — that ran with the legacy
# migration; a 0.0.14+ install already has the CA. install.sh owns reuse.
# The /mnt/c advisory section lives in sh/update-core.sh since #346
# wave 2 — the absence covers both files.)
check "update.sh has no CA provisioning left (legacy cleanup)" \
    sh -c "! grep -qF '/mnt/c/Users/*/AppData/Local/mkcert' \"\$1\" && ! grep -qF '/mnt/c/Users/*/AppData/Local/mkcert' \"\$2\"" _ "$UPDATE" "$UPDATE_CORE"

# --- status.sh mismatch warning (rows live in sh/status-core.sh, #346 wave 1) --
check "status.sh compares CA fingerprints" \
    sh -c "grep -q 'fingerprint -sha256' \"\$1\"" _ "$STATUS_CORE"
check "status.sh prints a MISMATCH warning" \
    sh -c "grep -q 'MISMATCH' \"\$1\"" _ "$STATUS_CORE"
check "status.sh points at the Windows CA source" \
    sh -c "grep -qF '/mnt/c/Users/*/AppData/Local/mkcert/rootCA.pem' \"\$1\"" _ "$STATUS_CORE"
check "status.sh names the fix (clear traefik certs + restart)" \
    sh -c "grep -q 'traefik/certs' \"\$1\" && grep -q 'ddev restart' \"\$1\"" _ "$STATUS_CORE"

# --- functional: glob + label extraction --------------------------------------
# Simulate the install.sh scan logic against a fake profile tree (the same
# shell snippets, copied verbatim) — verifies user-dir skipping via the
# CA-file requirement and the label extraction.
TMPDIR=$(work_new)
mkdir -p "$TMPDIR/Users/Public/AppData/Local/mkcert" \
    "$TMPDIR/Users/mail/AppData/Local/mkcert"
touch "$TMPDIR/Users/Public/AppData/Local/mkcert/rootCA.pem" # no key -> skipped
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
suite_done "tests"
