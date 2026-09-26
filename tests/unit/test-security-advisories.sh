#!/bin/sh
# Unit tests for the known security advisories database (issue #107):
#   - sh/advisories.sh sources clean and its helpers behave (version
#     parsing for 1.x/2.x --version lines, sort -V comparisons, range
#     conjunctions, channel matching)
#   - every shipped record is well-formed (7 fields, valid vocabulary)
#   - the shipped database matches affected installs and — the headline
#     property — does NOT warn for patched versions or non-matching
#     channels (kit installs are 'standalone', GHSA-632h-h47v-g4x4 is
#     npm-only)
#   - the wrapper and status.sh wiring exists (fresh --version probe with
#     timeout, warning + upgrade hint, upstream live check)
# No root, no network — the upstream feed is only faked in fixtures.
# Run: sh tests/unit/test-security-advisories.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/advisories.sh"
WRAPPER="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
STATUS="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

# shellcheck disable=SC1090  # the shipped database, checked below
[ -f "$LIB" ] && . "$LIB"

# --- 1. version parsing ----------------------------------------------------------

[ "$(advisories_version_of "1.18.31")" = "1.18.31" ] \
    && pass "version_of: 1.x bare line (1.18.31)" \
    || fail "version_of: 1.x bare line (got '$(advisories_version_of "1.18.31")')"
[ "$(advisories_version_of "opencode v2.0.11")" = "2.0.11" ] \
    && pass "version_of: 2.x prefixed line (opencode v2.0.11 -> 2.0.11)" \
    || fail "version_of: 2.x prefixed line (got '$(advisories_version_of "opencode v2.0.11")')"
[ -z "$(advisories_version_of "unknown")" ] \
    && pass "version_of: garbage yields empty" \
    || fail "version_of: garbage yields empty (got '$(advisories_version_of "unknown")')"
[ -z "$(advisories_version_of "")" ] \
    && pass "version_of: empty yields empty" \
    || fail "version_of: empty yields empty"

# --- 2. comparisons ---------------------------------------------------------------

[ "$(advisories_version_cmp 1.18.31 1.18.22)" = "gt" ] \
    && pass "version_cmp: 1.18.31 > 1.18.22" \
    || fail "version_cmp: 1.18.31 > 1.18.22"
[ "$(advisories_version_cmp 2.0.11 2.0.11)" = "eq" ] \
    && pass "version_cmp: 2.0.11 = 2.0.11" \
    || fail "version_cmp: 2.0.11 = 2.0.11"
[ "$(advisories_version_cmp 1.0.216 1.1.10)" = "lt" ] \
    && pass "version_cmp: 1.0.216 < 1.1.10" \
    || fail "version_cmp: 1.0.216 < 1.1.10"
# segment order, not lexicographic: 1.10.0 > 1.9.0
[ "$(advisories_version_cmp 1.10.0 1.9.0)" = "gt" ] \
    && pass "version_cmp: 1.10.0 > 1.9.0 (segment order, not lexicographic)" \
    || fail "version_cmp: 1.10.0 > 1.9.0 (segment order, not lexicographic)"

# --- 3. ranges ---------------------------------------------------------------------

if advisory_range_holds 1.14.30 ">=1.14.30"; then
    pass "range: boundary version is inside (>= includes)"
else
    fail "range: boundary version is inside (>= includes)"
fi
if advisory_range_holds 1.14.29 ">=1.14.30"; then
    fail "range: version below a >= range is outside"
else
    pass "range: version below a >= range is outside"
fi
if advisory_range_holds 1.18.22 "<1.18.22"; then
    fail "range: patched version is outside a < range"
else
    pass "range: patched version is outside a < range"
fi
if advisory_range_holds 1.18.21 ">=1.14.30,<1.18.22"; then
    pass "range: conjunction holds inside the window"
else
    fail "range: conjunction holds inside the window"
fi
if advisory_range_holds 1.18.22 ">=1.14.30,<1.18.22"; then
    fail "range: conjunction closes at the patched version"
else
    pass "range: conjunction closes at the patched version"
fi
if advisory_range_holds 1.1.10 ">= 1.0.0, < 1.1.10"; then
    fail "range: spaces inside comparators are tolerated"
else
    pass "range: spaces inside comparators are tolerated"
fi
if advisory_range_holds 1.1.10 "1.1.10"; then
    pass "range: bare version is an exact match"
else
    fail "range: bare version is an exact match"
fi
if advisory_range_holds 1.1.10 "not-a-range"; then
    fail "range: malformed comparator fails safe (outside)"
else
    pass "range: malformed comparator fails safe (outside)"
fi
if advisory_range_holds "" ">=1.0.0"; then
    fail "range: empty version fails safe (outside)"
else
    pass "range: empty version fails safe (outside)"
fi

# --- 4. shipped record shape ---------------------------------------------------------

shape_ok=true
shape_msg=""
while IFS= read -r rec; do
    case "$rec" in
        ''|'#'*) continue ;;
    esac
    IFS='|' read -r R_PKG R_RANGES R_PATCHED R_CHANNEL R_SEV R_ID R_SUMMARY R_EXTRA <<EOF
