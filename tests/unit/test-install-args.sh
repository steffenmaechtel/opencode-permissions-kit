#!/bin/sh
# Unit tests for install.sh's parse_args():
#   - flags work in any order (the old loop broke after --projects and
#     silently dropped every flag that followed it)
#   - --projects consumes all following non-flag args, parsing continues
#   - unknown options abort instead of being silently ignored
#   - --container-backend without a value aborts
#
# Unit tests for the distro whitelist gate (issue #145, 0.0.45a):
#   - --force-unsupported-distro parses / defaults to false
#   - os-release read pins: static (sed, never sourced) + behavioral
#     (the real read lines against fixtures: missing file, single-quoted
#     and CRLF values — 0.0.45a S1/C2)
#   - extracted _distro_gate functional matrix, verbatim call wiring pin
#     (0.0.45a C1) + gate-before-menu order pin
#
# Static extraction of parse_args() from install.sh, then table-driven
# checks. No root required.
#
# The three phase functions live in sh/install-core.sh since #346 wave 3
# — pins whose literal moved are retargeted to $INSTALL_CORE, absence
# pins cover BOTH files (the wave-2 sweep idiom), and the four fragment
# block-extractions (V15 guards, W6/W14 loops, V1 normalize case) are
# GONE: their fragments are lib functions now, pinned by sourcing in
# tests/unit/test-install-core.sh (the #396 payoff).
#
# Unit tests for the python3 health gate (#244 a W1/S1, b Q1/Q2/S2):
#   - extracted _py3_health_probe functional matrix: healthy passes,
#     absent and broken-shim abort loud (two distinct error classes),
#     hostile PYTHONPATH is ignored (-I isolation), and a noisy broken
#     interpreter surfaces its own diagnostic (#244 b S2)
#   - import-union drift pin: every shipped python import module must
#     appear in the gate's import list (#244 b Q1)
#   - verbatim call wiring pin + old inline-gate replacement count pin
#
# Run: sh tests/unit/test-install-args.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL="$SCRIPT_DIR/../../files/install.sh"
INSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

if [ -n "$(extract_func "$INSTALL" parse_args)" ]; then
    pass "parse_args defined in install.sh"
else
    fail "parse_args defined in install.sh"
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi

eval "$(extract_func "$INSTALL" parse_args)"

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
    FORCE_UNSUPPORTED_DISTRO=false
    OPENCHAMBER_POLICY=""
    OPENCHAMBER_POLICY_OPT=""
    OPENCHAMBER_POLICY_GIVEN=false
}

# expect_rc <want-rc> <description> <args...>
# Runs parse_args in a SUBSHELL: the function exits on bad input, and that
# exit must terminate only the subshell, not this test script.
expect_rc() {
    _want="$1"
    _desc="$2"
    shift 2
    reset_globals
    if [ "$_want" = "0" ]; then
        # Subshell (0.0.42g C1): parse_args aborts via exit 1 — a direct
        # call in this set -e shell would kill the whole suite instead
        # of recording the FAIL.
        if (parse_args "$@") 2>/dev/null; then
            pass "$_desc"
        else
            fail "$_desc (unexpected abort)"
        fi
    else
        if (parse_args "$@") 2>/dev/null; then
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

# #211 b W2: the -y alias cli.md documents — same family shape as
# update/config/uninstall. Abort-contained (#211 c W5): a reverted
# alias aborts parse_args (exit 1) — a bare call under this suite's
# set -e would kill the whole suite pre-tally instead of recording
# this FAIL (the expect_rc convention, 0.0.42g C1). The state is
# printed INSIDE the subshell — the assignment cannot cross it.
reset_globals
_cw5_out="$( (parse_args -y && printf '%s\n' "$SKIP_PROMPTS") 2>/dev/null)" || true
case "$_cw5_out" in
    true) pass "-y alias sets SKIP_PROMPTS (#211 b W2)" ;;
    *) fail "-y alias sets SKIP_PROMPTS (#211 b W2) (got: ${_cw5_out:-abort})" ;;
esac

reset_globals
parse_args --secure-git-config
[ "$SECURE_GIT_CONFIG" = true ] && [ "$GIT_FLAG_GIVEN" = true ] &&
    pass "--secure-git-config sets the flag + marker" ||
    fail "--secure-git-config sets the flag + marker"

reset_globals
parse_args --container-backend podman-rootless
[ "$CONTAINER_BACKEND_OPT" = "podman-rootless" ] &&
    pass "--container-backend captures its value" ||
    fail "--container-backend captures its value"

reset_globals
parse_args --skip-ddev-migration
[ "$SKIP_DDEV_MIGRATION" = true ] &&
    pass "--skip-ddev-migration sets the flag" ||
    fail "--skip-ddev-migration sets the flag"

# --ddev-settings (dev-owned mode): valid values captured, default on.
reset_globals
parse_args --ddev-settings dev-owned
[ "$DDEV_DEV_OWNED" = true ] && [ "$DDEV_SETTINGS_GIVEN" = true ] &&
    pass "--ddev-settings dev-owned is captured" ||
    fail "--ddev-settings dev-owned is captured"
reset_globals
parse_args --ddev-settings ddev
[ "$DDEV_DEV_OWNED" = false ] && [ "$DDEV_SETTINGS_GIVEN" = true ] &&
    pass "--ddev-settings ddev is captured (handover model)" ||
    fail "--ddev-settings ddev is captured (handover model)"
reset_globals
parse_args --yes
[ "$DDEV_DEV_OWNED" = true ] && [ "$DDEV_SETTINGS_GIVEN" = false ] &&
    pass "dev-owned mode ON by default (recommended)" ||
    fail "dev-owned mode ON by default (recommended)"
expect_rc 1 "--ddev-settings with an invalid value aborts" --ddev-settings maybe
expect_rc 1 "--ddev-settings without a value aborts" --ddev-settings

reset_globals
parse_args --yes
[ "$SKIP_DDEV_MIGRATION" = false ] &&
    pass "ddev migration stays ON by default" ||
    fail "ddev migration stays ON by default"

# --openchamber-policy (issue #154): valid values captured, invalid aborts,
# undecided by default (opt-in — detection + prompt decide, --yes keeps off).
for _ocp_v in yes no; do
    reset_globals
    parse_args --openchamber-policy "$_ocp_v"
    [ "$OPENCHAMBER_POLICY_OPT" = "$_ocp_v" ] && [ "$OPENCHAMBER_POLICY_GIVEN" = true ] &&
        pass "--openchamber-policy $_ocp_v is captured" ||
        fail "--openchamber-policy $_ocp_v is captured"
done
reset_globals
parse_args --yes
[ "$OPENCHAMBER_POLICY_OPT" = "" ] && [ "$OPENCHAMBER_POLICY_GIVEN" = false ] &&
    pass "openchamber policy undecided by default (opt-in)" ||
    fail "openchamber policy undecided by default (opt-in)"
reset_globals
parse_args --projects /var/www/vhosts --openchamber-policy yes
[ "$OPENCHAMBER_POLICY_OPT" = "yes" ] &&
    pass "--openchamber-policy works after --projects" ||
    fail "--openchamber-policy works after --projects"
expect_rc 1 "--openchamber-policy with an invalid value aborts" --openchamber-policy maybe
expect_rc 1 "--openchamber-policy without a value aborts" --openchamber-policy

# --migrate-agents (issue #19): valid values captured, invalid abort.
for _ma_v in move copy skip; do
    reset_globals
    parse_args --migrate-agents "$_ma_v"
    [ "$MIGRATE_AGENTS_OPT" = "$_ma_v" ] &&
        pass "--migrate-agents $_ma_v is captured" ||
        fail "--migrate-agents $_ma_v is captured"
done
reset_globals
parse_args --yes
[ "$MIGRATE_AGENTS_OPT" = "" ] &&
    pass "agents migration undecided by default (prompt/--yes recommended)" ||
    fail "agents migration undecided by default"
