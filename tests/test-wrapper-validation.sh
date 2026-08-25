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

# --- Headless mode (third-party UIs + orchestrators, issue #42) ---
# Ecosystem tools spawn opencode non-interactively: `opencode serve`
# (OpenChamber, cezar, CodeWalk — stdout parsed for the "listening on"
# line), `opencode run` (CI/eval harnesses, `--format json` stdout),
# `opencode acp` (JSON-RPC over stdio) and query subcommands. The wrapper
# must keep stdout machine-clean and must not refuse non-project CWDs
# there (worktrees, temp checkouts).
echo ""
echo "--- Headless mode (third-party tools) ---"

if grep -q '^HEADLESS=false' "$WRAPPER_FILE" && grep -q 'serve|acp|models|agent|providers' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper classifies headless subcommands (serve/acp/queries)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper lost headless subcommand classification"
    failures=$((failures + 1))
fi

if grep -q 'if \[ "\$VALID" != true \] && \[ "\$HEADLESS" != true \]; then' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  headless mode skips the project-dir refusal"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  headless mode still bound to project-dir validation"
    failures=$((failures + 1))
fi

# Classification is executable: extract the block and run it against
# representative argument vectors (same static-extraction technique as
# test-status.sh). tty-less CI makes `run` (no message) headless via the
# stdin check — an interactive terminal would keep it bannered; that
# branch is covered by the `-t 0` grep below.
HL_BLOCK="$(sed -n '/^HEADLESS=false/,/^esac/p' "$WRAPPER_FILE")"
[ -n "$HL_BLOCK" ] || { echo "  ${RED}FAIL${NC}  headless block not extractable"; failures=$((failures + 1)); }
hl_case() { # <desc> <expected> <args...>
    _desc="$1"; _want="$2"; shift 2
    _got=$(set -- "$@"; eval "$HL_BLOCK"; echo "$HEADLESS")
    if [ "$_got" = "$_want" ]; then
        echo "  ${GREEN}PASS${NC}  headless: $_desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  headless: $_desc (want=$_want got=$_got)"
        failures=$((failures + 1))
    fi
}
hl_case "serve is headless"             true  serve
hl_case "run with message is headless"  true  run "fix the bug"
hl_case "run --format json is headless" true  run --format json "hi"
hl_case "acp is headless"               true  acp
hl_case "models is headless"            true  models
hl_case "export is headless"            true  export sess-123
hl_case "tui stays interactive"         false  tui
hl_case "attach stays interactive"      false  attach
hl_case "no args stays interactive"     false
hl_case "flags-only start stays interactive" false --debug

if grep -q '\-t 0' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  run without message checks stdin tty (piped = headless)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  run lost the interactive-tty distinction"
    failures=$((failures + 1))
fi

if grep -q 'if \[ "${1:-}" = "serve" \]; then' "$WRAPPER_FILE" && grep -q 'CONTAINER_AUTO=false' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  serve requests container tools without prompting"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve lost the silent container-tool request"
    failures=$((failures + 1))
fi

if grep -q 'Press Enter to start opencode' "$WRAPPER_FILE"; then
    echo "  ${RED}FAIL${NC}  wrapper still pauses on Press Enter (removed 0.0.21)"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  no Press-Enter pause (removed 0.0.21 — the TUI shows the kit mode)"
    passed=$((passed + 1))
fi

if grep -q 'Run opencode with .*?\[Y/n\]\|Run opencode with %s? \[Y/n\]' "$WRAPPER_FILE" || grep -qF '"[Y/n]"' "$WRAPPER_FILE"; then
    echo "  ${RED}FAIL${NC}  wrapper still asks the [Y/n] container question (removed 0.0.21)"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  no [Y/n] container question (removed 0.0.21 — state is visible in the TUI)"
    passed=$((passed + 1))
fi

if grep -q 'read -r answer' "$WRAPPER_FILE"; then
    echo "  ${RED}FAIL${NC}  wrapper still reads an interactive answer"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  wrapper is prompt-free (no interactive reads left)"
    passed=$((passed + 1))
