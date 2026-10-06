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
# Run: sh tests/unit/test-install-args.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../../files/install.sh"

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
    MIGRATE_AGENTS_OPT=""
    DDEV_DEV_OWNED=true
    DDEV_SETTINGS_GIVEN=false
}

# expect_rc <want-rc> <description> <args...>
# Runs parse_args in a SUBSHELL: the function exits on bad input, and that
# exit must terminate only the subshell, not this test script.
expect_rc() {
    _want="$1"; _desc="$2"; shift 2
    reset_globals
    if [ "$_want" = "0" ]; then
        # Subshell (0.0.42g C1): parse_args aborts via exit 1 — a direct
        # call in this set -e shell would kill the whole suite instead
        # of recording the FAIL.
        if ( parse_args "$@" ) 2>/dev/null; then
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

# --ddev-settings (dev-owned mode): valid values captured, default on.
reset_globals
parse_args --ddev-settings dev-owned
[ "$DDEV_DEV_OWNED" = true ] && [ "$DDEV_SETTINGS_GIVEN" = true ] \
    && pass "--ddev-settings dev-owned is captured" \
    || fail "--ddev-settings dev-owned is captured"
reset_globals
parse_args --ddev-settings ddev
[ "$DDEV_DEV_OWNED" = false ] && [ "$DDEV_SETTINGS_GIVEN" = true ] \
    && pass "--ddev-settings ddev is captured (handover model)" \
    || fail "--ddev-settings ddev is captured (handover model)"
reset_globals
parse_args --yes
[ "$DDEV_DEV_OWNED" = true ] && [ "$DDEV_SETTINGS_GIVEN" = false ] \
    && pass "dev-owned mode ON by default (recommended)" \
    || fail "dev-owned mode ON by default (recommended)"
expect_rc 1 "--ddev-settings with an invalid value aborts" --ddev-settings maybe
expect_rc 1 "--ddev-settings without a value aborts" --ddev-settings

reset_globals
parse_args --yes
[ "$SKIP_DDEV_MIGRATION" = false ] \
    && pass "ddev migration stays ON by default" \
    || fail "ddev migration stays ON by default"

# --migrate-agents (issue #19): valid values captured, invalid abort.
for _ma_v in move copy skip; do
    reset_globals
    parse_args --migrate-agents "$_ma_v"
    [ "$MIGRATE_AGENTS_OPT" = "$_ma_v" ] \
        && pass "--migrate-agents $_ma_v is captured" \
        || fail "--migrate-agents $_ma_v is captured"
done
reset_globals
parse_args --yes
[ "$MIGRATE_AGENTS_OPT" = "" ] \
    && pass "agents migration undecided by default (prompt/--yes recommended)" \
    || fail "agents migration undecided by default"
reset_globals
parse_args --projects /var/www/vhosts --migrate-agents copy
[ "$MIGRATE_AGENTS_OPT" = "copy" ] \
    && pass "--migrate-agents works after --projects" \
    || fail "--migrate-agents works after --projects"

# Word forms normalize to the menu letters (0.0.44a V1): the migration
# semantics compare `[ "$_opk_ag" = m ]` — an untranslated word form made
# `--migrate-agents move` silently degrade to a copy. The normalization
# case is extracted from install.sh and executed against every accepted
# input form.
_install_sh="$SCRIPT_DIR/../../files/install.sh"
_extracted_case=$(sed -n '/^        # normalize-agents-forms (0.0.44a V1)/,/^        esac$/p' "$_install_sh")
[ -n "$_extracted_case" ] \
    && pass "install.sh: agents-form normalization extractable (V1)" \
    || fail "install.sh: agents-form normalization extractable (V1)"
for _pair in "m:m" "move:m" "c:c" "copy:c" "s:s" "skip:s"; do
    _in=${_pair%%:*}
    _want=${_pair##*:}
    _opk_ag="$_in"
    eval "$(printf '%s\n' "$_extracted_case" | sed -n '/^        case/,$p')"
    [ "$_opk_ag" = "$_want" ] \
        && pass "agents form '$_in' normalizes to '$_want' (V1)" \
        || fail "agents form '$_in' normalizes to '$_want' (V1, got '$_opk_ag')"
done
# and it runs BEFORE the dispatch that fires the migration loop
_norm_ln=$(grep -n 'normalize-agents-forms' "$_install_sh" | head -1 | cut -d: -f1)
_disp_ln=$(grep -n 'm|move|c|copy)' "$_install_sh" | head -1 | cut -d: -f1)
[ -n "$_norm_ln" ] && [ -n "$_disp_ln" ] && [ "$_norm_ln" -lt "$_disp_ln" ] \
    && pass "normalization precedes the migration dispatch (V1)" \
    || fail "normalization precedes the migration dispatch (V1)"

# Developer-side paths ride DEV_HOME, getent-resolved (0.0.44a V14): the
# installer used to hardcode /home/$DEFAULT_USER in ~14 provisioning
# sites (ddev discovery, .ddev registry, rc hooks, agents sources, the
# deny-all config, TUI theme) although it resolves the same home via
# getent 20 lines further up.
if grep -q 'DEV_HOME="/home/\$DEFAULT_USER"' "$_install_sh" \
   && grep -q 'getent passwd "\$DEFAULT_USER"' "$_install_sh" \
   && ! grep -q '/home/\$DEFAULT_USER/' "$_install_sh"; then
    pass "install.sh: DEV_HOME via getent, no hardcoded /home/\$DEFAULT_USER left (V14)"
else
    fail "install.sh: DEV_HOME via getent, no hardcoded /home/\$DEFAULT_USER left (V14)"
fi

# V15: the reuse guard aborts on a deviating home or primary group
# (maintainer decision B) instead of provisioning a shadow home. The two
# checks are extracted and executed against shims.
_h_guard=$(sed -n '/^        # reuse-guard-home (0.0.44a V15/,/^        fi$/p' "$_install_sh")
_g_guard=$(sed -n '/^        # reuse-guard-group (0.0.44a V15/,/^        fi$/p' "$_install_sh")
[ -n "$_h_guard" ] \
    && pass "install.sh: reuse home-guard extractable (V15)" \
    || fail "install.sh: reuse home-guard extractable (V15)"
[ -n "$_g_guard" ] \
    && pass "install.sh: reuse group-guard extractable (V15)" \
    || fail "install.sh: reuse group-guard extractable (V15)"
if [ -n "$_h_guard" ] && [ -n "$_g_guard" ]; then
    OPENCODE_USER="octest"
    ui_error() { :; }
    ui_info()  { :; }
    log()      { :; }
    # deviating home -> rc 1 (|| captures the rc: this suite runs set -e)
    _gr_rc=0
    (
        getent() { [ "$2" = "octest" ] && printf 'x:x:1000:1000::/srv/octest:/bin/sh\n'; }
        eval "$_h_guard"
    ) || _gr_rc=$?
    [ "$_gr_rc" -eq 1 ] \
        && pass "reuse guard: deviating home aborts (V15)" \
        || fail "reuse guard: deviating home aborts (V15, rc $_gr_rc)"
    # matching home -> rc 0
    _gr_rc=0
    (
        getent() { [ "$2" = "octest" ] && printf 'x:x:1000:1000::/home/octest:/bin/sh\n'; }
        eval "$_h_guard"
    ) || _gr_rc=$?
    [ "$_gr_rc" -eq 0 ] \
        && pass "reuse guard: matching home passes (V15)" \
        || fail "reuse guard: matching home passes (V15, rc $_gr_rc)"
    # deviating primary group -> rc 1
    _gr_rc=0
    (
        id() { [ "$1" = "-gn" ] && printf 'users\n'; }
        eval "$_g_guard"
    ) || _gr_rc=$?
    [ "$_gr_rc" -eq 1 ] \
        && pass "reuse guard: foreign primary group aborts (V15)" \
        || fail "reuse guard: foreign primary group aborts (V15, rc $_gr_rc)"
    # own primary group -> rc 0
    _gr_rc=0
    (
        id() { [ "$1" = "-gn" ] && printf 'octest\n'; }
        eval "$_g_guard"
    ) || _gr_rc=$?
    [ "$_gr_rc" -eq 0 ] \
        && pass "reuse guard: own primary group passes (V15)" \
        || fail "reuse guard: own primary group passes (V15, rc $_gr_rc)"
fi

# --- 0.0.44b W6/W14: EOF bails in BOTH Step-2 loops -----------------------------------
# The 0.0.44a V6 fix closed the outer selection loop only; the custom-
# path sub-loop still spun forever on a dead stdin (the class rule the
# wave itself added, applied to itself). Both empty-read guards are
# extracted and executed against an _ui_read stub that always yields
# the empty string.
_loop_w=$(sed -n '/^                    while \[ -z "\$_custom" \]; do$/,/^                    done$/p' "$_install_sh")
[ -n "$_loop_w" ] \
    && pass "install.sh: custom-path loop extractable (W6)" \
    || fail "install.sh: custom-path loop extractable (W6)"
if [ -n "$_loop_w" ]; then
    _w6_rc=0
    (
        _ui_read() {
            # hang breaker (0.0.44c C5): on a W6 revert the pre-fix loop
            # spins on empty reads — force-exit 124 after 9 so the pin
            # FAILS with a name instead of hanging the suite
            _ui_n=$((_ui_n + 1))
            [ "$_ui_n" -gt 9 ] && exit 124
            eval "$1="
        }
        _ui_n=0
        project_path_sane() { return 0; }
        ui_error() { :; }
        ui_info()  { :; }
        _PP_NORM="/var/tmp/x"
        _custom=""
        custom=""
        _custom_empty=0
        eval "$_loop_w"
    ) || _w6_rc=$?
    [ "$_w6_rc" -eq 1 ] \
        && pass "custom-path loop aborts on 5 empty reads instead of spinning (W6)" \
        || fail "custom-path loop aborts on 5 empty reads instead of spinning (W6, rc $_w6_rc)"
fi
_outer_bail=$(sed -n '/^            if \[ -z "\$selection" \]; then$/,/^            fi$/p' "$_install_sh")
[ -n "$_outer_bail" ] \
    && pass "install.sh: outer empty-read guard extractable (W14)" \
    || fail "install.sh: outer empty-read guard extractable (W14)"
if [ -n "$_outer_bail" ]; then
    _w14_rc=0
    (
        ui_error() { :; }
        _sel_empty=0
        _n=0
        while [ "$_n" -lt 5 ]; do
            selection=""
            eval "$_outer_bail"
            [ "$_sel_empty" -gt 0 ] && [ "$_n" -eq 4 ] && exit 1   # not reached: exit comes first
            _n=$((_n + 1))
        done
        exit 0
    ) || _w14_rc=$?
    [ "$_w14_rc" -eq 1 ] \
        && pass "outer selection guard exits on the 5th empty read (W14)" \
        || fail "outer selection guard exits on the 5th empty read (W14, rc $_w14_rc)"
fi
# and --yes takes the documented skip: the SKIP_PROMPTS elif sits before
# the interactive prompt block (order pin)
_skip_ln=$(grep -n 'elif \[ "\$SKIP_PROMPTS" = true \]; then' "$_install_sh" | head -1 | cut -d: -f1)
_prompt_ln=$(grep -n 'ui_section "Project roots"' "$_install_sh" | head -1 | cut -d: -f1)
[ -n "$_skip_ln" ] && [ -n "$_prompt_ln" ] && [ "$_skip_ln" -lt "$_prompt_ln" ] \
    && pass "--yes skip branch precedes the interactive prompt (W14)" \
    || fail "--yes skip branch precedes the interactive prompt (W14)"

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
expect_rc 1 "--migrate-agents without a value aborts" --yes --migrate-agents
expect_rc 1 "--migrate-agents with an invalid value aborts" --yes --migrate-agents steal

# Glob metacharacters in --projects values are rejected in parse_args on
# the RAW argument (0.0.42f S2): the old in-loop gate ran after the
# for-list pathname expansion and never saw a matching glob.
expect_rc 1 "--projects value with glob characters aborts" --yes --projects '/var/www/vhosts/*'
expect_rc 1 "--projects value with question mark aborts" --yes --projects '/opt/?vhosts'
expect_rc 0 "plain --projects value passes parse_args" --yes --projects /var/www/vhosts

# --- channel stamp (issue #38) -----------------------------------------------

# install.sh stamps the actually-used ref as KIT_CHANNEL into install.conf
# and reports it in the final summary. Since 0.0.39g C5 the stamp is
# written to a temp file beside it and renamed onto the canonical path —
# assert the full atomic shape (heredoc tee into the temp + mv).
if grep -qF "KIT_CHANNEL=\$KIT_BRANCH" "$INSTALL" \
   && grep -qF 'tee "$_INSTALL_CONF_TMP"' "$INSTALL" \
   && grep -qF 'mv -f "$_INSTALL_CONF_TMP" /etc/opencode-permissions-kit/install.conf' "$INSTALL" \
   && grep -qF 'ui_kv "Channel"' "$INSTALL"; then
    pass "install.sh stamps KIT_CHANNEL and reports the channel"
else
    fail "install.sh stamps KIT_CHANNEL and reports the channel"
fi

# --- session hint (issue #73) -------------------------------------------------

# The install's rc hook, profile PATH/umask and above all the sharing-group
# membership (usermod -aG) only reach sessions started AFTER the install —
# the final output must say so (mirrors the uninstall hint).
if grep -qF 'Restart your terminal (or log in again)' "$INSTALL" \
   && grep -qF 'sharing-group membership' "$INSTALL"; then
    pass "install final output tells the user to restart the terminal (issue #73)"
else
    fail "install final output tells the user to restart the terminal (issue #73)"
fi

# --- scratch cleanup (review 0.0.39a C1) ---------------------------------------

# Root-running installer must not leak its temp artifacts on failure or
# Ctrl-C: fetch tree + sudoers render temp are trapped on EXIT, and the
# signal handlers EXIT after cleanup (a resuming script would run on with
# its scratch already deleted). The backup dir is deliberately NOT in the
# trap (recovery material).
if grep -qF 'trap cleanup EXIT' "$INSTALL" \
   && grep -qF "trap 'cleanup; exit 1' INT TERM" "$INSTALL" \
   && grep -qF '_FETCH_TREE="$base"' "$INSTALL"; then
    pass "install.sh traps EXIT + exiting INT/TERM and registers the fetch tree for cleanup"
else
    fail "install.sh traps EXIT + exiting INT/TERM and registers the fetch tree for cleanup"
fi

# --- scratch cleanup: fetch refuses empty bodies (review 0.0.39e C1) --------------
# Fake curl: every file gets content EXCEPT etc/umask.sh, which answers
# HTTP-200-style success with an EMPTY body (captive portal / broken
# mirror). fetch_kit must abort instead of deploying the empty file.
FKWORK=$(mktemp -d)
mkdir -p "$FKWORK/bin"
cat > "$FKWORK/bin/curl" <<'FAKE'
#!/bin/sh
# args: -fsSL <url> -o <tmpfile>
last=
for a in "$@"; do last="$a"; done
case "$2" in
    */files/etc/umask.sh) : > "$last"; exit 0 ;;   # empty-but-200
    *) printf 'content\n' > "$last"; exit 0 ;;
