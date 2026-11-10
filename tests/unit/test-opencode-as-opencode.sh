#!/bin/sh
# Test wrapper directory validation logic.
# Creates temp directories and projects.conf, then tests various CWD scenarios.
# Since #449 the wrapper is decomposed (the #346 wave shape): the
# executable sections live in sh/as-opencode-core.sh, the entry
# bin/opencode-as-opencode keeps globals + section sequence + exec. The
# pins span BOTH files: entry-level pins stay on $WRAPPER_FILE, pins on
# moved code target $CORE_LIB, and the block-extraction legs became
# sourcing pins (source the lib, stub its dependencies, drive the REAL
# functions — #396 accounting). The lib's own contract (sourcing
# purity, definition census, pairing guard) lives in
# tests/unit/test-as-opencode-core.sh.
# Run: sh tests/unit/test-opencode-as-opencode.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Shared harness (issue #417 adoption, the #394 pattern): pass/fail,
# assert_eq, extract_func + the counters live in lib/harness.sh now;
# the work registry (issue #395) owns cleanup -- this suite carries no
# trap of its own (a local trap would disarm the harness registry).
# The former local assert_valid had assert_eq's exact 3-arg contract
# (desc expected actual) and was renamed; the inline PASS/FAIL rows
# became pass/fail calls.
. "$SCRIPT_DIR/lib/harness.sh"

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
            if [ "$CWD" = "$root_clean" ] || [ "${CWD#"$root_clean"/}" != "$CWD" ]; then
                VALID=true
                break
            fi
        done <"$PROJECTS_CONF"
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
# Scratch receiver via the work registry (issue #395): work_new
# registers it, the harness's central EXIT INT TERM trap collects it.
TMPDIR="$(work_new)"

mkdir -p "$TMPDIR/project-a"
mkdir -p "$TMPDIR/project-a/sub"
mkdir -p "$TMPDIR/project-a/deep/nested"
mkdir -p "$TMPDIR/project-b"
mkdir -p "$TMPDIR/project-ab" # partial name match trap
mkdir -p "$TMPDIR/other"

echo ""
echo "Wrapper Directory Validation Tests"
echo "===================================="
echo ""

# --- Test 1: Exact match ---
echo "--- Exact match ---"
printf '%s\n' "$TMPDIR/project-a" >"$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_eq "exact match on root" "valid" "$result"

# --- Test 2: First-level subdirectory ---
result=$(validate_dir "$TMPDIR/project-a/sub" "$TMPDIR/projects.conf")
assert_eq "first-level subdirectory" "valid" "$result"

# --- Test 3: Deep nested subdirectory ---
result=$(validate_dir "$TMPDIR/project-a/deep/nested" "$TMPDIR/projects.conf")
assert_eq "deep nested subdirectory" "valid" "$result"

# --- Test 4: Partial name match (different dir) ---
result=$(validate_dir "$TMPDIR/project-ab" "$TMPDIR/projects.conf")
assert_eq "partial name match (project-ab vs project-a)" "invalid" "$result"

# --- Test 5: Shorter prefix (project-a/ vs project) ---
result=$(validate_dir "$TMPDIR/other" "$TMPDIR/projects.conf")
assert_eq "unrelated directory" "invalid" "$result"

# --- Test 6: Home directory ---
result=$(validate_dir "$HOME" "$TMPDIR/projects.conf")
assert_eq "home directory (not in projects.conf)" "invalid" "$result"

# --- Test 7: Multiple roots ---
printf '%s\n' "$TMPDIR/project-a" "$TMPDIR/project-b" >"$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-b" "$TMPDIR/projects.conf")
assert_eq "second root in multi-root config" "valid" "$result"

result=$(validate_dir "$TMPDIR/project-a/sub" "$TMPDIR/projects.conf")
assert_eq "subdirectory of first root in multi-root config" "valid" "$result"

result=$(validate_dir "$TMPDIR/other" "$TMPDIR/projects.conf")
assert_eq "unrelated dir in multi-root config" "invalid" "$result"

# --- Test 8: Root with trailing slash in config ---
printf '%s\n' "$TMPDIR/project-a/" >"$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_eq "trailing-slash root: exact CWD" "valid" "$result"

result=$(validate_dir "$TMPDIR/project-a/sub" "$TMPDIR/projects.conf")
assert_eq "trailing-slash root: subdirectory" "valid" "$result"

# --- Test 9: CWD with trailing slash ---
printf '%s\n' "$TMPDIR/project-a" >"$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a/" "$TMPDIR/projects.conf")
assert_eq "CWD with trailing slash" "valid" "$result"

# --- Test 10: Empty projects.conf ---
true >"$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_eq "empty projects.conf" "invalid" "$result"

# --- Test 11: Missing projects.conf ---
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/no-such-file.conf")
assert_eq "missing projects.conf" "invalid" "$result"

# --- Test 12: Line with whitespace / blank lines ---
printf '\n%s\n\n%s\n\n' "$TMPDIR/project-a" "$TMPDIR/project-b" >"$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_eq "blank lines in projects.conf: valid" "valid" "$result"

result=$(validate_dir "$TMPDIR/other" "$TMPDIR/projects.conf")
assert_eq "blank lines in projects.conf: invalid" "invalid" "$result"

# --- Test 13: Non-existent directory in projects.conf (should skip) ---
printf '%s\n%s\n' "$TMPDIR/project-a" "$TMPDIR/project-nonexistent" >"$TMPDIR/projects.conf"
result=$(validate_dir "$TMPDIR/project-a" "$TMPDIR/projects.conf")
assert_eq "skips non-existent entry, matches valid one" "valid" "$result"

# --- Version banner ---
echo ""
echo "--- Version banner ---"

printf 'DEFAULT_USER=dev\nVERSION=1.2.3\n' >"$TMPDIR/install.conf"
result=$(banner_line "$TMPDIR/install.conf")
assert_eq "banner shows version from install.conf" \
    "$(printf '%b' "  ${GREEN}SECURED BY opencode permissions kit (1.2.3)${NC}")" "$result"

result=$(banner_line "$TMPDIR/no-such-install.conf")
assert_eq "banner defaults to 0.0.0 when no conf exists" \
    "$(printf '%b' "  ${GREEN}SECURED BY opencode permissions kit (0.0.0)${NC}")" "$result"

printf 'DEFAULT_USER=dev\n' >"$TMPDIR/no-version.conf"
result=$(banner_line "$TMPDIR/no-version.conf")
assert_eq "banner defaults to 0.0.0 when conf has no VERSION line" \
    "$(printf '%b' "  ${GREEN}SECURED BY opencode permissions kit (0.0.0)${NC}")" "$result"

# --- Soft-only model (DDEV-WORKING phase 2) ---
echo ""
echo "--- Soft-only wrapper/sudoers shape ---"

WRAPPER_FILE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
CORE_LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/as-opencode-core.sh"
SUDOERS_FILE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/templates/sudoers.template"

# The wrapper surface spans entry + sourced core lib since #449: absence
# pins sweep BOTH files (a reintroduction in either is the regression).
if ! grep -q 'protect-projects' "$WRAPPER_FILE" && ! grep -q 'protect-projects' "$CORE_LIB"; then
    pass "wrapper no longer calls protect-projects"
else
    fail "wrapper still references protect-projects"
fi

if ! grep -qE '\-g\|--gid' "$WRAPPER_FILE" && ! grep -qE '\-g\|--gid' "$CORE_LIB"; then
    pass "wrapper has no -g/--gid docker parsing"
