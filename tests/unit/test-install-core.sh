#!/bin/sh
# Unit tests for sh/install-core.sh (issue #346, wave 3): the install
# run's phase functions, sourced from the lib the way install.sh sources
# them (kit_source) — the log.sh pin pattern (source the lib, call the
# function, stub the environment). This suite is the #396 payoff: the
# four helpers below used to be indentation-anchored block extractions
# in test-install-args.sh (0.0.44a V15, 0.0.44b W6/W14, 0.0.44a V1) —
# the wave-3 wrap makes them real function pins. The root-run phase
# flows (user creation, provisioning, deploys) stay with e2e (category
# 3, no coverage promise). This suite pins what only the DECOMPOSED
# shape can pin:
#   - sourcing purity: definitions only, zero top-level side effects
#   - the three phases + the four wrapped helpers are defined by sourcing
#   - the pairing guard (#413, #452): real lib passes, truncated lib dies
#     loud, and both completeness riders (every phase the entry calls
#     AND every function the lib defines — comment-stripped,
#     boundary-anchored)
#   - install.sh resolves the lib via kit_source from $SCRIPT_DIR (the
#     checkout/fetched tree) and has NO $LIBDIR fallback — install.sh
#     never runs from the installed tree (presence-level; driving the
#     loud-die arm needs a broken fetch tree — deliberately not pinned,
#     pin-cost budget)
#   - the entry sequences the three phases in run order
#   - install_agents_form_normalize: every accepted form -> its letter
#   - the reuse guards: deviating home/group abort loud with the
#     remediation, matching values pass silently (getent/id stubs keep
#     every arm deterministic — the 0.0.46a F2 class)
#   - install_project_roots_select: both EOF bails (outer V6, inner W6)
#     abort after 5 empty reads instead of spinning, skip resolves,
#     custom paths ride project_path_sane/_PP_NORM
# Run: sh tests/unit/test-install-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh"
INSTALL="$SCRIPT_DIR/../../files/install.sh"

# Shared harness (issue #394): pass/fail, counters + the work registry
# (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# --- 1. sourcing purity: definitions only, zero side effects ----------------------
_purity_out=$(sh -c '. "$1"' _ "$LIB" 2>&1) || _purity_rc=$?
if [ "${_purity_rc:-0}" = 0 ] && [ -z "$_purity_out" ]; then
    pass "sourcing install-core.sh runs nothing, prints nothing"
else
    fail "sourcing install-core.sh must be side-effect free (rc=${_purity_rc:-0} out=$_purity_out)"
fi

# --- 2. every phase function + wrapped helper is defined by sourcing -------------
_defs="do_plan_phase do_ddev_phase do_deploy_phase
install_reuse_home_guard install_reuse_group_guard
install_project_roots_select install_agents_form_normalize
install_deploy_library"
_missing=""
for _fn in $_defs; do
    sh -c '. "$1" && command -v "$2" >/dev/null' _ "$LIB" "$_fn" 2>/dev/null ||
        _missing="$_missing $_fn"
done
if [ -z "$_missing" ]; then
    pass "all 3 phases + 4 helpers defined by sourcing"
else
    fail "functions missing after sourcing:$_missing"
fi

# --- 3. the entry resolves the lib from its own tree, no LIBDIR fallback ----------
# install.sh never runs from the installed tree (re-deploys go through
# update.sh), so a deployed-lib fallback could feed stale phases to a
# newer streamed script — the resolver must stay kit_source/$SCRIPT_DIR.
# Comment-strip on the positive conjunct (conventions.md
# "Source-counting pins", the #451 a Q3 shape): a commented-out
# kit_source line must not satisfy the pin. The no-fallback ABSENCE leg
# stays un-ridden (absence pins are out of scope — a commented-out
# forbidden line SHOULD keep counting there).
if live_src "$INSTALL" |
    grep -qF 'kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/install-core.sh"' &&
    ! grep -q 'LIBDIR/sh/install-core' "$INSTALL"; then
    pass "install.sh kit_sources install-core.sh from \$SCRIPT_DIR, no \$LIBDIR fallback"
else
    fail "install.sh resolver shape (kit_source from \$SCRIPT_DIR, no LIBDIR fallback)"
fi
# resolver sits before the phase calls (a later kit_source would still
# define the functions in time, but the block ordering is the documented
# shape — checkout cluster first, phases called from Main)
_kit_ln=$(grep -n 'kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/install-core.sh"' "$INSTALL" | cut -d: -f1)
_plan_ln=$(grep -n '^do_plan_phase$' "$INSTALL" | cut -d: -f1)
if [ -n "$_kit_ln" ] && [ -n "$_plan_ln" ] && [ "$_kit_ln" -lt "$_plan_ln" ]; then
    pass "kit_source line precedes the phase calls (order pin)"
else
    fail "kit_source line precedes the phase calls (kit=$_kit_ln plan=$_plan_ln)"
fi
# the entry sequences all three phases in run order (plan -> ddev -> deploy)
_p1=$(grep -n '^do_plan_phase$' "$INSTALL" | cut -d: -f1)
_p2=$(grep -n '^do_ddev_phase$' "$INSTALL" | cut -d: -f1)
_p3=$(grep -n '^do_deploy_phase$' "$INSTALL" | cut -d: -f1)
if [ -n "$_p1" ] && [ -n "$_p2" ] && [ -n "$_p3" ] &&
    [ "$_p1" -lt "$_p2" ] && [ "$_p2" -lt "$_p3" ]; then
    pass "entry calls plan -> ddev -> deploy in run order"
else
    fail "entry phase order (plan=$_p1 ddev=$_p2 deploy=$_p3)"
fi

