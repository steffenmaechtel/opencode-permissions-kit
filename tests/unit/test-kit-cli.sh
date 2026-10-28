#!/bin/sh
# Test the CLI dispatcher (files/opencode-permissions-kit-lib/bin/opk).
# Builds a fake library dir with stub scripts, symlinks the dispatcher,
# and checks dispatch, help, error handling, and flag pass-through.
# Run: sh tests/unit/test-kit-cli.sh
set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opk"

failures=0
passed=0

assert() {
    desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        expected: [$expected]  got: [$actual]"
        failures=$((failures + 1))
    fi
}

WORK="$(mktemp -d)"
# widen the trap to every receiver of the suite + signal arms (#283):
# _ho_pin_dir/_stubs were bare (trap covered $WORK only, EXIT only), so
# an abort between creation and their inline rm leaked the scratch.
trap 'rm -rf "${WORK:-}" "${_ho_pin_dir:-}" "${_stubs:-}"' EXIT INT TERM

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
for s in status config update uninstall; do
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
out="$(run_kit --help)"
assert "--help exits 0" "0" "$?"
for c in status config update uninstall handover help openchamber-secure ensure-shared; do
    case "$out" in
        *"$c"*)
            echo "  ${GREEN}PASS${NC}  --help mentions '$c'"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  --help mentions '$c'"
            failures=$((failures + 1))
            ;;
    esac
done
out_help="$(run_kit help)"
assert "help == --help" "$(run_kit --help)" "$out_help"

# version comes from the library VERSION file
case "$out" in
    *"v9.9.9"*)
        echo "  ${GREEN}PASS${NC}  version from install.conf stamp"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  version from install.conf stamp (got: $out)"
        failures=$((failures + 1))
        ;;
esac

# --version prints just the version, one line (issue #130)
out="$(run_kit --version)"
assert "--version exits 0" "0" "$?"
assert "--version prints 'opk <stamp>'" "opk 9.9.9" "$out"
# No install.conf: fallback stamp, never an error (dev checkouts)
out="$(OPK_INSTALL_CONF="$WORK/no-such.conf" "$BIN/opk" --version 2>/dev/null)"
assert "--version without install.conf falls back" "opk 0.0.0" "$out"

# status dispatches without sudo (root test envs: euid matches current)
out="$(run_kit status)"
assert "status dispatches" "status:euid=$(id -u):args=" "$out"

# config/update dispatch with args passed through (fake sudo passes them on;
# stubs run as the current user either way)
out="$(run_kit config projects list)"
assert "config passes args" "config:euid=$(id -u):args=projects list" "$out"
out="$(run_kit update --yes --refresh)"
assert "update passes flags" "update:euid=$(id -u):args=--yes --refresh" "$out"

# upgrade-opencode: binary-only shorthand — injects --yes --only-binary,
# extra flags pass through (issue #24)
out="$(run_kit upgrade-opencode --binary-path /tmp/x)"
assert "upgrade-opencode injects --yes --only-binary (flags pass through)" \
    "update:euid=$(id -u):args=--yes --only-binary --binary-path /tmp/x" "$out"

# non-root invocations of config/update go through sudo
if [ "$(id -u)" -ne 0 ]; then
    if [ -f "$WORK/sudo-marker" ]; then
        echo "  ${GREEN}PASS${NC}  config/update auto-elevate via sudo"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  config/update auto-elevate via sudo"
        failures=$((failures + 1))
    fi
else
    echo "  ${GREEN}PASS${NC}  config/update auto-elevate (skipped: test runs as root)"
    passed=$((passed + 1))
fi

# uninstall dispatches as the current user (no forced sudo)
out="$(run_kit uninstall --dry-run)"
assert "uninstall passes flags" "uninstall:euid=$(id -u):args=--dry-run" "$out"

# --- openchamber-secure (issue #154, Tier 3) -----------------------------------
# Inline command: static wiring pins (functional run needs root + /etc —
# covered by the e2e suite instead).
grep -q '    openchamber-secure)' "$KIT" &&
    echo "  ${GREEN}PASS${NC}  openchamber-secure dispatch exists" && passed=$((passed + 1)) ||
    {
        echo "  ${RED}FAIL${NC}  openchamber-secure dispatch exists"
        failures=$((failures + 1))
    }
grep -qF 'exec sudo sh "$LIBDIR/bin/opk" openchamber-secure "$@"' "$KIT" &&
    echo "  ${GREEN}PASS${NC}  openchamber-secure auto-elevates with flags intact" && passed=$((passed + 1)) ||
    {
        echo "  ${RED}FAIL${NC}  openchamber-secure auto-elevates with flags intact"
        failures=$((failures + 1))
    }
grep -qF 'mv -f "$_ocp_tmp" /etc/openchamber/policy.json' "$KIT" &&
    grep -qF 'OPENCHAMBER_POLICY=yes' "$KIT" &&
    echo "  ${GREEN}PASS${NC}  openchamber-secure writes the pin (atomic) + records the opt-in" && passed=$((passed + 1)) ||
    {
        echo "  ${RED}FAIL${NC}  openchamber-secure writes the pin (atomic) + records the opt-in"
        failures=$((failures + 1))
    }
