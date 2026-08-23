#!/bin/sh
# Unit tests for the "ddev always runs as the opencode user" feature
# (DDEV-WORKING §7): bin/ddev-as-opencode (sudoers helper) +
# ddev-as-opencode.sh (sourced `ddev()` shell function).
# Runs against the repo files as the CURRENT user — no root, no real
# opencode user required. Verifies:
#   - the helper refuses any non-opencode caller (exit 1)
#   - the helper's ddev resolution / env / exec logic (static)
#   - the function file sources cleanly, defines `ddev()`, and the
#     already-opencode branch execs the REAL ddev (no recursion)
#   - no reference to the removed legacy bin/ddev shim anywhere
#   - wiring: sudoers rule, install.sh/update.sh fetch+deploy+hook,
#     config.sh / migrate-denies.sh .ddev handover, status.sh reporting,
#     Makefile target, CI workflow chmod lists + test step
# Run: sh tests/test-ddev-as-opencode.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FILES="$SCRIPT_DIR/../files"
HELPER="$FILES/opencode-permissions-kit-lib/bin/ddev-as-opencode"
FUNC="$FILES/opencode-permissions-kit-lib/ddev-as-opencode.sh"
TEMPLATE="$FILES/opencode.jsonc"
SUDOERS="$FILES/sudoers.template"
INSTALL="$FILES/install.sh"
UPDATE="$FILES/update.sh"
CONFIG="$FILES/config.sh"
KIT="$FILES/opencode-permissions-kit-lib/kit"
HANDOVER="$FILES/opencode-permissions-kit-lib/ddev-handover.sh"
# Hermetic dev-owned checks: never read this machine's real install.conf
# (ddev_devowned_enabled falls back to the stamp) — point it at nothing.
OPK_INSTALL_CONF="/nonexistent-opk-test-install.conf"
export OPK_INSTALL_CONF
STATUS="$FILES/status.sh"
MAKEFILE="$SCRIPT_DIR/../Makefile"
TEST_CI="$SCRIPT_DIR/../.github/workflows/test.yml"
E2E_CI="$SCRIPT_DIR/../.github/workflows/e2e.yml"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

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
trap 'rm -rf "$TMPDIR"' EXIT

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
    sh -c "grep -q 'export HOME=\"/home/\$OPENCODE_USER\"' \"\$1\"" _ "$HELPER"
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

# --- 3. function file: sourcing + both branches -------------------------------
# Fixture: a fake ddev on PATH so the already-opencode branch runs something
# observable instead of the (absent) real ddev.
mkdir -p "$TMPDIR/bin"
cat > "$TMPDIR/bin/ddev" <<'FAKE'
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
)
assert_eq "already-opencode branch runs the real ddev (no sudo, no recursion)" \
    "REAL_DDEV_RAN:start web" "$RESULT"
check "function execs the kit's sudoers helper for the developer" \
    sh -c "grep -q 'sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode' \"\$1\"" _ "$FUNC"
check "function uses 'command ddev' in the opencode branch" \
    sh -c "grep -q 'command ddev' \"\$1\"" _ "$FUNC"

# --- 3a. launch special case (issue #20) ---------------------------------------
# `ddev launch` computes the URL AS OPENCODE via the sudoers helper with
# DDEV_DEBUG=true (ddev's launch script then prints "FULLURL <url>" instead
# of opening a browser) and only the browser open runs as the developer —
# as the developer ddev cannot see the rootless daemon and would run its
# internal `ddev start` on every launch. Static checks (the arm calls the
# absolute /usr/bin/sudo — not interceptable in unit tests; the e2e suite
# covers the full chain).
check "launch arm computes the URL as opencode via the helper (issue #20)" \
    sh -c "grep -qF 'DDEV_DEBUG=true /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode' \"\$1\"" _ "$FUNC"
check "launch arm extracts the FULLURL line (ddev debug contract)" \
    sh -c "grep -qF \"s/^FULLURL //p\" \"\$1\"" _ "$FUNC"
