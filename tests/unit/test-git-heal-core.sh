#!/bin/sh
# Unit tests for the git heal hooks subsystem (issue #671):
#
#   files/opencode-permissions-kit-lib/git-heal/heal-index-head -- the
#     narrow root heal (executed by the hooks via the sudoers grant):
#     argument/allowlist/shape refusals, symlink + hardlink operand
#     skips, the chown-failure and log-failure arms, the successful
#     heal's audit lines.
#   files/opencode-permissions-kit-lib/git-heal/hooks/post-* -- the
#     four identical developer-side hook bodies: byte-identity, the
#     MEASURED carrier matrix (post-checkout on checkout/switch,
#     post-index-change on add/reset/commit + stale-cache status, no
#     fire on fresh-cache status, post-merge on ff-pull, post-rewrite
#     on rebase, common-dir resolution for worktrees), the hard no-op
#     outside kit-managed roots, projects.conf comment tolerance, and
#     the fail-loud sudo-failed arm.
#   files/opencode-permissions-kit-lib/sh/git-heal-core.sh -- the
#     `opk git-heal` logic: state machine (off/on/foreign/unknown),
#     `on` (pieces gate, sudoers re-render, dev gitconfig write,
#     one-time heal sweep), `off` (kit-owned value only), usage rc 64,
#     the dispatcher loop-guard marker.
#
# Root code runs UNPRIVILEGED here: the heal script's root gate is
# relaxed via its documented GH_ALLOW_NONROOT override and chowns to
# the running user (a permitted no-op chown whose rc + audit line are
# the observables); the real two-uid ownership flip is pinned by the
# e2e suites. Hooks execute the heal through a stub sudo (exec "$@"),
# so the whole carrier matrix runs as this user on scratch repos.
# Run: sh tests/unit/test-git-heal-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_FILES="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib"
HEAL="$REPO_FILES/git-heal/heal-index-head"
HOOKS="$REPO_FILES/git-heal/hooks"
CORE="$REPO_FILES/sh/git-heal-core.sh"

# Shared harness (issue #394): pass/fail/assert_eq + the work registry
# (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"
WORK="$(work_new)"

# The unit overrides every GH_* consumer documents (git-heal-core.sh
# and heal-index-head headers): allowlist, log, agent user, nonroot
# gate, library base, developer home, privileged-drop prefix. The
# matrix sudo stub strips leading sudo flags (-n and kin) and execs
# the command directly -- git prepends GIT_EXEC_PATH to the hook's
# PATH but passes the rest through unchanged (measured).
CONF="$WORK/projects.conf"
LOG="$WORK/heal.log"
mkdir -p "$WORK/sbin"
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do\n    case "$1" in\n    -*) shift ;;\n    *) break ;;\n    esac\ndone\nexec "$@"\n' >"$WORK/sbin/sudo"
chmod +x "$WORK/sbin/sudo"

# --- 1. heal-index-head: argument + allowlist refusals ----------------------------

_heal_rc() { # <env...> -- <args...>: rc in _hr_rc, output in _hr_out
    _hr_rc=0
    _hr_out=$(env "$@" "$HEAL" ${2+"$@"} 2>&1) || _hr_rc=$?
}

mkdir -p "$WORK/r1"
printf '%s\n' "$WORK" >"$CONF"
: >"$LOG"

_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_PROJECTS_CONF="$CONF" "$HEAL" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_hr_out" | grep -qF 'usage:'; then
    pass "heal: no argument is a loud usage error"
else
    fail "heal: usage arm (rc=$_hr_rc out=$_hr_out)"
fi

