#!/bin/sh
# Unit tests for the e2e binary sources (tests/e2e/lib.sh, e2e_fetch_opencode):
# the download channel must be picked by major — 1.x from GitHub release
# assets, 2.x from the npm registry (2.x ships no GitHub assets) with the
# legacy @opencode-ai scope as fallback. Structural greps, like
# test-bypass-guard.sh: lib.sh is e2e scaffolding, not unit-testable code.
# Run: sh tests/unit/test-e2e-sources.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

LIB="$(cd "$(dirname "$0")/../e2e" && pwd)/lib.sh"

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

grep_q() { grep -q "$@" "$LIB"; }

# --- syntax -------------------------------------------------------------------
check "lib.sh passes POSIX sh syntax check" sh -n "$LIB"

# --- 2.x: npm registry, both scopes -------------------------------------------
check "2.x downloads from the npm registry (@opencode scope)" \
    grep_q 'registry\.npmjs\.org/@opencode/cli-\$target'
check "2.x falls back to the legacy @opencode-ai scope" \
    grep_q 'registry\.npmjs\.org/@opencode-ai/cli-\$target'
check "npm tarball layout: package/bin/opencode is moved into the cache" \
    grep_q 'package/bin/opencode'
check "major gate: only 2.* versions take the npm path" \
    grep_q '2\.\*)'

# --- 1.x: GitHub release assets (unchanged channel) ---------------------------
check "1.x downloads stay on GitHub release assets" \
    grep_q 'github\.com/anomalyco/opencode/releases/download'
check "1.x asset name keeps the target suffix" \
    grep_q 'opencode-\$target\.tar\.gz'

# --- both fetch paths route through the shared helper -------------------------
check "e2e_resolve_cache uses e2e_fetch_opencode" \
    grep_q 'e2e_fetch_opencode "\$OC_VERSION"'
check "e2e_fetch_old uses e2e_fetch_opencode" \
    grep_q 'e2e_fetch_opencode "\$OLD_VERSION"'

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All e2e binary source tests passed.$NC"
exit 0
