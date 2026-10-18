#!/bin/sh
# Unit tests for update.sh's binary-upgrade flow + --only-binary (issue #24):
#   - latest-fetch composition (resolve_latest_opencode_version +
#     fetch_opencode_version): functional test with a fake curl on PATH —
#     the extracted candidate must SURVIVE until the caller installs it
#     (the old flow `rm -rf $TMP`'d it before verification, so every
#     downloaded upgrade failed with "candidate failed verification")
#   - TMP cleanup happens AFTER the install attempt (static order check)
#   - --only-binary: parsing, gating, confirm text, summary, docs
# No root required.
# Run: sh tests/unit/test-update-flags.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
KIT="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opk"
TUIPLUGIN="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/tui-plugin.sh"
CLI_MD="$SCRIPT_DIR/../../docs/reference/cli.md"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }
check() {
    _d="$1"; shift
    if "$@"; then pass "$_d"; else fail "$_d"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# --- 0.0.45d W4: update.sh's ui.sh-less fallback covers its one prompt ----------
# The body's confirm() calls ui_confirm; the old fallback defined only
# output helpers, so a ui.sh-less run (damaged checkout + predating
# library) died rc 127 at the confirm instead of failing with the
# re-deploy hint — the exact class 0.0.45c C9 fixed in config.sh (the
# C9 sweep missed this fallback). The fallback must fail loudly.
_updfb="$(sed -n '/^    ui_info()    { echo "  info     $1"; }$/,/^    UI_GREEN=/p' "$UPDATE")"
if [ -n "$_updfb" ]; then
    if printf '%s\n' "$_updfb" | grep -q '_ui_no_prompt()' \
       && printf '%s\n' "$_updfb" | grep -q 'ui_confirm()'; then
        pass "update.sh ui.sh fallback fails loudly at its one prompt (W4)"
    else
        fail "update.sh ui.sh fallback must define the ui_confirm loud-fail stub (W4)"
    fi
else
    fail "update.sh ui.sh fallback block extractable (W4)"
fi

# --- 1. flag parsing (static extraction, same pattern as test-install-args) ------
extract_fn() {
    sed -n "/^$1() {/,/^}/p" "$UPDATE"
}

if [ -n "$(extract_fn resolve_latest_opencode_version)" ]; then
    pass "resolve_latest_opencode_version defined in update.sh"
else
    fail "resolve_latest_opencode_version defined in update.sh"
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi

# --- 2. functional: major-aware resolution + candidate survives (issue #99) ------
# Fake curl on PATH: registry.npmjs.org answers the dist-tags doc (no -o)
# or "downloads" an npm-layout tarball (-o); api.github.com answers the
# releases/latest tag (no -o) or a GitHub-layout tarball (-o).
mkdir -p "$WORK/bin" "$WORK/fixture" "$WORK/fixture-npm/package/bin"
printf '#!/bin/sh\necho "opencode version 9.9.9"\n' > "$WORK/fixture/opencode"
chmod +x "$WORK/fixture/opencode"
tar -czf "$WORK/fixture/release.tar.gz" -C "$WORK/fixture" opencode
printf '#!/bin/sh\necho "opencode v2.1.99"\n' > "$WORK/fixture-npm/package/bin/opencode"
chmod +x "$WORK/fixture-npm/package/bin/opencode"
tar -czf "$WORK/fixture/release-npm.tgz" -C "$WORK/fixture-npm" package
cat > "$WORK/bin/curl" <<FAKE
#!/bin/sh
_args="\$*"
case " \$_args " in
    *" -o "*)
        _out=""
        while [ \$# -gt 0 ]; do
            [ "\$1" = "-o" ] && _out="\$2" && break
            shift
        done
        if printf '%s' "\$_args" | grep -q 'registry.npmjs.org'; then
            cp "$WORK/fixture/release-npm.tgz" "\$_out"
        else
            cp "$WORK/fixture/release.tar.gz" "\$_out"
        fi
        ;;
    *registry.npmjs.org*)
        printf '{"_id":"cli","dist-tags":{"latest":"2.1.99","next":"2.2.0-beta.1"},"versions":{}}\n'
        ;;
    *api.github.com*)
        printf '{"tag_name":"v1.18.99"}\n'
        ;;
    *)
        printf '{"tag_name":"v1.18.99"}\n'
        ;;
esac
FAKE
chmod +x "$WORK/bin/curl"

# Extract every version-resolution function into one sourceable file.
FUNCS="$WORK/funcs.sh"
{
    sed -n '/^detect_target() {/,/^}/p' "$UPDATE"
    sed -n '/^version_major() {/,/^}/p' "$UPDATE"
    sed -n '/^opencode_version_line() {/,/^}/p' "$UPDATE"
    sed -n '/^current_opencode_major() {/,/^}/p' "$UPDATE"
    sed -n '/^resolve_latest_opencode_version() {/,/^}/p' "$UPDATE"
    sed -n '/^fetch_opencode_version() {/,/^}/p' "$UPDATE"
} > "$FUNCS"

# Stubs for current_opencode_major (2.x and 1.x --version shapes).
printf '#!/bin/sh\necho "opencode v2.0.11"\n' > "$WORK/stub-v2"; chmod +x "$WORK/stub-v2"
printf '#!/bin/sh\necho "1.18.31"\n'        > "$WORK/stub-v1"; chmod +x "$WORK/stub-v1"
mkdir -p "$WORK/conf"

# 2a. major detection from the binary's --version shape
run_resolver() {
    # run_resolver <curl-bin-dir> <stub> <expr>
    env PATH="$1:$PATH" SYSTEM_BIN="$2" CONFDIR="$WORK/conf" \
        sh -c ". '$FUNCS' && $3" 2>/dev/null
}
_re=$(run_resolver "$WORK/bin" "$WORK/stub-v2" 'current_opencode_major')
[ "$_re" = "2" ] && pass "resolve: 2.x --version line maps to major 2" || fail "resolve: 2.x --version line maps to major 2 (got: '$_re')"
_re=$(run_resolver "$WORK/bin" "$WORK/stub-v1" 'current_opencode_major')
[ "$_re" = "1" ] && pass "resolve: bare 1.x --version line maps to major 1" || fail "resolve: bare 1.x --version line maps to major 1 (got: '$_re')"

# The probes are BOUNDED (0.0.43b W3): a wedged 2.x service can make even
# --version hang (issue #80) — opk update, the remediation path, must
# never block on it. Every --version call site routes through the
# timeout-wrapped helper.
check "update.sh: bounded --version helper exists (timeout 10 + head -1)" \
    sh -c "grep -q 'timeout 10 \"\$SYSTEM_BIN\" --version' \"\$1\" && grep -q 'opencode_version_line() {' \"\$1\"" _ "$UPDATE"
