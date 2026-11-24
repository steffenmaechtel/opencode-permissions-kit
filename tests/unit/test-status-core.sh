#!/bin/sh
# Unit tests for sh/status-core.sh (issue #346, wave 1): the status
# report's section functions, sourced from the lib the way status.sh
# sources them — the log.sh pin pattern (source the lib, call the
# function, stub the environment). The full-script behavioral matrix
# stays in test-status.sh (it runs status.sh end to end); this suite
# pins what only the DECOMPOSED shape can pin:
#   - sourcing purity: definitions only, zero top-level side effects
#   - every section entry point + helper is defined by sourcing
#   - the pairing guard (#413, #452): real lib passes, truncated lib dies
#     loud, and both completeness riders (every call the entry makes
#     AND every function the lib defines — comment-stripped,
#     boundary-anchored)
#   - the Management section's --short gating, at function level
#   - the Core section's missing-lib fallback row (git-check absent)
#   - the Leak scan section's three verdict legs against a scratch
#     LIBDIR (hit list, unscannable config, no config)
#   - the Advisories section's missing-binary gate and healthy-binary
#     verdict against a scratch LIBDIR with the real shipped database
#   - the Git protection section (#764): the cross-lib call-site
#     guard (missing and partially skewed core), the not-enabled
#     counted warning, the enabled rows (state, deviations with their
#     commands, INFO orphans), stderr capture, mktemp degradation
# Run: sh tests/unit/test-status-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh"
UI_LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ui.sh"
# git-heal-core.sh (#777): the cross-lib resolver the git-heal section
# call-site-guards after — the entry sources it (management/status.sh);
# the function-level harness mirrors that sourcing (GHS_NO_GHC=1
# unsets it for the degrade arm).
GH_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/git-heal-core.sh"
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
_defs="status_section_core status_section_git_heal status_section_git_protection
status_section_advisories
status_section_projects status_section_backend status_section_ddev
status_section_wsl2 status_section_root_equiv status_section_leak_scan
status_section_management
_st_progress_tee _st_ddev_scan _st_ancestor_grants_x _st_root_blocker
_st_dbdump_gap _st_ddev_basic _st_ddev_share_scan _st_ddev_router_ports
_st_ddev_mkcert_ca _st_ddev_db_dumps _st_ddev_version _st_ddev_win_hosts
status_groups_hits status_sock_agent_reachable
status_sudo_verdict status_win_interop_verdict"
# (#590 b F1 residue) _opk_timeout_ok stays unlisted BY DESIGN: the #248
# sibling block below pins it BEHAVIORALLY (sourcing + broken-vs-healthy
# call) — a removal/rename reddens that pin, so the list stays 26.
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

# --- 4b. Git heal hooks section: state rows + lockout classification (#671) -------
# The section's whole state machine at FUNCTION level, sandboxed via
# GH_GITCONFIG (the documented unit override) + a scratch LIBDIR and
# PROJECTS_CONF: OFF renders the opt-in hint, ON renders the active
# row and mutes the lockout warn, a foreign value names itself, and a
# dev-owned index/HEAD under a heal-off state renders the counted
# lockout warn with its fix hint.
_ghs_stage() {
    mkdir -p "$WORK/ghs/lib/git-heal/hooks" "$WORK/ghs/devhome" "$WORK/ghs/root"
    cp "$REPO_FILES/git-heal/heal-index-head" "$WORK/ghs/lib/git-heal/"
    cp "$REPO_FILES/git-heal/hooks/post-checkout" "$WORK/ghs/lib/git-heal/hooks/"
    cp "$REPO_FILES/git-heal/hooks/post-index-change" "$WORK/ghs/lib/git-heal/hooks/"
    cp "$REPO_FILES/git-heal/hooks/post-merge" "$WORK/ghs/lib/git-heal/hooks/"
    cp "$REPO_FILES/git-heal/hooks/post-rewrite" "$WORK/ghs/lib/git-heal/hooks/"
    git -C "$WORK/ghs/root" init -q
    : >"$WORK/ghs/root/.git/index"
    : >"$WORK/ghs/root/.git/HEAD"
    # A widened-operand file in the fixture pins the mirror loop's row
    # set (#684 a a10): a dropped/typo'd operand name in status-core's
    # list silently under-reports lockout rows with nothing red.
    : >"$WORK/ghs/root/.git/ORIG_HEAD"
    : >"$WORK/ghs/devhome/.gitconfig"
    printf '%s\n' "$WORK/ghs/root" >"$WORK/ghs/projects.conf"
}
_ghs_run() {
    (
        PATH="$STUB:$PATH"
        export PATH NO_COLOR=1 GH_GITCONFIG="$WORK/ghs/devhome/.gitconfig"
        . "$UI_LIB"
        . "$LIB"
        # The entry's cross-lib sourcing (#777), mirrored: without the
        # resolver the section's pointer arm degrades (GHS_NO_GHC=1
        # drives that arm).
        if [ "${GHS_NO_GHC:-}" != 1 ]; then
            # shellcheck disable=SC1090
            . "$GH_CORE"
        fi
        DEFAULT_USER="$(id -un)"
        OPENCODE_USER=opencode-ghs-agent
        LIBDIR="$WORK/ghs/lib"
        PROJECTS_CONF="$WORK/ghs/projects.conf"
        status_section_git_heal
    ) 2>&1
}
_ghs_stage
_out=$(_ghs_run || true)
if printf '%s' "$_out" | grep -q "git-heal.*OFF — 'sudo opk git-heal on'" &&
    printf '%s' "$_out" | grep -q "lockout.*$WORK/ghs/root/.git/index is $(id -un)-owned — agent git" &&
    printf '%s' "$_out" | grep -q "lockout.*$WORK/ghs/root/.git/ORIG_HEAD is $(id -un)-owned"; then
    pass "git-heal section: OFF state renders the hint + lockout rows incl. a widened operand"
else
    fail "git-heal section: OFF/lockout rows broken (out=$(printf '%s' "$_out" | head -4))"
fi

# Parent-root registration (config.sh "parent of several projects"):
# the lockout enumeration recurses — a nested repo under the conf root
# renders its row (#674 a C3; the literal <root>/.git shape above
# still works, this pins the scan-root shape the on-sweep heals).
mkdir -p "$WORK/ghs/scan/deep/repo"
git -C "$WORK/ghs/scan/deep/repo" init -q
: >"$WORK/ghs/scan/deep/repo/.git/index"
: >"$WORK/ghs/scan/deep/repo/.git/HEAD"
printf '%s\n' "$WORK/ghs/scan" >"$WORK/ghs/projects.conf"
_out=$(_ghs_run || true)
if printf '%s' "$_out" | grep -q "lockout.*$WORK/ghs/scan/deep/repo/.git/index is $(id -un)-owned — agent git"; then
    pass "git-heal section: nested repo under a parent-root conf shows its lockout"
