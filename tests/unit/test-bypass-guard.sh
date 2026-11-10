#!/bin/sh
# Unit tests for the wrapper-bypass guard (self-install / absolute-path
# protection). Two layers are checked:
#   (1) Functional: files/opencode-permissions-kit-lib/sh/shell-warn.sh warns
#       when a self-installed opencode binary shadows the wrapper, and stays
#       quiet when the wrapper is in charge.
#   (2) Static wiring: install.sh, update.sh, the wrapper, umask.sh and the
#       git index modes reference the guard consistently so a streamed
#       `curl | bash` install fetches, deploys, hooks, and updates it.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/../.."
WARN="$REPO/files/opencode-permissions-kit-lib/sh/shell-warn.sh"
WRAPPER="$REPO/files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
# Wrapper core lib since #449 (the #346 wave shape): pins on moved
# wrapper code target the lib.
WRAPPER_CORE="$REPO/files/opencode-permissions-kit-lib/sh/as-opencode-core.sh"
INSTALL="$REPO/files/install.sh"
INSTALL_CORE="$REPO/files/opencode-permissions-kit-lib/sh/install-core.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
UPDATE_CORE="$REPO/files/opencode-permissions-kit-lib/sh/update-core.sh"
SECUREBIN="$REPO/files/opencode-permissions-kit-lib/sh/secure-binary.sh"
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
UMASK="$REPO/files/etc/umask.sh"
TEST_YML="$REPO/.github/workflows/test-unit.yml"

# Shared harness (issue #444 adoption, full local check()/counter stack):
# pass/fail rows, the counters and the summary gate live in
# lib/harness.sh now; the scratch receivers register with the work
# registry (issue #395) and the local trap is gone (a local trap would
# disarm the central registry trap).
. "$SCRIPT_DIR/lib/harness.sh"

# Source shell-warn.sh with a controlled HOME/PATH; prints nothing on stderr
# when quiet, the warning text when triggered.
run_warn() {
    local home="$1" path="$2"
    HOME="$home" PATH="$path" sh -c '. "$0"' "$WARN" 2>&1
}

TMP="$(work_new)"

echo ""
echo "Wrapper-Bypass Guard Tests"
echo "============================"
echo ""

echo "-- shell-warn.sh functional --"
mkdir -p "$TMP/bin"
printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/opencode"
chmod +x "$TMP/bin/opencode"

out=$(run_warn "$TMP/clean-home" "/usr/bin:/bin")
check "clean home, no opencode on PATH: quiet" [ -z "$out" ]

mkdir -p "$TMP/home-shadow/.opencode/bin"
echo "not-the-wrapper" >"$TMP/home-shadow/.opencode/bin/opencode"
out=$(run_warn "$TMP/home-shadow" "/usr/bin:/bin")
check "shadow real binary: warns" sh -c 'echo "$1" | grep -q "wrapper bypass"' _ "$out"
check "shadow real binary: suggests fix" sh -c 'echo "$1" | grep -q "rm -rf"' _ "$out"
check "shadow real binary: suggests opk shorthand, not the library path (issue #62)" \
    sh -c 'echo "$1" | grep -q "sudo opk update" && ! echo "$1" | grep -q "management/update.sh"' _ "$out"

mkdir -p "$TMP/home-link/.opencode/bin"
ln -s /usr/local/lib/opencode-permissions-kit/bin/opencode-as-opencode "$TMP/home-link/.opencode/bin/opencode"
out=$(run_warn "$TMP/home-link" "/usr/bin:/bin")
check "shadow symlink to kit wrapper: quiet" [ -z "$out" ]

out=$(run_warn "$TMP/clean-home" "$TMP/bin:/usr/bin:/bin")
check "PATH resolves to non-wrapper opencode: warns" sh -c 'echo "$1" | grep -q "resolves to"' _ "$out"

check "script is sourceable (uses return, not exit)" \
    sh -c 'grep -Eq "return 0" "$1" && ! grep -Eq "^[[:space:]]*exit" "$1"' _ "$WARN"

echo ""
echo "-- umask.sh / wrapper wiring --"
check "umask.sh sources shell-warn.sh" \
    grep -Fq 'shell-warn.sh' "$UMASK"
check "wrapper self-checks for shadow binary" \
    grep -Fq 'self-installed opencode detected' "$WRAPPER_CORE"
check "wrapper self-checks PATH resolution" \
    grep -Fq "'opencode' on this PATH resolves to" "$WRAPPER_CORE"

echo ""
echo "-- install.sh wiring --"
check "install.sh fetches shell-warn.sh" \
    grep -Fq 'opencode-permissions-kit-lib/sh/shell-warn.sh' "$INSTALL"
