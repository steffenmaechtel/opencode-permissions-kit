#!/bin/sh
# DEMO — style variants side by side (docs/_archive/design/ux-improvement.md §3).
# Pick what you like; nothing is executed. Run: sh tests/ux/example-styles.sh
set -u
. "$(dirname "$0")/lib/ux.sh"

ui_demo_notice

# --- A: labeled log lines (openchamber style) -----------------------------------
ui_section "A — labeled log lines (current favorite)"

ui_info "Checking Node.js..."
ui_success "Node.js v24 found"
ui_warn "cache directory is world-writable"
ui_error "something broke"
ui_detail "dimmed detail line under the previous message"

# --- B: symbol prefixes ------------------------------------------------------------
ui_section "B — symbol prefixes"

printf '  %s✔%s  step completed\n' "$UI_GREEN" "$UI_NC"
printf '  %s⚠%s  needs attention\n' "$UI_YELLOW" "$UI_NC"
printf '  %s✖%s  failed\n' "$UI_RED" "$UI_NC"
printf '  %sℹ%s  informational\n' "$UI_BLUE" "$UI_NC"

# --- C: bracketed steps ---------------------------------------------------------------
ui_section "C — bracketed steps"

printf '  %s[1/8]%s create user...\n' "$UI_DIM" "$UI_NC"
printf '  %s[2/8]%s provision backend...\n' "$UI_DIM" "$UI_NC"
printf '  %s[3/8]%s apply ACLs...\n' "$UI_DIM" "$UI_NC"

# --- D: checklist inventory --------------------------------------------------------------
ui_section "D — inventory checklist"

ui_have  "curl"                    "present"
ui_add   "user 'opencode'"         "will be created"
ui_atten "/mnt/c"                  "world-readable"
ui_miss  "ddev"                    "not installed"

# --- E: banner variants --------------------------------------------------------------------
ui_section "E — banner variants"

ui_banner "0.0.11" "slim banner (default)"
ui_banner_box "0.0.11" "boxed banner (variant B)"

# --- F: key/value panel -----------------------------------------------------------------------
ui_section "F — key/value panel (status, summaries)"

ui_kv "Mode"    "dedicated user + rootless containers" "$UI_GREEN"
ui_kv "Backend" "docker-rootless" "$UI_GREEN"
ui_kv "WSL2"    "pending wsl --shutdown" "$UI_YELLOW"

# --- G: density comparison ----------------------------------------------------------------------
ui_section "G — density (airy vs compact)"

echo "  airy:"
ui_info "Provisioning docker-rootless..."
sim 0.3
ui_success "rootless daemon ready"
echo ""
echo "  compact:"
printf '  %s%s%s  provisioning... done\n' "$UI_GREEN" "$UI_SYM_OK" "$UI_NC"

echo ""
ui_info "Feedback wanted: A vs B/C for logs, slim vs boxed banner, symbols OK, airy vs compact."