else
    fail "git-heal section: recursive lockout row missing (out=$(printf '%s' "$_out" | grep lockout | head -2))"
fi

# --- #777: pointer-file checkouts render lockout rows through the
# RESOLVED storage gitdir — the `opk status` twin of the git-heal sweep
# fix. Before it, a fully adopted host showed the state row and NO
# lockout (the same blindness the issue reports for `opk git-heal
# status`). Fixture: adopted-shape main + worktree pointer + relative
# (submodule-form) pointer under the scan root; the nonexistent-agent
# OPENCODE_USER above makes every present operand render.
mkdir -p "$WORK/ghs/ptstor"
git -C "$WORK/ghs/scan" init -q -b main ptmain
git -C "$WORK/ghs/scan/ptmain" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
mv "$WORK/ghs/scan/ptmain/.git" "$WORK/ghs/ptstor/ptmain.git"
printf 'gitdir: %s\n' "$WORK/ghs/ptstor/ptmain.git" >"$WORK/ghs/scan/ptmain/.git"
git --git-dir="$WORK/ghs/ptstor/ptmain.git" worktree add -q "$WORK/ghs/scan/ptwt" -b ptwb 2>/dev/null
printf '%s\n' "$WORK/ghs/scan" >"$WORK/ghs/projects.conf"
_out=$(_ghs_run || true)
if printf '%s' "$_out" | grep -q "lockout.*$WORK/ghs/ptstor/ptmain.git/index is $(id -un)-owned — agent git" &&
    ! printf '%s' "$_out" | grep -qF "$WORK/ghs/ptstor/ptmain.git/worktrees/"; then
    pass "git-heal section: a pointer checkout's lockout rows name the resolved gitdir (#777)"
else
    fail "git-heal section: pointer lockout rows (out=$(printf '%s' "$_out" | grep lockout | head -2)) (#777)"
fi
_ptr_n=$(printf '%s' "$_out" | grep -c "lockout.*$WORK/ghs/ptstor/ptmain.git/index is" || true)
if [ "$_ptr_n" = 1 ]; then
    pass "git-heal section: main and worktree pointers render one deduped row set (#777)"
else
    fail "git-heal section: pointer dedup (rows=$_ptr_n for one operand — 1 expected) (#777)"
fi
# The degrade arm: resolver unavailable (entry's sourcing failed) —
# ONE counted warn row names it, the classic rows still render, and
# the section never dies.
_out=$(GHS_NO_GHC=1 _ghs_run || true)
if printf '%s' "$_out" | grep -qF "pointer-file checkouts not checked — kit file sh/git-heal-core.sh" &&
    printf '%s' "$_out" | grep -qF "missing or outdated (fix: sudo opk update)" &&
    printf '%s' "$_out" | grep -q "lockout.*$WORK/ghs/scan/deep/repo/.git/index is $(id -un)-owned"; then
    pass "git-heal section: resolver unavailable degrades to a counted warn, classic rows stay (#777)"
else
    fail "git-heal section: resolver-degrade arm (out=$(printf '%s' "$_out" | grep -E 'git-heal|lockout' | head -3)) (#777)"
fi
printf '%s\n' "$WORK/ghs/root" >"$WORK/ghs/projects.conf"

# Wholesale-swap detection row (#653 family, #703): with the top-folder
# sticky gone, owner(.git) != owner(project dir) is the cheap
# after-the-fact detector. Discrimination via a stat stub keyed on the
# operand path: the gitdir reads "rogue"-owned, the project dir
# "devuser"-owned — the row must render with both names; the CONTROL
# (real stat, equal owners) renders nothing.
mkdir -p "$WORK/detstub"
cat >"$WORK/detstub/stat" <<'EOF'
#!/bin/sh
_p=$(eval "echo \${$#}")
case "$_p" in
*/.git) printf 'rogue\n' ;;
*) printf 'devuser\n' ;;
esac
EOF
chmod +x "$WORK/detstub/stat"
_out=$(
    (
        PATH="$WORK/detstub:$STUB:$PATH"
        export PATH NO_COLOR=1 GH_GITCONFIG="$WORK/ghs/devhome/.gitconfig"
        . "$UI_LIB"
        . "$LIB"
        # shellcheck disable=SC1090
        . "$GH_CORE"
        DEFAULT_USER="$(id -un)"
        OPENCODE_USER=opencode-ghs-agent
        LIBDIR="$WORK/ghs/lib"
        PROJECTS_CONF="$WORK/ghs/projects.conf"
        status_section_git_heal
    ) 2>&1 || true
)
if printf '%s' "$_out" | grep -q "\.git owner.*$WORK/ghs/root/\.git is rogue-owned while the project dir" &&
    printf '%s' "$_out" | grep -q "is devuser-owned — wholesale .git swap suspected"; then
    pass "git-heal section: owner-mismatch detection row renders (#703)"
else
    fail "git-heal section: detection row missing (#703; out=$(printf '%s' "$_out" | grep -F '.git owner' | head -2))"
fi
_out=$(_ghs_run || true)
if printf '%s' "$_out" | grep -qF '.git owner'; then
    fail "git-heal section: equal owners render no detection row (#703 control)"
else
    pass "git-heal section: equal owners render no detection row (#703 control)"
fi

# The mktemp failure path EXECUTES for the status-core twin too
# (#674 b D3): a dead TMPDIR drops the lockout rows with a loud warn,
# never silently — and the state row above still renders.
_out=$(TMPDIR="$WORK/ghs/no-such-tmp" _ghs_run || true)
if printf '%s' "$_out" | grep -qF 'lockout rows unavailable (mktemp failed)' &&
    printf '%s' "$_out" | grep -q "git-heal.*OFF — 'sudo opk git-heal on'"; then
    pass "git-heal section: mktemp failure is loud and non-fatal"
else
    fail "git-heal section: mktemp arm (out=$(printf '%s' "$_out" | head -3))"
fi

# The find partial-failure notice for the status-core twin (#674 c
# E4): an unreadable subtree under the conf root renders one honesty
# line while the readable repo's row still renders.
mkdir -p "$WORK/ghs/scan/locked"
chmod 000 "$WORK/ghs/scan/locked"
printf '%s\n' "$WORK/ghs/scan" >"$WORK/ghs/projects.conf"
_out=$(_ghs_run || true)
if printf '%s' "$_out" | grep -qF 'lockout rows may be incomplete under' &&
    printf '%s' "$_out" | grep -q "lockout.*$WORK/ghs/scan/deep/repo/.git/index"; then
    pass "git-heal section: unreadable subtree renders the notice, rows still render"