else
    fail "wrapper still parses -g/--gid"
fi

if ! grep -q 'OPENCODE_LAUNCH_CWD' "$WRAPPER_FILE" && ! grep -q 'OPENCODE_LAUNCH_CWD' "$CORE_LIB"; then
    pass "wrapper does not stamp OPENCODE_LAUNCH_CWD"
else
    fail "wrapper still stamps OPENCODE_LAUNCH_CWD"
fi

if ! grep -q 'CONTAINER_GROUP=' "$WRAPPER_FILE" && ! grep -q 'CONTAINER_GROUP=' "$CORE_LIB"; then
    pass "wrapper has no docker-group escalation variable"
else
    fail "wrapper still escalates via CONTAINER_GROUP"
fi

if grep -q 'jsonc-parser.py --tools' "$CORE_LIB"; then
    pass "wrapper keeps --tools project detection"
else
    fail "wrapper lost --tools detection"
fi

if grep -q 'DOCKER_HOST' "$WRAPPER_FILE" && grep -q 'XDG_RUNTIME_DIR' "$WRAPPER_FILE"; then
    pass "wrapper exports DOCKER_HOST/XDG_RUNTIME_DIR for rootless"
else
    fail "wrapper lost the rootless env exports"
fi

if grep -q 'sudo -u opencode' "$WRAPPER_FILE"; then
    pass "wrapper still execs via sudo -u opencode"
else
    fail "wrapper lost the sudo -u opencode exec"
fi

# --- #449 movement cross-checks: replica vs the REAL lib functions -------------
# The validate_dir/banner_line replicas above predate the decomposition
# and stay (their matrix is the suite's original core); these sourcing
# pins prove the MOVED code still matches them (movement purity at unit
# level — the full-script proof is the #449 purity drive + e2e). The
# moved wrapper_validate_cwd takes no arguments: it resolves CWD=$(pwd)
# itself, so the driver cds into the probe directory. Plain mkdir inside
# the registered work_new receiver -- no new scratch receiver (#283).
_vcwd_root="$TMPDIR/vcwd-root"
mkdir -p "$_vcwd_root/sub"
printf '%s\n' "$_vcwd_root" "$TMPDIR/project-b" >"$TMPDIR/vcwd.conf"
for _pair in \
    "$_vcwd_root:valid" "$_vcwd_root/sub:valid" "$TMPDIR/project-ab:invalid" \
    "$TMPDIR/other:invalid" "$TMPDIR/project-b:valid"; do
    _d="${_pair%:*}"
    _want="${_pair#*:}"
    _rep="$(validate_dir "$_d" "$TMPDIR/vcwd.conf")"
    _real="$(
        cd "$_d" || exit 1
        . "$CORE_LIB"
        PROJECTS_CONF="$TMPDIR/vcwd.conf"
        wrapper_validate_cwd
        if [ "$VALID" = true ]; then echo valid; else echo invalid; fi
    )"
    assert_eq "moved wrapper_validate_cwd matches replica ($_d) -> $_want" "$_rep" "$_real"
done

# banner: drive the moved wrapper_banner and compare its banner line
# against the replica (the section prints blank, banner, blank; the
# replica prints the banner line only). Shell-fidelity (#255 kcov
# class): the replica renders colors via printf '%b', the moved code
# via echo -- dash's echo interprets the escapes, bash's does not, so
# the REAL output is %b-normalized before the compare (the harness
# pass()/fail() idiom; identical bytes under sh and the coverage bash).
_bnr="$(
    . "$CORE_LIB"
    HEADLESS=false
    VERSION=1.2.3
    wrapper_banner
)"
assert_eq "moved wrapper_banner matches the banner_line replica" \
    "$(banner_line "$TMPDIR/install.conf")" \
    "$(printf '%b' "$(printf '%s\n' "$_bnr" | sed -n '2p')")"

# --- Version/help passthrough from ANY directory (issue #91) ---
# The official opencode installer probes `opencode --version` from $HOME
# (an invalid directory) while the kit installs; the wrapper must answer
# from the real binary instead of refusing (regression: the mid-install
# "ERROR: opencode cannot be started here" confused users). Since issue
# #91 the passthrough is its own case BEFORE the project-dir check —
# version/help must stay banner-free from valid directories too. The
# arms live in the lib's wrapper_version_passthrough since #449 — the
# pins drive the extracted function (#396 accounting).
_vp_fn="$(extract_func "$CORE_LIB" wrapper_version_passthrough)"
if [ -n "$_vp_fn" ] && printf '%s\n' "$_vp_fn" | grep -q -- '--version'; then
    pass "wrapper answers --version from any directory (installer probe)"
else
    fail "wrapper refuses --version outside a project directory"
fi

if [ -n "$_vp_fn" ] && printf '%s\n' "$_vp_fn" | grep -q 'bin/opencode "\$@"'; then
    pass "version passthrough execs the secured binary"
else
    fail "version passthrough lost the binary exec"
fi

# The passthrough must precede the refusal (exec replaces the process, the
# ERROR banner must stay unreachable for version/help args). Since #449
# both exec arms live in wrapper_version_passthrough and the precedence
# is the ENTRY's call order — pin the exact call lines.
_pass_ln="$(grep -n '^wrapper_version_passthrough "\$@"$' "$WRAPPER_FILE" | cut -d: -f1)"
_refusal_ln="$(grep -n '^wrapper_refusal$' "$WRAPPER_FILE" | cut -d: -f1)"
if [ -n "$_pass_ln" ] && [ -n "$_refusal_ln" ] && [ "$_pass_ln" -lt "$_refusal_ln" ]; then
    pass "passthrough is checked before the refusal"
else
    fail "refusal runs before the version passthrough (pass:$_pass_ln refusal:$_refusal_ln)"
fi

# --- Help in the leading flag region (#370 a E1) -----------------------------------
# `opencode run --help` (tty stdin, non-project cwd) used to hit the
# project-dir refusal instead of help: the #91 any-dir path covered
# flags in $1 only. Classification contract: a -h/--help BEFORE the
# first message argument is a help query (any-dir exec); past the first
# message argument, "--help" is message text. Sourcing pin since #449:
# the scan loop + subcommand case moved into the lib's
# wrapper_headless_classify -- source the lib and drive the REAL
# classifier (#396 accounting; the eval'd text extraction retired).
if [ -n "$(extract_func "$CORE_LIB" wrapper_headless_classify)" ]; then
    pass "leading-region help classifier present (#370 a E1)"
    # <args...> -> the classifier's msg/help state. The lib defines no
    # top-level side effects (pinned in test-as-opencode-core.sh), so
    # sourcing it inside the substitution is safe; the classifier's
    # "$@" resolves to hr_class's arguments.
    hr_class() {
        (
            . "$CORE_LIB"
            wrapper_headless_classify "$@"
            echo "msg=$_hr_msg help=$_hr_help"
        )
    }
    _got="$(hr_class run --help)"
    if [ "$_got" = "msg=false help=true" ]; then
        pass "'run --help' classifies as a help query (#370 a E1)"
    else
        fail "'run --help' classifies as a help query (got: $_got) (#370 a E1)"
    fi
    _got="$(hr_class run "please --help me")"
    if [ "$_got" = "msg=true help=false" ]; then
        pass "'--help' INSIDE a message stays message text (#370 a E1)"
    else
        fail "'--help' INSIDE a message stays message text (got: $_got) (#370 a E1)"
    fi
    _got="$(hr_class run --verbose --help)"
    if [ "$_got" = "msg=false help=true" ]; then
        pass "help behind other leading flags still a query (#370 a E1)"
    else
        fail "help behind other leading flags still a query (got: $_got) (#370 a E1)"
    fi
    # the any-dir exec for _hr_help must ALSO precede the refusal (the
    # classification is worthless if the refusal runs first) — the exec
    # lives in the lib's wrapper_version_passthrough (second arm), the
    # precedence is the entry's call order pinned above. Both the arm's
    # GATE and its EXEC are pinned here (#453 a C3): the exec count over
    # the function must be exactly 2 — the $1 case arm and the _hr_help
    # arm — so an arm reduced to `if …; then :; fi` fails loud (the
    # #370 a E1 regression).
    _vp_execs="$(printf '%s\n' "$_vp_fn" |
        grep -c 'exec /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/opencode "\$@"')"
    if printf '%s\n' "$_vp_fn" | grep -q 'if \[ "\$_hr_help" = true \]; then' &&
        [ "$_vp_execs" = 2 ]; then
        pass "the _hr_help exec arm exists in wrapper_version_passthrough (#370 a E1)"
    else
        fail "the _hr_help exec arm missing from wrapper_version_passthrough (execs:$_vp_execs) (#370 a E1)"
    fi
