#!/bin/sh
# opencode permissions kit -- status.sh
# Prints the current protection status. Works whether or not the kit is
# installed, and does not require root. Run directly:
#   /usr/local/lib/opencode-permissions-kit/status.sh
# or from a checkout:
#   files/status.sh
set -u

LIBDIR="/usr/local/lib/opencode-permissions-kit"
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"

# Shared UI helpers: installed library first, then the checkout layout.
UI_LIB="$LIBDIR/ui.sh"
if [ ! -f "$UI_LIB" ]; then
    _self="$(cd "$(dirname "$0")" && pwd)"
    [ -f "$_self/opencode-permissions-kit-lib/ui.sh" ] && UI_LIB="$_self/opencode-permissions-kit-lib/ui.sh"
fi
if [ -f "$UI_LIB" ]; then
    # shellcheck disable=SC1090
    . "$UI_LIB"
else
    echo "error  ui.sh not found (expected $LIBDIR/ui.sh or next to status.sh in a checkout)" >&2
    exit 1
fi

VERSION="0.0.0"
DEFAULT_USER=""
OPENCODE_USER="opencode"
OPENCODE_GROUP=""
if [ -f "$INSTALL_CONF" ]; then
    # shellcheck disable=SC1090
    . "$INSTALL_CONF"
fi
# Sharing group: the opencode user's own usergroup; prefer the live value.
OPENCODE_GROUP="${OPENCODE_GROUP:-opencode}"
LIVE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
[ -n "$LIVE_GROUP" ] && OPENCODE_GROUP="$LIVE_GROUP"

# installed = the wrapper is active (user + wrapper + library present)
installed=false
if id "$OPENCODE_USER" >/dev/null 2>&1 && [ -x "$LIBDIR/wrapper" ] && [ -L /usr/local/bin/opencode ]; then
    installed=true
fi

ui_banner "$VERSION" "protection status"

if [ "$installed" = false ]; then
    ui_warn "Hardening NOT active."
    echo ""
    ui_info "Install it with:"
    ui_detail "curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash"
    echo ""
    exit 0
fi

# === Core ======================================================================

ui_section "Core"

ui_kv "Mode"     "dedicated user (soft permissions only)" "$UI_GREEN"
if id "$OPENCODE_USER" >/dev/null 2>&1; then
    ui_kv "User"  "$OPENCODE_USER — exists"
else
    ui_kv "User"  "$OPENCODE_USER — MISSING" "$UI_RED"
fi
ui_kv "Wrapper"  "/usr/local/bin/opencode -> $(readlink /usr/local/bin/opencode 2>/dev/null || echo missing)"
ui_kv "Library"  "$LIBDIR"
_occonf="$(ls /home/$OPENCODE_USER/.config/opencode/opencode.jsonc 2>/dev/null || ls /home/$OPENCODE_USER/.config/opencode/opencode.json 2>/dev/null || echo "")"
if [ -n "$_occonf" ]; then
    ui_kv "Config" "$_occonf"
else
    ui_kv "Config" "none" "$UI_YELLOW"
fi
ui_kv "Sharing"  "group '$OPENCODE_GROUP' (default user: ${DEFAULT_USER:-unknown})"

f="/home/$OPENCODE_USER/.config/opencode/opencode.jsonc"
[ -f "$f" ] || f="/home/$OPENCODE_USER/.config/opencode/opencode.json"
if [ -f "$f" ]; then
    if grep -qE '^[[:space:]]*"\.git/config"' "$f" 2>/dev/null; then
        ui_kv ".git/config" "ON (soft-only — opencode tools)" "$UI_GREEN"
    else
        ui_kv ".git/config" "OFF"
    fi
fi

# === Projects ==================================================================

ui_section "Projects ($(grep -c . "$PROJECTS_CONF" 2>/dev/null || echo 0))"

