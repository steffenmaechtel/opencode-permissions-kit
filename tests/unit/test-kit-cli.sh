#!/bin/sh
# Test the CLI dispatcher (files/opencode-permissions-kit-lib/bin/opk).
# Builds a fake library dir with stub scripts, symlinks the dispatcher,
# and checks dispatch, help, error handling, and flag pass-through.
# Run: sh tests/unit/test-kit-cli.sh
set -e
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opk"
HOCORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/handover-core.sh"
OCCORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/openchamber-core.sh"

# Shared harness (issue #394 adoption, #415 ride-along): pass/fail,
# assert_eq, extract_func + the counters live in lib/harness.sh now;
# the work registry (issue #395) owns cleanup — the suite carries no
# trap of its own (a local trap would disarm the harness registry).
# assert_eq -> assert_eq kept the 3-arg shape; the inline PASS/FAIL rows
# became pass/fail calls.
. "$SCRIPT_DIR/lib/harness.sh"

WORK="$(work_new)"

# Fake library with stub scripts recording how they were invoked.
LIB="$WORK/lib"
mkdir -p "$LIB"
# install.conf carries the deployed VERSION stamp (a standalone VERSION file
# is NOT deployed to the library — regression guard for the v0.0.0 display).
# Users must EXIST for the handover tests (the command validates with id);
# the current user/group double as the fake developer and opencode user.
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nVERSION=9.9.9\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$WORK/install.conf"
mkdir -p "$LIB/management"
# The dispatcher's handover arm sources the REAL handover-core.sh since
# the #415 ride-along extraction — without it every handover pin below
# dies on the resolver's loud abort.
mkdir -p "$LIB/sh"
cp "$HOCORE" "$LIB/sh/handover-core.sh"
# openchamber-secure's arm sources the REAL openchamber-core.sh since
# the #415 wave-1 extraction — same coupling as handover above.
cp "$OCCORE" "$LIB/sh/openchamber-core.sh"
for s in status doctor config update uninstall; do
    cat >"$LIB/management/$s.sh" <<EOF
#!/bin/sh
echo "$s:euid=\$(id -u):args=\$*"
EOF
done

# Fake sudo: records invocation, then execs the command unchanged. The
# dispatcher's auto-elevation must go through sudo when not root; with the
# fake, the stub still runs as the current user.
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
cat >"$FAKEBIN/sudo" <<'EOF'
#!/bin/sh
echo "sudo-called" >> "$(dirname "$0")/../sudo-marker"
# Pass through `sudo [-u <user>] <cmd...>`: strip the user hop (-u and
# its argument), exec the rest unchanged. config/update elevate plain;
# ensure-shared hops to the agent user — the stub still runs everything
# as the current user, which is all the dispatch pins need.
while [ "$1" = "-u" ]; do
    shift
    [ "$#" -gt 0 ] && shift
done
exec "$@"
EOF
chmod +x "$FAKEBIN/sudo"
PATH="$FAKEBIN:$PATH"
export PATH

# Dispatch through a symlink like /usr/local/bin does. The dispatcher
# resolves LIBDIR as the parent of its own bin/ location. No sh/ui.sh in
# the fake lib: the dispatcher must fall back to its built-in ui_error
# (stderr) when the library is incomplete.
BIN="$WORK/bin"
mkdir -p "$BIN" "$LIB/bin"
ln -s "$LIB/bin/opk" "$BIN/opk"
cp "$KIT" "$LIB/bin/opk"
chmod +x "$LIB/bin/opk"

run_kit() {
    OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" "$@" 2>/dev/null
}

echo "=== CLI dispatcher tests ==="

# help lists every subcommand
# (#282): the capture is guarded -- a non-zero exit of the probe must
# redden the assert_eq below, never abort this set -e suite mid-run.
_rk_rc=0
out="$(run_kit --help)" || _rk_rc=$?
assert_eq "--help exits 0" "0" "$_rk_rc"
for c in status doctor config update uninstall handover help openchamber-secure ensure-shared; do
    case "$out" in
        *"$c"*)
            pass "--help mentions '$c'"
            ;;
        *)
            fail "--help mentions '$c'"
            ;;
    esac
done
# doctor fix is part of the doctor surface (#313 increment b): the
# two-word phrase must appear (the bare token 'fix' already did)
case "$out" in
    *"doctor fix"*)
        pass "--help mentions 'doctor fix' (#313 increment b)"
        ;;
    *)
        fail "--help mentions 'doctor fix' (#313 increment b)"
        ;;
esac
out_help="$(run_kit help)" || true
assert_eq "help == --help" "$(run_kit --help)" "$out_help"

# version comes from the library VERSION file
case "$out" in
    *"v9.9.9"*)
        pass "version from install.conf stamp"
        ;;
    *)
        fail "version from install.conf stamp (got: $out)"
        ;;
esac

# --version prints just the version, one line (issue #130)
_vk_rc=0
out="$(run_kit --version)" || _vk_rc=$?
assert_eq "--version exits 0" "0" "$_vk_rc"
assert_eq "--version prints 'opk <stamp>'" "opk 9.9.9" "$out"
# No install.conf: fallback stamp, never an error (dev checkouts)
out="$(OPK_INSTALL_CONF="$WORK/no-such.conf" "$BIN/opk" --version 2>/dev/null)" || true
assert_eq "--version without install.conf falls back" "opk 0.0.0" "$out"

# status dispatches without sudo (root test envs: euid matches current)
out="$(run_kit status)" || true
assert_eq "status dispatches" "status:euid=$(id -u):args=" "$out"

# doctor dispatches like status: no sudo, path passed through (#313)
out="$(run_kit doctor /tmp)" || true
assert_eq "doctor dispatches with the path" "doctor:euid=$(id -u):args=/tmp" "$out"
check "doctor dispatches to management/doctor.sh (no sudo hop)" grep -qF 'exec sh "$LIBDIR/management/doctor.sh" "$@"' "$KIT"

# config/update dispatch with args passed through (fake sudo passes them on;
# stubs run as the current user either way)
out="$(run_kit config projects list)" || true
assert_eq "config passes args" "config:euid=$(id -u):args=projects list" "$out"
out="$(run_kit update --yes --refresh)" || true
assert_eq "update passes flags" "update:euid=$(id -u):args=--yes --refresh" "$out"

# upgrade-opencode: binary-only shorthand — injects --yes --only-binary,
# extra flags pass through (issue #24)
out="$(run_kit upgrade-opencode --binary-path /tmp/x)" || true
assert_eq "upgrade-opencode injects --yes --only-binary (flags pass through)" \
    "update:euid=$(id -u):args=--yes --only-binary --binary-path /tmp/x" "$out"

# non-root invocations of config/update go through sudo
if [ "$(id -u)" -ne 0 ]; then
    if [ -f "$WORK/sudo-marker" ]; then
        pass "config/update auto-elevate via sudo"
    else
        fail "config/update auto-elevate via sudo"
    fi
else
    pass "config/update auto-elevate (skipped: test runs as root)"
fi

# uninstall dispatches as the current user (no forced sudo)
out="$(run_kit uninstall --dry-run)" || true
assert_eq "uninstall passes flags" "uninstall:euid=$(id -u):args=--dry-run" "$out"

# --- openchamber-secure (issue #154, Tier 3) -----------------------------------
# Static wiring pins (functional run needs root + /etc — covered by the
# e2e suite instead). The arm's body lives in sh/openchamber-core.sh
# since the #415 wave-1 extraction (#396 accounting: the pins that
# grep'd the arm body in bin/opk re-target the lib; the dispatcher
# pins stay on $KIT). oc_bypass_bin stays in bin/opk (dispatcher-level
# helper): its definition is pinned on $KIT, its USE sites on $OCCORE.
check "openchamber-secure dispatch exists" grep -q '    openchamber-secure)' "$KIT"
check "openchamber-secure auto-elevates with flags intact" grep -qF 'exec sudo sh "$LIBDIR/bin/opk" openchamber-secure "$@"' "$OCCORE"
grep -qF 'mv -f "$_ocp_tmp" /etc/openchamber/policy.json' "$OCCORE" &&
    check "openchamber-secure writes the pin (atomic) + records the opt-in" grep -qF 'mv -f "$_ocp_tmp" /etc/openchamber/policy.json' "$OCCORE" grep -qF 'OPENCHAMBER_POLICY=yes' "$OCCORE"
# 0.0.47a F1: replacing divergent policy content is announced, never silent
check "openchamber-secure announces replacing divergent content (F1)" grep -qF 'diverges from the kit pin — replacing it' "$OCCORE"
# 0.0.47a F3: the kit-symlink exemption helper exists and is used at the
# detection, listing and removal sites
# Comment-strip riders (#261, the #244 g W1 class): commented-out lines
# must not count. Full-line comments only (#244 h W6 residual): a
# trailing comment after a live line still counts.
_ocb_def="$(live_src "$KIT" | grep -c 'oc_bypass_bin' || true)"
check "openchamber-secure's probe helper stays dispatcher-level (#447)" [ "$_ocb_def" -ge 1 ]
_ocb_n="$(live_src "$OCCORE" | grep -c 'oc_bypass_bin' || true)"
check "openchamber-secure exempts kit-owned symlinks (F3)" [ "$_ocb_n" -ge 3 ]
# 0.0.47c C2: every completing path of openchamber-secure ends with the
# restart hint (getent-skip, nothing-found, decline, full run — the
# oc_bypass_bin count precedent; behavioral pinning of the decline path
# would need an interactive ui_confirm, static count is the proxy)
_rh_n="$(live_src "$OCCORE" | grep -c 'restart OpenChamber if it is running' || true)"
check "openchamber-secure prints the restart hint on every completing path (0.0.47c C2)" [ "$_rh_n" -ge 4 ]

# unknown flag for openchamber-secure aborts before elevation (runs as
# non-root with the fake sudo, so the flag check fires first). Direct
# call: run_kit swallows stderr, ui_error writes to stderr.
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" openchamber-secure --bogus 2>&1 >/dev/null || true)"
case "$errout" in
    *"unknown flag"*)
        pass "openchamber-secure rejects unknown flags"
        ;;
    *)
        fail "openchamber-secure rejects unknown flags (got: $errout)"
        ;;
esac

