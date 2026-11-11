#!/bin/sh
# Unit tests for the status.sh WSL2 /mnt/c exposure warning.
#
# Background: WSL2 mounts C: via 9p/drvfs with the Windows session token —
# NTFS ACLs do NOT distinguish WSL users, the Linux mode bits are the only
# filter, and the default mount is world-readable. Every WSL user (including
# the agent's opencode user) can then read the whole Windows profile
# (.ssh/id_rsa, NTUSER.DAT, browser profiles). status.sh reports this
# report-only and prints the wsl.conf fix.
#
# Static asserts on the repo files + a POSIX-arithmetic check of the
# mode-mask logic. No root, no WSL required.
# Run: sh tests/unit/test-wsl-exposure.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATUS="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/status.sh"
STATUS_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/status-core.sh"
INSTALL="$SCRIPT_DIR/../../files/install.sh"
INSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/install-core.sh" # phase lib since #346 wave 3
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"
UPDATE_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/update-core.sh"
DEPLOYLIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
WRAPPER="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
# Wrapper core lib since #449 (the #346 wave shape): the WSL checks
# moved into its wrapper_wsl_checks section — pins target the lib.
WRAPPER_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/as-opencode-core.sh"
OPK="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/bin/opk"

# Shared harness (issue #394 adoption): pass/fail, colors, counters
# and the summary gate live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

echo ""
echo "WSL2 /mnt/c exposure Tests"
echo "=========================="
echo ""

# --- syntax -------------------------------------------------------------------
check "status.sh passes sh -n" sh -n "$STATUS"
check "install.sh passes sh -n" sh -n "$INSTALL"
check "update.sh passes sh -n" sh -n "$UPDATE"

# --- warning wiring -------------------------------------------------------------
check_live "status.sh gates the section on /mnt/c existing" "$STATUS_CORE" -qF '[ -d /mnt/c ]'
check_live "status.sh checks the world-readable (other) bit of the mount mode" "$STATUS_CORE" -q '0004'
check_live "status.sh prints a world-readable warning" "$STATUS_CORE" -q 'world-readable'
check_live "status.sh names the asset at risk (Windows profile)" "$STATUS_CORE" -q 'Windows profile'
if live_src "$STATUS_CORE" | grep -qF '[automount]' &&
    live_src "$STATUS_CORE" | grep -q 'uid=1000,gid=1000,dmask=027,fmask=037'; then
    pass "status.sh shows the wsl.conf automount fix"
else
    fail "status.sh shows the wsl.conf automount fix"
fi
check_live "status.sh mentions 'wsl --shutdown'" "$STATUS_CORE" -q 'wsl --shutdown'
check_live "status.sh stays silent when the mount is restricted" "$STATUS_CORE" -qF 'restricted'
if live_src "$STATUS_CORE" | grep -q 'pending' &&
    live_src "$STATUS_CORE" | grep -q "options *=.*dmask"; then
    pass "status.sh detects a configured-but-pending fix (wsl --shutdown)"
else
    fail "status.sh detects a configured-but-pending fix (wsl --shutdown)"
fi

# --- install.sh report-only restriction (consent policy) ------------------------
# The kit never writes /etc/wsl.conf (internal/records/wsl-conf-consent.md):
# install prints the snippet, the user applies it.
check_live "install.sh gates the exposure info on /mnt/c existing" "$INSTALL" -qF '[ -d /mnt/c ]'
check_live "install.sh warns about the exposure" "$INSTALL_CORE" -qF 'ui_warn "/mnt/c is world-readable'
# absence pins cover BOTH files since #346 wave 3 (the exposure section
# lives in do_plan_phase, the lib)
check "install.sh never writes /etc/wsl.conf (no tee/append)" \
    sh -c "! grep -q 'tee -a /etc/wsl.conf' \"\$1\" && ! grep -q 'tee -a /etc/wsl.conf' \"\$2\"" _ "$INSTALL" "$INSTALL_CORE"
