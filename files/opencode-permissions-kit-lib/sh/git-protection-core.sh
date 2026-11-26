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
# update_git_protection_consent) with the same lookup order, and
# management/status.sh for the `Git protection` section (#764,
# checkout-first, call-site-guarded). POSIX sh, no top-level side
# effects (definitions and comments only). The functions run in the
# CALLER's shell — every entry sets `set -u`, update.sh adds `-e` —
# and read the globals the dispatcher sets: LIBDIR, INSTALL_CONF and
# the ui_* helpers.
#
# Commands (git_protection_cli parses and validates BEFORE the sudo
# hop — usage errors need no elevation; the re-exec is loop-guarded,
# the #479 a F24 shape):
#   status              per project: classic | nailed | unnailed |
#                       foreign-pointer | worktree-reg, plus INFO
#                       rows for unreferenced storage entries (#764
#                       topic 4); rc 1 when any actionable row exists
#                       (the verdict-in-rc rule, conventions.md
#                       "Script output style"), rc 0 when
#                       protected/idle
#   on                  storage init + persist GITDIR_STORAGE, the
#                       #779 reheal sweep over existing storage
#                       entries, then migrate ALL classic projects +
#                       nail (root); an explicit `on` replaces a
#                       GITDIR_STORAGE=none decline marker (#764)
#   adopt <path>        migrate + nail ONE project (root)
#   nail [<path>]       nail pending pointers; with <path> only that
#                       project's pointer (root)
#   revert <path>|--all walk back to the classic layout (root)
#   off                 revert --all + drop GITDIR_STORAGE (root)
#
# Migrations are per-project ATOMIC: verify (pointer content + git
# status) gates every step, rollback (pointer out, gitdir back) on
# failure; existing worktrees follow the moved gitdir through `git
# worktree repair` in the same breath. Storage entries are named
# `<parent>-<basename>.git` for NEW migrations (#764 topic 1, the
# rule and its fallbacks: _gp_entry_name); same-name duplicates take
# -2, -3... suffixes. Entries migrated before #764 keep their
# basename-only names — renaming a nailed pointer is the chattr -i
# dance for no protection gain.
#
# Reporting (one renderer, two surfaces — #764 topics 2-4): every
# actionable row names the command that helps in the CURRENT storage
# state (_gp_rows), and storage children no pointer targets any more
# render as INFO rows (_gp_orphan_rows). `opk git-protection status`
# shows everything; the `opk status` section (sh/status-core.sh,
# status_section_git_protection) shows the state plus the deviations.
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
#   - Re-application (#779): every `on` / update pass re-runs this
#     heal over every existing storage entry (_gp_reheal_storage) —
#     contract-idempotent, so a contract change reaches adopted
#     gitdirs the way the baseline reaches classic ones. The one
#     recurring side effect: FETCH_HEAD (a transient git cache) is
#     re-deleted on every pass — git refetches it.
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
# sed read, never a source of a root-owned file). Quote-strip like the
# DOCTOR_USER idiom (#785 b A1): a hand-quoted value would fail every
# dev-owner gate — silent storage-reheal skips, wrong-reason refusals.
_gp_var() {
    _gpv_ic="${GP_INSTALL_CONF:-${INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}}"
    sed -n "s/^$1=//p" "$_gpv_ic" 2>/dev/null | tail -n 1 | sed 's/^"//;s/"$//'
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
# DECLINED, rc 2), else the derived default (_gp_storage_derive).
# Echoes the path on rc 0, TRAILING SLASHES STRIPPED (#765 a M2):
# every consumer recognizes the storage by a prefix match
# (`"$stor"/*` -- classification, the reference list, the nail and
# revert gates), and a value spelled `/var/www/gitdirs/` made every
# kit-written pointer look foreign while the orphan pass reported the
# live entries. The slash is spelling, not location; `/` itself stays
# as written (the pattern below needs a character in front of the
# slash). rc 1 when nothing is derivable; rc 2 when explicitly
# declined. The caller re-validates any derived path through
# _gp_root_ok before creating anything.
_gp_storage() {
    if [ -n "${GP_STORAGE:-}" ]; then
        _gps_out=$GP_STORAGE
    else
        _gps_s=$(_gp_var GITDIR_STORAGE)
        if [ "$_gps_s" = "none" ]; then
            return 2
        fi
        if [ -n "$_gps_s" ]; then
            _gps_out=$_gps_s
        else
            _gps_out=$(_gp_storage_derive) || return 1
        fi
    fi
    while :; do
        case "$_gps_out" in
            ?*/) _gps_out="${_gps_out%/}" ;;
            *) break ;;
        esac
    done
    printf '%s\n' "$_gps_out"
}

