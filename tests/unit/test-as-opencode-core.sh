#!/bin/sh
# Unit tests for sh/as-opencode-core.sh (issue #346 wave shape, #449):
# the opencode wrapper's section functions, sourced from the lib the
# way bin/opencode-as-opencode sources them -- the doctor-core /
# status-core pin pattern. The full-wrapper behavioral matrix stays in
# test-opencode-as-opencode.sh (block pins retargeted there, sourcing
# legs included); this suite pins what only the DECOMPOSED shape can:
#   - sourcing purity: definitions only, zero top-level side effects
#   - every section entry point + helper is defined by sourcing
#   - the resolver: a missing lib refuses loud (the #165 class), and
#     the entry wires sourcing + pairing guard before any section
#   - the pairing guard (#413): real lib passes, a section-less
#     (version-skewed) lib dies loud naming the missing section, and
#     the guard list covers every section the entry calls
#   - the guard's failure is observed the way production observes it:
#     on stderr, before any banner or diagnostic byte of the wrapper
# Run: sh tests/unit/test-as-opencode-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/as-opencode-core.sh"
ENTRY="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opencode-as-opencode"

# Shared harness (issue #394): pass/fail, assert_eq, extract_func +
# the counters live in lib/harness.sh; the work registry (issue #395)
# owns cleanup -- no trap of our own.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# --- 1. sourcing purity: definitions only, zero side effects ---------------------
# The lib's core contract (#346): sourcing defines functions and nothing
# else -- no probes, no output, no file writes. A top-level probe or
# print sneaking in shows up here (the wrapper sources this lib on EVERY
# start, before the first user-visible byte).
_purity_out=$(sh -c '. "$1"' _ "$LIB" 2>&1) || _purity_rc=$?
if [ "${_purity_rc:-0}" = 0 ] && [ -z "$_purity_out" ]; then
    pass "sourcing as-opencode-core.sh runs nothing, prints nothing"
else
    fail "sourcing as-opencode-core.sh must be side-effect free (rc=${_purity_rc:-0} out=$_purity_out)"
fi
# structural twin: nothing appeared next to the receiver
_noside="$(find "$WORK" -mindepth 1 | wc -l)"
if [ "$_noside" = 0 ]; then
    pass "sourcing created no scratch receivers"
else
    fail "sourcing must not create scratch (found: $_noside)"
fi

# --- 2. every section entry point + helper is defined by sourcing ----------------
_defs="wrapper_headless_classify wrapper_validate_cwd
wrapper_version_passthrough wrapper_refusal wrapper_banner
wrapper_update_note wrapper_advisories wrapper_path_shadow_warning
wrapper_wsl_checks wrapper_resolve_major wrapper_container_detect
wrapper_container_resolve wrapper_container_advisory
wrapper_serve_cwd_fallback wrapper_login_cwd_fallback
openchamber_guard standalone_mode note _opk_timeout_ok merged_config
tools_from_config stop_merged_config_service sock_reachable cwd_probe"
# census size for the message + the guard rider below
_ndefs="$(printf '%s\n' $_defs | wc -w | tr -d ' ')"
_missing=""
for _fn in $_defs; do
    sh -c '. "$1" && command -v "$2" >/dev/null' _ "$LIB" "$_fn" 2>/dev/null ||
        _missing="$_missing $_fn"
done
if [ -z "$_missing" ]; then
    pass "all $_ndefs section/helper functions defined by sourcing"
else
    fail "functions missing after sourcing:$_missing"
fi

# --- 2b. structural purity: nothing executable at col 0 (#453 a C6) -------------
# The purity pin above observes output/rc/scratch only; a top-level
# ASSIGNMENT or `set` flag produces none of those yet contradicts the
# "definitions and comments only" contract. Structural twin: every
# col-0 non-blank line must be a comment, a function opener/closer, or
# one of the two heredoc payload/terminator lines inside
# wrapper_advisories (col 0 by contract, unindented); INDENTED lines
# are function-body bytes and out of this pin's scope.
_stray="$(awk 'NF && $0 !~ /^[ \t]/ && $0 !~ /^#/ && $0 !~ /^[a-z_]+\(\) \{$/ &&
    $0 !~ /^(}|\$ADV_HIT|\$ADV_HITS|EOF)$/ {print FNR": "$0}' "$LIB")"
