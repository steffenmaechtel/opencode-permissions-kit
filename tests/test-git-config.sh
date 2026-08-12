#!/bin/sh
# Unit tests for config.sh git-config on/off/status toggle.
# Verifies the //SECURE_GIT: sed manipulation in the bundled opencode.jsonc
# template produces a valid, parseable JSONC with .git/config denies
# present (on) or absent (off), and that status detection works.
# Run: ./tests/test-git-config.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../files/opencode.jsonc"
PARSER="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/jsonc-parser.py"

failures=0
passed=0

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

echo ""
echo "Git-Config Toggle (SECURE_GIT) Tests"
echo "====================================="
echo ""

# --- 1. Template has commented-out SECURE_GIT lines ---
if grep -q '//SECURE_GIT:' "$TEMPLATE"; then
    pass "template has //SECURE_GIT: comment markers"
else
    fail "template has //SECURE_GIT: comment markers"
fi

# --- 2. git-config ON: sed 's|//SECURE_GIT: ||' ---
ON_FILE="$TMPDIR/on.jsonc"
sed 's|//SECURE_GIT: ||' "$TEMPLATE" > "$ON_FILE"

if grep -q '"\.git/config"' "$ON_FILE" && ! grep -q '//SECURE_GIT' "$ON_FILE"; then
    pass "git-config ON: .git/config deny rules uncommented"
else
    fail "git-config ON: .git/config deny rules uncommented"
fi

# ON file must parse cleanly and emit .git/config as deny pattern
ON_DENY=$(python3 "$PARSER" "$ON_FILE" 2>/dev/null || true)
if echo "$ON_DENY" | grep -qF '.git/config'; then
    pass "git-config ON: parser emits .git/config in deny patterns"
else
    fail "git-config ON: parser emits .git/config in deny patterns"
fi

# ON file must parse cleanly (parser exits 0)
if python3 "$PARSER" "$ON_FILE" >/dev/null 2>&1; then
    pass "git-config ON: resulting JSONC is valid JSON"
else
    fail "git-config ON: resulting JSONC is valid JSON"
fi

# --- 3. git-config OFF: sed '/\/\/SECURE_GIT:/d' ---
OFF_FILE="$TMPDIR/off.jsonc"
sed '/\/\/SECURE_GIT:/d' "$TEMPLATE" > "$OFF_FILE"

if ! grep -q 'SECURE_GIT' "$OFF_FILE"; then
    pass "git-config OFF: all SECURE_GIT lines removed"
else
    fail "git-config OFF: all SECURE_GIT lines removed"
fi

OFF_DENY=$(python3 "$PARSER" "$OFF_FILE" 2>/dev/null || true)
if ! echo "$OFF_DENY" | grep -qF '.git/config'; then
    pass "git-config OFF: parser does NOT emit .git/config"
else
    fail "git-config OFF: parser does NOT emit .git/config"
fi

if python3 "$PARSER" "$OFF_FILE" >/dev/null 2>&1; then
    pass "git-config OFF: resulting JSONC is valid JSON"
else
    fail "git-config OFF: resulting JSONC is valid JSON"
fi

# --- 4. Status detection logic (matches config.sh git_config_status) ---
# ON  = active .git/config deny rule present (line starts with whitespace + ".git/config")
# OFF = no active .git/config rule (either absent or still a //SECURE_GIT comment)
if grep -qE '^[[:space:]]*"\.git/config"' "$ON_FILE"; then
    pass "status detection: ON file has active .git/config rule"
else
    fail "status detection: ON file has active .git/config rule"
fi

if ! grep -qE '^[[:space:]]*"\.git/config"' "$OFF_FILE"; then
    pass "status detection: OFF file has NO active .git/config rule"
else
    fail "status detection: OFF file has NO active .git/config rule"
fi

# --- 5. Round-trip: ON -> OFF removes the now-active rules ---
# Apply OFF sed to the ON file
ROUNDTRIP="$TMPDIR/roundtrip.jsonc"
sed '/\/\/SECURE_GIT:/d' "$ON_FILE" > "$ROUNDTRIP"
# ON file has no //SECURE_GIT comments (they were uncommented), so OFF sed
# should be a no-op — .git/config rules should survive
if grep -q '"\.git/config"' "$ROUNDTRIP"; then
    pass "round-trip: ON->OFF sed is no-op (rules already active)"
else
    fail "round-trip: ON->OFF sed is no-op (rules already active)"
fi

# --- Summary ---
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
else
    echo "  All tests passed."
fi
echo ""