reset_globals
parse_args --projects /var/www/vhosts --migrate-agents copy
[ "$MIGRATE_AGENTS_OPT" = "copy" ] &&
    pass "--migrate-agents works after --projects" ||
    fail "--migrate-agents works after --projects"

# Word forms normalize to the menu letters (0.0.44a V1): the
# normalization case and its before-the-dispatch order are FUNCTION pins
# since #346 wave 3 — the case moved into install_core's
# install_agents_form_normalize, sourced and called with stubs in
# tests/unit/test-install-core.sh (the #396 payoff: no more
# indentation-anchored block extraction here).

# Developer-side paths ride DEV_HOME, getent-resolved (0.0.44a V14): the
# installer used to hardcode /home/$DEFAULT_USER in ~14 provisioning
# sites (ddev discovery, .ddev registry, rc hooks, agents sources, the
# deny-all config, TUI theme) although it resolves the same home via
# getent 20 lines further up. Swept like the siblings below since
# #196 b B1: the former trailing-slash-only negation let the old gate
# shape `[ -d "/home/$DEFAULT_USER" ]` back in green. The initializer
# line itself is the one sanctioned slash-less site — positively pinned
# by the first grep and subtracted from the negative sweep.
# #346 wave 3: the initializer + getent live in install-core.sh (the
# plan phase moved); usage sites must stay absent from BOTH files (the
# wave-2 both-files sweep idiom).
_v14i_bad="$(cat "$INSTALL" "$INSTALL_CORE" |
    grep -e '/home/\$DEFAULT_USER' -e '/home/\${DEFAULT_USER' 2>/dev/null |
    grep -v '^[[:space:]]*#' |
    grep -v '^[[:space:]]*DEV_HOME="/home/\$DEFAULT_USER"$' || true)"
if grep -q 'DEV_HOME="/home/\$DEFAULT_USER"' "$INSTALL_CORE" &&
    grep -q 'getent passwd "\$DEFAULT_USER"' "$INSTALL_CORE" &&
    [ -z "$_v14i_bad" ]; then
    pass "install.sh: DEV_HOME via getent, no hardcoded /home/\$DEFAULT_USER left (V14)"
else
    fail "install.sh: DEV_HOME via getent, no hardcoded /home/\$DEFAULT_USER left (V14: ${_v14i_bad:-no initializer or getent})"
fi

# V14 sibling sweep (issue #192, tightened by #196 a T1; braced spelling
# added by #196 b B2): the management scripts lagged install.sh and kept
# hardcoded /home/$DEFAULT_USER usage sites — on the root-shell installs
# the new gate refuses, that path pointed at /home/root (never exists),
# so status warned "run opk update" while update silently skipped the
# whole hook section. The sweep flags every slash form of the literal
# spelling, braced included — the old update.sh gate was exactly
# `[ -d "/home/$DEFAULT_USER" ]`, and a trailing-slash-only pattern would
# let that exact shape back in green. Allowed survivors: comment lines,
# the getent-failure fallback (`|| var="/home/$DEFAULT_USER"`), and the
# braced self-default fallback (`var="${var:-/home/${DEFAULT_USER:-$USER}}"`
# — status.sh's openchamber home, positively pinned by the 0.0.47c C1 rows).
# status.sh's home usages live in its section lib since the #346 wave-1
# decomposition, uninstall.sh's since wave 4 — entry + lib are checked for
# those two (getent in either, hardcoded usage sites in neither).
_v14_core="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh"
for _v14_sib in status update uninstall; do
    _v14_sh="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/$_v14_sib.sh"
    _v14_files="$_v14_sh"
    [ "$_v14_sib" = status ] && _v14_files="$_v14_sh
$_v14_core"
    [ "$_v14_sib" = uninstall ] && _v14_files="$_v14_sh
$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/uninstall-core.sh"
    _v14_bad="$(printf '%s\n' "$_v14_files" | while IFS= read -r _v14_f; do
        grep -e '/home/\$DEFAULT_USER' -e '/home/\${DEFAULT_USER' "$_v14_f" 2>/dev/null ||
            true
    done |
        grep -v '^[[:space:]]*#' |
        grep -v '|| [[:alnum:]_]\{1,\}="/home/\$DEFAULT_USER"$' |
        grep -v '[[:alnum:]_]\{1,\}="\${[[:alnum:]_]\{1,\}:-/home/\${DEFAULT_USER:-\$USER}}"$' |
        grep -v '[[:alnum:]_]\{1,\}="\${[[:alnum:]_]\{1,\}:-/home/\${DEFAULT_USER:-\${USER:-}}}"$' || true)"
    # (the last allow-arm: the F9-deepened fallback #211 a F9 — set -u
    # survives both-unset; same self-default shape, one level deeper)
    _v14_getent=0
    for _v14_f in $_v14_files; do
        grep -q 'getent passwd "\$DEFAULT_USER"' "$_v14_f" 2>/dev/null && _v14_getent=1
    done
    if [ "$_v14_getent" = 1 ] && [ -z "$_v14_bad" ]; then
        pass "$_v14_sib.sh: developer home via getent, no hardcoded usage site (V14 sibling)"
    else
        fail "$_v14_sib.sh: developer home via getent, no hardcoded usage site (V14 sibling: ${_v14_bad:-no getent})"
    fi
done

# V15 (reuse guards) and 0.0.44b W6/W14 (EOF bails in both Step-2
# loops) are FUNCTION pins since #346 wave 3: the guards and the whole
# Step-2 selection block moved into install-core's
# install_reuse_home_guard / install_reuse_group_guard /
# install_project_roots_select, sourced and called against getent/id and
# _ui_read stubs in tests/unit/test-install-core.sh (the #396 payoff).
# The --yes-skip-before-prompt order pin moved with them (both literals
# live in do_plan_phase / its selection helper now).

# The regression this file exists for: flags AFTER --projects used to be
# silently dropped (the old loop `break`ed out of the parser).
reset_globals
parse_args --projects /var/www/vhosts /home/dev/x --yes --secure-git-config
if [ "$SKIP_PROMPTS" = true ] && [ "$GIT_FLAG_GIVEN" = true ] &&
    [ "$PREDEFINED_PROJECTS" = " /var/www/vhosts /home/dev/x" ]; then
    pass "--projects does not swallow following flags (--yes/--secure-git-config applied)"
else
    fail "--projects does not swallow following flags (projects='$PREDEFINED_PROJECTS' yes=$SKIP_PROMPTS git=$GIT_FLAG_GIVEN)"
fi

# --container-backend AFTER --projects works too (docs used to require the
# opposite order).
reset_globals
parse_args --projects /var/www/vhosts --container-backend docker-rootless
[ "$CONTAINER_BACKEND_OPT" = "docker-rootless" ] &&
    pass "--container-backend works after --projects" ||
    fail "--container-backend works after --projects"

# A flag directly after the --projects list stops project consumption and
# is parsed as a flag; a path starting with '-' is not a project root.
reset_globals
parse_args --yes --projects --container-backend docker-rootless
[ "$PREDEFINED_PROJECTS" = "" ] && [ "$CONTAINER_BACKEND_OPT" = "docker-rootless" ] &&
    pass "--projects with no roots keeps parsing (--container-backend applied)" ||
    fail "--projects with no roots keeps parsing (projects='$PREDEFINED_PROJECTS')"

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
# assert the full atomic shape (heredoc tee into the temp + mv). The
# stamp writes live in install-core.sh since #346 wave 3 (the plan
# phase moved); the ui_kv summary row stays in the entry's tail — each
# leg greps the file that owns the literal (the wave-2 split-pin idiom).
if grep -qF "KIT_CHANNEL=\$KIT_BRANCH" "$INSTALL_CORE" &&
    grep -qF 'tee "$_INSTALL_CONF_TMP"' "$INSTALL_CORE" &&
    grep -qF 'mv -f "$_INSTALL_CONF_TMP" /etc/opencode-permissions-kit/install.conf' "$INSTALL_CORE" &&
    grep -qF 'ui_kv "Channel"' "$INSTALL"; then
    pass "install.sh stamps KIT_CHANNEL and reports the channel"
