# shellcheck shell=sh
# opencode permissions kit -- wsl-browser-bridge.sh
#
# Deploys the WSL browser bridge (issue #91): opencode's device logins
# (`console login` on 1.x, `auth login` on 2.x) open the verification URL
# through the `open` npm package, which spawns
# <first `root =` in /etc/wsl.conf>c/Windows/System32/WindowsPowerShell/
# v1.0/powershell.exe. On a hardened /mnt/c the opencode user may not
# execute the real powershell.exe, and opencode dies on the synchronous
# spawn error (Bun throws EACCES before opencode's own catch runs) — the
# login flow aborts after printing URL and code.
#
# The bridge writes a kit-managed section into /etc/wsl.conf whose
# `root =` line points at the kit library, and installs the bin/browser-bridge
# stand-in at the powershell.exe path open() then computes. The stand-in
# forwards to the real powershell.exe whenever the calling user may
# execute it and exits 0 otherwise — see bin/browser-bridge.
#
# WSL itself ignores the [opencode-permissions-kit] section (unknown
# section); only `open`-style whole-file `root =` parsers see it. The
# section is kept at the TOP of /etc/wsl.conf so its `root =` line wins
# open's first-match scan even when a real automount root exists.
#
# POSIX sh, SOURCED (never executed) by install.sh and update.sh.
# Callers run as root (or via sudo) — plain file writes are fine. All
# operations are idempotent. No-ops on non-WSL hosts.
#
# Test overrides (same convention as DDEV_WIN_HOSTS / FS_SUDO):
#   OPK_WSL_CONF   the wsl.conf path (default /etc/wsl.conf)
#   OPK_WSL_SUDO   the sudo prefix ("" runs everything unprivileged;
#                  `${OPK_WSL_SUDO-sudo}` — a ":-" would re-substitute sudo)
#   OPK_WSL_FORCE  "1" claims WSL on any host (browser_bridge_is_wsl)
#
# Deployed to /usr/local/lib/opencode-permissions-kit/sh/wsl-browser-bridge.sh.

# Whether this host is WSL (the bridge is inert anywhere else).
# OPK_WSL_FORCE=1 claims WSL for tests on any host.
browser_bridge_is_wsl() {
    [ "${OPK_WSL_FORCE:-0}" = "1" ] && return 0
    grep -qi microsoft /proc/version 2>/dev/null
}

# (Re)insert the kit section at the top of /etc/wsl.conf, preserving every
# other line. An existing kit section is removed first — the rewrite is
# idempotent and heals stale root = values after a LIBDIR change.
browser_bridge_write_conf() {
    _bb_libdir="$1"
    _bb_conf="${OPK_WSL_CONF-/etc/wsl.conf}"
    _bb_tmp="$(mktemp)"
    printf '[opencode-permissions-kit]\n# Managed by the opencode permissions kit. WSL ignores this section; it\n# redirects the powershell.exe lookup of the `open` npm package (bundled in\n# opencode) to the kit stand-in so device logins survive a hardened /mnt/c\n# (issue #91). Do not add other keys here — uninstall removes the section.\nroot = %s/wsl\n\n' "$_bb_libdir" > "$_bb_tmp"
    if [ -f "$_bb_conf" ]; then
        # Drop a previous kit section (header up to the next header), then
        # append the remainder below the fresh section written above.
        sed -e '/^\[opencode-permissions-kit\]$/,/^\[/{/^\[opencode-permissions-kit\]$/d;/^\[/!d;}' "$_bb_conf" >> "$_bb_tmp"
    fi
    ${OPK_WSL_SUDO-sudo} cp "$_bb_tmp" "$_bb_conf"
    ${OPK_WSL_SUDO-sudo} chmod 644 "$_bb_conf"
    rm -f "$_bb_tmp"
}

# Deploy the stand-in at the path open() computes and register it in
# /etc/wsl.conf. <files_root> is the kit files/ tree holding
# opencode-permissions-kit-lib/bin/browser-bridge; <libdir> is the deployed
# library root (/usr/local/lib/opencode-permissions-kit).
browser_bridge_install() {
    _bb_files_root="$1"
    _bb_libdir="$2"
    browser_bridge_is_wsl || return 0
    _bb_src="$_bb_files_root/opencode-permissions-kit-lib/bin/browser-bridge"
    [ -f "$_bb_src" ] || return 0
    ${OPK_WSL_SUDO-sudo} mkdir -p "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell/v1.0"
    # shellcheck disable=SC2174
    ${OPK_WSL_SUDO-sudo} chmod 755 "$_bb_libdir/wsl" "$_bb_libdir/wsl/c" "$_bb_libdir/wsl/c/Windows" \
        "$_bb_libdir/wsl/c/Windows/System32" "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell" \
        "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell/v1.0"
    ${OPK_WSL_SUDO-sudo} install -m 755 "$_bb_src" "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
    browser_bridge_write_conf "$_bb_libdir"
}

# Remove the kit section from /etc/wsl.conf and drop the stand-in tree
# (uninstall). Safe when neither exists.
browser_bridge_remove() {
    _bb_libdir="$1"
    _bb_conf="${OPK_WSL_CONF-/etc/wsl.conf}"
    if [ -f "$_bb_conf" ] && grep -q '^\[opencode-permissions-kit\]$' "$_bb_conf"; then
        _bb_tmp="$(mktemp)"
        sed -e '/^\[opencode-permissions-kit\]$/,/^\[/{/^\[opencode-permissions-kit\]$/d;/^\[/!d;}' "$_bb_conf" > "$_bb_tmp"
        ${OPK_WSL_SUDO-sudo} cp "$_bb_tmp" "$_bb_conf"
        rm -f "$_bb_tmp"
    fi
    ${OPK_WSL_SUDO-sudo} rm -rf "${_bb_libdir:?}/wsl"
}