# 0.0.47a F1: replacing divergent policy content is announced, never silent
grep -qF 'diverges from the kit pin — replacing it' "$KIT" &&
    echo "  ${GREEN}PASS${NC}  openchamber-secure announces replacing divergent content (F1)" && passed=$((passed + 1)) ||
    {
        echo "  ${RED}FAIL${NC}  openchamber-secure announces replacing divergent content (F1)"
        failures=$((failures + 1))
    }
# 0.0.47a F3: the kit-symlink exemption helper exists and is used at the
# detection, listing and removal sites
# Comment-strip riders (#261, the #244 g W1 class): commented-out lines
# must not count. Full-line comments only (#244 h W6 residual): a
# trailing comment after a live line still counts.
[ "$(sed 's/^[[:space:]]*#.*$//' "$KIT" | grep -c 'oc_bypass_bin' || true)" -ge 4 ] &&
    echo "  ${GREEN}PASS${NC}  openchamber-secure exempts kit-owned symlinks (F3)" && passed=$((passed + 1)) ||
    {
        echo "  ${RED}FAIL${NC}  openchamber-secure exempts kit-owned symlinks (F3)"
        failures=$((failures + 1))
    }
# 0.0.47c C2: every completing path of openchamber-secure ends with the
# restart hint (getent-skip, nothing-found, decline, full run — the
# oc_bypass_bin count precedent; behavioral pinning of the decline path
# would need an interactive ui_confirm, static count is the proxy)
[ "$(sed 's/^[[:space:]]*#.*$//' "$KIT" | grep -c 'restart OpenChamber if it is running' || true)" -ge 4 ] &&
    echo "  ${GREEN}PASS${NC}  openchamber-secure prints the restart hint on every completing path (0.0.47c C2)" && passed=$((passed + 1)) ||
    {
        echo "  ${RED}FAIL${NC}  openchamber-secure restart hint missing from a completing path (0.0.47c C2)"
        failures=$((failures + 1))
    }

# unknown flag for openchamber-secure aborts before elevation (runs as
# non-root with the fake sudo, so the flag check fires first). Direct
# call: run_kit swallows stderr, ui_error writes to stderr.
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" openchamber-secure --bogus 2>&1 >/dev/null || true)"
case "$errout" in
    *"unknown flag"*)
        echo "  ${GREEN}PASS${NC}  openchamber-secure rejects unknown flags"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  openchamber-secure rejects unknown flags (got: $errout)"
        failures=$((failures + 1))
        ;;
esac

# unknown command fails with exit 1
if run_kit frobnicate >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  unknown command exits non-zero"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  unknown command exits non-zero"
    passed=$((passed + 1))
fi

# no command fails with exit 1
if run_kit >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  no command exits non-zero"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  no command exits non-zero"
    passed=$((passed + 1))
fi

# missing script -> clear error, non-zero
rm "${LIB:?}/management/update.sh"
if run_kit update >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  missing script exits non-zero"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  missing script exits non-zero"
    passed=$((passed + 1))
fi
errout="$("$BIN/opk" update 2>&1 >/dev/null || true)"
case "$errout" in
    *"not found"*)
        echo "  ${GREEN}PASS${NC}  missing script names the problem"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  missing script names the problem (got: $errout)"
        failures=$((failures + 1))
        ;;
esac

# --- handover: generic ownership switch ------------------------------------
# Validation and --dry-run must work unprivileged and BEFORE any sudo hop.
mkdir -p "$WORK/ho-tree/sub"
: >"$WORK/ho-tree/sub/file"

# no / too few arguments -> usage error
if run_kit handover >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  handover without args exits non-zero"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  handover without args exits non-zero"
    passed=$((passed + 1))
fi
if run_kit handover me >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  handover without a path exits non-zero"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  handover without a path exits non-zero"
    passed=$((passed + 1))
fi

# unknown target -> usage error naming the choices (hermetic: explicit
# install.conf — CI runners have no /etc/opencode-permissions-kit)
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover nobody "$WORK/ho-tree" 2>&1 >/dev/null || true)"
case "$errout" in
    *"me or opencode"*)
        echo "  ${GREEN}PASS${NC}  handover rejects unknown target"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  handover rejects unknown target (got: $errout)"
        failures=$((failures + 1))
        ;;
esac

# nonexistent path -> error
if run_kit handover me "$WORK/does-not-exist" >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  handover rejects nonexistent paths"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  handover rejects nonexistent paths"
    passed=$((passed + 1))
fi

# system roots, their SUBPATHS, and whole home directories are refused
# (0.0.39b S2: /etc/apache2 used to pass the exact-match blocklist)
for _bad in / /usr /etc /var "/home/$(id -un)" /etc/apache2 /usr/local/foo /var/log /var/lib/docker; do
    errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$_bad" 2>&1 >/dev/null || true)"
    case "$errout" in
        *"refusing"*)
            echo "  ${GREEN}PASS${NC}  handover refuses $_bad"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  handover refuses $_bad (got: $errout)"
            failures=$((failures + 1))
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
            echo "  ${GREEN}PASS${NC}  handover refuses slash form $_slashed"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  handover refuses slash form $_slashed (got: $errout)"
            failures=$((failures + 1))
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
            echo "  ${GREEN}PASS${NC}  handover refuses mid-dot form $_middot (S7)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  handover refuses mid-dot form $_middot (S7, got: $errout)"
            failures=$((failures + 1))
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
            echo "  ${GREEN}PASS${NC}  handover refuses dotdot form $_dotdot (W3)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  handover refuses dotdot form $_dotdot (W3, got: $errout)"
            failures=$((failures + 1))
            ;;
    esac