else
    fail "git-heal section: find-notice arm (out=$(printf '%s' "$_out" | grep -iE 'incomplete|lockout' | head -2))"
fi
chmod 700 "$WORK/ghs/scan/locked"
rmdir "$WORK/ghs/scan/locked"
printf '%s\n' "$WORK/ghs/root" >"$WORK/ghs/projects.conf"
git config -f "$WORK/ghs/devhome/.gitconfig" core.hooksPath "$WORK/ghs/lib/git-heal/hooks"
_out=$(_ghs_run || true)
if printf '%s' "$_out" | grep -q 'git-heal.*ON — developer git ops re-pin' &&
    ! printf '%s' "$_out" | grep -q 'is .*-owned — agent git'; then
    pass "git-heal section: ON state renders the active row, lockout turns transient"
else
    fail "git-heal section: ON rows broken (out=$(printf '%s' "$_out" | head -4))"
fi
if printf '%s' "$_out" | grep -q 'transient'; then
    pass "git-heal section: ON + dev-owned index classifies transient, not warn"
else
    fail "git-heal section: transient row missing on ON+dev-owned (out=$(printf '%s' "$_out" | head -4))"
fi
git config -f "$WORK/ghs/devhome/.gitconfig" core.hooksPath /dev/null
_out=$(_ghs_run || true)
if printf '%s' "$_out" | grep -q 'git-heal.*OFF — core.hooksPath holds a foreign value (/dev/null)'; then
    pass "git-heal section: foreign hooksPath is named, never silently overridden"
else
    fail "git-heal section: foreign row broken (out=$(printf '%s' "$_out" | head -4))"
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

# --- 6b. advisory feed parse under the hostile locale (#510 M4) ---------------------
# The freshness check decodes the whole advisory feed document; under a
# 7-bit locale the unpinned json.load used to degrade the row to "live
# check unavailable" when the decode died (an unread non-ASCII field on
# strict-stdin hosts) or when the id print died. Buffer read + guarded
# stdout reconfigure (#485 F22/F23 shapes). CANARY note (honesty): the
# shipped parser runs python3 -I (#249), whose -E strips
# PYTHONIOENCODING — under LC_ALL=C the stdin decode is surrogateescape,
# so with the ASCII ghsa_id the unpinned shape survives on C-locale
# hosts; the write side and the decode kill still discriminate on
# strict-stdin (exotic-locale) hosts, and the control arm proves the
# env's strict stdout. Control arm first (harness #510).
P510="$(hostile_stdio_python)"
if hostile_stdio_control "$P510"; then
    pass "control arm: strict 7-bit stdout kills the -I non-ASCII write (#510)"
else
    fail "control arm: hostile stdio not effective -- the #510 pins would pass vacuously"
fi
mkdir -p "$WORK/advbin510"
for _t in stat grep sed head cat python3; do
    ln -s "$(command -v "$_t")" "$WORK/advbin510/$_t" 2>/dev/null || true
done
printf '#!/bin/sh\ncat "%s"\n' "$WORK/adv-feed-nb.json" >"$WORK/advbin510/curl"
chmod 755 "$WORK/advbin510/curl"
cat >"$WORK/adv-feed-nb.json" <<'EOF'
[{"ghsa_id":"GHSA-9999-9999-9999","severity":"medium","html_url":"https://example/9",
  "summary":"Prüfung: nicht-ASCII Zusammenfassung",
  "vulnerabilities":[]}]
EOF
printf '#!/bin/sh\necho "opencode version 9.9.9"\n' >"$ADV/bin/opencode"
chmod 755 "$ADV/bin/opencode"
_adv_nb_rc=0
_out=$(
    export LC_ALL=C LANG=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 PYTHONIOENCODING=ascii
    PATH="$P510:$WORK/advbin510" # wrapper python3 + stub curl + externals
    export PATH NO_COLOR=1
    . "$UI_LIB"
    . "$LIB"
    LIBDIR="$ADV"
    VERSION=0.0.0
    OPENCODE_USER=opencode-no-such-user-424242
    status_section_advisories
) 2>&1 || _adv_nb_rc=$?
if printf '%s' "$_out" | grep -qF 'new advisory(ies) upstream, not yet in this kit: GHSA-9999-9999-9999' &&
    ! printf '%s' "$_out" | grep -qF 'live check unavailable'; then
    pass "advisories: non-ASCII feed parses under the 7-bit locale, freshness row renders (#510 M4)"
else
    fail "advisories feed parse must survive a non-ASCII summary under LC_ALL=C (rc=$_adv_nb_rc out=$(printf '%s' "$_out" | head -5)) (#510 M4)"
fi
rm -rf "${WORK:?}/advbin510" "${WORK:?}/adv-feed-nb.json"
rm -f "${ADV:?}/bin/opencode"

# -c source purity (#510, the argv-decode class): the -c command text
# reaches the interpreter as ARGV (locale codec + surrogateescape) --
# a 7-bit locale refuses non-ASCII command bytes at decode, before any
# code runs. The ticker's display glyphs ride \u escapes, comments
# stay "--"; all THREE -c regions are scanned (ticker, advisory ids,
# capability probe); ui text OUTSIDE them is deliberately UTF-8 and
# not scanned (doctor prefilter idiom: any 8th-bit byte).
for _510_range in \
    "/^    python3 -I -c '\$/,/^' \"\\\$1\"\$/p" \
    "/python3 -I -c 'import json,sys/,/ghsa_id\") or \"\"))'); then/p" \
    "/python3 -I -c 'import sys, threading, time'/p"; do
    if sed -n "$_510_range" "$LIB" |
        LC_ALL=C grep -q "$(printf '[\200-\377]')"; then
        fail "-c source must stay pure ASCII (range $_510_range) (#510 argv-decode class)"
        _510_bad=1
    fi
done
if [ "${_510_bad:-0}" = 0 ]; then
    pass "all three -c sources (ticker, advisory ids, capability probe) stay pure ASCII (#510 argv-decode class)"
else
    : # the per-range fail rows above carry the detail
fi

