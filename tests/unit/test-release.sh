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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RELEASE="$SCRIPT_DIR/../../scripts/release.sh"
GENSUMS="$SCRIPT_DIR/../../scripts/gen-sums.sh"
RELSUMS="$SCRIPT_DIR/../../scripts/release-sums.sh"
FILES_DIR="$SCRIPT_DIR/../../files"
MAKEFILE="$SCRIPT_DIR/../../Makefile"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

WORK="$(work_new)"

# mkrepo: fresh sandbox at $WORK/r with origin=$WORK/origin.git, master
# holding one commit (VERSION=1.2.3 + the release script + gen-sums +
# a files/ tree + a FRESH SHA256SUMS, issue #478), all pushed. The
# sandbox copy of each script resolves REPO from its own location, so
# copying the real scripts into the sandbox tests the real logic.
# _write_cksum_page <file> <entry-sha>: a page carrying one fresh
# entry-checksum marker block (issue #492) — the shape release-sums.sh
# and the 2.6 pre-flight expect in README.md and getting-started.md.
_write_cksum_page() {
    _wcp_file="$1"
    _wcp_sha="$2"
    mkdir -p "$(dirname "$_wcp_file")"
    {
        echo "kit"
        echo "<!-- opk-checksum:start -->"
        echo ""
        echo '```bash'
        echo "curl -fsSL -o /tmp/opk-install.sh https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh &&"
        echo "echo \"${_wcp_sha}  /tmp/opk-install.sh\" | sha256sum -c - &&"
        echo "sudo env KIT_BRANCH=stable bash /tmp/opk-install.sh"
        echo '```'
        echo ""
        echo "<!-- opk-checksum:end -->"
    } >"$_wcp_file"
}

mkrepo() {
    rm -rf "${WORK:?}/r" "${WORK:?}/origin.git"
    git init -q -b master "$WORK/origin.git" --bare
    git init -q -b master "$WORK/r"
    git -C "$WORK/r" config user.email test@invalid
    git -C "$WORK/r" config user.name test
    mkdir -p "$WORK/r/scripts"
    cp "$RELEASE" "$WORK/r/scripts/release.sh"
    cp "$GENSUMS" "$WORK/r/scripts/gen-sums.sh"
    chmod 755 "$WORK/r/scripts/gen-sums.sh"
    cp "$RELSUMS" "$WORK/r/scripts/release-sums.sh"
    chmod 755 "$WORK/r/scripts/release-sums.sh"
    cp -R "$FILES_DIR" "$WORK/r/files"
    echo "1.2.3" >"$WORK/r/VERSION"
    # Both entry-checksum pages fresh (issue #492): the 2.6 pre-flight
    # hashes the fixture's install.sh and refuses a stale block, so
    # every scenario starts from fresh ones.
    _eksha="$(sha256sum "$WORK/r/files/install.sh" | cut -d' ' -f1)"
    _write_cksum_page "$WORK/r/README.md" "$_eksha"
    _write_cksum_page "$WORK/r/docs/getting-started.md" "$_eksha"
    sh "$WORK/r/scripts/gen-sums.sh" >"$WORK/r/SHA256SUMS"
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
cat >"$WORK/ghbin/gh" <<'FAKEGH'
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
    _want="$1"
    _desc="$2"
    shift 2
    set +e
    out=$("$@" 2>&1)
    rc=$?
    set -e
    LAST_OUT="$out"
    if [ "$rc" = "$_want" ]; then pass "$_desc"; else fail "$_desc (rc=$rc, out=$out)"; fi
}

# --- 1. argument guards -----------------------------------------------------------
mkrepo
expect_rc 1 "bare 'v' prefix rejected (tags carry no v)" \
    sh "$WORK/r/scripts/release.sh" v1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "bare x.y.z" &&
    pass "v-prefix rejection explains the bare stamp" ||
    fail "v-prefix rejection explains the bare stamp (out=$LAST_OUT)"
expect_rc 1 "missing version argument rejected" \
    sh "$WORK/r/scripts/release.sh"

# --- 2. repo state guards ---------------------------------------------------------
mkrepo
git -C "$WORK/r" checkout -qb feature/x
expect_rc 1 "non-master branch refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "not on master" &&
    pass "non-master refusal names the branch" ||
    fail "non-master refusal names the branch (out=$LAST_OUT)"
