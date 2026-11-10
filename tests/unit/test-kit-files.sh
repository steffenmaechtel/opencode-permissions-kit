#!/bin/sh
# Unit tests for the kit file lists (single source of truth guard):
#   1. install.sh's fetch_kit() list and update.sh's KIT_FILES must be
#      IDENTICAL — the duplication is deliberate (both scripts must be
#      able to bootstrap a full fetch standalone, streamed via curl),
#      so drift has to be caught here.
#   2. every listed file must exist in the checkout (a removed file would
#      404 every streamed install; VERSION lives at the repo root).
#   3. every `cp "$SCRIPT_DIR/<path>"` deploy target in install.sh and
#      update.sh must be in the list — otherwise the streamed install
#      aborts mid-deploy (set -e) because the temp fetch never pulled it.
#
# Run: sh tests/unit/test-kit-files.sh
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$REPO/files/install.sh"
INSTALL_CORE="$REPO/files/opencode-permissions-kit-lib/sh/install-core.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$REPO/tests/unit/lib/harness.sh"

# Normalize a multi-line shell list (backslash continuations, leading
# prefixes) into one space-separated line.
normalize() {
    sed -e 's/\\$//' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ //'
}

# extract_update_list <update.sh> — the KIT_FILES="..." assignment
extract_update_list() {
    sed -n '/^KIT_FILES="/,/"$/p' "$1" |
        sed -e 's/^KIT_FILES="//' -e 's/"$//' | normalize
}

# extract_install_list <install.sh> — the `for f in ... ; do` inside fetch_kit()
extract_install_list() {
    extract_func "$1" fetch_kit |
        sed -n '/for f in /,/; do/p' |
        sed -e 's/^[[:space:]]*for f in //' -e 's/; do$//' | normalize
}

# --- 1. extract both lists from the repo files -----------------------------------

update_list=$(extract_update_list "$UPDATE")
install_list=$(extract_install_list "$INSTALL")

if [ -z "$update_list" ]; then
    fail "KIT_FILES extracted from update.sh (got an empty list)"
else
    pass "KIT_FILES extracted from update.sh ($(echo "$update_list" | wc -w) files)"
fi
if [ -z "$install_list" ]; then
    fail "fetch list extracted from install.sh (got an empty list)"
else
    pass "fetch list extracted from install.sh ($(echo "$install_list" | wc -w) files)"
fi

if [ "$install_list" = "$update_list" ]; then
    pass "install.sh fetch list and update.sh KIT_FILES are identical"
else
    fail "install.sh fetch list and update.sh KIT_FILES DRIFTED:"
    echo "        install.sh: $install_list"
    echo "        update.sh:  $update_list"
fi

# --- 2. every listed file exists -------------------------------------------------

missing=""
for f in $update_list; do
    if [ "$f" = "VERSION" ]; then
        [ -f "$REPO/VERSION" ] || missing="$missing $f"
    else
        [ -f "$REPO/files/$f" ] || missing="$missing $f"
    fi
done
if [ -z "$missing" ]; then
    pass "every listed kit file exists in the checkout"
else
    fail "listed files missing from the checkout:$missing"
fi

# --- 3. deploy targets are covered by the fetch list -----------------------------

# Path normalization for the cross-check: install.sh cp sources are rooted
# at files/ directly; update.sh lives in opencode-permissions-kit-lib/
# management/, so its "$SCRIPT_DIR/<rel>" sources resolve against that
# directory. Normalize both to files/-rooted paths.
norm_files_path() {
    printf '%s\n' "$1" | awk -F/ '{
        n = 0
        for (i = 1; i <= NF; i++) {
            if ($i == "" || $i == ".") continue
            if ($i == "..") { if (n > 0) n--; continue }
            stack[++n] = $i
        }
        out = ""
        for (i = 1; i <= n; i++) out = out (i > 1 ? "/" : "") stack[i]
        print out
    }'
}

deploy_missing=""
# install-core.sh joined the scan with #346 wave 3: the deploy cp sites
# moved into the phase lib, but $SCRIPT_DIR still resolves to files/ at
# run time (the lib is sourced, SCRIPT_DIR is install.sh's) — same
# base as install.sh itself.
for script in "$INSTALL" "$INSTALL_CORE" "$UPDATE"; do
    name="${script##*/}"
    base=""
    [ "$name" = "update.sh" ] && base=""
    # collect `cp "$SCRIPT_DIR/<target>"` / `cp "$FILES_ROOT/<target>"` sources
    targets=$(grep -oE 'cp "\$(SCRIPT_DIR|FILES_ROOT)/[^"]+"' "$script" | cut -d'"' -f3)
    for t in $targets; do
        ft="$(norm_files_path "$base/$t")"
        case " $update_list " in
            *" $ft "*) ;;
            *) deploy_missing="$deploy_missing $name:$ft" ;;
        esac
    done
