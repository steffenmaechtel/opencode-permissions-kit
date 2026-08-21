# shellcheck shell=sh
# opencode permissions kit -- ddev-handover.sh
#
# Shared handover for everything ddev must OWN while running as the
# opencode user. ddev chmods its target directories UNCONDITIONALLY
# (pkg/ddevapp/typo3.go: writeTypo3SettingsFile does util.Chmod(dir, 0755)
# before writing) — there is no writability check that group permissions
# could satisfy, and chmod is owner-only on Linux. So besides .ddev/ the
# app-type's settings directories must belong to the ddev user too:
#
#   .ddev/          at any depth under a registered root (a root is
#                   usually a parent folder of several projects), but
#                   NEVER inside vendor/ or node_modules/ (packages
#                   shipping a .ddev test fixture are not projects —
#                   mirrors the hosts-scan pruning, issue #21)
#   settings dirs   derived from the project's .ddev/config.yaml `type:`:
#                     typo3     -> config/system, <docroot>/typo3conf,
#                                  typo3conf (covers composer v12+,
#                                  legacy v12 system/, and v11-)
#                     drupal*/backdrop -> <docroot>/sites/default
#                     magento*  -> app/etc
#   project root    the directory INODE itself (never recursive) — only
#                   for typo3 projects whose TYPO3 is not yet installed
#                   (fresh clone, no vendor/): ddev's settings-path
#                   fallback then targets the APP ROOT, and its chmod
#                   needs ownership. Handed BACK to the developer once
#                   TYPO3 is detected (see ddev_handover_project_root).
#
# Everything is best-effort (|| true) and idempotent. POSIX sh, SOURCED
# (never executed) by install.sh, update.sh and config.sh (projects add,
# refresh, handover). Callers run as root (or via sudo) — plain chown is
# fine. No logging here: the functions echo their actions, callers wrap
# them with their own log calls as needed.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/ddev-handover.sh.
#
# DEV-OWNED MODE (docs/design/ddev-dev-owned-projects.md): when enabled
# (DDEV_DEV_OWNED=true or the install.conf stamp, see
# ddev_devowned_enabled), the scan also writes
# disable_settings_management: true into each project's .ddev/config.yaml.
# A FLAGGED project (repo-committed or mode-written) is dev-owned: ddev
# then never chmods/writes outside .ddev/ (early return in ddev's
# CreateSettingsFile, apptypes.go:329), so settings dirs + project root
# belong to the DEVELOPER permanently (2775/664 via the group baseline)
# and are handed BACK instead of over. Unflagged projects keep the
# handover logic below verbatim.

# ddev_devowned_enabled: true when the dev-owned mode is on — either the
# DDEV_DEV_OWNED variable (set by install.sh before its stamp exists) or
# the install.conf stamp (config.sh/update.sh/hook read it implicitly).
# OPK_INSTALL_CONF overrides the stamp path for tests.
ddev_devowned_enabled() {
    case "${DDEV_DEV_OWNED:-}" in
        true|TRUE|1|yes) return 0 ;;
    esac
    _dve_conf="${OPK_INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}"
    [ -f "$_dve_conf" ] && grep -qE '^DDEV_DEV_OWNED=(true|TRUE|1|yes)$' "$_dve_conf"
}

# ddev_devowned_flagged <project-dir>: true when the project's committed
# .ddev/config.yaml carries a top-level disable_settings_management: true
# — the per-project source of truth, regardless of the kit mode.
ddev_devowned_flagged() {
    [ -f "${1:-}/.ddev/config.yaml" ] || return 1
    sed -n 's/^disable_settings_management:[[:space:]]*//p' "$1/.ddev/config.yaml" \
        | head -1 | tr -d ' \t"'"'" | grep -qx true
}

# ddev_devowned_flag <project-dir>: append the top-level key to
# .ddev/config.yaml IFF the file exists and the key is absent (one line,
# idempotent — the file is committed team content, the kit adds exactly
# this key and nothing else). Caller echoes/prints; run as root.
ddev_devowned_flag() {
    [ -f "${1:-}/.ddev/config.yaml" ] || return 0
    if grep -q '^disable_settings_management:' "$1/.ddev/config.yaml"; then
        return 0
    fi
    # Guarantee a trailing newline: without it the appended comment would
    # join the file's last line.
    [ -n "$(tail -c1 "$1/.ddev/config.yaml" 2>/dev/null)" ] && printf '\n' >> "$1/.ddev/config.yaml"
    {
        printf '# opencode permissions kit: dev-owned mode — ddev must not\n'
        printf '# chmod/write settings files outside .ddev/ (permanent 2775/664).\n'
        printf 'disable_settings_management: true\n'
    } >> "$1/.ddev/config.yaml"
    chmod g+w "$1/.ddev/config.yaml" 2>/dev/null || true
    echo "  dev-owned flag written: $1/.ddev/config.yaml (disable_settings_management: true — commit it)"
    return 0
}