_hr_rc=0
_hr_out=$("$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_hr_out" | grep -qF 'must run as root'; then
    pass "heal: non-root without the test override is refused"
else
    fail "heal: root gate (rc=$_hr_rc out=$_hr_out)"
fi

_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_PROJECTS_CONF="$CONF" "$HEAL" r1 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_hr_out" | grep -qF 'not an absolute path'; then
    pass "heal: relative gitdir refused"
else
    fail "heal: relative arm (rc=$_hr_rc out=$_hr_out)"
fi

_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_PROJECTS_CONF="$CONF" "$HEAL" /tmp 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_hr_out" | grep -qF 'outside kit-managed roots'; then
    pass "heal: gitdir outside the projects.conf roots refused"
else
    fail "heal: allowlist arm (rc=$_hr_rc out=$_hr_out)"
fi

# --- 1b. heal: conf-line reader gate (#674 a A1) — a hand-edited line
# never authorizes a heal. Arms run WITHOUT GH_CONF_RELAX (system-path
# and agent-home arms live) except where a relax arm is named — the
# form arms (absolute, dot/empty segment, whitespace) never relax.

printf '%s\n' "/etc" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_PROJECTS_CONF="$CONF" "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'skip (conf): system path is never a project root: /etc' &&
    printf '%s' "$_hr_out" | grep -qF 'outside kit-managed roots'; then
    pass "heal: system-path conf line skipped loudly, authorizes nothing"
else
    fail "heal: conf system-path arm (rc=$_hr_rc out=$_hr_out)"
fi

printf '%s\n' "relative/root" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_PROJECTS_CONF="$CONF" "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'skip (conf): not an absolute root: relative/root'; then
    pass "heal: non-absolute conf line skipped"
else
    fail "heal: conf absolute arm (rc=$_hr_rc out=$_hr_out)"
fi

_ahome=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)
if [ -n "$_ahome" ]; then
    printf '%s\n' "$_ahome" >"$CONF"
    _hr_rc=0
    _hr_out=$(env GH_ALLOW_NONROOT=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
        "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
    if [ "$_hr_rc" -eq 1 ] &&
        printf '%s' "$_hr_out" | grep -qF "skip (conf): agent home is never a project root: $_ahome"; then
        pass "heal: agent-home conf line skipped"
    else
        fail "heal: conf agent-home arm (rc=$_hr_rc out=$_hr_out)"
    fi
fi

# Trailing-slash conf roots match after normalization (writer parity:
# the strip-then-compare shape) — the refusal below is the SHAPE
# gate's, proving the allowlist matched the normalized root.
printf '%s\n' "$WORK/r1/" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'not a (common) gitdir shape' &&
    ! printf '%s' "$_hr_out" | grep -qF 'outside kit-managed roots'; then
    pass "heal: trailing-slash conf root matches after normalization"
else
    fail "heal: conf trailing-slash arm (rc=$_hr_rc out=$_hr_out)"
fi

# Form gates stay live under GH_CONF_RELAX, and a refused line never
# poisons the good ones riding along in the same conf: the malformed
# line is skipped loudly while the well-formed root still matches.
printf '%s\n' "//malformed" "$WORK/r1" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'skip (conf): malformed root' &&
    printf '%s' "$_hr_out" | grep -qF 'not a (common) gitdir shape' &&
    ! printf '%s' "$_hr_out" | grep -qF 'outside kit-managed roots'; then
    pass "heal: malformed line skipped, well-formed sibling still matches (relax keeps form gates)"
else
    fail "heal: conf mixed-lines arm (rc=$_hr_rc out=$_hr_out)"
fi

# The `/` line (strip-to-empty) refuses LOUD in every mode — it sits
# before the relax guard (#674 b D1; silent before).
printf '%s\n' "/" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'skip (conf): system path is never a project root: /'; then
    pass "heal: bare / conf line refuses loud (strip-to-empty arm)"
else
    fail "heal: conf slash arm (rc=$_hr_rc out=$_hr_out)"
fi

# Dot and whitespace form arms execute UNDER relax — the "form arms
# never relax" claim, pinned (#674 b D4); both lines are skipped, so
# the gitdir matches nothing.
printf '%s\n' "$WORK/r1/../r1" "$WORK /gap" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'skip (conf): malformed root' &&
    ! printf '%s' "$_hr_out" | grep -qF 'not a (common) gitdir shape'; then
    pass "heal: dot and whitespace conf lines refused even under relax"
else
    fail "heal: conf form-arms-under-relax (rc=$_hr_rc out=$_hr_out)"
fi

printf '%s\n' "$WORK" >"$CONF"

# --- 2. heal-index-head: realpath + gitdir-shape refusals --------------------------

# The literal check passes (the link sits under an allowlisted root),
# the realpath-resolved form lands OUTSIDE it -> the second check must
# refuse (a symlinked gitdir must not smuggle an outside path).
mkdir -p "$WORK/inroot-zone" "$WORK/smuggle-target/real"
ln -s "$WORK/smuggle-target/real" "$WORK/inroot-zone/link"
printf '%s\n' "$WORK/inroot-zone" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    "$HEAL" "$WORK/inroot-zone/link" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_hr_out" | grep -qF 'refused after realpath'; then
    pass "heal: symlinked gitdir cannot smuggle an outside path past the literal check"
else
    fail "heal: realpath arm (rc=$_hr_rc out=$_hr_out)"
fi
printf '%s\n' "$WORK" >"$CONF"

mkdir -p "$WORK/plain"
: >"$WORK/plain/HEAD"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" "$HEAL" "$WORK/plain" 2>&1) ||
    _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_hr_out" | grep -qF 'not a (common) gitdir shape'; then
    pass "heal: non-gitdir shape refused"
else
    fail "heal: shape arm (rc=$_hr_rc out=$_hr_out)"
fi

# A worktree registration carries HEAD but no objects/ — rejected by
# the same shape gate, which is why only the COMMON gitdir is healed.
git -C "$WORK" init -q -b main wt-main 2>/dev/null
git -C "$WORK/wt-main" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
git -C "$WORK/wt-main" worktree add -q "$WORK/wt-second" -b wt-branch 2>/dev/null
_reg=$(find "$WORK/wt-main/.git/worktrees" -mindepth 1 -maxdepth 1 -type d | head -1)
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" "$HEAL" "$_reg" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_hr_out" | grep -qF 'not a (common) gitdir shape'; then
    pass "heal: worktree registration dir rejected by shape"
else
    fail "heal: worktree-shape arm (rc=$_hr_rc out=$_hr_out)"
fi

# --- 3. heal-index-head: operand skips + success + failure arms --------------------

git -C "$WORK" init -q -b main repo3 2>/dev/null
git -C "$WORK/repo3" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
rm -f "$LOG" && : >"$LOG"
rm -f "${WORK:?}/repo3/.git/index"
ln -s /dev/null "$WORK/repo3/.git/index"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && printf '%s' "$_hr_out" | grep -qF 'skip (symlink)'; then
    pass "heal: symlinked operand skipped, never followed"
else
    fail "heal: symlink-skip arm (rc=$_hr_rc out=$_hr_out)"
fi

rm -f "${WORK:?}/repo3/.git/index"
git -C "$WORK/repo3" read-tree HEAD 2>/dev/null
ln "$WORK/repo3/.git/index" "$WORK/hardlink-mate"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && printf '%s' "$_hr_out" | grep -qF 'skip (hardlink, nlink>1)'; then
    pass "heal: hardlinked operand skipped (a chown would re-own the shared inode)"
else
    fail "heal: hardlink-skip arm (rc=$_hr_rc out=$_hr_out)"
fi
rm -f "${WORK:?}/hardlink-mate"

rm -f "$LOG" && : >"$LOG"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
_lines=$(grep -c 'healed' "$LOG" || true)
if [ "$_hr_rc" -eq 0 ] && [ "$_lines" -ge 2 ] &&
    grep -qF 'healed index' "$LOG" && grep -qF 'healed HEAD' "$LOG" &&
    grep -qF "gitdir=$WORK/repo3/.git" "$LOG" && grep -qF 'caller_uid=' "$LOG"; then
    pass "heal: successful run audits one line per file (index + HEAD)"
else
    fail "heal: success arm (rc=$_hr_rc lines=$_lines log=$(cat "$LOG"))"
fi

# A missing operand (index removed; HEAD stays -- the shape gate
# requires it) is a quiet no-op for that file, the other still heals.
rm -f "${WORK:?}/repo3/.git/index"
: >"$LOG"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && [ "$(grep -c healed "$LOG" || true)" = 1 ]; then
    pass "heal: a missing operand is a quiet no-op for that file"
else
    fail "heal: missing-operand arm (rc=$_hr_rc log=$(cat "$LOG"))"
fi
git -C "$WORK/repo3" read-tree HEAD 2>/dev/null

# --- 3b. heal-index-head: the #678 widened operand set ------------------------------
# The measured carriers heal with the same audit contract; proven
# non-carriers stay untouched even when present (discrimination arm).

for _op in ORIG_HEAD REBASE_HEAD packed-refs MERGE_HEAD MERGE_MSG \
    MERGE_MODE AUTO_MERGE CHERRY_PICK_HEAD REVERT_HEAD; do
    : >"$WORK/repo3/.git/$_op"
done
rm -f "$LOG" && : >"$LOG"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
_lines=$(grep -c 'healed' "$LOG" || true)
if [ "$_hr_rc" -eq 0 ] && [ "$_lines" -eq 11 ] &&
    grep -qF 'healed ORIG_HEAD' "$LOG" &&
    grep -qF 'healed REBASE_HEAD' "$LOG" &&
    grep -qF 'healed packed-refs' "$LOG" &&
    grep -qF 'healed MERGE_HEAD' "$LOG" &&
    grep -qF 'healed MERGE_MSG' "$LOG" &&
    grep -qF 'healed MERGE_MODE' "$LOG" &&
    grep -qF 'healed AUTO_MERGE' "$LOG" &&
    grep -qF 'healed CHERRY_PICK_HEAD' "$LOG" &&
    grep -qF 'healed REVERT_HEAD' "$LOG"; then
    pass "heal: the #678 operand set heals per existing file (11 audit lines, every operand named — a swap for any present file reds)"
else
    fail "heal: widened-set arm (rc=$_hr_rc lines=$_lines log=$(cat "$LOG"))"
fi

# Gates apply to the widened set exactly as to index/HEAD: a symlinked
# ORIG_HEAD is skipped loudly, the other operands still heal.
rm -f "${WORK:?}/repo3/.git/ORIG_HEAD"
ln -s /dev/null "$WORK/repo3/.git/ORIG_HEAD"
rm -f "$LOG" && : >"$LOG"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    printf '%s' "$_hr_out" | grep -qF 'skip (symlink)' &&
    ! grep -qF 'healed ORIG_HEAD' "$LOG" &&
    grep -qF 'healed REBASE_HEAD' "$LOG"; then
    pass "heal: symlink gate holds for the widened set (ORIG_HEAD skipped)"
else
    fail "heal: widened symlink arm (rc=$_hr_rc out=$_hr_out log=$(cat "$LOG"))"
fi
rm -f "${WORK:?}/repo3/.git/ORIG_HEAD"

# Proven non-carriers are NOT healed even when present: FETCH_HEAD and
# COMMIT_EDITMSG write in place and never flip (measured #678) -- the
# operand list must not grow them by accident.
: >"$WORK/repo3/.git/FETCH_HEAD"
: >"$WORK/repo3/.git/COMMIT_EDITMSG"
rm -f "$LOG" && : >"$LOG"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    ! grep -qF 'healed FETCH_HEAD' "$LOG" &&
    ! grep -qF 'healed COMMIT_EDITMSG' "$LOG" &&
    grep -qF 'healed index' "$LOG"; then
    pass "heal: measured non-carriers (FETCH_HEAD, COMMIT_EDITMSG) stay untouched"
else
    fail "heal: non-carrier arm (rc=$_hr_rc log=$(cat "$LOG"))"
fi
rm -f "${WORK:?}/repo3/.git/FETCH_HEAD" "${WORK:?}/repo3/.git/COMMIT_EDITMSG"
for _op in REBASE_HEAD packed-refs MERGE_HEAD MERGE_MSG \
    MERGE_MODE AUTO_MERGE CHERRY_PICK_HEAD REVERT_HEAD; do
    rm -f "${WORK:?}/repo3/.git/$_op"
done

_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER=nosuchuser-gh GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && [ "$(printf '%s' "$_hr_out" | grep -cF 'chown failed')" -ge 2 ]; then
    pass "heal: chown failure warns per operand and never breaks the run"
else
    fail "heal: chown-fail arm (rc=$_hr_rc out=$_hr_out)"
fi

_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$WORK/no-such-dir/x/heal.log" "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && printf '%s' "$_hr_out" | grep -qF 'could not append'; then
    pass "heal: an unwritable log degrades loud, the heal still completes"
else
    fail "heal: log-fail arm (rc=$_hr_rc out=$_hr_out)"
fi

# --- 4. hook bodies: byte-identity -------------------------------------------------

_ident=1
for _h in post-merge post-rewrite post-index-change; do
    cmp -s "$HOOKS/post-checkout" "$HOOKS/$_h" || _ident=0
done
if [ "$_ident" = 1 ]; then
    pass "hooks: the four shipped bodies are byte-identical (filename selects the event)"
else
    fail "hooks: body drift across post-merge/post-checkout/post-rewrite/post-index-change"
fi

# --- 5. the carrier matrix (measured, not assumed — #671 pilot) --------------------
# Scratch lib + stub sudo: the hooks resolve the shipped logic against
# GH_LIBDIR, sudo de-escalates to this user, the heal runs with its
# nonroot override. Every assertion compares audit-line counts.
# _mlog: the healed-line count, 0-safe (grep -c already prints 0 on a
# no-match rc 1; only a MISSING file must map to 0 explicitly).

mkdir -p "$WORK/lib/git-heal/hooks" "$WORK/zone"
cp "$HEAL" "$WORK/lib/git-heal/"
for _h in post-merge post-checkout post-rewrite post-index-change; do
    cp "$HOOKS/$_h" "$WORK/lib/git-heal/hooks/"
done
printf '%s\n' "$WORK/zone" "# a comment line rides along (#660 M6)" "" >"$CONF"
: >"$LOG"

_gitenv() { # env prefix for every matrix git call
    printf 'GH_LIBDIR=%s GH_PROJECTS_CONF=%s GH_LOG=%s GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER=%s' \
        "$WORK/lib" "$CONF" "$LOG" "$(id -un)"
}
_mgit() { # git in the matrix zone (hooks + env applied)
    env PATH="$WORK/sbin:$PATH" $(_gitenv) git -C "$WORK/zone/repo" "$@"
}
_mlog() {
    _ml_n=$(grep -c 'healed' "$LOG" 2>/dev/null) || true
    printf '%s\n' "${_ml_n:-0}"
}

git -C "$WORK/zone" init -q -b main repo
git -C "$WORK/zone/repo" config user.email t@e
git -C "$WORK/zone/repo" config user.name t
git -C "$WORK/zone/repo" config core.hooksPath "$WORK/lib/git-heal/hooks"
echo one >"$WORK/zone/repo/f"
_mgit add f
_mgit commit -q -m c1

_before=$(_mlog)
_mgit checkout -q -b side
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: checkout -b heals via post-checkout"
else
    fail "matrix: checkout -b did not fire a heal"
fi

_before=$(_mlog)
_mgit checkout -q main
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: cross-branch checkout heals via post-checkout"
else
    fail "matrix: cross-branch checkout did not fire a heal"
fi

_before=$(_mlog)
_mgit reset -q --hard HEAD
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: reset --hard heals via post-index-change (no post-reset exists)"
else
    fail "matrix: reset --hard did not fire a heal"
fi

echo two >"$WORK/zone/repo/f"
# Deterministic freshness (the sleep-only settle flaked while two e2e
# suites loaded the host): staging caches this OLD mtime, so the entry
# can never be racily-clean (file mtime < index write second) and the
# fresh-cache status below is provably quiet under any load.
touch -d "@$(($(date +%s) - 120))" "$WORK/zone/repo/f"
_before=$(_mlog)
_mgit add f
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: git add heals via post-index-change"
else
    fail "matrix: git add did not fire a heal"
fi

_before=$(_mlog)
_mgit commit -q -m c2
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: commit's index write heals via post-index-change"
else
    fail "matrix: commit did not fire a heal"
fi

# Fresh-cache status: the index is CURRENT (f's cached stat is two
# minutes old -- the add/commit writes just refreshed everything), so
# status writes nothing and post-index-change must NOT fire. The racy
# nuance stays documented: a same-second mtime WOULD re-smudge
# (measured -- every same-second status rewrites the index until a
# second passes); the old-mtime staging keeps this arm out of that
# timing class.
_before=$(_mlog)
_mgit status --porcelain >/dev/null
if [ "$(_mlog)" = "$_before" ]; then
    pass "matrix: fresh-cache status writes nothing and fires nothing"
else
    fail "matrix: fresh-cache status fired a heal (over-firing)"
fi

# Stale-cache status: an mtime-touch without content change makes the
# refreshing status rewrite the index stat cache — the T5 pilot case
# (VS Code/gitk refreshing while the agent edits).
sleep 1
touch "$WORK/zone/repo/f"
_before=$(_mlog)
_mgit status --porcelain >/dev/null
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: stale-cache refreshing status heals via post-index-change (T5)"
else
    fail "matrix: stale-cache status did not fire a heal"
fi

# Racy-clean status — the same-second nuance the hook header documents,
# pinned as the racy half of the carrier claim (#674 a C1). A normally
# staged entry's cached mtime ties the index-write second; until a
# boundary-crossing rewrite stamps a newer index mtime, EVERY status
# re-smudges (rewrites the index, post-index-change fires) — the tie is
# between cache and index (both stamped by the add), so the firing is
# deterministic regardless of when the status runs; the sleep only
# guarantees the first status's rewrite lands in a later second, which
# makes the status after it provably quiet (the settled half).
echo racy >"$WORK/zone/repo/f"
_mgit add f
sleep 1
_before=$(_mlog)
_mgit status --porcelain >/dev/null
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: racy-clean statuses keep re-smudging until a second passes (fires)"
else
    fail "matrix: racy-clean status did not fire"
fi
_before=$(_mlog)
_mgit status --porcelain >/dev/null
if [ "$(_mlog)" = "$_before" ]; then
    pass "matrix: tie broken — the settled status after is quiet"
else
    fail "matrix: settled status fired again (tie not broken)"
fi

# Fast-forward pull: post-merge fires on --ff-only pulls (the pilot's
# scratch-proven carrier). Advance origin/main from a throwaway branch,
# keep local main behind, then pull --ff-only (no clone needed).
git -C "$WORK/zone" init -q --bare origin.git
_mgit remote add origin "$WORK/zone/origin.git"
_mgit push -q origin main 2>/dev/null
_mgit checkout -q -b throwaway
echo three >"$WORK/zone/repo/g"
_mgit add g
_mgit commit -q -m c3
_mgit push -q origin throwaway:main 2>/dev/null
_mgit checkout -q main
git -C "$WORK/zone/repo" branch -q -D throwaway
_before=$(_mlog)
env PATH="$WORK/sbin:$PATH" $(_gitenv) \
    git -C "$WORK/zone/repo" pull -q --ff-only origin main 2>/dev/null
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: fast-forward pull heals via post-merge"
else
    fail "matrix: ff-pull did not fire a heal"
fi

# Rebase: post-rewrite.
_mgit checkout -q -b feature
echo four >"$WORK/zone/repo/h"
_mgit add h
_mgit commit -q -m c4
_mgit checkout -q main
echo five >"$WORK/zone/repo/i"
_mgit add i
_mgit commit -q -m c5
_before=$(_mlog)
_mgit rebase -q HEAD feature >/dev/null 2>&1 || _mgit rebase feature >/dev/null 2>&1
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: rebase heals via post-rewrite"
else
    fail "matrix: rebase did not fire a heal"
fi

# Worktree: the hook must resolve the COMMON gitdir (the main .git is
# the allowlisted, heal-worthy dir) even when firing inside a worktree.
_before=$(_mlog)
env PATH="$WORK/sbin:$PATH" $(_gitenv) \
    git -C "$WORK/zone/repo" worktree add -q "$WORK/zone/wt2" -b wtb 2>/dev/null
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "matrix: worktree add heals the common gitdir (post-checkout, --git-common-dir)"
else
    fail "matrix: worktree add did not fire a heal"
fi

# --- 6. no-op outside the roots + carrier discrimination + sudo-failed arm ---------

git -C "$WORK" init -q -b main outside 2>/dev/null
# A commit first, or checkout -b runs on an unborn HEAD and never
# fires post-checkout -- the no-op pin would pass vacuously (found by
# sabotage cycle 3: deleting the allowlist left it green).
git -C "$WORK/outside" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
git -C "$WORK/outside" config user.email t@e
git -C "$WORK/outside" config user.name t
git -C "$WORK/outside" config core.hooksPath "$WORK/lib/git-heal/hooks"
_before=$(_mlog)
_out=$(env PATH="$WORK/sbin:$PATH" $(_gitenv) \
    git -C "$WORK/outside" checkout -q -b wherever 2>&1) || true
if [ "$(_mlog)" = "$_before" ] && [ -z "$_out" ]; then
    pass "no-op: a repo outside the kit roots heals nothing, prints nothing"
else
    fail "no-op: outside arm fired (log grew or stderr: $_out)"
fi

# Carrier discrimination: WITHOUT post-index-change the index-write
# family stops healing while checkout still does — the pin that keeps
# each op tied to its measured carrier.
mv "$WORK/lib/git-heal/hooks/post-index-change" "$WORK/pic-aside"
git -C "$WORK/outside" config --unset core.hooksPath
git -C "$WORK/zone/repo" config core.hooksPath "$WORK/lib/git-heal/hooks"
echo six >"$WORK/zone/repo/j"
_before=$(_mlog)
env PATH="$WORK/sbin:$PATH" $(_gitenv) git -C "$WORK/zone/repo" add j
if [ "$(_mlog)" = "$_before" ]; then
    pass "discrimination: add stops healing without post-index-change"
else
    fail "discrimination: add healed without post-index-change (wrong carrier)"
fi
_before=$(_mlog)
env PATH="$WORK/sbin:$PATH" $(_gitenv) \
    git -C "$WORK/zone/repo" checkout -q -b still-covered
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "discrimination: checkout still heals via post-checkout"
else
    fail "discrimination: checkout stopped healing too (carrier set broken)"
fi
mv "$WORK/pic-aside" "$WORK/lib/git-heal/hooks/post-index-change"

# Sudo exists but fails: the git op itself must survive, one stderr
# line explains the skip (fail-loud pin for the hook's || arm).
printf '#!/bin/sh\nexit 1\n' >"$WORK/sbin/sudo"
_before=$(_mlog)
_hr_rc=0
_out=$(env PATH="$WORK/sbin:$PATH" $(_gitenv) \
    git -C "$WORK/zone/repo" checkout -q -b sudo-broken 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && printf '%s' "$_out" | grep -qF 'heal skipped (sudo unavailable or failed)' &&
    [ "$(_mlog)" = "$_before" ]; then
    pass "sudo-failed: the git op survives, the skip is one loud line, nothing heals"
else
    fail "sudo-failed arm (rc=$_hr_rc out=$_out)"
fi
printf '#!/bin/sh\nexec "$@"\n' >"$WORK/sbin/sudo"

# --- 7. git-heal-core.sh: state machine + on/off/usage ------------------------------

_purity_out=$(sh -c '. "$1"' _ "$CORE" 2>&1) || _purity_rc=$?
if [ "${_purity_rc:-0}" = 0 ] && [ -z "$_purity_out" ]; then
    pass "core: sourcing git-heal-core.sh runs nothing, prints nothing"
else
    fail "core: sourcing must be side-effect free (rc=${_purity_rc:-0} out=$_purity_out)"
fi

_ui_stubs() {
    ui_info() { echo "info: $*"; }
    ui_success() { echo "success: $*"; }
    ui_detail() { echo "detail: $*"; }
    ui_error() { echo "error: $*" >&2; }
}
_core_run() { # <expr>: sources ui stubs + core with the scratch env
    (
        _ui_stubs
        . "$CORE"
        # exported: the heal sweep and git children must see them
        GH_LIBDIR="$WORK/lib"
        GH_DEV_HOME="$WORK/devhome"
        GH_SUDO=""
        GH_PROJECTS_CONF="$CONF"
        GH_LOG="$LOG"
        GH_ALLOW_NONROOT=1
        GH_CONF_RELAX=1
        GH_AGENT_USER="$(id -un)"
        INSTALL_CONF="$WORK/install.conf"
        export GH_LIBDIR GH_DEV_HOME GH_SUDO GH_PROJECTS_CONF GH_LOG \
            GH_ALLOW_NONROOT GH_CONF_RELAX GH_AGENT_USER INSTALL_CONF
        eval "$1"
    ) 2>&1
}

printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\n' "$(id -un)" "$(id -un)" >"$WORK/install.conf"
mkdir -p "$WORK/devhome"
: >"$WORK/devhome/.gitconfig"

_out=$(_core_run '_ghc_state')
if [ "$_out" = off ]; then
    pass "core: state off with no core.hooksPath"
else
    fail "core: state off (got $_out)"
fi

git config --file "$WORK/devhome/.gitconfig" core.hooksPath "$WORK/lib/git-heal/hooks"
_out=$(_core_run '_ghc_state')
if [ "$_out" = on ]; then
    pass "core: state on when hooksPath holds the kit dir"
else
    fail "core: state on (got $_out)"
fi

git config --file "$WORK/devhome/.gitconfig" core.hooksPath /dev/null
_out=$(_core_run '_ghc_state')
if [ "$_out" = foreign ]; then
    pass "core: state foreign for a non-kit value"
else
    fail "core: state foreign (got $_out)"
fi

rm -f "${WORK:?}/devhome/.gitconfig"
_out=$(GH_DEV_HOME="$WORK/devhome-no-such" INSTALL_CONF="$WORK/install.conf" sh -c \
    '. "$1"; ui_error() { echo "ERR: $*" >&2; }; _ghc_state' _ "$CORE" 2>&1)
if [ "$_out" = unknown ]; then
    pass "core: state unknown when the dev gitconfig is unreadable"
else
    fail "core: state unknown (got $_out)"
fi

# `on`: pieces + sudoers re-render + dev gitconfig + one-time heal sweep.
mkdir -p "$WORK/lib/sh" "$WORK/lib/templates" "$WORK/etc" "$WORK/sdd" "$WORK/zone/onroot"
cp "$REPO_FILES/sh/sudoers-deploy.sh" "$WORK/lib/sh/"
cp "$REPO_FILES/templates/sudoers.template" "$WORK/lib/templates/"
printf '#!/bin/sh\nexit 0\n' >"$WORK/visudo"
chmod +x "$WORK/visudo"
git -C "$WORK/zone/onroot" init -q -b main
git -C "$WORK/zone/onroot" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
# the sweep is recursive (find -name .git under each conf root — conf
# entries are scan roots; the heal output below asserts the sweep hit)
printf '%s\n' "$WORK/zone/onroot" "# comment tolerated" >"$WORK/on-projects.conf"
rm -f "${WORK:?}/devhome/.gitconfig"
: >"$LOG"
_hr_rc=0
_out=$(
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        HOME="$WORK/devhome" _git_heal_on'
) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ "$(git config --file "$WORK/devhome/.gitconfig" core.hooksPath)" = "$WORK/lib/git-heal/hooks" ] &&
    grep -q "^$(id -un) ALL=(root) NOPASSWD: /usr/local/lib/opencode-permissions-kit/git-heal/heal-index-head \*\$" \
        "$WORK/etc/sudoers" &&
    grep -qF "gitdir=$WORK/zone/onroot/.git" "$LOG" &&
    printf '%s' "$_out" | grep -qF "operand set re-pinned for $WORK/zone/onroot/.git" &&
    printf '%s' "$_out" | grep -qF 'success: git heal hooks active'; then
    pass "core: on renders sudoers, writes the dev gitconfig, heals the root once"
else
    fail "core: on leg failed (rc=$_hr_rc gc=$(git config --file "$WORK/devhome/.gitconfig" core.hooksPath 2>&1) sudoers=$(grep -c heal-index-head "$WORK/etc/sudoers" 2>/dev/null) log=$(wc -l <"$LOG"))"
fi
# #695: the sweep must SAY it is operand-only — the old wording read as
# "this .git is healed now" while the gitdir bits ride the fs baseline.
if printf '%s' "$_out" | grep -qF 'operand sweep only: the gitdir-level bits (sticky .git,' &&
    printf '%s' "$_out" | grep -qF "update' re-applies it when its semantics change"; then
    pass "core: on separates the operand sweep from the fs-baseline bits (#695)"
else
    fail "core: on must separate operand sweep and fs-baseline bits (#695)"
fi
# #710 a B1: the tee sits on the DATA path — a broken python3 (the
# health probe fails) must degrade to the cat passthrough: the sweep
# still heals and the warn names the degrade, never an empty list over
# a dead tee (the #221 a W3 class). heal-index-head needs no python3,
# so the broken stub can only hit the tee path.
mkdir -p "$WORK/badbin"
printf '#!/bin/sh\nexit 1\n' >"$WORK/badbin/python3"
chmod 755 "$WORK/badbin/python3"
printf '%s\n' "$WORK/zone/onroot" >"$WORK/on-projects.conf"
: >"$LOG"
_hr_rc=0
_out=$( (
    PATH="$WORK/badbin:$PATH"
    export PATH
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        HOME="$WORK/devhome" _git_heal_on'
) 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ "$(grep -c 'gitdir=' "$LOG" 2>/dev/null || true)" -ge 1 ] &&
    printf '%s' "$_out" | grep -qF 'operand set re-pinned for' &&
    printf '%s' "$_out" | grep -qF 'live progress unavailable (python3 missing or broken)'; then
    pass "core: broken python3 degrades to passthrough — sweep still heals, warn names it (#710 a B1)"
else
    fail "core: broken-python3 degrade leg (rc=$_hr_rc heals=$(grep -c 'gitdir=' "$LOG" 2>/dev/null) out=$_out) (#710 a B1)"
fi
# #710 b D2: the pre-probe runs ONCE in the main shell — the per-root
# tee forks inherit the cache, so an N-root sweep on broken python3
# warns EXACTLY once (a per-fork probe would print N+1).
git -C "$WORK/zone/onroot2" init -q -b main 2>/dev/null ||
    { mkdir -p "$WORK/zone/onroot2" && git -C "$WORK/zone/onroot2" init -q -b main; }
printf '%s\n%s\n' "$WORK/zone/onroot" "$WORK/zone/onroot2" >"$WORK/on-projects.conf"
: >"$LOG"
_hr_rc=0
_out=$( (
    PATH="$WORK/badbin:$PATH"
    export PATH
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        HOME="$WORK/devhome" _git_heal_on'
) 2>&1) || _hr_rc=$?
_hr_warns=$(printf '%s' "$_out" | grep -cF 'live progress unavailable (python3 missing or broken)' || true)
_hr_heals=$(grep -c 'gitdir=' "$LOG" 2>/dev/null || true)
if [ "$_hr_rc" -eq 0 ] && [ "$_hr_warns" -eq 1 ] && [ "$_hr_heals" -ge 2 ]; then
    pass "core: broken-python3 warn fires exactly once across N roots (#710 b D2)"
else
    fail "core: warn-count leg (warns=$_hr_warns heals=$_hr_heals rc=$_hr_rc) (#710 b D2)"
fi
# #710 a C8: the tee's DATA stream stays verbatim and a non-tty stderr
# emits nothing (captured runs must be byte-identical — the sibling
# verbatim-pin shape from test-status.sh). Runs the REAL tee (healthy
# python3): the probe passes, the python path is the one exercised.
printf 'a\nb\0c\n\nd\n' >"$WORK/tee-in.bin"
(. "$CORE" && _ghc_progress_tee "pin-label" <"$WORK/tee-in.bin" >"$WORK/tee-out.bin") \
    2>"$WORK/tee-err.txt"
if cmp -s "$WORK/tee-in.bin" "$WORK/tee-out.bin" && [ ! -s "$WORK/tee-err.txt" ]; then
    pass "core: tee passes data verbatim, non-tty stderr silent (#710 a C8)"
else
    fail "core: tee verbatim/silence leg (in/out differ or stderr nonempty) (#710 a C8)"
fi

# `on` sweep conf gate (#674 a A1): a hand-edited system-path line is
# skipped loudly and steers no root find — with GH_CONF_RELAX unset the
# blocklist is live even in the unit harness (the sweep's mktemp list
# stays empty, `on` still completes its other legs).
printf '%s\n' "/etc" "$WORK/zone/onroot" >"$WORK/on-projects.conf"
: >"$LOG"
_hr_rc=0
_out=$(
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        GH_CONF_RELAX= HOME="$WORK/devhome" _git_heal_on'
) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    printf '%s' "$_out" | grep -qF 'skip (conf): system path is never a project root: /etc' &&
    [ "$(grep -c 'gitdir=' "$LOG" 2>/dev/null || true)" = 0 ]; then
    pass "core: on skips a system-path conf line loudly, heals nothing under it"
else
    fail "core: on conf gate (rc=$_hr_rc out=$(printf '%s' "$_out" | grep 'skip (conf)' | head -2))"
fi

# The sweep's agent-home arm (rc 2, #674 b D4): the running user's own
# home as a conf line is skipped with its own reason — the core reads
# the agent from install.conf (OPENCODE_USER=$(id -un)), so getent's
# home for that user is the refused spelling.
_ahome=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f6)
if [ -n "$_ahome" ]; then
    printf '%s\n' "$_ahome" >"$WORK/on-projects.conf"
    : >"$LOG"
    _hr_rc=0
    _out=$(
        _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
            SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
            GH_CONF_RELAX= HOME="$WORK/devhome" _git_heal_on'
    ) || _hr_rc=$?
    if [ "$_hr_rc" -eq 0 ] &&
        printf '%s' "$_out" | grep -qF "skip (conf): agent home is never a project root: $_ahome" &&
        [ "$(grep -c 'gitdir=' "$LOG" 2>/dev/null || true)" = 0 ]; then
        pass "core: on skips the agent-home conf line with its own reason"
    else
        fail "core: on agent-home gate (rc=$_hr_rc out=$(printf '%s' "$_out" | grep 'skip (conf)' | head -2))"
    fi