check "FULLURL transport lines are filtered from the visible output" \
    sh -c "grep -qF \"grep -v '^FULLURL ' >&2\" \"\$1\"" _ "$FUNC"
check "launch arm opens the URL with the developer's interop (explorer.exe/xdg-open)" \
    sh -c "grep -q 'explorer.exe' \"\$1\" && grep -q 'xdg-open' \"\$1\"" _ "$FUNC"
check "sudoers env_keep includes DDEV_DEBUG (launch URL transport)" \
    sh -c "grep -q 'env_keep += \"DOCKER_HOST XDG_RUNTIME_DIR OPENCODE_SERVER_PASSWORD DDEV_DEBUG\"' \"\$1\"" _ "$SUDOERS"

# --- 3a-2. browser-command routing (issue #20 follow-up: mailpit/phpmyadmin) ---
# Functional against _opk_is_browser_cmd: the default list, the xhgui
# arg-awareness, and the extensible conf file (OPK_BROWSER_CMDS_CONF).
BC() { env OPK_BROWSER_CMDS_CONF="${3:-/nonexistent}" sh -c '. "$1" && if _opk_is_browser_cmd "$2" "${4:-}"; then echo yes; else echo no; fi' _ "$FUNC" "$1" "" "$2"; }
assert_eq "routing: launch is a browser command"        "yes" "$(BC launch)"
assert_eq "routing: mailpit is a browser command"       "yes" "$(BC mailpit)"
assert_eq "routing: phpmyadmin is a browser command"    "yes" "$(BC phpmyadmin)"
assert_eq "routing: adminer is a browser command"       "yes" "$(BC adminer)"
assert_eq "routing: bare xhgui is a browser command"    "yes" "$(BC xhgui)"
assert_eq "routing: xhgui launch is a browser command"  "yes" "$(BC xhgui launch)"
assert_eq "routing: xhgui status is NOT"                "no"  "$(BC xhgui status)"
assert_eq "routing: start is NOT"                       "no"  "$(BC start)"
assert_eq "routing: exec is NOT"                        "no"  "$(BC exec)"
CONF=$(mktemp)
printf '# custom browser commands\nmy-custom-tool\n\n# another\n  spaced-tool  \n' > "$CONF"
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
printf '#!/usr/bin/env sh\nexec "%s/target.sh" "$@"\n' "$VCHAIN" > "$VCHAIN/wrapper.sh"
printf '#!/usr/bin/env bash\ntype -t ddev\n' > "$VCHAIN/target.sh"
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
    python3 "$FILES/opencode-permissions-kit-lib/jsonc-parser.py" "$TEMPLATE"

# --- 5. install.sh wiring ------------------------------------------------------
check "install.sh fetches both new files (fetch_kit list)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-as-opencode.sh opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$INSTALL"
check "install.sh deploys the function file" \
    sh -c "grep -q '\"\$LIBDIR/ddev-as-opencode.sh\"' \"\$1\"" _ "$INSTALL"
check "install.sh deploys the helper (mode 755)" \
    sh -c "grep -q '\"\$LIBDIR/bin/ddev-as-opencode\"' \"\$1\"" _ "$INSTALL"
check "install.sh hooks the function into the developer rc files" \
    sh -c "grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' \"\$1\"" _ "$INSTALL"
check "install.sh hooks use the [ -f ] uninstall-safe guard" \
    sh -c "grep -qF '[ -f /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh ] && . /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh' \"\$1\"" _ "$INSTALL"
check "install.sh hands over ddev paths in the filesystem step" \
    sh -c "grep -q 'ddev_handover_root' \"\$1\"" _ "$INSTALL"

# --- 6. update.sh wiring -------------------------------------------------------
check "update.sh KIT_FILES includes both new files" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-as-opencode.sh opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$UPDATE"
check "update.sh KIT_FILES includes the handover helper" \
    sh -c "grep -q 'opencode-permissions-kit-lib/ddev-handover.sh' \"\$1\"" _ "$UPDATE"
check "update.sh deploys the function file" \
    sh -c "grep -q '\"\$LIBDIR/ddev-as-opencode.sh\"' \"\$1\"" _ "$UPDATE"
