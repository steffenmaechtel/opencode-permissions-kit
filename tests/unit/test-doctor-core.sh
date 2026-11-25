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

# Controlled PATH (tests/AGENTS.md, "Test sandbox (unit suites)"):
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
doctor_daemon_user doctor_git_heal doctor_ranges doctor_header doctor_policy
doctor_detect doctor_scan_trees doctor_fix doctor_summary
_doctor_usage _doctor_all_cleanup _doctor_cleanup doctor_cntrl_bad
doctor_show_sanitize doctor_userns_ranges doctor_load_policy
doctor_classify doctor_examples _doctor_detect_path_ok doctor_roots_append"
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
# rc-capture on the assignment (#499): a broken-non-empty extraction
# (truncation drift, the #396 class) makes eval itself fatal in the
# child, and the bare assignment aborted the whole suite mid-run under
# set -e -- no tally, downstream pins unseen. The capture routes the
# child death into the assert's own row (the _pg_tr_rc idiom below).
_pg_full_rc=0
_pg_full=$(sh -c 'eval "$1"; . "$2"; doctor_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1) || _pg_full_rc=$?
_pg_tr_rc=0
_pg_tr_out="$(PATH="$STUB" "$SH_BIN" -c 'eval "$1"; ui_error() { echo "error: $*" >&2; }; doctor_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if [ "$_pg_full_rc" -eq 0 ] && printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every function defined) (#413)"
else
    fail "pairing guard must pass against the real lib (rc=$_pg_full_rc out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "function 'doctor_cli' missing from doctor-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud before any section runs (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
if live_src "$DOCTOR_ENTRY" | grep -qF 'doctor_pairing_guard || exit 1'; then
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
_pg_entfns="$(live_src "$DOCTOR_ENTRY" |
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

# --- 5b. git heal hooks row at function level (#671) -------------------------------
# doctor_git_heal renders the heal state (from the developer's global
# gitconfig via the documented GH_GITCONFIG override, kit pieces via
# GH_LIBDIR) and classifies THIS project's main-checkout lockout:
# dev-owned index under heal-off is a counted warn with the fix hint,
# under heal-on a transient row, agent-owned renders nothing.
_dgh_stage() {
    _dgh_repo_lib="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib"
    mkdir -p "$WORK/dgh/lib/git-heal/hooks" "$WORK/dgh/devhome" "$WORK/dgh/proj"
    cp "$_dgh_repo_lib/git-heal/heal-index-head" "$WORK/dgh/lib/git-heal/"
    for _dgh_h in post-merge post-checkout post-rewrite post-index-change; do
        cp "$_dgh_repo_lib/git-heal/hooks/$_dgh_h" "$WORK/dgh/lib/git-heal/hooks/"
    done
    git -C "$WORK/dgh/proj" init -q
    : >"$WORK/dgh/proj/.git/index"
    : >"$WORK/dgh/proj/.git/HEAD"
    # Widened-operand fixture pins doctor's mirror row set (#684 a a10)
    : >"$WORK/dgh/proj/.git/ORIG_HEAD"
    : >"$WORK/dgh/devhome/.gitconfig"
    # GITDIR_STORAGE (#787 a B2): the worktree arm's layout
    # discriminator reads the storage root from install.conf ONLY --
    # the harness conf names the scratch storage; GH_STORAGE stays the
    # resolver's seam.
    printf 'DEFAULT_USER=%s\nOPENCODE_USER=opencode-dgh-agent\nGITDIR_STORAGE=%s\n' \
        "$(id -un)" "$WORK/dgh/ptstor" >"$WORK/dgh/install.conf"
}
_dgh_run() {
    (
        PATH="$STUB:$PATH"
        export PATH NO_COLOR=1 GH_GITCONFIG="$WORK/dgh/devhome/.gitconfig" \
            GH_LIBDIR="$WORK/dgh/lib"
        . "$UI_LIB"
        . "$LIB"
        # The entry's cross-lib sourcing (#777), mirrored: the pointer
        # classification arm needs the resolver (DGH_NO_GHC=1 drives
        # the degrade arm).
        if [ "${DGH_NO_GHC:-}" != 1 ]; then
            # shellcheck disable=SC1090
            . "$_dgh_repo_lib/sh/git-heal-core.sh"
            # The resolver's nomination gate (#777 review a C1) reads
            # the storage root through the documented seam; the value
            # runs through _ghc_root_ok's reader mirror (review b
            # B1/B2) -- GH_CONF_RELAX is the documented unit override
            # for /tmp scratch zones.
            export GH_STORAGE="$WORK/dgh/ptstor" GH_CONF_RELAX=1
        fi
        INSTALL_CONF="$WORK/dgh/install.conf"
        DOCTOR_ROOT="${1:-$WORK/dgh/proj}"
        DOCTOR_USER=opencode-dgh-agent
        doctor_git_heal
    ) 2>&1
}
_dgh_stage
_out=$(_dgh_run || true)
if printf '%s' "$_out" | grep -q "git-heal.*OFF -- 'sudo opk git-heal on'" &&
    printf '%s' "$_out" | grep -q "git-heal-file.*$WORK/dgh/proj/.git/index is $(id -un)-owned -- agent git" &&
    printf '%s' "$_out" | grep -q "git-heal-file.*$WORK/dgh/proj/.git/ORIG_HEAD is $(id -un)-owned"; then
    pass "doctor git-heal: OFF state + lockout rows incl. a widened operand"
else
    fail "doctor git-heal: OFF/lockout rows broken (out=$(printf '%s' "$_out" | head -4))"
fi
git config -f "$WORK/dgh/devhome/.gitconfig" core.hooksPath "$WORK/dgh/lib/git-heal/hooks"
_out=$(_dgh_run || true)
if printf '%s' "$_out" | grep -q 'git-heal.*ON -- developer git ops re-pin' &&
    printf '%s' "$_out" | grep -q 'transient'; then
    pass "doctor git-heal: ON state classifies dev-owned index as transient"
else
    fail "doctor git-heal: ON rows broken (out=$(printf '%s' "$_out" | head -4))"
fi

# --- #777: a POINTER-FILE checkout classifies through the resolved
# gitdir — before, doctor's per-project row rendered nothing at all
# for an adopted project (the [ -d .git ] gate never fired). Fixture:
# adopted-shape project, storage gitdir aside; hooksPath is ON (set
# above), so dev-owned operands render the transient form.
mkdir -p "$WORK/dgh/ptstor"
git -C "$WORK/dgh" init -q -b main ptproj
git -C "$WORK/dgh/ptproj" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
mv "$WORK/dgh/ptproj/.git" "$WORK/dgh/ptstor/ptproj.git"
printf 'gitdir: %s\n' "$WORK/dgh/ptstor/ptproj.git" >"$WORK/dgh/ptproj/.git"
_out=$(_dgh_run "$WORK/dgh/ptproj" || true)
if printf '%s' "$_out" | grep -q "git-heal-file.*$WORK/dgh/ptstor/ptproj.git/index is $(id -un)-owned (transient --" &&
    printf '%s' "$_out" | grep -q "git-heal-file.*$WORK/dgh/ptstor/ptproj.git/HEAD is $(id -un)-owned (transient --"; then
    pass "doctor git-heal: a pointer-file project classifies through the resolved gitdir (#777)"
else
    fail "doctor git-heal: pointer classification (out=$(printf '%s' "$_out" | grep -E 'git-heal' | head -3)) (#777)"
fi
# The degrade arm: resolver unavailable -> ONE counted warn row with
# the fix hint, the state row still renders.
_out=$(DGH_NO_GHC=1 _dgh_run "$WORK/dgh/ptproj" 2>&1 || true)
if printf '%s' "$_out" | grep -qF "pointer-file checkout not classified -- kit file" &&
    printf '%s' "$_out" | grep -qF "sh/git-heal-core.sh missing or outdated (fix: sudo opk update)" &&
    printf '%s' "$_out" | grep -q "git-heal.*ON -- developer git ops re-pin"; then
    pass "doctor git-heal: resolver unavailable degrades to a counted warn row (#777)"
else
    fail "doctor git-heal: resolver-degrade arm (out=$(printf '%s' "$_out" | grep -E 'git-heal' | head -3)) (#777)"
fi
# Review-a S4: a REFUSED pointer (garbage content) through doctor —
# the resolver's own skip note renders through doctor's ui set, no
# classification rows fire, and the degrade warn does NOT (the kit is
# not outdated; the pointer is unclassifiable by design).
mkdir -p "$WORK/dgh/ptgarbage"
printf 'not a pointer\n' >"$WORK/dgh/ptgarbage/.git"
_out=$(_dgh_run "$WORK/dgh/ptgarbage" || true)
if printf '%s' "$_out" | grep -qF "skip (pointer): no gitdir: line: $WORK/dgh/ptgarbage/.git" &&
    ! printf '%s' "$_out" | grep -qF 'git-heal-file' &&
    ! printf '%s' "$_out" | grep -qF 'not classified'; then
    pass "doctor git-heal: a refused pointer renders the resolver note, classifies nothing (S4, review a)"
else
    fail "doctor git-heal: refusal arm (out=$(printf '%s' "$_out" | grep -E 'git-heal|skip' | head -2)) (review a S4)"
fi

# Wholesale-swap detection row (#653 family, #703): the doctor twin
# flags owner($DOCTOR_ROOT/.git) != owner($DOCTOR_ROOT). Same stat-stub
# discrimination as the status-core pin: gitdir "rogue"-owned, project
# dir "devuser"-owned renders the row; the control (real stat, equal
# owners) renders nothing.
mkdir -p "$WORK/dgh/detstub"
cat >"$WORK/dgh/detstub/stat" <<'EOF'
#!/bin/sh
_p=$(eval "echo \${$#}")
case "$_p" in
*/.git) printf 'rogue\n' ;;
*) printf 'devuser\n' ;;
esac
EOF
chmod +x "$WORK/dgh/detstub/stat"
_out=$(
    (
        PATH="$WORK/dgh/detstub:$STUB:$PATH"
        export PATH NO_COLOR=1 GH_GITCONFIG="$WORK/dgh/devhome/.gitconfig" \
            GH_LIBDIR="$WORK/dgh/lib"
        . "$UI_LIB"
        . "$LIB"
        INSTALL_CONF="$WORK/dgh/install.conf"
        DOCTOR_ROOT="$WORK/dgh/proj"
        DOCTOR_USER=opencode-dgh-agent
        doctor_git_heal
    ) 2>&1 || true
)
if printf '%s' "$_out" | grep -q "\.git owner.*$WORK/dgh/proj/\.git is rogue-owned while the project dir" &&
    printf '%s' "$_out" | grep -q "is devuser-owned — wholesale .git swap suspected"; then
    pass "doctor git-heal: owner-mismatch detection row renders (#703)"