# --- 4. install_agents_form_normalize: every accepted form -> its letter ----------
# 0.0.44a V1: `--migrate-agents move` must not silently degrade to a
# copy — the words normalize to the letters the dispatch compares.
for _pair in "m:m" "move:m" "c:c" "copy:c" "s:s" "skip:s"; do
    _in=${_pair%%:*}
    _want=${_pair##*:}
    _got=$(sh -c '. "$1" && _opk_ag="$2" && install_agents_form_normalize && printf "%s" "$_opk_ag"' _ "$LIB" "$_in")
    [ "$_got" = "$_want" ] &&
        pass "agents form '$_in' normalizes to '$_want'" ||
        fail "agents form '$_in' normalizes to '$_want' (got '$_got')"
done

# --- 5. the reuse guards (0.0.44a V15) ---------------------------------------------
# Stubbed getent/id keep every arm deterministic on every host (which
# users exist locally must not decide the pin — 0.0.46a F2). Output is
# observed the way a terminal sees it (ui_error -> stderr, merged).
# deviating home -> rc 1, names the shadow-home risk + remediation
# (#407 a P3: no env prefix — the stubs hardcode their answers)
_rc=0
_out=$(sh -c '
    . "$1"
    OPENCODE_USER="octest"
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    log() { :; }
    getent() { [ "$2" = "octest" ] && printf "x:x:1000:1000::/srv/octest:/bin/sh\n"; }
    id() { [ "$1" = "-gn" ] && printf "octest\n"; }
    install_reuse_home_guard
' _ "$LIB" 2>&1) || _rc=$?
if [ "$_rc" -eq 1 ] &&
    printf '%s' "$_out" | grep -q 'shadow home' &&
    printf '%s' "$_out" | grep -q 'Move the user' &&
    ! printf '%s' "$_out" | grep -q 'primary group'; then
    pass "reuse guard: deviating home aborts with remediation (V15)"
else
    fail "reuse guard: deviating home aborts (rc=$_rc out=$_out)"
fi
# matching home -> the HOME guard passes silently (group guard not reached
# in this leg's shell — separate leg below drives it)
_rc=0
_out=$(sh -c '
    . "$1"
    OPENCODE_USER="octest"
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    log() { :; }
    getent() { [ "$2" = "octest" ] && printf "x:x:1000:1000::/home/octest:/bin/sh\n"; }
    install_reuse_home_guard
' _ "$LIB" 2>&1) || _rc=$?
if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    pass "reuse guard: matching home passes silently (V15)"
else
    fail "reuse guard: matching home passes silently (rc=$_rc out=$_out)"
fi
# foreign primary group -> rc 1, names the widened-baseline risk
_rc=0
_out=$(sh -c '
    . "$1"
    OPENCODE_USER="octest"
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    log() { :; }
    id() { [ "$1" = "-gn" ] && printf "users\n"; }
    install_reuse_group_guard
' _ "$LIB" 2>&1) || _rc=$?
if [ "$_rc" -eq 1 ] &&
    printf '%s' "$_out" | grep -q 'foreign primary group' &&
    printf '%s' "$_out" | grep -q 'group of its own name'; then
    pass "reuse guard: foreign primary group aborts with remediation (V15)"
else
    fail "reuse guard: foreign primary group aborts (rc=$_rc out=$_out)"
fi
# own primary group -> rc 0 silent
_rc=0
_out=$(sh -c '
    . "$1"
    OPENCODE_USER="octest"
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    log() { :; }
    id() { [ "$1" = "-gn" ] && printf "octest\n"; }
    install_reuse_group_guard
' _ "$LIB" 2>&1) || _rc=$?
if [ "$_rc" -eq 0 ] && [ -z "$_out" ]; then
    pass "reuse guard: own primary group passes silently (V15)"
else
    fail "reuse guard: own primary group passes silently (rc=$_rc out=$_out)"
fi

# --- 6. install_project_roots_select: EOF bails + resolution ----------------------
# ui_* stubs (the lib never runs without install.sh's ui.sh in
# production; the stubs observe the bail the way a terminal does).
# W14 (outer, 0.0.44a V6): EOF without a terminal — five consecutive
# empty reads abort loudly instead of spinning forever. The hang breaker
# (exit 124 after 9 reads) keeps a reverted guard FAILING with a name
# instead of hanging the suite (0.0.44c C5).
_rc=0
_out=$(sh -c '
    . "$1"
    ui_section() { :; }
    ui_warn() { :; }
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    _ui_read() { _n=$((_n + 1)); [ "$_n" -gt 9 ] && exit 124; eval "$1="; }
    _n=0
    install_project_roots_select
' _ "$LIB" 2>&1) || _rc=$?
if [ "$_rc" -eq 1 ] &&
    printf '%s' "$_out" | grep -q 'no usable input after 5 empty reads'; then
    pass "outer selection aborts on 5 empty reads instead of spinning (V6)"
else
    fail "outer selection EOF bail (rc=$_rc out=$_out)"
fi
# W6 (inner, 0.0.44b W6): the custom sub-loop bails the same way — the
# first read picks [c]ustom, every following read is empty; the custom
# prompt must have appeared (the discriminator: the OUTER loop got its
# non-empty answer, so the bail is the inner one's).
_rc=0
_out=$(sh -c '
    . "$1"
    ui_section() { :; }
    ui_warn() { :; }
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    _ui_read() {
        _n=$((_n + 1))
        [ "$_n" -gt 19 ] && exit 124
        if [ "$_n" -eq 1 ]; then eval "$1=c"; else eval "$1="; fi
    }
    _n=0
    install_project_roots_select
' _ "$LIB" 2>&1) || _rc=$?
if [ "$_rc" -eq 1 ] &&
    printf '%s' "$_out" | grep -q 'Enter paths (space-separated):' &&
    printf '%s' "$_out" | grep -q 'no usable input after 5 empty reads'; then
    pass "custom-path loop aborts on 5 empty reads instead of spinning (W6)"
else
    fail "custom-path EOF bail (rc=$_rc out=$_out)"
fi
# skip resolves: PROJECTS_ROOTS empty-but-set, rc 0. The menu echos ride
# stdout — the ROOTS marker is the LAST line (a bare pipe in an
# assertion, not a gate chain; suites use this shape throughout).
_out=$(sh -c '
    . "$1"
    ui_section() { :; }
    ui_warn() { :; }
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    _ui_read() { eval "$1=s"; }
    install_project_roots_select && printf "ROOTS=[%s]" "${PROJECTS_ROOTS-UNSET}"
' _ "$LIB" 2>&1 | tail -n 1)
if [ "$_out" = "ROOTS=[]" ]; then
    pass "selection 's' skips: empty PROJECTS_ROOTS, rc 0"
else
    fail "selection 's' skips (out=$_out)"
fi
# custom paths ride project_path_sane/_PP_NORM: valid input joins the
# root list via the normalized value (stub = the real contract; the
# first read picks [c]ustom, the second answers the path list). The
# final `  > ` prompt prints no newline — the marker rides its line.
_out=$(sh -c '
    . "$1"
    ui_section() { :; }
    ui_warn() { :; }
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    _ui_read() {
        _n=$((_n + 1))
        if [ "$_n" -eq 1 ]; then eval "$1=c"; else eval "$1=\"/srv/a /srv/b\""; fi
    }
    _n=0
    project_path_sane() { _PP_NORM="$1"; return 0; }
    install_project_roots_select && printf "ROOTS=[%s]" "${PROJECTS_ROOTS-UNSET}"
' _ "$LIB" 2>&1 | tail -n 1) || _rc=$?
case "$_out" in
    *"ROOTS=[ /srv/a /srv/b]")
        pass "custom paths join PROJECTS_ROOTS via _PP_NORM (invalid-free path)"
        ;;
    *)
        fail "custom paths resolution (out=$_out)"
        ;;
esac

# --- 7. order pins that moved with the phases (retargeted from --------------------
#        test-install-args.sh, #346 wave 3)
# --yes takes the documented skip (0.0.44b W14): the SKIP_PROMPTS elif
# sits before the interactive selection call (comment-stripped
# operands, #385 — the pin predates the move and keeps its semantics).
_skip_ln=$(live_src "$LIB" | grep -n 'elif \[ "\$SKIP_PROMPTS" = true \]; then' | head -1 | cut -d: -f1)
_sel_ln=$(live_src "$LIB" | grep -n 'install_project_roots_select$' | tail -1 | cut -d: -f1)
if [ -n "$_skip_ln" ] && [ -n "$_sel_ln" ] && [ "$_skip_ln" -lt "$_sel_ln" ]; then
    pass "--yes skip branch precedes the interactive selection (W14)"
else
    fail "--yes skip branch precedes the interactive selection (skip=$_skip_ln select=$_sel_ln)"
fi
# normalize-agents-forms (0.0.44a V1) runs before the dispatch that
# fires the migration loop — live anchors, not the naming comment (#385
# b b1): the CALL arm vs the dispatch arm.
_norm_ln=$(live_src "$LIB" | grep -n 'install_agents_form_normalize$' | tail -1 | cut -d: -f1)
_disp_ln=$(live_src "$LIB" | grep -n 'm | move | c | copy)' | head -1 | cut -d: -f1)
if [ -n "$_norm_ln" ] && [ -n "$_disp_ln" ] && [ "$_norm_ln" -lt "$_disp_ln" ]; then
    pass "normalization precedes the migration dispatch (V1)"
else
    fail "normalization precedes the migration dispatch (V1) (norm=$_norm_ln disp=$_disp_ln)"
fi
# the distro gate runs before the first interactive menu (0.0.45a order
# pin; comment-stripped operands)
_dg_call_ln=$(live_src "$LIB" | grep -n '^    _distro_gate ' | head -1 | cut -d: -f1)
_dg_menu_ln=$(live_src "$LIB" | grep -n 'ui_menu "How do you want to install?"' | head -1 | cut -d: -f1)
if [ -n "$_dg_call_ln" ] && [ -n "$_dg_menu_ln" ] && [ "$_dg_call_ln" -lt "$_dg_menu_ln" ]; then
    pass "distro gate runs before the first interactive menu (order pin)"
else
    fail "distro gate runs before the first interactive menu (gate=$_dg_call_ln menu=$_dg_menu_ln)"
fi
# Wiring pins (0.0.45a C1 discipline): the verbatim call lines prove the
# phase wires the parsed values/globals into the entry's gate helpers —
# a rewired call neuters the gate while every matrix pin stays green.
# Comment-stripped streams (#407 a P4, the #385 discipline): a
# commented-out call line must not satisfy a presence pin.
if live_src "$LIB" | grep -qF '_distro_gate "${_dg_id:-unknown}" "$_dg_ver"'; then
    pass "do_plan_phase wires the parsed os-release values into the gate (verbatim call pin)"
else
    fail "do_plan_phase wires the parsed os-release values into the gate (verbatim call pin)"
fi
if live_src "$LIB" | grep -qF '_root_user_gate "$DEFAULT_USER"'; then
    pass "do_plan_phase wires DEFAULT_USER into _root_user_gate (verbatim call pin)"
else
    fail "do_plan_phase wires DEFAULT_USER into _root_user_gate (verbatim call pin)"
fi
# root gate after the charset gate, before the distro gate (issue #192:
# a root shell is unrepairable, so it refuses first)
_rug_call_ln=$(live_src "$LIB" | grep -n '^    _root_user_gate ' | head -1 | cut -d: -f1)
_rug_charset_ln=$(live_src "$LIB" | grep -n "Invalid user name" | head -1 | cut -d: -f1)
if [ -n "$_rug_call_ln" ] && [ -n "$_rug_charset_ln" ] && [ -n "$_dg_call_ln" ] &&
    [ "$_rug_charset_ln" -lt "$_rug_call_ln" ] && [ "$_rug_call_ln" -lt "$_dg_call_ln" ]; then
    pass "root gate runs after the charset gate, before the distro gate (order pin)"
else
    fail "root gate order (charset=$_rug_charset_ln gate=$_rug_call_ln distro=$_dg_call_ln)"
fi
# the pre-flight wires the python3 health gate (verbatim call pin,
# #244; the gate function itself stays in install.sh and is matrix-
# pinned in test-install-args.sh). Comment-stripped (#407 a P4).
if live_src "$LIB" | grep -qF '    _py3_health_probe'; then
    pass "pre-flight wires the health gate (verbatim call pin)"
else
    fail "pre-flight wires the health gate (verbatim call pin)"
fi

# --- 8. loud stubs (#250): a truncated lib must abort, never complete green ----------
# install.sh's kit_source dies loud on a missing FILE; the stubs cover a
# present-but-INCOMPLETE copy (partial fetch, mid-deploy). The old
# silent `{ :; }` no-ops let the install complete green with the
# baseline/handover/migration never applied (#250, the update-core #211
# a F2 twins). Executed pins: the exact stub blocks are sed-extracted
# from install.sh and driven in a child — rc 1 + the error line each.
_stb_rc=0
_stb_out="$(
    sed -n '/^command -v fs_baseline_root/,/^}/p' "$INSTALL" >"$WORK/stub-fsb.sh"
    sh -c '. "$1"; fs_baseline_root /nonexistent g u' _ "$WORK/stub-fsb.sh" 2>&1
)" || _stb_rc=$?
if [ "$_stb_rc" -eq 1 ] && printf '%s' "$_stb_out" | grep -qF 'error: fs_baseline_root unavailable'; then
    pass "fs_baseline_root stub: loud, rc 1 — no silent no-op baseline (#250)"
else
    fail "fs_baseline_root stub must abort loud (rc=$_stb_rc out=$_stb_out) (#250)"
fi
_stb_rc=0
_stb_out="$(
    sed -n '/^command -v ddev_handover_root/,/^}/p' "$INSTALL" >"$WORK/stub-ho.sh"
    sh -c '. "$1"; ddev_handover_root /nonexistent o g d' _ "$WORK/stub-ho.sh" 2>&1
)" || _stb_rc=$?
if [ "$_stb_rc" -eq 1 ] && printf '%s' "$_stb_out" | grep -qF 'error: ddev_handover_root unavailable'; then
    pass "ddev_handover_root stub: loud, rc 1 — no silent no-op handover (#250 sweep)"
else
    fail "ddev_handover_root stub must abort loud (rc=$_stb_rc out=$_stb_out) (#250 sweep)"
fi
sed -n '/^command -v ddev_migrate_registry/,/^}/p' "$INSTALL" >"$WORK/stub-mig.sh"
_stb_rc=0
_stb_out="$(sh -c '. "$1"; ddev_migrate_registry /x; ddev_migrate_projects /x /y; ddev_migrate_done u' _ "$WORK/stub-mig.sh" 2>&1)" || _stb_rc=$?
if [ "$_stb_rc" -eq 1 ] &&
    printf '%s' "$_stb_out" | grep -qF 'error: ddev_migrate_registry unavailable' &&
    printf '%s' "$_stb_out" | grep -qF 'error: ddev_migrate_projects unavailable'; then
    pass "ddev_migrate stubs: the actions abort loud; the done probe fails safe rc 1 (#250 sweep)"
else
    fail "ddev_migrate stub contract broken (rc=$_stb_rc out=$_stb_out) (#250 sweep)"
fi
# The two DELIBERATE silent stubs, pinned as such (comment-stripped
# presence, #407 a P4): the stamp writer is a rescan optimization (a
# missing stamp costs the next update a scan, never a skipped action —
# the update-core twin's documented contract), and the done probe's
# rc 1 = "not migrated" keeps the flow on the migration path where the
# loud action stubs catch a truncated lib anyway.
if live_src "$INSTALL" | grep -qF 'ddev_handover_stamp_write() { :; }'; then
    pass "stamp-write stub stays deliberately silent (documented exception)"
else
    fail "stamp-write stub must stay the documented silent exception"
fi
if live_src "$INSTALL" | grep -qF 'ddev_migrate_done() { return 1; }'; then
    pass "done-probe stub stays deliberately fail-safe (documented exception)"
else
    fail "done-probe stub must stay the documented fail-safe exception"
fi

# --- 9. pairing guard (#413): a version-skewed entry/lib pairing dies loud -----------
# kit_source dies loud on a missing FILE; the guard closes the
# missing-FUNCTION twin (a truncated/incompletely-deployed core would
# rc-127 the bare phase calls — a cryptic not-found abort, set -e
# mid-install AFTER earlier phases ran). extract_func pulls the guard
# from the entry; both directions in fresh children. The guard pins
# EVERY function the run needs, phases AND helpers (#452 — a
# helper-level skew aborts mid-install after partial work), plus two
# completeness riders: every phase the entry calls AND every function
# the lib defines. Both riders grep a comment-stripped copy of the
# guard source (#452, conventions.md "Source-counting pins" over
# extracted blocks) and match with BOUNDARY-ANCHORED EREs (plain -qF
# would find phase names as substrings of helper names in the list and
# a dropped name would false-pass).
_pg_src="$(extract_func "$INSTALL" install_pairing_guard)"
_pg_src_s="$(printf '%s\n' "$_pg_src" | sed 's/^[[:space:]]*#.*$//')"
_pg_full=$(sh -c 'eval "$1"; . "$2"; install_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1)
_pg_tr_rc=0
_pg_tr_out="$(sh -c 'eval "$1"; install_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every function defined) (#413)"
else
    fail "pairing guard must pass against the real lib (out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "function 'do_plan_phase' missing from install-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud naming the first missing function (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
if live_src "$INSTALL" | grep -qF 'install_pairing_guard || exit 1'; then
    pass "install.sh wires the guard right after kit_source (#413)"
else
    fail "install.sh must call the guard after sourcing install-core.sh (#413)"
fi
_pg_missing=""
# A2 (#460): the digit class the #457 standard names -- latent today
# (no digit-bearing do_ entry call exists), a future do_2x_sync would
# silently escape the extraction without it.
_pg_entfns="$(grep -oE '^do_[a-z0-9_]+$' "$INSTALL" | sort -u)"
# emptiness probe (#457, the #455 a C2 contract -- the sibling-note
# sweep): an empty extraction would run the loop zero times and the
# rider would pass vacuously.
[ -n "$_pg_entfns" ] || _pg_missing="(entry call extraction empty)"
for _fn in $_pg_entfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "pairing guard list covers every phase the entry calls (#413)"
else
    fail "phases called by install.sh but absent from the guard:$_pg_missing (#413)"
fi
# completeness rider (helper direction, #452): every function the LIB
# defines must sit in the guard's list too — a helper missing from the
# list is the helper-skew hole the guard-list fix closes. Same boundary
# anchor, same stripped source. The extraction carries an emptiness
# probe (#455 a C2): an empty list would run the loop zero times and
# pass vacuously, and the harness contract puts that probe on the
# caller.
_pg_hmissing=""
_pg_libfns="$(grep -oE '^[A-Za-z_][A-Za-z_0-9]*\(\) \{' "$LIB" | sed 's/() {//' | sort -u)"
[ -n "$_pg_libfns" ] || _pg_hmissing="(lib function extraction empty)"
for _fn in $_pg_libfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_hmissing="$_pg_hmissing $_fn"
done
if [ -z "$_pg_hmissing" ]; then
    pass "pairing guard list covers every function the lib defines (#452)"
else
    fail "functions defined by install-core.sh but absent from the guard:$_pg_hmissing (#452, #455 a C2)"
fi

# --- 9b. cross-lib stub rider (#456): core-called lib functions stay stubbed ------
# The #250 stub sweep covered the functions the ENTRY calls from the
# kit_source'd libs; #456 closes the twin it missed: functions the CORE
# calls from those same libs (agent_home_sane was the live example — 13
# gated call sites, no stub: a truncated staged-write.sh would have
# rc-127'd the ddev phase under set -e). STRONGEST form — every
# function defined by ANY sh/ file (the glob carries the phase cores
# too; ui.sh exempt: its surface is the used-set guard's, own rider in
# test-ui.sh) and CALLED by entry or core (word-boundary, not the
# definition paren) must be DEFINED somewhere in the sourced run —
# entry stub arm, fallback, or install-core's own definitions (it is
# kit_source'd before main, so a definition there covers at runtime) —
# so a present-but-truncated lib can never rc-127 a bare call, and a
# call into a lib nothing sources fails the same way. Comment-stripped
# both sides (conventions.md "Source-counting pins"); stub-only names
# (defined, never called) are out of scope — staleness, not a gap.
# The extraction keeps tokens line-separated: a tr -d '[:space:]()'
# here concatenates every definition into one token and the loop goes
# vacuous (found by the #456 sabotage cycle, L4). The lib list is what
# THIS RUN sources — live from the kit_source lines plus log.sh's
# direct sourcing — not the whole sh/ glob: sh/ also carries
# wrapper-side scripts (ddev-terminal.sh, as-opencode-core.sh) whose
# shell-hook definitions (ddev(), note()) are not install's callable
# surface, and globbing them false-reds on binary-name prose.
_xl_missing=""
_xl_combined="$(
    live_src "$INSTALL"
    live_src "$LIB"
)"
[ -n "$_xl_combined" ] || _xl_missing="(stripped entry+core extraction empty)"
_xl_libs="$(
    grep -oE 'kit_source "\$SCRIPT_DIR/opencode-permissions-kit-lib/sh/[a-z0-9-]+\.sh"' "$INSTALL" |
        sed -e 's/^kit_source "\$SCRIPT_DIR\///' -e 's/"$//'
    echo opencode-permissions-kit-lib/sh/log.sh
)"
for _xl_rel in $_xl_libs; do
    _xl_lib="$SCRIPT_DIR/../../files/$_xl_rel"
    case $_xl_lib in */ui.sh) continue ;; esac
    [ -f "$_xl_lib" ] || {
        _xl_missing="$_xl_missing (missing lib $_xl_rel)"
        continue
    }
    for _xl_fn in $(grep -oE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$_xl_lib" | tr -d '()'); do
        printf '%s\n' "$_xl_combined" | grep -qE "(^|[^a-zA-Z0-9_])${_xl_fn}([^a-zA-Z0-9_(]|$)" ||
            continue
        printf '%s\n' "$_xl_combined" | grep -qE "(^|[|;[:space:]])${_xl_fn}\(\)" ||
            _xl_missing="$_xl_missing $_xl_fn"
    done
done
if [ -z "$_xl_missing" ]; then
    pass "every lib function entry-or-core calls is defined in install.sh/install-core.sh (#456)"
else
    fail "lib functions called but defined nowhere in install.sh/install-core.sh:$_xl_missing (#456)"
fi
# Nesting-shape pin (#461 a Q4): the ddev_migrate_gap/_export stubs
# must be TOP-LEVEL arms — anchored at column 0. The wave's first cut
# nested them inside the registry arm, where they armed only when the
# registry was undefined (ddev-migrate.sh defines registry at :82, gap
# at :154, export at :351 — every truncation after :82 left them
# unarmed and the tolerant call arms turned the miss into a silent
# green skip). An indented, nested copy fails this anchor.
if live_src "$INSTALL" | grep -qE '^command -v ddev_migrate_gap >/dev/null 2>&1 \|\| ddev_migrate_gap\(\) \{' &&
    live_src "$INSTALL" | grep -qE '^command -v ddev_migrate_export >/dev/null 2>&1 \|\| ddev_migrate_export\(\) \{'; then
    pass "ddev_migrate gap/export stubs are top-level arms (arm independently of the registry) (#461 a Q4)"
else
    fail "ddev_migrate gap/export stubs must be top-level command -v arms (#461 a Q4)"
fi
# B1 pin (#461 b): the INTRA-LIB CALLEE rides its own top-level arm.
# gap (:157) and export (:389) call ddev_migrate_latest_dir (def :651)
# inside $(…); a tail cut in the :158–:650 window keeps both callers
# (the stub arms above only fire on entirely-missing functions) and
# kills the callee — the tolerant call arms swallowed the rc behind
# the shell's bare "not found" with no counted row. The callee stub
# makes that window name itself; anchored at column 0 like Q4's.
if live_src "$INSTALL" |
    grep -qE '^command -v ddev_migrate_latest_dir >/dev/null 2>&1 \|\| ddev_migrate_latest_dir\(\) \{' &&
    live_src "$INSTALL" | grep -A2 -F 'ddev_migrate_latest_dir() {' |
    grep -qF 'skipping the ddev migration check'; then
    pass "ddev_migrate_latest_dir stub is a top-level arm naming the skip (B1: the intra-lib callee window) (#461 b B1)"
else
    fail "ddev_migrate_latest_dir must be a top-level command -v arm with the named skip (#461 b B1)"
fi
# X1 pin: the link-gate stub fails CLOSED and loud — the rc-0 draft left
# the direct-sudo gated writes (~/.ddev, ~/.config, ~/.agents) running
# with the gate silently off on truncation. Shape pin (inline arm, not
# extractable): fail-closed rc + named message.
if live_src "$INSTALL" | grep -A2 -F 'agent_home_sane() {' |
    grep -qF 'link gate closed, gated writes skip loudly' &&
    live_src "$INSTALL" | grep -A2 -F 'agent_home_sane() {' |
    grep -qF 'return 1'; then
    pass "agent_home_sane stub fails closed and loud (X1: direct-sudo gates never run ungated) (#461 a X1)"
else
    fail "agent_home_sane stub must fail closed (rc 1 + named message) (#461 a X1)"
fi

# --- 8. LOWS-1 (#371/#372/#340): install.sh residual hygiene ----------------------

# A1 + review a S1/P4 (#424 a): the agent-user gitconfig backup is
# gated on the gitconfig FILES (both of git's global-scope locations),
# not the user alone — `sudo -u` on a missing user fails unconditionally
# (fresh install), and `git config --global --list` fails rc 128 when
# the user exists without a global config (re-install residue). The
# skip arm's log names what was checked.
_ocbk_ln=$(live_src "$LIB" |
    grep -nF 'BACKUP_DIR/gitconfig-$OPENCODE_USER.txt' | head -1 | cut -d: -f1)
if [ -n "$_ocbk_ln" ] &&
    live_src "$LIB" | grep -qF 'backup skipped: no global gitconfig' &&
    live_src "$LIB" |
    grep -qF '[ -f "$_oc_gcfg_home/.gitconfig" ] || [ -f "$_oc_gcfg_home/.config/git/config" ]' &&
    sed -n "$((_ocbk_ln - 12)),$((_ocbk_ln - 1))p" "$LIB" |
    grep -qF '_oc_gcfg_home="$(getent passwd "$OPENCODE_USER"'; then
    pass "gitconfig backup gated on the global gitconfig files + skip arm (#371 A1 + #424 a S1/P4)"
else
    fail "gitconfig backup gate missing or user-only (#371 A1 + #424 a S1/P4)"
fi

# A2: custom-path input rejects glob characters on the RAW input before
# the unquoted for-loop can pathname-expand them (the --projects
# sibling's 0.0.42f S2 rule). Behavioral: read 1 picks [c]ustom, read 2
# carries a glob word, read 3 answers clean — the glob word must be
# refused AND must not leak into PROJECTS_ROOTS (without the gate the
# literal word rides the stub gate straight into the list).
_out=$(sh -c '
    . "$1"
    ui_section() { :; }
    ui_warn() { :; }
    ui_error() { printf "ui_error: %s\n" "$*" >&2; }
    _ui_read() {
        _n=$((_n + 1))
        if [ "$_n" -eq 1 ]; then eval "$1=c"
        elif [ "$_n" -eq 2 ]; then eval "$1=\"/srv/x[ab] /srv/ok\""
        else eval "$1=/srv/ok"; fi
    }
    _n=0
    project_path_sane() { _PP_NORM="$1"; return 0; }
    install_project_roots_select && printf "ROOTS=[%s]" "${PROJECTS_ROOTS-UNSET}"
' _ "$LIB" 2>&1)
case "$_out" in
    *"glob characters"*)
        case "$_out" in
            *"ROOTS=[ /srv/ok]"*) pass "custom-path glob input rejected, never joins roots (#372 A2)" ;;
            *) fail "glob gate ran but the word leaked into roots (#372 A2 out=$_out)" ;;
        esac
        ;;
    *)
        fail "custom-path glob input not rejected (#372 A2 out=$_out)"
        ;;
esac

# A5: every copy_binary_atomic call site names its cause on failure
# (four sites — the count is pinned at four in test-bypass-guard.sh).
_cba_err_n="$(live_src "$LIB" | grep -cF 'error: copying the opencode binary' || true)"
[ "$_cba_err_n" = 4 ] &&
    pass "all four binary-copy failures abort cause-loud (#371 A5)" ||
    fail "binary-copy failure arms incomplete (#371 A5; sites: $_cba_err_n of 4)"

# A6+I2+H2: the "registered (both users)" success line is conditional
# on both per-user syncs having succeeded — rc 2/3 skips print their
# own notes and no longer ride a success row. #424 a P3: the counter
# INCREMENT is pinned too — losing it (back to the old `:` no-op)
# would silence the closing row on the both-succeeded path while every
# conditional literal survives.
if live_src "$LIB" | grep -qF 'if [ "$_oc_tps_ok" -eq 2 ]; then' &&
    live_src "$LIB" | grep -qF 'elif [ "$_oc_tps_ok" -eq 1 ]; then' &&
    live_src "$LIB" |
    grep -qF '_oc_tps_ok=$((_oc_tps_ok + 1))'; then
    pass "TUI 2.x closing row conditional + counter increment (#371 A6 + #424 a P3)"
else
    fail "TUI 2.x closing row incomplete (#371 A6 + #424 a P3)"
fi

# A7+I3: the rc cleanup deletes only PATH EXPORT lines naming
# .opencode/bin (the old sed matched ANY line containing it — aliases,
# comments), backs the rc file up first, observes a failed cleanup, and
# the audit log names the cleaned count instead of claiming blindly.
if live_src "$LIB" |
    grep -qF '\|^[[:space:]]*export PATH=.*[.]opencode/bin|d' &&
    ! grep -qF 'sed -i '\''\|\.opencode/bin|d'\''' "$LIB" &&
    live_src "$LIB" |
    grep -qF '_bk_fail "rc-$(basename "$cf")"' &&
    live_src "$LIB" |
    grep -qF 'could not remove a stale .opencode/bin PATH export from $cf' &&
    live_src "$LIB" |
    grep -qF 'stale PATH exports cleaned in $_rc_cleaned rc file(s)'; then
    pass "rc cleanup anchored + backed up + observed + honest claim (#371 A7/I3)"
else
    fail "rc cleanup hygiene incomplete (#371 A7/I3)"
fi

# A4R: _oc_install_agent_config propagates staged_write's rc past the
# trailing rm (the latent trap for a future tested-context caller).
if live_src "$LIB" | grep -qF '_oic_rc=$?' &&
    live_src "$LIB" | grep -qF 'return "$_oic_rc"'; then
    pass "agent-config install propagates staged_write rc (#371 A4R)"
else
    fail "agent-config rc still masked by trailing rm (#371 A4R)"
fi

# A8: the truncated backend-selection comment line is gone.
if ! grep -qF 'Rootless is MANDATORY: docker-rootless' "$LIB"; then
    pass "backend-selection comment residue removed (#371 A8)"
else
    fail "backend-selection comment residue still present (#371 A8)"
fi

# I4: /usr/local/bin/opencode is excluded as a pickup source only in
# its wrapper-SYMLINK form — both loops (inventory + deploy pickup).
_i4_n="$(live_src "$LIB" |
    grep -cF '[ "$loc" != "/usr/local/bin/opencode" ] || [ ! -L "$loc" ]' || true)"
[ "$_i4_n" = 2 ] &&
    pass "binary pickup excludes /usr/local/bin/opencode only as a symlink (#372 I4)" ||
    fail "binary pickup name-exclusion not symlink-aware at both sites (#372 I4; sites: $_i4_n of 2)"

# I6 (#372 + #424 a P2): the template carries the ANCHORED kit marker;
# the replace heuristic requires marker OR permission block with the
# negation in front of the grep (a polarity flip `! grep` -> `grep`
# inverts the arm — the pin pins the negated SHAPE), and the keep arm
# sits BEFORE the re-render else (an elif reorder would bury it).
TEMPLATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/templates/opencode.jsonc"
RENDER_LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/render-agent-config.sh"
_i6_keep_ln=$(live_src "$LIB" | grep -nF 'existing opencode.jsonc has no kit marker' |
    head -1 | cut -d: -f1)
_i6_reap_ln=$(live_src "$LIB" | grep -nF 'agent config re-applied' |
    head -1 | cut -d: -f1)
# Leg 1 pins the NEGATED shape (a polarity flip drops the `! `); leg 2
# pins the ANCHORED marker form (the unanchored substring regression of
# review a S6 loses the `//` comment-form prefix). The two $LIB legs
# carry comment-strip riders (#458, conventions.md "Source-counting
# pins"): a commented-out heuristic line must not count.
if grep -qF '// _opencode_permissions_kit — kit-managed config' "$TEMPLATE" &&
    live_src "$LIB" | grep -qF '! grep -qE ' &&
    live_src "$LIB" |
    grep -qF '//[[:space:]]*_opencode_permissions_kit|"permission' &&
    live_src "$LIB" |
    grep -qF 'user-authored or broken/unreadable content' &&
    [ -n "$_i6_keep_ln" ] && [ -n "$_i6_reap_ln" ] &&
    [ "$_i6_keep_ln" -lt "$_i6_reap_ln" ]; then
    pass "agent config: anchored marker + negated keep heuristic + arm order (#372 I6 + #424 a P2)"
else
    fail "agent config marker/heuristic pin incomplete (#372 I6 + #424 a P2)"
fi
# the marker survives both render modes (the real render lib, driven)
if . "$RENDER_LIB" &&
    agent_config_render "$TEMPLATE" "$WORK/render-on.jsonc" on 2>/dev/null &&
    agent_config_render "$TEMPLATE" "$WORK/render-off.jsonc" off 2>/dev/null &&
    grep -qF '_opencode_permissions_kit' "$WORK/render-on.jsonc" &&
    grep -qF '_opencode_permissions_kit' "$WORK/render-off.jsonc"; then
    pass "kit marker survives both render modes (#372 I6)"
else
    fail "kit marker lost in a render mode (#372 I6)"
fi

# #340: the tilde-home setup is ONE call into sh/path-sane.sh, no
# inline copy left in the phase lib.
if live_src "$LIB" | grep -qxE '^[[:space:]]*path_sane_tilde_home$' &&
    ! grep -qE '^[[:space:]]*PROJECT_TILDE_HOME="\$HOME"$' "$LIB"; then
    pass "tilde-home setup delegated to path-sane.sh, no inline copy (#340)"
else
    fail "tilde-home setup not consolidated (#340)"
fi

# --- #377 O2: agent-resources migration re-checks the operand at exec time
# The entry gate classifies the destination chain ONCE; every operand is
# agent-replaceable (/home/opencode belongs to the agent), so a leaf
# swapped for a dir-symlink in the gate→op window would make the cp -a
# write developer content THROUGH the link (live-verified, review #370
# a O2). The exec-time recheck (the L5 rule, #267 shape) must trip
# between mkdir and cp. Executed: the function is sed-extracted from
# install-core.sh and run with stubbed sudo (no real /home writes —
# sandbox policy) and a pass-once agent_home_sane that flips to refusal
# on its second walk.
_MIG_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh"
_O372W="$(work_new)"
mkdir -p "$_O372W/dev/.agents/skill-a"
printf 'skill body\n' >"$_O372W/dev/.agents/skill-a/SKILL.md"
sed -n '/^[[:space:]]*_opk_migrate_one() {/,/^[[:space:]]*}$/p' "$_MIG_CORE" |
    sed 's/^[[:space:]]*//' >"$_O372W/migrate-one.sh"
if [ -s "$_O372W/migrate-one.sh" ]; then
    pass "migration helper extracted (#377 O2)"
else
    fail "migration helper extraction failed (#377 O2)"
fi
_O372_OUT=$(
    DEV_HOME="$_O372W/dev" OPENCODE_USER=oc _opk_ag=c sh -c '
        . "$1"
        _ahs_calls=0
        agent_home_sane() {
            _ahs_calls=$((_ahs_calls + 1))
            # first walk = entry gate (pass), second = exec-time recheck
            [ "$_ahs_calls" -ge 2 ] && return 1
            return 0
        }
        sudo() { echo "SUDO: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_success() { echo "success: $*"; }
        ui_info() { :; }
        ui_detail() { :; }
        log() { echo "log: $*"; }
        _opk_migrate_one .agents
    ' _ "$_O372W/migrate-one.sh" 2>&1
)
if printf '%s\n' "$_O372_OUT" | grep -qF 'SUDO: mkdir -p /home/oc/.agents' &&
    ! printf '%s\n' "$_O372_OUT" | grep -q 'SUDO: cp -a' &&
    printf '%s\n' "$_O372_OUT" | grep -qF 'warn: agent resources not migrated: the chain to /home/oc/.agents turned into a symlink' &&
    printf '%s\n' "$_O372_OUT" | grep -qF 'or the home-sane gate was unavailable' &&
    printf '%s\n' "$_O372_OUT" | grep -qF 'log: agents migration skipped: exec-time recheck tripped for /home/oc/.agents' &&
    [ -f "$_O372W/dev/.agents/skill-a/SKILL.md" ]; then
    pass "exec-time recheck trips between mkdir and cp: no copy, loud skip, source untouched (#377 O2, #461 b B3)"
else
    fail "exec-time recheck must skip the copy loudly (out=$_O372_OUT) (#377 O2, #461 b B3)"
fi
# Control arm: a gate that never trips runs the copy (the recheck must
# not break the happy path) — agent_home_sane passes every walk.
_O372C_OUT=$(
    DEV_HOME="$_O372W/dev" OPENCODE_USER=oc _opk_ag=c sh -c '
        . "$1"
        agent_home_sane() { return 0; }
        sudo() { echo "SUDO: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_success() { echo "success: $*"; }
        ui_info() { :; }
        ui_detail() { :; }
        log() { echo "log: $*"; }
        _opk_migrate_one .agents
    ' _ "$_O372W/migrate-one.sh" 2>&1
)
if printf '%s\n' "$_O372C_OUT" | grep -qF 'SUDO: cp -a' &&
    printf '%s\n' "$_O372C_OUT" | grep -qF 'success: agent resources COPIED: '; then
    pass "control arm: recheck silent on the happy path, copy runs (#377 O2)"
else
    fail "happy path broken by the recheck (out=$_O372C_OUT) (#377 O2)"
fi
# pr-00429 a C2: the SECOND exec-time recheck (after the copy, before
# the baseline legs) must trip on a swapped leaf — the chmod/chown legs
# dereference their operands (chmod has no -P, measured), so a trip
# must skip them loudly. Three walks: entry gate passes, pre-copy
# recheck passes, post-copy recheck trips.
_O372C2_OUT=$(
    DEV_HOME="$_O372W/dev" OPENCODE_USER=oc _opk_ag=c sh -c '
        . "$1"
        _ahs_calls=0
        agent_home_sane() {
            _ahs_calls=$((_ahs_calls + 1))
            [ "$_ahs_calls" -ge 3 ] && return 1
            return 0
        }
        sudo() { echo "SUDO: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_success() { echo "success: $*"; }
        ui_info() { :; }
        ui_detail() { :; }
        log() { echo "log: $*"; }
        _opk_migrate_one .agents
    ' _ "$_O372W/migrate-one.sh" 2>&1
)
if printf '%s\n' "$_O372C2_OUT" | grep -qF 'SUDO: cp -a' &&
    ! printf '%s\n' "$_O372C2_OUT" | grep -qE 'SUDO: (find|chown -R|chmod)' &&
    printf '%s\n' "$_O372C2_OUT" | grep -qF 'warn: agent resources copied but the sharing baseline was NOT applied:' &&
    ! printf '%s\n' "$_O372C2_OUT" | grep -qF 'success: agent resources COPIED'; then
    pass "second recheck trips before the baseline legs: no chmod/chown operand touched (pr-00429 a C2)"
else
    fail "post-copy recheck must skip the baseline legs loudly (out=$_O372C2_OUT) (pr-00429 a C2)"
fi
# pr-00429 b D1: move mode — the source removal waits for the pass arm.
# A tripped post-copy recheck keeps the dev's original (the recovery the
# remedy names); a clean run removes it only after copy AND baseline.
_O372D1_OUT=$(
    DEV_HOME="$_O372W/dev" OPENCODE_USER=oc _opk_ag=m sh -c '
        . "$1"
        _ahs_calls=0
        agent_home_sane() {
            _ahs_calls=$((_ahs_calls + 1))
            [ "$_ahs_calls" -ge 3 ] && return 1
            return 0
        }
        sudo() { echo "SUDO: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_success() { echo "success: $*"; }
        ui_info() { :; }
        ui_detail() { :; }
        log() { echo "log: $*"; }
        _opk_migrate_one .agents
    ' _ "$_O372W/migrate-one.sh" 2>&1
)
if ! printf '%s\n' "$_O372D1_OUT" | grep -q 'SUDO: rm -rf' &&
    printf '%s\n' "$_O372D1_OUT" | grep -qF 'SUDO: cp -a' &&
    printf '%s\n' "$_O372D1_OUT" | grep -qF 'warn: the original at' &&
    printf '%s\n' "$_O372D1_OUT" | grep -qF 'is untouched — re-run the install to normalize' &&
    [ -f "$_O372W/dev/.agents/skill-a/SKILL.md" ]; then
    pass "move mode + tripped recheck: source kept as recovery, remedy names it (pr-00429 b D1)"
else
    fail "move mode must keep the source when the post-copy recheck trips (out=$_O372D1_OUT) (pr-00429 b D1)"
fi
_O372D1C_OUT=$(
    DEV_HOME="$_O372W/dev" OPENCODE_USER=oc _opk_ag=m sh -c '
        . "$1"
        agent_home_sane() { return 0; }
        sudo() { echo "SUDO: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_success() { echo "success: $*"; }
        ui_info() { :; }
        ui_detail() { :; }
        log() { echo "log: $*"; }
        _opk_migrate_one .agents
    ' _ "$_O372W/migrate-one.sh" 2>&1
)
if printf '%s\n' "$_O372D1C_OUT" | grep -qF 'SUDO: rm -rf' &&
    printf '%s\n' "$_O372D1C_OUT" | grep -qF 'SUDO: find' &&
    printf '%s\n' "$_O372D1C_OUT" | grep -qF 'success: agent resources MOVED:'; then
    pass "move-mode control: source removed after copy AND baseline (pr-00429 b D1)"
else
    fail "move-mode happy path must still remove the source (out=$_O372D1C_OUT) (pr-00429 b D1)"
fi
# pr-00429 a C3: the Step 8 blocks (.config, .config/opencode, .agents)
# carry the same exec-time recheck — one entry gate + one re-walk per
# block before the chown -R/chmod legs. Count on comment-stripped
# source between the Step 8 and Step 8a markers: 3 entry gates + 3
# rechecks = 6 agent_home_sane calls (the migration helper has its own
# two, outside this range).
_O372C3_N=$(sed -n '/=== Step 8: opencode Home ===/,/=== Step 8a:/p' "$_MIG_CORE" |
    sed 's/^[[:space:]]*#.*$//' | grep -c 'agent_home_sane' || true)
if [ "$_O372C3_N" -eq 6 ]; then
    pass "Step 8 blocks: 3 entry gates + 3 exec-time rechecks (pr-00429 a C3)"
else
    fail "Step 8 blocks must carry 6 agent_home_sane calls, got $_O372C3_N (pr-00429 a C3)"
fi

# --- #257: install gates the xdg shim on the deployed binary's version ------------
# Execution against /usr/local/bin literals is not hermetic (sandbox
# policy) — the gate LOGIC is execution-pinned in test-deploy-lib.sh,
# the deployed behavior in e2e (2b). Here: the block consults the gate
# BEFORE the never-shadow deploy arm and logs the withhold cause.
if live_src "$LIB" | grep -qF 'if ! xdg_shim_needed_for "${_xdi_maj:-}" "$_xdi_trip"; then' &&
    live_src "$LIB" | grep -qF 'xdg-open shim skipped: opencode' &&
    live_src "$LIB" | grep -qF 'elif ! command -v xdg-open >/dev/null 2>&1 &&'; then
    pass "install xdg block: version gate before the never-shadow arm (#257)"
else
    fail "install must gate the shim deploy on xdg_shim_needed_for (#257)"
fi

# --- LOWS-6 (#428 disposition): the re-configure ask stays default-y -------------
# The PR-#426 decline rationale, pinned so an accidental flip to n
# reddens: install.sh reaching this gate is an explicit invocation
# whose yes is the purpose; the prompt is INTERACTIVE-gated (the
# curl|bash path never sees it), the re-configure keeps user config,
# and "no" just points at opk update and exits 0 — the conventions'
# carve-out (agent/conventions.md "Interactive prompts"). Comment-
# stripped grep for the default itself; the rationale comment must
# exist at the site too.
# The '#428 disposition' grep below is deliberately UN-RIDDEN (#458,
# conventions.md "Source-counting pins"): it pins a COMMENT literal --
# the full-line strip rider would delete the very bytes the pin
# requires and make it unmatchable. The strip rider class protects
# against commented-out code still counting; here the comment IS the
# pinned construct, so the discrimination is inverted by design.
if live_src "$LIB" |
    grep -qF '"Re-configure the existing installation with install.sh?" "y"' &&
    grep -qF '#428 disposition' "$LIB"; then
    pass "re-configure ask stays default-y, disposition documented (#428)"
else
    fail "re-configure ask default flipped or undocumented (#428)"
fi

# --- #482 F17: install-side openchamber pin is atomic stage+mv ---------------------
# Mechanism pin (the #211 a F17 update-twin pin's shape, issue #482):
# recording stubs prove the content lands on a pid-suffixed temp, the
# temp is registered with the cleanup trap BEFORE staging (an abort
# during the tee strands nothing), and the live file flips via mv only
# — no write may target the final path directly.
_f17i_block="$(sed -n '/#482 F17, install twin of #211 a F17/,/sudo mv -f/p' "$LIB")"
if [ -n "$_f17i_block" ]; then
    pass "openchamber install block extractable (#482 F17)"
    _f17i_out=$(
        sh -c '
            _tmp_track() { echo "TRACK $1" >&2; }
            sudo() {
                case "$1" in
                    mkdir | chown | chmod) return 0 ;;
                    tee) shift; printf "TEE %s\n" "$1" >&2 ;;
                    mv) shift; case "$1" in -*) shift ;; esac
                        printf "MV %s -> %s\n" "$1" "$2" ;;
                esac
            }
            eval "$1"
        ' sh "$_f17i_block" 2>&1
    ) || true
    if printf '%s' "$_f17i_out" | grep -q 'TEE /etc/openchamber/policy.json.opk-new\.' &&
        printf '%s' "$_f17i_out" | grep -q 'MV /etc/openchamber/policy.json.opk-new\.[0-9]* -> /etc/openchamber/policy.json' &&
        ! printf '%s' "$_f17i_out" | grep -q 'TEE /etc/openchamber/policy.json$'; then
        pass "install.sh: content staged on temp, live file flips via mv (#482 F17)"
    else
        fail "install.sh: staged write + mv (out=$_f17i_out) (#482 F17)"
    fi
    _f17i_trk=$(printf '%s\n' "$_f17i_out" | grep -n 'TRACK /etc/openchamber/policy.json.opk-new\.' | cut -d: -f1)
    _f17i_tee=$(printf '%s\n' "$_f17i_out" | grep -n 'TEE /etc/openchamber/policy.json.opk-new\.' | cut -d: -f1)
    if [ -n "$_f17i_trk" ] && [ -n "$_f17i_tee" ] && [ "$_f17i_trk" -lt "$_f17i_tee" ]; then
        pass "install.sh: temp registered with the trap BEFORE staging (#482 F17, #211 c W3 order)"
    else
        fail "install.sh: temp registration before staging (trk=${_f17i_trk:-none} tee=${_f17i_tee:-none}) (#482 F17)"
    fi
    # The chown || true is the block's one fail-soft leg (the update
    # twin's shape — the tee already created the file root-owned, the
    # chown is belt): L1 — the failure path EXECUTED, the flip must
    # still happen.
    _f17i_out2=$(
        sh -c '
            _tmp_track() { echo "TRACK $1" >&2; }
            sudo() {
                case "$1" in
                    mkdir | chmod) return 0 ;;
                    chown) return 1 ;;
                    tee) shift; printf "TEE %s\n" "$1" >&2 ;;
                    mv) shift; case "$1" in -*) shift ;; esac
                        printf "MV %s -> %s\n" "$1" "$2" ;;
                esac
            }
            eval "$1"
        ' sh "$_f17i_block" 2>&1
    ) || true
    if printf '%s' "$_f17i_out2" | grep -q 'MV /etc/openchamber/policy.json.opk-new\.[0-9]* -> /etc/openchamber/policy.json'; then
        pass "install.sh: chown failure does not block the flip (#482 F17 fail-soft arm)"
    else
        fail "install.sh: chown fail-soft arm must still flip (out=$_f17i_out2) (#482 F17)"
    fi
