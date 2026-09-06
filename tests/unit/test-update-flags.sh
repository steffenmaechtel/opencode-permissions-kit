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

# --- 2. functional: candidate survives until the caller installs it -------------
# Fake curl on PATH: without -o it answers the GitHub API call, with -o it
# "downloads" a fixture tarball containing an executable opencode stub.
mkdir -p "$WORK/bin" "$WORK/fixture"
printf '#!/bin/sh\necho "opencode version 9.9.9"\n' > "$WORK/fixture/opencode"
chmod +x "$WORK/fixture/opencode"
tar -czf "$WORK/fixture/release.tar.gz" -C "$WORK/fixture" opencode
cat > "$WORK/bin/curl" <<FAKE
#!/bin/sh
case " \$* " in
    *" -o "*)
        _out=""
        while [ \$# -gt 0 ]; do
            [ "\$1" = "-o" ] && _out="\$2" && break
            shift
        done
        cp "$WORK/fixture/release.tar.gz" "\$_out"
        ;;
    *)
        printf '{"tag_name":"v9.9.9"}\n'
        ;;
esac
FAKE
chmod +x "$WORK/bin/curl"

DL="$(mktemp -d)"
OUT=$(PATH="$WORK/bin:$PATH" sh -c "
    eval \"\$(sed -n '/^detect_asset() {/,/^}/p' \"\$1\")\"
    eval \"\$(sed -n '/^fetch_latest_opencode() {/,/^}/p' \"\$1\")\"
    fetch_latest_opencode \"\$2\"
" _ "$UPDATE" "$DL" 2>/dev/null || true)
check "fetch: prints the candidate path" [ "$OUT" = "$DL/opencode" ]
check "fetch: candidate binary exists and is executable" test -x "$DL/opencode"
check "fetch: candidate runs (--version works for install_binary)" \
    sh -c "\"\$1\" --version >/dev/null 2>&1" _ "$DL/opencode"
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

# --- Summary ----------------------------------------------------------------------
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
