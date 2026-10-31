#!/bin/sh
# Unit tests for the "ddev always runs as the opencode user" feature
# (DDEV-WORKING §7): bin/ddev-as-opencode (sudoers helper) +
# ddev-terminal.sh (sourced `ddev()` shell function) + bin/ddev-as-opencode.
# Runs against the repo files as the CURRENT user — no root, no real
# opencode user required. Verifies:
#   - the helper refuses any non-opencode caller (exit 1)
#   - the helper's ddev resolution / env / exec logic (static)
#   - the function file sources cleanly, defines `ddev()`, and the
#     already-opencode branch execs the REAL ddev (no recursion)
#   - no reference to the removed legacy bin/ddev shim anywhere
#   - wiring: sudoers rule, install.sh/update.sh fetch+deploy+hook,
#     config.sh .ddev handover, status.sh reporting,
#     Makefile target, CI run step + git exec bit
# Run: sh tests/unit/test-ddev-as-opencode.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/../../files"
HELPER="$FILES/opencode-permissions-kit-lib/bin/ddev-as-opencode"
FUNC="$FILES/opencode-permissions-kit-lib/sh/ddev-terminal.sh"
TEMPLATE="$FILES/opencode-permissions-kit-lib/templates/opencode.jsonc"
SUDOERS="$FILES/opencode-permissions-kit-lib/templates/sudoers.template"
INSTALL="$FILES/install.sh"
UPDATE="$FILES/opencode-permissions-kit-lib/management/update.sh"
CONFIG="$FILES/opencode-permissions-kit-lib/management/config.sh"
DEPLOYLIB="$FILES/opencode-permissions-kit-lib/sh/deploy-lib.sh"
KIT="$FILES/opencode-permissions-kit-lib/bin/opk"
HANDOVER="$FILES/opencode-permissions-kit-lib/sh/ddev-handover.sh"
# Hermetic dev-owned checks: never read this machine's real install.conf
# (ddev_devowned_enabled falls back to the stamp) — point it at nothing.
OPK_INSTALL_CONF="/nonexistent-opk-test-install.conf"
export OPK_INSTALL_CONF
STATUS="$FILES/opencode-permissions-kit-lib/management/status.sh"
MAKEFILE="$SCRIPT_DIR/../../Makefile"
TEST_CI="$SCRIPT_DIR/../../.github/workflows/test-unit.yml"

failures=0
passed=0

# Deterministic fixture modes (issue #112): the handover's top-inode fast
# path skips chown -R/chmod -R (and its echo) on already-conforming
# trees — under a developer's umask 002 freshly mkdir'ed dirs would
# conform immediately and flip the first-run assertions below.
umask 022

pass() {
    echo "  ${GREEN}PASS${NC}  $1"
    passed=$((passed + 1))
}
fail() {
    echo "  ${RED}FAIL${NC}  $1"
    failures=$((failures + 1))
}

check() {
    local desc="$1"
    shift
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

check_fail() {
    local desc="$1"
    shift
    if "$@"; then
        fail "$desc (expected absence, got a match)"
    else
        pass "$desc"
    fi
}

assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass "$desc"
    else
        fail "$desc (expected [$expected] got [$actual])"
    fi
}

TMPDIR=$(mktemp -d)
# widen to every bare receiver of the suite + signal arms (#283): the
# WF/SH/DF/CONF/VCHAIN/HWORK/BH/DFH/RN/DWORK/RACE/_112_dir families
# lived outside $TMPDIR with only inline rm on their normal paths — a
# set -e abort inside the window leaked them. Function form: the
# receiver list is far too long for one line; unset-safe operands skip
# cleanly (several receivers are created inside conditionals).
# HRH joined with the sweep finds VN + BS1 (same shape, pre-existing —
# #314 a F4's class sweep); the receiver-completeness probe below keeps
# the list honest from here on.
_trap_cleanup() {
    rm -rf "${TMPDIR:-}" "${WF:-}" "${SH_STUB:-}" "${SH:-}" \
        "${DF_STUB:-}" "${DF:-}" "${DFW:-}" "${CONF:-}" "${VCHAIN:-}" \
        "${HWORK:-}" "${HRH:-}" "${BH:-}" "${DFH:-}" "${DFH2:-}" \
        "${RN:-}" "${VN:-}" "${BS1:-}" "${DWORK:-}" "${RACE:-}" \
        "${RACESTUB:-}" "${RACESP:-}" "${RACESPS:-}" "${RACEC:-}" \
        "${RACECT:-}" "${RACEF:-}" "${RACEFT:-}" "${_112_dir:-}" \
        "${CB285:-}"
}
trap _trap_cleanup EXIT INT TERM

# --- receiver completeness (#314 a F4): every mktemp receiver of this
# suite file must appear in _trap_cleanup's rm -rf list in the unset-safe
# "${VAR:-}" form — an unlisted receiver leaks its scratch dir on every
# abort (the #283 leak class). Self-referential: the probe greps THIS
# file, so a future mktemp whose receiver never reaches the list goes red
# right here, before any test section runs. Indented receivers (BS1's
# conditional-creation shape) are covered by the leading-space-tolerant
# pattern — that shape is exactly the sibling the manual sweeps missed.
# (#328 a A1): quoted receivers (VAR="$(mktemp …)") are matched too —
# the original ERE required =( adjacent and a quoted receiver slipped
# past; quoting style must not blind the guard (pinned below by the
# planted-receiver probe pin).
_opk_recv_check() {
    _orc_list=$(awk '/^_trap_cleanup\(\)/,/^}/' "$1")
    _orc_rc=0
    for _orc_v in $(grep -oE '^[[:space:]]*[A-Za-z_0-9]+="?[[:space:]]*\$\(mktemp' "$1" | cut -d= -f1 | sort -u); do
        _orc_pat=$(printf '"${%s:-}"' "$_orc_v")
        printf '%s' "$_orc_list" | grep -qF "$_orc_pat" || {
            echo "  receiver completeness: $_orc_v is a mktemp receiver but missing from _trap_cleanup (add it to the rm -rf list)" >&2
            _orc_rc=1
        }
    done
    return "$_orc_rc"
}
check "trap cleanup lists every mktemp receiver (receiver completeness)" \
    _opk_recv_check "$(readlink -f "$0")"

echo ""
echo "ddev-as-opencode Tests (DDEV-WORKING §7)"
echo "========================================"
echo ""

# --- 1. helper refuses a non-opencode caller ----------------------------------
# Runs as the current user. Skipped when the current user IS the opencode
# user (then the guard must NOT fire) or when root + no opencode user (the
# guard cannot distinguish that case either).
if [ "$(id -u)" != "$(id -u opencode 2>/dev/null || echo 0)" ]; then
    set +e
    OUT=$(sh "$HELPER" --version 2>&1)
    RC=$?
    set -e
    assert_eq "helper refuses a non-opencode caller (exit 1)" "1" "$RC"
    check "helper prints 'must run as' hint" \
        sh -c "printf '%s' \"\$1\" | grep -q 'must run as'" _ "$OUT"
else
    echo "  ${GREEN}PASS${NC}  (guard test skipped: current user IS opencode/undeterminable)"
    passed=$((passed + 1))
fi

# --- 2. helper ddev-resolution / env / exec logic (static) ---------------------
check "helper resolves the real ddev via PATH" \
    sh -c "grep -q 'command -v ddev' \"\$1\"" _ "$HELPER"
check "helper falls back to /usr/local/bin/ddev" \
    sh -c "grep -qF '/usr/local/bin/ddev' \"\$1\"" _ "$HELPER"
check "helper falls back to /usr/bin/ddev" \
    sh -c "grep -qF '/usr/bin/ddev' \"\$1\"" _ "$HELPER"
check "helper exits 127 with a hint when ddev is missing" \
    sh -c "grep -q 'exit 127' \"\$1\"" _ "$HELPER"
check "helper re-sets HOME for the opencode user" \
    sh -c "grep -qF 'export HOME=\"\${OC_HOME:-/home/\$OPENCODE_USER}\"' \"\$1\" && grep -qF 'OC_HOME=\"\$(getent passwd \"\$OPENCODE_USER\"' \"\$1\"" _ "$HELPER"
check "helper re-sets XDG_RUNTIME_DIR" \
    sh -c "grep -q 'XDG_RUNTIME_DIR' \"\$1\"" _ "$HELPER"
check "helper exports DOCKER_HOST for docker-rootless" \
    sh -c "grep -q 'OPENCODE_DOCKER_HOST' \"\$1\"" _ "$HELPER"
check "helper exports DOCKER_HOST for podman-rootless" \
    sh -c "grep -q 'OPENCODE_PODMAN_SOCKET' \"\$1\"" _ "$HELPER"
check "helper applies umask 002" \
    sh -c "grep -q 'umask 002' \"\$1\"" _ "$HELPER"
check "helper execs the resolved ddev binary" \
    sh -c "grep -q 'exec \"\$DDEV\" \"\$@\"' \"\$1\"" _ "$HELPER"
check_fail "helper never references the removed legacy bin/ddev shim" \
    sh -c "grep -qE 'opencode-permissions-kit/bin/ddev(\$|[^-])' \"\$1\"" _ "$HELPER"

# --- 2b. working-directory fallback (issue #51) ---------------------------------
# sudo keeps the caller's cwd, so the opencode process can inherit a
# directory it cannot search (the developer's $HOME is 0750 on Ubuntu
# 24.04). ddev's compose loader resolves its embedded schema against the
# process cwd (os.Getwd -> stat "."), which dies with 'error in parsing
# "compose-spec.json": stat .: permission denied' there — the issue #51
# warning on cwd-independent runs like `ddev poweroff`. The helper must
# probe the inherited cwd and fall back to the opencode home, noting it
# on stderr and never aborting the run. Functional with stubs: a fake id
# (constant uid — the guard passes for any user) and a fake ddev (args +
# cwd marker). The unreadable cwd is built with the owner-bit trick: a
# process can SIT in a directory it cannot search (exactly what sudo's
# cwd inheritance produces) but [ -x . ] is false there — the condition
# behind Go's stat(".") EACCES.
check "helper probes the inherited cwd for search permission (issue #51)" \
    sh -c "grep -qF 'if ! [ -x . ]; then' \"\$1\"" _ "$HELPER"
check "helper falls back to the opencode home on an unreadable cwd" \
    sh -c "grep -qF 'cd \"\$HOME\" 2>/dev/null || true' \"\$1\"" _ "$HELPER"
check "helper notes the fallback on stderr and never aborts the run" \
    sh -c "grep -q 'not accessible to the opencode user - continuing in ' \"\$1\" && grep -qF '>&2' \"\$1\"" _ "$HELPER"

WF=$(mktemp -d)
mkdir -p "$WF/stub"
printf '#!/bin/sh\necho 4242\n' >"$WF/stub/id"
printf '#!/bin/sh\necho "FAKE_DDEV_ARGS:$*"\necho "FAKE_DDEV_CWD:$(pwd)"\n' >"$WF/stub/ddev"
chmod +x "$WF/stub/id" "$WF/stub/ddev"
mkdir "$WF/locked"

WF_OUT=$(cd "$WF" && PATH="$WF/stub:$PATH" sh "$HELPER" poweroff 2>&1) || true
check "fallback: readable cwd keeps the directory (ddev runs right there)" \
    sh -c "printf '%s\n' \"\$1\" | grep -qF 'FAKE_DDEV_CWD:$WF'" _ "$WF_OUT"
check "fallback: readable cwd stays silent (no note)" \
    sh -c "if printf '%s\n' \"\$1\" | grep -q 'not accessible'; then exit 1; fi" _ "$WF_OUT"
check "fallback: arguments pass through to ddev untouched" \
    sh -c "printf '%s\n' \"\$1\" | grep -qF 'FAKE_DDEV_ARGS:poweroff'" _ "$WF_OUT"

set +e
WF_OUT2=$(cd "$WF/locked" && chmod 007 "$WF/locked" && PATH="$WF/stub:$PATH" sh "$HELPER" stop myproject 2>&1)
WF_RC=$?
set -e
chmod 700 "$WF/locked"
check "fallback: unreadable cwd prints the explanatory note (issue #51)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'not accessible to the opencode user'" _ "$WF_OUT2"
check "fallback: unreadable cwd still execs ddev (exit code passes through)" \
    sh -c "printf '%s\n' \"\$1\" | grep -qF 'FAKE_DDEV_ARGS:stop myproject'" _ "$WF_OUT2" && [ "$WF_RC" = 0 ]
rm -rf "$WF"

# --- 2b. --opk-ensure-shared heal (issue #94) -----------------------------------
# ddev hardcodes explicit 0755/0644 modes which neither the umask nor the
# inherited default ACL can widen — the developer (sharing group) cannot
# write into ddev-created .ddev trees and `git pull` fails. The heal
# re-asserts g+w (owner-only chmod, runs as opencode via the sudoers gate)
# with the heavy generated subtrees pruned. The uid guard is satisfied the
# same way as above: a stubbed id(1) on PATH.
SH_STUB=$(mktemp -d)
printf '#!/bin/sh\necho 4242\n' >"$SH_STUB/id"
chmod 755 "$SH_STUB/id"

SH=$(mktemp -d)
mkdir -p "$SH/.ddev/commands/web" "$SH/.ddev/db_snapshots" "$SH/.ddev/import-db"
printf '#!/bin/sh\n' >"$SH/.ddev/config.yaml"
printf '#!/bin/sh\n' >"$SH/.ddev/commands/web/hostcmd"
printf 'SNAP\n' >"$SH/.ddev/db_snapshots/db.sql.gz"
printf 'DUMP\n' >"$SH/.ddev/import-db/dump.sql.gz"
chmod 755 "$SH/.ddev" "$SH/.ddev/commands" "$SH/.ddev/commands/web" "$SH/.ddev/db_snapshots" "$SH/.ddev/import-db"
chmod 644 "$SH/.ddev/config.yaml" "$SH/.ddev/commands/web/hostcmd" "$SH/.ddev/db_snapshots/db.sql.gz" "$SH/.ddev/import-db/dump.sql.gz"

HEAL_RC=0
HEAL_OUT=$(PATH="$SH_STUB:$PATH" sh "$HELPER" --opk-ensure-shared "$SH/.ddev" 2>&1) || HEAL_RC=$?

check "heal: exits 0 and stays silent" [ "$HEAL_RC" = 0 ] && [ -z "$HEAL_OUT" ]
check "heal: directories get group-write (git can deliver files there)" \
    [ "$(stat -c %a "$SH/.ddev/commands/web")" = "775" ]
check "heal: files get group-write (git can rewrite them)" \
    [ "$(stat -c %a "$SH/.ddev/config.yaml")" = "664" ]
check "heal: db_snapshots stays pruned (ddev chmods it 0777 itself)" \
    [ "$(stat -c %a "$SH/.ddev/db_snapshots")" = "755" ]
check "heal: import-db stays pruned (transient, gitignored)" \
    [ "$(stat -c %a "$SH/.ddev/import-db")" = "755" ]

_hmt_rc=0
PATH="$SH_STUB:$PATH" sh "$HELPER" --opk-ensure-shared "$SH/does-not-exist" >/dev/null 2>&1 ||
    _hmt_rc=$?
check "heal: missing target is a clean no-op (exit 0)" [ "$_hmt_rc" = 0 ]

# The heal must sit BEFORE the ddev resolution/exec: it never needs ddev,
# and the resolve block must not run for it. (#285: the walk runs over a
# comment-stripped copy -- substitute, not delete, so the NR bookkeeping
# stays true; a commented-out handler can no longer satisfy the anchor.)
check "heal: handled before the ddev binary resolution" \
    sh -c "sed 's/^[[:space:]]*#.*\$//' \"\$1\" | awk '/--opk-ensure-shared/{h=NR} /DDEV=\"\"/{d=NR} END{exit !(h>0 && d>0 && h<d)}'" _ "$HELPER"

rm -rf "$SH" "$SH_STUB"

# --- 2c. --opk-devowned-flag (issue #149, finding 1) ---------------------------
# Dev-owned mode must flag a project the moment `ddev config` creates it
# (the dev's ddev() hook routes through this helper mode). The uid guard
# is satisfied with the same stubbed id(1) as the heal tests; the mode is
# hermetic via DDEV_DEV_OWNED / the exported OPK_INSTALL_CONF override
# (the helper must respect it — checked below).
DF_STUB=$(mktemp -d)
printf '#!/bin/sh\necho 4242\n' >"$DF_STUB/id"
chmod 755 "$DF_STUB/id"

DF=$(mktemp -d)
mkdir -p "$DF/on/.ddev" "$DF/off/.ddev" "$DF/none"
printf 'name: flagon\ntype: typo3\ndocroot: public\n' >"$DF/on/.ddev/config.yaml"
printf 'name: flagoff\ntype: typo3\ndocroot: public\n' >"$DF/off/.ddev/config.yaml"

