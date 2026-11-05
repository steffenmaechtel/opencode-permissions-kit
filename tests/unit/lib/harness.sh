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
#   pass / fail          the counted PASS/FAIL rows -- printf '%b' based,
#                        byte-identical to the old echo definitions under
#                        sh/dash (the suites' runtime) AND under bash
#                        (the coverage shell: scripts/coverage.sh
#                        resolves sh to bash for kcov, and bash echo
#                        does not interpret \033 -- PR #397 CI caught
#                        the echo form differing there)
#   check <desc> cmd...  pass/fail around a command's rc
#   assert_eq <desc> <expected> <actual>
#                        string-equality assertion with expected/got
#                        output on failure
#   suite_done <label>   the summary gate: Passed count, the red Failed
#                        count + exit 1 on any failure, the green
#                        "All <label> passed." line + exit 0 otherwise.
#                        Must stay the suite's LAST call (L4: pins sit
#                        before the summary gate).
#   work_new / work_new_file / work_register / work_register_var
#                        the scratch-receiver registry + central EXIT
#                        INT TERM cleanup (issue #395; own section below)
#
# Deliberately NOT provided: mocking, setup/teardown hooks, filters,
# parallelism -- that is framework territory and was rejected in #255
# (runner lock-in, BDD translation layer in agent review fan-outs).
# Counters (passed/failures) and colors stay globals so existing
# suites read them unchanged.
#
# Standing rules (issue #394 -- the adoption wave's home):
#   1. Rule of three -- a shape moves into the harness at the third
#      real duplication, never speculatively.
#   2. Pin-on-entry -- every function here is pinned by
#      tests/unit/test-harness.sh the moment it lands (counting + rc
#      contracts; the #393 spike's second sabotage arm showed an
#      unpinned harness can print a FAIL row yet exit 0).
#   3. Boundary -- harness = shell test mechanics; suites keep their
#      subject knowledge (drivers, fixtures, seams like run_doctor or
#      run_ui stay local; centralizing them is framework creep, the
#      ShellSpec rejection reason in #255).
#
# Gate scope (review #398 a F4): part of the SHFMT gate -- Makefile
# SHFMT_TEST_FILES covers every tracked tests/*.sh, this file included.
# shellcheck covers files/ + scripts/ only (SHELLCHECK_FILES); this lib
# is NOT in the shellcheck gate.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failures=0

pass() {
    printf '  %bPASS%b  %s\n' "$GREEN" "$NC" "$1"
    passed=$((passed + 1))
}
fail() {
    printf '  %bFAIL%b  %s\n' "$RED" "$NC" "$1"
    failures=$((failures + 1))
}

check() {
    local desc="$1"
    shift
    # review #398 a F6: an empty command must fail loud, not silently
    # pass (a conversion slip dropping the command word would otherwise
    # record a vacuous PASS).
    if [ "$#" -eq 0 ]; then
        fail "$desc (check: no command given)"
        return
    fi
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
    printf '  %bPassed: %s%b\n' "$GREEN" "$passed" "$NC"
    if [ "$failures" -gt 0 ]; then
        printf '  %bFailed: %s%b\n' "$RED" "$failures" "$NC"
        exit 1
    fi
    echo "  All $_label passed."
    exit 0
}

# --- work registry (issue #395) -------------------------------------------------
#
# One central trap structurally ends the #283 leak class: receivers
# register at CREATION time into a per-process registry, and the single
# trap below iterates it on EXIT INT TERM -- no per-suite trap widening
# (test-status's nine-receiver _trap_cleanup was the largest of 22
# hand-rolled scaffolds at spike time).
#
# The registry is a FILE, not a shell variable: registration from inside
# command substitution (test-status's _w2_dir shape) must reach the
# parent's trap, and variable appends die with the subshell. The file is
# created lazily by the first append -- a suite that never registers
# (not yet converted, or one whose own trap replaced the harness trap)
# leaves nothing behind. Its name embeds $$; a PID-recycled run appending
# to a crashed run's leftover self-heals (stale paths are rm no-ops, the
# file is removed afterwards).
#
# API (rule of three: ~25 dir + 8 file receivers + 6 custom traps):
#   work_new [template-args...]   mktemp -d + register, prints the path.
#                                 The idiom for every NEW receiver: there
#                                 is no window between creation and
#                                 registration (the #283 window).
#   work_new_file [template-args...]  same for file receivers (mktemp).
#   work_register <path>...       register pre-existing receivers.
#   work_register_var <NAME>...   register variable NAMES, expanded
#                                 unset-safe at exit -- the migration
#                                 shape for custom _trap_cleanup suites:
#                                 their receiver lists collapse to one
#                                 line, same unset-skip semantics.
#
# set -e interplay (the original #283 trigger): a failed mktemp returns
# 1 BEFORE anything exists to leak; a failed registry append removes the
# receiver and returns 1; any later abort fires the EXIT trap, which
# iterates whatever is registered by then. Suite rc is preserved: the
# cleanup ends in `return 0`, the pending exit status stands.
#
# The registry never re-arms itself. A suite that keeps its own trap
# statement after a work_* call silently disarms the central cleanup
# (its trap replaces ours) -- the sandbox floor flags exactly that mix
# (test-sandbox-policy.sh, check 4). Converted suites carry no trap line
# of their own; unconverted suites keep theirs (they never register, so
# nothing leaks through the lazy file).
_WORK_REG="${TMPDIR:-/tmp}/opk-work-reg.$$"

_work_cleanup() {
    [ -f "$_WORK_REG" ] || return 0
    while IFS= read -r _we; do
        case "$_we" in
            '$'*) eval "_we=\${${_we#\$}:-}" ;;
        esac
        [ -n "$_we" ] && rm -rf -- "$_we"
    done <"$_WORK_REG"
    rm -f -- "$_WORK_REG"
    return 0
}
trap _work_cleanup EXIT INT TERM

_work_emit() {
    # $1 = the freshly created receiver: register it, print it. On a
    # failed append the receiver is removed again -- no unregistered
    # scratch may survive a work_new call.
    printf '%s\n' "$1" >>"$_WORK_REG" 2>/dev/null || {
        echo "work_new: registry append failed ($_WORK_REG)" >&2
        rm -rf -- "$1"
        return 1
    }
    printf '%s\n' "$1"
}

work_new() {
    _wn="$(mktemp -d "$@")" || return 1
    _work_emit "$_wn"
}

work_new_file() {
    _wn="$(mktemp "$@")" || return 1
    _work_emit "$_wn"
}

work_register() {
    for _wr in "$@"; do
        printf '%s\n' "$_wr" >>"$_WORK_REG" 2>/dev/null || {
            echo "work_register: registry append failed ($_WORK_REG)" >&2
            return 1
        }
    done
    return 0
}

work_register_var() {
    for _wv in "$@"; do
        case "$_wv" in
            '' | *[!A-Za-z0-9_]*)
                echo "work_register_var: not a variable name: [$_wv]" >&2
                return 1
                ;;
        esac
        printf '$%s\n' "$_wv" >>"$_WORK_REG" 2>/dev/null || {
            echo "work_register_var: registry append failed ($_WORK_REG)" >&2
            return 1
        }
    done
    return 0
}