esac
FAKE
chmod +x "$FKWORK/bin/curl"
eval "$(sed -n '/^fetch_kit() {/,/^}/p' "$INSTALL")"
# fetch_kit registers its fetch temps via _tmp_track (the host script's
# trap empties the registry; the isolated function only needs it defined).
_tmp_track() { :; }
FKOUT=""
FKRC=0
FKOUT=$(PATH="$FKWORK/bin:$PATH" KIT_BASE_URL="https://example.test" fetch_kit 2>&1) || FKRC=$?
if [ "$FKRC" -ne 0 ] && printf '%s' "$FKOUT" | grep -q "empty"; then
    pass "fetch_kit aborts on an empty (200) body instead of deploying it"
else
    fail "fetch_kit aborts on an empty (200) body (rc=$FKRC out=$FKOUT)"
fi
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
if grep -q '\[ ! -s "\$_fk_tmp" \]' "$UPDATE" && grep -q '_fk_url="\$KIT_BASE_URL/VERSION"' "$UPDATE"; then
    pass "update.sh fetch_kit carries the same empty-body guard (twin in sync)"
else
    fail "update.sh fetch_kit carries the same empty-body guard"
fi
# Direct call, never a command substitution: a subshell's _FETCH_TREE /
# registry writes never reach the parent and void the cleanup trap
# (wave-f review). Anchored — the comments reference the old form, the
# assignment must not exist.
if ! grep -q '^    SCRIPT_DIR="$(fetch_kit)"' "$INSTALL" \
   && ! grep -q '^    SCRIPT_DIR="$(fetch_kit)"' "$UPDATE" \
   && grep -q '_FK_DIR="\$dir"' "$INSTALL" && grep -q '_FK_DIR="\$dir"' "$UPDATE"; then
    pass "fetch_kit result leaves the shell via _FK_DIR, not a subshell echo"