check "update.sh: all --version probes route through the bounded helper" \
    sh -c "[ \"\$(grep -c 'opencode_version_line' \"\$1\")\" -ge 4 ]" _ "$UPDATE"
check "update.sh: post-copy failure message never names a backup that was never taken (W6)" \
    sh -c "grep -qF 'no previous binary was backed up' \"\$1\" && grep -qF '[ -f \"\$BACKUP_DIR/opencode.current\" ]' \"\$1\"" _ "$UPDATE"

# 2b. latest resolution per major (npm dist-tag vs GitHub releases/latest)
_re=$(run_resolver "$WORK/bin" "$WORK/stub-v2" 'resolve_latest_opencode_version 2')
[ "$_re" = "2.1.99" ] && pass "resolve: major 2 resolves through the npm dist-tag" || fail "resolve: major 2 resolves through the npm dist-tag (got: '$_re')"
_re=$(run_resolver "$WORK/bin" "$WORK/stub-v1" 'resolve_latest_opencode_version 1')
[ "$_re" = "1.18.99" ] && pass "resolve: major 1 resolves through GitHub releases/latest" || fail "resolve: major 1 resolves through GitHub releases/latest (got: '$_re')"

# 2c. a dist-tag outside the wanted major fails loudly (no silent crossing)
mkdir -p "$WORK/bin3"
sed 's/"latest":"2.1.99"/"latest":"3.0.0"/' "$WORK/bin/curl" > "$WORK/bin3/curl"
chmod +x "$WORK/bin3/curl"
_re=$(run_resolver "$WORK/bin3" "$WORK/stub-v2" 'resolve_latest_opencode_version 2' >/dev/null && echo resolved || echo refused)
[ "$_re" = "refused" ] && pass "resolve: dist-tag off the wanted major is refused (issue #99)" || fail "resolve: dist-tag off the wanted major is refused (got: '$_re')"

# 2d. exact-version download: npm layout (2.*) and GitHub layout (1.x)
DL="$(mktemp -d)"
OUT=$(PATH="$WORK/bin:$PATH" sh -c ". '$FUNCS' && fetch_opencode_version '$DL' '2.1.99'" 2>/dev/null || true)
check "fetch: 2.* downloads through npm (package/bin/opencode)" [ "$OUT" = "$DL/opencode" ]
check "fetch: 2.* candidate runs and reports the 2.x version" \
    sh -c "\"\$1\" --version 2>/dev/null | grep -q '^opencode v2\.1\.99\$'" _ "$DL/opencode"
rm -rf "$DL"; DL="$(mktemp -d)"
OUT=$(PATH="$WORK/bin:$PATH" sh -c ". '$FUNCS' && fetch_opencode_version '$DL' '1.18.99'" 2>/dev/null || true)
check "fetch: 1.x downloads through GitHub (tarball-root opencode)" [ "$OUT" = "$DL/opencode" ]
check "fetch: 1.x candidate runs (--version works for install_binary)" \
    sh -c "\"\$1\" --version >/dev/null 2>&1" _ "$DL/opencode"
rm -rf "$DL"

# 2e. latest-fetch composition (formerly fetch_latest_opencode, C20): the
# default stays on the CURRENT major (no 2.x -> 1.x downgrade); explicit
# major picks the channel. Composed from the two shipped functions exactly
# like the upgrade-opencode flow does.
DL="$(mktemp -d)"
OUT=$(PATH="$WORK/bin:$PATH" SYSTEM_BIN="$WORK/stub-v2" CONFDIR="$WORK/conf" \
    sh -c ". '$FUNCS' && _fl_ver=\$(resolve_latest_opencode_version \"\$(current_opencode_major)\") && fetch_opencode_version '$DL' \"\$_fl_ver\"" 2>/dev/null || true)
check "fetch: current major 2 -> npm candidate (issue #99: no downgrade)" \
    sh -c "[ \"\$1\" = \"\$2/opencode\" ] && \"\$1\" --version 2>/dev/null | grep -q '^opencode v2'" _ "$OUT" "$DL"
rm -rf "$DL"; DL="$(mktemp -d)"
OUT=$(PATH="$WORK/bin:$PATH" SYSTEM_BIN="$WORK/stub-v1" CONFDIR="$WORK/conf" \
    sh -c ". '$FUNCS' && _fl_ver=\$(resolve_latest_opencode_version \"\$(current_opencode_major)\") && fetch_opencode_version '$DL' \"\$_fl_ver\"" 2>/dev/null || true)
check "fetch: current major 1 -> GitHub candidate" \
    sh -c "[ \"\$1\" = \"\$2/opencode\" ] && \"\$1\" --version >/dev/null 2>&1" _ "$OUT" "$DL"
rm -rf "$DL"

# --- 3. TMP cleanup order: never before the install attempt ----------------------
IB_LINE=$(grep -n 'install_binary "\$SRC"' "$UPDATE" | head -1 | cut -d: -f1)
LAST_TMP_RM=$(grep -n 'rm -rf "\$TMP"' "$UPDATE" | tail -1 | cut -d: -f1)
check "cleanup: candidate dir removed only AFTER the install attempt (issue #24)" \
    sh -c "[ -n \"\$1\" ] && [ -n \"\$2\" ] && [ \"\$2\" -gt \"\$1\" ]" _ "$IB_LINE" "$LAST_TMP_RM"

# --- 3a. atomic binary replacement (issue #163) ---------------------------------
# update.sh:940's plain in-place `sudo cp` was the recorded reachability
# for a corrupt managed binary: a copy killed mid-write left a truncated
# binary with intact mode bits, and opk status reported "All green" over
# it. Every binary-writing site in update.sh must go through the shared
# copy_binary_atomic helper (sh/secure-binary.sh — behavioral pins in
# test-secure-binary.sh): the deploy, the pre-upgrade backup (a
# half-written backup is a poisoned restore source) and the fallback
# restore.
check "#163: install_binary deploys through the atomic helper" \
    sh -c "grep -qF 'copy_binary_atomic \"\$src\" \"\$SYSTEM_BIN\" || return 1' \"\$1\"" _ "$UPDATE"
check "#163: the pre-upgrade backup copy is atomic" \
    sh -c "grep -qF 'copy_binary_atomic \"\$SYSTEM_BIN\" \"\$BACKUP_DIR/opencode.current\"' \"\$1\"" _ "$UPDATE"
check "#163: the fallback restore is atomic" \
    sh -c "grep -qF 'copy_binary_atomic \"\$BACKUP_DIR/opencode.current\" \"\$SYSTEM_BIN\"' \"\$1\"" _ "$UPDATE"
