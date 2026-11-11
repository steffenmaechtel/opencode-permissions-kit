#!/bin/sh
# Unit tests for sh/doctor-core.sh (issue #346 wave shape, #448): the
# doctor run's section functions, sourced from the lib the way
# doctor.sh sources them -- the status-core pin pattern. The
# full-script behavioral matrix stays in test-doctor.sh (it runs
# doctor.sh end to end); this suite pins what only the DECOMPOSED shape
# can pin:
#   - sourcing purity: definitions only, zero top-level side effects
#   - every section entry point + helper is defined by sourcing
#   - the pairing guard (#413): real lib passes, truncated lib dies
#     loud, the entry wires the guard after the resolver, and the
#     guard list covers every section the entry calls AND every
#     function the lib defines (both riders comment-stripped and
#     boundary-anchored)
#   - the control-character gates at function level (doctor_cntrl_bad /
#     doctor_show_sanitize): C0/DEL/C1 detect, UTF-8 passes clean
#   - the report header at function level (doctor_header): verified and
#     unverified range arms, fix/detect mode rows
#   - python3 -I sweep floor over the lib's decoder sites (#249)
# Run: sh tests/unit/test-doctor-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/doctor-core.sh"
UI_LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ui.sh"
DOCTOR_ENTRY="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/doctor.sh"

# Shared harness (issue #394): pass/fail, colors, counters + the work
# registry (issue #395) -- no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# Controlled PATH (agent/conventions.md, "Test sandbox (unit suites)"):
# a scratch bin with the called functions' externals only. Sourcing the
# lib needs none (definitions only), python3/awk serve the called legs.
# sh itself is resolved ONCE from the host PATH before the prefix --
# dash resolves the command word after the assignment prefix, so a bare
# `PATH=$STUB sh -c` is rc-127 vacuous (the L4 wrong-mechanism class).
STUB="$WORK/bin"
mkdir -p "$STUB"
ln -s "$(command -v python3)" "$STUB/python3"
ln -s "$(command -v awk)" "$STUB/awk"
ln -s "$(command -v grep)" "$STUB/grep"
SH_BIN="$(command -v sh)"

# --- 1. sourcing purity: definitions only, zero side effects ----------------------
# The lib's core contract (#346): sourcing defines functions and nothing
# else -- no ui.sh needed, no probes, no output, no file writes. A
# top-level probe, print or mktemp sneaking in shows up here.
_purity_out=$(PATH="$STUB" "$SH_BIN" -c '. "$1"' _ "$LIB" 2>&1) || _purity_rc=$?
if [ "${_purity_rc:-0}" = 0 ] && [ -z "$_purity_out" ]; then
    pass "sourcing doctor-core.sh runs nothing, prints nothing"
else
    fail "sourcing doctor-core.sh must be side-effect free (rc=${_purity_rc:-0} out=$_purity_out)"
fi
# structural twin: after sourcing, $WORK-adjacent scratch must not exist
# (the ranges section's mktemp would have created one) -- a second eye
# on the same contract through the filesystem.
_noside="$(find "$WORK" -maxdepth 1 -type d | wc -l)"
if [ "$_noside" = 2 ]; then # $WORK itself + $STUB -- nothing else appeared
    pass "sourcing created no scratch receivers"
else
    fail "sourcing must not create scratch (dirs found: $_noside)"
fi

# --- 2. every section entry point + helper is defined by sourcing -----------------
_defs="doctor_cli doctor_all doctor_walkup doctor_opk_dispatcher
doctor_daemon_user doctor_ranges doctor_header doctor_policy
doctor_detect doctor_scan_trees doctor_fix doctor_summary
_doctor_usage _doctor_all_cleanup _doctor_cleanup doctor_cntrl_bad
doctor_show_sanitize doctor_userns_ranges doctor_load_policy
doctor_classify doctor_examples _doctor_detect_path_ok"
_missing=""
for _fn in $_defs; do
    sh -c '. "$1" && command -v "$2" >/dev/null' _ "$LIB" "$_fn" 2>/dev/null ||
        _missing="$_missing $_fn"
done
if [ -z "$_missing" ]; then
    pass "all 22 section/helper functions defined by sourcing"
else
    fail "functions missing after sourcing:$_missing"
fi

# --- 3. pairing guard (#413): a version-skewed entry/lib pairing dies loud ---------
# doctor is deliberately fail-soft (set -u only) -- an undefined call
# does NOT abort, the report silently loses the section while the
# summary still prints (over a possibly unscanned tree). The guard
# refuses the skewed pairing before any section runs; it pins EVERY
# function the run needs, sections AND helpers (#451 a M1 -- a
# helper-level skew would render "empty (nothing classified)" and
# exit 0). Both directions in fresh children + completeness riders
# over the entry's own calls and the lib's own definitions.
_pg_src="$(extract_func "$DOCTOR_ENTRY" doctor_pairing_guard)"
if [ -n "$_pg_src" ]; then
    pass "doctor_pairing_guard extractable from the entry"