# --- 7. pairing guard (#413): a version-skewed entry/lib pairing dies loud -----------
# status is deliberately fail-soft (set -u only) — an undefined call
# does NOT abort, the report silently loses the section while the
# summary still prints. The guard refuses the skewed pairing before any
# section renders; it pins EVERY function the run needs, sections AND
# helpers (#452 — a helper-level skew would degrade rows silently
# behind a green summary). Both directions in fresh children +
# completeness riders over the entry's own calls and the lib's own
# definitions.
STATUS_ENTRY="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"
_pg_src="$(extract_func "$STATUS_ENTRY" status_pairing_guard)"
# comment-stripped copy of the guard source for the riders below
# (#452, conventions.md "Source-counting pins" over extracted blocks):
# a full-line comment inside the guard naming a function must not count.
_pg_src_s="$(printf '%s\n' "$_pg_src" | sed 's/^[[:space:]]*#.*$//')"
# rc-capture on the assignment (#499): a broken-non-empty extraction
# makes eval itself fatal in the child, and the bare assignment aborted
# the whole suite mid-run under set -e -- no tally, downstream pins
# unseen. The capture routes the child death into the assert's own row
# (the _pg_tr_rc idiom below).
_pg_full_rc=0
_pg_full=$(sh -c 'eval "$1"; . "$2"; status_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1) || _pg_full_rc=$?
_pg_tr_rc=0
_pg_tr_out="$(sh -c 'eval "$1"; status_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if [ "$_pg_full_rc" -eq 0 ] && printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every function defined) (#413)"
else
    fail "pairing guard must pass against the real lib (rc=$_pg_full_rc out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "function 'status_section_core' missing from status-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud before any section renders (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
if live_src "$STATUS_ENTRY" | grep -qF 'status_pairing_guard || exit 1'; then
    pass "status.sh wires the guard right after the resolver (#413)"
else
    fail "status.sh must call the guard after sourcing status-core.sh (#413)"
fi
# completeness rider (entry direction): every section the entry CALLS
# (the report order) must sit in the guard's list — a section added to
# the run order without the guard is exactly the wiring bug #413
# describes. The grep is BOUNDARY-ANCHORED (#452): plain -qF would find
# section names as substrings of helper names in the list and a dropped
# name would false-pass.
_pg_missing=""
_pg_entfns="$(grep -oE '^[[:space:]]*status_section_[a-z_0-9]+[[:space:]]*$' "$STATUS_ENTRY" |
    awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' | sort -u)"
# emptiness probe (#457, the #455 a C2 contract -- the sibling-note
# sweep): an empty extraction would run the loop zero times and the
# rider would pass vacuously.
[ -n "$_pg_entfns" ] || _pg_missing="(entry call extraction empty)"
for _fn in $_pg_entfns; do
    printf '%s\n' "$_pg_src_s" | grep -qE "(^|[[:space:]])$_fn([[:space:];]|\$)" ||
        _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "pairing guard list covers every section the entry calls (#413)"
else
    fail "sections called by status.sh but absent from the guard:$_pg_missing (#413)"
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
    fail "functions defined by status-core.sh but absent from the guard:$_pg_hmissing (#452, #455 a C2)"
fi
# B2 pin (#461 b): both wiring-abort guards (ui + core pairing) carry
# the repair hint — docs/reference/cli.md's exit-code row promises
# "the named function and the repair hint land on stderr with
# fix: sudo opk update"; before the fix no abort path printed any
# hint (the row lied). Comment-stripped count pin: exactly two
# refusal lines, each with the hint. Guarded count (#663 T3): grep -c
# exits 1 on zero matches and this suite runs set -e (unlike the
# e2e-sources count family) — the bare shape aborted the suite before
# any fail row, a non-counted red; the guard records 0 instead.
_pg_hint=$(live_src "$STATUS_ENTRY" | grep -c 'refusing to run (fix: sudo opk update)' || true)
if [ "$_pg_hint" -eq 2 ]; then
    pass "both wiring-abort guards print the repair hint (docs row is true) (#461 b B2)"
else
    fail "wiring-abort guards must carry the repair hint, count 2 (got $_pg_hint) (#461 b B2)"
fi

# Cross-lib protection-map rider (#456): status's cross-lib surface is
# call-site-guarded, not stubbed (fail-soft report — a missing helper
# must degrade into a COUNTED warn row, never a silent skip), so the
# sibling stub riders' shape does not fit. Same extraction, status's
# requirement: every lib function (ui.sh exempt — the entry's
# used-set guard owns that surface, rider in test-ui.sh) CALLED by
# entry or core and defined NOWHERE in them must have a literal
# `command -v <fn>` guard at its call surface. The two truncation
# gates this wave added are what make that true today (ddev-migrate
# trio, ddev_reshare_needed); git_status_row and xdg_open_real_exists
# carried theirs (0.0.46a F4, #199 a W3).
_xl_missing=""
_xl_combined="$(
    live_src "$STATUS_ENTRY"
    live_src "$LIB"
)"
[ -n "$_xl_combined" ] || _xl_missing="(stripped entry+core extraction empty)"
# What THIS RUN sources: the entry resolves git-check.sh and ui.sh;
# status-core resolves ddev-migrate.sh, ddev-handover.sh,
# ddev-hosts.sh, update-check.sh and advisories.sh behind file guards
# (#461 a Q3 extended the list past the original four — the rider once
# pinned the incompleteness green; #764 added git-protection-core.sh,
# the Git protection section's cross-lib; #777 added git-heal-core.sh,
# the git-heal section's pointer resolver); wsl-browser-bridge.sh's
# never-shadow probe is the optional surface the xdg call site
# command-v-guards. Not the whole sh/ glob — its wrapper-side scripts
# define shell hooks (ddev(), note()) that are not status's callable
# surface. Token extraction stays line-separated: a
# tr -d '[:space:]()' concatenates every definition into one token and
# the loop goes vacuous (the #456 sabotage cycle found exactly that on
# the install twin, L4).
for _xl_rel in opencode-permissions-kit-lib/sh/git-check.sh \
    opencode-permissions-kit-lib/sh/ddev-migrate.sh \
    opencode-permissions-kit-lib/sh/ddev-handover.sh \
    opencode-permissions-kit-lib/sh/ddev-hosts.sh \
    opencode-permissions-kit-lib/sh/update-check.sh \
    opencode-permissions-kit-lib/sh/advisories.sh \
    opencode-permissions-kit-lib/sh/git-protection-core.sh \
    opencode-permissions-kit-lib/sh/git-heal-core.sh \
    opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh; do
    _xl_lib="$SCRIPT_DIR/../../files/$_xl_rel"
    [ -f "$_xl_lib" ] || {
        _xl_missing="$_xl_missing (missing lib $_xl_rel)"
        continue
    }
    for _xl_fn in $(grep -oE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*\(\)' "$_xl_lib" | tr -d '()'); do
        printf '%s\n' "$_xl_combined" | grep -qE "(^|[^a-zA-Z0-9_])${_xl_fn}([^a-zA-Z0-9_(]|$)" ||
            continue
        printf '%s\n' "$_xl_combined" | grep -qE "(^|[|;[:space:]])${_xl_fn}\(\)" &&
            continue
        printf '%s\n' "$_xl_combined" | grep -qF "command -v $_xl_fn" ||
            _xl_missing="$_xl_missing $_xl_fn"
    done
done
if [ -z "$_xl_missing" ]; then
    pass "every lib call site carries a command-v guard or stub (#456)"
else
    fail "lib functions called unguarded (no command -v, no stub):$_xl_missing (#456)"
fi
# The truncation gates this wave added, verbatim: present-but-truncated
# libs must land in a COUNTED warn row, not a silent skip — the row
# text is the user-visible contract (fix hint, #165 idiom).
if printf '%s\n' "$(live_src "$LIB")" |
    grep -qF 'ui_kv_warn "db dumps" "not checked — kit file sh/ddev-migrate.sh outdated (fix: sudo opk update)"'; then
    pass "db-dump truncation gate renders a counted warn row (#456)"
else
    fail "db-dump truncation gate must render a counted warn row (#456)"
fi
if printf '%s\n' "$(live_src "$LIB")" |
    grep -qF 'ui_kv_warn "ddev share" "not checked — kit file sh/ddev-handover.sh outdated (fix: sudo opk update)"'; then
    pass "share-scan truncation gate renders a counted warn row (#456)"
else
    fail "share-scan truncation gate must render a counted warn row (#456)"
fi
# The #461 a Q3 sibling gates, same counted-warn contract: ddev-hosts,
# update-check, advisories — grep-pinned; the PATTERN itself is
# executed-pinned twice above (db-dump, share-scan). No hosts-gate
# executed twin: _st_ddev_win_hosts gates readiness behind
# [ -d /mnt/c ] absolute literals — a full-function drive is
# environment-dependent (vacuous on non-WSL CI, the L4b class), and
# weakening the extraction to reach the gate would pin a copy, not
# the code.
if printf '%s\n' "$(live_src "$LIB")" |
    grep -qF 'ui_kv_warn "kit update" "not checked — kit file sh/update-check.sh outdated (fix: sudo opk update)"'; then
    pass "update-check truncation gate renders a counted warn row (#461 a Q3)"
else
    fail "update-check truncation gate must render a counted warn row (#461 a Q3)"
fi
if printf '%s\n' "$(live_src "$LIB")" |
    grep -qF 'ui_kv_warn "advisories database" "not checked — kit file sh/advisories.sh outdated (fix: sudo opk update)"'; then
    pass "advisories truncation gate renders a counted warn row (#461 a Q3)"
else
    fail "advisories truncation gate must render a counted warn row (#461 a Q3)"
fi
if printf '%s\n' "$(live_src "$LIB")" |
    grep -qF 'ui_kv_warn "hosts (win)" "not checked — kit file sh/ddev-hosts.sh outdated (fix: sudo opk update)"'; then
    pass "hosts(win) truncation gate renders a counted warn row (#461 a Q3)"
else
    fail "hosts(win) truncation gate must render a counted warn row (#461 a Q3)"
fi
# Behavioral pins (L1, #456): the truncation gates EXECUTED, not just
# present — fresh child per gate, scratch tree carrying a present-but-
# truncated lib copy (the skew shape), controlled PATH (/usr/bin:/bin,
# conventions.md "Test sandbox" controlled-PATH rule: the extracted
# code must not see a contributor's nvm & co),
# the warn row observed the way production renders it (stdout).
_gate_scratch="$(work_new)"
mkdir -p "${_gate_scratch:?}/lib/sh" "${_gate_scratch:?}/call/sh" "${_gate_scratch:?}/call/management"
printf '# truncated copy: definitions gone\n' >"${_gate_scratch:?}/lib/sh/ddev-migrate.sh"
printf '# truncated copy: definitions gone\n' >"${_gate_scratch:?}/call/sh/ddev-handover.sh"
_gate_ui="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ui.sh"
_gate_db_out="$(PATH='/usr/bin:/bin' sh -c '
    . "$1"
    DEFAULT_USER=dev
    LIBDIR="$2/lib"
    PROJECTS_CONF=""
    eval "$3"
    _st_ddev_db_dumps
' x "$_gate_ui" "$_gate_scratch" "$(extract_func "$LIB" _st_ddev_db_dumps)" 2>&1)"
if printf '%s' "$_gate_db_out" | grep -qF 'sh/ddev-migrate.sh outdated'; then
    pass "db-dump gate fires on a truncated ddev-migrate.sh (executed, #456)"
else
    fail "db-dump gate must fire on a truncated ddev-migrate.sh (out=$_gate_db_out) (#456)"
fi
# S5 variant (#461 a): PARTIAL truncation — the trio (gap/projects/home)
# survives, only ddev_migrate_latest_dir (defined :651, ~500 lines after
# its caller) is gone. The pre-fix gate passed this shape and the gap
# probe rc-127'd inside $(…) with no counted row.
printf '# partial: trio present, callee gone\nddev_migrate_gap() { :; }\nddev_migrate_projects() { :; }\nddev_migrate_home() { :; }\n' \
    >"${_gate_scratch:?}/lib/sh/ddev-migrate.sh"
_gate_db2_out="$(PATH='/usr/bin:/bin' sh -c '
    . "$1"
    DEFAULT_USER=dev
    LIBDIR="$2/lib"
    PROJECTS_CONF=""
    eval "$3"
    _st_ddev_db_dumps
' x "$_gate_ui" "$_gate_scratch" "$(extract_func "$LIB" _st_ddev_db_dumps)" 2>&1)"
if printf '%s' "$_gate_db2_out" | grep -qF 'sh/ddev-migrate.sh outdated'; then
    pass "db-dump gate fires when ONLY ddev_migrate_latest_dir is missing (executed, #461 a S5)"
else
    fail "db-dump gate must fire on the latest_dir-only truncation (out=$_gate_db2_out) (#461 a S5)"
fi
# OPENCODE_USER names a nonexistent user so the uid guard enters the
# scan arm deterministically on every host (an environment-dependent
# pin is vacuous somewhere, L4b).
_gate_share_out="$(PATH='/usr/bin:/bin' sh -c '
    . "$1"
    OPENCODE_USER=nosuchopkuser456
    ST_CALL_DIR="$2/call/management"
    LIBDIR="$2/lib"
    PROJECTS_CONF=""
    eval "$3"
    _st_ddev_share_scan
' x "$_gate_ui" "$_gate_scratch" "$(extract_func "$LIB" _st_ddev_share_scan)" 2>&1)"
if printf '%s' "$_gate_share_out" | grep -qF 'sh/ddev-handover.sh outdated'; then
    pass "share-scan gate fires on a truncated ddev-handover.sh (executed, #456)"
else
    fail "share-scan gate must fire on a truncated ddev-handover.sh (out=$_gate_share_out) (#456)"
fi

# --- 8. Git protection section (issue #764 topic 2) ---------------------------------
# status_section_git_protection at function level: the real status-core
# plus the real git-protection core, the ui helpers stubbed to tagged
# lines (the tag IS the severity), a scratch conf / storage /
# install.conf, and the lsattr marker stub of test-git-protection-core
# (the i flag reads a "<path>.nailed" marker — the real flag needs
# root to set). Every row the section renders carries a fix command
# or is a state row; the not-enabled states are COUNTED warnings with
# no project rows (maintainer decision, #764).
GP_CORE="$REPO_FILES/sh/git-protection-core.sh"
_gpc_work="$(work_new)"
mkdir -p "$_gpc_work/bin" "$_gpc_work/roots/r1/sub" "$_gpc_work/roots/r2" "$_gpc_work/storage"
cat >"$_gpc_work/bin/lsattr" <<'EOF'
#!/bin/sh
if [ -e "$1.nailed" ]; then
    printf -- "----i---------e------- %s\n" "$1"
else
    printf -- "--------------e------- %s\n" "$1"
fi
EOF
chmod 755 "$_gpc_work/bin/lsattr"
_gpc_repo() { # a scratch repo with one commit (identity inline)
    mkdir -p "$1"
    git -C "$1" init -q
    printf 'hello\n' >"$1/file.txt"
    git -C "$1" add file.txt
    git -C "$1" -c user.email=t@e.st -c user.name=t commit -qm c1
}
_gpc_repo "$_gpc_work/roots/r1/top"
_gpc_repo "$_gpc_work/roots/r1/sub/nested"
_gpc_repo "$_gpc_work/roots/r1/unnailedp"
rm -rf "${_gpc_work:?}/roots/r1/unnailedp/.git"
mkdir -p "$_gpc_work/storage/unnailedp.git" "$_gpc_work/storage/orphan1.git"
printf 'gitdir: %s\n' "$_gpc_work/storage/unnailedp.git" >"$_gpc_work/roots/r1/unnailedp/.git"
mkdir -p "$_gpc_work/roots/r1/wtreg/.git"
_gpc_repo "$_gpc_work/roots/r2/nailedp"
rm -rf "${_gpc_work:?}/roots/r2/nailedp/.git"
mkdir -p "$_gpc_work/storage/nailedp.git"
printf 'gitdir: %s\n' "$_gpc_work/storage/nailedp.git" >"$_gpc_work/roots/r2/nailedp/.git"
touch "$_gpc_work/roots/r2/nailedp/.git.nailed"
printf '%s\n' "$_gpc_work/roots/r1" >"$_gpc_work/projects.conf"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" "$_gpc_work/storage" >"$_gpc_work/install.conf"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=none\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$_gpc_work/install-declined.conf"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" "$_gpc_work/no-such-storage" >"$_gpc_work/install-nodir.conf"
_gpc_run() { # <real|none|trunc> <install.conf> [VAR=VALUE ...] -> rows on stdout, stderr apart
    _gpc_mode=$1 _gpc_ic=$2
    shift 2
    (
        PATH="$_gpc_work/bin:$STUB:$PATH"
        export PATH NO_COLOR=1
        # env carries the scratch seams (plus the caller's extras, if
        # any) into a fresh sh mirroring status.sh's own shell flags:
        # set -u yes, set -e no (the report is fail-soft by design).
        env GP_CONF="$_gpc_work/projects.conf" GP_CONF_RELAX=1 INSTALL_CONF="$_gpc_ic" "$@" sh -cu '
            . "$1"
            case "$2" in
                real) . "$3" ;;
                trunc) _gp_storage() { :; } ;;
            esac
            ui_section() { echo "section: $*"; }
            ui_kv() { echo "kv: $1 $2"; }
            ui_kv_ok() { echo "kv-ok: $1 $2"; }
            ui_kv_warn() { echo "kv-warn: $1 $2"; }
            ui_kv_bad() { echo "kv-bad: $1 $2"; }
            ui_detail() { echo "detail: $*"; }
            status_section_git_protection
        ' _ "$LIB" "$_gpc_mode" "$GP_CORE"
    ) 2>"$_gpc_work/err"
}
_gpc_tag() { # <tag> -> number of rows carrying it
    printf '%s\n' "$_gpc_out" | grep -c "^$1: " || true
}

