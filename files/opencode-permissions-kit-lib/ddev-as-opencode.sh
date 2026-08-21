# shellcheck shell=sh
# opencode permissions kit -- ddev-as-opencode.sh
# Sourced in the DEFAULT user's interactive shells (a guarded source line is
# appended to .bashrc/.zshrc/.profile at install/update). Defines a `ddev`
# shell function that ALWAYS runs ddev as the 'opencode' user, so the
# developer's terminal and the agent share one ddev home
# (/home/opencode/.ddev) and one container daemon — no owner collisions in
# .ddev/ (the "chmod .ddev/.webimageBuild: operation not permitted" bug).
#
# Already the opencode user? Run the real ddev directly (no recursion — the
# agent/opencode session is never wrapped). Otherwise run the kit's NOPASSWD
# sudoers helper at its fixed path (never a PATH-lookalike). No `exec`: this
# runs inside the developer's interactive shell — exec would REPLACE the
# shell, closing the terminal after ddev exits. Must stay POSIX sh, cheap,
# and never exit the parent shell.
#
# Windows hosts hint: after start/restart, ddev (running as opencode) cannot
# manage the Windows hosts file — the browser cannot resolve custom-tld
# domains until the developer adds them. The hook prints the ready-made
# command plus the missing domains; the agent never touches the hosts file.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh.
# _opk_browser_open <url>: open a URL AS THE DEVELOPER — the browser open
# needs WSL interop (explorer.exe / xdg-open -> wslview), which the
# opencode user deliberately has not (/mnt/c restricted).
_opk_browser_open() {
    if command -v explorer.exe >/dev/null 2>&1; then
        explorer.exe "$1"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$1"
    fi
}

# _opk_ddev_browser <ddev-args...>: issue #20 + follow-up. Covers every
# ddev command that opens a browser — `launch` itself and the wrappers
# whose internals spawn `ddev launch ...` (mailpit: "launch -m", the
# phpmyadmin/adminer add-ons: "launch :<port>", xhgui: "launch <url>").
# The command runs AS OPENCODE with DDEV_DEBUG=true: whatever internal
# `ddev launch` child it spawns (bash host command or Go exec) inherits
# the flag, prints "FULLURL <url>" and exits instead of opening a browser
# (as opencode it could not — no interop). Output streams to stderr live
# (prompts like the phpmyadmin install question stay interactive) but
# WITHOUT the FULLURL transport lines — they go to the capture file only,
# the clean URL is printed on stdout by this function. DDEV_DEBUG
# survives sudo via the kit's sudoers env_keep. ddev without the FULLURL
# debug contract simply shows its output; the browser then stays closed
# (upgrade ddev).
_opk_ddev_browser() {
    _opk_tmp="${TMPDIR:-/tmp}/opk-ddev-browser.$$"
    DDEV_DEBUG=true /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode "$@" 2>&1 \
        | tee "$_opk_tmp" | grep -v '^FULLURL ' >&2
    _opk_url="$(sed -n 's/^FULLURL //p' "$_opk_tmp" 2>/dev/null | tail -1)"
    rm -f "$_opk_tmp"
    if [ -n "$_opk_url" ]; then
        printf '%s\n' "$_opk_url"
        _opk_browser_open "$_opk_url"
    fi
    return 0
}

# _opk_browser_cmds: command names whose ddev run opens a browser —
# `launch` itself plus the wrappers whose internals spawn
# `ddev launch ...` (mailpit: "launch -m", phpmyadmin/adminer add-ons:
# "launch :<port>" — also matches CUSTOM project host commands of the
# same name, e.g. a phpmyadmin with own ports). Extendable via
# /etc/opencode-permissions-kit/ddev-browser-cmds.conf (one name per
# line, '#' comments allowed) for project-specific browser commands.
_opk_browser_cmds() {
    printf '%s\n' launch mailpit phpmyadmin adminer
    _opk_bcc="${OPK_BROWSER_CMDS_CONF:-/etc/opencode-permissions-kit/ddev-browser-cmds.conf}"
    [ -f "$_opk_bcc" ] && grep -v '^[[:space:]]*#' "$_opk_bcc" 2>/dev/null | grep -v '^[[:space:]]*$'
    return 0
}

# _opk_is_browser_cmd <cmd> [subcmd]: true when this ddev invocation
# opens a browser. xhgui only does so bare or as "xhgui launch" — its
# on/off/status are plain daemon commands.
_opk_is_browser_cmd() {
    if [ "$1" = "xhgui" ]; then
        case "${2:-}" in
            ""|launch) return 0 ;;
            *) return 1 ;;
        esac
    fi
    for _opk_bc in $(_opk_browser_cmds); do
        [ "$_opk_bc" = "$1" ] && return 0
    done
    return 1
}

ddev() {
    if [ "$(id -u)" = "$(id -u opencode 2>/dev/null || echo 0)" ]; then
        command ddev "$@"
    else
        # Bootstrap hint BEFORE the run: on a fresh typo3 clone `ddev
        # start` fails with a cryptic EPERM (ddev chmods the project
        # root while TYPO3 is undetected — owner-only operation). The
        # hint names the one-command fix while the error is still ahead.
        case "${1:-}" in
            start|restart) _opk_bootstrap_hint 2>/dev/null || true ;;
        esac
        if _opk_is_browser_cmd "${1:-}" "${2:-}"; then
            # Browser commands (issue #20): URL computed as opencode —
            # see _opk_ddev_browser above.
            _opk_ddev_browser "$@"
        else
            /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode "$@"
        fi
    fi
    _opk_rc=$?
    # ${1:-}: the exported function may land in child scripts running
    # `set -u` that call ddev without arguments (issue #18).
    case "${1:-}" in
        start|restart) _opk_hosts_hint 2>/dev/null || true ;;
    esac
    return "$_opk_rc"
}