DF_ON_RC=0
DF_ON_OUT=$(DDEV_DEV_OWNED=true PATH="$DF_STUB:$PATH" sh "$HELPER" --opk-devowned-flag "$DF/on" 2>&1) ||
    DF_ON_RC=$?
check "devowned-flag: exits 0 (mode on)" [ "$DF_ON_RC" = 0 ]
check "devowned-flag: writes disable_settings_management: true" \
    sh -c "grep -qx 'disable_settings_management: true' \"\$1/.ddev/config.yaml\"" _ "$DF/on"
check "devowned-flag: flag sits below the head (issue #28 shape, after type:)" \
    [ "$(grep -n '^disable_settings_management: true' "$DF/on/.ddev/config.yaml" | cut -d: -f1)" = 6 ]
check "devowned-flag: prints the commit-it note (dev-visible hint)" \
    sh -c "printf '%s' \"\$1\" | grep -q 'commit it'" _ "$DF_ON_OUT"
DF_ON2_OUT=$(DDEV_DEV_OWNED=true PATH="$DF_STUB:$PATH" sh "$HELPER" --opk-devowned-flag "$DF/on" 2>&1) || true
check "devowned-flag: idempotent — one flag, second run silent" \
    [ "$(grep -c '^disable_settings_management:' "$DF/on/.ddev/config.yaml")" = 1 ] && [ -z "$DF_ON2_OUT" ]

DF_OFF_RC=0
DF_OFF_OUT=$(env -u DDEV_DEV_OWNED PATH="$DF_STUB:$PATH" sh "$HELPER" --opk-devowned-flag "$DF/off" 2>&1) ||
    DF_OFF_RC=$?
check "devowned-flag: mode off writes nothing and stays silent" \
    [ "$DF_OFF_RC" = 0 ] && [ -z "$DF_OFF_OUT" ] && ! grep -q '^disable_settings_management:' "$DF/off/.ddev/config.yaml"

DF_NONE_RC=0
DF_NONE_OUT=$(DDEV_DEV_OWNED=true PATH="$DF_STUB:$PATH" sh "$HELPER" --opk-devowned-flag "$DF/none" 2>&1) ||
    DF_NONE_RC=$?
check "devowned-flag: project without .ddev/config.yaml is a clean no-op" \
    [ "$DF_NONE_RC" = 0 ] && [ -z "$DF_NONE_OUT" ]

check "devowned-flag: helper sources the sibling ddev-handover.sh lib" \
    sh -c "grep -q 'sh/ddev-handover.sh' \"\$1\"" _ "$HELPER"
check "devowned-flag: handled before the ddev binary resolution" \
    sh -c "sed 's/^[[:space:]]*#.*\$//' \"\$1\" | awk '/--opk-devowned-flag/{h=NR} /DDEV=\"\"/{d=NR} END{exit !(h>0 && d>0 && h<d)}'" _ "$HELPER"
check "devowned-flag: helper respects the OPK_INSTALL_CONF override" \
    sh -c "grep -qF 'INSTALL_CONF=\"\${OPK_INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}\"' \"\$1\"" _ "$HELPER"

# 0.0.46b W1: the delivery pins. The hook's sudo call runs this mode as
# `... 2>/dev/null || true`, so everything on stderr is discarded on
# exactly the path this mode exists for — which swallowed all four
# ddev_devowned_flag warnings (the two 0.0.46a F1 write failures and
# the two pre-existing symlink gates). The mode therefore routes its
# diagnostics to STDOUT (exec 2>&1 in the helper branch). These pins
# run the REAL helper with stderr suppressed — the hook's exact
# redirect shape — and assert each reachable warning still arrives; the
# mid-write symlink race (0.0.39h F13) shares the same stream merge and
# is not hermetically constructible (the static exec pin plus these
# cover the class).
DFW=$(mktemp -d)
mkdir -p "$DFW/cat/.ddev" "$DFW/tmp/.ddev" "$DFW/lnk/.ddev"
printf 'name: fwc\ntype: typo3\n' >"$DFW/cat/.ddev/config.yaml"
printf 'name: fwt\ntype: typo3\n' >"$DFW/tmp/.ddev/config.yaml"
printf 'target\n' >"$DFW/lnk/real-config.yaml"
ln -s "$DFW/lnk/real-config.yaml" "$DFW/lnk/.ddev/config.yaml"
chmod 444 "$DFW/cat/.ddev/config.yaml"
chmod 555 "$DFW/tmp/.ddev"
DFW_CAT=$(DDEV_DEV_OWNED=true PATH="$DF_STUB:$PATH" sh "$HELPER" --opk-devowned-flag "$DFW/cat" 2>/dev/null)
check "W1 delivery: cat-write warning arrives on stdout despite the hook's stderr suppression (0.0.46b W1)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'dev-owned flag write to .* failed'" _ "$DFW_CAT"
DFW_TMP=$(DDEV_DEV_OWNED=true PATH="$DF_STUB:$PATH" sh "$HELPER" --opk-devowned-flag "$DFW/tmp" 2>/dev/null)
check "W1 delivery: mktemp warning arrives on stdout (class sweep, 0.0.46b W1)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'not writable (mktemp failed)'" _ "$DFW_TMP"
DFW_LNK=$(DDEV_DEV_OWNED=true PATH="$DF_STUB:$PATH" sh "$HELPER" --opk-devowned-flag "$DFW/lnk" 2>/dev/null)
check "W1 delivery: symlink-gate warning arrives on stdout (pre-existing 0.0.39g S2 class, 0.0.46b W1)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'config.yaml is a symlink'" _ "$DFW_LNK"
check "W1 delivery: the flag mode carries the stdout merge (exec 2>&1 inside the branch, 0.0.46b W1)" \
    sh -c "sed 's/^[[:space:]]*#.*\$//' \"\$1\" | awk 'b&&/^[[:space:]]*exec 2>&1\$/{e=NR} /--opk-devowned-flag/{if(!b)b=NR} b&&/^fi\$/{f=NR} END{exit !(e>0 && e>b && e<f)}'" _ "$HELPER"
chmod 755 "$DFW/tmp/.ddev"
rm -rf "$DFW"

rm -rf "$DF" "$DF_STUB"

# --- 3. function file: sourcing + both branches -------------------------------
# Fixture: a fake ddev on PATH so the already-opencode branch runs something
# observable instead of the (absent) real ddev.
mkdir -p "$TMPDIR/bin"
cat >"$TMPDIR/bin/ddev" <<'FAKE'
#!/bin/sh
echo "REAL_DDEV_RAN:$*"
FAKE
chmod +x "$TMPDIR/bin/ddev"

check "function file sources cleanly (defines a ddev shell function)" \
    sh -c ". \"\$1\" && type ddev 2>&1 | grep -q function" _ "$FUNC"
# Already the opencode user? The function must exec the REAL ddev (fake id +
# a fake ddev on PATH proves no recursion and no sudo).
RESULT=$(
    PATH="$TMPDIR/bin:$PATH"
    id() { echo 4242; }
    . "$FUNC"
    ddev start web
) || true
assert_eq "already-opencode branch runs the real ddev (no sudo, no recursion)" \
    "REAL_DDEV_RAN:start web" "$RESULT"

# --- 2b. _opk_json_get stderr contract (#244 c S3) -----------------------------
# Expected misses are silent and empty (except: pass — the empty-on-miss
# stdout contract is untouched); a broken interpreter's own diagnostic
# passes through instead of being discarded.
GJ_OUT=$(. "$FUNC" && _opk_json_get '{"raw":{"primary_url":"https://x.y"}}' primary_url 2>"$TMPDIR/gj.err")
assert_eq "_opk_json_get returns the string at .raw.<key>" "https://x.y" "$GJ_OUT"
if [ ! -s "$TMPDIR/gj.err" ]; then
    pass "_opk_json_get is silent on the happy path"
else
    fail "_opk_json_get must be silent on the happy path (err=$(cat "$TMPDIR/gj.err"))"
fi
GJ_OUT=$(. "$FUNC" && _opk_json_get '{"broken' primary_url 2>>"$TMPDIR/gj.err")
assert_eq "_opk_json_get: unparseable input yields empty (miss contract)" "" "$GJ_OUT"
if [ ! -s "$TMPDIR/gj.err" ]; then
    pass "_opk_json_get: expected miss stays silent (#244 c S3)"
else
    fail "_opk_json_get: expected miss must stay silent (err=$(cat "$TMPDIR/gj.err"))"
fi
# passes through instead of being discarded. Diagnostic literal in a
# variable: consuming grep lines quoting it inline chain into the
# sandbox scanner's raw-line rm-suffix pattern (#244 c S1).
GJDIAG='platform independent libraries'
mkdir -p "$TMPDIR/noisypy"
printf '#!/bin/sh\necho "%s" >&2\nexit 9\n' "$GJDIAG" >"$TMPDIR/noisypy/python3"
chmod +x "$TMPDIR/noisypy/python3"
GJ_OUT=$(PATH="$TMPDIR/noisypy:$PATH" sh -c ". '$FUNC' && _opk_json_get '{}' primary_url" 2>"$TMPDIR/gj-noisy.err") || true
assert_eq "_opk_json_get: broken interpreter still yields empty (contract holds)" "" "$GJ_OUT"
if grep -qF "$GJDIAG" "$TMPDIR/gj-noisy.err"; then
    pass "_opk_json_get surfaces a broken interpreter's diagnostic (#244 c S3)"
else
    fail "_opk_json_get must pass interpreter stderr through (#244 c S3)"
fi
# (#244 d Q1) absent python3: guarded to the miss contract — empty
# output, no shell not-found noise (absence is legitimate mid-lifecycle,
# not a diagnostic event). Source first, then restrict PATH.
GJABS="$TMPDIR/gj-abs"
mkdir -p "$GJABS"
GJ_OUT=$(sh -c ". '$FUNC'; PATH='$GJABS'; _opk_json_get '{\"raw\":{\"primary_url\":\"https://x.y\"}}' primary_url" 2>"$TMPDIR/gj-abs.err") || true
assert_eq "_opk_json_get: absent python3 yields empty (miss contract)" "" "$GJ_OUT"
if [ ! -s "$TMPDIR/gj-abs.err" ]; then
    pass "_opk_json_get: absent python3 stays silent (#244 d Q1)"
else
    fail "_opk_json_get: absent python3 must stay silent (err=$(cat "$TMPDIR/gj-abs.err"))"
fi

check "function execs the kit's sudoers helper for the developer" \
    sh -c "grep -q 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode' \"\$1\"" _ "$FUNC"
check "function uses 'command ddev' in the opencode branch" \
    sh -c "grep -q 'command ddev' \"\$1\"" _ "$FUNC"

# --- 3a. browser commands (issue #20) ------------------------------------------
# `ddev launch` & co read their URL from `ddev describe -j` AS OPENCODE
# via the sudoers helper (upstream guidance, ddev/ddev#8771 — describe
# carries the URLs even for a stopped project) and only the browser open
# runs as the developer — as the developer ddev cannot see the rootless
# daemon and would run its internal `ddev start` on every launch. The
# describe→URL mapping is pure shell (tested functionally below); the
# sudo arms are static checks (the arm calls the absolute /usr/bin/sudo
# — not interceptable in unit tests; the e2e suite covers the full
# chain).
check "browser arm describes the project as opencode via the helper (issue #20)" \
    sh -c "grep -qF 'ddev-as-opencode describe -j' \"\$1\"" _ "$FUNC"
check "browser arm starts a stopped project first (launch-script parity)" \
    sh -c "grep -qF 'ddev-as-opencode start' \"\$1\"" _ "$FUNC"
check "browser arm prints the bootstrap hint before its internal start" \
    sh -c "grep -qF '_opk_bootstrap_hint' \"\$1\"" _ "$FUNC"
check "browser arm prints the hosts-file hint after its internal start (direct-start parity)" \
    sh -c "grep -qF '_opk_hosts_hint' \"\$1\"" _ "$FUNC"
check "browser arm opens the URL with the developer's interop (explorer.exe/xdg-open)" \
    sh -c "grep -q 'explorer.exe' \"\$1\" && grep -q 'xdg-open' \"\$1\"" _ "$FUNC"
check "browser arm plain-runs commands without a describe URL (prompts stay interactive)" \
    sh -c "grep -qF 'browser open is skipped' \"\$1\"" _ "$FUNC"
check "browser arm parses the describe JSON with python3 (kit prerequisite)" \
    sh -c "grep -q 'python3' \"\$1\"" _ "$FUNC"
check "sudoers env_keep keeps the transport vars" \
    sh -c "grep -q 'env_keep += \"DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD OPENCODE_SERVER_USERNAME\"' \"\$1\"" _ "$SUDOERS"
check_fail "sudoers no longer keep DDEV_DEBUG (describe transport needs none)" \
    sh -c "grep -q 'DDEV_DEBUG' \"\$1\"" _ "$SUDOERS"
check_fail "function file no longer uses the FULLURL debug contract" \
    sh -c "grep -q 'FULLURL' \"\$1\"" _ "$FUNC"

# describe→URL mapping, functional: the fixture mirrors the fields ddev
# emits for a running project (config-derived fields exist even when
# stopped). BU <json> <cmd> [arg] runs _opk_browser_url on the fixture.
DJ='{"raw":{"status":"running","primary_url":"https://fake-project.ddev.site","mailpit_https_url":"https://fake-project.ddev.site:8026","mailpit_url":"http://fake-project.ddev.site:8025","xhgui_status":"enabled","xhgui_https_url":"https://fake-project.ddev.site:8443","xhgui_url":"http://fake-project.ddev.site:8442","services":{"phpmyadmin":{"https_url":"https://fake-project.ddev.site:8036"}}},"level":"info","msg":"fake"}'
DJ_HTTP='{"raw":{"status":"running","primary_url":"http://fake-project.ddev.site:8080","mailpit_https_url":"https://fake-project.ddev.site:8026","mailpit_url":"http://fake-project.ddev.site:8025"},"level":"info","msg":"fake"}'
DJ_NOX='{"raw":{"status":"running","primary_url":"https://fake-project.ddev.site","xhgui_status":"disabled"},"level":"info","msg":"fake"}'
BU() { sh -c '. "$1" && _opk_browser_url "$2" "$3" "$4"' _ "$FUNC" "$1" "$2" "${3:-}"; }
assert_eq "url: bare launch is the primary URL" \
    "https://fake-project.ddev.site" "$(BU "$DJ" launch)"
assert_eq "url: launch <path> appends the path" \
    "https://fake-project.ddev.site/typo3" "$(BU "$DJ" launch /typo3)"
assert_eq "url: launch <rel-path> inserts the slash" \
    "https://fake-project.ddev.site/phpinfo.php" "$(BU "$DJ" launch phpinfo.php)"
assert_eq "url: launch <full-url> passes it through" \
    "https://elsewhere.example/sub" "$(BU "$DJ" launch https://elsewhere.example/sub)"
assert_eq "url: launch :<port> replaces the primary port" \
    "https://fake-project.ddev.site:8031" "$(BU "$DJ" launch :8031)"
assert_eq "url: launch :<port> on a ported primary strips the old port" \
    "http://fake-project.ddev.site:3000" "$(BU "$DJ_HTTP" launch :3000)"
assert_eq "url: launch -m is the Mailpit URL" \
    "https://fake-project.ddev.site:8026" "$(BU "$DJ" launch -m)"
assert_eq "url: launch --mailpit works too" \
    "https://fake-project.ddev.site:8026" "$(BU "$DJ" launch --mailpit)"
assert_eq "url: launch -m falls back to plain run for -p (ddev prints its hint)" \
    "" "$(BU "$DJ" launch -p)"
assert_eq "url: mailpit is the https variant (https primary)" \
    "https://fake-project.ddev.site:8026" "$(BU "$DJ" mailpit)"
assert_eq "url: mailpit is the http variant (http primary)" \
    "http://fake-project.ddev.site:8025" "$(BU "$DJ_HTTP" mailpit)"
assert_eq "url: xhgui is the xhgui URL when enabled" \
    "https://fake-project.ddev.site:8443" "$(BU "$DJ" xhgui)"
assert_eq "url: xhgui disabled falls back to plain run" \
    "" "$(BU "$DJ_NOX" xhgui)"
assert_eq "url: phpmyadmin comes from the describe service" \
    "https://fake-project.ddev.site:8036" "$(BU "$DJ" phpmyadmin)"
assert_eq "url: adminer without a describe service falls back to plain run" \
    "" "$(BU "$DJ" adminer)"
assert_eq "url: json field extraction of a nested path" \
    "https://fake-project.ddev.site:8036" \
    "$(sh -c '. "$1" && _opk_json_get "$2" services phpmyadmin https_url' _ "$FUNC" "$DJ")"
