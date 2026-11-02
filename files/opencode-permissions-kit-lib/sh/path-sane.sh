# shellcheck shell=sh
# opencode permissions kit -- path-sane.sh
#
# Shared project-root policy — TWO leaf functions:
#   project_path_sane  the system-path gate (below)
#   opk_policy_root    walk-up opk.json discovery (#353 / #313 phase 4)
# project_path_sane has ONE implementation for install.sh (do_plan_phase:
# --projects validation, the standard prompt, the custom dialog) and
# config.sh (projects add/remove, handover): the function existed
# verbatim in both, kept only because sourcing config.sh itself from
# install.sh is impossible — a management script with side effects
# (arg parsing, install.conf, die). A leaf lib is not: install.sh
# already sources a dozen of them (issue #216; the earlier keep-duplication
# dispositions were PR #109 C15 and PR #211 a F32).
# opk_policy_root exists for the same reason: doctor.sh and the bin/opk
# handover-me warning must resolve the policy root through ONE shared
# site (#353: the phase-3 comment pinned "moves doctor and this warning
# at their one shared resolution site, not per-command" — a per-command
# copy would be the #216 duplication class reborn).
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

# opk_policy_root <start-dir>                                    (#353)
# Walk-up opk.json discovery, like git locates .git: from <start-dir>
# upward to /, the FIRST directory carrying an opk.json wins — the
# NEAREST policy governs (a nested project with its own opk.json
# shadows any parent's, exactly like nested git repos). The opk.json
# marker IS the project registration (#313 phase 5), so no other stop
# condition exists: no .git boundary (the policy is deliberately
# git-independent — detect works without git), no depth limit.
#
# Contract:
#   - <start-dir> must be ABSOLUTE and normalized (no "..", no trailing
#     slash beyond one, no symlinks needing resolution) — both callers
#     realpath'd before calling; the function is pure parameter
#     expansion + test, no cd, no external command.
#   - OUT-OF-CONTRACT INPUT never hangs (#357 a A1): a slash-less
#     string ("." or any relative name) cannot progress through
#     ${var%/*} — the walk refuses with rc 1 instead of looping
#     forever (the belt behind the callers' normalization; output
#     normalization stays the caller's job, a hit echoes the input
#     verbatim, #357 a A4).
#   - prints the discovered root and returns 0 when an opk.json was
#     found (start dir included — a hit at depth 0 prints <start-dir>);
#     prints nothing and returns 1 when no opk.json exists anywhere on
#     the chain (the caller keeps its start dir, the v1 strict shape).
#   - a marker is a READABLE REGULAR FILE through symlinks ([ -f ]):
#     a dangling opk.json symlink, or a symlink to a directory, is NOT
#     a marker — the walk continues to the next ancestor and that
#     ancestor's policy governs (#357 a B3: deliberately; the reported
#     root is the one whose policy was read). Reading through a
#     symlink to a regular file is accepted v1 behavior at the project
#     root; only detect's WRITER refuses links.
#   - set -e safe: no bare `cmd && act` chains (a failed test would
#     abort the sourcing shell mid-walk).
opk_policy_root() {
    _opr_dir="${1%/}"
    if [ -z "$_opr_dir" ]; then _opr_dir="/"; fi
    while :; do
        if [ -f "$_opr_dir/opk.json" ]; then
            printf '%s\n' "$_opr_dir"
            return 0
        fi
        if [ "$_opr_dir" = "/" ]; then
            return 1
        fi
        _opr_prev="$_opr_dir"
        _opr_dir="${_opr_dir%/*}"
        if [ "$_opr_dir" = "$_opr_prev" ]; then
            # nothing stripped: no slash left — relative/degenerate
            # input the contract excludes. Refuse, never loop (#357 a A1)
            return 1
        fi
        if [ -z "$_opr_dir" ]; then _opr_dir="/"; fi
    done
}