else
    fail "leading-region help classifier present (#370 a E1)"
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

if grep -q 'HEADLESS=false' "$CORE_LIB" && grep -q 'serve | acp | models | agent | providers' "$CORE_LIB"; then
    pass "wrapper classifies headless subcommands (serve/acp/queries)"
else
    fail "wrapper lost headless subcommand classification"
fi

if grep -q 'if \[ "\$VALID" != true \] && \[ "\$HEADLESS" != true \]; then' "$CORE_LIB"; then
    pass "headless mode skips the project-dir refusal"
else
    fail "headless mode still bound to project-dir validation"
fi

# --- Device-login cwd fallback (issue #91, Bun posix_spawn EACCES) ----------
# console/auth logins open the browser through Bun's posix_spawn, which
# fails with EACCES when the opencode process cwd is unreadable for the
# opencode user (developer home, mode 750) — the login died right after
# printing URL + code. The wrapper must move device logins to a readable
# directory (opencode home) before the exec, using the same cwd_probe as
# the serve fallback.
if grep -q '\[ "\${1:-}" = "console" \] || \[ "\${1:-}" = "auth" \]' "$CORE_LIB"; then
    pass "device logins (console/auth) have a cwd fallback branch"
else
    fail "device logins lack the cwd fallback branch (Bun EACCES crash)"
fi

if sed -n '/= "console" \] || \[ "\${1:-}" = "auth" \]/,/^fi$/p' "$CORE_LIB" | grep -q 'cwd_probe'; then
    pass "device-login fallback probes readability (cwd_probe reuse)"
else
    fail "device-login fallback does not probe readability"
fi

if sed -n '/= "console" \] || \[ "\${1:-}" = "auth" \]/,/^fi$/p' "$CORE_LIB" | grep -q 'cd "\$LOGIN_FALLBACK"'; then
    pass "device-login fallback cds before the exec"
else
    fail "device-login fallback never changes directory"
fi

# Classification is executable: source the lib and drive the REAL
# classifier against representative argument vectors (sourcing pin,
# #396 accounting — same technique as hr_class above). tty-less CI
# makes `run` (no message) headless via the stdin check — an
# interactive terminal would keep it bannered; that branch is covered
# by the `-t 0` grep below.
hl_case() { # <desc> <expected> <args...>
    _desc="$1"
    _want="$2"
    shift 2
    _got=$(
        . "$CORE_LIB"
        wrapper_headless_classify "$@"
        echo "$HEADLESS"
    )
    if [ "$_got" = "$_want" ]; then
        pass "headless: $_desc"
    else
        fail "headless: $_desc (want=$_want got=$_got)"
    fi
}
hl_case "serve is headless" true serve
hl_case "run with message is headless" true run "fix the bug"
hl_case "run --format json is headless" true run --format json "hi"
hl_case "acp is headless" true acp
hl_case "models is headless" true models
hl_case "export is headless" true export sess-123
hl_case "2x api is headless" true api GET /config
hl_case "2x auth is headless" true auth login
hl_case "1x console login is headless" true console login
hl_case "2x plugin is headless" true plugin list
hl_case "2x service is headless" true service status
hl_case "2x pair is headless" true pair
hl_case "2x update is headless" true update
hl_case "tui stays interactive" false tui
hl_case "attach stays interactive" false attach
hl_case "2x mini stays interactive" false mini
hl_case "no args stays interactive" false
hl_case "flags-only start stays interactive" false --debug

if grep -q '\-t 0' "$CORE_LIB"; then
    pass "run without message checks stdin tty (piped = headless)"
else
    fail "run lost the interactive-tty distinction"
fi

if grep -q 'if \[ "${1:-}" = "serve" \]; then' "$CORE_LIB" && grep -q 'CONTAINER_AUTO=false' "$CORE_LIB"; then
    pass "serve requests container tools without prompting"
else
    fail "serve lost the silent container-tool request"
fi

if grep -q 'Press Enter to start opencode' "$WRAPPER_FILE" || grep -q 'Press Enter to start opencode' "$CORE_LIB"; then
    fail "wrapper still pauses on Press Enter (removed 0.0.21)"
else
    pass "no Press-Enter pause (removed 0.0.21 — the TUI shows the kit mode)"
fi

if { grep -q 'Run opencode with .*?\[Y/n\]\|Run opencode with %s? \[Y/n\]' "$WRAPPER_FILE" || grep -qF '"[Y/n]"' "$WRAPPER_FILE"; } ||
    { grep -q 'Run opencode with .*?\[Y/n\]\|Run opencode with %s? \[Y/n\]' "$CORE_LIB" || grep -qF '"[Y/n]"' "$CORE_LIB"; }; then
    fail "wrapper still asks the [Y/n] container question (removed 0.0.21)"
else
    pass "no [Y/n] container question (removed 0.0.21 — state is visible in the TUI)"
fi

if grep -q 'read -r answer' "$WRAPPER_FILE" || grep -q 'read -r answer' "$CORE_LIB"; then
    fail "wrapper still reads an interactive answer"
else
    pass "wrapper is prompt-free (no interactive reads left)"
fi

if grep -A8 '^note()' "$CORE_LIB" | grep -q '>&"\$_fd"\|>&\$_fd' && grep -A8 '^note()' "$CORE_LIB" | grep -q '_fd=2'; then
    pass "headless diagnostics go to stderr (note helper)"
else
    fail "headless diagnostics would pollute stdout"
fi

# The container-tools advisory must also route through note() — a raw
# printf to stdout would pollute `opencode run --format json` output.
# Both-file sweep (#453 a C1) over BOTH anchor spellings (#453 b D3):
# the historical raw-printf line (two leading spaces, gone with the
# note() rewrite) AND the current advisory wording (no leading spaces)
# — a plain note->printf flip on the live line must fail this pin.
if ! grep -qF 'printf "  ${GREEN}opencode will run with' "$WRAPPER_FILE" &&
    ! grep -qF 'printf "  ${GREEN}opencode will run with' "$CORE_LIB" &&
    ! grep -qF 'printf "${GREEN}opencode will run with' "$WRAPPER_FILE" &&
    ! grep -qF 'printf "${GREEN}opencode will run with' "$CORE_LIB"; then
    pass "container advisory uses note() (stdout-safe for orchestrators)"
