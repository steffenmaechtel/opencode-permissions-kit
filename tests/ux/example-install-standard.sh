#!/bin/sh
# DEMO — proposed STANDARD install flow (docs/design/UX-IMPROVEMENT.md §4.3).
# Simulated output only; nothing is executed. Run: sh tests/ux/example-install-standard.sh
set -u
. "$(dirname "$0")/lib/ux.sh"

VERSION="0.0.11"

ui_demo_notice
ui_banner "$VERSION" "installs opencode as its own user, rootless containers"

# --- mode selection ------------------------------------------------------------
ans=$(ui_menu "How do you want to install?" "1" \
    "1|Standard (recommended — 2 questions, safe defaults)" \
    "2|Advanced (control every step)" \
    "x|Abort")
case "$ans" in
    x*) ui_info "Aborted."; exit 0 ;;
    2*) ui_info "Switching to Advanced — see tests/ux/example-install-advanced.sh for that flow."; exit 0 ;;
esac

# --- pre-flight inventory --------------------------------------------------------
ui_section "Pre-flight — checking your system"

ui_info "Checking environment..."
sim 0.2
ui_success "WSL2 detected (Ubuntu 24.04)"
ui_info "Checking required tools..."
sim 0.2
ui_success "curl found"
ui_success "acl tools found (setfacl/getfacl)"
ui_info "Checking ddev..."
sim 0.2
ui_success "ddev v1.25.2 found (>= 1.25 required)"
ui_info "Checking container runtimes..."
sim 0.2
ui_success "docker CLI found — rootless backend will be provisioned for the agent user"
ui_detail "podman not detected — default backend: docker-rootless"
ui_info "Checking for an existing kit installation..."
sim 0.2
ui_success "none found — fresh install"
ui_info "Checking the opencode binary..."
sim 0.2
ui_success "found at /home/dev/.opencode/bin/opencode (will be secured)"
ui_warn "/mnt/c is world-readable (mode 777)"

ui_section "Inventory"

ui_have  "WSL2 (Ubuntu 24.04)"              "present"
ui_have  "curl / acl / ddev v1.25.2"        "present"
ui_add   "user 'opencode' + sharing group"  "will be created"
ui_add   "docker-rootless backend"          "will be provisioned"
ui_add   "wrapper /usr/local/bin/opencode"  "will be installed"
ui_add   "/mnt/c restriction"               "wsl.conf (pending wsl --shutdown)"
ui_atten "~/.opencode/bin/opencode"         "will be moved into the kit (backup kept)"

# --- the two Standard questions ---------------------------------------------------
ui_section "Standard setup — 2 questions"

PROJECT=$(ui_ask "Project directory?" "/var/www/vhosts")
GIT=$(ui_menu "Allow opencode access to git commands?" "no" \
    "no|block git for the agent (recommended)" \
    "yes|allow (soft-only .git/config deny)")
[ "$GIT" = "yes" ] && GIT_NOTE="allowed (soft-only deny)" || GIT_NOTE="blocked for the agent"

# --- plan + confirm -----------------------------------------------------------------
ui_section "Plan"

ui_plan 1 "Create user 'opencode' + sharing group"      "(dev user 'dev' added)"
ui_plan 2 "Provision docker-rootless for 'opencode'"    "(mandatory — aborts on failure)"
ui_plan 3 "Group + setgid + default ACLs"               "on $PROJECT"
ui_plan 4 "Secure the opencode binary + wrapper"        "root:opencode 750"
ui_plan 5 "Restrict /mnt/c via /etc/wsl.conf"           "takes effect after wsl --shutdown"
ui_plan 6 "Lower ip_unprivileged_port_start to 80"      "ddev-router 80/443"
ui_plan 7 "Deny-all config for your user"               "self-update bypass guard"
ui_plan 8 "Deploy library, sudoers, audit log"          "/usr/local/lib/opencode-permissions-kit"

echo ""
ans=$(ui_menu "Proceed?" "C" "C|Confirm" "A|Switch to Advanced" "X|Abort")
case "$ans" in
    X*) ui_info "Aborted — nothing was changed."; exit 0 ;;
    A*) ui_info "Switching to Advanced — see tests/ux/example-install-advanced.sh"; exit 0 ;;
esac

# --- simulated run --------------------------------------------------------------------
ui_section "Installing"

ui_info "Creating user + sharing group..."
sim
ui_success "user 'opencode' created, 'dev' added to group 'opencode'"
ui_info "Provisioning docker-rootless..."
sim 0.6
ui_success "rootless daemon ready (unix:///run/user/1001/docker.sock)"
ui_info "Applying group baseline + ACLs to $PROJECT..."
sim 0.4
ui_success "setgid + default ACLs applied (group rwx)"
ui_info "Securing the opencode binary..."
sim 0.3
ui_success "binary secured, wrapper installed at /usr/local/bin/opencode"
ui_success "user-local copy removed (backup in /tmp/opencode-install-backup-...)"
ui_info "Restricting /mnt/c..."
sim 0.3
ui_success "wsl.conf written"
ui_warn "takes effect after 'wsl --shutdown' from Windows"
ui_info "Lowering unprivileged port start to 80..."
sim 0.3
ui_success "sysctl applied + persisted (/etc/sysctl.d/99-ddev-rootless.conf)"
ui_info "Deploying library, sudoers, audit log..."
sim 0.4
ui_success "kit deployed to /usr/local/lib/opencode-permissions-kit"
[ "$GIT" = "yes" ] && { ui_info "Enabling git access..."; sim 0.2; ui_success "git allowed ($GIT_NOTE)"; }

# --- completion panel -------------------------------------------------------------------
ui_section "Installation complete"

ui_kv "Version"   "v$VERSION"
ui_kv "Backend"   "docker-rootless (rootless, owned by 'opencode')"
ui_kv "Projects"  "$PROJECT"
ui_kv "Git"       "$GIT_NOTE"
ui_kv "Backup"    "/tmp/opencode-install-backup-<timestamp>"
echo ""
ui_atten "Terminal"  "open a NEW terminal before running 'opencode'"
ui_atten "WSL2"      "run 'wsl --shutdown' from Windows to apply the /mnt/c fix"
echo ""
ui_info "Next:"
ui_detail "opencode                      # start the agent (new terminal!)"
ui_detail "status.sh                     # verify the protection"
ui_detail "config.sh                     # change settings later"
