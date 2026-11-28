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
# form arms (absolute, dot/empty segment, whitespace, glob character
# #665) never relax.

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
# the gitdir matches nothing. #665 adds the glob line: its skip line
# names the glob class, and WITHOUT the arm the root would pass the
# form gates (_gh_root_ok never checks existence), leave the allowlist
# unmatched, and the run would exit at "refused: … outside
# kit-managed roots" (discriminating through the loud skip, not
# through absence).
printf '%s\n' "$WORK/r1/../r1" "$WORK /gap" "$WORK/r1*glob" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    "$HEAL" "$WORK/r1" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'skip (conf): malformed root' &&
    printf '%s' "$_hr_out" | grep -qF "malformed root (dot, empty segment, whitespace, or glob): $WORK/r1*glob" &&
    ! printf '%s' "$_hr_out" | grep -qF 'not a (common) gitdir shape'; then
    pass "heal: dot, whitespace and glob conf lines refused even under relax (#674 b D4; #665)"
else
    fail "heal: conf form-arms-under-relax (rc=$_hr_rc out=$_hr_out) (#674/#665)"
fi

# --- 1c. heal-index-head: the git-protection storage leg (#704) --------------------
# After adoption the common gitdir lives OUTSIDE every conf root, in
# the external storage — honored like a conf root through the SAME
# _gh_root_ok gate. The storage is a plain dir here (not a gitdir
# shape): reaching the SHAPE refusal proves the allowlist authorized
# it — the conf holds no matching root.
mkdir -p "$WORK/gpstor/migrated.git"
printf '%s\n' "$WORK/r1" >"$CONF"
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    GH_STORAGE="$WORK/gpstor" "$HEAL" "$WORK/gpstor/migrated.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'not a (common) gitdir shape' &&
    ! printf '%s' "$_hr_out" | grep -qF 'outside kit-managed roots'; then
    pass "heal: a gitdir under the storage root is authorized (#704)"
else
    fail "heal: storage-allowlist arm (rc=$_hr_rc out=$_hr_out)"
fi

# A bogus (non-absolute) storage value authorizes nothing.
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_PROJECTS_CONF="$CONF" \
    GH_STORAGE="not-absolute" "$HEAL" "$WORK/gpstor/migrated.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'outside kit-managed roots'; then
    pass "heal: a malformed storage value authorizes nothing (#704)"
else
    fail "heal: storage-form arm (rc=$_hr_rc out=$_hr_out)"
fi

