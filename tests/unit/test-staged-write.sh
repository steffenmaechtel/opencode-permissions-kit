#!/bin/sh
# Unit tests for the 0.0.39g symlink-hardening wave (review 0.0.39g S1/S2 +
# the C3/C4/C5 contract gaps) and the 0.0.39h–k gate follow-ups:
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
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
TUIPLUGIN="$REPO/files/opencode-permissions-kit-lib/sh/tui-plugin.sh"

failures=0
passed=0

# Deterministic fixture modes (issue #112): the handover's top-inode fast
# path skips chown -R/chmod -R on already-conforming trees — under a
# developer's umask 002 freshly mkdir'ed dirs WOULD conform immediately
# if the calls here passed real ids (they do not: literal ocuser/ocgroup
# never match real stat output — 0.0.40a F7). The guard turns
# load-bearing the moment a call does.
umask 022

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
echo "staged-write + handover symlink gates (0.0.39g S1/S2 + follow-ups)"
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
# 0.0.39h F13: the exec-time recheck skip is ANNOUNCED (stderr note), not
# silent like a plain failure.
check "dev-owned flag: exec-time recheck skip is announced" \
    grep -q 'changed to a symlink mid-write' "$HANDOVER"

# --- 2c/2d. ddev_handover_root scan loop (0.0.39h F9 — S2's core had no
# behavioral coverage): the .ddev tree reaches chown -R AND chmod -R, and
# the exec-time [ -L ] recheck BETWEEN them closes the swapped-symlink
# window. The racing chown stub swaps the real .ddev for a symlink WHEN
# chown runs — the race, deterministically.
mkdir -p "$WORK/hr/proj/.ddev" "$WORK/hr/proj/web/typo3conf" "$WORK/hr-victim" "$WORK/stubhr"
printf 'type: typo3\ndocroot: web\n' > "$WORK/hr/proj/.ddev/config.yaml"
printf '#!/bin/sh\necho "chown $*" >> "$OPS_HR_LOG"\n' > "$WORK/stubhr/chown"
printf '#!/bin/sh\necho "chmod $*" >> "$OPS_HR_LOG"\n' > "$WORK/stubhr/chmod"
chmod +x "$WORK/stubhr/chown" "$WORK/stubhr/chmod"
OPS_HR_LOG="$WORK/ops-hr.log"; export OPS_HR_LOG
OUT_HR="$(PATH="$WORK/stubhr:$PATH" OPK_INSTALL_CONF=/nonexistent sh -c '. "$1" && ddev_handover_root "$2" ocuser ocgroup devuser' _ "$HANDOVER" "$WORK/hr")"
check "handover_root: .ddev reaches chown -R" \
    grep -qxF "chown -R ocuser:ocgroup $WORK/hr/proj/.ddev" "$OPS_HR_LOG"
check "handover_root: .ddev reaches chmod -R" \
    grep -qxF "chmod -R g+w $WORK/hr/proj/.ddev" "$OPS_HR_LOG"
check "handover_root: scan-loop settings handover runs (web/typo3conf)" \
    grep -qxF "chown -R ocuser:ocgroup $WORK/hr/proj/web/typo3conf" "$OPS_HR_LOG"
check "handover_root: handover echoed" \
    echo "$OUT_HR" | grep -qF ".ddev handover: $WORK/hr/proj/.ddev -> ocuser"
# racing variant: the stub swaps .ddev for a symlink at chown time
mkdir -p "$WORK/hr2/proj/.ddev" "$WORK/hr2/proj/web/typo3conf" "$WORK/hr2-victim" "$WORK/stubhr2"
printf 'type: typo3\ndocroot: web\n' > "$WORK/hr2/proj/.ddev/config.yaml"
printf '#!/bin/sh\ncase " $* " in *" $RACE_D "*) rm -rf "$RACE_D"; ln -s "$RACE_V" "$RACE_D";; esac\necho "chown $*" >> "$OPS_HR_LOG"\n' > "$WORK/stubhr2/chown"
printf '#!/bin/sh\necho "chmod $*" >> "$OPS_HR_LOG"\n' > "$WORK/stubhr2/chmod"
chmod +x "$WORK/stubhr2/chown" "$WORK/stubhr2/chmod"
RACE_D="$WORK/hr2/proj/.ddev"; RACE_V="$WORK/hr2-victim"; export RACE_D RACE_V
OUT_HR2="$(PATH="$WORK/stubhr2:$PATH" OPK_INSTALL_CONF=/nonexistent sh -c '. "$1" && ddev_handover_root "$2" ocuser ocgroup devuser' _ "$HANDOVER" "$WORK/hr2")"
check "handover_root recheck: swapped .ddev still hit chown -R (the stub ran first)" \
    grep -qxF "chown -R ocuser:ocgroup $WORK/hr2/proj/.ddev" "$OPS_HR_LOG"
