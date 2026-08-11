#!/bin/sh
# Regression test: git hooks must prefer OPENCODE_LAUNCH_CWD (the directory
# opencode was started in, stamped by the wrapper) and fall back to "$(pwd)"
# (the git worktree root) when git runs outside opencode.
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
    check "$hook reads OPENCODE_LAUNCH_CWD" grep -Fq '${OPENCODE_LAUNCH_CWD:-$(pwd)}' "$f"
    check "$hook passes --cwd \$CWD"        grep -Fq -- '--cwd "$CWD"' "$f"
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