check "install.sh no longer prompts for the restriction (explicit consent)" \
    sh -c "! grep -q 'Restrict /mnt/c to your user' \"\$1\" && ! grep -q 'Restrict /mnt/c to your user' \"\$2\"" _ "$INSTALL" "$INSTALL_CORE"
if live_src "$INSTALL_CORE" | grep -qF '[automount]' &&
    live_src "$INSTALL_CORE" | grep -q 'dmask=027,fmask=037'; then
    pass "install.sh prints the [automount] snippet with dmask/fmask"
else
    fail "install.sh prints the [automount] snippet with dmask/fmask"
fi
if live_src "$INSTALL_CORE" | grep -qF 'id -u "$DEFAULT_USER"' &&
    live_src "$INSTALL_CORE" | grep -qF 'id -g "$DEFAULT_USER"'; then
    pass "install.sh resolves uid/gid for the snippet from the default user"
else
    fail "install.sh resolves uid/gid for the snippet from the default user"
fi
check_live "install.sh leaves a pre-existing [automount] section untouched" \
    "$INSTALL_CORE" \
    -q 'already has an \[automount\]'
check_live "install.sh names the activation step (wsl --shutdown)" "$INSTALL" -q 'wsl --shutdown'
check_live "install.sh skips silently when the mount is already restricted" \
    "$INSTALL_CORE" \
    -qF '/mnt/c already restricted'
if live_src "$INSTALL" | grep -q 'still world-readable' &&
    live_src "$INSTALL" | grep -q 'warn on every start'; then
    pass "install.sh warns again in the final summary while /mnt/c is exposed"
else
    fail "install.sh warns again in the final summary while /mnt/c is exposed"
fi
check_live "install.sh points WSL users at the opt-in bridge command" "$INSTALL_CORE" -q 'opk wsl-add-opencode-1-fix'

# --- wrapper startup warning ------------------------------------------------------
# The WSL checks live in the lib's wrapper_wsl_checks since #449; both
# files must stay parseable and the markers target the lib.
check "wrapper passes sh -n" sh -n "$WRAPPER"
check "wrapper core lib passes sh -n" sh -n "$WRAPPER_CORE"
check_live "wrapper gates the warning on /mnt/c existing" "$WRAPPER_CORE" -qF '[ -d /mnt/c ]'
check_live "wrapper checks the world-readable (other) bit of the mount mode" "$WRAPPER_CORE" -q '0004'
check_live "wrapper warns about the world-readable /mnt/c on every start" \
    "$WRAPPER_CORE" \
    -q 'WARNING: /mnt/c is world-readable'
if live_src "$WRAPPER_CORE" | grep -qF '[automount]' &&
    live_src "$WRAPPER_CORE" | grep -q 'dmask=027,fmask=037'; then
    pass "wrapper shows the wsl.conf automount fix"
else
    fail "wrapper shows the wsl.conf automount fix"
fi
check_live "wrapper names the activation step (wsl --shutdown)" "$WRAPPER_CORE" -q 'wsl --shutdown'
check_live "wrapper points at the opt-in bridge command" "$WRAPPER_CORE" -q 'opk wsl-add-opencode-1-fix'
if live_src "$WRAPPER_CORE" | grep -q 'PENDING' &&
    live_src "$WRAPPER_CORE" | grep -q "options *=.*dmask"; then
    pass "wrapper detects a configured-but-pending restriction"
else
    fail "wrapper detects a configured-but-pending restriction"
fi
if ! awk '/if \[ -d \/mnt\/c \]/,/^    fi$/' "$WRAPPER_CORE" | grep -q 'already restricted'; then
    pass "wrapper stays silent when the mount is restricted (other bit off)"
else
    fail "wrapper stays silent when the mount is restricted (other bit off)"
