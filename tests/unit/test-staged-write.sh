#!/bin/sh
# Unit tests for the 0.0.39g symlink-hardening wave (review S1/S2 + the
# C3/C4/C5 contract gaps):
#   - staged_write (sh/staged-write.sh): stage in a root-owned dir, apply
#     owner/mode there, mv onto the destination — a planted symlink at the
#     destination (dangling or not) is REPLACED, never followed; the
#     victim keeps its content, no staging leftovers, failures leave the
#     destination untouched.
#   - ddev-handover.sh gates (S2): a planted settings-dir symlink never
#     reaches chown -R/chmod -R (PATH-stubbed ops, raceless [ -d ] &&
#     [ ! -L ] gate), and the dev-owned flag skips a symlinked config.yaml
#     instead of writing through it as root.
#   - projects_remove pipeline (C3): grep -v exits 1 on an empty result —
#     removing the LAST project must not abort the rewrite under pipefail.
#   - ensure_local_file (C4): refuses failed and empty fetches, never
#     deploys a partial file (stubbed curl, no root).
#   - install.conf stamp rewrite (C5) + staged-write wiring (fetch/deploy
#     lists) — structural.
# Runs as the CURRENT user (SW_SUDO="" / SW_STAGE_DIR override) — no root.
# Run: sh tests/unit/test-staged-write.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
STAGEDWRITE="$REPO/files/opencode-permissions-kit-lib/sh/staged-write.sh"
HANDOVER="$REPO/files/opencode-permissions-kit-lib/sh/ddev-handover.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
CONFIG="$REPO/files/opencode-permissions-kit-lib/management/config.sh"
INSTALL="$REPO/files/install.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

assert_eq() {
    _d="$1" _e="$2" _a="$3"
    if [ "$_e" = "$_a" ]; then pass "$_d"; else fail "$_d (expected [$_e] got [$_a])"; fi
}