# --- #415 wave-1 extraction wiring: resolver loud abort + pairing guard ----------
# A damaged library (openchamber-core.sh missing) must refuse loud,
# never fall through to "not found" + rc 0 semantics (bin/opk sets no
# set -e); a version-skewed lib (file present, function missing) hits
# the pairing guard with its own cause. Same shape as the #415
# handover wiring block above.
OC_NOLIB="$WORK/oc-nolib"
mkdir -p "$OC_NOLIB/bin" "$OC_NOLIB/sh"
cp "$BIN/opk" "$OC_NOLIB/bin/opk"
_no_rc=0
_no_out="$(OPK_INSTALL_CONF="$WORK/install.conf" "$OC_NOLIB/bin/opk" openchamber-secure --yes 2>&1 >/dev/null)" || _no_rc=$?
if [ "$_no_rc" -ne 0 ] &&
    printf '%s' "$_no_out" | grep -qF "openchamber-core.sh not found"; then
    pass "resolver: a missing openchamber-core.sh refuses loud (#447, #165 class)"
else
    fail "resolver: a missing openchamber-core.sh must refuse loud (rc=$_no_rc got: $_no_out) (#447)"
fi
printf '# stub lib without the function\n' >"$OC_NOLIB/sh/openchamber-core.sh"
_sk_rc=0
_sk_out="$(OPK_INSTALL_CONF="$WORK/install.conf" "$OC_NOLIB/bin/opk" openchamber-secure --yes 2>&1 >/dev/null)" || _sk_rc=$?
if [ "$_sk_rc" -ne 0 ] &&
    printf '%s' "$_sk_out" | grep -qF "version-skewed"; then
    pass "pairing guard: a function-less lib refuses with its own cause (#447)"
else
    fail "pairing guard: a function-less lib must refuse with its own cause (rc=$_sk_rc got: $_sk_out) (#447)"
fi

# (#370 a E3): the bypass-removal prompt defaults to n (the
# conventions' system-change default, agent/conventions.md
# "Interactive prompts"; under the old y default an unattended EOF
# followed the caller's default and REMOVED the files), and the
# fallback ui_confirm header no longer claims "fails closed" (EOF
# follows the caller's default — sh/ui.sh documents the true
# semantics). Comment-strip ridden: a commented-out call must not count.
# The prompt call moved to openchamber-core.sh with the #415 wave-1
# extraction; the fallback ui_confirm header pin below stays on $KIT
# (the fallback helper is dispatcher-level).
if live_src "$OCCORE" | grep -qF 'ui_confirm "Remove them now?" "n"'; then
    pass "bypass-removal prompt defaults to n (#370 a E3)"
else
    fail "bypass-removal prompt defaults to n (#370 a E3)"
fi
# wrap-robust (round a A5): join the extracted lines first -- the old
# single-line grep passed only because the phrase happened to wrap
# mid-comment in bin/opk; a benign reflow would have flipped the pin
# with no semantic change. The joined regex catches the claim in any
# spacing (and the hyphenated spelling).
if printf '%s' "$(sed -n '/^    ui_confirm() {/,/^    }/p' "$KIT" | tr '\n' ' ')" |
    grep -qE 'fails[[:space:]]*-?[[:space:]]*closed'; then
    fail "fallback ui_confirm header states true EOF semantics (#370 a E3)"
else
    pass "fallback ui_confirm header states true EOF semantics (#370 a E3)"
fi

# unknown command fails with exit 1
if run_kit frobnicate >/dev/null 2>&1; then
    fail "unknown command exits non-zero"
else
    pass "unknown command exits non-zero"
fi

# no command fails with exit 1
if run_kit >/dev/null 2>&1; then
    fail "no command exits non-zero"
else
    pass "no command exits non-zero"
fi

# missing script -> clear error, non-zero
rm "${LIB:?}/management/update.sh"
if run_kit update >/dev/null 2>&1; then
    fail "missing script exits non-zero"
else
    pass "missing script exits non-zero"
fi
errout="$("$BIN/opk" update 2>&1 >/dev/null || true)"
case "$errout" in
    *"not found"*)
        pass "missing script names the problem"
        ;;
    *)
        fail "missing script names the problem (got: $errout)"
        ;;
esac

# --- handover: generic ownership switch ------------------------------------
# Validation and --dry-run must work unprivileged and BEFORE any sudo hop.
mkdir -p "$WORK/ho-tree/sub"
: >"$WORK/ho-tree/sub/file"

# no / too few arguments -> usage error
if run_kit handover >/dev/null 2>&1; then
    fail "handover without args exits non-zero"
else
    pass "handover without args exits non-zero"
fi
if run_kit handover me >/dev/null 2>&1; then
    fail "handover without a path exits non-zero"
else
    pass "handover without a path exits non-zero"
fi

# #377 O1 (review #370 a O1): the handover operand gate carries the
# completed /var families (both the exact root and the subpath arm per
# family — presence pin over the system-path case block; the set-level
# writer-parity tripwire lives in test-project-paths.sh).
_ho377_block=$(sed -n '/case "\$_ho_np" in/,/hand over project trees/p' "$HOCORE")
_ho377_n=0
for _ho377_fam in /var/backups /var/opt /var/crash /var/local /var/lock /var/account /var/games /var/run /var/yp; do
    printf '%s\n' "$_ho377_block" | grep -qF "$_ho377_fam |" &&
        printf '%s\n' "$_ho377_block" | grep -qF "$_ho377_fam/*" &&
        _ho377_n=$((_ho377_n + 1))
done
if [ "$_ho377_n" -eq 9 ]; then
    pass "handover gate: all nine completed /var families blocked (#377 O1, pr-00429 a A1)"
else
    fail "handover gate: only $_ho377_n/9 new /var families present (#377 O1, pr-00429 a A1)"
fi

# (#370 a E2): --dry-run is NOT an operand — `handover me --dry-run`
# (a forgotten path) passed the arity gate ($#=2) and every consumer
# loop skipped the flag: silent rc 0, nothing printed, a forgotten path
# read as a clean dry run. Refuse loudly instead.
_e2_rc=0
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me --dry-run 2>&1 >/dev/null)" || _e2_rc=$?
if [ "$_e2_rc" -ne 0 ] &&
    printf '%s' "$errout" | grep -qF "need at least one path"; then
    pass "handover me --dry-run without a path refused (#370 a E2)"
else
    fail "handover me --dry-run without a path refused (rc=$_e2_rc got: $errout) (#370 a E2)"
fi

# unknown target -> usage error naming the choices (hermetic: explicit
# install.conf — CI runners have no /etc/opencode-permissions-kit)
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover nobody "$WORK/ho-tree" 2>&1 >/dev/null || true)"
case "$errout" in
    *"me or opencode"*)
        pass "handover rejects unknown target"
        ;;
    *)
        fail "handover rejects unknown target (got: $errout)"
        ;;
esac

# nonexistent path -> error
if run_kit handover me "$WORK/does-not-exist" >/dev/null 2>&1; then
    fail "handover rejects nonexistent paths"
else
    pass "handover rejects nonexistent paths"
fi

# system roots, their SUBPATHS, and whole home directories are refused
# (0.0.39b S2: /etc/apache2 used to pass the exact-match blocklist)
for _bad in / /usr /etc /var "/home/$(id -un)" /etc/apache2 /usr/local/foo /var/log /var/lib/docker; do
    errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$_bad" 2>&1 >/dev/null || true)"
    case "$errout" in
        *"refusing"*)
            pass "handover refuses $_bad"
            ;;
        *)
            fail "handover refuses $_bad (got: $errout)"
            ;;
    esac
done

# slash-terminated operands are refused (0.0.44a V2): [ -L "x/" ] is FALSE
# while chown -R -h and find x/ both act on the link's target — the symlink
# gate cannot see through trailing slashes, so the operand FORMS are
# refused at validation (x/, x//, x/., link/ alike).
for _slashed in "$WORK/ho-tree/sub/" "$WORK/ho-tree//" "$WORK/ho-tree/."; do
    errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$_slashed" 2>&1 >/dev/null || true)"
    case "$errout" in
        *"slash/dotdot path form"*)
            pass "handover refuses slash form $_slashed"
            ;;
        *)
            fail "handover refuses slash form $_slashed (got: $errout)"
            ;;
    esac
done
# mid single-dot form (0.0.45c S7): "x/./y" passed the filter while
# [ -L "x/./y" ] is blind to a symlinked INTERMEDIATE component — the
# handover would run through the link instead of refusing it.
for _middot in "$WORK/ho-tree/./sub" "$WORK/ho-tree/sub/./file"; do
    errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$_middot" 2>&1 >/dev/null || true)"
    case "$errout" in
        *"slash/dotdot path form"*)
            pass "handover refuses mid-dot form $_middot (S7)"
            ;;
        *)
            fail "handover refuses mid-dot form $_middot (S7, got: $errout)"
            ;;
    esac
done
# dotdot forms resolve through a link to its target's PARENT (0.0.44b
# W3): [ -L "x/.." ] is false and realpath follows the link — the same
# gate-blind class as trailing slashes.
ln -s "$WORK/ho-tree" "$WORK/ho-link"
for _dotdot in "$WORK/ho-link/.." "$WORK/ho-tree/sub/../../ho-tree" "$WORK/ho-tree/sub/../sub"; do
    errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$_dotdot" 2>&1 >/dev/null || true)"
    case "$errout" in
        *"slash/dotdot path form"*)
            pass "handover refuses dotdot form $_dotdot (W3)"
            ;;
        *)
            fail "handover refuses dotdot form $_dotdot (W3, got: $errout)"
            ;;
    esac
done
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$WORK/ho-link/" 2>&1 >/dev/null || true)"
case "$errout" in
    *"slash/dotdot path form"*)
        pass "handover refuses symlink-with-slash before any gate"
        ;;
    *)
        fail "handover refuses symlink-with-slash before any gate (got: $errout)"
        ;;
esac

# --dry-run: plan only, no changes, no sudo, exit 0
rm -f "${WORK:?}/sudo-marker"
_hd_rc=0
out="$(run_kit handover me "$WORK/ho-tree" --dry-run)" || _hd_rc=$?
assert_eq "handover --dry-run exits 0" "0" "$_hd_rc"
case "$out" in
    *"would hand over: $WORK/ho-tree -> $(id -un):$(id -gn)"*)
        pass "handover --dry-run prints the plan (user:group)"
        ;;
    *)
        fail "handover --dry-run prints the plan (got: $out)"
        ;;
esac
if [ -f "$WORK/sudo-marker" ]; then
    fail "handover --dry-run needs no sudo"
else
    pass "handover --dry-run needs no sudo"
fi

# real run (no --dry-run): elevates via sudo. With the FAKE sudo it cannot
# elevate — the loop guard must stop the re-entry instead of recursing.
rm -f "${WORK:?}/sudo-marker"
if [ "$(id -u)" -ne 0 ]; then
    errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$WORK/ho-tree" 2>&1 >/dev/null || true)"
    if [ -f "$WORK/sudo-marker" ]; then
        pass "handover elevates via sudo"
    else
        fail "handover elevates via sudo"
    fi
    case "$errout" in
        *"did not elevate"*)
            pass "handover loop guard stops non-elevating sudo"
            ;;
        *)
            fail "handover loop guard stops non-elevating sudo (got: $errout)"
            ;;
    esac
