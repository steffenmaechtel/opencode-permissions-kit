# shellcheck shell=sh
# opencode permissions kit -- git-protection-core.sh
#
# The `opk git-protection` subcommand's logic (issue #704, the "O4"
# layout from #702's research; Phase A measured green — the issue's
# harness artifacts): a project's .git DIRECTORY becomes a POINTER
# FILE ("gitdir: <storage>/<name>.git", worktree style) into a
# dev-owned sticky storage OUTSIDE every projects.conf root, and the
# pointer file itself is nailed with chattr +i (ext4/xfs inode flag:
# no rename, no unlink, no replace, no append — for every actor, root
# included until chattr -i). That closes the reopened wholesale arm
# (mv .git, #702's W1/W2) without any top-level sticky bit.
#
# Sourced (never executed) by bin/opk through its SELF-resolved $LIBDIR
# (checkout-first); the pairing guard in the dispatcher refuses a
# version-skewed pairing. update.sh sources it too (the consent phase,
# update_git_protection_consent) with the same lookup order. POSIX sh,
# no top-level side effects (definitions and comments only). The
# functions run in the CALLER's shell (bin/opk sets set -u only) and
# read the globals the dispatcher sets: LIBDIR, INSTALL_CONF and the
# ui_* helpers.
#
# Commands (git_protection_cli parses and validates BEFORE the sudo
# hop — usage errors need no elevation; the re-exec is loop-guarded,
# the #479 a F24 shape):
#   status              per project: classic | nailed | unnailed |
#                       foreign-pointer | worktree-reg; rc 1 when any
#                       actionable row exists (the verdict-in-rc rule,
#                       conventions.md "Script output style"), rc 0
#                       when protected/idle
#   on                  storage init + persist GITDIR_STORAGE +
#                       migrate ALL classic projects + nail (root)
#   adopt <path>        migrate + nail ONE project (root)
#   nail [<path>]       nail pending pointers; with <path> only that
#                       project's pointer (root)
#   revert <path>|--all walk back to the classic layout (root)
#   off                 revert --all + drop GITDIR_STORAGE (root)
#
# Migrations are per-project ATOMIC: verify (pointer content + git
# status) gates every step, rollback (pointer out, gitdir back) on
# failure; name collisions in the storage get -2, -3... suffixes;
# existing worktrees follow the moved gitdir through `git worktree
# repair` in the same breath.
#
# Heal contract (Phase A findings, the issue's run log):
#   - The relocated #651 heal pins config/hooks dev (no group write,
#     no ACLs) and the measured operand set (heal-index-head's list)
#     agent — chmod walks run BEFORE the chown walk (L5: the walk
#     order decides who can plant what).
#   - COMMIT_EDITMSG pins DEV (config class: git only rewrites it
#     in place, and file-owner==dir-owner exempts every opener under
#     fs.protected_regular=2 — an agent-pinned one locks the dev
#     commit out under =2).
#   - FETCH_HEAD stays transient-unpinned: the migration heal DELETES
#     it (a regenerating cache); whichever actor fetches first re-
#     creates it. Under =2 the other actor's first fetch over a
#     foreign-owned FETCH_HEAD is blocked (measured, the issue's d1i
#     cell) — documented residual, same class as the in-tree design.
#
# Test overrides (unit suite only, never set in production — none of
# them survives sudo's env_reset):
#   GP_STORAGE         storage path (default: GITDIR_STORAGE from
#                      install.conf, else the sibling of the first
#                      usable projects.conf root)
#   GP_CONF            projects.conf (default
#                      /etc/opencode-permissions-kit/projects.conf)
#   GP_INSTALL_CONF    install.conf (default $INSTALL_CONF, else
#                      /etc/opencode-permissions-kit/install.conf)
#   GP_LIBDIR          library base (default $LIBDIR, literal
#                      fallback) — the sudo re-exec resolves bin/opk
#   GP_ALLOW_NONROOT   relax the root gate (tests chown to the
#                      running user, a permitted no-op chown)
#   GP_CONF_RELAX      relax the conf-line system-path/agent-home
#                      arms (unit scratch zones live under /tmp)

# _gp_libdir: the library base the sudo re-exec resolves bin/opk
# against (checkout-first by construction — bin/opk resolved it).
_gp_libdir() {
    printf '%s' "${GP_LIBDIR:-${LIBDIR:-/usr/local/lib/opencode-permissions-kit}}"
}

# _gp_var <name>: one KEY=VALUE line from install.conf (doctor-style
# sed read, never a source of a root-owned file).
_gp_var() {
    _gpv_ic="${GP_INSTALL_CONF:-${INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}}"
    sed -n "s/^$1=//p" "$_gpv_ic" 2>/dev/null | tail -n 1
}

# _gp_devuser: the developer username; loud empty on a missing key
# (this is a kit-machine command, install.conf must exist).
_gp_devuser() {
    _gpd_du=$(_gp_var DEFAULT_USER)
    if [ -z "$_gpd_du" ]; then
        ui_error "DEFAULT_USER not found — is the kit installed?"
        exit 1
    fi
    printf '%s' "$_gpd_du"
}

# _gp_agentuser: the agent username (OPENCODE_USER, canonical
# fallback like every kit lib).
_gp_agentuser() {
    _gpa_au=$(_gp_var OPENCODE_USER)
    printf '%s' "${_gpa_au:-opencode}"
}

# _gp_group: the sharing group (OPENCODE_GROUP, canonical fallback).
_gp_group() {
    _gpg_gr=$(_gp_var OPENCODE_GROUP)
    printf '%s' "${_gpg_gr:-opencode}"
}