done
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$WORK/ho-link/" 2>&1 >/dev/null || true)"
case "$errout" in
    *"slash/dotdot path form"*)
        echo "  ${GREEN}PASS${NC}  handover refuses symlink-with-slash before any gate"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  handover refuses symlink-with-slash before any gate (got: $errout)"
        failures=$((failures + 1))
        ;;
esac

# --dry-run: plan only, no changes, no sudo, exit 0
rm -f "${WORK:?}/sudo-marker"
out="$(run_kit handover me "$WORK/ho-tree" --dry-run)"
assert "handover --dry-run exits 0" "0" "$?"
case "$out" in
    *"would hand over: $WORK/ho-tree -> $(id -un):$(id -gn)"*)
        echo "  ${GREEN}PASS${NC}  handover --dry-run prints the plan (user:group)"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  handover --dry-run prints the plan (got: $out)"
        failures=$((failures + 1))
        ;;
esac
if [ -f "$WORK/sudo-marker" ]; then
    echo "  ${RED}FAIL${NC}  handover --dry-run needs no sudo"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  handover --dry-run needs no sudo"
    passed=$((passed + 1))
fi

# real run (no --dry-run): elevates via sudo. With the FAKE sudo it cannot
# elevate — the loop guard must stop the re-entry instead of recursing.
rm -f "${WORK:?}/sudo-marker"
if [ "$(id -u)" -ne 0 ]; then
    errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" handover me "$WORK/ho-tree" 2>&1 >/dev/null || true)"
    if [ -f "$WORK/sudo-marker" ]; then
        echo "  ${GREEN}PASS${NC}  handover elevates via sudo"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  handover elevates via sudo"
        failures=$((failures + 1))
    fi
    case "$errout" in
        *"did not elevate"*)
            echo "  ${GREEN}PASS${NC}  handover loop guard stops non-elevating sudo"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  handover loop guard stops non-elevating sudo (got: $errout)"
            failures=$((failures + 1))
            ;;
    esac
else
    # test env is root: the real chown runs; the tree must end up owned by
    # the conf user with group write access.
    out="$(run_kit handover opencode "$WORK/ho-tree")"
    _own=$(stat -c '%U:%G' "$WORK/ho-tree/sub/file")
    assert "handover chowns recursively (root env)" "$(id -un):$(id -gn)" "$_own"
    case "$out" in
        *"handover: $WORK/ho-tree"*)
            echo "  ${GREEN}PASS${NC}  handover reports each path (root env)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  handover reports each path (root env, got: $out)"
            failures=$((failures + 1))
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
_ho_chmod_lns=$(sed 's/^[[:space:]]*#.*$//' "$KIT" | grep -n 'find "\$_ho_a" ! -type l -exec chmod g+w' | cut -d: -f1)
_ho_chown_lns=$(sed 's/^[[:space:]]*#.*$//' "$KIT" | grep -n 'chown -R -h "\$_ho_user:\$_ho_group" "\$_ho_a"' | cut -d: -f1)
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
    echo "  ${GREEN}PASS${NC}  handover: opencode branch chmod-before-chown, me branch chown-before-chmod (S4+W1)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  handover: per-direction order violated (S4+W1: chmod=$_ho_chmod_lns chown=$_ho_chown_lns)"
    failures=$((failures + 1))
fi

# W1 behavioral pin: run the REAL extracted executor loop per direction
# with shims that log every chown/chmod invocation — the log order pins
# the execution order causally (line-number statics above cannot see a
# rewired branch body). chown is shimmed to log+noop (unprivileged env,
# ownership itself is pinned by the root-env block above); chmod logs
# the operand's CURRENT owner at invocation time and then really runs.
_ho_pin_dir="$(mktemp -d)"
mkdir -p "$_ho_pin_dir/bin" "$_ho_pin_dir/tree"
echo keep >"$_ho_pin_dir/tree/file"
printf '#!/bin/sh\necho "chown $*" >> "$HO_LOG"\nexit 0\n' >"$_ho_pin_dir/bin/chown"
printf '#!/bin/sh\nfor _a do case "$_a" in -*) ;; *) [ -e "$_a" ] && echo "chmod $(stat -c %%U "$_a" 2>/dev/null || echo ?) $_a" >> "$HO_LOG" ;; esac; done\nexec /usr/bin/chmod "$@"\n' >"$_ho_pin_dir/bin/chmod"
chmod +x "$_ho_pin_dir/bin/chown" "$_ho_pin_dir/bin/chmod"
_ho_extract() {
    sed -n '/^        _ho_rc=0$/,/^        done$/p' "$KIT"
}
for _ho_tgt in opencode me; do
    rm -f "${_ho_pin_dir:?}/log"
    HO_LOG="$_ho_pin_dir/log" _ho_target="$_ho_tgt" _ho_user="$(id -un)" \
    _ho_group="$(id -gn)" _ho_rc=0 \
    PATH="$_ho_pin_dir/bin:$PATH" sh -c "$(
        printf 'ui_info() { :; }\nui_error() { echo "$1" >&2; }\nset -- "%s"\n' "${_ho_pin_dir}/tree"
        _ho_extract
    )" >/dev/null 2>&1 || true
    _ho_first_chown=$(grep -n '^chown ' "$_ho_pin_dir/log" 2>/dev/null | head -1 | cut -d: -f1)
    _ho_first_chmod=$(grep -n '^chmod ' "$_ho_pin_dir/log" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -n "$_ho_first_chown" ] && [ -n "$_ho_first_chmod" ]; then
        if [ "$_ho_tgt" = opencode ] && [ "$_ho_first_chmod" -lt "$_ho_first_chown" ]; then
            echo "  ${GREEN}PASS${NC}  handover opencode: chmod pass executes before the chown hand-over (W1)"
            passed=$((passed + 1))
        elif [ "$_ho_tgt" = me ] && [ "$_ho_first_chown" -lt "$_ho_first_chmod" ]; then
            echo "  ${GREEN}PASS${NC}  handover me: chown hand-over executes before the chmod pass (W1)"
            passed=$((passed + 1))
        else
            echo "  ${RED}FAIL${NC}  handover $_ho_tgt: execution order wrong (chown=$_ho_first_chown chmod=$_ho_first_chmod, W1)"
            failures=$((failures + 1))
        fi
    else
        echo "  ${RED}FAIL${NC}  handover $_ho_tgt: executor did not run both passes (chown=$_ho_first_chown chmod=$_ho_first_chmod, W1)"
        failures=$((failures + 1))
    fi