# a) cross-lib call-site guard: no core at all, and a PARTIAL skew
# (the #461 a S5 shape — only _gp_storage survives) — both land in the
# COUNTED warn row, never a silently dropped section (an undefined
# call would rc-127 under status.sh's set -u without set -e). The
# literal spans the row's dq-splice wrap: the unwrapped phrase pinned
# whole is the execution proof that the wrap is byte-identical.
_gpc_full='not checked — kit file sh/git-protection-core.sh missing or outdated (fix: sudo opk update)'
_gpc_out=$(_gpc_run none "$_gpc_work/install.conf" || true)
if printf '%s' "$_gpc_out" | grep -qF "kv-warn: git-protection $_gpc_full" &&
    [ "$(_gpc_tag kv-warn)" = 1 ] && [ "$(_gpc_tag kv-bad)" = 0 ]; then
    pass "git-protection section: missing core renders the counted warn row (#764)"
else
    fail "git-protection section: missing core (out=$_gpc_out)"
fi
_gpc_out=$(_gpc_run trunc "$_gpc_work/install.conf" || true)
if printf '%s' "$_gpc_out" | grep -qF "kv-warn: git-protection $_gpc_full" &&
    [ "$(_gpc_tag kv-warn)" = 1 ]; then
    pass "git-protection section: a partially skewed core (one helper left) is caught too (#764)"
