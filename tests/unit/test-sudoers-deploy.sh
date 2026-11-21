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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
LIB="$REPO/files/opencode-permissions-kit-lib/sh/sudoers-deploy.sh"
TEMPLATE_SRC="$REPO/files/opencode-permissions-kit-lib/templates/sudoers.template"
# Shared harness (issue #394): pass/fail, colors, counters live in
# lib/harness.sh now. The local check() below deliberately SHADOWS the
# harness form -- it suppresses the checked command's output; keep it
# (review #398 a F2: the shadow is intentional, the generic wording was
# false here).
. "$SCRIPT_DIR/lib/harness.sh"

check() {
    _d="$1"
    shift
    # F6 parity with the harness form (review a S2 class sweep, #468):
    # an empty command fails loud instead of vacuously passing through
    # the redirection-only null command.
    if [ "$#" -eq 0 ]; then
        fail "$_d (check: no command given)"
        return
    fi
    if "$@" >/dev/null 2>&1; then pass "$_d"; else fail "$_d"; fi
}

# Loud scratch guard (#441 a B1 / #454 a C1 class): no set -e here -- a
# failed work_new must abort instead of degenerating fixture writes.
WORK="$(work_new)" || {
    echo "sudoers-deploy tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
CONF="$WORK/conf"
SDD="$WORK/sudoers.d"
mkdir -p "$SDD"

# visudo stub: rejects a file containing the marker line REJECT (lets
# individual tests force the validation failure), accepts everything
# else. Counts invocations so the tests can assert it RAN.
VISUDO="$WORK/visudo"
cat >"$VISUDO" <<'EOF'
#!/bin/sh
# test stub: visudo -c -f <file>
[ "$1" = "-c" ] && [ "$2" = "-f" ] && [ $# -eq 3 ] || exit 2
echo run >> "$VISUDO_RUNS"
if grep -q '^REJECT' "$3"; then exit 1; fi
exit 0
EOF
chmod +x "$VISUDO"
VISUDO_RUNS="$WORK/visudo-runs"
export VISUDO_RUNS
: >"$VISUDO_RUNS"

# The template under test: same shape as the shipped one (DEFAULT_USER
# placeholders). The shipped template is used as-is; a reject variant
# renders invalid content via a prepended marker.
TPL="$WORK/sudoers.template"
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
    sudoers_deploy "$TPL" alice
    echo "rc=$?"
)
case "$_sd_out" in *rc=0*) pass "happy path: rc=0" ;; *) fail "happy path: rc (got [$_sd_out])" ;; esac
check "happy path: CONFDIR/sudoers installed" test -f "$CONF/sudoers"
check "happy path: mode 440" sh -c "[ \"\$(stat -c %a \"$CONF/sudoers\")\" = 440 ]"
check "happy path: DEFAULT_USER substituted" grep -q alice "$CONF/sudoers"
check_absent "happy path: placeholder gone" "$CONF/sudoers" -q DEFAULT_USER
check "happy path: sudoers.d symlink" test -L "$SDD/opencode-permissions-kit"
check "happy path: symlink points at CONFDIR/sudoers" \
    sh -c "[ \"\$(readlink \"$SDD/opencode-permissions-kit\")\" = \"$CONF/sudoers\" ]"
check "happy path: visudo ran on the rendered file" test -s "$VISUDO_RUNS"

# --- 1b. the git heal grant line renders (#671) ----------------------------
# The template must carry the heal grant exactly once, RunAs root
# (every other kit grant runs as the opencode user), naming the exact
# heal script path with the any-args wildcard the hooks need (they
# pass the resolved gitdir).
check "git-heal grant: RunAs-root line for the heal script renders" \
    grep -q '^alice ALL=(root) NOPASSWD: /usr/local/lib/opencode-permissions-kit/git-heal/heal-index-head \*$' \
    "$CONF/sudoers"
_gh_grants=$(grep -c 'heal-index-head' "$CONF/sudoers" || true)
if [ "$_gh_grants" = 1 ]; then
    pass "git-heal grant: exactly one heal grant line (#671)"