assert_eq "url: json field extraction of a missing path is empty" \
    "" "$(sh -c '. "$1" && _opk_json_get "$2" services adminer https_url' _ "$FUNC" "$DJ")"

# --- 3a-2. browser-command routing (issue #20 follow-up: mailpit/phpmyadmin) ---
# Functional against _opk_is_browser_cmd: the default list, the xhgui
# arg-awareness, and the extensible conf file (OPK_BROWSER_CMDS_CONF).
BC() { env OPK_BROWSER_CMDS_CONF="${3:-/nonexistent}" sh -c '. "$1" && if _opk_is_browser_cmd "$2" "${4:-}"; then echo yes; else echo no; fi' _ "$FUNC" "$1" "" "$2"; }
assert_eq "routing: launch is a browser command" "yes" "$(BC launch)"
assert_eq "routing: mailpit is a browser command" "yes" "$(BC mailpit)"
assert_eq "routing: phpmyadmin is a browser command" "yes" "$(BC phpmyadmin)"
assert_eq "routing: adminer is a browser command" "yes" "$(BC adminer)"
assert_eq "routing: bare xhgui is a browser command" "yes" "$(BC xhgui)"
assert_eq "routing: xhgui launch is a browser command" "yes" "$(BC xhgui launch)"
assert_eq "routing: xhgui status is NOT" "no" "$(BC xhgui status)"
assert_eq "routing: start is NOT" "no" "$(BC start)"
assert_eq "routing: exec is NOT" "no" "$(BC exec)"
CONF=$(mktemp)
printf '# custom browser commands\nmy-custom-tool\n\n# another\n  spaced-tool  \n' >"$CONF"
assert_eq "routing: conf file adds custom browser commands (issue #20 follow-up)" "yes" \
    "$(env OPK_BROWSER_CMDS_CONF="$CONF" sh -c '. "$1" && if _opk_is_browser_cmd my-custom-tool; then echo yes; else echo no; fi' _ "$FUNC")"
assert_eq "routing: conf entries are whitespace/comment tolerant" "yes" \
    "$(env OPK_BROWSER_CMDS_CONF="$CONF" sh -c '. "$1" && if _opk_is_browser_cmd spaced-tool; then echo yes; else echo no; fi' _ "$FUNC")"
rm -f "$CONF"
check "non-launch commands still route through the sudoers helper (case arm)" \
    sh -c "grep -qF 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode \"\$@\"' \"\$1\"" _ "$FUNC"
check_fail "function never references the removed legacy bin/ddev shim" \
    sh -c "grep -qE 'opencode-permissions-kit/bin/ddev(\$|[^-])' \"\$1\"" _ "$FUNC"

# --- 3b. exported function reaches child bash scripts (issue #18) -----------
# Vendor scripts (TYPO3 vendor/bin/runTests.sh) run ddev in a CHILD bash
# shell. The hook must export the function there (bash-only, guarded on
# BASH_VERSION), so `type -t ddev` in the child reports "function" and
# `command -v ddev` resolves to it. Nested bash chain:
# sh -> bash (source + export -f) -> bash (import via environment).
check "function file exports ddev for bash children" \
    sh -c "grep -qF 'export -f ddev' \"\$1\"" _ "$FUNC"
check "export block is guarded (never runs in dash/zsh)" \
    sh -c "grep -qF '[ -n \"\${BASH_VERSION:-}\" ]' \"\$1\"" _ "$FUNC"
check "function body is set -u safe (\${1:-} in the hosts-hint case)" \
    sh -c "grep -qF 'case \"\${1:-}\" in' \"\$1\"" _ "$FUNC"
check "exported ddev() reaches a child bash script (type -t)" \
    env OPK_FUNC="$FUNC" sh -c 'bash -c ". \"\$OPK_FUNC\" 2>/dev/null; bash -c \"type -t ddev\"" | grep -q function'
check "exported ddev() is what command -v resolves to in a child bash script" \
    env OPK_FUNC="$FUNC" sh -c 'bash -c ". \"\$OPK_FUNC\" 2>/dev/null; bash -c \"command -v ddev\"" | grep -qx ddev'

# --- 3c. BASH_ENV second transport: survives #!/bin/sh wrappers (issue #18) --
# The real vendor/bin/runTests.sh is a dash wrapper that execs a bash
# target; dash strips BASH_FUNC_* env entries, so only the BASH_ENV
# transport (plain variable, self-referential via BASH_SOURCE, never
# clobbering a user-set value) gets the function through the chain:
# sh -> bash (source hook) -> sh wrapper (exec) -> bash target.
VCHAIN=$(mktemp -d)
printf '#!/usr/bin/env sh\nexec "%s/target.sh" "$@"\n' "$VCHAIN" >"$VCHAIN/wrapper.sh"
printf '#!/usr/bin/env bash\ntype -t ddev\n' >"$VCHAIN/target.sh"
chmod +x "$VCHAIN/wrapper.sh" "$VCHAIN/target.sh"
check "hook sets BASH_ENV (self-referential, empty-guarded)" \
    sh -c "grep -qF '[ -z \"\${BASH_ENV:-}\" ]' \"\$1\" && grep -q 'export BASH_ENV=' \"\$1\"" _ "$FUNC"
check "ddev() survives a #!/bin/sh wrapper into the bash target (issue #18)" \
    env OPK_FUNC="$FUNC" OPK_CHAIN="$VCHAIN" sh -c 'bash -c ". \"\$OPK_FUNC\" 2>/dev/null; \"\$OPK_CHAIN/wrapper.sh\" -s phpstan" | grep -q function'
check "hook does not clobber a user-set BASH_ENV" \
    env OPK_FUNC="$FUNC" sh -c 'bash -c "export BASH_ENV=/nonexistent-user-file; . \"\$OPK_FUNC\" 2>/dev/null; test \"\$BASH_ENV\" = /nonexistent-user-file"'
rm -rf "$VCHAIN"

# --- 4. sudoers rule -----------------------------------------------------------
check "sudoers.template grants the ddev-as-opencode helper" \
    sh -c "grep -q 'NOPASSWD: /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode' \"\$1\"" _ "$SUDOERS"

# --- 4b. credential-import gate (ddev auth ssh) ---------------------------------
check "template denies 'ddev auth ssh*' (incl. sudo)" \
    sh -c "grep -q '\"ddev auth ssh\\*\": \"deny\"' \"\$1\" && grep -q '\"sudo ddev auth ssh\\*\": \"deny\"' \"\$1\"" _ "$TEMPLATE"
check "template explains the /home/opencode/.ddev key trade-off" \
    sh -c "grep -q 'home/opencode/.ddev' \"\$1\" && grep -q 'EVERY opencode session' \"\$1\"" _ "$TEMPLATE"
check "template states the import destination is user-independent" \
    sh -c "grep -q 'SAME no matter who runs' \"\$1\"" _ "$TEMPLATE"
check "template warns that project 'ddev *' allows override the gate" \
    sh -c "grep -q 'merge LAST and override' \"\$1\"" _ "$TEMPLATE"
check "template still parses cleanly with the new rules" \
    python3 "$FILES/opencode-permissions-kit-lib/py/jsonc-parser.py" "$TEMPLATE"

# --- 5. install.sh wiring ------------------------------------------------------
check "install.sh fetches both new files (fetch_kit list)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-terminal.sh' \"\$1\" && grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$INSTALL"
check "install.sh deploys the function file (lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-terminal.sh 644' \"\$2\" && grep -q 'lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"' \"\$1\"" _ "$INSTALL" "$DEPLOYLIB"
check "install.sh deploys the helper (mode 755, lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode 755' \"\$2\" && grep -q 'lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"' \"\$1\"" _ "$INSTALL" "$DEPLOYLIB"
check "install.sh hooks the function into the developer rc files" \
    sh -c "grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh' \"\$1\"" _ "$INSTALL"
# The hook line is splice-wrapped in the canonical dq form (#300 tier 1,
# #255 stage 0a idiom): frag2's opening quote sits at EOL, so both pinned
# literals are raw-matched per line -- the guard prefix with its quote
# boundary on the head line, the sourced path + kit marker on the
# continuation line.
check "install.sh hooks use the [ -f ] uninstall-safe guard" \
    sh -c "grep -qF '\"[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . \"' \"\$1\" && grep -qF '/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh  # opencode permissions kit' \"\$1\"" _ "$INSTALL"
check "install.sh hands over ddev paths in the filesystem step" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$INSTALL"

