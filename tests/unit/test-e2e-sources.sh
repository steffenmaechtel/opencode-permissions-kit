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

# --- rate-limit resilience (CI crash 2026-09-25: api.github.com 60 req/h
# per IP on shared runners killed the ddev-2x job at version resolution) ---
RUN_DDEV="$(cd "$(dirname "$0")/../e2e" && pwd)/run-ddev.sh"
WF_E2E="$(cd "$(dirname "$0")/../../.github/workflows" && pwd)/test-e2e.yml"
WF_DDEV="$(cd "$(dirname "$0")/../../.github/workflows" && pwd)/test-e2e-ddev.yml"

check "gh_latest_tag helper exists in lib.sh" \
    grep -q '^gh_latest_tag() {' "$LIB"
check "version resolution authorizes the API when a token is present" \
    sh -c "grep -q 'OPK_GH_TOKEN' \"\$1\" && grep -q 'Authorization: Bearer' \"\$1\"" _ "$LIB"
check "version resolution falls back to the releases/latest redirect" \
    sh -c "grep -q 'url_effective' \"\$1\" && grep -q '/tag/v' \"\$1\"" _ "$LIB"
check "run-ddev.sh resolves ddev through gh_latest_tag (no bare API call)" \
    sh -c "grep -q 'gh_latest_tag ddev/ddev' \"\$1\" && ! grep -q 'https://api.github.com/repos/ddev' \"\$1\"" _ "$RUN_DDEV"
check "workflows export the workflow token to the e2e steps" \
    sh -c "grep -q 'OPK_GH_TOKEN: \${{ github.token }}' \"\$1\" && grep -q 'OPK_GH_TOKEN: \${{ github.token }}' \"\$2\"" _ "$WF_E2E" "$WF_DDEV"

# --- git channel knob (issue #118): lib.sh must forward E2E_GIT_CHANNEL as a
# build-arg on BOTH builder paths (BuildKit + the classic setuid fallback) —
# a knob wired to only one path silently degrades the rootless suite and the
# setuid-rebuild to the distro git. The #116 unreadable-CWD fatal only existed
# on git >= 2.55: without the 'latest' leg the suite cannot see that class. ---
DOCKERFILE="$(cd "$(dirname "$0")/../e2e" && pwd)/Dockerfile"
DOCKERFILE_ROOTLESS="$(cd "$(dirname "$0")/../e2e" && pwd)/Dockerfile.rootless"
RUN_SH="$(cd "$(dirname "$0")/../e2e" && pwd)/run.sh"

check "lib.sh reads the E2E_GIT_CHANNEL knob (default distro)" \
    grep_q 'E2E_GIT_CHANNEL="\${E2E_GIT_CHANNEL:-distro}"'
_git_build_args=$(grep -c -- '--build-arg GIT_CHANNEL' "$LIB")
if [ "$_git_build_args" -ge 2 ]; then
    pass "git channel forwarded on both builder paths (BuildKit + classic)"
else
    fail "git channel forwarded on $_git_build_args of 2 builder paths"
fi
check "non-distro git channels get an image-tag suffix (cache separation)" \
    grep_q 'E2E_IMAGE="\$E2E_IMAGE-git-\$E2E_GIT_CHANNEL"'
check "Dockerfile declares the GIT_CHANNEL build arg" \
    sh -c "grep -q '^ARG GIT_CHANNEL=' \"\$1\" && grep -q '^ARG GIT_CHANNEL=' \"\$2\"" _ "$DOCKERFILE" "$DOCKERFILE_ROOTLESS"
check "both Dockerfiles upgrade via the git-core PPA on channel latest" \
    sh -c "grep -q 'ppa:git-core/ppa' \"\$1\" && grep -q 'ppa:git-core/ppa' \"\$2\"" _ "$DOCKERFILE" "$DOCKERFILE_ROOTLESS"
check "CI matrices the e2e job over the git channel (issue #118)" \
    sh -c "grep -q 'git: \[distro, latest\]' \"\$1\" && grep -q 'E2E_GIT_CHANNEL: \${{ matrix.git }}' \"\$1\"" _ "$WF_E2E"
check "run.sh asserts the latest leg really runs PPA git" \
    grep -q 'E2E_GIT_CHANNEL:-distro}" = "latest"' "$RUN_SH"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All e2e binary source tests passed.$NC"
exit 0