else
    fail "git-heal grant: expected exactly 1 heal grant line, found $_gh_grants (#671)"
fi

# --- 1c. env posture pinned: env_reset + !setenv (#677 WO-1) ----------------
# The kit's fragment must not lean on sudo's compiled-in defaults for
# the env posture: an admin edit or another sudoers.d fragment flipping
# env_reset (or enabling setenv) would reopen GH_* env smuggling into
# the root heal. Exact-count pins (not bare presence): a duplicated or
# missing Defaults block reddens either way. Note the visudo above is a
# STUB — real syntax validation of the rendered lines happens inside
# the e2e container install legs (the deploy pipeline's visudo,
# sh/sudoers-deploy.sh); these pins only hold the rendered shape.
_envreset=$(grep -c '^Defaults env_reset$' "$CONF/sudoers" || true)
if [ "$_envreset" = 1 ]; then
    pass "env posture: exactly one 'Defaults env_reset' (#677 WO-1)"
else
    fail "env posture: expected 1 'Defaults env_reset', found $_envreset (#677 WO-1)"
fi
_nosetenv=$(grep -c '^Defaults !setenv$' "$CONF/sudoers" || true)
if [ "$_nosetenv" = 1 ]; then
    pass "env posture: exactly one 'Defaults !setenv' (#677 WO-1)"
else
    fail "env posture: expected 1 'Defaults !setenv', found $_nosetenv (#677 WO-1)"
fi
# Raw per the harness absence contract (harness.sh: "RAW, never
# ridden -- a commented-out forbidden line still counts",
# conventions.md "Source-counting pins"): no uppercase SETENV anywhere
# in the fragment -- grant tags AND commented-out sabotage shapes
# count. The template's prose says lowercase "setenv" by contract of
# this pin (#726 a Q2).
check_absent "env posture: no SETENV tag anywhere in the fragment (#726 a Q2)" \
    "$CONF/sudoers" -q SETENV

# --- 1d. env_keep is command-scoped (#679) ---------------------------------
# The keep must ride a Cmnd_Alias whose ONLY member is the wrapper's exec
# target (the real binary under bin/opencode) — the per-rule audit found
# the other grants need none of the four vars. Exact-count pins lock the
# rendered shape; the absence pins reddens any re-globalized keep. The
# absence and member pins run over a CONTINUATION-JOINED view of the
# fragment: alias widening and merged Defaults ride backslash
# continuations, and the physical-line grep stayed green over a two-line
# widened alias (sabotage cycle B, 2026-11-22) — the pins must see the
# LOGICAL line. Commented-out sabotage shapes count too (harness
# absence contract).
_scoped_keep=$(grep -c '^Defaults!OPK_ENV_CMNDS env_keep += "DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME"$' "$CONF/sudoers" || true)
if [ "$_scoped_keep" = 1 ]; then
    pass "env_keep scoping: exactly one Defaults!OPK_ENV_CMNDS keep line (#679)"
else
    fail "env_keep scoping: expected 1 Defaults!OPK_ENV_CMNDS keep line, found $_scoped_keep (#679)"
fi
_alias_line=$(grep -c '^Cmnd_Alias OPK_ENV_CMNDS = /usr/local/lib/opencode-permissions-kit/bin/opencode \*$' "$CONF/sudoers" || true)
if [ "$_alias_line" = 1 ]; then
    pass "env_keep scoping: alias names exactly the wrapper exec target (#679)"
else
    fail "env_keep scoping: expected 1 exact wrapper-only alias line, found $_alias_line (#679)"
fi
sed -e ':a' -e '/\\$/N' -e 's/\\\n[[:space:]]*//' -e 'ta' "$CONF/sudoers" >"$WORK/sudoers-joined"
check_absent "env_keep scoping: no non-command-scoped env_keep Defaults left (#679)" \
    "$WORK/sudoers-joined" -q '^Defaults[^!]*env_keep'