# A storage root that is a system path is refused by the reader gate
# (no relax on this arm) — a bogus install.conf line never heals.
_hr_rc=0
_hr_out=$(env GH_ALLOW_NONROOT=1 GH_PROJECTS_CONF="$CONF" \
    GH_STORAGE="/etc/gitdirs" "$HEAL" "$WORK/gpstor/migrated.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_hr_out" | grep -qF 'outside kit-managed roots'; then
    pass "heal: a system-path storage root is refused (#704)"
else
    fail "heal: storage-system-path arm (rc=$_hr_rc out=$_hr_out)"
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

# --- 3c. heal-index-head: the group resolution (#818 a G1) -------------------------
# The chown spec's group operand used to be the agent username spelled
# twice — a dead heal (chown: invalid group) wherever the agent's
# primary group is not a same-named usergroup (pre-existing-user
# installs). A recording chown stub observes the spec the run actually
# hands to chown(1):
#   (a) an agent user that EXISTS: the live primary group must WIN over
#       any conf-stale GH_AGENT_GROUP (the config.sh "Sharing group"
#       order: live value over stale conf entry);
#   (b) an agent user that does NOT exist: the conf value stands with
#       the canonical literal fallback — this leg discriminates the
#       old hardcoded user:user spec directly.
mkdir -p "$WORK/g1bin"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\nexit 0\n' \
    "$WORK/g1-chown.log" >"$WORK/g1bin/chown"
chmod +x "$WORK/g1bin/chown"
_g1_live="$(id -gn "$(id -un)")"
# Leg (a) discriminates the conf-wins regression on every host, but
# the username-hardcode regression only where the running user's
# primary group is NOT the same-named usergroup (#818 b T1: on
# useradd-default hosts — CI runner images — the old spec's log line
# is byte-identical to the pinned one). Leg (b) below is the
# environment-independent backstop for exactly that regression; the
# pair is sound, the condition is named.
: >"$WORK/g1-chown.log"
_hr_rc=0
_hr_out=$(env PATH="$WORK/g1bin:$PATH" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER="$(id -un)" GH_AGENT_GROUP=zzz-stale-conf \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" \
    "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    grep -qF -- "-h $(id -un):$_g1_live --" "$WORK/g1-chown.log" &&
    ! grep -qF 'zzz-stale-conf' "$WORK/g1-chown.log"; then
    pass "heal: chown spec uses the agent's LIVE primary group, conf value loses (#818 a G1)"
else
    fail "heal: live-group leg (rc=$_hr_rc spec=$(cat "$WORK/g1-chown.log" 2>/dev/null | tr '\n' ' '))"
fi
: >"$WORK/g1-chown.log"
_hr_rc=0
_hr_out=$(env PATH="$WORK/g1bin:$PATH" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER=opk-g1-nonexistent GH_AGENT_GROUP=zzz-divgrp \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" \
    "$HEAL" "$WORK/repo3/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    grep -qF -- '-h opk-g1-nonexistent:zzz-divgrp --' "$WORK/g1-chown.log"; then
    pass "heal: chown spec resolves the group (conf leg), never user:user (#818 a G1)"
else
    fail "heal: conf-group leg (rc=$_hr_rc spec=$(cat "$WORK/g1-chown.log" 2>/dev/null | tr '\n' ' '))"
fi
check_live "heal: the chown operand carries the resolved group, not the username (#818 a G1)" \
    "$HEAL" -qF 'chown -h "$_gh_agent:$_gh_group"'

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
    printf 'GH_LIBDIR=%s GH_PROJECTS_CONF=%s GH_LOG=%s GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER=%s GP_NO_HINT=1' \
        "$WORK/lib" "$CONF" "$LOG" "$(id -un)"
}
_mgit() { # git in the matrix zone (hooks + env applied)
    env PATH="$WORK/sbin:$PATH" $(_gitenv) git -C "$WORK/zone/repo" "$@"
}
_mlog() {
    _ml_n=$(grep -c 'healed' "$LOG" 2>/dev/null) || true
    printf '%s\n' "${_ml_n:-0}"
}

_settle_tie() { # clock-step guard (#741): spin (bounded) until the
    # index on disk is stamped strictly later than f — the physical
    # invariant the settled half's quiet-guarantee rests on. A backward
    # host-clock step inside the add->rewrite window stamps status #1's
    # rewrite at or before f's second (measured on the WSL2 host: steps
    # up to 2.5 s, ~15/h even idle — #741 journal forensics); in that
    # state a re-fire is git's documented racy-clean behavior, not a
    # heal defect, so wait the step out and let a status re-establish a
    # strictly-newer index before the quiet assertion runs. The body
    # never runs on an honest clock: status #1 already stamped a later
    # second, so the loop condition is false on entry.
    _st_tries=0
    while [ "$(stat -c %Y "$WORK/zone/repo/.git/index")" \
        -le "$(stat -c %Y "$WORK/zone/repo/f")" ] &&
        [ "$_st_tries" -lt 5 ]; do
        sleep 1
        _mgit status --porcelain >/dev/null 2>&1
        _st_tries=$((_st_tries + 1))
    done
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
# between cache and index (both stamped by the add), so the racy firing
# is deterministic regardless of when the status runs. The settled half's
# quiet-guarantee, however, holds only on an honest clock: it is the
# invariant "index on disk stamped strictly later than f", which sleep 1
# establishes — unless a backward host-clock step lands in the window
# (#741). _settle_tie verifies the invariant instead of trusting the
# sleep and converges past a step; the pin below re-imposes the tie to
# prove the guard discriminates.
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
_settle_tie
_before=$(_mlog)
_mgit status --porcelain >/dev/null
if [ "$(_mlog)" = "$_before" ]; then
    pass "matrix: tie broken — the settled status after is quiet"
else
    fail "matrix: settled status fired again (tie not broken)"
fi

# Guard pin (#741): re-impose the tie directly — touch the index back to
# f's cached second, the tie member a ≤ 1 s backward step leaves behind
# (larger steps stamp the index strictly earlier; the guard's -le covers
# the whole family — probe-proven in #741) — and require the guard to
# converge back to a quiet settled status. Discriminates the guard:
# without _settle_tie the assert below reds, because the tie still holds
# when the settled status runs and git legitimately re-smudges.
touch -d "@$(stat -c %Y "$WORK/zone/repo/f")" "$WORK/zone/repo/.git/index"
_settle_tie
_before=$(_mlog)
_mgit status --porcelain >/dev/null
if [ "$(_mlog)" = "$_before" ]; then
    pass "matrix: settled status converges after a re-imposed tie (clock-step guard #741)"
else
    fail "matrix: settled status fired on a re-imposed tie (clock-step guard broken)"
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
# Restore the ORIGINAL flag-stripping stub — a bare `exec "$@"`
# restore (the pre-#704 spelling) leaves a stub that dies on sudo's
# leading `-n` (exec takes `-n` for the command name: "not found",
# rc 127), and every later sudo consumer inherits the breakage
# (found by the #704 storage fast-path arm, measured 2026-11-22).
printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do\n    case "$1" in\n    -*) shift ;;\n    *) break ;;\n    esac\ndone\nexec "$@"\n' >"$WORK/sbin/sudo"

# --- 6b. hooks: the git-protection fast path + adopt hint (#704) --------------------
# The storage leg of the fast path: a repo whose COMMON gitdir sits
# under GP_STORAGE fires the heal even when no conf root matches; the
# hint (below) is silenced per-arm instead of via _gitenv's blanket
# GP_NO_HINT=1.
git -C "$WORK" init -q -b main gpstorage-zone 2>/dev/null
git -C "$WORK/gpstorage-zone" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
printf '%s\n' "$WORK/r1" >"$CONF" # conf deliberately does NOT match
git -C "$WORK/gpstorage-zone" config core.hooksPath "$WORK/lib/git-heal/hooks"
_before=$(_mlog)
env PATH="$WORK/sbin:$PATH" GH_LIBDIR="$WORK/lib" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" \
    GH_STORAGE="$WORK/gpstorage-zone" GP_STORAGE="$WORK/gpstorage-zone" \
    git -C "$WORK/gpstorage-zone" checkout -q -b storage-hit 2>/dev/null || true
if [ "$(_mlog)" -gt "$_before" ]; then
    pass "hook: a gitdir under the storage root heals (fast path, #704)"
else
    fail "hook: storage fast path did not fire (#704)"
fi

# The adopt hint: a MANAGED tree with a classic .git layout carries
# the wholesale arm — the hook says so and names the command. GP_NO_HINT
# is unset for this arm (the matrix blanket silences it).
printf '%s\n' "$WORK/zone" "# comment" "" >"$CONF"
_hr_rc=0
_out=$(env PATH="$WORK/sbin:$PATH" $(_gitenv) GP_STORAGE="$WORK/gpstor" \
    env -u GP_NO_HINT git -C "$WORK/zone/repo" checkout -q -b hint-arm 2>&1) || _hr_rc=$?
if printf '%s' "$_out" | grep -qF '[opk git-protection post-checkout] kit-managed tree with classic .git layout' &&
    printf '%s' "$_out" | grep -qF 'run: sudo opk git-protection adopt'; then
    pass "hook: classic .git in a managed tree gets the adopt hint (#704)"
else
    fail "hook: hint arm (rc=$_hr_rc out=$_out)"
fi

# Self-silencing: a POINTER .git (adopted layout) gets no hint — git
# works through the pointer, the hint condition is dir-only.
git -C "$WORK" init -q -b main gpadopted 2>/dev/null
git -C "$WORK/gpadopted" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
mkdir -p "$WORK/gpstor"
mv "$WORK/gpadopted/.git" "$WORK/gpstor/adopted.git"
printf 'gitdir: %s\n' "$WORK/gpstor/adopted.git" >"$WORK/gpadopted/.git"
git -C "$WORK/gpadopted" config core.hooksPath "$WORK/lib/git-heal/hooks"
_hr_rc=0
_out=$(env PATH="$WORK/sbin:$PATH" GH_LIBDIR="$WORK/lib" GH_PROJECTS_CONF="$CONF" \
    GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 GH_AGENT_USER="$(id -un)" \
    GP_STORAGE="$WORK/gpstor" \
    git -C "$WORK/gpadopted" checkout -q -b adopted-quiet 2>&1) || _hr_rc=$?
if ! printf '%s' "$_out" | grep -qF 'opk git-protection'; then
    pass "hook: an adopted (pointer .git) tree gets no hint — self-silencing (#704)"
else
    fail "hook: pointer-silence arm (rc=$_hr_rc out=$_out)"
fi

# The decline marker silences the hint (a host that said no is not
# nagged on every checkout).
_hr_rc=0
_out=$(env PATH="$WORK/sbin:$PATH" $(_gitenv) GP_STORAGE=none \
    env -u GP_NO_HINT git -C "$WORK/zone/repo" checkout -q -b declined-quiet 2>&1) || _hr_rc=$?
if ! printf '%s' "$_out" | grep -qF 'opk git-protection'; then
    pass "hook: GITDIR_STORAGE=none silences the hint (#704)"
else
    fail "hook: decline-marker arm (rc=$_hr_rc out=$_out)"
fi
# restore the conf the matrix expects
printf '%s\n' "$WORK/zone" "# a comment line rides along (#660 M6)" "" >"$CONF"

# --- 6c. hooks: the adopt hint's argument is a paste-safe word (#766) ---------------
# The printed `sudo opk git-protection adopt <toplevel>` line is data
# until pasted -- then it is shell structure. The toplevel path
# (folder names under it are agent-influenceable, group-writable
# trees) must arrive as ONE shell word: bare when plain, single-quoted
# with '\'' escaping otherwise, NO command at all for a control byte
# (a rename hint instead). The round trip parses the printed text as
# SOURCE in a fresh shell of the same dialect -- the way a pasted line
# is read; the shell is the authority, never a hand-rolled quote check
# (the _gp_q matrix model, test-git-protection-core.sh).
_hq_tab=$(printf '\t')
_hq_nl=$(printf 'a\nb')
_hq_fail=""
_hq_n=0
for _hq_name in "my proj" "a;b" "it's" "a \$(id) b" "b\`tick\`x" "hq-plain" "a${_hq_tab}b" "${_hq_nl}"; do
    _hq_n=$((_hq_n + 1))
    _hq_repo="$WORK/zone/$_hq_name"
    git -C "$WORK/zone" init -q -b main "$_hq_name" 2>/dev/null || continue
    git -C "$_hq_repo" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
    git -C "$_hq_repo" config core.hooksPath "$WORK/lib/git-heal/hooks"
    _hq_rc=0
    _hq_out=$(env PATH="$WORK/sbin:$PATH" $(_gitenv) GP_STORAGE="$WORK/gpstor" \
        env -u GP_NO_HINT git -C "$_hq_repo" checkout -q -b "hq-$_hq_n" 2>&1) || _hq_rc=$?
    case "$_hq_name" in
        *[[:cntrl:]]*)
            # control byte: NO command line, the rename hint instead
            if printf '%s' "$_hq_out" | grep -qF 'run: sudo opk git-protection adopt'; then
                _hq_fail="$_hq_fail printed-a-command:[$_hq_name]"
            elif ! printf '%s' "$_hq_out" |
                grep -qF 'toplevel path carries a control byte -- rename the folder'; then
                _hq_fail="$_hq_fail no-rename-hint:[$_hq_name]"
            fi
            ;;
        *)
            _hq_arg=$(printf '%s' "$_hq_out" |
                sed -n 's/^.*run: sudo opk git-protection adopt //p' | head -n 1)
            if [ -z "$_hq_arg" ]; then
                _hq_fail="$_hq_fail no-command:[$_hq_name]"
                continue
            fi
            for _hq_sh in dash bash; do
                _hq_hrc=0
                _hq_rt=$("$_hq_sh" -c 'eval "set -- $1"; printf "%s|%s" "$#" "$1"' _ "$_hq_arg") || _hq_hrc=$?
                if [ "$_hq_hrc" != 0 ] || [ "$_hq_rt" != "1|$_hq_repo" ]; then
                    _hq_fail="$_hq_fail $_hq_sh:[$_hq_name]->[$_hq_arg]"
                fi
            done
            ;;
    esac
