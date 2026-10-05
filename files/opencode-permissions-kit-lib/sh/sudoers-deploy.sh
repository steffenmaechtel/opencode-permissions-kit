# shellcheck shell=sh
# opencode permissions kit -- sudoers-deploy.sh
#
# Shared sudoers pipeline — ONE implementation for install.sh, config.sh
# and update.sh (the former triple duplication was a sync hazard on a
# security-critical path: three copies of render + validate + install
# that had to move together). Pipeline:
#
#   1. validate the DEFAULT_USER charset — the username is
#      sed-interpolated into sudoers, an exotic name (e.g. from a
#      hand-edited install.conf) must be rejected before it can
#      corrupt the syntax,
#   2. render the template (s/DEFAULT_USER/<user>/g) into a mktemp
#      scratch file,
#   3. validate the RENDERED file with visudo BEFORE anything is
#      deployed — a broken file in /etc/sudoers.d makes sudo itself
#      refuse to run, and recovering would require non-sudo access
#      (0.0.38 S1),
#   4. install it mode 440 into the kit's CONFDIR, symlink it into
#      /etc/sudoers.d, and remove the pre-0.0.10 legacy name so only
#      the new name is active.
#
# POSIX sh, SOURCED by install.sh, config.sh and update.sh (checkout
# copy first, deployed LIBDIR fallback — same rules as
# staged-write.sh). Never executed directly. SD_SUDO overrides the
# sudo prefix ("" in tests), SD_VISUDO the visudo binary, SD_CONF_DIR
# the kit config dir, SD_SUDOERS_D the sudoers.d directory. Note the
# plain "-": SD_SUDO="" must stay empty, a ":-" would re-substitute
# sudo. visudo itself runs WITHOUT the sudo prefix (0.0.41f Q1): every
# caller runs as root (install/config/update), so the direct call is
# equivalent — tests and non-root harnesses must stub SD_VISUDO.
# Deployed to /usr/local/lib/opencode-permissions-kit/sh/sudoers-deploy.sh.

_sd_sudo() { ${SD_SUDO-sudo} "$@"; }

# sudoers_deploy <template> <default_user>
# Returns 0 on success. Returns 1 with a message on stderr — nothing
# is deployed then — when the user charset is invalid, the template is
# missing, visudo rejects the rendered file, or an install step fails.
# Success messages/logging stay with the CALLER (install / re-render /
# re-deploy wording differs on purpose).
sudoers_deploy() {
    _sd_template="$1"
    _sd_user="$2"
    case "$_sd_user" in
        ''|*[!A-Za-z0-9_.-]*|ALL)
            # ALL (0.0.41f S3): renders VALID sudoers ("ALL ALL=(opencode)
            # NOPASSWD: …") that widens the grant to every local user —
            # no Unix account can carry that name, so reject it outright.
            echo "error: invalid DEFAULT_USER '$_sd_user' (allowed: letters, digits, '_', '.', '-'; not 'ALL')" >&2
            return 1
            ;;
    esac
    if [ ! -f "$_sd_template" ]; then
        echo "error: sudoers template not found: $_sd_template" >&2
        return 1
    fi
    _sd_conf="${SD_CONF_DIR:-/etc/opencode-permissions-kit}"
    _sd_d="${SD_SUDOERS_D:-/etc/sudoers.d}"
    _sd_tmp=$(mktemp) || return 1
    # Register for the caller's scratch-cleanup trap (0.0.39e C3) when
    # the caller has one — the explicit rm paths below make the trap a
    # no-op, a missing trap never leaks the temp on the handled paths.
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_sd_tmp"
    fi
    if ! sed -e "s/DEFAULT_USER/$_sd_user/g" "$_sd_template" > "$_sd_tmp"; then
        rm -f "$_sd_tmp"
        echo "error: cannot render sudoers template: $_sd_template" >&2
        return 1
    fi
    if ! ${SD_VISUDO-/usr/sbin/visudo} -c -f "$_sd_tmp" >/dev/null 2>&1; then
        rm -f "$_sd_tmp"
        echo "error: sudoers template failed validation — nothing was deployed (user '$_sd_user')." >&2
        return 1
    fi
    if ! _sd_sudo mkdir -p "$_sd_conf"; then
        rm -f "$_sd_tmp"
        echo "error: cannot create $_sd_conf (user '$_sd_user')." >&2
        return 1
    fi
    # Atomic replace (0.0.44a V10): `cp` onto the live-referenced sudoers
    # content is O_TRUNC+write — a kill mid-window leaves a truncated
    # sudoers live (the file's own 0.0.38 S1 rationale: broken sudoers.d
    # makes sudo refuse for everyone). Stage INSIDE $_sd_conf (same
    # filesystem, rename(2) is atomic), then mv -f.
    if ! _sd_stage=$(_sd_sudo mktemp "$_sd_conf/.sudoers.XXXXXXXX"); then
        rm -f "$_sd_tmp"
        echo "error: cannot stage sudoers in $_sd_conf (user '$_sd_user')." >&2
        return 1
    fi
    if ! _sd_sudo cp "$_sd_tmp" "$_sd_stage" \
       || ! _sd_sudo chmod 440 "$_sd_stage" \
       || ! _sd_sudo mv -f "$_sd_stage" "$_sd_conf/sudoers"; then
        rm -f "$_sd_tmp"
        _sd_sudo rm -f "$_sd_stage" 2>/dev/null || true
        echo "error: cannot install sudoers to $_sd_conf (user '$_sd_user')." >&2
        return 1
    fi
    rm -f "$_sd_tmp"
    if ! _sd_sudo ln -sf "$_sd_conf/sudoers" "$_sd_d/opencode-permissions-kit"; then
        echo "error: cannot link sudoers into $_sd_d (user '$_sd_user')." >&2
        return 1
    fi
    # Remove the pre-0.0.10 sudoers symlink so only the new name is
    # active (unifies the cleanup config.sh and update.sh already did).
    _sd_sudo rm -f "$_sd_d/opencode" 2>/dev/null || true
    return 0
}