done
if [ -z "$deploy_missing" ]; then
    pass "every deploy cp target in install.sh/update.sh is in the fetch list"
else
    fail "deploy targets missing from the fetch list (streamed install would abort):$deploy_missing"
fi

# --- 4. canary: the guards themselves catch drift -------------------------------
# A guard that cannot fail is decoration. Mutate COPIES of the scripts
# (never the repo files) and verify the checks above would trip, reusing
# the SAME extraction helpers — not a re-implementation.

WORK="$(work_new)" || {
    echo "kit file list tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

# Shared mutation for 4a/4c: update.sh without opencode-deny-all.jsonc in
# KIT_FILES (a file install.sh both fetches and cp-deploys).
sed 's/opencode-deny-all\.jsonc //' "$UPDATE" >"$WORK/update-mutated.sh"
mutated_update_list=$(extract_update_list "$WORK/update-mutated.sh")

# 4a. list drift: the equality check (section 1) must detect the mismatch.
if [ "$mutated_update_list" != "$install_list" ]; then
    pass "canary: KIT_FILES mutation is detected (equality check works)"
else
    fail "canary: KIT_FILES mutation is detected (equality check is blind!)"
fi

# 4b. missing file: same mutation names one file fewer — against a list
#     with an ADDED nonexistent name the exists-check must trip. Build it
#     from the real install list plus a ghost entry.
ghost_list="$install_list ghost-file.sh"
_missing=""
for f in $ghost_list; do
    if [ "$f" = "VERSION" ]; then
        [ -f "$REPO/VERSION" ] || _missing="$_missing $f"
    else
        [ -f "$REPO/files/$f" ] || _missing="$_missing $f"
    fi
done
if [ "$_missing" = " ghost-file.sh" ]; then
    pass "canary: missing-file detection works"
else
    fail "canary: missing-file detection works (got: '$_missing')"
fi

# 4c. deploy coverage: section 3's logic must flag the cp'd file that the
#     mutated KIT_FILES no longer lists. The cp sites live in
#     install-core.sh since #346 wave 3.
_deploy_missing=""
targets=$(grep -oE 'cp "\$SCRIPT_DIR/[^"]+"' "$INSTALL_CORE" | sed -e 's|cp "\$SCRIPT_DIR/||' -e 's|"||')
for t in $targets; do
    case " $mutated_update_list " in
        *" $t "*) ;;
        *) _deploy_missing="$_deploy_missing install.sh:$t" ;;
    esac
done
case "$_deploy_missing" in
    *"opencode-deny-all.jsonc"*)
        pass "canary: deploy-coverage detection works (flagged:$_deploy_missing)"
        ;;
    *)
        fail "canary: deploy-coverage detection works (got: '$_deploy_missing')"
        ;;
esac

# --- 5. the lib_deploy manifest IS the deploy set (0.0.41d wave) -----------------
# install.sh and update.sh both deploy through sh/deploy-lib.sh; its
# manifest must equal the fetch lists' opencode-permissions-kit-lib/
# subset in BOTH directions:
#   manifest-only  -> deployed but never fetched: streamed install aborts
#   fetch-only     -> fetched but never deployed: goes stale in $LIBDIR
#                     on every update (the 0.0.38 C19 class)

DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
manifest_list=$(sed -n "/<<'DL_MANIFEST'/,/^DL_MANIFEST\$/p" "$DEPLOYLIB" |
    sed -e '1d' -e '$d' | grep -v '^#' | awk 'NF { print $1 }' | sort -u)
lib_fetch_list=$(printf '%s\n' $update_list | grep '^opencode-permissions-kit-lib/' | sort -u)

if [ -z "$manifest_list" ]; then
    fail "lib_deploy manifest extracted from deploy-lib.sh (got an empty list)"
else
    pass "lib_deploy manifest extracted from deploy-lib.sh ($(printf '%s\n' "$manifest_list" | wc -l) entries)"
fi

printf '%s\n' "$manifest_list" >"$WORK/manifest.txt"
printf '%s\n' "$lib_fetch_list" >"$WORK/fetchlib.txt"
if diff -q "$WORK/manifest.txt" "$WORK/fetchlib.txt" >/dev/null; then
    pass "lib_deploy manifest == fetch-list lib subset (deploy set has ONE source)"
