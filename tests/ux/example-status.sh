#!/bin/sh
# DEMO — proposed status.sh output (docs/design/ux-improvement.md §6).
# Simulated output only; nothing is executed. Run: sh tests/ux/example-status.sh
set -u
. "$(dirname "$0")/lib/ux.sh"

ui_demo_notice
ui_banner "0.0.11" "protection status"

ui_section "Core"

ui_have "opencode user"        "exists (uid 1001, group 'opencode')"
ui_have "wrapper"              "/usr/local/bin/opencode -> kit wrapper"
ui_have "library"              "/usr/local/lib/opencode-permissions-kit"
ui_have "audit log"            "/var/log/opencode-permissions-kit/ (admin-only)"

ui_section "Container backend"

ui_have "backend"              "docker-rootless"
ui_have "daemon socket"        "unix:///run/user/1001/docker.sock — live"
ui_have "root-equivalent access" "none (rootless only)"

ui_section "ddev runtime"

ui_have "ddev"                 "v1.25.2 — runs as 'opencode'"
ui_have "ddev home"            "/home/opencode/.ddev"
ui_have "router ports"         "80/443 (ip_unprivileged_port_start=80)"
ui_atten "mkcert CA"           "reused from Windows — expires in 26 months"

ui_section "Projects (3)"

ui_have "/var/www/vhosts/shop"       "group 'opencode', setgid + ACLs"
ui_have "/var/www/vhosts/blog"       "group 'opencode', setgid + ACLs"
ui_atten "/var/www/vhosts/old-shop"  "missing setgid bit — run config.sh refresh"

ui_section "Warnings"

ui_warn "/mnt/c restriction configured but still pending 'wsl --shutdown'"
ui_warn "leak scan: /tmp/backup.env matches a deny pattern (report-only)"

echo ""
ui_info "Summary: 4 attention items, 0 blockers — kit is protecting this system."