if [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ -d "$root" ] || { ui_miss "$root" "directory missing"; continue; }
        # setgid on the root is what keeps new files in the sharing group
        root_mode=$(stat -c %a "$root" 2>/dev/null || echo "?")
        if [ $((0${root_mode:-0} & 02000)) -ne 0 ]; then
            ui_have "$root" "setgid ($root_mode) + ACLs"
        else
            ui_atten "$root" "missing setgid bit — run config.sh refresh"
        fi
    done < "$PROJECTS_CONF"
else
    ui_atten "(none configured)" "run config.sh projects add <path>"
fi

# === Container backend ===========================================================

ui_section "Container backend"

case "${CONTAINER_BACKEND:-}" in
    docker-rootless)
        ui_kv "backend" "docker-rootless" "$UI_GREEN"
        sock="${OPENCODE_DOCKER_HOST:-}"
        sockpath="$sock"
        case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
        # The opencode user's runtime dir (/run/user/<uid>) is mode 700
        # opencode:opencode, so a non-root status.sh caller cannot stat the
        # socket inside it. Direct stat first; then sudo -n (non-interactive
        # — status.sh must never prompt for a password); when both fail but
        # the runtime dir exists and is NOT traversable by the caller, the
        # state is UNKNOWN, not broken (same wording pattern as the mkcert
        # CA check below — a red "NOT reachable" made users think the
        # daemon was down). A traversable dir without a socket stays red.
        if [ -n "$sock" ]; then
            if [ -S "$sockpath" ] 2>/dev/null || sudo -n test -S "$sockpath" 2>/dev/null; then
                ui_kv "socket" "reachable — $sock" "$UI_GREEN"
            elif [ -d "$(dirname "$sockpath")" ] && [ ! -x "$(dirname "$sockpath")" ]; then
                ui_kv "socket" "unknown — needs root to check (run: sudo opk status)" "$UI_YELLOW"
            else
                ui_kv "socket" "NOT reachable — $sock" "$UI_RED"
            fi
        else
            ui_kv "socket" "not configured" "$UI_YELLOW"
        fi
        # linger is best-effort: loginctl may need auth, ignore errors.
        if command -v loginctl >/dev/null 2>&1; then
            linger=$(loginctl show-user "$OPENCODE_USER" 2>/dev/null | sed -n 's/^Linger=//p')
            [ -n "$linger" ] && ui_kv "linger" "$linger"
        fi
        ;;
    podman-rootless)
        ui_kv "backend" "podman-rootless" "$UI_GREEN"
        sock="${OPENCODE_PODMAN_SOCKET:-}"
        if [ -n "$sock" ]; then
            # Optional podman docker-CLI-compat socket (see docker-rootless
            # branch for the probe rationale).
            sockpath="$sock"
            case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
            if [ -S "$sockpath" ] 2>/dev/null || sudo -n test -S "$sockpath" 2>/dev/null; then
                ui_kv "socket" "reachable — $sock" "$UI_GREEN"
            elif [ -d "$(dirname "$sockpath")" ] && [ ! -x "$(dirname "$sockpath")" ]; then
                ui_kv "socket" "unknown — needs root to check (run: sudo opk status)" "$UI_YELLOW"
            else
                ui_kv "socket" "NOT reachable — $sock" "$UI_RED"
            fi
        elif command -v podman >/dev/null 2>&1; then
            # Daemonless podman-CLI path (no socket needed, §9.8).
            pver=$(podman --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -1)
            ui_kv "podman CLI" "installed${pver:+  ($pver)}" "$UI_GREEN"
        else
            ui_kv "podman CLI" "NOT installed" "$UI_RED"
        fi
        ;;
    *)
        ui_kv "backend" "unknown ('${CONTAINER_BACKEND:-none}')" "$UI_RED"
        ui_detail "re-run install.sh with a rootless backend:"
        ui_detail "sudo bash files/install.sh --container-backend docker-rootless|podman-rootless"
        ;;
esac

# === ddev runtime ================================================================

ui_section "ddev runtime (as user $OPENCODE_USER)"

if [ -d "/home/$OPENCODE_USER/.ddev" ]; then
    ui_kv "ddev home" "present — /home/$OPENCODE_USER/.ddev" "$UI_GREEN"
else
    ui_kv "ddev home" "missing — created by install.sh / update.sh" "$UI_YELLOW"
