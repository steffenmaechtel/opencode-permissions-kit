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
#   - the work registry (#395): work_new / work_new_file create AND
#     register receivers, work_register / work_register_var migrate
#     pre-existing ones, the central trap collects on green, red, set -e
#     abort and SIGTERM -- with a disarmed control arm that must leak
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

# The registry pin cells below create real receivers (_lc_iso, _sig_iso,
# their cell scripts and _sig_out) -- this suite owns their cleanup with
# its OWN trap, like it owns its own counters (independence, header
# above: the main shell never sources the harness under test). The cell
# child scripts are printf-written into scratch with literal "$" text --
# embedded child scripts, the sandbox floor's documented invisible shape:
# child scripts own their cleanup, the floor does not scan them. Function
# form: the receiver list does not fit one line and the floor reads the
# arms off the trap's physical line.
_meta_cleanup() {
    rm -rf "${_lc_iso:-}" "${_lc_cell:-}" "${_sig_iso:-}" \
        "${_sig_scratch:-}" "${_af_out:-}" "${_af_cell:-}" "${_sig_out:-}"
}
trap _meta_cleanup EXIT INT TERM

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
# Registry pin helper: extracts the last "RECV=<path>" line the child
# printed and asserts that path no longer exists -- the receiver must be
# collected by the central trap, observed from OUTSIDE the child.
recv_gone() {
    _rp="$(printf '%s\n' "$_arm_out" | sed -n 's/^RECV=//p' | tail -n 1)"
    if [ -n "$_rp" ] && [ ! -e "$_rp" ]; then
        ok "$1"
    else
        bad "$1 (receiver [$_rp] still present)"
    fi
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
arm 'check "desc only, no command"; suite_done demo'
rc_is 1 "check without a command fails loud (F6)"
has "no command given" "empty-command check names the contract (F6)"

# --- 5b. quoting shapes (F5, review #398 a) ---------------------------------------
# The forms every real consumer uses: multi-word args with internal
# spaces through check, empty and multi-word strings through assert_eq.
# The bare arms above pass even under an unquoted-$@ regression; these
# must catch it (sabotage: harness check with `if $@` -> the quoted
# multi-word arm goes red because test re-parses the split words).
arm 'check "quoted args survive" test "a b" = "a b"; suite_done demo'
rc_is 0 "check keeps quoted multi-word args intact (F5)"
has "Passed: 1" "quoted check pass arm counts (F5)"
arm 'check "quoted args mismatch" test "a b" = "a c"; suite_done demo'
rc_is 1 "check multi-word mismatch -> red (F5)"
arm 'assert_eq "empty strings" "" ""; suite_done demo'
rc_is 0 "assert_eq empty equals empty (F5)"
arm 'assert_eq "two words" "a b" "a b"; suite_done demo'
rc_is 0 "assert_eq multi-word expected/actual (F5)"

# --- 6. mixed tally (integration) -------------------------------------------------
arm 'pass a; pass b; pass c; fail x; fail y; suite_done demo'
rc_is 1 "mixed suite: any failure -> rc 1"
has "Passed: 3" "mixed run: passes tallied"
has "Failed: 2" "mixed run: failures tallied"

# --- 7. row bytes under the coverage shell (bash) --------------------------------
# Fidelity arm (the #397 CI failure): the coverage run executes suites
# with a PATH shim resolving sh to bash (#343), and bash echo does NOT
# interpret \033 -- rows must not rely on echo escape interpretation.
# The harness prints via printf '%b', so the bytes are identical under
# both shells. On a host without bash the arm degrades to sh (which
# still pins the row bytes, just not the cross-shell property -- kcov
# itself needs bash, so such hosts never run the coverage job).
_arm_sh="sh"
command -v bash >/dev/null 2>&1 && _arm_sh="bash"
_arm_rc=0
_arm_out="$($_arm_sh -c '. "$1"; pass one; fail boom' x "$HARNESS" 2>&1)" || _arm_rc=$?
if arm_plain | grep -qF '[0;32mPASS[0m  one'; then
    ok "PASS row bytes identical under $_arm_sh (coverage-shell fidelity)"
else
    bad "PASS row bytes identical under $_arm_sh (coverage-shell fidelity)"
fi
if arm_plain | grep -qF '[0;31mFAIL[0m  boom'; then
    ok "FAIL row bytes identical under $_arm_sh (coverage-shell fidelity)"
else
    bad "FAIL row bytes identical under $_arm_sh (coverage-shell fidelity)"
fi

# --- 8. work registry (#395): the central trap ends the #283 leak class -------
# Every pin runs the mechanism the way a real suite runs it: a child sh
# sources the harness, registers receivers through the work_* API, exits
# -- the parent then observes the receiver PATH is gone and the child's
# rc. Sabotage discrimination (committed tree, then restore + re-run):
#   - delete `trap _work_cleanup EXIT INT TERM` from the harness -> the
#     recv_gone pins and the leak cell go red (receivers stay, control
#     arm proves the cell was discriminating all along)
#   - delete the `>>"$_WORK_REG"` append from _work_emit -> recv_gone
#     pins go red while the ISDIR/ISFILE shape pins stay green
arm 'W="$(work_new)"; echo "RECV=$W"; test -d "$W" && echo ISDIR; suite_done demo'
rc_is 0 "work_new suite exits green"
has ISDIR "work_new creates a directory receiver"
recv_gone "green exit: the central trap collects the work_new receiver"
arm 'W="$(work_new "${TMPDIR:-/tmp}/wntpl.XXXXXX")"; echo "RECV=$W"
     case "$W" in *wntpl.??????*) echo TPLMATCH ;; *) echo TPLBAD ;; esac
     suite_done demo'
