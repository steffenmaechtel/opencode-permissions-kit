#!/bin/sh
# Unit tests for the TUI mode display payload
# (docs/_archive/design/plan-ui-tui-opencode.md — option A' + B, spike-validated
# 2026-08-23):
#   - files/opencode-permissions-kit-lib/tui/ contains the plugin
#     (kit-mode.tsx), the danger theme, and both tui.json templates
#   - templates carry the _opencode_permissions_kit ownership marker
#   - the plugin renders the agreed strings (wording:
#     "opencode-permissions-kit Mode: no ddev/docker" /
#     "... with ddev/docker") and derives the mode from install.conf
#     live (no theme key on the opencode user — theme freedom)
#   - install.sh/update.sh deploy the payload (LIBDIR + both users,
#     only-if-absent-or-kit-written) and list it in their fetch lists
#     (test-kit-files.sh guards the rest of the list consistency)
#   - uninstall.sh mentions the leftovers
#
# Run: sh tests/unit/test-tui-mode.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TUIPLUGIN="$REPO/files/opencode-permissions-kit-lib/sh/tui-plugin.sh"
STAGEDWRITE="$REPO/files/opencode-permissions-kit-lib/sh/staged-write.sh"
TUIDIR="$REPO/files/opencode-permissions-kit-lib/tui"
PLUGIN="$TUIDIR/kit-mode.tsx"
THEME="$TUIDIR/opencode-danger.theme.json"
TUIJSON="$TUIDIR/tui.json"
TUIDANGER="$TUIDIR/tui-danger.json"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
UNINSTALL="$REPO/files/opencode-permissions-kit-lib/management/uninstall.sh"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

check() {
    desc="$1"; shift
    if "$@" >/dev/null 2>&1; then pass "$desc"; else fail "$desc"; fi
}

echo "== TUI mode display payload =="

# --- payload files ------------------------------------------------------------
check "plugin exists (kit-mode.tsx)"            test -f "$PLUGIN"
check "danger theme exists"                     test -f "$THEME"
check "opencode-user template exists (tui.json)"        test -f "$TUIJSON"
check "default-user template exists (tui-danger.json)"  test -f "$TUIDANGER"

check_no() {
    desc="$1"; shift
    if "$@" >/dev/null 2>&1; then fail "$desc"; else pass "$desc"; fi
}

check "opencode-user template carries the ownership marker" \
    grep -q '"_opencode_permissions_kit"' "$TUIJSON"
check "default-user template carries the ownership marker" \
    grep -q '"_opencode_permissions_kit"' "$TUIDANGER"
check "opencode-user template registers the plugin by absolute path" \
    grep -q '"/usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx"' "$TUIJSON"
check_no "opencode-user template sets NO theme (user theme freedom)" \
    grep -q '"theme":' "$TUIJSON"
check "default-user template sets the danger theme" \
    grep -q '"theme": "opencode-danger"' "$TUIDANGER"
check "default-user template registers the plugin (bypass warning row)" \
    grep -q '"/usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx"' "$TUIDANGER"
check "danger theme is valid JSON with a theme object" \
    python3 -c "import json,sys; d=json.load(open('$THEME')); sys.exit(0 if 'theme' in d and 'defs' in d else 1)"

# every dark/light ref in the theme resolves against defs
check "danger theme refs all resolve against defs" \
    python3 -c "
import json,sys
t=json.load(open('$THEME'))
defs=set(t['defs'])
for k,v in t['theme'].items():
    vals=v if isinstance(v,dict) else {'x':v}
    for ref in vals.values():
        if isinstance(ref,str) and not ref.startswith('#') and ref not in ('transparent','textMuted','none'):
            assert ref in defs, (k,ref)
sys.exit(0)"

# --- plugin content -----------------------------------------------------------
check "plugin renders the kit-prefixed mode string" \
    grep -qF '{prefix} Mode: {mode}' "$PLUGIN"
check "plugin reads the kit VERSION stamp from install.conf" \
    grep -q 'VERSION=' "$PLUGIN"
check "plugin renders the bypass warning string (exact wording)" \
    grep -qF 'WARNING UNSECURE (bypass of opencode-permissions-kit detected)' "$PLUGIN"
check "plugin detects the bypass via the real process user" \
    grep -q 'os.userInfo()' "$PLUGIN"
