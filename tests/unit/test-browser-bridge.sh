#!/bin/sh
# Unit tests for the WSL browser bridge (issue #91):
#   1. bin/browser-bridge stand-in: forwards to the real powershell.exe
#      when the caller may execute it, exit 0 otherwise (the opencode user
#      on a hardened /mnt/c — the login flow must survive the spawn).
#   2. sh/wsl-browser-bridge.sh: the /etc/wsl.conf rewrite (driven through
#      the REAL functions via the OPK_WSL_CONF/OPK_WSL_SUDO/OPK_WSL_FORCE
#      overrides, same convention as DDEV_WIN_HOSTS/FS_SUDO) prepends the
#      kit section, preserves every foreign line, is idempotent, and the
#      remove path restores the original file byte-for-byte.
# Run: sh tests/unit/test-browser-bridge.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
BRIDGE_BIN="$REPO/files/opencode-permissions-kit-lib/bin/browser-bridge"
BRIDGE_SH="$REPO/files/opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Hermetic driver: sourced helper + overrides, zero privileges.
CONF="$WORK/etc/wsl.conf"
LIBDIR="$WORK/lib"
FILES_ROOT="$REPO/files"
mkdir -p "$WORK/etc" "$LIBDIR"

# Default environment for every bridge function call below.
bb() {
    OPK_WSL_CONF="$CONF" OPK_WSL_SUDO="" OPK_WSL_FORCE=1 \
        sh -c '. "$1" && shift && eval "$BB_CALL"' _ "$BRIDGE_SH" "$@"
}

echo ""
echo "--- browser-bridge stand-in ---"

# 1. no real powershell reachable -> exit 0, no output, no crash
if OPK_WSL_C_ROOT="$WORK/nowhere" "$BRIDGE_BIN" -NoProfile -EncodedCommand AAA >/dev/null 2>&1; then
    pass "exit 0 when no real powershell.exe is executable (hardened mount)"
else
    fail "stand-in crashes instead of exit 0 (login flow would die)"
fi

# 2. real powershell reachable -> arguments forwarded verbatim
mkdir -p "$WORK/fakec/Windows/System32/WindowsPowerShell/v1.0"
cat > "$WORK/fakec/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" <<'PS'
#!/bin/sh
printf 'FORWARDED:%s\n' "$1"
PS
chmod 755 "$WORK/fakec/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
_fwd=$(OPK_WSL_C_ROOT="$WORK/fakec" "$BRIDGE_BIN" -EncodedCommand SECRET 2>/dev/null)
if [ "$_fwd" = "FORWARDED:-EncodedCommand" ]; then
    pass "forwards to the real powershell.exe with arguments (developer path)"
else
    fail "forwarding broken (got: '$_fwd')"
fi

# 3. a non-executable real powershell is not spawned (opencode user path)
chmod 644 "$WORK/fakec/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if OPK_WSL_C_ROOT="$WORK/fakec" "$BRIDGE_BIN" >/dev/null 2>&1; then
    pass "exit 0 when the real powershell.exe lacks the exec bit (opencode user)"
else
    fail "stand-in spawns (or fails on) a non-executable powershell.exe"
fi
chmod 755 "$WORK/fakec/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"

echo ""
echo "--- wsl.conf section rewrite (real functions, overridden paths) ---"

# Pre-existing user conf the bridge must preserve byte-for-byte:
cat > "$CONF" <<'CONF'
[boot]
systemd=true

[user]
default=infotest

[automount]
enabled = true
options = "uid=1000,gid=1000,dmask=027,fmask=037"
CONF
cp "$CONF" "$WORK/orig.conf"

# 4. full install: stand-in tree + conf section
BB_CALL='browser_bridge_install "$1" "$2"' bb "$FILES_ROOT" "$LIBDIR"
_SHIM="$LIBDIR/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if [ -f "$_SHIM" ] && [ -x "$_SHIM" ]; then
    pass "install deploys the stand-in at the path open() computes"
else
    fail "stand-in not deployed at $_SHIM"
fi

# 5. the deployed stand-in is the shipped script (not a stale copy)
if cmp -s "$_SHIM" "$BRIDGE_BIN"; then
    pass "deployed stand-in is byte-identical to bin/browser-bridge"
else
    fail "deployed stand-in differs from bin/browser-bridge"
