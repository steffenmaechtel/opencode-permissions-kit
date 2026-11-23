#!/bin/sh
# Unit tests for the git-protection subsystem (issue #704, the O4
# pointer layout):
#
#   files/opencode-permissions-kit-lib/sh/git-protection-core.sh --
#     the `opk git-protection` logic: reader-gate arms, storage
#     resolution (env / conf / sibling derivation / declined marker),
#     persist + drop on a scratch install.conf, project
#     classification (classic / nailed / unnailed / foreign-pointer /
#     worktree-reg), the atomic migrate (happy path, skip arms,
#     collision suffix, worktree repair, rollback), the storage entry
#     naming rule (#764: <parent>-<basename>, its fallbacks), nail gating
#     (storage prefix, dev ownership, chattr failure, lsattr verify),
#     revert (kit-owned only, happy path), status rc semantics, the
#     report rows (#764: fix command per storage state, unreferenced
#     storage entries, the pointer-reference list), and
#     the CLI surface (usage rc 64, pre-hop path validation, the
#     loop-guarded sudo re-exec shape).
#
# Root code runs UNPRIVILEGED here (the heal-index-head pattern): the
# core's root gate is relaxed via its documented GP_ALLOW_NONROOT
# override and chowns target the running user (permitted no-op
# chowns). chattr/lsattr are PATH STUBS (the controlled-PATH rule):
# a per-file ".nailed" marker records +i/-i, lsattr renders the i
# flag off the same marker — the real two-uid chattr behavior is
# pinned by the Phase A harness (issue #704's artifacts) and the e2e
# suites. The storage leg of heal-index-head and the hook hint live
# in test-git-heal-core.sh (the suites owning those files).
# Run: sh tests/unit/test-git-protection-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_FILES="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib"
CORE="$REPO_FILES/sh/git-protection-core.sh"

# Shared harness (issue #394): pass/fail/assert_eq + the work registry
# (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

command -v git >/dev/null 2>&1 || {
    echo "git is required for these tests" >&2
    exit 1
}

CONF="$WORK/projects.conf"
IC="$WORK/install.conf"

# --- controlled PATH: real tools + the chattr/lsattr/sudo stubs -----------------
mkdir -p "$WORK/bin"
PATH="$WORK/bin:/usr/bin:/bin"
export PATH

# chattr stub: records every call into $GP_STUB_LOG; +i/-i maintain a
# per-file "<path>.nailed" marker (the state lsattr renders).
# GP_CHATTR_FAIL=1 makes every call fail (the fstype-degradation arm).
cat >"$WORK/bin/chattr" <<'EOF'
#!/bin/sh
printf 'chattr %s\n' "$*" >>"${GP_STUB_LOG:?}"
if [ "${GP_CHATTR_FAIL:-}" = "1" ]; then
    echo "chattr: Operation not supported (stub)" >&2
    exit 1
fi
case "$1" in
    +i) touch "$2.nailed" ;;
    -i) rm -f "$2.nailed" ;;
esac
exit 0
EOF
# lsattr stub: renders the immutable flag off the same marker.
# GP_LSATTR_LIE=1 never shows i (the chattr-vs-lsattr verify arm).
cat >"$WORK/bin/lsattr" <<'EOF'
#!/bin/sh
if [ "${GP_LSATTR_LIE:-}" != "1" ] && [ -e "$1.nailed" ]; then
    printf '%s\n' "-----i---------e------- $1"
else
    printf '%s\n' "--------------e------- $1"
fi
EOF
# sudo stub: records argv and succeeds — the re-exec shape assert
# (never elevates; the loop-guard arm relies on exactly that).
cat >"$WORK/bin/sudo" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"${GP_SUDO_LOG:?}"
exit 0
EOF
chmod 755 "$WORK/bin/chattr" "$WORK/bin/lsattr" "$WORK/bin/sudo"
GP_STUB_LOG="$WORK/chattr.log"
GP_SUDO_LOG="$WORK/sudo.log"
export GP_STUB_LOG GP_SUDO_LOG

_ui_stubs() {
    ui_info() { echo "info: $*"; }
    ui_success() { echo "success: $*"; }
    ui_detail() { echo "detail: $*"; }
    ui_warn() { echo "warn: $*"; }
    ui_error() { echo "error: $*" >&2; }
    ui_section() { echo "section: $*"; }
    ui_kv() { echo "kv: $1 $2"; }
    ui_kv_ok() { echo "kv-ok: $1 $2"; }
    ui_kv_warn() { echo "kv-warn: $1 $2"; }
    ui_kv_bad() { echo "kv-bad: $1 $2"; }
    ui_confirm() {
        echo "confirm: $*"
        return 0
    }
}

# _core_run <expr>: ui stubs + core sourced with the scratch env
# (GP_ALLOW_NONROOT relaxes the root gate; GP_CONF_RELAX lets the
# /tmp scratch zones pass the reader gate's system-path arms).
_core_run() { # <expr>
    (
        _ui_stubs
        . "$CORE"
        GP_STORAGE="$WORK/storage"
        GP_CONF="$CONF"
        GP_INSTALL_CONF="$IC"
        GP_ALLOW_NONROOT=1
        GP_CONF_RELAX=1
        export GP_STORAGE GP_CONF GP_INSTALL_CONF GP_ALLOW_NONROOT GP_CONF_RELAX
        eval "$1"
    ) 2>&1
}

# _mkrepo <dir>: a real scratch repo with one commit (identity inline
# — the e2e authoring rule: never rely on a global git identity).
_mkrepo() {
    mkdir -p "$1"
    git -C "$1" init -q
    printf 'hello\n' >"$1/file.txt"
    git -C "$1" add file.txt
    git -C "$1" -c user.email=t@e.st -c user.name=t commit -qm c1
}

printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
mkdir -p "$WORK/roots/r1"

# --- 0. every core function is defined by sourcing (#754 a B10) ---------------------
# The three-registration-points rule (AGENTS.md, Testing): entry guard
# (bin/opk's git_protection_cli check) + this list + the derived count.
_defs="_gp_libdir _gp_var _gp_devuser _gp_agentuser _gp_group _gp_root_ok
_gp_conf_path _gp_storage _gp_storage_derive _gp_enabled _gp_nosym _gp_storage_init
_gp_persist_storage
_gp_drop_storage _gp_has_i _gp_devgit _gp_verify _gp_rollback _gp_worktrees
_gp_heal_gitdir _gp_pform_ok _gp_storage_sane _gp_unnest _gp_conf_root_p
_gp_entry_name _gp_migrate_one _gp_nail_one _gp_revert_one _gp_projects _gp_rows
_gp_disp _gp_orphan_rows _gp_revert_all
_git_protection_status _git_protection_on _git_protection_adopt
_git_protection_nail _gp_nail_path _git_protection_revert
_git_protection_off git_protection_cli"
_missing=""
for _fn in $_defs; do
    sh -c '. "$1" && command -v "$2" >/dev/null' _ "$CORE" "$_fn" 2>/dev/null ||
        _missing="$_missing $_fn"
done
_ndefs="$(printf '%s\n' $_defs | wc -w | tr -d ' ')"
if [ -z "$_missing" ]; then
    pass "all $_ndefs core functions defined by sourcing (#754 a B10)"
else
    fail "functions missing after sourcing:$_missing"
fi

# --- 1. sourcing purity + the CLI surface ----------------------------------------

_purity_rc=0
_purity_out=$(sh -c '. "$1"' _ "$CORE" 2>&1) || _purity_rc=$?
if [ "$_purity_rc" = 0 ] && [ -z "$_purity_out" ]; then
    pass "core: sourcing git-protection-core.sh runs nothing, prints nothing"
else
    fail "core: sourcing must be side-effect free (rc=$_purity_rc out=$_purity_out)"
fi

_rc=0
_out=$(_core_run 'git_protection_cli bogus' </dev/null) || _rc=$?
if [ "$_rc" = 64 ] && printf '%s' "$_out" | grep -qF 'usage: opk git-protection'; then
    pass "cli: unknown subcommand is a loud usage error (rc 64)"
else
    fail "cli: usage arm (rc=$_rc out=$_out)"
fi

_rc=0
_out=$(_core_run 'git_protection_cli' </dev/null) || _rc=$?
if [ "$_rc" = 64 ]; then
    pass "cli: no subcommand is a usage error"
else
    fail "cli: empty-cmd arm (rc=$_rc)"
fi

_rc=0
_out=$(_core_run 'git_protection_cli adopt' </dev/null) || _rc=$?
if [ "$_rc" = 64 ] && printf '%s' "$_out" | grep -qF 'adopt <path>'; then
    pass "cli: adopt without a path is a usage error"
else
    fail "cli: adopt arity arm (rc=$_rc out=$_out)"
fi

_rc=0
_out=$(_core_run 'git_protection_cli adopt relative/path' </dev/null) || _rc=$?
if [ "$_rc" = 64 ] && printf '%s' "$_out" | grep -qF 'absolute project path'; then
    pass "cli: adopt with a relative path refused before elevation"
else
    fail "cli: adopt path-form arm (rc=$_rc out=$_out)"
fi

_rc=0
_out=$(_core_run 'git_protection_cli revert' </dev/null) || _rc=$?
if [ "$_rc" = 64 ] && printf '%s' "$_out" | grep -qF -- 'revert <path>|--all'; then
    pass "cli: revert without argument is a usage error"
else
    fail "cli: revert arity arm (rc=$_rc out=$_out)"