else
    fail "fetch_kit result leaves the shell via _FK_DIR, not a subshell echo"
fi
# the test's own fetch run registered the tree — remove it
rm -rf "${_FETCH_TREE:-}" 2>/dev/null || true
rm -rf "$FKWORK"
# --- sudo-rs gate (Ubuntu 26.04): abort, never hang ------------------------------
# sudo-rs (Ubuntu 26.04's default sudo, < 0.2.14) permanently stops the
# read subshell of an interactive prompt when stdin is a pipe (upstream
# #1598): a streamed interactive install would freeze at the FIRST menu,
# rescue needs a second window + kill -CONT. install.sh must abort such a
# run BEFORE that menu (fail-closed), pass --yes runs through (no prompts
# = no hang), open the gate again from 0.2.14 (fix released), and ignore
# classic sudo entirely.
if grep -qF '_sudo_rs_gate()' "$INSTALL" \
   && grep -qF '[ -t 0 ] && return 0' "$INSTALL" \
   && grep -qF 'sudo --version 2>/dev/null | head -1' "$INSTALL"; then
    pass "install.sh has the _sudo_rs gate (tty guard + sudo-rs probe)"
else
    fail "install.sh has the _sudo_rs gate (tty guard + sudo-rs probe)"
fi
_rs_gate_ln=$(grep -n '^    _sudo_rs_gate$' "$INSTALL" | head -1 | cut -d: -f1)
_rs_menu_ln=$(grep -n 'ui_menu "How do you want to install?"' "$INSTALL" | head -1 | cut -d: -f1)
[ -n "$_rs_gate_ln" ] && [ -n "$_rs_menu_ln" ] && [ "$_rs_gate_ln" -lt "$_rs_menu_ln" ] \
    && pass "sudo-rs gate runs before the first interactive menu (order pin)" \
    || fail "sudo-rs gate runs before the first interactive menu (gate=$_rs_gate_ln menu=$_rs_menu_ln)"
