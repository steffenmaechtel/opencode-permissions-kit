# opencode permissions kit
# Set umask 002 so new files get group-write (the opencode usergroup).
# Prepend /usr/local/bin to ensure the wrapper takes priority.
# Also runs the wrapper-bypass warning (shell-warn.sh) so a self-installed
# opencode binary is reported at login.
# Deployed to /etc/profile.d/opencode-permissions-kit-umask.sh by install.sh.
umask 002
case ":$PATH:" in
    *:/usr/local/bin:*) ;;
    *) export PATH="/usr/local/bin:$PATH" ;;
esac
[ -r /usr/local/lib/opencode-permissions-kit/shell-warn.sh ] && . /usr/local/lib/opencode-permissions-kit/shell-warn.sh