# _gp_storage_derive: the default storage — the sibling of the first
# usable conf root (/var/www/vhosts -> /var/www/gitdirs; agent-home
# and refused lines are skipped), ignoring anything configured or
# declined in install.conf. Split out of _gp_storage for the one
# caller that must derive PAST a decline marker: `on` (#764, the
# maintainer decision that an explicit `on` outranks a recorded
# decline). Echoes the path on rc 0, rc 1 when nothing is derivable.
_gp_storage_derive() {
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

# _gp_enabled: rc 0 when git-protection is ENABLED on this host — the
# storage is an explicit configuration (the GP_STORAGE test seam, or a
# GITDIR_STORAGE=<path> that `on` / the update consent persisted into
# install.conf), never the sibling default that _gp_storage merely
# DERIVES from projects.conf. The discriminator the report surfaces
# need (#764 topics 2 and 3): a derived default with classic projects
# is "not configured" — `adopt` refuses without an initialized
# storage — and `off` drops the key while the storage dir stays
# behind, so directory existence is no enable signal.
_gp_enabled() {
    [ -n "${GP_STORAGE:-}" ] && return 0
    _gpenv_v=$(_gp_var GITDIR_STORAGE)
    [ -n "$_gpenv_v" ] && [ "$_gpenv_v" != none ]
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
    # The value rides the ENVIRONMENT, never `awk -v`: a -v assignment
    # processes backslash escapes, so a storage path holding `\n`
    # would land as two lines in the root-owned install.conf while
    # mkdir had just created the literal directory (#765 a S2).
    GPPS_VAL="$_gpps_val" awk '
        /^GITDIR_STORAGE=/ { print "GITDIR_STORAGE=" ENVIRON["GPPS_VAL"]; seen = 1; next }
        { print }
        END { if (!seen) print "GITDIR_STORAGE=" ENVIRON["GPPS_VAL"] }
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

# _gp_reheal_storage <stor>: issue #779's re-application sweep — every
# EXISTING storage entry walks through the CURRENT _gp_heal_gitdir
# contract, idempotently (the fs baseline's steady-state shape for
# classic trees; contract-idempotent, not a no-op — the FETCH_HEAD
# leg re-deletes a fresh fetch's cache on every pass, git refetches).
# Before #779 the migration heal ran exactly once per
# entry, at adoption: a later change to the heal's semantics reached
# classic gitdirs through the next baseline run but left every adopted
# storage gitdir at its adoption-time state until a manual revert + on.
# Scope and gates (the storage is agent-writable, mode 3770):
#   - the storage re-runs the use-time sanity check (the
#     _gp_migrate_one discipline); a missing storage is a clean no-op
#     (the first `on` has just created an empty one);
#   - children enumerate by glob (the _gp_orphan_rows idiom — a
#     newline in a planted name cannot forge a second operand) and
#     only DEV-OWNED, gitdir-shaped REAL directories heal: the A6
#     kit-owned discriminator the nail and revert gates carry too. An
#     agent-planted entry stays the status orphan rows' business (the
#     operator inspects and removes it). The gate bounds the entry
#     SET, not a healed entry's SIZE — subtrees stay group-writable by
#     the heal's own contract, so the agent can grow one between
#     passes and the next update walks it (latency/DoS only: chown -R
#     over agent-created files REDUCES agent control, no symlink is
#     traversed);
#   - [ -L ] re-check on the entry immediately before its heal (L5:
#     the glob->heal window spans the whole loop, so the operand is
#     re-tested right before the root ops act on it).
# Failure semantics: _gp_heal_gitdir's load-bearing failures (chown,
# sticky bit) return 1 and count into _gprs_failed — the caller fails
# its pass like a failed migration: an entry that cannot hold the
# contract must not read as protected. Every other child (a file, a
# symlink, a foreign-owned or non-gitdir shape) is a silent skip:
# drift-row business belongs to the report surfaces, not the sweep.
_gp_reheal_storage() {
    _gprs_stor=$1
    _gprs_failed=0
    _gprs_n=0
    [ -d "$_gprs_stor" ] || return 0
    if ! _gp_storage_sane "$_gprs_stor"; then
        ui_warn "storage reheal skipped: the use-time sanity check failed: $_gprs_stor"
        _gprs_failed=1
        return 0
    fi
    for _gprs_e in "$_gprs_stor"/* "$_gprs_stor"/.*; do
        _gprs_name=${_gprs_e##*/}
        case "$_gprs_name" in
            . | ..) continue ;;
        esac
        # A no-match glob hands the pattern through unexpanded — the
        # existence guard drops it (the _gp_orphan_rows shape).
        [ -e "$_gprs_e" ] || [ -L "$_gprs_e" ] || continue
        # L5 first: the shape and ownership probes below follow a
        # link; the heal must never act through one.
        if [ ! -L "$_gprs_e" ] && [ -d "$_gprs_e" ] &&
            [ -e "$_gprs_e/HEAD" ] && [ -d "$_gprs_e/objects" ] &&
            [ "$(stat -c '%U' "$_gprs_e" 2>/dev/null)" = "$(_gp_devuser)" ]; then
            if _gp_heal_gitdir "$_gprs_e"; then
                _gprs_n=$((_gprs_n + 1))
            else
                _gprs_failed=$((_gprs_failed + 1))
                ui_warn "storage reheal failed on $(_gp_rowkey "$_gprs_e") — the entry keeps its ownership/sticky"
                ui_warn "drift (the perm walks already applied; see above)"
            fi
        fi
    done
    if [ "$_gprs_n" -gt 0 ]; then
        ui_detail "storage reheal: existing storage entries walked through the current"
        ui_detail "gitdir heal contract (sticky, config/hooks pins, operand set — #779): $_gprs_n"
    fi
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
# ROLLBACK INCOMPLETE arm. The deletion is sound on a verifiable
# invariant: every rollback caller runs AFTER the project's gitdir
# was moved OUT, so a non-symlink directory at the `.git` name is
# never legit project data at this point (the one theoretical
# exception — a developer `git init` racing the sub-second error-path
# window — nested silently under the pre-wave behavior, which was
# strictly worse).
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
# migration operated one level above it. rc 0: usable path; rc 1:
# refused form; rc 3: refused, the bare "/" root (#793 — the
# _gp_root_ok disposition: "/" is absolute and not malformed, it is
# the out-of-scope system root).
_gp_pform_ok() {
    case "$1" in
        /*) ;;
        *) return 1 ;;
    esac
    # A lone slash passes the absolute gate and no form arm matches
    # it (#793) — refuse with the sibling rc 3, before the form arms.
    [ "$1" = "/" ] && return 3
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
# The bare "/" root is refused too (#794, the sibling class #793
# closed for _gp_pform_ok): no form arm matches a lone slash, the
# membership compares would degenerate to /* and migrate's mv
# destination would land at the filesystem root.
_gp_storage_sane() {
    _gpss_s=$1
    case "$_gpss_s" in
        /*) ;;
        *) return 1 ;;
    esac
    [ "$_gpss_s" = "/" ] && return 1
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
# F4 (#756): the move-back carries the same dir-aware pre-clear
# _gp_rollback has (#754 c E2, the F2 invariant): the project's gitdir
# was moved OUT to the storage above, so a non-symlink DIRECTORY
# planted at the .git name in the sub-second window is never legit
# project data — a plain mv would nest ours INSIDE the plant with
# rc 0 while this helper claims "classic layout restored". A planted
# file or symlink falls to the rm -f (mv would overwrite or follow).
_gp_unnest() {
    _gpun_t=$1 _gpun_p=$2
    [ -d "$_gpun_t/.git" ] || return 1
    ui_warn "collision sabotage shape: $_gpun_t already existed — gitdir nested inside"
    if [ -d "$_gpun_p/.git" ] && [ ! -L "$_gpun_p/.git" ]; then
        rm -rf "$_gpun_p/.git" || return 1
    fi
    rm -f "$_gpun_p/.git"
    mv "$_gpun_t/.git" "$_gpun_p/.git" || return 1
    rmdir "$_gpun_t" 2>/dev/null ||
        ui_warn "could not remove the planted dir $_gpun_t — next run suffixes past it"
    return 0
}

# _gp_conf_root_p <dir>: rc 0 when <dir> is a projects.conf ROOT line
# (trailing slashes stripped — the reader gate's normalization). The
# naming rule's "directly under a conf root" test (#764 topic 1). A
# lexical compare on purpose: the migration path is form-gated
# upstream (no dot or empty segment), and a path the `on` sweep took
# from a conf line spells its directory exactly as the line does. An
# `adopt <path>` argument brings whatever spelling it was given — a
# differently spelled route to the same folder simply takes the
# prefixed name (cosmetic: a different entry name, nothing else;
# #765 a Q9). An absent or unreadable conf
# answers "no root" (rc 1): with no root to compare against, every
# project takes the prefix — the same answer as a project outside
# every conf root.
_gp_conf_root_p() {
    _gpnr_conf=$(_gp_conf_path)
    [ -f "$_gpnr_conf" ] || return 1
    while IFS= read -r _gpnr_line; do
        case "$_gpnr_line" in '' | '#'*) continue ;; esac
        _gpnr_n="$_gpnr_line"
        while :; do
            case "$_gpnr_n" in
                */) _gpnr_n="${_gpnr_n%/}" ;;
                *) break ;;
            esac
        done
        [ "$_gpnr_n" = "$1" ] && return 0
    done <"$_gpnr_conf"
    return 1
}

