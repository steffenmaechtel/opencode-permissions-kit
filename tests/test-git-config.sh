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

# --- 6. install.sh git semantics (regression: 2026-08-16 live-test bugs) ---
# SECURE_GIT_CONFIG=true means the deny rules are ACTIVE = git BLOCKED.
# A live install run revealed three inversions/gaps that must never return:
#   a) the Standard question mapped "allow" to true (= block),
#   b) the completion panel showed the mapping backwards,
#   c) a re-install silently ignored the choice (config never re-rendered).
INSTALL="$SCRIPT_DIR/../files/install.sh"

if grep -q '^SECURE_GIT_CONFIG=true' "$INSTALL"; then
    pass "install.sh: default is git BLOCKED (SECURE_GIT_CONFIG=true)"
else
    fail "install.sh: default is git BLOCKED (SECURE_GIT_CONFIG=true)"
fi

if grep -q 'yes" \]; then SECURE_GIT_CONFIG=false' "$INSTALL" \
   || grep -Eq '=\s*"yes"\s*\]\s*&&\s*SECURE_GIT_CONFIG=false' "$INSTALL"; then
    pass "install.sh: Standard 'allow git' maps to SECURE_GIT_CONFIG=false"
else
    fail "install.sh: Standard 'allow git' maps to SECURE_GIT_CONFIG=false"
fi

if grep -q 'ui_kv "Git".*blocked for the agent' "$INSTALL" \
   && ! grep -q 'ui_kv "Git".*allowed (soft-only' "$INSTALL"; then
    pass "install.sh: completion panel maps true=blocked / false=allowed"
else
    fail "install.sh: completion panel maps true=blocked / false=allowed"
fi

# The re-install path must back up + re-render the agent config with the
# chosen git setting (never silently keep a stale one).
if grep -q 'opencode.jsonc-existing' "$INSTALL" \
   && grep -q 'config re-applied' "$INSTALL"; then
    pass "install.sh: re-install re-renders the agent config (backup kept)"
else
    fail "install.sh: re-install re-renders the agent config (backup kept)"
fi

# Plan numbering must be dynamic (_plan helper) — a skipped optional step
# must not leave a gap in the numbered plan the user confirms.
if grep -q '_plan()' "$INSTALL" && ! grep -Eq 'ui_plan [0-9]' "$INSTALL"; then
    pass "install.sh: plan numbering is dynamic (no gaps when steps are skipped)"
else
    fail "install.sh: plan numbering is dynamic (no gaps when steps are skipped)"
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