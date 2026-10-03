# shellcheck shell=sh
# opencode permissions kit -- git-check.sh
#
# Shared git presence/version probe against the kit's SOFT tested floor
# (issue #118): one implementation for install.sh's pre-flight,
# update.sh's banner phase and status.sh's Core section.
#
# Why a soft floor and no hard requirement: the kit itself only runs
# ancient plumbing — `git -C <dir> config --global` (git >= 1.8.5) and
# safe.directory, a harmless unknown key below 2.35.2 where no ownership
# check exists either. The #116 breakage class (the unreadable-CWD
# fatal) lived at the NEW end of the version range — CI's git matrix
# (test-e2e.yml: distro vs git-core PPA latest, resolved at build time)
# covers that end. The floor below only mirrors the documented oldest
# baseline distros; below it the kit warns, never aborts.
#
# POSIX sh, SOURCED by install.sh, update.sh and status.sh. Never
# executed directly. install.sh and update.sh source the checkout/fetch
# copy first with a deployed-LIBDIR fallback (their own sibling
# convention); status.sh probes the deployed LIBDIR first and falls back
# to the checkout copy next to itself (cf. its ui.sh block). Calls
# ui.sh helpers (ui_warn/ui_detail/ui_kv) at RUNTIME — every caller
# sources ui.sh before its phase runs; log.sh is optional (the audit
# line is best-effort). Deployed to
# /usr/local/lib/opencode-permissions-kit/sh/git-check.sh.

# The oldest git the kit is tested on: Debian 12 / Ubuntu 22.04 — the
# documented oldest supported baseline distros — ship exactly this.
GIT_TESTED_FLOOR="2.30"

# git_probe_version — probe the host git. Sets GIT_CHECK_VERSION to the
# dotted version ("" when git is missing or prints nothing parseable).
# Never fails: every stage is || true-guarded, so callers running under
# set -e (install/update) cannot trip over a missing git.
git_probe_version() {
    GIT_CHECK_VERSION="$(git --version 2>/dev/null \
        | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
}

# git_floor_ok <version> — rc 0 when <version> >= GIT_TESTED_FLOOR.
# Major/minor compare only (the patch level never decides the floor).
# A non-parseable argument compares as 0.0 and fails the floor.
git_floor_ok() {
    awk -v v="$1" -v f="$GIT_TESTED_FLOOR" 'BEGIN{
        split(v,a,"."); split(f,b,".");
        if(a[1]+0>b[1]+0) exit 0;
        if(a[1]+0==b[1]+0 && a[2]+0>=b[2]+0) exit 0;
        exit 1;
    }'
}

# git_check_report — the install/update advisory. Silent when git is
# present at/above the floor; one ui_warn (+ the PPA upgrade hint for
# old-WSL-Ubuntu users) below it; one ui_warn when git is missing.
# Never aborts — see the header for why there is no hard gate.
git_check_report() {
    git_probe_version
    command -v log >/dev/null 2>&1 \
        && log "git check: version=${GIT_CHECK_VERSION:-none} floor=$GIT_TESTED_FLOOR"
    if [ -z "$GIT_CHECK_VERSION" ]; then
        ui_warn "git not found — the agent will not be able to work in repositories."
        ui_detail "install it: sudo apt install git"
        return 0
    fi
    if ! git_floor_ok "$GIT_CHECK_VERSION"; then
        ui_warn "git $GIT_CHECK_VERSION found — the kit is tested with git >= $GIT_TESTED_FLOOR "\
"(Debian 12 / Ubuntu 22.04 baseline)."
        ui_detail "newer git on Ubuntu: sudo add-apt-repository ppa:git-core/ppa && sudo apt update && sudo apt install git"
    fi
    return 0
}

# git_status_row — the status.sh Core row: version + floor verdict,
# colored. Advisory like everything here: yellow, never red — the kit
# keeps working on an old or missing git (only the agent's repo work
# degrades).
git_status_row() {
    git_probe_version
    if [ -z "$GIT_CHECK_VERSION" ]; then
        ui_kv "git" "not installed — agent cannot work in repositories" "$UI_YELLOW"
    elif git_floor_ok "$GIT_CHECK_VERSION"; then
        ui_kv "git" "$GIT_CHECK_VERSION — ok (>= $GIT_TESTED_FLOOR tested floor)" "$UI_GREEN"
    else
        ui_kv "git" "$GIT_CHECK_VERSION — below the $GIT_TESTED_FLOOR tested floor (Debian 12 / Ubuntu 22.04)" "$UI_YELLOW"
    fi
    return 0
}