check "#163: no direct sudo-cp onto/from SYSTEM_BIN remains" \
    sh -c "! grep -qF 'sudo cp \"\$src\" \"\$SYSTEM_BIN\"' \"\$1\" \
        && ! grep -qF 'sudo cp \"\$SYSTEM_BIN\" \"\$BACKUP_DIR/opencode.current\"' \"\$1\" \
        && ! grep -qF 'sudo cp \"\$BACKUP_DIR/opencode.current\" \"\$SYSTEM_BIN\"' \"\$1\"" _ "$UPDATE"
check "#163: the missing-lib fallback fails loud for the helper too" \
    sh -c "grep -qF 'copy_binary_atomic() { echo \"error: copy_binary_atomic unavailable' \"\$1\"" _ "$UPDATE"
check "#163: the manual-restore advice teaches the atomic shape" \
    sh -c "grep -qF 'sudo mv \${SYSTEM_BIN}.tmp \$SYSTEM_BIN' \"\$1\"" _ "$UPDATE"

# --- 4. --only-binary (issue #24 feature) -----------------------------------------
check "flag: --only-binary parsed, implies BINARY_UPDATE" \
    sh -c "grep -q -- '--only-binary)' \"\$1\" && grep -A4 -- '--only-binary)' \"\$1\" | grep -q 'BINARY_UPDATE=true'" _ "$UPDATE"
check "flag: help text documents --only-binary" \
    sh -c "grep -q -- '--only-binary    skip every kit step' \"\$1\"" _ "$UPDATE"
check "gating: kit re-deploy sections are wrapped (2 skip zones)" \
    sh -c "[ \"\$(grep -c 'if \[ \"\$ONLY_BINARY\" != true \]; then' \"\$1\")\" -ge 2 ]" _ "$UPDATE"
check "no kit self-fetch in binary-only mode (library runs stay offline for kit files)" \
    sh -c "grep -qF 'for _opk_a in \"\$@\"' \"\$1\" && grep -qF '[ \"\$_opk_binonly\" != true ] && [ ! -f \"\$SCRIPT_DIR/../../../VERSION\" ]' \"\$1\"" _ "$UPDATE"
check "--binary-path alone does NOT skip the self-fetch (full update + binary swap, review 0.0.29)" \
    sh -c "grep -qF -- '--only-binary) _opk_binonly=true; break ;;' \"\$1\"" _ "$UPDATE"
check "library runs fall back to the installed version stamp" \
    sh -c "grep -q 's/^VERSION=//p' \"\$1\"" _ "$UPDATE"
check "gating: confirm prompt reflects binary-only mode" \
    sh -c "grep -q 'Only upgrade the opencode binary' \"\$1\"" _ "$UPDATE"
check "summary: binary-only mode reports Mode instead of Kit/Configs" \
    sh -c "grep -q 'binary-only (kit files untouched)' \"\$1\"" _ "$UPDATE"
check "kit CLI usage documents --only-binary" \
    sh -c "grep -q -- '--only-binary' \"\$1\"" _ "$KIT"
check "kit CLI has the upgrade-opencode shorthand (injects --yes --only-binary)" \
    sh -c "grep -q 'upgrade-opencode)' \"\$1\" && grep -q -- '--yes --only-binary' \"\$1\"" _ "$KIT"
check "docs: cli.md update flag table lists --only-binary" \
    sh -c "grep -q -- '--only-binary' \"\$1\"" _ "$CLI_MD"

# --- 5. channel resolution (issue #38: env KIT_BRANCH > KIT_CHANNEL stamp > master)
# The stamp read + fallback chain is extracted verbatim and executed with
# a fake sed on PATH (the stamp comes from install.conf via sed); the fake
# answers whatever stamp the case needs, independent of the host's /etc.
CHAN_BLOCK="$(grep -F '_kit_stamped_channel=' -A1 "$UPDATE" | head -2)
$(grep -F 'KIT_BRANCH="${KIT_BRANCH:-${_kit_stamped_channel:-master}}"' "$UPDATE" | head -1)"
if [ -n "$(printf '%s' "$CHAN_BLOCK" | grep -F '_kit_stamped_channel=')" ]; then
    pass "channel resolution block extractable from update.sh"
else
    fail "channel resolution block extractable from update.sh"
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
mkdir -p "$WORK/chanbin"
chan_case() {
    # $1 = what the fake sed answers (the stamp), $2 = KIT_BRANCH env (or "")
    printf '#!/bin/sh\n[ -n "%s" ] && echo "%s"\nexit 0\n' "$1" "$1" > "$WORK/chanbin/sed"
    chmod +x "$WORK/chanbin/sed"
    (
        PATH="$WORK/chanbin:$PATH"
        export PATH
        [ -n "$2" ] && export KIT_BRANCH="$2"
        [ -z "$2" ] && unset KIT_BRANCH
        eval "$CHAN_BLOCK"
        printf '%s' "$KIT_BRANCH"
    )
}
out=$(chan_case "stable" "")
[ "$out" = "stable" ] && pass "channel: stamp wins when no env is set" \
    || fail "channel: stamp wins when no env is set (out=$out)"
out=$(chan_case "stable" "master")
[ "$out" = "master" ] && pass "channel: explicit env overrides the stamp" \
    || fail "channel: explicit env overrides the stamp (out=$out)"
out=$(chan_case "" "")
[ "$out" = "master" ] && pass "channel: master fallback when nothing is stamped" \
    || fail "channel: master fallback when nothing is stamped (out=$out)"
out=$(chan_case "" "feature/x")
[ "$out" = "feature/x" ] && pass "channel: any branch env passes through" \
    || fail "channel: any branch env passes through (out=$out)"
check "channel: KIT_BASE_URL builds from the resolved ref" \
    sh -c "grep -F 'KIT_BASE_URL=\"\${KIT_BASE_URL:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/\$KIT_BRANCH}\"' \"\$1\"" _ "$UPDATE"
check "channel: install.conf refresh strips and re-stamps KIT_CHANNEL" \
    sh -c "grep -qF -- \"-e '^KIT_CHANNEL='\" \"\$1\" && grep -qF 'echo \"KIT_CHANNEL=\$KIT_BRANCH\"' \"\$1\"" _ "$UPDATE"

# --- 6. ddev version stamp refresh (issue #72) -------------------------------------
# DDEV_VERSION in install.conf is an install-time stamp; ddev upgrades leave
# it behind, and ddev >= 1.25.4 even refuses root-run probes (update.sh runs
# as root). The refresh must re-probe via the kit's helper (ddev exactly as
# the kit runs it) and keep the old stamp when nothing answers.
check "ddev stamp: refresh strips and re-stamps DDEV_VERSION" \
    sh -c "grep -qF -- \"-e '^DDEV_VERSION='\" \"\$1\" && grep -qF 'echo \"DDEV_VERSION=\$NEW_DDEV_VERSION\"' \"\$1\"" _ "$UPDATE"
