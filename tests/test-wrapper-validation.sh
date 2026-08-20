#!/bin/sh
# Test wrapper directory validation logic.
# Creates temp directories and projects.conf, then tests various CWD scenarios.
# Run: ./tests/test-wrapper-validation.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

failures=0
passed=0

assert_valid() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        expected: $expected  got: $actual"
        failures=$((failures + 1))
    fi
}

# Run the wrapper's validation logic against a given CWD and projects.conf.
# Prints "valid" or "invalid" to stdout.
validate_dir() {
    local cwd="$1" conf="$2"

    CWD="$cwd"
    PROJECTS_CONF="$conf"
    VALID=false
    if [ -f "$PROJECTS_CONF" ]; then
        while IFS= read -r root; do
            [ -z "$root" ] && continue
            [ ! -d "$root" ] && continue
            root_clean="${root%/}"
            if [ "$CWD" = "$root_clean" ] || [ "${CWD#$root_clean/}" != "$CWD" ]; then
                VALID=true
                break
            fi
        done < "$PROJECTS_CONF"
    fi

    if [ "$VALID" = true ]; then
        echo "valid"
    else
        echo "invalid"
    fi
}

# Replicate the wrapper's version banner logic: read VERSION from the
# install.conf, defaulting to 0.0.0. printf '%b' is used (not echo) so the
# \033 escapes render identically under dash and bash — matching the
# wrapper's colored banner.
banner_line() {
    local conf="$1"
    VERSION="0.0.0"
    if [ -f "$conf" ]; then
        . "$conf"
    fi
    printf '%b\n' "  ${GREEN}SECURED BY opencode permissions kit (${VERSION})${NC}"
}

# --- Setup temp directories ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/project-a"
mkdir -p "$TMPDIR/project-a/sub"
mkdir -p "$TMPDIR/project-a/deep/nested"
mkdir -p "$TMPDIR/project-b"
mkdir -p "$TMPDIR/project-ab"          # partial name match trap
mkdir -p "$TMPDIR/other"

echo ""
echo "Wrapper Directory Validation Tests"
echo "===================================="
echo ""

# --- Test 1: Exact match ---
echo "--- Exact match ---"
printf '%s\n' "$TMPDIR/project-a" > "$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_valid "exact match on root" "valid" "$result"

# --- Test 2: First-level subdirectory ---
result=$(validate_dir "$TMPDIR/project-a/sub" "$TMPDIR/projects.conf")
assert_valid "first-level subdirectory" "valid" "$result"

# --- Test 3: Deep nested subdirectory ---
result=$(validate_dir "$TMPDIR/project-a/deep/nested" "$TMPDIR/projects.conf")
assert_valid "deep nested subdirectory" "valid" "$result"

# --- Test 4: Partial name match (different dir) ---
result=$(validate_dir "$TMPDIR/project-ab" "$TMPDIR/projects.conf")
assert_valid "partial name match (project-ab vs project-a)" "invalid" "$result"

# --- Test 5: Shorter prefix (project-a/ vs project) ---
result=$(validate_dir "$TMPDIR/other" "$TMPDIR/projects.conf")
assert_valid "unrelated directory" "invalid" "$result"

# --- Test 6: Home directory ---
result=$(validate_dir "$HOME" "$TMPDIR/projects.conf")
assert_valid "home directory (not in projects.conf)" "invalid" "$result"

# --- Test 7: Multiple roots ---
printf '%s\n' "$TMPDIR/project-a" "$TMPDIR/project-b" > "$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-b" "$TMPDIR/projects.conf")
assert_valid "second root in multi-root config" "valid" "$result"

result=$(validate_dir "$TMPDIR/project-a/sub" "$TMPDIR/projects.conf")
assert_valid "subdirectory of first root in multi-root config" "valid" "$result"

result=$(validate_dir "$TMPDIR/other" "$TMPDIR/projects.conf")
assert_valid "unrelated dir in multi-root config" "invalid" "$result"

# --- Test 8: Root with trailing slash in config ---
printf '%s\n' "$TMPDIR/project-a/" > "$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_valid "trailing-slash root: exact CWD" "valid" "$result"

result=$(validate_dir "$TMPDIR/project-a/sub" "$TMPDIR/projects.conf")
assert_valid "trailing-slash root: subdirectory" "valid" "$result"

