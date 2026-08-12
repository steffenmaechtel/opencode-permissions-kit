#!/bin/sh
# Unit tests for the wrapper-bypass guard (self-install / absolute-path
# protection). Two layers are checked:
#   (1) Functional: files/opencode-permissions-kit-lib/shell-warn.sh warns
#       when a self-installed opencode binary shadows the wrapper, and stays
#       quiet when the wrapper is in charge.
#   (2) Static wiring: install.sh, update.sh, the wrapper, umask.sh and the
#       CI chmod lists reference the guard consistently so a streamed
#       `curl | bash` install fetches, deploys, hooks, and updates it.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/.."
WARN="$REPO/files/opencode-permissions-kit-lib/shell-warn.sh"
WRAPPER="$REPO/files/opencode-permissions-kit-lib/wrapper"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/update.sh"
UMASK="$REPO/files/umask.sh"
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

# Source shell-warn.sh with a controlled HOME/PATH; prints nothing on stderr
# when quiet, the warning text when triggered.
run_warn() {
    local home="$1" path="$2"
    HOME="$home" PATH="$path" sh -c '. "$0"' "$WARN" 2>&1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo ""
echo "Wrapper-Bypass Guard Tests"
echo "============================"
echo ""

echo "-- shell-warn.sh functional --"
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/opencode"
chmod +x "$TMP/bin/opencode"

out=$(run_warn "$TMP/clean-home" "/usr/bin:/bin")
check "clean home, no opencode on PATH: quiet" [ -z "$out" ]

mkdir -p "$TMP/home-shadow/.opencode/bin"
echo "not-the-wrapper" > "$TMP/home-shadow/.opencode/bin/opencode"
out=$(run_warn "$TMP/home-shadow" "/usr/bin:/bin")
check "shadow real binary: warns" sh -c 'echo "$1" | grep -q "wrapper bypass"' _ "$out"
check "shadow real binary: suggests fix" sh -c 'echo "$1" | grep -q "rm -rf"' _ "$out"

mkdir -p "$TMP/home-link/.opencode/bin"
ln -s /usr/local/lib/opencode-permissions-kit/wrapper "$TMP/home-link/.opencode/bin/opencode"
out=$(run_warn "$TMP/home-link" "/usr/bin:/bin")
check "shadow symlink to kit wrapper: quiet" [ -z "$out" ]

out=$(run_warn "$TMP/clean-home" "$TMP/bin:/usr/bin:/bin")
check "PATH resolves to non-wrapper opencode: warns" sh -c 'echo "$1" | grep -q "resolves to"' _ "$out"

check "script is sourceable (uses return, not exit)" \
    sh -c 'grep -Eq "return 0" "$1" && ! grep -Eq "^[[:space:]]*exit" "$1"' _ "$WARN"

echo ""
echo "-- umask.sh / wrapper wiring --"
check "umask.sh sources shell-warn.sh" \
    grep -Fq 'shell-warn.sh' "$UMASK"
check "wrapper self-checks for shadow binary" \
    grep -Fq 'self-installed opencode detected' "$WRAPPER"
check "wrapper self-checks PATH resolution" \
    grep -Fq "'opencode' on this PATH resolves to" "$WRAPPER"

echo ""
echo "-- install.sh wiring --"
check "install.sh fetches shell-warn.sh" \
    grep -Fq 'opencode-permissions-kit-lib/shell-warn.sh' "$INSTALL"
check "install.sh deploys shell-warn.sh to LIBDIR" \
    grep -Fq '"$LIBDIR/shell-warn.sh"' "$INSTALL"
check "install.sh hooks shell-warn.sh into rc files" \
    grep -Fq 'opencode-permissions-kit/shell-warn.sh' "$INSTALL"
check "install.sh restricts binary to root:group 750" \
    grep -Fq 'chmod 750 "$SYSTEM_BIN"' "$INSTALL"
check "install.sh never uses world-executable binary mode" \
    sh -c '! grep -Fq "chmod 755 \"\$SYSTEM_BIN\"" "$1"' _ "$INSTALL"

echo ""
echo "-- update.sh wiring --"
check "update.sh fetches shell-warn.sh" \
    grep -Fq 'opencode-permissions-kit-lib/shell-warn.sh' "$UPDATE"
check "update.sh deploys shell-warn.sh to LIBDIR" \
    grep -Fq '"$LIBDIR/shell-warn.sh"' "$UPDATE"
check "update.sh hooks shell-warn.sh into rc files" \
    grep -Fq 'opencode-permissions-kit/shell-warn.sh' "$UPDATE"
check "update.sh re-asserts binary 750" \
    grep -Fq 'chmod 750 "$SYSTEM_BIN"' "$UPDATE"
check "update.sh restricts migrated binary to 750" \
    grep -Fq 'chmod 750 "$LIBDIR/bin/opencode"' "$UPDATE"
check "update.sh never uses world-executable binary mode" \
    sh -c '! grep -Fq "chmod 755 \"\$SYSTEM_BIN\"" "$1"' _ "$UPDATE"

echo ""
echo "-- CI chmod lists --"
check "test.yml chmods shell-warn.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/shell-warn.sh' "$TEST_YML"
check "e2e.yml chmods shell-warn.sh" \
    grep -Fq './files/opencode-permissions-kit-lib/shell-warn.sh' "$E2E_YML"
check "test.yml runs test-bypass-guard.sh" \
    grep -Fq './tests/test-bypass-guard.sh' "$TEST_YML"

echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
