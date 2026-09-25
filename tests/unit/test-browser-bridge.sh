#!/bin/sh
# Unit tests for the WSL browser bridge (issues #91, #100):
#   1. bin/browser-bridge stand-in: forwards to the real powershell.exe
#      when the caller may execute it, exit 0 otherwise (the opencode user
#      on a hardened /mnt/c — the login flow must survive the spawn).
#   2. sh/wsl-browser-bridge.sh: the /etc/wsl.conf rewrite (driven through
#      the REAL functions via the OPK_WSL_CONF/OPK_WSL_SUDO/OPK_WSL_FORCE
#      overrides, same convention as DDEV_WIN_HOSTS/FS_SUDO) prepends a
#      pure-comment kit block (WSL-silent by construction, issue #100)
#      whose raw-CR carrier line wins open@<=10's `root =` scan, preserves
#      every foreign line, is idempotent, migrates the broken 0.0.36
#      section away, and the remove path restores the original file
#      byte-for-byte.
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

# --- parser simulations -----------------------------------------------------
# python3 stands in for the three consumers of /etc/wsl.conf:

# open@10.1.2 (bundled in opencode 1.18.x): first /(?<!#.*)root\s*=\s*(.*)/
# match in the whole file. Python re has no variable-length lookbehind, so
# the JS semantics are emulated: a match is rejected iff a '#' sits between
# the nearest line terminator (\r counts) and the match position.
opk_scan_ok() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import re, sys

conf, libdir = sys.argv[1], sys.argv[2]
content = open(conf, encoding='utf-8', newline='').read()
TERM = '\r\n\u2028\u2029'
res = None
for m in re.finditer(r'root\s*=\s*(?P<mp>.*)', content):
    j = m.start() - 1
    rejected = False
    while j >= 0 and content[j] not in TERM:
        if content[j] == '#':
            rejected = True
            break
        j -= 1
    if not rejected:
        res = m.group('mp')
        break
mp = res if res is not None else '/mnt/'
mp = mp if mp.endswith('/') else mp + '/'
want = libdir + '/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
sys.exit(0 if res == libdir + '/wsl' and mp + 'c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' == want else 1)
PY
}

# wsl-utils (newer open, line-based): skips ^\s*# lines, needs ^\s*root=.
# The kit block must NOT register there — those versions access-check
# powershell.exe themselves and fall back to xdg-open, no bridge needed.
wslutils_ignores_block() {
    python3 - "$1" <<'PY' 2>/dev/null
import re, sys

content = open(sys.argv[1], encoding='utf-8', newline='').read()
found = None
for line in content.split('\n'):
    if re.match(r'^\s*#', line):
        continue
    m = re.match(r'^\s*root\s*=\s*(?P<v>"[^"]*"|\'[^\']*\'|[^#]*)', line)
    if m:
        found = m.group('v').strip().strip('"\'')
        break
sys.exit(0 if found is None else 1)
PY
}