else
    fail "lib_deploy manifest and fetch list DRIFTED:"
    diff "$WORK/fetchlib.txt" "$WORK/manifest.txt" | sed 's/^/        /'
fi

# 5b. canary: drop one manifest line from a COPY — the equality check
# must see the drift.
sed '/sh\/staged-write\.sh 644/d' "$DEPLOYLIB" >"$WORK/deploy-lib-mutated.sh"
mutated_manifest=$(sed -n "/<<'DL_MANIFEST'/,/^DL_MANIFEST\$/p" "$WORK/deploy-lib-mutated.sh" |
    sed -e '1d' -e '$d' | grep -v '^#' | awk 'NF { print $1 }' | sort -u)
if [ "$mutated_manifest" != "$lib_fetch_list" ]; then
    pass "canary: manifest mutation is detected (equality check works)"
else
    fail "canary: manifest mutation is detected (equality check is blind!)"
fi

# --- 5. fetch_kit pre-creates every subdirectory in the list ----------------------
# curl -o cannot write into a missing directory: the streamed fetch aborts
# with curl error 23 at the first nested file (the tui/ regression — every
# `opk update` from the library failed mid-fetch).
fetch_body() {
    extract_func "$1" fetch_kit
}

# unique subdirectory prefixes referenced by the (verified-identical) lists
subdirs=$(for f in $update_list; do case "$f" in */*) echo "${f%/*}" ;; esac done | sort -u)

mkdir_missing=""
for script in "$INSTALL" "$UPDATE"; do
    name="${script##*/}"
    body="$(fetch_body "$script")"
    for d in $subdirs; do
        # a literal "$dir/$d" or any deeper "$dir/$d/..." mkdir covers $d
        # (mkdir -p creates the parents)
        echo "$body" | grep -qF "\"\$dir/$d\"" ||
            echo "$body" | grep -qF "\"\$dir/$d/" ||
            mkdir_missing="$mkdir_missing $name:$d"
    done
done
if [ -z "$mkdir_missing" ]; then
    pass "fetch_kit pre-creates every listed subdirectory ($(echo "$subdirs" | tr '\n' ' '))"
else
    fail "fetch_kit does not pre-create listed subdirectories (curl error 23):$mkdir_missing"
fi

# 5a. canary: without the tui/ mkdir the guard above must trip. Mutate a
#     COPY of update.sh exactly like the original regression.
sed 's| "\$dir/opencode-permissions-kit-lib/tui"||' "$UPDATE" >"$WORK/update-notui.sh"
_canary=""
_body="$(fetch_body "$WORK/update-notui.sh")"
for d in $subdirs; do
    echo "$_body" | grep -qF "\"\$dir/$d\"" ||
        echo "$_body" | grep -qF "\"\$dir/$d/" ||
        _canary="$_canary $d"
done
case "$_canary" in
    *opencode-permissions-kit-lib/tui*)
        pass "canary: missing tui/ mkdir is detected"
        ;;
    *)
        fail "canary: missing tui/ mkdir is detected (guard is blind!)"
        ;;
esac