# --- Test 9: CWD with trailing slash ---
printf '%s\n' "$TMPDIR/project-a" > "$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a/" "$TMPDIR/projects.conf")
assert_valid "CWD with trailing slash" "valid" "$result"

# --- Test 10: Empty projects.conf ---
true > "$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_valid "empty projects.conf" "invalid" "$result"

# --- Test 11: Missing projects.conf ---
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/no-such-file.conf")
assert_valid "missing projects.conf" "invalid" "$result"

# --- Test 12: Line with whitespace / blank lines ---
printf '\n%s\n\n%s\n\n' "$TMPDIR/project-a" "$TMPDIR/project-b" > "$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_valid "blank lines in projects.conf: valid" "valid" "$result"

result=$(validate_dir "$TMPDIR/other" "$TMPDIR/projects.conf")
assert_valid "blank lines in projects.conf: invalid" "invalid" "$result"

# --- Test 13: Non-existent directory in projects.conf (should skip) ---
printf '%s\n%s\n' "$TMPDIR/project-a" "$TMPDIR/project-nonexistent" > "$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_valid "skips non-existent entry, matches valid one" "valid" "$result"

# --- Version banner ---
echo ""
echo "--- Version banner ---"

printf 'DEFAULT_USER=dev\nVERSION=1.2.3\n' > "$TMPDIR/install.conf"
result=$(banner_line "$TMPDIR/install.conf")
assert_valid "banner shows version from install.conf" \
    "$(printf '%b' "  ${GREEN}SECURED BY opencode permissions kit (1.2.3)${NC}")" "$result"

result=$(banner_line "$TMPDIR/no-such-install.conf")
assert_valid "banner defaults to 0.0.0 when no conf exists" \
    "$(printf '%b' "  ${GREEN}SECURED BY opencode permissions kit (0.0.0)${NC}")" "$result"

printf 'DEFAULT_USER=dev\n' > "$TMPDIR/no-version.conf"
result=$(banner_line "$TMPDIR/no-version.conf")
assert_valid "banner defaults to 0.0.0 when conf has no VERSION line" \
    "$(printf '%b' "  ${GREEN}SECURED BY opencode permissions kit (0.0.0)${NC}")" "$result"

# --- Soft-only model (DDEV-WORKING phase 2) ---
echo ""
echo "--- Soft-only wrapper/sudoers shape ---"

WRAPPER_FILE="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/wrapper"
SUDOERS_FILE="$SCRIPT_DIR/../files/sudoers.template"

if ! grep -q 'protect-projects' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper no longer calls protect-projects"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper still references protect-projects"
    failures=$((failures + 1))
fi

if ! grep -qE '\-g\|--gid' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper has no -g/--gid docker parsing"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper still parses -g/--gid"
    failures=$((failures + 1))
fi

if ! grep -q 'OPENCODE_LAUNCH_CWD' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper does not stamp OPENCODE_LAUNCH_CWD"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper still stamps OPENCODE_LAUNCH_CWD"
    failures=$((failures + 1))
fi

if ! grep -q 'CONTAINER_GROUP=' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper has no docker-group escalation variable"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper still escalates via CONTAINER_GROUP"
    failures=$((failures + 1))
fi

if grep -q 'jsonc-parser.py --tools' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper keeps --tools project detection"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper lost --tools detection"
    failures=$((failures + 1))
fi

if grep -q 'DOCKER_HOST' "$WRAPPER_FILE" && grep -q 'XDG_RUNTIME_DIR' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper exports DOCKER_HOST/XDG_RUNTIME_DIR for rootless"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper lost the rootless env exports"
    failures=$((failures + 1))
fi

if grep -q 'sudo -u opencode' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper still execs via sudo -u opencode"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper lost the sudo -u opencode exec"
    failures=$((failures + 1))
fi

# --- Version/help passthrough from an invalid CWD ---
# The official opencode installer probes `opencode --version` from $HOME
# (an invalid directory) while the kit installs; the wrapper must answer
# from the real binary instead of refusing (regression: the mid-install
# "ERROR: opencode cannot be started here" confused users).
if grep -A14 'if \[ "\$VALID" != true \]' "$WRAPPER_FILE" | grep -q -- '--version'; then
    echo "  ${GREEN}PASS${NC}  wrapper answers --version from an invalid CWD (installer probe)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper refuses --version outside a project directory"
    failures=$((failures + 1))
fi