if grep -qxF "chmod -R g+w $WORK/hr2/proj/.ddev" "$OPS_HR_LOG"; then
    fail "handover_root recheck: swapped-symlink .ddev never reaches chmod -R"
else
    pass "handover_root recheck: swapped-symlink .ddev never reaches chmod -R"
fi
if echo "$OUT_HR2" | grep -qF ".ddev handover: $WORK/hr2/proj/.ddev"; then
    fail "handover_root recheck: swapped .ddev produces no handover echo"
else
    pass "handover_root recheck: swapped .ddev produces no handover echo"
fi

# --- 2e. ddev_handover_project_back (0.0.39h F9): planted settings-dir
# links never reach the recursive ops; the root-inode handback fires only
# for a kit-owned root (stubbed stat).
mkdir -p "$WORK/bk/proj/.ddev" "$WORK/bk/proj/web/typo3conf" "$WORK/bk/proj/config/system" "$WORK/bk-victim/typo3conf" "$WORK/stubbk"
printf 'type: typo3\ndocroot: web\n' > "$WORK/bk/proj/.ddev/config.yaml"
ln -s "$WORK/bk-victim/typo3conf" "$WORK/bk/proj/typo3conf"
printf '#!/bin/sh\necho "chown $*" >> "$OPS_BK_LOG"\n' > "$WORK/stubbk/chown"
printf '#!/bin/sh\necho "chmod $*" >> "$OPS_BK_LOG"\n' > "$WORK/stubbk/chmod"
printf '#!/bin/sh\nprintf "%%s\\n" "$STAT_OWNER"\n' > "$WORK/stubbk/stat"
chmod +x "$WORK/stubbk/chown" "$WORK/stubbk/chmod" "$WORK/stubbk/stat"
OPS_BK_LOG="$WORK/ops-bk.log"; export OPS_BK_LOG
STAT_OWNER=ocuser; export STAT_OWNER
PATH="$WORK/stubbk:$PATH" OPK_INSTALL_CONF=/nonexistent sh -c '. "$1" && ddev_handover_project_back "$2" ocuser ocgroup devuser' _ "$HANDOVER" "$WORK/bk/proj" >/dev/null 2>&1
check "project_back: real settings dirs reach chown -R (dev handback)" \
    sh -c 'grep -qxF "chown -R devuser:ocgroup '"$WORK"'/bk/proj/web/typo3conf" "$1" && grep -qxF "chown -R devuser:ocgroup '"$WORK"'/bk/proj/config/system" "$1"' _ "$OPS_BK_LOG"
if grep -q " $WORK/bk/proj/typo3conf" "$OPS_BK_LOG"; then
    fail "project_back: planted settings-dir symlink never reaches chown -R/chmod -R"
else
    pass "project_back: planted settings-dir symlink never reaches chown -R/chmod -R"
fi
check "project_back: kit-owned root (stat=ocuser) is handed back" \
    sh -c 'grep -qxF "chown devuser:ocgroup '"$WORK"'/bk/proj" "$1" && grep -qxF "chmod 2775 '"$WORK"'/bk/proj" "$1"' _ "$OPS_BK_LOG"
: > "$OPS_BK_LOG"
STAT_OWNER=devuser
PATH="$WORK/stubbk:$PATH" OPK_INSTALL_CONF=/nonexistent sh -c '. "$1" && ddev_handover_project_back "$2" ocuser ocgroup devuser' _ "$HANDOVER" "$WORK/bk/proj" >/dev/null 2>&1
if grep -qxF "chown devuser:ocgroup $WORK/bk/proj" "$OPS_BK_LOG"; then
    fail "project_back: developer-owned root (stat=devuser) is NOT touched"
else
    pass "project_back: developer-owned root (stat=devuser) is NOT touched"
fi

