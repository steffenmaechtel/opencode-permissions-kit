#!/bin/sh
# Unit tests for sh/deploy-lib.sh (0.0.41d wave): the shared library
# deployment manifest that replaced install.sh's and update.sh's
# twin cp/chmod listings.
#   - happy path: every manifest entry lands in <libdir> with its mode
#     (440 sudoers.template, 755 commands, 644 sourced libs/tui)
#   - a bad tree-root is rejected before anything is written
#   - a partial tree fails LOUD on the first missing source (a broken
#     fetch cannot half-deploy silently)
#   - "-" entries (jsonc templates) deploy without an explicit chmod
# Runs as the CURRENT user (DL_SUDO="") against the real checkout —
# no root.
# Run: sh tests/unit/test-deploy-lib.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"

failures=0
passed=0

pass() {
    echo "  ${GREEN}PASS${NC}  $1"
    passed=$((passed + 1))
}
fail() {
    echo "  ${RED}FAIL${NC}  $1"
    failures=$((failures + 1))
}

check() {
    _d="$1"
    shift
    if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}

mode_is() {
    [ "$(stat -c %a "$1")" = "$2" ]
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM
LIBD="$WORK/libdir"

# --- 1. happy path ----------------------------------------------------------

_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    lib_deploy "$REPO/files" "$LIBD" 2>&1
    echo "rc=$?"
)
case "$_dl_out" in *rc=0*) pass "happy: rc=0" ;; *) fail "happy: rc (got [$_dl_out])" ;; esac

_manifest_n=$(sed -n "/<<'DL_MANIFEST'/,/^DL_MANIFEST\$/p" "$LIB" |
    sed -e '1d' -e '$d' | grep -v '^#' | awk 'NF' | wc -l)
_deployed_n=$(find "$LIBD" -type f | wc -l)
if [ "$_deployed_n" = "$_manifest_n" ]; then
    pass "happy: all $_manifest_n manifest entries deployed"
else
    fail "happy: entry count (manifest $_manifest_n vs deployed $_deployed_n)"
fi

check "mode: sudoers.template 440" mode_is "$LIBD/templates/sudoers.template" 440
check "mode: bin/opk 755" mode_is "$LIBD/bin/opk" 755
check "mode: bin/opencode-as-opencode 755" mode_is "$LIBD/bin/opencode-as-opencode" 755
check "mode: sh/staged-write.sh 644" mode_is "$LIBD/sh/staged-write.sh" 644
check "mode: sh/sudoers-deploy.sh 644" mode_is "$LIBD/sh/sudoers-deploy.sh" 644
check "mode: sh/deploy-lib.sh 644 (self-deploy)" mode_is "$LIBD/sh/deploy-lib.sh" 644
check "mode: sh/log.sh 755" mode_is "$LIBD/sh/log.sh" 755
check "mode: management/config.sh 755" mode_is "$LIBD/management/config.sh" 755
check "mode: tui/tui.json 644" mode_is "$LIBD/tui/tui.json" 644
check "mode: py/tui-register.py 755" mode_is "$LIBD/py/tui-register.py" 755
check '"-" entry: templates/opencode.jsonc deployed (mode follows source)' \
    test -f "$LIBD/templates/opencode.jsonc"

# --- 2. bad tree-root -------------------------------------------------------

_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    lib_deploy "$WORK" "$WORK/lib2" 2>&1
    echo "rc=$?"
)
case "$_dl_out" in *rc=1*) pass "bad root: rc=1" ;; *) fail "bad root: rc (got [$_dl_out])" ;; esac
case "$_dl_out" in *"does not contain opencode-permissions-kit-lib"*) pass "bad root: loud message" ;; *) fail "bad root: message" ;; esac
check "bad root: nothing written" test ! -e "$WORK/lib2"

# --- 3. partial tree fails on the first missing source ----------------------

PART="$WORK/partial"
mkdir -p "$PART/opencode-permissions-kit-lib/management"
cp "$REPO/files/opencode-permissions-kit-lib/management/config.sh" "$PART/opencode-permissions-kit-lib/management/"
_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    # shellcheck disable=SC2030
    . "$LIB"
    lib_deploy "$PART" "$WORK/lib3" 2>&1
    echo "rc=$?"
)
case "$_dl_out" in *rc=1*) pass "partial tree: rc=1" ;; *) fail "partial tree: rc (got [$_dl_out])" ;; esac
case "$_dl_out" in *"missing source"*) pass "partial tree: names the missing source" ;; *) fail "partial tree: message" ;; esac

# --- 4. atomic per-entry deploy (0.0.49a W2) ---------------------------------
# The #163 class on the kit's own scripts: a cp killed mid-write over
# bin/opk or management/update.sh used to leave a truncated script with
# intact mode bits. Pins mirror test-secure-binary 5b/5c: the OLD entry
# must survive a killed cp and a failing mv byte-identical, no temp
# left behind — plus the mode-before-mv ordering (sudoers.template is
# 440 at the moment its name appears, never a cp-natural 644).