else
    fail "doctor git-heal: detection row missing (#703; out=$(printf '%s' "$_out" | grep -F '.git owner' | head -2))"
fi
_out=$(_dgh_run || true)
if printf '%s' "$_out" | grep -qF '.git owner'; then
    fail "doctor git-heal: equal owners render no detection row (#703 control)"
else
    pass "doctor git-heal: equal owners render no detection row (#703 control)"
fi

# --- #653 wave 1: heal-drift and planted-content rows (the status-core twin) -------
# Same contract, doctor's per-project shape and ASCII dash vocabulary.
# Explicit modes per arm — the ambient umask decides git's defaults.
# _dgh_run defaults DOCTOR_ROOT to dgh/proj (unhealed classic repo).
_ddr_reset() {
    chmod +t "$WORK/dgh/proj/.git"
    chmod 644 "$WORK/dgh/proj/.git/config"
    chmod 755 "$WORK/dgh/proj/.git/hooks"
    rm -f "${WORK:?}/dgh/proj/.git/hooks/pre-commit"
}
_out=$(_dgh_run || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/proj/.git -- sticky bit missing on the gitdir" &&
    printf '%s' "$_out" | grep -qF "sudo opk update --refresh' / 'opk config refresh"; then
    pass "doctor git-heal: fresh clone renders the sticky-drift row (#653 W1)"
else
    fail "doctor git-heal: sticky-drift row missing (#653 W1; out=$(printf '%s' "$_out" | grep -F 'heal drift' | head -2))"
fi
_ddr_reset
_out=$(_dgh_run || true)
if printf '%s' "$_out" | grep -qF "sticky bit missing"; then
    fail "doctor git-heal: healed gitdir renders no sticky row (#653 W1 control)"
else
    pass "doctor git-heal: healed gitdir renders no sticky row (#653 W1 control)"
fi
chmod 664 "$WORK/dgh/proj/.git/config"
chmod 775 "$WORK/dgh/proj/.git/hooks"
_out=$(_dgh_run || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/proj/.git/config -- group-writable" &&
    printf '%s' "$_out" | grep -qF "$WORK/dgh/proj/.git/hooks -- group-writable"; then
    pass "doctor git-heal: group-writable config/hooks render drift rows (#653 W1)"
else
    fail "doctor git-heal: group-write rows missing (#653 W1; out=$(printf '%s' "$_out" | grep -E 'config --|hooks --' | head -2))"
fi
_ddr_reset
: >"$WORK/dgh/proj/.git/hooks/pre-commit"
_out=$(_dgh_run || true)
if printf '%s' "$_out" | grep -qF "1 non-sample entries in $WORK/dgh/proj/.git/hooks" &&
    printf '%s' "$_out" | grep -qF 'that git call uses .git/hooks;' &&
    printf '%s' "$_out" | grep -qF 'survives the heal'; then
    pass "doctor git-heal: planted non-sample hook renders its row (#653 W1)"
else
    fail "doctor git-heal: planted row missing (#653 W1; out=$(printf '%s' "$_out" | grep -F 'non-sample' | head -2))"
fi
# Healed control: absence greps the row texts, not the key — the
# getfacl DEGRADE row shares the key and would false-red the control
# on hosts without the acl tools.
_ddr_reset
_out=$(_dgh_run || true)
if ! printf '%s' "$_out" | grep -qF 'sticky bit missing' &&
    ! printf '%s' "$_out" | grep -qF 'non-sample entries' &&
    ! printf '%s' "$_out" | grep -qE '\.git/(config|hooks) -- '; then
    pass "doctor git-heal: the fully-healed fixture renders no drift/planted rows (#653 W1 control)"
else
    fail "doctor git-heal: healed control fired (#653 W1; out=$(printf '%s' "$_out" | grep -E 'heal drift|planted' | head -3))"
fi
# Owner-mismatch arm: FORMAT-AWARE stat stub (a last-arg-keyed stub
# would corrupt the %A legs). %A on the gitdir reports the healed
# sticky shape, %U on config a foreign owner, everything else the real
# user — the lockout rows keep rendering.
mkdir -p "$WORK/dgh/driftstub"
cat >"$WORK/dgh/driftstub/stat" <<'EOF'
#!/bin/sh
case "$2" in
%A)
    case "$3" in
    */.git) printf 'drwxrws--T\n' ;;
    *) printf -- '---\n' ;;
    esac
    ;;
