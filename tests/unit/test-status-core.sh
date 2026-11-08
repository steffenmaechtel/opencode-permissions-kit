#!/bin/sh
# Unit tests for sh/status-core.sh (issue #346, wave 1): the status
# report's section functions, sourced from the lib the way status.sh
# sources them — the log.sh pin pattern (source the lib, call the
# function, stub the environment). The full-script behavioral matrix
# stays in test-status.sh (it runs status.sh end to end); this suite
# pins what only the DECOMPOSED shape can pin:
#   - sourcing purity: definitions only, zero top-level side effects
#   - every section entry point + helper is defined by sourcing
#   - the Management section's --short gating, at function level
#   - the Core section's missing-lib fallback row (git-check absent)
#   - the Leak scan section's three verdict legs against a scratch
#     LIBDIR (hit list, unscannable config, no config)
#   - the Advisories section's missing-binary gate and healthy-binary
#     verdict against a scratch LIBDIR with the real shipped database
# Run: sh tests/unit/test-status-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh"
UI_LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ui.sh"
REPO_FILES="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib"

# Shared harness (issue #394): pass/fail, colors, counters + the work
# registry (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# Controlled PATH (the 0.0.46a F2 environment-dependence class; the
# rule lives in agent/conventions.md, "Test sandbox (unit suites)"):
# a scratch bin with stubs for the probes whose HOST state would leak
# into rows. Everything else the sections touch (stat on scratch paths,
# getent for absent users) is deterministic on its own.
STUB="$WORK/bin"
mkdir -p "$STUB"
# readlink: the Wrapper row would answer with this host's real
# /usr/local/bin/opencode target on kit-managed hosts, "missing" on CI.
printf '#!/bin/sh\nexit 1\n' >"$STUB/readlink"
chmod +x "$STUB/readlink"

# --- 1. sourcing purity: definitions only, zero side effects ----------------------
# The lib's core contract (#346): sourcing defines functions and nothing
# else — no ui.sh needed, no probes, no output. A top-level probe or
# print sneaking in shows up here as output or a non-zero rc.
_purity_out=$(PATH="$STUB:$PATH" sh -c '. "$1"' _ "$LIB" 2>&1) || _purity_rc=$?
if [ "${_purity_rc:-0}" = 0 ] && [ -z "$_purity_out" ]; then
    pass "sourcing status-core.sh runs nothing, prints nothing"
else
    fail "sourcing status-core.sh must be side-effect free (rc=${_purity_rc:-0} out=$_purity_out)"
fi

# --- 2. every section entry point + helper is defined by sourcing -----------------
_defs="status_section_core status_section_advisories status_section_projects
status_section_backend status_section_ddev status_section_wsl2
status_section_root_equiv status_section_leak_scan status_section_management
_st_progress_tee _st_ddev_scan _st_ancestor_grants_x _st_root_blocker
_st_dbdump_gap _st_ddev_basic _st_ddev_share_scan _st_ddev_router_ports
_st_ddev_mkcert_ca _st_ddev_db_dumps _st_ddev_version _st_ddev_win_hosts
status_groups_hits status_sock_agent_reachable"
_missing=""
for _fn in $_defs; do
    sh -c '. "$1" && command -v "$2" >/dev/null' _ "$LIB" "$_fn" 2>/dev/null ||
        _missing="$_missing $_fn"
done
if [ -z "$_missing" ]; then
    pass "all 23 section/helper functions defined by sourcing"
else
    fail "functions missing after sourcing:$_missing"
fi

# --- 3. Management section: --short gating at function level ----------------------
# W4's contract (one verdict line means one line): the hints block is
# the section's whole body — false prints it, true prints nothing.
_mgmt_run() {
    (
        PATH="$STUB:$PATH"
        export PATH NO_COLOR=1
        . "$UI_LIB"
        . "$LIB"
        STATUS_SHORT="$1"
        status_section_management
    ) 2>&1
}
_out=$(_mgmt_run false || true)
if printf '%s' "$_out" | grep -q 'Management (run in a terminal)' &&
    printf '%s' "$_out" | grep -q 'sudo opk config'; then
    pass "management section prints the hints in full mode"
else
    fail "management section full mode broken (out=$_out)"
fi
_out=$(_mgmt_run true || true)
if [ -z "$(printf '%s' "$_out" | grep -v '^ *$')" ]; then
    pass "management section prints nothing under --short"
else
    fail "management section leaks into --short (out=$_out)"
fi

