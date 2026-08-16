#!/bin/sh
# DEMO — proposed ADVANCED install flow (docs/design/UX-IMPROVEMENT.md §4.4).
# Includes the docker-classic warning variant for the §5 discussion.
# Simulated output only; nothing is executed. Run: sh tests/ux/example-install-advanced.sh
set -u
. "$(dirname "$0")/lib/ux.sh"

VERSION="0.0.11"

ui_demo_notice
ui_banner "$VERSION" "advanced install — every step is yours to decide"

# --- condensed pre-flight --------------------------------------------------------
ui_section "Pre-flight"

ui_info "Checking system..."
sim 0.2
ui_have  "WSL2 (Ubuntu 24.04)"           "present"
ui_have  "curl / acl / ddev v1.25.2"     "present"
ui_have  "podman v4.9.3"                 "present"
ui_add   "user 'opencode'"               "will be created"
ui_atten "existing kit v0.0.9"           "detected — will be migrated"

# --- advanced questions -------------------------------------------------------------

ui_section "Choices"

# Backend — including the (deliberately scary) docker classic variant.
BACKEND=$(ui_menu "Container backend for the agent user?" "1" \
    "1|docker-rootless (recommended)" \
    "2|podman-rootless (daemonless, no systemd)" \
    "3|docker classic — root docker (INSECURE)")

if [ "$BACKEND" = "3" ]; then
    echo ""
    ui_error "docker classic grants the agent a ROOT-EQUIVALENT socket."
    ui_error "The agent user could escape every restriction the kit sets up:"
    ui_detail "mount the host filesystem, read /etc/shadow, install software,"
    ui_detail "patch the kit away. UID separation — the kit's only hard"
    ui_detail "guarantee — would be void."
    echo ""
    CONFIRM=$(ui_ask "Type 'root-docker' to accept the risk (anything else aborts)" "")
    if [ "$CONFIRM" = "root-docker" ]; then
        ui_warn "docker classic selected — AGAINST the kit's recommendation"
        BACKEND="docker-group (root-equivalent)"
    else
        ui_info "Falling back to docker-rootless."
        BACKEND="docker-rootless"
    fi
elif [ "$BACKEND" = "2" ]; then
    BACKEND="podman-rootless"
    ui_detail "podman detected earlier — staying with podman"
else
    BACKEND="docker-rootless"
fi

PROJECT=$(ui_ask "Project directory?" "/var/www/vhosts")
PORTS=$(ui_menu "Lower unprivileged port start to 80 (ddev-router 80/443)?" "yes" "yes|host-wide sysctl, recommended" "no|use higher router ports")
WSLC=$(ui_menu "Restrict /mnt/c to your user (needs wsl --shutdown)?" "yes" "yes|recommended" "no|leave world-readable")
GIT=$(ui_menu "Allow opencode git access?" "no" "no|block git for the agent (recommended)" "yes|allow (soft-only .git/config deny)")
DENY=$(ui_menu "Existing default-user opencode config found — replace with deny-all?" "backup" "backup|back up as opencode.jsonc_BAK_<ts> (recommended)" "keep|keep my config" "overwrite|overwrite without backup")

# --- plan ------------------------------------------------------------------------------

ui_section "Plan"

ui_kv "Backend"    "$BACKEND"
ui_kv "Projects"   "$PROJECT"
ui_kv "Router"     "$([ "$PORTS" = "yes" ] && echo "ports 80/443 (sysctl)" || echo "higher ports (8080/8443)")"
ui_kv "/mnt/c"     "$([ "$WSLC" = "yes" ] && echo "restrict via wsl.conf" || echo "leave world-readable (not recommended)")"
ui_kv "Git"        "$([ "$GIT" = "yes" ] && echo "allowed (soft deny only)" || echo "blocked")"
ui_kv "Old config" "$DENY"
ui_kv "Migration"  "v0.0.9 kit detected — legacy ACLs will be removed"

echo ""
ans=$(ui_menu "Proceed?" "C" "C|Confirm" "X|Abort")
[ "$ans" = "X" ] && { ui_info "Aborted — nothing was changed."; exit 0; }

# --- simulated run ------------------------------------------------------------------------

ui_section "Installing"

ui_info "Creating user + sharing group..."
sim 0.3
ui_success "done"
ui_info "Provisioning $BACKEND..."
sim 0.5
ui_success "backend ready"
ui_info "Migrating the existing v0.0.9 install..."
sim 0.4
ui_success "legacy hard-deny ACLs removed (12 entries)"
ui_success "files re-based to group 'opencode'"
ui_info "Applying ACL baseline, wrapper, configs..."
sim 0.5
ui_success "done"
[ "$WSLC" = "yes" ] && { ui_warn "/mnt/c restriction pending 'wsl --shutdown'"; }

ui_section "Installation complete"

ui_kv "Version"  "v$VERSION"
ui_kv "Backend"  "$BACKEND"
echo ""
ui_atten "Terminal" "open a NEW terminal before running 'opencode'"
