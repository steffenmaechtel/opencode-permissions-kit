#!/bin/sh
# opencode permissions kit -- cwd-check.sh
#
# Reports whether a directory is readable (r+x) from the opencode user's
# context. The wrapper uses this before headless `opencode serve`: a server
# spawned with an unreadable working directory (typically the developer's
# $HOME, mode 750 developer:developer under the kit's UID separation) still
# boots, but every request that loads config for that directory answers
# HTTP 500 — opencode treats EACCES on <dir>/opencode.jsonc as a hard
# error, not as "no config file". Access cannot be derived from the calling
# user's context, so the wrapper re-runs this check as the opencode user
# via the kit's NOPASSWD sudoers rule (same pattern as socket-check.sh).
#
# Prints "readable" or "unreadable" and always exits 0: empty output
# (sudoers rule missing, sudo denied) means "probe unavailable" — the
# wrapper then proceeds without touching the working directory rather
# than breaking serve. Deliberately does nothing but stat the directory —
# it is gated to this exact script in sudoers and must never gain extra
# power.
target="${1:-}"
if [ -n "$target" ] && [ -d "$target" ] && [ -r "$target" ] && [ -x "$target" ]; then
    echo readable
else
    echo unreadable
fi
