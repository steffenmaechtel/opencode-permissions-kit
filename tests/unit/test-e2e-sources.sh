#!/bin/sh
# Unit tests for the e2e binary sources (tests/e2e/lib.sh, e2e_fetch_opencode):
# the download channel must be picked by major — 1.x from GitHub release
# assets, 2.x from the npm registry (2.x ships no GitHub assets) with the
# legacy @opencode-ai scope as fallback. Plus the per-worktree
# container-name derivation (issue #366) and the skip-accounting /
# strict-lever class pins across the three runners (issue #480: every
# skip routes through skip(), no double-counted failure tallies, no rc
# leg measured behind a tee pipe). Mostly structural greps (like
# test-bypass-guard.sh — lib.sh's runner-facing plumbing is e2e
# scaffolding), plus behavioral probes of the self-contained helpers
# (npm_dist_latest via a fake curl, the test-update-flags.sh pattern).
# Run: sh tests/unit/test-e2e-sources.sh
set -u

LIB="$(cd "$(dirname "$0")/../e2e" && pwd)/lib.sh"

# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$(cd "$(dirname "$0")" && pwd)/lib/harness.sh"

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
check_live "default resolution is gated on an anchored 2.x semver" "$LIB" -q '\^2\\\.\[0'
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
if live_src "$LIB" | grep -q 'cannot resolve opencode version and no cached version available' &&
    live_src "$LIB" | grep -A1 'cannot resolve opencode version' | grep -q 'exit 1'; then
    pass "empty cache fails loud (FAIL message + adjacent exit 1, #224 b W1)"
else
    fail "empty cache fails loud (FAIL message + adjacent exit 1, #224 b W1)"