check "update.sh deploys the helper (mode 755)" \
    sh -c "grep -q '\"\$LIBDIR/bin/ddev-as-opencode\"' \"\$1\"" _ "$UPDATE"
check "update.sh heals the rc-file hook idempotently" \
    sh -c "grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' \"\$1\"" _ "$UPDATE"
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
printf 'type: typo3\n' > "$HWORK/proj/.ddev/config.yaml"
chmod 2775 "$HWORK/proj"

check "typo3 detection: no vendor, no typo3 dir => undetected" \
    sh -c ". \"\$1\" && if ddev_typo3_detected \"\$2\" .; then exit 1; fi" _ "$HANDOVER" "$HWORK/proj"

mkdir -p "$HWORK/proj/vendor/typo3/cms-core/Classes/Information"
touch "$HWORK/proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php"
check "typo3 detection: vendor Typo3Version.php => detected (composer mode)" \
    sh -c ". \"\$1\" && ddev_typo3_detected \"\$2\" ." _ "$HANDOVER" "$HWORK/proj"
rm -rf "$HWORK/proj/vendor"
check "typo3 detection: docroot typo3 dir => detected (legacy)" \
    sh -c "mkdir -p \"\$2/public/typo3\" && . \"\$1\" && ddev_typo3_detected \"\$2\" public" _ "$HANDOVER" "$HWORK/proj"
rm -rf "$HWORK/proj/public"

check "undetected typo3: root becomes 2755 (Perm==0755, ddev chmod is a no-op)" \
    sh -c ". \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2755" _ "$HANDOVER" "$HWORK/proj"

mkdir -p "$HWORK/proj/vendor/typo3/cms-core/Classes/Information"
touch "$HWORK/proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php"
check "detected typo3: root handed back with 2775 (g+w restored)" \
    sh -c ". \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2775" _ "$HANDOVER" "$HWORK/proj"

check "non-typo3 type: root untouched by the project-root handover" \
    sh -c "printf 'type: php\n' > \"\$2/.ddev/config.yaml\" && chmod 2770 \"\$2\" && . \"\$1\" && ddev_handover_project_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\" >/dev/null && test \"\$(stat -c %a \"\$2\")\" = 2770" _ "$HANDOVER" "$HWORK/proj"

check "handover_root signature carries the dev user (handback target)" \
    sh -c "grep -qF 'dhr_dev=\"\${4:-}\"' \"\$1\"" _ "$HANDOVER"

# Functional prune check: a .ddev inside vendor/ is NOT handed over (a
# shipped test fixture, not a project — issue #21 pattern), the real
# project .ddev still is.
rm -rf "$HWORK/scan"
mkdir -p "$HWORK/scan/proj/.ddev" "$HWORK/scan/proj/vendor/some/pkg/.ddev"
SCAN_OUT=$(sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\"" _ "$HANDOVER" "$HWORK/scan" 2>/dev/null || true)
check "handover scan skips .ddev inside vendor/" \
    sh -c "! printf '%s\n' \"\$1\" | grep -q 'vendor/some/pkg/.ddev'" _ "$SCAN_OUT"
check "handover scan still hands over the project .ddev" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'proj/.ddev'" _ "$SCAN_OUT"
rm -rf "$HWORK/scan"

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

# --- 7e. dev-owned mode (docs/design/ddev-dev-owned-projects.md) ------------------
# Mode on: the scan writes disable_settings_management: true; a FLAGGED
# project (mode-written or repo-committed) keeps settings dirs + root as
# the developer's (handback), unflagged projects keep the handover.
# Functional as the CURRENT user (oc-user == dev-user == tester), so the
# observable differences are the MODE (2755 handover vs 2775 handback),
# the flag line in .ddev/config.yaml, and the echo output.
DWORK=$(mktemp -d)