fi

# The core's `/` -> rc-3 mapping (#674 c E2): the skip line names the
# system-path reason, never the generic form message.
printf '%s\n' "/" >"$WORK/on-projects.conf"
: >"$LOG"
_hr_rc=0
_out=$(
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        GH_CONF_RELAX= HOME="$WORK/devhome" _git_heal_on'
) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    printf '%s' "$_out" | grep -qF 'skip (conf): system path is never a project root: /' &&
    ! printf '%s' "$_out" | grep -qF 'not an absolute root, or malformed' &&
    [ "$(grep -c 'gitdir=' "$LOG" 2>/dev/null || true)" = 0 ]; then
    pass "core: on maps the bare / line to the system-path reason (rc 3)"
else
    fail "core: on slash mapping (rc=$_hr_rc out=$(printf '%s' "$_out" | grep 'skip (conf)' | head -2))"
fi
printf '%s\n' "$WORK/zone/onroot" "# comment tolerated" >"$WORK/on-projects.conf"

# `on` pieces gate: an incomplete lib refuses before touching anything.
mv "$WORK/lib/git-heal/hooks/post-merge" "$WORK/pm-aside"
_hr_rc=0
_out=$(_core_run '_git_heal_on') || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_out" | grep -qF 'heal hooks incomplete'; then
    pass "core: on refuses on incomplete kit pieces"