else
    fail "doctor_pairing_guard extractable from the entry"
fi
# comment-stripped copy of the guard source for the riders below
# (#451 b B3, conventions.md "Source-counting pins" over extracted
# blocks): a FULL-LINE comment inside the guard naming a function must
# not count (the strip is full-line only -- trailing comments after
# live lines still count, the #244 h W6 residual).
_pg_src_s="$(printf '%s\n' "$_pg_src" | sed 's/^[[:space:]]*#.*$//')"
_pg_full=$(sh -c 'eval "$1"; . "$2"; doctor_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1)
_pg_tr_rc=0
_pg_tr_out="$(PATH="$STUB" "$SH_BIN" -c 'eval "$1"; ui_error() { echo "error: $*" >&2; }; doctor_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every function defined) (#413)"
else
    fail "pairing guard must pass against the real lib (out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "function 'doctor_cli' missing from doctor-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud before any section runs (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
if sed 's/^[[:space:]]*#.*$//' "$DOCTOR_ENTRY" | grep -qF 'doctor_pairing_guard || exit 1'; then
    pass "doctor.sh wires the guard right after the resolver (#413)"
else
    fail "doctor.sh must call the guard after sourcing doctor-core.sh (#413)"
fi
# completeness rider (entry direction): every section the entry CALLS
# at col 0 (the run sequence) must sit in the guard's list -- a
# section added to the run order without the guard is exactly the
# wiring bug #413 describes. The grep is BOUNDARY-ANCHORED (#451 b B2):
# plain -qF would find section names as substrings of the helper names
# in the list (_doctor_all_cleanup contains doctor_all) and a dropped
# name would false-pass.
_pg_missing=""
_pg_entfns="$(sed 's/^[[:space:]]*#.*$//' "$DOCTOR_ENTRY" |
    grep -oE '^doctor_[a-z_0-9]+' | grep -v '^doctor_pairing_guard$' |
    grep -v '^doctor_ui_pairing_guard$' | sort -u)"
# emptiness probe (#457, the #455 a C2 contract): an empty extraction
# would run the loop zero times and the rider would pass vacuously --
# the harness contract puts that probe on the caller. The second
# exclusion drops the entry's OWN ui used-set guard (#456) — its def
# and call are doctor_* tokens but belong to the ui-lib surface, not
# the doctor-core guard list.
[ -n "$_pg_entfns" ] || _pg_missing="(entry call extraction empty)"
for _fn in $_pg_entfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "pairing guard list covers every section the entry calls (#413)"
else
    fail "sections called by doctor.sh but absent from the guard:$_pg_missing (#413)"
fi
# completeness rider (helper direction, #451 a M1): every function the
# LIB defines must sit in the guard's list too -- a helper missing
# from the list is the helper-skew hole the round-a fix closes. Same
# boundary anchor (#451 b B2), same stripped source (B3).
_pg_hmissing=""
_pg_libfns="$(grep -oE '^[A-Za-z_][A-Za-z_0-9]*\(\) \{' "$LIB" | sed 's/() {//' | sort -u)"
# emptiness probe (#457, the #455 a C2 contract -- same shape the four
# core suites' helper-direction riders already carry): an empty
# extraction would run the loop zero times and pass vacuously.
[ -n "$_pg_libfns" ] || _pg_hmissing="(lib function extraction empty)"
for _fn in $_pg_libfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_hmissing="$_pg_hmissing $_fn"
done
if [ -z "$_pg_hmissing" ]; then
    pass "pairing guard list covers every function the lib defines (#451 a M1)"
else
    fail "functions defined by doctor-core.sh but absent from the guard:$_pg_hmissing (#451 a M1)"
fi

# --- 4. control-character gates at function level ----------------------------------
# doctor_cntrl_bad: the C0/DEL/C1 gate (#370 a C1). The prefilter plus
# python decoder must detect every control class and PASS clean UTF-8
# (the plain byte-bracket pattern false-positives on trail bytes --
# U+00DC = 0xC3 0x9C -- measured in round a A1).
_cb_run() { # <string> -> rc of doctor_cntrl_bad
    PATH="$STUB" "$SH_BIN" -c '. "$1" && doctor_cntrl_bad "$2"' _ "$LIB" "$1" 2>/dev/null
}
if _cb_run "$(printf 'a\tb')"; then
    pass "cntrl gate: TAB (C0) detected"
else
    fail "cntrl gate: TAB (C0) detected"
fi
if _cb_run "$(printf 'a\177b')"; then
    pass "cntrl gate: DEL detected"
else
    fail "cntrl gate: DEL detected"
fi
if _cb_run "$(printf 'a\203b')"; then
    pass "cntrl gate: raw C1 byte (0x83) detected"
else
    fail "cntrl gate: raw C1 byte (0x83) detected"
fi
if _cb_run "plain-ascii/path"; then
    fail "cntrl gate: clean ASCII must pass"
else
    pass "cntrl gate: clean ASCII must pass"
fi
if _cb_run "$(printf '\303\234mlaut')"; then
    fail "cntrl gate: UTF-8 umlaut must pass (trail bytes are not C1)"
else
    pass "cntrl gate: UTF-8 umlaut must pass (trail bytes are not C1)"
fi
# doctor_show_sanitize: display copy strips control CHARACTERS, valid
# UTF-8 round-trips byte-identical (round b B1).
_ss_out=$(PATH="$STUB" "$SH_BIN" -c '. "$1" && doctor_show_sanitize "$2"' _ "$LIB" "$(printf 'a\tb\233c')" 2>/dev/null |
    od -An -tx1 | tr -s ' ')
if [ "$_ss_out" = " 61 62 63" ]; then
    pass "sanitize: TAB and CSI bytes stripped, letters kept"
else
    fail "sanitize must strip control characters (got [$_ss_out])"
fi
_ss_out=$(PATH="$STUB" "$SH_BIN" -c '. "$1" && doctor_show_sanitize "$2"' _ "$LIB" "$(printf '\303\234mlaut')" 2>/dev/null |
    od -An -tx1 | tr -s ' ')
if [ "$_ss_out" = " c3 9c 6d 6c 61 75 74" ]; then
    pass "sanitize: UTF-8 round-trips byte-identical"
else
    fail "sanitize must keep UTF-8 intact (got [$_ss_out])"
fi

# --- 5. report header at function level --------------------------------------------
# doctor_header renders the section banner, root/mode/daemon rows and
# the mapped-range row (verified: formatted from $WORK/ranges; else the
# unverified warn). Runs with ui.sh loaded and the section's globals
# set the way doctor.sh sets them before the call.
_hdr_run() { # <range-file-content|none> <mode> <extra-env...>
    _hr_ranges="$1"
    _hr_mode="$2"
    shift 2
    (
        PATH="$STUB:$PATH"
        export PATH NO_COLOR=1
        . "$UI_LIB"
        . "$LIB"
        DOCTOR_ROOT="$WORK/hdr-proj"
        DOCTOR_DISCOVERED=0
        DOCTOR_START_DIR=""
        DOCTOR_MODE="$_hr_mode"
        DOCTOR_FIX_DRY=0
        DOCTOR_USER=opencode
        DOCTOR_DAEMON_UID=1000
        DOCTOR_RANGE_VERIFIED=0
        if [ "$_hr_ranges" != none ]; then
            printf '%s\n' "$_hr_ranges" >"$WORK/ranges"
            DOCTOR_RANGE_VERIFIED=1
        else
            : >"$WORK/ranges"
        fi
        eval "$@"
        doctor_header
    ) 2>&1
}
_out=$(_hdr_run "0:1
1000:56" scan "" || true)
if printf '%s' "$_out" | grep -qF 'project root' &&
    printf '%s' "$_out" | grep -qF 'mapped range' &&
    printf '%s' "$_out" | grep -qF '0, 1000-1055 -- live uid_map' &&
    ! printf '%s' "$_out" | grep -qF 'mode'; then
    pass "header: verified ranges formatted, no mode row in scan"
else
    fail "header: verified-range row broken (out=$_out)"
fi
_out=$(_hdr_run none scan "" || true)
if printf '%s' "$_out" | grep -qF 'unverified -- no user namespace' &&
    printf '%s' "$_out" | grep -qF 'until the backend runs'; then
    pass "header: unverified arm renders the backend-down warn"
else
    fail "header: unverified arm broken (out=$_out)"
fi
_out=$(_hdr_run "0:1" fix "DOCTOR_FIX_DRY=1" || true)
if printf '%s' "$_out" | grep -qF 'fix --dry-run (show the handover plan, change nothing)'; then
    pass "header: fix --dry-run mode row"
else
    fail "header: fix --dry-run mode row broken (out=$_out)"
fi
_out=$(_hdr_run "0:1" detect "" || true)
if printf '%s' "$_out" | grep -qF 'detect (propose opk.json entries from ownership evidence)'; then
    pass "header: detect mode row"
else
    fail "header: detect mode row broken (out=$_out)"
fi

# --- sweep floor: doctor-core's python3 sites run -I (#249) ------------------------
# Comment-strip rider per conventions.md ("Source-counting pins") -- a
# commented-out site must not count. Four sites: cntrl_bad,
# show_sanitize, load_policy, the detect write block.
_pc=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -c 'python3 -I' || true)
if [ "${_pc:-0}" = 4 ]; then
    pass "sweep floor: doctor-core.sh python3 calls run -I (all $_pc sites, #249)"
else
    fail "doctor-core.sh must run exactly 4 python3 sites with -I (found ${_pc:-0}) (#249)"
fi

suite_done
