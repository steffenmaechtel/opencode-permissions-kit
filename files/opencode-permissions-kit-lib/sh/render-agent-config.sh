# shellcheck shell=sh
# opencode permissions kit -- render-agent-config.sh
#
# Shared opencode.jsonc template render — ONE implementation for
# install.sh (_oc_install_agent_config) and config.sh (git_config_apply):
# the SECURE_GIT sed pair existed verbatim in both.
#
# The template carries the .git/config deny rules as commented
# `//SECURE_GIT:` lines; "on" uncomments them (the soft deny is active),
# "off" drops them. The render is deliberately OFFLINE (0.0.39h F8):
# the FINAL content is produced here on a scratch file and deployed by
# the caller with ONE staged_write — no privileged second write on the
# agent-owned destination.
#
# POSIX sh, SOURCED by install.sh and config.sh (checkout copy first,
# deployed LIBDIR fallback — same rules as staged-write.sh). Never
# executed directly. Deployed to
# /usr/local/lib/opencode-permissions-kit/sh/render-agent-config.sh.

# agent_config_render <template> <outfile> <on|off>
# Renders the template into <outfile>. Returns 1 loud on an unknown
# mode or a failing sed; never touches the destination (that is the
# caller's staged_write).
agent_config_render() {
    _acr_template="$1"
    _acr_out="$2"
    _acr_mode="$3"
    case "$_acr_mode" in
        on)
            if ! sed 's|//SECURE_GIT: ||' "$_acr_template" > "$_acr_out"; then
                echo "error: cannot render agent config (on) from $_acr_template" >&2
                return 1
            fi
            ;;
        off)
            if ! sed '/\/\/SECURE_GIT:/d' "$_acr_template" > "$_acr_out"; then
                echo "error: cannot render agent config (off) from $_acr_template" >&2
                return 1
            fi
            ;;
        *)
            echo "error: agent_config_render: mode must be on|off (got: '$_acr_mode')" >&2
            return 1
            ;;
    esac
    return 0
}