else
    # test env is root: the real chown runs; the tree must end up owned by
    # the conf user with group write access.
    out="$(run_kit handover opencode "$WORK/ho-tree")" || true
    _own=$(stat -c '%U:%G' "$WORK/ho-tree/sub/file")
    assert_eq "handover chowns recursively (root env)" "$(id -un):$(id -gn)" "$_own"
    case "$out" in
        *"handover: $WORK/ho-tree"*)
            pass "handover reports each path (root env)"
            ;;
        *)
            fail "handover reports each path (root env, got: $out)"
            ;;
    esac
fi

# 0.0.45c S4 / 0.0.45d W1 direction-aware order pins: the executor is
# per-direction since W1 — `handover opencode` (dev->agent) chmods while
# the tree is dev-owned and hands over LAST; `handover me` (agent->dev)
# re-owns FIRST (after chown -R -h no entry is agent-owned, so the chmod
# pass races no one) and grants group write second. The opencode branch
# comes first in the file; each executor line appears exactly twice.
# Static line-number pins (the race itself is not unit-pinnable);
# reverting an order inside a branch swaps its numbers, collapsing back
# to the old single unconditional executor removes the second match.
# Comment-strip rider on the extraction legs too (#261): a commented-out
# executor line must not be extracted — sed substitutes (never deletes),
# so the grep -n numbers still match the real file.
_ho_chmod_lns=$(live_src "$HOCORE" | grep -n 'find "\$_ho_a" ! -type l -exec chmod g+w' | cut -d: -f1)
_ho_chown_lns=$(live_src "$HOCORE" | grep -n 'chown -R -h "\$_ho_user:\$_ho_group" "\$_ho_a"' | cut -d: -f1)
# Guarded counts (#260, the #244 f W1 class — sites beyond the issue's
# list, found by this wave's sweep): an executor line vanishing from the
# kit script leaves grep -c . counting zero non-empty lines, rc 1 —
# under set -e the bare assignment aborted before the order FAIL.
_ho_nchmod=$(printf '%s\n' "$_ho_chmod_lns" | grep -c . || true)
_ho_nchown=$(printf '%s\n' "$_ho_chown_lns" | grep -c . || true)
_ho_c1=$(printf '%s\n' "$_ho_chmod_lns" | head -1)
_ho_c2=$(printf '%s\n' "$_ho_chmod_lns" | tail -1)
_ho_h1=$(printf '%s\n' "$_ho_chown_lns" | head -1)
_ho_h2=$(printf '%s\n' "$_ho_chown_lns" | tail -1)
if [ "$_ho_nchmod" = 2 ] && [ "$_ho_nchown" = 2 ] &&
    [ "$_ho_c1" -lt "$_ho_h1" ] && [ "$_ho_h2" -lt "$_ho_c2" ] &&
    [ "$_ho_c1" -lt "$_ho_c2" ] && [ "$_ho_h1" -lt "$_ho_h2" ]; then
    pass "handover: opencode branch chmod-before-chown, me branch chown-before-chmod (S4+W1)"
else
    fail "handover: per-direction order violated (S4+W1: chmod=$_ho_chmod_lns chown=$_ho_chown_lns)"
fi

# W1 behavioral pin: run the REAL extracted executor loop per direction
# with shims that log every chown/chmod invocation — the log order pins
# the execution order causally (line-number statics above cannot see a
# rewired branch body). chown is shimmed to log+noop (unprivileged env,
# ownership itself is pinned by the root-env block above); chmod logs
# the operand's CURRENT owner at invocation time and then really runs.
_ho_pin_dir="$(work_new)"
mkdir -p "$_ho_pin_dir/bin" "$_ho_pin_dir/tree"
echo keep >"$_ho_pin_dir/tree/file"
printf '#!/bin/sh\necho "chown $*" >> "$HO_LOG"\nexit 0\n' >"$_ho_pin_dir/bin/chown"
printf '#!/bin/sh\nfor _a do case "$_a" in -*) ;; *) [ -e "$_a" ] && echo "chmod $(stat -c %%U "$_a" 2>/dev/null || echo ?) $_a" >> "$HO_LOG" ;; esac; done\nexec /usr/bin/chmod "$@"\n' >"$_ho_pin_dir/bin/chmod"
chmod +x "$_ho_pin_dir/bin/chown" "$_ho_pin_dir/bin/chmod"
_ho_extract() {
    # handover-core.sh since the #415 ride-along: the executor loop is
    # function-body level (4-space base), $HOCORE the subject.
    sed -n '/^    _ho_rc=0$/,/^    done$/p' "$HOCORE"
}
for _ho_tgt in opencode me; do
    rm -f "${_ho_pin_dir:?}/log"
    HO_LOG="$_ho_pin_dir/log" _ho_target="$_ho_tgt" _ho_user="$(id -un)" \
    _ho_group="$(id -gn)" _ho_rc=0 \
    PATH="$_ho_pin_dir/bin:$PATH" sh -c "$(
        printf 'ui_info() { :; }\nui_error() { echo "$1" >&2; }\nset -- "%s"\n' "${_ho_pin_dir}/tree"
        extract_func "$HOCORE" _ho_chain_sane
        _ho_extract
    )" >/dev/null 2>&1 || true
    _ho_first_chown=$(grep -n '^chown ' "$_ho_pin_dir/log" 2>/dev/null | head -1 | cut -d: -f1)
    _ho_first_chmod=$(grep -n '^chmod ' "$_ho_pin_dir/log" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$_ho_first_chown" ] && [ -n "$_ho_first_chmod" ]; then
        if [ "$_ho_tgt" = opencode ] && [ "$_ho_first_chmod" -lt "$_ho_first_chown" ]; then
            pass "handover opencode: chmod pass executes before the chown hand-over (W1)"
        elif [ "$_ho_tgt" = me ] && [ "$_ho_first_chown" -lt "$_ho_first_chmod" ]; then
            pass "handover me: chown hand-over executes before the chmod pass (W1)"
        else
            fail "handover $_ho_tgt: execution order wrong (chown=$_ho_first_chown chmod=$_ho_first_chmod, W1)"
        fi
    else
        fail "handover $_ho_tgt: executor did not run both passes (chown=$_ho_first_chown chmod=$_ho_first_chmod, W1)"
    fi
done

# --- #422: exec-time component walk before the executors ----------------------------
# The leaf [ -L ] gates cannot see a PARENT swapped for a symlink since
# validation — _ho_chain_sane walks every component of the operand's
# chain (realpath -s: lexical normalize only) and the executor loop
# skips loud on the first link. Three pins: the walker itself, the
# dry-run preview (0.0.39i F4 parity: what --dry-run announces must
# match the real run), and the loop's refuse through the extracted
# executor (nothing reaches chown/chmod).
HO_WALK="$WORK/ho-walk"
mkdir -p "$HO_WALK/real/tree"
: >"$HO_WALK/real/tree/file"
ln -s "$HO_WALK/real" "$HO_WALK/link-parent"
# walker, direct drive (the lib is definitions-only — sourcing it into
# the suite shell defines handover_core/_ho_chain_sane, never called)
. "$HOCORE"
check "chain walk: a clean absolute chain passes (#422)" \
    _ho_chain_sane "$HO_WALK/real/tree"
check "chain walk: a symlinked parent component refuses (#422)" \
    sh -c '! _ho_chain_sane "$1"' _ "$HO_WALK/link-parent/tree"
check "chain walk: relative operands resolve against the cwd (#422)" \
    sh -c '. "$1" && cd "$2/real" && _ho_chain_sane tree' _ "$HOCORE" "$HO_WALK"
check "chain walk: spaced paths survive the string-op walk (#422)" \
    sh -c '. "$1" && mkdir -p "$2/spaced root" && _ho_chain_sane "$2/spaced root"' _ "$HOCORE" "$HO_WALK"
# The realpath-absent fallback (#437 a C4): a PATH-shadowed FAILING
# realpath drives the || printf arm — the walk runs on the raw prefixed
# form and still gates the linked parent (and still passes the clean
# chain; string-op walk needs no externals beyond the probed realpath).
_nrb="$WORK/norealpath-bin"
mkdir -p "$_nrb"
printf '#!/bin/sh\nexit 1\n' >"$_nrb/realpath"
chmod +x "$_nrb/realpath"
check "chain walk: realpath-absent fallback still refuses a linked parent (#437 a C4)" \
    sh -c '! (. "$1" && PATH="$2" _ho_chain_sane "$3")' _ "$HOCORE" "$_nrb" "$HO_WALK/link-parent/tree"
check "chain walk: realpath-absent fallback passes a clean chain (#437 a C4)" \
    sh -c '. "$1" && PATH="$2" _ho_chain_sane "$3"' _ "$HOCORE" "$_nrb" "$HO_WALK/real/tree"

# dry-run previews the chain refuse like the leaf refuse (F4 parity)
out="$(run_kit handover me "$HO_WALK/link-parent/tree" --dry-run)"
case "$out" in
    *"would refuse: '$HO_WALK/link-parent/tree' crosses a symlinked path component"*)
        pass "handover --dry-run previews the chain refuse (#422, 0.0.39i F4 parity)"
        ;;
    *)
        fail "handover --dry-run must preview the chain refuse (#422, got: $out)"
        ;;
esac

# the executor loop refuses the operand; nothing reaches the shims
rm -f "${_ho_pin_dir:?}/log"
HO_LOG="$_ho_pin_dir/log" _ho_target=me _ho_user="$(id -un)" \
_ho_group="$(id -gn)" _ho_rc=0 \
PATH="$_ho_pin_dir/bin:$PATH" sh -c "$(
    printf 'ui_info() { :; }\nui_error() { echo "$1" >&2; }\nset -- "%s"\n' "$HO_WALK/link-parent/tree"
    extract_func "$HOCORE" _ho_chain_sane
    _ho_extract
)" >/dev/null 2>"$WORK/ho-walk-loop.err" || true
if [ ! -e "$_ho_pin_dir/log" ] &&
    grep -qF "crosses a symlinked path component" "$WORK/ho-walk-loop.err"; then
    pass "executor loop: a symlinked parent refuses the operand loud, no chown/chmod runs (#422)"
else
    fail "executor loop: a symlinked parent must refuse loud without running the executors (#422)"
fi