git -C "$WORK/r" checkout -q master

echo dirty >"$WORK/r/README.md"
expect_rc 1 "dirty working tree refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
git -C "$WORK/r" checkout -- README.md

echo "9.9.9" >"$WORK/r/VERSION"
git -C "$WORK/r" add VERSION && git -C "$WORK/r" commit -qm "wrong stamp" &&
    git -C "$WORK/r" push -q origin master
expect_rc 1 "VERSION mismatch refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "Bump lands via PR" &&
    pass "VERSION mismatch points at the bump-PR workflow" ||
    fail "VERSION mismatch points at the bump-PR workflow (out=$LAST_OUT)"
git -C "$WORK/r" reset -q --hard HEAD~1
git -C "$WORK/r" push -qf origin master

# --- 3. tag/mirror guards ---------------------------------------------------------
mkrepo
echo extra >"$WORK/r/extra"
git -C "$WORK/r" add extra && git -C "$WORK/r" commit -qm "second commit"
git -C "$WORK/r" push -q origin master
git -C "$WORK/r" tag -a 1.2.3 -m x HEAD~1
expect_rc 1 "tag taken by another commit refused" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "different commit" &&
    pass "taken-tag refusal explains the collision" ||
    fail "taken-tag refusal explains the collision (out=$LAST_OUT)"
git -C "$WORK/r" tag -d 1.2.3 >/dev/null

# diverged stable: an origin/stable commit master does not carry
git -C "$WORK/r" checkout -qb stable
echo divergent >"$WORK/r/divergent"
git -C "$WORK/r" add divergent && git -C "$WORK/r" commit -qm "divergence"
git -C "$WORK/r" push -q origin stable
git -C "$WORK/r" checkout -q master
expect_rc 1 "diverged stable refused (no force-push)" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "Never force-push" &&
    pass "divergence refusal forbids force-push explicitly" ||
    fail "divergence refusal forbids force-push explicitly (out=$LAST_OUT)"

# --- 4. dry-run: prints mechanics, touches nothing --------------------------------
mkrepo
expect_rc 0 "dry-run happy path exits 0" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run
printf '%s' "$LAST_OUT" | grep -q "dry-run: git.*tag -a 1.2.3" &&
    printf '%s' "$LAST_OUT" | grep -q "dry-run: git.*push" &&
    pass "dry-run announces tag + mirror push" ||
    fail "dry-run announces tag + mirror push (out=$LAST_OUT)"
[ -z "$(git -C "$WORK/r" tag)" ] &&
    pass "dry-run created no tag" ||
    fail "dry-run created no tag"

# --- 5. real run: tag + stable pushed, invariant holds ----------------------------
mkrepo
MASTER_REV="$(git -C "$WORK/r" rev-parse master)"
expect_rc 0 "real run completes (offline file:// origin)" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
[ "$(git -C "$WORK/r" rev-parse 'refs/tags/1.2.3^{commit}')" = "$MASTER_REV" ] &&
    pass "tag 1.2.3 created at master" ||
    fail "tag 1.2.3 created at master"
[ "$(git -C "$WORK/origin.git" rev-parse refs/heads/stable)" = "$MASTER_REV" ] &&
    pass "origin/stable fast-forwarded to master" ||
    fail "origin/stable fast-forwarded to master"
[ "$(git -C "$WORK/origin.git" rev-parse 'refs/tags/1.2.3^{commit}')" = "$MASTER_REV" ] &&
    pass "tag pushed to origin" ||
    fail "tag pushed to origin"
git -C "$WORK/r" fetch -q origin stable
git -C "$WORK/r" diff --quiet stable master &&
    pass "stable mirror is byte-identical to master" ||
    fail "stable mirror is byte-identical to master"

# --- 6. resumability: a second run is a no-op --------------------------------------
expect_rc 0 "second run exits 0 (resume)" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
printf '%s' "$LAST_OUT" | grep -q "nothing to push" &&
    pass "second run recognizes nothing to push" ||
    fail "second run recognizes nothing to push (out=$LAST_OUT)"