# _gp_entry_name <proj>: the storage entry name (without ".git") for
# a project about to migrate — "<parent>-<basename>" (#764 topic 1).
# Two checkouts sharing a basename (a main checkout and a git worktree
# of the same repository) used to collide into opaque -2, -3 suffixes,
# and an entry left behind could not be attributed to its folder. The
# rule applies to NEW migrations only: entries migrated before #764
# keep their names (renaming a nailed pointer is the chattr -i dance
# for no protection gain). Three fallbacks to the plain basename:
#   - the project sits DIRECTLY in a projects.conf root: no
#     distinguishing folder exists, and the root's own basename would
#     prefix every such entry alike (maintainer decision, #764);
#   - no parent component resolves (the caller's form gates refuse
#     such paths earlier anyway);
#   - the composed name exceeds 200 bytes: it would not fit a
#     255-byte filename (NAME_MAX on ext4/xfs, the chattr-capable
#     filesystems) next to ".git" and a collision suffix. Measured in
#     BYTES via wc -c — ${#} counts characters under UTF-8 locales.
#     The fallback covers the COMPOSED name only: a basename that is
#     itself too long for `<basename>.git` (252 bytes and more) still
#     fails at the mv, loud — as it did before #764 (#765 a S1).
# Same-name duplicates under one parent (a re-created checkout, a
# pre-#764 entry of that name) still take the -2, -3... suffix loop.
_gp_entry_name() {
    _gpen_p="$1"
    while :; do
        case "$_gpen_p" in
            */) _gpen_p="${_gpen_p%/}" ;;
            *) break ;;
        esac
    done
    _gpen_base="${_gpen_p##*/}"
    _gpen_par="${_gpen_p%/*}"
    _gpen_par="${_gpen_par##*/}"
    _gpen_c="$_gpen_par-$_gpen_base"
    if [ -n "$_gpen_base" ] && [ -n "$_gpen_par" ] &&
        ! _gp_conf_root_p "${_gpen_p%/*}" &&
        [ "$(printf '%s' "$_gpen_c" | wc -c)" -le 200 ]; then
        printf '%s\n' "$_gpen_c"
    else
        printf '%s\n' "$_gpen_base"
    fi
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
    # from the parent-only gate below. rc 3 is the bare-"/" refusal
    # (#793): "/" has no parent, so the parent gate below could
    # never name that cause.
    _gpm_pf_rc=0
    _gp_pform_ok "$_gpm_p" || _gpm_pf_rc=$?
    case "$_gpm_pf_rc" in
        0) ;;
        3)
            ui_error "project path refused (the whole filesystem is out of scope): $_gpm_p"
            return 1
            ;;
        *)
            ui_error "malformed project path (dot, empty segment, whitespace, or glob): $_gpm_p"
            return 1
            ;;
    esac
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
    # use-time storage sanity (#754 a A5): form + bare-/ refusal
    # (#794) + no symlinked component — init-time rigor alone trusts
    # a too-wide window.
    if ! _gp_storage_sane "$_gpm_stor"; then
        ui_error "storage failed the use-time sanity check (bare /, malformed form, or symlinked component?): $_gpm_stor"
        return 1
    fi

    # entry name: <parent>-<basename> for nested projects, the plain
    # basename directly under a conf root and for over-long names
    # (#764 topic 1, _gp_entry_name).
    _gpm_name=$(_gp_entry_name "$_gpm_p")
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
    # FULL-path form gate (#754 a A4 — the `x/..` shape). rc 3 is
    # the bare-"/" refusal (#793): a lone slash must not reach the
    # pointer probes below.
    _gpr_pf_rc=0
    _gp_pform_ok "$_gpr_p" || _gpr_pf_rc=$?
    case "$_gpr_pf_rc" in
        0) ;;
        3)
            ui_error "project path refused (the whole filesystem is out of scope): $_gpr_p"
            return 1
            ;;
        *)
            ui_error "malformed project path (dot, empty segment, whitespace, or glob): $_gpr_p"
            return 1
            ;;
    esac
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
# Optional argument <ref-file> (#764 topic 4): when given, every
# pointer whose target lies INSIDE the storage appends the storage
# CHILD it keeps alive (one name per line) — mains and worktree
# registrations alike, because a surviving worktree still uses the
# common gitdir after its main checkout is gone. The orphan pass
# (_gp_orphan_rows) diffs that list against the storage's children.
# The comparison is LEXICAL on the target as written (leading slashes
# collapsed): kit-written and git-repaired pointers are canonical, and
# an unusual spelling can only ever produce an INFO row, never a root
# operation.
# rc contract (#775 a S1): 0 = enumerated (rows on stdout); 1 = absent
# projects.conf — nothing to classify, benign by design since #704;
# 2 = REFUSED (python3 missing or broken, staging mktemp failed, the
# NUL reader failed) — a loud failure whose stdout stays empty, and
# every sweep caller MUST treat it as failure: never a success banner,
# never a config drop over an unenumerated tree (the #754 a B2
# honesty gate counts pointers through this enumeration — a refused
# run reads as zero and must not authorize `off`'s drop).
_gp_projects() {
    _gpp_ref="${1:-}"
    _gpp_conf=$(_gp_conf_path)
    [ -f "$_gpp_conf" ] || return 1
    _gpp_stor_rc=0
    _gpp_stor=$(_gp_storage) || _gpp_stor_rc=$?
    # A8 (#756): NUL-delivered enumeration. The former
    # `find -print | while read` split a .git under a newline-bearing
    # path into garbage rows — and a fragment could name a real
    # classic repo one level up: an unintended MIGRATION, a root op
    # that SUCCEEDS instead of failing loud. The find output is staged
    # NUL-separated and a python3 reader hands the classifier whole
    # paths (dash's read has no -d; pure-POSIX NUL splitting does not
    # exist). A path carrying a NEWLINE is refused loud and produces
    # no row: it can never migrate (the form gate refuses whitespace)
    # and its row would corrupt the line protocol — attacker noise,
    # never a legit checkout (the _fsb_heal_git doctrine,
    # fs-baseline.sh). Other control bytes (a tab) keep flowing: their
    # rows render through _gp_rowkey/_gp_disp at REPORT time (#765
    # b F1, #756). The git-heal sweeps keep the newline idiom
    # DELIBERATELY — in their ON-sweep a split fragment usually
    # vanishes at the pointer resolver's regular-file gate (#777,
    # silently — attacker noise gets no row); when a fragment happens
    # to name an existing regular file it renders an uncounted skip
    # note ("no gitdir: line: <fragment>") — either way, never a heal
    # attempt; pre-#777 the on-sweep
    # healed attacker-planted garbage in-tree and the status twin
    # dropped the fragment's rows silently — while this enumerator's rows drive
    # migrations: the damage profiles differ, hence split idioms by
    # risk class (#775 a A5 scopes this claim). python3 missing or the reader failing refuses
    # the WHOLE enumeration: authorize nothing, say why (the
    # reader-gate doctrine) — never a silent newline downgrade.
    if ! command -v python3 >/dev/null 2>&1; then
        printf 'git-protection: python3 unavailable — cannot enumerate .git entries safely (nothing authorized)\n' >&2
        return 2
    fi
    _gpp_nul=$(mktemp) || {
        printf 'git-protection: mktemp failed (is $TMPDIR writable?) — no enumeration, nothing authorized\n' >&2
        return 2
    }
    _gpp_txt=$(mktemp) || {
        printf 'git-protection: mktemp failed (is $TMPDIR writable?) — no enumeration, nothing authorized\n' >&2
        rm -f "$_gpp_nul"
        return 2
    }
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
        find "$_gp_root_norm" -name .git \( -type d -o -type f \) -print0 >>"$_gpp_nul" 2>/dev/null ||
            printf 'git-protection: scan may be incomplete under %s (unreadable)\n' \
                "$_gp_root_norm" >&2
    done <"$_gpp_conf"
    if ! python3 -I -c '
import sys
with open(sys.argv[1], "rb") as f:
    data = f.read()
paths = data.split(b"\0")
# find -print0 NUL-terminates EVERY entry: a tail without its NUL is a
# truncated write (SIGKILL/ENOSPC mid-staging) — drop it, one missing
# row beats one row for a path that does not exist (#775 a S2).
if data and not data.endswith(b"\0"):
    paths = paths[:-1]
for path in paths:
    if not path:
        continue
    if b"\n" in path:
        esc = "".join("\\x%02x" % b for b in path)
        sys.stderr.write(
            "git-protection: refusing a .git under a newline-bearing path"
            " (skipped — rename the folder): " + esc + "\n")
        continue
    sys.stdout.buffer.write(path + b"\n")
' "$_gpp_nul" >"$_gpp_txt"; then
        printf 'git-protection: the NUL reader failed — cannot enumerate .git entries safely (nothing authorized)\n' >&2
        rm -f "$_gpp_nul" "$_gpp_txt"
        return 2
    fi
    rm -f "$_gpp_nul"
    while IFS= read -r _gpp_g; do
        _gpp_proj=$(dirname "$_gpp_g")
        if [ -f "$_gpp_g" ]; then
            _gpp_t=$(sed -n 's/^gitdir: //p' "$_gpp_g" 2>/dev/null | head -n 1)
            # referenced storage child, for the orphan pass (#764
            # topic 4) — recorded before any classification branches.
            if [ -n "$_gpp_ref" ] && [ "$_gpp_stor_rc" -eq 0 ]; then
                case "$_gpp_t" in
                    "$_gpp_stor"/*)
                        _gpp_c="${_gpp_t#"$_gpp_stor"}"
                        while :; do
                            case "$_gpp_c" in
                                /*) _gpp_c="${_gpp_c#/}" ;;
                                *) break ;;
                            esac
                        done
                        _gpp_c=${_gpp_c%%/*}
                        if [ -n "$_gpp_c" ]; then
                            printf '%s\n' "$_gpp_c" >>"$_gpp_ref"
                        fi
                        ;;
                esac
            fi
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
    done <"$_gpp_txt"
    rm -f "$_gpp_txt"
}

# _gp_q <word>: the word as a PASTE-SAFE shell word for a command the
# report prints (#765 a S3) — unquoted when it is plain (letters,
# digits and `._/+-`, not starting with a dash), single-quoted with
# every embedded quote escaped (`'\''`, the POSIX spelling) otherwise;
# rc 1, nothing printed, for a word carrying a control byte (no
# quoting makes a raw newline or escape byte safe to render in a
# report row). A printed `sudo …` line is data until a developer
# pastes it — then it is shell structure, and a project path or a
# storage entry name is agent-influenceable (group-writable trees): an
# unquoted `$(…)` or `;` in a name would run at paste time.
_gp_q() {
    case "$1" in
        *[[:cntrl:]]*) return 1 ;;
    esac
    case "$1" in
        '' | -* | *[!A-Za-z0-9._/+-]*) ;;
        *)
            printf '%s\n' "$1"
            return 0
            ;;
    esac
    _gpq_out="'"
    _gpq_rest=$1
    while :; do
        case "$_gpq_rest" in
            *"'"*)
                _gpq_out="$_gpq_out${_gpq_rest%%"'"*}'\\''"
                _gpq_rest=${_gpq_rest#*"'"}
                ;;
            *)
                _gpq_out="$_gpq_out$_gpq_rest'"
                break
                ;;
        esac
    done
    printf '%s\n' "$_gpq_out"
    return 0
}

# _gp_rows <list> <all|gaps> <adopt|on>: render the per-project
# rows for a classified list (_gp_projects output) — the ONE renderer
# behind both report surfaces: `opk git-protection status` (mode all:
# every state, worktree registrations as detail lines) and the
# `opk status` section (mode gaps: deviations only — the protected
# projects are the state row's count there, #764 topic 2). Rows print
# in the MAIN shell from the temp-file list (never inside a pipeline:
# the ui counters a summary tallies die in a subshell, conventions.md
# "Script output style"). Every actionable row names the command that
# helps in the CURRENT storage state (#764 topic 3 — the house style
# of opk status / opk doctor), selected by the third argument:
#   adopt     storage initialized: sudo opk git-protection adopt <path>
#   anything else (`on`)  no initialized storage — `adopt` refuses
#             without one, while `on` sets it up, migrates everything
#             and (since #764) replaces a GITDIR_STORAGE=none marker
# The path in a command goes through _gp_q, and a path the migration
# form gate refuses (whitespace, glob character, dot segment —
# `_gp_pform_ok`) gets NO command: `adopt` would refuse it, so the row
# names the rename instead (#765 a S3). A no-command row whose path
# carries a CONTROL byte renders its key through _gp_disp — that byte
# must not reach the terminal raw (#765 b F1); a merely whitespace-
# bearing path keeps its key as is (a UTF-8 name must not turn into
# question marks).
# Two or more classic rows under `adopt` add the all-at-once hint
# (`on` migrates every project in one run — the better fit there).
# _gp_rows_actionable is the callers' counter (1 when a classic or
# unnailed row rendered — the status rc); _gp_rows_classic is this
# function's own, it drives the all-at-once hint.
_gp_rows() {
    _gprl_list=$1 _gprl_mode=$2
    _gp_rows_actionable=0
    _gp_rows_classic=0
    case "$3" in
        adopt) _gprl_fix=" -- run: sudo opk git-protection adopt" ;;
        *) _gprl_fix=" -- run: sudo opk git-protection on" ;;
    esac
    while IFS=' ' read -r _gprl_state _gprl_proj; do
        [ -n "${_gprl_state:-}" ] || continue
        case "$_gprl_state" in
            classic)
                _gprl_q=""
                if _gp_pform_ok "$_gprl_proj" && _gprl_q=$(_gp_q "$_gprl_proj"); then
                    _gprl_msg="classic .git (unprotected -- the mv .git arm)$_gprl_fix"
                    [ "$3" = adopt ] && _gprl_msg="$_gprl_msg $_gprl_q"
                    ui_kv_bad "$_gprl_proj" "$_gprl_msg"
                else
                    _gprl_key=$(_gp_rowkey "$_gprl_proj")
                    ui_kv_bad "$_gprl_key" "classic .git (unprotected -- the mv .git arm) -- no command""\
 for this path"
                    ui_detail "the path fails a migration gate or cannot be pasted safely (whitespace, glob"
                    ui_detail "character, dot segment or control byte) -- rename the folder, then adopt it"
                fi
                _gp_rows_actionable=1
                _gp_rows_classic=$((_gp_rows_classic + 1))
                ;;
            unnailed)
                _gprl_q=$(_gp_q "$_gprl_proj") || _gprl_q=""
                if [ -n "$_gprl_q" ]; then
                    ui_kv_warn "$_gprl_proj" "pointer, NOT nailed (run: sudo opk git-protection nail $_gprl_q)"
                else
                    _gprl_key=$(_gp_rowkey "$_gprl_proj")
                    ui_kv_warn "$_gprl_key" "pointer, NOT nailed -- no command for this path"
                    ui_detail "the path carries a control byte -- rename the folder, then nail it"
                fi
                _gp_rows_actionable=1
                ;;
            nailed)
                [ "$_gprl_mode" = all ] &&
                    ui_kv_ok "$(_gp_rowkey "$_gprl_proj")" "pointer + nailed"
                ;;
            foreign-pointer)
                [ "$_gprl_mode" = all ] &&
                    ui_kv "$(_gp_rowkey "$_gprl_proj")" "pointer outside storage (not managed)"
                ;;
            worktree-reg)
                [ "$_gprl_mode" = all ] &&
                    ui_detail "worktree registration: $(_gp_rowkey "$_gprl_proj")"
                ;;
        esac
    done <"$_gprl_list"
    if [ "$_gp_rows_classic" -ge 2 ] && [ "$3" = adopt ]; then
        ui_detail "several projects -- one run adopts them all: sudo opk git-protection on"
    fi
    return 0
}

# _gp_disp <string>: a display-safe copy of an agent-influenced name —
# every byte outside printable ASCII becomes "?" (control characters
# included: a storage entry name is agent-writable input, and a raw
# newline or escape byte in a report row would forge or corrupt rows).
# LC_ALL=C pins the class to its byte meaning across locales.
_gp_disp() {
    printf '%s' "$1" | LC_ALL=C tr -c '[:print:]' '?'
}

# _gp_rowkey <path>: the ROW-KEY form of a project path (#756, the
# #765 b F1 class): a path carrying a control byte renders through
# _gp_disp — the byte must not reach the terminal raw (it could forge
# or clear report rows); every other path keeps its key AS IS: _gp_disp
# would also turn a non-ASCII letter into "?", and a merely
# whitespace-bearing path must stay readable (#765 round c G1 — a
# space is not a control byte and keeps its exact key).
_gp_rowkey() {
    case "$1" in
        *[[:cntrl:]]*) _gp_disp "$1" ;;
        *) printf '%s\n' "$1" ;;
    esac
}

# _gp_orphan_rows <storage> <ref-file>: INFO rows for storage children
# no pointer targets any more (#764 topic 4 — a project removed
# without `revert`, a pilot-era leftover). Plain ui_kv/ui_detail rows,
# never counted and never actionable: an unreferenced entry is
# harmless (nothing discovers it) and the removal is the developer's
# call after inspecting it. Display-only — no root operation reads
# this list. Three safety properties, all because the storage is
# AGENT-WRITABLE (mode 3770):
#   - names are enumerated by glob, never line-split (a newline in a
#     name cannot forge a second row) and rendered through _gp_rowkey
#     (a control byte masks, a non-ASCII name stays readable — #775
#     a A4, the same key contract as project rows);
#   - the removal hint prints the path through _gp_q (plain names
#     bare, anything else single-quoted — never a raw shell
#     metacharacter a developer would paste) and never with a trailing
#     slash: `rm -rf <link>/` would follow a planted symlink and
#     delete the target's content; a name carrying a control byte gets
#     no command at all;
#   - an absent or unreadable reference list skips the pass with a
#     counted row instead of reporting every child unreferenced (a
#     caller bug must not read as N orphans).
# Scope: "unreferenced" means no pointer under the CONFIGURED roots
# targets it — a project adopted outside every conf root, or under a
# root since removed from projects.conf, still uses its entry.
_gp_orphan_rows() {
    _gpo_stor=$1 _gpo_ref=$2
    [ -d "$_gpo_stor" ] || return 0
    [ -r "$_gpo_ref" ] || {
        ui_kv_warn "git-protection" "unreferenced-entry check skipped (no readable reference list)"
        return 0
    }
    for _gpo_e in "$_gpo_stor"/* "$_gpo_stor"/.*; do
        _gpo_n=${_gpo_e##*/}
        case "$_gpo_n" in
            . | ..) continue ;;
        esac
        [ -e "$_gpo_e" ] || [ -L "$_gpo_e" ] || continue
        grep -qxF -- "$_gpo_n" "$_gpo_ref" && continue
        _gpo_kind=""
        [ -L "$_gpo_e" ] && _gpo_kind=" (a symlink)"
        ui_kv "$(_gp_rowkey "$_gpo_e")" "unreferenced storage entry$_gpo_kind -- no pointer under the""\
 configured roots targets it"
        if _gpo_q=$(_gp_q "$_gpo_e"); then
            ui_detail "inspect, then remove: sudo rm -rf $_gpo_q"
        else
            ui_detail "inspect it by hand -- the name carries a control byte, so no removal command is printed"
        fi
    done
    return 0
}