# --- 6. update.sh wiring -------------------------------------------------------
check "update.sh KIT_FILES includes both new files" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-terminal.sh' \"\$1\" && grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$UPDATE"
check "update.sh KIT_FILES includes the handover helper" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-handover.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys the function file (lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/sh/ddev-terminal.sh 644' \"\$2\" && grep -q 'lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"' \"\$1\"" _ "$UPDATE" "$DEPLOYLIB"
check "update.sh deploys the helper (mode 755, lib_deploy manifest)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode 755' \"\$2\" && grep -q 'lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"' \"\$1\"" _ "$UPDATE" "$DEPLOYLIB"
check "update.sh heals the rc-file hook idempotently" \
    sh -c "grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh' \"\$1\"" _ "$UPDATE"
check "update.sh runs the ddev handover unconditionally" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$UPDATE"

# --- 7. handover helper + call sites ---------------------------------------------
check "handover helper searches .ddev at any depth" \
    sh -c "grep -qF 'find \"\$dhr_root\"' \"\$1\" && grep -qF -- '-type d -name .ddev -prune -print' \"\$1\"" _ "$HANDOVER"
check "handover scan prunes vendor/node_modules (issue #21 pattern)" \
    sh -c "grep -qF -- '-name vendor -o -name node_modules' \"\$1\"" _ "$HANDOVER"
check "handover helper chowns recursively with g+w" \
    sh -c "grep -q 'chmod -R g+w' \"\$1\"" _ "$HANDOVER"
check "handover helper maps typo3 settings dirs (config/system, typo3conf)" \
    sh -c "grep -qF 'echo \"config/system \$dts_docroot/typo3conf typo3conf\"' \"\$1\"" _ "$HANDOVER"
check "handover helper maps drupal settings dirs (sites/default)" \
    sh -c "grep -qF '\$dts_docroot/sites/default' \"\$1\"" _ "$HANDOVER"
check "handover helper skips unknown app types" \
    sh -c "grep -qF 'return 0' \"\$1\"" _ "$HANDOVER"
check "config.sh projects add uses the handover helper" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$CONFIG"
check "update.sh refresh uses the handover helper" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$UPDATE"

# --- 7b. project-root handover (TYPO3 bootstrap, EPERM on fresh clones) ---------
# ddev's settings-path fallback targets the APP ROOT while TYPO3 is not
# yet installed and chmods it to 0755 — owner-only, so the root must
# belong to the ddev user during bootstrap and go back to the developer
# once detection kicks in. Functional test as the CURRENT user (chown to
# self is permitted, so the ownership branches are exercised as no-ops;
# the MODE changes are real).
HWORK=$(mktemp -d)
mkdir -p "$HWORK/proj/.ddev"
printf 'type: typo3\n' >"$HWORK/proj/.ddev/config.yaml"
chmod 2775 "$HWORK/proj"

check "typo3 detection: no vendor, no typo3 dir => undetected" \
    sh -c ". \"\$1\" && if ddev_typo3_detected \"\$2\" .; then exit 1; fi" _ "$HANDOVER" "$HWORK/proj"

mkdir -p "$HWORK/proj/vendor/typo3/cms-core/Classes/Information"
touch "$HWORK/proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php"
check "typo3 detection: vendor Typo3Version.php => detected (composer mode)" \
    sh -c ". \"\$1\" && ddev_typo3_detected \"\$2\" ." _ "$HANDOVER" "$HWORK/proj"
rm -rf "${HWORK:?}/proj/vendor"
check "typo3 detection: docroot typo3 dir => detected (legacy)" \
    sh -c "mkdir -p \"\$2/public/typo3\" && . \"\$1\" && ddev_typo3_detected \"\$2\" public" _ "$HANDOVER" "$HWORK/proj"
rm -rf "${HWORK:?}/proj/public"

check "undetected typo3: root becomes 2755 (Perm==0755, ddev chmod is a no-op)" \
    sh -c ". \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2755" _ "$HANDOVER" "$HWORK/proj"

mkdir -p "$HWORK/proj/vendor/typo3/cms-core/Classes/Information"
touch "$HWORK/proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php"
check "detected typo3: root handed back with 2775 (g+w restored)" \
    sh -c ". \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2775" _ "$HANDOVER" "$HWORK/proj"

# --- 7c. docroot containment (0.0.39e S2) -----------------------------------------
# docroot comes from the group-writable .ddev/config.yaml and feeds
# root-run chown -R paths — traversal or absolute values must fall back
# to "." (with a warning), never escape the project root.
printf 'name: d1\ntype: typo3\ndocroot: public\n' >"$HWORK/proj/.ddev/config.yaml"
check "docroot containment: sane docroot passes through" \
    sh -c ". \"\$1\" 2>/dev/null && [ \"\$(ddev_type_settings_dirs \"\$2\" 2>/dev/null)\" = 'config/system public/typo3conf typo3conf' ]" _ "$HANDOVER" "$HWORK/proj"
printf 'name: d2\ntype: typo3\ndocroot: ../../..\n' >"$HWORK/proj/.ddev/config.yaml"
check "docroot containment: traversal falls back to '.' and warns" \
    sh -c ". \"\$1\" && out=\$(ddev_type_settings_dirs \"\$2\" 2>&1); case \"\$out\" in *WARNING*) ;; *) exit 1 ;; esac; [ \"\$(printf '%s\n' \"\$out\" | grep -v WARNING)\" = 'config/system ./typo3conf typo3conf' ]" _ "$HANDOVER" "$HWORK/proj"
printf 'name: d3\ntype: drupal\ndocroot: /etc\n' >"$HWORK/proj/.ddev/config.yaml"
check "docroot containment: absolute docroot falls back to '.'" \
    sh -c ". \"\$1\" && [ \"\$(ddev_type_settings_dirs \"\$2\" 2>/dev/null)\" = './sites/default' ]" _ "$HANDOVER" "$HWORK/proj"
printf 'type: typo3\n' >"$HWORK/proj/.ddev/config.yaml"

check "non-typo3 type: root untouched by the project-root handover" \
    sh -c "printf 'type: php\n' > \"\$2/.ddev/config.yaml\" && chmod 2770 \"\$2\" && . \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2770" _ "$HANDOVER" "$HWORK/proj"

# --- 7c-2. unmapped types join the map (issue #149, finding 5) --------------------
# ddev's generic CreateSettingsFile chmods Dir(SiteSettingsPath) for every
# type with settings paths — maho (app/etc) and modx (<docroot>/core/config)
# are dir types like magento/drupal; codeigniter/shopware6/symfony are
# root-file types (.env/.env.local at the root) handled via the project-root
# inode (permanent while unflagged, handed back once flagged).
printf 'type: maho\n' >"$HWORK/proj/.ddev/config.yaml"
check "type map: maho -> app/etc (magento fork)" \
    sh -c ". \"\$1\" && [ \"\$(ddev_type_settings_dirs \"\$2\" 2>/dev/null)\" = 'app/etc' ]" _ "$HANDOVER" "$HWORK/proj"
printf 'type: modx\ndocroot: html\n' >"$HWORK/proj/.ddev/config.yaml"
check "type map: modx -> <docroot>/core/config" \
    sh -c ". \"\$1\" && [ \"\$(ddev_type_settings_dirs \"\$2\" 2>/dev/null)\" = 'html/core/config' ]" _ "$HANDOVER" "$HWORK/proj"
printf 'type: codeigniter\n' >"$HWORK/proj/.ddev/config.yaml"
check "type map: root-file types have no settings dirs (root inode instead)" \
    sh -c ". \"\$1\" && [ -z \"\$(ddev_type_settings_dirs \"\$2\" 2>/dev/null)\" ]" _ "$HANDOVER" "$HWORK/proj"

chmod 2770 "$HWORK/proj"
check "root-file type (symfony): unflagged root handed to the kit user 2755" \
    sh -c "printf 'type: symfony\n' > \"\$2/.ddev/config.yaml\" && chmod 2770 \"\$2\" && . \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2755" _ "$HANDOVER" "$HWORK/proj"
check "root-file type (shopware6): same permanent root handover" \
    sh -c "printf 'type: shopware6\n' > \"\$2/.ddev/config.yaml\" && . \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2755" _ "$HANDOVER" "$HWORK/proj"
check "root-file type (codeigniter): same permanent root handover" \
    sh -c "printf 'type: codeigniter\n' > \"\$2/.ddev/config.yaml\" && . \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2755" _ "$HANDOVER" "$HWORK/proj"
check "root-file types: flagged project gets the root back (handback)" \
    sh -c "printf 'type: symfony\ndisable_settings_management: true\n' > \"\$2/.ddev/config.yaml\" && . \"\$1\" && ddev_handover_project_back \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2775" _ "$HANDOVER" "$HWORK/proj"

# hint coverage (static): the bootstrap hint names the new type classes
check "hint: covers maho/modx settings dirs (issue #149 finding 5)" \
    sh -c "awk '/^_opk_bootstrap_hint\(\)/,/^}/' \"\$1\" | grep -q 'maho | modx'" _ "$FUNC"
check "hint: covers the root-file types (codeigniter/shopware6/symfony)" \
    sh -c "awk '/^_opk_bootstrap_hint\(\)/,/^}/' \"\$1\" | grep -q 'codeigniter | shopware6 | symfony'" _ "$FUNC"
check "hint: typo3 wording unchanged (e2e greps it)" \
    sh -c "awk '/^_opk_bootstrap_hint\(\)/,/^}/' \"\$1\" | grep -q 'hint: fresh typo3 clone'" _ "$FUNC"
printf 'type: typo3\n' >"$HWORK/proj/.ddev/config.yaml"

check "handover_root signature carries the dev user (handback target)" \
    sh -c "grep -qF 'dhr_dev=\"\${4:-}\"' \"\$1\"" _ "$HANDOVER"

# Functional prune check: a .ddev inside vendor/ is NOT handed over (a
# shipped test fixture, not a project — issue #21 pattern), the real
# project .ddev still is.
rm -rf "${HWORK:?}/scan"
mkdir -p "$HWORK/scan/proj/.ddev" "$HWORK/scan/proj/vendor/some/pkg/.ddev"
SCAN_OUT=$(sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\"" _ "$HANDOVER" "$HWORK/scan" 2>/dev/null || true)
check "handover scan skips .ddev inside vendor/" \
    sh -c "! printf '%s\n' \"\$1\" | grep -q 'vendor/some/pkg/.ddev'" _ "$SCAN_OUT"
check "handover scan still hands over the project .ddev" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'proj/.ddev'" _ "$SCAN_OUT"
rm -rf "${HWORK:?}/scan"

# --- 7c. config.sh handover subcommand (fresh-clone EPERM repair) -----------------
check "config.sh dispatches the handover action" \
    sh -c "grep -q 'handover)' \"\$1\"" _ "$CONFIG"
check "config.sh handover uses the handover helper (no baseline)" \
    sh -c "awk '/^handover\(\)/,/^}/' \"\$1\" | grep -q 'ddev_handover_root'" _ "$CONFIG"
check "config.sh handover screens system paths" \
    sh -c "awk '/^handover\(\)/,/^}/' \"\$1\" | grep -q 'project_path_sane'" _ "$CONFIG"
check "config.sh header documents the handover usage" \
    sh -c "grep -q 'config.sh handover' \"\$1\"" _ "$CONFIG"
check "kit CLI usage documents the handover command" \
    sh -c "grep -q 'handover <path...>' \"\$1\"" _ "$KIT"

# --- 7c-2. config.sh handover tail note: rootless metadata ownership (#312) -------
# Functional (7b extraction pattern): the note must fire for BOTH rootless
# backends and stay silent for unknown/empty/legacy values — a non-rootless
# daemon has no unmapped-uid class, and the note would be wrong there.
# ui_detail is stubbed to pass text through; OPENCODE_USER is pinned to
# config.sh's install.conf default. CONTAINER_BACKEND feeds the case arm
# via the environment, so no INSTALL_CONF fixture is needed.
HRH=$(mktemp -d)
awk '/^_handover_rootless_hint\(\)/,/^}/' "$CONFIG" >"$HRH/fn.sh"
_hrh() {
    CONTAINER_BACKEND="$1" OPENCODE_USER=opencode sh -c '
        ui_detail() { printf "%s\n" "$1"; }
        . "$1/fn.sh" && _handover_rootless_hint
    ' _ "$HRH"
}
HRH_DR=$(_hrh docker-rootless)
HRH_PR=$(_hrh podman-rootless)
HRH_DOCKER=$(_hrh docker)
HRH_EMPTY=$(_hrh "")
check "tail note fires on docker-rootless and names the EPERM symptom" \
    sh -c "printf '%s\n' \"\$1\" | grep -qF \"EPERM ... futime\"" _ "$HRH_DR"
check "tail note fires on podman-rootless too (both rootless backends)" \
    sh -c "printf '%s\n' \"\$1\" | grep -qF \"EPERM ... futime\"" _ "$HRH_PR"
check "tail note names the ready-made fix command" \
    sh -c "printf '%s\n' \"\$1\" | grep -qF 'sudo opk handover opencode'" _ "$HRH_DR"
check "tail note points at the troubleshooting entry" \
    sh -c "printf '%s\n' \"\$1\" | grep -qF 'docs/troubleshooting.md'" _ "$HRH_DR"
check "tail note stays silent for a non-rootless backend value" \
    sh -c "! printf '%s\n' \"\$1\" | grep -qF 'EPERM ... futime'" _ "$HRH_DOCKER"
check "tail note stays silent for an empty backend value" \
    sh -c "! printf '%s\n' \"\$1\" | grep -qF 'EPERM ... futime'" _ "$HRH_EMPTY"
check "config.sh handover wires the tail note after the repair loop" \
    sh -c "awk '/^handover\(\)/,/^}/' \"\$1\" | grep -q '_handover_rootless_hint'" _ "$CONFIG"
rm -rf "${HRH:?}"

# --- 7d. ddev() hook: typo3 bootstrap hint ----------------------------------------
# Fresh clone + type typo3 + undetected + root not opencode-owned => ddev
# start fails with EPERM. The hook must name the one-command fix BEFORE
# the run; silent in every other case (grep-based, mirrors the hosts-hint
# tests — the fixed /usr/local lib path prevents a functional test).
check "hook prints the typo3-bootstrap hint before start/restart" \
    sh -c "grep -qE 'start\\\|restart\\) _opk_bootstrap_hint' \"\$1\"" _ "$FUNC"
check "hook bootstrap hint shows the ready-made handover command" \
    sh -c "grep -q 'config handover' \"\$1\"" _ "$FUNC"
check "hook bootstrap hint is gated on a project in the cwd" \
    sh -c "grep -qF '[ -f \"\$PWD/.ddev/config.yaml\" ]' \"\$1\"" _ "$FUNC"
check "hook bootstrap hint reuses the kit typo3 detection" \
    sh -c "grep -q 'ddev_typo3_detected' \"\$1\"" _ "$FUNC"
check "hook bootstrap hint stays silent for dev-owned flagged projects" \
    sh -c "awk '/^_opk_bootstrap_hint\(\)/,/^}/' \"\$1\" | grep -q 'ddev_devowned_flagged \"\$PWD\" && return 0'" _ "$FUNC"
check "hook bootstrap hint stays silent when the root is already handed over" \
    sh -c "grep -qF '[ \"\$(stat -c %U \"\$PWD\" 2>/dev/null)\" = \"opencode\" ]' \"\$1\"" _ "$FUNC"
check "hook exports the bootstrap hint for bash children" \
    sh -c "grep -q 'export -f ddev _opk_hosts_hint _opk_bootstrap_hint' \"\$1\"" _ "$FUNC"

# --- 7d-1b. maho/modx hint arms, functional (0.0.46a F6) ------------------------
# Static greps cannot catch a typo'd target path, and e2e DD16 covers
# maho + symfony only — a broken modx arm would ship green. Functional
# via the OPK_DDEV_HANDOVER_LIB stub (unflagged, mode off so the
# dev-owned tail note stays out) and a PATH stub for stat(1) answering
# as the developer (the owner gate compares against "opencode"). The
# arm only prints when its target DIR exists — exactly the path fact
# these pins verify.
BH=$(mktemp -d)
mkdir -p "$BH/bin" "$BH/m/.ddev" "$BH/m/app/etc" "$BH/x/.ddev" "$BH/x/html/core/config"
printf 'name: bm\ntype: maho\n' >"$BH/m/.ddev/config.yaml"
printf 'name: bx\ntype: modx\ndocroot: html\n' >"$BH/x/.ddev/config.yaml"
printf '#!/bin/sh\necho some-developer\n' >"$BH/bin/stat"
chmod 755 "$BH/bin/stat"
printf 'ddev_devowned_flagged() { return 1; }\nddev_devowned_enabled() { return 1; }\n' >"$BH/lib.sh"
BH_M=$(cd "$BH/m" && PATH="$BH/bin:$PATH" OPK_DDEV_HANDOVER_LIB="$BH/lib.sh" sh -c '. "$1" && _opk_bootstrap_hint' _ "$FUNC")
check "hint arm: maho prints the app/etc settings-dir hint (functional, 0.0.46a F6)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q \"hint: this maho project's settings dir\"" _ "$BH_M"
BH_X=$(cd "$BH/x" && PATH="$BH/bin:$PATH" OPK_DDEV_HANDOVER_LIB="$BH/lib.sh" sh -c '. "$1" && _opk_bootstrap_hint' _ "$FUNC")
check "hint arm: modx builds <docroot>/core/config (functional, 0.0.46a F6)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q \"hint: this modx project's settings dir\"" _ "$BH_X"
# owner gate: an opencode-owned target must stay silent
printf '#!/bin/sh\necho opencode\n' >"$BH/bin/stat"
BH_S=$(cd "$BH/x" && PATH="$BH/bin:$PATH" OPK_DDEV_HANDOVER_LIB="$BH/lib.sh" sh -c '. "$1" && _opk_bootstrap_hint' _ "$FUNC")
check "hint arm: opencode-owned target stays silent (functional)" \
    sh -c "[ -z \"\$1\" ]" _ "$BH_S"
rm -rf "$BH"

# --- 7d. reshare wiring (issue #94, widened to every command in #279) --------------
# The ddev() function must re-assert group-write after EVERY ddev command
# (ddev's explicit 0755/0644 modes cap the inherited ACL mask, AND its
# command-list walk re-chmods .ddev/commands/** on every invocation —
# describe/--version included), through the sudoers helper's heal mode.
check "reshare: _opk_ddev_reshare calls the helper's heal mode" \
    sh -c "awk '/^_opk_ddev_reshare\(\)/,/^}/' \"\$1\" | grep -q -- '--opk-ensure-shared' " _ "$FUNC"
check "reshare: heal follows EVERY ddev command — no command gate (issue #279)" \
    sh -c "awk '/^ddev\(\)/,/^}/' \"\$1\" | grep -qE '^[[:space:]]*_opk_ddev_reshare[[:space:]]*$' && ! awk '/^ddev\(\)/,/^}/' \"\$1\" | grep -q 'config | get | start | restart'" _ "$FUNC"
check "reshare: heal is silent and never changes the ddev exit code" \
    sh -c "awk '/^_opk_ddev_reshare\(\)/,/^}/' \"\$1\" | grep -qF '|| true' && awk '/^_opk_ddev_reshare\(\)/,/^}/' \"\$1\" | grep -qF 'return 0'" _ "$FUNC"
check "reshare: no heal without a project in the cwd" \
    sh -c "awk '/^_opk_ddev_reshare\(\)/,/^}/' \"\$1\" | grep -qF '[ -d \"\$PWD/.ddev\" ]'" _ "$FUNC"
check "reshare: exported for bash children (issue #18)" \
    sh -c "grep -q 'export -f ddev _opk_hosts_hint _opk_bootstrap_hint _opk_ddev_reshare' \"\$1\"" _ "$FUNC"
check "reshare: browser arm has no separate heal — the ddev() tail covers it (issue #279)" \
    sh -c "! awk '/_opk_ddev_browser\(\)/,/^}/' \"\$1\" | grep -q _opk_ddev_reshare" _ "$FUNC"

# --- 7d-2. dev-owned flag wiring (issue #149, finding 1) --------------------------
# The ddev() function must flag a fresh project right after `ddev config`
# (dev-owned mode on): mode-gated, flagged-gated, never prompting for a
# sudo password (-n), never failing the ddev command.
DFH=$(mktemp -d)
mkdir -p "$DFH/proj/.ddev"
printf 'name: dfh\ntype: typo3\ndocroot: public\n' >"$DFH/proj/.ddev/config.yaml"
check "devowned hook: _opk_devowned_flag calls the helper's flag mode" \
    sh -c "awk '/^_opk_devowned_flag\(\)/,/^}/' \"\$1\" | grep -q -- '--opk-devowned-flag'" _ "$FUNC"
check "devowned hook: flag write runs after ddev config" \
    sh -c "grep -q 'config) _opk_devowned_flag' \"\$1\"" _ "$FUNC"
check "devowned hook: gated on the dev-owned mode (ddev_devowned_enabled)" \
    sh -c "awk '/^_opk_devowned_flag\(\)/,/^}/' \"\$1\" | grep -q 'ddev_devowned_enabled || return 0'" _ "$FUNC"
check "devowned hook: already-flagged projects skip the sudo call" \
    sh -c "awk '/^_opk_devowned_flag\(\)/,/^}/' \"\$1\" | grep -q 'ddev_devowned_flagged \"\$PWD\" && return 0'" _ "$FUNC"
check "devowned hook: sudo never prompts (-n, V22 pattern)" \
    sh -c "awk '/^_opk_devowned_flag\(\)/,/^}/' \"\$1\" | grep -qF 'sudo -n -u opencode'" _ "$FUNC"
check "devowned hook: best-effort — never fails the ddev command" \
    sh -c "awk '/^_opk_devowned_flag\(\)/,/^}/' \"\$1\" | grep -qF '|| true'" _ "$FUNC"
check "devowned hook: exported for bash children (issue #18)" \
    sh -c "grep -q '_opk_ddev_reshare _opk_devowned_flag' \"\$1\"" _ "$FUNC"
# Functional mode pins, hermetic via OPK_DDEV_HANDOVER_LIB (0.0.46a F2):
# the old check sourced the FIXED deployed lib path — on CI (no deployed
# kit) the lib gate returned before the mode gate ever ran, so "mode off
# is a no-op" passed vacuously (the review's F2). The stub libs record
# gate reach inside the project dir: mode ON must reach the flagged gate
# (the step right before the sudo call), mode OFF must stop BEFORE it.
# The sudo exec itself uses the absolute /usr/bin/sudo — not
# PATH-interceptable (see section 3a) — and stays static-pinned above.
DFH2=$(mktemp -d)
mkdir -p "$DFH2/on/.ddev" "$DFH2/off/.ddev"
printf 'name: fh1\ntype: typo3\n' >"$DFH2/on/.ddev/config.yaml"
printf 'name: fh2\ntype: typo3\n' >"$DFH2/off/.ddev/config.yaml"
cat >"$DFH2/on-lib.sh" <<'STUB'
# 0.0.46a F2 stub: mode ON, unflagged — the flagged probe records that
# execution passed the mode gate (reached the pre-sudo gating).
ddev_devowned_enabled() { return 0; }
ddev_devowned_flagged() { : >> "$1/.opk-f2-flaggate"; return 1; }
STUB
cat >"$DFH2/off-lib.sh" <<'STUB'
# 0.0.46a F2 stub: mode OFF — the flagged probe must NEVER run (its
# marker file appearing means the mode gate was skipped or reordered).
ddev_devowned_enabled() { return 1; }
ddev_devowned_flagged() { : >> "$1/.opk-f2-flaggate"; return 1; }
STUB
check "devowned hook: mode on reaches the flag write gating (hermetic, 0.0.46a F2)" \
    env OPK_DDEV_HANDOVER_LIB="$DFH2/on-lib.sh" sh -c "cd \"\$2/on\" && . \"\$1\" && _opk_devowned_flag && test -f .opk-f2-flaggate" _ "$FUNC" "$DFH2"
check "devowned hook: mode off stops before the flag gate (hermetic, 0.0.46a F2)" \
    env OPK_DDEV_HANDOVER_LIB="$DFH2/off-lib.sh" sh -c "cd \"\$2/off\" && . \"\$1\" && _opk_devowned_flag && ! test -e .opk-f2-flaggate && ! grep -q '^disable_settings_management:' .ddev/config.yaml" _ "$FUNC" "$DFH2"
check "devowned hook: the lib path is stubbable via OPK_DDEV_HANDOVER_LIB (0.0.46a F2)" \
    sh -c "grep -qF '_opk_dhl=\"\${OPK_DDEV_HANDOVER_LIB:-/usr/local/lib/opencode-permissions-kit/sh/ddev-handover.sh}\"' \"\$1\"" _ "$FUNC"
rm -rf "$DFH" "$DFH2"

# --- 7d-3. reshare detection (issue #149, finding 2) ------------------------------
# Agent-side ddev runs (real binary, no hook) leave .ddev entries with the
# ACL mask capped below g+w — the dev's git pull then fails. Detection:
# ddev_reshare_needed <dir> <user> finds user-owned entries without
# group-write (pruned like the heal itself); status.sh surfaces it.
RN=$(mktemp -d)
mkdir -p "$RN/proj/.ddev/commands" "$RN/proj/.ddev/db_snapshots"
printf 'cfg\n' >"$RN/proj/.ddev/config.yaml"
printf 'cmd\n' >"$RN/proj/.ddev/commands/hostcmd"
printf 'snap\n' >"$RN/proj/.ddev/db_snapshots/db.sql.gz"
chmod 2775 "$RN/proj/.ddev" "$RN/proj/.ddev/commands"
chmod 664 "$RN/proj/.ddev/config.yaml" "$RN/proj/.ddev/commands/hostcmd"
chmod 755 "$RN/proj/.ddev/db_snapshots"
chmod 644 "$RN/proj/.ddev/db_snapshots/db.sql.gz"
RN_U=$(id -un)
check "reshare detect: conforming tree needs no heal" \
    sh -c ". \"\$1\" && ! ddev_reshare_needed \"\$2/proj/.ddev\" \"\$3\"" _ "$HANDOVER" "$RN" "$RN_U"
chmod 644 "$RN/proj/.ddev/config.yaml"
check "reshare detect: capped opencode-owned file is detected" \
    sh -c ". \"\$1\" && ddev_reshare_needed \"\$2/proj/.ddev\" \"\$3\"" _ "$HANDOVER" "$RN" "$RN_U"
chmod 664 "$RN/proj/.ddev/config.yaml"
chmod 755 "$RN/proj/.ddev/commands"
check "reshare detect: capped directory is detected" \
    sh -c ". \"\$1\" && ddev_reshare_needed \"\$2/proj/.ddev\" \"\$3\"" _ "$HANDOVER" "$RN" "$RN_U"
chmod 2775 "$RN/proj/.ddev/commands"
check "reshare detect: pruned db_snapshots does not count (heal parity)" \
    sh -c ". \"\$1\" && ! ddev_reshare_needed \"\$2/proj/.ddev\" \"\$3\"" _ "$HANDOVER" "$RN" "$RN_U"
# 0.0.46a F6: description corrected — this pins find's UNKNOWN-user
# error path (stderr swallowed, output empty, `!` holds); the -user
# filter's exclusivity against a live second user is real but would
# need root to construct and stays unpinned.
check "reshare detect: unknown user yields no findings (find -user error path; live second-user exclusivity needs root)" \
    sh -c ". \"\$1\" && ! ddev_reshare_needed \"\$2/proj/.ddev\" \"opencode-no-such-user-424242\"" _ "$HANDOVER" "$RN"
check "reshare detect: missing dir is a clean no-need" \
    sh -c ". \"\$1\" && ! ddev_reshare_needed \"\$2/does-not-exist\" \"\$3\"" _ "$HANDOVER" "$RN" "$RN_U"
check "reshare detect: status.sh wires ddev_reshare_needed per project root" \
    sh -c "grep -q 'ddev_reshare_needed' \"\$1\" && grep -qF 'ui_kv_warn \"ddev share\"' \"\$1\"" _ "$STATUS"
check "reshare detect: status.sh prints the opk ensure-shared one-command fix (issue #159)" \
    sh -c "grep -qF 'opk ensure-shared \\\"\$_st_d\\\"' \"\$1\"" _ "$STATUS"
check "reshare detect: status.sh fix line is the short form only (no raw helper call)" \
    sh -c "! grep -q -- '--opk-ensure-shared' \"\$1\"" _ "$STATUS"
check "reshare detect: status.sh resolves the lib checkout-first (0.0.46a F4)" \
    sh -c "grep -qF '_st_dhl=\"\$(cd \"\$(dirname \"\$0\")\" && pwd)/../sh/ddev-handover.sh\"' \"\$1\" && grep -qF '[ -f \"\$_st_dhl\" ] || _st_dhl=\"\$LIBDIR/sh/ddev-handover.sh\"' \"\$1\"" _ "$STATUS"
check "reshare detect: status fix names 'any ddev command' — every invocation heals (0.0.46a F7 wording inverted by issue #279)" \
    sh -c "grep -q 'any ddev command in this project' \"\$1\" && ! grep -q 'tree-creating ddev command (config/get/start/restart' \"\$1\"" _ "$STATUS"
check "reshare detect: warn line names the general cause, not only agent runs (issue #279)" \
    sh -c "grep -q 'group-write missing (a ddev run without the following heal)' \"\$1\" && ! grep -q 'agent-side ddev run' \"\$1\"" _ "$STATUS"
rm -rf "$RN"

# --- 7d-4. version-probe neutrality (issue #279) ----------------------------------
# ddev chmods .ddev/commands/** to 0755 on every IN-PROJECT invocation
# (--version included — the command-list walk runs in init()). The kit's
# version probes (status.sh, update.sh) call bin/ddev-as-opencode
# --version with the CALLER's cwd; from a project directory that re-broke
# the tree a heal had just fixed. The helper therefore execs --version
# from the agent home — pinned functionally: a PATH-stub ddev records
# the cwd it was exec'd with, the pin asserts it is the agent home
# (getent-derived, exactly how the helper computes it), not the project
# dir. The cd is best-effort by design (a failed cd keeps the inherited
# cwd so the probe still runs); that arm stays comment-level — forcing
# it would need a home-less passwd entry, outside the unit sandbox
# (pin-cost budget).
VN=$(mktemp -d)
mkdir -p "$VN/proj/.ddev/commands/host" "$VN/bin"
printf 'cmd\n' >"$VN/proj/.ddev/commands/host/hostcmd"
printf 'OPENCODE_USER=%s\n' "$(id -un)" >"$VN/install.conf"
cat >"$VN/bin/ddev" <<'STUB'
#!/bin/sh
# 279 stub: record the process cwd the real ddev would run with — that
# cwd decides whether ddev's command walk chmods the project's files.
printf 'cwd=%s args=%s\n' "$PWD" "$*" >>"$VN_MARKER"
echo "ddev version v9.9.9"
STUB
chmod 755 "$VN/bin/ddev"
VN_MARKER="$VN/marker" OPK_INSTALL_CONF="$VN/install.conf" PATH="$VN/bin:$PATH" \
    sh -c 'cd "$1/proj" && "$2" --version >/dev/null 2>&1' _ "$VN" "$HELPER"
VN_CWD=$(sed -n 's/^cwd=\(.*\) args=--version$/\1/p' "$VN/marker" 2>/dev/null)
check "version probe: --version execs ddev from the agent home, not the project (issue #279)" \
    sh -c "[ -n \"\$1\" ] && [ \"\$1\" = \"\$2\" ]" _ "$VN_CWD" "$(getent passwd "$(id -un)" | cut -d: -f6)"
check "version probe: the neutral cd is gated on --version alone (other args keep the cwd)" \
    sh -c "grep -qF '[ \"\$#\" -eq 1 ] && [ \"\$1\" = \"--version\" ]' \"\$1\"" _ "$HELPER"
rm -rf "$VN"

# --- 7d-5. round-a fix-wave pins (pr-309 a: M1+S1+Q1, M2, Q3, M3, M4, S3) ---------
# The a(review) findings, fixed in the a(fix) wave — each fix carries its
# pin; the deliberate not-dones (M3 suggestion texts, S2, Q2) carry their
# dispositions in round b's comment instead.
E2ELIB="$SCRIPT_DIR/../e2e/lib.sh"
check "fix a M1: status tier-1 probe runs ddev from / — no caller cwd" \
    sh -c 'grep -qF "(cd / && \"\$_st_bin\" --version)" "$1" && ! grep -qF "[ -n \"\$_st_bin\" ] && _st_ver=" "$1"' _ "$STATUS"
check "fix a M2: e2e dump hooked in e2e_cleanup (every exit path), not e2e_finish" \
    sh -c "awk '/^e2e_cleanup\(\)/,/^}/' \"\$1\" | grep -q e2e_dump_container && ! awk '/^e2e_finish\(\)/,/^}/' \"\$1\" | grep -q e2e_dump_container" _ "$E2ELIB"
check "fix a M2: the dump precedes the cleanup rm (evidence before destruction)" \
    sh -c "awk '/^e2e_cleanup\(\)/,/^}/' \"\$1\" | awk '/e2e_dump_container/{if (d == 0) d = NR} /^[[:space:]]*docker rm -f/{if (r == 0) r = NR} END{exit !(d > 0 && r > 0 && d < r)}'" _ "$E2ELIB"
check "fix a S3: symlinks stripped from the dump (docker cp preserves them)" \
    sh -c "awk '/^_e2e_dump_strip\(\)/,/^}/' \"\$1\" | grep -q -- '-type l -delete'" _ "$E2ELIB"
check "fix a Q3: install.sh probes the ddev version subcommand from /" \
    sh -c 'grep -q "env HOME=\"\$DEV_HOME\" sh -c .cd / && exec" "$1" && ! grep -q "\"\$DDEV_BIN_DEV\" version" "$1"' _ "$INSTALL"
check "fix a M3: config.sh probes the ddev version from /" \
    sh -c 'grep -qF "(cd / && \"\$_cand_bin\" version)" "$1" && ! grep -qF "\"\$_cand_bin\" version 2>/dev/null" "$1"' _ "$CONFIG"
check "fix a M4: opk usage tells the generalized story, not 'agent-side'" \
    sh -c "grep -q 'a .ddev tree a' \"\$1\" && ! grep -q 'agent-side ddev run' \"\$1\"" _ "$KIT"

# --- 7d-6. round-b fix-wave pins (pr-309 b: M2, M3, M4, S3, S1, M1-rider) ---------
# The b(review) findings, fixed in the b(fix) wave. Class sweep evidence
# lives in the b(fix) commit message: every non-root `sudo -u ... ddev`
# shape in files/ now runs through a neutral-cwd choke point (helper,
# handover runner, migrate runner/imports) or is root-only and inert
# (verified round b: root never walks on any 1.25.x).
HANDOVERSH="$FILES/opencode-permissions-kit-lib/sh/ddev-handover.sh"
MIGRATESH="$FILES/opencode-permissions-kit-lib/sh/ddev-migrate.sh"
check "fix b M2: handover runner hops through a neutral cwd" \
    sh -c "awk '/^_ddev_handover_run_as\(\)/,/^}/' \"\$1\" | grep -qF \"sh -c 'cd / && exec\"" _ "$HANDOVERSH"
check "fix b M3: migrate runner hops through a neutral cwd" \
    sh -c "awk '/^_ddev_migrate_run_as\(\)/,/^}/' \"\$1\" | grep -qF \"sh -c 'cd / && exec\"" _ "$MIGRATESH"
# Comment-strip rider (#261, the #244 g W1 class — pr-00320 b F1):
# commented-out invocations stop counting; full-line comments only
# (#244 h W6 residual). The combined pattern is the old pipeline's
# accept set (both terms on one line): the two live imports.
_m3i_n="$(sed 's/^[[:space:]]*#.*$//' "$MIGRATESH" | grep -c 'cd / && exec.*migrate-import' || true)"
check "fix b M3: both inline import invocations hop through a neutral cwd (import sites: $_m3i_n of 2)" \
    [ "$_m3i_n" = 2 ]
check "fix b M1: install.sh root probe from / (consistency)" \
    sh -c 'grep -qF "(cd / && \"\$DDEV_BIN\" version)" "$1" && ! grep -qF "\"\$DDEV_BIN\" version 2>/dev/null" "$1"' _ "$INSTALL"
check "fix b M1: update.sh root fallback probe from / (consistency)" \
    sh -c 'grep -qF "(cd / && \"\$_ddev_bin\" --version)" "$1" && ! grep -qF "\"\$_ddev_bin\" --version 2>/dev/null" "$1"' _ "$UPDATE"
check "fix b M4/S3: dump gate sees the exit status, not only counted failures" \
    sh -c "awk '/^e2e_cleanup\(\)/,/^}/' \"\$1\" | grep -qF '_ecc_rc=\$?' && awk '/^e2e_cleanup\(\)/,/^}/' \"\$1\" | grep -qF '\"\$_ecc_rc\" -ne 0'" _ "$E2ELIB"
check "fix b M4: dump fires before the keep branches (red --debug runs get evidence)" \
    sh -c "awk '/^e2e_cleanup\(\)/,/^}/' \"\$1\" | awk '/e2e_dump_container/{if (d == 0) d = NR} /E2E_KEEP.*keeping container/{if (k == 0) k = NR} END{exit !(d > 0 && k > 0 && d < k)}'" _ "$E2ELIB"
check "fix b M4: E2E_KEEP stays dump-free by design" \
    sh -c "awk '/^e2e_cleanup\(\)/,/^}/' \"\$1\" | grep -qF '[ \"\${E2E_KEEP:-0}\" != \"1\" ]'" _ "$E2ELIB"
check "fix b S1: strip notice is conditional — success and failure arms both named" \
    sh -c "awk '/^_e2e_dump_strip\(\)/,/^}/' \"\$1\" | grep -q 'symlinks stripped' && awk '/^_e2e_dump_strip\(\)/,/^}/' \"\$1\" | grep -q 'strip failed'" _ "$E2ELIB"
# Functional L1 pin for the strip failure path (find untraversable subdir):
# extract _e2e_dump_strip, run it against a scratch dump with a 000-dir and
# a surviving symlink — the WARNING arm must fire and the link must survive.
# c-L3 (pr-309 c): root-guarded fixture — root traverses chmod-000 via
# CAP_DAC_OVERRIDE, the strip would succeed and the pin red spuriously.
# Unit suites are user-run by policy; the skip is disclosed, never hidden.
if [ "$(id -u)" = "0" ]; then
    echo "  note: fix-b-S1 functional pin skipped under root (find traverses chmod-000)"
else
    BS1=$(mktemp -d)
    mkdir -p "$BS1/tmp/locked" "$BS1/bin"
    ln -s /etc/passwd "$BS1/tmp/locked/planted-link"
    ln -s /etc/passwd "$BS1/tmp/top-link"
    printf 'x\n' >"$BS1/tmp/file.txt"
    chmod 000 "$BS1/tmp/locked"
    ln -s /usr/bin/find "$BS1/bin/find"
    ln -s /usr/bin/echo "$BS1/bin/echo"
    BS1_OUT=$(awk '/^_e2e_dump_strip\(\)/,/^}/' "$E2ELIB" >"$BS1/fn.sh" && cd "$BS1" && PATH="$BS1/bin:$PATH" sh -c '. ./fn.sh 2>/dev/null; _e2e_dump_strip "$1"' sh "$BS1/tmp" 2>/dev/null)
    # find -delete still removes the top-level links it can reach (order is
    # directory-dependent) — the honest survival assertion is the link INSIDE
    # the untraversable dir; re-chmod first so test -L can see it again.
    chmod 755 "$BS1/tmp/locked"
    check "fix b S1: partial strip warns and never claims clean (functional, L1)" \
        sh -c "printf '%s\n' \"\$1\" | grep -q 'strip failed' && ! printf '%s\n' \"\$1\" | grep -q 'symlinks stripped)' && test -L \"\$2/tmp/locked/planted-link\"" _ "$BS1_OUT" "$BS1"
    rm -rf "$BS1"
fi

# --- 7d-7. round-c fix-wave pins (pr-309 c: M1, S1, L1, L2) ------------------------
# The c(review) findings, fixed in the c(fix) wave; the class sweep with
# variable-indirection resolution is recorded in the c(fix) commit message.
HOSTSSH="$FILES/opencode-permissions-kit-lib/sh/ddev-hosts.sh"
check "fix c M1: ddev-hosts helper hops through a neutral cwd (sudo + direct arms)" \
    sh -c "awk '/^_dha_hostname\(\)/,/^}/' \"\$1\" | grep -qF \"sh -c 'cd / && exec\" && awk '/^_dha_hostname\(\)/,/^}/' \"\$1\" | grep -qF '(cd / && \"\$dha_bin\" hostname'" _ "$HOSTSSH"
# Comment-strip rider (#261, the #244 g W1 class — pr-00320 c F1):
# a commented-out twin invocation stops counting; full-line comments
# only (#244 h W6 residual).
_dha_n="$(sed 's/^[[:space:]]*#.*$//' "$HOSTSSH" | grep -cF '"$dha_bin" hostname' || true)"
check "fix c M1: no bare ddev-hosts invocation remains outside the helper (invocation sites: $_dha_n of 2)" \
    [ "$_dha_n" = 2 ]
check "fix c S1: ddev-migrate absolutizes a relative dump-dir" \
    sh -c "grep -qF 'dm_dir=\"\$PWD/\$dm_dir\"' \"\$1\" && grep -qF 'case \"\$dm_dir\" in' \"\$1\"" _ "$MIGRATESH"
check "fix d M1: empty-dir refusal precedes the absolutization (guard hoisted)" \
    sh -c 'g=$(grep -nF "[ -n \"\$dm_dir\" ] ||" "$1" | head -1 | cut -d: -f1); c=$(grep -nF "case \"\$dm_dir\" in" "$1" | head -1 | cut -d: -f1); test -n "$g" && test -n "$c" && test "$g" -lt "$c"' _ "$MIGRATESH"
check "fix c L1: container guard precedes the dumps mkdir" \
    sh -c "awk '/^e2e_dump_container\(\)/,/^}/' \"\$1\" | grep -vE '^[[:space:]]*#' | awk '/E2E_CONTAINER/{if (g == 0) g = NR} /mkdir -p/{if (m == 0) m = NR} END{exit !(g > 0 && m > 0 && g < m)}'" _ "$E2ELIB"
check "fix c L2: the rc capture is the FIRST statement of the trap handler" \
    sh -c "awk '/^e2e_cleanup\(\)/,/^}/' \"\$1\" | grep -vE '^[[:space:]]*#' | grep -n . | sed -n '2p' | grep -qF '_ecc_rc=\$?'" _ "$E2ELIB"

# --- 7e. dev-owned mode (internal/records/ddev-dev-owned-projects.md) ------------------
# Mode on: the scan writes disable_settings_management: true; a FLAGGED
# project (mode-written or repo-committed) keeps settings dirs + root as
# the developer's (handback), unflagged projects keep the handover.
# Functional as the CURRENT user (oc-user == dev-user == tester), so the
# observable differences are the MODE (2755 handover vs 2775 handback),
# the flag line in .ddev/config.yaml, and the echo output.
DWORK=$(mktemp -d)

# flag writer: inserts iff absent, idempotent, comment on its own lines
mkdir -p "$DWORK/fw/.ddev"
printf 'name: fw\ntype: typo3\n' >"$DWORK/fw/.ddev/config.yaml"
check "flag writer: writes the key when absent" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null && grep -qx 'disable_settings_management: true' \"\$2/.ddev/config.yaml\"" _ "$HANDOVER" "$DWORK/fw"
check "flag writer: idempotent (no duplicate key)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; [ \"\$(grep -c '^disable_settings_management:' \"\$2/.ddev/config.yaml\")\" = 1 ]" _ "$HANDOVER" "$DWORK/fw"
# pre-existing explicit false stays untouched (repo decided otherwise)
mkdir -p "$DWORK/fw2/.ddev"
printf 'name: fw2\ndisable_settings_management: false\n' >"$DWORK/fw2/.ddev/config.yaml"
check "flag writer: pre-existing key (false) left untouched" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; grep -qx 'disable_settings_management: false' \"\$2/.ddev/config.yaml\" && [ \"\$(grep -c '^disable_settings_management:' \"\$2/.ddev/config.yaml\")\" = 1 ]" _ "$HANDOVER" "$DWORK/fw2"
# missing config.yaml: silent no-op
mkdir -p "$DWORK/fw3/.ddev"
check "flag writer: missing config.yaml is a no-op" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" && test ! -f \"\$2/.ddev/config.yaml\"" _ "$HANDOVER" "$DWORK/fw3"
# no trailing newline: the inserted key must still land on its own line
mkdir -p "$DWORK/fw4/.ddev"
printf 'name: fw4' >"$DWORK/fw4/.ddev/config.yaml"
check "flag writer: survives a file without trailing newline" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null && grep -qx 'disable_settings_management: true' \"\$2/.ddev/config.yaml\"" _ "$HANDOVER" "$DWORK/fw4"

# insertion point (issue #28): below corepack_enable, below type: as
# fallback, at the top as last resort — never appended after ddev's
# trailing comment block. Blank line before and after, never doubled.
mkdir -p "$DWORK/fw5/.ddev"
printf 'name: fw5\ntype: typo3\ncorepack_enable: false\n\n# Key features of DDEV config.yaml:\n# name: <projectname>\n' >"$DWORK/fw5/.ddev/config.yaml"
check "flag writer: inserts after corepack_enable (issue #28)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; _a=\$(grep -n '^corepack_enable:' \"\$2/.ddev/config.yaml\" | cut -d: -f1); _b=\$(grep -n '^disable_settings_management: true' \"\$2/.ddev/config.yaml\" | cut -d: -f1); [ \"\$((_b - _a))\" = 4 ]" _ "$HANDOVER" "$DWORK/fw5"
check "flag writer: blank line after the inserted block (no doubling)" \
    sh -c "[ \"\$(grep -c '^\$' \"\$1/.ddev/config.yaml\")\" = 2 ]" _ "$DWORK/fw5"
mkdir -p "$DWORK/fw6/.ddev"
printf 'name: fw6\ntype: typo3\ndocroot: public\n' >"$DWORK/fw6/.ddev/config.yaml"
check "flag writer: type fallback when corepack_enable is absent (issue #28)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; _a=\$(grep -n '^type:' \"\$2/.ddev/config.yaml\" | cut -d: -f1); _b=\$(grep -n '^disable_settings_management: true' \"\$2/.ddev/config.yaml\" | cut -d: -f1); [ \"\$((_b - _a))\" = 4 ]" _ "$HANDOVER" "$DWORK/fw6"
mkdir -p "$DWORK/fw7/.ddev"
printf 'webimage: config.yaml\nhooks:\n  post-start:\n    - exec: \"ls\"\n' >"$DWORK/fw7/.ddev/config.yaml"
check "flag writer: no anchor key at all -> top of the file (issue #28)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; [ \"\$(grep -n '^disable_settings_management: true' \"\$2/.ddev/config.yaml\" | cut -d: -f1)\" = 3 ] && [ \"\$(grep -c '^\$' \"\$2/.ddev/config.yaml\")\" = 1 ]" _ "$HANDOVER" "$DWORK/fw7"

# 0.0.46a F1: the opencode-uid caller (ddev-as-opencode
# --opk-devowned-flag) can actually fail the write — a clone whose
# config.yaml arrived 0644 dev-owned. The failure must be loud and
# honest: a WARNING, never the unconditional success note (and never
# silence). Owner-mode bits block the CURRENT non-root user — the same
# self-blocking fixture shape as the chmod 007 cwd in section 2b.
mkdir -p "$DWORK/f1a/.ddev"
printf 'name: f1a\ntype: typo3\n' >"$DWORK/f1a/.ddev/config.yaml"
chmod 444 "$DWORK/f1a/.ddev/config.yaml"
F1A_RC=0
F1A_OUT=$(sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\"" _ "$HANDOVER" "$DWORK/f1a" 2>&1) || F1A_RC=$?
check "flag writer: unwritable config.yaml warns instead of lying (0.0.46a F1)" \
    sh -c "[ \"\$2\" = 0 ] && printf '%s\n' \"\$1\" | grep -q 'dev-owned flag write to .* failed' && ! printf '%s\n' \"\$1\" | grep -q 'flag written'" _ "$F1A_OUT" "$F1A_RC"
check "flag writer: failed write never claims NOT written — ENOSPC may leave a partial file (0.0.46b W2)" \
    sh -c "! printf '%s\n' \"\$1\" | grep -q 'flag NOT'" _ "$F1A_OUT"
check "flag writer: retry hint names the explicit paths, not the stamp-skipped scan (0.0.46b W2)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'sudo opk config handover' && printf '%s\n' \"\$1\" | grep -q 'opk update --refresh' && ! printf '%s\n' \"\$1\" | grep -q 'next root-run scan retries'" _ "$F1A_OUT"
F1A_RETRY="sudo opk config handover \"$DWORK/f1a\""
check "flag writer: retry hint is verbatim-runnable — prints the root's path (0.0.46c C1)" \
    sh -c "printf '%s\n' \"\$1\" | grep -F \"\$2\"" _ "$F1A_OUT" "$F1A_RETRY"
chmod 644 "$DWORK/f1a/.ddev/config.yaml"
mkdir -p "$DWORK/f1b/.ddev"
printf 'name: f1b\ntype: typo3\n' >"$DWORK/f1b/.ddev/config.yaml"
chmod 555 "$DWORK/f1b/.ddev"
F1B_RC=0
F1B_OUT=$(sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\"" _ "$HANDOVER" "$DWORK/f1b" 2>&1) || F1B_RC=$?
check "flag writer: unwritable .ddev dir warns (mktemp branch, 0.0.46a F1)" \
    sh -c "[ \"\$2\" = 0 ] && printf '%s\n' \"\$1\" | grep -q 'not writable (mktemp failed)' && ! printf '%s\n' \"\$1\" | grep -q 'flag written'" _ "$F1B_OUT" "$F1B_RC"
chmod 755 "$DWORK/f1b/.ddev"

# flagged detection
check "flagged detection: true" \
    sh -c ". \"\$1\" && ddev_devowned_flagged \"\$2\"" _ "$HANDOVER" "$DWORK/fw"
check "flagged detection: false" \
    sh -c ". \"\$1\" && if ddev_devowned_flagged \"\$2\"; then exit 1; fi" _ "$HANDOVER" "$DWORK/fw2"

# scan: mode ON + unflagged typo3 -> flag written + handback (2775)
mkdir -p "$DWORK/on/proj/.ddev" "$DWORK/on/proj/config/system"
printf 'type: typo3\n' >"$DWORK/on/proj/.ddev/config.yaml"
echo "db" >"$DWORK/on/proj/config/system/settings.php"
chmod 2770 "$DWORK/on/proj"
# testdata pruning (issue #29): a checkout of ddev's own repository ships
# .ddev dirs under cmd/pkg testdata — fixtures, not projects. The scan
# must neither chown them nor write dev-owned flags into their configs.
mkdir -p "$DWORK/on/ddev-checkout/pkg/ddevapp/testdata/TestHooksMerge/proj/.ddev"
printf 'name: p\ntype: php\n' >"$DWORK/on/ddev-checkout/pkg/ddevapp/testdata/TestHooksMerge/proj/.ddev/config.yaml"
DON_OUT=$(DDEV_DEV_OWNED=true sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\"" _ "$HANDOVER" "$DWORK/on" 2>/dev/null || true)
check "scan mode on: writes the dev-owned flag" \
    sh -c "grep -qx 'disable_settings_management: true' \"\$1/.ddev/config.yaml\"" _ "$DWORK/on/proj"
check "scan mode on: .ddev inside testdata/ is skipped entirely (issue #29)" \
    sh -c "! grep -q 'disable_settings_management:' \"\$1/ddev-checkout/pkg/ddevapp/testdata/TestHooksMerge/proj/.ddev/config.yaml\" && ! printf '%s\n' \"\$2\" | grep -q 'testdata'" _ "$DWORK/on" "$DON_OUT"
check "scan mode on: undetected typo3 root stays dev-owned 2775 (no bootstrap handover)" \
    sh -c "test \"\$(stat -c %a \"\$1\")\" = 2775" _ "$DWORK/on/proj"
check "scan mode on: settings dir stays with the developer" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'dev-owned handback: .*config/system'" _ "$DON_OUT"
check "scan mode on: .ddev still handed over" \
    sh -c "printf '%s\n' \"\$1\" | grep -q '.ddev handover:'" _ "$DON_OUT"

# scan: mode OFF + repo-committed flag -> handback anyway, no flag write
mkdir -p "$DWORK/off/proj/.ddev" "$DWORK/off/proj/config/system"
printf 'type: typo3\ndisable_settings_management: true\n' >"$DWORK/off/proj/.ddev/config.yaml"
chmod 2755 "$DWORK/off/proj"
DOFF_OUT=$(DDEV_DEV_OWNED=false sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\"" _ "$HANDOVER" "$DWORK/off" 2>/dev/null || true)
check "scan mode off: committed flag honored (handback, not handover)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'dev-owned handback:' && ! printf '%s\n' \"\$1\" | grep -q 'dev-owned flag written'" _ "$DOFF_OUT"
check "scan mode off: flagged root handed back to 2775" \
    sh -c "test \"\$(stat -c %a \"\$1\")\" = 2775" _ "$DWORK/off/proj"

# scan: mode OFF + unflagged -> today's handover (root 2755)
mkdir -p "$DWORK/old/proj/.ddev"
printf 'type: typo3\n' >"$DWORK/old/proj/.ddev/config.yaml"
chmod 2775 "$DWORK/old/proj"
DDEV_DEV_OWNED=false sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\"" _ "$HANDOVER" "$DWORK/old" >/dev/null 2>&1 || true
check "scan mode off + unflagged: bootstrap root still handed over (2755)" \
    sh -c "test \"\$(stat -c %a \"\$1\")\" = 2755" _ "$DWORK/old/proj"
rm -rf "$DWORK"
unset DDEV_DEV_OWNED

# --- 7f. scan performance (issue #112) ---------------------------------------------
# Three optimizations for large project trees: .git pruned from the scan,
# a top-inode fast path that skips the recursive chown/chmod pair on
# already-conforming trees, and scan-skip stamps that let a plain
# `opk update` skip roots whose last full pass still matches.

# .git prune: a .ddev inside .git/ is never a project (ddev finds .ddev
# by walking UP from the cwd — no ddev command runs inside .git/).
rm -rf "${HWORK:?}/gitprune"
mkdir -p "$HWORK/gitprune/proj/.ddev" "$HWORK/gitprune/proj/.git/modules/sub/.ddev"
GITPRUNE_OUT=$(sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\"" _ "$HANDOVER" "$HWORK/gitprune" 2>/dev/null || true)
check "handover scan skips .ddev inside .git/ (issue #112)" \
    sh -c "! printf '%s\n' \"\$1\" | grep -q '.git/modules'" _ "$GITPRUNE_OUT"
check "handover scan still hands over the project .ddev next to .git/" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'proj/.ddev'" _ "$GITPRUNE_OUT"
rm -rf "${HWORK:?}/gitprune"

# Top-inode fast path: the FIRST pass chowns/chmods and echoes; the
# second (everything conforms: user:group + group-write on the top
# inode) stays silent for the recursive pairs. Detected typo3 (vendor
# marker) so the project-root logic stays silent too (no dev user).
rm -rf "${HWORK:?}/fastpath"
mkdir -p "$HWORK/fastpath/proj/.ddev" "$HWORK/fastpath/proj/config/system" \
    "$HWORK/fastpath/proj/vendor/typo3/cms-core/Classes/Information"
printf 'type: typo3\n' >"$HWORK/fastpath/proj/.ddev/config.yaml"
touch "$HWORK/fastpath/proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php"
FP1=$(sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\"" _ "$HANDOVER" "$HWORK/fastpath" 2>/dev/null || true)
check "fast path: first pass hands .ddev over" \
    sh -c "printf '%s\n' \"\$1\" | grep -q '.ddev handover:'" _ "$FP1"
check "fast path: first pass hands the settings dir over" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'ddev settings handover: .*config/system'" _ "$FP1"
# 0.0.40a F2: rc must be captured, not swallowed — "no handover echoes"
# would also hold for a run that died before printing (|| true alone
# made the silence assertion pass vacuously).
FP2_RC=0
FP2=$(sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\"" _ "$HANDOVER" "$HWORK/fastpath" 2>/dev/null) || FP2_RC=$?
check "fast path: second pass completes (rc 0)" \
    sh -c '[ "$1" -eq 0 ]' _ "$FP2_RC"
check "fast path: second pass is silent for .ddev + settings dirs" \
    sh -c "! printf '%s\n' \"\$1\" | grep -qe '.ddev handover:' -e 'ddev settings handover:'" _ "$FP2"
# ...and the skip is a MODE fact, not luck: the top inode carries g+w now.
check "fast path: .ddev top inode is group-writable after the pass" \
    sh -c "case \"\$(stat -c %A \"\$1\")\" in ?????w*) exit 0 ;; *) exit 1 ;; esac" _ "$HWORK/fastpath/proj/.ddev"
# Mid-tree drift (a developer-owned file inside the conformed tree) is
# invisible to the probe by design — explicit repair paths cover it.
rm -rf "${HWORK:?}/fastpath"

# --- 7f-2. exec-time parent-swap race on the .ddev pair (#215, #211 a F1 class) --
# The chmod half of the .ddev pair dereferences its operand: a PARENT
# directory swapped for a symlink between find's scan and the pair
# redirects root chmod -R g+w outside the scan root while every leaf
# gate passes (the leaf is a real dir). Deterministic seam — the a F1
# pin pattern from tests/unit/test-fs-baseline.sh: a PATH-stubbed find
# runs the REAL find into a buffer, swaps the project dir for a symlink
# to a victim tree OUTSIDE the scan root, and only then releases the
# scan stream (the buffer is the barrier — a stream-through stub races
# the consumer loop). The component walk must skip the WHOLE
# iteration; a deleted or voided walk chmods through the link (victim
# 620) and the pins go red. The slashed scan root (#211 b W7 shape) rides in
# the same drive: an unnormalized root voids the walk's prefix match
# the same way. The victim carries config.yaml + a settings dir so the
# drive also pins the iteration TAIL (ddev_handover_project) never
# acting through the swapped parent.
RACE=$(mktemp -d)
RACESTUB=$(mktemp -d)
mkdir -p "$RACE/scan/proj/.ddev" "$RACE/scan/proj/config/system" \
    "$RACE/victim/.ddev" "$RACE/victim/config/system"
printf 'type: typo3\n' >"$RACE/scan/proj/.ddev/config.yaml"
printf 'type: typo3\n' >"$RACE/victim/.ddev/config.yaml"
printf 'victim-secret\n' >"$RACE/victim/.ddev/secret"
printf 'victim-settings\n' >"$RACE/victim/config/system/settings.php"
chmod 600 "$RACE/victim/.ddev/secret" "$RACE/victim/config/system/settings.php"
# No g+w on the victim .ddev top inode: this drive pins the PAIR half —
# a conforming top inode would take the fast path and skip the pair
# even with no gate at all (the pin would go green for the wrong
# reason, the b W6 class). The conforming-victim drives below cover the
# fast-path branch (pr-00234 a W1).
chmod 755 "$RACE/victim/.ddev"
cat >"$RACESTUB/find" <<EOF
#!/bin/sh
# Buffer the real find's output, perform the swap, THEN release the
# scan stream — a stream-through stub races the consumer loop (the
# loop can run the whole iteration while the stub is still between
# find and mv; measured ~8% flake before the buffer). The temp file is
# the a F1 barrier, moved into the stub because ddev_handover_root
# streams find directly into the while loop.
_out=\$(mktemp)
"$(command -v find)" "\$@" > "\$_out"
_rc=\$?
if [ -d "$RACE/scan/proj" ] && [ ! -L "$RACE/scan/proj" ]; then
    mv "$RACE/scan/proj" "$RACE/scan/moved-away"
    ln -s "$RACE/victim" "$RACE/scan/proj"
fi
cat "\$_out"
rm -f "\$_out"
exit \$_rc
EOF
chmod +x "$RACESTUB/find"
RACE_RC=0
RACE_OUT=$(PATH="$RACESTUB:$PATH" sh -c \
    '. "$1" && ddev_handover_root "$2" "$(id -un)" "$(id -gn)"' \
    _ "$HANDOVER" "$RACE/scan/" 2>&1) || RACE_RC=$?
if [ -d "$RACE/scan/moved-away/.ddev" ] && [ -L "$RACE/scan/proj" ]; then
    pass "race fixture: parent swapped between scan and the pair (seam fired)"
else
    fail "race fixture: parent swapped between scan and the pair (seam fired)"
fi
assert_eq "parent-swap: victim .ddev keeps its mode (component walk skips, #215)" "600" \
    "$(stat -c %a "$RACE/victim/.ddev/secret")"
assert_eq "parent-swap: victim settings dir untouched — iteration tail skipped too (#215)" "600" \
    "$(stat -c %a "$RACE/victim/config/system/settings.php")"
assert_eq "parent-swap: skip is not a failure (rc 0, #215)" "0" "$RACE_RC"
case "$RACE_OUT" in
    *"warn: skipping .ddev handover"*)
        pass "parent-swap: the skip announces itself with the reason (#215)"
        ;;
    *) fail "parent-swap: the skip must announce itself (got: $RACE_OUT) (#215)" ;;