check "plugin reads OPENCODE_USER from install.conf for bypass detection" \
    grep -q 'OPENCODE_USER' "$PLUGIN"
check "bypass warning renders in the theme error color" \
    grep -q 'theme.error' "$PLUGIN"
check "plugin wording: with ddev/docker" \
    grep -q '"with ddev/docker"' "$PLUGIN"
check "plugin wording: no ddev/docker" \
    grep -q '"no ddev/docker"' "$PLUGIN"
check "plugin derives the mode live from install.conf" \
    grep -q 'CONTAINER_BACKEND' "$PLUGIN"
check "plugin registers the app_bottom slot (universal append)" \
    grep -q 'app_bottom' "$PLUGIN"
check "plugin has bottom padding (does not hug the terminal edge)" \
    grep -q 'paddingBottom' "$PLUGIN"
check "plugin render is defensive (try/catch)" \
    grep -q 'catch' "$PLUGIN"
check_no "plugin never touches the user's theme (no theme.set/install)" \
    grep -qE 'theme\.(set|install)' "$PLUGIN"

# --- install.sh wiring --------------------------------------------------------
check "install.sh fetch list includes the tui payload" \
    grep -q 'opencode-permissions-kit-lib/tui/kit-mode.tsx' "$INSTALL"
check "install.sh deploys the plugin to LIBDIR/tui (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/tui/kit-mode.tsx 644" "$2" && grep -qF "lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"" "$1"' _ "$INSTALL" "$DEPLOYLIB"
check "install.sh installs the opencode-user tui.json (marker policy)" \
    grep -q 'grep -q .\"_opencode_permissions_kit\". \"\$OC_TUI_CONF\"' "$INSTALL"
check "install.sh installs the default-user danger theme" \
    grep -q 'opencode-danger.theme.json" "$DEFAULT_THEME_DIR' "$INSTALL"
check "install.sh keeps user-managed tui.json (skip branch)" \
    grep -q 'existing $OC_TUI_CONF kept' "$INSTALL"

# --- update.sh wiring ---------------------------------------------------------
check "update.sh KIT_FILES includes the tui payload" \
    grep -q 'opencode-permissions-kit-lib/tui/kit-mode.tsx' "$UPDATE"
check "update.sh re-deploys the plugin to LIBDIR/tui (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/tui/kit-mode.tsx 644" "$2" && grep -qF "lib_deploy \"\$FILES_ROOT\" \"\$LIBDIR\"" "$1"' _ "$UPDATE" "$DEPLOYLIB"
check "update.sh refreshes the opencode-user tui.json (marker policy)" \
    grep -q 'grep -q .\"_opencode_permissions_kit\". \"\$OC_TUI_CONF\"' "$UPDATE"
check "update.sh refreshes the default-user danger theme" \
    grep -q 'opencode-danger.theme.json" "$DEFAULT_THEME_DIR' "$UPDATE"

# --- uninstall.sh hints -------------------------------------------------------
check "uninstall.sh documents the tui.json leftovers" \
    grep -q 'tui.json' "$UNINSTALL"

# --- opencode 2.x port (issue #80) ---------------------------------------------
PLUGIN2X="$TUIDIR/kit-mode-2x.tsx"
REGISTER="$REPO/files/opencode-permissions-kit-lib/py/tui-register.py"

check "2x plugin exists (kit-mode-2x.tsx)" test -f "$PLUGIN2X"
check "2x plugin uses the v2 Plugin.define entrypoint" \
    grep -q 'Plugin.define' "$PLUGIN2X"
check "2x plugin has a stable id" \
    grep -q "id: \"opencode-permissions-kit-mode\"" "$PLUGIN2X"
check "2x plugin renders the kit-prefixed mode string" \
    grep -qF '{prefix} Mode: {mode}' "$PLUGIN2X"
check "2x plugin renders the bypass warning string (exact wording)" \
    grep -qF 'WARNING UNSECURE (bypass of opencode-permissions-kit detected)' "$PLUGIN2X"
check "2x plugin wording: with ddev/docker" \
    grep -q '"with ddev/docker"' "$PLUGIN2X"
check "2x plugin wording: no ddev/docker" \
    grep -q '"no ddev/docker"' "$PLUGIN2X"
check "2x plugin detects the bypass via the real process user" \
    grep -q 'os.userInfo()' "$PLUGIN2X"
check "2x plugin derives the mode live from install.conf" \
    grep -q 'CONTAINER_BACKEND' "$PLUGIN2X"