fi

_rc=0
_out=$(_core_run 'git_protection_cli revert relative' </dev/null) || _rc=$?
if [ "$_rc" = 64 ] && printf '%s' "$_out" | grep -qF -- '--all or an absolute'; then
    pass "cli: revert with a relative path refused"
else
    fail "cli: revert path-form arm (rc=$_rc out=$_out)"
fi

_rc=0
_out=$(_core_run 'git_protection_cli nail a b' </dev/null) || _rc=$?
if [ "$_rc" = 64 ]; then
    pass "cli: nail takes at most one path"
else
    fail "cli: nail arity arm (rc=$_rc)"
fi

# status needs no root: with the root gate armed (no GP_ALLOW_NONROOT)
# status still runs — here the not-configured shape: nothing is
# persisted, so the storage row is the counted "not configured" warn
# naming the DERIVED default (never a configured-looking path, #764
# topic 3), and no project is actionable (the actionable arm is
# section 8; rc 0 here: r1 is empty).
printf '%s\n' "$WORK/roots/r1" >"$CONF"
rc=0
out=$(
    GP_CONF="$CONF" GP_INSTALL_CONF="$IC" GP_CONF_RELAX=1 sh -c '
        . "$1"
        ui_section() { echo "section: $*"; }
        ui_kv() { echo "kv: $1 $2"; }
        ui_kv_ok() { echo "kv-ok: $1 $2"; }
        ui_kv_warn() { echo "kv-warn: $1 $2"; }
        ui_kv_bad() { echo "kv-bad: $1 $2"; }
        ui_detail() { echo "detail: $*"; }
        ui_error() { echo "error: $*" >&2; }
        git_protection_cli status
    ' _ "$CORE" 2>&1
) || rc=$?
if [ "$rc" = 0 ] &&
    printf '%s' "$out" | grep -qF "kv-warn: storage not configured (derived default: $WORK/roots/gitdirs)" &&
    printf '%s' "$out" | grep -qF 'run: sudo opk git-protection on'; then
    pass "cli: status runs unprivileged (no elevation, no GP_ALLOW_NONROOT) — derived default is not configured (#764)"
else
    fail "cli: status unprivileged arm (rc=$rc out=$out)"
fi

# The loop guard (#479 a F24 shape): a sudo that does not elevate
# must not re-exec forever — the marker the re-exec carries refuses.
rc=0
out=$(
    GP_CONF="$CONF" GP_INSTALL_CONF="$IC" OPK_GITPROTECT_ROOT=1 sh -c '
        . "$1"
        ui_error() { echo "ERR: $*" >&2; }
        git_protection_cli on
    ' _ "$CORE" </dev/null 2>&1
) || rc=$?
if [ "$rc" = 1 ] && printf '%s' "$out" | grep -qF 'sudo did not elevate'; then
    pass "cli: loop guard refuses a non-elevating sudo (marker)"
else
    fail "cli: loop-guard arm (rc=$rc out=$out)"
fi

# The re-exec shape: non-root, no marker, root gate armed → exactly one
# sudo spawn with env marker + the subcommand riding along.
: >"$GP_SUDO_LOG"
rc=0
out=$(
    GP_CONF="$CONF" GP_INSTALL_CONF="$IC" sh -c '
        . "$1"
        ui_error() { echo "ERR: $*" >&2; }
        git_protection_cli adopt "$2"
    ' _ "$CORE" "$WORK/roots/r1" </dev/null 2>&1
) || rc=$?
if [ "$rc" = 0 ] && [ "$(wc -l <"$GP_SUDO_LOG")" = 1 ] &&
    grep -qF 'env OPK_GITPROTECT_ROOT=1 sh ' "$GP_SUDO_LOG" &&
    grep -qF 'bin/opk git-protection adopt' "$GP_SUDO_LOG" &&
    grep -qF "$WORK/roots/r1" "$GP_SUDO_LOG"; then
    pass "cli: non-root re-execs sudo once, cmd+args ride along"
else
    fail "cli: re-exec shape (rc=$rc log=$(cat "$GP_SUDO_LOG"))"
fi

# --- 2. _gp_root_ok reader gate ----------------------------------------------------

# form arms never relax (they run without GP_CONF_RELAX).
_rk() { # <expr> — rc in _rk_rc
    _rk_rc=0
    _core_run "_gp_root_ok $1" >/dev/null || _rk_rc=$?
}

_rk 'relative'
[ "$_rk_rc" = 1 ] && pass "root_ok: relative refused" || fail "root_ok: relative (rc=$_rk_rc)"
_rk '"/a/../b"'
[ "$_rk_rc" = 1 ] && pass "root_ok: dot segments refused" || fail "root_ok: dots (rc=$_rk_rc)"
_rk '"/a//b"'
[ "$_rk_rc" = 1 ] && pass "root_ok: empty segment refused" || fail "root_ok: empty (rc=$_rk_rc)"
_rk '"/a b"'
[ "$_rk_rc" = 1 ] && pass "root_ok: whitespace refused" || fail "root_ok: whitespace (rc=$_rk_rc)"
_rk '"/a/b*"'
[ "$_rk_rc" = 1 ] && pass "root_ok: glob refused" || fail "root_ok: glob (rc=$_rk_rc)"

# rc 2/3 arms need the real arms (no relax): run without GP_CONF_RELAX.
_out2=$(
    _ui_stubs
    GP_STORAGE="$WORK/storage" GP_CONF="$CONF" GP_INSTALL_CONF="$IC" sh -c '
        . "$1"
        _gp_root_ok "/etc"
        echo "rc3=$?"
        _gp_root_ok "/"
        echo "rcslash=$?"
    ' _ "$CORE" 2>&1
)
if printf '%s' "$_out2" | grep -qF 'rc3=3' && printf '%s' "$_out2" | grep -qF 'rcslash=3'; then
    pass "root_ok: system paths refused with rc 3 (incl. bare /)"
else
    fail "root_ok: system-path arms (out=$_out2)"
fi

_ahome=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)
if [ -n "$_ahome" ]; then
    _out3=$(
        _ui_stubs
        GP_STORAGE="$WORK/storage" GP_CONF="$CONF" GP_INSTALL_CONF="$IC" sh -c '
            . "$1"
            _gp_root_ok "$2"
            echo "rc2=$?"
        ' _ "$CORE" "$_ahome" 2>&1
    )
    if printf '%s' "$_out3" | grep -qF 'rc2=2'; then
        pass "root_ok: agent home refused with rc 2"
    else
        fail "root_ok: agent-home arm (out=$_out3)"
    fi
fi

# trailing slash normalizes (the strip-then-compare parity).
_out4=$(_core_run '_gp_root_ok "$WORK/roots/r1/"; echo "norm=$_gp_root_norm"')
if printf '%s' "$_out4" | grep -qF "norm=$WORK/roots/r1"; then
    pass "root_ok: trailing slash stripped into _gp_root_norm"
else
    fail "root_ok: normalization (out=$_out4)"
fi

# --- 3. storage resolution ---------------------------------------------------------

printf '%s\n' "$WORK/roots/r1" >"$CONF"
_out=$(_core_run 'unset GP_STORAGE; _gp_storage')
if [ "$_out" = "$WORK/roots/gitdirs" ]; then
    pass "storage: sibling of the first usable conf root derived"
else
    fail "storage: sibling derivation (got $_out)"
fi

printf 'GITDIR_STORAGE=%s\n' "$WORK/elsewhere" >"$IC.tmp"
mv "$IC.tmp" "$IC"
_out=$(_core_run 'unset GP_STORAGE; _gp_storage')
if [ "$_out" = "$WORK/elsewhere" ]; then
    pass "storage: GITDIR_STORAGE from install.conf wins over derivation"
else
    fail "storage: conf override (got $_out)"
fi

printf 'GITDIR_STORAGE=none\n' >"$IC.tmp"
mv "$IC.tmp" "$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; _gp_storage') || _rc=$?
if [ "$_rc" = 2 ] && [ -z "$_out" ]; then
    pass "storage: the declined marker answers rc 2 (no path)"
else
    fail "storage: declined marker (rc=$_rc out=$_out)"
fi

printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\n' "$(id -un)" "$(id -un)" >"$IC"
_out=$(_core_run 'GP_STORAGE="$WORK/envstorage" _gp_storage')
if [ "$_out" = "$WORK/envstorage" ]; then
    pass "storage: GP_STORAGE env wins over everything"
else
    fail "storage: env override (got $_out)"
fi

# agent-home roots are skipped by the derivation (the design: the
# storage never lives inside the agent's home).
printf '%s\n' "$_ahome" >"$CONF"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; _gp_storage') || _rc=$?
if [ "$_rc" = 1 ]; then
    pass "storage: agent-home conf root skipped, nothing derived"
else
    fail "storage: agent-home skip (rc=$_rc out=$_out)"
fi

: >"$CONF"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; _gp_storage') || _rc=$?
if [ "$_rc" = 1 ]; then
    pass "storage: empty conf derives nothing (rc 1)"
else
    fail "storage: empty conf (rc=$_rc)"
fi

# --- 4. persist + drop on a scratch install.conf ------------------------------------

printf 'DEFAULT_USER=%s\nGITDIR_STORAGE=%s\n' "$(id -un)" "$WORK/old" >"$IC"
_out=$(_core_run '_gp_persist_storage "$WORK/new"; grep "^GITDIR_STORAGE=" "$IC"')
if [ "$_out" = "GITDIR_STORAGE=$WORK/new" ] &&
    [ "$(grep -c '^GITDIR_STORAGE=' "$IC")" = 1 ]; then
    pass "persist: existing key replaced in place, no duplicate"