done
rm -rf "${_ho_pin_dir:?}"

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
out="$(run_kit ensure-shared "$WORK/es-proj/.ddev" 2>&1)"
assert "ensure-shared exits 0" "0" "$?"
case "$out" in
    *"group-write re-asserted on $WORK/es-proj/.ddev"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared reports success"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared reports success (got: $out)"
        failures=$((failures + 1))
        ;;
esac
assert "ensure-shared passes the dir to the helper" \
    "args=--opk-ensure-shared $WORK/es-proj/.ddev" "$(tail -1 "$WORK/es-marker")"
if [ -f "$WORK/sudo-marker" ]; then
    echo "  ${RED}FAIL${NC}  ensure-shared needs no sudo as the agent user"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  ensure-shared needs no sudo as the agent user"
    passed=$((passed + 1))
fi

# no argument: defaults to ./.ddev from the current directory
: >"$WORK/es-marker"
(cd "$WORK/es-proj" && OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" ensure-shared >/dev/null 2>&1)
assert "ensure-shared defaults to ./.ddev" \
    "args=--opk-ensure-shared $WORK/es-proj/.ddev" "$(tail -1 "$WORK/es-marker")"

# nonexistent dir -> loud usage error BEFORE any sudo hop (nobody conf:
# the happy path would elevate, the error path must not)
rm -f "${WORK:?}/sudo-marker"
errout="$(OPK_INSTALL_CONF="$WORK/install-nobody.conf" "$BIN/opk" ensure-shared "$WORK/does-not-exist" 2>&1 >/dev/null || true)"
case "$errout" in
    *"no such directory"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared rejects nonexistent dirs"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared rejects nonexistent dirs (got: $errout)"
        failures=$((failures + 1))
        ;;
esac
if [ -f "$WORK/sudo-marker" ]; then
    echo "  ${RED}FAIL${NC}  ensure-shared validates before the sudo hop"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  ensure-shared validates before the sudo hop"
    passed=$((passed + 1))
fi

# more than one argument -> usage error
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" ensure-shared a b 2>&1 >/dev/null || true)"
case "$errout" in
    *"exactly one directory"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared rejects extra arguments"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared rejects extra arguments (got: $errout)"
        failures=$((failures + 1))
        ;;
esac

# no install.conf / no OPENCODE_USER -> loud error, no elevation
errout="$(OPK_INSTALL_CONF="$WORK/no-such.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 >/dev/null || true)"
case "$errout" in
    *"is the kit installed"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared names a missing install.conf"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared names a missing install.conf (got: $errout)"
        failures=$((failures + 1))
        ;;
esac
printf 'DEFAULT_USER=%s\nVERSION=9.9.9\n' "$(id -un)" >"$WORK/install-nouser.conf"
errout="$(OPK_INSTALL_CONF="$WORK/install-nouser.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 >/dev/null || true)"
case "$errout" in
    *"no OPENCODE_USER"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared names a missing OPENCODE_USER"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared names a missing OPENCODE_USER (got: $errout)"
        failures=$((failures + 1))
        ;;
esac

# missing helper -> loud error
rm "${LIB:?}/bin/ddev-as-opencode"
errout="$(OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 >/dev/null || true)"
case "$errout" in
    *"is the kit installed"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared names a missing helper"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared names a missing helper (got: $errout)"
        failures=$((failures + 1))
        ;;
esac
cp "$WORK/es-helper-master" "$LIB/bin/ddev-as-opencode"
chmod +x "$LIB/bin/ddev-as-opencode"

# different agent user (nobody): hops through sudo -u, args intact
rm -f "${WORK:?}/sudo-marker"
: >"$WORK/es-marker"
out="$(OPK_INSTALL_CONF="$WORK/install-nobody.conf" "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1)"
assert "ensure-shared (sudo path) exits 0" "0" "$?"
assert "ensure-shared (sudo path) passes the dir to the helper" \
    "args=--opk-ensure-shared $WORK/es-proj/.ddev" "$(tail -1 "$WORK/es-marker")"
