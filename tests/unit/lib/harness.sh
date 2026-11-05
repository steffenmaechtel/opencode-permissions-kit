# tests/unit/lib/harness.sh -- the shared unit-test harness (issue #255
# stage 2 spike). Sourced by suites, never executed directly. It carries
# exactly the helpers the suites duplicate today (30 byte-identical
# pass()/fail() definitions at spike time) plus the two assertion shapes
# and the summary gate -- no runner, no DSL: the contract stays
# `sh tests/unit/test-*.sh`, each suite directly executable (Makefile
# per-suite targets, CI, kcov via scripts/coverage.sh).
#
# Sourcing contract: the suite computes SCRIPT_DIR (nearly every suite
# already does) and then sources this file:
#
#     SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#     . "$SCRIPT_DIR/lib/harness.sh"
#
# Provides:
#   pass / fail          the counted PASS/FAIL rows (identical bytes to
#                        the duplicated definitions: colors, two-space
#                        indent, message last)
#   check <desc> cmd...  pass/fail around a command's rc
#   assert_eq <desc> <expected> <actual>
#                        string-equality assertion with expected/got
#                        output on failure
#   suite_done <label>   the summary gate: Passed count, the red Failed
#                        count + exit 1 on any failure, the green
#                        "All <label> passed." line + exit 0 otherwise.
#                        Must stay the suite's LAST call (L4: pins sit
#                        before the summary gate).
#
# Deliberately NOT provided: mocking, setup/teardown hooks, filters,
# parallelism -- that is framework territory and was rejected in #255
# (runner lock-in, BDD translation layer in agent review fan-outs).
# Counters (passed/failures) and colors stay globals so existing
# suites read them unchanged.
#
# Part of the shfmt + shellcheck gate scope (Makefile SHFMT_TEST_FILES
# covers every tracked tests/*.sh).

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failures=0

pass() {
    echo "  ${GREEN}PASS${NC}  $1"
    passed=$((passed + 1))
}
fail() {
    echo "  ${RED}FAIL${NC}  $1"
    failures=$((failures + 1))
}

check() {
    local desc="$1"
    shift
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

assert_eq() {
    _d="$1" _e="$2" _a="$3"
    if [ "$_e" = "$_a" ]; then pass "$_d"; else fail "$_d (expected [$_e] got [$_a])"; fi
}

suite_done() {
    _label="$1"
    echo ""
    echo "===================================="
    echo "  ${GREEN}Passed: $passed${NC}"
    if [ "$failures" -gt 0 ]; then
        echo "  ${RED}Failed: $failures${NC}"
        exit 1
    fi
    echo "  All $_label passed."
    exit 0
}