%U)
    case "$3" in
    */.git/config) printf 'rogue\n' ;;
    *) printf '%s\n' "$(id -un)" ;;
    esac
    ;;
esac
EOF
chmod +x "$WORK/dgh/driftstub/stat"
_out=$(
    (
        PATH="$WORK/dgh/driftstub:$STUB:$PATH"
        export PATH NO_COLOR=1 GH_GITCONFIG="$WORK/dgh/devhome/.gitconfig" \
            GH_LIBDIR="$WORK/dgh/lib"
        . "$UI_LIB"
        . "$LIB"
        INSTALL_CONF="$WORK/dgh/install.conf"
        DOCTOR_ROOT="$WORK/dgh/proj"
        DOCTOR_USER=opencode-dgh-agent
        doctor_git_heal
    ) 2>&1 || true
)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/proj/.git/config -- rogue-owned (not $(id -un))" &&
    ! printf '%s' "$_out" | grep -qF 'sticky bit missing'; then
    pass "doctor git-heal: foreign config owner renders the drift row, sticky stays quiet (#653 W1)"
else
    fail "doctor git-heal: owner arm (out=$(printf '%s' "$_out" | grep -F 'heal drift' | head -2)) (#653 W1)"
fi
# ACL arm (tool-gated): a named entry re-grants what the heal strips;
# setfacl's mask fires the group-write leg too (the honest combined
# row).
if command -v setfacl >/dev/null 2>&1 && command -v getfacl >/dev/null 2>&1; then
    _ddr_reset
    setfacl -m "u:$(id -un):rw" "$WORK/dgh/proj/.git/config"
    _out=$(_dgh_run || true)
    if printf '%s' "$_out" | grep -qF "$WORK/dgh/proj/.git/config -- group-writable, extended ACLs present"; then
        pass "doctor git-heal: an extended ACL on config renders its drift fragment (#653 W1)"
    else
        fail "doctor git-heal: ACL arm (out=$(printf '%s' "$_out" | grep -F 'config --' | head -1)) (#653 W1)"
    fi
    setfacl -b "$WORK/dgh/proj/.git/config"