# --- 6a. resume after a PARTIAL push: tag missing on origin (0.0.45c C7) ----------
# A previous run can move stable but fail on the tag ref (per-ref partial
# push failure) — or the maintainer created the tag without pushing it.
# The resume path used to derive PUSH_NEEDED from the LOCAL tag only and
# printed "nothing to push ... released" while tag-pinned installs
# (KIT_BRANCH=<version>) 404'd. The ls-remote probe closes it: the tag
# must exist on ORIGIN.
git -C "$WORK/origin.git" tag -d 1.2.3 >/dev/null
expect_rc 0 "resume with tag missing on origin exits 0" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests
if printf '%s' "$LAST_OUT" | grep -q "nothing to push"; then
    fail "resume re-pushes a tag that never reached origin (C7, out says nothing-to-push)"
else
    pass "resume re-pushes a tag that never reached origin (C7)"
fi
[ "$(git -C "$WORK/origin.git" rev-parse 'refs/tags/1.2.3^{commit}' 2>/dev/null)" = "$MASTER_REV" ] &&
    pass "the missing tag actually landed on origin (C7)" ||
    fail "the missing tag actually landed on origin (C7)"

# --- 6b. CI pre-flight (master must be green before the mirror is cut) ------------
# The fake gh (set up next to mkrepo, green by default, already on PATH)
# answers `run list` with the post--jq TSV the script expects. FAKE_GH_*
# are exported/unset around each run — env(1) prefixes cannot reach the
# expect_rc shell function (rc 127).
mkrepo

FAKE_GH_CONCLUSION=failure
export FAKE_GH_CONCLUSION
expect_rc 1 "red CI on master blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_CONCLUSION

FAKE_GH_STATUS=in_progress
export FAKE_GH_STATUS
expect_rc 1 "still-running CI blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_STATUS

FAKE_GH_EMPTY=1
export FAKE_GH_EMPTY
expect_rc 1 "no CI runs for the commit blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_EMPTY

FAKE_GH_RAW="$(printf 'completed\tsuccess\ncompleted\tfailure')"
export FAKE_GH_RAW
expect_rc 1 "one red run among green ones still blocks" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run 2>/dev/null
unset FAKE_GH_RAW

expect_rc 0 "green CI passes the pre-flight" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run

FAKE_GH_CONCLUSION=failure
export FAKE_GH_CONCLUSION
expect_rc 0 "--skip-ci overrides the CI gate" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run --skip-ci
unset FAKE_GH_CONCLUSION

grep -q 'actions/runs?branch=master' "$RELEASE" &&
    pass "CI gate has the curl+python3 fallback (no gh needed on the host)" ||
    fail "CI gate has the curl+python3 fallback (no gh needed on the host)"

# hostile-locale pin (#510 M4): the fallback decodes the whole runs list;
# under a 7-bit locale the unpinned json.load used to die on an unread
# non-ASCII field (a run display title ANYWHERE in the list) and the
# release reported "cannot verify CI status". Buffer read pin (#485 F22
# shape): the rows for the matching sha must still come out. The
# shipped parser invokes python3 WITHOUT -I, so PYTHONIOENCODING=ascii
# is honored here (strict stdin — the full decode kill); the extracted
# parser below runs under the same shape. Control arm first (harness
# #510).
P510="$(hostile_stdio_python)"
if printf '{"k":"Pr\303\274fung"}' | PATH="$P510:$PATH" LC_ALL=C LANG=C PYTHONUTF8=0 \
    PYTHONCOERCECLOCALE=0 PYTHONIOENCODING=ascii \
    python3 -c 'import json,sys; json.load(sys.stdin)' >/dev/null 2>&1; then
    fail "control arm: hostile stdio not effective -- the #510 pins would pass vacuously"
else
    pass "control arm: strict 7-bit stdin kills the unpinned decode (#510)"
fi
CI_PY="$(work_new_file)"
sed -n "/python3 -c '/,/2>\/dev\/null)\"; then/p" "$RELEASE" |
    sed -e "1s/^.*python3 -c '//" -e '$d' >"$CI_PY"
if [ -s "$CI_PY" ] && grep -q '^import json, os, sys' "$CI_PY" &&
    ! grep -q '2>/dev/null' "$CI_PY"; then
    pass "release.sh: CI gate parser extractable"
else
    fail "release.sh: CI gate parser extractable"