done
if [ -z "$_hq_fail" ]; then
    pass "hook hint: the adopt argument round-trips as one word through dash and bash; control bytes get no command (#766)"
else
    fail "hook hint paste-safety ($_hq_fail)"
fi

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
    ui_warn() { echo "warn: $*"; }
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

# #818 a G2: XDG-only homes. The write legs are native --global, which
# lands in ~/.config/git/config whenever that file exists and
# ~/.gitconfig does not (probed on git 2.56.1 — no ~/.gitconfig is
# created, --unset removes the key from XDG); the read legs used to
# address ~/.gitconfig only, so `on` activated while `off` printed
# "already off" and the hooks kept firing, and status said unknown.
mkdir -p "${WORK:?}/devhome-xdg/.config/git"
git config --file "$WORK/devhome-xdg/.config/git/config" \
    core.hooksPath "$WORK/lib/git-heal/hooks"
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-xdg" INSTALL_CONF="$WORK/install.conf" sh -c \
    '. "$1"; ui_error() { echo "ERR: $*" >&2; }; _ghc_state' _ "$CORE" 2>&1)
if [ "$_out" = on ]; then
    pass "core: state on for an XDG-only home (hooksPath lives in ~/.config/git/config, #818 a G2)"
else
    fail "core: XDG-only state on (got $_out)"
fi

# The MED's harm leg: `off` on an XDG-only home actually unsets the
# kit-owned value (it used to print "already off" while the hooks
# kept firing).
_hr_rc=0
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-xdg" GH_SUDO="" \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER="$(id -un)" INSTALL_CONF="$WORK/install.conf" \
    sh -c '. "$1"; ui_info() { :; }; ui_success() { echo "ok: $*"; }; \
        ui_detail() { :; }; ui_error() { echo "ERR: $*" >&2; }; _git_heal_off' \
    _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ -z "$(git config --file "$WORK/devhome-xdg/.config/git/config" core.hooksPath 2>/dev/null)" ] &&
    printf '%s' "$_out" | grep -qF 'core.hooksPath unset'; then
    pass "core: off unsets the kit-owned hooksPath in an XDG-only home (#818 a G2)"
else
    fail "core: XDG off leg (rc=$_hr_rc out=$_out value=$(git config --file "$WORK/devhome-xdg/.config/git/config" core.hooksPath 2>/dev/null))"
fi
# The CI-lane twin (the followup this leg forced): the unset targets
# the CARRIER file explicitly — native --global --unset is
# git-version-dependent (older gits operate on ~/.gitconfig only and
# the CI unit lane reddened exactly there over an XDG-carried value).
# The behavioral XDG leg above executes the -f path; this source pin
# guards its shape (the helper since #818 c G1).
check_live "core: off unsets per carrier file, never git-version-dependent --global (#818 a G2)" \
    "$CORE" -qF 'config -f "$_ghouk_f" --unset core.hooksPath'
# #818 b G1: the consent discipline holds for MASKED carriers — a
# foreign value in the XDG file under a kit-owned ~/.gitconfig (the
# merged reader says kit) must survive `off` untouched. The first
# wave's loop unset ANY carrier and destroyed it (probed in the
# round-b scratch: xdg value gone after off).
mkdir -p "${WORK:?}/devhome-b/.config/git"
printf '[core]\n\thooksPath = %s\n' "$WORK/lib/git-heal/hooks" >"$WORK/devhome-b/.gitconfig"
git config --file "$WORK/devhome-b/.config/git/config" core.hooksPath /leftover-foreign-b
_hr_rc=0
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-b" GH_SUDO="" \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER="$(id -un)" INSTALL_CONF="$WORK/install.conf" \
    sh -c '. "$1"; ui_info() { :; }; ui_success() { echo "ok: $*"; }; \
        ui_detail() { :; }; ui_error() { echo "ERR: $*" >&2; }; _git_heal_off' \
    _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ -z "$(git config --file "$WORK/devhome-b/.gitconfig" core.hooksPath 2>/dev/null)" ] &&
    [ "$(git config --file "$WORK/devhome-b/.config/git/config" core.hooksPath 2>/dev/null)" = /leftover-foreign-b ]; then
    pass "core: off leaves a masked foreign XDG value untouched, unsets only kit carriers (#818 b G1)"
else
    fail "core: masked-foreign leg (rc=$_hr_rc gitconfig=$(git config --file "$WORK/devhome-b/.gitconfig" core.hooksPath 2>/dev/null) xdg=$(git config --file "$WORK/devhome-b/.config/git/config" core.hooksPath 2>/dev/null)) (#818 b G1)"
fi
rm -rf "${WORK:?}/devhome-b"

# #818 c G1: the mask's other side — a KIT-OWNED XDG copy under a
# foreign primary (the shape the on-leg itself creates when
# ~/.gitconfig is absent, later masked): every branch sweeps the
# carriers, the kit copy is unset and NAMED, the foreign mask stays
# untouched. Pre-c: the copy survived and the hooks resurrected when
# the user cleared the mask (probed in the round-c scratch).
mkdir -p "${WORK:?}/devhome-c/.config/git"
printf '[core]\n\thooksPath = /foreign-mask-c\n' >"$WORK/devhome-c/.gitconfig"
git config --file "$WORK/devhome-c/.config/git/config" \
    core.hooksPath "$WORK/lib/git-heal/hooks"
