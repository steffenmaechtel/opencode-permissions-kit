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
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode-permissions-kit/setup.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
[ -f "$PROJECTS_CONF" ] || PROJECTS_CONF="/etc/opencode/projects.conf"

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
HARD_DENY_REMOVED=""
if [ -f "$INSTALL_CONF" ]; then
    # shellcheck disable=SC1090
    . "$INSTALL_CONF"
fi
# Prefer OPENCODE_GROUP, fall back to the legacy WWW_GROUP key a pre-rename
# install.conf still carries; then the live primary usergroup.
OPENCODE_GROUP="${OPENCODE_GROUP:-${WWW_GROUP:-opencode}}"
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
        # socket inside it. Try stat directly; if that fails (perm), use sudo.
        if [ -n "$sock" ]; then
            if [ -S "$sockpath" ] 2>/dev/null || sudo test -S "$sockpath" 2>/dev/null; then
                ui_kv "socket" "reachable — $sock" "$UI_GREEN"
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
            # Optional podman docker-CLI-compat socket.
            sockpath="$sock"
            case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
            if [ -S "$sockpath" ] 2>/dev/null || sudo test -S "$sockpath" 2>/dev/null; then
                ui_kv "socket" "reachable — $sock" "$UI_GREEN"
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
        ui_kv "backend" "none / legacy docker-group" "$UI_RED"
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
        ui_kv "mkcert CA" "unknown — needs root to check (run: sudo opencode-permissions-kit status)" "$UI_YELLOW"
    else
        ui_kv "mkcert CA" "missing (optional — ddev HTTPS will need a trusted CA)" "$UI_YELLOW"
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

# === Migration state (DDEV-WORKING §4) ==========================================

ui_section "Hard-deny migration"

if [ "${HARD_DENY_REMOVED:-}" = "1" ]; then
    ui_kv "stamp" "done (soft-only model active)" "$UI_GREEN"
else
    ui_kv "stamp" "missing — run update.sh to remove legacy u:$OPENCODE_USER ACL denies" "$UI_YELLOW"
fi
# Report-only scan for leftover hard denies from a pre-migration install.
if command -v getfacl >/dev/null 2>&1 && [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
    leftover=0
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ -d "$root" ] || continue
        n=$(getfacl -R -p "$root" 2>/dev/null | awk -v u="$OPENCODE_USER" '
            /^# file: / { path = substr($0, 9); has = 0; next }
            index($0, "user:" u ":") == 1 { has = 1; next }
            /^$/ { if (path != "" && has) { print path; has = 0 } path = "" }
        ' | grep -c . || true)
        leftover=$((leftover + ${n:-0}))
    done < "$PROJECTS_CONF"
    if [ "${leftover:-0}" -gt 0 ]; then
        ui_kv "leftover denies" "$leftover file(s) with u:$OPENCODE_USER ACL entries" "$UI_RED"
        ui_detail "remove them with: sudo bash $LIBDIR/update.sh"
    else
        ui_kv "leftover denies" "none" "$UI_GREEN"
    fi
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