# _gp_declined_rows <key>: the declined-state row pair — ONE wording
# for both report surfaces (#765 a Q5): a counted warn plus the enable
# command. A decline is a recorded "no", and the reports count it
# exactly like "never configured": until `on` runs, the wholesale swap
# stays possible for every project. <key> is each surface's row label
# (`storage` in the command, `git-protection` in the status section).
_gp_declined_rows() {
    ui_kv_warn "$1" "declined (GITDIR_STORAGE=none) — every project keeps a classic .git (wholesale swap possible)"
    ui_detail "run: sudo opk git-protection on (the command replaces the decline marker)"
}

_git_protection_status() {
    ui_section "git-protection (#704 O4 pointer layout)"
    _gpst_stor_rc=0
    _gpst_stor=$(_gp_storage) || _gpst_stor_rc=$?
    # The classic rows' fix command follows the storage state (#764
    # topic 3): `adopt` works only with an initialized storage; `on`
    # works in every other state — a declined marker included, the
    # explicit command replaces it.
    _gpst_fix=on
    case "$_gpst_stor_rc" in
        2)
            _gp_declined_rows storage
            ;;
        0)
            if _gp_enabled; then
                if [ -d "$_gpst_stor" ]; then
                    _gpst_fix=adopt
                    ui_kv "storage" "$_gpst_stor"
                else
                    ui_kv_warn "storage" "configured but missing: $_gpst_stor"
                    ui_detail "re-create it: sudo opk git-protection on"
                fi
            else
                ui_kv_warn "storage" "not configured (derived default: $_gpst_stor)"
                ui_detail "run: sudo opk git-protection on"
            fi
            ;;
        *)
            ui_kv_warn "storage" "not configured (default would be a sibling of the first projects.conf root)"
            ui_detail "run: sudo opk git-protection on"
            ;;
    esac
    _gpst_actionable=0
    # Temp files, not a pipeline into the loop (conventions.md
    # "Script output style": rows printed inside a pipeline's subshell
    # would bypass the tally).
    _gpst_list=$(mktemp) || {
        ui_error "mktemp failed — cannot enumerate projects"
        exit 1
    }
    _gpst_ref=$(mktemp) || {
        ui_error "mktemp failed — cannot collect pointer targets"
        rm -f "$_gpst_list"
        exit 1
    }
    # || true: an absent projects.conf (rc 1) means "nothing to
    # classify" — stderr (refused conf lines, scan notes) still flows.
    _gpst_prc=0
    _gp_projects "$_gpst_ref" >"$_gpst_list" || _gpst_prc=$?
    if [ "$_gpst_prc" -ge 2 ]; then
        ui_error "the project enumeration refused — no rows, no health claim (see the note above)"
        rm -f "$_gpst_ref" "$_gpst_list"
        exit 1
    fi
    _gp_rows "$_gpst_list" all "$_gpst_fix"
    _gpst_actionable=$_gp_rows_actionable
    [ "$_gpst_stor_rc" -eq 0 ] && _gp_orphan_rows "$_gpst_stor" "$_gpst_ref"
    rm -f "$_gpst_ref" "$_gpst_list"
    ui_detail "nail check: lsattr is unprivileged -- this row is cheap to re-run"
    [ "$_gpst_actionable" -eq 0 ]
}

