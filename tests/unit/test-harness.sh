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
#   - extract_func (#396): the strict col-0 anchor contract (right
#     block, full extent, indented-only defs invisible), the emptiness
#     contract for absent names, rider composability on stdout, the
#     probe+eval production idiom, and the two fail-loud guards
#     (invalid name, missing file)
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

# The registry pin cells below create real receivers (the isolated
# TMPDIRs, their cell scripts and the a1h receivers) -- this suite owns
# their cleanup with its OWN trap (_meta_cleanup's operand list is the
# authoritative inventory), like it owns its own counters (independence,
# header above: the main shell never sources the harness under test).
# The cell child scripts are printf-written into scratch with literal
# "$" text -- embedded child scripts, the sandbox floor's documented
# invisible shape: child scripts own their cleanup, the floor does not
# scan them (the a1h cell is a quoted heredoc, the same shape). Function
# form: the receiver list does not fit one line and the floor reads the
# arms off the trap's physical line.
_meta_cleanup() {
    rm -rf "${_lc_iso:-}" "${_lc_cell:-}" "${_sgi_iso:-}" \
        "${_sgi_scratch:-}" "${_afc_out:-}" "${_afc_cell:-}" \
        "${_a1h_out:-}" "${_a1h_cell:-}" "${_a1h_a:-}" "${_a1h_b:-}" \
        "${_ef_fix:-}" "${_ls_fix:-}" "${_tc_fix:-}"
    rm -f "${_sgi_out:-}"
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
# Raw-ESC pin (round A B7): arm_plain strips ESC before matching, so a
# harness regression losing the ESC byte (colors without \033) stays
# byte-identical to the strippers -- this arm greps the RAW bytes.
_esc="$(printf '\033')"
if printf '%s' "$_arm_out" | grep -qF "${_esc}[0;32mPASS"; then
    ok "PASS row emits the raw ESC byte before the color code (B7)"
else
    bad "PASS row emits the raw ESC byte before the color code (B7)"
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
#     recv_gone pins, the leak cell and the signal cell go red
#     (receivers stay; the gone control arms prove the cells were
#     discriminating all along)
#   - delete the `>>"$_WORK_REG"` append from _work_emit -> the SIX
#     _work_emit-routed recv_gone arms go red while the ISDIR/ISFILE
#     shape pins stay green; the work_register/work_register_var arms
#     stay green TOO -- their appends are their own inline sites
#     (round A B2 + re-review F1: the red set is 6 of 8 arms; those two
#     sites are discriminated by the _af_case pins below, not by this
#     sabotage). The leak cell's armed pin and the signal window pin
#     red under this sabotage as well.
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

# --- 8b. A1/A3: work_register takes paths, never $-arguments -------------------
# Round A A1/A3: a "$"-prefixed argument is the work_register_var
# contract or a quoting slip -- unvalidated it put an eval target (or a
# syntax-error bomb) into the registry. Rejected at the gate now.
arm 'set -e; work_register '\''$(echo NOPE)'\''; pass unreachable'
rc_is 1 "work_register rejects a \$-prefixed non-name loud (A1)"
has "not \$names" "the rejection names the contract and the operand (A1)"
arm 'set -e; work_register '\''$WORK2'\''; pass unreachable'
rc_is 1 "the quoting-slip shape '\$WORK2' is rejected too (A3: no late-bound targets)"

# A1 hardening: a malformed $-line IN the registry (stale file, PID
# recycle -- work_register rejects them, corruption still reaches the
# file) must SKIP with a warning: later receivers stay collected, the
# registry file is removed, rc preserved. The cell seeds the registry
# directly (good / poison / good) before its exit runs the trap.
_a1h_out="$(mktemp -d)"
_a1h_a="$(mktemp -d)"
_a1h_b="$(mktemp -d)"
_a1h_cell="$(mktemp)"
cat >"$_a1h_cell" <<'A1H'
#!/bin/sh
. "$1"
printf '%s\n' "$2" '$(echo POISON)' "$3" >>"${TMPDIR:-/tmp}/opk-work-reg.$$"
exit 0
A1H
_a1h_rc=0
_a1h_err="$(TMPDIR="$_a1h_out" sh "$_a1h_cell" "$HARNESS" "$_a1h_a" "$_a1h_b" 2>&1 >/dev/null)" ||
    _a1h_rc=$?
_a1h_left="$(find "$_a1h_out" -mindepth 1 | wc -l | tr -d ' ')"
if [ "$_a1h_rc" = 0 ] && [ "$_a1h_left" = 0 ] &&
    printf '%s' "$_a1h_err" | grep -qF 'skipping malformed entry'; then
    ok "malformed registry line skips: later receivers collected, rc 0 (A1 hardening)"
else
    bad "malformed registry line must skip loudly and collect the rest (rc=$_a1h_rc left=$_a1h_left err=$(printf '%s' "$_a1h_err" | head -c 80))"
fi

# --- 8c. A2: errexit-safe cleanup keeps the suite rc ---------------------------
# A set -e suite with an unremovable registered receiver: the cleanup
# reports and skips it (loud), collects the rest, and the pending rc 0
# stands. The unremovable path is a read-only proc file -- rm fails on
# permissions, harmlessly, every run.
arm 'set -e; work_register /proc/version; W="$(work_new)"; echo "RECV=$W"; suite_done demo'
rc_is 0 "set -e suite with an unremovable receiver keeps rc 0 (A2)"
has "could not remove [/proc/version]" "the unremovable receiver is reported loud, skipped (A2)"
recv_gone "the removable receiver is still collected (A2)"

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
# after the sleep (0.0.46a F2 vacuity class). Round A B2/B3: the cell
# also verifies the child actually REGISTERED a receiver (the RECV=
# line -- an early-dying child used to green it vacuously) and carries
# its own disarmed control arm that must leak.
_sgi_cell() {
    # $1 = armed|gone -- sets _sig_left, _sig_el, _sig_recv
    _sgi_iso="$(mktemp -d)"
    _sgi_scratch="$(mktemp -d)"
    _sgi_script="$_sgi_scratch/cell.sh"
    _sgi_out="$(mktemp)"
    printf '#!/bin/sh\n. "$1"\nif [ "$2" = gone ]; then trap - EXIT INT TERM; fi\nW1="$(work_new)"\necho "RECV=$W1"\nsleep 30\n' \
        >"$_sgi_script"
    _sgi_start=$(date +%s)
    TMPDIR="$_sgi_iso" setsid sh "$_sgi_script" "$HARNESS" "$1" \
        >"$_sgi_out" 2>&1 &
    _sgi_pid=$!
    sleep 1
    kill -TERM "-$_sgi_pid" 2>/dev/null || :
    wait "$_sgi_pid" 2>/dev/null || :
    _sig_left="$(find "$_sgi_iso" -mindepth 1 | wc -l | tr -d ' ')"
    _sig_el=$(($(date +%s) - _sgi_start))
    _sig_recv="$(sed -n 's/^RECV=//p' "$_sgi_out" | tail -n 1)"
    rm -rf -- "$_sgi_iso"
    rm -rf -- "$_sgi_scratch"
    rm -f -- "$_sgi_out"
}
_sgi_cell armed
if [ -n "$_sig_recv" ]; then
    ok "signal cell: the child registered a receiver before the TERM (B3)"
else
    bad "signal cell: no RECV= line -- the child never registered (B3 vacuity)"
fi
if [ "$_sig_left" = 0 ] && [ "$_sig_el" -lt 10 ]; then
    ok "signal window: TERM lands, registry collects (zero leftovers, ${_sig_el}s)"
else
    bad "signal window: TERM must collect within the window (left=$_sig_left elapsed=${_sig_el}s)"
fi
_sgi_cell gone
if [ "$_sig_left" -ge 1 ] && [ "$_sig_el" -lt 10 ]; then
    ok "signal control arm: disarmed registry leaks under TERM (B2, pin discriminates)"
else
    bad "signal control arm must leak within the kill window (left=$_sig_left elapsed=${_sig_el}s)"
fi

# Append-failure arm (L1: every fail-loud spot gets a pin that executes
# the failure path). Round A B1: THREE separate append implementations
# exist (work_new/work_new_file via _work_emit, work_register and
# work_register_var inline) -- each site is pinned by its own blocked-
# registry case, asserting rc 1 AND the site's stderr message (round A
# B4: the message half must be observable, not discarded).
_af_case() {
    # $1 = the work_* call (child code), $2 = expected stderr token,
    # $3 = site label. The registry path is blocked by a directory
    # while mktemp still works. Asserts rc 1, the site's stderr message
    # (B4: observable, not discarded) and zero unregistered scratch.
    _afc_out="$(mktemp -d)"
    _afc_cell="$(mktemp)"
    printf '#!/bin/sh\n. "$1"\nmkdir "${TMPDIR:-/tmp}/opk-work-reg.$$"\nset -e\n%s\necho unreachable\n' "$1" \
        >"$_afc_cell"
    _afc_rc=0
    _afc_err="$(TMPDIR="$_afc_out" sh "$_afc_cell" "$HARNESS" 2>&1 >/dev/null)" ||
        _afc_rc=$?
    _afc_left="$(find "$_afc_out" -mindepth 1 ! -name 'opk-work-reg.*' | wc -l | tr -d ' ')"
    if [ "$_afc_rc" = 1 ] && [ "$_afc_left" = 0 ] &&
        printf '%s' "$_afc_err" | grep -qF "$2"; then
        ok "append failure ($3): rc 1 + message + no unregistered scratch"
    else
        bad "append failure ($3): must exit 1 naming [$2] with zero leftovers (rc=$_afc_rc left=$_afc_left err=$(printf '%s' "$_afc_err" | head -c 80))"
    fi
    rm -rf -- "$_afc_out"
    rm -f -- "$_afc_cell"
}
_af_case 'W="$(work_new)"' 'work_new: registry append failed' 'work_new'
_af_case 'F="$(work_new_file)"' 'work_new_file: registry append failed' 'work_new_file'
_af_case 'work_register /tmp/opk-af-nonexistent' 'work_register: registry append failed' 'work_register'
_af_case 'work_register_var V' 'work_register_var: registry append failed' 'work_register_var'
# mktemp-failure path (round A B1): a dead TMPDIR fails work_new loud
# before anything exists to leak -- mktemp's own error surfaces.
# (TMPDIR must be exported BEFORE the call: a prefix assignment applies
# after word expansion, and an unexported var never reaches mktemp.)
arm 'set -e; TMPDIR="/opk-dead-af"; export TMPDIR; W="$(work_new)"; echo unreachable'
rc_is 1 "work_new fails loud when mktemp fails (dead TMPDIR)"
has "failed to create" "mktemp's own error surfaces (no silent empty path)"
lacks unreachable "the abort happened at the failed mktemp"

# --- 9. extract_func (#396): the canonical function-extraction helper -----------
# Consolidation target of the nine suite-local extractors (inventory on
# #396): every converted suite relies on the strict-anchor contract --
# col-0 `name() {` .. first `^}` -- so these pins prove exactly that
# contract plus the two fail-loud guards, observed through the child
# shell the way production observes it (command substitution, pipes
# onto the output, stderr in the combined stream). Sabotage arms (run
# against a committed tree, then restore + re-run green):
#   - delete extract_func from harness.sh -> every 9.x pin goes red
#   - widen BOTH anchors to `^[[:space:]]*` -> the decoy_only pin (9.2)
#     goes red (over-capture guard discriminates)
#   - widen ONLY the end anchor -> the outer_host full-extent pin (9.8)
#     goes red (truncation discriminates)
_ef_fix="$(mktemp -d)"
printf '%s\n' \
    'alpha_fn() {' \
    '    # rider comment alpha' \
    '    A="set"' \
    '}' \
    'target_fn() {' \
    '    # rider comment target' \
    '    inner="}"' \
    '    case "$inner" in' \
    '        *)' \
    '            echo case-arm' \
    '            ;;' \
    '    esac' \
    '    TARGET_REACHED=1' \
    '}' \
    'outer_host() {' \
    '    decoy_only() {' \
    '        echo indented-decoy' \
    '    }' \
    '    HOST_REACHED=1' \
    '}' \
    >"$_ef_fix/subject.sh"

arm "extract_func \"$_ef_fix/subject.sh\" target_fn"
rc_is 0 "9.1 extract_func: known top-level function, rc 0"
has "target_fn() {" "9.1 ... finds the definition line"
has "TARGET_REACHED=1" "9.1 ... spans the whole body to its own closing brace"
has 'inner="}"' "9.1 ... an indented brace line does not close the range"
lacks "alpha_fn" "9.1 ... does not spill backwards into the previous def"
lacks "indented-decoy" "9.1 ... does not spill forward into later defs"

arm "extract_func \"$_ef_fix/subject.sh\" decoy_only"
rc_is 0 "9.2 absent at col 0: rc 0, not an error"
if [ -z "$_arm_out" ]; then
    ok "9.2 ... an indented-only def is invisible (over-capture guard)"
else
    bad "9.2 ... an indented-only def must extract empty (got: $_arm_out)"
fi

arm "extract_func \"$_ef_fix/subject.sh\" missing_fn"
rc_is 0 "9.3 unknown name: rc 0, not an error"
if [ -z "$_arm_out" ]; then
    ok "9.3 ... empty output (the caller's emptiness probe owns the verdict)"
else
    bad "9.3 ... unknown name must extract empty (got: $_arm_out)"
fi

arm "B=\$(extract_func \"$_ef_fix/subject.sh\" alpha_fn | sed 's/^[[:space:]]*#.*\$//'); printf '%s\n' \"\$B\""
lacks "# rider comment" "9.4 the #385 comment-strip rider composes on stdout"
has 'A="set"' "9.4 ... code lines survive the rider"

arm "_b=\$(extract_func \"$_ef_fix/subject.sh\" alpha_fn); [ -n \"\$_b\" ] && eval \"\$_b\"; alpha_fn; echo \"A=\$A\""
has "A=set" "9.5 the production idiom: emptiness probe + eval + call runs the block"

arm "extract_func \"$_ef_fix/subject.sh\" 'bad name'"
rc_is 1 "9.6 invalid name: rc 1 (fail-loud, L1)"
has "not a function name" "9.6 ... stderr names the bad argument"

arm "extract_func \"$_ef_fix/subject.sh\" ''"
rc_is 1 "9.6 empty name: rc 1 (a dropped argument cannot probe silently)"
has "not a function name" "9.6 ... stderr names it too"

arm "extract_func \"$_ef_fix/no-such-file\" alpha_fn"
rc_is 1 "9.7 missing file: rc 1 (fail-loud, L1)"
has "not a regular file" "9.7 ... stderr names the file"

# 9.7b (a R7): a DIRECTORY operand pins the -f semantics deterministically
# (the env-dependent unreadable-regular-file path stays unpinned by design —
# under a root runner sed would succeed and the pin could not discriminate).
arm "extract_func \"$_ef_fix\" alpha_fn"
rc_is 1 "9.7b directory operand: rc 1 (caught by the regular-file check)"
has "not a regular file" "9.7b ... same guard, same message"

# 9.8 (a R8): the full-extent discriminator the truncating end-anchor
# widening escaped — outer_host is the one fixture function whose body
# carries an indented nested def with its own indented close. A widened
# end anchor (`/^[[:space:]]*}/`) truncates right after the decoy's
# `    }` and drops HOST_REACHED=1 — every earlier pin observes nothing.
arm "extract_func \"$_ef_fix/subject.sh\" outer_host"
rc_is 0 "9.8 outer_host: rc 0"
has "outer_host() {" "9.8 ... finds the definition line"
has "indented-decoy" "9.8 ... spans past the nested def's indented close"
has "HOST_REACHED=1" "9.8 ... reaches the real body end (truncation discriminator)"

# --- 10. live_src / check_live (#460): the canonical comment-strip rider -------
# The rider primitive + the single-file sugar, pinned through the child
# shell the way production observes them (pipelines, command
# substitution, check_live rows + rc). Sabotage arms (committed tree,
# then restore + re-run green):
#   - delete the strip from live_src (body -> `cat "$_ls_f"`) -> the
#     strip pin (10.1) and BOTH survivor-trap arms (10.2, 10.9) go
#     red: a commented-out construct counts again -- exactly the
#     #261/#244 g W1 trap the rider exists to kill
#   - delete live_src from harness.sh -> the section reds. LIVE-
#     VERIFIED enumeration (round c, deletion executed against the
#     committed tree) -- RED ARMS: 10.1, 10.3, 10.4, 10.5, 10.6,
#     10.7, 10.11, 10.12, 10.15. FULLY GREEN ARMS: 10.2, 10.8,
#     10.9 -- rc-1-pinned absent-pattern arms: grep over the empty
#     stream yields the same rc 1 / FAIL row they pin, so their
#     outcome is identical with or without the stripper; 10.10, 10.13, 10.14 -- check_live's ARG guards precede any
#     live_src call. GREEN PINS inside red arms (expectations an
#     error-only or fail-row output satisfies): 10.1 p2/p3
#     (lacks-pins), 10.5 p2, 10.6 p1 (rc-1 pins), 10.7 p3 (the
#     desc rides the FAIL row too), 10.12 p1 (NORC=1 substring-
#     matches NORC=127) and p3/p4 (rc 1 + Failed: 1).
#   - break check_live's pipe (grep the FILE directly) -> 10.9 reds
#     while 10.1 stays green (discrimination runs through the strip,
#     not through the fixture)
_ls_fix="$(mktemp -d)"
printf '%s\n' \
    '# col-0 full-line comment rider_target' \
    '    # indented full-line comment rider_target' \
    'pinned_alpha="live-one"' \
    '# pinned_beta="survivor_trap_construct"' \
    '    # pinned_beta_ind="survivor_trap_construct"' \
    'pinned_gamma="live-two"' \
    'trailing_arm="kept # trailing comment stays"' \
    >"$_ls_fix/subject.sh"
printf '%s\n' \
    'fileb_marker="live-in-b"' \
    >"$_ls_fix/second.sh"

arm "live_src \"$_ls_fix/subject.sh\""
rc_is 0 "10.1 live_src: rc 0 over a readable file"
lacks "rider_target" "10.1 ... strips col-0 AND indented full-line comments"
lacks "survivor_trap_construct" "10.1 ... the commented constructs are gone from the stream"
has 'pinned_alpha="live-one"' "10.1 ... live lines survive verbatim"

arm "live_src \"$_ls_fix/subject.sh\" | grep -qF survivor_trap_construct"
rc_is 1 "10.2 survivor trap: a commented-out construct does NOT count (grep rc 1)"

arm "live_src \"$_ls_fix/subject.sh\" | grep -qF 'kept # trailing comment stays'"
rc_is 0 "10.3 full-line strip only: a trailing comment after live code still counts (#244 h W6)"

arm "live_src \"$_ls_fix/subject.sh\" \"$_ls_fix/second.sh\" | grep -qF live-in-b"
rc_is 0 "10.4 multi-file: concatenation carries the second file (any-file presence)"
arm "_c=\$(live_src \"$_ls_fix/subject.sh\" \"$_ls_fix/second.sh\" | grep -c 'live-'); printf 'COUNT=%s' \"\$_c\""
has "COUNT=3" "10.4 ... counts sum over the concatenation (3 live markers)"

arm "live_src \"$_ls_fix/subject.sh\" | grep -qF pinned_alpha"
rc_is 0 "10.5 rc contract: the consumer grep owns rc 0 on a live match"
arm "live_src \"$_ls_fix/subject.sh\" | grep -qF absent_pattern_xyz"
rc_is 1 "10.5 ... and rc 1 on no match (no || true swallowed in here)"

arm "live_src \"$_ls_fix/no-such-file\" | grep -qF x"
rc_is 1 "10.6 missing file: downstream grep rc 1 (the pin fails loud)"
has "no-such-file" "10.6 ... sed's own error names the file -- never a silent pass"

arm "check_live \"cl pass\" \"$_ls_fix/subject.sh\" -qF live-one; suite_done demo"
rc_is 0 "10.7 check_live: live match -> green suite"
has "Passed: 1" "10.7 ... counts as a pass"
has "cl pass" "10.7 ... the row carries the description"

arm "check_live \"cl absent\" \"$_ls_fix/subject.sh\" -qF absent_pattern_xyz; suite_done demo"
rc_is 1 "10.8 check_live: absent pattern -> red suite"
has "Failed: 1" "10.8 ... counts as a failure"

arm "check_live \"cl survivor\" \"$_ls_fix/subject.sh\" -qF survivor_trap_construct; suite_done demo"
rc_is 1 "10.9 check_live survivor trap: comment-only construct -> red (the #460 core)"
has "Failed: 1" "10.9 ... the trap counts as a failure, not a vacuous pass"

arm "check_live \"cl noargs\" \"$_ls_fix/subject.sh\"; suite_done demo"
rc_is 1 "10.10 check_live without grep arguments fails loud (F6 mirror)"
has "no grep arguments given" "10.10 ... names the contract"

arm "check_live \"cl ere\" \"$_ls_fix/subject.sh\" -Eq 'pinned_(alpha|gamma)=\"live'; suite_done demo"
rc_is 0 "10.11 grep flags pass through verbatim (-Eq ERE arm)"
arm "check_live \"cl spaced\" \"$_ls_fix/subject.sh\" -qF 'kept # trailing comment stays'; suite_done demo"
rc_is 0 "10.11 ... a spaced pattern with a # survives quoting intact"

# 10.12 (round a A4): a no-args live_src is a conversion-slip shape --
# it must fail loud, never stream empty rc 0 into a vacuous pass.
arm 'live_src >/dev/null 2>&1; echo "NORC=$?"'
has "NORC=1" "10.12 live_src without files returns rc 1 (A4)"
arm 'live_src 2>&1; true'
has "no files given" "10.12 ... the rejection names the contract on stderr (A4)"
arm 'check "vac slip" live_src; suite_done demo'
rc_is 1 "10.12 ... check around a bare live_src reds the suite (A4 vacuity)"
has "Failed: 1" "10.12 ... counted as a failure, not a vacuous pass"

# 10.13/10.14 (round a A5): dropped-argument slip shapes must land in
# a counted FAIL row -- under dash the unguarded `shift 2` used to
# abort the whole suite (rc 2, no fail row, no summary gate).
arm 'check_live "one arg"; suite_done demo'
rc_is 1 "10.13 check_live with only a desc -> fail row, suite rc 1 (A5)"
has "file argument missing" "10.13 ... the rejection names the missing operand (A5)"
arm 'check_live; suite_done demo'
rc_is 1 "10.14 zero-arg check_live -> fail row, suite rc 1 (A5)"
has "no arguments given" "10.14 ... the guard fires before any unset access (A5)"

# 10.15 (round a A6): the strip is LINE-PRESERVING (substitute-to-
# empty, not deletion) -- grep -n extraction legs keep raw-file line
# numbers. A deletion dialect (`/d`) must go red here.
arm "_ls=\$(live_src \"$_ls_fix/subject.sh\" | wc -l | tr -d ' '); _raw=\$(wc -l < \"$_ls_fix/subject.sh\" | tr -d ' '); printf 'LINES=%s/%s' \"\$_ls\" \"\$_raw\""
has "LINES=7/7" "10.15 line-preserving dialect: comment lines become empty lines (A6)"

# --- 11. test_chain (#464): the wrapped make-test chain reader -----------------
# The one-prerequisite-per-line chain layout is RULE-enforced in the
# Makefile (layout pin in test-workflows.sh); test_chain is the READER
# every membership pin uses. Fixture pins pin SHAPE, not the live
# chain's contents -- suites get added, counts belong to no meta-pin.
# Sabotage note: delete test_chain from harness.sh -> every 11.x pin
# goes red.
_tc_fix="$(mktemp -d)"
printf '%s\n' \
    '.PHONY: x' \
    'test: lint \' \
    '      test-docs \' \
    '      test-kit-cli' \
    '' \
    '	@echo hi' >"$_tc_fix/wrapped.mk"
printf '%s\n' \
    'test: lint test-docs test-kit-cli' \
    '' \
    '	@echo hi' >"$_tc_fix/unwrapped.mk"
printf '%s\n' \
    '.PHONY: x \' \
    '    test-docs' \
    'test: lint' \
    '' \
    '	@echo hi' >"$_tc_fix/phony-only.mk"

# 11.1 exact output: head token stripped, one prerequisite per line,
# recipe line excluded (the span stops at the first TAB line).
arm "_tc_out=\$(test_chain \"$_tc_fix/wrapped.mk\"); printf 'OUT:%s|END' \"\$_tc_out\""
rc_is 0 "11.1 test_chain exits 0 on a wrapped chain"
has "OUT:lint
test-docs
test-kit-cli|END" "11.1 wrapped chain: stripped head, one name per line, recipe excluded"

# 11.2 the reader is layout-independent: an unwrapped single-line chain
# yields the same token stream (membership must not depend on wrapping).
arm "printf 'OUT:%s|END' \"\$(test_chain \"$_tc_fix/unwrapped.mk\")\""
has "OUT:lint
test-docs
test-kit-cli|END" "11.2 unwrapped chain: same token stream"

# 11.3 the stray-dog discriminator: the name only in a .PHONY
# continuation must NOT count as chain membership -- this exact slip
# shipped in the first #464 fix wave and the sabotage run caught it.
arm "test_chain \"$_tc_fix/phony-only.mk\" | grep -qxF 'test-docs'"
rc_is 1 "11.3 .PHONY-only name is not chain membership"

# 11.4 guards fail loud (L1): wrong arity and missing file, both before
# any vacuous empty output can read as a green membership probe.
arm 'test_chain'
rc_is 1 "11.4 arity guard: no argument"
has "test_chain: exactly one Makefile path required" "11.4 arity guard names the contract"
arm 'test_chain /nonexistent/nowhere.mk'
rc_is 1 "11.4 missing-file guard"
has "no such file" "11.4 missing-file guard names the path"

# --- summary gate (independent on purpose -- see header) ------------------------
echo ""
if [ "$bad" -gt 0 ]; then
    echo "  $bad meta-test(s) failed."
    exit 1
fi
echo "  all harness meta-tests passed ($ok)."
exit 0