if [ -f "$WORK/sudo-marker" ]; then
    echo "  ${GREEN}PASS${NC}  ensure-shared hops to the agent user via sudo -u"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  ensure-shared hops to the agent user via sudo -u"
    failures=$((failures + 1))
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
    echo "  ${GREEN}PASS${NC}  ensure-shared exits non-zero when sudo fails"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  ensure-shared exits non-zero when sudo fails"
    failures=$((failures + 1))
fi
errout="$(PATH="$FAILBIN:$PATH" OPK_INSTALL_CONF="$WORK/install-nobody.conf" \
    "$BIN/opk" ensure-shared "$WORK/es-proj/.ddev" 2>&1 || true)"
case "$errout" in
    *"could not run"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared reports the failed heal"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared reports the failed heal (got: $errout)"
        failures=$((failures + 1))
        ;;
esac
case "$errout" in
    *"--opk-ensure-shared"*)
        echo "  ${GREEN}PASS${NC}  ensure-shared prints the long-form fallback"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  ensure-shared prints the long-form fallback (got: $errout)"
        failures=$((failures + 1))
        ;;
esac
unset ES_MARKER

# List drift guard: install.sh's fetch_kit() list and update.sh's KIT_FILES
# must carry the same file set — a missing entry means streamed installs
# fetch an incomplete kit and crash at deploy time (set -e).
install_list="$(sed -n '/^fetch_kit() {/,/^}/p' "$SCRIPT_DIR/../../files/install.sh" |
    grep -v 'mkdir' |
    grep -vE '^[[:space:]]*("\$dir/[^"]*"[[:space:]]*)+\\?$' |
    grep -oE '(install|config|update|uninstall|status)\.sh|opencode(-deny-all)?\.jsonc|sudoers\.template|umask\.sh|VERSION|etc/[a-zA-Z0-9./_-]+|opencode-permissions-kit-lib/[a-zA-Z0-9./_-]+' | sort -u)"
update_list="$(awk '/^KIT_FILES=/{flag=1} flag{printf "%s ", $0} flag && /"[[:space:]]*$/{exit}' "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh" |
    sed -e 's/^KIT_FILES="//' -e 's/"[[:space:]]*$//' -e 's/\\//g' | tr ' ' '\n' | grep -v '^$' | sort -u)"
if [ "$install_list" = "$update_list" ]; then
    echo "  ${GREEN}PASS${NC}  install.sh fetch list == update.sh KIT_FILES"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  install.sh fetch list == update.sh KIT_FILES"
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
    echo "  ${RED}FAIL${NC}  migrate-denies.sh stub must not exist (stub era ended with 0.0.29)"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  no migrate-denies.sh stub (stub era ended with 0.0.29)"
    passed=$((passed + 1))
fi
if sed -n 's/^KIT_FILES="\(.*\)"$/\1/p' "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh" | grep -q 'opencode-permissions-kit-lib/migrate-denies.sh'; then
    echo "  ${RED}FAIL${NC}  stub must NOT be in KIT_FILES (never deployed)"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  stub not in KIT_FILES (never deployed)"
    passed=$((passed + 1))
fi

# ddev-hosts sudo re-exec: HOME via getent (0.0.43b W1). After the re-exec
# ddev_hosts_add runs AS the developer, so its own getent fix (0.0.43a F12)
# never fires on this path — the value passed here is the one ddev sees;
# a hardcoded /home/<user> would reintroduce the F12 symptom on relocated
# homes, on one of the two documented invocation paths.
if grep -qF 'env HOME="$_kit_home"' "$BIN/opk" &&
    grep -qF '_kit_home=$(getent passwd "$_kitsu"' "$BIN/opk" &&
    ! grep -qF 'HOME="/home/$_kitsu"' "$BIN/opk"; then
    echo "  ${GREEN}PASS${NC}  ddev-hosts re-exec resolves HOME via getent (0.0.43b W1)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  ddev-hosts re-exec resolves HOME via getent (0.0.43b W1)"
    failures=$((failures + 1))
fi