_hr_rc=0
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-c" GH_SUDO="" \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER="$(id -un)" INSTALL_CONF="$WORK/install.conf" \
    sh -c '. "$1"; ui_info() { :; }; ui_success() { echo "ok: $*"; }; \
        ui_detail() { echo "detail: $*"; }; ui_error() { echo "ERR: $*" >&2; }; _git_heal_off' \
    _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ "$(git config --file "$WORK/devhome-c/.gitconfig" core.hooksPath 2>/dev/null)" = /foreign-mask-c ] &&
    [ -z "$(git config --file "$WORK/devhome-c/.config/git/config" core.hooksPath 2>/dev/null)" ] &&
    printf '%s' "$_out" | grep -qF "masked kit-owned copy unset from: $WORK/devhome-c/.config/git/config" &&
    printf '%s' "$_out" | grep -qF '/foreign-mask-c) — left untouched'; then
    pass "core: off unsets the masked kit-owned XDG copy and names it, the foreign mask stays (#818 c G1)"
else
    fail "core: masked-kit leg (rc=$_hr_rc mask=$(git config --file "$WORK/devhome-c/.gitconfig" core.hooksPath 2>/dev/null) kit=$(git config --file "$WORK/devhome-c/.config/git/config" core.hooksPath 2>/dev/null) out=$_out) (#818 c G1)"
fi
rm -rf "${WORK:?}/devhome-c"

# #818 d T2: the fail-loud arm's executing leg — a MULTI-VALUED kit
# carrier in a masked branch (the read's last value is the kit path →
# the gate passes; `git config --unset` refuses a multi-valued key,
# rc 5) → the helper returns 1 → the arm fires: its message + exit 1
# (pre-d nothing executed this path; a dropped capture or exit would
# report off-success over the surviving copy). Deterministic on every
# git (multi-value semantics stable), root-independent.
mkdir -p "${WORK:?}/devhome-d/.config/git"
printf '[core]\n\thooksPath = /foreign-mask-d\n' >"$WORK/devhome-d/.gitconfig"
git config --file "$WORK/devhome-d/.config/git/config" \
    core.hooksPath "$WORK/lib/git-heal/hooks"
git config --file "$WORK/devhome-d/.config/git/config" \
    --add core.hooksPath "$WORK/lib/git-heal/hooks"
_hr_rc=0
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-d" GH_SUDO="" \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER="$(id -un)" INSTALL_CONF="$WORK/install.conf" \
    sh -c '. "$1"; ui_info() { :; }; ui_success() { echo "ok: $*"; }; \
        ui_detail() { echo "detail: $*"; }; ui_error() { echo "ERR: $*" >&2; }; _git_heal_off' \
    _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    printf '%s' "$_out" | grep -qF 'could not unset a masked kit-owned core.hooksPath' &&
    [ "$(git config --file "$WORK/devhome-d/.config/git/config" core.hooksPath 2>/dev/null)" = "$WORK/lib/git-heal/hooks" ]; then
    pass "core: a failing masked unset fails the off loud (rc 1, arm message, copy intact) (#818 d T2)"
else
    fail "core: masked-failure leg (rc=$_hr_rc kit=$(git config --file "$WORK/devhome-d/.config/git/config" core.hooksPath 2>/dev/null) out=$_out) (#818 d T2)"
fi
rm -rf "${WORK:?}/devhome-d"

# #818 d G3: the branch-2 sweep — the hooks-disable EMPTY mask over a
# kit-owned XDG copy (the fix's own first-class motivation): off says
# "already off" AND unsets the masked copy, rc 0.
mkdir -p "${WORK:?}/devhome-e/.config/git"
printf '[core]\n\thooksPath =\n' >"$WORK/devhome-e/.gitconfig"
git config --file "$WORK/devhome-e/.config/git/config" \
    core.hooksPath "$WORK/lib/git-heal/hooks"
_hr_rc=0
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-e" GH_SUDO="" \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER="$(id -un)" INSTALL_CONF="$WORK/install.conf" \
    sh -c '. "$1"; ui_info() { :; }; ui_success() { echo "ok: $*"; }; \
        ui_detail() { echo "detail: $*"; }; ui_error() { echo "ERR: $*" >&2; }; _git_heal_off' \
    _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ -z "$(git config --file "$WORK/devhome-e/.config/git/config" core.hooksPath 2>/dev/null)" ] &&
    printf '%s' "$_out" | grep -qF 'already off' &&
    printf '%s' "$_out" | grep -qF 'masked kit-owned copy unset from'; then
    pass "core: the empty-mask sweep unsets the kit copy and says already-off (#818 d G3)"
else
    fail "core: empty-mask leg (rc=$_hr_rc kit=$(git config --file "$WORK/devhome-e/.config/git/config" core.hooksPath 2>/dev/null) out=$_out) (#818 d G3)"
fi
rm -rf "${WORK:?}/devhome-e"

# #818 d G1: branch 1 discards the helper's echo — the carrier PATHS
# must not appear in a successful off's output (the pre-d uncaptured
# call leaked them as a bare unlabeled stdout line).
mkdir -p "${WORK:?}/devhome-f"
printf '[core]\n\thooksPath = %s\n' "$WORK/lib/git-heal/hooks" >"$WORK/devhome-f/.gitconfig"
_hr_rc=0
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-f" GH_SUDO="" \
    GH_PROJECTS_CONF="$CONF" GH_LOG="$LOG" GH_ALLOW_NONROOT=1 GH_CONF_RELAX=1 \
    GH_AGENT_USER="$(id -un)" INSTALL_CONF="$WORK/install.conf" \
    sh -c '. "$1"; ui_info() { :; }; ui_success() { echo "ok: $*"; }; \
        ui_detail() { echo "detail: $*"; }; ui_error() { echo "ERR: $*" >&2; }; _git_heal_off' \
    _ "$CORE" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    printf '%s' "$_out" | grep -qF 'core.hooksPath unset' &&
    ! printf '%s' "$_out" | grep -qF "$WORK/devhome-f/.gitconfig"; then
    pass "core: a successful off leaks no bare carrier-path line (#818 d G1)"
else
    fail "core: branch-1 echo leak leg (rc=$_hr_rc out=$_out) (#818 d G1)"
fi
rm -rf "${WORK:?}/devhome-f"

# The #100 consent discipline survives the XDG fix: a foreign value in
# an XDG-only home is foreign (reported, never touched by off).
git config --file "$WORK/devhome-xdg/.config/git/config" core.hooksPath /dev/null
_out=$(GH_DEV_HOME="$WORK/devhome-xdg" INSTALL_CONF="$WORK/install.conf" sh -c \
    '. "$1"; ui_error() { echo "ERR: $*" >&2; }; _ghc_state' _ "$CORE" 2>&1)
if [ "$_out" = foreign ]; then
    pass "core: state foreign for a foreign XDG value (consent discipline, #818 a G2)"
else
    fail "core: XDG foreign state (got $_out)"
fi

# Git's merge order under the merged reader: ~/.gitconfig wins per
# key when both files exist — a KIT value in XDG must not mask a
# foreign value in ~/.gitconfig (#818 b T2: the pre-b fixture left
# the foreign /dev/null in the XDG carrier, so every reader variant —
# primary-only, XDG-only, either precedence — answered foreign and
# the pin could not red; the XDG carrier now holds the KIT value: a
# reader with inverted precedence says ON here and reds).
git config --file "$WORK/devhome-xdg/.config/git/config" \
    core.hooksPath "$WORK/lib/git-heal/hooks"