check "install.sh deploys shell-warn.sh to LIBDIR (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/shell-warn.sh 644" "$2" \
        && grep -qF "lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"" "$1"' _ "$INSTALL_CORE" "$DEPLOYLIB"
# #376 B3 class sweep — install.sh's twin of update.sh's VERSION gate
# (behavioral, extraction-driven): the streamed/fetched VERSION is
# remote-mirror content stamped into the root-sourced install.conf; a
# malformed file aborts BEFORE the banner or any step runs.
_BGW="$(work_new)"
sed -n '/^if \[ -f "\$SCRIPT_DIR\/\.\.\/VERSION" \]; then/,/^fi$/p' "$INSTALL" >"$_BGW/vergate.sh"
mkdir -p "$_BGW/proj" # [ -f ] resolves THROUGH proj/.. — without it the gate never fires
printf '0.0.59-suffix\n' >"$_BGW/VERSION"
if _bgw_out=$(SCRIPT_DIR="$_BGW/proj" sh "$_BGW/vergate.sh" 2>&1); then
    _bgw_rc=0
else
    _bgw_rc=$?
fi
if [ "$_bgw_rc" -ne 0 ] &&
    printf '%s\n' "$_bgw_out" | grep -qF "error: fetched VERSION file is malformed (expected x.y.z, got '0.0.59-suffix')"; then
    pass "install.sh gates its fetched VERSION to x.y.z (#376 B3 sweep)"
else
    fail "install.sh VERSION gate missing (rc=$_bgw_rc out=$_bgw_out) (#376 B3 sweep)"
fi
# #211 b W4: the sourced-lib mode invariant needs a pin per lib —
# shell-warn.sh was the only one here (log.sh via test-deploy-lib);
# advisories.sh and ui.sh had no mode pin anywhere. Modes flipped 755 ->
# 644 by #377 F2 (review #370 a F2): nothing executes them by path (the
# git index has been 644 all along); the manifest's own "sourced libs
# 644" rule now applies to them too.
check "install.sh deploys advisories.sh to LIBDIR (lib_deploy manifest, 644)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/advisories.sh 644" "$2"' _ "$INSTALL" "$DEPLOYLIB"
check "install.sh deploys ui.sh to LIBDIR (lib_deploy manifest, 644)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/ui.sh 644" "$2"' _ "$INSTALL" "$DEPLOYLIB"
# The rc-hook emissions live in do_deploy_phase — install-core.sh since
# #346 wave 3 (the fetch-list pins above stay on the entry).
check "install.sh hooks shell-warn.sh into rc files" \
    grep -Fq 'opencode-permissions-kit/sh/shell-warn.sh' "$INSTALL_CORE"
# #331 b b-1: install.sh's hook emissions have no functional unit
# renderer (root/sudo deploy phase; e2e covers them with substring
# greps only). Pin the exact wrap construct on the JOINED source --
# empty-replacement continuation join, the conventions-sanctioned
# view for literals spanning a wrap: the seam quotes stay visible in
# it, and a seam mutation (inserted space, lost quote) survives the
# join as a byte change that fails the -qF match. Source-joined equals
# the emitted bytes here: the fragments carry no expansions (the
# functional counterpart pins the rendered lines in test-update-flags).
# The join runs as a PIPE into grep -- the joined view of a ~150 KB
# script must not travel through argv (the 128 KiB single-argument
# limit makes the whole check E2BIG, a fail-loud trap).
check "install.sh shell-warn wrap byte-exact on joined source (splice-seam pin)" \
    sh -c "sed -e ':a' -e '/\\\\$/N; s/\\\\\\n//; ta' \"\$1\" | grep -qF '\"[ -f /usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh ] && . \"\"/usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh  # opencode permissions kit\"\" (wrapper bypass warning)\"'" _ "$INSTALL_CORE"
check "install.sh ddev wrap byte-exact on joined source (splice-seam pin)" \
    sh -c "sed -e ':a' -e '/\\\\$/N; s/\\\\\\n//; ta' \"\$1\" | grep -qF '\"[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . \"\"/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh  # opencode permissions kit\"\" (ddev always runs as opencode)\"'" _ "$INSTALL_CORE"
check "install.sh restricts binary to root:group 750 (shared helper)" \
    sh -c 'grep -Fq "chmod 750 \"\$_sb_bin\"" "$2" && grep -Fq "secure_binary \"\$SYSTEM_BIN\" \"\$BINARY_GROUP\"" "$1"' _ "$INSTALL_CORE" "$SECUREBIN"
# absence pin covers BOTH hosts since #346 wave 3 (the phases live in
# the lib; the entry keeps the definitions and fallbacks)
check "install.sh never uses world-executable binary mode" \
    sh -c '! grep -Fq "chmod 755 \"\$SYSTEM_BIN\"" "$1" && ! grep -Fq "chmod 755 \"\$SYSTEM_BIN\"" "$3"' _ "$INSTALL" "$SECUREBIN" "$INSTALL_CORE"
