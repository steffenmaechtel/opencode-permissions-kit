#!/bin/sh
# Unit tests for scripts/release.sh (maintainer release helper, issue #38):
# runs the REAL script inside throwaway git sandboxes (local bare "origin",
# no network) and asserts every guard + the happy path + resumability:
#   - refuses: non-master branch, dirty tree, VERSION mismatch, taken tag,
#     diverged stable (never force-pushes)
#   - dry-run prints the mechanics but creates nothing
#   - real run: tag + stable mirror pushed, byte-identical invariant holds
#   - second run is a no-op ("nothing to push")
# The sandbox copy of the script resolves REPO from its own location, so
# copying scripts/release.sh into the sandbox tests the real logic.
# Run: sh tests/unit/test-release.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="$SCRIPT_DIR/../../scripts/release.sh"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# mkrepo: fresh sandbox at $WORK/r with origin=$WORK/origin.git, master
# holding one commit (VERSION=1.2.3 + the release script), all pushed.
mkrepo() {
    rm -rf "$WORK/r" "$WORK/origin.git"
    git init -q -b master "$WORK/origin.git" --bare
    git init -q -b master "$WORK/r"
    git -C "$WORK/r" config user.email test@invalid
    git -C "$WORK/r" config user.name test
    mkdir -p "$WORK/r/scripts"
    cp "$RELEASE" "$WORK/r/scripts/release.sh"
    echo "1.2.3" > "$WORK/r/VERSION"
    echo "kit" > "$WORK/r/README.md"
    git -C "$WORK/r" add -A
    git -C "$WORK/r" commit -qm "init 1.2.3"
    git -C "$WORK/r" remote add origin "$WORK/origin.git"
    git -C "$WORK/r" push -q origin master
}

# Fake gh on PATH for EVERY sandbox run (the CI pre-flight must not
# depend on the host: a real gh would fail on the file:// sandbox origin
# and abort the script with "no CI runs"). Defaults to green; section 6b
# steers scenarios via FAKE_GH_* env vars.
mkdir -p "$WORK/ghbin"
cat > "$WORK/ghbin/gh" <<'FAKEGH'
#!/bin/sh
case " $* " in
    *" run list "*)
        [ -n "${FAKE_GH_EMPTY:-}" ] && exit 0
        [ -n "${FAKE_GH_RAW:-}" ] && { printf '%s\n' "$FAKE_GH_RAW"; exit 0; }
        printf '%s\t%s\n' "${FAKE_GH_STATUS:-completed}" "${FAKE_GH_CONCLUSION:-success}"
        ;;
    *) exit 0 ;;
esac
FAKEGH
chmod +x "$WORK/ghbin/gh"
PATH="$WORK/ghbin:$PATH"
export PATH

expect_rc() {
    _want="$1"; _desc="$2"; shift 2
    set +e
    out=$( "$@" 2>&1 ); rc=$?
    set -e
    LAST_OUT="$out"
    if [ "$rc" = "$_want" ]; then pass "$_desc"; else fail "$_desc (rc=$rc, out=$out)"; fi
}

# --- 1. argument guards -----------------------------------------------------------
mkrepo
expect_rc 1 "bare 'v' prefix rejected (tags carry no v)" \
    sh "$WORK/r/scripts/release.sh" v1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "bare x.y.z" \
    && pass "v-prefix rejection explains the bare stamp" \
    || fail "v-prefix rejection explains the bare stamp (out=$LAST_OUT)"
expect_rc 1 "missing version argument rejected" \
    sh "$WORK/r/scripts/release.sh"

# --- 2. repo state guards ---------------------------------------------------------
mkrepo
git -C "$WORK/r" checkout -qb feature/x
expect_rc 1 "non-master branch refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "not on master" \
    && pass "non-master refusal names the branch" \
    || fail "non-master refusal names the branch (out=$LAST_OUT)"
git -C "$WORK/r" checkout -q master

echo dirty > "$WORK/r/README.md"
expect_rc 1 "dirty working tree refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
git -C "$WORK/r" checkout -- README.md

echo "9.9.9" > "$WORK/r/VERSION"
git -C "$WORK/r" add VERSION && git -C "$WORK/r" commit -qm "wrong stamp" \
    && git -C "$WORK/r" push -q origin master
expect_rc 1 "VERSION mismatch refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "Bump lands via PR" \
    && pass "VERSION mismatch points at the bump-PR workflow" \
    || fail "VERSION mismatch points at the bump-PR workflow (out=$LAST_OUT)"
git -C "$WORK/r" reset -q --hard HEAD~1
git -C "$WORK/r" push -qf origin master