# flag writer: inserts iff absent, idempotent, comment on its own lines
mkdir -p "$DWORK/fw/.ddev"
printf 'name: fw\ntype: typo3\n' > "$DWORK/fw/.ddev/config.yaml"
check "flag writer: writes the key when absent" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null && grep -qx 'disable_settings_management: true' \"\$2/.ddev/config.yaml\"" _ "$HANDOVER" "$DWORK/fw"
check "flag writer: idempotent (no duplicate key)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; [ \"\$(grep -c '^disable_settings_management:' \"\$2/.ddev/config.yaml\")\" = 1 ]" _ "$HANDOVER" "$DWORK/fw"
# pre-existing explicit false stays untouched (repo decided otherwise)
mkdir -p "$DWORK/fw2/.ddev"
printf 'name: fw2\ndisable_settings_management: false\n' > "$DWORK/fw2/.ddev/config.yaml"
check "flag writer: pre-existing key (false) left untouched" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; grep -qx 'disable_settings_management: false' \"\$2/.ddev/config.yaml\" && [ \"\$(grep -c '^disable_settings_management:' \"\$2/.ddev/config.yaml\")\" = 1 ]" _ "$HANDOVER" "$DWORK/fw2"
# missing config.yaml: silent no-op
mkdir -p "$DWORK/fw3/.ddev"
check "flag writer: missing config.yaml is a no-op" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" && test ! -f \"\$2/.ddev/config.yaml\"" _ "$HANDOVER" "$DWORK/fw3"
# no trailing newline: the inserted key must still land on its own line
mkdir -p "$DWORK/fw4/.ddev"
printf 'name: fw4' > "$DWORK/fw4/.ddev/config.yaml"
check "flag writer: survives a file without trailing newline" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null && grep -qx 'disable_settings_management: true' \"\$2/.ddev/config.yaml\"" _ "$HANDOVER" "$DWORK/fw4"

# insertion point (issue #28): below corepack_enable, below type: as
# fallback, at the top as last resort — never appended after ddev's
# trailing comment block. Blank line before and after, never doubled.
mkdir -p "$DWORK/fw5/.ddev"
printf 'name: fw5\ntype: typo3\ncorepack_enable: false\n\n# Key features of DDEV config.yaml:\n# name: <projectname>\n' > "$DWORK/fw5/.ddev/config.yaml"
check "flag writer: inserts after corepack_enable (issue #28)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; _a=\$(grep -n '^corepack_enable:' \"\$2/.ddev/config.yaml\" | cut -d: -f1); _b=\$(grep -n '^disable_settings_management: true' \"\$2/.ddev/config.yaml\" | cut -d: -f1); [ \"\$((_b - _a))\" = 4 ]" _ "$HANDOVER" "$DWORK/fw5"
check "flag writer: blank line after the inserted block (no doubling)" \
    sh -c "[ \"\$(grep -c '^\$' \"\$1/.ddev/config.yaml\")\" = 2 ]" _ "$DWORK/fw5"
mkdir -p "$DWORK/fw6/.ddev"
printf 'name: fw6\ntype: typo3\ndocroot: public\n' > "$DWORK/fw6/.ddev/config.yaml"
check "flag writer: type fallback when corepack_enable is absent (issue #28)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; _a=\$(grep -n '^type:' \"\$2/.ddev/config.yaml\" | cut -d: -f1); _b=\$(grep -n '^disable_settings_management: true' \"\$2/.ddev/config.yaml\" | cut -d: -f1); [ \"\$((_b - _a))\" = 4 ]" _ "$HANDOVER" "$DWORK/fw6"
mkdir -p "$DWORK/fw7/.ddev"
printf 'webimage: config.yaml\nhooks:\n  post-start:\n    - exec: \"ls\"\n' > "$DWORK/fw7/.ddev/config.yaml"
check "flag writer: no anchor key at all -> top of the file (issue #28)" \
    sh -c ". \"\$1\" && ddev_devowned_flag \"\$2\" >/dev/null; [ \"\$(grep -n '^disable_settings_management: true' \"\$2/.ddev/config.yaml\" | cut -d: -f1)\" = 3 ] && [ \"\$(grep -c '^\$' \"\$2/.ddev/config.yaml\")\" = 1 ]" _ "$HANDOVER" "$DWORK/fw7"

