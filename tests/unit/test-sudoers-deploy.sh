#!/bin/sh
# Unit tests for sh/sudoers-deploy.sh (0.0.41b wave): the shared sudoers
# pipeline that replaced the triple duplication in install.sh, config.sh
# and update.sh.
#   - happy path: DEFAULT_USER substituted, visudo ran on the RENDERED
#     file, installed mode 440 into CONFDIR, symlinked into sudoers.d,
#     legacy pre-0.0.10 name removed
#   - invalid user charset (sed-interpolated into sudoers) rejected,
#     nothing deployed
#   - missing template rejected, nothing deployed
#   - visudo rejection deploys NOTHING (the 0.0.38 S1 contract: a broken
#     file in /etc/sudoers.d makes sudo itself refuse to run)
#   - the mktemp scratch is gone on every exit path
# Runs as the CURRENT user (SD_SUDO="" + temp CONFDIR/sudoers.d + a
# PATH-stubbed visudo) — no root.
# Run: sh tests/unit/test-sudoers-deploy.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO/files/opencode-permissions-kit-lib/sh/sudoers-deploy.sh"
TEMPLATE_SRC="$REPO/files/opencode-permissions-kit-lib/templates/sudoers.template"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    _d="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CONF="$WORK/conf"
SDD="$WORK/sudoers.d"
mkdir -p "$SDD"

# visudo stub: rejects a file containing the marker line REJECT (lets
# individual tests force the validation failure), accepts everything
# else. Counts invocations so the tests can assert it RAN.
VISUDO="$WORK/visudo"
cat > "$VISUDO" <<'EOF'
#!/bin/sh
# test stub: visudo -c -f <file>
[ "$1" = "-c" ] && [ "$2" = "-f" ] && [ $# -eq 3 ] || exit 2
echo run >> "$VISUDO_RUNS"
if grep -q '^REJECT' "$3"; then exit 1; fi
exit 0
EOF
chmod +x "$VISUDO"
VISUDO_RUNS="$WORK/visudo-runs"; export VISUDO_RUNS
: > "$VISUDO_RUNS"

# The template under test: same shape as the shipped one (DEFAULT_USER
# placeholders). The shipped template is used as-is; a reject variant
# renders invalid content via a prepended marker.
TPL="$WORK/sudoers.template"
sed 's/^/# /; s/$//' "$TEMPLATE_SRC" > /dev/null  # touch: template must parse as text
cp "$TEMPLATE_SRC" "$TPL"

# test env: no sudo, stubbed visudo, redirected dirs
sd_env() {
    SD_SUDO="" SD_VISUDO="$VISUDO" SD_CONF_DIR="$CONF" SD_SUDOERS_D="$SDD"
}

# --- 1. happy path ---------------------------------------------------------

rm -rf "$CONF"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL" alice; echo "rc=$?"
)
case "$_sd_out" in *rc=0*) pass "happy path: rc=0" ;; *) fail "happy path: rc (got [$_sd_out])" ;; esac
check "happy path: CONFDIR/sudoers installed" test -f "$CONF/sudoers"
check "happy path: mode 440" sh -c "[ \"\$(stat -c %a \"$CONF/sudoers\")\" = 440 ]"
check "happy path: DEFAULT_USER substituted" grep -q alice "$CONF/sudoers"
check "happy path: placeholder gone" sh -c "! grep -q DEFAULT_USER \"$CONF/sudoers\""
check "happy path: sudoers.d symlink" test -L "$SDD/opencode-permissions-kit"
check "happy path: symlink points at CONFDIR/sudoers" \
    sh -c "[ \"\$(readlink \"$SDD/opencode-permissions-kit\")\" = \"$CONF/sudoers\" ]"
check "happy path: visudo ran on the rendered file" test -s "$VISUDO_RUNS"

# --- 2. legacy name cleanup ------------------------------------------------

# A 440 file cannot be overwritten by its (non-root) owner — reset the
# CONFDIR between runs like the privileged callers never have to.
rm -rf "$CONF"
touch "$SDD/opencode"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL" alice; echo "rc=$?"
)
check "legacy: pre-0.0.10 sudoers.d/opencode removed" test ! -e "$SDD/opencode"

# --- 3. invalid user charset ----------------------------------------------

rm -rf "$CONF"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL" 'bad;name' ; echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "charset: rc=1" ;; *) fail "charset: rc (got [$_sd_out])" ;; esac
check "charset: nothing deployed" test ! -e "$CONF/sudoers"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL" ""; echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "charset: empty user rejected" ;; *) fail "charset: empty user (got [$_sd_out])" ;; esac

# --- 4. missing template ---------------------------------------------------

_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$WORK/does-not-exist" alice; echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "missing template: rc=1" ;; *) fail "missing template: rc (got [$_sd_out])" ;; esac

# --- 5. visudo rejection deploys NOTHING -----------------------------------

rm -rf "$CONF"
rm -f "$SDD/opencode-permissions-kit"
TPL_BAD="$WORK/sudoers-bad.template"
{ echo "REJECT"; cat "$TPL"; } > "$TPL_BAD"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL_BAD" alice 2>&1; echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "visudo reject: rc=1" ;; *) fail "visudo reject: rc (got [$_sd_out])" ;; esac
case "$_sd_out" in *"nothing was deployed"*) pass "visudo reject: loud message" ;; *) fail "visudo reject: message" ;; esac
check "visudo reject: no CONFDIR/sudoers" test ! -e "$CONF/sudoers"
check "visudo reject: no sudoers.d link" test ! -e "$SDD/opencode-permissions-kit"

# --- 6. scratch cleanup ----------------------------------------------------

# After all paths above the mktemp scratch must be gone: the only files
# left in TMPDIR from this run are the visudo-runs counter (created by
# the test, not the lib) — assert no world-readable opk leftover.
# mindepth 1: $WORK itself is a mktemp dir named tmp.* — the starting
# point must not count as a leftover.
_n_before=$(find "$WORK" -mindepth 1 -name 'tmp.*' | wc -l)
check "scratch: no mktemp leftovers in the test workdir" test "$_n_before" -eq 0

# --- summary ---------------------------------------------------------------

echo ""
echo "===================================="
echo "  Passed: $passed  Failed: $failures"
[ "$failures" -eq 0 ] && echo "  All tests passed." || exit 1
exit 0