# --- 4. Core section: missing-lib fallback rows at function level -----------------
# The #165/#199 a W3 contract at FUNCTION level: without git_status_row
# defined (neither checkout nor deployed lib delivered it) and without
# sh/update-check.sh at the resolved lib path, BOTH rows must render as
# counted warns naming the broken kit — never a silent drop.
# OPK_UPDATE_CHECK=0 is deliberately set AND ignored: the missing-lib
# arm fires first. Only UNCONDITIONAL rows are asserted — the
# OpenChamber verdict reads this host's real /etc/openchamber state, so
# its row (and with it the counter totals) is environment-dependent on
# kit-managed hosts vs CI (the 0.0.46a F2 class; the row itself is
# pinned host-independently in test-status.sh's verdict matrix).
_core_run() {
    (
        PATH="$STUB:$PATH"
        export PATH NO_COLOR=1
        . "$UI_LIB"
        . "$LIB"
        VERSION=0.0.0
        KIT_CHANNEL=master
        DEFAULT_USER=""
        OPENCODE_USER=opencode-no-such-user-424242
        OPENCODE_GROUP=opencode
        LIBDIR="$WORK/no-lib"
        OPK_UPDATE_CHECK=0
        export OPK_UPDATE_CHECK
        status_section_core
    ) 2>&1
}
_out=$(_core_run || true)
if printf '%s' "$_out" | grep -q 'kit update.*not checked — kit file sh/update-check.sh missing' &&
    printf '%s' "$_out" | grep -q 'git.*not checked — kit file sh/git-check.sh missing or outdated'; then
    pass "core: missing kit libs render their broken-kit warn rows"
else
    fail "core: missing-lib fallback rows broken (out=$(printf '%s' "$_out" | head -4))"
fi

# --- 5. Leak scan section: the no-config leg at function level -------------------
# The section derives SCAN_CFG from OPENCODE_USER's home itself (pure
# movement — no env seam was added), so only the no-config leg runs
# sandboxed (an absent home config). The hit-list, --short and
# unscannable legs stay pinned by test-status.sh's block-level harness
# (#217/#379), which drives the section's scan block with a controlled
# SCAN_CFG.
LK="$WORK/lk"
mkdir -p "$LK"
_lk_run() {
    (
        PATH="$STUB:$PATH"
        export PATH NO_COLOR=1
        . "$UI_LIB"
        . "$LIB"
        LIBDIR="$LK" # no sh/log.sh: the noop log stays, the sandbox holds
        OPENCODE_USER=opencode-no-such-user-424242
        STATUS_SHORT=false
        status_section_leak_scan
    ) 2>&1
}
_out=$(_lk_run || true)
if printf '%s' "$_out" | grep -q 'unknown — no agent config to scan'; then
    pass "leak scan: absent config renders the uncounted unknown (#217)"
else
    fail "leak scan: absent-config leg broken (out=$(printf '%s' "$_out" | head -4))"
fi

# --- 6. Advisories section: missing-binary gate + healthy verdict ------------------
# Scratch LIBDIR with the REAL shipped advisory database and a stub
# opencode binary. Controlled PATH (agent/conventions.md, "Test sandbox
# (unit suites)" — the controlled-PATH rule): a scratch bin with
# symlinks to the section's few externals — stat, grep, sed, head — and
# deliberately NO sudo, NO timeout, NO curl (every network / privilege
# probe degrades deterministically instead of hitting the host's tools).
# 9.9.9 is beyond every shipped range -> ok row.
ADV="$WORK/adv"
mkdir -p "$ADV/sh" "$ADV/bin" "$WORK/advbin"
for _t in stat grep sed head; do
    ln -s "$(command -v "$_t")" "$WORK/advbin/$_t"
done
cp "$REPO_FILES/sh/advisories.sh" "$ADV/sh/"
printf '#!/bin/sh\necho "opencode version 9.9.9"\n' >"$ADV/bin/opencode"
chmod 755 "$ADV/bin/opencode"
_adv_run() {
    (
        PATH="$WORK/advbin" # only the section's externals: no sudo/timeout/curl
        export PATH NO_COLOR=1
        . "$UI_LIB"
        . "$LIB"
        LIBDIR="$ADV"
        VERSION=0.0.0
        OPENCODE_USER=opencode-no-such-user-424242
        status_section_advisories
        printf 'COUNTS warn=%s bad=%s ok=%s\n' \
            "${UI_ROWS_WARN:-0}" "${UI_ROWS_BAD:-0}" "${UI_ROWS_OK:-0}"
    ) 2>&1
}
_out=$(_adv_run || true)
if printf '%s' "$_out" | grep -q 'opencode 9.9.9' &&
    printf '%s' "$_out" | grep -q 'no known advisory affects this install' &&
    printf '%s' "$_out" | grep -q 'COUNTS warn=0 bad=0 ok='; then
    pass "advisories: healthy binary renders the no-advisory ok row"
else
    fail "advisories: healthy-binary leg broken (out=$(printf '%s' "$_out" | head -5))"
fi
# missing binary: the C1/#166 gate — counted warn, upgrade-opencode fix
rm -f "${ADV:?}/bin/opencode"
_out=$(_adv_run || true)
if printf '%s' "$_out" | grep -q 'missing or not executable — advisory check skipped' &&
    printf '%s' "$_out" | grep -q 'sudo opk upgrade-opencode' &&
    printf '%s' "$_out" | grep -q 'COUNTS warn=1'; then
    pass "advisories: missing binary counts the broken-kit warn (C1/#166)"
else
    fail "advisories: missing-binary gate broken (out=$(printf '%s' "$_out" | head -5))"
fi