else
    fail "persist: replace arm (out=$_out)"
fi

printf 'DEFAULT_USER=%s\n' "$(id -un)" >"$IC"
_out=$(_core_run '_gp_persist_storage "$WORK/new"; grep "^GITDIR_STORAGE=" "$IC"')
if [ "$_out" = "GITDIR_STORAGE=$WORK/new" ]; then
    pass "persist: key appended when absent"
else
    fail "persist: append arm (out=$_out)"
fi

printf 'DEFAULT_USER=%s\nGITDIR_STORAGE=%s\n' "$(id -un)" "$WORK/new" >"$IC"
_out=$(_core_run '_gp_drop_storage; grep -c "^GITDIR_STORAGE=" "$IC" || true')
if [ "$_out" = 0 ]; then
    pass "drop: the key is removed, other keys survive"
else
    fail "drop: arm (count=$_out)"
fi

printf 'DEFAULT_USER=%s\n' "$(id -un)" >"$IC"
_out=$(
    GP_INSTALL_CONF="$WORK/missing-install.conf" sh -c '
        . "$1"
        ui_error() { echo "error: $*" >&2; }
        _gp_persist_storage "$WORK/x"
    ' _ "$CORE" 2>&1
) || true
if printf '%s' "$_out" | grep -qF 'install.conf not found'; then
    pass "persist: missing install.conf is a loud refusal"
else
    fail "persist: missing-conf arm (out=$_out)"
fi

# --- 5. project classification -------------------------------------------------------

printf '%s\n' "$WORK/roots/r1" >"$CONF"
mkdir -p "$WORK/storage"
_mkrepo "$WORK/roots/r1/classic"

_mkrepo "$WORK/roots/r1/nailedp"
rm -rf "${WORK:?}/roots/r1/nailedp/.git"
mkdir -p "$WORK/storage/nailedp.git"
printf 'gitdir: %s\n' "$WORK/storage/nailedp.git" >"$WORK/roots/r1/nailedp/.git"
touch "$WORK/roots/r1/nailedp/.git.nailed"

_mkrepo "$WORK/roots/r1/unnailedp"
rm -rf "${WORK:?}/roots/r1/unnailedp/.git"
mkdir -p "$WORK/storage/unnailedp.git"
printf 'gitdir: %s\n' "$WORK/storage/unnailedp.git" >"$WORK/roots/r1/unnailedp/.git"

mkdir -p "$WORK/roots/r1/foreign"
printf 'gitdir: /somewhere/else.git\n' >"$WORK/roots/r1/foreign/.git"
mkdir -p "$WORK/roots/r1/wtreg/.git"

_out=$(_core_run '_gp_projects')
for _want in "classic $WORK/roots/r1/classic" \
    "nailed $WORK/roots/r1/nailedp" \
    "unnailed $WORK/roots/r1/unnailedp" \
    "foreign-pointer $WORK/roots/r1/foreign" \
    "worktree-reg $WORK/roots/r1/wtreg"; do
    if printf '%s\n' "$_out" | grep -qxF "$_want"; then
        pass "classify: $_want"
    else
        fail "classify: $_want (out=$(printf '%s' "$_out" | tr '\n' ';'))"
    fi
done

# a refused conf line authorizes nothing (stdout data channel stays
# empty) and says why on stderr — the loud-skip contract.
printf '%s\n' "/etc" >"$CONF"
_rc=0
_out=$(_core_run 'unset GP_CONF_RELAX; _gp_projects') || _rc=$?
if ! printf '%s' "$_out" | grep -qE '^(classic|nailed|unnailed|foreign-pointer|worktree-reg) ' &&
    printf '%s' "$_out" | grep -qF 'system path is never a project root'; then
    pass "classify: refused conf line yields no projects, says why"
else
    fail "classify: refused conf line (out=$_out)"
fi

# an unreadable subtree under a good root: the scan note fires on
# stderr, the data channel keeps the readable projects (the
# git-heal-status twin shape — find rc 1 must not be silence).
printf '%s\n' "$WORK/roots/r1" >"$CONF"
mkdir -p "$WORK/roots/r1/locked/sub"
_mkrepo "$WORK/roots/r1/locked/sub/inner"
chmod 000 "$WORK/roots/r1/locked/sub"
_rc=0
_out=$(_core_run '_gp_projects') || _rc=$?
chmod 755 "$WORK/roots/r1/locked/sub"
if printf '%s' "$_out" | grep -qF 'scan may be incomplete under' &&
    printf '%s' "$_out" | grep -qF "classic $WORK/roots/r1/classic"; then
    pass "classify: unreadable subtree renders the incompleteness note, data flows"
else
    fail "classify: unreadable-subtree arm (out=$_out)"
fi

# --- 6. the atomic migrate -----------------------------------------------------------

printf '%s\n' "$WORK/roots/r1" >"$CONF"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
rm -rf "${WORK:?}/storage"
mkdir -p "$WORK/storage"
_mkrepo "$WORK/roots/r1/proj1"

_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/proj1" yes') || _rc=$?
_ptr=$(cat "$WORK/roots/r1/proj1/.git" 2>/dev/null)
if [ "$_rc" = 0 ] && [ -d "$WORK/storage/proj1.git" ] &&
    [ "$_ptr" = "gitdir: $WORK/storage/proj1.git" ] &&
    [ -f "$WORK/roots/r1/proj1/.git.nailed" ] &&
    git -C "$WORK/roots/r1/proj1" status --porcelain >/dev/null 2>&1; then
    pass "migrate: happy path — pointer written, gitdir moved, nailed, git green"
else
    fail "migrate: happy path (rc=$_rc ptr=$_ptr out=$_out)"
fi

# the migrated gitdir carries the relocated heal: the MODE contract is
# the discriminator (#754 a B11 — ownership legs are vacuous when
# dev==agent==runner; the mode classes separate): config-class 644
# (no group write), operand-class 664, hooks 755 (setgid may ride:
# numeric chmod does NOT clear a directory's setgid on Linux —
# measured; harmless, the contract is no group WRITE), sticky+setgid
# on the gitdir (the #651 group-baseline semantics — the exact base
# mode rides the source tree's umask, only the added bits are the
# contract).
_mode_cfg=$(stat -c %a "$WORK/storage/proj1.git/config")
_mode_idx=$(stat -c %a "$WORK/storage/proj1.git/index")
_mode_msg=$(stat -c %a "$WORK/storage/proj1.git/COMMIT_EDITMSG")
_mode_hooks=$(stat -c %a "$WORK/storage/proj1.git/hooks")
_hooks_ok=0
case "$_mode_hooks" in
    755 | 2755) _hooks_ok=1 ;;
esac
# The index is umask-tolerant: _gp_verify's own status refresh may
# rewrite it under the invoking umask (002 here -> 664, CI's 022 ->
# 644; measured on the CI runner) — git floats operand modes by
# design (#671). The CLASS discriminator is config-no-group-write vs
# COMMIT_EDITMSG-group-write; the index asserts only the two observed
# post-status shapes.
_idx_ok=0
case "$_mode_idx" in
    644 | 664) _idx_ok=1 ;;
esac
if [ "$_mode_cfg" = 644 ] && [ "$_idx_ok" = 1 ] &&
    [ "$_mode_msg" = 664 ] && [ "$_hooks_ok" = 1 ] &&
    [ -k "$WORK/storage/proj1.git" ] && [ -g "$WORK/storage/proj1.git" ]; then
    pass "migrate: relocated heal — mode classes 644/664/755 + sticky+setgid"
else
    fail "migrate: heal contract (cfg=$_mode_cfg idx=$_mode_idx msg=$_mode_msg hooks=$_mode_hooks)"
fi

# skip arms: no .git, not a gitdir shape, symlinked .git.
mkdir -p "$WORK/roots/r1/nogit"
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/nogit" yes')
if printf '%s' "$_out" | grep -qF 'skip: no classic .git dir'; then
    pass "migrate: no .git is a skip"
else
    fail "migrate: nogit arm (out=$_out)"
fi

mkdir -p "$WORK/roots/r1/notgit/.git"
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/notgit" yes')
if printf '%s' "$_out" | grep -qF 'skip: not a (common) gitdir shape'; then
    pass "migrate: non-gitdir .git is a skip"
else
    fail "migrate: notgit arm (out=$_out)"
fi

mkdir -p "$WORK/roots/r1/linktarget/.git"
mktarget="$WORK/roots/r1/linktarget/.git"
ln -s "$mktarget" "$WORK/roots/r1/symproj/.git" 2>/dev/null || {
    mkdir -p "$WORK/roots/r1/symproj"
    ln -s "$mktarget" "$WORK/roots/r1/symproj/.git"
}
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/symproj" yes')
if printf '%s' "$_out" | grep -qF 'skip: .git is a symlink'; then
    pass "migrate: symlinked .git refused (L5 final-component gate)"
else
    fail "migrate: symlink arm (out=$_out)"
fi

