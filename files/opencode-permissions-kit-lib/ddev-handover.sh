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
#                   usually a parent folder of several projects)
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
# refresh). Callers run as root (or via sudo) — plain chown is fine. No
# logging here: the functions echo their actions, callers wrap them with
# their own log calls as needed.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/ddev-handover.sh.

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
    find "$dhr_root" -type d -name .ddev -prune 2>/dev/null | while IFS= read -r dhr_d; do
        chown -R "$dhr_user:$dhr_group" "$dhr_d" 2>/dev/null || true
        chmod -R g+w "$dhr_d" 2>/dev/null || true
        echo "  .ddev handover: $dhr_d -> $dhr_user"
        ddev_handover_project "$(dirname "$dhr_d")" "$dhr_user" "$dhr_group"
        ddev_handover_project_root "$(dirname "$dhr_d")" "$dhr_user" "$dhr_group" "$dhr_dev"
    done
    return 0
}

# ddev_handover_project <project-dir> <user> <group>
# Hands the settings directories ddev chmods for the detected app type
# over to <user>:<group> with g+w. Projects without .ddev/config.yaml or
# with an unknown/unsupported type are skipped (wordpress manages a file
# at the project root — see docs/concepts/ddev-integration.md).
ddev_handover_project() {
    dhp_proj="${1:-}"
    dhp_user="${2:-}"
    dhp_group="${3:-}"
    [ -n "$dhp_proj" ] && [ -d "$dhp_proj/.ddev" ] || return 0
    [ -f "$dhp_proj/.ddev/config.yaml" ] || return 0
    dhp_type=$(sed -n 's/^type:[[:space:]]*//p' "$dhp_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    dhp_docroot=$(sed -n 's/^docroot:[[:space:]]*//p' "$dhp_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d " \t\"'")
    [ -n "$dhp_docroot" ] || dhp_docroot="."
    case "$dhp_type" in
        typo3)
            dhp_dirs="config/system $dhp_docroot/typo3conf typo3conf"
            ;;
        drupal*|backdrop)
            dhp_dirs="$dhp_docroot/sites/default"
            ;;
        magento*)
            dhp_dirs="app/etc"
            ;;
        *)
            return 0
            ;;
    esac
    for dhp_d in $dhp_dirs; do
        [ "$dhp_d" = "." ] && continue
        [ -d "$dhp_proj/$dhp_d" ] || continue
        chown -R "$dhp_user:$dhp_group" "$dhp_proj/$dhp_d" 2>/dev/null || true
        chmod -R g+w "$dhp_proj/$dhp_d" 2>/dev/null || true
        echo "  ddev settings handover: $dhp_proj/$dhp_d -> $dhp_user"
    done
    return 0
}