fi

if grep -A8 '^note()' "$WRAPPER_FILE" | grep -q '>&"\$_fd"\|>&\$_fd' && grep -A8 '^note()' "$WRAPPER_FILE" | grep -q '_fd=2'; then
    echo "  ${GREEN}PASS${NC}  headless diagnostics go to stderr (note helper)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  headless diagnostics would pollute stdout"
    failures=$((failures + 1))
fi

# The container-tools advisory must also route through note() — a raw
# printf to stdout would pollute `opencode run --format json` output.
if ! grep -q 'printf "  ${GREEN}opencode will run with' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  container advisory uses note() (stdout-safe for orchestrators)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  container advisory prints raw to stdout"
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

if grep -q 'env_keep += "DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME DDEV_DEBUG"' "$SUDOERS_FILE" \
   && grep -q '(opencode) NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/opencode' "$SUDOERS_FILE" \
   && grep -q 'socket-check.sh' "$SUDOERS_FILE"; then
    echo "  ${GREEN}PASS${NC}  sudoers.template keeps base RunAs + socket-check + env_keep"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  sudoers.template lost a required rule"
    failures=$((failures + 1))
fi

# --- Headless serve cwd probe (OpenChamber HTTP 500 fix) ---
# OpenChamber spawns `opencode serve` with the developer's $HOME as cwd;
# the opencode user cannot read it (UID separation), so config load for
# that directory turns into HTTP 500. The wrapper probes readability via
# cwd-check.sh (as the opencode user) and falls back to a readable
# projects root, warning on stderr.
echo ""
echo "--- Headless serve cwd probe ---"

CWD_CHECK="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/bin/cwd-check.sh"

# functional: the helper itself (it only stats — runs as the test user)
result=$(sh "$CWD_CHECK" "$TMPDIR/project-a")
assert_valid "cwd-check: existing readable dir reports readable" "readable" "$result"

result=$(sh "$CWD_CHECK" "$TMPDIR/no-such-dir")
assert_valid "cwd-check: missing dir reports unreadable" "unreadable" "$result"

result=$(sh "$CWD_CHECK" "")
assert_valid "cwd-check: empty argument reports unreadable" "unreadable" "$result"

sh "$CWD_CHECK" "$TMPDIR/no-such-dir" >/dev/null 2>&1
assert_valid "cwd-check: always exits 0 (empty output = probe unavailable)" "0" "$?"

# functional: the wrapper's fallback selection (block extracted and run
# with a stubbed cwd_probe — same static-extraction technique as HL_BLOCK)
SC_BLOCK="$(sed -n '/^if \[ "\${1:-}" = "serve" \] &&/,/^# Rootless: pass the per-user socket/p' "$WRAPPER_FILE" | sed '$d')"
if [ -n "$SC_BLOCK" ]; then
    echo "  ${GREEN}PASS${NC}  serve cwd block extractable"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve cwd block not extractable"
    failures=$((failures + 1))
fi

# sc_serve <cwd> <readable-dirs, space-separated> — runs the extracted
# block with $1=serve, a stubbed cwd_probe and a silent note(); prints
# "fallback=<dir|none> pwd=<dir> warn=<0|1>"
sc_serve() {
    _cwd="$1"; _readable="$2"
    (
        set -- serve
        CWD="$_cwd"
        PROJECTS_CONF="$TMPDIR/sc-projects.conf"
        SERVE_FALLBACK=""
        _warned=0
        RED='' GREEN='' CYAN='' YELLOW='' NC=''
        note() { if [ -n "$1" ]; then _warned=1; fi; }
        cwd_probe() {
            case " $_readable " in *" $1 "*) echo readable ;; *) echo unreadable ;; esac
        }
        eval "$SC_BLOCK"
        printf 'fallback=%s pwd=%s warn=%s\n' "${SERVE_FALLBACK:-none}" "$(pwd)" "$_warned"
    )
}

