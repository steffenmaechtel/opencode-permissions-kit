#!/bin/sh
# tests/unit/test-harness.sh -- meta-suite for the shared unit-test
# harness tests/unit/lib/harness.sh (issue #394, adoption PR 1): pins
# the contracts every converted suite relies on, before the mechanical
# conversion widens the dependents from 2 to ~20 suites.
#
# What is pinned (each through a child sh that sources the harness and
# runs real code -- observed the way production observes a suite: the
# child's combined output and its exit code):
#   - pass/fail counting (the tally rows "Passed: N" / "Failed: N")
#   - the PASS/FAIL row bytes (color codes, word, two spaces, message)
#   - suite_done rc in both directions: 0 green, 1 with any failure,
#     and the green/red verdict lines
#   - assert_eq pass arm + fail arm (expected/got text)
#   - check pass arm + fail arm
#   - the mixed-tally integration: 3 pass + 2 fail -> both counts in
#     one output, rc 1
#
# Independent by design: this suite uses its OWN local ok/bad counters
# and its own summary gate -- NOT the harness under test. A corrupted
# harness (the #393 spike's second sabotage arm: a broken fail counter
# let a suite print a FAIL row yet exit 0) must not be able to make
# this suite's own verdict lie. Sabotage discrimination (run against a
# committed tree, then restore + re-run green):
#   - delete `failures=$((failures + 1))` from fail() -> the counting
#     pins (Failed: N, mixed tally) go red
#   - delete the `exit 1` from suite_done's failure arm -> the rc
#     pins go red
#
# Run: sh tests/unit/test-harness.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HARNESS="$SCRIPT_DIR/lib/harness.sh"

ok=0
bad=0
ok() {
    echo "  ok    $1"
    ok=$((ok + 1))
}
bad() {
    echo "  BAD   $1"
    bad=$((bad + 1))
}

# arm <code>: source the harness in a child sh and eval the code;
# captures the child's rc and combined output. Every pin below reads
# those two, never the harness's internals.
arm() {
    _arm_code="$1"
    _arm_rc=0
    _arm_out="$(sh -c '. "$1"; eval "$2"' x "$HARNESS" "$_arm_code" 2>&1)" || _arm_rc=$?
}

rc_is() {
    if [ "$_arm_rc" = "$1" ]; then
        ok "$2 (rc $1)"
    else
        bad "$2 (rc want $1, got $_arm_rc)"
    fi
}
has() {
    if printf '%s' "$_arm_out" | grep -qF -- "$1"; then
        ok "$2"
    else
        bad "$2 (output missing [$1])"
    fi
}
lacks() {
    if printf '%s' "$_arm_out" | grep -qF -- "$1"; then
        bad "$2 (output must not contain [$1])"
    else
        ok "$2"
    fi
}
# Row-format pin helper: ESC bytes stripped (tr -d), so the remaining
# [0;3Xm...[0m text pins color codes + spacing + message position.
arm_plain() {
    printf '%s' "$_arm_out" | tr -d '\033'
}

echo ""
echo "Test Harness Meta Tests (lib/harness.sh)"
echo "========================================"
echo ""

# --- 1. green path: counting + verdict + row bytes ----------------------------
arm 'pass one; pass two; pass three; suite_done demo'
rc_is 0 "green suite exits 0"
has "Passed: 3" "pass() counts into the tally"
lacks "Failed:" "green suite shows no Failed row"
has "All demo passed." "suite_done prints the green verdict line"
if arm_plain | grep -qF '[0;32mPASS[0m  one'; then
    ok "PASS row bytes: color codes, word, two spaces, message"
else
    bad "PASS row bytes: color codes, word, two spaces, message"
fi

# --- 2. red path: fail counting + rc 1 + no green line ------------------------
arm 'pass one; fail boom; fail bam; suite_done demo'
rc_is 1 "suite with failures exits 1"
has "Passed: 1" "pass and fail both count in the same run"
has "Failed: 2" "fail() counts into the tally"
lacks "All demo passed." "red suite must not print the green line"
if arm_plain | grep -qF '[0;31mFAIL[0m  boom'; then
    ok "FAIL row bytes: color codes, word, two spaces, message"
else
    bad "FAIL row bytes: color codes, word, two spaces, message"
fi

# --- 3. suite_done minimal arms ------------------------------------------------
arm 'suite_done demo'
rc_is 0 "zero tests, zero failures -> rc 0"
has "Passed: 0" "empty suite prints its zero tally"

# --- 4. assert_eq ----------------------------------------------------------------
arm 'assert_eq "eq arm" want want; suite_done demo'
rc_is 0 "assert_eq equal values -> green"
has "Passed: 1" "assert_eq pass arm counts as a pass"
arm 'assert_eq "eq arm" want got; suite_done demo'
rc_is 1 "assert_eq mismatch -> red"
has "expected [want] got [got]" "assert_eq fail arm names expected and actual"

# --- 5. check --------------------------------------------------------------------
arm 'check "cmd ok" true; suite_done demo'
rc_is 0 "check with succeeding command -> green"
has "Passed: 1" "check pass arm counts as a pass"
arm 'check "cmd bad" false; suite_done demo'
rc_is 1 "check with failing command -> red"
has "cmd bad" "check fail arm carries the description"

# --- 6. mixed tally (integration) -------------------------------------------------
arm 'pass a; pass b; pass c; fail x; fail y; suite_done demo'
rc_is 1 "mixed suite: any failure -> rc 1"
has "Passed: 3" "mixed run: passes tallied"
has "Failed: 2" "mixed run: failures tallied"

# --- summary gate (independent on purpose -- see header) ------------------------
echo ""
if [ "$bad" -gt 0 ]; then
    echo "  $bad meta-test(s) failed."
    exit 1
fi
echo "  all harness meta-tests passed ($ok)."
exit 0