fi
if live_src "$WRAPPER_CORE" | grep -qF 'advisories_version_cmp' &&
    live_src "$WRAPPER_CORE" | grep -qF '1.18.33' &&
    live_src "$WRAPPER_CORE" | grep -qF '2.0.18'; then
    pass "wrapper skips the bridge warning for open@11 versions (1.18.33 / 2.0.18)"
else
    fail "wrapper skips the bridge warning for open@11 versions (1.18.33 / 2.0.18)"
fi

# --- update.sh report-only hint (the section lives in sh/update-core.sh,
# #346 wave 2) ------------------------------------------------------------------
if live_src "$UPDATE_CORE" | grep -qF 'ui_warn "/mnt/c is world-readable' &&
    ! sed -n '/restriction configured but still pending/,/kit never edits \/etc\/wsl.conf/p' "$UPDATE_CORE" |
    grep -Eq 'ui_confirm|ui_ask|ui_menu'; then
    pass "update.sh warns about the world-readable /mnt/c (no prompt)"
else
    fail "update.sh warns about the world-readable /mnt/c (no prompt)"
fi
if live_src "$UPDATE_CORE" | grep -qF '[automount]' &&
    live_src "$UPDATE_CORE" | grep -q 'dmask=027'; then
    pass "update.sh prints the recommended wsl.conf options"
else
    fail "update.sh prints the recommended wsl.conf options"
fi
check_live "update.sh reminds about a configured-but-pending restriction" "$UPDATE_CORE" -q "pending 'wsl --shutdown'"
check "update.sh never writes /etc/wsl.conf (carrier left to the user)" \
    sh -c "! grep -q 'browser_bridge_write_conf' \"\$1\" && ! grep -q 'browser_bridge_write_conf' \"\$2\" && grep -q 'opk wsl-add-opencode-1-fix' \"\$1\"" _ "$UPDATE_CORE" "$UPDATE"

# --- the explicit-consent command (opk wsl-add-opencode-1-fix) -------------------
check_live "opk implements the wsl-add-opencode-1-fix subcommand" "$OPK" -q 'wsl-add-opencode-1-fix)'
if live_src "$OPK" | awk '/wsl-add-opencode-1-fix\)/,/;;/' | grep -q 'sudo' &&
    live_src "$OPK" | awk '/wsl-add-opencode-1-fix\)/,/;;/' | grep -q 'browser_bridge_write_conf'; then
    pass "opk wsl-add-opencode-1-fix elevates via sudo and runs write_conf"
else
    fail "opk wsl-add-opencode-1-fix elevates via sudo and runs write_conf"
fi
check "opk wsl-add-opencode-1-fix is the ONLY shipped entry point calling write_conf" \
    sh -c "! grep -rl 'browser_bridge_write_conf' \"\$1\" 2>/dev/null | grep -v 'sh/wsl-browser-bridge.sh$' | grep -v 'bin/opk$' | grep -q ." _ "$SCRIPT_DIR/../../files"
check_live "status.sh points at the opt-in bridge command" "$STATUS_CORE" -q 'opk wsl-add-opencode-1-fix'
if live_src "$STATUS_CORE" | grep -qF 'advisories_version_cmp' &&
    live_src "$STATUS_CORE" | grep -qF '1.18.33' &&
    live_src "$STATUS_CORE" | grep -qF '2.0.18' &&
    live_src "$STATUS_CORE" | grep -qF 'not needed'; then
    pass "status.sh skips the bridge warning for open@11 versions (1.18.33 / 2.0.18)"
else
    fail "status.sh skips the bridge warning for open@11 versions (1.18.33 / 2.0.18)"
fi

# --- xdg-open fallback shim (opencode 1.18.33+ / 2.0.18+ login fix) ---------------
check_live "lib manifest deploys bin/xdg-open 755" "$DEPLOYLIB" -q 'opencode-permissions-kit-lib/bin/xdg-open 755'
# split legs (#346 wave 3): the path literal is the fetch-list entry
# (stays in install.sh), the guarded ln sits in do_deploy_phase (the lib)
if live_src "$INSTALL" | grep -q 'opencode-permissions-kit-lib/bin/xdg-open' &&
    live_src "$INSTALL_CORE" | grep -qF 'ln -s "$LIBDIR/bin/xdg-open" /usr/local/bin/xdg-open'; then
    pass "install.sh deploys the xdg-open shim (guarded, never shadows a real one)"
