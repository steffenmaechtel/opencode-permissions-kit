#!/bin/sh
# Regression test: git hooks must pass --cwd "$(pwd)" so the project-level
# opencode.jsonc denies/allows are applied for the worktree on git operations.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(dirname "$0")"
HOOKS_DIR="$SCRIPT_DIR/../files/opencode-lib/hooks"

failures=0
passed=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        failures=$((failures + 1))
    fi
}

echo ""
echo "Git Hook Tests"
echo "==============="
echo ""

for hook in post-checkout post-merge post-commit; do
    f="$HOOKS_DIR/$hook"
    check "$hook exists and is executable"  [ -x "$f" ]
    check "$hook calls protect-projects.sh" grep -q 'protect-projects.sh' "$f"
    check "$hook passes --force"            grep -q -- '--force' "$f"
    check "$hook passes --cwd \$(pwd)"      grep -q -- '--cwd "$(pwd)"' "$f"
done

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