check "ddev stamp: probe asks the ddev-as-opencode helper (ddev >= 1.25.4 refuses root)" \
    sh -c "grep -q 'sudo -n -u \"\$OPENCODE_USER\" \"\$LIBDIR/bin/ddev-as-opencode\" --version' \"\$1\"" _ "$UPDATE"
check "ddev stamp: old stamp survives when no binary answers" \
    sh -c "grep -q 's/^DDEV_VERSION=//p' \"\$1\"" _ "$UPDATE"
check "ddev stamp: summary line reports the refreshed value" \
    sh -c "grep -q 'DDEV_VERSION=\$NEW_DDEV_VERSION' \"\$1\"" _ "$UPDATE"

# --- 7. --channel (switch the tracking ref without editing install.conf) --------
_prescan_ln=$(grep -n '_prev_arg' "$UPDATE" | head -1 | cut -d: -f1)
_resolv_ln=$(grep -n '_kit_stamped_channel=' "$UPDATE" | head -1 | cut -d: -f1)
if [ -n "$_prescan_ln" ] && [ -n "$_resolv_ln" ] && [ "$_prescan_ln" -lt "$_resolv_ln" ]; then
    pass "channel: pre-scan runs before the stamp resolution (fetch uses the new ref)"
else
    fail "channel: pre-scan runs before the stamp resolution (fetch uses the new ref)"
fi
check "channel: arg loop accepts --channel with a value (not 'unknown option')" \
    sh -c "grep -q -- '--channel)' \"\$1\" && grep -qF -- '--channel requires a ref' \"\$1\"" _ "$UPDATE"
check "channel: help text documents --channel" \
    sh -c "grep -q -- '--channel <ref>' \"\$1\"" _ "$UPDATE"
check "channel: switch persists via the KIT_CHANNEL re-stamp" \
    sh -c "grep -qF 'KIT_CHANNEL=\$KIT_BRANCH' \"\$1\"" _ "$UPDATE"
check "channel: missing ref is rejected (arg loop, from a checkout)" \
    sh -c "! sh \"\$1\" --channel >/dev/null 2>&1" _ "$UPDATE"
check "channel: --help with --channel still works (pre-scan is silent)" \
    sh -c "sh \"\$1\" --channel testref --help >/dev/null 2>&1" _ "$UPDATE"
check "channel: ref charset is enforced — metacharacters rejected (0.0.39b S1)" \
    sh -c "! sh \"\$1\" --channel 'foo;rm' >/dev/null 2>&1" _ "$UPDATE"
check "channel: ref charset is enforced — '..' rejected (URL traversal off the repo prefix, 0.0.39e S4)" \
    sh -c "! sh \"\$1\" --channel 'a..b' >/dev/null 2>&1" _ "$UPDATE"
check "channel: ref charset is enforced — newline rejected, also via env" \
    sh -c "! env KIT_BRANCH=\$(printf 'a\\nb') sh \"\$1\" --help >/dev/null 2>&1" _ "$UPDATE"
check "channel: a real ref shape passes the gate (stable)" \
    sh -c "sh \"\$1\" --channel stable --help >/dev/null 2>&1" _ "$UPDATE"

# --- 7b. scratch cleanup (review 0.0.39a C1) --------------------------------------
check "cleanup: EXIT/INT/TERM trap removes fetch tree, sudoers + conf temps" \
    sh -c "grep -qF 'trap cleanup EXIT' \"\$1\" && grep -qF \"trap 'cleanup; exit 1' INT TERM\" \"\$1\" && grep -qF '_FETCH_TREE=\"\$base\"' \"\$1\" && grep -qF '_CONF_TMP=' \"\$1\"" _ "$UPDATE"
check "cleanup: fetched tree survives the self re-exec via the environment" \
    sh -c "grep -qF 'export _FETCH_TREE' \"\$1\"" _ "$UPDATE"

# --- 8. --major / --version (issue #99: upgrades never cross majors) ------------
check "flag: --major parsed, only 1 or 2 accepted" \
    sh -c "grep -q -- '--major)' \"\$1\" && grep -q -- '--major must be 1 or 2' \"\$1\"" _ "$UPDATE"
check "flag: --version parsed with a value" \
    sh -c "grep -q -- '--version)' \"\$1\" && grep -q -- '--version requires an opencode version' \"\$1\"" _ "$UPDATE"
check "flag: --major 3 is rejected" \
    sh -c "! sh \"\$1\" --binary --major 3 >/dev/null 2>&1" _ "$UPDATE"
check "flag: --version without a value is rejected" \
    sh -c "! sh \"\$1\" --binary --version >/dev/null 2>&1" _ "$UPDATE"
check "flag: help text documents --major and --version" \
    sh -c "grep -q -- '--major 1|2' \"\$1\" && grep -q -- '--version <ver>' \"\$1\"" _ "$UPDATE"
check "resolve: latest-version resolution guards the requested major" \
    sh -c "grep -q '2\.\*) echo \"\$_rlov_ver\"' \"\$1\" && grep -q '1\.\*) echo \"\$_rlov_ver\"' \"\$1\"" _ "$UPDATE"
check "resolve: 2.x channel is the npm registry (with scope fallback)" \
    sh -c "grep -q 'registry.npmjs.org/@opencode/cli-' \"\$1\" && grep -q 'registry.npmjs.org/@opencode-ai/cli-' \"\$1\"" _ "$UPDATE"
check "tui: registration flips with the major (sync function, both directions)" \
    sh -c "grep -q '^sync_tui_registration() {' \"\$1\" && grep -q 'tui_plugin_sync_user \"\$_str_major\"' \"\$1\" && grep -qF 'rm -rf \"\${_tp_user_dir:?}/plugins/opencode-permissions-kit\"' \"\$2\"" _ "$UPDATE" "$TUIPLUGIN"
check "tui: a major flip re-anchors the registration even in --only-binary runs" \
    sh -c "grep -n 'sync_tui_registration \"\$_maj_after\"' \"\$1\" | head -1 | cut -d: -f1 | grep -q ." _ "$UPDATE"