_git_protection_on() {
    ui_section "git-protection: on (#704 O4 pointer layout)"
    _gpon_stor_rc=0
    _gpon_stor=$(_gp_storage) || _gpon_stor_rc=$?
    if [ "$_gpon_stor_rc" -eq 2 ]; then
        # A recorded decline never blocks the explicit command
        # (maintainer decision, #764): the marker's job is to keep
        # `opk update` from asking again — `on` IS the consent. The
        # default storage is derived past the marker; persisting it
        # below replaces the `none` line, so every later run — and
        # the status rows that say "'sudo opk git-protection on'
        # enables" — finds the feature enabled.
        _gpon_stor_rc=0
        _gpon_stor=$(_gp_storage_derive) || _gpon_stor_rc=$?
        if [ "$_gpon_stor_rc" -ne 0 ]; then
            ui_error "git-protection is declined on this host (GITDIR_STORAGE=none) and no default"
            ui_error "storage is derivable (no usable projects.conf root)"
            ui_detail "replace that line with an absolute storage path, then run: opk git-protection on"
            exit 1
        fi
        ui_info "git-protection was declined on this host (GITDIR_STORAGE=none) -- this run enables it"
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
    _gpon_prc=0
    _gp_projects >"$_gpon_list" || _gpon_prc=$?
    if [ "$_gpon_prc" -ge 2 ]; then
        ui_error "the project enumeration refused — nothing migrated (see the note above)"
        rm -f "$_gpon_list"
        exit 1
    fi
    _gpon_failed=0
    # #779 re-application sweep: existing storage entries first, so
    # entries migrated by THIS run heal exactly once (their own
    # _gp_migrate_one heal) and adoption-era entries reach the CURRENT
    # contract. A heal that cannot hold the contract fails the pass
    # like a failed migration.
    _gp_reheal_storage "$_gpon_stor"
    if [ "${_gprs_failed:-0}" -ne 0 ]; then
        _gpon_failed=1
    fi
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
        ui_warn "pass had failures (migration or storage reheal — see above) -- re-run: opk git-protection on"
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
    _gpnl_prc=0
    _gp_projects >"$_gpnl_list" || _gpnl_prc=$?
    if [ "$_gpnl_prc" -ge 2 ]; then
        ui_error "the project enumeration refused — nothing nailed (see the note above)"
        rm -f "$_gpnl_list"
        exit 1
    fi
    while IFS=' ' read -r _gpnl_state _gpnl_proj; do
        [ "$_gpnl_state" = unnailed ] || continue
        _gpnl_t=$(sed -n 's/^gitdir: //p' "$_gpnl_proj/.git" 2>/dev/null | head -n 1)
        if _gp_nail_one "$_gpnl_proj" "$_gpnl_t"; then
            ui_detail "nailed: $(_gp_rowkey "$_gpnl_proj")"
        else
            ui_detail "left unnailed: $(_gp_rowkey "$_gpnl_proj") (see warnings above)"
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
    _gpra_prc=0
    _gp_projects >"$_gpra_list" || _gpra_prc=$?
    if [ "$_gpra_prc" -ge 2 ]; then
        ui_error "the project enumeration refused — nothing reverted (see the note above)"
        rm -f "$_gpra_list"
        return 1
    fi
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
    _gpof_prc=0
    _gp_projects >"$_gpof_list" || _gpof_prc=$?
    if [ "$_gpof_prc" -ge 2 ]; then
        ui_error "the project enumeration refused — config NOT dropped, nothing reverted (see the note above)"
        rm -f "$_gpof_list"
        exit 1
    fi
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
  on                  storage init + re-heal entries + migrate all + nail (root)
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