# Issue #163: install.sh's four binary deploys (found-binary menu x2,
# official-installer x2) must go through the shared atomic helper — a
# plain in-place cp killed mid-write leaves a truncated binary with
# intact mode bits (dead at the first agent session). Behavioral pins
# for the helper itself live in test-secure-binary.sh.
# 0.0.49a W6: the count pattern carries the opening quote of the first
# argument, so it counts CALL SITES only (the `command -v` wiring line
# and the fallback definition don't match) — and -eq, not -ge: adding a
# fifth site must be a conscious pin update, not a silent pass.
check "install.sh defines the atomic-copy fallback for a missing lib (#163)" \
    sh -c 'grep -A1 -F "copy_binary_atomic() {" "$1" | grep -Fq "echo \"error: copy_binary_atomic unavailable"' _ "$INSTALL"
# Comment-strip rider (#261, the #244 g W1 class): commented-out call
# sites must not count. Full-line comments only (#244 h W6 residual):
# a trailing comment after a live line still counts. The four call
# sites live in do_deploy_phase — install-core.sh since #346 wave 3.
_cbina_n="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" | grep -cF 'copy_binary_atomic "' || true)"
check "install.sh deploys the binary through the atomic helper at exactly four call sites (#163, 0.0.49a W6; call sites: $_cbina_n of 4)" \
    [ "$_cbina_n" -eq 4 ]
check "install.sh no longer sudo-cps directly onto SYSTEM_BIN (#163)" \
    sh -c '! grep -Fq "sudo cp \"\$loc\" \"\$SYSTEM_BIN\"" "$1" \
        && ! grep -Fq "sudo cp \"/root/.opencode/bin/opencode\" \"\$SYSTEM_BIN\"" "$1" \
        && ! grep -Fq "sudo cp \"\$DEV_HOME/.opencode/bin/opencode\" \"\$SYSTEM_BIN\"" "$1" \
        && ! grep -Fq "sudo cp \"\$loc\" \"\$SYSTEM_BIN\"" "$2" \
        && ! grep -Fq "sudo cp \"/root/.opencode/bin/opencode\" \"\$SYSTEM_BIN\"" "$2" \
        && ! grep -Fq "sudo cp \"\$DEV_HOME/.opencode/bin/opencode\" \"\$SYSTEM_BIN\"" "$2"' _ "$INSTALL" "$INSTALL_CORE"
# 0.0.49b C1: the umask profile deploys through the mode-atomic file
# helper too — a cp killed mid-write over /etc/profile.d/ leaves a
# truncated profile with intact mode bits, sourced at every login
# (the #163 class on a protection layer). Behavioral pins for the
# helper live in test-secure-binary.sh §6.
# 0.0.49c F2: the wiring pins carry the MODE — 644 is load-bearing
# (an unreadable profile is silently skipped by non-root shells), and
# a 644→600 mutation matched no pin before (greps covered the call
# prefix only; e2e checks existence + content, not mode). The old
# in-place shape matches neither grep (its chmod orders 644 BEFORE
# the path), so the combined pin discriminates both axes.
check "install.sh defines the atomic-file fallback for a missing lib (0.0.49b C1)" \
    sh -c 'grep -A1 -F "copy_file_atomic() {" "$1" | grep -Fq "echo \"error: copy_file_atomic unavailable"' _ "$INSTALL"
check "install.sh deploys the umask profile through the atomic file helper at mode 644 (0.0.49b C1, 0.0.49c F2)" \
    sh -c 'grep -Fq "copy_file_atomic \"\$SCRIPT_DIR/etc/umask.sh\"" "$1" \
        && grep -Fq "opencode-permissions-kit-umask.sh 644" "$1"' _ "$INSTALL_CORE"
# 0.0.49c F3: W6's count-pin shape for the new helper — the pattern
# carries the opening quote, so it counts CALL SITES only (the
# command -v wiring line and the fallback definition don't match);
# -eq, not -ge: a second copy_file_atomic deploy must be a conscious
# pin update, not a silent pass.
_cfa_i_n="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL_CORE" | grep -cF 'copy_file_atomic "' || true)"
check "install.sh routes exactly one deploy through copy_file_atomic (0.0.49c F3; deploy sites: $_cfa_i_n of 1)" \
    [ "$_cfa_i_n" -eq 1 ]
check "install.sh no longer sudo-cps the umask profile in place (0.0.49b C1)" \
    sh -c '! grep -Fq "sudo cp \"\$SCRIPT_DIR/etc/umask.sh\" /etc/profile.d" "$1" \
        && ! grep -Fq "sudo cp \"\$SCRIPT_DIR/etc/umask.sh\" /etc/profile.d" "$2"' _ "$INSTALL" "$INSTALL_CORE"