# _opk_hosts_hint: after start/restart, list the hostnames missing from the
# Windows hosts file together with the ready-made add command. Silent (no
# output, no failure) whenever anything is off: not WSL2, no project in the
# current directory, lib missing, or nothing missing.
_opk_hosts_hint() {
    [ -f /mnt/c/Windows/System32/drivers/etc/hosts ] || return 0
    [ -f /usr/local/lib/opencode-permissions-kit/ddev-hosts.sh ] || return 0
    [ -f "$PWD/.ddev/config.yaml" ] || return 0
    # shellcheck disable=SC1091  # deployed kit path, checked above
    . /usr/local/lib/opencode-permissions-kit/ddev-hosts.sh
    _opk_miss=$(ddev_hosts_missing "$PWD")
    [ -n "$_opk_miss" ] || return 0
    echo ""
    echo "  hint: these hostnames are missing from the Windows hosts file"
    echo "  (your Windows browser cannot resolve them until added):"
    printf '%s\n' "$_opk_miss" | sed 's/^/    /'
    echo ""
    echo "  add them (Windows asks for permission, one command each —"
    echo "  you see exactly what gets added):"
    for _opk_h in $_opk_miss; do
        echo "    opencode-permissions-kit ddev-hosts-add $_opk_h"
    done
    return 0
}

# _opk_bootstrap_hint: before start/restart, detect the TYPO3 bootstrap
# case (fresh clone) that makes `ddev start` fail with EPERM: without
# vendor/ ddev cannot detect the installation, writes its settings file
# at the PROJECT ROOT and chmods the root directory — an owner-only
# operation, and the root belongs to the developer, not to opencode.
# Prints the one-command fix (config.sh handover — root-run, hands the
# root back once TYPO3 is installed). Silent whenever anything is off:
# no project in the cwd, not typo3, TYPO3 detected, root already handed
# over, or the kit lib missing.
_opk_bootstrap_hint() {
    [ -f /usr/local/lib/opencode-permissions-kit/ddev-handover.sh ] || return 0
    [ -f "$PWD/.ddev/config.yaml" ] || return 0
    _opk_type=$(sed -n 's/^type:[[:space:]]*//p' "$PWD/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    [ "$_opk_type" = "typo3" ] || return 0
    _opk_docroot=$(sed -n 's/^docroot:[[:space:]]*//p' "$PWD/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    [ -n "$_opk_docroot" ] || _opk_docroot="."
    # shellcheck disable=SC1091  # deployed kit path, checked above
    . /usr/local/lib/opencode-permissions-kit/ddev-handover.sh
    ddev_typo3_detected "$PWD" "$_opk_docroot" && return 0
    [ "$(stat -c %U "$PWD" 2>/dev/null)" = "opencode" ] && return 0
    echo ""
    echo "  hint: fresh typo3 clone — until composer install, ddev writes its"
    echo "  settings file at the project root and must chmod it (owner-only;"
    echo "  the root belongs to you, ddev runs as opencode). Hand it over once"
    echo "  (the kit hands it back after install):"
    echo ""
    echo "    sudo opencode-permissions-kit config handover $PWD"
    echo ""
    return 0
}

# Export for bash child processes (issue #18): vendor scripts like TYPO3's
# vendor/bin/runTests.sh call `ddev` in a CHILD bash shell, where this file
# was never sourced — the script resolved the real binary and ran ddev as
# the developer, colliding with the opencode-owned .ddev/ ("chmod
# .ddev/.webimageBuild: operation not permitted"). Two transports:
#   1. export -f: bash children inherit the function directly via the
#      environment (BASH_FUNC_*). Does NOT survive a #!/bin/sh (dash)
#      wrapper in between — dash drops BASH_FUNC_* entries (invalid
#      identifier names) before exec.
#   2. BASH_ENV: non-interactive bash startups source the file it names
#      before running the script. A plainly-named variable, so dash
#      wrappers (vendor/bin/runTests.sh -> exec the bash target) and
#      Makefile/zsh spawn paths pass it through untouched. Self-
#      referential via BASH_SOURCE (works for repo checkouts and
#      deployed kits alike); never clobbers a user-set BASH_ENV.
# Either way a child bash script — whether it calls `ddev ...` bare or
# resolves it via `command -v ddev` — gets this function and ddev runs as
# opencode there too. sudo's env_reset keeps both out of the opencode
# session (no recursion). Pure dash targets still need the documented
# workarounds — see docs/troubleshooting.md.
# shellcheck disable=SC3045  # bash-only block, guarded above
if [ -n "${BASH_VERSION:-}" ]; then
    export -f ddev _opk_hosts_hint _opk_bootstrap_hint 2>/dev/null || true
    if [ -z "${BASH_ENV:-}" ]; then
        # shellcheck disable=SC3028  # bash-only variable in a guarded block
        _opk_hook="${BASH_SOURCE:-}"
        _opk_hook=$(readlink -f "$_opk_hook" 2>/dev/null || printf '%s' "$_opk_hook")
        [ -n "$_opk_hook" ] && export BASH_ENV="$_opk_hook"
    fi
fi
