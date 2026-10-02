# shellcheck shell=sh
# opencode permissions kit -- deploy-lib.sh
#
# Shared library deployment — ONE manifest for install.sh and update.sh
# (both carried their own ~34-line cp/chmod listing of the same set,
# a known sync hazard: update.sh's copy even said "Same deploy set as
# install.sh (0.0.38 C19)" — the denial-of-drift comment that a single
# list makes unnecessary).
#
# Layout (docs/design/streamline.md): bin/ = commands (no extension),
# sh/ = sourced shell libraries, py/ = python, management/ = the
# management entry scripts, templates/ = rendered/deployed templates.
# The manifest below is the SINGLE SOURCE OF TRUTH for what ships into
# /usr/local/lib/opencode-permissions-kit — tests/unit/test-kit-files.sh
# enforces it against the fetch lists (adding a kit file means adding
# it to the fetch lists AND this manifest; forgetting either fails CI).
#
# POSIX sh, SOURCED by install.sh and update.sh (checkout copy first,
# deployed LIBDIR fallback — same rules as staged-write.sh). Never
# executed directly. DL_SUDO overrides the sudo prefix ("" in tests).
# Note the plain "-": DL_SUDO="" must stay empty, a ":-" would
# re-substitute sudo. Deployed to
# /usr/local/lib/opencode-permissions-kit/sh/deploy-lib.sh.

_dl_sudo() { ${DL_SUDO-sudo} "$@"; }

# lib_deploy <tree-root> <libdir>
# <tree-root> is a directory containing opencode-permissions-kit-lib/
# (a checkout's files/, or the streamed temp fetch tree); <libdir> is
# the deployment target. Creates the sublayout, copies every manifest
# entry, applies the listed mode ("-" = keep the copied mode — used
# for data templates whose mode follows the source under the umask).
# Returns 1 loud — BEFORE writing the entry — when a source is
# missing, so a broken fetch cannot half-deploy silently.
lib_deploy() {
    _dl_root="$1"
    _dl_lib="$2"
    if [ ! -d "$_dl_root/opencode-permissions-kit-lib" ]; then
        echo "error: lib_deploy: '$_dl_root' does not contain opencode-permissions-kit-lib/" >&2
        return 1
    fi
    _dl_sudo mkdir -p "$_dl_lib/bin" "$_dl_lib/sh" "$_dl_lib/py" "$_dl_lib/tui" \
        "$_dl_lib/management" "$_dl_lib/templates" || return 1
    while IFS=' ' read -r _dl_rel _dl_mode _dl_x; do
        case "$_dl_rel" in ''|'#'*) continue ;; esac
        _dl_src="$_dl_root/$_dl_rel"
        _dl_dst="$_dl_lib/${_dl_rel#opencode-permissions-kit-lib/}"
        if [ ! -f "$_dl_src" ]; then
            echo "error: lib_deploy: missing source: $_dl_src" >&2
            return 1
        fi
        _dl_sudo cp "$_dl_src" "$_dl_dst" || return 1
        [ "$_dl_mode" = "-" ] || _dl_sudo chmod "$_dl_mode" "$_dl_dst" || return 1
    done <<'DL_MANIFEST'
# management entry scripts
opencode-permissions-kit-lib/management/config.sh 755
opencode-permissions-kit-lib/management/status.sh 755
opencode-permissions-kit-lib/management/uninstall.sh 755
opencode-permissions-kit-lib/management/update.sh 755
# templates — sudoers.template is needed by the installed config.sh for
# backend switches (render_sudoers looks in $LIBDIR/templates first);
# the deny-all template must re-deploy or it goes stale on every
# update (0.0.38 C19); the jsonc templates carry no chmod (data).
opencode-permissions-kit-lib/templates/opencode-deny-all.jsonc -
opencode-permissions-kit-lib/templates/opencode.jsonc -
opencode-permissions-kit-lib/templates/sudoers.template 440
# bin/ commands
opencode-permissions-kit-lib/bin/browser-bridge 755
opencode-permissions-kit-lib/bin/cwd-check 755
opencode-permissions-kit-lib/bin/ddev-as-opencode 755
opencode-permissions-kit-lib/bin/ddev-migrate 755
opencode-permissions-kit-lib/bin/opencode-as-opencode 755
opencode-permissions-kit-lib/bin/opk 755
opencode-permissions-kit-lib/bin/setup-container-backend 755
opencode-permissions-kit-lib/bin/socket-check 755
# py/
opencode-permissions-kit-lib/py/jsonc-parser.py 755
opencode-permissions-kit-lib/py/tui-register.py 755
# sh/ — executables the wrapper/management invoke, sourced libs 644.
# advisories.sh: known security advisories (issue #107), sourced by the
# wrapper (local check on every start) and status.sh (upstream diff).
# wsl-browser-bridge.sh: the deploy helper; the stand-in tree + the
# wsl.conf carrier are (re)applied by the CALLER after this deploy.
opencode-permissions-kit-lib/sh/advisories.sh 755
opencode-permissions-kit-lib/sh/ddev-handover.sh 644
opencode-permissions-kit-lib/sh/ddev-hosts.sh 644
opencode-permissions-kit-lib/sh/ddev-migrate.sh 644
opencode-permissions-kit-lib/sh/ddev-terminal.sh 644
opencode-permissions-kit-lib/sh/deploy-lib.sh 644
opencode-permissions-kit-lib/sh/fs-baseline.sh 644
opencode-permissions-kit-lib/sh/log.sh 755
opencode-permissions-kit-lib/sh/secure-binary.sh 644
opencode-permissions-kit-lib/sh/shell-warn.sh 755
opencode-permissions-kit-lib/sh/staged-write.sh 644
opencode-permissions-kit-lib/sh/sudoers-deploy.sh 644
opencode-permissions-kit-lib/sh/ui.sh 755
opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh 644
# tui/ mode display (docs/_archive/design/plan-ui-tui-opencode.md)
opencode-permissions-kit-lib/tui/kit-mode-2x.tsx 644
opencode-permissions-kit-lib/tui/kit-mode.tsx 644
opencode-permissions-kit-lib/tui/opencode-danger.theme.json 644
opencode-permissions-kit-lib/tui/tui-danger.json 644
opencode-permissions-kit-lib/tui/tui.json 644
DL_MANIFEST
    return 0
}