fi
# ddev always runs as the opencode user: the sudoers helper + the shell
# function hooked into the default user's rc files.
if [ -x "$LIBDIR/bin/ddev-as-opencode" ]; then
    ui_kv "helper" "deployed — $LIBDIR/bin/ddev-as-opencode" "$UI_GREEN"
else
    ui_kv "helper" "missing — run $LIBDIR/update.sh to deploy" "$UI_YELLOW"
fi
if [ -n "$DEFAULT_USER" ] && [ -f "$LIBDIR/ddev-as-opencode.sh" ]; then
    hooked=""
    for cf in "/home/$DEFAULT_USER/.bashrc" "/home/$DEFAULT_USER/.zshrc" "/home/$DEFAULT_USER/.profile"; do
        [ -f "$cf" ] && grep -q 'opencode-permissions-kit/ddev-as-opencode.sh' "$cf" 2>/dev/null && hooked="$cf" && break
    done
    if [ -n "$hooked" ]; then
        ui_kv "ddev() hook" "active — $hooked" "$UI_GREEN"
    else
        ui_kv "ddev() hook" "not hooked — run $LIBDIR/update.sh" "$UI_YELLOW"
    fi
fi
# Dev-owned mode (docs/design/ddev-dev-owned-projects.md): on = the kit
# writes disable_settings_management: true into projects' .ddev/config.yaml
# and keeps settings dirs + project root developer-owned; off = ddev
# manages settings (handover model). install.conf is world-readable.
_dv_stamp=$(sed -n 's/^DDEV_DEV_OWNED=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null | tail -1)
case "${_dv_stamp:-}" in
    true|TRUE|1|yes)
        ui_kv "ddev settings" "dev-owned — kit writes disable_settings_management (permanent 2775/664)" "$UI_GREEN"
        ;;
    false|FALSE|0|no|"")
        ui_kv "ddev settings" "ddev-managed — handover model (config.sh ddev-settings on to switch)"
        ;;
esac
# Router-port readiness: rootless ddev-router cannot bind 80/443 unless
# ip_unprivileged_port_start <= 80. Shows the HOST value (the docker-rootless
# daemon netns inherits it at start; the daemon may need a restart if it
# started before the sysctl was applied).
port_start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo "?")
if [ "${port_start:-1024}" -le 80 ] 2>/dev/null; then
    ui_kv "router ports" "ready (ip_unprivileged_port_start=$port_start)" "$UI_GREEN"
else
    ui_kv "router ports" "NOT ready (ip_unprivileged_port_start=$port_start > 80)" "$UI_RED"
    ui_detail "ddev-router cannot bind 80/443 — fix: sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