# ddev_type_settings_dirs <project-dir>: echoes the settings dirs ddev
# chmods for the project's app type (empty for unknown types).
ddev_type_settings_dirs() {
    dts_proj="${1:-}"
    [ -n "$dts_proj" ] && [ -d "$dts_proj/.ddev" ] || return 0
    [ -f "$dts_proj/.ddev/config.yaml" ] || return 0
    dts_type=$(sed -n 's/^type:[[:space:]]*//p' "$dts_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    dts_docroot=$(sed -n 's/^docroot:[[:space:]]*//p' "$dts_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    [ -n "$dts_docroot" ] || dts_docroot="."
    case "$dts_type" in
        typo3)
            echo "config/system $dts_docroot/typo3conf typo3conf"
            ;;
        drupal*|backdrop)
            echo "$dts_docroot/sites/default"
            ;;
        magento*)
            echo "app/etc"
            ;;
    esac
    return 0
}

# ddev_handover_project_root <project-dir> <oc-user> <group> [dev-user]
# Manages the project's ROOT DIRECTORY (the inode only, never its
# contents) for the TYPO3 bootstrap case.
#
# Why: a fresh `git clone` made by the developer with the kit's umask 002
# + setgid parent is dev-owned mode 2775. Until TYPO3 is detectable
# (vendor/ absent), ddev's setTypo3SiteSettingsPaths fallback puts the
# settings file at the APP ROOT (pkg/ddevapp/typo3.go: "As long as TYPO3
# is not installed ..."), and CreateSettingsFile then chmods
# Dir(SiteSettingsPath) — the project root — to 0755 (apptypes.go).
# util.Chmod skips only when Perm() == 0755 EXACTLY, so 2775 fires a real
# chmod; chmod is owner-only, the dir belongs to dev, ddev runs as the
# kit user => EPERM, and `ddev start` aborts BEFORE composer install
# could ever make the app detectable (bootstrap deadlock).
#
# The rule (mirrors ddev's own detection, see ddev_typo3_detected):
#   undetected  -> root belongs to <oc-user>, mode 2755: Perm() == 0755
#                  makes ddev's chmod a structural no-op (bootstrap can
#                  create the root-level settings file as owner). No ACL
#                  entry with w: any group-class write would raise the
#                  mask, Perm() would read 0775 again and ddev's next
#                  chmod would reset the mask — capping the developer
#                  anyway. Top-level file creation is therefore
#                  oc-only during bootstrap; files themselves stay
#                  group-writable.
#   detected    -> ddev targets the real settings dirs instead
#                  (config/system, typo3conf — handled above), never the
#                  root: hand the root BACK to [dev-user] with 2775 so
#                  the developer regains full top-level write access.
#                  Only roots currently owned by <oc-user> are touched.
ddev_handover_project_root() {
    dhq_proj="${1:-}"
    dhq_user="${2:-}"
    dhq_group="${3:-}"
    dhq_dev="${4:-}"
    [ -n "$dhq_proj" ] && [ -d "$dhq_proj" ] || return 0
    [ -f "$dhq_proj/.ddev/config.yaml" ] || return 0
    dhq_type=$(sed -n 's/^type:[[:space:]]*//p' "$dhq_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    [ "$dhq_type" = "typo3" ] || return 0
    dhq_docroot=$(sed -n 's/^docroot:[[:space:]]*//p' "$dhq_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    [ -n "$dhq_docroot" ] || dhq_docroot="."
    if ddev_typo3_detected "$dhq_proj" "$dhq_docroot"; then
        if [ -n "$dhq_dev" ] && [ "$(stat -c %U "$dhq_proj" 2>/dev/null)" = "$dhq_user" ]; then
            chown "$dhq_dev:$dhq_group" "$dhq_proj" 2>/dev/null || true
            chmod 2775 "$dhq_proj" 2>/dev/null || true
            echo "  project-root handback: $dhq_proj -> $dhq_dev (TYPO3 detected, ddev no longer targets the root)"
        fi
    else
        chown "$dhq_user:$dhq_group" "$dhq_proj" 2>/dev/null || true
        chmod 2755 "$dhq_proj" 2>/dev/null || true
        echo "  project-root handover: $dhq_proj -> $dhq_user (TYPO3 not yet installed, bootstrap needs root ownership)"
    fi
    return 0
}

# ddev_typo3_detected <project-dir> <docroot>
# True (0) when ddev's isTypo3* detection finds an installed TYPO3 —
# mirrored from pkg/ddevapp/typo3.go: composer mode checks
# vendor/typo3/cms-core/Classes/Information/Typo3Version.php, legacy
# modes check the docroot's typo3/ folder. When NONE match, ddev's
# setTypo3SiteSettingsPaths falls back to the APP ROOT for the settings
# files — the case the project-root handover exists for.
ddev_typo3_detected() {
    dht_proj="${1:-}"
    dht_docroot="${2:-.}"
    [ -n "$dht_proj" ] || return 1
    [ -f "$dht_proj/$dht_docroot/vendor/typo3/cms-core/Classes/Information/Typo3Version.php" ] && return 0
    [ -f "$dht_proj/vendor/typo3/cms-core/Classes/Information/Typo3Version.php" ] && return 0
    [ -e "$dht_proj/$dht_docroot/typo3" ] && return 0
    return 1
}

# ddev_handover_root <root> <user> <group> [dev-user]
# Hands every .ddev tree under <root> (any depth) plus the owning
# project's ddev settings directories over to <user>:<group> with g+w.
ddev_handover_root() {
    dhr_root="${1:-}"
    dhr_user="${2:-}"
    dhr_group="${3:-}"
    dhr_dev="${4:-}"
    [ -n "$dhr_root" ] && [ -d "$dhr_root" ] || return 0
    # Prune vendor/node_modules (issue #21 pattern): a .ddev found there
    # belongs to a shipped test fixture, not to a project — handing it
    # over would chown third-party package files for no benefit.
    find "$dhr_root" -type d \( -name vendor -o -name node_modules \) -prune -o \
        -type d -name .ddev -prune -print 2>/dev/null | while IFS= read -r dhr_d; do
        chown -R "$dhr_user:$dhr_group" "$dhr_d" 2>/dev/null || true
        chmod -R g+w "$dhr_d" 2>/dev/null || true
        echo "  .ddev handover: $dhr_d -> $dhr_user"
        dhr_p="$(dirname "$dhr_d")"
        # Dev-owned mode (see file header): write the ddev flag first,
        # then branch on the FLAG (per-project truth, mode-independent).
        if ddev_devowned_enabled; then
            ddev_devowned_flag "$dhr_p"
        fi
        if ddev_devowned_flagged "$dhr_p"; then
            ddev_handover_project_back "$dhr_p" "$dhr_user" "$dhr_group" "$dhr_dev"
        else
            ddev_handover_project "$dhr_p" "$dhr_user" "$dhr_group"
            ddev_handover_project_root "$dhr_p" "$dhr_user" "$dhr_group" "$dhr_dev"
        fi
    done
    return 0
}

# ddev_handover_project_back <project-dir> <oc-user> <group> <dev-user>
# Dev-owned counterpart of the handovers: for a FLAGGED project (ddev
# settings management off — ddev never chmods outside .ddev/), the
# settings dirs and the project root belong to the DEVELOPER
# permanently. Repairs trees that went through the handover model
# before the flag existed (migration) and keeps fresh clones dev-owned
# (then these are structural no-ops: the dirs never left the developer).
ddev_handover_project_back() {
    dhb_proj="${1:-}"
    dhb_user="${2:-}"
    dhb_group="${3:-}"
    dhb_dev="${4:-}"
    [ -n "$dhb_proj" ] && [ -d "$dhb_proj/.ddev" ] || return 0
    [ -f "$dhb_proj/.ddev/config.yaml" ] || return 0
    [ -n "$dhb_dev" ] || return 0
    for dhb_d in $(ddev_type_settings_dirs "$dhb_proj"); do
        [ "$dhb_d" = "." ] && continue
        [ -d "$dhb_proj/$dhb_d" ] || continue
        chown -R "$dhb_dev:$dhb_group" "$dhb_proj/$dhb_d" 2>/dev/null || true
        chmod -R g+w "$dhb_proj/$dhb_d" 2>/dev/null || true
        echo "  dev-owned handback: $dhb_proj/$dhb_d -> $dhb_dev"
    done
    # Root inode: hand it back only when a previous handover model run
    # gave it to the kit user (never touches developer-owned roots).
    if [ "$(stat -c %U "$dhb_proj" 2>/dev/null)" = "$dhb_user" ]; then
        chown "$dhb_dev:$dhb_group" "$dhb_proj" 2>/dev/null || true
        chmod 2775 "$dhb_proj" 2>/dev/null || true
        echo "  dev-owned handback: $dhb_proj (root) -> $dhb_dev (2775)"
    fi
    return 0
}

# ddev_handover_project <project-dir> <user> <group>
# Hands the settings directories ddev chmods for the detected app type
# over to <user>:<group> with g+w. Projects without .ddev/config.yaml or
# with an unknown/unsupported type are skipped (wordpress manages a file
# at the project root — see docs/concepts/ddev-integration.md). Only for
# UNFLAGGED projects — flagged (dev-owned) ones use
# ddev_handover_project_back instead.
ddev_handover_project() {
    dhp_proj="${1:-}"
    dhp_user="${2:-}"
    dhp_group="${3:-}"
    [ -n "$dhp_proj" ] && [ -d "$dhp_proj/.ddev" ] || return 0
    [ -f "$dhp_proj/.ddev/config.yaml" ] || return 0
    for dhp_d in $(ddev_type_settings_dirs "$dhp_proj"); do
        [ "$dhp_d" = "." ] && continue
        [ -d "$dhp_proj/$dhp_d" ] || continue
        chown -R "$dhp_user:$dhp_group" "$dhp_proj/$dhp_d" 2>/dev/null || true
        chmod -R g+w "$dhp_proj/$dhp_d" 2>/dev/null || true
        echo "  ddev settings handover: $dhp_proj/$dhp_d -> $dhp_user"
    done
    return 0
}
