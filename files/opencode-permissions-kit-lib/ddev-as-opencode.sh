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
    case "$1" in
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