# --- damaged-library fallback ui_confirm (issue #187 C) -------------------------
# The fallback definition in bin/opk exists only for a damaged library
# (sh/ui.sh missing) — extract it and run it standalone under a real
# pty (script(1)): it reads /dev/tty ONLY (no stdin fallback, fails
# closed). Mixed-case answers must be honored — the old arms
# y|Y|yes|YES mapped Yes/No/yEs to the DEFAULT, silently declining an
# explicit yes and accepting an explicit no under a y default. Unknown
# input falls back to the default; the shape is ui_confirm's
# marker-less render.
OPK_UC="$(sed -n '/^    ui_confirm() {/,/^    }/p' "$KIT")"
if [ -n "$OPK_UC" ] && printf '%s' "$OPK_UC" | grep -qF "tr '[:upper:]' '[:lower:]'"; then
    echo "  ${GREEN}PASS${NC}  opk fallback ui_confirm extractable (lowercased, issue #187 C)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  opk fallback ui_confirm extractable (lowercased, issue #187 C)"
    failures=$((failures + 1))
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
            echo "  ${GREEN}PASS${NC}  $1"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  $1 (got: $_ocline)"
            failures=$((failures + 1))
            ;;
    esac
}
oc_pin "opk fallback: mixed-case Yes accepted under an n default (issue #187 C)" Yes n yes
oc_pin "opk fallback: mixed-case No declines under a y default (issue #187 C)" No y no
oc_pin "opk fallback: unknown input falls back to a y default (issue #187 A class)" garbage y yes
oc_pin "opk fallback: unknown input falls back to an n default (issue #187 A class)" garbage n no
oc_pin "opk fallback: padded ' y' accepted under an n default (#189 a W2)" " y" n yes
oc_pin "opk fallback: trailing-space 'no ' declines under a y default (#189 a W2)" "no " y no
oc_pin "opk fallback: empty input fails closed to the default" "" n no
_ocline=$(opk_uc "" y)
if printf '%s' "$_ocline" | grep -qF '  Remove them now? [Y/n] ' &&
    ! printf '%s' "$_ocline" | grep -qF '[?]'; then
    echo "  ${GREEN}PASS${NC}  opk fallback shape: '  <question> [Y/n] ' — no marker (issue #187 B)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  opk fallback shape: '  <question> [Y/n] ' — no marker (got: $_ocline)"
    failures=$((failures + 1))
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
_stubs=$(mktemp -d)
sed -n '/^\[ -n "\$_handover" \] || ddev_handover_root/,/^}$/p' "$CONFIG" >"$_stubs/ho.sh"
sed -n '/^\[ -n "\$_handover" \] || ddev_rootless_bindmounts/,/^}$/p' "$CONFIG" >"$_stubs/rb.sh"
sed -n '/^command -v fs_baseline_root/,/^}$/p' "$CONFIG" >"$_stubs/fsb.sh"
for _s in ho rb fsb; do
    if [ -s "$_stubs/$_s.sh" ] && grep -q 'unavailable' "$_stubs/$_s.sh"; then
        echo "  ${GREEN}PASS${NC}  F2: $_s stub present and names its cause"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  F2: $_s stub present and names its cause"
        failures=$((failures + 1))
    fi
done
_rc=0
_out=$(_handover="" sh -c '. "$1" >/dev/null 2>&1; ddev_handover_root /proj u g d' \
    sh "$_stubs/ho.sh" 2>&1) || _rc=$?
assert "F2: ddev_handover_root stub returns 1 (loud, not 127-silent)" "1" "${_rc:-0}"
case "$_out" in
    *"ddev_handover_root unavailable"*)
        echo "  ${GREEN}PASS${NC}  F2: ddev_handover_root stub names the missing lib on stderr"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  F2: ddev_handover_root stub names the missing lib on stderr (got: $_out)"
        failures=$((failures + 1))
        ;;
esac
# _rc must be reset before EVERY capture — a stale value from the
# previous block masked a silent-stub regression during the F2 pin's
# own sabotage verification (L4).
_rc=0
_out=$(_handover="" sh -c '. "$1" >/dev/null 2>&1; fs_baseline_root /proj g u' \
    sh "$_stubs/fsb.sh" 2>&1) || _rc=$?
assert "F2: fs_baseline_root stub returns 1 (no false 'baseline refreshed')" "1" "${_rc:-0}"
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
    echo "  ${GREEN}PASS${NC}  F2: set -e aborts before any success line (REACHED not printed)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  F2: set -e aborts before any success line (REACHED printed)"
    failures=$((failures + 1))
fi
# ddev_rootless_bindmounts: rc 2 = the backend switch's warn arm — the
# gate must not evaluate as success (rc 127 fell through silently).
_rc=0
_handover="" sh -c '. "$1" >/dev/null 2>&1; ddev_rootless_bindmounts u b v bin' \
    sh "$_stubs/rb.sh" >/dev/null 2>&1 || _rc=$?