check "2x plugin renders its own footer rows (home + app slot)" \
    grep -q '"home.footer"' "$PLUGIN2X" && grep -q '"app"' "$PLUGIN2X"
check "2x plugin keeps one row per screen (app slot renders in sessions only)" \
    grep -q 'route?.type === "session" ?' "$PLUGIN2X"
check "2x plugin session row has bottom padding (does not hug the terminal edge)" \
    grep -q 'paddingBottom={1}' "$PLUGIN2X"
check "2x plugin rows have left padding (aligned with the TUI content)" \
    grep -q 'paddingLeft={2}' "$PLUGIN2X"
check "2x plugin colors follow theme tokens (subdued/info/error)" \
    grep -q 'text.subdued' "$PLUGIN2X" && grep -q 'feedback.info.default' "$PLUGIN2X" && grep -q 'feedback.error.default' "$PLUGIN2X"
check "2x plugin render is defensive (try/catch)" \
    grep -q 'catch' "$PLUGIN2X"
check "install.sh fetch list includes the 2x plugin" \
    grep -q 'opencode-permissions-kit-lib/tui/kit-mode-2x.tsx' "$INSTALL"
check "install.sh deploys the 2x plugin to LIBDIR/tui (lib_deploy manifest)" \
    sh -c 'grep -qF "opencode-permissions-kit-lib/tui/kit-mode-2x.tsx 644" "$2" && grep -qF "lib_deploy \"\$SCRIPT_DIR\" \"\$LIBDIR\"" "$1"' _ "$INSTALL" "$DEPLOYLIB"
check "install.sh registers the 2x plugin as a discovered plugin dir (major-gated, shared helper)" \
    sh -c 'grep -qF "kit_source \"\$SCRIPT_DIR/opencode-permissions-kit-lib/sh/tui-plugin.sh\"" "$1" && grep -qF "tui_plugin_sync_user \"\$OPENCODE_MAJOR\"" "$1"' _ "$INSTALL"
check "install.sh unregisters inert cli.json path entries (2x cleanup, via sh/tui-plugin.sh)" \
    grep -qF 'tui-register.py" "$_tp_user_dir/cli.json" unregister' "$TUIPLUGIN"
check "update.sh fetch list includes the 2x plugin" \
    grep -q 'opencode-permissions-kit-lib/tui/kit-mode-2x.tsx' "$UPDATE"
check "update.sh re-registers the 2x plugin dir (major-gated, sync function)" \
    sh -c 'grep -qF "tui_plugin_sync_user \"\$_str_major\"" "$1" && grep -q "sync_tui_registration \"\$_oc_major\"" "$1" && grep -qF "sh/tui-plugin.sh" "$1"' _ "$UPDATE" \
    && grep -q 'sync_tui_registration "$_maj_after"' "$UPDATE"
check "uninstall.sh removes the 2x plugin dir and cli.json entries" \
    grep -q 'plugins/opencode-permissions-kit' "$UNINSTALL" && grep -q 'kit-mode-2x.tsx' "$UNINSTALL"

# tui-register.py functional behavior (cli.json is user-owned state)
check "tui-register.py exists" test -f "$REGISTER"
T2X=$(mktemp -d)
TUIWORK=""
check "register: creates minimal cli.json" \
    python3 "$REGISTER" "$T2X/cli.json" register /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx \
    && grep -q '"package": "/usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx"' "$T2X/cli.json"
check "register: idempotent (second run, still exactly one entry)" \
    python3 "$REGISTER" "$T2X/cli.json" register /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx \
    && [ "$(grep -c kit-mode-2x.tsx "$T2X/cli.json")" = "1" ]
printf '{\n  // user comment survives\n  "theme": {"name": "gruvbox"},\n  "plugins": ["user-pkg", {"package": "/usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx"}]\n}\n' > "$T2X/cli2.json"
check "register: JSONC input, user keys survive, legacy v1 entry dropped" \
    python3 "$REGISTER" "$T2X/cli2.json" register /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx --drop /usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx \
    && grep -q '"user-pkg"' "$T2X/cli2.json" && grep -q 'gruvbox' "$T2X/cli2.json" \
    && grep -q kit-mode-2x.tsx "$T2X/cli2.json" && ! grep -q '"package": "/usr/local/lib/opencode-permissions-kit/tui/kit-mode.tsx"' "$T2X/cli2.json"