else
    fail "git-protection section: partial skew (out=$_gpc_out)"
fi

# b) not enabled: ONE counted warning naming the enable command, no
# project rows — the classic layout is not a finding before the
# opt-in, the open arm is.
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$_gpc_work/install-nokey.conf"
_gpc_out=$(_gpc_run real "$_gpc_work/install-nokey.conf" || true)
if printf '%s' "$_gpc_out" | grep -qF 'kv-warn: git-protection not configured — every project keeps a classic .git' &&
    printf '%s' "$_gpc_out" | grep -qF 'detail: run: sudo opk git-protection on' &&
    [ "$(_gpc_tag kv-warn)" = 1 ] && [ "$(_gpc_tag kv-bad)" = 0 ] &&
    ! printf '%s' "$_gpc_out" | grep -qF 'classic .git (unprotected'; then
    pass "git-protection section: not configured = one counted warning, no project rows (#764)"
else
    fail "git-protection section: not-configured arm (out=$_gpc_out)"
fi
_gpc_full='declined (GITDIR_STORAGE=none) — every project keeps a classic .git (wholesale swap possible)'
_gpc_out=$(_gpc_run real "$_gpc_work/install-declined.conf" || true)
if printf '%s' "$_gpc_out" | grep -qF "kv-warn: git-protection $_gpc_full" &&
    printf '%s' "$_gpc_out" |
    grep -qF 'detail: run: sudo opk git-protection on (the command replaces the decline marker)' &&
    [ "$(_gpc_tag kv-warn)" = 1 ] && [ "$(_gpc_tag kv-bad)" = 0 ] &&
    ! printf '%s' "$_gpc_out" | grep -qF 'classic .git (unprotected'; then
    pass "git-protection section: declined = one counted warning naming the one-command enable (#764)"