esac
case "$RACE_OUT" in
    *".ddev handover:"* | *"ddev settings handover:"*)
        fail "parent-swap: no success echo over a skipped operand (#215)"
        ;;
    *) pass "parent-swap: no success echo over a skipped operand (#215)" ;;
esac
rm -rf "${RACE:?}" "${RACESTUB:?}"

# Spaced-component variant (the 82cdd4a lesson from fs-baseline): the
# happy-path drives cannot catch a walk regression that stops SKIPPING,
# and a word-splitting rewrite of the prefix-peeling would chmod through
# the link on spaced names while unspaced paths stay green. Spaces in
# every swapped component; same deterministic seam.
RACESP=$(mktemp -d)
RACESPS=$(mktemp -d)
mkdir -p "$RACESP/scan/pro j/.ddev" "$RACESP/vic tim/.ddev"
printf 'type: typo3\n' >"$RACESP/scan/pro j/.ddev/config.yaml"
printf 'spaced-victim\n' >"$RACESP/vic tim/.ddev/has space.txt"
chmod 600 "$RACESP/vic tim/.ddev/has space.txt"
chmod 755 "$RACESP/vic tim/.ddev"
cat >"$RACESPS/find" <<EOF
#!/bin/sh
# Same buffered seam as the plain drive: swap first, then release the
# scan stream — never let the consumer loop lap the swap.
_out=\$(mktemp)
"$(command -v find)" "\$@" > "\$_out"
_rc=\$?
if [ -d "$RACESP/scan/pro j" ] && [ ! -L "$RACESP/scan/pro j" ]; then
    mv "$RACESP/scan/pro j" "$RACESP/scan/moved away"
    ln -s "$RACESP/vic tim" "$RACESP/scan/pro j"
