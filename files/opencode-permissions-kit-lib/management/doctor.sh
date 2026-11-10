#!/bin/sh
# opencode permissions kit -- doctor.sh (issue #313, stage 1)
#
# Per-project deep diagnosis for the rootless ownership failure class
# (#312): container processes cannot futimes/chmod/chown files whose
# host uid is UNMAPPED in the daemon's user namespace -- data writes
# still succeed, builds abort with EPERM (gulp/vinyl-fs dest, rsync -t,
# cp -p, tar -xpf). doctor reads the project's opk.json policy (a file
# the project commits; format below and in docs/reference/cli.md) and
# classifies every entry in the declared container trees:
#   mapped-safe  owner is mapped into the daemon userns (the daemon uid
#                or one of its subuid ranges) -> container metadata ops
#                are allowed
#   at-risk      owner unmapped (usually the developer's uid) -> the
#                #312 EPERM class
#
# The mapped ranges come from the LIVE user namespaces, never from
# /etc/subuid -- on the #312 reference host the subuid database is
# empty although the mapping demonstrably exists. Every process carries
# its uid_map in /proc, world-readable; the daemon's own userns and the
# containers nested in it map onto the same host-uid set, so scanning
# the maps whose zero-row points at the daemon user is enough (and it
# needs no docker socket access at all -- #313 open question 2 stays
# open, this is the socket-free primary source). Fallback when no such
# namespace is found (daemon down): daemon-uid-only matching plus an
# explicit "range unverified" warn -- subuid-owned files may then read
# as at-risk until the backend runs again.
#
# The scan is read-only. No sudo: stat, /proc/<pid>/uid_map and
# install.conf are world-readable. Fix rows name the guided remedy
# ('opk doctor fix'); the scan itself never changes a thing.
#
# 'doctor fix' (issue #313, increment b) orchestrates exactly those
# existing remedies: it runs the scan, then offers ONE interactive
# [y/N] prompt (default n) per finding that has an unambiguous remedy --
# a declared, existing, non-symlink directory tree with at-risk entries
# (warnings like missing or symlinked trees have no fix and are never
# offered). A confirmed answer runs 'opk handover opencode <tree>'
# (--dry-run passes through, no prompts, nothing changed). doctor never
# wields sudo itself: the elevation happens inside handover, so no new
# sudoers surface exists. After any executed handover the trees are
# re-checked and the fresh verdict decides the summary.
#
# opk.json -- strict JSON (JSONC was rejected deliberately: jq and
# other tooling must keep reading it, and strict editor validation
# catches malformed policy files; documentation lives in "note"
# fields, not comments). Tolerant read: unknown keys are ignored,
# "version" is reserved for migrations (only 1 exists today).
#
# 'doctor detect' (issue #352 / #313 phase 3) proposes opk.json entries
# from OWNERSHIP EVIDENCE, never from name heuristics: container-written
# entries are the ones whose host uid only a container process can have
# -- mapped subuid twins (the #312 "nobody twin", case C/E) anywhere, and
# daemon-uid entries inside git-ignored (regenerable) paths. Purely
# human-owned trees carry no evidence (the #312 case-A blind spot is
# closed by the handover-me warning instead, not by detect). opk.json is
# a COMMITTED project file: every entry is written only after an
# explicit per-finding [y/N] consent (default n); without consent the
# snippet is printed to paste. Declined findings leave rc 1.
#
# 'doctor all' (#354 / #313 phase 5) runs the scan over EVERY project at
# once: opk.json doubles as the project registration marker -- every
# opk.json found (max 3 levels below a scan root) is one project, one
# FRESH doctor process per DISCOVERED PROJECT (duplicate hits -- a
# project under several scan roots -- spawn one child, the project list
# is deduped). No central registry, no project-name heuristics; 'opk
# status' integration is deliberately deferred (#313 Q3). The full
# contract lives in the all block below.
#
# CLI:  opk doctor [project-root]                 scan (default: cwd, walked
#                                                  up to the nearest opk.json)
#       opk doctor fix [project-root] [--dry-run]  orchestrate the fixes
#       opk doctor detect [project-root]           propose opk.json entries
#       opk doctor all [scan-root]                 one scan per project (the
#                                                  opk.json markers decide)
# Root resolution (#353 / #313 phase 4): without a positional (a plain
# '.' or './' counts as none -- other dot-spellings like './.' are
# explicit roots, #357 a A2) the root is DISCOVERED upward from the cwd
# like git locates .git -- nearest opk.json wins, the used root is
# reported; an explicit positional is authoritative, no discovery.
# Exit codes (the status.sh contract): 0 all declared trees healthy
#      (post-fix, for 'fix'), or detect found nothing / wrote every
#      proposed entry, 1 at-risk finding(s) remain -- declined,
#      dry-run, failed handover, or re-written-before-recheck -- or a
#      rejected policy / degraded-install error (all modes), or detect
#      candidates left undeclared (snippet printed), 2 warning(s) only,
#      64 usage error. 'doctor all' aggregates worst-of across the
#      scanned roots (any alert -> 1, else any warning or nothing
#      scanned -> 2, else 0; the all block owns the details).
#
# Run directly:
#   /usr/local/lib/opencode-permissions-kit/management/doctor.sh [path]
# or from a checkout:
#   files/opencode-permissions-kit-lib/management/doctor.sh [path]
# Deliberately set -u ONLY (no -e): a read-only report -- one failing
# tree must not kill the remaining verdicts (same fail-soft class as
# status.sh).
set -u