else
    fail "container advisory prints raw to stdout"
fi

if grep -q 'OPENCODE_SERVER_PASSWORD' "$SUDOERS_FILE"; then
    pass "sudoers.template keeps OPENCODE_SERVER_PASSWORD across sudo"
else
    fail "sudoers.template drops OPENCODE_SERVER_PASSWORD (headless serve loses auth)"
fi

for marker in '#@docker-group-begin' '#@ddev-delegated-begin' '#@ddev-sandbox-begin' 'DDEV_BIN' 'OPENCODE_LAUNCH_CWD' 'protect-projects'; do
    if ! grep -q "$marker" "$SUDOERS_FILE"; then
        pass "sudoers.template free of '$marker'"
    else
        fail "sudoers.template still contains '$marker'"
    fi
done

if grep -q 'env_keep += "DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME"' "$SUDOERS_FILE" &&
    ! grep -q 'DDEV_DEBUG' "$SUDOERS_FILE" &&
    grep -q '(opencode) NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/opencode' "$SUDOERS_FILE" &&
    grep -q 'socket-check \*' "$SUDOERS_FILE"; then
    pass "sudoers.template keeps base RunAs + socket-check + env_keep (no DDEV_DEBUG)"
else
    fail "sudoers.template lost a required rule"
fi

# --- Headless serve cwd probe (OpenChamber HTTP 500 fix) ---
# OpenChamber spawns `opencode serve` with the developer's $HOME as cwd;
# the opencode user cannot read it (UID separation), so config load for
# that directory turns into HTTP 500. The wrapper probes readability via
# cwd-check (as the opencode user) and falls back to a readable
# projects root, warning on stderr.
echo ""
echo "--- Headless serve cwd probe ---"

CWD_CHECK="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/cwd-check"

# functional: the helper itself (it only stats — runs as the test user)
result=$(sh "$CWD_CHECK" "$TMPDIR/project-a")
assert_eq "cwd-check: existing readable dir reports readable" "readable" "$result"

result=$(sh "$CWD_CHECK" "$TMPDIR/no-such-dir")
assert_eq "cwd-check: missing dir reports unreadable" "unreadable" "$result"

result=$(sh "$CWD_CHECK" "")
assert_eq "cwd-check: empty argument reports unreadable" "unreadable" "$result"

sh "$CWD_CHECK" "$TMPDIR/no-such-dir" >/dev/null 2>&1
assert_eq "cwd-check: always exits 0 (empty output = probe unavailable)" "0" "$?"

# functional: the wrapper's fallback selection (sourcing pin since #449:
# the block moved into the lib's wrapper_serve_cwd_fallback — source the
# lib, stub cwd_probe + note (later definitions win), drive the REAL
# function with $1=serve; #396 accounting)
if [ -n "$(extract_func "$CORE_LIB" wrapper_serve_cwd_fallback)" ]; then
    pass "serve cwd fallback function present"
else
    fail "serve cwd fallback function missing"
fi

# sc_serve <cwd> <readable-dirs, space-separated> — runs the sourced
# section with $1=serve, a stubbed cwd_probe and a silent note(); prints
# "fallback=<dir|none> pwd=<dir> warn=<0|1>"
sc_serve() {
    _cwd="$1"
    _readable="$2"
    (
        . "$CORE_LIB"
        HEADLESS=false
        CWD="$_cwd"
        PROJECTS_CONF="$TMPDIR/sc-projects.conf"
        SERVE_FALLBACK=""
        _warned=0
        RED='' GREEN='' CYAN='' YELLOW='' NC=''
        note() { if [ -n "$1" ]; then _warned=1; fi; }
        cwd_probe() {
            case " $_readable " in *" $1 "*) echo readable ;; *) echo unreadable ;; esac
        }
        wrapper_serve_cwd_fallback serve
        printf 'fallback=%s pwd=%s warn=%s\n' "${SERVE_FALLBACK:-none}" "$(pwd)" "$_warned"
    )
}

mkdir -p "$TMPDIR/sc-root-a" "$TMPDIR/sc-root-b" "$TMPDIR/sc-root-b/sub"
printf '%s\n' "$TMPDIR/sc-root-a" "$TMPDIR/sc-root-b" >"$TMPDIR/sc-projects.conf"

# OpenChamber case: cwd unrelated to any root (like $HOME), both roots
# readable -> first configured readable root wins, warning printed, cd done
result=$(sc_serve "$TMPDIR/other" "$TMPDIR/sc-root-a $TMPDIR/sc-root-b")
assert_eq "serve fallback: unrelated cwd -> first readable root" \
    "fallback=$TMPDIR/sc-root-a pwd=$TMPDIR/sc-root-a warn=1" "$result"

# cwd inside a root's subdir -> that root wins even though it is listed second
result=$(sc_serve "$TMPDIR/sc-root-b/sub" "$TMPDIR/sc-root-a $TMPDIR/sc-root-b")
assert_eq "serve fallback: cwd under a root -> that root (ancestor preferred)" \
    "fallback=$TMPDIR/sc-root-b pwd=$TMPDIR/sc-root-b warn=1" "$result"

# first root unreadable -> pass 2 picks the next readable one
result=$(sc_serve "$TMPDIR/other" "$TMPDIR/sc-root-b")
assert_eq "serve fallback: skips unreadable configured roots" \
    "fallback=$TMPDIR/sc-root-b pwd=$TMPDIR/sc-root-b warn=1" "$result"

# readable cwd -> no probe complaint, no fallback, no cd, no warning
result=$(sc_serve "$TMPDIR/sc-root-a" "$TMPDIR/sc-root-a")
assert_eq "serve cwd: readable cwd is left alone" \
    "fallback=none pwd=$(pwd) warn=0" "$result"

# probe unavailable (sudoers rule missing / sudo denied -> empty output)
# must NOT trigger the fallback path
sc_serve_noprobe() {
    (
        . "$CORE_LIB"
        HEADLESS=false
        CWD="$TMPDIR/other"
        PROJECTS_CONF="$TMPDIR/sc-projects.conf"
        SERVE_FALLBACK=""
        _warned=0
        RED='' GREEN='' CYAN='' YELLOW='' NC=''
        note() { if [ -n "$1" ]; then _warned=1; fi; }
        cwd_probe() { :; }
        wrapper_serve_cwd_fallback serve
        printf 'fallback=%s warn=%s\n' "${SERVE_FALLBACK:-none}" "$_warned"
    )
}
result=$(sc_serve_noprobe)
assert_eq "serve cwd: unavailable probe (empty output) changes nothing" \
    "fallback=none warn=0" "$result"

# static: wrapper wiring + sudoers rule
if grep -q 'cwd-check "\$1" 2>/dev/null || true' "$CORE_LIB" &&
    grep -q 'sudo -n -u opencode.*cwd-check' "$CORE_LIB"; then
    pass "wrapper probes the serve cwd via cwd-check (sudo -n, fault-tolerant)"
else
    fail "wrapper lost the fault-tolerant cwd-check probe"
fi

if grep -q 'OPENCHAMBER_OPENCODE_CWD' "$CORE_LIB"; then
    pass "serve warning names OPENCHAMBER_OPENCODE_CWD as the fix"
else
    fail "serve warning lost the OPENCHAMBER_OPENCODE_CWD hint"
fi

if grep -q 'getent passwd opencode' "$CORE_LIB"; then
    pass "serve fallback ends at the opencode user's home"
