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
#
# Everything is best-effort (|| true) and idempotent. POSIX sh, SOURCED
# (never executed) by install.sh, update.sh and config.sh (projects add,
# refresh). Callers run as root (or via sudo) — plain chown is fine. No
# logging here: the functions echo their actions, callers wrap them with
# their own log calls as needed.
#
# Deployed to /usr/local/lib/opencode-permissions-kit/ddev-handover.sh.

# ddev_handover_root <root> <user> <group>
# Hands every .ddev tree under <root> (any depth) plus the owning
# project's ddev settings directories over to <user>:<group> with g+w.
ddev_handover_root() {
    dhr_root="${1:-}"
    dhr_user="${2:-}"
    dhr_group="${3:-}"
    [ -n "$dhr_root" ] && [ -d "$dhr_root" ] || return 0
    find "$dhr_root" -type d -name .ddev -prune 2>/dev/null | while IFS= read -r dhr_d; do
        chown -R "$dhr_user:$dhr_group" "$dhr_d" 2>/dev/null || true
        chmod -R g+w "$dhr_d" 2>/dev/null || true
        echo "  .ddev handover: $dhr_d -> $dhr_user"
        ddev_handover_project "$(dirname "$dhr_d")" "$dhr_user" "$dhr_group"
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