check() {
    _d="$1"; shift
    if "$@"; then pass "$_d"; else fail "$_d"; fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT INT TERM

echo ""
echo "staged-write + handover symlink gates (0.0.39g S1/S2)"
echo "====================================================="
echo ""

# --- 1. staged_write semantics --------------------------------------------------

# shellcheck disable=SC1090
. "$STAGEDWRITE"
SW_SUDO=""
SW_STAGE_DIR="$WORK/stage"
mkdir -p "$WORK/stage" "$WORK/src" "$WORK/dst"
OWNER="$(id -un):$(id -gn)"
printf 'KIT-CONTENT-A\n' > "$WORK/src/a"
printf 'KIT-CONTENT-B\n' > "$WORK/src/b"

# 1a. fresh destination
if staged_write 664 "$OWNER" "$WORK/src/a" "$WORK/dst/conf.json"; then
    pass "fresh write: succeeds"
else
    fail "fresh write: succeeds"
fi
assert_eq "fresh write: content" "KIT-CONTENT-A" "$(cat "$WORK/dst/conf.json" 2>/dev/null)"
assert_eq "fresh write: mode 664 applied" "664" "$(stat -c %a "$WORK/dst/conf.json" 2>/dev/null)"
assert_eq "fresh write: no staging leftovers" "" "$(ls -A "$WORK/stage" 2>/dev/null)"

# 1b. destination is a symlink to an existing VICTIM file — the overwrite
# variant of S1: cp/chown would follow the link and clobber the victim.
printf 'VICTIM-SECRET\n' > "$WORK/victim"
ln -s "$WORK/victim" "$WORK/dst/linked.json"
if staged_write 664 "$OWNER" "$WORK/src/b" "$WORK/dst/linked.json"; then
    pass "linked dst: write succeeds"
else
    fail "linked dst: write succeeds"
fi
check "linked dst: link itself replaced by a regular file" test ! -L "$WORK/dst/linked.json"
assert_eq "linked dst: new content at the destination" "KIT-CONTENT-B" "$(cat "$WORK/dst/linked.json" 2>/dev/null)"
assert_eq "linked dst: VICTIM untouched (never written through)" "VICTIM-SECRET" "$(cat "$WORK/victim" 2>/dev/null)"

# 1c. destination is a DANGLING symlink — pre-coreutils-9.2 cp created the
# attacker-chosen path through it; the gate [ ! -f ] never sees it.
ln -s "$WORK/never-created" "$WORK/dst/dangling.json"
if staged_write 664 "$OWNER" "$WORK/src/a" "$WORK/dst/dangling.json"; then
    pass "dangling dst: write succeeds"
else
    fail "dangling dst: write succeeds"
fi
check "dangling dst: link target path NOT created" test ! -e "$WORK/never-created"
check "dangling dst: link itself replaced" test ! -L "$WORK/dst/dangling.json"
assert_eq "dangling dst: no staging leftovers" "" "$(ls -A "$WORK/stage" 2>/dev/null)"

# 1d. failure leaves the destination and the staging dir clean
printf 'PRE-EXISTING\n' > "$WORK/dst/keep.json"
if staged_write 664 "$OWNER" "$WORK/src/missing" "$WORK/dst/keep.json" 2>/dev/null; then
    fail "failed src: staged_write reports failure"
else
    pass "failed src: staged_write reports failure"
fi
assert_eq "failed src: destination untouched" "PRE-EXISTING" "$(cat "$WORK/dst/keep.json" 2>/dev/null)"
assert_eq "failed src: no staging leftovers" "" "$(ls -A "$WORK/stage" 2>/dev/null)"

# 1e. destination is a DIRECTORY (review 0.0.39h F3): `mv -f` would move
# the staged file INSIDE it and return 0 — staged_write must refuse, the
# directory must stay empty. [ -d ] follows a link-to-directory, so that
# variant is covered by the same gate; a link to a FILE is still replaced
# (1b).
mkdir -p "$WORK/dst/asdir"
if staged_write 664 "$OWNER" "$WORK/src/a" "$WORK/dst/asdir" 2>/dev/null; then
    fail "dir dst: staged_write refuses"
else
    pass "dir dst: staged_write refuses"
fi
assert_eq "dir dst: nothing landed inside the directory" "" "$(ls -A "$WORK/dst/asdir" 2>/dev/null)"
assert_eq "dir dst: no staging leftovers" "" "$(ls -A "$WORK/stage" 2>/dev/null)"
ln -s "$WORK/dst/asdir" "$WORK/dst/dirlink"
if staged_write 664 "$OWNER" "$WORK/src/a" "$WORK/dst/dirlink" 2>/dev/null; then
    fail "dir-link dst: staged_write refuses"
else
    pass "dir-link dst: staged_write refuses"
fi
assert_eq "dir-link dst: nothing landed inside the link target" "" "$(ls -A "$WORK/dst/asdir" 2>/dev/null)"

# --- 2. ddev-handover gates (S2) -------------------------------------------------
# PATH-stubbed chown/chmod record their operands; the fixture carries a
# REAL settings dir (web/typo3conf, config/system) and a PLANTED symlink
# named after one (typo3conf -> a tree outside the project). The symlink
# operand must never reach the recursive ops.

STUB="$WORK/stub"
OPS="$WORK/ops.log"
mkdir -p "$STUB"
printf '#!/bin/sh\necho "chown $*" >> "$OPS_LOG"\n' > "$STUB/chown"
printf '#!/bin/sh\necho "chmod $*" >> "$OPS_LOG"\n' > "$STUB/chmod"
chmod +x "$STUB/chown" "$STUB/chmod"

mkdir -p "$WORK/proj/.ddev" "$WORK/proj/web/typo3conf" "$WORK/proj/config/system" "$WORK/victim-tree/typo3conf"
printf 'type: typo3\ndocroot: web\n' > "$WORK/proj/.ddev/config.yaml"
ln -s "$WORK/victim-tree/typo3conf" "$WORK/proj/typo3conf"

OPS_LOG="$OPS"
export OPS_LOG
OUT="$(PATH="$STUB:$PATH" sh -c '. "$1" && ddev_handover_project "$2" ocuser ocgroup' _ "$HANDOVER" "$WORK/proj" 2>&1)"

check "handover: real settings dir reaches chown -R" \
    grep -qxF "chown -R ocuser:ocgroup $WORK/proj/web/typo3conf" "$OPS"
check "handover: real settings dir reaches chmod -R" \
    grep -qxF "chmod -R g+w $WORK/proj/web/typo3conf" "$OPS"
check "handover: config/system reaches chown -R" \
    grep -qxF "chown -R ocuser:ocgroup $WORK/proj/config/system" "$OPS"
if grep -qxF "chown -R ocuser:ocgroup $WORK/proj/typo3conf" "$OPS" \
   || grep -qxF "chmod -R g+w $WORK/proj/typo3conf" "$OPS"; then
    fail "handover: planted settings-dir symlink never reaches chown -R/chmod -R"
else
    pass "handover: planted settings-dir symlink never reaches chown -R/chmod -R"
fi
if echo "$OUT" | grep -qF "ddev settings handover: $WORK/proj/typo3conf"; then
    fail "handover: planted symlink produces no handover echo"
else
    pass "handover: planted symlink produces no handover echo"
fi

# 2b. dev-owned flag: a symlinked config.yaml is skipped, never written
# through as root (the cat-rewrite follows the link).
mkdir -p "$WORK/flagproj/.ddev" "$WORK/flagsrc"
printf 'type: typo3\n' > "$WORK/flagsrc/config.yaml"
ln -s "$WORK/flagsrc/config.yaml" "$WORK/flagproj/.ddev/config.yaml"
FLAGOUT="$(PATH="$STUB:$PATH" sh -c '. "$1" && ddev_devowned_flag "$2"' _ "$HANDOVER" "$WORK/flagproj" 2>&1)"
if grep -q 'disable_settings_management' "$WORK/flagsrc/config.yaml"; then
    fail "dev-owned flag: linked config.yaml not written through"
else
    pass "dev-owned flag: linked config.yaml not written through"
fi
check "dev-owned flag: skip is announced" \
    echo "$FLAGOUT" | grep -qF "is a symlink"
# ... and a REAL config.yaml gets the flag (the function keeps working).
mkdir -p "$WORK/flagproj2/.ddev"
printf 'type: typo3\n' > "$WORK/flagproj2/.ddev/config.yaml"
PATH="$STUB:$PATH" sh -c '. "$1" && ddev_devowned_flag "$2"' _ "$HANDOVER" "$WORK/flagproj2" >/dev/null 2>&1
check "dev-owned flag: real config.yaml gets the flag" \
    grep -q 'disable_settings_management: true' "$WORK/flagproj2/.ddev/config.yaml"

# --- 3. projects_remove pipeline (C3) --------------------------------------------
# GNU grep -v exits 1 when the result is EMPTY: removing the last project
# must not abort the rewrite. The guard shape is config.sh's exact
# pipeline (minus sudo), run under bash pipefail — dash has no pipefail,
# which is precisely the nothing-documents-it reliance C3 flags.

PCONF="$WORK/projects.conf"
printf '/var/www/only-project\n' > "$PCONF"
if bash -c 'set -o pipefail; { grep -vxF "$1" "$2" || true; } | cat > "$3"' _ "/var/www/only-project" "$PCONF" "$WORK/projects.out"; then
    pass "C3 pipeline: last-project removal exits 0 under pipefail"
else
    fail "C3 pipeline: last-project removal exits 0 under pipefail"
fi
assert_eq "C3 pipeline: empty result, no stale copy" "" "$(cat "$WORK/projects.out" 2>/dev/null)"
# control: WITHOUT the guard the same pipeline fails under pipefail (the
# test must be able to detect the class it guards against)
if bash -c 'set -o pipefail; grep -vxF "$1" "$2" | cat > /dev/null' _ "/var/www/only-project" "$PCONF" 2>/dev/null; then
    fail "C3 control: unguarded pipeline fails under pipefail"
else
    pass "C3 control: unguarded pipeline fails under pipefail"
fi
check "C3: config.sh carries the guarded pipeline" \
    grep -qF '{ sudo grep -vxF "$p" "$PROJECTS_CONF" || true; }' "$CONFIG"

# --- 4. ensure_local_file (C4) ----------------------------------------------------
# Extracted from update.sh (the CLI runs its main on source), with a
# PATH-stubbed curl: a failed or EMPTY fetch must abort with no partial
# file at FILES_ROOT — the temp-then-mv contract.

BIN="$WORK/bin"
mkdir -p "$BIN"
printf '#!/bin/sh\nout=""\nprev=""\nfor a in "$@"; do\n  [ "$prev" = "-o" ] && out="$a"\n  prev="$a"\ndone\ncase "$CURL_STUB" in\n  fail) exit 1 ;;\n  empty) : > "$out" ;;\n  *) printf "KIT FILE CONTENT\\n" > "$out" ;;\nesac\n' > "$BIN/curl"
chmod +x "$BIN/curl"

eval "$(sed -n '/^ensure_local_file() {/,/^}/p' "$UPDATE")"
FILES_ROOT="$WORK/fr"
KIT_BASE_URL="https://example.invalid"
_tmp_track() { :; }   # scratch-registry stub (update.sh's real one is a no-op here)

mkdir -p "$FILES_ROOT"
printf 'PRESENT\n' > "$WORK/fr/present.txt"
if (PATH="$BIN:$PATH" ensure_local_file "present.txt"); then
    pass "ensure_local_file: present file is a no-op"
else
    fail "ensure_local_file: present file is a no-op"
fi
assert_eq "ensure_local_file: present file untouched" "PRESENT" "$(cat "$WORK/fr/present.txt")"

if (PATH="$BIN:$PATH" CURL_STUB=ok ensure_local_file "new.txt"); then
    pass "ensure_local_file: sound fetch is deployed"
else
    fail "ensure_local_file: sound fetch is deployed"
fi
assert_eq "ensure_local_file: fetched content in place" "KIT FILE CONTENT" "$(cat "$WORK/fr/new.txt" 2>/dev/null)"

if (PATH="$BIN:$PATH" CURL_STUB=fail ensure_local_file "fail.txt" 2>/dev/null); then
    fail "ensure_local_file: failed fetch aborts"
else
    pass "ensure_local_file: failed fetch aborts"
fi
check "ensure_local_file: no partial file after failed fetch" test ! -e "$WORK/fr/fail.txt"

if (PATH="$BIN:$PATH" CURL_STUB=empty ensure_local_file "empty.txt" 2>/dev/null); then
    fail "ensure_local_file: empty-body fetch aborts (refuse-empty guard)"
else
    pass "ensure_local_file: empty-body fetch aborts (refuse-empty guard)"
fi
check "ensure_local_file: no empty file deployed" test ! -e "$WORK/fr/empty.txt"

# --- 5. wiring (C5 + the shipped lists) --------------------------------------------

check "C5: install.conf stamp written via temp + mv" \
    sh -c 'grep -qF "_INSTALL_CONF_TMP=" "$1" && grep -qF "mv -f \"\$_INSTALL_CONF_TMP\"" "$1"' _ "$INSTALL"
check "wiring: install.sh fetch list carries staged-write.sh" \
    grep -qF 'opencode-permissions-kit-lib/sh/staged-write.sh \' "$INSTALL"
check "wiring: install.sh deploys staged-write.sh" \
    grep -qF 'sudo cp "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/staged-write.sh" "$LIBDIR/sh/staged-write.sh"' "$INSTALL"
check "wiring: update.sh KIT_FILES carries staged-write.sh" \
    grep -qF 'opencode-permissions-kit-lib/sh/staged-write.sh \' "$UPDATE"
check "wiring: update.sh deploys staged-write.sh" \
    grep -qF 'sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/sh/staged-write.sh" "$LIBDIR/sh/staged-write.sh"' "$UPDATE"
check "wiring: config.sh sources staged-write.sh" \
    grep -qF 'for cand in "$SCRIPT_DIR/../sh/staged-write.sh" "$LIBDIR/sh/staged-write.sh"' "$CONFIG"
check "wiring: update.sh tui.json write goes through staged_write" \
    grep -qF 'staged_write 664 "$OPENCODE_USER:$NEW_OPENCODE_GROUP" "$LIBDIR/tui/tui.json"' "$UPDATE"
check "wiring: install.sh config writes go through staged_write" \
    sh -c 'grep -c "staged_write 664" "$1" | grep -q "^[3-9]$" ' _ "$INSTALL"

# --- 6. agent_home_sane (0.0.39h F1/F2) ---------------------------------------------
# The walker asserts every component of a path below the agent home
# (OPK_AGENT_HOME overrides the base for this unprivileged run).
AH="$WORK/ah"; mkdir -p "$AH/oc/.config/opencode" "$AH/other"
ln -s "$AH/other" "$AH/oc/linked"
check "walker: clean chain passes silently" \
    sh -c '. "$1" && OPK_AGENT_HOME="$2/oc" agent_home_sane oc "$2/oc/.config/opencode"' _ "$STAGEDWRITE" "$AH"
if OPK_AGENT_HOME="$AH/oc" sh -c '. "$1" && agent_home_sane oc "$2/oc/linked/x"' _ "$STAGEDWRITE" "$AH" 2>/dev/null; then
    fail "walker: linked intermediate component trips"
else
    pass "walker: linked intermediate component trips"
fi
if OPK_AGENT_HOME="$AH/oc" sh -c '. "$1" && agent_home_sane oc "$2/oc/linked"' _ "$STAGEDWRITE" "$AH" 2>/dev/null; then
    fail "walker: linked leaf trips"
else
    pass "walker: linked leaf trips"
fi
check "walker: path outside the agent home passes" \
    sh -c '. "$1" && OPK_AGENT_HOME="$2/oc" agent_home_sane oc "$2/other/x"' _ "$STAGEDWRITE" "$AH"
check "walker: the home itself passes" \
    sh -c '. "$1" && OPK_AGENT_HOME="$2/oc" agent_home_sane oc "$2/oc"' _ "$STAGEDWRITE" "$AH"

# --- 7. wiring: the 0.0.39h gates ----------------------------------------------
UNINSTALL="$REPO/files/opencode-permissions-kit-lib/management/uninstall.sh"
check "gates: install.sh ~/.ddev operand gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"/home/\$OPENCODE_USER/.ddev\"" "$1"' _ "$INSTALL"
check "gates: install.sh Step 8 operand gates (.config/.config/opencode/.agents)" \
    sh -c 'grep -c "agent_home_sane \"\$OPENCODE_USER\" /home/opencode/" "$1" | grep -q "^[3-9]$"' _ "$INSTALL"
check "gates: install.sh agents-migration operand gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$_opk_dst\"" "$1"' _ "$INSTALL"
check "gates: install.sh mkcert chain gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$caroot\"" "$1"' _ "$INSTALL"
check "gates: install.sh agent-config + tui + plugin chain gates" \
    sh -c 'grep -q "agent_home_sane \"\$OPENCODE_USER\" /home/opencode/.config/opencode" "$1" && grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$OC_TUI_DIR\"" "$1" && grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$_oc_user_dir\"" "$1"' _ "$INSTALL"
check "gates: update.sh sources staged-write.sh early + walker fallback" \
    sh -c 'grep -q "command -v agent_home_sane >/dev/null 2>&1 \|\| agent_home_sane() { return 0; }" "$1"' _ "$UPDATE"
check "gates: update.sh sync_tui_registration + tui.json chain gates" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$_str_user_dir\"" "$1" && grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$OC_TUI_DIR\"" "$1"' _ "$UPDATE"
check "gates: config.sh git_config_apply chain gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$(dirname \"\$target\")\"" "$1"' _ "$CONFIG"
check "gates: uninstall.sh plugin-removal chain gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$_un_dir\"" "$1"' _ "$UNINSTALL"
check "F3: staged-write.sh refuses a directory destination" \
    grep -qF 'destination '"'"'$_sw_dst'"'"' is a directory' "$STAGEDWRITE"

# --- summary -----------------------------------------------------------------------

echo ""
echo "======================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All staged-write / handover gate tests passed."
echo ""