if [ -z "$_stray" ]; then
    pass "lib carries no col-0 executable lines (definitions/comments only)"
else
    fail "col-0 side-effect candidates in the lib: $(printf '%s' "$_stray" | head -3)"
fi

# --- 3. resolver: a missing lib refuses loud (#165 class) ------------------------
# A damaged deployment (lib not deployed / deleted) must refuse with a
# NAMED error on stderr, never fall through to the exec or die with a
# bare shell message. The failure is observed the way production
# observes it: stderr, before any wrapper output. The entry copy runs
# from a scratch lib root that has no sh/as-opencode-core.sh -- the
# checkout fallback path in the entry resolves the scratch dir first.
_rm_root="$WORK/resolver-missing"
mkdir -p "$_rm_root/bin"
cp "$ENTRY" "$_rm_root/bin/opencode-as-opencode"
_rm_rc=0
_rm_out="$(cd "$WORK" && sh "$_rm_root/bin/opencode-as-opencode" 2>&1 >/dev/null)" || _rm_rc=$?
if [ "$_rm_rc" -ne 0 ] &&
    printf '%s' "$_rm_out" | grep -qF 'as-opencode-core.sh not found'; then
    pass "resolver: a missing as-opencode-core.sh refuses loud (#449, #165 class)"
else
    fail "resolver: a missing lib must refuse loud, rc!=0 (rc=$_rm_rc got: $_rm_out)"
fi
# and the refusal is the FIRST thing the wrapper ever prints: stdout
# stays empty (no banner, no diagnostics ahead of the wiring error)
_rm_stdout="$(cd "$WORK" && sh "$_rm_root/bin/opencode-as-opencode" 2>/dev/null)" || true
if [ -z "$_rm_stdout" ]; then
    pass "resolver: the missing-lib refusal prints nothing on stdout"
else
    fail "resolver: wiring error must precede every stdout byte (got: $_rm_stdout)"
fi

# --- 4. pairing guard (#413): a version-skewed lib dies loud ---------------------
_pg_src="$(extract_func "$ENTRY" wrapper_pairing_guard)"
if [ -n "$_pg_src" ]; then
    pass "wrapper_pairing_guard extractable from the entry"
else
    fail "wrapper_pairing_guard not extractable from the entry"
fi
# 4a. the real lib passes the guard
if [ -n "$_pg_src" ] &&
    sh -c '. "$1"; eval "$2"; wrapper_pairing_guard' _ "$LIB" "$_pg_src" 2>/dev/null; then
    pass "pairing guard: the real lib passes (no skew)"
else
    fail "pairing guard: the real lib must pass the guard"
fi
# 4b. a lib missing ONE section (version skew: renamed/newly-added
# section not yet deployed) is refused loud, naming the section -- the
# unset emulates a truncated/skewed vintage without a second fixture
_sk_out="$(sh -c '. "$1"; unset -f wrapper_refusal; eval "$2"; wrapper_pairing_guard' \
    _ "$LIB" "$_pg_src" 2>&1)" && _sk_rc=0 || _sk_rc=$?
if [ "$_sk_rc" -ne 0 ] &&
    printf '%s' "$_sk_out" | grep -qF 'version-skewed (wrapper_refusal missing)'; then
    pass "pairing guard: a section-less lib refuses naming the section (#413)"
else
    fail "pairing guard: skew refusal must name the section (rc=$_sk_rc got: $_sk_out)"