# OPENCODE_MAJOR re-stamp discipline (0.0.44a V5/V20, hardened 0.0.44b
# W4): a RETURNED version line is always a major (2.x prints "opencode
# vN...", 1.x the bare version — current_opencode_major parity; the old
# gate treated 1.x as undetermined and kept a stale 2-stamp across the
# documented `--major 1` downgrade). Only an empty probe (unknown) keeps
# the previous stamp; both stamp writes fail loud (rc 2 = post-copy).
_restamp_block=$(sed -n '/^    if \[ "\$new" != "unknown" \]; then/,/^    fi$/p' "$UPDATE")
_restamp_writes=$(printf '%s\n' "$_restamp_block" | grep -c 'OPENCODE_MAJOR=$_new_major' || true)
_restamp_guards=$(printf '%s\n' "$_restamp_block" | grep -c 'return 2' || true)
if grep -qF 'OPENCODE_MAJOR stamp left unchanged' "$UPDATE" \
   && [ "$_restamp_writes" -eq 2 ] && [ "$_restamp_guards" -ge 2 ]; then
    pass "re-stamp only on a probed line, writes fail loud (V5/V20, W4 shape)"
else
    fail "re-stamp only on a probed line, writes fail loud (V5/V20, W4 shape, writes=$_restamp_writes guards=$_restamp_guards)"
fi
# behavioral: the extracted block runs against a fixture conf with a
# direct sudo shim — 0.0.44b W4's regression case (bare 1.x line) must
# stamp 1 over a stale 2 (the old code kept 2 and the wrapper passed the
# 2.x-only --standalone to a 1.x binary).
if [ -n "$_restamp_block" ]; then
    _rst_conf="$WORK/install.conf"
    _rst_run() {
        printf 'OPENCODE_MAJOR=2\n' > "$_rst_conf"
        (
            CONFDIR="$WORK"
            sudo() { "$@"; }
            log() { :; }
            new="$_rst_line"
            eval "$_restamp_block"
        ) >/dev/null 2>&1
        sed -n 's/^OPENCODE_MAJOR=//p' "$_rst_conf" | tail -1
    }
    _rst_line="opencode v2.0.11"
    [ "$(_rst_run)" = "2" ] \
        && pass "re-stamp: 2.x line stamps 2 (W4)" \
        || fail "re-stamp: 2.x line stamps 2 (W4)"
    _rst_line="1.18.31"
    [ "$(_rst_run)" = "1" ] \
        && pass "re-stamp: bare 1.x line stamps 1 over a stale 2 (W4)" \
        || fail "re-stamp: bare 1.x line stamps 1 over a stale 2 (W4)"
    _rst_line="unknown"
    [ "$(_rst_run)" = "2" ] \
        && pass "re-stamp: unknown probe keeps the previous stamp (V5)" \
        || fail "re-stamp: unknown probe keeps the previous stamp (V5)"
    # a NON-matching non-empty line (a warning grabbed by head -1) is
    # unparseable, not major 1 — it must keep the stamp too (0.0.44c C6)
    _rst_line="warn: something odd on stdout"
    [ "$(_rst_run)" = "2" ] \
        && pass "re-stamp: unparseable line keeps the previous stamp (C6)" \
        || fail "re-stamp: unparseable line keeps the previous stamp (C6)"
    # dev-suffixed and digit-leading noise are unparseable too (0.0.44d
    # F3: the bare-version arm is full-line anchored)
    _rst_line="2.0.11-dev"
    [ "$(_rst_run)" = "2" ] \
        && pass "re-stamp: dev-suffixed line keeps the previous stamp (F3)" \
        || fail "re-stamp: dev-suffixed line keeps the previous stamp (F3)"
    _rst_line="404 not found"
    [ "$(_rst_run)" = "2" ] \
        && pass "re-stamp: digit-leading noise keeps the previous stamp (F3)" \
        || fail "re-stamp: digit-leading noise keeps the previous stamp (F3)"

# current_opencode_major anchors the same way (0.0.44e E2): this value
# picks the UPGRADE CHANNEL — a misparsed probe on a 2.x host must fall
# through to the install.conf stamp, not resolve the 1.x channel.
_com_fns=$(sed -n '/^version_major() {/,/^}/p' "$UPDATE")
_com_c=$(sed -n '/^current_opencode_major() {/,/^}/p' "$UPDATE")
# literal newline in quotes: $(printf '\n') strips it and glues the
# function bodies together (Syntax error: Bad function name)
_com_fns="$_com_fns
$_com_c"
if [ -n "$_com_fns" ]; then
    _com_dir="$WORK/comconf"; mkdir -p "$_com_dir"
    printf 'OPENCODE_MAJOR=2\n' > "$_com_dir/install.conf"
    _com_run() {
        (
            CONFDIR="$_com_dir"
            opencode_version_line() { printf '%s\n' "$_probe"; }
            eval "$_com_fns"
            current_opencode_major
        )
    }
    _probe="opencode v2.0.11"
    [ "$(_com_run)" = "2" ] \
        && pass "major probe: 2.x line -> 2 (E2)" \
        || fail "major probe: 2.x line -> 2 (E2)"
    _probe="1.18.31"
    [ "$(_com_run)" = "1" ] \
        && pass "major probe: bare 1.x line -> 1 (E2)" \
        || fail "major probe: bare 1.x line -> 1 (E2)"
    _probe="404 not found"
    [ "$(_com_run)" = "2" ] \
        && pass "major probe: noise falls through to the stamp, not 1 (E2)" \
        || fail "major probe: noise falls through to the stamp, not 1 (E2)"
    _probe="2.0.11-dev"
    [ "$(_com_run)" = "2" ] \
        && pass "major probe: dev-suffixed line falls through to the stamp (E2)" \
        || fail "major probe: dev-suffixed line falls through to the stamp (E2)"
else
    fail "current_opencode_major extractable (E2)"
fi
else
    fail "re-stamp block extractable (W4)"
fi