else
    fail "install.sh stamps KIT_CHANNEL and reports the channel"
fi

# --- session hint (issue #73) -------------------------------------------------

# The install's rc hook, profile PATH/umask and above all the sharing-group
# membership (usermod -aG) only reach sessions started AFTER the install —
# the final output must say so (mirrors the uninstall hint).
if grep -qF 'Restart your terminal (or log in again)' "$INSTALL" &&
    grep -qF 'sharing-group membership' "$INSTALL"; then
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
if grep -qF 'trap cleanup EXIT' "$INSTALL" &&
    grep -qF "trap 'cleanup; exit 1' INT TERM" "$INSTALL" &&
    grep -qF '_FETCH_TREE="$base"' "$INSTALL"; then
    pass "install.sh traps EXIT + exiting INT/TERM and registers the fetch tree for cleanup"
else
    fail "install.sh traps EXIT + exiting INT/TERM and registers the fetch tree for cleanup"
fi

# --- scratch cleanup: fetch refuses empty bodies (review 0.0.39e C1) --------------
# Fake curl: every file gets content EXCEPT etc/umask.sh, which answers
# HTTP-200-style success with an EMPTY body (captive portal / broken
# mirror). fetch_kit must abort instead of deploying the empty file.
FKWORK=$(mktemp -d)
# Trap every mktemp receiver of this suite on abort and signals (#283):
# the suite had no live trap (its only "trap" lines are grep pins over
# install.sh), so a set -e abort between a receiver's creation and its
# inline rm leaked the scratch in /tmp. The receiver list is a function
# because twelve receivers do not fit one line; every operand is
# unset-safe — receivers created in conditionals below (the _p3* block)
# may not exist at fire time, and an unset operand expands empty, which
# rm skips. Sibling idiom: the scratch traps in test-project-paths.sh
# (line form) and test-fs-baseline.sh (function form).
_trap_cleanup() {
    rm -rf "${FKWORK:-}" "${_dg_w:-}" "${_pb_w:-}" "${_py3w:-}" \
        "${_p3tmp:-}" "${_p3g:-}" "${_p3raw:-}" "${_p3mods:-}" \
        "${_p3fx:-}" "${_p3fraw:-}" "${_p3fmods:-}" "${_p3fwant:-}"
}
trap _trap_cleanup EXIT INT TERM
mkdir -p "$FKWORK/bin"
cat >"$FKWORK/bin/curl" <<'FAKE'
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
eval "$(extract_func "$INSTALL" fetch_kit)"
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

# --- dead-TMPDIR staging guards (#364 sweep sibling) ------------------------
# fetch_kit's base mktemp ran unguarded where set -e cannot reach it:
# both hosts call `fetch_kit || {...}` (a suppressed callee), so a dead
# TMPDIR left base="" and the pre-create ran mkdir -p /files/... AS ROOT
# (the #360 a F5 class) before the fetch errors blamed curl; a dead
# per-file _fk_tmp surfaced as "could not fetch". Two scenarios per
# host, executing the EXTRACTED function (the twin-grep above proves
# shape only): (a) real mktemp + dead TMPDIR -> the base guard fires
# BEFORE any mkdir runs (the stub records every call — zero records is
# the no-root-garbage pin); (b) stubbed mktemp (ok for base, fails on
# the per-file call) -> the _fk_tmp guard names mktemp, not curl.
_fkg_i=0
for _fkg_host in "$INSTALL" "$UPDATE"; do
    _fkg_i=$((_fkg_i + 1))
    _fkg_w="$FKWORK/g-$_fkg_i"
    mkdir -p "$_fkg_w/a-bin" "$_fkg_w/b-bin"
    _fkg_name="$(basename "$_fkg_host")"
    eval "$(extract_func "$_fkg_host" fetch_kit)"
    _tmp_track() { :; }

    # shared: fake curl (never reached in green; sabotage must not hit
    # the network) + recording mkdir stub (proves what mkdir WOULD run)
    for _fkg_bin in a b; do
        cat >"$_fkg_w/$_fkg_bin-bin/curl" <<FAKE
#!/bin/sh
_last=
for _a in "\$@"; do _last="\$_a"; done
printf 'content\n' >"\$_last"
FAKE
        cat >"$_fkg_w/$_fkg_bin-bin/mkdir" <<FAKE
#!/bin/sh
printf '%s\n' "\$*" >>"$_fkg_w/$_fkg_bin-mkdir.log"
exit 0
FAKE
        chmod 755 "$_fkg_w/$_fkg_bin-bin/curl" "$_fkg_w/$_fkg_bin-bin/mkdir"
    done

    # (a) real mktemp, dead TMPDIR -> base guard, no mkdir call at all.
    # KIT_FILES: update.sh's copy iterates the global list (install.sh's
    # is inline) — an empty one would run zero iterations and pass
    # vacuously through a green rc 0.
    _fkg_out=""
    _fkg_rc=0
    _fkg_out=$(TMPDIR="$_fkg_w/dead" PATH="$_fkg_w/a-bin:$PATH" \
        KIT_BASE_URL="https://example.test" KIT_FILES="opencode-permissions-kit-lib/sh/ui.sh" \
        fetch_kit 2>&1) || _fkg_rc=$?
    if [ "$_fkg_rc" -ne 0 ] &&
        printf '%s' "$_fkg_out" | grep -qF 'mktemp failed (is $TMPDIR writable?)' &&
        printf '%s' "$_fkg_out" | grep -q 'cannot stage the kit fetch' &&
        ! printf '%s' "$_fkg_out" | grep -q 'could not fetch' &&
        [ ! -e "$_fkg_w/a-mkdir.log" ]; then
        pass "$_fkg_name: dead TMPDIR stops fetch_kit before any mkdir (#364)"
    else
        fail "$_fkg_name: dead TMPDIR staging diagnostics (rc=$_fkg_rc out=$_fkg_out)"
    fi

    # (b) mktemp stub: call 1 (base -d) answers a scratch path, call 2+
    # (per-file) fails -> the _fk_tmp guard names mktemp, not curl, and
    # the pre-create mkdirs landed under the scratch base, never /files
    cat >"$_fkg_w/b-bin/mktemp" <<FAKE
#!/bin/sh
_n=\$(( \$(cat "$_fkg_w/cnt" 2>/dev/null || echo 0) + 1 ))
echo "\$_n" >"$_fkg_w/cnt"
if [ "\$_n" -gt 1 ]; then
    echo "mktemp: stubbed per-file failure" >&2
    exit 1
fi
printf '%s\n' "$_fkg_w/stub-base"
FAKE
    chmod 755 "$_fkg_w/b-bin/mktemp"
    _fkg_out=""
    _fkg_rc=0
    _fkg_out=$(PATH="$_fkg_w/b-bin:$PATH" \
        KIT_BASE_URL="https://example.test" KIT_FILES="opencode-permissions-kit-lib/sh/ui.sh" \
        fetch_kit 2>&1) || _fkg_rc=$?
    if [ "$_fkg_rc" -ne 0 ] &&
        printf '%s' "$_fkg_out" | grep -qF 'mktemp failed (is $TMPDIR writable?)' &&
        ! printf '%s' "$_fkg_out" | grep -q 'could not fetch' &&
        ! grep -q '^/files' "$_fkg_w/b-mkdir.log"; then
        pass "$_fkg_name: dead per-file mktemp names mktemp, not curl (#364)"
    else
        fail "$_fkg_name: per-file mktemp diagnostics (rc=$_fkg_rc out=$_fkg_out)"
    fi
done
unset _fkg_host _fkg_w _fkg_bin _fkg_name _fkg_out _fkg_rc _fkg_i
# Direct call, never a command substitution: a subshell's _FETCH_TREE /
# registry writes never reach the parent and void the cleanup trap
# (wave-f review). Anchored — the comments reference the old form, the
# assignment must not exist.
if ! grep -q '^    SCRIPT_DIR="$(fetch_kit)"' "$INSTALL" &&
    ! grep -q '^    SCRIPT_DIR="$(fetch_kit)"' "$UPDATE" &&
    grep -q '_FK_DIR="\$dir"' "$INSTALL" && grep -q '_FK_DIR="\$dir"' "$UPDATE"; then
    pass "fetch_kit result leaves the shell via _FK_DIR, not a subshell echo"