else
    fail "serve fallback lost the opencode-home last resort"
fi

if grep -q 'bin/cwd-check \*' "$SUDOERS_FILE"; then
    pass "sudoers.template gates cwd-check (NOPASSWD, opencode RunAs)"
else
    fail "sudoers.template lost the cwd-check rule"
fi

# --- OpenChamber bypass guard (issue #154, Tier 1) ---
# openchamber_guard() warns state-specifically about self-installed
# binaries (~/.opencode/bin/opencode + opencode2) and the OpenChamber
# settings pin (~/.config/openchamber/settings.json "opencodeBinary"):
#   bins + pin  -> bypass warning, fix is TWO steps (a half fix hangs
#                  OpenChamber at startup)
#   bins only   -> shadow warning (classic installer re-run)
#   pin only    -> hang warning (pin outlives deleted binaries)
#   kit policy  -> secured note, leftovers inert (Tier 2 defuses the pin)
# Functional via the static-extraction technique (HL_BLOCK et al.): the
# absolute kit paths are rewritten to TMPDIR fixtures so the block runs
# portably (no kit install needed), note() is stubbed, colors distinguish
# warning (W:) from note (C:).
echo ""
echo "--- OpenChamber bypass guard (issue #154) ---"

OC_BLOCK="$(extract_func "$CORE_LIB" openchamber_guard)"
if [ -n "$OC_BLOCK" ]; then
    pass "openchamber_guard function extractable"
else
    fail "openchamber_guard function not extractable"
fi

OC_KIT_WRAPPER="$TMPDIR/oc-kit-wrapper"
OC_KIT_BIN="$TMPDIR/oc-kit-bin"
OC_POLICY="$TMPDIR/oc-policy.json"
: >"$OC_KIT_WRAPPER"
: >"$OC_KIT_BIN"
OC_BLOCK="$(printf '%s\n' "$OC_BLOCK" | sed \
    -e "s|/usr/local/lib/opencode-permissions-kit/bin/opencode-as-opencode|$OC_KIT_WRAPPER|g" \
    -e "s|/usr/local/bin/opencode|$OC_KIT_BIN|g" \
    -e "s|/etc/openchamber/policy.json|$OC_POLICY|g")"