fi
# mkcert CAROOT readiness for the opencode user (ddev HTTPS).
ca="/home/$OPENCODE_USER/.local/share/mkcert/rootCA.pem"
if [ -f "$ca" ]; then
    ui_kv "mkcert CA" "present — $ca" "$UI_GREEN"
    # Mismatch check (report-only): if a Windows mkcert CA exists but the
    # opencode CAROOT holds a DIFFERENT CA, Windows browsers trust the
    # Windows one and ddev's certs show as "not secure". Happens when the
    # CA was reused from the wrong source (e.g. a second WSL distro).
    win_ca=""
    if [ -d /mnt/c/Users ]; then
        for wca in /mnt/c/Users/*/AppData/Local/mkcert/rootCA.pem; do
            [ -f "$wca" ] && { win_ca="$wca"; break; }
        done
    fi
    if [ -n "$win_ca" ]; then
        oc_fp=$(openssl x509 -in "$ca" -noout -fingerprint -sha256 2>/dev/null || true)
        win_fp=$(openssl x509 -in "$win_ca" -noout -fingerprint -sha256 2>/dev/null || true)
        if [ -n "$oc_fp" ] && [ -n "$win_fp" ] && [ "$oc_fp" != "$win_fp" ]; then
            ui_kv "mkcert CA" "MISMATCH — opencode CA != Windows CA ($win_ca)" "$UI_RED"
            ui_detail "Windows browsers will show ddev sites as not-secure."
            ui_detail "fix: copy the Windows CA (rootCA.pem + rootCA-key.pem) to"
            ui_detail "$ca's directory, then remove ~/.ddev/traefik/certs/* and 'ddev restart'"
        fi
    fi
else
    # The CA lives under opencode-only dirs (typically 700) — a non-root
    # caller cannot stat the file, so "missing" may just mean "unchecked".
    # Only root can genuinely confirm absence.
    if [ "$(id -u)" -ne 0 ] && [ -d "/home/$OPENCODE_USER" ]; then
        ui_kv "mkcert CA" "unknown — needs root to check (run: sudo opk status)" "$UI_YELLOW"
    else
        ui_kv "mkcert CA" "missing (optional — ddev HTTPS will need a trusted CA)" "$UI_YELLOW"
    fi
fi
# Migration dumps (issue #15): databases exported from the developer's
# daemon at install time wait here until they are imported into the
# opencode daemon. Read-only listing — importing is the user's call.
_mig_root="/var/backups/opencode-permissions-kit"
_mig_dir=$(ls -1d "$_mig_root"/ddev-migration-* 2>/dev/null | sort | tail -1 || true)
if [ -n "$_mig_dir" ] && [ -f "$_mig_dir/manifest.conf" ]; then
    _mig_ok=$(grep -c '^OK|' "$_mig_dir/manifest.conf" 2>/dev/null || true)
    _mig_ok=${_mig_ok:-0}
    if [ "$_mig_ok" -gt 0 ]; then
        _mig_imported=0
        if [ -d "/home/$OPENCODE_USER/.ddev" ]; then
            _mig_imported=$(grep -c '^project_info:' "/home/$OPENCODE_USER/.ddev/global_config.yaml" 2>/dev/null || true)
            _mig_imported=${_mig_imported:-0}
        fi
        if [ "$_mig_imported" -gt 0 ]; then
            ui_kv "db dumps" "$_mig_ok dump(s) — ${_mig_dir##*/}" "$UI_GREEN"
            ui_detail "if some databases are missing in the opencode projects, import manually:"
            ui_detail "  sudo sh $LIBDIR/ddev-migrate.sh import"
        else
            ui_kv_warn "db dumps" "$_mig_ok dump(s) waiting for import — ${_mig_dir##*/}"
            ui_detail "import all: sudo sh $LIBDIR/ddev-migrate.sh import  (first start pulls images)"
            ui_detail "or per project: ddev start <name> && ddev import-db <name> --file=<dump>.sql.gz"
        fi
    fi
fi
if [ -n "${DDEV_VERSION:-}" ]; then
    ddev_low=$(awk -v v="$DDEV_VERSION" 'BEGIN{split(v,a,"."); if(a[1]+0<1 || (a[1]+0==1 && a[2]+0<25)) print "yes"; else print "no"}' 2>/dev/null)
    if [ "$ddev_low" = yes ]; then
        ui_kv "ddev version" "$DDEV_VERSION (ddev < 1.25 — rootless needs ddev >= 1.25, upgrade ddev)" "$UI_RED"
    else
        ui_kv "ddev version" "$DDEV_VERSION"
    fi
