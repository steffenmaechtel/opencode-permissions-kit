# shellcheck shell=sh
# opencode permissions kit -- path-sane.sh
#
# Shared project-root policy gate — ONE implementation for install.sh
# (do_plan_phase: --projects validation, the standard prompt, the custom
# dialog) and config.sh (projects add/remove, handover): the function
# existed verbatim in both, kept only because sourcing config.sh itself
# from install.sh is impossible — a management script with side effects
# (arg parsing, install.conf, die). A leaf lib is not: install.sh
# already sources a dozen of them (issue #216; the earlier keep-duplication
# dispositions were PR #109 C15 and PR #211 a F32).
#
# WHY THIS IS LOAD-BEARING: project_path_sane bounds the recursive group
# baseline (chgrp -R + setfacl -R, run as root over every project root)
# — a path bug here has the maximum blast radius of anything in the kit.
# The call contract is fail-closed: a caller whose library is damaged
# must refuse every path, never allow them (see the callers' stubs).
#
# Deploy order (the chicken-and-egg from the old dispositions, evaluated
# for issue #216): a streamed install.sh has no siblings only until
# fetch_kit() returns — the COMPLETE file list is fetched before the
# first kit_source call, and the first project_path_sane call happens
# much later, deep inside the interactive phase. `opk update` from an
# older install is covered by update.sh's heal loop (ensure_local_file
# re-fetches every KIT_FILES entry missing from the fetched tree before
# lib_deploy runs). Fetch order inside the lists is cosmetic — placement
# at the head of the sh/ block is convention, not a load-bearing fix.
#
# Reads at CALL time (safe to source early): PROJECT_TILDE_HOME
# (fallback $HOME) and OPENCODE_USER (fallback "opencode") — both are
# set by the callers long before any call. Returns the normalized path
# in _PP_NORM for the caller.
#
# POSIX sh, SOURCED by install.sh (via kit_source — aborts loud when
# missing) and config.sh (checkout copy first, deployed LIBDIR fallback
# — same rules as staged-write.sh, but with a fail-closed stub). Never
# executed directly. Deployed to
# /usr/local/lib/opencode-permissions-kit/sh/path-sane.sh.

# project_path_sane <path>
# A project root must never be (or live directly under) a system path:
# the group baseline runs chgrp -R + setfacl -R over it. Allowed below
# /home/ and /var/www...; everything else system-ish is rejected. Also
# rejects relative paths and ../. traversal games. "~" is expanded to
# $HOME; the normalized path is returned in _PP_NORM for the caller.
project_path_sane() {
    _pp="${1%/}"
    [ -n "$_pp" ] || return 1
    # expand ~ / ~/... / ~name is rejected (no user lookup). Note: the ~ in
    # the pattern must be escaped (\~) or it tilde-expands and never matches.
    # ~ resolves against PROJECT_TILDE_HOME (the DEFAULT user's home when
    # running under sudo — $HOME would be /root).
    # shellcheck disable=SC2088  # tilde deliberately literal: matching ~ input
    if [ "$_pp" = "~" ]; then _pp="${PROJECT_TILDE_HOME:-$HOME}"; else case "$_pp" in
        "~/"*) _pp="${PROJECT_TILDE_HOME:-$HOME}${_pp#\~}" ;;
        "~"*) return 1 ;;
    esac fi
    _PP_NORM="$_pp"
    case "$_pp" in
        /*) ;;
        *) return 1 ;; # relative paths are error-prone in projects.conf
    esac
    case "$_pp" in
        # Dot/empty-segment forms, complete (0.0.45c S1): the old arms
        # caught only INTERIOR dots — a trailing "/." passed and (with
        # no /var/*, /home/* catch-all in the blocklist below, by
        # design) sent the root-side recursive group baseline over /,
        # /var or every home; a leading "//" resolved outside the
        # blocklist too. Same arms as bin/opk's handover form filter.
        *..* | /./ | */./* | ./* | */. | *//*) return 1 ;; # traversal / dot / empty segments
        *[[:space:]]*) return 1 ;;                         # storage format is line-based and
            # space-free (0.0.39b C3)
    esac
    case "$_pp" in
        / | /bin | /bin/* | /boot | /boot/* | /dev | /dev/* | /etc | /etc/* | /home | /lib* | \
            /media | /media/* | /mnt | /mnt/* | /opt | /opt/* | /proc | /proc/* | /root | /root/* | \
            /run | /run/* | /sbin | /sbin/* | /srv | /srv/* | /sys | /sys/* | /tmp | /tmp/* | /var/tmp/* | \
            /usr | /usr/* | /var | /var/tmp | /var/cache | /var/cache/* | /var/lib | /var/lib/* | \
            /var/log | /var/log/* | /var/mail | /var/mail/* | /var/spool | /var/spool/*)
            return 1
            ;;
    esac
    # The agent user's own home is never a valid project root: the group
    # baseline (chgrp/setfacl -R) would run over the very directory that
    # carries the agent's config and state (review 0.0.39a S4).
    # pr-00263 a F10: getent alongside the literal spelling — a relocated
    # agent home must refuse too (the uninstall.sh twin, opk pattern).
    _pp_agent_home="$(getent passwd "${OPENCODE_USER:-opencode}" 2>/dev/null | cut -d: -f6 || true)"
    if [ "$_pp" = "/home/${OPENCODE_USER:-opencode}" ] ||
        { [ -n "$_pp_agent_home" ] && [ "$_pp" = "$_pp_agent_home" ]; }; then
        return 1
    fi
    # The developer's whole home as a root is allowed but deserves a
    # warning: the baseline gives the agent group-write over every file
    # in it.
    if [ -n "${PROJECT_TILDE_HOME:-}" ] && [ "$_pp" = "$PROJECT_TILDE_HOME" ]; then
        echo "  warn     '$PROJECT_TILDE_HOME' is your whole home — the agent gains group-write over it" >&2
    fi
    return 0
}