# --- 3. projects_remove rewrite (C3 / 0.0.39h F4) ---------------------------------
# GNU grep -v exits 1 when the result is EMPTY (removing the last project
# — benign) and 2 on a real read error. config.sh's shape captures the rc
# OUTSIDE the write pipeline (dash has no pipefail — an `|| rc=$?` on a
# pipeline would only ever see tee's 0) and dies on rc >= 2 BEFORE the
# .tmp is mv'd over projects.conf: the old `{ grep -v || true; } | tee`
# guard masked rc 2 into an empty rewrite that clobbered the file.

PCONF="$WORK/projects.conf"
printf '/var/www/only-project\n' > "$PCONF"
if sh -c 'rc=0; out=$(grep -vxF "$1" "$2" 2>/dev/null) || rc=$?; [ "$rc" -le 1 ]' _ "/var/www/only-project" "$PCONF"; then
    pass "C3 (0.0.39g) / F4 (0.0.39h): last-project removal (rc 1) stays benign"
else
    fail "C3 (0.0.39g) / F4 (0.0.39h): last-project removal (rc 1) stays benign"
fi
assert_eq "C3 (0.0.39g) / F4 (0.0.39h): empty result, no stale copy" "" "$(grep -vxF "/var/www/only-project" "$PCONF" 2>/dev/null)"
# control: a real read error (grep on a directory) yields rc 2 — the
# narrowed guard must refuse (the old || true masked this class)
if sh -c 'rc=0; out=$(grep -vxF "$1" "$2" 2>/dev/null) || rc=$?; [ "$rc" -le 1 ]' _ "x" "$WORK" 2>/dev/null; then
    fail "C3 (0.0.39g) / F4 (0.0.39h) control: grep rc 2 (read error) refuses the rewrite"
else
    pass "C3 (0.0.39g) / F4 (0.0.39h) control: grep rc 2 (read error) refuses the rewrite"
fi
check "C3 (0.0.39g) / F4 (0.0.39h): config.sh narrows the guard (rc <= 1 ok, rc 2 dies) + registers the .tmp" \
    sh -c 'grep -qF "_pr_out=\$(sudo grep -vxF \"\$p\" \"\$PROJECTS_CONF\" 2>/dev/null) || _pr_rc=\$?" "$1" && grep -qF "[ \"\$_pr_rc\" -le 1 ] || die" "$1" && grep -qF "_tmp_track \"\$PROJECTS_CONF.tmp\"" "$1"' _ "$CONFIG"
check "0.0.39h F4/F6: update.sh install.conf rewrite is narrowed + atomic (temp + mv)" \
    sh -c 'grep -qF "_ic_keep=\$(grep -v -e '"'"'^VERSION='"'"' -e '"'"'^OPENCODE_GROUP='"'"' -e '"'"'^KIT_CHANNEL='"'"'" "$1" && grep -qF "-e '"'"'^DDEV_VERSION='"'"' \"\$INSTALL_CONF\" 2>/dev/null) || _ic_rc=\$?" "$1" && grep -qF "_tmp_track \"\$_INSTALL_CONF_TMP\"" "$1" && grep -qF "mv -f \"\$_INSTALL_CONF_TMP\" \"\$CONFDIR/install.conf\"" "$1"' _ "$UPDATE"
check "0.0.39h F4/F6: config.sh conf rewrites are narrowed + atomic (class sweep)" \
    sh -c 'grep -qF "_ucb_keep=\$(grep -v" "$1" && grep -qF "mv -f \"\$_ucb_tmp\" \"\$INSTALL_CONF\"" "$1" && grep -qF "mv -f \"\$_udd_tmp\" \"\$INSTALL_CONF\"" "$1"' _ "$CONFIG"

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
check "wiring: install.sh deploys staged-write.sh (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/staged-write.sh 644" "$2" \
        && grep -qF "lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"" "$1"' _ "$INSTALL" "$DEPLOYLIB"
check "wiring: update.sh KIT_FILES carries staged-write.sh" \
    grep -qF 'opencode-permissions-kit-lib/sh/staged-write.sh \' "$UPDATE"
check "wiring: update.sh deploys staged-write.sh (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/sh/staged-write.sh 644" "$2" \
        && grep -qF "lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"" "$1"' _ "$UPDATE" "$DEPLOYLIB"
check "wiring: config.sh sources staged-write.sh" \
    grep -qF 'for cand in "$SCRIPT_DIR/../sh/staged-write.sh" "$LIBDIR/sh/staged-write.sh"' "$CONFIG"