else
    fail "git-protection section: declined arm (out=$_gpc_out)"
fi

# S1 (#775 a): a refused enumeration (rc 2) replaces the OK-claim row
# with a counted warn — `opk status` never reports health over a sweep
# that could not enumerate (the broken-python3 stub drives the
# refusal; the notes rows below the warn name the cause).
mkdir -p "$_gpc_work/badpy"
printf '#!/bin/sh\nexit 1\n' >"$_gpc_work/badpy/python3"
chmod 755 "$_gpc_work/badpy/python3"
_gpc_out=$(_gpc_run real "$_gpc_work/install.conf" PATH="$_gpc_work/badpy:$PATH" || true)
if [ "$(_gpc_tag kv-warn)" -ge 1 ] &&
    printf '%s' "$_gpc_out" | grep -qF 'project rows unavailable — the enumeration refused' &&
    ! printf '%s' "$_gpc_out" | grep -qF 'kv-ok: git-protection ON'; then
    pass "git-protection section: a refused enumeration renders the counted warn, no OK claim (#775 a S1)"
else
    fail "git-protection section: refused-enum arm (out=$_gpc_out)"
fi
# B1 (#775 b): the refused enumeration must also skip the ORPHAN pass
# — the reference list stayed empty, and running the pass would label
# every storage child (the fixture has three) "unreferenced", a
# positive claim over a tree the run could not enumerate.
if ! printf '%s' "$_gpc_out" | grep -qF 'unreferenced storage entry'; then
    pass "git-protection section: no orphan claims over a refused enumeration (#775 b B1)"
else
    fail "git-protection section: orphan rows over refused enumeration (out=$_gpc_out)"
fi

# c) enabled with deviations: the state row counts the protected
# projects, classic rows are alerts and unnailed rows warnings — each
# with its command and path — and no per-project green row, no
# worktree-registration line and nothing on stderr (the core's notes
# re-render as detail rows). `${_gpc_sto:?}` inside the expected
# string: the sandbox floor walks message prose on live lines too
# (#630) — a literal `rm` next to a `"$VAR/suffix"` in one statement
# reads as an unguarded deletion.
_gpc_r1="$_gpc_work/roots/r1"
_gpc_sto="$_gpc_work/storage"
_gpc_out=$(_gpc_run real "$_gpc_work/install.conf" || true)
if printf '%s' "$_gpc_out" | grep -qF "kv: git-protection ON — storage $_gpc_sto; no project under the configured roots is nailed yet" &&
    printf '%s' "$_gpc_out" | grep -qF "kv-bad: $_gpc_r1/top classic .git (unprotected -- the mv .git arm)" &&
    printf '%s' "$_gpc_out" | grep -qF " -- run: sudo opk git-protection adopt $_gpc_r1/top" &&
    printf '%s' "$_gpc_out" | grep -qF " -- run: sudo opk git-protection adopt $_gpc_r1/sub/nested" &&
    printf '%s' "$_gpc_out" |
    grep -qF "kv-warn: $_gpc_r1/unnailedp pointer, NOT nailed (run: sudo opk git-protection nail $_gpc_r1/unnailedp)" &&
    [ "$(_gpc_tag kv-bad)" = 2 ] && [ "$(_gpc_tag kv-warn)" = 1 ] && [ "$(_gpc_tag kv-ok)" = 0 ] &&
    ! printf '%s' "$_gpc_out" | grep -qF 'pointer + nailed' &&
    ! printf '%s' "$_gpc_out" | grep -qF 'worktree registration' &&
    printf '%s' "$_gpc_out" | grep -qF "kv: $_gpc_sto/orphan1.git unreferenced storage entry" &&
    printf '%s' "$_gpc_out" | grep -qF "detail: inspect, then remove: sudo rm -rf ${_gpc_sto:?}/orphan1.git" &&
    [ ! -s "$_gpc_work/err" ]; then
    pass "git-protection section: enabled rows = state + alert/warn deviations with commands + INFO orphans (#764)"
else
    fail "git-protection section: enabled arm (out=$_gpc_out err=$(cat "${_gpc_work:?}/err"))"
fi

# d) all protected: one green state row carrying the count, no finding.
printf '%s\n' "$_gpc_work/roots/r2" >"$_gpc_work/projects.conf"
_gpc_out=$(_gpc_run real "$_gpc_work/install.conf" || true)
if printf '%s' "$_gpc_out" |
    grep -qF "kv-ok: git-protection ON — 1 project(s) on the nailed pointer layout (storage $_gpc_sto)" &&
    [ "$(_gpc_tag kv-ok)" = 1 ] && [ "$(_gpc_tag kv-warn)" = 0 ] && [ "$(_gpc_tag kv-bad)" = 0 ] &&
    ! printf '%s' "$_gpc_out" | grep -qF 'nailedp pointer'; then
    pass "git-protection section: an all-nailed root renders one green state row, no per-project rows (#764)"
else
    fail "git-protection section: all-nailed arm (out=$_gpc_out)"
fi
printf '%s\n' "$_gpc_work/roots/r1" >"$_gpc_work/projects.conf"

# d2) enabled with NO pointer into the storage (#765 a M1): the
# reference list is pre-created by the section — _gp_projects only
# appends to it — so a healthy host renders no "check skipped"
# warning, and a storage entry nothing points at is listed (the
# orphan pass used to skip exactly when no live pointer existed).
mkdir -p "$_gpc_work/roots/r7"
printf '%s\n' "$_gpc_work/roots/r7" >"$_gpc_work/projects.conf"
_gpc_out=$(_gpc_run real "$_gpc_work/install.conf" || true)
printf '%s\n' "$_gpc_work/roots/r1" >"$_gpc_work/projects.conf"
if printf '%s' "$_gpc_out" |
    grep -qF "kv: git-protection ON — storage $_gpc_sto; no project under the configured roots is nailed yet" &&
    ! printf '%s' "$_gpc_out" | grep -qF 'check skipped' &&
    [ "$(_gpc_tag kv-warn)" = 0 ] && [ "$(_gpc_tag kv-bad)" = 0 ] &&
    printf '%s' "$_gpc_out" | grep -qF "kv: $_gpc_sto/orphan1.git unreferenced storage entry" &&
    printf '%s' "$_gpc_out" | grep -qF "inspect, then remove: sudo rm -rf ${_gpc_sto:?}/orphan1.git"; then
    pass "git-protection section: no pointer into the storage -> no skip warning, orphan listed (#765 a M1)"
