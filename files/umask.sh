# opencode permissions kit
# Set umask 002 so new files get group-write (www-data).
# Prepend /usr/local/bin to ensure the wrapper takes priority.
# Deployed to /etc/profile.d/opencode-permissions-kit-umask.sh by install.sh.
umask 002
case ":$PATH:" in
    *:/usr/local/bin:*) ;;
    *) export PATH="/usr/local/bin:$PATH" ;;
esac
