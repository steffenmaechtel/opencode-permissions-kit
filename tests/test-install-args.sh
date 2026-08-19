#!/bin/sh
# Unit tests for install.sh's parse_args():
#   - flags work in any order (the old loop broke after --projects and
#     silently dropped every flag that followed it)
#   - --projects consumes all following non-flag args, parsing continues
#   - unknown options abort instead of being silently ignored
#   - --container-backend without a value aborts
#
# Static extraction of parse_args() from install.sh, then table-driven
# checks. No root required.
# Run: sh tests/test-install-args.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../files/install.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

extract_fn() {
    sed -n '/^parse_args() {/,/^}/p' "$1"
}

if [ -n "$(extract_fn "$INSTALL")" ]; then
    pass "parse_args defined in install.sh"
else
    fail "parse_args defined in install.sh"
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi

eval "$(extract_fn "$INSTALL")"

reset_globals() {
    SKIP_PROMPTS=false
    PREDEFINED_PROJECTS=""
    SECURE_GIT_CONFIG=true
    GIT_FLAG_GIVEN=""
    CONTAINER_BACKEND_OPT=""
    SKIP_DDEV_MIGRATION=false
}

# expect_rc <want-rc> <description> <args...>
# Runs parse_args in a SUBSHELL: the function exits on bad input, and that
# exit must terminate only the subshell, not this test script.
expect_rc() {
    _want="$1"; _desc="$2"; shift 2
    reset_globals
    if [ "$_want" = "0" ]; then
        if parse_args "$@" 2>/dev/null; then
            pass "$_desc"
        else
            fail "$_desc (unexpected abort)"
        fi
    else
        if ( parse_args "$@" ) 2>/dev/null; then
            fail "$_desc (should have aborted)"
        else
            pass "$_desc"
        fi
    fi
}

# --- accepted invocations ----------------------------------------------------

reset_globals
parse_args --yes
[ "$SKIP_PROMPTS" = true ] && pass "--yes sets SKIP_PROMPTS" || fail "--yes sets SKIP_PROMPTS"

reset_globals
parse_args --secure-git-config
[ "$SECURE_GIT_CONFIG" = true ] && [ "$GIT_FLAG_GIVEN" = true ] \
    && pass "--secure-git-config sets the flag + marker" \
    || fail "--secure-git-config sets the flag + marker"

reset_globals
parse_args --container-backend podman-rootless
[ "$CONTAINER_BACKEND_OPT" = "podman-rootless" ] \
    && pass "--container-backend captures its value" \
    || fail "--container-backend captures its value"

reset_globals
parse_args --skip-ddev-migration
[ "$SKIP_DDEV_MIGRATION" = true ] \
    && pass "--skip-ddev-migration sets the flag" \
    || fail "--skip-ddev-migration sets the flag"

reset_globals
parse_args --yes
[ "$SKIP_DDEV_MIGRATION" = false ] \
    && pass "ddev migration stays ON by default" \
    || fail "ddev migration stays ON by default"

# The regression this file exists for: flags AFTER --projects used to be
# silently dropped (the old loop `break`ed out of the parser).
reset_globals
parse_args --projects /var/www/vhosts /home/dev/x --yes --secure-git-config
if [ "$SKIP_PROMPTS" = true ] && [ "$GIT_FLAG_GIVEN" = true ] \
    && [ "$PREDEFINED_PROJECTS" = " /var/www/vhosts /home/dev/x" ]; then
    pass "--projects does not swallow following flags (--yes/--secure-git-config applied)"
else
    fail "--projects does not swallow following flags (projects='$PREDEFINED_PROJECTS' yes=$SKIP_PROMPTS git=$GIT_FLAG_GIVEN)"
fi

# --container-backend AFTER --projects works too (docs used to require the
# opposite order).
reset_globals
parse_args --projects /var/www/vhosts --container-backend docker-rootless
[ "$CONTAINER_BACKEND_OPT" = "docker-rootless" ] \
    && pass "--container-backend works after --projects" \
    || fail "--container-backend works after --projects"

# A flag directly after the --projects list stops project consumption and
# is parsed as a flag; a path starting with '-' is not a project root.
reset_globals
parse_args --yes --projects --container-backend docker-rootless
[ "$PREDEFINED_PROJECTS" = "" ] && [ "$CONTAINER_BACKEND_OPT" = "docker-rootless" ] \
    && pass "--projects with no roots keeps parsing (--container-backend applied)" \
    || fail "--projects with no roots keeps parsing (projects='$PREDEFINED_PROJECTS')"

# --- rejected invocations ----------------------------------------------------

expect_rc 1 "unknown option aborts" --yes --bogus
expect_rc 1 "--container-backend without a value aborts" --yes --container-backend
expect_rc 1 "typo'd flag aborts (--ye)" --ye

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All install.sh arg-parsing tests passed.${NC}"
exit 0