grep -qF 'a[3]+0>=14' "$INSTALL" \
    && pass "gate version floor is sudo-rs 0.2.14 (fix release)" \
    || fail "gate version floor is sudo-rs 0.2.14 (fix release)"

# Functional: the extracted gate against sudo version shims (stdin piped
# via </dev/null, output stubs, exit 1 confined to a subshell).
SRSWORK=$(mktemp -d)
mkdir -p "$SRSWORK/bin"
mk_sudo_shim() {
    printf '#!/bin/sh\necho "%s"\n' "$1" > "$SRSWORK/bin/sudo"
    chmod +x "$SRSWORK/bin/sudo"
}
if [ -n "$(sed -n '/^_sudo_rs_gate() {/,/^}/p' "$INSTALL")" ]; then
    eval "$(sed -n '/^_sudo_rs_gate() {/,/^}/p' "$INSTALL")"
    ui_error()  { echo "error: $*"; }
    ui_info()   { echo "info: $*"; }
    ui_detail() { echo "detail: $*"; }
    log() { :; }
    run_gate() {
        ( export INTERACTIVE="$1" PATH="$SRSWORK/bin:$PATH"; _sudo_rs_gate ) </dev/null 2>&1
    }
    mk_sudo_shim 'sudo-rs 0.2.13-0ubuntu1.2'
    _rg_rc=0; _rg_out=$(run_gate true) || _rg_rc=$?
    if [ "$_rg_rc" -eq 1 ] && printf '%s' "$_rg_out" | grep -q 'non-interactively'; then
        pass "buggy sudo-rs + interactive + piped stdin -> abort with instructions (rc 1)"
    else
        fail "buggy sudo-rs + interactive + piped stdin -> abort with instructions (rc=$_rg_rc out=$_rg_out)"
    fi
    _rg_rc=0; _rg_out=$(run_gate false) || _rg_rc=$?
    if [ "$_rg_rc" -eq 0 ] && printf '%s' "$_rg_out" | grep -q 'prompts skipped'; then
        pass "buggy sudo-rs + --yes -> passes with an info line (rc 0)"
    else
        fail "buggy sudo-rs + --yes -> passes with an info line (rc=$_rg_rc out=$_rg_out)"
    fi
    mk_sudo_shim 'sudo-rs version 0.2.15'
    _rg_rc=0; _rg_out=$(run_gate true) || _rg_rc=$?
    if [ "$_rg_rc" -eq 0 ] && ! printf '%s' "$_rg_out" | grep -q 'error:'; then
        pass "fixed sudo-rs (>= 0.2.14) -> interactive run passes (gate open)"
    else
        fail "fixed sudo-rs (>= 0.2.14) -> interactive run passes (rc=$_rg_rc out=$_rg_out)"
    fi
    mk_sudo_shim 'sudo-rs version unknown-build'
    _rg_rc=0; _rg_out=$(run_gate true) || _rg_rc=$?
    [ "$_rg_rc" -eq 1 ] \
        && pass "unparseable sudo-rs version -> fail-closed abort (interactive)" \
        || fail "unparseable sudo-rs version -> fail-closed abort (rc=$_rg_rc out=$_rg_out)"
    mk_sudo_shim 'Sudo version 1.9.15p5'
    _rg_rc=0; _rg_out=$(run_gate true) || _rg_rc=$?
    [ "$_rg_rc" -eq 0 ] \
        && pass "classic sudo -> gate is a no-op" \
        || fail "classic sudo -> gate is a no-op (rc=$_rg_rc out=$_rg_out)"
else
    fail "_sudo_rs_gate extractable from install.sh"
fi
rm -rf "$SRSWORK"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All install.sh arg-parsing tests passed.${NC}"
exit 0