# --- install.sh install-time major stamp + preflight probe (0.0.44f F1) -----------
# Statics: the anchored shape must exist at the third site of the class,
# the bare default-to-1 must be gone, and the preflight must probe the
# reused binary bounded. The arm statics are scoped to the extracted
# STAMP block — the preflight probe carries the same idiom and would
# satisfy a file-wide grep (the 0.0.42d token-blindness class).
# Behavioral pins for the anchored semantics live above (E2 probes);
# e2e covers the parseable paths with real binaries.
INSTALL="$SCRIPT_DIR/../../files/install.sh"
_f1_dir="$WORK/f1stamp"; mkdir -p "$_f1_dir"
sed -n '/_stamp_ver=/,/major stamp skipped/p' "$INSTALL" > "$_f1_dir/stampblock"
if [ -s "$_f1_dir/stampblock" ]; then
    # Scoping tripwires (0.0.44g G1): the end anchor above is PROSE (the
    # log line) — a rewording would silently run the range to EOF and
    # decay the arm greps back to file-wide/token-blind (the 0.0.42d
    # class). Both decay modes fail LOUD instead: preflight tokens inside
    # the block, or a block grown past every legitimate edit's size.
    check "stamp block scoping: no preflight tokens inside (G1)" \
        sh -c "! grep -q '_pf_oc' \"\$1\"" _ "$_f1_dir/stampblock"
    check "stamp block scoping: block stays compact, no EOF over-run (G1)" \
        sh -c "[ \"\$(wc -l < \"\$1\")\" -le 40 ]" _ "$_f1_dir/stampblock"
    check "install-time stamp anchors the sed major arm (F1)" \
        sh -c 'grep -qF "s/^opencode v\\([0-9][0-9]*\\).*" "$1"' _ "$_f1_dir/stampblock"
    check "install-time stamp anchors the bare-version arm (F1)" \
        sh -c 'grep -qF "grep -qE '"'"'^[0-9]+(\\.[0-9]+)*$'"'"'" "$1"' _ "$_f1_dir/stampblock"
    check "unparseable probe keeps the stamp and warns (F1)" \
        sh -c "grep -qF 'OPENCODE_MAJOR stamp left unchanged' \"\$1\" && grep -qF 'stamp skipped: version probe unparseable' \"\$1\"" _ "$_f1_dir/stampblock"
else
    fail "install-time stamp block extractable (F1)"
fi
check "install-time stamp has no bare default-to-1 (F1)" \
    sh -c "! grep -qE '^[[:space:]]+OPENCODE_MAJOR=1\$' \"\$1\"" _ "$INSTALL"
check "preflight probes the reused binary bounded (F1)" \
    sh -c "grep -qF 'timeout 10 \"\$_pf_oc_bin\" --version' \"\$1\"" _ "$INSTALL"
check "preflight warns instead of aborting on an unresponsive binary (F1)" \
    sh -c "grep -qF 'does not answer --version' \"\$1\" && grep -qF \"the install reuses this binary\" \"\$1\"" _ "$INSTALL"

# --- streamed stdin guard (0.0.45c S8) + help-text drift (D2) ---------------------
# A streamed update (curl | sudo bash) has the script body on stdin: the
# prompt helpers must never fall back to reading it — install.sh has set
# UI_NO_STDIN_FALLBACK since 0.0.39b C6; update.sh, the one remaining
# streamed entry point, consumed script bytes as the confirm answer and
# unknown input silently resolved to the default y. Set AND exported:
# the re-exec'd fetched copy below inherits it.
check "streamed update never reads the confirm answer from the script stream (S8)" \
    sh -c "grep -qF 'UI_NO_STDIN_FALLBACK=1' \"\$1\" && grep -qF 'export UI_NO_STDIN_FALLBACK' \"\$1\"" _ "$UPDATE"
check "update.sh --help no longer claims prompt-free defaults (D2)" \
    sh -c "! grep -qF 'No prompts by default' \"\$1\"" _ "$UPDATE"

# --- OpenChamber policy pin re-apply (issue #154, Tier 2) -------------------------
# Opt-in only: the pin is re-applied when install.conf says
# OPENCHAMBER_POLICY=yes (sourced above), never created without the
# opt-in, and an admin-owned policy.json without the opt-in stays
# untouched.
check "update re-applies the policy pin when opted in" \
    sh -c "grep -qF '[ \"\${OPENCHAMBER_POLICY:-}\" = \"yes\" ]' \"\$1\" \
        && grep -qF 'sudo tee /etc/openchamber/policy.json' \"\$1\"" _ "$UPDATE"
check "update never creates the policy pin without the opt-in" \
    sh -c "! grep -qF 'OPENCHAMBER_POLICY=\"yes\"' \"\$1\"" _ "$UPDATE"
# 0.0.47a F1: the re-apply never overwrites admin content — byte-gate on
# the kit one-liner, loud skip (not a silent tee) when the file diverges,
# and the write sits in the gated else branch.
check "update re-apply is byte-gated on kit-shaped content (0.0.47a F1)" \
    sh -c "grep -qF '_oc_expected=' \"\$1\" \
        && grep -qF '!= \"\$_oc_expected\" ]' \"\$1\" \
        && grep -qF 'diverges from the kit pin (admin-owned content) — left untouched' \"\$1\"" _ "$UPDATE"
check "install twin carries the same admin-content gate (0.0.47a F1)" \
    sh -c "grep -qF 'diverges from the kit pin' \"\$1\"" _ \
    "$SCRIPT_DIR/../../files/install.sh"

# --- issue #164: presence probes run at the write's authority ---------------------
# The openchamber gate probed /etc/openchamber/policy.json at INVOKING-user
# level while its else branch writes via sudo: with an admin-created 0700
# /etc/openchamber a direct non-root run read "absent" and the sudo write
# reconfigured admin-owned state. Sweep (L2, pattern '\[ -[fde] /etc' over
# install.sh/update.sh/uninstall.sh): update.sh:731 + install.sh:2046 (the
# two gate-before-sudo-write sites, fixed), uninstall.sh:557 (same gate
# before sudo rm, live-relevant — uninstall refuses root, so the gate
# ALWAYS runs as the developer; fixed incl. the content grep), install.sh
# 1060 (opt-in prompt detection, branch writes nothing — left plain),
# update.sh:618 (old-layout rm, disagreement direction is a benign
# leftover), update.sh:680 (xdg-open never-shadow gate — ln without -f
# fails loudly on a hidden existing target, no overwrite).
check "update openchamber presence probe escalates like the write (issue #164)" \
    sh -c "grep -qF 'sudo test -f /etc/openchamber/policy.json' \"\$1\" \
        && ! grep -qF 'if [ -f /etc/openchamber/policy.json ]' \"\$1\"" _ "$UPDATE"
check "install twin probes at the same authority (issue #164)" \
    sh -c "grep -qF 'sudo test -f /etc/openchamber/policy.json' \"\$1\"" _ \
    "$SCRIPT_DIR/../../files/install.sh"
check "uninstall twin probes at the same authority (issue #164)" \
    sh -c "grep -qF 'sudo test -f /etc/openchamber/policy.json' \"\$1\" \
        && grep -qF 'sudo grep -q ' \"\$1\"" _ \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"

# Behavioral (L1/L4): the extracted gate block runs verbatim against a
# fixture /etc/openchamber, mode 000 — caller-blind, root-visible (the
# sudo stub models root's DAC override by flipping the dir open around
# read-only probes only; writes are logged, never executed). Fixed probe
# + divergent admin file under the blind dir -> warn branch, NO write.
# Control (readable dir, kit-shaped file) -> the write branch still flows.
# In-vitro sabotage (plain [ -f ] re-planted) -> the bug fires: the same
# blind state slips into the sudo write, proving the pin discriminates.
OC164_BLOCK="$(sed -n '/^    _oc_expected=/,/^    fi$/p' "$UPDATE")"
if [ -n "$OC164_BLOCK" ] \
    && printf '%s' "$OC164_BLOCK" | grep -qF 'sudo test -f /etc/openchamber/policy.json'; then
    pass "openchamber gate block extractable from update.sh (issue #164)"