else
    fail "fetch_kit result leaves the shell via _FK_DIR, not a subshell echo"
fi
# the test's own fetch run registered the tree — remove it
rm -rf "${_FETCH_TREE:-}" 2>/dev/null || true
rm -rf "$FKWORK"
# remove the fetched VERSION artifact fetch_kit may have written to CWD
# (it returns a tree path; nothing lands outside $FKWORK on failure)

# --- distro whitelist gate ----------------------------------------------------
# Ubuntu whitelist: only 22.04/24.04 install; every other Ubuntu version
# (incl. unknown/empty) aborts BEFORE the first prompt unless
# --force-unsupported-distro. Non-Ubuntu distros pass unchanged. Matrix
# mirrors docs/getting-started.md#supported-distros (issue #145).
reset_globals
parse_args --yes --force-unsupported-distro
[ "$FORCE_UNSUPPORTED_DISTRO" = true ] &&
    pass "--force-unsupported-distro parses" ||
    fail "--force-unsupported-distro parses"
reset_globals
parse_args --yes
[ "$FORCE_UNSUPPORTED_DISTRO" = false ] &&
    pass "force flag defaults to false" ||
    fail "force flag defaults to false"
# The reads sit in do_plan_phase (install-core.sh since #346 wave 3);
# the _distro_gate FUNCTION below stays in install.sh.
if grep -qF 'sed -n '"'"'s/^ID=//p'"'"' /etc/os-release' "$INSTALL_CORE" &&
    grep -qF 'sed -n '"'"'s/^VERSION_ID=//p'"'"' /etc/os-release' "$INSTALL_CORE"; then
    pass "gate reads ID/VERSION_ID from /etc/os-release (sed, not sourced)"
else
    fail "gate reads ID/VERSION_ID from /etc/os-release (sed, not sourced)"
fi
if [ -n "$(extract_func "$INSTALL" _distro_gate)" ]; then
    eval "$(extract_func "$INSTALL" _distro_gate)"
    ui_error() { echo "error: $*"; }
    ui_info() { echo "info: $*"; }
    ui_detail() { echo "detail: $*"; }
    ui_warn() { echo "warn: $*"; }
    log() { :; }
    run_distro_gate() {
        (
            export FORCE_UNSUPPORTED_DISTRO="$1"
            _distro_gate "$2" "$3"
        ) 2>&1
    }
    _dg_rc=0
    _dg_out=$(run_distro_gate false ubuntu 24.04) || _dg_rc=$?
    if [ "$_dg_rc" -eq 0 ] && ! printf '%s' "$_dg_out" | grep -q 'error:'; then
        pass "ubuntu 24.04 passes silently"
    else
        fail "ubuntu 24.04 passes silently (rc=$_dg_rc out=$_dg_out)"
    fi
    _dg_rc=0
    _dg_out=$(run_distro_gate false ubuntu 22.04) || _dg_rc=$?
    [ "$_dg_rc" -eq 0 ] &&
        pass "ubuntu 22.04 passes" ||
        fail "ubuntu 22.04 passes (rc=$_dg_rc out=$_dg_out)"
    _dg_rc=0
    _dg_out=$(run_distro_gate false ubuntu 26.04) || _dg_rc=$?
    if [ "$_dg_rc" -eq 1 ] && printf '%s' "$_dg_out" | grep -q 'not supported' &&
        printf '%s' "$_dg_out" | grep -q 'issues/145'; then
        pass "ubuntu 26.04 aborts with the supported list + issue #145"
    else
        fail "ubuntu 26.04 aborts with the supported list + issue #145 (rc=$_dg_rc out=$_dg_out)"
    fi
    _dg_rc=0
    _dg_out=$(run_distro_gate false ubuntu 25.10) || _dg_rc=$?
    [ "$_dg_rc" -eq 1 ] &&
        pass "ubuntu 25.10 (interim) aborts" ||
        fail "ubuntu 25.10 (interim) aborts (rc=$_dg_rc out=$_dg_out)"
    _dg_rc=0
    _dg_out=$(run_distro_gate false ubuntu '') || _dg_rc=$?
    [ "$_dg_rc" -eq 1 ] &&
        pass "ubuntu with unknown version aborts (fail-closed)" ||
        fail "ubuntu with unknown version aborts (rc=$_dg_rc out=$_dg_out)"
    _dg_rc=0
    _dg_out=$(run_distro_gate false debian 12) || _dg_rc=$?
    [ "$_dg_rc" -eq 0 ] &&
        pass "debian 12 passes (non-Ubuntu unchanged)" ||
        fail "debian 12 passes (rc=$_dg_rc out=$_dg_out)"
    _dg_rc=0
    _dg_out=$(run_distro_gate false debian '') || _dg_rc=$?
    [ "$_dg_rc" -eq 0 ] &&
        pass "debian without version passes" ||
        fail "debian without version passes (rc=$_dg_rc out=$_dg_out)"
    _dg_rc=0
    _dg_out=$(run_distro_gate true ubuntu 26.04) || _dg_rc=$?
    if [ "$_dg_rc" -eq 0 ] && printf '%s' "$_dg_out" | grep -q 'force-unsupported-distro'; then
        pass "--force-unsupported-distro overrides ubuntu 26.04 (warn + continue)"
    else
        fail "--force-unsupported-distro overrides ubuntu 26.04 (rc=$_dg_rc out=$_dg_out)"
    fi
else
    fail "_distro_gate extractable from install.sh"
