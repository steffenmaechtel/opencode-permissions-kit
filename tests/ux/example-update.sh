#!/bin/sh
# DEMO — proposed update.sh output (docs/design/ux-improvement.md §6).
# Simulated output only; nothing is executed. Run: sh tests/ux/example-update.sh
set -u
. "$(dirname "$0")/lib/ux.sh"

OLD="0.0.10"; NEW="0.0.11"

ui_demo_notice
ui_banner "$NEW" "update — re-deploys the kit, keeps your configuration"

ui_info "Checking the current installation..."
sim 0.2
ui_success "kit v$OLD found (backend: docker-rootless, 3 project roots)"

ui_info "Fetching kit files (branch master)..."
sim 0.4
ui_success "18 files fetched, checksums consistent"

ui_info "Re-deploying the library to /usr/local/lib/opencode-permissions-kit..."
sim 0.4
ui_success "library updated ($OLD -> $NEW)"
ui_detail "projects.conf, opencode.jsonc, and the binary were NOT touched"

ui_info "Refreshing sudoers + wrapper symlink..."
sim 0.2
ui_success "sudoers re-validated (visudo -c)"

ui_info "Re-applying the ddev handover (.ddev + settings dirs)..."
sim 0.4
ui_success "3 projects handed over to 'opencode'"

ui_info "Checking pending migrations..."
sim 0.2
ui_success "none — already on the soft-only model"

ui_warn "/mnt/c restriction configured but still pending 'wsl --shutdown'"

ui_section "Update complete"

ui_kv "Kit"      "v$OLD -> $NEW"
ui_kv "Backup"   "/tmp/opencode-install-backup-<timestamp>"
ui_kv "Config"   "unchanged"
echo ""
ui_kv_warn "WSL2" "run 'wsl --shutdown' from Windows to apply the /mnt/c fix"
echo ""
ui_info "Next:"
ui_detail "update.sh --binary      # also upgrade the opencode binary"
ui_detail "status.sh               # verify the protection"
