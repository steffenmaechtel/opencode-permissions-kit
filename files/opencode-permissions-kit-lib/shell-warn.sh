# opencode permissions kit — wrapper-bypass warning for shell startup
# Sourced at login (via /etc/profile.d/opencode-permissions-kit-umask.sh) and
# in interactive shells (via a line appended to .bashrc/.zshrc/.profile).
# Quiet when the kit wrapper is in charge; prints a warning when a self-installed
# opencode binary could shadow it in the next shell (official installer re-run,
# PATH re-add). Must stay POSIX-sh, cheap, and never exit the parent shell.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/shell-warn.sh.

[ -n "${HOME:-}" ] || return 0

KIT_WRAPPER="/usr/local/lib/opencode-permissions-kit/wrapper"
KIT_BIN="/usr/local/bin/opencode"

warn_path=""
SHADOW="${HOME}/.opencode/bin/opencode"
if [ -e "$SHADOW" ]; then
    if [ -L "$SHADOW" ]; then
        target=$(readlink -f "$SHADOW" 2>/dev/null || echo "$SHADOW")
        [ "$target" = "$KIT_WRAPPER" ] || [ "$target" = "$KIT_BIN" ] || warn_path="$SHADOW"
    else
        warn_path="$SHADOW"
    fi
fi

if [ -z "$warn_path" ]; then
    resolved=$(command -v opencode 2>/dev/null || true)
    case "$resolved" in
        /*)
            [ "$resolved" = "$KIT_BIN" ] || [ "$resolved" = "$KIT_WRAPPER" ] || warn_path="$resolved"
            ;;
    esac
fi

[ -n "$warn_path" ] || return 0

cat >&2 <<EOF

  *** WARNING: opencode permissions kit — wrapper bypass ***
  'opencode' resolves to $warn_path — not the kit wrapper ($KIT_BIN).
  The real binary runs WITHOUT the kit's ACL protection and sandbox user.
  Fix:
      rm -rf "$HOME/.opencode/bin"
      sudo bash /usr/local/lib/opencode-permissions-kit/update.sh
  New shells keep warning until this is resolved.

EOF