assert "F2: ddev_rootless_bindmounts stub returns 2 (caller's warn arm)" "2" "$_rc"
# The update.sh twins of the same stub (#211 a F2 sweep — its loop logs
# "ddev handover pass completed" unconditionally; #211 b W3 — the
# fs_baseline_root stub in the --refresh section was missed by the same
# sweep): loud rc 1 as well. EXECUTED, not just grepped (#211 b W12):
# a presence-only pin passes a `return 0` regression with the echo kept.
sed -n '/^        command -v ddev_handover_root/,/^        }$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh" >"$_stubs/uho.sh"
sed -n '/^        command -v fs_baseline_root/,/^        }$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh" >"$_stubs/ufsbl.sh"
for _stubpair in uho:ddev_handover_root:handover ufsbl:fs_baseline_root:baseline; do
    _short="${_stubpair%%:*}"
    _rest="${_stubpair#*:}"
    _fn="${_rest%%:*}"
    _lbl="${_rest##*:}"
    _rc=0
    _msg=$(sh -c '. "$1"; "$2" u b v' sh "$_stubs/$_short.sh" "$_fn" 2>&1 >/dev/null) || _rc=$?
    if [ "$_rc" -eq 1 ] && printf '%s' "$_msg" | grep -q 'unavailable'; then
        echo "  ${GREEN}PASS${NC}  F2 sweep: update.sh $_lbl stub loud (executes: rc 1 + stderr) (#211 b W3, b W12)"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  F2 sweep: update.sh $_lbl stub loud (rc=$_rc msg=$_msg) (#211 b W3, b W12)"
        failures=$((failures + 1))
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
# the eval fails confusingly. Bound it: the loop+gate is 51 lines
# (shfmt-canonical since the #255 stage 0a reformat; was 47 joined).
if [ -n "$_f11_block" ] && [ "$(printf '%s\n' "$_f11_block" | wc -l)" -le 54 ]; then
    echo "  ${GREEN}PASS${NC}  config arg loop + F11 gate extractable (#211 a F11)"
    passed=$((passed + 1))
    _f11_run() {
        (
            YES=false
            ACTION=""
            SUB=""
            TARGETS=""
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
            echo "  ${GREEN}PASS${NC}  junk token after an action dies loudly (#211 a F11)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  junk token after an action dies loudly (out=$_out)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f11_run status refresh) || true
    case "$_out" in
        *die:*)
            echo "  ${GREEN}PASS${NC}  misplaced second action word dies (#211 a F11)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  misplaced second action word dies (out=$_out)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f11_run projects add /a/proj) || true
    case "$_out" in
        *"OK ACTION=[projects] SUB=[add] TARGETS=[/a/proj]"*)
            echo "  ${GREEN}PASS${NC}  projects add keeps its path targets (#211 a F11)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  projects add keeps its path targets (out=$_out)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f11_run git-config status) || true
    case "$_out" in
        *"OK ACTION=[git-config] SUB=[status] TARGETS=[]"*)
            echo "  ${GREEN}PASS${NC}  git-config status consumed as SUB, e2e flow intact (#211 a F11)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  git-config status consumed as SUB (out=$_out)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f11_run git-config off status) || true
    case "$_out" in
        *"die: unknown or misplaced argument(s):status"*)
            echo "  ${GREEN}PASS${NC}  status no longer clobbers a set SUB — dies loud (#211 b W20)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  status no longer clobbers a set SUB (out=$_out) (#211 b W20)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f11_run refresh status) || true
    case "$_out" in
        *"OK ACTION=[refresh] SUB=[status] TARGETS=[]"*)
            echo "  ${GREEN}PASS${NC}  refresh status still consumed (SUB was empty) (#211 b W20)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  refresh status still consumed (out=$_out) (#211 b W20)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f11_run handover /a/proj) || true
    case "$_out" in
        *"OK ACTION=[handover] SUB=[] TARGETS=[/a/proj]"*)
            echo "  ${GREEN}PASS${NC}  handover keeps its documented path target (#211 a F11)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  handover keeps its documented path target (out=$_out)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f11_run --yes) || true
    case "$_out" in
        *"OK ACTION=[] SUB=[] TARGETS=[]"*)
            echo "  ${GREEN}PASS${NC}  bare --yes stays clean (#211 a F11)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  bare --yes stays clean (out=$_out)"
            failures=$((failures + 1))
            ;;
    esac
else
    echo "  ${RED}FAIL${NC}  config arg loop + F11 gate extractable (#211 a F11)"
    failures=$((failures + 1))
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
        echo "  ${GREEN}PASS${NC}  chained symlink dispatches (readlink -f, #211 a F15)"
        passed=$((passed + 1))
        ;;
    *)
        echo "  ${RED}FAIL${NC}  chained symlink dispatches (#211 a F15, got: $_out)"
        failures=$((failures + 1))
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
    echo "  ${GREEN}PASS${NC}  F24 guard block extractable"
    passed=$((passed + 1))
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
            echo "  ${GREEN}PASS${NC}  missing lib names itself (#211 a F24)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  missing lib names itself (got: $_out)"
            failures=$((failures + 1))
            ;;
    esac
    _out=$(_f24_run yes) || true
    case "$_out" in
        *NOT-REACHED*)
            echo "  ${GREEN}PASS${NC}  healthy helper passes through (#211 a F24)"
            passed=$((passed + 1))
            ;;
        *)
            echo "  ${RED}FAIL${NC}  healthy helper passes through (got: $_out)"
            failures=$((failures + 1))
            ;;
    esac
else
    echo "  ${RED}FAIL${NC}  F24 guard block extractable"
    failures=$((failures + 1))
fi

# --- F26: config.sh status shows the backend row like the menu --------------------
if sed -n '/^    status)$/,/^        ;;$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh" |
    tr '\n' ' ' | grep -qE 'banner +git_config_status +container_backend_status'; then
    echo "  ${GREEN}PASS${NC}  config status lists the backend row (menu parity, #211 a F26)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  config status lists the backend row (#211 a F26)"
    failures=$((failures + 1))
fi

# --- openchamber-secure settings edit: guard inside the sudo context (#244 f W2) --
# The #244 e-S1 class fix at opk's settings-edit compound: guard and exec
# share ONE PATH (the sudo context). Static shape pins, then functional
# asymmetry arms — the compound is extracted from opk (the F24 idiom)
# and driven with PATH-fixing sudo shims over a binary farm (the
# test-tui-mode arm idiom).
OCW2_BLOCK="$(sed -n '/#244 f W2/,/^            fi$/p' "$KIT")"
# Bound is 35 lines: 33 (the #244 f W2 compound) + 2 for pr-00263 c C2
# (the else branch exits 1 instead of falling through to exit 0).
if [ -n "$OCW2_BLOCK" ] &&
    [ "$(printf '%s\n' "$OCW2_BLOCK" | wc -l)" -le 35 ] &&
    printf '%s\n' "$OCW2_BLOCK" |
    grep -qF 'sh -c ' &&
    printf '%s\n' "$OCW2_BLOCK" |
    grep -qF 'command -v python3 >/dev/null 2>&1 && exec python3 "$@"'; then
    echo "  ${GREEN}PASS${NC}  settings-edit guard runs inside the sudo context (#244 f W2)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  settings-edit guard inside the sudo context (#244 f W2)"
    failures=$((failures + 1))