else
    fail "core: pieces gate (rc=$_hr_rc out=$_out)"
fi
mv "$WORK/pm-aside" "$WORK/lib/git-heal/hooks/post-merge"

# `off`: kit-owned value unset; foreign untouched; absent no-op.
git config --file "$WORK/devhome/.gitconfig" core.hooksPath "$WORK/lib/git-heal/hooks"
_hr_rc=0
_out=$(_core_run 'HOME="$WORK/devhome" _git_heal_off') || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    ! git config --file "$WORK/devhome/.gitconfig" core.hooksPath >/dev/null 2>&1; then
    pass "core: off unsets the kit-owned hooksPath"
else
    fail "core: off arm (rc=$_hr_rc out=$_out)"
fi
git config --file "$WORK/devhome/.gitconfig" core.hooksPath /dev/null
_hr_rc=0
_out=$(_core_run 'HOME="$WORK/devhome" _git_heal_off') || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ "$(git config --file "$WORK/devhome/.gitconfig" core.hooksPath)" = /dev/null ] &&
    printf '%s' "$_out" | grep -qF 'foreign value'; then
    pass "core: off leaves a foreign value untouched"
else
    fail "core: off foreign leg failed (rc=$_hr_rc out=$_out gc=$(cat "$WORK/devhome/.gitconfig"))"