fi
# The order pin (gate before the first menu) and the verbatim wiring
# pins moved to tests/unit/test-install-core.sh with the phase bodies
# (#346 wave 3) — the literals live in do_plan_phase / install-core.sh.
# Behavioral read pins (0.0.45a S1/C2): the REAL read lines, extracted,
# path-swapped onto fixtures and executed under bash with install.sh's
# own set -eu/pipefail idiom — a missing os-release must survive and
# parse empty (the || true; without it pipefail propagates sed's rc 2
# and errexit aborts rc 2 with zero output — invisible under dash, which
# is why the pins pin bash explicitly), single-quoted and CRLF values
# must normalize.
_dg_line_id="$(grep -F "_dg_id=\$(sed -n 's/^ID=//p' /etc/os-release" "$INSTALL_CORE" | head -1 | sed 's/^ *//')"
_dg_line_ver="$(grep -F "_dg_ver=\$(sed -n 's/^VERSION_ID=//p' /etc/os-release" "$INSTALL_CORE" | head -1 | sed 's/^ *//')"
_dg_w="$(mktemp -d)"
printf 'ID="ubuntu"\nVERSION_ID=%s\n' "'24.04'" >"$_dg_w/quoted"
printf 'ID=ubuntu\r\nVERSION_ID=24.04\r\n' >"$_dg_w/crlf"
_dg_eval_reads() {
    # bash, not the suite's sh: pipefail (the abort mechanism under
    # test) is a bash option — args: id-line, fixture path, ver-line
    bash -c '
        PS4="+ " # kcov shield: PS4 ${BASH_SOURCE} vs set -u (internal/records/kcov-coverage.md)
        set -eu
        (set -o pipefail) 2>/dev/null && set -o pipefail || true
        eval "$(printf "%s\n" "$1" | sed "s|/etc/os-release|$2|")"
        eval "$(printf "%s\n" "$3" | sed "s|/etc/os-release|$2|")"
        printf "%s\n%s" "${_dg_id:-}" "${_dg_ver:-}"
    ' _dg_read_sh "$_dg_line_id" "$1" "$_dg_line_ver"
}
if command -v bash >/dev/null 2>&1; then
    _dg_got_id() { printf '%s\n' "$_dg_out" | sed -n 1p; }
    _dg_got_ver() { printf '%s\n' "$_dg_out" | sed -n 2p; }
    _dg_rc=0
    _dg_out=$(_dg_eval_reads "$_dg_w/missing") || _dg_rc=$?
    if [ "$_dg_rc" -eq 0 ] && [ -z "$(printf '%s' "$_dg_out" | tr -d '\n')" ]; then
        pass "missing os-release survives the reads and parses empty (S1)"
    else
        fail "missing os-release survives the reads and parses empty (S1) (rc=$_dg_rc out=$_dg_out)"
    fi
    _dg_rc=0
    _dg_out=$(_dg_eval_reads "$_dg_w/quoted") || _dg_rc=$?
    if [ "$_dg_rc" -eq 0 ] && [ "$(_dg_got_id)" = ubuntu ] && [ "$(_dg_got_ver)" = 24.04 ]; then
        pass "quoted os-release values normalize, both quote styles (C2)"
    else
        fail "quoted os-release values normalize, both quote styles (C2) (rc=$_dg_rc id=$(_dg_got_id) ver=$(_dg_got_ver))"
    fi
    _dg_rc=0
    _dg_out=$(_dg_eval_reads "$_dg_w/crlf") || _dg_rc=$?
    if [ "$_dg_rc" -eq 0 ] && [ "$(_dg_got_id)" = ubuntu ] && [ "$(_dg_got_ver)" = 24.04 ]; then
        pass "CRLF-edited os-release parses clean (C2)"
    else
        fail "CRLF-edited os-release parses clean (C2) (rc=$_dg_rc id=$(_dg_got_id) ver=$(_dg_got_ver))"
    fi
else
    echo "  SKIP  S1/C2 read pins need bash (pipefail semantics)"
fi
rm -rf "$_dg_w"

# Behavioral probe pins (0.0.45c C1/C2): the REAL probe lines, extracted
# verbatim, binary-swapped onto a hanging shim and executed under bash
# with install.sh's own set -eu/pipefail idiom — a wedged binary (the
# timeout kill, rc 124) must NOT abort the installer: the old shape died
# rc 124 with ZERO output (dash hides the pipefail mechanism, hence
# bash-explicit, same as the os-release pins above). The duration is
# swapped 10 -> 1s (shim sleeps 3) to keep the suite fast — the swap
# touches only the timeout argument; the pipefail-able pipeline shape
# stays verbatim, so removing the || true re-aborts rc 124 and fails
# both pins.
_pb_w="$(mktemp -d)"
printf '#!/bin/sh\nsleep 3\n' >"$_pb_w/hang"
chmod +x "$_pb_w/hang"
_pb_pf="$(grep -F '_pf_oc_ver=$(timeout 10 "$_pf_oc_bin" --version' "$INSTALL_CORE" | head -1 | sed 's/^ *//' | sed 's/timeout 10/timeout 1/')"
_pb_st="$(grep -F '_stamp_ver=$(timeout 10 "$SYSTEM_BIN" --version' "$INSTALL_CORE" | head -1 | sed 's/^ *//' | sed 's/timeout 10/timeout 1/')"
if command -v bash >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1 &&
    [ -n "$_pb_pf" ] && [ -n "$_pb_st" ]; then
    _pb_rc=0
    _pb_out=$(bash -c '
        PS4="+ " # kcov shield: PS4 ${BASH_SOURCE} vs set -u (internal/records/kcov-coverage.md)
        set -eu
        (set -o pipefail) 2>/dev/null && set -o pipefail || true
        _pf_oc_bin="$2"
        eval "$1"
        printf "[%s]" "${_pf_oc_ver:-}"
    ' _pb_sh "$_pb_pf" "$_pb_w/hang") || _pb_rc=$?
    if [ "$_pb_rc" -eq 0 ] && [ -z "$(printf '%s' "$_pb_out" | tr -d '[]')" ]; then
        pass "preflight probe: a hung binary never aborts the install (C1)"
    else
        fail "preflight probe: a hung binary never aborts the install (C1) (rc=$_pb_rc out=$_pb_out)"
    fi
    _pb_rc=0
    _pb_out=$(bash -c '
        PS4="+ " # kcov shield: PS4 ${BASH_SOURCE} vs set -u (internal/records/kcov-coverage.md)
        set -eu
        (set -o pipefail) 2>/dev/null && set -o pipefail || true
        SYSTEM_BIN="$2"
        eval "$1"
        printf "[%s]" "${_stamp_ver:-}"
    ' _pb_sh "$_pb_st" "$_pb_w/hang") || _pb_rc=$?
    if [ "$_pb_rc" -eq 0 ] && [ -z "$(printf '%s' "$_pb_out" | tr -d '[]')" ]; then
        pass "major-stamp probe: a hung binary never aborts the install (C2)"
    else
        fail "major-stamp probe: a hung binary never aborts the install (C2) (rc=$_pb_rc out=$_pb_out)"
    fi
else
    echo "  SKIP  C1/C2 probe pins need bash + timeout (pipefail semantics)"
fi
rm -rf "$_pb_w"

# --- ui.sh-less fallback (0.0.45c C5) --------------------------------------------
# A --yes run never prompts, so the fallback must carry EVERY output
# helper for its whole run — the old block lacked ui_have/ui_atten/
# ui_add/ui_miss and a ui.sh-less --yes install died rc 127 at the
# inventory's first ui_have, before any prompt. The local _ui_read
# fallback was dead code (only ui.sh's prompt helpers call it) and is
# gone with them.
_uifb=$(sed -n '/^    ui_info() { echo "  info     $1"; }$/,/^    UI_GREEN=/p' "$INSTALL")
if [ -n "$_uifb" ]; then
    if printf '%s\n' "$_uifb" | grep -q 'ui_have()' &&
        printf '%s\n' "$_uifb" | grep -q 'ui_atten()' &&
        printf '%s\n' "$_uifb" | grep -q 'ui_add()' &&
        printf '%s\n' "$_uifb" | grep -q 'ui_miss()'; then
        pass "ui.sh-less fallback defines the inventory helpers (C5)"
    else
        fail "ui.sh-less fallback defines the inventory helpers (C5)"
    fi
    if printf '%s\n' "$_uifb" | grep -q '_ui_read'; then
        fail "dead local _ui_read fallback removed (C5)"
    else
        pass "dead local _ui_read fallback removed (C5)"
    fi
    # Process-log label alignment (maintainer PR review 2026-10-08): ui.sh's
    # _ui_label prints a 7-char label field + 2 separator spaces, so the
    # message starts at column 11 — the echo stubs must match that exactly,
    # or a degraded (ui.sh-less) run misaligns its lines against the ui.sh
    # path. Verbatim pin: c80da5d slipped a stray space into ui_error's
    # label (unlisted in its message, unseen by reviews b–f).
    if printf '%s\n' "$_uifb" | grep -qF 'ui_info() { echo "  info     $1"; }' &&
        printf '%s\n' "$_uifb" | grep -qF 'ui_success() { echo "  success  $1"; }' &&
        printf '%s\n' "$_uifb" | grep -qF 'ui_warn() { echo "  warn     $1"; }' &&
        printf '%s\n' "$_uifb" | grep -qF 'ui_error() { echo "  error    $1" >&2; }'; then
        pass "fallback process-log labels match ui.sh's column-11 alignment (PR review)"
    else
        fail "fallback process-log labels match ui.sh's column-11 alignment (PR review)"
    fi
else
    fail "ui.sh-less fallback block extractable (C5)"
fi

# --- root-shell guard (issue #192) ---------------------------------------------
# A root login (wsl -u root, su -) has no SUDO_USER: whoami wins and the
# developer used to resolve to root — the whole install provisioned for
# root (rc hooks into /root, sharing group for root) while the real
# developer got nothing, and the resulting "ddev() hook not hooked"
# warning survived every opk update (update skipped the /home/root
# phantom silently). _root_user_gate aborts before the first prompt; it
# must fire on the NAME root and on ANY uid-0 developer, independently.
_rug_fn="$(extract_func "$INSTALL" _root_user_gate)"
if [ -n "$_rug_fn" ]; then
    pass "_root_user_gate extractable from install.sh"
    eval "$_rug_fn"
    # _rug_run <name> <stubbed-uid> — id/getent stubs keep the arms
    # deterministic on every host (which users exist locally must not
    # decide the pin, the 0.0.46a F2 class). Output merged the way a
    # user sees it (stderr + stdout).
    _rug_run() {
        (
            RUG_UID="$2"
            export RUG_UID
            id() { [ "${1:-}" = "-u" ] && printf '%s\n' "$RUG_UID"; }
            ui_error() { echo "error: $*"; }
            ui_detail() { echo "detail: $*"; }
            log() { :; }
            _root_user_gate "$1"
        ) 2>&1
    }
    _rc=0
    _out=$(_rug_run root 0) || _rc=$?
    if [ "$_rc" -eq 1 ] && printf '%s' "$_out" | grep -q 'normal user account' &&
        printf '%s' "$_out" | grep -q 'issues/192'; then
        pass "root gate: DEFAULT_USER=root aborts with the guidance (issue link)"
    else
        fail "root gate: DEFAULT_USER=root aborts with the guidance (rc=$_rc out=$_out)"
    fi
    _rc=0
    _out=$(_rug_run root 1000) || _rc=$?
    [ "$_rc" -eq 1 ] &&
        pass "root gate: the name 'root' aborts even with a bogus uid" ||
        fail "root gate: the name 'root' aborts even with a bogus uid (rc=$_rc out=$_out)"
    _rc=0
    _out=$(_rug_run rug-toor 0) || _rc=$?
    [ "$_rc" -eq 1 ] &&
        pass "root gate: any uid-0 developer aborts (name arm independent)" ||
        fail "root gate: any uid-0 developer aborts (rc=$_rc out=$_out)"
    _rc=0
    _out=$(_rug_run rug-dev 1000) || _rc=$?
    if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
        pass "root gate: a regular developer passes silently"
    else
        fail "root gate: a regular developer passes silently (rc=$_rc out=$_out)"
    fi
else
    fail "_root_user_gate extractable from install.sh"
fi
# Wiring + order (0.0.45a C1 discipline) moved to
# tests/unit/test-install-core.sh with the phase bodies (#346 wave 3):
# the call lines and the charset/distro cluster sit in do_plan_phase.

# --- bootstrap installer channel (issue #197): the optional fallback
# install (opencode missing) streams the official V2 installer — fresh
# machines get the current 2.x through the npm registry. The v1 URL
# must not come back (it resolves GitHub 1.x); the v2 installer keeps
# the ~/.opencode/bin layout, so the pickup paths are version-agnostic.
# The channel section lives in do_deploy_phase (install-core.sh since
# #346 wave 3) — the count reads the lib, the v1 absence covers BOTH
# files (a re-added URL in either host would resolve 1.x).
# Comment lines stripped before the count (#244 g W1 class sweep, the
# _p3old rider): a commented-out URL must not count as a surviving
# call site — the two-step false-green the f-W4 sweep left bounded.
# Full-line comments only (#244 h W6): a trailing comment after a
# live line would still count — the same residual _p3old carries.
_v2hits=$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" | grep -c 'https://opencode.ai/v2/install' || true)
if [ "$_v2hits" -ge 2 ]; then
    pass "bootstrap streams the v2 installer (prompt + curl, $_v2hits sites)"
else
    fail "bootstrap v2 installer URL missing (expected prompt + curl, found $_v2hits)"
fi
if grep -qF 'https://opencode.ai/install' "$INSTALL" ||
    grep -qF 'https://opencode.ai/install' "$INSTALL_CORE"; then
    fail "bootstrap still references the v1 installer URL (resolves 1.x)"
else
    pass "no v1 installer URL left in install.sh or install-core.sh"
fi

# --- python3 health gate (#244 a W1/S1, b Q1/Q2/S2) ------------------------------------
# Presence-only was the findable-but-broken hole (a pyenv shim installs
# green, every later consumer fails attributelessly): the gate must RUN
# the interpreter — isolated (-I), so PYTHONHOME/PYTHONPATH poison can
# neither break nor shadow it. Functional matrix on the extracted
# function + verbatim call wiring pin (the _distro_gate pattern,
# 0.0.45a C1). Fix-wave-2 additions: the noisy-broken case (the gate
# must surface the interpreter's own diagnostic, #244 b S2) and the
# import-union drift pin (#244 b Q1).
if [ -n "$(extract_func "$INSTALL" _py3_health_probe)" ]; then
    eval "$(extract_func "$INSTALL" _py3_health_probe)"
    pass "_py3_health_probe defined in install.sh"
    _py3w="$(mktemp -d)"
    mkdir -p "$_py3w/empty" "$_py3w/shim" "$_py3w/noisy"
    printf '#!/bin/sh\nexit 9\n' >"$_py3w/shim/python3"
    chmod +x "$_py3w/shim/python3"
    # A broken interpreter that NAMES its problem on stderr (#244 b
    # S2): the moved-/usr/local/python shape — works only via env,
    # prints its real diagnostic and fails. Marker wording is CPython's
    # real unhyphenated message (#244 c S1): the pin asserts the
    # passthrough mechanism, not the text. The literal lives in a
    # variable — consuming grep lines quoting it inline chain into
    # the sandbox scanner's raw-line rm-suffix pattern (the wave-2
    # mechanism, real for grep lines; the definition line is clean).
    _p3diag='platform independent libraries'
    printf '#!/bin/sh\necho "%s" >&2\nexit 9\n' "$_p3diag" >"$_py3w/noisy/python3"
    chmod +x "$_py3w/noisy/python3"
    mkdir -p "$_py3w/shadow"
    # json.py (NOT os.py): os is preloaded in sys.modules at -c startup,
    # an os.py shadow never loads and the pin would be vacuous — caught
    # by sabotage during the fix wave; json is imported by the probe and
    # a shadow FIRES without -I.
    printf 'import sys\nsys.exit(9)\n' >"$_py3w/shadow/json.py"
    # _py3case <PATH> <PYTHONPATH-or-empty> — runs the extracted
    # gate in a subshell (its exit must not kill the suite), ui_error
    # stubbed onto stderr: observe the message the way a real
    # terminal does, not via a 2>&1 that production never runs.
    # (No dead desc parameter — #244 b Q2: the pass/fail messages
    # name their case themselves.)
    _py3case() {
        _p3p="$1" _p3e="$2"
        rm -f "${_py3w:?}/err"
        (
            PATH="$_p3p"
            [ -n "$_p3e" ] && export PYTHONPATH="$_p3e" || unset PYTHONPATH
            ui_error() { printf '%s\n' "$1" >&2; }
            _py3_health_probe
        ) 2>"$_py3w/err"
        return $?
    }
    _p3rc=0
    _py3case "$PATH" "" || _p3rc=$?
    if [ "$_p3rc" -eq 0 ] && [ ! -s "$_py3w/err" ]; then
        pass "gate: healthy python3 passes silently"
    else
        fail "gate: healthy python3 passes silently (rc=$_p3rc)"
    fi
    _p3rc=0
    _py3case "$_py3w/empty" "" || _p3rc=$?
    if [ "$_p3rc" -eq 1 ] && grep -qF 'not installed' "$_py3w/err"; then
        pass "gate: absent python3 aborts loud, names the class"
    else
        fail "gate: absent python3 aborts loud (rc=$_p3rc err=$(cat "$_py3w/err"))"
    fi
    _p3rc=0
    _py3case "$_py3w/shim" "" || _p3rc=$?
    if [ "$_p3rc" -eq 1 ] && grep -qF 'present but broken' "$_py3w/err"; then
        pass "gate: broken shim aborts loud, names the OTHER class (#244 a W1)"
    else
        fail "gate: broken shim aborts loud (rc=$_p3rc err=$(cat "$_py3w/err"))"
    fi
    _p3rc=0
    _py3case "$PATH" "$_py3w/shadow" || _p3rc=$?
    if [ "$_p3rc" -eq 0 ]; then
        pass "gate: hostile PYTHONPATH ignored (-I isolation, #244 a S1)"
    else
        fail "gate: hostile PYTHONPATH ignored (rc=$_p3rc err=$(cat "$_py3w/err"))"
    fi
    _p3rc=0
    _py3case "$_py3w/noisy" "" || _p3rc=$?
    if [ "$_p3rc" -eq 1 ] && grep -qF "$_p3diag" "$_py3w/err" &&
        grep -qF 'present but broken' "$_py3w/err"; then
        pass "gate: failed probe surfaces the interpreter's diagnostic (#244 b S2)"
    else
        fail "gate: diagnostic passthrough (rc=$_p3rc err=$(cat "$_py3w/err"))"
    fi
    rm -rf "$_py3w"
    # Wiring pin: the matrix proves the function works — the verbatim
    # call line proves the pre-flight runs it (a dropped call leaves
    # every matrix pin green; the call site lives in install-core.sh's
    # do_plan_phase since #346 wave 3). The presence-check count pins
    # that the old inline gate is GONE from the entry's main flow:
    # exactly one occurrence survives, the one inside the function
    # itself (which stays in install.sh).
    if grep -qF '    _py3_health_probe' "$INSTALL_CORE"; then
        pass "pre-flight wires the health gate (verbatim call pin)"
    else
        fail "pre-flight wires the health gate (verbatim call pin)"
    fi
    _p3old=0
    # Comment lines are stripped before the count (#244 f W4 sibling
    # sweep): -F counts substrings anywhere, so a commented-out gate
    # would count as the surviving gate — the exact commented-sabotage
    # pass-green trap.
    _p3old=$(sed 's/^[[:space:]]*#.*$//' "$INSTALL" |
        grep -cF 'if ! command -v python3 >/dev/null 2>&1; then') || true
    if [ "$_p3old" -eq 1 ]; then
        pass "old presence-only gate replaced (check survives only inside the function)"
    else
        fail "old presence-only gate replaced (found $_p3old occurrences, want 1)"
    fi
    # Import-union drift pin (#244 b Q1; c Q1/W2/W1): every module any
    # shipped python imports must appear in the gate's import list —
    # a new consumer adding an import without extending the gate goes
    # red here (sabotage-verified: dropping threading or pathlib from
    # the gate list fails this pin naming the module). Extraction
    # (#244 c W2): EVERY regular file under the lib root (find,
    # recursive — tui/, templates/ and future subdirs included; four
    # fixed globs made the resolution's "anywhere in the lib" claim
    # false). Shapes collected: line-start imports in .py files and
    # python blocks embedded in sh/bin scripts (comment lines
    # stripped), plus inline `-c 'import ...'` probes including
    # semicolon chains (#244 c W1 — `import x; x.run()` splits on ';'
    # like ','). Known residual, deliberately not extracted (#244 c
    # S4): double-quoted -c strings, mid-line imports,
    # importlib/__import__ dynamic loads, `as` aliases. A
    # `from X import y` line must carry the second `import` keyword —
    # a bare "from the ..." prose line is not a module dependency
    # (the opk hosts-file continuation).
    _p3gate="$(sed -n "s/^[[:space:]]*_py3_imports='\([^']*\)'.*$/\1/p" "$INSTALL")"
    if [ -n "$_p3gate" ]; then
        pass "gate: import list extractable"
    else
        fail "gate: import list extractable (no _py3_imports assignment found)"
    fi
    # Executed-value drift pin (#244 c W3, d W2, e W2, f W1/W3/W4,
    # g W1 — the count/dup regex pair is RETIRED): the invariant is
    # now checked semantically, not by enumerating accident shapes
    # in regex. The runtime gate executes the LAST value of
    # _py3_imports; the extraction above UNIONS every single-quoted
    # list (#244 h W3/Q1 — this said "FIRST", false: the sed /p
    # prints every match; any second assignment makes the union
    # diverge from the executed LAST value and reds — the coverage
    # pin audits the union's modules, the one list when sole).
    # This pin executes every assignment-shaped line (token at line
    # start, full-line comments stripped first, in file order) under
    # install.sh's own interpreter — its SHEBANG; sh today, while
    # the production pipe runs bash: a divergence that can only
    # fail LOUDER (bash-isms error under dash and red), #244 h S4 —
    # and requires: executed final value == extracted list. The
    # COVERED accident shapes red by construction — separate-line
    # seconds, appends, same-line doubles, quoted-# doubles (g W1:
    # invisible to the old dup regex, visible to the executed
    # value), first-token-`+=` doubles (interpreter failure under
    # sh — dash has no +=), and a deleted or commented-out sole
    # assignment (empty extraction); exceptions and residuals are
    # named at the residual comment below (#244 h S1/Q3/W5).
    # Assignment-prefixed shapes count too (#244 g W1 self-check):
    # `export`/`readonly`/`local` before the token are collected —
    # an `export _py3_imports=…` second line changes the executed
    # value and reds (probe-verified; the old regex pair missed it).
    # A trailing backslash on an assignment line is DETECTED loudly
    # (the e-W4 concealment residual #1 closed as a detector); the
    # line-start filter keeps execution lines off the use sites at
    # :578/:583 (python3 -c "$_py3_imports"). Every grep here is
    # empty-match-guarded (L7, #244 f W1).
    _p3she="$(sed -n '1{s/^#!//p;q;}' "$INSTALL")"
    case "$_p3she" in
        *bash*) _p3bin=bash ;;
        *) _p3bin=sh ;;
    esac
    _p3lines="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL" |
        grep -E '^[[:space:]]*(export[[:space:]]+|readonly[[:space:]]+|local[[:space:]]+)?_py3_imports[^_[:alnum:]]' || true)"
    _p3n="$(printf '%s\n' "$_p3lines" |
        grep -cE '^[[:space:]]*(export[[:space:]]+|readonly[[:space:]]+|local[[:space:]]+)?_py3_imports[^_[:alnum:]]' || true)"
    _p3cont="$(printf '%s\n' "$_p3lines" | grep -n '\\$' || true)"
    if [ -z "$_p3lines" ] || [ -n "$_p3cont" ]; then
        fail "gate: _py3_imports assignment present, no continuation (lines=$_p3n cont=[$_p3cont])"
    else
        _p3tmp="$(mktemp)"
        {
            echo 'set -e'
            printf '%s\n' "$_p3lines"
            echo 'printf "%s" "$_py3_imports"'
        } >"$_p3tmp"
        _p3rc=0
        _p3rt="$("$_p3bin" "$_p3tmp" 2>&1)" || _p3rc=$?
        rm -f "$_p3tmp"
        if [ "$_p3rc" -eq 0 ] && [ -n "$_p3gate" ] &&
            [ "$_p3rt" = "$_p3gate" ]; then
            pass "gate: executed _py3_imports equals the extracted list (#244 c W3, #244 g W1)"
        else
            fail "gate: executed _py3_imports equals the extracted list (rc=$_p3rc lines=$_p3n executed=[{$_p3rt}] extracted=[{$_p3gate}])"
        fi
    fi
    # Residual, deliberately not caught (#244 e W4): eval-built or
    # command-substitution assignments (`_py3_imports="$(…)"`) —
    # deliberate concealment shapes outside the maintenance-accident
    # threat model; most such shapes red above anyway (the executed
    # subshell value differs from the extracted literal list). Same
    # class: a second assignment hidden behind a `;` on a USE line
    # (`python3 -c "$_py3_imports"; _py3_imports=…`) — line-start
    # collection cannot see it; concealment, not accident.
    # Accident-class residuals, named not detected (#244 h S1/Q3):
    # a backslash ending the line ABOVE an assignment steals it
    # into a continuation — collected standalone, the pin
    # GREEN-PASSES it while production fails loud at the use site
    # (set -u: parameter not set; probe: snapshot h) — the loud
    # failure bounds it. And the prefix alternation is
    # export/readonly/local only: a declare/typeset second line is
    # invisible to the pin (under the current #!/bin/sh it errors
    # loudly at runtime — a real miss only if the shebang becomes
    # bash). Boundary note (#244 h W5): the token class
    # `[^_[:alnum:]]` also collects suffixed names
    # (`_py3_imports-foo=x`) — nothing like that ships and the
    # failure is a loud false-red.
    _p3g="$(mktemp)"
    printf '%s\n' "$_p3gate" | sed 's/^[[:space:]]*import[[:space:]]*//' |
        tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' |
        grep -E '^[A-Za-z_][A-Za-z0-9_.]*$' | sort -u >"$_p3g"
    # Collector and splitter as functions so the fixture self-test
    # below runs the SAME code path as the lib scan (#244 c W1 pin).
    _p3collect() {
        # _p3collect <root> <rawfile>: line-start imports (comment
        # lines stripped) + inline single-quoted -c 'import' probes
        # from every regular file under <root>, recursive.
        find "$1" -type f 2>/dev/null | while IFS= read -r _p3cf; do
            # The two greps find nothing in most files — rc 1 is the
            # normal case there (guarded empty-match greps); a wholly
            # empty collection is caught by the non-empty check below.
            sed 's/^[[:space:]]*#.*$//' "$_p3cf" 2>/dev/null |
                grep -oE "^[[:space:]]*(import|from)[[:space:]]+[^[:space:]#][^#]*" \
                    >>"$2" || true
            grep -oE -- "-c[[:space:]]+'import[^']*" "$_p3cf" 2>/dev/null |
                sed "s/.*'//" >>"$2" || true
        done
    }
    _p3split() {
        # _p3split <rawfile> <modfile>: raw lines -> module names. tr
        # splits comma AND semicolon chains (#244 c W1); the second
        # import-prefix strip catches `import a; import b` shapes the
        # split re-exposes.
        {
            sed -n 's/^[[:space:]]*import[[:space:]]*//p' "$1" | tr ',;' '\n\n'
            sed -n 's/^[[:space:]]*from[[:space:]]*\([A-Za-z_][A-Za-z0-9_.]*\)[[:space:]]\{1,\}import.*/\1/p' "$1"
        } | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^[[:space:]]*import[[:space:]]\{1,\}//' |
            grep -E '^[A-Za-z_][A-Za-z0-9_.]*$' | sort -u >"$2"
    }
    _p3raw="$(mktemp)"
    _p3collect "$(dirname "$INSTALL")/opencode-permissions-kit-lib" "$_p3raw"
    _p3mods="$(mktemp)"
    _p3split "$_p3raw" "$_p3mods"
    if [ -s "$_p3mods" ] && [ -s "$_p3g" ]; then
        pass "gate: shipped import surface collected"
    else
        fail "gate: shipped import surface collected (empty extraction — fixture broken)"
    fi
    # Fixture self-test of the extraction shapes (#244 c W1): the same
    # collector/splitter over a fixture dir must yield exactly the
    # planted modules — line-start comma import, from-import, inline
    # -c semicolon one-liner — and nothing from the prose from-line.
    # Red here means the EXTRACTION broke, not the shipped surface.
    _p3fx="$(mktemp -d)"
    printf 'import zmod_a, zmod_b\nfrom zmod_c import thing\nfrom the fixture prose line\n' >"$_p3fx/consumer.py"
    printf '#!/bin/sh\npython3 -c '"'"'import zmod_d; zmod_d.run()'"'"'\n' >"$_p3fx/consumer.sh"
    chmod +x "$_p3fx/consumer.sh"
    _p3fraw="$(mktemp)"
    _p3fmods="$(mktemp)"
    _p3fwant="$(mktemp)"
    _p3collect "$_p3fx" "$_p3fraw"
    _p3split "$_p3fraw" "$_p3fmods"
    printf 'zmod_a\nzmod_b\nzmod_c\nzmod_d\n' | sort -u >"$_p3fwant"
    if cmp -s "$_p3fmods" "$_p3fwant"; then
        pass "gate: extraction collects semicolon -c chains + from-imports (#244 c W1)"
    else
        fail "gate: extraction shape self-test (got: $(tr '\n' ' ' <"$_p3fmods"))"
    fi
    _p3miss="$(comm -23 "$_p3mods" "$_p3g")"
    if [ -z "$_p3miss" ]; then
        pass "gate: import list covers the shipped python surface (#244 b Q1, c W2: whole lib)"
    else
        fail "gate: import list covers the shipped python surface — missing: $(printf '%s' "$_p3miss" | tr '\n' ' ')"
    fi
    rm -rf "$_p3fx"
    rm -f "$_p3raw" "$_p3mods" "$_p3g" "$_p3fraw" "$_p3fmods" "$_p3fwant"