else
    echo "skip: acl tools unavailable -- the #653 W1 ACL arm did not run"
fi
# getfacl-missing degrade arm (restricted PATH): the ACL leg degrades
# to ONE counted warn row while the other checks keep rendering.
mkdir -p "$WORK/dgh/nogfacl"
for _ddr_b in stat find git getent cut grep wc sed; do
    ln -s "$(command -v "$_ddr_b")" "$WORK/dgh/nogfacl/$_ddr_b"
done
chmod -t "$WORK/dgh/proj/.git"
_out=$(
    (
        PATH="$WORK/dgh/nogfacl:$STUB"
        export PATH NO_COLOR=1 GH_GITCONFIG="$WORK/dgh/devhome/.gitconfig" \
            GH_LIBDIR="$WORK/dgh/lib"
        . "$UI_LIB"
        . "$LIB"
        INSTALL_CONF="$WORK/dgh/install.conf"
        DOCTOR_ROOT="$WORK/dgh/proj"
        DOCTOR_USER=opencode-dgh-agent
        doctor_git_heal
    ) 2>&1 || true
)
if printf '%s' "$_out" | grep -qF 'heal drift ACLs not checked -- getfacl unavailable' &&
    printf '%s' "$_out" | grep -qF 'sticky bit missing'; then
    pass "doctor git-heal: missing getfacl degrades the ACL leg loudly, checks survive (#653 W1)"
else
    fail "doctor git-heal: getfacl-degrade arm (out=$(printf '%s' "$_out" | head -3)) (#653 W1)"