# --- shared UI helpers (checkout-first, status.sh pattern) ------------------------
# Caller-dir anchor (#405, review a A2; #434 readlink alignment, #433
# hardening): a streamed stdin run (curl ... | sudo sh) has no real $0
# — the dirname-$0 lookups below (and DOCTOR_OPK's exec in fix mode)
# would resolve cwd-sibling files, unpinned, as root. Pin stdin runs to
# the deployed library's management dir on the FLAT layout; checkout
# and installed runs keep their own dir. The dir resolves through
# readlink -f like uninstall.sh's UN_CALL_DIR — a user SYMLINK to this
# entry keeps the checkout-first sibling lookup instead of silently
# serving the deployed vintage from the link's dir. The stdin
# discriminator compares $0 against the interpreter's own argv[0]
# (#433: a planted cwd FILE named like the interpreter must not
# re-open the cwd trust; same discriminator at all six #405 anchors).
DR_CALL_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")"
_opk_stdin=false
_opk_argv0="$(tr '\0' '\n' 2>/dev/null </proc/$$/cmdline | head -n 1)"
if [ -n "$_opk_argv0" ]; then
    if [ "$0" = "$_opk_argv0" ]; then
        _opk_stdin=true
    fi
elif ! [ -f "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" ]; then
    _opk_stdin=true
fi
if [ "$_opk_stdin" = true ]; then
    DR_CALL_DIR="/usr/local/lib/opencode-permissions-kit/management"
fi
UI_LIB="$DR_CALL_DIR/../sh/ui.sh"
[ -f "$UI_LIB" ] || UI_LIB="/usr/local/lib/opencode-permissions-kit/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    # shellcheck disable=SC1090
    . "$UI_LIB"
else
    echo "error: ui.sh not found (expected it next to doctor.sh in a checkout, or in the kit library)" >&2
    exit 1
fi

# Walk-up opk.json discovery (#353 / #313 phase 4) lives in the shared
# leaf lib (the same resolution site bin/opk's handover-me warning
# uses — one implementation, not per-command copies; see path-sane.sh).
# Hard fail like ui.sh: a missing sibling means the deployment is
# broken, and the default root needs the walker.
PS_LIB="$DR_CALL_DIR/../sh/path-sane.sh"
[ -f "$PS_LIB" ] || PS_LIB="/usr/local/lib/opencode-permissions-kit/sh/path-sane.sh"
if [ -f "$PS_LIB" ]; then
    # shellcheck disable=SC1090
    . "$PS_LIB"
else
    ui_error "doctor: path-sane.sh not found (expected it next to doctor.sh in a checkout, or in the kit library)"
    exit 1
fi

# --- section logic: sh/doctor-core.sh (#346 wave shape, #448) --------------------
# Every section below the shared-lib sourcing lives in the sourced lib
# -- checkout-first like ui.sh above (a checkout doctor.sh runs its own
# sections; an older deployed lib could predate one). A deployed run
# resolves both candidates to the same path, so a missing lib is a
# broken kit (issue #165 class): loud error, no silent section drops.
DOCTOR_CORE="$DR_CALL_DIR/../sh/doctor-core.sh"
[ -f "$DOCTOR_CORE" ] || DOCTOR_CORE="/usr/local/lib/opencode-permissions-kit/sh/doctor-core.sh"
if [ -f "$DOCTOR_CORE" ]; then
    # shellcheck disable=SC1090
    . "$DOCTOR_CORE"
else
    ui_error "doctor: doctor-core.sh not found (expected it next to doctor.sh in a checkout, or in the kit library)"
    exit 1
fi

# Pairing guard (#413, the status.sh/update.sh pattern) -- LOAD-BEARING
# here: doctor is deliberately fail-soft (set -u only, no -e; one
# failing tree must not kill the remaining verdicts), so an undefined
# section call does NOT abort -- it prints "not found", returns rc 127
# and the report would silently lose the section while the summary
# still prints (over a possibly unscanned tree). A version-skewed
# entry/lib pairing (a core missing one renamed or newly-added
# section) is a wiring error, not a tree failure: refuse loud, whole
# run, before any section renders (the ui.sh-missing precedent above
# -- a wiring abort is not a verdict and must not collide with the rc
# contract's codes).
doctor_pairing_guard() {
    for _dpg in doctor_cli doctor_all doctor_walkup doctor_opk_dispatcher \
        doctor_daemon_user doctor_ranges doctor_header doctor_policy \
        doctor_detect doctor_scan_trees doctor_fix doctor_summary; do
        command -v "$_dpg" >/dev/null 2>&1 || {
            ui_error "doctor: section '$_dpg' missing from doctor-core.sh -- version-skewed entry/lib pairing, refusing to run"
            return 1
        }
    done
}
doctor_pairing_guard || exit 1

# Section-shared globals (pure movement: INSTALL_CONF sat above the
# all block, DOCTOR_TAB above the scan helpers -- both before any
# consumer runs; the sections read them as globals).
INSTALL_CONF="${OPK_INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}"
DOCTOR_TAB="$(printf '\t')"

# --- sections, in run order (output order is user-visible) ----------------------
# doctor_cli parses the grammar and exits 64 on usage errors; doctor_all
# and doctor_detect exit per their block comments (the all aggregate
# and the detect rc contract); the fix section falls through to the
# summary's 0/1/2 verdict.
doctor_cli "$@"
doctor_all
doctor_walkup
doctor_opk_dispatcher
doctor_daemon_user
doctor_ranges
doctor_header
doctor_policy
doctor_detect
doctor_scan_trees
doctor_fix
doctor_summary