fi
rm -f "${WORK:?}/devhome/.gitconfig"
_hr_rc=0
_out=$(_core_run 'HOME="$WORK/devhome" _git_heal_off') || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && printf '%s' "$_out" | grep -qF 'already off'; then
    pass "core: off on an absent value is a clean no-op"
else
    fail "core: off absent arm (rc=$_hr_rc out=$_out)"
fi

# cli usage + loop-guard marker (parse precedes the sudo hop).
_hr_rc=0
_out=$(sh -c '. "$1"; ui_error() { echo "usage-err" >&2; }; git_heal_cli bogus' \
    _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 64 ]; then
    pass "core: cli usage error exits 64"
else
    fail "core: cli usage (rc=$_hr_rc out=$_out)"
fi
_hr_rc=0
_out=$(OPK_GITHEAL_ROOT=1 sh -c '. "$1"
    ui_error() { echo "ERR: $*" >&2; }
    _ghc_libdir() { printf %s "$WORK/lib"; }
    git_heal_cli on' _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] && printf '%s' "$_out" | grep -qF 'sudo did not elevate'; then
    pass "core: the loop-guard marker refuses before any sudo exec (#479 a F24 shape)"
else
    fail "core: loop guard (rc=$_hr_rc out=$_out)"
fi

# --- 7. status renderer: state vocabulary (#674 a C6), lockout
# classification (a C7) and the recursive lockout enumeration (a C3).
# The core reads the agent user from install.conf (OPENCODE_USER), so
# this section carries its own conf naming a NON-existent agent —
# every real file then counts as foreign-owned and the rows must fire.
mkdir -p "$WORK/zone/scan/nested/repo"
git -C "$WORK/zone/scan/nested/repo" init -q -b main
git -C "$WORK/zone/scan/nested/repo" -c user.email=t@e -c user.name=t \
    commit -q --allow-empty -m x
# An unreadable empty subtree under the scan root (#674 c E4): find
# hits EACCES there (rc 1) while the readable repo still enumerates.
mkdir "$WORK/zone/scan/locked"
chmod 000 "$WORK/zone/scan/locked"
printf '%s\n' "$WORK/zone/scan" >"$CONF"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=ghs-render-agent\n' "$(id -un)" \
    >"$WORK/install-render.conf"

# foreign hooksPath: the same state word the opk status / doctor rows
# render — INACTIVE is gone (one vocabulary across the surfaces).
git config --file "$WORK/devhome/.gitconfig" core.hooksPath /dev/null
_out=$(_core_run 'INSTALL_CONF="$WORK/install-render.conf" _git_heal_status')
if printf '%s' "$_out" | grep -qF 'git-heal: OFF — core.hooksPath holds a foreign value' &&
    ! printf '%s' "$_out" | grep -qF 'INACTIVE'; then
    pass "status renderer: foreign state says OFF (opk status vocabulary)"
else
    fail "status renderer: foreign wording (out=$(printf '%s' "$_out" | head -3))"
fi
if printf '%s' "$_out" | grep -qF "lockout risk: $WORK/zone/scan/nested/repo/.git/index"; then
    pass "status renderer: nested repo under a scan root shows its lockout risk"
else
    fail "status renderer: recursive lockout row missing (out=$(printf '%s' "$_out" | grep lockout | head -2))"
fi
# The find partial-failure notice rides the same output (#674 c E4):
# one honesty line for the unreadable subtree, rows still rendered.
if printf '%s' "$_out" | grep -qF 'lockout rows may be incomplete under'; then
    pass "status renderer: unreadable subtree renders the incompleteness notice"
else
    fail "status renderer: find-notice arm (out=$(printf '%s' "$_out" | grep -i incomplete | head -2))"
fi

# ON: the same dev-owned operands render transient (the next developer
# git operation heals them), matching the opk status / doctor rows.
git config --file "$WORK/devhome/.gitconfig" core.hooksPath "$WORK/lib/git-heal/hooks"
_out=$(_core_run 'INSTALL_CONF="$WORK/install-render.conf" _git_heal_status')
if printf '%s' "$_out" | grep -qF 'lockout (transient — the next developer git operation' &&
    printf '%s' "$_out" | grep -qF "heals it): $WORK/zone/scan/nested/repo/.git/index"; then
    pass "status renderer: ON classifies the same lockout as transient"
else
    fail "status renderer: transient classification (out=$(printf '%s' "$_out" | grep -i lockout | head -2))"
fi

# The mktemp failure path EXECUTES (#674 b D3): a dead TMPDIR drops
# the lockout rows with a loud line, never silently — and the state
# row above still renders (status never dies).
_out=$(_core_run 'INSTALL_CONF="$WORK/install-render.conf" \
    TMPDIR="$WORK/no-such-tmp" _git_heal_status')
if printf '%s' "$_out" | grep -qF 'git-heal: lockout rows unavailable (mktemp failed)' &&
    printf '%s' "$_out" | grep -qF 'git-heal: ON — heal hooks active'; then
    pass "status renderer: mktemp failure is loud and non-fatal"
else
    fail "status renderer: mktemp arm (out=$(printf '%s' "$_out" | head -3))"
fi
chmod 700 "$WORK/zone/scan/locked"
rmdir "$WORK/zone/scan/locked"
rm -f "${WORK:?}/devhome/.gitconfig"

suite_done "git heal hooks (heal script + hook matrix + core)"