has TPLMATCH "work_new passes template args through to mktemp"
recv_gone "template receiver collected too"
arm 'F="$(work_new_file)"; echo "RECV=$F"; test -f "$F" && echo ISFILE; suite_done demo'
has ISFILE "work_new_file creates a file receiver"
recv_gone "file receiver collected by the same trap"
arm 'P="$(mktemp -d)"; work_register "$P"; echo "RECV=$P"; suite_done demo'
recv_gone "work_register collects a pre-existing receiver (migration shape)"
arm 'work_register_var NEVERSET_YET; suite_done demo'
rc_is 0 "work_register_var on a never-set name is unset-safe (skip, no crash)"
arm 'LV=""; work_register_var LV; LV="$(mktemp -d)"; echo "RECV=$LV"; suite_done demo'
recv_gone "work_register_var expands the name at EXIT time (late value collected)"
arm 'OUT="$(work_new)"; echo "RECV=$OUT"; suite_done demo'
recv_gone "registration from inside \$( ) reaches the trap (file registry)"
arm 'set -e; work_register_var "bad name"; pass unreachable'
rc_is 1 "work_register_var rejects a non-name loud under set -e"
has "not a variable name" "the rejection names the bad operand"
arm 'W="$(work_new)"; echo "RECV=$W"; fail boom; suite_done demo'
rc_is 1 "red suite with a registered receiver still exits 1"
recv_gone "red exit: cleanup ran AND the rc stayed 1 (rc preserved)"

# Leak-shaped pin (acceptance of #395): the #283 form executing the
# failure path -- isolated TMPDIR, receiver created, set -e abort inside
# the window. Zero entries may remain (receiver AND registry file). The
# control arm disarms the harness trap inline (the shape a deleted trap
# line produces) and MUST leak -- the pair discriminates through the
# trap, not through the abort.
_leak_cell() {
    # $1 = armed|gone -- sets _lc_left (leftover count) and _lc_rc. The
    # cell script lives OUTSIDE the isolated TMPDIR (its file must not
    # count as a leftover); printf-formatted with literal "$" text, the
    # embedded-child-script shape.
    _lc_iso="$(mktemp -d)"
    _lc_cell="$(mktemp)"
    printf '#!/bin/sh\nset -e\n. "$1"\nif [ "$2" = gone ]; then trap - EXIT INT TERM; fi\nW1="$(work_new)"\necho "RECV=$W1"\nfalse\necho unreachable\n' \
        >"$_lc_cell"
    _lc_rc=0
    TMPDIR="$_lc_iso" sh "$_lc_cell" "$HARNESS" "$1" >/dev/null 2>&1 || _lc_rc=$?
    _lc_left="$(find "$_lc_iso" -mindepth 1 | wc -l | tr -d ' ')"
    rm -rf -- "$_lc_iso"
    rm -f -- "$_lc_cell"
}
_leak_cell armed
if [ "$_lc_left" = 0 ]; then
    ok "#283 abort window: armed registry leaves zero leftovers"