# oc_run <home> — eval the block with a stubbed note(), run the guard,
# print every non-empty note prefixed with its color stub (W: warning,
# C: note). Empty output = guard stayed quiet.
oc_run() {
    _home="$1"
    (
        HOME="$_home"
        RED='' GREEN='' CYAN='C:' YELLOW='W:' NC=''
        _oc_notes=""
        note() { if [ -n "$1" ]; then _oc_notes="$_oc_notes
$1"; fi; }
        eval "$OC_BLOCK"
        openchamber_guard
        printf '%s' "$_oc_notes"
    )
}

# fixture helper
oc_mkbin() { # <home> [names...] — real shadow binaries
    _h="$1"
    shift
    mkdir -p "$_h/.opencode/bin"
    for _n in "$@"; do echo "fake" >"$_h/.opencode/bin/$_n"; done
}

# clean home -> quiet
mkdir -p "$TMPDIR/oc-clean"
out=$(oc_run "$TMPDIR/oc-clean")
assert_eq "openchamber guard: clean home -> quiet" "" "$out"

# bins only -> shadow warning, both names, rm -f fix, no bypass wording
mkdir -p "$TMPDIR/oc-bins"
oc_mkbin "$TMPDIR/oc-bins" opencode opencode2
out=$(oc_run "$TMPDIR/oc-bins")
assert_eq "openchamber guard: bins only -> warns (shadow)" "1" \
    "$(printf '%s' "$out" | grep -c 'self-installed opencode detected')"
assert_eq "openchamber guard: bins only -> names both binaries (detect + fix lines)" "2" \
    "$(printf '%s' "$out" | grep -c 'bin/opencode .*bin/opencode2')"
assert_eq "openchamber guard: bins only -> rm -f fix, no rm -rf" "1" \
    "$(printf '%s' "$out" | grep -c 'Fix: rm -f ')"

# pin only -> hang warning + settings line fix
mkdir -p "$TMPDIR/oc-pin/.config/openchamber"
printf '{ "opencodeBinary": "%s/.opencode/bin/opencode" }\n' "$TMPDIR/oc-pin" \
    >"$TMPDIR/oc-pin/.config/openchamber/settings.json"
out=$(oc_run "$TMPDIR/oc-pin")
assert_eq "openchamber guard: pin only -> hang warning" "1" \
    "$(printf '%s' "$out" | grep -c 'will hang')"
assert_eq "openchamber guard: pin only -> fix removes the settings line" "1" \
    "$(printf '%s' "$out" | grep -c 'remove the .opencodeBinary. line')"

# bins + pin -> bypass warning, BOTH steps
mkdir -p "$TMPDIR/oc-both/.config/openchamber"
oc_mkbin "$TMPDIR/oc-both" opencode opencode2
printf '{ "opencodeBinary": "/home/dev/.opencode/bin/opencode" }\n' \
    >"$TMPDIR/oc-both/.config/openchamber/settings.json"
out=$(oc_run "$TMPDIR/oc-both")
assert_eq "openchamber guard: bins+pin -> bypass wording" "1" \
    "$(printf '%s' "$out" | grep -c 'OUTSIDE the kit')"
assert_eq "openchamber guard: bins+pin -> BOTH-steps fix advice" "1" \
    "$(printf '%s' "$out" | grep -c 'BOTH steps')"
assert_eq "openchamber guard: bins+pin -> fix names binaries AND settings line" "2" \
    "$(printf '%s' "$out" | grep -c -e 'rm -f ' -e 'remove the .opencodeBinary. line')"

# pin on the kit wrapper -> secured, quiet
mkdir -p "$TMPDIR/oc-wrapped/.config/openchamber"
printf '{ "opencodeBinary": "%s" }\n' "$OC_KIT_BIN" \
    >"$TMPDIR/oc-wrapped/.config/openchamber/settings.json"
out=$(oc_run "$TMPDIR/oc-wrapped")
assert_eq "openchamber guard: pin on the kit wrapper -> quiet" "" "$out"

# empty-string pin -> unset (openchamber optionalText semantics), quiet
mkdir -p "$TMPDIR/oc-empty/.config/openchamber"
printf '{ "opencodeBinary": "" }\n' >"$TMPDIR/oc-empty/.config/openchamber/settings.json"
out=$(oc_run "$TMPDIR/oc-empty")
assert_eq "openchamber guard: empty pin counts as unset" "" "$out"

# kit-owned symlink -> not a shadow; the plain opencode2 shim still is
mkdir -p "$TMPDIR/oc-link/.opencode/bin"
ln -s "$OC_KIT_WRAPPER" "$TMPDIR/oc-link/.opencode/bin/opencode"
echo "sh shim" >"$TMPDIR/oc-link/.opencode/bin/opencode2"
out=$(oc_run "$TMPDIR/oc-link")
assert_eq "openchamber guard: kit symlink not listed, shim still is (2 lines)" "2" \
    "$(printf '%s' "$out" | grep -c 'bin/opencode2')"
assert_eq "openchamber guard: kit symlink ignored (no pair listing)" "0" \
    "$(printf '%s' "$out" | grep -c 'bin/opencode .*bin/opencode2')"

# kit policy pins the wrapper -> secured NOTE (cyan), not a bypass warning,
# even with bins + settings pin present
printf '{ "opencodeBinary": "%s" }\n' "$OC_KIT_BIN" >"$OC_POLICY"
out=$(oc_run "$TMPDIR/oc-both")
assert_eq "openchamber guard: policy secures -> NOTE not WARNING" "1" \
    "$(printf '%s' "$out" | grep -c '^C:NOTE')"
assert_eq "openchamber guard: policy secures -> both leftovers called inert" "2" \
    "$(printf '%s' "$out" | grep -c 'inert')"
assert_eq "openchamber guard: policy secures -> stale settings pin named" "1" \
    "$(printf '%s' "$out" | grep -c 'settings.json is')"
assert_eq "openchamber guard: policy secures -> no bypass wording" "0" \
    "$(printf '%s' "$out" | grep -c 'OUTSIDE the kit')"
# policy + pin-only leftover (0.0.47a F2): the stale settings pin is named,
# no dangling "safe to remove:" list without binaries
out=$(oc_run "$TMPDIR/oc-pin")
assert_eq "openchamber guard: policy + pin-only -> NOTE not WARNING" "1" \
    "$(printf '%s' "$out" | grep -c '^C:NOTE')"
assert_eq "openchamber guard: policy + pin-only -> stale pin named" "1" \
    "$(printf '%s' "$out" | grep -c 'settings.json is')"
assert_eq "openchamber guard: policy + pin-only -> no dangling remove list" "0" \
    "$(printf '%s' "$out" | grep -c 'safe to remove:')"
: >"$OC_POLICY"

# settings.json without the key -> quiet
mkdir -p "$TMPDIR/oc-otherkey/.config/openchamber"
printf '{ "theme": "dark", "port": 3000 }\n' \
    >"$TMPDIR/oc-otherkey/.config/openchamber/settings.json"
out=$(oc_run "$TMPDIR/oc-otherkey")
assert_eq "openchamber guard: foreign settings keys -> quiet" "" "$out"

# untrusted pin value must never reach the output (printf %b expansion,
# $(...) smuggling — only file and key are named)
mkdir -p "$TMPDIR/oc-evil/.config/openchamber"
printf '{ "opencodeBinary": "/tmp/x\\n\\033[31mFAKE $(touch %s/pwned)" }\n' "$TMPDIR" \
    >"$TMPDIR/oc-evil/.config/openchamber/settings.json"
out=$(oc_run "$TMPDIR/oc-evil")
assert_eq "openchamber guard: pin VALUE never printed" "0" \
    "$(printf '%s' "$out" | grep -c 'FAKE')"
if [ -e "$TMPDIR/pwned" ]; then
    assert_eq "openchamber guard: pin value not executed" "0" "1"
else
    assert_eq "openchamber guard: pin value not executed" "1" "1"
fi

# static wiring: the wrapper calls the guard and links the how-to
if grep -q '^openchamber_guard$' "$WRAPPER_FILE" &&
    grep -q 'docs/how-to/openchamber.md' "$CORE_LIB"; then
    pass "wrapper calls openchamber_guard and links the how-to"
else
    fail "wrapper lost the openchamber_guard call or how-to link"
fi

# --- Container-tool detection from the final merged config (issue #81) ---
# The wrapper asks opencode itself (`opencode debug config`, run as the
# opencode user from the cwd) for the session's FINAL permission config and
# applies the broad-allow detection to that — a broad allow in the opencode
# user's global config counts too. Only when the probe returns nothing does
# it fall back to the pre-#81 project-only scan.
echo ""
echo "--- Merged-config container detection (issue #81) ---"

# static: the probe is wired as designed (fault-tolerant, no prompt)
if grep -q '/usr/bin/sudo -n -u opencode' "$CORE_LIB" && grep -q 'bin/opencode debug config' "$CORE_LIB"; then
    pass "wrapper probes the merged config via opencode debug config (sudo -n)"
else
    fail "wrapper lost the opencode debug config probe"
fi

if grep -q 'tools_from_config -' "$CORE_LIB" && grep -q 'tools_from_config "\$PROJECT_CONFIG"' "$CORE_LIB"; then
    pass "wrapper evaluates the merged config first, project file as fallback"
else
    fail "wrapper lost the merged/project detection order"
fi

# --- #249: tools_from_config runs the parser isolated (-I) ------------------------
# The wrapper's own function names the deployed LIBDIR path (unpinnable
# hermetically), so the wiring pin greps the real call site behind the
# comment-strip rider; the mechanism pin (shadow pair) runs at
# REAL_PARSER below, where the parser path is in hand.
if live_src "$CORE_LIB" | grep -q 'python3 -I /usr/local/lib/opencode-permissions-kit/py/jsonc-parser.py --tools'; then
    pass "tools_from_config invokes the parser with -I (#249)"
else
    fail "tools_from_config must run python3 -I (ambient env must not steer it) (#249)"
fi

# --- #248: the wrapper's bounded probes gate on the two-class timeout probe -------
# Sabotage discriminator: reverting a gate to presence-only reintroduces
# the `command -v timeout ...; then` GATE shape — the helper's own
# first class is the `command -v ... && timeout 2 true` pair, which the
# count pin above already requires.
_w248="$(live_src "$CORE_LIB" | grep -c 'if _opk_timeout_ok; then' || true)"
if [ "${_w248:-0}" -ge 4 ]; then
    pass "all four wrapper probe gates use _opk_timeout_ok ($_w248 sites) (#248)"
else
    fail "wrapper probe gates must use the two-class timeout probe (found ${_w248:-0}) (#248)"
fi
if live_src "$WRAPPER_FILE" | grep -q 'command -v timeout >/dev/null 2>&1; then' ||
    live_src "$CORE_LIB" | grep -q 'command -v timeout >/dev/null 2>&1; then'; then
    fail "wrapper must not gate probes on presence-only timeout checks (#248)"
else
    pass "no presence-only timeout gate remains in the wrapper (#248)"
fi

# --- #453 a A1: the re-wrapped "Running WITHOUT container tools" warning ---------
# must render byte-identical to the original single-line string: the
# house `""\` continuation idiom keeps exactly ONE content space at the
# join (a continuation indented into the string adds bytes to the
# rendered output -- the A1 regression, first caught in review round a
# after the purity drive had missed this arm). Sourcing pin on
# wrapper_container_resolve, podman-socket-unreachable arm, colors
# blanked so the assert compares the message bytes themselves.
_wrap_out="$(
    . "$CORE_LIB"
    HEADLESS=false
    RED='' GREEN='' CYAN='' YELLOW='' NC=''
    CONTAINER_REQUESTED=true
    CONTAINER_BACKEND=podman-rootless
    OPENCODE_PODMAN_SOCKET=unix:///run/podman/podman.sock
    _w=""
    note() {
        if [ -n "$1" ]; then
            if [ -n "$_w" ]; then _w="$_w
$1"; else _w="$1"; fi
        fi
    }
    sock_reachable() { return 1; }
    wrapper_container_resolve
    printf '%s' "$_w"
)"
assert_eq "wrapped container warning renders with one join space (#453 a A1)" \
    "$(printf 'WARNING: podman-rootless socket not reachable (unix:///run/podman/podman.sock).\nRunning WITHOUT container tools — not downgrading to a root-equivalent path.')" \
    "$_wrap_out"

# functional: source the lib's detection section, stub the probe + note,
# run the REAL parser (sourcing pin since #449, #396 accounting — same
# technique as HL/sc_serve: later definitions override the lib's)
if [ -n "$(extract_func "$CORE_LIB" wrapper_container_detect)" ]; then
    pass "detection section function present"