fi
# Windows hosts readiness (WSL2): custom-tld projects need their hostnames
# in the Windows hosts file for the browser; ddev (running as opencode)
# cannot manage that file. Report-only, per project root.
if [ -d /mnt/c ] && [ -f "$LIBDIR/ddev-hosts.sh" ] && [ -f /mnt/c/Windows/System32/drivers/etc/hosts ] \
   && [ -n "${DEFAULT_USER:-}" ] && [ "$(id -u)" != "$(id -u "$OPENCODE_USER" 2>/dev/null || echo 1)" ]; then
    # shellcheck disable=SC1091  # deployed lib, checked above
    . "$LIBDIR/ddev-hosts.sh"
    _st_miss_total=0
    if [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
        while IFS= read -r _st_root; do
            [ -z "$_st_root" ] && continue
            [ -d "$_st_root" ] || continue
            # vendor/, node_modules/ and testdata/ pruned (issues #21,
            # #29): composer/npm packages and test fixtures (e.g. a
            # checkout of ddev's own repository) ship their own .ddev
            # dirs — they are not the user's projects and their
            # hostnames must never hit the Windows hosts file.
            find "$_st_root" \( -type d \( -name vendor -o -name node_modules -o -name testdata \) \) -prune -o -type d -name .ddev -prune -print 2>/dev/null | while IFS= read -r _st_d; do
                _st_m=$(ddev_hosts_missing "$(dirname "$_st_d")")
                [ -n "$_st_m" ] || continue
                ui_kv_warn "hosts (win)" "$(dirname "$_st_d"): missing $(printf '%s' "$_st_m" | tr '\n' ' ')"
                for _st_h in $_st_m; do
                    echo "     add: opk ddev-hosts-add $_st_h"
                done
            done
        done < "$PROJECTS_CONF"
    fi
fi

# === WSL2 /mnt/c exposure (drvfs world-readable by default) =====================
# The 9p/drvfs server runs with the Windows session token, so NTFS ACLs do
# NOT distinguish WSL users — the Linux mode bits are the only filter, and
# the WSL default mounts C: world-readable. Every WSL user (including the
# agent's) can then read the whole Windows profile (.ssh, NTUSER.DAT, ...).
# Report-only; the fix is a host-level wsl.conf change.
if [ -d /mnt/c ]; then
    ui_section "WSL2 /mnt/c exposure"
    mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -n "$mnt_mode" ] && [ $((0$mnt_mode & 0004)) -ne 0 ]; then
        if grep -q '^options *=.*dmask' /etc/wsl.conf 2>/dev/null; then
            ui_kv "/mnt/c" "fix configured, pending" "$UI_YELLOW"
            ui_detail "wsl.conf carries the restriction — run 'wsl --shutdown' from Windows to apply"
        else
            ui_kv "/mnt/c" "world-readable (mode $mnt_mode)" "$UI_RED"
            ui_detail "the agent user can read the whole Windows profile"
            ui_detail "fix: restrict the drvfs mount to the developer in /etc/wsl.conf:"
            ui_detail "  [automount]"
            ui_detail "  enabled = true"
            ui_detail "  options = \"uid=1000,gid=1000,dmask=027,fmask=037\""
            ui_detail "(replace uid/gid with the default user's; install.sh asks) and run 'wsl --shutdown' from Windows."
        fi
    else
        ui_kv "/mnt/c" "restricted (mode ${mnt_mode:-?})" "$UI_GREEN"
    fi
fi

# === Root-equivalent access audit (issue #37) ====================================
# Root-equivalent surfaces BEYOND the kit's own backends: a rootful docker
# daemon or containerd, LXD/libvirt — and, very common on WSL2, the Docker
# Desktop / Rancher Desktop integration sockets under /mnt/wsl, which the
# distro mounts world-usable. Any of these reachable by the agent user
# breaks the "containers ≠ root" guarantee as thoroughly as a root docker
# group membership. All checks are report-only stat math — no privileged
# probe, no prompt, no fix (removing access is the admin's decision).

# status_groups_hits <groups-list> <danger-list>: prints every group from
# <danger-list> that appears in <groups-list> (word match).
# shellcheck disable=SC2086  # word splitting intended: both are group lists
status_groups_hits() {
    for sgh_g in $2; do
        case " $1 " in *" $sgh_g "*) printf '%s\n' "$sgh_g" ;; esac
    done
    return 0
}

# status_sock_agent_reachable <socket-path> <agent-groups>: exit 0 when the
# agent user can plausibly connect — socket world-writable, or group-writable
# with its group among <agent-groups>. Pure stat math, works unprivileged.
status_sock_agent_reachable() {
    ssr_mode=$(stat -c %a "$1" 2>/dev/null) || return 1
    [ $((0$ssr_mode & 0002)) -ne 0 ] && return 0
    if [ $((0$ssr_mode & 0020)) -ne 0 ]; then
        ssr_grp=$(stat -c %G "$1" 2>/dev/null)
        case " $2 " in *" $ssr_grp "*) return 0 ;; esac
    fi
    return 1
}

