# shellcheck shell=sh
# opencode permissions kit -- tui-plugin.sh
#
# Shared TUI 2.x plugin registration — ONE implementation for
# install.sh (Step 8c) and update.sh (sync_tui_registration): the
# per-user plugin-dir body (chain gate, plugins-symlink gate,
# mkdir + symlink + chowns, inert-entry unregister) existed in both.
#
# opencode 2.x (issue #80) discovers local CLI plugins as DIRECTORIES
# under ~/.config/opencode/plugins/<name>/; the kit-mode-2x.tsx port is
# registered as a symlinked plugin dir so LIBDIR stays the single
# source of truth. On 1.x the plugin dir is removed (2.x-only artifact);
# the tui.json/danger-theme artifacts are major-agnostic and stay.
#
# POSIX sh, SOURCED by install.sh and update.sh (checkout copy first,
# deployed LIBDIR fallback — same rules as staged-write.sh). Never
# executed directly. TR_SUDO overrides the sudo prefix (tests may
# wrap it to neutralize chown). Note the plain "-": TR_SUDO="" must
# stay empty, a ":-" would re-substitute sudo. Deployed to
# /usr/local/lib/opencode-permissions-kit/sh/tui-plugin.sh.

_tp_sudo() { ${TR_SUDO-sudo} "$@"; }

# tui_plugin_sync_user <major> <user_dir> <owner> <group> <libdir> <opencode_user>
# Registers (major 2) or removes (major 1) the plugin dir for ONE user.
# Return codes:
#   0 = applied (registered or removed)
#   2 = skipped: a symlink in the parent chain of <user_dir> (user-managed)
#   3 = skipped: <user_dir>/plugins (or the plugin dir) is a symlink
# Skip reasons are LOGGED here (audit trail); the caller decides whether
# to surface them in the UI as well.
# Security gates (reviews 0.0.39h F2 + 0.0.39g S1): mkdir -p passes
# through a linked parent silently, chown dereferences a symlink
# OPERAND, rm -rf would delete through it — planted links in the agent
# home are skipped loudly, never followed. The agent_home_sane walker
# no-ops outside the agent home (the developer side is trusted).
tui_plugin_sync_user() {
    _tp_major="$1"
    _tp_user_dir="$2"
    _tp_owner="$3"
    _tp_group="$4"
    _tp_libdir="$5"
    _tp_oc_user="$6"
    if ! agent_home_sane "$_tp_oc_user" "$_tp_user_dir"; then
        log "tui plugin registration skipped: symlink in the chain to $_tp_user_dir (user-managed)"
        return 2
    fi
    if [ -L "$_tp_user_dir/plugins" ] || [ -L "$_tp_user_dir/plugins/opencode-permissions-kit" ]; then
        log "tui plugin registration skipped: $_tp_user_dir/plugins is a symlink (user-managed)"
        return 3
    fi
    if [ "$_tp_major" = 2 ]; then
        _tp_sudo mkdir -p "$_tp_user_dir/plugins/opencode-permissions-kit" || return 1
        _tp_sudo ln -sfn "$_tp_libdir/tui/kit-mode-2x.tsx" \
            "$_tp_user_dir/plugins/opencode-permissions-kit/tui.tsx" || return 1
        # Ownership of the freshly created dirs is load-bearing (the
        # user must reach the plugin): fail loud, do not best-effort it.
        _tp_sudo chown "$_tp_owner:$_tp_group" "$_tp_user_dir/plugins" \
            "$_tp_user_dir/plugins/opencode-permissions-kit" || return 1
        _tp_sudo chown -h "$_tp_owner:$_tp_group" \
            "$_tp_user_dir/plugins/opencode-permissions-kit/tui.tsx" 2>/dev/null || true
        log "tui mode registered for 2.x: $_tp_user_dir/plugins/opencode-permissions-kit/tui.tsx"
    else
        _tp_sudo rm -rf "$_tp_user_dir/plugins/opencode-permissions-kit" || return 1
        log "tui mode 2.x registration removed: $_tp_user_dir/plugins/opencode-permissions-kit"
    fi
    # best-effort cleanup of inert file-path entries (pre-0.0.35 kits)
    _tp_sudo python3 "$_tp_libdir/py/tui-register.py" "$_tp_user_dir/cli.json" unregister \
        "$_tp_libdir/tui/kit-mode-2x.tsx" --drop "$_tp_libdir/tui/kit-mode.tsx" >/dev/null 2>&1 || true
    return 0
}