# --- #415 extraction wiring: resolver loud abort + pairing guard --------------------
# A damaged library (handover-core.sh missing) must refuse loud, never
# fall through to "not found" + rc 0 semantics (bin/opk sets no set -e);
# a version-skewed lib (file present, function missing) hits the pairing
# guard with its own cause.
HO_NOLIB="$WORK/ho-nolib"
mkdir -p "$HO_NOLIB/bin" "$HO_NOLIB/sh"
cp "$BIN/opk" "$HO_NOLIB/bin/opk"
_no_rc=0
_no_out="$(OPK_INSTALL_CONF="$WORK/install.conf" "$HO_NOLIB/bin/opk" handover me "$WORK" 2>&1 >/dev/null)" || _no_rc=$?
if [ "$_no_rc" -ne 0 ] &&
    printf '%s' "$_no_out" | grep -qF "handover-core.sh not found"; then
    pass "resolver: a missing handover-core.sh refuses loud (#415, #165 class)"
else
    fail "resolver: a missing handover-core.sh must refuse loud (rc=$_no_rc got: $_no_out) (#415)"
fi
printf '# stub lib without the function\n' >"$HO_NOLIB/sh/handover-core.sh"
_sk_rc=0
_sk_out="$(OPK_INSTALL_CONF="$WORK/install.conf" "$HO_NOLIB/bin/opk" handover me "$WORK" 2>&1 >/dev/null)" || _sk_rc=$?
if [ "$_sk_rc" -ne 0 ] &&
    printf '%s' "$_sk_out" | grep -qF "version-skewed"; then
    pass "pairing guard: a function-less lib refuses with its own cause (#415)"
else
    fail "pairing guard: a function-less lib must refuse with its own cause (rc=$_sk_rc got: $_sk_out) (#415)"
fi

rm -rf "${_ho_pin_dir:?}"

# --- handover me: declared container-tree warning (#352 / #313 phase 3) ---------
# Advisory warning when the takeover covers -- or sits inside -- a tree
# the project declares in its opk.json. Fires in the UNPRIVILEGED phase
# (so --dry-run previews it, and the sudo re-entry does not repeat it).
# Policy resolution is WALK-UP discovery since phase 4 (#353): from the
# cwd upward, the NEAREST opk.json wins — the same shared resolution
# site doctor's default uses (sh/path-sane.sh's opk_policy_root, one
# implementation for both commands, not per-command copies).
HO_PROJ="$WORK/ho-proj"
mkdir -p "$HO_PROJ/tree/sub" "$HO_PROJ/other"
: >"$HO_PROJ/tree/sub/file"
printf '{"version":1,"containerTrees":[{"path":"tree","note":"build outputs"}]}\n' \
    >"$HO_PROJ/opk.json"
# The warning's policy resolution lives in sh/path-sane.sh since #353 —
# the fake lib above ships only bin/opk + handover-core.sh + management
# stubs, so the leaf lib must be present or every pin below exercises
# the degraded strict-cwd fallback instead of the walk-up
mkdir -p "$LIB/sh"
cp "$(dirname "$(dirname "$KIT")")/sh/path-sane.sh" "$LIB/sh/path-sane.sh"
_ho_warn_run() { # <cwd> <args...> — opk handover from <cwd>, output+rc
    _hw_dir="$1"
    shift
    (
        cd "$_hw_dir" &&
            OPK_INSTALL_CONF="$WORK/install.conf" NO_COLOR=1 "$BIN/opk" handover "$@" 2>&1
    )
}

# operand COVERS the declared tree (the #312 `handover me .` re-poison)
_hw_rc=0
out="$(_ho_warn_run "$HO_PROJ" me . --dry-run)" || _hw_rc=$?
assert_eq "warning run: dry-run still exits 0" "0" "$_hw_rc"
if printf '%s' "$out" | grep -qF "takes back the declared container tree 'tree'" &&
    printf '%s' "$out" | grep -qF "expect a clean rebuild of its outputs"; then
    pass "handover me . warns about the declared tree it covers"
else
    fail "handover me . warns about the declared tree it covers (got: $out)"
fi

# operand INSIDE the declared tree (partial takeover re-poisons too)
out="$(_ho_warn_run "$HO_PROJ" me tree/sub --dry-run)" || true
case "$out" in
    *"takes back the declared container tree 'tree'"*)
        pass "handover me inside a declared tree warns too"
        ;;
    *)
        fail "handover me inside a declared tree warns too (got: $out)"
        ;;
esac

# sibling operand: no overlap, no warning
out="$(_ho_warn_run "$HO_PROJ" me other --dry-run)" || true
case "$out" in
    *"takes back the declared container tree"*)
        fail "sibling takeover does not warn"
        ;;
    *)
        pass "sibling takeover does not warn"
        ;;
esac

# the remedy direction never warns (handover opencode IS the fix)
out="$(_ho_warn_run "$HO_PROJ" opencode tree --dry-run)" || true
case "$out" in
    *"takes back the declared container tree"*)
        fail "handover opencode does not warn (it is the remedy)"
        ;;
    *)
        pass "handover opencode does not warn (it is the remedy)"
        ;;
esac

# walk-up (#353): a policy in a PARENT of the cwd IS read -- run from
# tree/, the project policy sits one level above and the operand sub is
# inside its declared tree. v1 stayed strict-cwd here; phase 4 flipped
# the pin (the flipped direction is the discrimination: strict-cwd
# again and this goes red)
out="$(_ho_warn_run "$HO_PROJ/tree" me sub --dry-run)" || true
if printf '%s' "$out" | grep -qF "takes back the declared container tree 'tree'"; then
    pass "walk-up: parent-dir policy warns (phase 4 discovery)"
else
    fail "walk-up: parent-dir policy warns (phase 4 discovery, got: $out)"
fi

# nearest wins (#353): a NESTED opk.json shadows the parent's — from
# tree/sub/ with its own (non-overlapping) policy, the parent's 'tree'
# declaration must NOT warn; delete the nested file and the same run
# warns through the parent (the pair discriminates in both directions).
# Operand 'file' overlaps NEITHER 'elsewhere' (the nested declaration)
# nor anything else -- a 'me .' here would cover every nested tree by
# definition and warn through both policies
printf '{"containerTrees":["elsewhere"]}\n' >"$HO_PROJ/tree/sub/opk.json"
out="$(_ho_warn_run "$HO_PROJ/tree/sub" me file --dry-run)" || true
if printf '%s' "$out" | grep -qF "takes back the declared container tree"; then
    fail "nearest wins: nested policy shadows the parent (no warn)"
else
    pass "nearest wins: nested policy shadows the parent (no warn)"
fi
rm -f "${HO_PROJ:?}/tree/sub/opk.json"
out="$(_ho_warn_run "$HO_PROJ/tree/sub" me file --dry-run)" || true
if printf '%s' "$out" | grep -qF "takes back the declared container tree 'tree'"; then
    pass "nearest gone: the parent policy warns again"
else
    fail "nearest gone: the parent policy warns again (got: $out)"
fi

# degraded lib (L1 pin for the #353 fallback): path-sane.sh missing —
# the dispatcher must keep working and the warning falls back to v1
# strict-cwd (a SUBSET: it then only sees a policy in the cwd itself;
# the parent policy here must NOT warn). A missing leaf lib may never
# crash a takeover preview
HO_DEG="$WORK/ho-degraded-lib"
mkdir -p "$HO_DEG/bin" "$HO_DEG/sh"
cp "$BIN/opk" "$HO_DEG/bin/opk"
cp "$(dirname "$(dirname "$KIT")")/sh/ui.sh" "$HO_DEG/sh/ui.sh"
# handover-core.sh rides the degraded fixture too (the arm sources it
# since the #415 extraction); path-sane.sh stays ABSENT — that absence
# is the pin's subject (strict-cwd fallback).
cp "$(dirname "$(dirname "$KIT")")/sh/handover-core.sh" "$HO_DEG/sh/handover-core.sh"
(
    cd "$HO_PROJ/tree" &&
        OPK_INSTALL_CONF="$WORK/install.conf" NO_COLOR=1 \
            "$HO_DEG/bin/opk" handover me sub --dry-run 2>&1
) >"$WORK/ho-deg.log" || true
deg_out="$(cat "$WORK/ho-deg.log")"
if printf '%s' "$deg_out" | grep -qF "would hand over" &&
    ! printf '%s' "$deg_out" | grep -qF "takes back the declared container tree"; then
    pass "degraded lib: strict-cwd fallback, handover preview intact"
else
    fail "degraded lib: strict-cwd fallback, handover preview intact (got: $deg_out)"
fi
rm -rf "${HO_DEG:?}" "${WORK:?}/ho-deg.log"

# broken opk.json: the advisory read fails loudly (warn row), the
# handover itself proceeds -- a broken policy file never blocks a takeover
printf '{oops\n' >"$HO_PROJ/opk.json"
out="$(_ho_warn_run "$HO_PROJ" me . --dry-run)" || true
if printf '%s' "$out" | grep -qF "is unreadable -- declared-tree warning skipped" &&
    printf '%s' "$out" | grep -qF "would hand over"; then
    pass "broken opk.json: warn-skip row, handover proceeds"
else
    fail "broken opk.json: warn-skip row, handover proceeds (got: $out)"
fi

# belt discrimination (#356 a A4, V1's recipe): a declared path that
# would MATCH the operand when unbelted. Policy "../tree" read from cwd
# $HO_PROJ/tree resolves (unbelted) to $HO_PROJ/tree, which CONTAINS the
# operand tree/sub -- with the belt it is skipped and announced; delete
# the belt and this pin goes red through the appearing warn row (the
# old ../escape pin was byte-identical with the belt deleted).
printf '{"containerTrees":["../tree"]}\n' >"$HO_PROJ/tree/opk.json"
out="$(_ho_warn_run "$HO_PROJ/tree" me sub --dry-run)" || true
if printf '%s' "$out" | grep -qF "takes back the declared container tree"; then
    fail "belt skips the unbelted-match path ../tree (no warn)"
else
    pass "belt skips the unbelted-match path ../tree (no warn)"
fi
case "$out" in
    *"declared path '../tree' skipped -- unusable form"*)
        pass "belt skip is announced, never silent (#356 a C7)"
        ;;
    *)
        fail "belt skip is announced, never silent (#356 a C7, got: $out)"
        ;;
esac

# a top-level non-dict opk.json (the natural "paste a list" mistake)
# takes the same warn row as broken JSON (#356 a A3) -- never a silent
# skip
printf '["tree","other"]\n' >"$HO_PROJ/opk.json"
out="$(_ho_warn_run "$HO_PROJ" me tree/sub --dry-run)" || true
if printf '%s' "$out" | grep -qF "is unreadable -- declared-tree warning skipped" &&
    printf '%s' "$out" | grep -qF "would hand over"; then
    pass "non-dict opk.json: warn row + handover proceeds (#356 a A3)"
