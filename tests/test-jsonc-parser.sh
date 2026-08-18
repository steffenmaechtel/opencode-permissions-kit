#!/bin/sh
# Unit tests for jsonc-parser.py edge cases.
# Verifies: block comments, URLs in strings, escaped quotes, malformed input,
# missing permission key, bash-only config, mixed allow/deny, trailing comments,
# --tools mode (container tool detection).
# Run: ./tests/test-jsonc-parser.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/jsonc-parser.py"
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

# --- 9. Trailing comment after value ---
OUT=$(python3 "$PARSER" "$FIXTURES/trailing-comment.jsonc" 2>/dev/null || true)
assert_contains "trailing-comment: .env* extracted" ".env*" "$OUT"

# --- 9b. Trailing commas (legal JSONC, strict json would reject) ---
OUT=$(python3 "$PARSER" "$FIXTURES/trailing-comma.jsonc" 2>/dev/null || true)
RC=$?
assert_exitcode "trailing-comma: exits zero" 0 sh -c "exit $RC"
assert_contains "trailing-comma: **/.env* extracted" "**/.env*" "$OUT"
assert_contains "trailing-comma: README.md extracted" "*README.md" "$OUT"
assert_contains "trailing-comma: README.txt extracted" "*README.txt" "$OUT"
OUT=$(python3 "$PARSER" --tools "$FIXTURES/trailing-comma.jsonc" 2>/dev/null || true)
assert_contains "trailing-comma --tools: ddev detected" "ddev" "$OUT"
assert_contains "trailing-comma --tools: docker detected" "docker" "$OUT"

# --- 10. Missing file → non-zero exit ---
assert_exitcode "missing-file: exits non-zero" 1 python3 "$PARSER" "$FIXTURES/nonexistent.jsonc"

# --- 11. No args → non-zero exit ---
assert_exitcode "no-args: exits non-zero" 1 python3 "$PARSER"

# --- 12. Bundled template parses cleanly ---
OUT=$(python3 "$PARSER" "$SCRIPT_DIR/../files/opencode.jsonc" 2>/dev/null || true)
assert_contains "bundled: .env* present" ".env*" "$OUT"
assert_contains "bundled: auth.json present" "auth.json" "$OUT"
assert_contains "bundled: README.md present" "README.md" "$OUT"
assert_contains "bundled: README.txt present (deny again — soft-only, ddev-safe)" "README.txt" "$OUT"
assert_not_contains "bundled: //SECURE_GIT NOT present (commented)" "//SECURE_GIT" "$OUT"

# --- 13. Bundled template: deny mode only (SECURE_GIT lines are comments) ---
OUT=$(python3 "$PARSER" "$SCRIPT_DIR/../files/opencode.jsonc" 2>/dev/null || true)
assert_not_contains "bundled: .git/config NOT emitted (commented)" ".git/config" "$OUT"
# The removed --allow mode must fail loudly if anything still calls it.
assert_exitcode "no --allow mode: exits non-zero" 1 python3 "$PARSER" --allow "$SCRIPT_DIR/../files/opencode.jsonc"

# --- 14. --tools: no permission.bash → no tools ---
OUT=$(python3 "$PARSER" --tools "$FIXTURES/block-comments.jsonc" 2>/dev/null || true)
assert_empty "tools: no bash section → no tools" "$OUT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- 15. --tools: catch-all allow → docker AND ddev ---
printf '%s\n' '{ "permission": { "bash": { "*": "allow" } } }' > "$TMP/catchall.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/catchall.jsonc" 2>/dev/null || true)
assert_contains "tools: catch-all allow → docker" "docker" "$OUT"
assert_contains "tools: catch-all allow → ddev" "ddev" "$OUT"

# --- 16. --tools: "docker *": "allow" → docker only ---
printf '%s\n' '{ "permission": { "bash": { "docker *": "allow" } } }' > "$TMP/docker.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/docker.jsonc" 2>/dev/null || true)
assert_contains "tools: docker * allow → docker" "docker" "$OUT"
assert_not_contains "tools: docker * allow → no ddev" "ddev" "$OUT"

# --- 17. --tools: subcommand-only allow does NOT trigger ---
printf '%s\n' '{ "permission": { "bash": { "ddev composer *": "allow" } } }' > "$TMP/subcmd.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/subcmd.jsonc" 2>/dev/null || true)
assert_empty "tools: ddev composer * does NOT trigger ddev" "$OUT"

# --- 18. --tools: bare "docker": "allow" counts ---
printf '%s\n' '{ "permission": { "bash": { "docker": "allow" } } }' > "$TMP/bare.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/bare.jsonc" 2>/dev/null || true)
assert_contains "tools: bare docker allow → docker" "docker" "$OUT"

# --- 19. --tools: last match wins — "docker ps" allow then "docker *" deny ---
printf '%s\n' '{ "permission": { "bash": { "docker ps": "allow", "docker *": "deny" } } }' > "$TMP/deny-last.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/deny-last.jsonc" 2>/dev/null || true)
assert_not_contains "tools: later docker * deny wins over docker ps allow" "docker" "$OUT"

# --- 20. --tools: shorthand "permission.bash": "allow" and "permission": "allow" ---
printf '%s\n' '{ "permission": { "bash": "allow" } }' > "$TMP/shorthand.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/shorthand.jsonc" 2>/dev/null || true)
assert_contains "tools: shorthand bash allow → docker" "docker" "$OUT"
printf '%s\n' '{ "permission": "allow" }' > "$TMP/toplevel.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/toplevel.jsonc" 2>/dev/null || true)
assert_contains "tools: top-level allow → ddev" "ddev" "$OUT"

# --- 21. --tools: "sudo docker *" and "docker compose *" do NOT trigger ---
printf '%s\n' '{ "permission": { "bash": { "sudo docker *": "allow" } } }' > "$TMP/sudo.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/sudo.jsonc" 2>/dev/null || true)
assert_empty "tools: sudo docker * does NOT trigger" "$OUT"
printf '%s\n' '{ "permission": { "bash": { "docker compose *": "allow" } } }' > "$TMP/compose.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/compose.jsonc" 2>/dev/null || true)
assert_empty "tools: docker compose * does NOT trigger" "$OUT"

# --- 22. --tools: catch-all allow + "docker *" deny → docker granted via
#     docker-compose (matches only "*", like opencode itself) ---
printf '%s\n' '{ "permission": { "bash": { "*": "allow", "docker *": "deny" } } }' > "$TMP/slip.jsonc"
OUT=$(python3 "$PARSER" --tools "$TMP/slip.jsonc" 2>/dev/null || true)
assert_contains "tools: catch-all allow + docker * deny → docker (compose slips through)" "docker" "$OUT"

# --- 23. --tools: bundled template → no container tools (all deny) ---
OUT=$(python3 "$PARSER" --tools "$SCRIPT_DIR/../files/opencode.jsonc" 2>/dev/null || true)
assert_empty "tools: bundled template → no container tools" "$OUT"

# --- 24. --tools: project fixture (ddev composer only) → no tools ---
OUT=$(python3 "$PARSER" --tools "$SCRIPT_DIR/fixtures/project-opencode.jsonc" 2>/dev/null || true)
assert_empty "tools: project fixture → no container tools" "$OUT"

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