fi
# The pin must not just EXIST but WIN: the assignment has to sit before the
# default resolution, or the resolved value is clobbered after the fact
# (#224 a W6 — presence-only would stay green under reordering). Both
# greps run over the comment-stripped lib (#385): a future comment
# quoting either literal must not become the pin's anchor.
_pin_ln=$(live_src "$LIB" | grep -n 'OC_VERSION="\$E2E_OC_VERSION"' | head -1 | cut -d: -f1)
_res_ln=$(live_src "$LIB" |
    grep -n 'OC_VERSION=\$(npm_dist_latest "\$target")' | head -1 | cut -d: -f1)
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
# Loud scratch guard (#441 a B1 / #454 a C1 class): no set -e here -- a
# failed work_new must abort instead of degenerating fixture writes.
NPMWORK="$(work_new)" || {
    echo "e2e-sources tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
mkdir -p "$NPMWORK/bin"
cat >"$NPMWORK/bin/curl" <<'CURLEOF'
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
extract_func "$LIB" npm_dist_latest >"$NPMWORK/fn.sh"

_npmres() {
    FAKE_CURL_MODE="$1" PATH="$NPMWORK/bin:$PATH" \
        sh -c '. "$1"; npm_dist_latest linux-x64' _ "$NPMWORK/fn.sh" 2>/dev/null
}
_npmout=$(_npmres ok)
[ "$_npmout" = "2.1.7" ] && pass "npm_dist_latest: dist-tag latest resolves (2.1.7)" ||
    fail "npm_dist_latest: dist-tag latest resolves (got: '$_npmout')"
_npmout=$(_npmres junk)
[ -z "$_npmout" ] && pass "npm_dist_latest: unparseable registry output -> empty (fallback premise)" ||
    fail "npm_dist_latest: unparseable registry output -> empty (got: '$_npmout')"
_npmout=$(_npmres down)
[ -z "$_npmout" ] && pass "npm_dist_latest: unreachable registry -> empty (fallback premise)" ||
    fail "npm_dist_latest: unreachable registry -> empty (got: '$_npmout')"
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
if live_src "$LIB" | grep -q 'OPK_GH_TOKEN' &&
    live_src "$LIB" | grep -q 'Authorization: Bearer'; then
    pass "version resolution authorizes the API when a token is present"
else
    fail "version resolution authorizes the API when a token is present"
fi
if live_src "$LIB" | grep -q 'url_effective' &&
    live_src "$LIB" | grep -q '/tag/v'; then
    pass "version resolution falls back to the releases/latest redirect"
else
    fail "version resolution falls back to the releases/latest redirect"
fi
check "run-ddev.sh resolves ddev through gh_latest_tag (no bare API call)" \
    sh -c "grep -q 'gh_latest_tag ddev/ddev' \"\$1\" && ! grep -q 'https://api.github.com/repos/ddev' \"\$1\"" _ "$RUN_DDEV"
# Token backstop (#224 a W3: since the #197 flip only the GitHub-calling
# steps need it — the -1x lane resolves and both ddev jobs' gh_latest_tag;
# the per-job auth contract lives in test-workflows.sh's lane pins, this
# file-level grep is the coarse "no workflow went fully tokenless" net).
if live_src "$WF_E2E" | grep -q 'OPK_GH_TOKEN: ${{ github.token }}' &&
    live_src "$WF_DDEV" | grep -q 'OPK_GH_TOKEN: ${{ github.token }}'; then
    pass "workflows export the workflow token to the api.github.com-calling steps"
else
    fail "workflows export the workflow token to the api.github.com-calling steps"
fi

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
_git_build_args=$(live_src "$LIB" | grep -c -- '--build-arg GIT_CHANNEL' || true)
if [ "$_git_build_args" -ge 2 ]; then
    pass "git channel forwarded on both builder paths (BuildKit + classic)"
else
    fail "git channel forwarded on $_git_build_args of 2 builder paths"
fi
check "non-distro git channels get an image-tag suffix (cache separation)" \
    grep_q 'E2E_IMAGE="\$E2E_IMAGE-git-\$E2E_GIT_CHANNEL"'
if live_src "$DOCKERFILE" | grep -q '^ARG GIT_CHANNEL=' &&
    live_src "$DOCKERFILE_ROOTLESS" | grep -q '^ARG GIT_CHANNEL='; then
    pass "Dockerfile declares the GIT_CHANNEL build arg"
else
    fail "Dockerfile declares the GIT_CHANNEL build arg"
fi
if live_src "$DOCKERFILE" | grep -q 'ppa:git-core/ppa' &&
    live_src "$DOCKERFILE_ROOTLESS" | grep -q 'ppa:git-core/ppa'; then
    pass "both Dockerfiles upgrade via the git-core PPA on channel latest"
else
    fail "both Dockerfiles upgrade via the git-core PPA on channel latest"
fi
# The git channel pair runs as two explicit jobs (lane-naming wave
# 2026-10-23, was a matrix): stable per-leg check names for branch
# protection, and a job-level skip can no longer collapse the legs.
# The per-leg channel assignment is pinned by test-workflows.sh
# (per-job blocks); this is the presence + no-matrix pin.
# (#285: the absence leg in the check below stays raw on purpose -- a
# commented forbidden construct SHOULD keep tripping; the absence
# carve-out in conventions.md "Source-counting pins".)
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
_base_build_args=$(live_src "$LIB" | grep -c -- '--build-arg BASE_IMAGE' || true)
if [ "$_base_build_args" -ge 2 ]; then
    pass "base image forwarded on both builder paths (BuildKit + classic)"
else
    fail "base image forwarded on $_base_build_args of 2 builder paths"
fi
if live_src "$DOCKERFILE" | grep -q '^ARG BASE_IMAGE=ubuntu:24.04' &&
    live_src "$DOCKERFILE_ROOTLESS" | grep -q '^ARG BASE_IMAGE=ubuntu:24.04'; then
    pass "both Dockerfiles pin the default base image (ARG BASE_IMAGE)"
else
    fail "both Dockerfiles pin the default base image (ARG BASE_IMAGE)"
fi
if live_src "$DOCKERFILE" | grep -q '^FROM ${BASE_IMAGE}' &&
    live_src "$DOCKERFILE_ROOTLESS" | grep -q '^FROM ${BASE_IMAGE}'; then
    pass "both Dockerfiles pull the configurable base (FROM \${BASE_IMAGE})"
else
    fail "both Dockerfiles pull the configurable base (FROM \${BASE_IMAGE})"
fi
if live_src "$WF_E2E" | grep -q 'E2E_BASE_IMAGE: mirror.gcr.io/library/ubuntu:24.04' &&
    live_src "$WF_DDEV" | grep -q 'E2E_BASE_IMAGE: mirror.gcr.io/library/ubuntu:24.04'; then
    pass "workflows export the mirror base image to the e2e steps"
else
    fail "workflows export the mirror base image to the e2e steps"
fi

# --- per-worktree container names (issue #366): two checkouts running the
# SAME suite on one docker daemon shared the fixed container name — the
# second start's rm -f tore the first run's container down mid-suite
# (rc 137 + cross-run red checks). lib.sh now suffixes E2E_CONTAINER with
# a slug of the checkout path at source time; the runners must PASS an
# exported E2E_CONTAINER through instead of clobbering it before lib.sh
# reads the env (the pre-fix hardcode silently killed the override). ---
RUN_ROOTLESS="$(cd "$(dirname "$0")/../e2e" && pwd)/run-docker-rootless.sh"

# Comment-stripped (a commented-out assignment must not satisfy the pin).
if live_src "$LIB" |
    grep -q 'E2E_CONTAINER="\$E2E_CONTAINER-$(e2e_worktree_suffix)"'; then
    pass "lib.sh appends the worktree suffix to E2E_CONTAINER at source time"
else
    fail "lib.sh lost the worktree-suffix assignment on E2E_CONTAINER"
fi
check "e2e_worktree_suffix helper exists in lib.sh" \
    grep -q '^e2e_worktree_suffix() {' "$LIB"
if live_src "$RUN_SH" | grep -q 'E2E_CONTAINER:-opencode-e2e-test}"' &&
    live_src "$RUN_ROOTLESS" | grep -q 'E2E_CONTAINER:-opencode-e2e-rootless-test}"' &&
    live_src "$RUN_DDEV" | grep -q 'E2E_CONTAINER:-opencode-e2e-ddev-test}"'; then
    pass "per-suite base names stay distinct (the suites stay disjoint)"
else
    fail "per-suite base names stay distinct (the suites stay disjoint)"
fi
# Passthrough count, comment-stripped: all three runners must read the
# env, not clobber it (guarded count — grep-in-pipe cannot trip set -e).
_pwc=0
for _r in "$RUN_SH" "$RUN_ROOTLESS" "$RUN_DDEV"; do
    if live_src "$_r" | grep -q 'E2E_CONTAINER="\${E2E_CONTAINER:-'; then
        _pwc=$((_pwc + 1))
    fi
done
if [ "$_pwc" -eq 3 ]; then
    pass "all three runners pass an exported E2E_CONTAINER through (issue #366)"
else
    fail "E2E_CONTAINER passthrough present in only $_pwc of 3 runners"
fi
# The effective name must be visible at container start (incident aid:
# with two same-suite runs the log must show which run owns which
# container). Comment-stripped likewise.
if live_src "$LIB" | grep -q 'echo "  container: \$E2E_CONTAINER'; then
    pass "e2e_start_container prints the effective container name"
else
    fail "e2e_start_container does not print the effective container name"
fi

# Behavioral: the slug itself (pure tr/sed, no fakes). Deterministic per
# checkout, discriminating between checkouts, and a valid docker name
# component (the leading '/' slugs away, so the first char stays alnum).
# Example paths only (/tmp/example/...) — the sandbox policy forbids real
# project-tree literals inside unit suites, and a real path here invites a
# later session to reuse it for something destructive.
WTWORK="$(work_new)" || {
    echo "e2e-sources tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
extract_func "$LIB" e2e_worktree_suffix >"$WTWORK/fn.sh"
_wts() {
    REPO_DIR="$1" sh -c '. "$1"; e2e_worktree_suffix' _ "$WTWORK/fn.sh"
}
_wt1=$(_wts /tmp/example/opencode-permissions-kit/repo)
_wt2=$(_wts /tmp/example/opencode-permissions-kit/repo-kasantra)
assert_eq "suffix slugs the checkout path deterministically" \
    "tmp-example-opencode-permissions-kit-repo" "$_wt1"
if [ "$(_wts /tmp/example/opencode-permissions-kit/repo)" = "$_wt1" ]; then
    pass "suffix is stable across calls (same worktree -> same name)"
else
    fail "suffix unstable across calls"
fi
if [ -n "$_wt2" ] && [ "$_wt2" != "$_wt1" ]; then
    pass "suffix discriminates two worktrees"
else
    fail "suffix does not discriminate worktrees (got: '$_wt1' / '$_wt2')"
fi
if printf '%s' "$_wt1" | grep -qE '^[a-zA-Z0-9][a-zA-Z0-9-]*$'; then
    pass "suffix is a valid docker name component (alnum start, no foreign chars)"
else
    fail "suffix is not a valid docker name component: '$_wt1'"
fi
rm -rf "$WTWORK"

# --- lib.sh cleanup traps (#287 a S2 / b S3, reapplied per #289) ----------------
# e2e lib.sh is outside trap_scan's unit-suite floor, so its signal
# arms ride unpinned without this: the EXIT trap alone let an untrapped
# fatal signal kill the runner and leak the host-side TMP_PROJECT.
# Comment-strip rider on both counts (the source-counting convention):
# a commented-out trap must not satisfy the pin.
_LTRAP_EXIT=$(live_src "$LIB" | grep -c '^trap e2e_cleanup EXIT$' || true)
_LTRAP_SIG=$(live_src "$LIB" | grep -cF "trap 'trap - EXIT INT TERM; e2e_cleanup; exit 1' INT TERM" || true)
if [ "$_LTRAP_EXIT" = 1 ] && [ "$_LTRAP_SIG" = 1 ]; then
    pass "lib.sh: cleanup on EXIT plus self-disarming signal arms (INT TERM, exit 1)"
else
    fail "lib.sh cleanup traps: EXIT=$_LTRAP_EXIT signal=$_LTRAP_SIG (expected 1/1)"
fi

# --- outage-wave build knobs (2026-11-11; pins owed by issue #467) ------------
# Comment-strip riders on every count (the source-counting convention):
# a commented-out knob must stop counting.

# E2E_BUILD_NETWORK (CI exports 'host' in all 7 lanes, pinned in
# test-workflows.sh): the default, the banner print, and forwarding on
# BOTH builder paths — the classic-builder fallback (DOCKER_BUILDKIT=0,
# the setuid-quirk arm) losing the forwarding would silently rebuild on
# the flaky bridge in exactly the runs that hit the quirk.
_BN_DEFAULT=$(live_src "$LIB" | grep -cF 'E2E_BUILD_NETWORK="${E2E_BUILD_NETWORK:-}"' || true)
_BN_FWD=$(live_src "$LIB" | grep -cF -- '--network "$E2E_BUILD_NETWORK"' || true)
_BN_BANNER=$(live_src "$LIB" | grep -cF 'build network: ${E2E_BUILD_NETWORK:-docker default bridge}' || true)
if [ "$_BN_DEFAULT" = 1 ] && [ "$_BN_FWD" = 2 ] && [ "$_BN_BANNER" = 1 ]; then
    pass "lib.sh: E2E_BUILD_NETWORK default + banner + both builder paths forward it"
else
    fail "lib.sh E2E_BUILD_NETWORK: default=$_BN_DEFAULT fwd=$_BN_FWD (want 2), banner=$_BN_BANNER"
fi

# E2E_APT_ARCHIVE_MIRROR — pinned AS-IS (issue #467 offered pin-or-drop):
# CI no longer exports it (the resolver battery superseded the Azure
# mirror route), but it stays a working local operator escape for
# Azure-adjacent runners — the machinery must not rot silently: lib.sh
# forwards the build-arg on both paths, and both Dockerfiles rewrite
# the apt sources only when it is set.
E2E_DIR="$(dirname "$LIB")"
_AM_FWD=$(live_src "$LIB" | grep -cF -- '--build-arg APT_ARCHIVE_MIRROR="$E2E_APT_ARCHIVE_MIRROR"' || true)
if [ "$_AM_FWD" = 2 ]; then
    pass "lib.sh: APT_ARCHIVE_MIRROR build-arg forwarded on both builder paths"
else
    fail "lib.sh APT_ARCHIVE_MIRROR forwarding sites: $_AM_FWD (expected 2)"
fi
for _df in "$E2E_DIR/Dockerfile" "$E2E_DIR/Dockerfile.rootless"; do
    _am_arg=$(live_src "$_df" | grep -c '^ARG APT_ARCHIVE_MIRROR=""$' || true)
    _am_sed=$(live_src "$_df" | grep -cF 's|archive.ubuntu.com|${APT_ARCHIVE_MIRROR}|g' || true)
    if [ "$_am_arg" = 1 ] && [ "$_am_sed" -ge 1 ]; then
        pass "$(basename "$_df"): conditional archive-mirror rewrite (ARG + sed, gated on non-empty)"
    else
        fail "$(basename "$_df") archive-mirror machinery: ARG=$_am_arg sed=$_am_sed"
    fi
done

# --- skip accounting + strict lever (issue #480: F3/F33/F34/F35) ---------------
# The E2E_STRICT lever (every e2e lane's dispatch input, pinned in
# test-workflows.sh) turns counted skips into failures — it only works
# when every skip site routes through lib.sh's skip(). A hand-incremented
# tally next to a custom SKIP echo is invisible to the lever AND drifts
# from the detail lines printed. Raw absence pins (a commented-out
# forbidden line still trips, the documented semantics) plus positive
# controls on lib.sh so nothing passes vacuously.
for _r in "$RUN_SH" "$RUN_ROOTLESS" "$RUN_DDEV"; do
    check_absent "$(basename "$_r"): no hand-incremented skip tally (all skips via skip(), #480 F3)" \
        "$_r" -F -- 'skipped=$((skipped'
    check_absent "$(basename "$_r"): no uncounted 'skipped:' echo line (#480 F35)" \
        "$_r" -F -- 'echo "  skipped:'
    check_absent "$(basename "$_r"): no rc leg measured behind a tee pipe (dash rc is tee's, #480 F34)" \
        "$_r" -nE '\| *tee [^|]*; *test *\$\?'
done
check_live "lib.sh skip() owns the skip tally (the lever's anchor, #480 F3)" "$LIB" \
    -qF 'skipped=$((skipped + 1))'
check_live "lib.sh skip() escalates to a failure under E2E_STRICT=1" "$LIB" \
    -qF '[ "${E2E_STRICT:-0}" = "1" ]'

# Double-count window (issue #480 F33): one failed event = one failure.
# The pre-fix shape incremented the tally before AND after the log dump
# (2-3 lines apart); genuinely separate failures always sit farther
# apart (an exit/fi and the next guard between them). Positive control:
# the pattern matches run-ddev.sh's 19 live increments (verified in the
# wave), so the pin cannot pass vacuously at zero.
_dc_sites=""
for _r in "$RUN_SH" "$RUN_ROOTLESS" "$RUN_DDEV"; do
    _hits="$(awk '/failures=\$\(\(failures \+ 1\)\)/ { if (_p && NR - _p < 4) print _p ":" NR; _p = NR }' "$_r")"
    [ -n "$_hits" ] && _dc_sites="$_dc_sites $(basename "$_r"):$_hits"
done
if [ -z "$_dc_sites" ]; then
    pass "runners: no failure tally incremented twice within one event window (#480 F33)"
else
    fail "failure tallies double-counted (two increments < 4 lines apart):$_dc_sites"
fi
# Vacuous-pass control (#494 a F3): the window pin consumes the awk in a
# $( ) — empty output (pattern regression, quoting slip) would pass at
# zero forever. This arm proves the SAME pattern still sees run-ddev.sh's
# live increments, so a zero-match window result means "clean", not
# "blind".
check "double-count pattern still matches live increments (vacuous-pass control, #494 a F3)" \
    awk '/failures=\$\(\(failures \+ 1\)\)/ { n++ } END { exit !(n >= 1) }' "$RUN_DDEV"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All e2e binary source tests passed.$NC"
exit 0