fi
cat "\$_out"
rm -f "\$_out"
exit \$_rc
EOF
chmod +x "$RACESPS/find"
RACESP_RC=0
PATH="$RACESPS:$PATH" sh -c \
    '. "$1" && ddev_handover_root "$2" "$(id -un)" "$(id -gn)"' \
    _ "$HANDOVER" "$RACESP/scan" >/dev/null 2>&1 || RACESP_RC=$?
if [ -d "$RACESP/scan/moved away/.ddev" ] && [ -L "$RACESP/scan/pro j" ]; then
    pass "spaces race: seam fired (parent swapped between scan and the pair)"
else
    fail "spaces race: seam fired (parent swapped between scan and the pair)"
fi
assert_eq "spaces race: victim outside the tree keeps its mode (walk skips on spaced components)" "600" \
    "$(stat -c %a "$RACESP/vic tim/.ddev/has space.txt")"
assert_eq "spaces race: skip is not a failure (rc 0)" "0" "$RACESP_RC"
rm -rf "${RACESP:?}" "${RACESPS:?}"

# Conforming-victim drive (pr-00234 a W1 / a W2): the victim's .ddev
# top inode ALREADY conforms (current user:group + g+w — mkdir/chmod
# as the running user; the steady state of every handed-over project),
# so the pre-fix gate inside the else branch never fired: the fast
# path took the PAIR out, but the iteration TAIL still acted through
# the swapped parent — the settings pairs' resolved containment
# canonicalizes both sides through the swap and cannot catch a
# relocated project root. The hoisted walk must skip the WHOLE
# iteration. The victim's settings dir is non-conforming (755 top
# inode, 600 files): without the hoist, the forward settings pair
# chmod -R g+w's it through the link (620) — the pin discriminates
# through exactly the W1 mechanism.
RACEC=$(mktemp -d)
RACECT=$(mktemp -d)
mkdir -p "$RACEC/scan/proj/.ddev" "$RACEC/victim/.ddev" \
    "$RACEC/victim/config/system"