# --- 7. pairing guard (#413): a version-skewed entry/lib pairing dies loud -----------
# status is deliberately fail-soft (set -u only) — an undefined section
# call does NOT abort, the report silently loses the section while the
# summary still prints. The guard refuses the skewed pairing before any
# section renders. Both directions in fresh children + completeness
# rider over the entry's own section calls.
STATUS_ENTRY="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"
_pg_src="$(extract_func "$STATUS_ENTRY" status_pairing_guard)"
_pg_full=$(sh -c 'eval "$1"; . "$2"; status_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1)
_pg_tr_rc=0
_pg_tr_out="$(sh -c 'eval "$1"; status_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every section defined) (#413)"
else
    fail "pairing guard must pass against the real lib (out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "section 'status_section_core' missing from status-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud before any section renders (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
if sed 's/^[[:space:]]*#.*$//' "$STATUS_ENTRY" | grep -qF 'status_pairing_guard || exit 1'; then
    pass "status.sh wires the guard right after the resolver (#413)"
else
    fail "status.sh must call the guard after sourcing status-core.sh (#413)"
fi
_pg_missing=""
for _fn in $(grep -oE '^[[:space:]]*status_section_[a-z_0-9]+[[:space:]]*$' "$STATUS_ENTRY" |
    awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' | sort -u); do
    printf '%s\n' "$_pg_src" | grep -qF "$_fn" || _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "pairing guard list covers every section the entry calls (#413)"
else
    fail "sections called by status.sh but absent from the guard:$_pg_missing (#413)"
fi

# --- progress tee under hostile PYTHONHOME (#249) ---------------------------------
# _st_progress_tee runs `python3 -I` on the scan pipeline: a poisoned
# PYTHONHOME must not kill the progress display (or corrupt the stream
# it reports on — passthrough must stay byte-exact).
_tee_out=$(printf 'a\0b\0c\0' | PYTHONHOME="$WORK/nonexistent-py-home" \
    sh -c '. "$1" && _st_progress_tee label' _ "$LIB" 2>/dev/null |
    od -An -tx1 | tr -s ' ')
if [ "$_tee_out" = " 61 00 62 00 63 00" ]; then
    pass "progress tee: hostile PYTHONHOME leaves the stream intact (-I, #249)"
else
    fail "progress tee must ignore PYTHONHOME under -I (got [$_tee_out]) (#249)"
fi

# --- scan-root readability gate (#322) --------------------------------------------
# A registered root that is missing (or unreadable for the caller) used
# to scan EMPTY — the report rendered its rows over that tree as a
# false-clean. The gate renders a counted warn and skips just that
# root. Root-hermetic: runs as the suite user; skipped when the suite
# itself runs as root (a root caller reads everything).
if [ "$(id -u)" != 0 ]; then
    _srw="$(work_new)"
    mkdir -p "$_srw/locked"
    chmod 000 "$_srw/locked"
    _srw_out=$(
        UI_SILENT=1 sh -c '. "$1"
            ui_kv_warn() { echo "warn: $1 $2"; }
            _st_ddev_scan "ddev share" "$2/locked" "$2/out"
            echo "outfile-lines=$(wc -l <"$2/out" 2>/dev/null || echo 0)"
        ' _ "$LIB" "$_srw" 2>&1
    )
    chmod 755 "$_srw/locked"
    if printf '%s\n' "$_srw_out" | grep -qF 'warn: ddev share scan skipped — root unreadable' &&
        printf '%s\n' "$_srw_out" | grep -qF 'outfile-lines=0'; then
        pass "scan root gate: unreadable root warns and skips instead of scanning empty (#322)"
    else
        fail "unreadable scan root must warn, not false-clean (out=$_srw_out) (#322)"
    fi
else
    echo "  SKIP  scan root gate needs a non-root suite user (root reads everything) (#322)"
fi

# --- sweep floor: every python3 invocation in the lib runs isolated (#249) --------
_pc=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -c 'python3 -I' || true)
if [ "${_pc:-0}" -ge 4 ]; then
    pass "sweep: status-core.sh python3 calls run -I ($_pc site(s), #249)"
else
    fail "status-core.sh must run its 4 python3 sites with -I (found ${_pc:-0}) (#249)"
fi

# --- #248 sibling copy: the local _opk_timeout_ok executes its failure path -------
# Same probe as update-core.sh (kept in sync per the copies' comments);
# the broken-timeout arm runs against THIS copy so a drifted sibling
# cannot ride on the twin's pin. Arms: broken timeout -> rc 1 (the
# fallback arm), the suite's own healthy PATH -> rc 0 (the bounded arm).
_TO2="$(work_new)"
mkdir -p "$_TO2/bin"
printf '#!/bin/sh\nexit 1\n' >"$_TO2/bin/timeout"
chmod +x "$_TO2/bin/timeout"
if PATH="$_TO2/bin:/usr/bin:/bin" sh -c '. "$1" && ! _opk_timeout_ok' _ "$LIB" &&
    sh -c '. "$1" && _opk_timeout_ok' _ "$LIB"; then
    pass "status-core timeout probe: broken timeout degrades, healthy passes (#248)"
else
    fail "the status-core timeout probe must discriminate broken vs healthy (#248)"
fi

suite_done