else
    fail "openchamber gate block not extractable (anchor drift?)"
    OC164_BLOCK=""
fi
OC164_ETC="$WORK/oc164-root/etc/openchamber"
mkdir -p "$OC164_ETC"
# oc164_run <block> <dir-mode> — helpers stubbed to markers; sudo models
# root: test/cat flip the fixture dir open for the probe and restore the
# scenario mode afterwards, every write verb logs SUDO-WRITE.
oc164_run() {
    (
        _oc_dir="$OC164_ETC"
        ui_warn() { echo "WARN|$1"; }
        ui_detail() { :; }
        ui_success() { echo "OK|$1"; }
        log() { :; }
        sudo() {
            case "$1" in
                test|cat)
                    _oc_cmd="$1"; shift
                    chmod 700 "$_oc_dir"
                    if [ "$_oc_cmd" = test ]; then
                        [ "-f" = "$1" ] && [ -f "$2" ]; _oc_rc=$?
                    else
                        command cat "$1" 2>/dev/null; _oc_rc=$?
                    fi
                    chmod "$OC164_MODE" "$_oc_dir"
                    return "$_oc_rc" ;;
                tee)
                    command cat > /dev/null; echo "SUDO-WRITE tee" ;;
                *)  echo "SUDO-WRITE $*" ;;
            esac
        }
        eval "$1"
    )
}
if [ -n "$OC164_BLOCK" ]; then
    OC164_FIXED="$(printf '%s' "$OC164_BLOCK" | sed "s|/etc/openchamber|$OC164_ETC|g")"
    OC164_SABOTAGE="$(printf '%s' "$OC164_FIXED" \
        | sed 's|sudo test -f |[ -f |')"
    # S1: admin 0700 dir (mode 000 = caller-blind), divergent content.
    printf '{ "opencodeBinary": "/usr/local/bin/somewhere-else" }\n' \
        > "$OC164_ETC/policy.json"
    chmod 000 "$OC164_ETC"; OC164_MODE=000
    _out="$(oc164_run "$OC164_FIXED" || true)"
    if printf '%s' "$_out" | grep -q '^WARN|openchamber policy pin NOT re-applied' \
        && ! printf '%s' "$_out" | grep -q 'SUDO-WRITE'; then
        pass "#164 S1: blind admin dir + divergent file -> warn, no write"
    else
        fail "#164 S1: gate must warn and not write (got: $_out)"
    fi
    # S2 control: readable dir, kit-shaped content -> write branch flows.
    chmod 755 "$OC164_ETC"
    printf '{ "opencodeBinary": "/usr/local/bin/opencode" }\n' \
        > "$OC164_ETC/policy.json"
    chmod 755 "$OC164_ETC"; OC164_MODE=755
    _out="$(oc164_run "$OC164_FIXED" || true)"
    if printf '%s' "$_out" | grep -q '^OK|openchamber policy pin re-applied' \
        && printf '%s' "$_out" | grep -q 'SUDO-WRITE'; then
        pass "#164 S2: readable dir + kit shape -> write branch (control)"
    else
        fail "#164 S2: control must reach the write branch (got: $_out)"
    fi
    # S3 in-vitro sabotage: the old plain [ -f ] shape over the same blind
    # state MUST fire the sudo write — the discrimination proof.
    chmod 000 "$OC164_ETC"; OC164_MODE=000
    _out="$(oc164_run "$OC164_SABOTAGE" || true)"
    if printf '%s' "$_out" | grep -q 'SUDO-WRITE'; then
        pass "#164 S3: plain [ -f ] sabotage slips into the write (discriminates)"
    else
        fail "#164 S3: sabotage run must fire the write (pin is vacuous?)"
    fi
    chmod 755 "$OC164_ETC"
fi

# --- shell-startup hook re-apply via getent home (issue #192) --------------------
# The rc-hook section must reach the REAL developer home (getent-resolved
# DEFAULT_HOME). On the root-shell installs the installer now refuses,
# the old /home/$DEFAULT_USER gate pointed at /home/root (never exists)
# and this whole section SKIPPED SILENTLY — while status.sh kept telling
# users "run opk update". Pins: uid-0 developer -> loud skip, no writes;
# missing home -> loud skip; healthy home -> the hook line is appended.
_hk_block="$(sed -n '/^# Root-shell installs (issue #192)/,/^fi$/p' "$UPDATE")"
if [ -n "$_hk_block" ]; then
    pass "shell-startup hook block extractable from update.sh (issue #192)"
    _hk_run() {
        # $1=DEFAULT_USER $2=uid|empty=id-fails $3=DEFAULT_HOME — sudo runs
        # inlined (the suite is rootless), ui/log echo, so arms assert on
        # output. An EMPTY uid makes id fail, executing the probe's
        # `|| echo 1` fallback arm (#196 a T2).
        (
            DEFAULT_USER="$1"; DEFAULT_HOME="$3"
            export DEFAULT_USER DEFAULT_HOME
            HK_UID="$2"
            export HK_UID
            id() { [ "${1:-}" = "-u" ] || return 1; [ -n "$HK_UID" ] \
                && printf '%s\n' "$HK_UID" || return 1; }
            sudo() { "$@"; }
            ui_warn()   { echo "warn: $*"; }
            ui_detail() { echo "detail: $*"; }
            ui_success(){ echo "success: $*"; }
            log()       { echo "log: $*"; }
            eval "$_hk_block"
        ) 2>&1
    }
    _rc=0; _out=$(_hk_run root 0 "$WORK/hku-root") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'shell-startup hooks skipped' \
       && printf '%s' "$_out" | grep -q 'uid 0' \
       && ! printf '%s' "$_out" | grep -q 'ddev terminal hook installed'; then
        pass "uid-0 developer: loud skip, no hook provisioning for root"
    else
        fail "uid-0 developer: loud skip, no hook provisioning for root (rc=$_rc out=$_out)"
    fi
    _rc=0; _out=$(_hk_run hku-dev 1000 "$WORK/hku-missing") || _rc=$?
    if [ "$_rc" -eq 0 ] && printf '%s' "$_out" | grep -q 'does not exist' \
       && ! printf '%s' "$_out" | grep -q 'ddev terminal hook installed'; then
        pass "missing home: loud skip instead of the old silent one"
    else
        fail "missing home: loud skip instead of the old silent one (rc=$_rc out=$_out)"
    fi
    mkdir -p "$WORK/hku-home"
    printf '# plain rc\n' > "$WORK/hku-home/.bashrc"
    _rc=0; _out=$(_hk_run hku-dev 1000 "$WORK/hku-home") || _rc=$?
    if [ "$_rc" -eq 0 ] && grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh' "$WORK/hku-home/.bashrc" \
       && grep -q 'opencode-permissions-kit/sh/shell-warn.sh' "$WORK/hku-home/.bashrc" \
       && printf '%s' "$_out" | grep -qF "ddev terminal hook installed into $WORK/hku-home/.bashrc"; then
        pass "healthy home: shell-warn + ddev hook lines appended to the real rc"
    else
        fail "healthy home: shell-warn + ddev hook lines appended to the real rc (rc=$_rc out=$_out rcfile=$(cat "$WORK/hku-home/.bashrc" 2>/dev/null))"
    fi
    # id-probe failure arm (#196 a T2): unresolvable developer → id fails
    # → `|| echo 1` sentinel → NOT the uid-0 loud skip; the healthy home
    # still provisions. Fresh rc file — hku-home above is already hooked,
    # a re-run would take the sed branch and stay silent.
    mkdir -p "$WORK/hku-idfail"
    printf '# plain rc\n' > "$WORK/hku-idfail/.bashrc"
    _rc=0; _out=$(_hk_run hku-dev2 "" "$WORK/hku-idfail") || _rc=$?
    if [ "$_rc" -eq 0 ] && grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh' "$WORK/hku-idfail/.bashrc" \
       && ! printf '%s' "$_out" | grep -q 'uid 0'; then
        pass "id-probe failure: sentinel uid provisions, no false uid-0 skip (executed)"
    else
        fail "id-probe failure: sentinel uid provisions, no false uid-0 skip (rc=$_rc out=$_out)"
    fi
