#!/bin/sh
# opencode permissions kit -- status.sh
# Prints the current protection status. Works whether or not the kit is
# installed, and does not require root. Run directly:
#   /usr/local/lib/opencode-permissions-kit/status.sh
# or from a checkout:
#   files/status.sh
set -u

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

LIBDIR="/usr/local/lib/opencode-permissions-kit"
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode-permissions-kit/setup.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/install.conf"
[ -f "$INSTALL_CONF" ] || INSTALL_CONF="/etc/opencode/setup.conf"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"
[ -f "$PROJECTS_CONF" ] || PROJECTS_CONF="/etc/opencode/projects.conf"

VERSION="0.0.0"
DEFAULT_USER=""
OPENCODE_USER="opencode"
WWW_GROUP="opencode"
HARD_DENY_REMOVED=""
if [ -f "$INSTALL_CONF" ]; then
    # shellcheck disable=SC1090
    . "$INSTALL_CONF"
fi
[ -n "$WWW_GROUP" ] || WWW_GROUP="opencode"
# Prefer the live primary usergroup over a stale conf value.
LIVE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
[ -n "$LIVE_GROUP" ] && WWW_GROUP="$LIVE_GROUP"

# installed = the wrapper is active (user + wrapper + library present)
installed=false
if id "$OPENCODE_USER" >/dev/null 2>&1 && [ -x "$LIBDIR/wrapper" ] && [ -L /usr/local/bin/opencode ]; then
    installed=true
fi

echo ""
echo "  ${GREEN}opencode permissions kit${NC}  v$VERSION"
echo "  ${CYAN}=============================================${NC}"
echo ""

if [ "$installed" = false ]; then
    echo "  ${YELLOW}Hardening NOT active.${NC}"
    echo ""
    echo "  Install it with:"
    echo "      curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/master/files/install.sh | sudo bash"
    echo ""
    exit 0
fi

echo "  Mode:       ${GREEN}user sandbox${NC} (opencode runs as its own user, soft permissions only)"
echo "  User:       $OPENCODE_USER $(id "$OPENCODE_USER" >/dev/null 2>&1 && echo "exists" || echo "${RED}MISSING${NC}")"
echo "  Wrapper:    /usr/local/bin/opencode -> $(readlink /usr/local/bin/opencode 2>/dev/null || echo missing)"
echo "  Library:    $LIBDIR"
echo "  Config:     $(ls /home/$OPENCODE_USER/.config/opencode/opencode.jsonc 2>/dev/null || ls /home/$OPENCODE_USER/.config/opencode/opencode.json 2>/dev/null || echo "${YELLOW}none${NC}")"
echo "  Default user: $DEFAULT_USER  sharing group: $WWW_GROUP"

echo ""
echo "  ${CYAN}Project roots ($(grep -c . "$PROJECTS_CONF" 2>/dev/null || echo 0)):${NC}"
if [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        echo "    - $root"
    done < "$PROJECTS_CONF"
else
    echo "    (none)"
fi

f="/home/$OPENCODE_USER/.config/opencode/opencode.jsonc"
[ -f "$f" ] || f="/home/$OPENCODE_USER/.config/opencode/opencode.json"
if [ -f "$f" ]; then
    if grep -qE '^[[:space:]]*"\.git/config"' "$f" 2>/dev/null; then
        echo ""
        echo "  .git/config hardening: ${GREEN}ON${NC} (soft-only — opencode tools)"
    else
        echo ""
        echo "  .git/config hardening: ${CYAN}OFF${NC}"
    fi
fi

echo ""
echo "  ${CYAN}Container backend:${NC}"
case "${CONTAINER_BACKEND:-}" in
    docker-rootless)
        echo "    backend:    docker-rootless"
        sock="${OPENCODE_DOCKER_HOST:-}"
        sockpath="$sock"
        case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
        # The opencode user's runtime dir (/run/user/<uid>) is mode 700
        # opencode:opencode, so a non-root status.sh caller cannot stat the
        # socket inside it. Try stat directly; if that fails (perm), use sudo.
        if [ -n "$sock" ]; then
            if [ -S "$sockpath" ] 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            elif sudo test -S "$sockpath" 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            else
                echo "    socket:     ${RED}NOT reachable${NC}  $sock"
            fi
        else
            echo "    socket:     ${YELLOW}not configured${NC}"
        fi
        # linger is best-effort: loginctl may need auth, ignore errors.
        if command -v loginctl >/dev/null 2>&1; then
            linger=$(loginctl show-user "$OPENCODE_USER" 2>/dev/null | sed -n 's/^Linger=//p')
            [ -n "$linger" ] && echo "    linger:     $linger"
        fi
        ;;
    podman-rootless)
        echo "    backend:    podman-rootless"
        sock="${OPENCODE_PODMAN_SOCKET:-}"
        if [ -n "$sock" ]; then
            # Optional podman docker-CLI-compat socket.
            sockpath="$sock"
            case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
            if [ -S "$sockpath" ] 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            elif sudo test -S "$sockpath" 2>/dev/null; then
                echo "    socket:     ${GREEN}reachable${NC}  $sock"
            else
                echo "    socket:     ${RED}NOT reachable${NC}  $sock"
            fi
        elif command -v podman >/dev/null 2>&1; then
            # Daemonless podman-CLI path (no socket needed, §9.8).
            pver=$(podman --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -1)
            echo "    podman CLI: ${GREEN}installed${NC}${pver:+  ($pver)}"
        else
            echo "    podman CLI: ${RED}NOT installed${NC}"
        fi
        ;;
    *)
        echo "    backend:    ${RED}none / legacy docker-group${NC}"
        echo "    re-run install.sh with a rootless backend:"
        echo "      sudo bash files/install.sh --container-backend docker-rootless|podman-rootless"
        ;;