printf 'type: typo3\n' >"$RACEC/scan/proj/.ddev/config.yaml"
printf 'type: typo3\n' >"$RACEC/victim/.ddev/config.yaml"
printf 'victim-secret\n' >"$RACEC/victim/.ddev/secret"
printf 'victim-settings\n' >"$RACEC/victim/config/system/settings.php"
chmod 600 "$RACEC/victim/.ddev/secret" "$RACEC/victim/config/system/settings.php"
chmod 775 "$RACEC/victim/.ddev"
chmod 755 "$RACEC/victim/config/system"
cat >"$RACECT/find" <<EOF
#!/bin/sh
# Same buffered seam as the plain drive: swap the parent AFTER the
# real find classified it, BEFORE the stream reaches the consumer.
_out=\$(mktemp)
"$(command -v find)" "\$@" > "\$_out"
_rc=\$?
if [ -d "$RACEC/scan/proj" ] && [ ! -L "$RACEC/scan/proj" ]; then
    mv "$RACEC/scan/proj" "$RACEC/scan/moved-away"
    ln -s "$RACEC/victim" "$RACEC/scan/proj"
fi
cat "\$_out"
rm -f "\$_out"
exit \$_rc
EOF
chmod +x "$RACECT/find"
RACEC_RC=0
RACEC_OUT=$(PATH="$RACECT:$PATH" sh -c \
    '. "$1" && ddev_handover_root "$2" "$(id -un)" "$(id -gn)"' \
    _ "$HANDOVER" "$RACEC/scan" 2>&1) || RACEC_RC=$?
if [ -d "$RACEC/scan/moved-away/.ddev" ] && [ -L "$RACEC/scan/proj" ]; then
    pass "conforming race: seam fired (parent swapped before the fast-path branch)"
else
    fail "conforming race: seam fired (parent swapped before the fast-path branch)"
fi
assert_eq "conforming race: victim settings untouched — tail skipped on the fast-path branch (#234 a W1)" "600" \
    "$(stat -c %a "$RACEC/victim/config/system/settings.php")"
assert_eq "conforming race: skip is not a failure (rc 0)" "0" "$RACEC_RC"
case "$RACEC_OUT" in
    *"warn: skipping .ddev handover"*)
        pass "conforming race: the skip announces itself (#234 a W1)"
        ;;
    *) fail "conforming race: the skip must announce itself (got: $RACEC_OUT) (#234 a W1)" ;;
esac
case "$RACEC_OUT" in
    *"ddev settings handover:"*)
        fail "conforming race: no settings echo over a skipped operand (#234 a W1)"
        ;;
    *) pass "conforming race: no settings echo over a skipped operand (#234 a W1)" ;;
esac
rm -rf "${RACEC:?}" "${RACECT:?}"

# Flag-write half (pr-00234 a W2): the raced drives so far run dev-owned
# mode OFF — the "flag write included" claim of the whole-iteration
# skip was unexercisable. With DDEV_DEV_OWNED=true the flag write must
# not reach the victim's committed config.yaml through the swapped
# parent (project unflagged: without the walk, ddev_devowned_flag
# writes the key through the link and echoes success).
RACEF=$(mktemp -d)
RACEFT=$(mktemp -d)
mkdir -p "$RACEF/scan/proj/.ddev" "$RACEF/victim/.ddev" \
    "$RACEF/victim/config/system"
printf 'type: typo3\n' >"$RACEF/scan/proj/.ddev/config.yaml"
printf 'type: typo3\n' >"$RACEF/victim/.ddev/config.yaml"
printf 'victim-settings\n' >"$RACEF/victim/config/system/settings.php"
chmod 600 "$RACEF/victim/config/system/settings.php"
chmod 775 "$RACEF/victim/.ddev"
chmod 755 "$RACEF/victim/config/system"
cat >"$RACEFT/find" <<EOF
#!/bin/sh
_out=\$(mktemp)
"$(command -v find)" "\$@" > "\$_out"
_rc=\$?
if [ -d "$RACEF/scan/proj" ] && [ ! -L "$RACEF/scan/proj" ]; then
    mv "$RACEF/scan/proj" "$RACEF/scan/moved-away"
    ln -s "$RACEF/victim" "$RACEF/scan/proj"
fi
cat "\$_out"
rm -f "\$_out"
exit \$_rc
EOF
chmod +x "$RACEFT/find"
RACEF_RC=0
RACEF_OUT=$(DDEV_DEV_OWNED=true PATH="$RACEFT:$PATH" sh -c \
    '. "$1" && ddev_handover_root "$2" "$(id -un)" "$(id -gn)"' \
    _ "$HANDOVER" "$RACEF/scan" 2>&1) || RACEF_RC=$?
if [ -d "$RACEF/scan/moved-away/.ddev" ] && [ -L "$RACEF/scan/proj" ]; then
    pass "flag race: seam fired (parent swapped before the flag write)"
else
    fail "flag race: seam fired (parent swapped before the flag write)"
fi
if grep -q '^disable_settings_management:' "$RACEF/victim/.ddev/config.yaml"; then
    fail "flag race: the dev-owned flag must not be written through a swapped parent (#234 a W1)"
else
    pass "flag race: the dev-owned flag must not be written through a swapped parent (#234 a W1)"
fi
case "$RACEF_OUT" in
    *"dev-owned flag written:"*)
        fail "flag race: no flag-written echo over a skipped operand (#234 a W1)"
        ;;
    *) pass "flag race: no flag-written echo over a skipped operand (#234 a W1)" ;;
esac
assert_eq "flag race: victim settings untouched too (whole iteration skipped)" "600" \
    "$(stat -c %a "$RACEF/victim/config/system/settings.php")"
assert_eq "flag race: skip is not a failure (rc 0)" "0" "$RACEF_RC"
rm -rf "${RACEF:?}" "${RACEFT:?}"

# Walk contract edges (pr-00234 a W4): a scan root of '/' refuses LOUD
# like _fsb_pass — rc 1 plus a warn on stderr (the failure path
# executes, observed the way a caller would). An operand equal to the
# scan root returns 0 silently — nothing below the root to walk, the
# documented contract edge (the caller's leaf gate covers the operand).
DCS_RC=0
DCS_OUT=$(sh -c '. "$1" && _ddev_components_sane "/" "/tmp"' _ "$HANDOVER" 2>&1) || DCS_RC=$?
assert_eq "walk: root '/' refuses loud — rc 1 (#234 a W4)" "1" "$DCS_RC"
case "$DCS_OUT" in
    *"refusing scan root '/'"*)
        pass "walk: the '/' refusal announces itself (#234 a W4)"
        ;;
    *) fail "walk: the '/' refusal must announce itself (got: $DCS_OUT) (#234 a W4)" ;;
esac
DCS2_RC=0
DCS2_OUT=$(sh -c '. "$1" && _ddev_components_sane "/tmp" "/tmp"' _ "$HANDOVER" 2>&1) || DCS2_RC=$?
assert_eq "walk: operand == scan root returns 0 (contract edge, #234 a W4)" "0" "$DCS2_RC"
assert_eq "walk: operand == scan root stays silent (contract edge, #234 a W4)" "" "$DCS2_OUT"

# Scan-skip stamps: write -> valid; any field mismatch -> invalid; a
# cksum filename collision must not validate a different root.
_112_dir=$(mktemp -d)
OPK_HANDOVER_STAMP_DIR="$_112_dir/stamps"
export OPK_HANDOVER_STAMP_DIR
mkdir -p "$_112_dir/stamps"
# 0.0.40b: guarded like the tamper below (set -e) — a failed stamp write
# must not abort the suite before the rm -rf/unset cleanup.
sh -c ". \"\$1\" && ddev_handover_stamp_write \"\$2\" \"\$3\" \"\$4\"" _ "$HANDOVER" "/srv/projects" ocuser ocgroup || true
check "stamp: written into the override dir" \
    sh -c "ls \"\$1\"/*.stamp >/dev/null 2>&1" _ "$_112_dir/stamps"
check "stamp: valid for the same root/user/group" \
    sh -c ". \"\$1\" && ddev_handover_stamp_valid \"/srv/projects\" ocuser ocgroup" _ "$HANDOVER"
check "stamp: invalid for a different user" \
    sh -c ". \"\$1\" && if ddev_handover_stamp_valid \"/srv/projects\" otheruser ocgroup; then exit 1; fi" _ "$HANDOVER"
check "stamp: invalid for a different group" \
    sh -c ". \"\$1\" && if ddev_handover_stamp_valid \"/srv/projects\" ocuser othergroup; then exit 1; fi" _ "$HANDOVER"
check "stamp: invalid for a different root" \
    sh -c ". \"\$1\" && if ddev_handover_stamp_valid \"/srv/other\" ocuser ocgroup; then exit 1; fi" _ "$HANDOVER"
check "stamp: invalid when missing entirely" \
    sh -c ". \"\$1\" && if ddev_handover_stamp_valid \"/srv/never-scanned\" ocuser ocgroup; then exit 1; fi" _ "$HANDOVER"
check "stamp: dev-owned toggle invalidates (mode is part of the shape)" \
    sh -c "DDEV_DEV_OWNED=true . \"\$1\" && if ddev_handover_stamp_valid \"/srv/projects\" ocuser ocgroup; then exit 1; fi" _ "$HANDOVER"
# 0.0.40a F1: the dev user (handback target) is part of the shape — a
# DEFAULT_USER re-base must invalidate, not wait for --refresh.
# (0.0.40b: guarded — same set -e cleanup rationale as above.)
sh -c ". \"\$1\" && ddev_handover_stamp_write \"\$2\" \"\$3\" \"\$4\" \"\$5\"" _ "$HANDOVER" "/srv/projects" ocuser ocgroup devuser || true
check "stamp: valid for the same dev user (4-arg shape, 0.0.40a F1)" \
    sh -c ". \"\$1\" && ddev_handover_stamp_valid \"/srv/projects\" ocuser ocgroup devuser" _ "$HANDOVER"