$rec
EOF
    [ -z "$R_EXTRA" ] || { shape_ok=false; shape_msg="$shape_msg [$R_ID: more than 7 fields]"; continue; }
    [ -n "$R_PKG" ] && [ -n "$R_RANGES" ] && [ -n "$R_PATCHED" ] && [ -n "$R_ID" ] && [ -n "$R_SUMMARY" ] \
        || { shape_ok=false; shape_msg="$shape_msg [$R_ID: empty required field]"; continue; }
    case "$R_CHANNEL" in
        ''|npm|standalone) ;;
        *) shape_ok=false; shape_msg="$shape_msg [$R_ID: unknown channel '$R_CHANNEL']" ;;
    esac
    case "$R_SEV" in
        low|moderate|high|critical) ;;
        *) shape_ok=false; shape_msg="$shape_msg [$R_ID: unknown severity '$R_SEV']" ;;
    esac
    printf '%s' "$R_ID" | grep -q '^GHSA-[0-9a-z-]*$' \
        || { shape_ok=false; shape_msg="$shape_msg [$R_ID: not a GHSA id]"; }
    # every comparator of every range must parse
    _rest="$R_RANGES,"
    while [ -n "$_rest" ]; do
        _c="${_rest%%,*}"
        _rest="${_rest#*,}"
        _c=$(printf '%s' "$_c" | tr -d ' ')
        [ -n "$_c" ] || continue
        printf '%s' "$_c" | grep -qE '^(>=|<=|<|>|=)?[0-9]+(\.[0-9]+)*$' \
            || { shape_ok=false; shape_msg="$shape_msg [$R_ID: bad comparator '$_c']"; }
    done
done <<EOF
$ADVISORY_RECORDS
EOF
if [ "$shape_ok" = true ]; then
    pass "every shipped record is well-formed (7 fields, vocabulary, comparators)"
else
    fail "shipped record shape:$shape_msg"
fi

# --- 5. matching against the shipped database ------------------------------------------

if printf '%s' "$(advisories_matching opencode 1.18.21 npm)" | grep -q 'GHSA-632h-h47v-g4x4'; then
    pass "matching: npm-managed 1.18.21 hits GHSA-632h-h47v-g4x4"
else
    fail "matching: npm-managed 1.18.21 hits GHSA-632h-h47v-g4x4"
fi
# the headline property: kit installs are 'standalone', the advisory is npm-only
if [ -z "$(advisories_matching opencode 1.18.21 standalone)" ]; then
    pass "matching: standalone 1.18.21 (kit installs) does NOT hit the npm-only advisory"
else
    fail "matching: standalone 1.18.21 (kit installs) does NOT hit the npm-only advisory"
fi
if [ -z "$(advisories_matching opencode 1.18.22 npm)" ]; then
    pass "matching: patched 1.18.22 does not hit"
else
    fail "matching: patched 1.18.22 does not hit"
fi
if [ -z "$(advisories_matching opencode 1.14.29 npm)" ]; then
    pass "matching: 1.14.29 (below the range) does not hit"
else
    fail "matching: 1.14.29 (below the range) does not hit"
fi
# any-channel records hit regardless of the channel
if printf '%s' "$(advisories_matching opencode 1.0.100 standalone)" | grep -q 'GHSA-vxw4-wv6m-9hhh'; then
    pass "matching: any-channel record hits standalone 1.0.100"
else
    fail "matching: any-channel record hits standalone 1.0.100"
fi
if printf '%s' "$(advisories_matching opencode 1.0.100 npm)" | grep -q 'GHSA-vxw4-wv6m-9hhh'; then
    pass "matching: any-channel record hits npm 1.0.100"
else
    fail "matching: any-channel record hits npm 1.0.100"
fi
if [ -z "$(advisories_matching ddev 1.18.21 npm)" ]; then
    pass "matching: other packages do not hit opencode records"
else
    fail "matching: other packages do not hit opencode records"
fi

# --- 6. ids ------------------------------------------------------------------------------

_ids=$(advisories_ids opencode)
for want_id in GHSA-632h-h47v-g4x4 GHSA-c83v-7274-4vgp GHSA-vxw4-wv6m-9hhh; do
    if printf '%s\n' "$_ids" | grep -qxF "$want_id"; then
        pass "ids: $want_id known"
    else
        fail "ids: $want_id known"
    fi
done

# --- 7. wiring -----------------------------------------------------------------------------

if grep -q '/sh/advisories.sh' "$WRAPPER" \
   && grep -q "WARNING: the installed opencode .* is affected by a known security advisory" "$WRAPPER" \
   && grep -q "Please upgrade opencode with 'opk upgrade-opencode'" "$WRAPPER"; then
    pass "wrapper: sources the database, warns, hints the upgrade command"
else
    fail "wrapper: sources the database, warns, hints the upgrade command"
fi
# the --version early-exec must stay ahead of the advisory block: scripts and
# the official installer parse that output, the warning must never pollute it
_verline=$(grep -n -m1 -- '--version|-v|-h|--help)' "$WRAPPER" | cut -d: -f1)
_advline=$(grep -n -m1 '/sh/advisories.sh' "$WRAPPER" | cut -d: -f1)
if [ -n "$_verline" ] && [ -n "$_advline" ] && [ "$_verline" -lt "$_advline" ]; then
    pass "wrapper: --version early-exec stays ahead of the advisory check"
else
    fail "wrapper: --version early-exec stays ahead of the advisory check ($_verline vs $_advline)"
fi
if grep -q 'timeout 5 /usr/bin/sudo -n -u opencode /usr/local/lib/opencode-permissions-kit/bin/opencode --version' "$WRAPPER"; then
    pass "wrapper: the --version probe is timeout-bounded (wedged 2.x service, issue #80)"
else
    fail "wrapper: the --version probe is timeout-bounded (wedged 2.x service, issue #80)"
fi
if grep -q 'ui_section "Security advisories"' "$STATUS" \
   && grep -q 'https://api.github.com/repos/anomalyco/opencode/security-advisories' "$STATUS" \
   && grep -q 'opk upgrade-opencode' "$STATUS"; then
    pass "status.sh: advisory section, upstream live check, upgrade hint"
else
    fail "status.sh: advisory section, upstream live check, upgrade hint"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All security advisory tests passed.$NC"
exit 0