esac

echo ""
echo "  ${CYAN}ddev runtime (as user $OPENCODE_USER):${NC}"
if [ -d "/home/$OPENCODE_USER/.ddev" ]; then
    echo "    ddev home:  ${GREEN}present${NC}  /home/$OPENCODE_USER/.ddev"
else
    echo "    ddev home:  ${YELLOW}missing${NC}  /home/$OPENCODE_USER/.ddev (created by install.sh / update.sh)"
fi
# Router-port readiness: rootless ddev-router cannot bind 80/443 unless
# ip_unprivileged_port_start <= 80. Shows the HOST value (the docker-rootless
# daemon netns inherits it at start; the daemon may need a restart if it
# started before the sysctl was applied).
port_start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo "?")
if [ "${port_start:-1024}" -le 80 ] 2>/dev/null; then
    echo "    router ports: ${GREEN}ready${NC} (ip_unprivileged_port_start=$port_start)"
else
    echo "    router ports: ${RED}NOT ready${NC} (ip_unprivileged_port_start=$port_start > 80 — ddev-router cannot bind 80/443)"
    echo "                  fix: sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
fi
# mkcert CAROOT readiness for the opencode user (ddev HTTPS).
ca="/home/$OPENCODE_USER/.local/share/mkcert/rootCA.pem"
if [ -f "$ca" ]; then
    echo "    mkcert CA: ${GREEN}present${NC}  $ca"
else
    echo "    mkcert CA: ${YELLOW}missing${NC}  (optional — ddev HTTPS will need a trusted CA)"
fi
if [ -n "${DDEV_VERSION:-}" ]; then
    ddev_low=$(awk -v v="$DDEV_VERSION" 'BEGIN{split(v,a,"."); if(a[1]+0<1 || (a[1]+0==1 && a[2]+0<25)) print "yes"; else print "no"}' 2>/dev/null)
    if [ "$ddev_low" = yes ]; then
        echo "    ddev version: $DDEV_VERSION  ${RED}(ddev < 1.25 — rootless needs ddev >= 1.25, upgrade ddev)${NC}"
    else
        echo "    ddev version: $DDEV_VERSION"
    fi
fi

# === Migration state (DDEV-WORKING §4) ========================================
echo ""
echo "  ${CYAN}Hard-deny migration:${NC}"
if [ "${HARD_DENY_REMOVED:-}" = "1" ]; then
    echo "    stamp:      ${GREEN}done${NC} (soft-only model active)"
else
    echo "    stamp:      ${YELLOW}missing${NC} — run update.sh to remove legacy u:$OPENCODE_USER ACL denies"
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
        echo "    leftover denies: ${RED}$leftover file(s) with u:$OPENCODE_USER ACL entries${NC}"
        echo "    remove them with: sudo bash $LIBDIR/update.sh"
    else
        echo "    leftover denies: ${GREEN}none${NC}"
    fi
fi

# === Sensitive-file leak scan (report-only) ===================================
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

echo ""
echo "  ${CYAN}Leak scan (scratch dirs, name-based, report-only):${NC}"
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
        echo "    ${YELLOW}${scan_count} match(es)${NC} — deny-pattern files outside the protected roots:"
        printf '%s\n' "$scan_hits" | head -20 | sed 's/^/      /'
        [ "$scan_count" -gt 20 ] && echo "      ... and $((scan_count - 20)) more"
        echo "    inspect and remove manually (report-only; renamed copies stay invisible)"
        log "leak scan: $scan_count deny-pattern match(es) in scratch dirs (report-only)"
    else
        echo "    ${GREEN}no matches${NC} in: $LEAK_DIRS"
    fi
else
    echo "    ${YELLOW}skipped${NC} (global config or parser not available)"
fi

echo ""
echo "  Management (run in a terminal):"
echo "      sudo $LIBDIR/config.sh                 change settings"
echo "      sudo $LIBDIR/update.sh                 re-deploy kit after an update"
echo "      bash $LIBDIR/uninstall.sh              remove the kit"
echo ""