else
    fail "install.sh deploys the xdg-open shim (guarded, never shadows a real one)"
fi
check "update.sh refreshes and heals the xdg-open shim (stands back for a real one)" \
    sh -c "grep -q 'opencode-permissions-kit-lib/bin/xdg-open' \"\$2\" && grep -qF 'xdg_open_real_exists' \"\$1\" && ! grep -qF '/usr/bin/xdg-open' \"\$1\" && ! grep -qF '/usr/bin/xdg-open' \"\$2\"" _ "$UPDATE_CORE" "$UPDATE"
check_live "status.sh reports the xdg-open fallback state" "$STATUS_CORE" -qF 'xdg-open fallback'
check_live "status.sh never-shadow verdict uses the shared PATH probe (0.0.42d S1)" \
    "$STATUS_CORE" \
    -qF 'xdg_open_real_exists'
check_live "status.sh flags a dangling kit shim instead of green (0.0.42d C2)" \
    "$STATUS_CORE" \
    -qF 'shim symlink dangles'

# --- uninstall consent (internal/records/wsl-conf-consent.md) --------------------------
UNINSTALL="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"
UNINSTALL_CORE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/uninstall-core.sh"
check_live "uninstall removes only the kit-owned xdg-open symlink" "$UNINSTALL_CORE" -qF 'not kit-owned'
check "uninstall.sh passes sh -n" sh -n "$UNINSTALL"
check "uninstall-core.sh passes sh -n" sh -n "$UNINSTALL_CORE"
if live_src "$UNINSTALL_CORE" | grep -q "Remove the kit's wsl.conf bridge block?" &&
    live_src "$UNINSTALL_CORE" | grep -q 'prompt_yn'; then
    pass "uninstall.sh asks before removing kit-owned wsl.conf content"
else
    fail "uninstall.sh asks before removing kit-owned wsl.conf content"
fi
if live_src "$UNINSTALL_CORE" | grep -q 'browser bridge -- begin\$' &&
    live_src "$UNINSTALL_CORE" | grep -q 'left untouched'; then
    pass "uninstall.sh prints the manual line range when declined"
else
    fail "uninstall.sh prints the manual line range when declined"
fi
if live_src "$DEPLOYLIB" | grep -q 'opencode-permissions-kit-lib/bin/browser-bridge 755' &&
    live_src "$INSTALL_CORE" | grep -q 'lib_deploy "$SCRIPT_DIR" "$LIBDIR"' &&
    live_src "$UPDATE_CORE" | grep -q 'lib_deploy "$FILES_ROOT" "$LIBDIR"'; then
    pass "install.sh and update.sh deploy bin/browser-bridge into the library (lib_deploy manifest)"
else
    fail "install.sh and update.sh deploy bin/browser-bridge into the library (lib_deploy manifest)"
fi

# --- mode-mask arithmetic (the exact check status.sh performs) -----------------
mode_allows_other() {
    m=$(stat -c %a "$1" 2>/dev/null) || return 0
    [ $((0$m & 0004)) -ne 0 ]
}
mode_is_restricted() { ! mode_allows_other "$1"; }
TMPDIR=$(work_new)
mkdir -p "$TMPDIR/open" "$TMPDIR/locked"
chmod 777 "$TMPDIR/open"
chmod 770 "$TMPDIR/locked"
check "mask logic: 777 counts as world-readable" \
    mode_allows_other "$TMPDIR/open"
check "mask logic: 770 counts as restricted" \
    mode_is_restricted "$TMPDIR/locked"

# --- Summary ---------------------------------------------------------------------
suite_done "tests"