ui_section "Root-equivalent access (audit)"

# Groups that are root-equivalent (or credential-equivalent) if the AGENT
# user is a member. The kit never adds them — this catches later manual
# grants (usermod -aG docker opencode "to make something work").
sra_groups=$(id -nG "$OPENCODE_USER" 2>/dev/null || true)
sra_finding=false
# shellcheck disable=SC2086  # word splitting intended: group lists
sra_red=$(status_groups_hits "$sra_groups" "docker containerd lxd libvirt libvirt-qemu snap disk sudo admin wheel" | tr '\n' ' ')
# shellcheck disable=SC2086  # word splitting intended: group lists
sra_yellow=$(status_groups_hits "$sra_groups" "wireshark adm systemd-journal" | tr '\n' ' ')
sra_red=${sra_red% } ; sra_yellow=${sra_yellow% }
if [ -n "$sra_red" ]; then
    ui_kv "groups (root-equiv)" "$OPENCODE_USER in: $sra_red — full root, remove with: sudo gpasswd -d $OPENCODE_USER <group>" "$UI_RED"
    sra_finding=true
fi
if [ -n "$sra_yellow" ]; then
    ui_kv "groups (sensitive)" "$OPENCODE_USER in: $sra_yellow — log/packet access can leak credentials" "$UI_YELLOW"
    sra_finding=true
fi

# Root-equivalent daemon sockets: system-wide paths plus everything the
# WSL2 desktop integrations mount under /mnt/wsl (Docker Desktop exposes
# its daemon socket world-usable to every WSL distro user by default).
# Override the list via ROOT_EQUIV_SOCKS (same pattern as LEAK_SCAN_DIRS).
sra_sock_list="/var/run/docker.sock /run/containerd/containerd.sock /var/lib/lxd/unix.socket /run/libvirt/libvirt-sock"
sra_sock_list="${ROOT_EQUIV_SOCKS:-$sra_sock_list}"
if [ -d /mnt/wsl ]; then
    sra_sock_list="$sra_sock_list $(find /mnt/wsl -maxdepth 4 \( -type s -o -type l \) \( -name docker.sock -o -name podman.sock -o -name containerd.sock -o -name crio.sock \) 2>/dev/null)"
fi
sra_seen=""
for sra_s in $sra_sock_list; do
    [ -S "$sra_s" ] || continue
    # dedup (symlinked paths resolve to the same socket)
    sra_r=$(readlink -f "$sra_s" 2>/dev/null || echo "$sra_s")
    case " $sra_seen " in *" $sra_r "*) continue ;; esac
    sra_seen="$sra_seen $sra_r"
    if status_sock_agent_reachable "$sra_s" "$sra_groups"; then
        ui_kv "socket" "$sra_s — AGENT-REACHABLE (root-equivalent daemon)" "$UI_RED"
        sra_finding=true
    else
        ui_kv "socket" "$sra_s — present, not agent-reachable" "$UI_GREEN"
    fi
done

# Windows interop: with a world-executable /mnt/c the agent can run Windows
# binaries as the Windows session user (no Linux root, but full Windows
# profile access). The /mnt/c restriction above (fmask) also blocks this
# exec path — this probe makes the interop outcome explicit.
if [ -e /mnt/c/Windows/System32 ]; then
    sra_mode=$(stat -c %a /mnt/c/Windows/System32/cmd.exe 2>/dev/null || true)
    if [ -n "$sra_mode" ] && [ $((0$sra_mode & 0001)) -ne 0 ]; then
        ui_kv "win interop" "agent can execute Windows binaries (/mnt/c world-executable)" "$UI_RED"
        sra_finding=true
    else
        ui_kv "win interop" "blocked for the agent (/mnt/c restricted)" "$UI_GREEN"
    fi
fi