fi
# Pointer-target arm: drift rows name the RESOLVED storage gitdir (the
# #777 twin — the ptproj fixture from the pointer classification arm).
_out=$(_dgh_run "$WORK/dgh/ptproj" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/ptstor/ptproj.git -- sticky bit missing on the gitdir"; then
    pass "doctor git-heal: a pointer project's drift rows name the resolved gitdir (#653 W1)"
else
    fail "doctor git-heal: pointer drift rows (out=$(printf '%s' "$_out" | grep -F 'heal drift' | head -2)) (#653 W1)"
fi
# a B5: a hand-QUOTED DEFAULT_USER must not fire the owner drift row —
# the extraction strips quotes like the DOCTOR_USER sibling idiom, and
# the state leg heals with it (getent sees the stripped name, so the
# state row is not "unknown"). The fixture is otherwise healed
# (_ddr_reset: the getfacl arm above left the sticky stripped).
printf 'DEFAULT_USER="%s"\nOPENCODE_USER=opencode-dgh-agent\nGITDIR_STORAGE=%s\n' "$(id -un)" \
    "$WORK/dgh/ptstor" >"$WORK/dgh/install.conf"
_ddr_reset
_out=$(_dgh_run || true)
printf 'DEFAULT_USER=%s\nOPENCODE_USER=opencode-dgh-agent\nGITDIR_STORAGE=%s\n' "$(id -un)" \
    "$WORK/dgh/ptstor" >"$WORK/dgh/install.conf"
if ! printf '%s' "$_out" | grep -qE '\.git/(config|hooks) -- ' &&
    ! printf '%s' "$_out" | grep -q "git-heal.*unknown"; then
    pass "doctor git-heal: a quoted DEFAULT_USER compares stripped, state resolves (#785 a B5)"
else
    fail "doctor git-heal: quoted-conf arm (out=$(printf '%s' "$_out" | grep -E 'heal drift|git-heal' | head -3)) (#785 a B5)"
fi

# --- #653 wave 2: group/setgid leg, repo-config keys, worktree arms ---------------
# The status-core twin's arms over doctor's per-project shape (ASCII
# dash vocabulary). Dedicated fixture: a classic repo with ONE real
# worktree (dgh/proj is init-only, no commit — no worktree possible
# there), explicit modes everywhere; the reset heals the full W2
# contract and restores the reg files' content from pristine copies.
mkdir -p "$WORK/dgh/wt2"
git -C "$WORK/dgh/wt2" init -q -b main repo
git -C "$WORK/dgh/wt2/repo" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
git -C "$WORK/dgh/wt2/repo" worktree add -q "$WORK/dgh/wt2/awt" -b awtb 2>/dev/null
mkdir -p "$WORK/dgh/wt2/regkeep"
cp "$WORK/dgh/wt2/repo/.git/worktrees/awt/commondir" "$WORK/dgh/wt2/regkeep/"
cp "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir" "$WORK/dgh/wt2/regkeep/"
_dwt_reset() {
    chmod 3770 "$WORK/dgh/wt2/repo/.git"
    chmod 644 "$WORK/dgh/wt2/repo/.git/config"
    chmod 755 "$WORK/dgh/wt2/repo/.git/hooks"
    chmod 3770 "$WORK/dgh/wt2/repo/.git/worktrees"
    cp "$WORK/dgh/wt2/regkeep/commondir" "$WORK/dgh/wt2/repo/.git/worktrees/awt/commondir"
    cp "$WORK/dgh/wt2/regkeep/gitdir" "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir"
    chmod 644 "$WORK/dgh/wt2/repo/.git/worktrees/awt/commondir" \
        "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir"
    rm -f "${WORK:?}/dgh/wt2/repo/.git/hooks/pre-commit"
    git -C "$WORK/dgh/wt2/repo" config -f "$WORK/dgh/wt2/repo/.git/config" \
        --unset-all core.fsmonitor 2>/dev/null || true
    git -C "$WORK/dgh/wt2/repo" config -f "$WORK/dgh/wt2/repo/.git/config" \
        --unset-all core.editor 2>/dev/null || true
    git -C "$WORK/dgh/wt2/repo" config -f "$WORK/dgh/wt2/repo/.git/config" \
        --unset-all core.pager 2>/dev/null || true
}
# Group-access/setgid leg (the #785 fold): 1700 keeps sticky, kills
# the group leg — the shape that stayed quiet on every surface (the
# status twin's comment carries the measured shapes; this arm adds
# the true '---' form via symbolic g-s).
_dwt_reset
chmod 1700 "$WORK/dgh/wt2/repo/.git"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git -- group access/setgid missing on the gitdir" &&
    ! printf '%s' "$_out" | grep -qF 'sticky bit missing on the gitdir'; then
    pass "doctor git-heal: a 1700 gitdir renders the group-access row, sticky stays quiet (#653 W2)"
else
    fail "doctor git-heal: group leg 1700 arm (out=$(printf '%s' "$_out" | grep -F 'heal drift' | head -2)) (#653 W2)"
fi
_dwt_reset
chmod g-rwx,g-s "$WORK/dgh/wt2/repo/.git"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git -- group access/setgid missing on the gitdir" &&
    [ "$(stat -c %A "$WORK/dgh/wt2/repo/.git")" = 'drwx-----T' ]; then
    pass "doctor git-heal: the fully-stripped group leg renders the row too (--- arm) (#653 W2)"
else
    fail "doctor git-heal: group leg --- shape (mode=$(stat -c %A "$WORK/dgh/wt2/repo/.git"); out=$(printf '%s' "$_out" | grep -F 'heal drift' | head -2)) (#653 W2)"
fi
# Plain-x discrimination: a 755 clone fires the sticky row only.
_dwt_reset
chmod 755 "$WORK/dgh/wt2/repo/.git"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF 'sticky bit missing on the gitdir' &&
    ! printf '%s' "$_out" | grep -qF 'group access/setgid'; then
    pass "doctor git-heal: a 755 clone fires the sticky row only, never the group row (#653 W2)"
else
    fail "doctor git-heal: group leg 755 arm (out=$(printf '%s' "$_out" | grep -F 'heal drift' | head -2)) (#653 W2)"
fi
# Suspicious repo-config keys: one row per gitdir, key names only
# (the injection twin: crafted values never reach the row).
_dwt_reset
git -C "$WORK/dgh/wt2/repo" config -f "$WORK/dgh/wt2/repo/.git/config" core.fsmonitor /usr/bin/false
git -C "$WORK/dgh/wt2/repo" config -f "$WORK/dgh/wt2/repo/.git/config" \
    core.editor "$(printf 'ev\033[31mil')"
printf '[core]\n\tpager = line1\\\n\tline2\n' >>"$WORK/dgh/wt2/repo/.git/config"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "suspicious repo-config keys in $WORK/dgh/wt2/repo/.git/config:" &&
    printf '%s' "$_out" | grep -qF 'core.fsmonitor,core.editor,core.pager' &&
    ! printf '%s' "$_out" | grep -qF 'line2' &&
    ! printf '%s' "$_out" | grep -qF "$(printf '\033[31m')"; then
    pass "doctor git-heal: planted repo-config keys render key names only, never values (#653 W2)"
else
    fail "doctor git-heal: repo-keys arm (out=$(printf '%s' "$_out" | grep -F 'repo keys' | head -2)) (#653 W2)"
fi
# Symlinked-config skip arm: the wave-1 symlink row fires, the key
# probe never reads through the link.
_dwt_reset
mv "$WORK/dgh/wt2/repo/.git/config" "$WORK/dgh/wt2/cfg-real"
printf '[core]\n\tfsmonitor = planted\n' >"$WORK/dgh/wt2/cfg-decoy"
ln -s "$WORK/dgh/wt2/cfg-decoy" "$WORK/dgh/wt2/repo/.git/config"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/config is a symlink" &&
    ! printf '%s' "$_out" | grep -qF 'suspicious repo-config keys'; then
    pass "doctor git-heal: a symlinked config renders the symlink row, no key read-through (#653 W2)"
else
    fail "doctor git-heal: symlinked-config arm (out=$(printf '%s' "$_out" | grep -E 'heal drift|repo keys' | head -2)) (#653 W2)"
fi
rm -f "${WORK:?}/dgh/wt2/repo/.git/config"
mv "$WORK/dgh/wt2/cfg-real" "$WORK/dgh/wt2/repo/.git/config"
rm -f "${WORK:?}/dgh/wt2/cfg-decoy"
# Worktree arms: group-write on a registration pointer file.
_dwt_reset
chmod 664 "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir -- group-writable" &&
    printf '%s' "$_out" | grep -qF 'the heal pins them developer-owned 644 under a sticky'; then
    pass "doctor git-heal: a group-writable registration pointer renders its row (#653 W2)"
else
    fail "doctor git-heal: worktree group-write arm (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#653 W2)"
fi
# Collection sticky arm.
_dwt_reset
chmod -t "$WORK/dgh/wt2/repo/.git/worktrees"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/worktrees -- sticky bit missing on the collection"; then
    pass "doctor git-heal: a non-sticky worktrees collection renders its row (#653 W2)"
else
    fail "doctor git-heal: collection sticky arm (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#653 W2)"
fi
# Owner arm (FORMAT-AWARE stat stub): %U rogue on a registration
# gitdir file, %A healed everywhere.
mkdir -p "$WORK/dgh/wtstub"
cat >"$WORK/dgh/wtstub/stat" <<'EOF'
#!/bin/sh
case "$2" in
%A)
    case "$3" in
    */.git | */.git/worktrees) printf 'drwxrws--T\n' ;;
    *) printf -- '-rw-r--r--\n' ;;
    esac
    ;;