else
    fail "openchamber install block extractable (#482 F17)"
fi

# --- #482 F44: install_deploy_library restores the pre-install tree ----------------
# The #376 B5 update-twin pin's shape (test-update-core.sh §18):
# lib_deploy stubbed to rc 1 after half-planting a new file (the mixed
# old/new state of the finding); real cp/mv on scratch. The helper must
# back the existing tree up, move the mixed tree aside, restore the
# pre-install copy and abort loud.
_F44W="$(work_new)"
mkdir -p "$_F44W/ldir" "$_F44W/backups/install-test"
printf 'old-lib\n' >"$_F44W/ldir/marker-old.txt"
_f44_out=$(
    sh -c '
        SCRIPT_DIR="$1/froot"
        LIBDIR="$1/ldir"
        BACKUP_DIR="$1/backups/install-test"
        log() { echo "log: $*"; }
        ui_section() { :; }
        ui_success() { echo "success: $*"; }
        ui_detail() { echo "detail: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_error() { echo "error: $*"; }
        lib_deploy() { echo "new-lib" >"$LIBDIR/planted-new.txt"; return 1; }
        . "$2"
        install_deploy_library
        echo "BAD: rc 0"
    ' _ "$_F44W" "$LIB" 2>&1
) || true
if printf '%s\n' "$_f44_out" | grep -qF 'warn: library deploy FAILED — previous library tree restored' &&
    printf '%s\n' "$_f44_out" | grep -qF 'error: library deploy failed — install aborted' &&
    ! printf '%s\n' "$_f44_out" | grep -q 'BAD: rc 0' &&
    [ -f "$_F44W/ldir/marker-old.txt" ] &&
    [ ! -f "$_F44W/ldir/planted-new.txt" ] &&
    [ -f "$_F44W/backups/install-test/lib/marker-old.txt" ] &&
    [ -f "$(find "$_F44W/backups/install-test" -maxdepth 1 -name 'lib-failed.*' -type d 2>/dev/null | head -1)/planted-new.txt" ]; then
    pass "failed lib_deploy: mixed tree moved aside, pre-install tree restored (#482 F44)"
else
    fail "failed lib_deploy must restore the pre-install tree (out=$_f44_out) (#482 F44)"
fi
# Fail-closed backup gate (the update twin's pre-deploy doctrine): a
# backup that cannot be produced aborts BEFORE anything is touched —
# cp fails on an unwritable backup dir, lib_deploy must never run (the
# marker stub proves the ordering), the live tree stays as-is.
mkdir -p "$_F44W/ldir2" "$_F44W/nobackup/install"
printf 'old-lib-2\n' >"$_F44W/ldir2/marker-old.txt"
chmod 500 "$_F44W/nobackup/install"
_f44g_rc=0
_f44g_out=$(
    sh -c '
        SCRIPT_DIR="$1/froot"
        LIBDIR="$1/ldir2"
        BACKUP_DIR="$1/nobackup/install"
        log() { :; }
        ui_section() { :; }
        ui_success() { :; }
        ui_detail() { :; }
        ui_warn() { echo "warn: $*"; }
        ui_error() { echo "error: $*"; }
        lib_deploy() { echo "DEPLOY-RAN"; return 0; }
        . "$2"
        install_deploy_library
    ' _ "$_F44W" "$LIB" 2>&1
) || _f44g_rc=$?
chmod 700 "$_F44W/nobackup/install"
if [ "$_f44g_rc" -ne 0 ] &&
    printf '%s\n' "$_f44g_out" | grep -qF 'error: cannot back up the existing library tree' &&
    ! printf '%s\n' "$_f44g_out" | grep -q 'DEPLOY-RAN' &&
    [ -f "$_F44W/ldir2/marker-old.txt" ]; then
    pass "unbackable tree: aborts before the deploy, live tree untouched (#482 F44)"
else
    fail "backup gate must abort before deploying (rc=$_f44g_rc out=$_f44g_out) (#482 F44)"
fi
# Incomplete-restore arm (L1 — the new `mv … 2>/dev/null` failure path
# EXECUTED): the backup cp succeeds, the restore cp fails — the run must
# abort loud with the manual-recovery hint, not paper over a half
# restore with success rows. Counting cp stub: call 1 (backup) real,
# call 2 (restore) fails.
mkdir -p "$_F44W/ldir3" "$_F44W/backups3"
printf 'old-lib-3\n' >"$_F44W/ldir3/marker-old.txt"
_f44r_rc=0
_f44r_out=$(
    sh -c '
        SCRIPT_DIR="$1/froot"
        LIBDIR="$1/ldir3"
        BACKUP_DIR="$1/backups3"
        _cpn=0
        cp() {
            _cpn=$((_cpn + 1))
            [ "$_cpn" -ge 2 ] && return 1
            command cp "$@"
        }
        log() { echo "log: $*"; }
        ui_section() { :; }
        ui_success() { echo "success: $*"; }
        ui_detail() { echo "detail: $*"; }
        ui_warn() { echo "warn: $*"; }
        ui_error() { echo "error: $*"; }
        lib_deploy() { echo "new-lib" >"$LIBDIR/planted-new.txt"; return 1; }
        . "$2"
        install_deploy_library
    ' _ "$_F44W" "$LIB" 2>&1
) || _f44r_rc=$?
if [ "$_f44r_rc" -ne 0 ] &&
    printf '%s\n' "$_f44r_out" | grep -qF 'warn: library deploy FAILED and the automatic restore did not complete' &&
    printf '%s\n' "$_f44r_out" | grep -qF 'recoverable at' &&
    printf '%s\n' "$_f44r_out" | grep -qF 'error: library deploy failed — install aborted' &&
    [ -f "$_F44W/backups3/lib/marker-old.txt" ]; then
    pass "restore failure: aborts loud, keeps the recovery material + manual hint (#482 F44)"
else
    fail "restore failure must abort loud with the manual hint (rc=$_f44r_rc out=$_f44r_out) (#482 F44)"
fi
# Fresh-install arm (#482 F44; real drive per #497 a Q5 — the other
# three arms got drives, this one was presence-only): NO previous tree
# — lib_deploy failure aborts loud with the re-run hint, the partial
# new tree KEEPS its planted entry (inert; the symlink phase never
# ran), and no backup material is created (the gate short-circuits).
mkdir -p "$_F44W/freshroot"
_f44f_rc=0
_f44f_out=$(
    sh -c '
        SCRIPT_DIR="$1/froot"
        LIBDIR="$1/freshroot/lib"
        BACKUP_DIR="$1/backups-fresh"
        log() { echo "log: $*"; }
        ui_section() { :; }
        ui_success() { :; }
        ui_detail() { :; }
        ui_warn() { echo "warn: $*"; }
        ui_error() { echo "error: $*"; }
        lib_deploy() {
            mkdir -p "$LIBDIR"
            echo "new-lib" >"$LIBDIR/planted-new.txt"
            return 1
        }
        . "$2"
        install_deploy_library
    ' _ "$_F44W" "$LIB" 2>&1
) || _f44f_rc=$?
if [ "$_f44f_rc" -ne 0 ] &&
    printf '%s\n' "$_f44f_out" | grep -qF 'warn: library deploy FAILED — no previous install existed' &&
    printf '%s\n' "$_f44f_out" | grep -qF 'error: library deploy failed — install aborted' &&
    [ -f "$_F44W/freshroot/lib/planted-new.txt" ] &&
    [ ! -e "$_F44W/backups-fresh" ]; then
    pass "fresh-install deploy failure: loud abort + re-run hint, partial tree kept, no backup material (#482 F44, #497 a Q5)"
else
    fail "fresh-install arm drive (rc=$_f44f_rc out=$_f44f_out) (#482 F44, #497 a Q5)"
fi

echo ""
suite_done