if grep -A14 'if \[ "\$VALID" != true \]' "$WRAPPER_FILE" | grep -q 'bin/opencode "\$@"'; then
    echo "  ${GREEN}PASS${NC}  invalid-CWD version passthrough execs the secured binary"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  invalid-CWD version passthrough lost the binary exec"
    failures=$((failures + 1))
fi

# The passthrough must precede the refusal (exec replaces the process, the
# ERROR banner must stay unreachable for version/help args).
if [ "$(grep -n -- '--version' "$WRAPPER_FILE" | head -1 | cut -d: -f1)" -lt "$(grep -n 'ERROR: opencode cannot be started here' "$WRAPPER_FILE" | head -1 | cut -d: -f1)" ]; then
    echo "  ${GREEN}PASS${NC}  passthrough is checked before the refusal"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  refusal runs before the version passthrough"
    failures=$((failures + 1))
fi

# --- Headless serve mode (third-party UIs like OpenChamber) ---
# OpenChamber et al. spawn `opencode serve` with stdin ignored and parse
# stdout for the "opencode server listening on <url>" line. The wrapper
# must not banner/prompt there (read-on-EOF + set -e would kill it before
# the exec) and must keep stdout clean.
echo ""
echo "--- Serve mode (headless, third-party UIs) ---"

if grep -q 'if \[ "${1:-}" = "serve" \]; then SERVE_MODE=true; fi' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper detects the serve subcommand"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper lost serve detection"
    failures=$((failures + 1))
fi

if grep -q 'if \[ "\$VALID" != true \] && \[ "\$SERVE_MODE" != true \]; then' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  serve mode skips the project-dir refusal"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve mode still bound to project-dir validation"
    failures=$((failures + 1))
fi

if [ "$(grep -n 'SERVE_MODE" != true \]; then' "$WRAPPER_FILE" | tail -1 | cut -d: -f1)" -lt "$(grep -n 'Press Enter to start opencode' "$WRAPPER_FILE" | head -1 | cut -d: -f1)" ]; then
    echo "  ${GREEN}PASS${NC}  serve mode suppresses the Press-Enter prompt"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve mode would still block on Press Enter"
    failures=$((failures + 1))
fi

if grep -A8 '^note()' "$WRAPPER_FILE" | grep -q '>&"\$_fd"\|>&\$_fd' && grep -A8 '^note()' "$WRAPPER_FILE" | grep -q '_fd=2'; then
    echo "  ${GREEN}PASS${NC}  serve-mode diagnostics go to stderr (note helper)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve-mode diagnostics would pollute stdout"
    failures=$((failures + 1))
fi

if grep -q 'if \[ "\$SERVE_MODE" = true \]; then' "$WRAPPER_FILE" && grep -q 'CONTAINER_AUTO=false' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  serve mode requests container tools without prompting"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve mode lost the silent container-tool request"
    failures=$((failures + 1))
fi

if grep -q 'OPENCODE_SERVER_PASSWORD' "$SUDOERS_FILE"; then
    echo "  ${GREEN}PASS${NC}  sudoers.template keeps OPENCODE_SERVER_PASSWORD across sudo"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  sudoers.template drops OPENCODE_SERVER_PASSWORD (headless serve loses auth)"
    failures=$((failures + 1))
fi

for marker in '#@docker-group-begin' '#@ddev-delegated-begin' '#@ddev-sandbox-begin' 'DDEV_BIN' 'OPENCODE_LAUNCH_CWD' 'protect-projects'; do
    if ! grep -q "$marker" "$SUDOERS_FILE"; then
        echo "  ${GREEN}PASS${NC}  sudoers.template free of '$marker'"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  sudoers.template still contains '$marker'"
        failures=$((failures + 1))
    fi
done

if grep -q 'env_keep += "DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD DDEV_DEBUG"' "$SUDOERS_FILE" \
   && grep -q '(opencode) NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/opencode' "$SUDOERS_FILE" \
   && grep -q 'socket-check.sh' "$SUDOERS_FILE"; then
    echo "  ${GREEN}PASS${NC}  sudoers.template keeps base RunAs + socket-check + env_keep"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  sudoers.template lost a required rule"
    failures=$((failures + 1))
fi

# --- Summary ---
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
else
    echo "  All tests passed."
fi
echo ""

[ "$failures" -eq 0 ] && exit 0 || exit 1