mkdir -p "$TMPDIR/sc-root-a" "$TMPDIR/sc-root-b" "$TMPDIR/sc-root-b/sub"
printf '%s\n' "$TMPDIR/sc-root-a" "$TMPDIR/sc-root-b" > "$TMPDIR/sc-projects.conf"

# OpenChamber case: cwd unrelated to any root (like $HOME), both roots
# readable -> first configured readable root wins, warning printed, cd done
result=$(sc_serve "$TMPDIR/other" "$TMPDIR/sc-root-a $TMPDIR/sc-root-b")
assert_valid "serve fallback: unrelated cwd -> first readable root" \
    "fallback=$TMPDIR/sc-root-a pwd=$TMPDIR/sc-root-a warn=1" "$result"

# cwd inside a root's subdir -> that root wins even though it is listed second
result=$(sc_serve "$TMPDIR/sc-root-b/sub" "$TMPDIR/sc-root-a $TMPDIR/sc-root-b")
assert_valid "serve fallback: cwd under a root -> that root (ancestor preferred)" \
    "fallback=$TMPDIR/sc-root-b pwd=$TMPDIR/sc-root-b warn=1" "$result"

# first root unreadable -> pass 2 picks the next readable one
result=$(sc_serve "$TMPDIR/other" "$TMPDIR/sc-root-b")
assert_valid "serve fallback: skips unreadable configured roots" \
    "fallback=$TMPDIR/sc-root-b pwd=$TMPDIR/sc-root-b warn=1" "$result"

# readable cwd -> no probe complaint, no fallback, no cd, no warning
result=$(sc_serve "$TMPDIR/sc-root-a" "$TMPDIR/sc-root-a")
assert_valid "serve cwd: readable cwd is left alone" \
    "fallback=none pwd=$(pwd) warn=0" "$result"

# probe unavailable (sudoers rule missing / sudo denied -> empty output)
# must NOT trigger the fallback path
sc_serve_noprobe() {
    (
        set -- serve
        CWD="$TMPDIR/other"
        PROJECTS_CONF="$TMPDIR/sc-projects.conf"
        SERVE_FALLBACK=""
        _warned=0
        RED='' GREEN='' CYAN='' YELLOW='' NC=''
        note() { if [ -n "$1" ]; then _warned=1; fi; }
        cwd_probe() { :; }
        eval "$SC_BLOCK"
        printf 'fallback=%s warn=%s\n' "${SERVE_FALLBACK:-none}" "$_warned"
    )
}
result=$(sc_serve_noprobe)
assert_valid "serve cwd: unavailable probe (empty output) changes nothing" \
    "fallback=none warn=0" "$result"

# static: wrapper wiring + sudoers rule
if grep -q 'cwd-check.sh "\$1" 2>/dev/null || true' "$WRAPPER_FILE" \
   && grep -q 'sudo -n -u opencode.*cwd-check.sh' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  wrapper probes the serve cwd via cwd-check.sh (sudo -n, fault-tolerant)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  wrapper lost the fault-tolerant cwd-check.sh probe"
    failures=$((failures + 1))
fi

if grep -q 'OPENCHAMBER_OPENCODE_CWD' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  serve warning names OPENCHAMBER_OPENCODE_CWD as the fix"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve warning lost the OPENCHAMBER_OPENCODE_CWD hint"
    failures=$((failures + 1))
fi

if grep -q 'getent passwd opencode' "$WRAPPER_FILE"; then
    echo "  ${GREEN}PASS${NC}  serve fallback ends at the opencode user's home"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  serve fallback lost the opencode-home last resort"
    failures=$((failures + 1))
fi

if grep -q 'bin/cwd-check.sh \*' "$SUDOERS_FILE"; then
    echo "  ${GREEN}PASS${NC}  sudoers.template gates cwd-check.sh (NOPASSWD, opencode RunAs)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  sudoers.template lost the cwd-check.sh rule"
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