else
    fail "non-dict opk.json: warn row + handover proceeds (got: $out)"
fi

# a control character inside a declared path (JSON \n) is a shape
# doctor's validator rejects -- the advisory reader refuses the policy
# instead of letting newline-split fragments reach the matching loop
# (#356 a B3)
printf '{"containerTrees":["tr\\nnee"]}\n' >"$HO_PROJ/opk.json"
out="$(_ho_warn_run "$HO_PROJ" me tree/sub --dry-run)" || true
if printf '%s' "$out" | grep -qF "is unreadable -- declared-tree warning skipped" &&
    printf '%s' "$out" | grep -qF "would hand over"; then
    pass "newline-in-path policy: warn row, no fragment matching (#356 a B3)"
else
    fail "newline-in-path policy: warn row, no fragment matching (got: $out)"
fi

# the OPK_HANDOVER_ROOT=1 re-entry skip arm (#356 a A9): the root pass
# must not repeat the unprivileged warning -- same covering scenario,
# env-armed, no warn row
printf '{"containerTrees":["tree"]}\n' >"$HO_PROJ/opk.json"
out="$(
    cd "$HO_PROJ" &&
        OPK_HANDOVER_ROOT=1 OPK_INSTALL_CONF="$WORK/install.conf" NO_COLOR=1 \
            "$BIN/opk" handover me . --dry-run 2>&1
)" || true
if printf '%s' "$out" | grep -qF "takes back the declared container tree"; then
    fail "root re-entry does not repeat the warning (#356 a A9)"
else
    pass "root re-entry does not repeat the warning (#356 a A9)"
fi

# --- ensure-shared: short heal wrapper (issue #159) ----------------------------
# The real helper (bin/ddev-as-opencode) is stubbed with an argument
# recorder — this suite pins dispatch, validation and the sudo hop; the
# heal itself is pinned by test-ddev-as-opencode.sh.
mkdir -p "$WORK/es-proj/.ddev"
cat >"$WORK/es-helper-master" <<'EOF'
#!/bin/sh
echo "args=$*" >> "$ES_MARKER"
exit 0
EOF
cp "$WORK/es-helper-master" "$LIB/bin/ddev-as-opencode"
chmod +x "$LIB/bin/ddev-as-opencode"
export ES_MARKER="$WORK/es-marker"
# Second conf: OPENCODE_USER is an existing user that is never the current
# one (root or not) — forces the sudo -u hop.
printf 'DEFAULT_USER=%s\nOPENCODE_USER=nobody\nOPENCODE_GROUP=%s\nVERSION=9.9.9\n' \
    "$(id -un)" "$(id -gn)" >"$WORK/install-nobody.conf"

# explicit dir, agent user == current user (fake conf): direct call, no sudo
rm -f "${WORK:?}/sudo-marker"
: >"$WORK/es-marker"
_es_rc=0
out="$(run_kit ensure-shared "$WORK/es-proj/.ddev" 2>&1)" || _es_rc=$?
assert_eq "ensure-shared exits 0" "0" "$_es_rc"
case "$out" in
    *"group-write re-asserted on $WORK/es-proj/.ddev"*)
        pass "ensure-shared reports success"
        ;;
    *)
        fail "ensure-shared reports success (got: $out)"
        ;;
esac
assert_eq "ensure-shared passes the dir to the helper" \
    "args=--opk-ensure-shared $WORK/es-proj/.ddev" "$(tail -1 "$WORK/es-marker")"
if [ -f "$WORK/sudo-marker" ]; then
    fail "ensure-shared needs no sudo as the agent user"
else
    pass "ensure-shared needs no sudo as the agent user"
fi

# no argument: defaults to ./.ddev from the current directory
: >"$WORK/es-marker"
(cd "$WORK/es-proj" && OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" ensure-shared >/dev/null 2>&1)
assert_eq "ensure-shared defaults to ./.ddev" \
    "args=--opk-ensure-shared $WORK/es-proj/.ddev" "$(tail -1 "$WORK/es-marker")"

# nonexistent dir -> loud usage error BEFORE any sudo hop (nobody conf:
# the happy path would elevate, the error path must not)
rm -f "${WORK:?}/sudo-marker"
errout="$(OPK_INSTALL_CONF="$WORK/install-nobody.conf" "$BIN/opk" ensure-shared "$WORK/does-not-exist" 2>&1 >/dev/null || true)"
case "$errout" in
    *"no such directory"*)
        pass "ensure-shared rejects nonexistent dirs"
        ;;
    *)
        fail "ensure-shared rejects nonexistent dirs (got: $errout)"
        ;;
esac
if [ -f "$WORK/sudo-marker" ]; then
    fail "ensure-shared validates before the sudo hop"
else
    pass "ensure-shared validates before the sudo hop"
fi

# more than one argument -> usage error
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" ensure-shared a b 2>&1 >/dev/null || true)"
case "$errout" in
    *"exactly one directory"*)
        pass "ensure-shared rejects extra arguments"
        ;;
    *)
        fail "ensure-shared rejects extra arguments (got: $errout)"
        ;;
esac

# no install.conf / no OPENCODE_USER -> loud error, no elevation
errout="$(OPK_INSTALL_CONF="$WORK/no-such.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 >/dev/null || true)"
case "$errout" in
    *"is the kit installed"*)
        pass "ensure-shared names a missing install.conf"
        ;;
    *)
        fail "ensure-shared names a missing install.conf (got: $errout)"
        ;;
esac
printf 'DEFAULT_USER=%s\nVERSION=9.9.9\n' "$(id -un)" >"$WORK/install-nouser.conf"
errout="$(OPK_INSTALL_CONF="$WORK/install-nouser.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 >/dev/null || true)"
case "$errout" in
    *"no OPENCODE_USER"*)
        pass "ensure-shared names a missing OPENCODE_USER"
        ;;
    *)
        fail "ensure-shared names a missing OPENCODE_USER (got: $errout)"
        ;;
esac

# missing helper -> loud error
rm "${LIB:?}/bin/ddev-as-opencode"
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 >/dev/null || true)"
case "$errout" in
    *"is the kit installed"*)
        pass "ensure-shared names a missing helper"
        ;;
    *)
        fail "ensure-shared names a missing helper (got: $errout)"
        ;;
esac
cp "$WORK/es-helper-master" "$LIB/bin/ddev-as-opencode"
chmod +x "$LIB/bin/ddev-as-opencode"

# different agent user (nobody): hops through sudo -u, args intact
rm -f "${WORK:?}/sudo-marker"
: >"$WORK/es-marker"
_esn_rc=0
out="$(OPK_INSTALL_CONF="$WORK/install-nobody.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1)" || _esn_rc=$?
assert_eq "ensure-shared (sudo path) exits 0" "0" "$_esn_rc"
assert_eq "ensure-shared (sudo path) passes the dir to the helper" \
    "args=--opk-ensure-shared $WORK/es-proj/.ddev" "$(tail -1 "$WORK/es-marker")"
if [ -f "$WORK/sudo-marker" ]; then
    pass "ensure-shared hops to the agent user via sudo -u"
else
    fail "ensure-shared hops to the agent user via sudo -u"
fi

# failing sudo: loud error naming the long-form fallback (fail-loud pin —
# the helper itself never fails, so a swallowed sudo failure would look
# like a successful heal)
FAILBIN="$WORK/failbin"
mkdir -p "$FAILBIN"
printf '#!/bin/sh\nexit 1\n' >"$FAILBIN/sudo"
chmod +x "$FAILBIN/sudo"
_es_rc=0
PATH="$FAILBIN:$PATH" OPK_INSTALL_CONF="$WORK/install-nobody.conf" \
    "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" >/dev/null 2>&1 || _es_rc=$?
if [ "$_es_rc" -ne 0 ]; then
    pass "ensure-shared exits non-zero when sudo fails"
else
    fail "ensure-shared exits non-zero when sudo fails"
fi
errout="$(PATH="$FAILBIN:$PATH" OPK_INSTALL_CONF="$WORK/install-nobody.conf" \
    "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 || true)"
case "$errout" in
    *"could not run"*)
        pass "ensure-shared reports the failed heal"
        ;;
    *)
        fail "ensure-shared reports the failed heal (got: $errout)"
        ;;
esac
case "$errout" in
    *"--opk-ensure-shared"*)
        pass "ensure-shared prints the long-form fallback"
        ;;
    *)
        fail "ensure-shared prints the long-form fallback (got: $errout)"
        ;;
esac
unset ES_MARKER

# List drift guard: install.sh's fetch_kit() list and update.sh's KIT_FILES
# must carry the same file set — a missing entry means streamed installs
# fetch an incomplete kit and crash at deploy time (set -e).
# extract_func since #441 a A1: this inventory leg stayed literal when
# #437 adopted the harness (byte-identity proven before the swap).
install_list="$(extract_func "$SCRIPT_DIR/../../files/install.sh" fetch_kit |
    grep -v 'mkdir' |
    grep -vE '^[[:space:]]*("\$dir/[^"]*"[[:space:]]*)+\\?$' |
    grep -oE '(install|config|update|uninstall|status)\.sh|opencode(-deny-all)?\.jsonc|sudoers\.template|umask\.sh|VERSION|etc/[a-zA-Z0-9./_-]+|opencode-permissions-kit-lib/[a-zA-Z0-9./_-]+' | sort -u)"
update_list="$(awk '/^KIT_FILES=/{flag=1} flag{printf "%s ", $0} flag && /"[[:space:]]*$/{exit}' "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh" |
    sed -e 's/^KIT_FILES="//' -e 's/"[[:space:]]*$//' -e 's/\\//g' | tr ' ' '\n' | grep -v '^$' | sort -u)"
if [ "$install_list" = "$update_list" ]; then
    pass "install.sh fetch list == update.sh KIT_FILES"
else
    fail "install.sh fetch list == update.sh KIT_FILES"
    echo "        only in install.sh: $(printf '%s\n' "$install_list" | grep -vxF "$(printf '%s\n' "$update_list")" | tr '\n' ' ')"
    echo "        only in update.sh: $(printf '%s\n' "$update_list" | grep -vxF "$(printf '%s\n' "$install_list")" | tr '\n' ' ')"
    failures=$((failures + 1))
fi

# Compat-stub guard retired with 0.0.29 (internal/records/streamline.md): no
# compatibility stubs are kept for pre-0.0.29 fetch lists — old update.sh
# copies 404 on the moved paths and users migrate via the streamed
# one-liner instead. The stub file and its KIT_FILES entry must both be
# gone.
if [ -e "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/migrate-denies.sh" ]; then
    fail "migrate-denies.sh stub must not exist (stub era ended with 0.0.29)"