fi
if printf '%s\n' "$OCW2_BLOCK" | grep -qE '^ +if command -v python3'; then
    echo "  ${RED}FAIL${NC}  settings-edit guard is caller-side again (#244 f W2)"
    failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  no caller-side guard shape in the settings edit (#244 f W2)"
    passed=$((passed + 1))
fi
if [ -z "$OCW2_BLOCK" ]; then
    echo "  ${RED}FAIL${NC}  settings-edit block extractable for asymmetry arms (#244 f W2)"
    failures=$((failures + 1))
elif ! command -v python3 >/dev/null 2>&1; then
    # Distinct failure surface (#244 g Q1): extraction failure and
    # the arms' python3 hard-require are different causes — one
    # label each, per the check-host make-test contract.
    echo "  ${RED}FAIL${NC}  settings-edit asymmetry arms need python3 (check-host contract) (#244 g Q1)"
    failures=$((failures + 1))
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
        echo "  ${GREEN}PASS${NC}  settings edit arm A: exec context without python3 stays silent, rc 1 (pr-00263 c C2)"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  settings edit arm A (#244 f W2 + pr-00263 c C2, rc=$_ocrc, got: $_ocout)"
        failures=$((failures + 1))
    fi
    # Arm B: caller PATH has NO python3, exec context the real one — a
    # caller-side guard would skip the edit; the inner guard runs it
    # (the settings file itself is the proof). Success stays rc 0.
    _ocrc=0
    _ocout="$(_ocw2_run "$OCW2ABSB")" || _ocrc=$?
    if [ "$_ocrc" -eq 0 ] && printf '%s' "$_ocout" | grep -q W2:success &&
        ! grep -q opencodeBinary "$OCW2/case/settings.json" &&
        grep -q '"port": 3000' "$OCW2/case/settings.json"; then
        echo "  ${GREEN}PASS${NC}  settings edit arm B: exec-context python3 edits despite caller absence (#244 f W2)"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  settings edit arm B (#244 f W2, rc=$_ocrc, got: $_ocout)"
        failures=$((failures + 1))
    fi
    rm -rf "$OCW2"
fi

# --- openchamber-secure settings edit: value-shaped match fails loud (#244 g S1) --
# The outer grep needle '"opencodeBinary"' can hit the literal as a
# VALUE; the edit script must not report success then (#244 g S1
# added the else-exit). Direct behavioral pins on the extracted
# heredoc script — both directions, python3 hard-required (labels
# say so; the check-host make-test contract).
OPYSCR="$(sed -n '/opk-settings-edit/,/^PYEOF$/p' "$KIT" | sed '1d;$d')"
if [ -z "$OPYSCR" ] || ! printf '%s\n' "$OPYSCR" | grep -qF 'del d["opencodeBinary"]' ||
    ! printf '%s\n' "$OPYSCR" | grep -qF 'sys.exit(1)'; then
    echo "  ${RED}FAIL${NC}  settings-edit python script extractable (anchors: del d[\"opencodeBinary\"], sys.exit(1)) (#244 g S1)"
    failures=$((failures + 1))
elif ! command -v python3 >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  settings-edit S1 pins need python3 (check-host contract) (#244 g S1)"
    failures=$((failures + 1))
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
        echo "  ${GREEN}PASS${NC}  value-shaped opencodeBinary match fails silent, file untouched (#244 g S1)"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  value-shaped opencodeBinary match fails silent, file untouched (#244 g S1, rc=$_s1rc out=[$_s1out])"
        failures=$((failures + 1))
    fi
    # Key-shaped match: rc 0, key gone, other keys preserved — the
    # S1 change must not break the success path.
    printf '{ "opencodeBinary": "/x", "port": 3000 }\n' >"$OCW2S1/key.json"
    if printf '%s\n' "$OPYSCR" | python3 - "$OCW2S1/key.json" >/dev/null 2>&1 &&
        ! grep -q opencodeBinary "$OCW2S1/key.json" &&
        grep -q '"port": 3000' "$OCW2S1/key.json"; then
        echo "  ${GREEN}PASS${NC}  key-shaped opencodeBinary removed, other keys preserved (#244 g S1)"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  key-shaped opencodeBinary removal (#244 g S1)"
        failures=$((failures + 1))
    fi
    rm -rf "$OCW2S1"
fi

# pr-00263 a F21: the settings-edit failure message names the entry as
# key-or-value — the grep can match the literal as a VALUE, "remove the
# line" was wrong for that arm.
grep -qF 'entry (key or value) by hand' "$KIT" &&
    echo "  ${GREEN}PASS${NC}  settings-edit failure names key-or-value (pr-00263 a F21)" && passed=$((passed + 1)) ||
    {
        echo "  ${RED}FAIL${NC}  settings-edit wording residue survives (pr-00263 a F21)"
        failures=$((failures + 1))
    }

echo ""
if [ "$failures" -gt 0 ]; then
    echo "${RED}$failures test(s) failed${NC}"
    exit 1
fi
echo "${GREEN}All CLI dispatcher tests passed.${NC}"
exit 0