# naming rule (#764 topic 1): a project NESTED below its conf root is
# named <parent>-<basename>.git — the same basename in two folders no
# longer collides (r1/proj1 above is top-level and keeps proj1.git).
_mkrepo "$WORK/roots/r1/sub/proj1"
_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/sub/proj1" yes') || _rc=$?
if [ "$_rc" = 0 ] && [ -d "$WORK/storage/sub-proj1.git" ] &&
    [ "$(cat "$WORK/roots/r1/sub/proj1/.git")" = "gitdir: $WORK/storage/sub-proj1.git" ]; then
    pass "migrate: a nested project is named <parent>-<basename>.git (#764)"
else
    fail "migrate: nested naming arm (rc=$_rc out=$_out)"
fi

# the suffix loop stays the belt for same-parent duplicates: a
# pre-#764 entry (or a since-deleted checkout of that name) already
# holds the name.
mkdir -p "$WORK/storage/sub2-dup.git"
_mkrepo "$WORK/roots/r1/sub2/dup"
_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/sub2/dup" yes') || _rc=$?
if [ "$_rc" = 0 ] && [ -d "$WORK/storage/sub2-dup-2.git" ] &&
    [ "$(cat "$WORK/roots/r1/sub2/dup/.git")" = "gitdir: $WORK/storage/sub2-dup-2.git" ] &&
    [ -d "$WORK/storage/sub2-dup.git" ]; then
    pass "migrate: a taken name under one parent gets the -2 suffix (#764)"
else
    fail "migrate: collision arm (rc=$_rc out=$_out)"
fi

