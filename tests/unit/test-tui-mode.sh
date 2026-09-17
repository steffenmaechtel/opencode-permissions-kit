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
# Run: sh tests/test-tui-mode.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
TUIDIR="$REPO/files/opencode-permissions-kit-lib/tui"
PLUGIN="$TUIDIR/kit-mode.tsx"
THEME="$TUIDIR/opencode-danger.theme.json"
TUIJSON="$TUIDIR/tui.json"
TUIDANGER="$TUIDIR/tui-danger.json"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
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
check "install.sh deploys the plugin to LIBDIR/tui" \
    grep -q 'cp "$SCRIPT_DIR/opencode-permissions-kit-lib/tui/kit-mode.tsx" "$LIBDIR/tui/kit-mode.tsx"' "$INSTALL"
check "install.sh installs the opencode-user tui.json (marker policy)" \
    grep -q 'grep -q .\"_opencode_permissions_kit\". \"\$OC_TUI_CONF\"' "$INSTALL"
check "install.sh installs the default-user danger theme" \
    grep -q 'opencode-danger.theme.json" "$DEFAULT_THEME_DIR' "$INSTALL"
check "install.sh keeps user-managed tui.json (skip branch)" \
    grep -q 'existing $OC_TUI_CONF kept' "$INSTALL"

# --- update.sh wiring ---------------------------------------------------------
check "update.sh KIT_FILES includes the tui payload" \
    grep -q 'opencode-permissions-kit-lib/tui/kit-mode.tsx' "$UPDATE"
check "update.sh re-deploys the plugin to LIBDIR/tui" \
    grep -q 'cp "$FILES_ROOT/opencode-permissions-kit-lib/tui/kit-mode.tsx" "$LIBDIR/tui/kit-mode.tsx"' "$UPDATE"
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
check "install.sh deploys the 2x plugin to LIBDIR/tui" \
    grep -q 'cp "$SCRIPT_DIR/opencode-permissions-kit-lib/tui/kit-mode-2x.tsx" "$LIBDIR/tui/kit-mode-2x.tsx"' "$INSTALL"
check "install.sh registers the 2x plugin as a discovered plugin dir (major-gated)" \
    grep -q 'ln -sfn "$LIBDIR/tui/kit-mode-2x.tsx" "$_oc_user_dir/plugins/opencode-permissions-kit/tui.tsx"' "$INSTALL"
check "install.sh unregisters inert cli.json path entries (2x cleanup)" \
    grep -q 'tui-register.py" "$_oc_user_dir/cli.json" unregister' "$INSTALL"
check "update.sh fetch list includes the 2x plugin" \
    grep -q 'opencode-permissions-kit-lib/tui/kit-mode-2x.tsx' "$UPDATE"
check "update.sh re-registers the 2x plugin dir (major-gated)" \
    grep -q 'ln -sfn "$LIBDIR/tui/kit-mode-2x.tsx" "$_oc_user_dir/plugins/opencode-permissions-kit/tui.tsx"' "$UPDATE"
check "uninstall.sh removes the 2x plugin dir and cli.json entries" \
    grep -q 'plugins/opencode-permissions-kit' "$UNINSTALL" && grep -q 'kit-mode-2x.tsx' "$UNINSTALL"

# tui-register.py functional behavior (cli.json is user-owned state)
check "tui-register.py exists" test -f "$REGISTER"
T2X=$(mktemp -d)
trap 'rm -rf "$T2X"' EXIT INT TERM
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

# --- summary ------------------------------------------------------------------
echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  ${GREEN}All TUI mode tests passed.${NC}"