else
    fail "_py3_health_probe defined in install.sh"
fi

# --- pr-00263 a F6/F8/F19 + d W1/W2/W3: fail-loud backups + wrapper ---------------
# F6: backup copies record failures loudly (_bk_fail) and degrade the
# closing Backup summary row; F8: both getfacl backup sites observe the
# copy before announcing recovery material; F19: the official-installer
# pipe carries its failure (pipefail) into a kit error wrapper.
# pr-00263 d W1/W2: the three sites the a-wave sweep missed (binary-menu
# branch b, existing-config replace, re-render twin) observe their copy
# too. The recorder itself is DRIVEN below (extract-eval, both arms);
# the site wirings are anchored statically (exact call count + announce
# anchors); e2e drives install success paths, not failure arms.
# pr-00263 e W2: drive a production-shaped label — the real call site
# (do_plan_phase) interpolates the invoking user (DEFAULT_USER from
# SUDO_USER/whoami), never an empty string. The recorder definition and
# every wiring site live in install-core.sh since #346 wave 3; the
# closing summary row (INCOMPLETE) stays in the entry's tail — each leg
# greps the file that owns the literal.
DEFAULT_USER=opencode
_BKDEF="$(sed -n '/^    _BK_FAIL=""$/,/^    }$/p' "$INSTALL_CORE")"
if [ -n "$_BKDEF" ] && (
    eval "$_BKDEF"
    _bk_fail "gitconfig-$DEFAULT_USER"
    _bk_fail "sudoers"
    [ "$_BK_FAIL" = "gitconfig-$DEFAULT_USER, sudoers" ]
) 2>/dev/null; then
    pass "recorder accumulates failed labels (extract-eval, driven REAL) (pr-00263 a F6 + d W3)"
