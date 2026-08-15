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
# shell, closing the terminal after ddev exits. Must stay POSIX-sh, cheap,
# and never exit the parent shell.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/ddev-as-opencode.sh.
ddev() {
    if [ "$(id -u)" = "$(id -u opencode 2>/dev/null || echo 0)" ]; then
        command ddev "$@"
    else
        /usr/bin/sudo -u opencode /usr/local/lib/opencode-permissions-kit/bin/ddev-as-opencode "$@"
    fi
}