echo ""
echo "-- update.sh wiring --"
check "update.sh fetches shell-warn.sh" \
    grep -Fq 'opencode-permissions-kit-lib/sh/shell-warn.sh' "$UPDATE"
check "update.sh deploys shell-warn.sh to LIBDIR (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/shell-warn.sh 644" "$2" \
        && grep -qF "lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"" "$1"' _ "$UPDATE_CORE" "$DEPLOYLIB"
# #211 b W4: update twins of the advisories/ui mode pins above
# (755 -> 644 by #377 F2, review #370 a F2 — sourced libs, never
# executed by path).
check "update.sh deploys advisories.sh to LIBDIR (lib_deploy manifest, 644)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/advisories.sh 644" "$2"' _ "$UPDATE" "$DEPLOYLIB"
check "update.sh deploys ui.sh to LIBDIR (lib_deploy manifest, 644)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/ui.sh 644" "$2"' _ "$UPDATE" "$DEPLOYLIB"
check "update.sh hooks shell-warn.sh into rc files" \
    grep -Fq 'opencode-permissions-kit/sh/shell-warn.sh' "$UPDATE_CORE"
# 0.0.49b C1 (update twin of the install pins above): the umask
# re-deploy routes through the atomic file helper, never an in-place
# sudo cp over the sourced profile. 0.0.49c F2/F3: mode-carrying
# deploy pin + call-site count, twin-for-twin with the install pins.
# The call site and literals moved to sh/update-core.sh with the
# re-deploy sections (#346 wave 2); the missing-lib fallback stub and
# the sh/secure-binary.sh sourcing reference stay in update.sh.
check "update.sh defines the atomic-file fallback for a missing lib (0.0.49b C1)" \
    sh -c 'grep -A1 -F "copy_file_atomic() {" "$1" | grep -Fq "echo \"error: copy_file_atomic unavailable"' _ "$UPDATE"
check "update.sh re-deploys the umask profile through the atomic file helper at mode 644 (0.0.49b C1, 0.0.49c F2)" \
    sh -c 'grep -Fq "copy_file_atomic \"\$FILES_ROOT/etc/umask.sh\"" "$1" \
        && grep -Fq "opencode-permissions-kit-umask.sh 644" "$1"' _ "$UPDATE_CORE"
_cfa_u_n="$(sed 's/^[[:space:]]*#.*$//' "$UPDATE_CORE" | grep -cF 'copy_file_atomic "' || true)"
check "update.sh routes exactly one deploy through copy_file_atomic (0.0.49c F3; deploy sites: $_cfa_u_n of 1)" \
    [ "$_cfa_u_n" -eq 1 ]
check "update.sh no longer sudo-cps the umask profile in place (0.0.49b C1)" \
    sh -c '! grep -Fq "sudo cp \"\$FILES_ROOT/etc/umask.sh\" /etc/profile.d" "$1" \
        && ! grep -Fq "sudo cp \"\$FILES_ROOT/etc/umask.sh\" /etc/profile.d" "$2"' _ "$UPDATE" "$UPDATE_CORE"
check "update.sh re-asserts binary 750 (shared helper)" \
    sh -c 'grep -Fq "secure_binary \"\$SYSTEM_BIN\" \"\$BINARY_GROUP\"" "$1" && grep -Fq "chmod 750 \"\$_sb_bin\"" "$2" && grep -Fq "sh/secure-binary.sh" "$3"' _ "$UPDATE_CORE" "$SECUREBIN" "$UPDATE"
check "update.sh never uses world-executable binary mode" \
    sh -c '! grep -Fq "chmod 755 \"\$SYSTEM_BIN\"" "$1" \
        && ! grep -Fq "chmod 755 \"\$SYSTEM_BIN\"" "$2"' _ "$UPDATE" "$UPDATE_CORE"

echo ""
echo "-- CI wiring (issue #123: exec bits live in the git index) --"
# shell-warn.sh is a SOURCED lib (rc files, wrapper) — per the repo
# invariant (755 <=> executed by path) it must be tracked 100644; the
# deploy manifest re-asserts its LIBDIR mode on every install/update.
check "shell-warn.sh is a sourced lib (git 100644, not executed by path)" \
    [ "$(git -C "$REPO" ls-files -s -- files/opencode-permissions-kit-lib/sh/shell-warn.sh | awk '{print $1}')" = "100644" ]
check "test-unit.yml runs test-bypass-guard.sh" \
    grep -Fq './tests/unit/test-bypass-guard.sh' "$TEST_YML"

suite_done "wrapper-bypass guard tests"
