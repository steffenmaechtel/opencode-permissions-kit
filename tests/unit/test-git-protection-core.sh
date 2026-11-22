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
#     collision suffix, worktree repair, rollback), nail gating
#     (storage prefix, dev ownership, chattr failure, lsattr verify),
#     revert (kit-owned only, happy path), status rc semantics, and
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
_gp_conf_path _gp_storage _gp_nosym _gp_storage_init _gp_persist_storage
_gp_drop_storage _gp_has_i _gp_devgit _gp_verify _gp_rollback _gp_worktrees
_gp_heal_gitdir _gp_pform_ok _gp_storage_sane _gp_unnest _gp_migrate_one
_gp_nail_one _gp_revert_one _gp_projects _gp_revert_all
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
# status still runs — here just the empty-conf rc-1 shape (no projects
# actionable is rc 0; the actionable arm is section 8).
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
if [ "$rc" = 0 ] && printf '%s' "$out" | grep -qF 'kv: storage'; then
    pass "cli: status runs unprivileged (no elevation, no GP_ALLOW_NONROOT)"
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

# collision suffix: a second project with the same basename.
_mkrepo "$WORK/roots/r1/sub/proj1"
_rc=0
_out=$(_core_run '_gp_migrate_one "$WORK/roots/r1/sub/proj1" yes') || _rc=$?
if [ "$_rc" = 0 ] && [ -d "$WORK/storage/proj1-2.git" ] &&
    [ "$(cat "$WORK/roots/r1/sub/proj1/.git")" = "gitdir: $WORK/storage/proj1-2.git" ]; then
    pass "migrate: name collision gets a -2 suffix"
else
    fail "migrate: collision arm (rc=$_rc out=$_out)"
fi

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

suite_done "git-protection core tests"