check "unregister: removes the kit entry, keeps the rest" \
    python3 "$REGISTER" "$T2X/cli2.json" unregister /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx \
    && ! grep -q kit-mode-2x.tsx "$T2X/cli2.json" && grep -q '"user-pkg"' "$T2X/cli2.json"
echo "garbage" > "$T2X/bad.json"
check_no "register: refuses to touch unparseable cli.json" \
    python3 "$REGISTER" "$T2X/bad.json" register /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx
printf '{"plugins": "not-a-list"}' > "$T2X/bad2.json"
check_no "register: refuses non-list plugins key" \
    python3 "$REGISTER" "$T2X/bad2.json" register /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx

# 0.0.39g C2: a symlinked cli.json is user structure — stat would restore
# the TARGET's owner/mode and os.replace would destroy the link; the
# register must refuse, leaving link and target untouched.
mkdir -p "$T2X/symhome" "$T2X/dotfiles"
printf '{"existing": true}\n' > "$T2X/dotfiles/cli.json"
ln -s "$T2X/dotfiles/cli.json" "$T2X/symhome/cli.json"
check_no "register: refuses a symlinked cli.json (C2)" \
    python3 "$REGISTER" "$T2X/symhome/cli.json" register /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx
check "symlink refusal: the link itself survives" \
    test -L "$T2X/symhome/cli.json"
check "symlink refusal: the link target keeps its content" \
    sh -c '! grep -q kit-mode-2x "$1"' _ "$T2X/dotfiles/cli.json"
# no-op unregister (nothing to change) stays rc 0 — the refusal only
# applies when a write would be needed
check "unregister on a symlinked cli.json without changes is a no-op" \
    python3 "$REGISTER" "$T2X/symhome/cli.json" unregister /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx
check "no-op unregister: link still intact" \
    test -L "$T2X/symhome/cli.json"
# 0.0.39g S4: a first-run creation is owned by the config DIR's owner
# with 0644 (the dir owner is the test user here — assert the mode half)
mkdir -p "$T2X/fresh"
check "first-run register creates cli.json (S4)" \
    python3 "$REGISTER" "$T2X/fresh/cli.json" register /usr/local/lib/opencode-permissions-kit/tui/kit-mode-2x.tsx
check "first-run cli.json has mode 0644" \
    sh -c '[ "$(stat -c %a "$1")" = "644" ]' _ "$T2X/fresh/cli.json"
check "first-run cli.json parses and carries the plugin entry" \
    sh -c 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert any(e.get(\"package\",\"\").endswith(\"kit-mode-2x.tsx\") for e in d[\"plugins\"])" "$1"' _ "$T2X/fresh/cli.json"

# --- shared per-user sync (sh/tui-plugin.sh, 0.0.41e wave) ----------------------
# tui_plugin_sync_user replaces the twin inline bodies in install.sh
# Step 8c and update.sh's sync_tui_registration. Runs here as the
# current user: TR_SUDO wraps sudo with a stub that drops chown (a
# non-root chown always fails; ownership is asserted by the e2e suites).
TUIWORK=$(mktemp -d)
mkdir -p "$TUIWORK/tps/bin"
cat > "$TUIWORK/tps/bin/sudo-stub" <<'EOF'
#!/bin/sh
# test sudo stub: execute everything except chown (unownable as non-root)
case "$1" in chown) exit 0 ;; esac
exec "$@"
EOF
chmod +x "$TUIWORK/tps/bin/sudo-stub"
TPS="$TUIWORK/tps/home/oc/.config/opencode"
mkdir -p "$TPS"

_tps_run() {
    _tps_desc="$1"; _tps_expect="$2"; shift 2
    TR_SUDO="$TUIWORK/tps/bin/sudo-stub"
    OPK_AGENT_HOME="${_tps_ah:-$TUIWORK/tps/home/oc}"
    export TR_SUDO OPK_AGENT_HOME
    log() { :; }
    # shellcheck disable=SC2030,SC2031
    . "$TUIPLUGIN"
    # shellcheck disable=SC2030,SC2031
    . "$STAGEDWRITE"
    tui_plugin_sync_user "$@" 2>&1
    echo "rc=$?"
}

_LIBROOT="$REPO/files/opencode-permissions-kit-lib"
_tps_out=$(_tps_run "register" 0 2 "$TPS" ocuser ocgroup "$_LIBROOT" opencode)
case "$_tps_out" in *rc=0*) check "sync 2.x: rc=0 (registered)" true ;; *) check "sync 2.x: rc=0 (got [$_tps_out])" false ;; esac
check "sync 2.x: plugin dir exists" test -d "$TPS/plugins/opencode-permissions-kit"
check "sync 2.x: tui.tsx symlink points into the tree" \
    sh -c '[ "$(readlink "$1/plugins/opencode-permissions-kit/tui.tsx")" = "$2/tui/kit-mode-2x.tsx" ]' _ "$TPS" "$_LIBROOT"

