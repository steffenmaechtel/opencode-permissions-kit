#!/bin/sh
# Unit tests for the ddev delegation shim.
#
# Two layers are checked:
#   (1) Static structure of files/opencode-lib/bin/ddev — the shim must read
#       DEFAULT_USER + DDEV_BIN from /etc/opencode/install.conf, gate on the
#       opencode sandbox user, delegate via `sudo -u <DEFAULT_USER>`, and
#       pass through to the real ddev otherwise.
#   (2) Installation wiring — install.sh, update.sh, uninstall.sh, sudoers
#       template, and the CI chmod lists must reference the shim consistently
#       so a streamed `curl | bash` install fetches, deploys, links, and
#       removes it.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/.."
SHIM="$REPO/files/opencode-lib/bin/ddev"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/update.sh"
UNINSTALL="$REPO/files/uninstall.sh"
STATUS="$REPO/files/status.sh"
SUDOERS="$REPO/files/sudoers.template"
TEST_YML="$REPO/.github/workflows/test.yml"
E2E_YML="$REPO/.github/workflows/e2e.yml"

failures=0
passed=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        failures=$((failures + 1))
    fi
}

echo ""
echo "ddev Shim Tests"
echo "================"
echo ""

echo "-- shim file structure --"
check "shim exists"                [ -f "$SHIM" ]
check "shim has shebang"           sh -c 'test "$(head -1 "$1")" = "#!/bin/sh"' _ "$SHIM"
check "shim reads DEFAULT_USER from install.conf" \
    grep -Fq 'DEFAULT_USER=$(sed -n '"'"'s/^DEFAULT_USER=//p'"'"' /etc/opencode/install.conf)' "$SHIM"
check "shim reads DDEV_BIN from install.conf" \
    grep -Fq 'DDEV_BIN=$(sed -n '"'"'s/^DDEV_BIN=//p'"'"' /etc/opencode/install.conf)' "$SHIM"
check "shim defaults DDEV_BIN to /usr/bin/ddev" \
    grep -Fq 'DDEV_BIN="/usr/bin/ddev"' "$SHIM"
check "shim gates on opencode sandbox user"   grep -Fq '"$(id -un)" = "opencode"' "$SHIM"
check "shim requires DEFAULT_USER non-empty"  grep -Fq '[ -n "$DEFAULT_USER" ]' "$SHIM"
check "shim delegates via sudo -u"            grep -Fq 'sudo -u "$DEFAULT_USER"' "$SHIM"
check "shim delegates to DDEV_BIN"            grep -Fq '"$DDEV_BIN" "$@"' "$SHIM"
check "shim passthrough execs DDEV_BIN"      grep -Eq '^exec "\$DDEV_BIN" "\$@"' "$SHIM"
check "shim passthrough is the final line"   tail -1 "$SHIM" | grep -Eq '^exec "\$DDEV_BIN" "\$@"'

echo ""
echo "-- install.sh wiring --"
check "install.sh fetches the shim" \
    grep -Fq 'opencode-lib/bin/ddev' "$INSTALL"
check "install.sh mkdirs opencode-lib/bin for fetch" \
    grep -Fq '"$dir/opencode-lib/bin"' "$INSTALL"
check "install.sh deploys the shim to LIBDIR/bin/ddev" \
    grep -Fq '"$LIBDIR/bin/ddev"' "$INSTALL"
check "install.sh detects DDEV_BIN" \
    grep -Fq 'DDEV_BIN="$(command -v ddev' "$INSTALL"
check "install.sh records DDEV_BIN in install.conf" \
    grep -Fq 'DDEV_BIN=$DDEV_BIN' "$INSTALL"
check "install.sh links /usr/local/bin/ddev -> shim" \
    grep -Fq 'ln -sf "$LIBDIR/bin/ddev" /usr/local/bin/ddev' "$INSTALL"
check "install.sh shadows only when free or ours" \
    grep -Eq '\[ -e /usr/local/bin/ddev \]' "$INSTALL"
check "install.sh renders DDEV_BIN into sudoers" \
    grep -Eq 'sed -e "s/DEFAULT_USER/\$DEFAULT_USER/g" -e "s#DDEV_BIN#\$DDEV_BIN#g"' "$INSTALL"

echo ""
echo "-- update.sh wiring --"
check "update.sh fetches the shim" \
    grep -Fq 'opencode-lib/bin/ddev' "$UPDATE"
check "update.sh deploys the shim" \
    grep -Fq '"$LIBDIR/bin/ddev"' "$UPDATE"
check "update.sh re-links the shim" \
    grep -Fq 'ln -sf "$LIBDIR/bin/ddev" /usr/local/bin/ddev' "$UPDATE"
check "update.sh renders DDEV_BIN into sudoers" \
    grep -Eq 'sed -e "s/DEFAULT_USER/\$DEFAULT_USER/g" -e "s#DDEV_BIN#\$DDEV_BIN#g"' "$UPDATE"
check "update.sh preserves DDEV_BIN in install.conf" \
    grep -Eq 'grep -v -e '"'"'\^VERSION='"'"' -e '"'"'\^DDEV_BIN='"'"' "\$INSTALL_CONF"' "$UPDATE"
check "update.sh writes DDEV_BIN back to install.conf" \
    grep -Fq 'echo "DDEV_BIN=$DDEV_BIN"' "$UPDATE"
check "update.sh skips shadow when /usr/local/bin/ddev is a real binary" \
    grep -Eq '\[ -e /usr/local/bin/ddev \] && \[ ! -L /usr/local/bin/ddev \]' "$UPDATE"

echo ""
echo "-- uninstall.sh wiring --"
check "uninstall.sh removes /usr/local/bin/ddev symlink" \
    grep -Fq 'sudo rm -f /usr/local/bin/ddev' "$UNINSTALL"

echo ""
echo "-- status.sh wiring --"
check "status.sh reports the ddev shim" \
    grep -Fq 'ddev delegation shim' "$STATUS"
check "status.sh reports active shim when symlinked" \
    grep -Fq '/usr/local/bin/ddev -> $LIBDIR/bin/ddev' "$STATUS"
check "status.sh reports real-ddev conflict" \
    grep -Eq 'real ddev \(delegation unavailable\)' "$STATUS"

echo ""
echo "-- sudoers rule --"
check "sudoers grants opencode RunAs DEFAULT_USER for DDEV_BIN" \
    grep -Eq 'opencode[[:space:]]+ALL=\(DEFAULT_USER\)[[:space:]]+NOPASSWD: DDEV_BIN' "$SUDOERS"

echo ""
echo "-- CI chmod lists --"
check "test.yml chmods the shim"  grep -Fq './files/opencode-lib/bin/ddev' "$TEST_YML"
check "e2e.yml chmods the shim"   grep -Fq './files/opencode-lib/bin/ddev' "$E2E_YML"
check "test.yml runs test-ddev-shim.sh" \
    grep -Fq './tests/test-ddev-shim.sh' "$TEST_YML"

echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""