fi
# 4c. the guard is wired AFTER the resolver and BEFORE the first
# section call (a guard that runs after sections protects nothing)
_src_ln="$(grep -nF '. "$WRAPPER_CORE"' "$ENTRY" | cut -d: -f1)"
_guard_ln="$(grep -nF 'wrapper_pairing_guard || exit 1' "$ENTRY" | cut -d: -f1)"
_first_ln="$(grep -nF 'wrapper_headless_classify "$@"' "$ENTRY" | cut -d: -f1)"
if [ -n "$_src_ln" ] && [ -n "$_guard_ln" ] && [ -n "$_first_ln" ] &&
    [ "$_src_ln" -lt "$_guard_ln" ] && [ "$_guard_ln" -lt "$_first_ln" ]; then
    pass "entry wires resolver -> guard -> sections in order"
else
    fail "entry wiring order broken (src:$_src_ln guard:$_guard_ln first:$_first_ln)"
fi
# 4d. completeness riders (#453 a A2/B1/C5, brought to the four-suite
# standard by #457): the guard's list must cover EVERY function the lib
# defines -- sections AND helpers -- extracted from the lib itself, so
# a future helper addition that misses the guard fails here (the old
# rider compared entry calls only and left the 7 helpers uncovered).
# #457 fixes the substandard mechanics: the match source is a
# comment-stripped copy of the guard source (the comment-survivor
# trap was armed -- a comment inside wrapper_pairing_guard naming a
# dropped function would have counted as coverage; no such comment
# exists today, the raw-source match was the latent hazard, #459 a
# B2), the extraction uses the family ERE (digit-bearing and
# uppercase names visible, latent -- no such name exists among
# today's 24 defs; the old '^[a-z_]+' form was blind to them), the
# match is BOUNDARY-ANCHORED
# (the old " $_c[ ;]" prefix shape let a strict-prefix name of a listed
# one match, #453 b D1), and the extraction carries an emptiness probe
# (#455 a C2 contract): an empty list must fail loud, not run the loop
# zero times and pass vacuously.
_pg_src_s="$(printf '%s\n' "$_pg_src" | sed 's/^[[:space:]]*#.*$//')"
_pg_hmissing=""
_pg_libfns="$(grep -oE '^[A-Za-z_][A-Za-z_0-9]*\(\) \{' "$LIB" | sed 's/() {//' | sort -u)"
[ -n "$_pg_libfns" ] || _pg_hmissing="(lib function extraction empty)"
for _fn in $_pg_libfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_hmissing="$_pg_hmissing $_fn"
done
if [ -z "$_pg_hmissing" ]; then
    pass "guard list covers every lib-defined function ($(printf '%s\n' "$_pg_libfns" | wc -l | tr -d ' ') names)"
else
    fail "guard list misses function(s):$_pg_hmissing"
fi
# 4e. completeness rider (entry direction, #457): every function the
# ENTRY calls at col 0 (the run sequence) plus the standalone_mode
# gate -- whose call shape `case $(standalone_mode "$@") in` does NOT
# put the name at col 0, so the extraction normalizes it first
# (#459 a B1: the original form claimed the gate while the anchored
# grep could never see it; class sweep: this is the only non-col-0
# call of a covered function across all six entries) -- must sit in
# the guard's list too. The #453 fix had replaced the old entry-calls
# rider with the lib-defs rider above, so the wrapper's own calls
# were enforced by nothing (latent: no unguarded call exists today,
# verified at #457 filing). Same stripped guard source, same boundary
# anchor, same emptiness probe as 4d.
_pg_missing=""
_pg_entfns="$(sed 's/^[[:space:]]*#.*$//' "$ENTRY" |
    sed 's/^case \$(standalone_mode.*/standalone_mode/' |
    grep -oE '^(wrapper_[a-z_0-9]+|openchamber_guard|standalone_mode)' |
    grep -v '^wrapper_pairing_guard$' | sort -u)"
[ -n "$_pg_entfns" ] || _pg_missing="(entry call extraction empty)"
for _fn in $_pg_entfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "guard list covers every function the entry calls (#457)"
else
    fail "functions called by opencode-as-opencode but absent from the guard:$_pg_missing (#457)"
fi

suite_done "as-opencode-core lib tests"