else
    fail "shell-startup hook block extractable from update.sh (issue #192)"
fi
# DEFAULT_HOME is getent-resolved once, beside the DEFAULT_USER default
# (V14 sibling resolution — every developer-side site below rides it).
# Negative sweep tightened (#196 a T1; braced spelling added by
# #196 b B2; survivor list completed by #196 c C2): every slash form
# of the literal /home/$DEFAULT_USER spelling counts, braced included
# — the old gate was exactly the slash-less
# `[ -d "/home/$DEFAULT_USER" ]`. Allowed survivors: comment lines,
# the getent-failure fallback (`|| var="/home/$DEFAULT_USER"`), and
# the braced self-default fallback
# (`var="${var:-/home/${DEFAULT_USER:-$USER}}"` — sanctioned shape,
# status.sh's openchamber home).
_up_bad="$(grep -e '/home/\$DEFAULT_USER' -e '/home/\${DEFAULT_USER' "$UPDATE" 2>/dev/null \
    | grep -v '^[[:space:]]*#' \
    | grep -v '|| [[:alnum:]_]\{1,\}="/home/\$DEFAULT_USER"$' \
    | grep -v '[[:alnum:]_]\{1,\}="\${[[:alnum:]_]\{1,\}:-/home/\${DEFAULT_USER:-\$USER}}"$' || true)"
if grep -q 'DEFAULT_HOME="$(getent passwd "$DEFAULT_USER"' "$UPDATE" \
   && [ -z "$_up_bad" ]; then
    pass "update.sh resolves DEFAULT_HOME via getent, no hardcoded usage site"
else
    fail "update.sh resolves DEFAULT_HOME via getent, no hardcoded usage site (${_up_bad:-no getent})"
fi

# --- DEFAULT_HOME probe fallback executes (#196 a T2) ----------------------------
# The two resolution lines run with a stubbed getent: the miss arm MUST
# land on the /home/<name> fallback, the hit arm MUST keep the passwd
# home. Value pins — a deleted fallback or a broken getent line fails on
# the VALUE, not just on a missing branch.
_dh_lines="$(sed -n '/^DEFAULT_HOME="\$(getent passwd/p' "$UPDATE"; \
    sed -n '/^\[ -n "\$DEFAULT_HOME" \] || DEFAULT_HOME="\/home/p' "$UPDATE")"
if [ "$(printf '%s\n' "$_dh_lines" | wc -l | tr -d ' ')" = "2" ]; then
    pass "DEFAULT_HOME resolution lines extractable from update.sh"
    _dh_arm() {
        (
            DEFAULT_USER="hku-dh"; DH_HOME="$1"
            export DEFAULT_USER DH_HOME
            getent() { [ -n "$DH_HOME" ] && printf 'x:x:1000:1000::%s:/bin/sh\n' "$DH_HOME"; }
            eval "$_dh_lines"
            printf '%s\n' "$DEFAULT_HOME"
        )
    }
    _rc=0; _out=$(_dh_arm "") || _rc=$?
    if [ "$_rc" -eq 0 ] && [ "$_out" = "/home/hku-dh" ]; then
        pass "DEFAULT_HOME getent miss falls back to /home/<name> (executed)"
    else
        fail "DEFAULT_HOME getent miss falls back to /home/<name> (rc=$_rc out=$_out)"
    fi
    _rc=0; _out=$(_dh_arm "/relocated/home") || _rc=$?
    if [ "$_rc" -eq 0 ] && [ "$_out" = "/relocated/home" ]; then
        pass "DEFAULT_HOME getent hit keeps the passwd home (executed)"
    else
        fail "DEFAULT_HOME getent hit keeps the passwd home (rc=$_rc out=$_out)"
    fi
else
    fail "DEFAULT_HOME resolution lines extractable from update.sh"
fi

# id-probe sentinel value (#196 a T2): `|| echo 1` must yield exactly "1"
# for an unresolvable developer — `|| true` (empty uid) keeps every branch
# pin above green while silently re-arming the uid-0 loud skip for ghosts.
_du_line="$(grep '^ *_du_uid=' "$UPDATE" | head -1)"
if [ -n "$_du_line" ]; then
    _rc=0; _out=$(
        (
            DEFAULT_USER="hku-duval"
            export DEFAULT_USER
            id() { return 1; }
            eval "$_du_line"
            printf '%s\n' "${_du_uid:-}"
        )
    ) || _rc=$?
    if [ "$_rc" -eq 0 ] && [ "$_out" = "1" ]; then
        pass "update.sh id probe: unresolvable developer resolves to sentinel 1 (executed)"
    else
        fail "update.sh id probe: unresolvable developer resolves to sentinel 1 (rc=$_rc out=$_out)"
    fi
else
    fail "update.sh id probe line extractable from update.sh"
fi

# --- Summary ----------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