else
    fail "detection section function missing"
fi

mkdir -p "$TMPDIR/dt-project"
REAL_PARSER="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/py/jsonc-parser.py"

# --- #249 mechanism pair: the parser tools_from_config runs survives a shadow -----
# -I keeps the real json module against a functional PYTHONPATH shadow
# (the os.py lesson from #244: json is imported by the parser at call
# time, not preloaded); the control arm proves the shadow is genuinely
# hostile — without it the -I pin would pass vacuously.
_shadow_dir="$TMPDIR/py-shadow-249"
mkdir -p "$_shadow_dir" "$TMPDIR/shadow-proj"
printf 'raise SystemExit("shadow json imported")\n' >"$_shadow_dir/json.py"
printf '{ "permission": { "bash": { "docker *": "allow" } } }\n' >"$TMPDIR/shadow-proj/opencode.jsonc"
if PYTHONPATH="$_shadow_dir" python3 -I "$REAL_PARSER" --tools "$TMPDIR/shadow-proj/opencode.jsonc" 2>/dev/null |
    grep -q '^docker$'; then
    pass "parser under -I ignores a functional json.py shadow (PYTHONPATH) (#249)"
else
    fail "-I must keep the real json module against a PYTHONPATH shadow (#249)"
fi
if PYTHONPATH="$_shadow_dir" python3 "$REAL_PARSER" --tools "$TMPDIR/shadow-proj/opencode.jsonc" >/dev/null 2>&1; then
    fail "control arm: bare python3 must pick the shadow (vacuous -I pin) (#249)"
else
    pass "control arm: bare python3 picks the shadow json.py (#249)"
fi

# dt_run <merged-json|EMPTY> <project-file|-> <project-content>
# Prints "tools=[...] requested=.. auto=.. banner=.." (banner counts the
# non-empty note() calls the section makes).
dt_run() {
    _merged="$1"
    _proj="$2"
    _content="$3"
    (
        cd "$TMPDIR/dt-project" || exit 1
        rm -f opencode.jsonc opencode.json
        if [ "$_proj" != "-" ]; then printf '%s\n' "$_content" >"$_proj"; fi
        . "$CORE_LIB"
        HEADLESS=false
        _banner=0
        note() { if [ -n "$1" ]; then _banner=$((_banner + 1)); fi; }
        merged_config() {
            if [ "$_merged" = "EMPTY" ]; then return 0; fi
            printf '%s\n' "$_merged"
        }
        tools_from_config() { command python3 "$REAL_PARSER" --tools "$@" 2>/dev/null; }
        stop_merged_config_service() { :; }
        wrapper_container_detect run >/dev/null
        printf 'tools=[%s] requested=%s auto=%s banner=%s\n' \
            "$(printf '%s' "$PROJECT_TOOLS" | tr '\n' ' ')" "$CONTAINER_REQUESTED" "$CONTAINER_AUTO" "$_banner"
    )
}

# issue #81 core: broad allows live in the GLOBAL config only (no project
# file) — the merged debug-config output carries them
result=$(dt_run '{ "permission": { "bash": { "*": "allow", "docker *": "allow", "docker-compose *": "deny", "sudo docker *": "deny", "ddev *": "allow", "sudo ddev *": "deny", "ddev auth ssh*": "deny" } } }' - '')
assert_eq "merged: global-config allows → docker+ddev, session requested" \
    "tools=[docker ddev] requested=true auto=true banner=1" "$result"

# merged config without broad allows → nothing enabled, no banner
result=$(dt_run '{ "permission": { "bash": { "ls *": "allow" } } }' - '')
assert_eq "merged: no broad allows → no tools" \
    "tools=[] requested=false auto=false banner=0" "$result"

# probe failed (EMPTY output) + project opencode.jsonc → fallback finds it
result=$(dt_run EMPTY opencode.jsonc '{ "permission": { "bash": { "docker *": "allow" } } }')
assert_eq "fallback: project opencode.jsonc scanned when probe is empty" \
    "tools=[docker] requested=true auto=true banner=1" "$result"

# probe failed + only opencode.json → the .json variant is picked
result=$(dt_run EMPTY opencode.json '{ "permission": { "bash": { "ddev *": "allow" } } }')
assert_eq "fallback: opencode.json variant scanned" \
    "tools=[ddev] requested=true auto=true banner=1" "$result"

# probe SUCCEEDED and says no tools → authoritative; the project file's
# allow must NOT re-enable them through the fallback
result=$(dt_run '{ "permission": { "bash": { "docker *": "deny" } } }' opencode.jsonc '{ "permission": { "bash": { "docker *": "allow" } } }')
assert_eq "merged: successful probe is authoritative (no project fallback)" \
    "tools=[] requested=false auto=false banner=0" "$result"

# probe answered an ERROR OBJECT (cold-start failure, parser exit 3) → not
# trustworthy → the project fallback fires despite non-empty probe output
result=$(dt_run '{ "error": "service starting" }' opencode.jsonc '{ "permission": { "bash": { "docker *": "allow" } } }')
assert_eq "merged: error-object probe falls back to the project scan" \
    "tools=[docker] requested=true auto=true banner=1" "$result"

# 2.x: the probe's background service is stopped again (stale-config guard)
if grep -q 'stop_merged_config_service()' "$CORE_LIB" && grep -q 'service stop' "$CORE_LIB"; then
    pass "wrapper stops the 2.x probe service (stale-config guard)"
else
    fail "wrapper lost the probe service stop"
fi

# the probe is time-bounded: a 2.x service blocked from its port makes
# `debug config` retry forever (port is per channel, not per user) — the
# wrapper must fall through instead of hanging even --version
if grep -q 'timeout 10' "$CORE_LIB" && grep -q 'timeout 5' "$CORE_LIB"; then
    pass "probe + service stop are time-bounded (port-collision hang)"
else
    fail "wrapper lost the probe/stop timeouts"
fi

# the OPENCODE_MAJOR fallback probe is bounded too (0.0.43a F3): the same
# issue-#80 hang must not block every start when install.conf lacks the
# stamp — timeout + head -1, failure/empty means major 1. Since 0.0.44a
# V21 the unstamped path REUSES the advisories probe's ADV_LINE (the same
# bounded --version first line — a second serial probe only added fail-
# open delay); the direct fallback stays bounded for advisories-less
# stamps and covers the pre-advisories cohort.
if grep -qF '_MAJOR_SRC="${ADV_LINE:-}"' "$CORE_LIB" &&
    grep -qF 'case "$_MAJOR_SRC" in' "$CORE_LIB" &&
    grep -q '_MAJOR_SRC=$(timeout 10' "$CORE_LIB"; then
    pass "OPENCODE_MAJOR fallback probe reuses ADV_LINE, direct fallback bounded (0.0.43a F3, 0.0.44a V21)"
else
    fail "OPENCODE_MAJOR fallback probe is unbounded or duplicated (0.0.43a F3, 0.0.44a V21)"
fi

# the serve fallback cd is guarded like the login twin (0.0.43a F4): the
# fallback was probed AS opencode — the invoking developer may lack
# traversal, and under set -e an unguarded cd would kill serve.
if grep -qF 'cd "$SERVE_FALLBACK" 2>/dev/null || true' "$CORE_LIB"; then
    pass "serve fallback cd fails open (0.0.43a F4)"
else
    fail "serve fallback cd aborts on failure (0.0.43a F4)"
fi

