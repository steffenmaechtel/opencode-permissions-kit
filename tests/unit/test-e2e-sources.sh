#!/bin/sh
# Unit tests for the e2e binary sources (tests/e2e/lib.sh, e2e_fetch_opencode):
# the download channel must be picked by major — 1.x from GitHub release
# assets, 2.x from the npm registry (2.x ships no GitHub assets) with the
# legacy @opencode-ai scope as fallback. Mostly structural greps (like
# test-bypass-guard.sh — lib.sh's runner-facing plumbing is e2e
# scaffolding), plus behavioral probes of the self-contained helpers
# (npm_dist_latest via a fake curl, the test-update-flags.sh pattern).
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

# --- default lane = 2.x (issue #197): with E2E_OC_VERSION empty, lib.sh
# resolves the npm dist-tag 'latest' (GitHub releases/latest stays 1.x
# and is the E2E_OC_VERSION pin / -1x CI lane). The resolved value is
# anchored-validated against 2.x before use — registry output is
# untrusted — and an unreachable registry falls back to the newest
# cached binary (the offline chain must stay). ---
check "npm_dist_latest helper exists in lib.sh" \
    grep -q '^npm_dist_latest() {' "$LIB"
check "default resolution goes through npm_dist_latest" \
    grep_q 'OC_VERSION=\$(npm_dist_latest "\$target")'
check "npm_dist_latest reads the per-target packument" \
    grep_q 'registry\.npmjs\.org/@opencode/cli-\$tgt'
check "default resolution is gated on an anchored 2.x semver" \
    sh -c "grep -q '\\^2\\\\\\.\\[0' \"\$1\"" _ "$LIB"
check "2.x gate message names the E2E_OC_VERSION escape hatch" \
    grep_q 'pin E2E_OC_VERSION=<ver> to test another major'
check "offline fallback to the newest cached binary stays" \
    grep_q 'WARNING: version endpoint unreachable'
check "offline fallback prefers the newest cached 2.x (lane major, #224 a W1)" \
    grep_q 'OC_CACHE_DIR./opencode-2\.\* 2'
check "off-major offline degradation is named, never silent (#224 a W1)" \
    grep_q 'no cached 2x, using cached opencode'
check "off-major warning names the E2E_OC_VERSION escape hatch (#224 a W1)" \
    grep_q "off the default lane's 2.x major"
# Empty-cache hard fail (#224 b W1 follow-up): both halves must exist AND sit
# together — the FAIL message alone without the exit would print red and
# keep going (OC_VERSION empty -> messy failure far downstream), the exit
# without the message fails silently. Presence + adjacency pins the pair.
check "empty cache fails loud (FAIL message + adjacent exit 1, #224 b W1)" \
    sh -c "grep -q 'cannot resolve opencode version and no cached version available' \"\$1\" && grep -A1 'cannot resolve opencode version' \"\$1\" | grep -q 'exit 1'" _ "$LIB"
# The pin must not just EXIST but WIN: the assignment has to sit before the
# default resolution, or the resolved value is clobbered after the fact
# (#224 a W6 — presence-only would stay green under reordering).
_pin_ln=$(grep -n 'OC_VERSION="\$E2E_OC_VERSION"' "$LIB" | head -1 | cut -d: -f1)
_res_ln=$(grep -n 'OC_VERSION=\$(npm_dist_latest "\$target")' "$LIB" | head -1 | cut -d: -f1)
if [ -n "$_pin_ln" ] && [ -n "$_res_ln" ] && [ "$_pin_ln" -lt "$_res_ln" ]; then
    pass "a pin wins before any resolution (order pinned, line $_pin_ln < $_res_ln)"
else
    fail "pin-before-resolution order violated (pin line: ${_pin_ln:-missing}, resolve line: ${_res_ln:-missing})"
fi

# --- behavioral: npm_dist_latest against a fake registry (fake curl on
# PATH, the test-update-flags.sh pattern). Proves the happy path prints
# the dist-tag version, and that garbage or an unreachable registry
# prints EMPTY (the caller's fallback premise) — never a partial value
# or an abort under lib.sh's set -e. ---
NPMWORK="$(mktemp -d)"
mkdir -p "$NPMWORK/bin" 
cat > "$NPMWORK/bin/curl" <<'CURLEOF'
#!/bin/sh
# fake registry endpoint, switched by FAKE_CURL_MODE:
#   ok   -> packument whose dist-tags.latest is 2.1.7
#   junk -> non-JSON body (python3 parse fails)
#   down -> connection refused (curl exit 1)
case "${FAKE_CURL_MODE:-ok}" in
    ok)   printf '{"dist-tags":{"latest":"2.1.7","next":"2.2.0-beta.1"}}\n' ;;
    junk) printf '<html>502 Bad Gateway</html>\n' ;;
    down) exit 1 ;;
esac
CURLEOF
chmod +x "$NPMWORK/bin/curl"
sed -n '/^npm_dist_latest() {/,/^}/p' "$LIB" > "$NPMWORK/fn.sh"