# _gp_entry_name matrix (#764 topic 1): one level deep only, the plain
# basename directly under a conf root (trailing slash on the conf line
# or the project path alike), outside every conf root prefixed, an
# absent conf and an over-long parent both falling back to the
# basename. Each row prints the name; r1 is the conf root here.
_en() { # <path> -> sets _en_out (the name) and _en_rc; no command
    # substitution on purpose: a subshell would lose _en_rc for the caller.
    _en_rc=0
    _en_out=$(_core_run "_gp_entry_name \"$1\"") || _en_rc=$?
}
_enlong=$(printf '%0.sx' $(seq 1 250))
for _en_row in \
    "$WORK/roots/r1/proj1|proj1" \
    "$WORK/roots/r1/proj1/|proj1" \
    "$WORK/roots/r1/sub/proj1|sub-proj1" \
    "$WORK/roots/r1/a/b/c|b-c" \
    "$WORK/elsewhere/deep/x|deep-x" \
    "$WORK/elsewhere/$_enlong/x|x"; do
    _en_exp=${_en_row#*|}
    _en_p=${_en_row%|*}
    _en "$_en_p"
    if [ "$_en_rc" = 0 ] && [ "$_en_out" = "$_en_exp" ]; then
        pass "entry-name: $(printf '%s' "${_en_p#*"$WORK"/}" | cut -c1-44) -> $_en_exp"
    else
        fail "entry-name: $(printf '%s' "$_en_p" | cut -c1-60) (expected $_en_exp, got '$_en_out', rc=$_en_rc)"
    fi
done
# conf line with a trailing slash still names the root; with NO conf
# there is no root to compare against — a nested project takes the
# prefix exactly like one outside every conf root (row above).
printf '%s/\n' "$WORK/roots/r1" >"$CONF"
_en "$WORK/roots/r1/p"
if [ "$_en_out" = p ]; then
    pass "entry-name: a trailing-slash conf line still detects the root"
else
    fail "entry-name: trailing-slash conf line (got '$_en_out')"
fi
_en_out=$(_core_run 'GP_CONF="$WORK/no-such.conf" _gp_entry_name "$WORK/roots/r1/sub/p"')
if [ "$_en_out" = sub-p ]; then
    pass "entry-name: no conf -> no root, the nested project keeps its prefix"
else
    fail "entry-name: absent conf (got '$_en_out')"
fi
printf '%s\n' "$WORK/roots/r1" >"$CONF"

# worktree repair: the worktree's pointer follows the moved gitdir.
_mkrepo "$WORK/roots/r1/wtbase"
git -C "$WORK/roots/r1/wtbase" worktree add "$WORK/roots/r1/wtside" -q 2>/dev/null ||
    git -C "$WORK/roots/r1/wtbase" worktree add -q "$WORK/roots/r1/wtside"
_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/wtbase" yes') || _rc=$?
_wtptr=$(cat "$WORK/roots/r1/wtside/.git" 2>/dev/null)
if [ "$_rc" = 0 ] && printf '%s' "$_wtptr" | grep -qF "$WORK/storage/wtbase.git/worktrees/"; then
    pass "migrate: worktree pointer follows the moved gitdir (repair)"
else
    fail "migrate: worktree repair (rc=$_rc ptr=$_wtptr out=$_out)"
fi

# rollback: pointer out, gitdir back (constructed post-mv state).
_mkrepo "$WORK/roots/r1/rb"
mv "$WORK/roots/r1/rb/.git" "$WORK/storage/rb.git"
printf 'gitdir: %s\n' "$WORK/storage/rb.git" >"$WORK/roots/r1/rb/.git"
_rc=0
_out=$(_core_run '_gp_rollback "$WORK/roots/r1/rb" "$WORK/storage/rb.git"') || _rc=$?
if [ "$_rc" = 0 ] && [ -d "$WORK/roots/r1/rb/.git" ] &&
    [ -e "$WORK/roots/r1/rb/.git/HEAD" ] &&
    git -C "$WORK/roots/r1/rb" status --porcelain >/dev/null 2>&1; then
    pass "rollback: pointer out, gitdir back, git green"
else
    fail "rollback: arm (rc=$_rc out=$_out)"
fi

# nail failure degrades loud but the migration STAYS (warn-only).
_mkrepo "$WORK/roots/r1/noimm"
_rc=0
_out=$(GP_CHATTR_FAIL=1 _core_run '_gp_migrate_one "$WORK/roots/r1/noimm" yes') || _rc=$?
if [ "$_rc" = 0 ] && [ -f "$WORK/roots/r1/noimm/.git" ] &&
    printf '%s' "$_out" | grep -qF 'stays UNNAILED'; then
    pass "migrate: chattr failure degrades loud, layout stays"
else
    fail "migrate: nail-degrade arm (rc=$_rc out=$_out)"
fi

# --- 7. nail gating -------------------------------------------------------------------

# target outside the storage never gets sealed.
mkdir -p "$WORK/outsidestorage/x.git"
_rc=0
_out=$(_core_run '_gp_nail_one "$WORK/roots/r1/classic" "$WORK/outsidestorage/x.git"') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'does not point at a storage child'; then
    pass "nail: pointer target outside the storage refused"
else
    fail "nail: outside arm (rc=$_rc out=$_out)"
fi

# the bare storage ROOT is never a sealable target (#754 a A3).
_rc=0
_out=$(_core_run '_gp_nail_one "$WORK/roots/r1/classic" "$WORK/storage"') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'does not point at a storage child'; then
    pass "nail: the storage root itself is refused (#754 a A3)"
else
    fail "nail: storage-root arm (rc=$_rc out=$_out)"
fi

# gitdir not dev-owned: DEFAULT_USER=root while scratch is runner-owned.
printf 'DEFAULT_USER=root\nOPENCODE_USER=%s\n' "$(id -un)" >"$IC.tmp"
mv "$IC.tmp" "$IC"
_rc=0
_out=$(_core_run '_gp_nail_one "$WORK/roots/r1/classic" "$WORK/storage/proj1.git"') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'gitdir not dev-owned'; then
    pass "nail: non-dev-owned gitdir refused"
else
    fail "nail: ownership arm (rc=$_rc out=$_out)"
fi
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"

# lsattr not showing i after chattr: refuse (the stubs are
# deliberately inconsistent for this arm — GP_LSATTR_LIE).
_rc=0
_out=$(
    PATH="$WORK/bin:/usr/bin:/bin" GP_LSATTR_LIE=1 GP_STORAGE="$WORK/storage" \
        GP_INSTALL_CONF="$IC" sh -c '
        . "$1"
        ui_warn() { echo "warn: $*" >&2; }
        ui_error() { echo "error: $*" >&2; }
        _gp_nail_one "$2" "$3"
    ' _ "$CORE" "$WORK/roots/r1/proj1" "$WORK/storage/proj1.git" 2>&1
) || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'lsattr does not show i'; then
    pass "nail: lsattr-without-i refused (verify gate)"
else
    fail "nail: verify arm (rc=$_rc out=$_out)"
fi

# happy nail: chattr + lsattr both green.
_out=$(_core_run '_gp_nail_one "$WORK/roots/r1/proj1" "$WORK/storage/proj1.git"')
if [ -f "$WORK/roots/r1/proj1/.git.nailed" ] &&
    grep -qF 'chattr +i' "$GP_STUB_LOG"; then
    pass "nail: happy path nails and verifies"
else
    fail "nail: happy arm (out=$_out)"
fi

# --- 8. status rc semantics ------------------------------------------------------------

printf '%s\n' "$WORK/roots/r1" >"$CONF"
# classic projects exist under r1 → actionable → rc 1.
_rc=0
_out=$(_core_run 'git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'kv-bad:'; then
    pass "status: rc 1 with a classic (unprotected) project"
else
    fail "status: actionable rc (rc=$_rc out=$_out)"
fi

# a clean storage-only tree: rc 0 — ISOLATED legs (#754 a B12): a
# NAILED-only root answers rc 0, the same root with the marker gone
# (unnailed-only) answers rc 1.
mkdir -p "$WORK/roots/r2"
printf '%s\n' "$WORK/roots/r2" >"$CONF"
_mkrepo "$WORK/roots/r2/prot"
rm -rf "${WORK:?}/roots/r2/prot/.git"
mkdir -p "$WORK/storage/prot.git"
printf 'gitdir: %s\n' "$WORK/storage/prot.git" >"$WORK/roots/r2/prot/.git"
touch "$WORK/roots/r2/prot/.git.nailed"
_rc=0
_out=$(_core_run 'git_protection_cli status') || _rc=$?
if [ "$_rc" = 0 ] && printf '%s' "$_out" | grep -qF 'pointer + nailed'; then
    pass "status: rc 0 with a nailed-only tree (isolated)"
else
    fail "status: nailed-only rc (rc=$_rc out=$_out)"
fi
rm -f "${WORK:?}/roots/r2/prot/.git.nailed"
_rc=0
_out=$(_core_run 'git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'pointer, NOT nailed'; then
    pass "status: rc 1 with an unnailed-only tree (isolated)"
else
    fail "status: unnailed-only rc (rc=$_rc out=$_out)"
fi

# --- 8b. fix commands per row (#764 topic 3) + unreferenced entries (topic 4) -------
# Fresh root r5 so the earlier fixtures cannot pollute the pins.
# Storage entries: n1.git / u1.git are pointed at (nailed / unnailed),
# n1wt.git only through a WORKTREE-REGISTRATION pointer (a surviving
# worktree keeps the common gitdir alive); everything else is
# unreferenced — a plain dir, a dot-named dir, a symlink, a name that
# is not paste-safe. f1 points outside the storage (never a reference).
_r5="$WORK/roots/r5"
_sto="$WORK/storage"
mkdir -p "$_r5/sub" "$WORK/elsewhere-lnk"
printf '%s\n' "$_r5" >"$CONF"
_mkrepo "$_r5/p1"
_mkrepo "$_r5/sub/p2"
_mkrepo "$_r5/n1"
rm -rf "${WORK:?}/roots/r5/n1/.git"
mkdir -p "$_sto/n1.git"
printf 'gitdir: %s\n' "$_sto/n1.git" >"$_r5/n1/.git"
touch "$_r5/n1/.git.nailed"
_mkrepo "$_r5/u1"
rm -rf "${WORK:?}/roots/r5/u1/.git"
mkdir -p "$_sto/u1.git"
printf 'gitdir: %s\n' "$_sto/u1.git" >"$_r5/u1/.git"
mkdir -p "$_r5/wtside" "$_sto/n1wt.git/worktrees/wtside"
printf 'gitdir: %s\n' "$_sto/n1wt.git/worktrees/wtside" >"$_r5/wtside/.git"
mkdir -p "$_r5/f1"
printf 'gitdir: /somewhere/else.git\n' >"$_r5/f1/.git"
mkdir -p "$_sto/orphan1.git" "$_sto/.orphan2.git" "$_sto/odd name.git"
ln -s "$WORK/elsewhere-lnk" "$_sto/lnk.git"

# the reference list _gp_projects appends to: exactly the storage
# children some pointer targets — mains and the worktree registration
# alike, never the unreferenced entries or the outside pointer. rc on
# the assignment: a missing list makes sort die (rc 2), and a failing
# substitution would abort this set -e suite BEFORE the FAIL row —
# the red must come from the assertion (sabotage c06, #764).
_rc=0
_out=$(_core_run "_gp_projects \"$WORK/r5-ref.out\" >/dev/null; LC_ALL=C sort \"$WORK/r5-ref.out\"") || _rc=$?
if [ "$_out" = "$(printf '%s\n' n1.git n1wt.git u1.git)" ]; then
    pass "projects: the reference list names every pointed-at storage child (#764 topic 4)"
else
    fail "projects: reference list (got: $(printf '%s' "$_out" | tr '\n' ' '))"
fi

# enabled (GP_STORAGE seam): every actionable row names its command
# with the path filled in; two classic rows add the all-at-once hint.
_rc=0
_out=$(_core_run 'git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" | grep -qF "kv-bad: $_r5/p1 classic .git (unprotected -- the mv .git arm)" &&
    printf '%s' "$_out" | grep -qF " -- run: sudo opk git-protection adopt $_r5/p1" &&
    printf '%s' "$_out" | grep -qF " -- run: sudo opk git-protection adopt $_r5/sub/p2" &&
    printf '%s' "$_out" | grep -qF "kv-warn: $_r5/u1 pointer, NOT nailed (run: sudo opk git-protection nail $_r5/u1)" &&
    printf '%s' "$_out" | grep -qF "kv-ok: $_r5/n1 pointer + nailed" &&
    printf '%s' "$_out" | grep -qF 'several projects -- one run adopts them all: sudo opk git-protection on'; then
    pass "status: classic rows name adopt <path>, unnailed rows nail <path>, 2+ add the on hint (#764)"
else
    fail "status: fix-command rows (rc=$_rc out=$_out)"
fi

# unreferenced entries render as INFO rows (plain kv:, counted nowhere)
# with the removal hint; referenced entries render nothing; a symlink
# is flagged; a name that is not paste-safe gets NO removal command.
# (`${_sto:?}` inside the expected strings: the sandbox floor walks
# message prose on live lines too, #630 — a literal `rm` next to a
# `"$VAR/suffix"` in one statement reads as an unguarded deletion.)
if printf '%s' "$_out" |
    grep -qF "kv: $_sto/orphan1.git unreferenced storage entry -- no pointer under the configured" &&
    printf '%s' "$_out" | grep -qF "inspect, then remove: sudo rm -rf ${_sto:?}/orphan1.git" &&
    printf '%s' "$_out" | grep -qF "kv: $_sto/.orphan2.git unreferenced storage entry" &&
    printf '%s' "$_out" | grep -qF "kv: $_sto/lnk.git unreferenced storage entry (a symlink)" &&
    printf '%s' "$_out" | grep -qF "kv: $_sto/odd name.git unreferenced storage entry" &&
    ! printf '%s' "$_out" | grep -qF "sudo rm -rf ${_sto:?}/odd name.git" &&
    ! printf '%s' "$_out" | grep -qE "storage/(n1|u1|n1wt)\.git unreferenced"; then
    pass "status: unreferenced entries are INFO rows with a paste-safe removal hint (#764)"
else
    fail "status: orphan rows (out=$_out)"
fi

# INFO means INFO: over a root with no projects, the unreferenced
# entries alone keep rc 0.
mkdir -p "$_r5/clean"
printf '%s\n' "$_r5/clean" >"$CONF"
_rc=0
_out=$(_core_run 'git_protection_cli status') || _rc=$?
printf '%s\n' "$_r5" >"$CONF"
if [ "$_rc" = 0 ] && printf '%s' "$_out" | grep -qF "kv: $_sto/orphan1.git unreferenced"; then
    pass "status: unreferenced entries alone never make the rc non-zero (#764)"
else
    fail "status: orphan-only rc (rc=$_rc out=$_out)"
fi

# the forged-row arm: an entry name carrying a raw newline (the storage
# is agent-writable) renders as ONE row with the byte shown as ?, never
# as a second row. Embedded newline via a variable (POSIX strips
# trailing newlines from command substitution — the intuitive
# `$(printf '\n')` is EMPTY).
NL=$(printf '\nX')
NL=${NL%X}
: >"$_sto/bad${NL}FORGED.git"
# rc capture on the assignment: the root still holds classic projects
# (status answers rc 1), and a failing substitution aborts this
# set -e suite before the tally.
_rc=0
_out=$(_core_run 'git_protection_cli status') || _rc=$?
rm -f "${WORK:?}/storage/bad${NL}FORGED.git"
if printf '%s' "$_out" | grep -qF "kv: $_sto/bad?FORGED.git unreferenced storage entry" &&
    ! printf '%s' "$_out" | grep -q '^FORGED' &&
    ! printf '%s' "$_out" | grep -qF "sudo rm -rf ${_sto:?}/bad?FORGED.git"; then
    pass "status: a newline in an entry name cannot forge a row (#764)"
else
    fail "status: forged-row arm (out=$(printf '%s' "$_out" | grep -a FORGED))"
fi

# an absent reference list skips the pass with a counted row — never
# "everything is unreferenced" over a caller bug.
_out=$(_core_run "_gp_orphan_rows \"$WORK/storage\" \"$WORK/no-such-ref\"")
if printf '%s' "$_out" | grep -qF 'kv-warn: git-protection unreferenced-entry check skipped (no readable reference list)' &&
    ! printf '%s' "$_out" | grep -qF 'unreferenced storage entry'; then
    pass "orphans: a missing reference list skips loud, lists nothing (#764)"
else
    fail "orphans: missing-ref arm (out=$_out)"
fi
# ... an UNREADABLE one too (a present file this caller cannot read
# would make every grep fail into "unreferenced"). Root-hermetic: a
# root suite user reads everything, so the arm needs a non-root runner.
if [ "$(id -u)" != 0 ]; then
    : >"$WORK/unreadable-ref"
    chmod 000 "$WORK/unreadable-ref"
    _out=$(_core_run "_gp_orphan_rows \"$WORK/storage\" \"$WORK/unreadable-ref\"")
    chmod 600 "$WORK/unreadable-ref"
    if printf '%s' "$_out" | grep -qF 'unreferenced-entry check skipped (no readable reference list)' &&
        ! printf '%s' "$_out" | grep -qF 'unreferenced storage entry'; then
        pass "orphans: an unreadable reference list skips loud too (#764)"
    else
        fail "orphans: unreadable-ref arm (out=$_out)"
    fi
else
    echo "  SKIP  unreadable-ref arm needs a non-root suite user (#764)"
fi

# both mktemp guards of the status command are live (L1: a new
# fail-soft spot executes its failure path): a broken TMPDIR fails
# the FIRST allocation (the project list) loud.
_rc=0
_out=$(_core_run 'TMPDIR="$WORK/no-such-tmp" git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" | grep -qF 'error: mktemp failed — cannot enumerate projects'; then
    pass "status: a failed list mktemp names the cause, rc 1 (#764)"
else
    fail "status: first mktemp arm (rc=$_rc out=$_out)"
fi
# the SECOND allocation (the reference list) needs a stub that
# succeeds once and then fails; the guard must name its cause AND
# remove the list file the first allocation left behind.
mkdir -p "$WORK/bin-mk"
cat >"$WORK/bin-mk/mktemp" <<'EOF'
#!/bin/sh
if [ -e "${GP_MKTEMP_MARK:?}" ]; then
    exit 1
fi
: >"$GP_MKTEMP_MARK"
_t=$(/usr/bin/mktemp "$@") || exit 1
printf '%s\n' "$_t" >"${GP_MKTEMP_LOG:?}"
printf '%s\n' "$_t"
EOF
chmod 755 "$WORK/bin-mk/mktemp"
_rc=0
_out=$(
    PATH="$WORK/bin-mk:$PATH" GP_MKTEMP_MARK="$WORK/mktemp.mark" GP_MKTEMP_LOG="$WORK/mktemp.log" \
        GP_STORAGE="$WORK/storage" GP_CONF="$CONF" GP_INSTALL_CONF="$IC" \
        sh -c '
        . "$1"
        ui_section() { echo "section: $*"; }
        ui_kv() { echo "kv: $1 $2"; }
        ui_kv_warn() { echo "kv-warn: $1 $2"; }
        ui_kv_bad() { echo "kv-bad: $1 $2"; }
        ui_detail() { echo "detail: $*"; }
        ui_error() { echo "error: $*" >&2; }
        git_protection_cli status
    ' _ "$CORE" 2>&1
) || _rc=$?
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" | grep -qF 'error: mktemp failed — cannot collect pointer targets' &&
    [ -s "$WORK/mktemp.log" ] && [ ! -e "$(cat "$WORK/mktemp.log")" ]; then
    pass "status: a failed reference-list mktemp names the cause and removes the list file (#764)"
else
    fail "status: second mktemp arm (rc=$_rc out=$_out)"
fi

# not enabled — derived default (nothing persisted): the storage row
# says "not configured" and names the derived path; a classic row's
# command is `on` (adopt refuses without an initialized storage).
mkdir -p "$WORK/roots/r6"
_mkrepo "$WORK/roots/r6/c1"
printf '%s\n' "$WORK/roots/r6" >"$CONF"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" | grep -qF "kv-warn: storage not configured (derived default: $WORK/roots/gitdirs)" &&
    printf '%s' "$_out" | grep -qF 'detail: run: sudo opk git-protection on' &&
    printf '%s' "$_out" | grep -qF "kv-bad: $WORK/roots/r6/c1 classic .git (unprotected -- the mv .git arm)" &&
    printf '%s' "$_out" | grep -qF ' -- run: sudo opk git-protection on' &&
    ! printf '%s' "$_out" | grep -qF 'git-protection adopt'; then
    pass "status: not enabled -> derived default is not configured, classic rows name on (#764)"
else
    fail "status: not-enabled arm (rc=$_rc out=$_out)"
fi

# not enabled — nothing derivable (empty conf): the pre-#764 row.
: >"$CONF"
_out=$(_core_run 'unset GP_STORAGE; git_protection_cli status')
if printf '%s' "$_out" | grep -qF 'kv-warn: storage not configured (default would be a sibling' &&
    printf '%s' "$_out" | grep -qF 'detail: run: sudo opk git-protection on'; then
    pass "status: nothing derivable keeps the not-configured row + the on hint (#764)"
else
    fail "status: not-derivable arm (out=$_out)"
fi

# declined (maintainer decision for #764: an explicit `on` replaces
# the marker): the storage row keeps its "'sudo opk git-protection
# on' enables" wording — true again — and a classic row names `on`.
printf '%s\n' "$WORK/roots/r6" >"$CONF"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=none\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" |
    grep -qF "kv: storage declined (GITDIR_STORAGE=none) — 'sudo opk git-protection on' enables" &&
    printf '%s' "$_out" |
    grep -qF "kv-bad: $WORK/roots/r6/c1 classic .git (unprotected -- the mv .git arm)" &&
    printf '%s' "$_out" | grep -qF "arm) -- run: sudo opk git-protection on" &&
    ! printf '%s' "$_out" | grep -qF 'git-protection adopt'; then
    pass "status: declined -> the storage row names on, and on is the classic rows' command (#764)"
else
    fail "status: declined arm (rc=$_rc out=$_out)"
fi

# enabled through the PERSISTED key (no GP_STORAGE seam): _gp_enabled
# reads install.conf; one classic row -> the adopt command and NO
# all-at-once hint.
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" "$WORK/storage" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF "kv: storage $WORK/storage" &&
    printf '%s' "$_out" | grep -qF " -- run: sudo opk git-protection adopt $WORK/roots/r6/c1" &&
    ! printf '%s' "$_out" | grep -qF 'one run adopts them all'; then
    pass "status: the persisted key enables adopt <path>; one classic row adds no on hint (#764)"
else
    fail "status: persisted-key arm (rc=$_rc out=$_out)"
fi

# enabled but the storage directory is gone: adopt would refuse — the
# row says so and the classic command is `on` (it re-creates the
# storage).
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" "$WORK/no-such-storage" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; git_protection_cli status') || _rc=$?
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" | grep -qF "kv-warn: storage configured but missing: $WORK/no-such-storage" &&
    printf '%s' "$_out" | grep -qF 'detail: re-create it: sudo opk git-protection on' &&
    printf '%s' "$_out" | grep -qF "kv-bad: $WORK/roots/r6/c1 classic .git (unprotected -- the mv .git arm)" &&
    printf '%s' "$_out" | grep -qF ' -- run: sudo opk git-protection on' &&
    ! printf '%s' "$_out" | grep -qF 'git-protection adopt'; then
    pass "status: a missing storage dir turns the classic command into on (#764)"
else
    fail "status: missing-storage arm (rc=$_rc out=$_out)"
fi

# `on` on a DECLINED host replaces the marker (the same decision): the
# default storage is derived PAST GITDIR_STORAGE=none, initialized,
# persisted over the marker and the classic project migrated — one
# command, as the how-tos claim. Fixture set HERE (the arm once
# inherited the previous arm's install.conf and ran past the decline).
printf '%s\n' "$WORK/roots/r6" >"$CONF"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=none\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; git_protection_cli on') || _rc=$?
if [ "$_rc" = 0 ] &&
    printf '%s' "$_out" |
    grep -qF 'info: git-protection was declined on this host (GITDIR_STORAGE=none) -- this run enables it' &&
    [ "$(sed -n 's/^GITDIR_STORAGE=//p' "$IC")" = "$WORK/roots/gitdirs" ] &&
    [ "$(grep -c '^GITDIR_STORAGE=' "$IC")" = 1 ] &&
    [ -d "$WORK/roots/gitdirs" ] && [ -k "$WORK/roots/gitdirs" ] &&
    [ "$(cat "$WORK/roots/r6/c1/.git")" = "gitdir: $WORK/roots/gitdirs/c1.git" ] &&
    git -C "$WORK/roots/r6/c1" status --porcelain >/dev/null 2>&1; then
    pass "on: a declined marker is replaced — storage derived, persisted over none, project migrated (#764)"
else
    fail "on: declined-override arm (rc=$_rc out=$_out ic=$(cat "$IC"))"
fi

# ... with no default derivable, `on` still refuses and names the line
# to edit; the marker stays.
: >"$CONF"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=none\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; git_protection_cli on') || _rc=$?
printf '%s\n' "$WORK/roots/r6" >"$CONF"
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" |
    grep -qF 'error: git-protection is declined on this host (GITDIR_STORAGE=none) and no default' &&
    printf '%s' "$_out" | grep -qF 'replace that line with an absolute storage path' &&
    # the declined-specific refusal is the one that STOPS the run —
    # the generic "no storage path derivable" arm must not follow
    # (sabotage c22: without the arm's own exit the message still
    # prints and the pin stayed green).
    ! printf '%s' "$_out" | grep -qF 'no storage path derivable' &&
    [ "$(sed -n 's/^GITDIR_STORAGE=//p' "$IC")" = none ]; then
    pass "on: declined with no derivable default refuses loud, names the line, keeps the marker (#764)"
else
    fail "on: declined-not-derivable arm (rc=$_rc out=$_out ic=$(cat "$IC"))"
fi
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"

# --- 9. revert --------------------------------------------------------------------------

printf '%s\n' "$WORK/roots/r1" >"$CONF"
# foreign pointer: not ours, skipped.
_out=$(_core_run '_gp_revert_one "$WORK/roots/r1/foreign"')
if printf '%s' "$_out" | grep -qF 'outside storage (not ours)'; then
    pass "revert: foreign pointer skipped"
else
    fail "revert: foreign arm (out=$_out)"
fi

# happy revert: pointer + kit-owned target → classic layout back.
_rc=0
_out=$(_core_run '_gp_revert_one "$WORK/roots/r1/proj1"') || _rc=$?
if [ "$_rc" = 0 ] && [ -d "$WORK/roots/r1/proj1/.git" ] &&
    grep -qF 'chattr -i' "$GP_STUB_LOG" &&
    git -C "$WORK/roots/r1/proj1" status --porcelain >/dev/null 2>&1; then
    pass "revert: happy path — chattr -i, pointer out, gitdir back"
else
    fail "revert: happy arm (rc=$_rc out=$_out)"
fi

# target missing: loud error.
mkdir -p "$WORK/roots/r1/missing"
printf 'gitdir: %s\n' "$WORK/storage/vanished.git" >"$WORK/roots/r1/missing/.git"
_rc=0
_out=$(_core_run '_gp_revert_one "$WORK/roots/r1/missing"') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'pointer target missing'; then
    pass "revert: vanished target is a loud error"
else
    fail "revert: missing-target arm (rc=$_rc out=$_out)"
fi

# --- 10. round-a security arms (#754 a) ---------------------------------------------

printf '%s\n' "$WORK/roots/r1" >"$CONF"

# A3: a planted `gitdir: <storage-root>` pointer is foreign, unsealable
# and unrevertable — the equality arm is gone.
mkdir -p "$WORK/roots/r1/rootptr"
printf 'gitdir: %s\n' "$WORK/storage" >"$WORK/roots/r1/rootptr/.git"
_out=$(_core_run '_gp_projects')
if printf '%s' "$_out" | grep -qxF "foreign-pointer $WORK/roots/r1/rootptr"; then
    pass "security A3: the storage root itself classifies foreign-pointer"
else
    fail "security A3: classification (out=$(printf '%s' "$_out" | tr '\n' ';'))"
fi
_rc=0
_out=$(_core_run '_gp_nail_one "$WORK/roots/r1/rootptr" "$WORK/storage"') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'does not point at a storage child'; then
    pass "security A3: nailing the storage root refused"
else
    fail "security A3: nail arm (rc=$_rc out=$_out)"
fi
_rc=0
_out=$(_core_run '_gp_revert_one "$WORK/roots/r1/rootptr"') || _rc=$?
if [ "$_rc" = 0 ] && printf '%s' "$_out" | grep -qF 'outside storage (not ours)' &&
    [ -d "$WORK/storage" ] && [ -f "$WORK/roots/r1/rootptr/.git" ]; then
    pass "security A3: reverting a storage-root pointer skips (storage intact)"
else
    fail "security A3: revert arm (rc=$_rc out=$_out)"
fi

# A4: the trailing `/..` shape is refused by the FULL-path form gate.
_mkrepo "$WORK/roots/r1/dotdot"
_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/dotdot/.." yes') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'malformed project path' &&
    [ -d "$WORK/roots/r1/dotdot/.git" ]; then
    pass "security A4: adopt-shaped /.. path refused before any move"
else
    fail "security A4: /.. arm (rc=$_rc out=$_out)"
fi

# A5: a symlinked storage is refused at use time (migrate leg).
_mkrepo "$WORK/roots/r1/symstor"
rm -rf "${WORK:?}/storage-sym"
ln -s "$WORK/storage" "$WORK/storage-sym"
_rc=0
_out=$(_core_run 'GP_STORAGE="$WORK/storage-sym" _gp_migrate_one "$WORK/roots/r1/symstor" yes') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'use-time sanity check' &&
    [ -d "$WORK/roots/r1/symstor/.git" ]; then
    pass "security A5: symlinked storage refused at use time"
else
    fail "security A5: symstor arm (rc=$_rc out=$_out)"
fi

# A6: revert requires a dev-owned target — a planted, runner-foreign
# gitdir (root-owned here: the runner cannot own it) is skipped. The
# foreign owner rides a SCRATCH install.conf (an env assignment prefix
# never reaches _gp_var's conf read).
mkdir -p "$WORK/roots/r1/plant" "$WORK/storage/evil.git"
printf 'gitdir: %s\n' "$WORK/storage/evil.git" >"$WORK/roots/r1/plant/.git"
printf 'HEAD' >"$WORK/storage/evil.git/HEAD"
printf 'DEFAULT_USER=root\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -gn)" >"$WORK/ic-a6"
_rc=0
_out=$(_core_run 'GP_INSTALL_CONF="$WORK/ic-a6" _gp_revert_one "$WORK/roots/r1/plant"') || _rc=$?
if [ "$_rc" = 0 ] && printf '%s' "$_out" | grep -qF 'gitdir not dev-owned' &&
    [ -d "$WORK/storage/evil.git" ]; then
    pass "security A6: non-dev-owned storage entry is not reverted"
else
    fail "security A6: plant arm (rc=$_rc out=$_out)"
fi

# B4: linked worktrees survive revert --all (the registration is never
# moved; the main project's repair leg fixes the worktree pointer).
# Fresh root r3 so leftover section-5 fixtures cannot pollute the sweep.
mkdir -p "$WORK/roots/r3"
printf '%s\n' "$WORK/roots/r3" >"$CONF"
_mkrepo "$WORK/roots/r3/wtrt"
git -C "$WORK/roots/r3/wtrt" worktree add "$WORK/roots/r3/wtrt-side" -q 2>/dev/null ||
    git -C "$WORK/roots/r3/wtrt" worktree add -q "$WORK/roots/r3/wtrt-side"
_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r3/wtrt" yes') || _rc=$?
if [ "$_rc" = 0 ]; then
    # the worktree path ITSELF is a skip while adopted (the B4 guard).
    _rc=0
    _out=$(_core_run '_gp_revert_one "$WORK/roots/r3/wtrt-side"') || _rc=$?
    if [ "$_rc" = 0 ] && printf '%s' "$_out" | grep -qF 'worktree registration'; then
        pass "security B4: the worktree registration itself is never reverted"
    else
        fail "security B4: wt-path arm (rc=$_rc out=$_out)"
    fi
    _rc2=0
    _out2=$(_core_run '_gp_revert_all') || _rc2=$?
    if [ "$_rc2" = 0 ] && [ -d "$WORK/roots/r3/wtrt/.git" ] &&
        [ -f "$WORK/roots/r3/wtrt-side/.git" ] &&
        git -C "$WORK/roots/r3/wtrt-side" status --porcelain >/dev/null 2>&1; then
        pass "security B4: revert --all leaves linked worktrees working"
    else
        fail "security B4: revert roundtrip (rc=$_rc2 wtptr=$(cat "$WORK/roots/r3/wtrt-side/.git" 2>/dev/null))"
    fi
else
    fail "security B4: migrate leg failed (rc=$_rc out=$_out)"
fi
printf '%s\n' "$WORK/roots/r1" >"$CONF"

# C1 (with the A9 trigger): a heal chown failure rolls the migration
# back — the caller's rollback arm is LIVE. The bad group rides a
# scratch install.conf (env prefixes never reach _gp_var's conf read).
_mkrepo "$WORK/roots/r1/badgrp"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=no-such-group-xyz\n' \
    "$(id -un)" "$(id -un)" >"$WORK/ic-c1"
_rc=0
_out=$(_core_run 'GP_INSTALL_CONF="$WORK/ic-c1" _gp_migrate_one "$WORK/roots/r1/badgrp" yes') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'chown -R failed' &&
    printf '%s' "$_out" | grep -qF 'rolling back' &&
    [ -d "$WORK/roots/r1/badgrp/.git" ] &&
    git -C "$WORK/roots/r1/badgrp" status --porcelain >/dev/null 2>&1; then
    pass "security C1/A9: heal chown failure rolls back loudly"
else
    fail "security C1: badgroup arm (rc=$_rc out=$_out)"
fi

# B2: off with an unresolvable storage over existing pointers refuses
# and keeps the marker (GP_STORAGE unset so the conf's "none" governs).
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=none\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; _git_protection_off') || _rc=$?
if [ "$_rc" = 1 ] &&
    printf '%s' "$_out" | grep -qF 'storage is not resolvable' &&
    [ "$(sed -n 's/^GITDIR_STORAGE=//p' "$IC")" = "none" ]; then
    pass "security B2: off refuses over orphan-able pointers, keeps the config"
else
    fail "security B2: off-honesty arm (rc=$_rc out=$_out)"
fi
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"

# C5: a getent-failing agent user still refuses the literal agent-home
# root (the bounded degradation the finding names) — scratch conf with
# a NONEXISTENT agent user so getent itself fails.
printf 'DEFAULT_USER=%s\nOPENCODE_USER=no-such-agent-xyz\n' "$(id -un)" >"$WORK/ic-c5"
printf '%s\n' "/home/no-such-agent-xyz" >"$CONF"
_out=$(
    GP_STORAGE="$WORK/storage" GP_CONF="$CONF" GP_INSTALL_CONF="$WORK/ic-c5" sh -c '
        . "$1"
        _gp_root_ok "/home/no-such-agent-xyz"
        echo "rc=$?"
    ' _ "$CORE" 2>&1
)
if printf '%s' "$_out" | grep -qF 'rc=2'; then
    pass "security C5: literal agent-home arm covers a getent failure"
else
    fail "security C5: getent-failure arm (out=$_out)"
fi

# --- 10b. round-b arms (#754 b) ------------------------------------------------------

# D1: the nail sweep never seals a worktree registration (a sealed
# pointer would block the main project's repair leg) — run the REAL
# sweep over a migrated project with a linked worktree.
mkdir -p "$WORK/roots/r4"
printf '%s\n' "$WORK/roots/r4" >"$CONF"
_mkrepo "$WORK/roots/r4/d1p"
git -C "$WORK/roots/r4/d1p" worktree add "$WORK/roots/r4/d1w" -q 2>/dev/null ||
    git -C "$WORK/roots/r4/d1p" worktree add -q "$WORK/roots/r4/d1w"
_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r4/d1p" yes') || _rc=$?
_rc2=0
_out2=$(_core_run '_git_protection_nail') || _rc2=$?
if [ "$_rc" = 0 ] && [ "$_rc2" = 0 ] &&
    [ ! -e "$WORK/roots/r4/d1w/.git.nailed" ] &&
    [ -e "$WORK/roots/r4/d1p/.git.nailed" ]; then
    pass "security D1: the nail sweep seals the main pointer, never the worktree's"
else
    fail "security D1: nail-sweep arm (rc=$_rc rc2=$_rc2 out=$_out2)"
fi
_out=$(_core_run '_gp_projects')
if printf '%s' "$_out" | grep -qxF "worktree-reg $WORK/roots/r4/d1w" &&
    ! printf '%s' "$_out" | grep -qxE "(nailed|unnailed) $WORK/roots/r4/d1w"; then
    pass "security D1/D3: a migrated worktree classifies worktree-reg (not actionable)"
else
    fail "security D1/D3: classification (out=$(printf '%s' "$_out" | tr '\n' ';'))"
fi
_rc=0
_out=$(_core_run 'git_protection_cli status') || _rc=$?
if [ "$_rc" = 0 ]; then
    pass "security D3: status rc 0 with a nailed main + worktree-reg rows only"
else
    fail "security D3: status rc (rc=$_rc out=$_out)"
fi
# and off succeeds end-to-end (no skip-refusal over the worktree row):
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\nGITDIR_STORAGE=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" "$WORK/storage" >"$IC"
_rc=0
_out=$(_core_run 'unset GP_STORAGE; _git_protection_off') || _rc=$?
if [ "$_rc" = 0 ] && [ -d "$WORK/roots/r4/d1p/.git" ] &&
    git -C "$WORK/roots/r4/d1w" status --porcelain >/dev/null 2>&1; then
    pass "security D1/D2: off succeeds over a worktree host (no forced re-run)"
else
    fail "security D1/D2: off arm (rc=$_rc out=$_out)"
fi
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nOPENCODE_GROUP=%s\n' \
    "$(id -un)" "$(id -un)" "$(id -gn)" >"$IC"
printf '%s\n' "$WORK/roots/r1" >"$CONF"

# D7: a storage whose OWN path contains a "worktrees" component does
# not swallow its main gitdirs — classification keys on the
# .git/worktrees/ shape, not the bare component.
rm -rf "${WORK:?}/wtcomp"
mkdir -p "$WORK/wtcomp"
_mkrepo "$WORK/roots/r1/wtc"
mv "$WORK/roots/r1/wtc/.git" "$WORK/wtcomp/wtc.git"
printf 'gitdir: %s\n' "$WORK/wtcomp/wtc.git" >"$WORK/roots/r1/wtc/.git"
_out=$(_core_run 'GP_STORAGE="$WORK/wtcomp" _gp_projects')
if printf '%s' "$_out" | grep -qxF "unnailed $WORK/roots/r1/wtc" &&
    ! printf '%s' "$_out" | grep -qxF "worktree-reg $WORK/roots/r1/wtc"; then
    pass "security D7: a worktrees-named storage keeps classifying its mains"
else
    fail "security D7: wtcomp classification (out=$(printf '%s' "$_out" | tr '\n' ';'))"
fi
# direct nail call on a worktree registration is refused (D1 belt).
_rc=0
_out=$(_core_run '_gp_nail_one "$WORK/roots/r4/d1w" "$WORK/storage/d1p.git/worktrees/d1w"') || _rc=$?
if [ "$_rc" = 1 ] && printf '%s' "$_out" | grep -qF 'worktree registration'; then
    pass "security D1: direct nail of a worktree registration refused"
else
    fail "security D1: nail belt (rc=$_rc out=$_out)"
fi

# D6/A1 observables: the pointer is a REGULAR file, no staging residue
# (noimm: migrated in section 6, still on the pointer layout).
if [ -f "$WORK/roots/r1/noimm/.git" ] && [ ! -L "$WORK/roots/r1/noimm/.git" ] &&
    [ -z "$(ls "$WORK/roots/r1/noimm/".git.opk* 2>/dev/null || true)" ]; then
    pass "fix-wave A1: pointer is a regular file, no staging residue"
else
    fail "fix-wave A1: observables (residue=$(ls "$WORK/roots/r1/noimm/".git.opk* 2>/dev/null || true))"
fi

# D6/A7/E1: _gp_unnest restores ours from the nested shape (the only
# reachable nest is depth 1 — probed; junk inside rides along).
_mkrepo "$WORK/roots/r1/nn1"
mkdir -p "$WORK/storage/nn1.git"
mv "$WORK/roots/r1/nn1/.git" "$WORK/storage/nn1.git/.git"
_rc=0
_out=$(_core_run '_gp_unnest "$WORK/storage/nn1.git" "$WORK/roots/r1/nn1"') || _rc=$?
if [ "$_rc" = 0 ] && [ -e "$WORK/roots/r1/nn1/.git/HEAD" ]; then
    pass "fix-wave A7: _gp_unnest restores the nested gitdir (plain)"
else
    fail "fix-wave A7: unnest plain (rc=$_rc out=$_out)"
fi
_mkrepo "$WORK/roots/r1/nn2"
# #754 c E1 regression: junk `.git` planted INSIDE the moved gitdir
# (the reachable state the retired deepest-heuristic misfired on) —
# unnest must still take the depth-1 dir (ours, junk rides along).
mkdir -p "$WORK/storage/nn2.git"
mv "$WORK/roots/r1/nn2/.git" "$WORK/storage/nn2.git/.git"
mkdir -p "$WORK/storage/nn2.git/.git/.git"
_rc=0
_out=$(_core_run '_gp_unnest "$WORK/storage/nn2.git" "$WORK/roots/r1/nn2"') || _rc=$?
if [ "$_rc" = 0 ] && [ -e "$WORK/roots/r1/nn2/.git/HEAD" ] &&
    [ -d "$WORK/roots/r1/nn2/.git/.git" ]; then
    pass "fix-wave E1: unnest takes depth 1 (ours) — junk rides inside"
else
    fail "fix-wave E1: unnest junk arm (rc=$_rc out=$_out)"
fi

# D6/E3: the dir-aware rollback recovers the D8 planted-dir shape —
# plant (with residue) at .git, gitdir external: rollback must put
# the gitdir AT the name, not nested inside the plant.
_mkrepo "$WORK/roots/r1/e2p"
mv "$WORK/roots/r1/e2p/.git" "$WORK/storage/e2p.git"
mkdir -p "$WORK/roots/r1/e2p/.git"
touch "$WORK/roots/r1/e2p/.git/opk-residue"
_rc=0
_out=$(_core_run '_gp_rollback "$WORK/roots/r1/e2p" "$WORK/storage/e2p.git"') || _rc=$?
if [ "$_rc" = 0 ] && [ -e "$WORK/roots/r1/e2p/.git/HEAD" ] &&
    [ ! -e "$WORK/roots/r1/e2p/.git/e2p.git" ] &&
    [ ! -e "$WORK/roots/r1/e2p/.git/opk-residue" ]; then
    pass "fix-wave E2/E3: dir-aware rollback removes the plant, lands the gitdir at the name"
else
    fail "fix-wave E2/E3: rollback arm (rc=$_rc out=$_out)"
fi
# D6/C3: a failed chattr -i on revert is named (GP_CHATTR_FAIL seam).
_mkrepo "$WORK/roots/r1/c3p"
rm -rf "${WORK:?}/storage/c3p.git" "${WORK:?}/roots/r1/c3p/.git"
mkdir -p "$WORK/storage/c3p.git"
printf 'gitdir: %s\n' "$WORK/storage/c3p.git" >"$WORK/roots/r1/c3p/.git"
_rc=0
_out=$(GP_CHATTR_FAIL=1 _core_run '_gp_revert_one "$WORK/roots/r1/c3p"') || _rc=$?
if printf '%s' "$_out" | grep -qF 'chattr -i failed'; then
    pass "fix-wave C3: revert names a failed chattr -i"
else
    fail "fix-wave C3: chattr warn (rc=$_rc out=$_out)"
fi

# D6/C4: a failing worktree enumeration warns (PATH-stubbed git).
mkdir -p "$WORK/badgit"
printf '#!/bin/sh\nexit 1\n' >"$WORK/badgit/git"
chmod 755 "$WORK/badgit/git"
_mkrepo "$WORK/roots/r1/c4p"
_out=$(
    PATH="$WORK/badgit:/usr/bin:/bin" sh -c '
        . "$1"
        ui_warn() { echo "warn: $*" >&2; }
        _gp_worktrees "$2"
    ' _ "$CORE" "$WORK/roots/r1/c4p/.git" 2>&1
) || true
if printf '%s' "$_out" | grep -qF 'worktree enumeration failed'; then
    pass "fix-wave C4: enumeration failure warns"
else
    fail "fix-wave C4: enumeration warn (out=$_out)"
fi

suite_done "git-protection core tests"