else
    bad "#283 abort window: armed registry must leave zero leftovers (got $_lc_left)"
fi
if [ "$_lc_rc" = 1 ]; then
    ok "abort rc preserved through the central trap (rc 1, not clobbered)"
else
    bad "abort rc must stay 1 through the trap (got $_lc_rc)"
fi
_leak_cell gone
if [ "$_lc_left" -ge 1 ]; then
    ok "abort control arm: disarmed registry leaks (pin discriminates)"
else
    bad "abort control arm must leak -- otherwise the armed cell is vacuous"
fi

# Signal arm (the #283 signal trigger): TERM into the receiver window
# via a session-group kill (the house cell pattern, test-sandbox-policy
# section 5) with a work_new receiver. The elapsed guard (<10 s) proves
# the kill landed -- a missed kill would green through the EXIT arm
# after the sleep (0.0.46a F2 vacuity class).
_sig_iso="$(mktemp -d)"
_sig_scratch="$(mktemp -d)"
_sig_cell="$_sig_scratch/cell.sh"
_sig_out="$(mktemp)"
printf '#!/bin/sh\n. "$1"\nW1="$(work_new)"\necho "RECV=$W1"\nsleep 30\n' \
    >"$_sig_cell"
_sig_start=$(date +%s)
TMPDIR="$_sig_iso" setsid sh "$_sig_cell" "$HARNESS" >"$_sig_out" 2>&1 &
_sig_pid=$!
sleep 1
kill -TERM "-$_sig_pid" 2>/dev/null || :
wait "$_sig_pid" 2>/dev/null || :
_sig_left="$(find "$_sig_iso" -mindepth 1 | wc -l | tr -d ' ')"
_sig_el=$(($(date +%s) - _sig_start))
rm -rf -- "$_sig_iso"
rm -rf -- "$_sig_scratch"
rm -f -- "$_sig_out"
if [ "$_sig_left" = 0 ] && [ "$_sig_el" -lt 10 ]; then
    ok "signal window: TERM lands, registry collects (zero leftovers, ${_sig_el}s)"
else
    bad "signal window: TERM must collect within the window (left=$_sig_left elapsed=${_sig_el}s)"
fi

# Append-failure arm (L1: every fail-loud spot gets a pin that executes
# the failure path): the registry path blocked by a directory while
# mktemp still works. work_new must fail loud (rc 1, stderr names the
# registry) AND remove the created receiver again -- no unregistered
# scratch may survive a failed registration. The _work_emit message
# covers all three append sites (work_new, work_register, var) -- the
# mechanism is one, the pin drives it.
_af_out="$(mktemp -d)"
_af_cell="$(mktemp)"
printf '#!/bin/sh\n. "$1"\nmkdir "${TMPDIR:-/tmp}/opk-work-reg.$$"\nset -e\nW="$(work_new)"\necho unreachable\n' \
    >"$_af_cell"
_af_rc=0
TMPDIR="$_af_out" sh "$_af_cell" "$HARNESS" >/dev/null 2>&1 || _af_rc=$?
_af_left="$(find "$_af_out" -mindepth 1 ! -name 'opk-work-reg.*' | wc -l | tr -d ' ')"
rm -rf -- "$_af_out"
rm -f -- "$_af_cell"
if [ "$_af_rc" = 1 ] && [ "$_af_left" = 0 ]; then
    ok "append failure: loud rc 1, receiver removed (no unregistered scratch)"
else
    bad "append failure must be loud rc 1 with the receiver removed (rc=$_af_rc left=$_af_left)"
fi

# --- summary gate (independent on purpose -- see header) ------------------------
echo ""
if [ "$bad" -gt 0 ]; then
    echo "  $bad meta-test(s) failed."
    exit 1
fi
echo "  all harness meta-tests passed ($ok)."
exit 0
