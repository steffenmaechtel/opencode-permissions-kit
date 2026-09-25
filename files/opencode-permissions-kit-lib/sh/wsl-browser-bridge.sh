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
# The bridge keeps a kit-managed COMMENT block at the top of /etc/wsl.conf
# whose carrier line (last line of the block) is the first `root =` match
# of open's scan and points at the kit library; bin/browser-bridge is
# installed at the powershell.exe path open() then computes. The stand-in
# forwards to the real powershell.exe whenever the calling user may
# execute it and exits 0 otherwise — see bin/browser-bridge.
#
# Why a comment block and not an INI section (issue #100): WSL's wsl.conf
# parser (src/shared/configfile/configfile.cpp) only accepts section names
# matching [A-Za-z][A-Za-z0-9]* and keys matching the same charset — the
# hyphenated [opencode-permissions-kit] section shipped in kit 0.0.36 made
# WSL print `wsl: Expected ']' in /etc/wsl.conf:1` and (WSL <= 2.9.12,
# before #41606 started skipping invalid lines) abort parsing, so every
# other setting in the file (automount restriction, [boot] systemd, ...)
# silently stopped applying. A parser-valid section name does not help
# either: every unknown key draws `wsl: Unknown key '<section>.<key>'` on
# each WSL start. Comments are the only WSL-silent carrier — and open's
# scan still finds `root =` inside them thanks to a raw CR (\r) mid-line:
# open@<=10 matches /(?<!#.*)root\s*=\s*(.*)/, and JS regex `.` cannot
# cross a carriage return, so the leading `#` never reaches the match,
# while WSL's comment skip reads to the next \n (a lone \r is consumed
# with the following character). Newer `open` (wsl-utils based) parses
# line-based, skips `^\s*#` lines, and checks powershell access before
# spawning — it ignores the carrier and falls back to xdg-open, so no
# bridge is needed there.
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

# (Re)insert the kit comment block at the top of /etc/wsl.conf, preserving
# every other line. An existing kit block (any root = value) and the
# legacy 0.0.36 [opencode-permissions-kit] section are removed first —
# the rewrite is idempotent and heals stale root = values and the
# issue-#100 breakage alike.
browser_bridge_write_conf() {
    _bb_libdir="$1"
    _bb_conf="${OPK_WSL_CONF-/etc/wsl.conf}"
    _bb_tmp="$(mktemp)"
    printf '# opencode permissions kit browser bridge -- begin\n# Managed by the opencode permissions kit (issues #91, #100). Every line\n# in this block is a comment for WSL -- no section, no key, no effect on\n# WSL itself. The `open` npm package bundled in opencode scans\n# /etc/wsl.conf for the first `root =` line to locate powershell.exe; the\n# carrier line at the end of this block wins that scan and redirects it\n# to the kit stand-in, keeping opencode device logins alive on a\n# hardened /mnt/c. Do not edit -- `opk uninstall` removes this block.\n# ----------------------------------------------------------------------\rroot = %s/wsl\n# opencode permissions kit browser bridge -- end\n\n' "$_bb_libdir" > "$_bb_tmp"
    if [ -f "$_bb_conf" ]; then
        # Strip a previous kit block (including its trailing blank line)
        # and the legacy 0.0.36 section (header through next header,
        # exclusive), then append the remainder below the fresh block.
        # A block without its end marker stops stripping at the first
        # non-comment line (hand-edited file — never eat foreign content).
        awk '
            in_block {
                if ($0 ~ /^# opencode permissions kit browser bridge -- end$/) { in_block = 0; next }
                if ($0 !~ /^#/) { in_block = 0; print; next }
                next
            }
            /^# opencode permissions kit browser bridge -- begin$/ { in_block = 1; pend_blank = 1; next }
            pend_blank == 1 {
                pend_blank = 0
                if ($0 == "") next
            }
            in_legacy {
                if ($0 ~ /^\[/) { in_legacy = 0; print; next }
                next
            }
            /^\[opencode-permissions-kit\]$/ { in_legacy = 1; next }
            { print }
        ' "$_bb_conf" >> "$_bb_tmp"
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

# Remove the kit block (and any legacy 0.0.36 section) from /etc/wsl.conf
# and drop the stand-in tree (uninstall). Safe when neither exists.
browser_bridge_remove() {
    _bb_libdir="$1"
    _bb_conf="${OPK_WSL_CONF-/etc/wsl.conf}"
    if [ -f "$_bb_conf" ] && { grep -q '^# opencode permissions kit browser bridge -- begin$' "$_bb_conf" \
            || grep -q '^\[opencode-permissions-kit\]$' "$_bb_conf"; }; then
        _bb_tmp="$(mktemp)"
        awk '
            in_block {
                if ($0 ~ /^# opencode permissions kit browser bridge -- end$/) { in_block = 0; next }
                if ($0 !~ /^#/) { in_block = 0; print; next }
                next
            }
            /^# opencode permissions kit browser bridge -- begin$/ { in_block = 1; pend_blank = 1; next }
            pend_blank == 1 {
                pend_blank = 0
                if ($0 == "") next
            }
            in_legacy {
                if ($0 ~ /^\[/) { in_legacy = 0; print; next }
                next
            }
            /^\[opencode-permissions-kit\]$/ { in_legacy = 1; next }
            { print }
        ' "$_bb_conf" > "$_bb_tmp"
        ${OPK_WSL_SUDO-sudo} cp "$_bb_tmp" "$_bb_conf"
        rm -f "$_bb_tmp"
    fi
    ${OPK_WSL_SUDO-sudo} rm -rf "${_bb_libdir:?}/wsl"
}