fi
cat >"${WORK:?}/ci-runs-nb.json" <<'EOF'
{"workflow_runs":[{"head_sha":"other","status":"completed","conclusion":"success","display_title":"Prüfung: nicht-ASCII Titel"},
 {"head_sha":"abc123","status":"completed","conclusion":"success","display_title":"release prep"}]}
EOF
CI_RUNS_RC=0
CI_RUNS_OUT="$(PATH="$P510:$PATH" LC_ALL=C LANG=C PYTHONUTF8=0 PYTHONCOERCECLOCALE=0 \
    PYTHONIOENCODING=ascii HEAD_SHA=abc123 python3 "$CI_PY" <"${WORK:?}/ci-runs-nb.json" 2>/dev/null)" || CI_RUNS_RC=$?
if [ "$CI_RUNS_RC" = 0 ] &&
    [ "$CI_RUNS_OUT" = "$(printf 'completed\tsuccess')" ]; then
    pass "release.sh: non-ASCII runs list decodes under the 7-bit locale (#510 M4)"
else
    fail "release.sh CI parse must survive a non-ASCII runs list under LC_ALL=C (rc=$CI_RUNS_RC out=[$CI_RUNS_OUT]) (#510 M4)"
fi
rm -f "$CI_PY" "${WORK:?}/ci-runs-nb.json"

# --- 6c. SHA256SUMS freshness pre-flight (issue #478) -----------------------------
# A release must not be cut from a stale integrity manifest: streamed
# installs verify every fetched file against it. A committed files/
# change without `make sums` blocks the release; a fresh manifest passes.
mkrepo
expect_rc 0 "fresh SHA256SUMS passes the pre-flight" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run
printf 'drift\n' >>"$WORK/r/files/install.sh"
git -C "$WORK/r" add files/install.sh
git -C "$WORK/r" commit -qm "tamper files/ without regenerating the manifest"
git -C "$WORK/r" push -q origin master
expect_rc 1 "stale SHA256SUMS blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run
if printf '%s' "$LAST_OUT" | grep -q 'SHA256SUMS is stale'; then
    pass "stale-manifest refusal points at make sums"
else
    fail "stale-manifest refusal points at make sums (out=$LAST_OUT)"
fi
# Regenerating heals the sandbox (and proves the refusal was the drift,
# not the fixture): make sums' exact pipeline + make release-sums (the
# tamper staled the entry block too, #492) + a re-run.
sh "$WORK/r/scripts/gen-sums.sh" >"$WORK/r/SHA256SUMS"
sh "$WORK/r/scripts/release-sums.sh" >/dev/null
git -C "$WORK/r" add SHA256SUMS README.md docs/getting-started.md
git -C "$WORK/r" commit -qm "regenerate SHA256SUMS + entry checksums"
git -C "$WORK/r" push -q origin master
expect_rc 0 "regenerated SHA256SUMS releases again" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run

# --- 6e. entry-checksum freshness pre-flight (issue #492) --------------------------
# A release must not ship a README whose verified-install hash fails
# against the served install.sh: the 2.6 pre-flight hashes the tree's
# install.sh and refuses a stale marker block by name.
mkrepo
expect_rc 0 "fresh entry checksum passes the pre-flight" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run
_ek_stale="$(printf 'a%.0s' $(seq 1 64))"
sed -i "s/^echo \"[0-9a-f]\\{64\\}  \\/tmp\\/opk-install.sh\"/echo \"${_ek_stale}  \\/tmp\\/opk-install.sh\"/" "$WORK/r/README.md"
git -C "$WORK/r" add README.md
git -C "$WORK/r" commit -qm "stale the entry checksum block"
git -C "$WORK/r" push -q origin master
expect_rc 1 "stale entry checksum blocks the release" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run
if printf '%s' "$LAST_OUT" | grep -q 'entry checksum stale'; then
    pass "stale-checksum refusal names the drift (discriminates a run failure)"
else
    fail "stale-checksum refusal names the drift (out=$LAST_OUT)"
fi
# Regen heals (and proves the refusal was the block, not the fixture).
sh "$WORK/r/scripts/release-sums.sh" >/dev/null
git -C "$WORK/r" add README.md docs/getting-started.md
git -C "$WORK/r" commit -qm "regenerate entry checksum"
git -C "$WORK/r" push -q origin master
expect_rc 0 "regenerated entry checksum releases again" \
    sh "$WORK/r/scripts/release.sh" 1.2.3 --skip-tests --dry-run