# _gp_root_ok <line>: reader-side conf-line gate (the files.md
# contract — every consumer that runs root operations over the roots
# re-validates each line; the uninstall-core reader mirror, #674 a
# A1). rc 0: usable root, trailing-slash-stripped form in
# _gp_root_norm. rc 1: refused, form (non-absolute, dot/empty
# segment, whitespace, glob character #665); rc 2: refused, agent
# home; rc 3: refused, system path (incl. the bare "/" that strips
# to empty, #674 b D1). The system-path and agent-home arms sit
# behind GP_CONF_RELAX (unit scratch zones live under /tmp); the
# form arms never relax.
_gp_root_ok() {
    _gpr_ro="$1"
    case "$_gpr_ro" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$_gpr_ro" in
        *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]* | *[\*\?\[]*) return 1 ;;
    esac
    while :; do
        case "$_gpr_ro" in
            */) _gpr_ro="${_gpr_ro%/}" ;;
            *) break ;;
        esac
    done
    # "/" strips to empty: rc 3 (system path), never the generic
    # rc 1 form message — "/" is absolute and not malformed.
    [ -n "$_gpr_ro" ] || return 3
    if [ "${GP_CONF_RELAX:-}" != "1" ]; then
        _gpr_ah=$(getent passwd "$(_gp_agentuser)" 2>/dev/null | cut -d: -f6) ||
            true
        if [ "$_gpr_ro" = "/home/$(_gp_agentuser)" ] ||
            { [ -n "$_gpr_ah" ] && [ "$_gpr_ro" = "$_gpr_ah" ]; }; then
            return 2
        fi
        case "$_gpr_ro" in
            # The writer's FHS-complete blocklist (sh/path-sane.sh
            # project_path_sane — same arms as every reader mirror).
            / | /bin | /bin/* | /boot | /boot/* | /dev | /dev/* | /etc | /etc/* | /home | /lib* | \
                /media | /media/* | /mnt | /mnt/* | /opt | /opt/* | /proc | /proc/* | /root | /root/* | \
                /run | /run/* | /sbin | /sbin/* | /srv | /srv/* | /sys | /sys/* | /tmp | /tmp/* | /var/tmp/* | \
                /usr | /usr/* | /var | /var/tmp | /var/account | /var/account/* | /var/backups | \
                /var/backups/* | /var/cache | /var/cache/* | /var/crash | /var/crash/* | /var/games | \
                /var/games/* | /var/lib | /var/lib/* | /var/local | /var/local/* | /var/lock | \
                /var/lock/* | /var/log | /var/log/* | /var/mail | /var/mail/* | /var/opt | \
                /var/opt/* | /var/run | /var/run/* | /var/spool | /var/spool/* | /var/yp | /var/yp/*)
                return 3
                ;;
        esac
    fi
    _gp_root_norm="$_gpr_ro"
    return 0
}

# _gp_conf_path: the projects.conf the sweeps read.
_gp_conf_path() {
    printf '%s' "${GP_CONF:-/etc/opencode-permissions-kit/projects.conf}"
}

# _gp_storage: resolve the storage path (the Phase B design, issue
# #704's design comment): explicit conf wins (GP_STORAGE test seam,
# then GITDIR_STORAGE from install.conf — the marker "none" means
# DECLINED, rc 2), else the sibling of the first usable conf root
# (/var/www/vhosts -> /var/www/gitdirs; agent-home and refused lines
# are skipped). Echoes the path on rc 0; rc 1 when nothing is
# derivable; rc 2 when explicitly declined. The caller re-validates
# any derived path through _gp_root_ok before creating anything.
_gp_storage() {
    if [ -n "${GP_STORAGE:-}" ]; then
        printf '%s\n' "$GP_STORAGE"
        return 0
    fi
    _gps_s=$(_gp_var GITDIR_STORAGE)
    if [ "$_gps_s" = "none" ]; then
        return 2
    fi
    if [ -n "$_gps_s" ]; then
        printf '%s\n' "$_gps_s"
        return 0
    fi
    _gps_conf=$(_gp_conf_path)
    [ -f "$_gps_conf" ] || return 1
    _gps_agent=$(_gp_agentuser)
    _gps_ah=$(getent passwd "$_gps_agent" 2>/dev/null | cut -d: -f6) || true
    while IFS= read -r _gps_root; do
        case "$_gps_root" in '' | '#'*) continue ;; esac
        _gps_rk_rc=0
        _gp_root_ok "$_gps_root" || _gps_rk_rc=$?
        [ "$_gps_rk_rc" -eq 0 ] || continue
        [ -d "$_gp_root_norm" ] || continue
        case "$_gp_root_norm" in
            "$_gps_ah" | "$_gps_ah"/*) continue ;;
        esac
        printf '%s\n' "${_gp_root_norm%/*}/gitdirs"
        return 0
    done <"$_gps_conf"
    return 1
}

# _gp_nosym <path>: rc 0 when no path COMPONENT is a symlink (L5:
# gates that check only the final component are bypassed via
# parents). A missing tail component is fine (the storage is about
# to be created); a symlinked EXISTING component is refused.
_gp_nosym() {
    _gpns_p="$1"
    _gpns_acc=""
    _gpns_rest="${_gpns_p#/}"
    while [ -n "$_gpns_rest" ]; do
        _gpns_c=${_gpns_rest%%/*}
        if [ "$_gpns_c" = "$_gpns_rest" ]; then
            _gpns_rest=""
        else
            _gpns_rest=${_gpns_rest#*/}
        fi
        [ -n "$_gpns_c" ] || continue
        _gpns_acc="$_gpns_acc/$_gpns_c"
        [ -L "$_gpns_acc" ] && return 1
    done
    return 0
}