check_absent "env_keep scoping: socket-check NOT in the alias (#679 audit: argv-only)" \
    "$WORK/sudoers-joined" -q 'OPK_ENV_CMNDS = .*socket-check'
check_absent "env_keep scoping: cwd-check NOT in the alias (#679 audit: argv-only)" \
    "$WORK/sudoers-joined" -q 'OPK_ENV_CMNDS = .*cwd-check'
check_absent "env_keep scoping: ddev-as-opencode NOT in the alias (#679 audit: re-derives env)" \
    "$WORK/sudoers-joined" -q 'OPK_ENV_CMNDS = .*ddev-as-opencode'
check_absent "env_keep scoping: heal-index-head NOT in the alias (#679 audit: RunAs-root chown helper)" \
    "$WORK/sudoers-joined" -q 'OPK_ENV_CMNDS = .*heal-index-head'

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
    sudoers_deploy "$TPL" alice
    echo "rc=$?"
)
check "legacy: pre-0.0.10 sudoers.d/opencode removed" test ! -e "$SDD/opencode"

# --- 3. invalid user charset ----------------------------------------------

rm -rf "$CONF"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL" 'bad;name'
    echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "charset: rc=1" ;; *) fail "charset: rc (got [$_sd_out])" ;; esac
check "charset: nothing deployed" test ! -e "$CONF/sudoers"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL" ""
    echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "charset: empty user rejected" ;; *) fail "charset: empty user (got [$_sd_out])" ;; esac
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL" ALL
    echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "charset: ALL rejected (0.0.41f S3 — renders valid sudoers)" ;; *) fail "charset: ALL (got [$_sd_out])" ;; esac
check "charset: ALL deploys nothing" test ! -e "$CONF/sudoers"

# --- 4. missing template ---------------------------------------------------

_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$WORK/does-not-exist" alice
    echo "rc=$?"
)
case "$_sd_out" in *rc=1*) pass "missing template: rc=1" ;; *) fail "missing template: rc (got [$_sd_out])" ;; esac

# --- 5. visudo rejection deploys NOTHING -----------------------------------

rm -rf "$CONF"
rm -f "${SDD:?}/opencode-permissions-kit"
TPL_BAD="$WORK/sudoers-bad.template"
{
    echo "REJECT"
    cat "$TPL"
} >"$TPL_BAD"
_sd_out=$(
    sd_env
    export SD_SUDO SD_VISUDO SD_CONF_DIR SD_SUDOERS_D
    # shellcheck disable=SC2030
    . "$LIB"
    sudoers_deploy "$TPL_BAD" alice 2>&1
    echo "rc=$?"
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

# --- #479 a F18 sweep: sudoers_deploy's mktemp failure names the render ----
# The file-missing arm is loud; a dead TMPDIR must name the interrupted
# sudoers render too (the config.sh #431 family wording). The template
# must EXIST so the pin drives past the file arm into the mktemp arm.
printf 'u-DEFAULT_USER ALL=(ALL) NOPASSWD: /bin/true\n' >"$WORK/f18-template"
SD_RC=0
SD_OUT="$(TMPDIR="$WORK/no-such-tmpdir-f18" sh -c '
    . "$1"
    SD_CONF_DIR="$2/conf" SD_SUDOERS_D="$2/sudoers.d" sudoers_deploy "$2/f18-template" someuser
' _ "$LIB" "$WORK" 2>&1)" || SD_RC=$?
if [ "$SD_RC" -eq 1 ] &&
    printf '%s' "$SD_OUT" | grep -qF 'mktemp failed (is $TMPDIR writable?) — sudoers render NOT applied'; then
    pass "sudoers mktemp failure names the interrupted render (#479 a F18 sweep)"
else
    fail "sudoers mktemp failure must name the render (rc=$SD_RC out=$SD_OUT) (#479 a F18 sweep)"
fi

# --- summary ---------------------------------------------------------------

echo ""
echo "===================================="
echo "  Passed: $passed  Failed: $failures"
[ "$failures" -eq 0 ] && echo "  All tests passed." || exit 1
exit 0