printf '[core]\n\thooksPath = /foreign-from-gitconfig\n' >"$WORK/devhome-xdg/.gitconfig"
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-xdg" INSTALL_CONF="$WORK/install.conf" sh -c \
    '. "$1"; ui_error() { echo "ERR: $*" >&2; }; _ghc_state' _ "$CORE" 2>&1)
if [ "$_out" = foreign ]; then
    pass "core: ~/.gitconfig wins per key over the XDG value (git merge order, #818 a G2)"
else
    fail "core: gitconfig-precedence state (got $_out)"
fi
# #818 b G2: an explicitly EMPTY ~/.gitconfig hooksPath (the
# `git config --global core.hooksPath ""` hooks-disable idiom) MASKS
# the XDG value per git's per-key precedence — the reader must not
# fall through to the XDG carrier (pre-b: state said foreign over an
# XDG value git itself never honors; probed in the round-b scratch:
# rc 0 with empty output is the masked shape).
mkdir -p "${WORK:?}/devhome-b2/.config/git"
printf '[core]\n\thooksPath =\n' >"$WORK/devhome-b2/.gitconfig"
git config --file "$WORK/devhome-b2/.config/git/config" core.hooksPath /foreign-xdg-b2
_out=$(GH_LIBDIR="$WORK/lib" GH_DEV_HOME="$WORK/devhome-b2" INSTALL_CONF="$WORK/install.conf" sh -c \
    '. "$1"; ui_error() { echo "ERR: $*" >&2; }; _ghc_state' _ "$CORE" 2>&1)
if [ "$_out" = off ]; then
    pass "core: an explicitly empty gitconfig hooksPath masks the XDG value (state off, #818 b G2)"
else
    fail "core: empty-value masking leg (got $_out) (#818 b G2)"
fi
rm -rf "${WORK:?}/devhome-b2"
rm -f "${WORK:?}/devhome-xdg/.gitconfig"
rm -rf "${WORK:?}/devhome-xdg"

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
    printf '%s' "$_out" | grep -qF "by 'sudo opk update' when its semantics change"; then
    pass "core: on separates the operand sweep from the fs-baseline bits (#695)"
else
    fail "core: on must separate operand sweep and fs-baseline bits (#695)"
fi

