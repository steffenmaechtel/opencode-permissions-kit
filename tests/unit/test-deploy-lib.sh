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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
# Shared harness (issue #394): pass/fail, colors, counters live in
# lib/harness.sh now. The local check() below deliberately SHADOWS the
# harness form -- it suppresses the checked command's output; keep it
# (review #398 a F2: the shadow is intentional, the generic wording was
# false here).
. "$SCRIPT_DIR/lib/harness.sh"

check() {
    _d="$1"
    shift
    # F6 parity with the harness form (round A B6): an empty command
    # fails loud instead of vacuously passing through the redirection-
    # only null command.
    if [ "$#" -eq 0 ]; then
        fail "$_d (check: no command given)"
        return
    fi
    if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}

mode_is() {
    [ "$(stat -c %a "$1")" = "$2" ]
}

# Loud scratch guard (#441 a B1 / #454 a C1 class): no set -e here -- a
# failed work_new must abort instead of degenerating fixture writes.
WORK="$(work_new)" || {
    echo "deploy-lib tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
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
check "mode: sh/log.sh 644 (sourced lib, #377 F2)" mode_is "$LIBD/sh/log.sh" 644
check "mode: sh/ui.sh 644 (sourced lib, #377 F2)" mode_is "$LIBD/sh/ui.sh" 644
check "mode: sh/advisories.sh 644 (sourced lib, #377 F2)" mode_is "$LIBD/sh/advisories.sh" 644
check "mode: sh/shell-warn.sh 644 (sourced lib, #377 F2)" mode_is "$LIBD/sh/shell-warn.sh" 644
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

# --- xdg_shim_needed_for (issue #257) --------------------------------------------
# The version gate behind the shim deploy/withhold decisions in
# install-core.sh and update-core.sh: 2.x at or above the upstream fix
# (first release v2.0.32, anomalyco/opencode#52548 / PR #56082) opens
# without an xdg-open; 1.x (never fixed upstream) and everything the
# probe cannot parse keep the shim (fail-safe direction).
_xsg="$(extract_func "$LIB" xdg_shim_needed_for)" || _xsg=""
if [ -n "$_xsg" ]; then
    eval "$_xsg"
    # Source the constant the way the lib defines it (top-level var).
    XDG_SHIM_FIX_VERSION="$(sed -n 's/^XDG_SHIM_FIX_VERSION="\(.*\)"$/\1/p' "$LIB")"
    if xdg_shim_needed_for 1 1.19.5; then
        pass "xdg gate: 1.x needs the shim (1.19.5)"
    else
        fail "xdg gate: 1.x needs the shim (1.19.5)"
    fi
    if xdg_shim_needed_for 2 2.0.31; then
        pass "xdg gate: 2.0.31 (pre-fix) needs the shim"
    else
        fail "xdg gate: 2.0.31 (pre-fix) needs the shim"
    fi
    if xdg_shim_needed_for 2 2.0.32; then
        fail "xdg gate: 2.0.32 (fix release) withholds the shim"
    else
        pass "xdg gate: 2.0.32 (fix release) withholds the shim"
    fi
    if xdg_shim_needed_for 2 2.1.0 && xdg_shim_needed_for 2 2.2.6; then
        fail "xdg gate: 2.1.0/2.2.6 withhold the shim"
    else
        pass "xdg gate: 2.1.0/2.2.6 withhold the shim"
    fi
    if xdg_shim_needed_for 2 "" && xdg_shim_needed_for "" "9.9.9"; then
        pass "xdg gate: empty version/major keep the shim (fail-safe)"
    else
        fail "xdg gate: empty version/major keep the shim (fail-safe)"
    fi
    # Non-empty garbage must ALSO keep the shim (review a A3): sort -V
    # places non-numeric strings after the triple — without the shape
    # gate a garbage version would compare as "newer" and fail OPEN.
    if xdg_shim_needed_for 2 "unknown" && xdg_shim_needed_for 2 "2.0.x"; then
        pass "xdg gate: non-version-shaped values keep the shim (review a A3)"
    else
        fail "xdg gate: garbage versions must fail CLOSED (review a A3)"
    fi
    assert_eq "xdg gate: fix version pin is 2.0.32" "2.0.32" "$XDG_SHIM_FIX_VERSION"
else
    fail "xdg gate: xdg_shim_needed_for extractable from deploy-lib.sh"
fi

# --- summary ----------------------------------------------------------------

echo ""
echo "===================================="
echo "  Passed: $passed  Failed: $failures"
[ "$failures" -eq 0 ] && echo "  All tests passed." || exit 1
exit 0
