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
# Consent policy (docs/design/wsl-conf-consent.md): the kit NEVER writes
# /etc/wsl.conf implicitly. install.sh/update.sh deploy only the stand-in
# tree and strip kit-owned legacy content (the broken 0.0.36 section);
# writing the carrier block is reserved for the explicit user command
# `sudo opk wsl-add-opencode-1-fix` (bin/opk), which calls
# browser_bridge_write_conf. Existing carriers are never touched by
# updates — removal happens only through `opk uninstall`.
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
# bridge is needed there. opencode >= 1.18.33 bundles it (open 11.0.4,
# upstream PR #51414): the wrapper and `opk status` skip their bridge
# warnings from that version on — this bridge (and the carrier) only
# serve older opencode pins (opk upgrade-opencode --version).
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

# Scratch-file registration (review 0.0.39e C3): the rewriting functions
# mktemp their staging files; when sourced by install.sh/update.sh/
# config.sh they register with the host's EXIT/INT/TERM cleanup via
# _tmp_track. The no-op fallback covers standalone/test sourcing (no
# trap there — the normal code paths still remove their own temps).
command -v _tmp_track >/dev/null 2>&1 || _tmp_track() { :; }

# _bb_install_conf <src>: atomically replace the wsl.conf carrier
# (0.0.44a V10). Plain `cp` onto /etc/wsl.conf is O_TRUNC+write — a kill
# mid-window truncates the carrier AND the user's foreign settings the
# awk rewrites go to lengths to preserve. Stage BESIDE the target (same
# filesystem) and mv -f (rename(2) is atomic); mode 644 is the canonical
# wsl.conf mode (cp-onto-existing used to preserve the old inode's mode
# implicitly — the rename replaces the inode, so it is set explicitly).
_bb_install_conf() {
    _bb_stage="$(dirname "$_bb_conf")/.wsl.conf.opk.$$"
    _tmp_track "$_bb_stage"
    if ${OPK_WSL_SUDO-sudo} cp "$1" "$_bb_stage" \
       && ${OPK_WSL_SUDO-sudo} chmod 644 "$_bb_stage" \
       && ${OPK_WSL_SUDO-sudo} mv -f "$_bb_stage" "$_bb_conf"; then
        return 0
    fi
    ${OPK_WSL_SUDO-sudo} rm -f "$_bb_stage" 2>/dev/null || true
    return 1
}

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
    _tmp_track "$_bb_tmp"
    # The block below is byte-frozen: the unit tests assert the carrier
    # line's position (line 9 of the file), the block length, and
    # idempotency by byte compare. The carrier line's raw \r (CR before
    # `root =`) is the deliberate hotfix from issue #100 -- do NOT "fix"
    # it away: open@<=10's JS regex cannot cross a CR, so the leading
    # `#` never voids the `root =` match, while WSL skips the whole line
    # as a comment (full story in the header above and
    # docs/reference/files.md).
    {
        printf '%s\n' \
            '# opencode permissions kit browser bridge -- begin' \
            '# Managed by the opencode permissions kit (issues #91, #100). Every line' \
            '# in this block is a comment for WSL -- no section, no key, no effect on' \
            '# WSL itself. The `open` npm package bundled in opencode scans' \
            '# /etc/wsl.conf for the first `root =` line to locate powershell.exe; the' \
            '# carrier line at the end of this block wins that scan and redirects it' \
            '# to the kit stand-in, keeping opencode device logins alive on a' \
            '# hardened /mnt/c. Do not edit -- `opk uninstall` removes this block.'
        printf '# ----------------------------------------------------------------------\rroot = %s/wsl\n' "$_bb_libdir"
        printf '# opencode permissions kit browser bridge -- end\n\n'
    } > "$_bb_tmp"
    if [ -f "$_bb_conf" ]; then
        # Strip a previous kit block (including its trailing blank line)
        # and the legacy 0.0.36 section (header through next header,
        # exclusive), then append the remainder below the fresh block.
        # A block without its end marker stops stripping at the first
        # non-comment line (hand-edited file — never eat foreign content).
        awk '
            in_block {
                if ($0 ~ /^# opencode permissions kit browser bridge -- end$/) { in_block = 0; next }
                # Hand-edited file, end marker destroyed: exit at the first
                # non-comment line WITHOUT the blank-eater staying armed
                # (0.0.43a F11) — the next blank, if any, belongs to foreign
                # content and must survive ("never eat foreign content").
                if ($0 !~ /^#/) { in_block = 0; pend_blank = 0; print; next }
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
    _bb_install_conf "$_bb_tmp"
    _bb_rc=$?
    rm -f "$_bb_tmp" 2>/dev/null || true
    # The tmp cleanup must not swallow the install result (0.0.45c C4):
    # rc 1 = the carrier was NOT written — the caller reports failure
    # instead of the old unconditional success.
    return "$_bb_rc"
}

# Deploy the stand-in tree at the path open() computes. <src> is the
# browser-bridge script (files/ tree or deployed library); <libdir> is the
# deployed library root (/usr/local/lib/opencode-permissions-kit).
# Conf-free by design — this touches only kit-owned paths.
browser_bridge_deploy_tree() {
    _bb_src="$1"
    _bb_libdir="$2"
    browser_bridge_is_wsl || return 0
    [ -f "$_bb_src" ] || return 0
    ${OPK_WSL_SUDO-sudo} mkdir -p "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell/v1.0"
    # shellcheck disable=SC2174
    ${OPK_WSL_SUDO-sudo} chmod 755 "$_bb_libdir/wsl" "$_bb_libdir/wsl/c" "$_bb_libdir/wsl/c/Windows" \
        "$_bb_libdir/wsl/c/Windows/System32" "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell" \
        "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell/v1.0"
    ${OPK_WSL_SUDO-sudo} install -m 755 "$_bb_src" \
        "$_bb_libdir/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
}

# xdg_open_real_exists: any real xdg-open on the caller's PATH, ignoring
# /usr/local/bin where the kit's shim symlink lives (0.0.42d S1/C1).
# install, update and status must share ONE never-shadow probe: install
# refuses to deploy while `command -v xdg-open` hits anything, and the
# fixed-path `/usr/bin` checks in update/status let update deploy a shim
# install would have refused (shadowing a real xdg-open in /usr/sbin,
# /snap/bin, ...) and kept a stale green verdict. Deliberately narrower
# than `command -v` (0.0.42f Q1): empty PATH elements (cwd) are skipped
# — the probe must never consider a cwd-installed binary "real", which
# would silently drop a needed shim.
xdg_open_real_exists() {
    _xre_dir=""
    _xre_oldifs="$IFS"
    IFS=:
    for _xre_dir in $PATH; do
        [ -n "$_xre_dir" ] || continue
        [ "$_xre_dir" = "/usr/local/bin" ] && continue
        if [ -x "$_xre_dir/xdg-open" ]; then
            IFS="$_xre_oldifs"
            return 0
        fi
    done
    IFS="$_xre_oldifs"
    return 1
}

# Strip ONLY the legacy 0.0.36 hyphen section (kit-owned regression
# cleanup, issue #100 — restores WSL's ability to parse the file). Never
# writes anything new; a valid carrier block is left untouched.
browser_bridge_strip_legacy() {
    _bb_conf="${OPK_WSL_CONF-/etc/wsl.conf}"
    [ -f "$_bb_conf" ] || return 0
    grep -q '^\[opencode-permissions-kit\]$' "$_bb_conf" || return 0
    _bb_tmp="$(mktemp)"
    _tmp_track "$_bb_tmp"
    awk '
        in_legacy {
            if ($0 ~ /^\[/) { in_legacy = 0; print; next }
            next
        }
        /^\[opencode-permissions-kit\]$/ { in_legacy = 1; next }
        { print }
    ' "$_bb_conf" > "$_bb_tmp"
    _bb_install_conf "$_bb_tmp"
    _bb_rc=$?
    rm -f "$_bb_tmp" 2>/dev/null || true
    return "$_bb_rc"   # rc 1 = strip failed, not stripped (0.0.45c C4)
}

# Deploy the stand-in tree and clean up kit-owned legacy wsl.conf content
# (install.sh/update.sh entry point). Deliberately does NOT write the
# carrier block — that is the user's explicit call (`sudo opk
# wsl-add-opencode-1-fix`, see the consent policy above).
# <files_root> is the kit files/ tree holding
# opencode-permissions-kit-lib/bin/browser-bridge; <libdir> is the deployed
# library root.
browser_bridge_install() {
    _bb_files_root="$1"
    _bb_libdir="$2"
    browser_bridge_is_wsl || return 0
    browser_bridge_deploy_tree "$_bb_files_root/opencode-permissions-kit-lib/bin/browser-bridge" "$_bb_libdir" \
        || return 1
    browser_bridge_strip_legacy
}

# Remove the kit block (and any legacy 0.0.36 section) from /etc/wsl.conf
# and drop the stand-in tree (uninstall). Safe when neither exists.
browser_bridge_remove() {
    _bb_libdir="$1"
    _bb_conf="${OPK_WSL_CONF-/etc/wsl.conf}"
    if [ -f "$_bb_conf" ] && { grep -q '^# opencode permissions kit browser bridge -- begin$' "$_bb_conf" \
            || grep -q '^\[opencode-permissions-kit\]$' "$_bb_conf"; }; then
        _bb_tmp="$(mktemp)"
        _tmp_track "$_bb_tmp"
        awk '
            in_block {
                if ($0 ~ /^# opencode permissions kit browser bridge -- end$/) { in_block = 0; next }
                # Hand-edited file, end marker destroyed: exit at the first
                # non-comment line WITHOUT the blank-eater staying armed
                # (0.0.43a F11) — the next blank, if any, belongs to foreign
                # content and must survive ("never eat foreign content").
                if ($0 !~ /^#/) { in_block = 0; pend_blank = 0; print; next }
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
        _bb_install_conf "$_bb_tmp"
        _bb_rc=$?
        rm -f "$_bb_tmp" 2>/dev/null || true
        # rc 1 = the kit block was NOT removed (0.0.45c C4) — propagate
        # after the tmp cleanup; the tree removal below is best-effort
        # either way (uninstall continues, the failure is reported).
        if [ "$_bb_rc" -ne 0 ]; then
            ${OPK_WSL_SUDO-sudo} rm -rf "${_bb_libdir:?}/wsl" 2>/dev/null || true
            return "$_bb_rc"
        fi
    fi
    ${OPK_WSL_SUDO-sudo} rm -rf "${_bb_libdir:?}/wsl"
}