# #818 a G3: on refuses a foreign core.hooksPath BEFORE anything is
# touched — the old leg overwrote the developer's value (a lefthook/
# pre-commit setup) unrecoverably while off/uninstall/status refuse
# foreign values by design (the #100 consent discipline). The clean
# arm (no value / the kit value) is the on pin above; this is the
# foreign arm: rc 1, the value untouched, NO sudoers re-render.
git config --file "$WORK/devhome/.gitconfig" core.hooksPath /leftover-foreign-hooks
rm -rf "${WORK:?}/etc-g3" "${WORK:?}/sdd-g3"
_hr_rc=0
_out=$(_core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc-g3" \
    SD_SUDOERS_D="$WORK/sdd-g3" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
    HOME="$WORK/devhome" _git_heal_on') || _hr_rc=$?
if [ "$_hr_rc" -eq 1 ] &&
    [ "$(git config --file "$WORK/devhome/.gitconfig" core.hooksPath)" = /leftover-foreign-hooks ] &&
    [ ! -f "$WORK/etc-g3/sudoers" ] &&
    printf '%s' "$_out" | grep -qF 'holds a foreign value — leaving it untouched'; then
    pass "core: on refuses a foreign hooksPath before touching anything (#818 a G3)"
else
    fail "core: foreign-refuse leg (rc=$_hr_rc value=$(git config --file "$WORK/devhome/.gitconfig" core.hooksPath) sudoers=$([ -f "$WORK/etc-g3/sudoers" ] && echo rendered || echo none) out=$_out) (#818 a G3)"
fi
# restore the kit-owned value: later on-arms run the clean leg
git config --file "$WORK/devhome/.gitconfig" core.hooksPath "$WORK/lib/git-heal/hooks"

# #818 a G5: the activation version probe. A git stub answers
# --version with 2.30.1 (the kit's tested floor) and delegates
# everything else to the real git: `on` must WARN (soft floor, never
# an abort — the write still lands) naming the dead carrier; a clean
# re-run with the real git (>= 2.31) shows no warn line.
mkdir -p "$WORK/g5bin"
cat >"$WORK/g5bin/git" <<EOF
#!/bin/sh
if [ "\$1" = "--version" ]; then
    echo "git version 2.30.1"
    exit 0
fi
exec $(command -v git) "\$@"
EOF
chmod 755 "$WORK/g5bin/git"
printf '%s\n' "$WORK/zone/onroot" >"$WORK/on-projects.conf"
_hr_rc=0
_out=$( (
    PATH="$WORK/g5bin:$PATH"
    export PATH
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        HOME="$WORK/devhome" _git_heal_on'
) 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    printf '%s' "$_out" | grep -qF 'below 2.31 — the post-index-change carrier' &&
    [ "$(git config --file "$WORK/devhome/.gitconfig" core.hooksPath)" = "$WORK/lib/git-heal/hooks" ]; then
    pass "core: on warns below git 2.31 (dead carrier named), still activates (#818 a G5)"
else
    fail "core: version-warn leg (rc=$_hr_rc out=$_out) (#818 a G5)"
fi
# The no-warn control (#818 b T3: through a version stub — the real
# git made the leg environment-fragile: on the kit's own tested floor
# 2.30.x the lib warns BY DESIGN and the leg false-reds; the stub
# answers --version deterministically as a modern git).
mkdir -p "$WORK/g5bin2"
cat >"$WORK/g5bin2/git" <<EOF
#!/bin/sh
if [ "\$1" = "--version" ]; then
    echo "git version 2.56.1"
    exit 0
fi
exec $(command -v git) "\$@"
EOF
chmod 755 "$WORK/g5bin2/git"
_hr_rc=0
_out=$( (
    PATH="$WORK/g5bin2:$PATH"
    export PATH
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        HOME="$WORK/devhome" _git_heal_on'
) 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && ! printf '%s' "$_out" | grep -qF 'below 2.31'; then
    pass "core: on shows no version warn on git >= 2.31 (#818 a G5)"
else
    fail "core: version-warn control leg (rc=$_hr_rc out=$_out) (#818 a G5)"
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
# #665: a glob-bearing conf line maps to the FORM why (rc 1) in the
# on-scan's conf loop — the form gate catches it before the
# relax-gated blocklist (GH_CONF_RELAX stays off here: without the
# glob arm the /tmp-scratch root would fall through to the
# system-path skip line, a DIFFERENT reason — the leg discriminates
# through the why-text, not through the skip volume).
printf '%s\n' "$WORK/r1*glob" >"$WORK/on-projects.conf"
: >"$LOG"
_hr_rc=0
_out=$(
    _core_run 'SD_SUDO="" SD_VISUDO="$WORK/visudo" SD_CONF_DIR="$WORK/etc" \
        SD_SUDOERS_D="$WORK/sdd" GH_PROJECTS_CONF="$WORK/on-projects.conf" \
        GH_CONF_RELAX= HOME="$WORK/devhome" _git_heal_on'
) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    printf '%s' "$_out" | grep -qF 'or malformed (dot, empty segment, whitespace, or glob): '"$WORK/r1*glob" &&
    ! printf '%s' "$_out" | grep -qF 'system path is never a project root'; then
    pass "core: on maps a glob conf line to the form-arm why (#665)"
else
    fail "core: on glob conf line (rc=$_hr_rc out=$(printf '%s' "$_out" | grep 'skip (conf)' | head -2)) (#665)"
fi
printf '%s\n' "$WORK/zone/onroot" "# comment tolerated" >"$WORK/on-projects.conf"

# --- 7a. #777: the sweeps see POINTER-FILE checkouts ------------------------------
# The #704 O4 layout seals every kit-managed checkout as `gitdir:
# <storage>/<name>.git` -- a FILE the sweeps' old `find -type d`
# never matched, so `on` healed nothing and `status` showed no lockout
# on a pointer-shaped host (the live incident: root-owned indexes
# under /var/www/gitdirs, both sweeps green over them). Fixture: an
# adopted-shape main checkout, a linked worktree whose pointer targets
# <gitdir>/worktrees/<id>, a relative (submodule-form) pointer, a
# garbage pointer file and a malformed absolute target.
mkdir -p "$WORK/zone/ptzone" "$WORK/ptstor"
git -C "$WORK/zone/ptzone" init -q -b main pmain
git -C "$WORK/zone/ptzone/pmain" -c user.email=t@e -c user.name=t commit -q --allow-empty -m x
mv "$WORK/zone/ptzone/pmain/.git" "$WORK/ptstor/main.git"
printf 'gitdir: %s\n' "$WORK/ptstor/main.git" >"$WORK/zone/ptzone/pmain/.git"
git --git-dir="$WORK/ptstor/main.git" worktree add -q "$WORK/zone/ptzone/pwt" -b ptwb 2>/dev/null
mkdir -p "$WORK/zone/ptzone/psub" "$WORK/zone/ptzone/pjunk" "$WORK/zone/ptzone/pmal"
printf 'gitdir: ../.git/modules/sub\n' >"$WORK/zone/ptzone/psub/.git"
printf 'not a pointer\n' >"$WORK/zone/ptzone/pjunk/.git"
printf 'gitdir: /tmp/has space/x.git\n' >"$WORK/zone/ptzone/pmal/.git"
# Review-a hardening fixtures: a planted pointer nominating a
# gitdir-shaped dir OUTSIDE the storage (C1 — a bare repo, HEAD+
# objects present, would pass every heal gate), a control-byte target
# (C3) and a trailing-slash alias of the legit target (C4).
mkdir -p "$WORK/zone/ptzone/patk" "$WORK/zone/ptzone/pctl" "$WORK/zone/ptzone/pslash"
git -C "$WORK/zone/ptzone" init -q --bare ptmirror.git
printf 'gitdir: %s\n' "$WORK/zone/ptzone/ptmirror.git" >"$WORK/zone/ptzone/patk/.git"
printf 'gitdir: /tmp/ctl-%sx.git\n' "$(printf '\033')" >"$WORK/zone/ptzone/pctl/.git"
printf 'gitdir: %s/\n' "$WORK/ptstor/main.git" >"$WORK/zone/ptzone/pslash/.git"
printf '%s\n' "$WORK/zone/ptzone" >"$WORK/pt-projects.conf"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\n' "$(id -un)" "$(id -un)" >"$WORK/install.conf"

# `on` heals the pointer checkout THROUGH its resolved storage gitdir
# (GH_STORAGE must be exported: heal-index-head's allowlist honors the
# storage root, and the unit scratch sits outside every conf root).
rm -f "$LOG" && : >"$LOG"
_hr_rc=0
_out=$(
    _core_run 'export GH_STORAGE="$WORK/ptstor"; SD_SUDO="" SD_VISUDO="$WORK/visudo" \
        SD_CONF_DIR="$WORK/etc" SD_SUDOERS_D="$WORK/sdd" \
        GH_PROJECTS_CONF="$WORK/pt-projects.conf" HOME="$WORK/devhome" _git_heal_on'
) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    grep -qF "gitdir=$WORK/ptstor/main.git" "$LOG" &&
    grep -qF 'healed index' "$LOG" &&
    printf '%s' "$_out" | grep -qF "operand set re-pinned for $WORK/ptstor/main.git"; then
    pass "core: on heals a pointer-file checkout through its resolved gitdir (#777)"
else
    fail "core: on pointer arm (rc=$_hr_rc log=$(cat "$LOG") out=$(printf '%s' "$_out" | grep -E 'pointer|re-pinned' | head -3)) (#777)"
fi

# Dedup: the worktree pointer and the main pointer name the SAME common
# gitdir -- exactly one re-pin detail, exactly the common gitdir's own
# operand audits (index + HEAD once each; the registration dir is
# non-sticky by design and never a candidate).
_repin_n=$(printf '%s' "$_out" | grep -cF "operand set re-pinned for $WORK/ptstor/main.git" || true)
_log_n=$(grep -cF "gitdir=$WORK/ptstor/main.git " "$LOG" || true)
if [ "$_repin_n" = 1 ] && [ "$_log_n" = 2 ] &&
    ! printf '%s' "$_out" | grep -qF "operand heal skipped for $WORK/ptstor/main.git/worktrees"; then
    pass "core: on dedups main and worktree pointers onto one common gitdir (#777)"
else
    fail "core: on pointer dedup (repin=$_repin_n audits=$_log_n — 1/2 expected) (#777)"
fi

# The relative (submodule-form) pointer is skipped LOUDLY and never
# healed: .git/modules is developer-pinned by the fs baseline (#655
# b Q4), healing into it would fight the baseline.
if printf '%s' "$_out" | grep -qF 'skip (pointer): relative target (submodule form' &&
    printf '%s' "$_out" | grep -qF "never healed): $WORK/zone/ptzone/psub/.git" &&
    ! grep -qF 'modules/sub' "$LOG"; then
    pass "core: on skips the relative (submodule) pointer loudly, heals nothing (#777)"
else
    fail "core: on submodule-pointer arm (out=$(printf '%s' "$_out" | grep 'skip (pointer)' | head -2)) (#777)"
fi

# Garbage (no gitdir: line) and malformed absolute targets are skipped
# with their own notes.
if printf '%s' "$_out" | grep -qF "skip (pointer): no gitdir: line: $WORK/zone/ptzone/pjunk/.git" &&
    printf '%s' "$_out" | grep -qF 'skip (pointer): malformed target (dot, empty segment,' &&
    printf '%s' "$_out" | grep -qF "whitespace, or glob): $WORK/zone/ptzone/pmal/.git"; then
    pass "core: on skips garbage and malformed pointer targets with named reasons (#777)"
else
    fail "core: on pointer-refusal arms (out=$(printf '%s' "$_out" | grep 'skip (pointer)' | head -3)) (#777)"
fi

# Review-a C1 (MED): the nomination gate. A planted pointer naming a
# gitdir-shaped directory OUTSIDE the storage (this bare repo carries
# HEAD+objects and sits under the conf root — heal-index-head's
# allowlist and shape gates pass it by construction) must be refused
# loudly and heal NOTHING: without the gate the sweep's nomination
# universe widens to any such directory, which the pre-#777 -type d
# walk could never reach.
if printf '%s' "$_out" | grep -qF 'skip (pointer): target outside the storage root and not a .git dir' &&
    printf '%s' "$_out" | grep -qF "foreign or planted): $WORK/zone/ptzone/patk/.git" &&
    ! grep -qF "gitdir=$WORK/zone/ptzone/ptmirror.git" "$LOG"; then
    pass "core: on refuses a pointer nominating an out-of-storage gitdir (C1 gate, review a)"
else
    fail "core: on nomination gate (out=$(printf '%s' "$_out" | grep 'outside the storage' | head -2) log=$(grep -c 'gitdir=' "$LOG" || true) healed) (review a C1)"
fi

# Review-b B1 (HIGH): the DEFAULT host — no storage configured at all
# (no GITDIR_STORAGE in install.conf, no GH_STORAGE export). The
# storage arm must be DISABLED: an unvalidated empty pattern would
# degenerate to `/*` and accept every absolute target — the mirror
# AND the legit-looking ptstor pointer would heal. Everything
# pointer-shaped is refused (the .git-named class still passes, none
# lives in this fixture); the sweep stays green and heals nothing.
# The eval UNSETS GH_STORAGE (review c C1, rationale corrected per
# round d D1): the subshell would inherit an ambient export from the
# invoking shell — an empty assignment ALSO masks that export for
# the children (verified in bash and dash), and the resolver's
# ${GH_STORAGE:-…} treats empty and unset alike, so either spelling
# resolves the no-storage class HERE. The unset is the explicit-
# absence spelling: the pin's no-storage class rests on the fixture
# install.conf carrying no GITDIR_STORAGE line, and the unset states
# that independence from the invoking environment directly (a future
# ${GH_STORAGE+x}-style check would distinguish it from empty).
: >"$LOG"
_hr_rc=0
_b1_out=$(
    _core_run 'unset GH_STORAGE; SD_SUDO="" SD_VISUDO="$WORK/visudo" \
        SD_CONF_DIR="$WORK/etc" SD_SUDOERS_D="$WORK/sdd" \
        GH_PROJECTS_CONF="$WORK/pt-projects.conf" HOME="$WORK/devhome" _git_heal_on'
) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    [ "$(grep -c 'gitdir=' "$LOG" 2>/dev/null || true)" = 0 ] &&
    printf '%s' "$_b1_out" | grep -qF 'skip (pointer): target outside the storage root and not a .git dir' &&
    printf '%s' "$_b1_out" | grep -qF 'success: git heal hooks active'; then
    pass "core: on with NO storage configured refuses every pointer target (B1, review b)"
else
    fail "core: on empty-storage arm (rc=$_hr_rc healed=$(grep -c 'gitdir=' "$LOG" 2>/dev/null || true)) (review b B1)"
fi

# Review-b B2: a hand-edited storage value (system path) never steers
# the resolver — the reader-side validation disables the storage arm
# and the target gets the loud foreign refusal instead of rows/heals.
# Resolver-direct, NO relax (the production posture of the reader
# mirror).
mkdir -p "$WORK/zone/ptzone/pb2"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\nGITDIR_STORAGE=/etc/gitdirs\n' "$(id -un)" "$(id -un)" \
    >"$WORK/install-b2.conf"
printf 'gitdir: /etc/gitdirs/evil.git\n' >"$WORK/zone/ptzone/pb2/.git"
_hr_rc=0
_b2_out=$(sh -c '
    ui_detail() { echo "detail: $*"; }
    . "$1"
    INSTALL_CONF="$2"
    if _ghc_pt_target "$3"; then echo "ACCEPTED"; fi
' _ "$CORE" "$WORK/install-b2.conf" "$WORK/zone/ptzone/pb2/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] &&
    ! printf '%s' "$_b2_out" | grep -qF 'ACCEPTED' &&
    printf '%s' "$_b2_out" | grep -qF 'skip (pointer): target outside the storage root and not a .git dir'; then
    pass "core: a system-path storage value disables the storage arm (B2, review b)"
else
    fail "core: bogus-storage arm (rc=$_hr_rc out=$_b2_out) (review b B2)"
fi

# Review-a C3: control bytes never reach the report rows raw.
if printf '%s' "$_out" | grep -qF 'skip (pointer): target carries a control byte: ' &&
    printf '%s' "$_out" | grep -qF "$WORK/zone/ptzone/pctl/.git" &&
    ! printf '%s' "$_out" | grep -qF "$(printf '\033')"; then
    pass "core: on refuses a control-byte target before any row renders it (C3, review a)"
else
    fail "core: on control-byte gate (out=$(printf '%s' "$_out" | grep -c 'control byte' || true) hits) (review a C3)"
fi

# Review-a C4: a trailing-slash alias of the legit target normalizes
# onto the same candidate (no note, no duplicate heal — the dedup
# counts above stay 1/2).
if ! printf '%s' "$_out" | grep -qF 'pslash'; then
    pass "core: on normalizes a trailing-slash target into the deduped candidate (C4, review a)"
else
    fail "core: on trailing-slash arm (out=$(printf '%s' "$_out" | grep pslash | head -1)) (review a C4)"
fi

# Review-a C2: the resolver refuses a FIFO swapped onto a .git name
# BEFORE any read — timeout-wrapped (the test-doctor no-hang idiom):
# without the [ -f ] gate the sed open blocks forever and the run
# dies rc 124.
mkdir -p "$WORK/zone/ptzone/pfifo"
mkfifo "$WORK/zone/ptzone/pfifo/.git"
_hr_rc=0
_fifo_out=$(timeout 10 sh -c '
    ui_detail() { echo "detail: $*"; }
    . "$1"
    INSTALL_CONF="$2"
    if _ghc_pt_target "$3"; then echo "ACCEPTED"; fi
' _ "$CORE" "$WORK/install.conf" "$WORK/zone/ptzone/pfifo/.git" 2>&1) || _hr_rc=$?
if [ "$_hr_rc" -eq 0 ] && ! printf '%s' "$_fifo_out" | grep -qF 'ACCEPTED'; then
    pass "core: the resolver refuses a FIFO .git without reading it (C2, review a)"
else
    fail "core: FIFO gate (rc=$_hr_rc out=$_fifo_out) (review a C2)"
fi

# Claim audit for the extended layer-separation note: the sweep SAYS
# where adopted checkouts' gitdir-level bits come from — the
# git-protection heal at adoption, re-applied by that heal's own pass
# on every update / on run since #779 (the pre-#779 wording asserted
# the gap; the storage reheal sweep closed it).
if printf '%s' "$_out" | grep -qF 'for adopted' &&
    printf '%s' "$_out" | grep -qF 'the git-protection heal sets them at adoption time' &&
    printf '%s' "$_out" | grep -qF '(the storage reheal sweep)'; then
    pass "core: on names the pointer gitdir bits' owner and re-application (#777, #779)"
else
    fail "core: on pointer caveat arm (out=$(printf '%s' "$_out" | grep 'operand sweep' | head -2)) (#777, #779)"
fi

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

# issue #810: the heal errors' bare root-requiring hints carry the sudo
# prefix now (followable remediations — the house style of the sibling
# 'sudo opk update' hints). The pieces-gate error wraps under the
# 120-column ratchet; its pin greps the WRAP's fragments, not the
# contiguous phrase (conventions.md "Formatting (shfmt)").
if live_src "$CORE" | grep -qF "heal hooks incomplete under \$(_ghc_libdir)/git-heal — run 'sudo opk update' first" &&
    live_src "$CORE" | grep -qF 'sudoers-deploy.sh or sudoers.template missing under' &&
    live_src "$CORE" | grep -qF " \$(_ghc_libdir) — run 'sudo opk update' first" &&
    live_src "$CORE" | grep -qF "'sudo opk git-protection on' (the storage reheal sweep)" &&
    live_src "$CORE" | grep -qF "kit pieces INCOMPLETE under \$(_ghc_libdir)/git-heal — run 'sudo opk update'"; then
    pass "heal hints carry the sudo spelling (issue #810)"
else
    fail "heal hints lost the sudo spelling (issue #810)"
fi

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
# #782: the label line stays whole, the operand line carries path +
# owner — both fragments pinned separately (the wrap discipline).
if printf '%s' "$_out" | grep -qF 'lockout (transient — the next developer git operation heals it):' &&
    printf '%s' "$_out" | grep -qF "$WORK/zone/scan/nested/repo/.git/index is $(id -un)-owned"; then
    pass "status renderer: ON classifies the same lockout as transient"
else
    fail "status renderer: transient classification (out=$(printf '%s' "$_out" | grep -i lockout | head -2))"
fi

# #782: ONE fix-all hint after the row set (blank line + label row +
# detail row). Discrimination: in THIS run the state is ON (the state
# row carries no command text) and the transient lockout arm names no
# command either — 'sudo opk git-heal on' can only come from the hint.
if printf '%s' "$_out" | grep -qF 'git-heal: fix all lockouts with:' &&
    printf '%s' "$_out" | grep -qF 'sudo opk git-heal on'; then
    pass "status renderer: the fix-all hint renders once lockouts exist (#782)"
else
    fail "status renderer: fix-all hint missing (#782; out=$(printf '%s' "$_out" | tail -4))"
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
# #782 negative arm: NO lockouts (every operand matches the agent
# user) renders NO hint — the row set is the hint's only trigger.
printf 'DEFAULT_USER=%s\nOPENCODE_USER=%s\n' "$(id -un)" "$(id -un)" \
    >"$WORK/install-noagent.conf"
_out=$(_core_run 'INSTALL_CONF="$WORK/install-noagent.conf" _git_heal_status')
if printf '%s' "$_out" | grep -qF 'git-heal: ON — heal hooks active' &&
    ! printf '%s' "$_out" | grep -qF 'fix all lockouts' &&
    ! printf '%s' "$_out" | grep -qE 'lockout \(transient|lockout risk'; then
    pass "status renderer: no lockouts renders no fix-all hint (#782)"
else
    fail "status renderer: hint must ride the rows only (out=$(printf '%s' "$_out" | tail -3)) (#782)"
fi
# a A2: the fix-all-hint COUNTER's mktemp failing (the third mktemp —
# list, raw, counter) drops only the hint and must leave the rc at 0:
# an AND-list tail returned 1 there and the display command inherited
# it. A dead TMPDIR cannot reach the path (the FIRST mktemp dies and
# returns early) — a stateful mktemp stub failing from call 3 on does.
mkdir -p "$WORK/cntstub"
cat >"$WORK/cntstub/mktemp" <<EOF
#!/bin/sh
_c=\$(cat "\$CNT_STATE" 2>/dev/null || printf '0')
_c=\$((_c + 1))
printf '%s' "\$_c" >"\$CNT_STATE"
[ "\$_c" -ge 3 ] && exit 1
exec $(command -v mktemp) "\$@"
EOF
chmod +x "$WORK/cntstub/mktemp"
: >"$WORK/cntstub/state"
_a2rc=0
_out=$(_core_run 'PATH="$WORK/cntstub:$PATH" CNT_STATE="$WORK/cntstub/state"; export PATH CNT_STATE; INSTALL_CONF="$WORK/install-noagent.conf" _git_heal_status') ||
    _a2rc=$?
if [ "$_a2rc" -eq 0 ] &&
    printf '%s' "$_out" | grep -qF 'git-heal: fix-all hint unavailable (mktemp failed)'; then
    pass "status renderer: counter-mktemp failure drops only the hint, rc 0 (#785 a A2)"
else
    fail "status renderer: counter-mktemp arm (rc=$_a2rc; out=$(printf '%s' "$_out" | grep -i 'mktemp' | head -2)) (#785 a A2)"
fi
# b A1: quoted conf values compare stripped — OPENCODE_USER quoted to
# the REAL invoking user must not fire lockout rows (the pre-fix
# compare kept the quotes and rendered every operand as a lockout).
printf 'DEFAULT_USER="%s"\nOPENCODE_USER="%s"\n' "$(id -un)" "$(id -un)" \
    >"$WORK/install-quoted.conf"
_out=$(_core_run 'INSTALL_CONF="$WORK/install-quoted.conf" _git_heal_status' || true)
if ! printf '%s' "$_out" | grep -qE 'lockout \(transient|lockout risk'; then
    pass "status renderer: quoted conf values compare stripped — no false lockouts (#785 b A1)"
else
    fail "status renderer: quoted conf fired false lockout rows (out=$(printf '%s' "$_out" | grep -E 'lockout' | head -2)) (#785 b A1)"
fi
chmod 700 "$WORK/zone/scan/locked"
rmdir "$WORK/zone/scan/locked"
rm -f "${WORK:?}/devhome/.gitconfig"

# --- 7b. #777: status sees pointer-file checkouts ----------------------------------
# The lockout rows must name the RESOLVED gitdir (the operand's real
# location under the storage) -- the diagnosis surface the live
# incident needed. Same mismatch-agent trick as the classic arms: a
# nonexistent OPENCODE_USER makes every present operand render.
printf '%s\n' "$WORK/zone/ptzone" >"$CONF"
printf 'DEFAULT_USER=%s\nOPENCODE_USER=ghs-pt-agent\n' "$(id -un)" >"$WORK/install-pt.conf"
_out=$(_core_run 'export GH_STORAGE="$WORK/ptstor"; INSTALL_CONF="$WORK/install-pt.conf" _git_heal_status')
if printf '%s' "$_out" | grep -qF "lockout risk: $WORK/ptstor/main.git/index" &&
    printf '%s' "$_out" | grep -qF "lockout risk: $WORK/ptstor/main.git/HEAD" &&
    ! printf '%s' "$_out" | grep -qF "$WORK/ptstor/main.git/worktrees/"; then
    pass "status renderer: a pointer checkout's rows name the resolved storage gitdir (#777)"
else
    fail "status renderer: pointer rows (out=$(printf '%s' "$_out" | grep lockout | head -2)) (#777)"
fi

# Worktree + main pointer dedup in the status scan too: two entries,
# one common gitdir -- one row per operand, not two.
_ptrow_n=$(printf '%s' "$_out" | grep -cF "lockout risk: $WORK/ptstor/main.git/index" || true)
if [ "$_ptrow_n" = 1 ]; then
    pass "status renderer: main and worktree pointers render one deduped row set (#777)"
else
    fail "status renderer: pointer dedup (rows=$_ptrow_n for one operand — 1 expected) (#777)"
fi

# The refusals ride the status surface as well (display-only, but the
# same resolver: the notes say why a checkout under the root has no
# rows).
if printf '%s' "$_out" | grep -qF 'skip (pointer): relative target (submodule form' &&
    printf '%s' "$_out" | grep -qF "skip (pointer): no gitdir: line: $WORK/zone/ptzone/pjunk/.git"; then
    pass "status renderer: pointer refusals render their skip notes (#777)"
else
    fail "status renderer: pointer skip notes (out=$(printf '%s' "$_out" | grep 'skip (pointer)' | head -2)) (#777)"
fi

suite_done "git heal hooks (heal script + hook matrix + core)"