# 5b. functional: run update.sh's fetch_kit with a fake curl that writes the
#     -o target directly (NO directory creation, like real curl — a missing
#     parent dir must fail, reproducing curl error 23).
mkdir -p "$WORK/fakebin"
cat >"$WORK/fakebin/curl" <<'FAKE'
#!/bin/sh
_out=""
while [ $# -gt 0 ]; do
    [ "$1" = "-o" ] && _out="$2" && break
    shift
done
printf 'stub\n' > "$_out"
FAKE
chmod +x "$WORK/fakebin/curl"

sed -n '/^KIT_FILES="/,/"$/p' "$UPDATE" >"$WORK/kitfiles.env"
extract_func "$UPDATE" fetch_kit >"$WORK/fetchkit.fn"
# fetch_kit reports the tree via the _FK_DIR global (no stdout — a
# command-substitution call would void the trap registrations); the
# inner shell echoes it deliberately for this test. The dump contract is
# two stdout lines: ALWAYS the staging base first (_FETCH_TREE, set by
# the extracted function before any fetch step -- on a FAILED fetch
# nothing else reaches stdout, and without the base line the partial
# tree had no handle to register, #454 a C2), then the fetched tree
# (_FK_DIR) only on success. No inner trap: the sandbox floor reads any
# line-start trap statement as the suite's own and reds the
# work-registry mix (check 4b).
_fk_out="$(PATH="$WORK/fakebin:$PATH" sh -c '
    . "$1"
    eval "$(cat "$2")"
    fetch_kit
    _fk_rc=$?
    printf "%s\n" "${_FETCH_TREE:-}"
    [ "$_fk_rc" -eq 0 ] && printf "%s\n" "$_FK_DIR"
' _ "$WORK/kitfiles.env" "$WORK/fetchkit.fn" 2>/dev/null || true)"
# The staging BASE is the receiver (#443): inside the inner shell
# fetch_kit's `mktemp -d` base has no cleanup of its own (the inner shell
# loads only KIT_FILES plus the extracted function -- update.sh's
# _tmp_track registry and its trap are not there), and the parent never
# collected it either: one tmp.<X> directory leaked per run. On success
# the base is dirname of _FK_DIR (VERSION lands at $base/VERSION); on a
# failed fetch the dump line names the partial tree. An empty base means
# nothing was created -- nothing to register; a REGISTRATION failure must
# not ride silently or the leak returns on a green run (#454 a A1: the
# swallowed work_register rc used to leak the tree while the suite exited
# green).
_fk_base="$(printf '%s\n' "$_fk_out" | sed -n 1p)"
_fk_dir="$(printf '%s\n' "$_fk_out" | sed -n 2p)"
if [ -z "$_fk_base" ] && [ -n "$_fk_dir" ]; then
    # fallback for a truncated dump; guarded so dirname("") can never
    # degenerate to "." and distort the missing-list (#454 a A2)
    _fk_base="$(dirname "$_fk_dir")"
fi
if [ -n "$_fk_base" ]; then
    work_register "$_fk_base" || {
        echo "kit file list tests: staging-tree registration failed (TMPDIR=${TMPDIR:-unset})" >&2
        exit 1
    }
fi
_fk_missing=""
for f in $update_list; do
    if [ "$f" = "VERSION" ]; then p="$_fk_base/VERSION"; else p="$_fk_dir/$f"; fi
    [ -f "$p" ] || _fk_missing="$_fk_missing $f"
done
if [ -z "$_fk_missing" ] && [ -n "$_fk_dir" ]; then
    pass "functional: fake-curl fetch_kit writes every listed file incl. nested dirs"
else
    fail "functional: fake-curl fetch_kit writes every listed file (missing:$_fk_missing)"
fi

# #454 a C2/A2 canary: a FAILING curl stub must leave (a) the fetch red
# with every listed file honestly missing incl. VERSION (the base from
# the dump is the real staging tree, never a cwd-relative "."), and
# (b) the partial staging base captured on the dump's first line for the
# registration above -- the #443 leak's failure branch. Reuses the
# suite's fakebin by swapping the stub for a failing one; the canary's
# own staging tree registers like the main arm's.
cat >"$WORK/fakebin/curl" <<'FAKE'
#!/bin/sh
exit 1
FAKE
_fk2_out="$(PATH="$WORK/fakebin:$PATH" sh -c '
    . "$1"
    eval "$(cat "$2")"
    fetch_kit
    _fk_rc=$?
    printf "%s\n" "${_FETCH_TREE:-}"
    [ "$_fk_rc" -eq 0 ] && printf "%s\n" "$_FK_DIR"
' _ "$WORK/kitfiles.env" "$WORK/fetchkit.fn" 2>/dev/null || true)"
_fk2_base="$(printf '%s\n' "$_fk2_out" | sed -n 1p)"
_fk2_dir="$(printf '%s\n' "$_fk2_out" | sed -n 2p)"
if [ -n "$_fk2_base" ]; then
    work_register "$_fk2_base" || {
        echo "kit file list tests: staging-tree registration failed (TMPDIR=${TMPDIR:-unset})" >&2
        exit 1
    }
fi
_fk2_missing=""
for f in $update_list; do
    if [ "$f" = "VERSION" ]; then p="$_fk2_base/VERSION"; else p="$_fk2_dir/$f"; fi
    [ -f "$p" ] || _fk2_missing="$_fk2_missing $f"
done
_fk2_ok=1
case " $_fk2_missing " in
    "  ") _fk2_ok=0 ;; # nothing missing is not the red this canary wants
esac
for f in $update_list; do
    case " $_fk2_missing " in
        *" $f "*) ;;
        *) _fk2_ok=0 ;;
    esac
done
if [ -z "$_fk2_dir" ] && [ -n "$_fk2_base" ] && [ "$_fk2_ok" -eq 1 ]; then
    pass "canary: failing-curl fetch aborts red with every file missing, staging base captured (C2/A2)"
else
    fail "canary: failing-curl fetch arms (dir='$_fk2_dir' base='$_fk2_base' missing='$_fk2_missing') (C2/A2)"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All kit file list tests passed.${NC}"
exit 0