check "stamp: invalid for a different dev user (0.0.40a F1)" \
    sh -c ". \"\$1\" && if ddev_handover_stamp_valid \"/srv/projects\" ocuser ocgroup otherdev; then exit 1; fi" _ "$HANDOVER"
_112_stampfile=$(ls "$_112_dir/stamps"/*.stamp 2>/dev/null || true)
if [ -n "$_112_stampfile" ]; then
    # 0.0.40a F3: guarded — under the suite's set -e an unguarded sed/mv
    # failure would abort BEFORE the rm -rf/unset below, leaking the
    # exported OPK_HANDOVER_STAMP_DIR and the temp dir into later
    # sections. A failed tamper just weakens the rev check below (the
    # written-stamp checks above still gate the feature).
    sed 's/|1|/|99|/' "$_112_stampfile" >"$_112_stampfile.new" &&
        mv "$_112_stampfile.new" "$_112_stampfile" || true
fi
check "stamp: a scan-rev mismatch invalidates" \
    sh -c ". \"\$1\" && if ddev_handover_stamp_valid \"/srv/projects\" ocuser ocgroup devuser; then exit 1; fi" _ "$HANDOVER"
rm -rf "$_112_dir"
unset OPK_HANDOVER_STAMP_DIR

# Wiring: update.sh skips via the stamps (plain update only — --refresh
# forces), re-stamps after every full pass, and says how to force;
# install.sh + config.sh stamp their explicit passes too.
check "update.sh: plain-update loop gates the skip on REFRESH + stamp_valid" \
    sh -c "grep -qF '[ \"\$REFRESH\" != true ]' \"\$1\" && grep -qF 'ddev_handover_stamp_valid \"\$root\" \"\$OPENCODE_USER\" \"\$NEW_OPENCODE_GROUP\" \"\$DEFAULT_USER\"; then' \"\$1\"" _ "$UPDATE"
check "update.sh: stamps the root after the handover" \
    sh -c "grep -qF 'ddev_handover_stamp_write \"\$root\" \"\$OPENCODE_USER\" \"\$NEW_OPENCODE_GROUP\"' \"\$1\"" _ "$UPDATE"
check "update.sh: the scanning detail is printed only for roots actually scanned" \
    sh -c "grep -qF '_ho_announced=false' \"\$1\" && grep -qF 'if [ \"\$_ho_announced\" = false ]' \"\$1\"" _ "$UPDATE"
check "update.sh: skip message names both force paths" \
    sh -c "grep -q 'opk update --refresh' \"\$1\" && grep -q 'config handover' \"\$1\"" _ "$UPDATE"
check "update.sh: --refresh pass re-stamps" \
    sh -c "awk '/^    if \[ \"\\\$REFRESH\" = true \]/,/^    fi\$/' \"\$1\" | grep -q 'ddev_handover_stamp_write'" _ "$UPDATE"
check "install.sh: stamps after the install-time handover" \
    sh -c "grep -qF 'ddev_handover_stamp_write \"\$root\" \"\$OPENCODE_USER\" \"\$OPENCODE_GROUP\"' \"\$1\"" _ "$INSTALL"
# Comment-strip riders (#261, the #244 g W1 class): commented-out lines
# stop counting; full-line comments only (#244 h W6 residual).
_stampw_n="$(sed 's/^[[:space:]]*#.*$//' "$CONFIG" | grep -c "ddev_handover_stamp_write" || true)"
check "config.sh: refresh + projects add + handover re-stamp (stamp sites: $_stampw_n, need >=3)" \
    [ "$_stampw_n" -ge 3 ]
check "handover.sh: stamp dir defaults to /etc/opencode-permissions-kit/handover" \
    sh -c "grep -qF 'OPK_HANDOVER_STAMP_DIR:-/etc/opencode-permissions-kit/handover' \"\$1\"" _ "$HANDOVER"
check "handover.sh: stamp stubs fail open (valid=1) when the lib is missing" \
    sh -c "grep -qF 'ddev_handover_stamp_valid() { return 1; }' \"\$1\" && grep -qF 'ddev_handover_stamp_write() { :; }' \"\$1\"" _ "$UPDATE"

# wiring: config.sh / install.sh / status.sh / hook / kit CLI
check "config.sh dispatches ddev-settings" \
    sh -c "grep -q 'ddev-settings)' \"\$1\"" _ "$CONFIG"
check "config.sh ddev-settings has status + apply" \
    sh -c "grep -q 'ddev_settings_status' \"\$1\" && grep -q 'ddev_settings_apply' \"\$1\"" _ "$CONFIG"
check "config.sh ddev-settings re-stamps install.conf" \
    sh -c "grep -q 'update_install_conf_ddev_owned' \"\$1\"" _ "$CONFIG"
check "config.sh menu offers ddev-settings" \
    sh -c "grep -q 'ddev-settings: dev-owned projects on/off' \"\$1\"" _ "$CONFIG"
check "install.sh parses --ddev-settings" \
    sh -c "grep -q -- '--ddev-settings' \"\$1\"" _ "$INSTALL"
check "install.sh defaults to dev-owned (DDEV_DEV_OWNED=true)" \
    sh -c "grep -qF 'DDEV_DEV_OWNED=true' \"\$1\"" _ "$INSTALL"
check "install.sh stamps DDEV_DEV_OWNED into install.conf" \
    sh -c "grep -qF 'DDEV_DEV_OWNED=\$DDEV_DEV_OWNED' \"\$1\"" _ "$INSTALL"
_dsetq_n="$(sed 's/^[[:space:]]*#.*$//' "$INSTALL" | grep -c 'ddev settings management? (dev-owned projects)' || true)"
check "install.sh asks the ddev-settings question (standard + advanced; question sites: $_dsetq_n, need >=2)" \
    [ "$_dsetq_n" -ge 2 ]
check "status.sh reports the ddev settings mode" \
    sh -c "grep -q 'ddev settings' \"\$1\"" _ "$STATUS"
check "hook hint mentions the dev-owned effect" \
    sh -c "grep -q 'disable_settings_management:' \"\$1\"" _ "$FUNC"
check "kit CLI usage documents ddev-settings" \
    sh -c "grep -q 'ddev-settings on|off|status' \"\$1\"" _ "$KIT"
check "install.sh passes DEFAULT_USER to the handover" \
    sh -c "grep -qF 'ddev_handover_root \"\$root\" \"\$OPENCODE_USER\" \"\$OPENCODE_GROUP\" \"\$DEFAULT_USER\"' \"\$1\"" _ "$INSTALL"
check "update.sh passes DEFAULT_USER to the handover" \
    sh -c "grep -qF 'ddev_handover_root \"\$root\" \"\$OPENCODE_USER\" \"\$NEW_OPENCODE_GROUP\" \"\$DEFAULT_USER\"' \"\$1\"" _ "$UPDATE"
check "config.sh passes DEFAULT_USER to the handover" \
    sh -c "grep -qF 'ddev_handover_root \"\$p\" \"\$OPENCODE_USER\" \"\$OPENCODE_GROUP\" \"\$DEFAULT_USER\"' \"\$1\"" _ "$CONFIG"
rm -rf "$HWORK"

# --- 8. status.sh reporting ----------------------------------------------------
check "status.sh reports ddev-as-opencode state" \
    sh -c "grep -q 'ddev-as-opencode' \"\$1\"" _ "$STATUS"

# --- 8b. config.sh ui.sh fallback (0.0.45c C9) ----------------------------------
# The body calls ui_have/ui_atten (projects list) and ui_confirm/ui_menu/
# ui_ask (interactive flows); the fallback block must define them all —
# the old block died rc 127 ("ui_have: not found") at the first list on
# an install whose library predates ui.sh, contradicting its own
# "keeps config.sh working" comment.
_cfgfb=$(sed -n '/^    ui_info() { echo "  info     $1"; }$/,/^    UI_GREEN=/p' "$CONFIG")
if [ -n "$_cfgfb" ]; then
    if printf '%s\n' "$_cfgfb" | grep -q 'ui_have()' &&
        printf '%s\n' "$_cfgfb" | grep -q 'ui_atten()' &&
        printf '%s\n' "$_cfgfb" | grep -q 'ui_confirm()' &&
        printf '%s\n' "$_cfgfb" | grep -q 'ui_menu()' &&
        printf '%s\n' "$_cfgfb" | grep -q 'ui_ask()'; then
        pass "config.sh ui.sh fallback defines every helper the body calls (C9)"
    else
        fail "config.sh ui.sh fallback defines every helper the body calls (C9)"
    fi
else
    fail "config.sh ui.sh fallback block extractable (C9)"
fi

# --- 9. Makefile + CI wiring ---------------------------------------------------
check "Makefile has a test-ddev-as-opencode target in the test: list" \
    sh -c "grep -q 'test-ddev-as-opencode' \"\$1\"" _ "$MAKEFILE"
check "test-unit.yml run step mentions the new test" \
    sh -c "grep -q 'test-ddev-as-opencode.sh' \"\$1\"" _ "$TEST_CI"
check "bin/ddev-as-opencode is executed by path (git 100755)" \
    sh -c '[ "$(git -C "$2" ls-files -s -- files/opencode-permissions-kit-lib/bin/ddev-as-opencode | cut -d" " -f1)" = "100755" ]' _ x "$SCRIPT_DIR/../.."

# --- Summary -------------------------------------------------------------------
echo ""
echo "========================================"
echo "  ${GREEN}Passed: $passed${NC}"
# describe probe rides sudo -n like every probe (0.0.44b W16/V22)
grep -q -- 'sudo -n -u opencode' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/ddev-terminal.sh" &&
    pass "describe probe uses sudo -n (V22)" ||
    fail "describe probe uses sudo -n (V22)"
# --- #211 a F14: handover lines honest about pair failures -----------------------
# The root-run handover pairs were `|| true`-silent with unconditional
# success echoes — a partial handover (EPERM, immutable flag) reported
# as done. The pairs stay best-effort (self-heal on the next rescan)
# but the line now tells the truth. Extract the REAL site-1 block and
# drive it with stubbed chmod/chown; sites 2/3 are wiring-grepped.
_f14_block="$(sed -n '/^            _dhr_ok=true$/,/^            fi$/p' "$HANDOVER")"
if [ -n "$_f14_block" ]; then
    pass "dhr handover pair block extractable (#211 a F14)"
    _f14_run() {
        F14MODE="$1" sh -c '
            dhr_d="/x/dir"; dhr_user=oc; dhr_group=g
            chmod() { [ "$F14MODE" = chmodfail ] && return 1; return 0; }
            chown() { [ "$F14MODE" = chownfail ] && return 1; return 0; }
            eval "$1"
        ' sh "$_f14_block" 2>&1
    }
    _out=$(_f14_run ok) || true
    case "$_out" in
        *".ddev handover: /x/dir -> oc"*) pass "healthy pair: success line (#211 a F14)" ;;
        *) fail "healthy pair: success line (got: $_out)" ;;
    esac
    _out=$(_f14_run chmodfail) || true
    case "$_out" in
        *"warn: .ddev handover incomplete"*) pass "chmod failure: warn, no success line (#211 a F14)" ;;
        *) fail "chmod failure: warn (got: $_out)" ;;
    esac
    _out=$(_f14_run chownfail) || true
    case "$_out" in
        *"warn: .ddev handover incomplete"*) pass "chown failure: warn, no success line (#211 a F14)" ;;
        *) fail "chown failure: warn (got: $_out)" ;;
    esac
else
    fail "dhr handover pair block extractable (#211 a F14)"
fi
grep -q 'warn: dev-owned handback incomplete' "$HANDOVER" &&
    pass "dhb site honest too (#211 a F14 sweep)" ||
    fail "dhb site honest too (#211 a F14 sweep)"
grep -q 'warn: ddev settings handover incomplete' "$HANDOVER" &&
    pass "dhp site honest too (#211 a F14 sweep)" ||
    fail "dhp site honest too (#211 a F14 sweep)"

# --- #211 b W9: the four single-inode pairs the a F14 sweep missed ----------------
# Same shape, one inode: chown+chmod || true with an unconditional
# success echo (project-root handback/handover x3, dev-owned root-inode
# handback). Extract the typo3-bootstrap site and drive it; the other
# three are wiring-grepped by their warn lines.
_w9_block="$(sed -n '/^                _dhq_ok=true$/,/^                fi$/p' "$HANDOVER" | sed -n '1,10p')"
if [ -n "$_w9_block" ] && printf '%s' "$_w9_block" | grep -q 'project-root handover:'; then
    pass "typo3-bootstrap pair block extractable (#211 b W9)"
    _w9_run() {
        W9MODE="$1" sh -c '
            dhq_proj=/x/p; dhq_user=oc; dhq_group=g
            chmod() { [ "$W9MODE" = chmodfail ] && return 1; return 0; }
            chown() { [ "$W9MODE" = chownfail ] && return 1; return 0; }
            eval "$1"
        ' sh "$_w9_block" 2>&1
    }
    _out=$(_w9_run ok) || true
    case "$_out" in
        *"project-root handover: /x/p -> oc"*) pass "healthy pair: success line (#211 b W9)" ;;
        *) fail "healthy pair: success line (got: $_out)" ;;
    esac
    _out=$(_w9_run chmodfail) || true
    case "$_out" in
        *"warn: project-root handover incomplete"*) pass "chmod failure: warn, no success line (#211 b W9)" ;;
        *) fail "chmod failure: warn (got: $_out)" ;;
    esac
    _out=$(_w9_run chownfail) || true
    case "$_out" in
        *"warn: project-root handover incomplete"*) pass "chown failure: warn, no success line (#211 b W9)" ;;
        *) fail "chown failure: warn (got: $_out)" ;;
    esac
else
    fail "typo3-bootstrap pair block extractable (#211 b W9)"
fi
# Guarded count (#260, the #244 f W1 class; #244 h W4): zero matches
# (a warn-wording change in the shipped script) aborted the suite under
# set -e before the -ge 3 FAIL could record.
# Comment-strip rider (#261, the #244 g W1 class): commented-out warn
# lines must not count; full-line comments only (#244 h W6 residual).
_n_w9=$(sed 's/^[[:space:]]*#.*$//' "$HANDOVER" | grep -c 'warn: project-root hand\(back\|over\) incomplete' || true)
[ "$_n_w9" -ge 3 ] &&
    pass "all three project-root warn lines present (#211 b W9)" ||
    fail "all three project-root warn lines present (got $_n_w9) (#211 b W9)"
grep -q 'warn: dev-owned handback incomplete for $dhb_proj (root inode' "$HANDOVER" &&
    pass "root-inode handback warn line present (#211 b W9)" ||
    fail "root-inode handback warn line present (#211 b W9)"

# #285 pin-of-the-pin: the handler-before-resolution order pins walk
# comment-stripped copies -- commenting out a whole handler block
# (disable-by-edit: doc comment through its fi) must flip the pin RED.
# Executed on scratch copies; the unsabotaged controls are the order
# pins above (green every suite run).
CB285=$(mktemp -d)
for _h in --opk-ensure-shared --opk-devowned-flag; do
    sed "/${_h}/,/^fi\$/ s/^/#/" "$HELPER" >"$CB285/helper-$_h"
    if sed 's/^[[:space:]]*#.*$//' "$CB285/helper-$_h" |
        awk -v pat="$_h" '$0 ~ pat {h=NR} /DDEV=""/{d=NR} END{exit !(h>0 && d>0 && h<d)}'; then
        fail "#285: order pin green with the $_h handler commented out (comment-blind)"
    else
        pass "#285: order pin reds with the $_h handler commented out"
    fi
done
rm -rf "${CB285:?}"

# (#328 a A1) probe-hardening pin: a QUOTED mktemp receiver must not
# dodge the completeness probe -- the original ERE required =( adjacent
# and CB285="$(mktemp -d)" slipped past it (executed failure path: a
# planted quoted receiver in a scratch copy of this file must redden
# the probe, with the message naming the plant).
_orc_plant="$TMPDIR/recv-probe-copy.$$.sh"
cp -- "$(readlink -f "$0")" "$_orc_plant"
printf '%s\n' 'QUOTEDPLANT="$(mktemp -d)"' >>"$_orc_plant"
if _opk_recv_check "$_orc_plant" 2>"$TMPDIR/recv-probe-err.$$"; then
    fail "receiver completeness: quoted mktemp receiver invisible to the probe (#328 a A1)"
else
    if grep -qF 'QUOTEDPLANT' "$TMPDIR/recv-probe-err.$$"; then
        pass "receiver completeness: quoted mktemp receiver caught and named (#328 a A1)"
    else
        fail "receiver completeness reds but does not name the quoted plant (#328 a A1)"
    fi
fi
rm -f -- "$_orc_plant" "${TMPDIR:?}/recv-probe-err.$$"

if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
