#!/bin/sh
# Unit tests for update.sh's binary-upgrade flow + --only-binary (issue #24):
#   - fetch_latest_opencode: functional test with a fake curl on PATH —
#     the extracted candidate must SURVIVE until the caller installs it
#     (the old flow `rm -rf $TMP`'d it before verification, so every
#     downloaded upgrade failed with "candidate failed verification")
#   - TMP cleanup happens AFTER the install attempt (static order check)
#   - --only-binary: parsing, gating, confirm text, summary, docs
# No root required.
# Run: sh tests/test-update-flags.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
KIT="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opk"
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

# --- 1. flag parsing (static extraction, same pattern as test-install-args) ------
extract_fn() {
    sed -n "/^$1() {/,/^}/p" "$UPDATE"
}

if [ -n "$(extract_fn fetch_latest_opencode)" ]; then
    pass "fetch_latest_opencode defined in update.sh"
else
    fail "fetch_latest_opencode defined in update.sh"
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
    sed -n '/^detect_asset() {/,/^}/p' "$UPDATE"
    sed -n '/^version_major() {/,/^}/p' "$UPDATE"
    sed -n '/^current_opencode_major() {/,/^}/p' "$UPDATE"
    sed -n '/^resolve_latest_opencode_version() {/,/^}/p' "$UPDATE"
    sed -n '/^fetch_opencode_version() {/,/^}/p' "$UPDATE"
    sed -n '/^fetch_latest_opencode() {/,/^}/p' "$UPDATE"
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

# 2e. fetch_latest_opencode: default stays on the CURRENT major (no 2.x ->
# 1.x downgrade); explicit major picks the channel
DL="$(mktemp -d)"
OUT=$(PATH="$WORK/bin:$PATH" SYSTEM_BIN="$WORK/stub-v2" CONFDIR="$WORK/conf" \
    sh -c ". '$FUNCS' && fetch_latest_opencode '$DL'" 2>/dev/null || true)
check "fetch: current major 2 -> npm candidate (issue #99: no downgrade)" \
    sh -c "[ \"\$1\" = \"\$2/opencode\" ] && \"\$1\" --version 2>/dev/null | grep -q '^opencode v2'" _ "$OUT" "$DL"
rm -rf "$DL"; DL="$(mktemp -d)"
OUT=$(PATH="$WORK/bin:$PATH" SYSTEM_BIN="$WORK/stub-v1" CONFDIR="$WORK/conf" \
    sh -c ". '$FUNCS' && fetch_latest_opencode '$DL'" 2>/dev/null || true)
check "fetch: current major 1 -> GitHub candidate" \
    sh -c "[ \"\$1\" = \"\$2/opencode\" ] && \"\$1\" --version >/dev/null 2>&1" _ "$OUT" "$DL"
rm -rf "$DL"

# --- 3. TMP cleanup order: never before the install attempt ----------------------
IB_LINE=$(grep -n 'install_binary "\$SRC"' "$UPDATE" | head -1 | cut -d: -f1)
LAST_TMP_RM=$(grep -n 'rm -rf "\$TMP"' "$UPDATE" | tail -1 | cut -d: -f1)
check "cleanup: candidate dir removed only AFTER the install attempt (issue #24)" \
    sh -c "[ -n \"\$1\" ] && [ -n \"\$2\" ] && [ \"\$2\" -gt \"\$1\" ]" _ "$IB_LINE" "$LAST_TMP_RM"

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
CHAN_BLOCK="$(grep -F '_kit_stamped_channel=' "$UPDATE" | head -1)
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
    sh -c "grep -q '^sync_tui_registration() {' \"\$1\" && grep -q 'if \[ \"\$_str_major\" = 2 \]' \"\$1\" && grep -q 'rm -rf \"\$_str_user_dir/plugins/opencode-permissions-kit\"' \"\$1\"" _ "$UPDATE"
check "tui: a major flip re-anchors the registration even in --only-binary runs" \
    sh -c "grep -n 'sync_tui_registration \"\$_maj_after\"' \"\$1\" | head -1 | cut -d: -f1 | grep -q ." _ "$UPDATE"

# --- Summary ----------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