# probe failed + no project config → nothing
result=$(dt_run EMPTY - '')
assert_eq "fallback: no project config → no tools" \
    "tools=[] requested=false auto=false banner=0" "$result"

# --- opencode 2.x session servers: --standalone gating (issue #80) ---
# 2.x runs tools in a shared background service whose env never saw the
# wrapper's DOCKER_HOST — session commands (TUI default, run, mini) get
# --standalone (private server child, full env). 1.x never gets the flag
# (unknown there); an explicit --server/--standalone wins.
echo ""
echo "--- 2.x standalone gating (issue #80) ---"

SM_BLOCK="$(extract_func "$CORE_LIB" standalone_mode)"
if [ -n "$SM_BLOCK" ]; then
    pass "standalone_mode function extractable"
else
    fail "standalone_mode function not extractable"
fi

sm_case() { # <expected: none|append|after-first> <OPENCODE_MAJOR> <args...>
    _want="$1"
    OPENCODE_MAJOR="$2"
    shift 2
    _got=$(
        eval "$SM_BLOCK"
        standalone_mode "$@"
    )
    if [ "$_got" = "$_want" ]; then
        pass "standalone: $3${*:+ }-> $_want"
    else
        fail "standalone: args=[$*] want=$_want got=$_got"
    fi
}
sm_case none 1
sm_case none 1 run "fix"
sm_case none ""
sm_case append 2
sm_case append 2 --debug
sm_case append 2 --port 57222
sm_case after-first 2 run "fix the bug"
sm_case after-first 2 mini
sm_case none 2 serve --port 4199
sm_case none 2 models
sm_case none 2 debug config
sm_case none 2 run --server http://127.0.0.1:1 "hi"
sm_case none 2 --standalone
sm_case none 2 run --standalone "hi"

# arg rewriting: the wrapper's case block inserts/appends correctly
if grep -q 'case \$(standalone_mode "\$@")' "$WRAPPER_FILE" && grep -q 'set -- "\$_sub" --standalone "\$@"' "$WRAPPER_FILE"; then
    pass "wrapper rewrites args via standalone_mode"
else
    fail "wrapper lost the standalone arg rewriting"
fi

# runtime fallback detects 2.x from --version output
if grep -q '"opencode v2"\*) OPENCODE_MAJOR=2' "$CORE_LIB"; then
    pass "wrapper runtime-detects 2.x (fallback without stamp)"
else
    fail "wrapper lost the 2.x runtime detection"
fi

# --- F29: note() does not expand escape sequences in interpolated paths ----------
# note() used printf %b — a directory named like a \-sequence garbled the
# warning that interpolates it. Extract the REAL note() and assert a
# literal passthrough.
_f29_fn="$(extract_func "$CORE_LIB" note)"
if [ -n "$_f29_fn" ]; then
    _out=$(HEADLESS=false sh -c 'eval "$1"; note "$2"' sh "$_f29_fn" '\tdangerous-name') || true
    if printf '%s' "$_out" | grep -qF '\tdangerous-name' &&
        ! printf '%s' "$_out" | grep -q "$(printf '\t')dangerous"; then
        pass "note() prints escape-looking names literally (#211 a F29)"
    else
        fail "note() prints escape-looking names literally (got: $_out)"
    fi
else
    fail "note() extractable (#211 a F29)"
fi

# --- #220: bridge gate fails safe without the comparator ---------------------
# The bridge gate keys on ADV_VERSION — a variable owned by the advisories
# probe block. An env-exported ADV_VERSION (name collision) plus a broken
# kit (advisories.sh missing, comparator undefined) made the empty
# substitution satisfy `!= lt` and suppressed the bridge warning (the
# unsafe side, issue #220). Pin: the extracted gate block, eval'd with the
# comparator unset and PATH emptied (a host binary of the same name must
# not satisfy the guard either — 0.0.46a F2 class), keeps _bridge_needed=1
# on both arms and unknown; with the REAL advisories.sh comparator the
# version keying still holds (boundaries on their own arm each). The
# anchors re-dented 4->8 spaces with the #449 move (the gate sits one
# nesting level deeper inside wrapper_wsl_checks).
_b220_block="$(sed -n '/^        _bridge_needed=1$/,/^        fi$/p' "$CORE_LIB")"
_b220_adv_src="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/advisories.sh"
if [ -n "$_b220_block" ] && [ -f "$_b220_adv_src" ]; then
    pass "bridge gate block extractable (#220)"
    # with the real comparator: the gate keys on the version as documented
    _b220_gate() {
        (
            # shellcheck disable=SC1090
            . "$_b220_adv_src"
            ADV_VERSION="$1"
            eval "$_b220_block"
            printf '%s\n' "$_bridge_needed"
        )
    }
    # without any comparator: broken kit + inherited env value
    _b220_gate_nocmp() {
        (
            unset -f advisories_version_cmp
            PATH=
            ADV_VERSION="$1"
            eval "$_b220_block"
            printf '%s\n' "$_bridge_needed"
        )
    }
    if [ "$(_b220_gate 1.19.0)" = 0 ] && [ "$(_b220_gate 1.18.33)" = 0 ] &&
        [ "$(_b220_gate 2.0.19)" = 0 ] && [ "$(_b220_gate 2.0.18)" = 0 ] &&
        [ "$(_b220_gate 1.18.32)" = 1 ] && [ "$(_b220_gate 2.0.17)" = 1 ] &&
        [ "$(_b220_gate '')" = 1 ]; then
        pass "bridge gate keys on ADV_VERSION (1.18.33+/2.0.18+ unneeded)"
    else
        fail "bridge gate version keying drifted (extract: $_b220_block)"
    fi
    if [ "$(_b220_gate_nocmp 1.19.0)" = 1 ] && [ "$(_b220_gate_nocmp 2.0.19)" = 1 ] &&
        [ "$(_b220_gate_nocmp '')" = 1 ]; then
        pass "#220: missing comparator keeps the bridge warning (fails safe)"
    else
        fail "#220: bridge gate lost its fail-safe (extract: $_b220_block)"
    fi
else
    fail "bridge gate block not extractable (#220 anchor drift?)"
fi

# --- #220: the probe initializes its variables (no env inheritance) ----------
# The init before the guarded block kills the collision vector at the
# source: an exported ADV_LINE/ADV_VERSION/ADV_HITS can no longer
# impersonate a probe result while advisories.sh is missing (a1 swept
# the whole ADV_* family, ADV_HITS included). Pin: every init literal
# exists (comment-strip-ridden) and sits BEFORE the advisories.sh gate.
_b220_gate_ln="$(live_src "$CORE_LIB" |
    grep -nF '[ -f /usr/local/lib/opencode-permissions-kit/sh/advisories.sh ]; then' | head -1 | cut -d: -f1)"
_b220_init_n=0
for _v in ADV_LINE ADV_VERSION ADV_HITS; do
    _ln="$(live_src "$CORE_LIB" | grep -nF "${_v}=\"\"" | head -1 | cut -d: -f1)"
    if [ -n "$_ln" ] && [ -n "$_b220_gate_ln" ] && [ "$_ln" -lt "$_b220_gate_ln" ]; then
        _b220_init_n=$((_b220_init_n + 1))
    fi
done
if [ "$_b220_init_n" -eq 3 ]; then
    pass "#220: ADV_LINE/ADV_VERSION/ADV_HITS inits precede the advisories gate"
else
    fail "#220: init(s) missing or behind the gate (got $_b220_init_n/3, gate:$_b220_gate_ln)"
fi

suite_done "wrapper tests"