%U)
    case "$3" in
    */worktrees/*/gitdir) printf 'rogue\n' ;;
    *) printf '%s\n' "$(id -un)" ;;
    esac
    ;;
esac
EOF
chmod +x "$WORK/dgh/wtstub/stat"
_dwt_reset
_out=$(
    (
        PATH="$WORK/dgh/wtstub:$STUB:$PATH"
        export PATH NO_COLOR=1 GH_GITCONFIG="$WORK/dgh/devhome/.gitconfig" \
            GH_LIBDIR="$WORK/dgh/lib"
        . "$UI_LIB"
        . "$LIB"
        INSTALL_CONF="$WORK/dgh/install.conf"
        DOCTOR_ROOT="$WORK/dgh/wt2/repo"
        DOCTOR_USER=opencode-dgh-agent
        doctor_git_heal
    ) 2>&1 || true
)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir -- rogue-owned (not $(id -un))"; then
    pass "doctor git-heal: a foreign-owned registration pointer renders its row (#653 W2)"
else
    fail "doctor git-heal: worktree owner arm (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#653 W2)"
fi
# Back-reference swap arm (the fs-baseline .git-pointer residual).
_dwt_reset
printf 'gitdir: %s\n' "$WORK/dgh/wt2/repo/.git" >"$WORK/dgh/wt2/awt/.git"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/worktrees/awt -- its worktree's .git does not" &&
    printf '%s' "$_out" | grep -qF 'swapped pointer'; then
    pass "doctor git-heal: a swapped worktree .git pointer renders the back-reference row (#653 W2)"
else
    fail "doctor git-heal: swap arm (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#653 W2)"
fi
printf 'gitdir: %s\n' "$WORK/dgh/wt2/repo/.git/worktrees/awt" >"$WORK/dgh/wt2/awt/.git"
# Prunable arm: detail line, never a counted warn.
_dwt_reset
mv "$WORK/dgh/wt2/awt/.git" "$WORK/dgh/wt2/awt/.git.orig"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/worktrees/awt names a gone worktree (prunable" &&
    printf '%s' "$_out" | grep -qE '^  worktree .*gone worktree' &&
    ! printf '%s' "$_out" | grep -qF "does not"; then
    pass "doctor git-heal: a prunable registration renders an owning plain row, no warn (#653 W2, #787 a A2)"
else
    fail "doctor git-heal: prunable arm (out=$(printf '%s' "$_out" | grep 'worktree' | head -2)) (#653 W2, #787 a A2)"
fi
mv "$WORK/dgh/wt2/awt/.git.orig" "$WORK/dgh/wt2/awt/.git"
# Malformed back-reference arm.
_dwt_reset
printf 'ev\033[31mil\n' >"$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir -- malformed back-reference" &&
    ! printf '%s' "$_out" | grep -qF "$(printf '\033[31m')"; then
    pass "doctor git-heal: a malformed back-reference renders its row without the payload (#653 W2)"
else
    fail "doctor git-heal: malformed-ref arm (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#653 W2)"
fi
# Healed control: none of the new rows render.
_dwt_reset
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if ! printf '%s' "$_out" | grep -qE 'worktree|repo keys|group access/setgid'; then
    pass "doctor git-heal: the fully-healed W2 fixture renders no new rows (#653 W2 control)"
else
    fail "doctor git-heal: healed W2 control fired (out=$(printf '%s' "$_out" | grep -E 'worktree|repo keys|group access' | head -3)) (#653 W2)"
fi
# Layout-split arm (the storage contract): the §777 ptproj fixture
# gains a real worktree; group-writable reg pointer files under the
# storage root stay quiet (#779 leaves the subtree g+rw by design).
git --git-dir="$WORK/dgh/ptstor/ptproj.git" worktree add -q "$WORK/dgh/ptwt" -b ptwb 2>/dev/null
chmod 664 "$WORK/dgh/ptstor/ptproj.git/worktrees/ptwt/commondir" \
    "$WORK/dgh/ptstor/ptproj.git/worktrees/ptwt/gitdir"
_out=$(_dgh_run "$WORK/dgh/ptproj" || true)
if ! printf '%s' "$_out" | grep -qF "$WORK/dgh/ptstor/ptproj.git/worktrees/ptwt"; then
    pass "doctor git-heal: storage-layout registration pointer files stay quiet at g+rw (#653 W2)"
else
    fail "doctor git-heal: storage relaxed arm fired (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#653 W2)"
fi

# --- #787 review a: fix-wave pins (the status-core twin's arms) ---------------------
# a A1/a B2: no storage key in install.conf + an env GH_STORAGE
# pointing at the classic tree -- the strict contract must hold (the
# pre-fix empty-prefix degeneration to /*).
_dwt_reset
chmod 664 "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir"
printf '# no storage key here\n' >"$WORK/dgh/install-nostor.conf"
_out=$(
    (
        GH_STORAGE="$WORK/dgh/wt2"
        # GH_CONF_RELAX: the simulated attack value must PASS the
        # reader-side validation (wrong-mechanism trap, the status
        # twin's comment).
        export GH_STORAGE GH_CONF_RELAX=1 NO_COLOR=1 GH_GITCONFIG="$WORK/dgh/devhome/.gitconfig" \
            GH_LIBDIR="$WORK/dgh/lib"
        PATH="$STUB:$PATH"
        . "$UI_LIB"
        . "$LIB"
        # shellcheck disable=SC1090
        . "$_dgh_repo_lib/sh/git-heal-core.sh"
        INSTALL_CONF="$WORK/dgh/install-nostor.conf"
        DOCTOR_ROOT="$WORK/dgh/wt2/repo"
        DOCTOR_USER=opencode-dgh-agent
        doctor_git_heal
    ) 2>&1 || true
)
if printf '%s' "$_out" | grep -qF "$WORK/dgh/wt2/repo/.git/worktrees/awt/gitdir -- group-writable"; then
    pass "doctor git-heal: no storage key keeps the strict contract; env GH_STORAGE cannot relax it (#787 a A1/a B2)"
else
    fail "doctor git-heal: empty-stor strict arm (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#787 a A1/a B2)"
fi
# a C5: camelCase hooksPath renders its lowercased row.
_dwt_reset
git -C "$WORK/dgh/wt2/repo" config -f "$WORK/dgh/wt2/repo/.git/config" core.hooksPath /tmp/e2e-evil
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF 'suspicious repo-config keys in' &&
    printf '%s' "$_out" | grep -qF 'core.hookspath'; then
    pass "doctor git-heal: a camelCase hooksPath plant renders its lowercased row (#787 a C5)"
else
    fail "doctor git-heal: hooksPath tolower arm (out=$(printf '%s' "$_out" | grep -F 'repo keys' | head -1)) (#787 a C5)"
fi
# b A1 (the round-a B3 arm reworked): UTF-8 pointer content must
# SURVIVE into the row text (the status twin's comment carries the
# trade).
_dwt_reset
_en=$(printf '\342\200\223')
printf 'gitdir: %s%s\n' "$WORK/dgh/wt2/repo/.git" "$_en" >"$WORK/dgh/wt2/awt/.git"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "its worktree's .git does not" &&
    printf '%s' "$_out" | grep -qF "$_en"; then
    pass "doctor git-heal: the swap row preserves UTF-8 pointer content (#787 b A1)"
else
    fail "doctor git-heal: UTF-8 preservation arm (out=$(printf '%s' "$_out" | grep -F 'worktree' | head -2)) (#787 b A1)"
fi
printf 'gitdir: %s\n' "$WORK/dgh/wt2/repo/.git/worktrees/awt" >"$WORK/dgh/wt2/awt/.git"
# a B4: the traversability notice.
_dwt_reset
chmod 000 "$WORK/dgh/wt2/repo/.git"
_out=$(_dgh_run "$WORK/dgh/wt2/repo" || true)
if printf '%s' "$_out" | grep -qF "entry rows under $WORK/dgh/wt2/repo/.git may be incomplete (not traversable)" &&
    printf '%s' "$_out" | grep -qF 'sticky bit missing on the gitdir'; then
    pass "doctor git-heal: a non-traversable gitdir renders the incompleteness notice (#787 a B4)"
else
    fail "doctor git-heal: traversability notice arm (out=$(printf '%s' "$_out" | grep -F 'traversable' | head -1)) (#787 a B4)"
fi

# --- sweep floor: doctor-core's python3 sites run -I (#249) ------------------------
# Comment-strip rider per conventions.md ("Source-counting pins") -- a
# commented-out site must not count. Four sites: cntrl_bad,
# show_sanitize, load_policy, the detect write block.
_pc=$(live_src "$LIB" | grep -c 'python3 -I' || true)
if [ "${_pc:-0}" = 4 ]; then
    pass "sweep floor: doctor-core.sh python3 calls run -I (all $_pc sites, #249)"
else
    fail "doctor-core.sh must run exactly 4 python3 sites with -I (found ${_pc:-0}) (#249)"
fi

suite_done