fi

# 6. kit section lands at the TOP (first `root =` in the file wins open's scan)
if head -1 "$CONF" | grep -q '^\[opencode-permissions-kit\]$'; then
    pass "kit section is the first section in wsl.conf (wins open's first-match scan)"
else
    fail "kit section is not at the top of wsl.conf"
fi

# 7. the `root =` line points into the kit library
if grep -q "^root = $LIBDIR/wsl\$" "$CONF"; then
    pass "kit root = line points at the library wsl/ tree"
else
    fail "kit root = line missing or wrong"
fi

# 8. every foreign line survives below the section (7-line kit block + blank)
if tail -n +8 "$CONF" | diff -q - "$WORK/orig.conf" >/dev/null 2>&1; then
    pass "foreign wsl.conf content preserved byte-for-byte below the section"
else
    fail "foreign wsl.conf content altered by the rewrite"
fi

# 9. idempotent: a second install run changes nothing
cp "$CONF" "$WORK/before-second.conf"
BB_CALL='browser_bridge_install "$1" "$2"' bb "$FILES_ROOT" "$LIBDIR"
if diff -q "$CONF" "$WORK/before-second.conf" >/dev/null 2>&1; then
    pass "rewrite is idempotent (second run is a no-op)"
else
    fail "rewrite is not idempotent (section duplicated or content changed)"
fi

# 10. a stale root = value heals (old kit section replaced, not appended)
printf '[opencode-permissions-kit]\nroot = /old/lib/wsl\n\n[boot]\nsystemd=true\n' > "$CONF"
BB_CALL='browser_bridge_write_conf "$1"' bb "$LIBDIR"
if ! grep -q '/old/lib' "$CONF" && grep -q "^root = $LIBDIR/wsl\$" "$CONF"; then
    pass "stale kit section (old root =) is replaced, not duplicated"
else
    fail "stale kit section survives the rewrite"
fi

# 11. the user's own [automount] root = (if they ever set one) stays intact
#     BELOW the kit section — open's first-match still resolves to the kit
printf '[automount]\nroot = /mnt/\nenabled = true\n' > "$WORK/orig-automount.conf"
cp "$WORK/orig-automount.conf" "$CONF"
BB_CALL='browser_bridge_write_conf "$1"' bb "$LIBDIR"
if grep -q "^root = $LIBDIR/wsl\$" "$CONF" \
   && tail -n +8 "$CONF" | diff -q - "$WORK/orig-automount.conf" >/dev/null 2>&1; then
    pass "foreign [automount] root = preserved, kit line still first"
else
    fail "rewrite damages a foreign automount root = line"
fi

# 12. fresh install without any pre-existing wsl.conf works (no read crash)
rm -f "$CONF"
BB_CALL='browser_bridge_write_conf "$1"' bb "$LIBDIR"
if [ -f "$CONF" ] && grep -q "^root = $LIBDIR/wsl\$" "$CONF"; then
    pass "fresh wsl.conf is created when none exists"
else
    fail "fresh-install path broken"
fi

# 13. remove restores the original conf byte-for-byte and drops the tree
cat > "$CONF" <<'CONF'
[boot]
systemd=true

[automount]
enabled = true
options = "uid=1000,gid=1000,dmask=027,fmask=037"
CONF
cp "$CONF" "$WORK/orig2.conf"
BB_CALL='browser_bridge_install "$1" "$2"' bb "$FILES_ROOT" "$LIBDIR"
[ -d "$LIBDIR/wsl" ] || { fail "setup: install did not create the tree"; }
BB_CALL='browser_bridge_remove "$1"' bb "$LIBDIR"
if diff -q "$CONF" "$WORK/orig2.conf" >/dev/null 2>&1; then
    pass "removing the section restores the original conf byte-for-byte"
else
    fail "section removal leaves residue behind"
fi
if [ ! -e "$LIBDIR/wsl" ]; then
    pass "stand-in tree removed with the bridge"
else
    fail "stand-in tree survives browser_bridge_remove"
fi

# 14. remove is safe on a bridge-free conf (no kit section, no tree)
BB_CALL='browser_bridge_remove "$1"' bb "$LIBDIR"
if diff -q "$CONF" "$WORK/orig2.conf" >/dev/null 2>&1; then
    pass "remove is a no-op when no kit section exists"