else
    fail "git-protection section: zero-pointer arm (out=$_gpc_out)"
fi

# d3) the core's own scan note carries one prefix (#765 a M3). Root-
# hermetic: a root suite user reads the 000 subtree, so the note
# never fires there.
if [ "$(id -u)" != 0 ]; then
    mkdir -p "$_gpc_work/roots/r8/locked/sub"
    chmod 000 "$_gpc_work/roots/r8/locked/sub"
    printf '%s\n' "$_gpc_work/roots/r8" >"$_gpc_work/projects.conf"
    _gpc_out=$(_gpc_run real "$_gpc_work/install.conf" || true)
    chmod 755 "$_gpc_work/roots/r8/locked/sub"
    printf '%s\n' "$_gpc_work/roots/r1" >"$_gpc_work/projects.conf"
    if printf '%s' "$_gpc_out" |
        grep -qF 'detail: git-protection: scan may be incomplete under' &&
        ! printf '%s' "$_gpc_out" | grep -qF 'git-protection: git-protection:' &&
        [ ! -s "$_gpc_work/err" ]; then
        pass "git-protection section: the core's scan note renders with one prefix (#765 a M3)"
    else
        fail "git-protection section: doubled-prefix arm (out=$_gpc_out)"
    fi
else
    echo "  SKIP  scan-note prefix arm needs a non-root suite user (#765 a M3)"
fi

# e) enabled but the storage dir is gone: a counted row, and the
# classic command becomes `on` (adopt would refuse).
_gpc_out=$(_gpc_run real "$_gpc_work/install-nodir.conf" || true)
if printf '%s' "$_gpc_out" |
    grep -qF "kv-warn: git-protection storage missing: $_gpc_work/no-such-storage — pointer projects cannot" &&
    printf '%s' "$_gpc_out" | grep -qF 'detail: re-create it: sudo opk git-protection on' &&
    printf '%s' "$_gpc_out" | grep -qF "kv-bad: $_gpc_r1/top classic .git (unprotected -- the mv .git arm) -- run: sudo opk git-protection on" &&
    ! printf '%s' "$_gpc_out" | grep -qF 'git-protection adopt' &&
    ! printf '%s' "$_gpc_out" | grep -qF 'unreferenced storage entry'; then
    pass "git-protection section: a missing storage dir warns, switches the classic command to on, lists no orphans (#764)"
else
    fail "git-protection section: missing-storage arm (out=$_gpc_out)"
fi

# f) the core's stderr never leaks raw (the --short one-line
# contract): a refused conf line re-renders as a detail row. Enabled
# conf — only the enabled arm reaches the classification pass whose
# notes this captures.
printf 'relative/path\n%s\n' "$_gpc_work/roots/r1" >"$_gpc_work/projects.conf"
_gpc_out=$(_gpc_run real "$_gpc_work/install.conf" || true)
printf '%s\n' "$_gpc_work/roots/r1" >"$_gpc_work/projects.conf"
if printf '%s' "$_gpc_out" | grep -qF 'detail: git-protection: refused-conf not an absolute root' &&
    [ ! -s "$_gpc_work/err" ]; then
    pass "git-protection section: the core's stderr re-renders as a detail row, stderr stays empty (#764)"
else
    fail "git-protection section: stderr capture (out=$_gpc_out err=$(cat "$_gpc_work/err"))"
fi

# g) a failed scratch allocation is a counted row, never a dropped
# section (the #674 b D3 twin — TMPDIR points nowhere, mktemp -d dies).
_gpc_out=$(_gpc_run real "$_gpc_work/install.conf" "TMPDIR=$_gpc_work/no-such-dir" || true)
if printf '%s' "$_gpc_out" | grep -qF 'kv-warn: git-protection project rows unavailable (mktemp failed)' &&
    [ "$(_gpc_tag kv-bad)" = 0 ]; then
    pass "git-protection section: mktemp failure degrades into a counted row (#764)"
else
    fail "git-protection section: mktemp arm (out=$_gpc_out)"
fi

# h) entry wiring: status.sh resolves the core checkout-first (the
# ui.sh / git-check.sh resolver shape) — a deployed-first lookup would
# run an older core against a checkout's status-core.
if live_src "$STATUS_ENTRY" | grep -qF 'GIT_PROTECTION_CORE="$ST_CALL_DIR/../sh/git-protection-core.sh"' &&
    live_src "$STATUS_ENTRY" | grep -qF '. "$GIT_PROTECTION_CORE"'; then
    pass "status.sh resolves sh/git-protection-core.sh checkout-first and sources it (#764)"
else
    fail "status.sh must resolve + source sh/git-protection-core.sh checkout-first (#764)"
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

# --- sweep floor: status-core's four sites run isolated (#249; the
# tree-wide absence pin in test-update-core.sh is the ceiling) --------
_pc=$(live_src "$LIB" | grep -c 'python3 -I' || true)
if [ "${_pc:-0}" -ge 4 ]; then
    pass "sweep floor: status-core.sh python3 calls run -I ($_pc site(s), #249)"
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

# --- #660 M6 wiring: every projects.conf reader in this lib skips '#'-lines ------
# The projects-section pin (test-status.sh) covers the false-red arm
# behaviorally; the share/hosts loops and the db-dump root argv have no
# observable row change (comments already skipped silently via [ -d ]) --
# their comment tolerance is pinned at the wiring level so a future gate
# reorder cannot flip an annotation into a verdict or an operand. The
# one-line case tail is identical in all three loops; the db-dump argv
# leg is a COUNT pin on purpose (#670 a L4): the quote-free `grep -v -e`
# fragment also matches the systemd-private filter line (status-core's
# `done | grep -v -e '/systemd-private-' ...`) — presence alone stayed
# green over a reverted db-dump line, == 2 discriminates (a regressed
# dbdump line loses the `grep -v -e` spelling entirely).
_pc6=$(live_src "$LIB" | grep -cF "in '#'*) continue ;; esac" || true)
_pc6b=$(live_src "$LIB" | grep -cF 'grep -v -e' || true)
if [ "${_pc6:-0}" = 3 ] &&
    [ "${_pc6b:-0}" = 2 ] &&
    live_src "$LIB" | grep -qF 'grep -cv -e'; then
    pass "projects/share/hosts loops, count and db-dump argv exclude '#'-lines (#660 M6)"
else
    fail "every projects.conf reader must exclude '#'-lines (loops: ${_pc6:-0} of 3, grep -v -e: ${_pc6b:-0} of 2) (#660 M6)"
fi

suite_done