check "wiring: update.sh tui.json write goes through staged_write" \
    grep -qF 'staged_write 664 "$OPENCODE_USER:$NEW_OPENCODE_GROUP" "$LIBDIR/tui/tui.json"' "$UPDATE"
check "wiring: install.sh config writes go through staged_write (0.0.39h F8: offline-rendered, ONE write per branch)" \
    sh -c 'grep -c "_oc_install_agent_config" "$1" | grep -q "^[4-9]$" && ! grep -q "sed -i .*opencode\.jsonc" "$1"' _ "$INSTALL"
check "wiring: config.sh git_config_apply renders offline, ONE staged_write (0.0.39h F8)" \
    sh -c 'grep -qF "_gca_tmp" "$1" && grep -c "staged_write 664" "$1" | grep -q "^2$" && ! grep -qF "sed -i '"'"'s|" "$1"' _ "$CONFIG"
OPK="$REPO/files/opencode-permissions-kit-lib/bin/opk"
check "0.0.39h F10: opk handover refuses symlinked operands + rechecks between the ops" \
    sh -c 'grep -qF "[ -L \"\$_ho_a\" ]" "$1" && grep -qF "[ ! -L \"\$_ho_a\" ]" "$1"' _ "$OPK"
check "0.0.39i F4: opk handover --dry-run previews the symlink refuse" \
    grep -qF "would refuse" "$OPK"
check "0.0.39h F12: no 1;33 color definition remains repo-wide (files/)" \
    sh -c '! grep -rq "1;33" "$1"' _ "$REPO/files"

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
# 0.0.39i F1: the combined top-level mkdir is gone — every Step 8 mkdir
# runs INSIDE its operand gate (three per-operand mkdirs), so no root
# mkdir passes through a linked parent.
check "gates: install.sh Step 8 mkdir sits inside the operand gates (0.0.39i F1)" \
    sh -c '! grep -qF "mkdir -p /home/opencode/.config/opencode /home/opencode/.agents" "$1" && grep -c "sudo mkdir -p /home/opencode/" "$1" | grep -q "^[3-9]$"' _ "$INSTALL"
# 0.0.39j F1: every Step 8 operand carries its own chown — gate 2's mkdir
# runs after gate 1's chown -R, so without its own chown the fresh-install
# leaf ends root-owned.
check "gates: install.sh Step 8 chowns every operand it creates (0.0.39j F1)" \
    sh -c 'grep -qF "sudo chown -R \"\$OPENCODE_USER:\$OPENCODE_GROUP\" /home/opencode/.config/opencode" "$1"' _ "$INSTALL"
check "gates: install.sh agents-migration operand gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$_opk_dst\"" "$1"' _ "$INSTALL"
check "gates: install.sh mkcert chain gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$caroot\"" "$1"' _ "$INSTALL"
check "gates: install.sh agent-config + tui + plugin chain gates" \
    sh -c 'grep -q "agent_home_sane \"\$OPENCODE_USER\" /home/opencode/.config/opencode" "$1" \
        && grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$OC_TUI_DIR\"" "$1" \
        && grep -qF "kit_source \"\$SCRIPT_DIR/opencode-permissions-kit-lib/sh/tui-plugin.sh\"" "$1"' _ "$INSTALL"
check "gates: update.sh sources staged-write.sh early + walker fallback" \
    sh -c 'grep -q "command -v agent_home_sane >/dev/null 2>&1 \|\| agent_home_sane() { return 0; }" "$1"' _ "$UPDATE"
check "gates: update.sh sync_tui_registration + tui.json chain gates" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$OC_TUI_DIR\"" "$1" \
        && grep -qF "sh/tui-plugin.sh" "$1" && grep -qF "agent_home_sane \"\$_tp_oc_user\" \"\$_tp_user_dir\"" "$3"' _ "$UPDATE" "$CONFIG" "$TUIPLUGIN"
check "gates: config.sh git_config_apply chain gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$(dirname \"\$target\")\"" "$1"' _ "$CONFIG"
check "gates: uninstall.sh plugin-removal chain gate" \
    sh -c 'grep -qF "agent_home_sane \"\$OPENCODE_USER\" \"\$_un_dir\"" "$1"' _ "$UNINSTALL"
check "0.0.39h F3: staged-write.sh refuses a directory destination" \
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