_npmres() {
    FAKE_CURL_MODE="$1" PATH="$NPMWORK/bin:$PATH" \
        sh -c '. "$1"; npm_dist_latest linux-x64' _ "$NPMWORK/fn.sh" 2>/dev/null
}
_npmout=$(_npmres ok)
[ "$_npmout" = "2.1.7" ] && pass "npm_dist_latest: dist-tag latest resolves (2.1.7)" \
    || fail "npm_dist_latest: dist-tag latest resolves (got: '$_npmout')"
_npmout=$(_npmres junk)
[ -z "$_npmout" ] && pass "npm_dist_latest: unparseable registry output -> empty (fallback premise)" \
    || fail "npm_dist_latest: unparseable registry output -> empty (got: '$_npmout')"
_npmout=$(_npmres down)
[ -z "$_npmout" ] && pass "npm_dist_latest: unreachable registry -> empty (fallback premise)" \
    || fail "npm_dist_latest: unreachable registry -> empty (got: '$_npmout')"
rm -rf "$NPMWORK"

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
# Token backstop (#224 a W3: since the #197 flip only the GitHub-calling
# steps need it — the -1x lane resolves and both ddev jobs' gh_latest_tag;
# the per-job auth contract lives in test-workflows.sh's lane pins, this
# file-level grep is the coarse "no workflow went fully tokenless" net).
check "workflows export the workflow token to the api.github.com-calling steps" \
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
# Guarded counts (#260, the #244 f W1 class): grep -c exits 1 on zero
# matches. This suite runs set -u only — no -e — so the bare shape
# records its FAIL rather than aborting today; the guard keeps the
# swept count family uniform if set -e ever lands here.
# Comment-strip rider (#261, the #244 g W1 class): a commented-out
# builder line stops counting; full-line comments only (#244 h W6
# residual). lib.sh is repo-internal source, same blindness class.
_git_build_args=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -c -- '--build-arg GIT_CHANNEL' || true)
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
# The git channel pair runs as two explicit jobs (lane-naming wave
# 2026-10-23, was a matrix): stable per-leg check names for branch
# protection, and a job-level skip can no longer collapse the legs.
# The per-leg channel assignment is pinned by test-workflows.sh
# (per-job blocks); this is the presence + no-matrix pin.
check "CI covers the git pair as explicit jobs (distro + latest legs, issue #118)" \
    sh -c "grep -q 'e2e-2x-git-distro:' \"\$1\" && grep -q 'e2e-2x-git-latest:' \"\$1\" && ! grep -qE 'matrix\.git|git: \[distro' \"\$1\"" _ "$WF_E2E"
check "run.sh asserts the latest leg really runs PPA git" \
    grep -q 'E2E_GIT_CHANNEL:-distro}" = "latest"' "$RUN_SH"

# --- base image knob (auth.docker.io 504 outage 2026-10): CI pulls ubuntu
# through the Google Docker Hub mirror; local runs stay on docker.io. Same
# contract class as E2E_GIT_CHANNEL: knob in lib.sh, forwarded on BOTH
# builder paths, ARG-before-FROM in BOTH Dockerfiles, exported by BOTH
# workflow files. ---
check "lib.sh reads the E2E_BASE_IMAGE knob (default ubuntu:24.04)" \
    grep_q 'E2E_BASE_IMAGE="\${E2E_BASE_IMAGE:-ubuntu:24.04}"'
_base_build_args=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -c -- '--build-arg BASE_IMAGE' || true)
if [ "$_base_build_args" -ge 2 ]; then
    pass "base image forwarded on both builder paths (BuildKit + classic)"
else
    fail "base image forwarded on $_base_build_args of 2 builder paths"
fi
check "both Dockerfiles pin the default base image (ARG BASE_IMAGE)" \
    sh -c "grep -q '^ARG BASE_IMAGE=ubuntu:24.04' \"\$1\" \
&& grep -q '^ARG BASE_IMAGE=ubuntu:24.04' \"\$2\"" _ "$DOCKERFILE" "$DOCKERFILE_ROOTLESS"
check "both Dockerfiles pull the configurable base (FROM \${BASE_IMAGE})" \
    sh -c "grep -q '^FROM \${BASE_IMAGE}' \"\$1\" \
&& grep -q '^FROM \${BASE_IMAGE}' \"\$2\"" _ "$DOCKERFILE" "$DOCKERFILE_ROOTLESS"
check "workflows export the mirror base image to the e2e steps" \
    sh -c "grep -q 'E2E_BASE_IMAGE: mirror.gcr.io/library/ubuntu:24.04' \"\$1\" \
&& grep -q 'E2E_BASE_IMAGE: mirror.gcr.io/library/ubuntu:24.04' \"\$2\"" _ "$WF_E2E" "$WF_DDEV"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All e2e binary source tests passed.$NC"
exit 0