# WSL's wsl.conf parser (configfile.cpp): everything the kit writes must be
# a comment line — WSL can then neither warn nor abort on kit content
# (issue #100: the 0.0.36 section name tripped `wsl: Expected ']'`).
wsl_sees_nothing() {
    python3 - "$1" <<'PY' 2>/dev/null
import sys

lines = open(sys.argv[1], encoding='utf-8', newline='').read().split('\n')
bad = [l for l in lines[:10] if l.strip() and not l.startswith('#')]
sys.exit(1 if bad or len(lines) < 10 else 0)
PY
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
echo "--- wsl.conf bridge block rewrite (real functions, overridden paths) ---"

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

# 4. full install: stand-in tree + conf block
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

# 6. the kit block lands at the TOP (open's scan is first-match)
if head -1 "$CONF" | grep -q '^# opencode permissions kit browser bridge -- begin$'; then
    pass "kit block is the first thing in wsl.conf (wins open's first-match scan)"
else
    fail "kit block is not at the top of wsl.conf"
fi

# 7. the carrier line is a raw-CR comment: '# ---...\rroot = <libdir>/wsl'
if printf '%s\n' "$(sed -n '9p' "$CONF" | cat -v)" | grep -q '\^Mroot = '"$LIBDIR"'/wsl$'; then
    pass "carrier line is comment + raw CR + root = <libdir>/wsl"
else
    fail "carrier line malformed (must be # ---...<CR>root = <libdir>/wsl)"
fi

# 8. open@10.1.2 scan resolves to the stand-in path
if opk_scan_ok "$CONF" "$LIBDIR"; then
    pass "open@10.1.2 scan resolves powershell.exe to the kit stand-in"
else
    fail "open@10.1.2 scan does not resolve to the kit stand-in"
fi

# 9. newer open (wsl-utils, line-based) skips the whole block
if wslutils_ignores_block "$CONF"; then
    pass "wsl-utils line parser ignores the kit block (access-check fallback)"
else
    fail "wsl-utils parser picks up the kit carrier (would break its fallback)"
fi

# 10. WSL itself sees no section and no key from the kit
if wsl_sees_nothing "$CONF"; then
    pass "WSL sees only comments from the kit (no section, no key, no warning)"
else
    fail "kit content would be parsed by WSL (warning/abort risk, issue #100)"
fi

# 11. every foreign line survives below the block (10 block lines + blank)
if tail -n +12 "$CONF" | diff -q - "$WORK/orig.conf" >/dev/null 2>&1; then
    pass "foreign wsl.conf content preserved byte-for-byte below the block"
else
    fail "foreign wsl.conf content altered by the rewrite"
fi

# 12. idempotent: a second install run changes nothing
cp "$CONF" "$WORK/before-second.conf"
BB_CALL='browser_bridge_install "$1" "$2"' bb "$FILES_ROOT" "$LIBDIR"
if diff -q "$CONF" "$WORK/before-second.conf" >/dev/null 2>&1; then
    pass "rewrite is idempotent (second run is a no-op)"
else
    fail "rewrite is not idempotent (block duplicated or content changed)"
fi

# 13. migration from the broken 0.0.36 section (issue #100): the hyphenated
#     section is replaced by the comment block; user content stays intact
cat > "$CONF" <<'CONF'
[opencode-permissions-kit]
# Managed by the opencode permissions kit. WSL ignores this section; it
# redirects the powershell.exe lookup of the `open` npm package (bundled in
# opencode) to the kit stand-in so device logins survive a hardened /mnt/c
# (issue #91). Do not add other keys here — uninstall removes the section.
root = /usr/local/lib/opencode-permissions-kit/wsl

[boot]
systemd=true
CONF
BB_CALL='browser_bridge_write_conf "$1"' bb "$LIBDIR"
printf '[boot]\nsystemd=true\n' > "$WORK/migrate.expect"
if ! grep -q 'opencode-permissions-kit\]' "$CONF" \
   && grep -q '^# opencode permissions kit browser bridge -- begin$' "$CONF" \
   && opk_scan_ok "$CONF" "$LIBDIR" \
   && tail -n +12 "$CONF" | diff -q - "$WORK/migrate.expect" >/dev/null 2>&1; then
    pass "0.0.36 hyphen section migrated to the comment block (issue #100)"
else
    fail "0.0.36 section migration broken"
fi

# 14. a stale root = value heals (old kit block replaced, not appended)
printf '# opencode permissions kit browser bridge -- begin\n# stale deploy\n# ----\rroot = /old/lib/wsl\n# opencode permissions kit browser bridge -- end\n\n[boot]\nsystemd=true\n' > "$CONF"
BB_CALL='browser_bridge_write_conf "$1"' bb "$LIBDIR"
if ! grep -q '/old/lib' "$CONF" && opk_scan_ok "$CONF" "$LIBDIR"; then
    pass "stale kit block (old root =) is replaced, not duplicated"
else
    fail "stale kit block survives the rewrite"
fi

# 15. the user's own [automount] root = (if they ever set one) stays intact
#     BELOW the kit block — open's first-match still resolves to the kit
printf '[automount]\nroot = /mnt/\nenabled = true\n' > "$WORK/orig-automount.conf"
cp "$WORK/orig-automount.conf" "$CONF"
BB_CALL='browser_bridge_write_conf "$1"' bb "$LIBDIR"
if opk_scan_ok "$CONF" "$LIBDIR" \
   && tail -n +12 "$CONF" | diff -q - "$WORK/orig-automount.conf" >/dev/null 2>&1; then
    pass "foreign [automount] root = preserved, kit carrier still first"
else
    fail "rewrite damages a foreign automount root = line"
fi

# 16. fresh install without any pre-existing wsl.conf works (no read crash)
rm -f "$CONF"
BB_CALL='browser_bridge_write_conf "$1"' bb "$LIBDIR"
if [ -f "$CONF" ] && opk_scan_ok "$CONF" "$LIBDIR"; then
    pass "fresh wsl.conf is created when none exists"
else
    fail "fresh-install path broken"
fi

# 17. remove restores the original conf byte-for-byte and drops the tree
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
    pass "removing the block restores the original conf byte-for-byte"
else
    fail "block removal leaves residue behind"
fi
if [ ! -e "$LIBDIR/wsl" ]; then
    pass "stand-in tree removed with the bridge"
else
    fail "stand-in tree survives browser_bridge_remove"
fi

# 18. remove also strips a legacy 0.0.36 section (uninstall migration)
printf '[opencode-permissions-kit]\n# Managed by the opencode permissions kit. WSL ignores this section; it\n# redirects the powershell.exe lookup (issue #91). Do not add other keys\n# here — uninstall removes the section.\nroot = /usr/local/lib/opencode-permissions-kit/wsl\n\n[boot]\nsystemd=true\n' > "$CONF"
BB_CALL='browser_bridge_remove "$1"' bb "$LIBDIR"
if printf '[boot]\nsystemd=true\n' | diff -q - "$CONF" >/dev/null 2>&1; then
    pass "remove strips a legacy 0.0.36 section"
else
    fail "remove leaves legacy section residue"
fi

# 19. remove is safe on a bridge-free conf (no kit block, no tree)
BB_CALL='browser_bridge_remove "$1"' bb "$LIBDIR"
if printf '[boot]\nsystemd=true\n' | diff -q - "$CONF" >/dev/null 2>&1; then
    pass "remove is a no-op when no kit block exists"
else
    fail "remove mangles a bridge-free wsl.conf"
fi

echo ""
echo "--- helper contract ---"

# 20. sourcing defines the API and executes nothing (deploy is caller-side)
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

# 21. without OPK_WSL_FORCE the is_wsl probe delegates to /proc/version
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

# 22. install no-ops (gracefully) when the stand-in source is absent —
#     e.g. a partial files/ tree
if OPK_WSL_CONF="$CONF" OPK_WSL_SUDO="" OPK_WSL_FORCE=1 \
    sh -c '. "$1" && browser_bridge_install "$2" "$3"' _ "$BRIDGE_SH" "$WORK/no-such-files-root" "$LIBDIR" >/dev/null 2>&1; then
    pass "install no-ops when the stand-in source file is missing"
else
    fail "install fails on a missing stand-in source"
fi

echo ""
echo "--- diagnostics (debug trace + tty hint) ---"

# 23. without the debug env the no-op path is completely silent (opencode's
#     spawn would show any stdout/stderr noise in the login dialog)
_out="$(OPK_WSL_C_ROOT="$WORK/nowhere" "$BRIDGE_BIN" -EncodedCommand X 2>&1)"
if [ -z "$_out" ]; then
    pass "no-op path is silent without OPK_BROWSER_BRIDGE_DEBUG"
else
    fail "no-op path leaks output without the debug env (got: '$_out')"
fi

# 24. with the debug env the no-op path traces the decision
if OPK_BROWSER_BRIDGE_DEBUG=1 OPK_WSL_C_ROOT="$WORK/nowhere" "$BRIDGE_BIN" -EncodedCommand X 2>&1 \
   | grep -q "browser-bridge\[debug\]: no real powershell reachable"; then
    pass "debug env traces the no-op decision"
else
    fail "debug env does not trace the no-op decision"
fi

# 25. with the debug env the forwarding path traces target + decision
if OPK_BROWSER_BRIDGE_DEBUG=1 OPK_WSL_C_ROOT="$WORK/fakec" "$BRIDGE_BIN" 2>&1 \
   | grep -q "browser-bridge\[debug\]: forwarding to $WORK/fakec"; then
    pass "debug env traces the forwarding decision"
else
    fail "debug env does not trace the forwarding decision"
fi

# 26. the no-op hint goes to the controlling terminal, not stdout/stderr:
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