# --- 6f. a A3: a failing sha256sum aborts loudly, writes nothing ---------------
# POSIX sh has no pipefail: without the shape validation a failing
# sha256sum yields an EMPTY entry_sha that rewrite mode would write
# into both pages with a success message. The stub proves the abort.
mkrepo
mkdir -p "$WORK/badbin"
printf '#!/bin/sh\necho "stub: sha256sum down" >&2\nexit 1\n' >"$WORK/badbin/sha256sum"
chmod 755 "$WORK/badbin/sha256sum"
_ek_out="$(PATH="$WORK/badbin:$PATH" sh "$WORK/r/scripts/release-sums.sh" 2>&1)" && _ek_rc=0 || _ek_rc=$?
[ "$_ek_rc" -eq 1 ] &&
    pass "failing sha256sum aborts rc 1 (a A3)" ||
    fail "failing sha256sum aborts rc 1, got $_ek_rc (out=$_ek_out)"
printf '%s' "$_ek_out" | grep -q 'could not derive a sha256' &&
    pass "empty-hash abort names the derivation failure (a A3)" ||
    fail "empty-hash abort names the derivation failure (out=$_ek_out)"
if [ -z "$(git -C "$WORK/r" status --porcelain)" ]; then
    pass "failed derivation touched no page (a A3)"
else
    fail "failed derivation modified the tree (a A3)"
fi

# --- 6g. a A4: a duplicated echo line cannot be "successfully" rewritten -------
# The guard counts marker pairs, not echo lines: two echo lines used to
# end as two canonical lines with rc 0. The post-rewrite verification
# must refuse.
mkrepo
awk '/^echo "[0-9a-f]/ { print; print; next } { print }' \
    "$WORK/r/README.md" >"$WORK/r/README.md.dup" && mv "$WORK/r/README.md.dup" "$WORK/r/README.md"
_ek_out="$(sh "$WORK/r/scripts/release-sums.sh" 2>&1)" && _ek_rc=0 || _ek_rc=$?
[ "$_ek_rc" -eq 1 ] &&
    pass "duplicated echo line fails the rewrite verification (a A4)" ||
    fail "duplicated echo line failed loudly, got $_ek_rc (out=$_ek_out)"
printf '%s' "$_ek_out" | grep -q 'rewrite verification failed' &&
    pass "dup refusal tells the maintainer to fix the block by hand (a A4)" ||
    fail "dup refusal message missing (out=$_ek_out)"

# --- 6h. make sums fails loud over a broken manifest write (#701) ------------------
# The old recipe closed with `mv …; echo …`: any failed mv left the
# manifest unwritten while the target exited rc 0 (fail-open, #701).
# These arms drive the REAL Makefile's sums target in the sandbox:
# broken target, failing mv (PATH stub), and both happy legs.
mkrepo
cp "$MAKEFILE" "$WORK/r/Makefile"
rm -f "${WORK:?}/r/SHA256SUMS"
mkdir "${WORK:?}/r/SHA256SUMS"
_701_rc=0
_701_out="$(make -C "$WORK/r" sums 2>&1)" || _701_rc=$?
if [ "$_701_rc" -ne 0 ] &&
    printf '%s' "$_701_out" | grep -q 'not a regular file'; then
    pass "sums: non-file manifest target refused loud (#701)"
else
    fail "sums: non-file manifest target refused loud (rc=$_701_rc out=$_701_out) (#701)"
fi
if printf '%s' "$_701_out" | grep -q 'SHA256SUMS regenerated'; then
    fail "sums: broken-target refusal still prints the success line (#701)"
else
    pass "sums: broken-target refusal prints no success line (#701)"
fi
# Failing mv (PATH stub, the 6f badbin idiom): abort rc != 0, named
# cause, temp cleaned, committed manifest untouched.
mkdir -p "${WORK:?}/mvfail"
printf '#!/bin/sh\necho "stub: mv down" >&2\nexit 1\n' >"${WORK:?}/mvfail/mv"
chmod 755 "${WORK:?}/mvfail/mv"
mkrepo
cp "$MAKEFILE" "$WORK/r/Makefile"
printf 'drift\n' >>"${WORK:?}/r/files/install.sh"
_701_rc=0
_701_out="$(PATH="${WORK:?}/mvfail:$PATH" make -C "$WORK/r" sums 2>&1)" || _701_rc=$?
if [ "$_701_rc" -ne 0 ] &&
    printf '%s' "$_701_out" | grep -q 'replacing SHA256SUMS failed'; then
    pass "sums: failing mv aborts loud with the named cause (#701)"