# The agent user itself must have NO sudo rules (the kit grants rules only
# to the developer, RunAs opencode). Only checkable when status.sh runs as
# root; otherwise silent.
if [ "$(id -u)" -eq 0 ] && command -v sudo >/dev/null 2>&1; then
    if sudo -n -l -U "$OPENCODE_USER" 2>/dev/null | grep -Eq '\((ALL|opencode)[^)]*\)' ; then
        ui_kv "sudo rules" "$OPENCODE_USER may run sudo — the kit grants it none (investigate)" "$UI_RED"
        sra_finding=true
    else
        ui_kv "sudo rules" "none for $OPENCODE_USER" "$UI_GREEN"
    fi
fi

if [ "$sra_finding" = false ]; then
    ui_kv "result" "no root-equivalent access found for $OPENCODE_USER" "$UI_GREEN"
fi

# === Sensitive-file leak scan (report-only) =====================================
# Name-based sweep of scratch directories for files matching the global deny
# patterns. The kit protects storage locations, not information flows: a copy
# that left the project roots (cp .env /tmp/backup) is outside every future
# scan. This surfaces such leftovers for manual inspection. REPORT-ONLY —
# no ACL is ever changed outside the project roots, and false positives (a
# developer's own /tmp/foo.env.example) are expected. Renamed copies stay
# invisible: this is a name tripwire, not content DLP. Runs unprivileged;
# copies hidden in 0700 directories are only visible when run as root.
# Override the directories via LEAK_SCAN_DIRS="/tmp /some/dir".
log() { :; }
[ -f "$LIBDIR/log.sh" ] && . "$LIBDIR/log.sh"
LEAK_DIRS="${LEAK_SCAN_DIRS:-/tmp /var/tmp /dev/shm}"
PARSER="$LIBDIR/jsonc-parser.py"
SCAN_CFG="/home/$OPENCODE_USER/.config/opencode/opencode.jsonc"
[ -f "$SCAN_CFG" ] || SCAN_CFG="/home/$OPENCODE_USER/.config/opencode/opencode.json"

ui_section "Leak scan (report-only)"

if [ -f "$SCAN_CFG" ] && [ -x "$PARSER" ] && command -v python3 >/dev/null 2>&1; then
    scan_patterns=$(python3 "$PARSER" "$SCAN_CFG" 2>/dev/null || true)
    scan_hits=""
    if [ -n "$scan_patterns" ]; then
        scan_hits=$(
            for scan_dir in $LEAK_DIRS; do
                [ -d "$scan_dir" ] || continue
                while IFS= read -r scan_pat; do
                    [ -z "$scan_pat" ] && continue
                    case "$scan_pat" in
                        */*) find "$scan_dir" -maxdepth 4 -type f -path "*/$scan_pat" -print 2>/dev/null ;;
                        *)   find "$scan_dir" -maxdepth 4 -type f -name "$scan_pat" -print 2>/dev/null ;;
                    esac
                done <<EOF
$scan_patterns
EOF
            done | grep -v -e '/systemd-private-' -e '/snap-private-tmp/' | sort -u
        )
    fi
    scan_count=$(printf '%s\n' "$scan_hits" | grep -c . || true)
    if [ "${scan_count:-0}" -gt 0 ]; then
        ui_warn "$scan_count match(es) — deny-pattern files outside the protected roots:"
        printf '%s\n' "$scan_hits" | head -20 | sed 's/^/     /'
        [ "$scan_count" -gt 20 ] && ui_detail "... and $((scan_count - 20)) more"
        ui_detail "inspect and remove manually (report-only; renamed copies stay invisible)"
        log "leak scan: $scan_count deny-pattern match(es) in scratch dirs (report-only)"
    else
        ui_kv "result" "no matches in: $LEAK_DIRS" "$UI_GREEN"
    fi
else
    ui_kv "result" "skipped (global config or parser not available)" "$UI_YELLOW"
fi

# === Management ==================================================================

echo ""
ui_info "Management (run in a terminal):"
ui_detail "sudo $LIBDIR/config.sh                 change settings"
ui_detail "sudo $LIBDIR/update.sh                 re-deploy kit after an update"
ui_detail "bash $LIBDIR/uninstall.sh              remove the kit"
echo ""
