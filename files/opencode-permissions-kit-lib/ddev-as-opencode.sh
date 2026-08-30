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
# that would spawn it (mailpit, the phpmyadmin/adminer add-ons, xhgui).
# The URL is read from `ddev describe -j` run AS OPENCODE (via the
# sudoers helper): running as opencode is what makes it correct — as
# *you*, ddev cannot see the rootless daemon and would decide "not
# running" and run its internal `ddev start` on EVERY call. ddev
# maintains every URL in the describe document from the project config,
# even while the project is stopped (upstream-recommended scripting
# interface, ddev/ddev#8771) — no DDEV_DEBUG log flooding needed
# anymore. A stopped project is started first, exactly like ddev's own
# launch script (whose `ddev start` used to arrive wrapped in debug
# logging). Commands whose URL describe does not carry — the built-in
# phpmyadmin installer prompt (add-on not installed yet), custom
# project commands without a matching service — fall back to a plain
# run AS OPENCODE: output and prompts stay interactive, only the
# browser open is skipped (as opencode there is no interop anyway).
# The URL is printed on stdout and opened AS THE DEVELOPER
# (_opk_browser_open — WSL interop, which the opencode user must not
# have).
_opk_ddev_describe() {
    /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode describe -j 2>/dev/null || true
}

# _opk_json_get <json> <key>...: the string value at .raw.<key1>.<key2>...
# of a `ddev describe -j` document (single line); empty when the path is
# absent or not a string. Keys may be passed as separate arguments or
# dot-joined. python3 is a kit prerequisite (the installer already
# depends on it for its jsonc parsing).
_opk_json_get() {
    _opk_gj="$1"
    shift
    printf '%s' "$_opk_gj" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)["raw"]
    for k in ".".join(sys.argv[1:]).split("."):
        d = d[k]
    if isinstance(d, str):
        print(d)
except Exception:
    pass' "$@" 2>/dev/null
}

# _opk_scheme_url <json> <https-key> <http-key>: the URL variant matching
# the primary URL's scheme (ddev's launch script picks the mailpit port
# the same way), the other variant as fallback — empty when describe
# carries neither.
_opk_scheme_url() {
    case "$(_opk_json_get "$1" primary_url)" in
        https*) _opk_su="$(_opk_json_get "$1" "$2")" ;;
        *) _opk_su="$(_opk_json_get "$1" "$3")" ;;
    esac
    [ -n "$_opk_su" ] || _opk_su="$(_opk_json_get "$1" "$2")"
    [ -n "$_opk_su" ] || _opk_su="$(_opk_json_get "$1" "$3")"
    printf '%s\n' "$_opk_su"
}

# _opk_browser_url <json> <argv...>: the URL this browser command would
# open, computed from the describe document — empty when the command
# must fall back to a plain run. The `launch` argument handling mirrors
# ddev's launch script: -m switches to the Mailpit URL, -p must run ddev
# itself (ddev prints its phpMyAdmin add-on hint there), `--` ends the
# flags, then one positional — a full URL as-is, :<port> replaces the
# primary URL's port (keeping its scheme), anything else is appended as
# a path.
_opk_browser_url() {
    _opk_bj="$1"
    shift
    _opk_bc="$1"
    case "$_opk_bc" in
        launch)
            shift
            _opk_bl_base="$(_opk_json_get "$_opk_bj" primary_url)"
            while :; do
                case "${1:-}" in
                    -m|--mailpit|--mailhog)
                        _opk_bl_base="$(_opk_scheme_url "$_opk_bj" mailpit_https_url mailpit_url)"
                        ;;
                    -p|--phpmyadmin) return 0 ;;
                    --) shift; break ;;
                    -*) ;;
                    *) break ;;
                esac
                shift
            done
            case "${1:-}" in
                "") printf '%s\n' "$_opk_bl_base" ;;
                http://*|https://*) printf '%s\n' "$1" ;;
                :*) printf '%s\n' "${_opk_bl_base%:[0-9]*}$1" ;;
                *) printf '%s\n' "${_opk_bl_base%/}/${1#/}" ;;
            esac
            return 0
            ;;
        mailpit)
            _opk_scheme_url "$_opk_bj" mailpit_https_url mailpit_url
            return 0
            ;;
        xhgui)
            if [ "$(_opk_json_get "$_opk_bj" xhgui_status)" = "enabled" ]; then
                _opk_scheme_url "$_opk_bj" xhgui_https_url xhgui_url
            fi
            return 0
            ;;
    esac
    # phpmyadmin/adminer (+ conf-registered commands): a ddev service of
    # the same name carries the URL in describe
    _opk_scheme_url "$_opk_bj" "services.$_opk_bc.https_url" "services.$_opk_bc.http_url"
}

_opk_ddev_browser() {
    _opk_desc="$(_opk_ddev_describe)"
    _opk_url=""
    if [ -n "$_opk_desc" ]; then
        _opk_url="$(_opk_browser_url "$_opk_desc" "$@")"
    fi
    if [ -z "$_opk_url" ]; then
        # No URL from describe (not a project dir, unknown command,
        # add-on not installed): plain run — ddev's own output, prompts
        # and exit code pass through.
        /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode "$@"
        return $?
    fi
    if [ "$(_opk_json_get "$_opk_desc" status)" != "running" ]; then
        # Launch-script parity: a stopped project is started first
        /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode start || return $?
        _opk_desc="$(_opk_ddev_describe)"
        _opk_url2="$(_opk_browser_url "$_opk_desc" "$@")"
        if [ -n "$_opk_url2" ]; then
            _opk_url="$_opk_url2"
        fi
    fi
    printf '%s\n' "$_opk_url"
    _opk_browser_open "$_opk_url"
    return 0
}

# _opk_browser_cmds: command names whose ddev run opens a browser —
# `launch` itself plus the wrappers (mailpit, the phpmyadmin/adminer
# add-ons, xhgui). Their URL comes from `ddev describe -j`: the
# built-ins carry theirs in dedicated fields, add-on commands appear as
# raw.services.<name> — CUSTOM project host commands of the same name
# only open their browser when describe carries a service of that name
# too (otherwise they plain-run as opencode and the browser stays
# closed). Extendable via
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
        echo "    opk ddev-hosts-add $_opk_h"
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
    # Dev-owned (flagged) project: ddev never touches paths outside
    # .ddev/ — the bootstrap EPERM cannot occur, stay silent.
    ddev_devowned_flagged "$PWD" && return 0
    ddev_typo3_detected "$PWD" "$_opk_docroot" && return 0
    [ "$(stat -c %U "$PWD" 2>/dev/null)" = "opencode" ] && return 0
    echo ""
    echo "  hint: fresh typo3 clone — until composer install, ddev writes its"
    echo "  settings file at the project root and must chmod it (owner-only;"
    echo "  the root belongs to you, ddev runs as opencode). Hand it over once"
    echo "  (the kit hands it back after install):"
    echo ""
    echo "    sudo opk config handover $PWD"
    # Dev-owned mode: the same command also writes
    # disable_settings_management: true (the durable fix — ddev then never
    # touches paths outside .ddev/, the root stays yours permanently).
    if ddev_devowned_enabled; then
        echo "    (dev-owned mode on: this also writes disable_settings_management:"
        echo "     true into .ddev/config.yaml — commit that line)"
    fi
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