else
    fail "sums: failing mv aborts loud (rc=$_701_rc out=$_701_out) (#701)"
fi
if [ -z "$(ls "${WORK:?}"/r/SHA256SUMS.*.tmp 2>/dev/null)" ] &&
    [ -z "$(git -C "$WORK/r" status --porcelain -- SHA256SUMS)" ]; then
    pass "sums: failed mv leaves no temp, committed manifest intact (#701)"
else
    fail "sums: failed mv leaves no temp, committed manifest intact (#701)"
fi
# Happy legs: a stale manifest regenerates for real; a fresh one no-ops.
_701_rc=0
_701_out="$(make -C "$WORK/r" sums 2>&1)" || _701_rc=$?
if [ "$_701_rc" -eq 0 ] &&
    printf '%s' "$_701_out" | grep -q 'SHA256SUMS regenerated' &&
    [ -n "$(git -C "$WORK/r" status --porcelain -- SHA256SUMS)" ]; then
    pass "sums: stale manifest regenerates and really writes (#701)"
else
    fail "sums: stale manifest regenerates and really writes (rc=$_701_rc out=$_701_out) (#701)"
fi
_701_rc=0
_701_out="$(make -C "$WORK/r" sums 2>&1)" || _701_rc=$?
if [ "$_701_rc" -eq 0 ] &&
    printf '%s' "$_701_out" | grep -q 'already fresh'; then
    pass "sums: fresh manifest takes the no-op branch (#701)"
else
    fail "sums: fresh manifest takes the no-op branch (rc=$_701_rc out=$_701_out) (#701)"
fi

# --- 7. static: test gate + suite wiring -------------------------------------------
grep -q 'make -C "$REPO" test check-version' "$RELEASE" &&
    pass "release runs the suite (make test check-version) by default" ||
    fail "release runs the suite (make test check-version) by default"

# --- 7a. static: release-sums temp hygiene (pr-00600 a A2) -------------------------
# mktemp (not a predictable $$ name: the checkout is group-writable for
# the agent user, and the temp redirect follows a planted symlink) and
# the INT/TERM/EXIT traps release.sh arms for the same pattern (#493 a B4).
grep -q 'mktemp "${path}.release-sums.XXXXXX"' "$RELSUMS" &&
    pass "release-sums temp name is unguessable (mktemp)" ||
    fail "release-sums lost its mktemp temp handling"
_traps=$(grep -c '^trap ' "$RELSUMS")
[ "$_traps" -eq 3 ] &&
    pass "release-sums arms EXIT/INT/TERM temp traps" ||
    fail "release-sums trap count wrong ($_traps, want 3)"

# --- 7b. static: entry-hash shape validation (pr-00600 a A3) -----------------------
grep -qF "printf '%s' \"\$entry_sha\" | grep -q" "$RELSUMS" &&
    pass "release-sums validates the derived hash shape before use" ||
    fail "release-sums lost the entry_sha shape validation"

# --- 0.0.44b W16: --help carries no code lines (V26); status list (V27) -----------------
_h_out=$(sh "$RELEASE" --help 2>&1 || true)
case "$_h_out" in
    *"set -eu"* | *REPO=*) fail "--help prints only the header comment, no code lines (V26)" ;;
    *) pass "--help prints only the header comment, no code lines (V26)" ;;
esac
_list_line=$(grep -n 'in_progress|queued' "$RELEASE" | head -1)
case "$_list_line" in
    *requested*) [ -n "$_list_line" ] && ! printf '%s' "$_list_line" | grep -q action_required &&
        pass "still-running list: statuses only, requested in, action_required out (V27)" ||
        fail "still-running list: statuses only, requested in, action_required out (V27)" ;;
    *) fail "still-running list: statuses only, requested in, action_required out (V27)" ;;
esac

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All release-helper tests passed.${NC}"
exit 0