else
    fail "recorder broken — accumulation shape changed (pr-00263 a F6 + d W3)"
fi
# Comment-strip riders (#261, the #244 g W1 class — sweep finds beyond
# the issue list): commented-out failure-recorder sites stop counting;
# full-line comments only (#244 h W6 residual).
_bk_n="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" | grep -c '_bk_fail' || true)"
[ "$_bk_n" = 10 ] &&
    grep -qF 'INCOMPLETE: $_BK_FAIL' "$INSTALL" &&
    pass "backup failures record loudly + degrade the summary row (pr-00263 a F6 + d W1/W2)" ||
    fail "backup failure silence survived somewhere (pr-00263 a F6 + d W1/W2; _bk_fail sites: $_bk_n of 10)"
_cba_n="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" |
    grep -cF 'config backup FAILED — see Backup summary' || true)"
[ "$_cba_n" = 2 ] &&
    grep -qF 'binary backup FAILED — see Backup summary' "$INSTALL_CORE" &&
    pass "the three swept backup sites degrade their announce on failure (pr-00263 d W1/W2)" ||
    fail "a backup announce still lies on failure (pr-00263 d W1/W2; config-announce sites: $_cba_n of 2)"
_acl_n="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" | grep -cF 'no ACL recovery material' || true)"
[ "$_acl_n" = 2 ] &&
    pass "both getfacl backups announce failure instead of success (pr-00263 a F8)" ||
    fail "a getfacl success line still lies (pr-00263 a F8; no-ACL sites: $_acl_n of 2)"
grep -qF 'the official opencode installer failed' "$INSTALL_CORE" &&
    pass "official-installer pipe has the kit error wrapper (pr-00263 a F19)" ||
    fail "official-installer failure still bare (pr-00263 a F19)"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All install.sh arg-parsing tests passed.${NC}"
exit 0