else
    pass "no migrate-denies.sh stub (stub era ended with 0.0.29)"
fi
if sed -n 's/^KIT_FILES="\(.*\)"$/\1/p' "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh" | grep -q 'opencode-permissions-kit-lib/migrate-denies.sh'; then
    fail "stub must NOT be in KIT_FILES (never deployed)"
else
    pass "stub not in KIT_FILES (never deployed)"
fi

# ddev-hosts sudo re-exec: HOME via getent (0.0.43b W1). After the re-exec
# ddev_hosts_add runs AS the developer, so its own getent fix (0.0.43a F12)
# never fires on this path — the value passed here is the one ddev sees;
# a hardcoded /home/<user> would reintroduce the F12 symptom on relocated
# homes, on one of the two documented invocation paths.
if grep -qF 'env HOME="$_kit_home"' "$BIN/opk" &&
    grep -qF '_kit_home=$(getent passwd "$_kitsu"' "$BIN/opk" &&
    ! grep -qF 'HOME="/home/$_kitsu"' "$BIN/opk"; then
    pass "ddev-hosts re-exec resolves HOME via getent (0.0.43b W1)"
else
    fail "ddev-hosts re-exec resolves HOME via getent (0.0.43b W1)"
fi

# --- damaged-library fallback ui_confirm (issue #187 C) -------------------------
# The fallback definition in bin/opk exists only for a damaged library
# (sh/ui.sh missing) — extract it and run it standalone under a real
# pty (script(1)): it reads /dev/tty ONLY (no stdin fallback; EOF or
# unrecognized input follows the CALLER'S default, #370 a E3). Mixed-
# case answers must be honored — the old arms y|Y|yes|YES mapped
# Yes/No/yEs to the DEFAULT, silently declining an explicit yes and
# accepting an explicit no under a y default. Unknown input falls
# back to the default; the shape is ui_confirm's marker-less render.
OPK_UC="$(sed -n '/^    ui_confirm() {/,/^    }/p' "$KIT")"
if [ -n "$OPK_UC" ] && printf '%s' "$OPK_UC" | grep -qF "tr '[:upper:]' '[:lower:]'"; then
    pass "opk fallback ui_confirm extractable (lowercased, issue #187 C)"
else
    fail "opk fallback ui_confirm extractable (lowercased, issue #187 C)"
fi
printf '%s\n' "$OPK_UC" >"$WORK/opk-uc-fn.sh"
cat >"$WORK/opk-uc-driver.sh" <<'OCEOF'
#!/bin/sh
eval "$(cat "${OPK_UC_SRC:?}")"
if ui_confirm "Remove them now?" "${1:?}"; then
    echo "RESULT=yes"
else
    echo "RESULT=no"
fi
OCEOF
opk_uc() { # <typed-line> <default> -> last pty line (prompt + RESULT)
    printf '%s\n' "$1" | OPK_UC_SRC="$WORK/opk-uc-fn.sh" \
        script -qec "sh '$WORK/opk-uc-driver.sh' '$2'" /dev/null 2>/dev/null |
        tr -d '\r' | tail -1
}
oc_pin() { # <desc> <typed> <default> <expected result yes|no>
    _ocline=$(opk_uc "$2" "$3")
    case "$_ocline" in
        *"RESULT=$4")
            pass "$1"
            ;;
        *)
            fail "$1 (got: $_ocline)"
            ;;
    esac
}
oc_pin "opk fallback: mixed-case Yes accepted under an n default (issue #187 C)" Yes n yes
oc_pin "opk fallback: mixed-case No declines under a y default (issue #187 C)" No y no
oc_pin "opk fallback: unknown input falls back to a y default (issue #187 A class)" garbage y yes
oc_pin "opk fallback: unknown input falls back to an n default (issue #187 A class)" garbage n no
oc_pin "opk fallback: padded ' y' accepted under an n default (#189 a W2)" " y" n yes
oc_pin "opk fallback: trailing-space 'no ' declines under a y default (#189 a W2)" "no " y no
oc_pin "opk fallback: empty input follows the caller's default (#370 a E3)" "" n no
_ocline=$(opk_uc "" y)
if printf '%s' "$_ocline" | grep -qF '  Remove them now? [Y/n] ' &&
    ! printf '%s' "$_ocline" | grep -qF '[?]'; then
    pass "opk fallback shape: '  <question> [Y/n] ' — no marker (issue #187 B)"
else
    fail "opk fallback shape: '  <question> [Y/n] ' — no marker (got: $_ocline)"
fi

# --- #211 a F2: missing-lib fallbacks for the mutating helpers fail loud ------
# config.sh used to degrade silently when sh/ libs were missing:
# fs_baseline_root and ddev_handover_root were no-op stubs and
# ddev_rootless_bindmounts was not stubbed at all — projects add /
# refresh and the backend switch printed success ("setgid, default-acl",
# "baseline refreshed", "backend switched") over work that never ran.
# The stubs now fail loud like the write helpers (staged_write & co).
# Extract each stub from the real config.sh and execute it the way a
# damaged kit would (the lookup loop found nothing, only the stub ran).
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
_stubs=$(work_new)
sed -n '/^\[ -n "\$_handover" \] || ddev_handover_root/,/^}$/p' "$CONFIG" >"$_stubs/ho.sh"
sed -n '/^\[ -n "\$_handover" \] || ddev_rootless_bindmounts/,/^}$/p' "$CONFIG" >"$_stubs/rb.sh"
sed -n '/^\[ -n "\$_handover" \] || ddev_devowned_enabled/,/^}$/p' "$CONFIG" >"$_stubs/dde.sh"
sed -n '/^command -v fs_baseline_root/,/^}$/p' "$CONFIG" >"$_stubs/fsb.sh"
for _s in ho rb fsb dde; do
    if [ -s "$_stubs/$_s.sh" ] && grep -q 'unavailable' "$_stubs/$_s.sh"; then
        pass "F2: $_s stub present and names its cause"
    else
        fail "F2: $_s stub present and names its cause"
    fi
done
_rc=0
_out=$(_handover="" sh -c '. "$1" >/dev/null 2>&1; ddev_handover_root /proj u g d' \
    sh "$_stubs/ho.sh" 2>&1) || _rc=$?
assert_eq "F2: ddev_handover_root stub returns 1 (loud, not 127-silent)" "1" "${_rc:-0}"
case "$_out" in
    *"ddev_handover_root unavailable"*)
        pass "F2: ddev_handover_root stub names the missing lib on stderr"
        ;;
    *)
        fail "F2: ddev_handover_root stub names the missing lib on stderr (got: $_out)"
        ;;
esac
# _rc must be reset before EVERY capture — a stale value from the
# previous block masked a silent-stub regression during the F2 pin's
# own sabotage verification (L4).
_rc=0
_out=$(_handover="" sh -c '. "$1" >/dev/null 2>&1; fs_baseline_root /proj g u' \
    sh "$_stubs/fsb.sh" 2>&1) || _rc=$?
assert_eq "F2: fs_baseline_root stub returns 1 (no false 'baseline refreshed')" "1" "${_rc:-0}"
# The success-line mechanism itself: under set -e the loud stub aborts
# BEFORE any caller success line can print (0.0.44a V9's sibling class).
_reached=""
_rc=0
_out=$(sh -c 'set -e; _handover=""; . "$1" >/dev/null 2>&1; ddev_handover_root /proj u g d; echo REACHED' \
    sh "$_stubs/ho.sh" 2>&1) || _rc=$?
case "$_out" in
    *REACHED*) _reached=yes ;;
esac
if [ -z "$_reached" ]; then
    pass "F2: set -e aborts before any success line (REACHED not printed)"
else
    fail "F2: set -e aborts before any success line (REACHED printed)"
fi
# ddev_rootless_bindmounts: rc 2 = the backend switch's warn arm — the
# gate must not evaluate as success (rc 127 fell through silently).
_rc=0
_handover="" sh -c '. "$1" >/dev/null 2>&1; ddev_rootless_bindmounts u b v bin' \
    sh "$_stubs/rb.sh" >/dev/null 2>&1 || _rc=$?
assert_eq "F2: ddev_rootless_bindmounts stub returns 2 (caller's warn arm)" "2" "$_rc"
# (#370 a D3R): the mode probe's stub must DIE, not return 1 — its only
# call site sits in an if-condition (ddev_settings_status), where rc 1
# reads as false and `config ddev-settings status` FALSE-reported "off"
# over a damaged library (rc 0, "not found" on stderr). The drive below
# reproduces the caller's shape: no OFF verdict may print.
_rc=0
_out=$(_handover="" sh -c '. "$1" >/dev/null 2>&1; if ddev_devowned_enabled; then echo ON; else echo OFF; fi' \
    sh "$_stubs/dde.sh" 2>&1) || _rc=$?
if [ "$_rc" -eq 1 ] &&
    printf '%s' "$_out" | grep -q 'ddev_devowned_enabled unavailable' &&
    ! printf '%s' "$_out" | grep -qF 'OFF'; then
    pass "D3R: ddev_devowned_enabled stub dies in-condition, no false 'off' (#370 a D3R)"
else
    fail "D3R: ddev_devowned_enabled stub dies in-condition (rc=$_rc out=$_out) (#370 a D3R)"
fi
# The update.sh twins of the same stub (#211 a F2 sweep — its loop logs
# "ddev handover pass completed" unconditionally; #211 b W3 — the
# fs_baseline_root stub, in the refresh arm of the project-root loop
# since issue #219, was missed by the same sweep): loud rc 1 as well.
# EXECUTED, not just grepped (#211 b W12): a presence-only pin passes a
# `return 0` regression with the echo kept. Both stubs live in
# sh/update-core.sh since #346 wave 2 (indents unchanged).
sed -n '/^        command -v ddev_handover_root/,/^        }$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/update-core.sh" >"$_stubs/uho.sh"
sed -n '/^            command -v fs_baseline_root/,/^            }$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/update-core.sh" >"$_stubs/ufsbl.sh"
for _stubpair in uho:ddev_handover_root:handover ufsbl:fs_baseline_root:baseline; do
    _short="${_stubpair%%:*}"
    _rest="${_stubpair#*:}"
    _fn="${_rest%%:*}"
    _lbl="${_rest##*:}"
    _rc=0
    _msg=$(sh -c '. "$1"; "$2" u b v' sh "$_stubs/$_short.sh" "$_fn" 2>&1 >/dev/null) || _rc=$?
    if [ "$_rc" -eq 1 ] && printf '%s' "$_msg" | grep -q 'unavailable'; then
        pass "F2 sweep: update.sh $_lbl stub loud (executes: rc 1 + stderr) (#211 b W3, b W12)"
    else
        fail "F2 sweep: update.sh $_lbl stub loud (rc=$_rc msg=$_msg) (#211 b W3, b W12)"
    fi
