#!/bin/sh
# tests/unit/test-fetch-integrity.sh -- SHA256SUMS download verification
# (issue #478):
#   1. generator (scripts/gen-sums.sh): coreutils line format, coverage
#      == KIT_FILES, path sort order, no self-entry, sample digests,
#      determinism, loud failures (missing file)
#   2. repo freshness: the committed SHA256SUMS matches files/ on disk
#      (the drift gate every `make test` runs), plus a discriminating
#      scratch-tamper arm
#   3. fetch_kit end-to-end against a file-server curl stub (no network,
#      no real curl dependency -- check-host keeps curl an e2e-only
#      tool): success, tampered body, missing manifest, malformed
#      manifest, missing entry, duplicate entry, KIT_SHA_VERIFY=0
#      break-glass, missing sha256sum, install.sh twin parity
#   4. ensure_local_file heal path: verified re-fetch + tamper abort
#   5. update.sh tree verification: the old-fetcher window (_fk_sums_
#      resolve fetches a manifest the pre-manifest fetcher never pulled,
#      verify_fetched_tree gates the staged tree) + checkout carve-out
#   6. wiring pins (check_live): the gate and its seam exist in both hosts
#
# Every failure arm also asserts the issue's no-deployment + cleanup
# contract: the file never lands in the staged tree, no temp leaks.
#
# Run: sh tests/unit/test-fetch-integrity.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
GENSUMS="$REPO/scripts/gen-sums.sh"
. "$SCRIPT_DIR/lib/harness.sh"