_tps_out=$(_tps_run "remove" 0 1 "$TPS" ocuser ocgroup "$_LIBROOT" opencode)
case "$_tps_out" in *rc=0*) check "sync 1.x: rc=0 (removed)" true ;; *) check "sync 1.x: rc=0 (got [$_tps_out])" false ;; esac
check "sync 1.x: plugin dir removed" test ! -e "$TPS/plugins/opencode-permissions-kit"

# chain gate: a symlinked parent chain inside the agent home is skipped
# (rc 2), never followed (_tps_ah redirects the walker's base)
mkdir -p "$TUIWORK/tps/ah/real"
ln -s "$TUIWORK/tps/ah/real" "$TUIWORK/tps/ah/linked"
_tps_ah="$TUIWORK/tps/ah"
_tps_out=$(_tps_run "chain-skip" 2 2 "$TUIWORK/tps/ah/linked/.config/opencode" ocuser ocgroup "$_LIBROOT" opencode)
unset _tps_ah
case "$_tps_out" in *rc=2*) check "chain gate: rc=2 (user-managed skip)" true ;; *) check "chain gate: rc=2 (got [$_tps_out])" false ;; esac

# plugins-symlink gate: a symlinked plugins/ dir is skipped (rc 3)
mkdir -p "$TUIWORK/tps/ah/real2/.config/opencode" "$TUIWORK/tps/real-plugins"
ln -s "$TUIWORK/tps/real-plugins" "$TUIWORK/tps/ah/real2/.config/opencode/plugins"
_tps_ah="$TUIWORK/tps/ah/real2"
_tps_out=$(_tps_run "plugins-skip" 3 2 "$TUIWORK/tps/ah/real2/.config/opencode" ocuser ocgroup "$_LIBROOT" opencode)
unset _tps_ah
case "$_tps_out" in *rc=3*) check "plugins gate: rc=3 (user-managed skip)" true ;; *) check "plugins gate: rc=3 (got [$_tps_out])" false ;; esac

# hard failure (0.0.41f C5): a failing privileged op returns rc 1 — the
# path both callers map to die/exit 1. Stub fails mkdir only.
mkdir -p "$TUIWORK/tps/bin2"
cat > "$TUIWORK/tps/bin2/sudo-stub" <<'EOF'
#!/bin/sh
case "$1" in mkdir) exit 1 ;; esac
exec "$@"
EOF
chmod +x "$TUIWORK/tps/bin2/sudo-stub"
TPS4="$TUIWORK/tps/home4/oc/.config/opencode"
mkdir -p "$TPS4"
_tps_out=$( TR_SUDO="$TUIWORK/tps/bin2/sudo-stub"
    OPK_AGENT_HOME="$TUIWORK/tps/home4/oc"
    export TR_SUDO OPK_AGENT_HOME
    log() { :; }
    # shellcheck disable=SC2030,SC2031
    . "$TUIPLUGIN"
    # shellcheck disable=SC2030,SC2031
    . "$STAGEDWRITE"
    tui_plugin_sync_user 2 "$TPS4" ocuser ocgroup "$_LIBROOT" opencode 2>&1; echo "rc=$?" )
case "$_tps_out" in *rc=1*) check "hard failure: rc=1 (mapped to die/exit at callers)" true ;; *) check "hard failure: rc=1 (got [$_tps_out])" false ;; esac
check "hard failure: no plugin dir left behind" test ! -e "$TPS4/plugins"

# ONE merged trap (0.0.41f C4): a second EXIT trap would REPLACE the
# suite's T2X cleanup — chain both scratch dirs.
trap 'rm -rf "$T2X" "${TUIWORK:-}"' EXIT INT TERM

# --- summary ------------------------------------------------------------------
echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  ${GREEN}All TUI mode tests passed.${NC}"