done
rm -rf "$_stubs"

# --- config arg loop: junk is a usage error, not silence (#211 a F11) -----------
# Unknown tokens fell into TARGETS and were ignored with rc 0 for every
# action that takes no positionals — `config git-config ON` rendered the
# status view as if nothing was wrong. Extract the REAL loop+gate and
# drive it: junk/misplaced die; projects add keeps paths; --yes clean.
_f11_block="$(sed -n '/^for arg; do$/,/#211 a F11 gate end/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh")"
# #211 b W23 (the #198 a W5 / F7 shapes): end anchors are a shipped
# marker comment (F11) — if it ever drifts, the extract runs to EOF and
# the eval fails confusingly. Bound it: the loop+gate is 97 lines
# (shfmt-canonical; 51 pre-#370, 85 after D4/D5, 97 after round a's
# messages, divergence comment and the D5-pin tails — re-measured,
# round b B3: the comment had said 95). Slack is 3 lines to ≤100.
if [ -n "$_f11_block" ] && [ "$(printf '%s\n' "$_f11_block" | wc -l)" -le 100 ]; then
    pass "config arg loop + F11 gate extractable (#211 a F11)"
    _f11_run() {
        (
            YES=false
            ACTION=""
            SUB=""
            TARGETS=""
            _TGT_SPACED=0
            die() {
                echo "die: $*"
                exit 1
            }
            eval "$_f11_block"
            echo "OK ACTION=[$ACTION] SUB=[$SUB] TARGETS=[$TARGETS]"
        )
    }
    _out=$(_f11_run git-config ON) || true
    case "$_out" in
        *"die: unknown or misplaced argument(s):ON"*)
            pass "junk token after an action dies loudly (#211 a F11)"
            ;;
        *)
            fail "junk token after an action dies loudly (out=$_out)"
            ;;
    esac
    _out=$(_f11_run status refresh) || true
    case "$_out" in
        *die:*)
            pass "misplaced second action word dies (#211 a F11)"
            ;;
        *)
            fail "misplaced second action word dies (out=$_out)"
            ;;
    esac
    _out=$(_f11_run projects add /a/proj) || true
    case "$_out" in
        *"OK ACTION=[projects] SUB=[add] TARGETS=[/a/proj]"*)
            pass "projects add keeps its path targets (#211 a F11)"
            ;;
        *)
            fail "projects add keeps its path targets (out=$_out)"
            ;;
    esac
    _out=$(_f11_run git-config status) || true
    case "$_out" in
        *"OK ACTION=[git-config] SUB=[status] TARGETS=[]"*)
            pass "git-config status consumed as SUB, e2e flow intact (#211 a F11)"
            ;;
        *)
            fail "git-config status consumed as SUB (out=$_out)"
            ;;
    esac
    _out=$(_f11_run git-config off status) || true
    case "$_out" in
        *"die: unknown or misplaced argument(s):status"*)
            pass "status no longer clobbers a set SUB — dies loud (#211 b W20)"
            ;;
        *)
            fail "status no longer clobbers a set SUB (out=$_out) (#211 b W20)"
            ;;
    esac
    _out=$(_f11_run refresh status) || true
    case "$_out" in
        *"OK ACTION=[refresh] SUB=[status] TARGETS=[]"*)
            pass "refresh status still consumed (SUB was empty) (#211 b W20)"
            ;;
        *)
            fail "refresh status still consumed (out=$_out) (#211 b W20)"
            ;;
    esac
    _out=$(_f11_run handover /a/proj) || true
    case "$_out" in
        *"OK ACTION=[handover] SUB=[] TARGETS=[/a/proj]"*)
            pass "handover keeps its documented path target (#211 a F11)"
            ;;
        *)
            fail "handover keeps its documented path target (out=$_out)"
            ;;
    esac
    _out=$(_f11_run --yes) || true
    case "$_out" in
        *"OK ACTION=[] SUB=[] TARGETS=[]"*)
            pass "bare --yes stays clean (#211 a F11)"
            ;;
        *)
            fail "bare --yes stays clean (out=$_out)"
            ;;
    esac
    # --- #370 a D4: `projects list` takes no path targets ---------------------
    _out=$(_f11_run projects list) || true
    case "$_out" in
        *"OK ACTION=[projects] SUB=[list] TARGETS=[]"*)
            pass "bare projects list stays clean (#370 a D4)"
            ;;
        *)
            fail "bare projects list stays clean (out=$_out) (#370 a D4)"
            ;;
    esac
    _out=$(_f11_run projects list /junk/path) || true
    case "$_out" in
        *"die: unknown or misplaced argument(s):/junk/path"*)
            pass "junk after projects list dies loudly (#370 a D4)"
            ;;
        *)
            fail "junk after projects list dies loudly (out=$_out) (#370 a D4)"
            ;;
    esac
    # --- #370 a D5: ONE argument carrying whitespace never reaches the
    # word-splitting consumers -- the gate refuses it at parse time
    _out=$(_f11_run projects add "/a/proj with space") || true
    case "$_out" in
        *"die: path arguments must not contain whitespace"*"not supported as project roots"*)
            pass "spaced path operand to projects add refused, names the limit (#370 a D5, a A3)"
            ;;
        *)
            fail "spaced path operand to projects add refused (out=$_out) (#370 a D5, a A3)"
            ;;
    esac
    _out=$(_f11_run handover "/a/b c") || true
    case "$_out" in
        *"die: path arguments must not contain whitespace"*"not expressible through config.sh"*"opk handover <me|opencode>"*)
            pass "spaced path operand to handover refused, hint names the escape (#370 a D5, a A3)"
            ;;
        *)
            fail "spaced path operand to handover refused (out=$_out) (#370 a D5, a A3)"
            ;;
    esac
    _out=$(_f11_run projects add /a/proj /b/other) || true
    case "$_out" in
        *"OK ACTION=[projects] SUB=[add] TARGETS=[/a/proj /b/other]"*)
            pass "separate path arguments keep flowing (#370 a D5)"
            ;;
        *)
            fail "separate path arguments keep flowing (out=$_out) (#370 a D5)"
            ;;
    esac
else
    fail "config arg loop + F11 gate extractable (#211 a F11)"
fi

# --- chained user symlink resolves (#211 a F15) -----------------------------------
# A second hop (~/bin/opk -> $BIN/opk -> lib) used to defeat the
# single-hop readlink: LIBDIR resolved one level short and every
# subcommand reported "not found". readlink -f walks the whole chain
# (sibling shape: ddev-migrate, xdg-open).
mkdir -p "$WORK/bin2"
ln -s "$BIN/opk" "$WORK/bin2/opk"
_out="$(OPK_INSTALL_CONF="$WORK/install.conf" "$WORK/bin2/opk" status 2>/dev/null)" || true
case "$_out" in
    *"status:euid="*)
        pass "chained symlink dispatches (readlink -f, #211 a F15)"
        ;;
    *)
        fail "chained symlink dispatches (#211 a F15, got: $_out)"
        ;;
esac

# --- F24: a missing staged-write.sh names itself, not a symlink --------------------
# agent_home_sane returning 127 (lib missing) used to die with "a parent
# is a symlink" — wrong diagnosis for a broken kit. Extract the guard
# block and drive both arms with a fixed $target.
_f24_block="$(sed -n '/#211 a F24/,/^    fi$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh")"
# #211 b W23: first-fi end anchor — bound the extract (guard block is
# 5 lines) so anchor drift fails HERE instead of eval-ing to EOF.
if [ -n "$_f24_block" ] && [ "$(printf '%s\n' "$_f24_block" | wc -l)" -le 8 ]; then
    pass "F24 guard block extractable"
    _f24_run() {
        # $1 = define sane fn (yes|no)
        # /var/tmp path (#211 b W5): the first draft carried a real-tree
        # /home/... literal — inert (both arms are FS-free) but forbidden
        # by the sandbox shape (the inert-literal sandbox rule).
        (
            OPENCODE_USER=oc
            target=/var/tmp/opk-f24-fixture/settings.json
            die() {
                echo "die: $*"
                exit 1
            }
            if [ "$1" = yes ]; then agent_home_sane() { return 0; }; fi
            eval "$_f24_block"
            echo "NOT-REACHED"
        )
    }
    _out=$(_f24_run no) || true
    case "$_out" in
        *"die: kit file sh/staged-write.sh missing"*)
            pass "missing lib names itself (#211 a F24)"
            ;;
        *)
            fail "missing lib names itself (got: $_out)"
            ;;
    esac
    _out=$(_f24_run yes) || true
    case "$_out" in
        *NOT-REACHED*)
            pass "healthy helper passes through (#211 a F24)"
            ;;
        *)
            fail "healthy helper passes through (got: $_out)"
            ;;
    esac
else
    fail "F24 guard block extractable"
fi

# --- F26: config.sh status shows the backend row like the menu --------------------
if sed -n '/^    status)$/,/^        ;;$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh" |
    tr '\n' ' ' | grep -qE 'banner +git_config_status +container_backend_status'; then
    pass "config status lists the backend row (menu parity, #211 a F26)"
else
    fail "config status lists the backend row (#211 a F26)"
fi

# --- openchamber-secure settings edit: guard inside the sudo context (#244 f W2) --
# The #244 e-S1 class fix at opk's settings-edit compound: guard and exec
# share ONE PATH (the sudo context). Static shape pins, then functional
# asymmetry arms — the compound is extracted from opk (the F24 idiom)
# and driven with PATH-fixing sudo shims over a binary farm (the
# test-tui-mode arm idiom).
OCW2_BLOCK="$(sed -n '/#244 f W2/,/^        fi$/p' "$OCCORE")"
# Bound is 38 lines: 33 (the #244 f W2 compound) + 2 for pr-00263 c C2
# (the else branch exits 1 instead of falling through to exit 0) + 3
# for the #249 isolation note (review a C2). (End anchor re-dented
# with the body by the #415 wave-1 extraction: the compound's closing
# fi sits at 8 spaces in the lib, was 12 in the bin/opk arm.)
if [ -n "$OCW2_BLOCK" ] &&
    [ "$(printf '%s\n' "$OCW2_BLOCK" | wc -l)" -le 38 ] &&
    printf '%s\n' "$OCW2_BLOCK" |
    grep -qF 'sh -c ' &&
    printf '%s\n' "$OCW2_BLOCK" |
    grep -qF 'command -v python3 >/dev/null 2>&1 && exec python3 -I "$@"'; then
    pass "settings-edit guard runs inside the sudo context (#244 f W2)"
