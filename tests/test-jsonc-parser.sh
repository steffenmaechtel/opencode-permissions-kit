#!/bin/sh
# Unit tests for jsonc-parser.py edge cases.
# Verifies: block comments, URLs in strings, escaped quotes, malformed input,
# missing permission key, bash-only config, mixed allow/deny, trailing comments.
# Run: ./tests/test-jsonc-parser.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SCRIPT_DIR/../files/opencode-lib/jsonc-parser.py"
FIXTURES="$SCRIPT_DIR/fixtures/jsonc"

failures=0
passed=0

assert_contains() {
    local desc="$1" pattern="$2" list="$3"
    if echo "$list" | grep -qF "$pattern"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        expected pattern '$pattern' in output"
        failures=$((failures + 1))
    fi
}

assert_not_contains() {
    local desc="$1" pattern="$2" list="$3"
    if ! echo "$list" | grep -qF "$pattern"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        pattern '$pattern' should NOT be present"
        failures=$((failures + 1))
    fi
}

assert_empty() {
    local desc="$1" list="$2"
    if [ -z "$(echo "$list" | tr -d '[:space:]')" ]; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        expected empty output, got: $list"
        failures=$((failures + 1))
    fi
}

assert_exitcode() {
    local desc="$1" expected="$2"
    shift 2
    if "$@" >/dev/null 2>&1; ec=$?; [ "$ec" = "$expected" ]; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        expected exit code $expected"
        failures=$((failures + 1))
    fi
}

echo ""
echo "JSONC Parser Edge-Case Tests"
echo "=============================="
echo ""

# --- 1. Block comments ---
OUT=$(python3 "$PARSER" "$FIXTURES/block-comments.jsonc" 2>/dev/null || true)
assert_contains "block-comments: .env* extracted" ".env*" "$OUT"
assert_contains "block-comments: **/*.env extracted" "**/*.env" "$OUT"

# --- 2. URL in string (// must not be treated as comment start) ---
OUT=$(python3 "$PARSER" "$FIXTURES/url-in-string.jsonc" 2>/dev/null || true)
assert_contains "url-in-string: .env* extracted" ".env*" "$OUT"
assert_contains "url-in-string: **/*.env extracted" "**/*.env" "$OUT"
assert_not_contains "url-in-string: url NOT in deny patterns" "https://opencode.ai/foo" "$OUT"

# --- 3. Escaped quote in string ---
OUT=$(python3 "$PARSER" "$FIXTURES/escaped-quote-in-string.jsonc" 2>/dev/null || true)
assert_contains "escaped-quote: .env* extracted" ".env*" "$OUT"
assert_contains "escaped-quote: escaped pattern extracted" 'escaped"quote' "$OUT"

# --- 4. Malformed JSON → non-zero exit ---
assert_exitcode "malformed: exits non-zero" 1 python3 "$PARSER" "$FIXTURES/malformed.jsonc"

# --- 5. Missing permission key → empty output, exit 0 ---
OUT=$(python3 "$PARSER" "$FIXTURES/missing-permission.jsonc" 2>/dev/null || true)
assert_empty "missing-permission: empty deny patterns" "$OUT"
assert_exitcode "missing-permission: exits 0" 0 python3 "$PARSER" "$FIXTURES/missing-permission.jsonc"

# --- 6. Bash-only config → empty deny patterns (parser only reads read+edit) ---
OUT=$(python3 "$PARSER" "$FIXTURES/bash-only.jsonc" 2>/dev/null || true)
assert_empty "bash-only: no deny patterns emitted" "$OUT"

# --- 7. Mixed allow/deny: deny mode returns only denies ---
OUT=$(python3 "$PARSER" "$FIXTURES/mixed-allow-deny.jsonc" 2>/dev/null || true)
assert_contains "mixed-deny: .env* in deny list" ".env*" "$OUT"
assert_contains "mixed-deny: **/*.env in deny list" "**/*.env" "$OUT"
assert_not_contains "mixed-deny: README.md NOT in deny list" "README.md" "$OUT"

# --- 8. Mixed allow/deny: allow mode returns only allows ---
OUT=$(python3 "$PARSER" --allow "$FIXTURES/mixed-allow-deny.jsonc" 2>/dev/null || true)
assert_contains "mixed-allow: README.md in allow list" "README.md" "$OUT"
assert_contains "mixed-allow: **/README.md in allow list" "**/README.md" "$OUT"
assert_not_contains "mixed-allow: .env* NOT in allow list" ".env*" "$OUT"

# --- 9. Trailing comment after value ---
OUT=$(python3 "$PARSER" "$FIXTURES/trailing-comment.jsonc" 2>/dev/null || true)
assert_contains "trailing-comment: .env* extracted" ".env*" "$OUT"

# --- 10. Missing file → non-zero exit ---
assert_exitcode "missing-file: exits non-zero" 1 python3 "$PARSER" "$FIXTURES/nonexistent.jsonc"

# --- 11. No args → non-zero exit ---
assert_exitcode "no-args: exits non-zero" 1 python3 "$PARSER"

# --- 12. Bundled template parses cleanly ---
OUT=$(python3 "$PARSER" "$SCRIPT_DIR/../files/opencode.jsonc" 2>/dev/null || true)
assert_contains "bundled: .env* present" ".env*" "$OUT"
assert_contains "bundled: auth.json present" "auth.json" "$OUT"
assert_contains "bundled: README.md present" "README.md" "$OUT"
assert_not_contains "bundled: //SECURE_GIT NOT present (commented)" "//SECURE_GIT" "$OUT"

# --- 13. Bundled template allow mode (SECURE_GIT lines are comments → not emitted) ---
OUT=$(python3 "$PARSER" --allow "$SCRIPT_DIR/../files/opencode.jsonc" 2>/dev/null || true)
assert_not_contains "bundled-allow: .git/config NOT emitted (commented)" ".git/config" "$OUT"

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