ATD="$WORK/atomic"
mkdir -p "$ATD/lib/management"
printf 'OLD-ENTRY-BYTES\n' >"$ATD/lib/management/config.sh"

# 4a. killed cp: partial bytes into the temp, then die — old entry
# survives, temp cleaned.
mkdir -p "$WORK/killing-cp-bin"
cat >"$WORK/killing-cp-bin/cp" <<'KILLCP'
#!/bin/sh
[ "$#" -ge 2 ] || exit 1
head -c 4 "$1" > "$2" || exit 1
exit 1
KILLCP
chmod +x "$WORK/killing-cp-bin/cp"
_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    PATH="$WORK/killing-cp-bin:$PATH"
    export DL_SUDO PATH
    # shellcheck disable=SC2031
    . "$LIB"
    lib_deploy "$REPO/files" "$ATD/lib" 2>&1
    echo "rc=$?"
)
case "$_dl_out" in *rc=1*) pass "atomic: killed cp fails the deploy rc=1" ;; *) fail "atomic: killed cp rc (got [$_dl_out])" ;; esac
check "atomic: killed cp leaves the OLD entry byte-identical (W2)" \
    sh -c '[ "$(cat "$1")" = "OLD-ENTRY-BYTES" ]' _ "$ATD/lib/management/config.sh"
check "atomic: killed cp leaves no temp behind" \
    sh -c '[ -z "$(find "$1" -name "*.tmp.*" -print)" ]' _ "$ATD/lib"

# 4b. failing mv: the copy+chmod landed in the temp, the rename dies —
# old entry survives, temp cleaned.
mkdir -p "$WORK/failing-mv-bin"
printf '#!/bin/sh\nexit 1\n' >"$WORK/failing-mv-bin/mv"
chmod +x "$WORK/failing-mv-bin/mv"
_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    PATH="$WORK/failing-mv-bin:$PATH"
    export DL_SUDO PATH
    # shellcheck disable=SC2031
    . "$LIB"
    lib_deploy "$REPO/files" "$ATD/lib" 2>&1
    echo "rc=$?"
)
case "$_dl_out" in *rc=1*) pass "atomic: failing mv fails the deploy rc=1" ;; *) fail "atomic: failing mv rc (got [$_dl_out])" ;; esac
check "atomic: failing mv leaves the OLD entry byte-identical" \
    sh -c '[ "$(cat "$1")" = "OLD-ENTRY-BYTES" ]' _ "$ATD/lib/management/config.sh"
check "atomic: failing mv cleans its temp up" \
    sh -c '[ -z "$(find "$1" -name "*.tmp.*" -print)" ]' _ "$ATD/lib"

# 4c. mode-before-mv ordering: a capturing mv stub records the staged
# temp's mode at rename time. sudoers.template (checkout mode 664,
# deployed 440) must be 440 AT the mv — under a reverted cp-then-chmod
# the temp would still carry the cp-natural 644.
mkdir -p "$WORK/capture-mv-bin"
MV_REAL="$(command -v mv)"
MODE_CAPT="$WORK/mv-modes.txt"
export MV_REAL MODE_CAPT
cat >"$WORK/capture-mv-bin/mv" <<'CAPMV'
#!/bin/sh
# capture the staged temp's mode at rename time — the SOURCE is the
# last-but-one argument (`mv -f src dst` puts -f first)
_cap_src=
_cap_prev=
for _cap_a in "$@"; do
    _cap_prev=$_cap_src
    _cap_src=$_cap_a
done
printf '%s %s\n' "$(stat -c %a "$_cap_prev" 2>/dev/null || echo none)" "$_cap_prev" >> "$MODE_CAPT"
exec "$MV_REAL" "$@"
CAPMV
chmod +x "$WORK/capture-mv-bin/mv"
ATD2="$WORK/atomic2"
_dl_out=$(
    DL_SUDO=""
    export DL_SUDO
    PATH="$WORK/capture-mv-bin:$PATH"
    export DL_SUDO PATH
    # shellcheck disable=SC2031
    . "$LIB"
    lib_deploy "$REPO/files" "$ATD2" 2>&1
    echo "rc=$?"
)
case "$_dl_out" in *rc=0*) pass "atomic: capturing-mv deploy rc=0" ;; *) fail "atomic: capturing-mv rc (got [$_dl_out])" ;; esac
check "atomic: sudoers.template is 440 at mv time (mode rides before the rename)" \
    sh -c 'grep -q "^440 .*sudoers\.template\.tmp\." "$1"' _ "$MODE_CAPT"
check "atomic: capturing-mv run leaves the deployed mode correct" \
    mode_is "$ATD2/templates/sudoers.template" 440
check "atomic: capturing-mv run leaves no temp behind" \
    sh -c '[ -z "$(find "$1" -name "*.tmp.*" -print)" ]' _ "$ATD2"

# --- summary ----------------------------------------------------------------

echo ""
echo "===================================="
echo "  Passed: $passed  Failed: $failures"
[ "$failures" -eq 0 ] && echo "  All tests passed." || exit 1
exit 0