else
    fail "remove mangles a bridge-free wsl.conf"
fi

echo ""
echo "--- helper contract ---"

# 15. sourcing defines the API and executes nothing (deploy is caller-side)
_api=$(OPK_WSL_CONF="$CONF" OPK_WSL_SUDO="" sh -c '
    . "$1"
    command -v browser_bridge_is_wsl >/dev/null 2>&1 \
    && command -v browser_bridge_write_conf >/dev/null 2>&1 \
    && command -v browser_bridge_install >/dev/null 2>&1 \
    && command -v browser_bridge_remove >/dev/null 2>&1 \
    && echo ok' _ "$BRIDGE_SH")
if [ "$_api" = "ok" ]; then
    pass "helper exports the four bridge functions (sourced, not executed)"
else
    fail "helper API incomplete"
fi

# 16. without OPK_WSL_FORCE the is_wsl probe delegates to /proc/version
#     (whatever that says on the host — WSL dev boxes included)
_raw=no
grep -qi microsoft /proc/version 2>/dev/null && _raw=yes
if OPK_WSL_FORCE=0 sh -c '. "$1" && browser_bridge_is_wsl' _ "$BRIDGE_SH"; then
    _probe=yes
else
    _probe=no
fi
if [ "$_probe" = "$_raw" ]; then
    pass "is_wsl without FORCE follows /proc/version (host: $_raw)"
else
    fail "is_wsl ignores /proc/version without FORCE (probe=$_probe raw=$_raw)"
fi

# 17. install no-ops (gracefully) when the stand-in source is absent —
#     e.g. a partial files/ tree
if OPK_WSL_CONF="$CONF" OPK_WSL_SUDO="" OPK_WSL_FORCE=1 \
    sh -c '. "$1" && browser_bridge_install "$2" "$3"' _ "$BRIDGE_SH" "$WORK/no-such-files-root" "$LIBDIR" >/dev/null 2>&1; then
    pass "install no-ops when the stand-in source file is missing"
else
    fail "install fails on a missing stand-in source"
fi

echo ""
echo "--- diagnostics (debug trace + tty hint) ---"

# 18. without the debug env the no-op path is completely silent (opencode's
#     spawn would show any stdout/stderr noise in the login dialog)
_out="$(OPK_WSL_C_ROOT="$WORK/nowhere" "$BRIDGE_BIN" -EncodedCommand X 2>&1)"
if [ -z "$_out" ]; then
    pass "no-op path is silent without OPK_BROWSER_BRIDGE_DEBUG"
else
    fail "no-op path leaks output without the debug env (got: '$_out')"
fi

# 19. with the debug env the no-op path traces the decision
if OPK_BROWSER_BRIDGE_DEBUG=1 OPK_WSL_C_ROOT="$WORK/nowhere" "$BRIDGE_BIN" -EncodedCommand X 2>&1 \
   | grep -q "browser-bridge\[debug\]: no real powershell reachable"; then
    pass "debug env traces the no-op decision"
else
    fail "debug env does not trace the no-op decision"
fi

# 20. with the debug env the forwarding path traces target + decision
if OPK_BROWSER_BRIDGE_DEBUG=1 OPK_WSL_C_ROOT="$WORK/fakec" "$BRIDGE_BIN" 2>&1 \
   | grep -q "browser-bridge\[debug\]: forwarding to $WORK/fakec"; then
    pass "debug env traces the forwarding decision"
else
    fail "debug env does not trace the forwarding decision"
fi

# 21. the no-op hint goes to the controlling terminal, not stdout/stderr:
#     under a pty (script -e) it must appear, detached it must not.
if command -v script >/dev/null 2>&1; then
    _pty_out="$(script -qec "OPK_WSL_C_ROOT='$WORK/nowhere' '$BRIDGE_BIN'" /dev/null 2>&1 | tr -d '\r')"
    case "$_pty_out" in
        *"auto-open unavailable for the agent"*)
            pass "tty hint appears on a controlling terminal (pty)" ;;
        *)
            fail "tty hint missing under a pty (got: '$_pty_out')" ;;
    esac
else
    echo "  SKIP  tty hint under a pty (script(1) not available)"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All browser bridge tests passed.${NC}"
exit 0
