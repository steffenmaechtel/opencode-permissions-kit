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
ddev() {
    if [ "$(id -u)" = "$(id -u opencode 2>/dev/null || echo 0)" ]; then
        command ddev "$@"
    else
        /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode "$@"
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
    echo "  add them (Windows asks for permission):"
    echo "    opencode-permissions-kit ddev-hosts-add"
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
    export -f ddev _opk_hosts_hint 2>/dev/null || true
    if [ -z "${BASH_ENV:-}" ]; then
        # shellcheck disable=SC3028  # bash-only variable in a guarded block
        _opk_hook="${BASH_SOURCE:-}"
        _opk_hook=$(readlink -f "$_opk_hook" 2>/dev/null || printf '%s' "$_opk_hook")
        [ -n "$_opk_hook" ] && export BASH_ENV="$_opk_hook"
    fi
fi
