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
install_project_roots_select install_agents_form_normalize"
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
if grep -qF 'kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/install-core.sh"' "$INSTALL" &&
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
_skip_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n 'elif \[ "\$SKIP_PROMPTS" = true \]; then' | head -1 | cut -d: -f1)
_sel_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n 'install_project_roots_select$' | tail -1 | cut -d: -f1)
if [ -n "$_skip_ln" ] && [ -n "$_sel_ln" ] && [ "$_skip_ln" -lt "$_sel_ln" ]; then
    pass "--yes skip branch precedes the interactive selection (W14)"
else
    fail "--yes skip branch precedes the interactive selection (skip=$_skip_ln select=$_sel_ln)"
fi
# normalize-agents-forms (0.0.44a V1) runs before the dispatch that
# fires the migration loop — live anchors, not the naming comment (#385
# b b1): the CALL arm vs the dispatch arm.
_norm_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n 'install_agents_form_normalize$' | tail -1 | cut -d: -f1)
_disp_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n 'm | move | c | copy)' | head -1 | cut -d: -f1)
if [ -n "$_norm_ln" ] && [ -n "$_disp_ln" ] && [ "$_norm_ln" -lt "$_disp_ln" ]; then
    pass "normalization precedes the migration dispatch (V1)"
else
    fail "normalization precedes the migration dispatch (V1) (norm=$_norm_ln disp=$_disp_ln)"
fi
# the distro gate runs before the first interactive menu (0.0.45a order
# pin; comment-stripped operands)
_dg_call_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n '^    _distro_gate ' | head -1 | cut -d: -f1)
_dg_menu_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n 'ui_menu "How do you want to install?"' | head -1 | cut -d: -f1)
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
if sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -qF '_distro_gate "${_dg_id:-unknown}" "$_dg_ver"'; then
    pass "do_plan_phase wires the parsed os-release values into the gate (verbatim call pin)"
else
    fail "do_plan_phase wires the parsed os-release values into the gate (verbatim call pin)"
fi
if sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -qF '_root_user_gate "$DEFAULT_USER"'; then
    pass "do_plan_phase wires DEFAULT_USER into _root_user_gate (verbatim call pin)"
else
    fail "do_plan_phase wires DEFAULT_USER into _root_user_gate (verbatim call pin)"
fi
# root gate after the charset gate, before the distro gate (issue #192:
# a root shell is unrepairable, so it refuses first)
_rug_call_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n '^    _root_user_gate ' | head -1 | cut -d: -f1)
_rug_charset_ln=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n "Invalid user name" | head -1 | cut -d: -f1)
if [ -n "$_rug_call_ln" ] && [ -n "$_rug_charset_ln" ] && [ -n "$_dg_call_ln" ] &&
    [ "$_rug_charset_ln" -lt "$_rug_call_ln" ] && [ "$_rug_call_ln" -lt "$_dg_call_ln" ]; then
    pass "root gate runs after the charset gate, before the distro gate (order pin)"
else
    fail "root gate order (charset=$_rug_charset_ln gate=$_rug_call_ln distro=$_dg_call_ln)"
fi
# the pre-flight wires the python3 health gate (verbatim call pin,
# #244; the gate function itself stays in install.sh and is matrix-
# pinned in test-install-args.sh). Comment-stripped (#407 a P4).
if sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -qF '    _py3_health_probe'; then
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
if sed 's/^[[:space:]]*#.*$//' "$INSTALL" | grep -qF 'ddev_handover_stamp_write() { :; }'; then
    pass "stamp-write stub stays deliberately silent (documented exception)"
else
    fail "stamp-write stub must stay the documented silent exception"
fi
if sed 's/^[[:space:]]*#.*$//' "$INSTALL" | grep -qF 'ddev_migrate_done() { return 1; }'; then
    pass "done-probe stub stays deliberately fail-safe (documented exception)"
else
    fail "done-probe stub must stay the documented fail-safe exception"
fi

# --- 9. pairing guard (#413): a version-skewed entry/lib pairing dies loud -----------
# kit_source dies loud on a missing FILE; the guard closes the
# missing-FUNCTION twin (a truncated/incompletely-deployed core would
# rc-127 the bare phase calls — a cryptic not-found abort). extract_func
# pulls the guard from the entry; both directions in fresh children,
# plus the completeness rider over the entry's own phase calls.
_pg_src="$(extract_func "$INSTALL" install_pairing_guard)"
_pg_full=$(sh -c 'eval "$1"; . "$2"; install_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1)
_pg_tr_rc=0
_pg_tr_out="$(sh -c 'eval "$1"; install_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every phase defined) (#413)"
else
    fail "pairing guard must pass against the real lib (out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "phase 'do_plan_phase' missing from install-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud naming the first missing phase (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
if sed 's/^[[:space:]]*#.*$//' "$INSTALL" | grep -qF 'install_pairing_guard || exit 1'; then
    pass "install.sh wires the guard right after kit_source (#413)"
else
    fail "install.sh must call the guard after sourcing install-core.sh (#413)"
fi
_pg_missing=""
for _fn in $(grep -oE '^do_[a-z_]+$' "$INSTALL" | sort -u); do
    printf '%s\n' "$_pg_src" | grep -qF "$_fn" || _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "pairing guard list covers every phase the entry calls (#413)"
else
    fail "phases called by install.sh but absent from the guard:$_pg_missing (#413)"
fi

echo ""
suite_done
