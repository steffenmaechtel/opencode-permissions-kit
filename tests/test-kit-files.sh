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
# Run: sh tests/test-kit-files.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/update.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

# Normalize a multi-line shell list (backslash continuations, leading
# prefixes) into one space-separated line.
normalize() {
    sed -e 's/\\$//' -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//' | tr '\n' ' ' | sed -e 's/  */ /g' -e 's/^ //'
}

# extract_update_list <update.sh> — the KIT_FILES="..." assignment
extract_update_list() {
    sed -n '/^KIT_FILES="/,/"$/p' "$1" \
        | sed -e 's/^KIT_FILES="//' -e 's/"$//' | normalize
}

# extract_install_list <install.sh> — the `for f in ... ; do` inside fetch_kit()
extract_install_list() {
    sed -n '/^fetch_kit() {/,/^}/p' "$1" \
        | sed -n '/for f in /,/; do/p' \
        | sed -e 's/^[[:space:]]*for f in //' -e 's/; do$//' | normalize
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

deploy_missing=""
for script in "$INSTALL" "$UPDATE"; do
    name="${script##*/}"
    # collect `cp "$SCRIPT_DIR/<target>"` sources
    targets=$(grep -oE 'cp "\$SCRIPT_DIR/[^"]+"' "$script" | sed -e 's|cp "\$SCRIPT_DIR/||' -e 's|"||')
    for t in $targets; do
        case " $update_list " in
            *" $t "*) ;;
            *) deploy_missing="$deploy_missing $name:$t" ;;
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Shared mutation for 4a/4c: update.sh without opencode-deny-all.jsonc in
# KIT_FILES (a file install.sh both fetches and cp-deploys).
sed 's/opencode-deny-all\.jsonc //' "$UPDATE" > "$WORK/update-mutated.sh"
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
        [ -f "$REPO/VERSION" ] || _missing="$missing $f"
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
#     mutated KIT_FILES no longer lists.
_deploy_missing=""
targets=$(grep -oE 'cp "\$SCRIPT_DIR/[^"]+"' "$INSTALL" | sed -e 's|cp "\$SCRIPT_DIR/||' -e 's|"||')
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

# --- 5. fetch_kit pre-creates every subdirectory in the list ----------------------
# curl -o cannot write into a missing directory: the streamed fetch aborts
# with curl error 23 at the first nested file (the tui/ regression — every
# `opencode-permissions-kit update` from the library failed mid-fetch).
fetch_body() {
    sed -n '/^fetch_kit() {/,/^}/p' "$1"
}

# unique subdirectory prefixes referenced by the (verified-identical) lists
subdirs=$(for f in $update_list; do case "$f" in */*) echo "${f%/*}" ;; esac; done | sort -u)

mkdir_missing=""
for script in "$INSTALL" "$UPDATE"; do
    name="${script##*/}"
    body="$(fetch_body "$script")"
    for d in $subdirs; do
        # a literal "$dir/$d" or any deeper "$dir/$d/..." mkdir covers $d
        # (mkdir -p creates the parents)
        echo "$body" | grep -qF "\"\$dir/$d\"" \
            || echo "$body" | grep -qF "\"\$dir/$d/" \
            || mkdir_missing="$mkdir_missing $name:$d"
    done
done
if [ -z "$mkdir_missing" ]; then
    pass "fetch_kit pre-creates every listed subdirectory ($(echo "$subdirs" | tr '\n' ' '))"
else
    fail "fetch_kit does not pre-create listed subdirectories (curl error 23):$mkdir_missing"
fi

# 5a. canary: without the tui/ mkdir the guard above must trip. Mutate a
#     COPY of update.sh exactly like the original regression.
sed 's| "\$dir/opencode-permissions-kit-lib/tui"||' "$UPDATE" > "$WORK/update-notui.sh"
_canary=""
_body="$(fetch_body "$WORK/update-notui.sh")"
for d in $subdirs; do
    echo "$_body" | grep -qF "\"\$dir/$d\"" \
        || echo "$_body" | grep -qF "\"\$dir/$d/" \
        || _canary="$_canary $d"
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
cat > "$WORK/fakebin/curl" <<'FAKE'
#!/bin/sh
_out=""
while [ $# -gt 0 ]; do
    [ "$1" = "-o" ] && _out="$2" && break
    shift
done
printf 'stub\n' > "$_out"
FAKE
chmod +x "$WORK/fakebin/curl"

sed -n '/^KIT_FILES="/,/"$/p' "$UPDATE" > "$WORK/kitfiles.env"
sed -n '/^fetch_kit() {/,/^}/p' "$UPDATE" > "$WORK/fetchkit.fn"
_fk_dir="$(PATH="$WORK/fakebin:$PATH" sh -c '
    . "$1"
    eval "$(cat "$2")"
    fetch_kit
' _ "$WORK/kitfiles.env" "$WORK/fetchkit.fn" 2>/dev/null || true)"
_fk_base="$(dirname "$_fk_dir")"
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

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All kit file list tests passed.${NC}"
exit 0