# flagged detection
check "flagged detection: true" \
    sh -c ". \"\$1\" && ddev_devowned_flagged \"\$2\"" _ "$HANDOVER" "$DWORK/fw"
check "flagged detection: false" \
    sh -c ". \"\$1\" && if ddev_devowned_flagged \"\$2\"; then exit 1; fi" _ "$HANDOVER" "$DWORK/fw2"

# scan: mode ON + unflagged typo3 -> flag written + handback (2775)
mkdir -p "$DWORK/on/proj/.ddev" "$DWORK/on/proj/config/system"
printf 'type: typo3\n' > "$DWORK/on/proj/.ddev/config.yaml"
echo "db" > "$DWORK/on/proj/config/system/settings.php"
chmod 2770 "$DWORK/on/proj"
# testdata pruning (issue #29): a checkout of ddev's own repository ships
# .ddev dirs under cmd/pkg testdata — fixtures, not projects. The scan
# must neither chown them nor write dev-owned flags into their configs.
mkdir -p "$DWORK/on/ddev-checkout/pkg/ddevapp/testdata/TestHooksMerge/proj/.ddev"
printf 'name: p\ntype: php\n' > "$DWORK/on/ddev-checkout/pkg/ddevapp/testdata/TestHooksMerge/proj/.ddev/config.yaml"
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
printf 'type: typo3\ndisable_settings_management: true\n' > "$DWORK/off/proj/.ddev/config.yaml"
chmod 2755 "$DWORK/off/proj"
DOFF_OUT=$(DDEV_DEV_OWNED=false sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\"" _ "$HANDOVER" "$DWORK/off" 2>/dev/null || true)
check "scan mode off: committed flag honored (handback, not handover)" \
    sh -c "printf '%s\n' \"\$1\" | grep -q 'dev-owned handback:' && ! printf '%s\n' \"\$1\" | grep -q 'dev-owned flag written'" _ "$DOFF_OUT"
check "scan mode off: flagged root handed back to 2775" \
    sh -c "test \"\$(stat -c %a \"\$1\")\" = 2775" _ "$DWORK/off/proj"

# scan: mode OFF + unflagged -> today's handover (root 2755)
mkdir -p "$DWORK/old/proj/.ddev"
printf 'type: typo3\n' > "$DWORK/old/proj/.ddev/config.yaml"
chmod 2775 "$DWORK/old/proj"
DDEV_DEV_OWNED=false sh -c ". \"\$1\" && ddev_handover_root \"\$2\" \"\$(id -un)\" \"\$(id -gn)\" \"\$(id -un)\"" _ "$HANDOVER" "$DWORK/old" >/dev/null 2>&1 || true
check "scan mode off + unflagged: bootstrap root still handed over (2755)" \
    sh -c "test \"\$(stat -c %a \"\$1\")\" = 2755" _ "$DWORK/old/proj"
rm -rf "$DWORK"
unset DDEV_DEV_OWNED

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
check "install.sh asks the ddev-settings question (standard + advanced)" \
    sh -c "[ \"\$(grep -c 'ddev settings management? (dev-owned projects)' \"\$1\")\" -ge 2 ]" _ "$INSTALL"
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

# --- 9. Makefile + CI wiring ---------------------------------------------------
check "Makefile has a test-ddev-as-opencode target in the test: list" \
    sh -c "grep -q 'test-ddev-as-opencode' \"\$1\"" _ "$MAKEFILE"
check "test.yml chmod list + run step mention the new test" \
    sh -c "grep -q 'test-ddev-as-opencode.sh' \"\$1\"" _ "$TEST_CI"
check "test.yml chmod list includes the new lib files" \
    sh -c "grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$TEST_CI"
check "e2e.yml chmod list includes the new lib files" \
    sh -c "grep -q 'opencode-permissions-kit-lib/bin/ddev-as-opencode' \"\$1\"" _ "$E2E_CI"

# --- Summary -------------------------------------------------------------------
echo ""
echo "========================================"
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  All tests passed."
echo ""