# --- 3. tag/mirror guards ---------------------------------------------------------
mkrepo
echo extra > "$WORK/r/extra"
git -C "$WORK/r" add extra && git -C "$WORK/r" commit -qm "second commit"
git -C "$WORK/r" push -q origin master
git -C "$WORK/r" tag -a 1.2.3 -m x HEAD~1
expect_rc 1 "tag taken by another commit refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "different commit" \
    && pass "taken-tag refusal explains the collision" \
    || fail "taken-tag refusal explains the collision (out=$LAST_OUT)"
git -C "$WORK/r" tag -d 1.2.3 >/dev/null

# diverged stable: an origin/stable commit master does not carry
git -C "$WORK/r" checkout -qb stable
echo divergent > "$WORK/r/divergent"
git -C "$WORK/r" add divergent && git -C "$WORK/r" commit -qm "divergence"
git -C "$WORK/r" push -q origin stable
git -C "$WORK/r" checkout -q master
expect_rc 1 "diverged stable refused (no force-push)" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "Never force-push" \
    && pass "divergence refusal forbids force-push explicitly" \
    || fail "divergence refusal forbids force-push explicitly (out=$LAST_OUT)"

# --- 4. dry-run: prints mechanics, touches nothing --------------------------------
mkrepo
expect_rc 0 "dry-run happy path exits 0" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run
printf '%s' "$LAST_OUT" | grep -q "dry-run: git.*tag -a 1.2.3" \
    && printf '%s' "$LAST_OUT" | grep -q "dry-run: git.*push" \
    && pass "dry-run announces tag + mirror push" \
    || fail "dry-run announces tag + mirror push (out=$LAST_OUT)"
[ -z "$(git -C "$WORK/r" tag)" ] \
    && pass "dry-run created no tag" \
    || fail "dry-run created no tag"

# --- 5. real run: tag + stable pushed, invariant holds ----------------------------
mkrepo
MASTER_REV="$(git -C "$WORK/r" rev-parse master)"
expect_rc 0 "real run completes (offline file:// origin)" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
[ "$(git -C "$WORK/r" rev-parse 'refs/tags/1.2.3^{commit}')" = "$MASTER_REV" ] \
    && pass "tag 1.2.3 created at master" \
    || fail "tag 1.2.3 created at master"
[ "$(git -C "$WORK/origin.git" rev-parse refs/heads/stable)" = "$MASTER_REV" ] \
    && pass "origin/stable fast-forwarded to master" \
    || fail "origin/stable fast-forwarded to master"
[ "$(git -C "$WORK/origin.git" rev-parse 'refs/tags/1.2.3^{commit}')" = "$MASTER_REV" ] \
    && pass "tag pushed to origin" \
    || fail "tag pushed to origin"
git -C "$WORK/r" fetch -q origin stable
git -C "$WORK/r" diff --quiet stable master \
    && pass "stable mirror is byte-identical to master" \
    || fail "stable mirror is byte-identical to master"

# --- 6. resumability: a second run is a no-op --------------------------------------
expect_rc 0 "second run exits 0 (resume)" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "nothing to push" \
    && pass "second run recognizes nothing to push" \
    || fail "second run recognizes nothing to push (out=$LAST_OUT)"

# --- 6b. CI pre-flight (master must be green before the mirror is cut) ------------
# The fake gh (set up next to mkrepo, green by default, already on PATH)
# answers `run list` with the post--jq TSV the script expects. FAKE_GH_*
# are exported/unset around each run — env(1) prefixes cannot reach the
# expect_rc shell function (rc 127).
mkrepo

FAKE_GH_CONCLUSION=failure; export FAKE_GH_CONCLUSION
expect_rc 1 "red CI on master blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_CONCLUSION

FAKE_GH_STATUS=in_progress; export FAKE_GH_STATUS
expect_rc 1 "still-running CI blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_STATUS

FAKE_GH_EMPTY=1; export FAKE_GH_EMPTY
expect_rc 1 "no CI runs for the commit blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_EMPTY

FAKE_GH_RAW="$(printf 'completed\tsuccess\ncompleted\tfailure')"; export FAKE_GH_RAW
expect_rc 1 "one red run among green ones still blocks" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_RAW

expect_rc 0 "green CI passes the pre-flight" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run

FAKE_GH_CONCLUSION=failure; export FAKE_GH_CONCLUSION
expect_rc 0 "--skip-ci overrides the CI gate" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run --skip-ci
unset FAKE_GH_CONCLUSION

grep -q 'actions/runs?branch=master' "$RELEASE" \
    && pass "CI gate has the curl+python3 fallback (no gh needed on the host)" \
    || fail "CI gate has the curl+python3 fallback (no gh needed on the host)"

# --- 7. static: test gate + suite wiring -------------------------------------------
grep -q 'make -C "$REPO" test check-version' "$RELEASE" \
    && pass "release runs the suite (make test check-version) by default" \
    || fail "release runs the suite (make test check-version) by default"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All release-helper tests passed.${NC}"
exit 0
