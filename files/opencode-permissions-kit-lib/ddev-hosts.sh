# shellcheck shell=sh
# opencode permissions kit -- ddev-hosts.sh
#
# Windows hosts-file bridge for ddev projects on WSL2 (issue #15 follow-up).
#
# Stock ddev on WSL2 manages the WINDOWS hosts file via ddev-hostname.exe
# + WSL interop. For the kit's ddev user that path is closed (/mnt/c is
# restricted to the developer; interop is broken on many WSL2+systemd
# hosts) — ddev then only WARNS and continues (`ddev start` succeeds,
# "Unable to open hosts file ... permission denied"). The BROWSER still
# cannot resolve custom project_tld domains, so the developer ends up
# editing C:\Windows\System32\drivers\etc\hosts by hand.
#
# This helper closes that gap on the DEVELOPER side only — the agent
# (opencode user) gets no hosts-file access at all:
#
#   ddev_hosts_list <project-dir>      hostnames ddev will serve (from
#                                      .ddev/config.yaml: name+project_tld,
#                                      additional_hostnames, additional_fqdns
#                                      — non-wildcard)
#   ddev_hosts_missing <project-dir>   those NOT yet in the Windows hosts
#   ddev_hosts_add <project-dir>       run `ddev hostname <name> 127.0.0.1`
#                                      AS THE DEVELOPER for every missing
#                                      hostname — ddev's own native path:
#                                      it elevates via ddev-hostname.exe
#                                      (interop) and Windows shows the UAC
#                                      confirmation dialog. Requires working
#                                      interop (see docs/troubleshooting.md).
#
# POSIX sh, SOURCED (kit CLI, ddev-as-opencode.sh hook) and never executed.
# Deployed to /usr/local/lib/opencode-permissions-kit/ddev-hosts.sh.

DDEV_WIN_HOSTS="${DDEV_WIN_HOSTS:-/mnt/c/Windows/System32/drivers/etc/hosts}"