# _gp_storage_init <path>: create + normalize the storage shape
# (Phase A fixture semantics: dev:group, 3770 — sticky+setgid; the
# sticky bit costs nothing there and closes the agent's rename arm
# inside the storage). The path is form-gated and walked for
# symlinked components first (L5); the PARENT must not be
# group-writable for the kit group — else the agent can move the
# whole storage aside (Phase A w11) — warned loud when it is.
_gp_storage_init() {
    _gpsi_stor=$1
    case "$_gpsi_stor" in
        /*) ;;
        *)
            ui_error "storage path is not absolute: $_gpsi_stor"
            return 1
            ;;
    esac
    _gpsi_rk_rc=0
    _gp_root_ok "$_gpsi_stor" || _gpsi_rk_rc=$?
    if [ "$_gpsi_rk_rc" -ne 0 ]; then
        ui_error "storage path refused (system path, agent home, or malformed): $_gpsi_stor"
        return 1
    fi
    if ! _gp_nosym "$_gpsi_stor"; then
        ui_error "storage path has a symlinked component: $_gpsi_stor"
        return 1
    fi
    [ -L "$_gpsi_stor" ] && {
        ui_error "storage path is a symlink: $_gpsi_stor"
        return 1
    }
    mkdir -p "$_gpsi_stor" || {
        ui_error "cannot create $_gpsi_stor"
        return 1
    }
    chown "$(_gp_devuser):$(_gp_group)" "$_gpsi_stor" || {
        ui_error "cannot chown $_gpsi_stor"
        return 1
    }
    chmod 3770 "$_gpsi_stor" || {
        ui_error "cannot set mode 3770 on $_gpsi_stor — the storage shape is load-bearing (sticky+setgid+group-write)"
        return 1
    }
    _gpsi_parent=$(dirname "$_gpsi_stor")
    if [ "$(stat -c '%G' "$_gpsi_parent" 2>/dev/null)" = "$(_gp_group)" ] &&
        [ -n "$(find "$_gpsi_parent" -maxdepth 0 -perm -g+w 2>/dev/null)" ]; then
        ui_warn "storage parent $_gpsi_parent is group-writable for $(_gp_group)"
        ui_detail "the agent could move the whole storage aside (Phase A w11) — tighten the parent"
    fi
    return 0
}

# _gp_persist_storage <value>: write GITDIR_STORAGE=<value> into
# install.conf (cat-over keeps the inode: mode/ownership of the
# root-owned file survive; sed -i would recreate it). Named-cause
# mktemp guard (the #364 class).
_gp_persist_storage() {
    _gpps_val=$1
    _gpps_ic="${GP_INSTALL_CONF:-${INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}}"
    [ -f "$_gpps_ic" ] || {
        ui_error "install.conf not found at $_gpps_ic — cannot persist the storage path"
        return 1
    }
    _gpps_tmp=$(mktemp) || {
        ui_error "mktemp failed (is \$TMPDIR writable?) — cannot persist the storage path"
        return 1
    }
    awk -v v="$_gpps_val" '
        /^GITDIR_STORAGE=/ { print "GITDIR_STORAGE=" v; seen = 1; next }
        { print }
        END { if (!seen) print "GITDIR_STORAGE=" v }
    ' "$_gpps_ic" >"$_gpps_tmp" || {
        rm -f "$_gpps_tmp"
        return 1
    }
    cat "$_gpps_tmp" >"$_gpps_ic" || {
        rm -f "$_gpps_tmp"
        return 1
    }
    rm -f "$_gpps_tmp"
    return 0
}

# _gp_drop_storage: remove the GITDIR_STORAGE line from install.conf
# (same cat-over discipline; kit-owned bytes only).
_gp_drop_storage() {
    _gpds_ic="${GP_INSTALL_CONF:-${INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}}"
    [ -f "$_gpds_ic" ] || {
        ui_error "install.conf not found at $_gpds_ic — cannot drop the storage key"
        return 1
    }
    _gpds_tmp=$(mktemp) || {
        ui_error "mktemp failed (is \$TMPDIR writable?) — cannot drop the storage key"
        return 1
    }
    awk '!/^GITDIR_STORAGE=/' "$_gpds_ic" >"$_gpds_tmp" || {
        rm -f "$_gpds_tmp"
        return 1
    }
    cat "$_gpds_tmp" >"$_gpds_ic" || {
        rm -f "$_gpds_tmp"
        return 1
    }
    rm -f "$_gpds_tmp"
    return 0
}

# _gp_has_i <file>: rc 0 when lsattr shows the immutable flag
# (unprivileged-readable — the check behind the status rows).
_gp_has_i() {
    lsattr "$1" 2>/dev/null | awk '{print $1}' | grep -q i
}

# _gp_worktrees <gitdir>: echo registered worktree paths (minus the
# main one, which is the project itself). A failed enumeration is a
# LOUD warn (#754 a C4), never a silent empty list — registered
# worktrees would keep dangling pointers with no row at all.
_gp_worktrees() {
    _gpw_out=$(_gp_devgit -c safe.directory='*' -c core.fsmonitor=false \
        -c core.hooksPath=/dev/null --git-dir="$1" worktree list --porcelain 2>/dev/null) ||
        ui_warn "worktree enumeration failed on $1 — repair may be skipped"
    printf '%s' "$_gpw_out" | sed -n 's/^worktree //p' | tail -n +2
}

# _gp_heal_gitdir <gitdir>: the relocated #651 heal + the Phase A
# ownership contract (see header). chmod walks BEFORE the chown walk
# (L5: the walk order decides who can plant what — after the chmod
# pass the moved tree is already group-shared, the chown pass then
# flips ownership without re-opening a plant window). Failure
# semantics (#754 a C1, closing the A9 trigger): the load-bearing
# ownership/sticky steps return 1 (the caller's rollback arm is LIVE);
# the perm-walk failures warn and continue (partial perms are
# recoverable, an un-owned or un-sticky gitdir is not).
_gp_heal_gitdir() {
    _gph_gd=$1
    find "$_gph_gd" -type d -exec chmod g+rwxs {} + 2>/dev/null ||
        ui_warn "perm walk incomplete on $_gph_gd (chmod)"
    find "$_gph_gd" -type f -exec chmod g+rw {} + 2>/dev/null ||
        ui_warn "perm walk incomplete on $_gph_gd (file chmod)"
    chown -R "$(_gp_devuser):$(_gp_group)" "$_gph_gd" || {
        ui_error "chown -R failed on $_gph_gd (group '$(_gp_group)' missing?)"
        return 1
    }
    chmod +t "$_gph_gd" || {
        ui_error "cannot set the sticky bit on $_gph_gd"
        return 1
    }
    # config-class pins (dev, no group write, no ACLs)
    if [ -e "$_gph_gd/config" ] && [ ! -L "$_gph_gd/config" ]; then
        chown "$(_gp_devuser)" "$_gph_gd/config"
        chmod 644 "$_gph_gd/config"
        setfacl -b "$_gph_gd/config" 2>/dev/null
    fi
    if [ -d "$_gph_gd/hooks" ] && [ ! -L "$_gph_gd/hooks" ]; then
        chown "$(_gp_devuser)" "$_gph_gd/hooks"
        chmod 755 "$_gph_gd/hooks"
        setfacl -b "$_gph_gd/hooks" 2>/dev/null
    fi
    # operand set (heal-index-head's measured list) -> agent
    for _gph_f in index HEAD ORIG_HEAD REBASE_HEAD packed-refs \
        MERGE_HEAD MERGE_MSG MERGE_MODE AUTO_MERGE \
        CHERRY_PICK_HEAD REVERT_HEAD; do
        [ -L "$_gph_gd/$_gph_f" ] && continue
        [ -e "$_gph_gd/$_gph_f" ] || continue
        chown -h "$(_gp_agentuser)" "$_gph_gd/$_gph_f"
        chmod 664 "$_gph_gd/$_gph_f"
    done
    # COMMIT_EDITMSG pins DEV (Phase A finding 2: config class — an
    # agent-owned one locks the dev commit out under =2)
    if [ -e "$_gph_gd/COMMIT_EDITMSG" ] && [ ! -L "$_gph_gd/COMMIT_EDITMSG" ]; then
        chown "$(_gp_devuser)" "$_gph_gd/COMMIT_EDITMSG"
        chmod 664 "$_gph_gd/COMMIT_EDITMSG"
    fi
    rm -f "$_gph_gd/FETCH_HEAD"
    return 0
}

# _gp_devgit <git-args...>: git AS THE REPOSITORY-OWNING DEVELOPER,
# never as root (#754 a A2): status/worktree-repair honor repo-config
# `core.fsmonitor` (string form runs the configured command) and hooks
# as the INVOKING user — on agent-influenceable trees that is arbitrary
# code execution as root. The dev drop follows the `_ghc_devgit` house
# pattern (sh/git-heal-core.sh) INCLUDING its `env HOME=` hop (#754 b
# D4: without it a HOME-preserving sudo makes dev-git resolve root's
# gitconfig — under a 700 /root that fails every leg); unprivileged
# runs (unit suite, the running user owns the fixtures) execute in
# place — the `-c` arms stay on every leg as defense in depth (they
# also keep a planted fsmonitor from running as the dev).
_gp_devgit() {
    if [ "$(id -u)" -eq 0 ]; then
        _gpdg_home=$(getent passwd "$(_gp_devuser)" 2>/dev/null | cut -d: -f6) ||
            true
        if [ -n "$_gpdg_home" ]; then
            sudo -u "$(_gp_devuser)" env HOME="$_gpdg_home" git "$@"
        else
            sudo -u "$(_gp_devuser)" git "$@"
        fi
    else
        git "$@"
    fi
}

# _gp_verify <proj> <gitdir>: the migration gate — pointer content,
# git functional — before anything touches the next project. git runs
# through _gp_devgit (A2: never as root).
_gp_verify() {
    _gpv_p=$1 _gpv_gd=$2
    [ "$(cat "$_gpv_p/.git" 2>/dev/null)" = "gitdir: $_gpv_gd" ] || return 1
    _gp_devgit -c safe.directory="$_gpv_p" -c safe.directory="$_gpv_gd" \
        -c core.fsmonitor=false -c core.hooksPath=/dev/null \
        -C "$_gpv_p" status --porcelain >/dev/null 2>&1 || return 1
    return 0
}

# _gp_rollback <proj> <gitdir>: pointer out, gitdir back, best-effort
# group perms. Loud but never fatal (we are already on the error
# path — the caller reports). DIR-AWARE (#754 c E2): when a planted
# DIRECTORY occupies the `.git` name (the D8 post-rename shape, or a
# verify-failure race), `rm -f` no-ops and a plain mv would move the
# gitdir INSIDE the plant with rc 0 — silently defeating the
# ROLLBACK INCOMPLETE arm. Agent-planted content under the project
# root is expendable by the kit's model: the plant is removed, then
# the gitdir lands at its name.
_gp_rollback() {
    _gpb_p=$1 _gpb_gd=$2
    if [ -d "$_gpb_p/.git" ] && [ ! -L "$_gpb_p/.git" ]; then
        rm -rf "$_gpb_p/.git" || {
            ui_error "ROLLBACK INCOMPLETE: cannot remove the planted directory at $_gpb_p/.git"
            return 1
        }
    fi
    rm -f "$_gpb_p/.git"
    mv "$_gpb_gd" "$_gpb_p/.git" 2>/dev/null || {
        ui_error "ROLLBACK INCOMPLETE: $_gpb_gd is still external; move it back to $_gpb_p/.git manually"
        return 1
    }
    find "$_gpb_p/.git" -type d -exec chmod g+rwxs {} + 2>/dev/null
    find "$_gpb_p/.git" -type f -exec chmod g+rw {} + 2>/dev/null
    return 0
}

# _gp_pform_ok <path>: FULL-path form gate (#754 a A4): absolute, no
# dot/empty segment, whitespace or glob character — the same shape
# arms _gp_root_ok carries, applied to the WHOLE project path. The
# parent-only gate (`${p%/*}`) strips a trailing `..` away from the
# checked bytes; `/root/x/..` then gated only `/root/x` while the
# migration operated one level above it.
_gp_pform_ok() {
    case "$1" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$1" in
        *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]* | *[\*\?\[]*) return 1 ;;
    esac
    return 0
}

# _gp_storage_sane <stor>: the use-time storage re-check (#754 a A5):
# form gate + no symlinked component + not a link itself. _gp_storage_init
# enforces this at creation; every later consumer (migrate/nail/revert)
# re-derives the path from env/conf and MUST re-check — an
# agent-writable storage parent (the w11 condition the init warns
# about) allows swapping the storage for a symlink between runs.
_gp_storage_sane() {
    _gpss_s=$1
    case "$_gpss_s" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$_gpss_s" in
        *..* | *//* | *[[:space:]]* | *[\*\?\[]*) return 1 ;;
    esac
    _gp_nosym "$_gpss_s" || return 1
    [ -L "$_gpss_s" ] && return 1
    return 0
}

# _gp_unnest <tgt> <proj>: recover the A7 collision-nest — the agent
# pre-created <tgt> as a directory in the storage AFTER the collision
# loop checked, so root's `mv .git <tgt>` moved the gitdir INSIDE it
# (<tgt>/.git). GNU mv refuses to overwrite a NON-EMPTY directory
# (probed, #754 c E1) — every reachable nest has ours at depth 1, and
# a `.git` inside the moved gitdir is agent junk that rides back
# harmlessly (selecting it — the retired "deepest" heuristic — would
# strand the real gitdir as an unactionable worktree-reg row).
# Detect, move ours back out, remove the agent shell, restore the
# classic layout; the caller then fails loud (next run picks the next
# suffix). rc 0 = classic layout restored.
_gp_unnest() {
    _gpun_t=$1 _gpun_p=$2
    [ -d "$_gpun_t/.git" ] || return 1
    ui_warn "collision sabotage shape: $_gpun_t already existed — gitdir nested inside"
    mv "$_gpun_t/.git" "$_gpun_p/.git" || return 1
    rmdir "$_gpun_t" 2>/dev/null ||
        ui_warn "could not remove the planted dir $_gpun_t — next run suffixes past it"
    return 0
}

# _gp_migrate_one <proj> <nailed:yes|no>: the atomic layout switch.
# Root context required (or GP_ALLOW_NONROOT). The project path is
# form-gated and .git re-checked immediately before the move (L5:
# re-check the operand immediately before acting; a symlinked .git
# is refused — only a real directory migrates).
_gp_migrate_one() {
    _gpm_p=$1 _gpm_nail=$2
    case "$_gpm_p" in
        /*) ;;
        *)
            ui_error "not an absolute path: $_gpm_p"
            return 1
            ;;
    esac
    # FULL-path form gate first (#754 a A4): a trailing `..` hides
    # from the parent-only gate below.
    if ! _gp_pform_ok "$_gpm_p"; then
        ui_error "malformed project path (dot, empty segment, whitespace, or glob): $_gpm_p"
        return 1
    fi
    _gpm_rk_rc=0
    _gp_root_ok "${_gpm_p%/*}" || _gpm_rk_rc=$?
    if [ "$_gpm_rk_rc" -ne 0 ]; then
        ui_error "project parent refused (system path, agent home, or malformed): $_gpm_p"
        return 1
    fi
    [ -d "$_gpm_p" ] || {
        ui_detail "skip: not a directory: $_gpm_p"
        return 0
    }
    [ -L "$_gpm_p/.git" ] && {
        ui_detail "skip: .git is a symlink (not migrated): $_gpm_p"
        return 0
    }
    [ -d "$_gpm_p/.git" ] || {
        ui_detail "skip: no classic .git dir: $_gpm_p"
        return 0
    }
    [ -e "$_gpm_p/.git/HEAD" ] && [ -d "$_gpm_p/.git/objects" ] || {
        ui_detail "skip: not a (common) gitdir shape: $_gpm_p"
        return 0
    }
    _gpm_stor_rc=0
    _gpm_stor=$(_gp_storage) || _gpm_stor_rc=$?
    if [ "$_gpm_stor_rc" -ne 0 ]; then
        ui_error "no storage configured (run: opk git-protection on)"
        return 1
    fi
    [ -d "$_gpm_stor" ] || {
        ui_error "storage missing: $_gpm_stor (run: opk git-protection on)"
        return 1
    }
    # use-time storage sanity (#754 a A5): form + no symlinked
    # component — init-time rigor alone trusts a too-wide window.
    if ! _gp_storage_sane "$_gpm_stor"; then
        ui_error "storage failed the use-time sanity check (symlinked component?): $_gpm_stor"
        return 1
    fi

    _gpm_name=$(basename "$_gpm_p")
    _gpm_tgt="$_gpm_stor/$_gpm_name.git"
    _gpm_n=1
    while [ -e "$_gpm_tgt" ]; do
        _gpm_n=$((_gpm_n + 1))
        _gpm_tgt="$_gpm_stor/$_gpm_name-$_gpm_n.git"
    done

    _gpm_wts=$(_gp_worktrees "$_gpm_p/.git")

    mv "$_gpm_p/.git" "$_gpm_tgt" || {
        ui_error "mv failed: $_gpm_p/.git -> $_gpm_tgt"
        return 1
    }
    # A7 collision shape: a dir planted at _gpm_tgt between the loop
    # check and the mv nests the gitdir inside it — recover ours and
    # fail loud (the next run suffixes past the planted name).
    if [ -d "$_gpm_tgt/.git" ]; then
        _gp_unnest "$_gpm_tgt" "$_gpm_p" || {
            ui_error "cannot recover the nested gitdir from $_gpm_tgt — manual recovery needed"
            return 1
        }
        ui_error "migration aborted after collision sabotage shape: $_gpm_p"
        return 1
    fi
    _gp_heal_gitdir "$_gpm_tgt" || {
        ui_error "heal failed on $_gpm_tgt -- rolling back"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    }

    # A1: the .git name is FREE here and the project dir is
    # agent-writable — never write/chown/chmod through it directly.
    # Land the pointer as a staged O_EXCL temp + rename (rename does
    # not follow symlinks: a plant at .git is replaced, not written
    # through), with the ownership/mode set on the temp BEFORE the
    # rename, and refuse when anything re-occupied the name mid-heal.
    if [ -e "$_gpm_p/.git" ] || [ -L "$_gpm_p/.git" ]; then
        ui_error "the .git name was re-occupied during the heal -- rolling back"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    fi
    _gpm_tmp=$(mktemp "$_gpm_p/.git.opkXXXXXX") || {
        ui_error "mktemp failed in $_gpm_p — cannot stage the pointer"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    }
    printf 'gitdir: %s\n' "$_gpm_tgt" >"$_gpm_tmp" || {
        ui_error "pointer write failed -- rolling back"
        rm -f "$_gpm_tmp"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    }
    chown "$(_gp_devuser):$(_gp_group)" "$_gpm_tmp" || {
        ui_error "cannot chown the staged pointer -- rolling back"
        rm -f "$_gpm_tmp"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    }
    chmod 664 "$_gpm_tmp"
    setfacl -b "$_gpm_tmp" 2>/dev/null
    mv -f "$_gpm_tmp" "$_gpm_p/.git" || {
        ui_error "pointer rename failed -- rolling back"
        rm -f "$_gpm_tmp"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    }
    # D8: rename does not follow symlinks, but a DIRECTORY planted at
    # .git after the re-occupation check makes mv -f move the temp
    # INSIDE it (rc 0, pointer at .git/.git.opk*) — the final state
    # must be a REGULAR FILE at the .git name or we roll back (the
    # dir-aware rollback removes the plant including the temp residue,
    # #754 c E2).
    if [ ! -f "$_gpm_p/.git" ]; then
        ui_error "the .git name is not a regular file after the pointer rename -- rolling back"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    fi

    # existing worktrees: their .git pointer files must follow the
    # moved gitdir (git worktree repair rewrites them; dev-dropped
    # per A2)
    if [ -n "$_gpm_wts" ]; then
        # shellcheck disable=SC2086
        _gp_devgit -c safe.directory='*' -c core.fsmonitor=false \
            -c core.hooksPath=/dev/null --git-dir="$_gpm_tgt" worktree repair $_gpm_wts >/dev/null 2>&1 ||
            ui_warn "worktree repair had issues -- check: git --git-dir=$_gpm_tgt worktree list"
        find "$_gpm_tgt/worktrees" -type d -exec chmod g+rwxs {} + 2>/dev/null
        find "$_gpm_tgt/worktrees" -type f -exec chmod g+rw {} + 2>/dev/null
    fi

    _gp_verify "$_gpm_p" "$_gpm_tgt" || {
        ui_error "verify failed -- rolling back $_gpm_p"
        _gp_rollback "$_gpm_p" "$_gpm_tgt"
        return 1
    }

    if [ "$_gpm_nail" = yes ]; then
        # Warn-only: an unnailed pointer is a degraded, reportable
        # state (the status rows surface it), never a failed
        # migration — the layout switch itself is done and verified.
        _gp_nail_one "$_gpm_p" "$_gpm_tgt" ||
            ui_warn "migrated, but the pointer stays UNNAILED: $_gpm_p (see above)"
    fi
    ui_detail "migrated: $_gpm_p -> $_gpm_tgt"
    return 0
}

# _gp_nail_one <proj> <gitdir>: chattr +i + verify. The pointer
# TARGET is re-checked (a storage CHILD — never the bare storage root,
# #754 a A3: a planted `gitdir: <storage>` pointer would otherwise
# pass every gate and seal the root itself; no symlink; gitdir
# dev-owned) before the nail — a hand-planted pointer pointing
# elsewhere never gets sealed. Storage sanity re-checked at use time
# (#754 a A5).
_gp_nail_one() {
    _gpn_p=$1 _gpn_gd=$2
    _gpn_stor_rc=0
    _gpn_stor=$(_gp_storage) || _gpn_stor_rc=$?
    [ "$_gpn_stor_rc" -eq 0 ] || return 1
    case "$_gpn_gd" in
        "$_gpn_stor"/*) ;;
        *)
            ui_warn "not nailing: $_gpn_p/.git does not point at a storage child ($_gpn_gd)"
            return 1
            ;;
    esac
    # D1 belt: a worktree registration is never sealed — a sealed
    # pointer blocks the main project's repair leg (worktree repair
    # must rewrite it). The classification excludes worktree-reg rows
    # from the sweep; this refuses direct `nail <worktree>` calls.
    # The anchor is the .git/worktrees/ SHAPE: it protects against a
    # bare "worktrees" path component, NOT against a storage whose own
    # path ends in <x>.git/worktrees (self-inflicted config — every
    # main target then carries the shape; #754 c E5).
    case "$_gpn_gd" in
        *.git/worktrees/*)
            ui_warn "not nailing: worktree registration (the main project owns it): $_gpn_gd"
            return 1
            ;;
    esac
    _gp_storage_sane "$_gpn_stor" || {
        ui_warn "not nailing: storage failed the use-time sanity check: $_gpn_stor"
        return 1
    }
    [ -L "$_gpn_gd" ] && {
        ui_warn "not nailing: gitdir is a symlink: $_gpn_gd"
        return 1
    }
    [ "$(stat -c '%U' "$_gpn_gd" 2>/dev/null)" = "$(_gp_devuser)" ] || {
        ui_warn "not nailing: gitdir not dev-owned: $_gpn_gd"
        return 1
    }
    chattr +i "$_gpn_p/.git" 2>/dev/null || {
        ui_warn "chattr +i failed on $_gpn_p/.git (fstype?) -- pointer stays unnailed"
        return 1
    }
    _gp_has_i "$_gpn_p/.git" || {
        ui_warn "lsattr does not show i on $_gpn_p/.git -- pointer stays unnailed"
        return 1
    }
    return 0
}

# _gp_revert_one <proj>: chattr -i, pointer out, gitdir back, repair.
# Kit-owned layouts only: a pointer whose target is a storage CHILD
# (never the bare storage root — #754 a A3: `gitdir: <storage>` would
# otherwise mv the WHOLE storage into the project), is not a worktree
# REGISTRATION (#754 a B4: `<stor>/<name>.git/worktrees/<id>` is the
# registration dir of a linked worktree — moving it breaks the
# worktree; the MAIN project's revert repairs its worktrees itself),
# and is dev-owned (#754 a A6: parity with the nail gate — an
# agent-planted <stor>/evil.git must never be root-mv'd into a
# project). Storage sanity re-checked at use time (#754 a A5).
_gp_revert_one() {
    _gpr_p=$1
    case "$_gpr_p" in
        /*) ;;
        *)
            ui_error "not an absolute path: $_gpr_p"
            return 1
            ;;
    esac
    # FULL-path form gate (#754 a A4 — the `x/..` shape).
    if ! _gp_pform_ok "$_gpr_p"; then
        ui_error "malformed project path (dot, empty segment, whitespace, or glob): $_gpr_p"
        return 1
    fi
    [ -f "$_gpr_p/.git" ] || {
        ui_detail "skip: no pointer file: $_gpr_p"
        return 0
    }
    [ -L "$_gpr_p/.git" ] && {
        ui_detail "skip: .git is a symlink (not ours): $_gpr_p"
        return 0
    }
    _gpr_tgt=$(sed -n 's/^gitdir: //p' "$_gpr_p/.git" 2>/dev/null | head -n 1)
    case "$_gpr_tgt" in
        /*) ;;
        *)
            ui_detail "skip: pointer target malformed (not ours): $_gpr_p"
            return 0
            ;;
    esac
    _gpr_stor_rc=0
    _gpr_stor=$(_gp_storage) || _gpr_stor_rc=$?
    _gpr_ours=1
    if [ "$_gpr_stor_rc" -eq 0 ]; then
        case "$_gpr_tgt" in
            "$_gpr_stor"/*) _gpr_ours=0 ;;
        esac
    fi
    if [ "$_gpr_ours" -ne 0 ]; then
        ui_detail "skip: pointer target outside storage (not ours): $_gpr_p"
        return 0
    fi
    # B4/D7: worktree registrations are reverted by their MAIN
    # project's repair leg, never moved themselves — the pattern
    # anchors on the .git/worktrees/ SHAPE so a storage path that
    # itself contains a "worktrees" component cannot swallow main
    # gitdirs.
    case "$_gpr_tgt" in
        *.git/worktrees/*)
            ui_detail "skip: worktree registration (its main project's revert repairs it): $_gpr_p"
            return 0
            ;;
    esac
    # A5: use-time storage sanity.
    _gp_storage_sane "$_gpr_stor" || {
        ui_error "storage failed the use-time sanity check — not reverting: $_gpr_stor"
        return 1
    }
    [ -d "$_gpr_tgt" ] || {
        ui_error "pointer target missing: $_gpr_tgt"
        return 1
    }
    [ -L "$_gpr_tgt" ] && {
        ui_error "pointer target is a symlink: $_gpr_tgt"
        return 1
    }
    # A6: ownership parity with the nail gate.
    [ "$(stat -c '%U' "$_gpr_tgt" 2>/dev/null)" = "$(_gp_devuser)" ] || {
        ui_detail "skip: gitdir not dev-owned (not ours): $_gpr_p"
        return 0
    }

    # C3: a failed chattr -i is named HERE — the manual recovery this
    # path demands starts with exactly this step.
    chattr -i "$_gpr_p/.git" 2>/dev/null ||
        ui_warn "chattr -i failed on $_gpr_p/.git — an immutable pointer blocks the removal below"
    rm -f "$_gpr_p/.git"
    mv "$_gpr_tgt" "$_gpr_p/.git" || {
        ui_error "mv back failed: $_gpr_tgt -> $_gpr_p/.git (manual recovery: sudo chattr -i $_gpr_p/.git, then mv)"
        return 1
    }
    find "$_gpr_p/.git" -type d -exec chmod g+rwxs {} + 2>/dev/null
    find "$_gpr_p/.git" -type f -exec chmod g+rw {} + 2>/dev/null
    # worktree pointers still point into the (now moved-away) storage
    # (dev-dropped git per #754 a A2)
    _gpr_wts=$(_gp_worktrees "$_gpr_p/.git")
    if [ -n "$_gpr_wts" ]; then
        # shellcheck disable=SC2086
        _gp_devgit -c safe.directory='*' -c core.fsmonitor=false \
            -c core.hooksPath=/dev/null --git-dir="$_gpr_p/.git" worktree repair $_gpr_wts >/dev/null 2>&1 ||
            ui_warn "worktree repair had issues -- check: git --git-dir=$_gpr_p/.git worktree list"
    fi
    # revert verify: .git is a DIRECTORY again — plain status check
    _gp_devgit -c safe.directory="$_gpr_p" -c core.fsmonitor=false \
        -c core.hooksPath=/dev/null -C "$_gpr_p" status --porcelain >/dev/null 2>&1 || {
        ui_warn "verify after revert failed for $_gpr_p -- check manually"
        return 1
    }
    ui_detail "reverted: $_gpr_p"
    _gp_reverted=1
    return 0
}

# _gp_projects: enumerate the .git entries under the conf roots and
# classify each project. Echo lines: "<state> <path>" with state in
#   classic          real .git directory (the unprotected layout)
#   nailed           pointer into OUR storage, chattr i present
#   unnailed         pointer into OUR storage, no i (degraded)
#   foreign-pointer  pointer somewhere else (not managed)
#   worktree-reg     a worktree registration — either a .git DIR
#                    without HEAD+objects, or (since the #754 b
#                    classification) a pointer FILE targeting
#                    <something>.git/worktrees/<id>; never actionable
#                    (the main project owns repair and nail decisions)
# Every conf line runs the reader gate first (the files.md root-op
# contract); refused lines say why and authorize nothing.
_gp_projects() {
    _gpp_conf=$(_gp_conf_path)
    [ -f "$_gpp_conf" ] || return 1
    _gpp_stor_rc=0
    _gpp_stor=$(_gp_storage) || _gpp_stor_rc=$?
    while IFS= read -r _gpp_root; do
        case "$_gpp_root" in '' | '#'*) continue ;; esac
        _gpp_rk_rc=0
        _gp_root_ok "$_gpp_root" || _gpp_rk_rc=$?
        if [ "$_gpp_rk_rc" -ne 0 ]; then
            case "$_gpp_rk_rc" in
                2) _gpp_why="agent home is never a project root" ;;
                3) _gpp_why="system path is never a project root" ;;
                *) _gpp_why="not an absolute root, or malformed (dot, empty segment, whitespace, or glob)" ;;
            esac
            printf 'refused-conf %s: %s\n' "$_gpp_why" "$_gpp_root" >&2
            continue
        fi
        [ -d "$_gp_root_norm" ] || continue
        # Loud on partial failure (the git-heal status twin): an
        # unreadable subtree silently loses its projects otherwise —
        # the note rides stderr, stdout is the data channel.
        find "$_gp_root_norm" -name .git \( -type d -o -type f \) -print 2>/dev/null ||
            printf 'git-protection: scan may be incomplete under %s (unreadable)\n' \
                "$_gp_root_norm" >&2
    done <"$_gpp_conf" | while IFS= read -r _gpp_g; do
        _gpp_proj=$(dirname "$_gpp_g")
        if [ -f "$_gpp_g" ]; then
            _gpp_t=$(sed -n 's/^gitdir: //p' "$_gpp_g" 2>/dev/null | head -n 1)
            # Worktree registrations FIRST (#754 b D1/D3/D7): a linked
            # worktree's .git is a pointer file targeting
            # <something>.git/worktrees/<id> — migrated (under the
            # storage) or classic (under the project) alike. They are
            # NEVER actionable: the nail sweep must not seal them (a
            # sealed pointer blocks the main project's repair leg —
            # D1), revert must not move them (round a B4), and status
            # must not advise nailing them. The pattern anchors on the
            # .git/worktrees/ SHAPE — it defeats a bare "worktrees"
            # path component (D7); a storage whose OWN path ends in
            # <x>.git/worktrees still swallows its mains
            # (self-inflicted config, #754 c E5 — refused nowhere,
            # documented here).
            case "$_gpp_t" in
                *.git/worktrees/*)
                    printf 'worktree-reg %s\n' "$_gpp_proj"
                    continue
                    ;;
            esac
            _gpp_ours=1
            if [ "$_gpp_stor_rc" -eq 0 ]; then
                case "$_gpp_t" in
                    "$_gpp_stor"/*) _gpp_ours=0 ;;
                esac
            fi
            if [ "$_gpp_ours" -eq 0 ]; then
                if _gp_has_i "$_gpp_g"; then
                    printf 'nailed %s\n' "$_gpp_proj"
                else
                    printf 'unnailed %s\n' "$_gpp_proj"
                fi
            else
                printf 'foreign-pointer %s\n' "$_gpp_proj"
            fi
        elif [ -e "$_gpp_g/HEAD" ] && [ -d "$_gpp_g/objects" ]; then
            printf 'classic %s\n' "$_gpp_proj"
        else
            printf 'worktree-reg %s\n' "$_gpp_proj"
        fi
    done
}

_git_protection_status() {
    ui_section "git-protection (#704 O4 pointer layout)"
    _gpst_stor_rc=0
    _gpst_stor=$(_gp_storage) || _gpst_stor_rc=$?
    case "$_gpst_stor_rc" in
        0) ui_kv "storage" "$_gpst_stor" ;;
        2) ui_kv "storage" "declined (GITDIR_STORAGE=none) — 'sudo opk git-protection on' enables" ;;
        *)
            ui_kv_warn "storage" "not configured (default would be a sibling of the first projects.conf root)"
            ;;
    esac
    _gpst_actionable=0
    # Temp-file list, not a pipeline into the loop (conventions.md
    # "Script output style": rows printed inside a pipeline's
    # subshell would bypass the tally).
    _gpst_list=$(mktemp) || {
        ui_error "mktemp failed — cannot enumerate projects"
        exit 1
    }
    # || true: an absent projects.conf (rc 1) means "nothing to
    # classify" — stderr (refused conf lines, scan notes) still flows.
    _gp_projects >"$_gpst_list" || true
    while IFS=' ' read -r _gpst_state _gpst_proj; do
        [ -n "${_gpst_state:-}" ] || continue
        case "$_gpst_state" in
            classic)
                ui_kv_bad "$_gpst_proj" "classic .git (unprotected -- the mv .git arm)"
                _gpst_actionable=1
                ;;
            nailed) ui_kv_ok "$_gpst_proj" "pointer + nailed" ;;
            unnailed)
                ui_kv_warn "$_gpst_proj" "pointer, NOT nailed (run: sudo opk git-protection nail)"
                _gpst_actionable=1
                ;;
            foreign-pointer) ui_kv "$_gpst_proj" "pointer outside storage (not managed)" ;;
            worktree-reg) ui_detail "worktree registration: $_gpst_proj" ;;
        esac
    done <"$_gpst_list"
    rm -f "$_gpst_list"
    ui_detail "nail check: lsattr is unprivileged -- this row is cheap to re-run"
    [ "$_gpst_actionable" -eq 0 ]
}

_git_protection_on() {
    ui_section "git-protection: on (#704 O4 pointer layout)"
    _gpon_stor_rc=0
    _gpon_stor=$(_gp_storage) || _gpon_stor_rc=$?
    if [ "$_gpon_stor_rc" -eq 2 ]; then
        ui_error "git-protection is declined on this host (GITDIR_STORAGE=none)"
        ui_detail "remove the marker line from install.conf, then run: opk git-protection on"
        exit 1
    fi
    if [ "$_gpon_stor_rc" -ne 0 ]; then
        ui_error "no storage path derivable — none configured, no usable projects.conf root"
        ui_detail "set one first: edit GITDIR_STORAGE in install.conf, then re-run"
        exit 1
    fi
    _gp_storage_init "$_gpon_stor" || exit 1
    _gp_persist_storage "$_gpon_stor" ||
        ui_warn "could not persist GITDIR_STORAGE (install.conf) — the heal hooks read it there"
    ui_kv "storage" "$_gpon_stor"
    # Temp-file list: the loop stays in the main shell (a pipeline
    # would fork it and swallow the exit codes — the temp-file-list
    # rule, conventions.md "Script output style").
    _gpon_list=$(mktemp) || {
        ui_error "mktemp failed — cannot enumerate migration targets"
        exit 1
    }
    _gp_projects >"$_gpon_list" || true
    _gpon_failed=0
    while IFS=' ' read -r _gpon_state _gpon_proj; do
        [ "$_gpon_state" = classic ] || continue
        _gp_migrate_one "$_gpon_proj" yes || _gpon_failed=1
    done <"$_gpon_list"
    rm -f "$_gpon_list"
    # pending pointers from earlier partial runs get their nail now
    _git_protection_nail
    if [ "$_gpon_failed" -eq 0 ]; then
        ui_success "migration complete — wholesale .git attacks (mv .git, rename-over,"
        ui_success "rm, append, hardlink) are closed for every migrated project"
    else
        ui_warn "migration had failures (see above) -- re-run: opk git-protection on"
        exit 1
    fi
    ui_detail "new clones: the git-heal post-* hooks print the adopt hint for classic trees"
    ui_detail "(needs 'opk git-heal on'; 'opk git-protection status' detects them too)"
    return 0
}

_git_protection_adopt() {
    _gpad_p=$1
    _gpad_stor_rc=0
    _gpad_stor=$(_gp_storage) || _gpad_stor_rc=$?
    if [ "$_gpad_stor_rc" -ne 0 ]; then
        ui_error "no storage configured (run: opk git-protection on)"
        exit 1
    fi
    [ -d "$_gpad_stor" ] || {
        ui_error "storage missing: $_gpad_stor (run: opk git-protection on)"
        exit 1
    }
    _gp_migrate_one "$_gpad_p" yes || exit 1
    return 0
}

# _gp_nail_path <proj>: nail ONE project's pointer (the `nail <path>`
# form) — reads the pointer target and runs the gated nail.
_gp_nail_path() {
    _gpnp_p=$1
    [ -f "$_gpnp_p/.git" ] || {
        ui_detail "skip: no pointer file: $_gpnp_p"
        return 0
    }
    _gpnp_t=$(sed -n 's/^gitdir: //p' "$_gpnp_p/.git" 2>/dev/null | head -n 1)
    if _gp_nail_one "$_gpnp_p" "$_gpnp_t"; then
        ui_detail "nailed: $_gpnp_p"
    else
        ui_detail "left unnailed: $_gpnp_p (see warnings above)"
        return 1
    fi
    return 0
}

_git_protection_nail() {
    _gpnl_stor_rc=0
    _gpnl_stor=$(_gp_storage) || _gpnl_stor_rc=$?
    if [ "$_gpnl_stor_rc" -ne 0 ]; then
        ui_error "no storage configured (run: opk git-protection on)"
        exit 1
    fi
    # `nail <path>`: the one project, no sweep.
    if [ $# -ge 1 ]; then
        _gp_nail_path "$1" || exit 1
        return 0
    fi
    _gpnl_list=$(mktemp) || {
        ui_error "mktemp failed — cannot enumerate nail targets"
        exit 1
    }
    _gp_projects >"$_gpnl_list" || true
    while IFS=' ' read -r _gpnl_state _gpnl_proj; do
        [ "$_gpnl_state" = unnailed ] || continue
        _gpnl_t=$(sed -n 's/^gitdir: //p' "$_gpnl_proj/.git" 2>/dev/null | head -n 1)
        if _gp_nail_one "$_gpnl_proj" "$_gpnl_t"; then
            ui_detail "nailed: $_gpnl_proj"
        else
            ui_detail "left unnailed: $_gpnl_proj (see warnings above)"
        fi
    done <"$_gpnl_list"
    rm -f "$_gpnl_list"
    return 0
}

# _gp_revert_all: every nailed/unnailed project back to classic.
# Returns (never exits): rc 1 when any revert failed. Counters for
# the `off` honesty gate (#754 a B2): _gpra_n reverted, _gpra_skip
# skipped-as-not-ours — since the #754 b classification, worktree
# registrations never reach this filter; a skip means a non-dev-owned
# or otherwise ungated target inside the storage (the A6 plant shape).
_gp_revert_all() {
    _gpra_list=$(mktemp) || {
        ui_error "mktemp failed — cannot enumerate revert targets"
        return 1
    }
    _gp_projects >"$_gpra_list" || true
    _gpra_failed=0
    _gpra_n=0
    _gpra_skip=0
    while IFS=' ' read -r _gpra_state _gpra_proj; do
        case "$_gpra_state" in
            nailed | unnailed)
                _gp_reverted=0
                _gp_revert_one "$_gpra_proj" || _gpra_failed=1
                if [ "$_gp_reverted" = 1 ]; then
                    _gpra_n=$((_gpra_n + 1))
                else
                    _gpra_skip=$((_gpra_skip + 1))
                fi
                ;;
        esac
    done <"$_gpra_list"
    rm -f "$_gpra_list"
    [ "$_gpra_failed" -eq 0 ]
}

_git_protection_revert() {
    _gprv_mode=${1:-}
    case "$_gprv_mode" in
        --all)
            _gp_revert_all || exit 1
            ;;
        /*)
            _gp_revert_one "$_gprv_mode" || exit 1
            ;;
        *)
            ui_error "usage: opk git-protection revert <path>|--all"
            exit 64
            ;;
    esac
    return 0
}

_git_protection_off() {
    ui_section "git-protection: off (#704 O4 pointer layout)"
    # Honesty gate before anything is dropped (#754 a B2): pointers
    # whose locator this config IS must never be orphaned by a
    # success-shaped run that reverted nothing.
    _gpof_stor_rc=0
    _gpof_stor=$(_gp_storage) || _gpof_stor_rc=$?
    _gpof_list=$(mktemp) || {
        ui_error "mktemp failed — cannot enumerate pointers"
        exit 1
    }
    _gp_projects >"$_gpof_list" || true
    _gpof_ptr=$(grep -cE '^(nailed|unnailed|foreign-pointer) ' "$_gpof_list" || true)
    if [ "$_gpof_stor_rc" -ne 0 ] && [ "${_gpof_ptr:-0}" -gt 0 ]; then
        ui_error "pointer projects exist ($_gpof_ptr) but the storage is not resolvable —"
        ui_error "the config is their only locator and is NOT dropped; fix GITDIR_STORAGE, then re-run"
        rm -f "$_gpof_list"
        exit 1
    fi
    rm -f "$_gpof_list"
    # Revert FIRST, drop config only on a clean, non-skipping success:
    # revert needs the storage config to recognize kit-owned pointers.
    if _gp_revert_all; then
        if [ "${_gpra_skip:-0}" -gt 0 ]; then
            ui_error "$_gpra_skip pointer project(s) were skipped as not kit-owned (non-dev-owned"
            ui_error "or otherwise ungated targets in the storage) — config NOT dropped;"
            ui_error "inspect 'opk git-protection status', then re-run"
            exit 1
        fi
        _gp_drop_storage || ui_warn "could not drop GITDIR_STORAGE from install.conf"
        ui_success "git-protection off — every kit-managed project is back on the"
        ui_success "classic .git layout and the storage config is dropped"
    else
        ui_error "revert had failures — config NOT dropped (the remaining pointers"
        ui_error "need it); fix them, then re-run: opk git-protection off"
        exit 1
    fi
    ui_detail "storage dir left in place (remove manually if unwanted)"
    return 0
}

git_protection_cli() {
    _gpc_cmd="${1:-}"
    # Usage validation BEFORE the sudo hop (usage errors need no
    # elevation) — the git-heal shape.
    case "$_gpc_cmd" in
        status | on | off) ;;
        adopt | nail | revert) ;;
        *)
            cat >&2 <<'EOF'
usage: opk git-protection <command> (#704 O4 pointer layout)
  status              per-project layout state (no root needed)
  on                  storage init + migrate all + nail (root)
  adopt <path>        migrate + nail one project (root)
  nail [<path>]       nail pending pointers (root)
  revert <path>|--all walk back to the classic layout (root)
  off                 revert all + drop config (root)
EOF
            exit 64
            ;;
    esac
    shift
    # Per-subcommand arity + path-shape validation (still pre-hop).
    case "$_gpc_cmd" in
        status | on | off)
            [ $# -eq 0 ] || {
                ui_error "usage: opk git-protection $_gpc_cmd (no arguments)"
                exit 64
            }
            ;;
        adopt)
            [ $# -eq 1 ] || {
                ui_error "usage: opk git-protection adopt <path>"
                exit 64
            }
            case "$1" in
                /*) ;;
                *)
                    ui_error "adopt needs an absolute project path (got: $1)"
                    exit 64
                    ;;
            esac
            ;;
        nail)
            [ $# -le 1 ] || {
                ui_error "usage: opk git-protection nail [<path>]"
                exit 64
            }
            if [ $# -eq 1 ]; then
                case "$1" in
                    /*) ;;
                    *)
                        ui_error "nail needs an absolute project path (got: $1)"
                        exit 64
                        ;;
                esac
            fi
            ;;
        revert)
            [ $# -eq 1 ] || {
                ui_error "usage: opk git-protection revert <path>|--all"
                exit 64
            }
            case "$1" in
                --all | /*) ;;
                *)
                    ui_error "revert needs --all or an absolute project path (got: $1)"
                    exit 64
                    ;;
            esac
            ;;
    esac
    # status needs no root (lsattr is unprivileged); everything else
    # auto-elevates (the config.sh pattern) through the loop-guarded
    # re-exec.
    if [ "$_gpc_cmd" != status ] && [ "$(id -u)" -ne 0 ] &&
        [ "${GP_ALLOW_NONROOT:-}" != "1" ]; then
        # Loop guard (#479 a F24, the git-heal shape): the re-exec
        # enters bin/opk again, which dispatches back into this arm
        # -- a sudo that exits 0 without actually elevating (fake
        # or broken sudo) would exec this cycle forever. Refuse on
        # the marker the re-exec itself carries.
        if [ "${OPK_GITPROTECT_ROOT:-}" = "1" ]; then
            ui_error "git-protection: sudo did not elevate — giving up"
            exit 1
        fi
        exec sudo env OPK_GITPROTECT_ROOT=1 sh "$(_gp_libdir)/bin/opk" git-protection "$_gpc_cmd" "$@"
    fi
    # Running as root from here (or the unit-suite override).
    case "$_gpc_cmd" in
        status) _git_protection_status "$@" ;;
        on) _git_protection_on "$@" ;;
        adopt) _git_protection_adopt "$@" ;;
        nail) _git_protection_nail "$@" ;;
        revert) _git_protection_revert "$@" ;;
        off) _git_protection_off "$@" ;;
    esac
}