WORK="$(work_new)" || {
    echo "fetch integrity tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

# KIT_LIST: update.sh's KIT_FILES, one flat space-separated line (same
# normalize idiom as tests/unit/test-kit-files.sh, which pins it equal
# to install.sh's inline fetch list).
KIT_LIST="$(sed -n '/^KIT_FILES="/,/"$/p' "$UPDATE" |
    sed -e 's/^KIT_FILES="//' -e 's/"$//' -e 's/\\$//' |
    tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//')"
if [ -z "$KIT_LIST" ]; then
    echo "fetch integrity tests: KIT_FILES extraction came up empty" >&2
    exit 1
fi
KIT_COUNT="$(printf '%s\n' $KIT_LIST | wc -l | tr -d ' ')"

# --- 1. generator ----------------------------------------------------------------

GEN_OUT="$(sh "$GENSUMS")"
GEN_RC=$?
GEN_OUT2="$(sh "$GENSUMS")"
GEN_RC2=$?
if [ "$GEN_RC" -eq 0 ] && [ -n "$GEN_OUT" ]; then
    pass "generator runs against the checkout ($(printf '%s\n' "$GEN_OUT" | wc -l | tr -d ' ') lines)"
else
    fail "generator runs against the checkout (rc=$GEN_RC)"
fi

# 1a. line format: every line exactly `<64 lc hex><2 spaces><ref path>`.
if printf '%s\n' "$GEN_OUT" | grep -vEq '^[0-9a-f]{64}  [A-Za-z0-9._/-]+$'; then
    fail "generator lines are coreutils sha256sum format (a line deviates)"
else
    pass "generator lines are coreutils sha256sum format"
fi

# 1b. coverage: names == KIT_FILES (both directions via sorted diff;
# the files/ prefix is the generator's repo-root-relative form).
printf '%s\n' "$GEN_OUT" | awk '{print $2}' | sed 's|^files/||' | LC_ALL=C sort >"$WORK/gen-names.txt"
printf '%s\n' $KIT_LIST | LC_ALL=C sort >"$WORK/list-names.txt"
if diff -q "$WORK/gen-names.txt" "$WORK/list-names.txt" >/dev/null; then
    pass "generator covers exactly the KIT_FILES set ($KIT_COUNT names)"
else
    fail "generator names and KIT_FILES drifted:"
    diff "$WORK/list-names.txt" "$WORK/gen-names.txt" | sed 's/^/        /'
fi

# 1c. deterministic byte-for-byte (sorted paths, no timestamps).
if [ "$GEN_RC2" -eq 0 ] && [ "$GEN_OUT" = "$GEN_OUT2" ]; then
    pass "generator output is deterministic"
else
    fail "generator output differs between two runs"
fi

# 1d. path-sorted (stable diffs when the fetch list is reordered).
if printf '%s\n' "$GEN_OUT" | awk '{print $2}' | LC_ALL=C sort -c; then
    pass "generator output is sorted by path"
else
    fail "generator output is not sorted by path"
fi

# 1e. no self-entry (a manifest cannot carry its own digest).
if printf '%s\n' "$GEN_OUT" | grep -q '  SHA256SUMS$'; then
    fail "generator emits no SHA256SUMS self-entry (found one)"
else
    pass "generator emits no SHA256SUMS self-entry"
fi

# 1f. sample digests: recompute three files the way production does and
# compare with the generator's lines (generator vs verifier are
# different code paths -- the awk lookup vs sha256sum itself).
_fi_sample_ok=1
for _fi_n in VERSION install.sh opencode-permissions-kit-lib/sh/ui.sh; do
    if [ "$_fi_n" = "VERSION" ]; then
        _fi_p="$REPO/VERSION"
        _fi_mname="VERSION"
    else
        _fi_p="$REPO/files/$_fi_n"
        _fi_mname="files/$_fi_n"
    fi
    _fi_h="$(sha256sum "$_fi_p" | awk '{print $1}')"
    if ! printf '%s\n' "$GEN_OUT" | grep -qF "$_fi_h  $_fi_mname"; then
        _fi_sample_ok=0
    fi
done
if [ "$_fi_sample_ok" -eq 1 ]; then
    pass "generator digests match recomputed sha256sum (3-file sample)"
else
    fail "generator digests match recomputed sha256sum (sample deviates)"
fi

# 1g. loud failures: a scratch clone with one listed file removed must
# abort naming the file (never emit a partial manifest). The clone gets
# the real generator, a real update.sh copy and symlinks for every
# listed file -- the removal breaks exactly one link. NOTHING in this
# suite ever writes through a clone symlink into the repo tree.
_fi_clone="$WORK/genclone"
mkdir -p "$_fi_clone/scripts" "$_fi_clone/files/opencode-permissions-kit-lib/management"
cp "$GENSUMS" "$_fi_clone/scripts/gen-sums.sh"
cp "$UPDATE" "$_fi_clone/files/opencode-permissions-kit-lib/management/update.sh"
ln -s "$REPO/VERSION" "$_fi_clone/VERSION"
for _fi_n in $KIT_LIST; do
    [ "$_fi_n" = "VERSION" ] && continue
    mkdir -p "$_fi_clone/files/$(dirname "$_fi_n")"
    ln -s "$REPO/files/$_fi_n" "$_fi_clone/files/$_fi_n"
done
rm -f "${_fi_clone:?}/files/etc/umask.sh"
if sh "$_fi_clone/scripts/gen-sums.sh" >"$WORK/clone-out.txt" 2>"$WORK/clone-err.txt"; then
    fail "generator aborts on a missing listed file (it exited 0)"
else
    if grep -q 'etc/umask.sh' "$WORK/clone-err.txt" &&
        grep -q 'missing from the checkout' "$WORK/clone-err.txt" &&
        [ ! -s "$WORK/clone-out.txt" ]; then
        pass "generator aborts on a missing listed file, names it, emits nothing"
    else
        fail "generator missing-file abort names the file and emits nothing (err=$(cat "$WORK/clone-err.txt"))"
    fi
fi

# --- 2. repo freshness (the CI drift gate) ---------------------------------------

if [ ! -f "$REPO/SHA256SUMS" ]; then
    fail "committed SHA256SUMS exists (run: make sums)"
else
    pass "committed SHA256SUMS exists"
    printf '%s\n' "$GEN_OUT" >"$WORK/sums-now.txt"
    if diff -q "$WORK/sums-now.txt" "$REPO/SHA256SUMS" >/dev/null; then
        pass "committed SHA256SUMS is fresh (matches files/ on disk)"
    else
        fail "committed SHA256SUMS is STALE — regenerate and commit: make sums"
        diff "$REPO/SHA256SUMS" "$WORK/sums-now.txt" | sed 's/^/        /' | head -10
    fi
fi

# 2b. the freshness check discriminates: a tampered scratch copy must
# produce a manifest that differs from the committed one (the L4 duty —
# a drift gate that cannot go red is decoration). The tampered file is
# a real COPY in the clone, never a symlink write into the repo tree.
rm -f "${_fi_clone:?}/files/install.sh"
printf 'tampered\n' >"$_fi_clone/files/install.sh"
ln -s "$REPO/files/etc/umask.sh" "$_fi_clone/files/etc/umask.sh"
if sh "$_fi_clone/scripts/gen-sums.sh" >"$WORK/clone-tampered.txt" &&
    ! diff -q "$WORK/clone-tampered.txt" "$REPO/SHA256SUMS" >/dev/null; then
    pass "freshness check discriminates (tampered tree yields a different manifest)"
else
    fail "freshness check discriminates (tampered tree produced the committed manifest)"
fi

# --- shared fixture machinery (sections 3-5) -------------------------------------

# extract_sums_helpers <host>: the marker-delimited fetch-integrity
# helper block, executed by the inner shells below (behavioral probe,
# raw by the conventions carve-out).
extract_sums_helpers() {
    sed -n '/^# --- fetch integrity (issue #478) ---/,/^# --- end fetch integrity ---/p' "$1" |
        sed '1d;$d'
}

# srvbin: the file-server curl stub + the tools the extracted code
# needs. Real sha256sum on purpose -- the arms hash real bytes.
SRVBIN="$WORK/srvbin"
mkdir -p "$SRVBIN"
for _fi_t in mktemp mkdir chmod mv rm cat sed awk grep sort head tr diff find; do
    _fi_w="$(command -v "$_fi_t" 2>/dev/null || true)"
    [ -n "$_fi_w" ] && ln -s "$_fi_w" "$SRVBIN/$_fi_t"
done
cat >"$SRVBIN/curl" <<'FAKECURL'
#!/bin/sh
# File-server stub: strips $KIT_BASE_URL from the URL and copies the
# fixture file to the -o target. Missing file = exit 1 (curl -f shape).
_out=""
_url=""
while [ $# -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        _out="$2"
        shift 2
        continue
    fi
    _url="$1"
    shift
done
case "$_url" in
    "$KIT_BASE_URL"/*) ;;
    *) exit 1 ;;
esac
_p="${_url#"$KIT_BASE_URL"/}"
[ -f "$KIT_BASE_ROOT/$_p" ] || exit 1
cat "$KIT_BASE_ROOT/$_p" >"$_out" || exit 1
FAKECURL
chmod 755 "$SRVBIN/curl"
# NOSHBIN: same as SRVBIN but WITHOUT any sha256sum at all — the tool
# probe must abort on absence (#493 a C9: the previous dead-644-file
# variant relied on dash's command -v refusing non-executable files;
# bash accepts them, which reddened the arm under kcov's sh→bash shim
# — evidence in issue #486. Absence trips the probe under every shell).
NOSHBIN="$WORK/noshbin"
cp -R "$SRVBIN" "$NOSHBIN"
rm -f "${NOSHBIN:?}/sha256sum"
# env(1) must still resolve the interpreter itself with this PATH.
_fi_w="$(command -v sh 2>/dev/null || true)"
[ -n "$_fi_w" ] && ln -s "$_fi_w" "$NOSHBIN/sh"
# NOCURLBIN: the resolve/verify checkout arm — the tools the extracted
# block itself needs, deliberately NO curl: a resolve that wrongly
# reached for the network dies "curl: not found" and the arm reddens
# (discrimination).
NOCURLBIN="$WORK/nocurlbin"
mkdir -p "$NOCURLBIN"
for _fi_t in sha256sum cat sh; do
    _fi_w="$(command -v "$_fi_t" 2>/dev/null || true)"
    [ -n "$_fi_w" ] && ln -s "$_fi_w" "$NOCURLBIN/$_fi_t"
done

# build_fixture <root>: repo-root-shaped tree (files/ + VERSION) with a
# stub body per listed name and a matching SHA256SUMS (name-sorted like
# the generator's output).
build_fixture() {
    _fx_root="$1"
    mkdir -p "$_fx_root/files"
    for _fi_n in $KIT_LIST; do
        if [ "$_fi_n" = "VERSION" ]; then
            printf '9.9.9\n' >"$_fx_root/VERSION"
        else
            mkdir -p "$_fx_root/files/$(dirname "$_fi_n")"
            printf 'fixture-body %s\n' "$_fi_n" >"$_fx_root/files/$_fi_n"
        fi
    done
    fixture_manifest "$_fx_root"
}

# fixture_manifest <root>: (re)write <root>/SHA256SUMS from the tree's
# CURRENT contents, repo-root-relative names like the generator's
# output (`files/<name>` / `VERSION`). Arms that tamper a body AFTER
# this call test the stale-manifest direction without regenerating.
fixture_manifest() {
    _fm_root="$1"
    (
        cd "$_fm_root" || exit 1
        for _fi_n in $KIT_LIST; do
            if [ "$_fi_n" = "VERSION" ]; then
                _fm_p="VERSION"
                _fm_mname="VERSION"
            else
                _fm_p="files/$_fi_n"
                _fm_mname="files/$_fi_n"
            fi
            printf '%s  %s\n' "$(sha256sum "$_fm_p" | awk '{print $1}')" "$_fm_mname"
        done | LC_ALL=C sort -k2,2
    ) >"$_fm_root/SHA256SUMS"
}

# run_fetch_kit <host> <fixture-root> [NAME=VALUE...]: runs the host's
# extracted fetch_kit + integrity helpers against the fixture via the
# curl stub; extra arguments become environment assignments. Sets
# RUN_RC / RUN_OUT / RUN_BASE / RUN_DIR / RUN_TMP. The per-arm TMPDIR
# is fresh so the leftover probe below is honest.
run_fetch_kit() {
    _rk_host="$1"
    _rk_root="$2"
    shift 2
    _rk_tmp="$(work_new "$WORK/tmp-run.XXXXXX")" || return 1
    extract_sums_helpers "$_rk_host" >"$WORK/helpers.sh"
    extract_func "$_rk_host" fetch_kit >"$WORK/fetchkit.sh"
    if [ "$_rk_host" = "$UPDATE" ]; then
        printf 'KIT_FILES="%s"\n' "$KIT_LIST" >"$WORK/kitfiles.env"
    else
        : >"$WORK/kitfiles.env"
    fi
    _rk_script='
        _tmp_track() { :; }
        . "$1"
        . "$2"
        eval "$(cat "$3")"
        fetch_kit
        _rc=$?
        printf "BASE %s\n" "${_FETCH_TREE:-}"
        [ "$_rc" -eq 0 ] && printf "DIR %s\n" "${_FK_DIR:-}"
        exit "$_rc"
    '
    RUN_OUT="$(TMPDIR="$_rk_tmp" env KIT_BASE_URL="file://$_rk_root" \
        KIT_BASE_ROOT="$_rk_root" PATH="$SRVBIN:$PATH" "$@" \
        sh -c "$_rk_script" fetchrun "$WORK/kitfiles.env" \
        "$WORK/helpers.sh" "$WORK/fetchkit.sh" 2>&1)"
    RUN_RC=$?
    RUN_TMP="$_rk_tmp"
    RUN_BASE="$(printf '%s\n' "$RUN_OUT" | sed -n 's/^BASE //p')"
    RUN_DIR="$(printf '%s\n' "$RUN_OUT" | sed -n 's/^DIR //p')"
    if [ -n "$RUN_BASE" ] && [ -d "$RUN_BASE" ]; then
        work_register "$RUN_BASE"
    fi
    return 0
}

# assert_no_leftovers <tmpdir> <label>: after the run's staging base is
# removed, the per-arm TMPDIR must be EMPTY — no leaked fetch temp ever
# survives a failure path (issue #478 cleanup criterion).
assert_no_leftovers() {
    rm -rf "${RUN_BASE:-}"
    if [ -z "$(ls -A "${1:?}" 2>/dev/null)" ]; then
        pass "$2 (no temp leftovers)"
    else
        fail "$2 (temp leftovers: $(ls -A "$1"))"
    fi
}

# --- 3. fetch_kit end-to-end -----------------------------------------------------

# 3a. success (update.sh): everything fetched, verified, staged.
FIX="$WORK/fix-good"
build_fixture "$FIX"
run_fetch_kit "$UPDATE" "$FIX"
if [ "$RUN_RC" -eq 0 ] && [ -n "$RUN_DIR" ]; then
    pass "update.sh fetch_kit: verified fetch succeeds (rc 0)"
else
    fail "update.sh fetch_kit: verified fetch succeeds (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi
if [ -n "$RUN_DIR" ] &&
    [ "$(find "$RUN_DIR" -type f | wc -l | tr -d ' ')" = "$((KIT_COUNT - 1))" ]; then
    pass "staged tree carries every listed file (VERSION at the root)"
else
    _fi_got=0
    [ -n "$RUN_DIR" ] && _fi_got="$(find "$RUN_DIR" -type f | wc -l | tr -d ' ')"
    fail "staged tree file count (want $((KIT_COUNT - 1)) under files/, got $_fi_got)"
fi
if [ -n "$RUN_BASE" ] && [ -f "$RUN_BASE/SHA256SUMS" ]; then
    pass "the verified manifest itself landed at the staging root"
else
    fail "the verified manifest itself landed at the staging root"
fi

# 3b. tampered remote body: the hash gate fires BEFORE the file stages.
FIX="$WORK/fix-tamper"
build_fixture "$FIX"
printf 'captive-portal-html\n' >>"$FIX/files/etc/umask.sh"
run_fetch_kit "$UPDATE" "$FIX"
if [ "$RUN_RC" -ne 0 ] &&
    printf '%s' "$RUN_OUT" | grep -q 'SHA256 mismatch' &&
    printf '%s' "$RUN_OUT" | grep -qF 'etc/umask.sh' &&
    printf '%s' "$RUN_OUT" | grep -q 'expected:' &&
    printf '%s' "$RUN_OUT" | grep -q 'actual:'; then
    pass "tampered body aborts with file + expected/actual digests"
else
    fail "tampered body aborts with file + expected/actual digests (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -4))"
fi
if [ -n "$RUN_DIR" ]; then
    fail "tampered body never enters the staged tree (DIR marker set)"
elif [ -n "$RUN_BASE" ] && [ -e "$RUN_BASE/files/etc/umask.sh" ]; then
    fail "tampered body never enters the staged tree (file present)"
else
    pass "tampered body never enters the staged tree"
fi
assert_no_leftovers "$RUN_TMP" "tamper abort cleans its temps"

# 3c. missing manifest (pre-manifest ref / broken origin): fail closed
# with the named causes + the break-glass hint.
FIX="$WORK/fix-nomanifest"
build_fixture "$FIX"
rm -f "${FIX:?}/SHA256SUMS"
run_fetch_kit "$UPDATE" "$FIX"
if [ "$RUN_RC" -ne 0 ] &&
    printf '%s' "$RUN_OUT" | grep -q 'could not fetch the integrity manifest' &&
    printf '%s' "$RUN_OUT" | grep -q 'KIT_SHA_VERIFY=0'; then
    pass "missing manifest fails closed with the break-glass hint"
else
    fail "missing manifest fails closed with the break-glass hint (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi
assert_no_leftovers "$RUN_TMP" "missing-manifest abort cleans its temps"

# 3d. malformed manifest (an HTML body at the manifest URL): the shape
# gate refuses garbage before any verification runs.
FIX="$WORK/fix-htmlmanifest"
build_fixture "$FIX"
printf '<html>login page</html>\n' >"$FIX/SHA256SUMS"
run_fetch_kit "$UPDATE" "$FIX"
if [ "$RUN_RC" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q 'malformed'; then
    pass "malformed manifest (HTML body) fails closed at the shape gate"
else
    fail "malformed manifest (HTML body) fails closed at the shape gate (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi
assert_no_leftovers "$RUN_TMP" "malformed-manifest abort cleans its temps"

# 3e. missing entry: a manifest without the file the fetcher is on must
# abort (manifest/list drift), never skip that file's verification.
FIX="$WORK/fix-noentry"
build_fixture "$FIX"
grep -v '  files/etc/umask.sh$' "$FIX/SHA256SUMS" >"$FIX/SHA256SUMS.new" &&
    mv "$FIX/SHA256SUMS.new" "$FIX/SHA256SUMS"
run_fetch_kit "$UPDATE" "$FIX"
if [ "$RUN_RC" -ne 0 ] &&
    printf '%s' "$RUN_OUT" | grep -q 'no unique SHA256SUMS entry' &&
    printf '%s' "$RUN_OUT" | grep -qF 'etc/umask.sh'; then
    pass "a file without a manifest entry aborts the fetch"
else
    fail "a file without a manifest entry aborts the fetch (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi
assert_no_leftovers "$RUN_TMP" "missing-entry abort cleans its temps"

# 3f. duplicate entry: ambiguity is drift, not a pick-one situation.
FIX="$WORK/fix-dupentry"
build_fixture "$FIX"
_fi_dup="$(grep '  VERSION$' "$FIX/SHA256SUMS")"
{
    printf '%s\n%s\n' "$_fi_dup" "$_fi_dup"
    grep -v '  VERSION$' "$FIX/SHA256SUMS"
} >"$FIX/SHA256SUMS.new"
mv "$FIX/SHA256SUMS.new" "$FIX/SHA256SUMS"
run_fetch_kit "$UPDATE" "$FIX"
if [ "$RUN_RC" -ne 0 ] &&
    printf '%s' "$RUN_OUT" | grep -q 'no unique SHA256SUMS entry' &&
    printf '%s' "$RUN_OUT" | grep -qF 'VERSION'; then
    pass "a duplicate manifest entry aborts the fetch (ambiguity is drift)"
else
    fail "a duplicate manifest entry aborts the fetch (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi

# 3g. KIT_SHA_VERIFY=0: the documented break-glass disables the gate
# (the tampered body from 3b passes -- the seam is real, not cosmetic).
FIX="$WORK/fix-verifyoff"
build_fixture "$FIX"
printf 'captive-portal-html\n' >>"$FIX/files/etc/umask.sh"
run_fetch_kit "$UPDATE" "$FIX" KIT_SHA_VERIFY=0
if [ "$RUN_RC" -eq 0 ] && [ -n "$RUN_DIR" ]; then
    pass "KIT_SHA_VERIFY=0 disables the gate (break-glass seam)"
else
    fail "KIT_SHA_VERIFY=0 disables the gate (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi

# 3h. missing sha256sum: loud abort, never a silently unverified fetch
# (absence from the stub PATH — shell-agnostic, see NOSHBIN above).
FIX="$WORK/fix-nosh"
build_fixture "$FIX"
_fi_tmpnosh="$(work_new "$WORK/tmp-nosh.XXXXXX")"
extract_sums_helpers "$UPDATE" >"$WORK/helpers.sh"
extract_func "$UPDATE" fetch_kit >"$WORK/fetchkit.sh"
printf 'KIT_FILES="%s"\n' "$KIT_LIST" >"$WORK/kitfiles.env"
_fi_script='
    _tmp_track() { :; }
    . "$1"
    . "$2"
    eval "$(cat "$3")"
    fetch_kit
'
_fi_out="$(TMPDIR="$_fi_tmpnosh" env KIT_BASE_URL="file://$FIX" \
    KIT_BASE_ROOT="$FIX" PATH="$NOSHBIN" \
    sh -c "$_fi_script" fetchrun \
    "$WORK/kitfiles.env" "$WORK/helpers.sh" "$WORK/fetchkit.sh" 2>&1)"
_fi_rc=$?
if [ "$_fi_rc" -ne 0 ] &&
    printf '%s' "$_fi_out" | grep -q 'sha256sum is required'; then
    pass "missing sha256sum aborts the fetch loudly"
else
    fail "missing sha256sum aborts the fetch loudly (rc=$_fi_rc out=$(printf '%s' "$_fi_out" | tail -2))"
fi
_fi_noshbase="$(find "$_fi_tmpnosh" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | head -1)"
[ -n "$_fi_noshbase" ] && work_register "$_fi_noshbase"

# 3i. install.sh twin parity: the same success + tamper gates on the
# other host (inline list, no KIT_FILES global).
FIX="$WORK/fix-install-good"
build_fixture "$FIX"
run_fetch_kit "$INSTALL" "$FIX"
if [ "$RUN_RC" -eq 0 ] && [ -n "$RUN_DIR" ]; then
    pass "install.sh fetch_kit (twin): verified fetch succeeds"
else
    fail "install.sh fetch_kit (twin): verified fetch succeeds (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi
FIX="$WORK/fix-install-tamper"
build_fixture "$FIX"
printf 'captive-portal-html\n' >>"$FIX/files/etc/umask.sh"
run_fetch_kit "$INSTALL" "$FIX"
if [ "$RUN_RC" -ne 0 ] && printf '%s' "$RUN_OUT" | grep -q 'SHA256 mismatch'; then
    pass "install.sh fetch_kit (twin): tampered body aborts"
else
    fail "install.sh fetch_kit (twin): tampered body aborts (rc=$RUN_RC out=$(printf '%s' "$RUN_OUT" | tail -3))"
fi
assert_no_leftovers "$RUN_TMP" "twin tamper abort cleans its temps"

# --- 4. ensure_local_file heal path ----------------------------------------------

FIX="$WORK/fix-elf"
build_fixture "$FIX"
# A partially staged tree (one file missing) + the fetched manifest --
# the resolve context update.sh establishes before the heal loop.
ELF_ROOT="$WORK/elf-tree"
mkdir -p "$ELF_ROOT/files"
cp "$FIX/SHA256SUMS" "$ELF_ROOT/SHA256SUMS"
for _fi_n in $KIT_LIST; do
    [ "$_fi_n" = "VERSION" ] && continue
    [ "$_fi_n" = "opencode-permissions-kit-lib/sh/ui.sh" ] && continue
    mkdir -p "$ELF_ROOT/files/$(dirname "$_fi_n")"
    printf 'fixture-body %s\n' "$_fi_n" >"$ELF_ROOT/files/$_fi_n"
done
extract_sums_helpers "$UPDATE" >"$WORK/helpers.sh"
extract_func "$UPDATE" ensure_local_file >"$WORK/elf.fn"
_fi_tmpelf="$(work_new "$WORK/tmp-elf.XXXXXX")"
_fi_elfscript='
    _tmp_track() { :; }
    . "$2"
    eval "$(cat "$3")"
    _fk_sums="$4"
    ensure_local_file "opencode-permissions-kit-lib/sh/ui.sh"
'
_fi_out="$(TMPDIR="$_fi_tmpelf" env KIT_BASE_URL="file://$FIX" \
    KIT_BASE_ROOT="$FIX" FILES_ROOT="$ELF_ROOT/files" PATH="$SRVBIN:$PATH" \
    sh -c "$_fi_elfscript" elfrun _ "$WORK/helpers.sh" "$WORK/elf.fn" \
    "$ELF_ROOT/SHA256SUMS" 2>&1)"
_fi_rc=$?
if [ "$_fi_rc" -eq 0 ] &&
    [ "$(cat "$ELF_ROOT/files/opencode-permissions-kit-lib/sh/ui.sh" 2>/dev/null)" = \
        "fixture-body opencode-permissions-kit-lib/sh/ui.sh" ]; then
    pass "ensure_local_file: verified re-fetch lands the healed file"
else
    fail "ensure_local_file: verified re-fetch lands the healed file (rc=$_fi_rc out=$(printf '%s' "$_fi_out" | tail -3))"
fi
# 4b. tampered remote body: no heal into the deploy tree.
rm -f "${ELF_ROOT:?}/files/opencode-permissions-kit-lib/sh/ui.sh"
printf 'evil-heal\n' >>"$FIX/files/opencode-permissions-kit-lib/sh/ui.sh"
_fi_out="$(TMPDIR="$_fi_tmpelf" env KIT_BASE_URL="file://$FIX" \
    KIT_BASE_ROOT="$FIX" FILES_ROOT="$ELF_ROOT/files" PATH="$SRVBIN:$PATH" \
    sh -c "$_fi_elfscript" elfrun _ "$WORK/helpers.sh" "$WORK/elf.fn" \
    "$ELF_ROOT/SHA256SUMS" 2>&1)"
_fi_rc=$?
if [ "$_fi_rc" -ne 0 ] &&
    printf '%s' "$_fi_out" | grep -q 'SHA256 mismatch' &&
    [ ! -e "$ELF_ROOT/files/opencode-permissions-kit-lib/sh/ui.sh" ]; then
    pass "ensure_local_file: tampered re-fetch aborts, nothing staged"
else
    fail "ensure_local_file: tampered re-fetch aborts, nothing staged (rc=$_fi_rc out=$(printf '%s' "$_fi_out" | tail -3))"
fi
if [ -z "$(ls -A "$_fi_tmpelf" 2>/dev/null)" ]; then
    pass "ensure_local_file failure path leaves no temp"
else
    fail "ensure_local_file failure path leaves no temp ($(ls -A "$_fi_tmpelf"))"
fi

# --- 5. update.sh tree verification (the old-fetcher window) ----------------------

extract_sums_helpers "$UPDATE" >"$WORK/helpers.sh"
extract_func "$UPDATE" _fk_sums_resolve >"$WORK/resolve.fn"
extract_func "$UPDATE" verify_fetched_tree >"$WORK/verify.fn"
_fi_script='
    _tmp_track() { :; }
    . "$2"
    eval "$(cat "$3")"
    eval "$(cat "$4")"
    _fk_sums_resolve || { printf "RESOLVE-FAIL\n"; exit 1; }
    verify_fetched_tree || { printf "VERIFY-FAIL\n"; exit 1; }
    printf "SUMS %s\n" "${_fk_sums:-none}"
'
_fi_tmptree="$(work_new "$WORK/tmp-tree.XXXXXX")"

# 5a. resolve fetches the manifest an old (pre-manifest) fetcher never
# pulled, then the tree verify passes -- the upgrade path into the
# SHA-verified era on an already-installed machine.
FIX="$WORK/fix-tree"
build_fixture "$FIX"
TREE_A="$WORK/tree-a"
cp -R "$FIX" "$TREE_A"
rm -f "${TREE_A:?}/SHA256SUMS"
_fi_out="$(TMPDIR="$_fi_tmptree" env _FETCH_TREE="$TREE_A" \
    FILES_ROOT="$TREE_A/files" KIT_BASE_URL="file://$FIX" KIT_BASE_ROOT="$FIX" \
    PATH="$SRVBIN:$PATH" sh -c "$_fi_script" treerun _ \
    "$WORK/helpers.sh" "$WORK/resolve.fn" "$WORK/verify.fn" 2>&1)"
_fi_rc=$?
if [ "$_fi_rc" -eq 0 ] &&
    printf '%s' "$_fi_out" | grep -qF "SUMS $TREE_A/SHA256SUMS"; then
    pass "old-fetcher window: resolve pulls the missing manifest, tree verifies"
else
    fail "old-fetcher window: resolve pulls the missing manifest, tree verifies (rc=$_fi_rc out=$(printf '%s' "$_fi_out" | tail -3))"
fi
if [ -f "$TREE_A/SHA256SUMS" ]; then
    pass "the fetched manifest persisted in the staging tree"
else
    fail "the fetched manifest persisted in the staging tree"
fi

# 5b. tampered staged tree: the whole-tree gate refuses before deploy.
# A1 pin (#493 a): the refusal must NOT offer the KIT_SHA_VERIFY=0
# bypass -- verification ran and failed; the hint would invite
# deploying exactly the refused content.
printf 'staged-corruption\n' >>"$TREE_A/files/etc/umask.sh"
_fi_out="$(TMPDIR="$_fi_tmptree" env _FETCH_TREE="$TREE_A" \
    FILES_ROOT="$TREE_A/files" KIT_BASE_URL="file://$FIX" KIT_BASE_ROOT="$FIX" \
    PATH="$SRVBIN:$PATH" sh -c "$_fi_script" treerun _ \
    "$WORK/helpers.sh" "$WORK/resolve.fn" "$WORK/verify.fn" 2>&1)"
_fi_rc=$?
if [ "$_fi_rc" -ne 0 ] &&
    printf '%s' "$_fi_out" | grep -q 'failed the SHA256SUMS verification' &&
    printf '%s' "$_fi_out" | grep -qF 'etc/umask.sh' &&
    ! printf '%s' "$_fi_out" | grep -q 'KIT_SHA_VERIFY=0'; then
    pass "tampered staged tree fails verify_fetched_tree before deploy (no bypass hint)"
else
    fail "tampered staged tree fails verify_fetched_tree before deploy, without the bypass hint (rc=$_fi_rc out=$(printf '%s' "$_fi_out" | tail -3))"
fi

# 5c. checkout carve-out: no _FETCH_TREE and no manifest anywhere --
# resolve must not reach for the network (PATH carries neither curl nor
# mktemp; a wrong fetch dies loudly at _kit_sums_fetch's first external,
# whichever it is -- #493 a C5) and verify is an rc 0 no-op: a dirty
# checkout must not read as a corrupted fetch.
_fi_tmp5c="$(work_new "$WORK/tmp-5c.XXXXXX")"
mkdir -p "$_fi_tmp5c/files"
_fi_out="$(TMPDIR="$_fi_tmp5c" env _FETCH_TREE="" FILES_ROOT="$_fi_tmp5c/files" \
    KIT_BASE_URL="file://$FIX" PATH="$NOCURLBIN" \
    sh -c "$_fi_script" treerun _ \
    "$WORK/helpers.sh" "$WORK/resolve.fn" "$WORK/verify.fn" 2>&1)"
_fi_rc=$?
if [ "$_fi_rc" -eq 0 ] && printf '%s' "$_fi_out" | grep -q '^SUMS none$'; then
    pass "checkout run without a manifest: resolve + verify are no-ops"
else
    fail "checkout run without a manifest: resolve + verify are no-ops (rc=$_fi_rc out=$(printf '%s' "$_fi_out" | tail -2))"
fi

# --- 6. wiring pins (source-level) ------------------------------------------------

# B6 pin (#493 a): the marker range must capture ONLY the helper block.
# An over-capture (the second block header once shared the start
# pattern's prefix) would drag update.sh's flow code into every inner
# eval; _fk_sums_resolve lives after the end marker by construction.
extract_sums_helpers "$UPDATE" >"$WORK/helpers-pin.sh"
if grep -q '_fk_sums_resolve' "$WORK/helpers-pin.sh" ||
    grep -q 'exec bash' "$WORK/helpers-pin.sh"; then
    fail "helper extraction stops at the end marker (over-capture, B6)"
else
    pass "helper extraction stops at the end marker (B6)"
fi
if grep -q '^_kit_sums_check() {' "$WORK/helpers-pin.sh"; then
    pass "helper extraction carries the four helpers (B6 sane leg)"
else
    fail "helper extraction carries the four helpers (B6 sane leg)"
fi

check_live "update.sh gates the fetch loop on KIT_SHA_VERIFY" "$UPDATE" -qF 'KIT_SHA_VERIFY:-1'
check_live "install.sh gates the fetch loop on KIT_SHA_VERIFY (twin)" "$INSTALL" -qF 'KIT_SHA_VERIFY:-1'
check_live "update.sh verifies each staged temp before the mv" "$UPDATE" -qF '_kit_sums_check "$_fk_tmp" "$f" "$_fk_sums"'
check_live "install.sh verifies each staged temp before the mv (twin)" "$INSTALL" -qF '_kit_sums_check "$_fk_tmp" "$f" "$_fk_sums"'
# Presence-of-CALL only, anchored to the indented statement (the bare
# name also matches the function DEFINITION, col 0, and its comment
# mentions; the functional 5b arm extracts the function directly). The
# description deliberately claims presence, not order — #493 a C4: a
# pin must not claim what it does not check.
check_live "update.sh calls the whole-tree verify (call site anchored)" "$UPDATE" -Eq '^[[:space:]]+verify_fetched_tree$'
check_live "update.sh heals through the verified path (ensure_local_file gate)" "$UPDATE" -qF 're-fetched $f failed the SHA256SUMS check'
check_live "update.sh names the break-glass in the abort messages" "$UPDATE" -qF 'KIT_SHA_VERIFY=0 disables verification'
check_live "install.sh names the break-glass too (twin)" "$INSTALL" -qF 'KIT_SHA_VERIFY=0 disables verification'

suite_done "fetch integrity tests"