# _ddev_hosts_yaml_list <file> <key>
# Prints the string items of a YAML scalar-list <key> (inline [a, b] and
# block "- a" forms — the subset ddev writes into config.yaml).
_ddev_hosts_yaml_list() {
    [ -f "$1" ] || return 0
    awk -v key="$2" '
        $0 ~ "^[[:space:]]*" key ":" {
            line = $0
            sub(/^[^:]*:[[:space:]]*/, "", line)
            sub(/[[:space:]]+#.*$/, "", line)
            if (line ~ /^\[/) {
                sub(/^\[/, "", line); sub(/\].*$/, "", line)
                n = split(line, a, ",")
                for (i = 1; i <= n; i++) {
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", a[i])
                    gsub(/"/, "", a[i])
                    if (a[i] != "") print a[i]
                }
                exit
            }
            inlist = 1; next
        }
        inlist {
            if ($0 ~ /^[[:space:]]*-[[:space:]]/) {
                line = $0
                sub(/^[[:space:]]*-[[:space:]]*/, "", line)
                sub(/[[:space:]]+#.*$/, "", line)
                gsub(/"/, "", line)
                if (line != "") print line
            } else if ($0 ~ /^[^[:space:]]/) {
                inlist = 0
            }
            next
        }
    ' "$1"
    return 0
}

# ddev_hosts_list <project-dir>
# Prints the hostnames ddev's GetHostnames() would serve for the project
# (mirrors pkg/ddevapp/config.go): "<name>.<project_tld>" (name defaults
# to the directory basename, tld to ddev.site), "<item>.<project_tld>"
# per additional_hostnames, additional_fqdns as-is. Wildcards skipped —
# they cannot live in a hosts file. No .ddev/config.yaml => no output.
ddev_hosts_list() {
    dhl_proj="${1:-}"
    [ -n "$dhl_proj" ] && [ -f "$dhl_proj/.ddev/config.yaml" ] || return 0
    dhl_name=$(sed -n 's/^name:[[:space:]]*//p' "$dhl_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d '[:space:]"' | tr '[:upper:]' '[:lower:]')
    [ -n "$dhl_name" ] || dhl_name=$(basename "$dhl_proj" | tr '[:upper:]' '[:lower:]')
    dhl_tld=$(sed -n 's/^project_tld:[[:space:]]*//p' "$dhl_proj/.ddev/config.yaml" 2>/dev/null | head -1 | tr -d '[:space:]"')
    [ -n "$dhl_tld" ] || dhl_tld="ddev.site"
    # Collect via command substitution (single stream): nested
    # pipe-while subshells write interleaved and can RACE a downstream
    # `read` — the aggregate keeps the output deterministic.
    dhl_extra=$(
        { _ddev_hosts_yaml_list "$dhl_proj/.ddev/config.yaml" additional_hostnames \
            | while IFS= read -r dhl_h; do printf '%s.%s\n' "$dhl_h" "$dhl_tld"; done
          _ddev_hosts_yaml_list "$dhl_proj/.ddev/config.yaml" additional_fqdns \
            | while IFS= read -r dhl_f; do
                case "$dhl_f" in *\**) continue ;; esac
                printf '%s\n' "$dhl_f"
              done
        } | sort
    )
    printf '%s.%s\n' "$dhl_name" "$dhl_tld"
    [ -n "$dhl_extra" ] && printf '%s\n' "$dhl_extra"
    return 0
}

# ddev_hosts_missing <project-dir> [hosts-file]
# Prints the project's hostnames that are NOT in the Windows hosts file
# (default $DDEV_WIN_HOSTS) — EXCEPT hostnames under the default tld
# (*.ddev.site): ddev's public wildcard DNS already resolves them to
# 127.0.0.1, no hosts entry is ever needed (issue #21; ddev itself stopped
# managing hosts entries for the default tld). An unreadable hosts file
# counts as "all missing" — the hint then still shows, ddev-host-add
# re-checks.
ddev_hosts_missing() {
    dhmi_proj="${1:-}"
    dhmi_hosts="${2:-$DDEV_WIN_HOSTS}"
    # Aggregate first (single stream — see ddev_hosts_list for the race),
    # then filter line by line in a plain loop writing to stdout directly.
    dhmi_list=$(ddev_hosts_list "$dhmi_proj")
    [ -n "$dhmi_list" ] || return 0
    for dhmi_h in $dhmi_list; do
        case "$dhmi_h" in
            *.ddev.site) continue ;;
        esac
        if [ -f "$dhmi_hosts" ] && grep -Eq "[[:space:]]$dhmi_h([[:space:]]|\$)" "$dhmi_hosts" 2>/dev/null; then
            continue
        fi
        printf '%s\n' "$dhmi_h"
    done
    return 0
}

# ddev_hosts_add <project-dir|hostname>
# Adds hostnames via ddev's own elevation path, run AS THE DEVELOPER
# (ddev must not run as the agent user here — the Windows hosts file and
# interop belong to the developer). One ddev call per hostname (ddev
# hostname takes a single name); Windows may show one UAC dialog per call.
# Prints a manual fallback when ddev or interop fails.
# Two modes (issue #21): an existing DIRECTORY adds that project's missing
# hostnames; a HOSTNAME adds exactly that one name — the per-hostname
# commands the status/hints print, so the user sees and adds exactly what
# was reported.
ddev_hosts_add() {
    dha_arg="${1:-}"
    [ -n "$dha_arg" ] || dha_arg="$PWD"

    dha_conf="/etc/opencode-permissions-kit/install.conf"
    dha_dev="${DDEV_HOSTS_DEV_USER:-}"
    [ -n "$dha_dev" ] || { [ -f "$dha_conf" ] && dha_dev=$(sed -n 's/^DEFAULT_USER=//p' "$dha_conf" | tail -1); }
    # Resolve the caller: prefer the override/install.conf, fall back to
    # SUDO_USER; empty when already running as that user (or root without
    # either) — then run ddev directly.
    if [ -n "$dha_dev" ] && id "$dha_dev" >/dev/null 2>&1 && [ "$(id -u "$dha_dev")" != "$(id -u)" ]; then
        :
    elif [ -n "${SUDO_USER:-}" ] && [ "$(id -u "${SUDO_USER:-x}")" != "0" ]; then
        dha_dev="$SUDO_USER"
    else
        dha_dev=""
    fi

    dha_bin="$(command -v ddev 2>/dev/null || true)"
    [ -n "$dha_bin" ] || { [ -x /usr/local/bin/ddev ] && dha_bin=/usr/local/bin/ddev; }
    [ -n "$dha_bin" ] || { [ -x /usr/bin/ddev ] && dha_bin=/usr/bin/ddev; }
    [ -n "$dha_bin" ] || { echo "ddev-hosts: ddev is not installed"; return 1; }

    # Hostname mode: not an existing directory and no path separator.
    if [ ! -d "$dha_arg" ]; then
        case "$dha_arg" in
            */*) echo "ddev-hosts: no ddev project in $dha_arg"; return 1 ;;
        esac
        echo "adding $dha_arg (Windows may ask for permission) ..."
        if [ -n "$dha_dev" ]; then
            sudo -u "$dha_dev" env HOME="/home/$dha_dev" "$dha_bin" hostname "$dha_arg" 127.0.0.1
        else
            "$dha_bin" hostname "$dha_arg" 127.0.0.1
        fi || { echo "  FAILED: $dha_arg — add it manually (see below)"; return 1; }
        echo ""
        echo "  Windows hosts file: $DDEV_WIN_HOSTS"
        echo "  manual fallback (Windows PowerShell as admin):"
        echo "    Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '127.0.0.1 $dha_arg'"
        return 0
    fi

    dha_proj="$dha_arg"
    [ -f "$dha_proj/.ddev/config.yaml" ] || { echo "ddev-hosts: no ddev project in $dha_proj"; return 1; }

    dha_missing=$(ddev_hosts_missing "$dha_proj")
    if [ -z "$dha_missing" ]; then
        echo "all hostnames already in $DDEV_WIN_HOSTS — nothing to do"
        return 0
    fi

    dha_failed=""
    dha_rc=0
    # for-loop, not a pipe: the exit code must survive the loop (a while
    # pipeline would run in a subshell and lose dha_rc). Hostnames never
    # contain whitespace.
    for dha_h in $dha_missing; do
        echo "adding $dha_h (Windows may ask for permission) ..."
        if [ -n "$dha_dev" ]; then
            sudo -u "$dha_dev" env HOME="/home/$dha_dev" "$dha_bin" hostname "$dha_h" 127.0.0.1 \
                || { echo "  FAILED: $dha_h — add it manually (see below)"; dha_rc=1; }
        else
            "$dha_bin" hostname "$dha_h" 127.0.0.1 \
                || { echo "  FAILED: $dha_h — add it manually (see below)"; dha_rc=1; }
        fi
    done
    echo ""
    echo "  Windows hosts file: $DDEV_WIN_HOSTS"
    echo "  manual fallback (Windows PowerShell as admin):"
    echo "    Add-Content -Path 'C:\Windows\System32\drivers\etc\hosts' -Value '127.0.0.1 <hostname>'"
    return "$dha_rc"
}