else
    fail "settings-edit guard inside the sudo context (#244 f W2)"
fi
if printf '%s\n' "$OCW2_BLOCK" | grep -qE '^ +if command -v python3'; then
    fail "settings-edit guard is caller-side again (#244 f W2)"
else
    pass "no caller-side guard shape in the settings edit (#244 f W2)"
fi
if [ -z "$OCW2_BLOCK" ]; then
    fail "settings-edit block extractable for asymmetry arms (#244 f W2)"
elif ! command -v python3 >/dev/null 2>&1; then
    # Distinct failure surface (#244 g Q1): extraction failure and
    # the arms' python3 hard-require are different causes — one
    # label each, per the check-host make-test contract.
    fail "settings-edit asymmetry arms need python3 (check-host contract) (#244 g Q1)"
else
    OCW2="$WORK/ocw2"
    OCW2F="$OCW2/farms"
    OCW2BASE="$OCW2F/base"
    mkdir -p "$OCW2BASE"
    for _ocd in /usr/bin /bin /usr/local/bin; do
        for _ocb in "$_ocd"/*; do
            [ -e "$_ocb" ] || continue
            [ "${_ocb##*/}" = python3 ] && continue
            ln -sfn "$_ocb" "$OCW2BASE/${_ocb##*/}"
        done
    done
    # Exec contexts: arm A = base (no python3); arm B = base + the real
    # interpreter. PATH-fixing sudo shims strip -u (the suite-fake
    # idiom), then exec under the fixed PATH (the secure_path stand-in).
    OCW2FIXB="$OCW2F/fixb"
    mkdir -p "$OCW2FIXB"
    for _ocf in "$OCW2BASE"/*; do ln -sfn "$_ocf" "$OCW2FIXB/${_ocf##*/}"; done
    ln -s "$(command -v python3)" "$OCW2FIXB/python3"
    mkdir -p "$OCW2F/sudo-a" "$OCW2F/sudo-b"
    cat >"$OCW2F/sudo-a/sudo" <<EOF
#!/bin/sh
while [ "\$1" = -u ]; do shift; [ "\$#" -gt 0 ] && shift; done
PATH="$OCW2BASE" exec "\$@"
EOF
    cat >"$OCW2F/sudo-b/sudo" <<EOF
#!/bin/sh
while [ "\$1" = -u ]; do shift; [ "\$#" -gt 0 ] && shift; done
PATH="$OCW2FIXB" exec "\$@"
EOF
    chmod +x "$OCW2F/sudo-a/sudo" "$OCW2F/sudo-b/sudo"
    # Caller PATHs (whole PATH, so command -v sees exactly these): arm A
    # = base + a NOISY python3 (any execution of the caller's shim is a
    # red); arm B = base only (no python3 anywhere for the caller).
    OCW2NOISY="$OCW2F/noisybin"
    mkdir -p "$OCW2NOISY"
    for _ocf in "$OCW2BASE"/*; do ln -sfn "$_ocf" "$OCW2NOISY/${_ocf##*/}"; done
    printf '#!/bin/sh\necho "ocw2-noisy-python3" >&2\nexit 9\n' >"$OCW2NOISY/python3"
    chmod +x "$OCW2NOISY/python3"
    ln -sfn "$OCW2F/sudo-a/sudo" "$OCW2NOISY/sudo"
    OCW2ABSB="$OCW2F/absbin"
    mkdir -p "$OCW2ABSB"
    for _ocf in "$OCW2BASE"/*; do ln -sfn "$_ocf" "$OCW2ABSB/${_ocf##*/}"; done
    ln -sfn "$OCW2F/sudo-b/sudo" "$OCW2ABSB/sudo"
    _ocw2_run() { # <caller-PATH-dir> — fresh fixture, eval the compound
        mkdir -p "$OCW2/case"
        printf '{ "opencodeBinary": "/home/dev/.opencode/bin/opencode", "port": 3000 }\n' \
            >"$OCW2/case/settings.json"
        (
            PATH="$1"
            export PATH
            _oc_settings="$OCW2/case/settings.json"
            _oc_duser=devuser
            ui_success() { echo "W2:success"; }
            ui_error() { echo "W2:error:$1"; }
            eval "$OCW2_BLOCK"
        ) 2>&1
    }
    # Arm A: caller PATH has (noisy) python3, exec context none — the
    # inner guard skips silently; a caller-side guard would leak sudo's
    # not-found notice (or run the noisy shim). pr-00263 c C2: the
    # compound must also FAIL (rc 1) — it used to fall through to 0.
    _ocrc=0
    _ocout="$(_ocw2_run "$OCW2NOISY")" || _ocrc=$?
    _ocok=0
    case "$_ocout" in *W2:error:*) _ocok=$((_ocok + 1)) ;; esac
    case "$_ocout" in *"not found"* | *"ocw2-noisy-python3"*) ;; *) _ocok=$((_ocok + 1)) ;; esac
    if grep -q opencodeBinary "$OCW2/case/settings.json"; then _ocok=$((_ocok + 1)); fi
    [ "$_ocrc" -eq 1 ] && _ocok=$((_ocok + 1))
    if [ "$_ocok" -eq 4 ]; then
        pass "settings edit arm A: exec context without python3 stays silent, rc 1 (pr-00263 c C2)"
    else
        fail "settings edit arm A (#244 f W2 + pr-00263 c C2, rc=$_ocrc, got: $_ocout)"
    fi
    # Arm B: caller PATH has NO python3, exec context the real one — a
    # caller-side guard would skip the edit; the inner guard runs it
    # (the settings file itself is the proof). Success stays rc 0.
    _ocrc=0
    _ocout="$(_ocw2_run "$OCW2ABSB")" || _ocrc=$?
    if [ "$_ocrc" -eq 0 ] && printf '%s' "$_ocout" | grep -q W2:success &&
        ! grep -q opencodeBinary "$OCW2/case/settings.json" &&
        grep -q '"port": 3000' "$OCW2/case/settings.json"; then
        pass "settings edit arm B: exec-context python3 edits despite caller absence (#244 f W2)"
    else
        fail "settings edit arm B (#244 f W2, rc=$_ocrc, got: $_ocout)"
    fi
    rm -rf "$OCW2"
fi

# --- openchamber-secure settings edit: value-shaped match fails loud (#244 g S1) --
# The outer grep needle '"opencodeBinary"' can hit the literal as a
# VALUE; the edit script must not report success then (#244 g S1
# added the else-exit). Direct behavioral pins on the extracted
# heredoc script — both directions, python3 hard-required (labels
# say so; the check-host make-test contract).
OPYSCR="$(sed -n '/opk-settings-edit/,/^PYEOF$/p' "$OCCORE" | sed '1d;$d')"
if [ -z "$OPYSCR" ] || ! printf '%s\n' "$OPYSCR" | grep -qF 'del d["opencodeBinary"]' ||
    ! printf '%s\n' "$OPYSCR" | grep -qF 'sys.exit(1)'; then
    fail "settings-edit python script extractable (anchors: del d[\"opencodeBinary\"], sys.exit(1)) (#244 g S1)"
elif ! command -v python3 >/dev/null 2>&1; then
    fail "settings-edit S1 pins need python3 (check-host contract) (#244 g S1)"
else
    OCW2S1="$WORK/ocw2s1"
    mkdir -p "$OCW2S1"
    # Value-shaped match: rc != 0, SILENT (exit, not a traceback),
    # file byte-identical — no destructive write on the failure path.
    printf '{ "note": "opencodeBinary", "port": 3000 }\n' >"$OCW2S1/val.json"
    cp "$OCW2S1/val.json" "$OCW2S1/val.exp"
    _s1rc=0
    _s1out="$(printf '%s\n' "$OPYSCR" | python3 - "$OCW2S1/val.json" 2>&1)" || _s1rc=$?
    if [ "$_s1rc" -ne 0 ] && [ -z "$_s1out" ] &&
        cmp -s "$OCW2S1/val.json" "$OCW2S1/val.exp"; then
        pass "value-shaped opencodeBinary match fails silent, file untouched (#244 g S1)"
    else
        fail "value-shaped opencodeBinary match fails silent, file untouched (#244 g S1, rc=$_s1rc out=[$_s1out])"
    fi
    # Key-shaped match: rc 0, key gone, other keys preserved — the
    # S1 change must not break the success path.
    printf '{ "opencodeBinary": "/x", "port": 3000 }\n' >"$OCW2S1/key.json"
    if printf '%s\n' "$OPYSCR" | python3 - "$OCW2S1/key.json" >/dev/null 2>&1 &&
        ! grep -q opencodeBinary "$OCW2S1/key.json" &&
        grep -q '"port": 3000' "$OCW2S1/key.json"; then
        pass "key-shaped opencodeBinary removed, other keys preserved (#244 g S1)"
    else
        fail "key-shaped opencodeBinary removal (#244 g S1)"
    fi
    rm -rf "$OCW2S1"
fi

# pr-00263 a F21: the settings-edit failure message names the entry as
# key-or-value — the grep can match the literal as a VALUE, "remove the
# line" was wrong for that arm.
check "settings-edit failure names key-or-value (pr-00263 a F21)" grep -qF 'entry (key or value) by hand' "$OCCORE"

echo ""
_kit_pi=$(live_src "$OCCORE" | grep -c 'python3 -I' || true)
if [ "${_kit_pi:-0}" -ge 1 ]; then
    pass "openchamber-core's settings edit runs python3 -I ($_kit_pi found) (#249, moved with the #415 wave-1 extraction)"
else
    fail "openchamber-core must run its settings edit with python3 -I (found ${_kit_pi:-0}) (#249)"
fi
_kit_hc_pi=$(live_src "$HOCORE" | grep -c 'python3 -I' || true)
if [ "${_kit_hc_pi:-0}" -ge 1 ]; then
    pass "handover-core's opk.json reader runs python3 -I ($_kit_hc_pi found) (#249, moved with the #415 extraction)"
else
    fail "handover-core must run its opk.json reader with python3 -I (found ${_kit_hc_pi:-0}) (#249)"
fi
_kit_exec_pi=$(live_src "$OCCORE" | grep -c 'exec python3 -I' || true)
if [ "${_kit_exec_pi:-0}" -ge 1 ]; then
    pass "openchamber-core's settings-edit exec runs python3 -I (review a C2, moved with the #415 wave-1 extraction)"
else
    fail "the settings-edit exec must run python3 -I (found ${_kit_exec_pi:-0}) (review a C2)"
fi

suite_done "CLI dispatcher tests"
