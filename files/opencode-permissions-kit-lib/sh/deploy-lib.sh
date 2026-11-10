# shellcheck shell=sh
# opencode permissions kit -- deploy-lib.sh
#
# Shared library deployment — ONE manifest for install.sh and update.sh
# (both carried their own ~34-line cp/chmod listing of the same set,
# a known sync hazard: update.sh's copy even said "Same deploy set as
# install.sh (0.0.38 C19)" — the denial-of-drift comment that a single
# list makes unnecessary).
#
# Layout (internal/records/streamline.md): bin/ = commands (no extension),
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

# --- xdg-open shim gate (issue #257) ---------------------------------------------
# opencode 2.x crashed `auth login` on hosts without any xdg-open
# (upstream anomalyco/opencode#52548, fixed in PR #56082; first release
# carrying the fix: v2.0.32, tagged 2026-10-16 — verified against the
# upstream tags by ancestry: v2.0.31 predates the merge, v2.0.32 is the
# first tag containing the fix commit). The 1.x line never received
# the fix (v1.19.x diverged from it), so the shim stays required there.
# Both consumers (install-core.sh, update-core.sh) read this through
# sourcing — the ONE definition keeps the version pin from drifting.
XDG_SHIM_FIX_VERSION="2.0.32"

# xdg_shim_needed_for <major> <x.y.z>: rc 0 = the binary still needs
# the fallback shim; rc 1 = it opens without one itself (2.x at or
# above XDG_SHIM_FIX_VERSION). An empty or non-version-shaped value
# keeps the shim — the probe must prove safety, never assume it (the
# wrapper's fail-open idiom; 1.x is never fixed, so major 2 plus an
# all-numeric dotted value — a triple today — is the only rc-1 path).
# The shape gate is load-bearing (review a
# A3): sort -V places non-numeric strings AFTER the triple, so without
# it a garbage version would compare as "newer" and fail OPEN.
# Version order via sort -V, the advisories.sh idiom.
xdg_shim_needed_for() {
    [ "$1" = 2 ] || return 0
    [ -n "$2" ] || return 0
    printf '%s' "$2" | grep -qE '^[0-9]+(\.[0-9]+)*$' || return 0
    _xsg_hi=$(printf '%s\n%s\n' "$2" "$XDG_SHIM_FIX_VERSION" | sort -V | tail -n 1)
    [ "$_xsg_hi" = "$2" ] && return 1
    return 0
}

# lib_deploy <tree-root> <libdir>
# <tree-root> is a directory containing opencode-permissions-kit-lib/
# (a checkout's files/, or the streamed temp fetch tree); <libdir> is
# the deployment target. Creates the sublayout, copies every manifest
# entry, applies the listed mode ("-" = keep the copied mode — used
# for data templates whose mode follows the source under the umask).
# Returns 1 loud — BEFORE writing the entry — when a source is
# missing, so a broken fetch cannot half-deploy silently.
# Each entry deploys ATOMICALLY (0.0.49a W2): the copy lands in a
# sibling temp that gets its final mode, then one mv renames it into
# place — an interrupted run can never leave a half-written or
# wrongly-moded script at a path the kit executes.
lib_deploy() {
    _dl_root="$1"
    _dl_lib="$2"
    if [ ! -d "$_dl_root/opencode-permissions-kit-lib" ]; then
        echo "error: lib_deploy: '$_dl_root' does not contain opencode-permissions-kit-lib/" >&2
        return 1
    fi
    _dl_sudo mkdir -p "$_dl_lib/bin" "$_dl_lib/sh" "$_dl_lib/py" "$_dl_lib/tui" \
        "$_dl_lib/management" "$_dl_lib/templates" || return 1
    while IFS=' ' read -r _dl_rel _dl_mode; do
        case "$_dl_rel" in '' | '#'*) continue ;; esac
        _dl_src="$_dl_root/$_dl_rel"
        _dl_dst="$_dl_lib/${_dl_rel#opencode-permissions-kit-lib/}"
        if [ ! -f "$_dl_src" ]; then
            echo "error: lib_deploy: missing source: $_dl_src" >&2
            return 1
        fi
        # Atomic per-entry deploy (0.0.49a W2): a plain in-place cp over
        # bin/opk or management/update.sh, killed mid-write, leaves a
        # truncated script with intact mode bits — the #163 class on the
        # kit's own repair tooling. Sibling temp = same directory = same
        # filesystem, so the mv renames: the entry is always the complete
        # old or the complete new file. chmod rides BEFORE the mv, so the
        # mode is atomic too (sudoers.template never sits at a cp-natural
        # 644 — it is 440 the moment the name appears). Same two-leg
        # shape as sh/secure-binary.sh's copy_binary_atomic, staged here
        # separately because lib_deploy owns the per-entry mode and its
        # own _dl_sudo. A run killed between the legs leaves one
        # root-owned $$-suffixed temp behind — inert (nothing executes
        # it by name) and never colliding with a later run's temp
        # (0.0.49b C2 wording, aligned with copy_binary_atomic's note).
        _dl_tmp="$_dl_dst.tmp.$$"
        if ! _dl_sudo cp "$_dl_src" "$_dl_tmp"; then
            _dl_sudo rm -f "$_dl_tmp"
            return 1
        fi
        if [ "$_dl_mode" != "-" ] && ! _dl_sudo chmod "$_dl_mode" "$_dl_tmp"; then
            _dl_sudo rm -f "$_dl_tmp"
            return 1
        fi
        if ! _dl_sudo mv -f "$_dl_tmp" "$_dl_dst"; then
            _dl_sudo rm -f "$_dl_tmp"
            return 1
        fi
    done <<'DL_MANIFEST'
# management entry scripts
opencode-permissions-kit-lib/management/config.sh 755
opencode-permissions-kit-lib/management/doctor.sh 755
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
opencode-permissions-kit-lib/bin/xdg-open 755
# py/
opencode-permissions-kit-lib/py/jsonc-parser.py 755
opencode-permissions-kit-lib/py/tui-register.py 755
# sh/ — executables the wrapper/management invoke, sourced libs 644.
# advisories.sh: known security advisories (issue #107), sourced by the
# wrapper (local check on every start) and status.sh (upstream diff).
# wsl-browser-bridge.sh: the deploy helper; the stand-in tree + the
# wsl.conf carrier are (re)applied by the CALLER after this deploy.
# Sourced-only libs ship 644 (#377 F2, review #370 a F2): advisories,
# log, shell-warn and ui were 755 against this rule's own wording —
# nothing executes them by path (git index 644; sourced everywhere).
opencode-permissions-kit-lib/sh/advisories.sh 644
opencode-permissions-kit-lib/sh/ddev-handover.sh 644
opencode-permissions-kit-lib/sh/ddev-hosts.sh 644
opencode-permissions-kit-lib/sh/ddev-migrate.sh 644
opencode-permissions-kit-lib/sh/ddev-terminal.sh 644
opencode-permissions-kit-lib/sh/deploy-lib.sh 644
opencode-permissions-kit-lib/sh/fs-baseline.sh 644
opencode-permissions-kit-lib/sh/git-check.sh 644
opencode-permissions-kit-lib/sh/log.sh 644
# path-sane.sh: the project-root policy gate (issue #216) — bounds the
# recursive group baseline; sourced by install.sh and config.sh with
# fail-closed stubs.
opencode-permissions-kit-lib/sh/path-sane.sh 644
# doctor-core.sh: the doctor run's section functions (issue #346 wave
# shape, #448), sourced checkout-first by management/doctor.sh
opencode-permissions-kit-lib/sh/doctor-core.sh 644
# install-core.sh: the install run's phase functions (issue #346), sourced
# by install.sh from its checkout/fetch tree (kit_source, no LIBDIR
# fallback — install.sh never runs from the installed tree)
opencode-permissions-kit-lib/sh/install-core.sh 644
# uninstall-core.sh: the uninstall run's section functions (issue #346),
# sourced checkout-first by management/uninstall.sh (with the deployed
# $LIBDIR fallback -- `opk uninstall` runs from the installed tree)
opencode-permissions-kit-lib/sh/uninstall-core.sh 644
# handover-core.sh: the opk handover subcommand (issue #415 ride-along on
# #346), sourced by bin/opk through its SELF-resolved $LIBDIR
opencode-permissions-kit-lib/sh/handover-core.sh 644
# openchamber-core.sh: the opk openchamber-secure subcommand (#415 wave 1,
# the #346 wave shape), sourced by bin/opk through its SELF-resolved $LIBDIR
opencode-permissions-kit-lib/sh/openchamber-core.sh 644
# as-opencode-core.sh: the opencode wrapper's section functions (#415 wave 3,
# the #346 wave shape), sourced by bin/opencode-as-opencode through its
# SELF-resolved $LIBDIR
opencode-permissions-kit-lib/sh/as-opencode-core.sh 644
opencode-permissions-kit-lib/sh/render-agent-config.sh 644
opencode-permissions-kit-lib/sh/secure-binary.sh 644
opencode-permissions-kit-lib/sh/shell-warn.sh 644
opencode-permissions-kit-lib/sh/staged-write.sh 644
# status-core.sh: the status report's section functions (issue #346),
# sourced checkout-first by management/status.sh
opencode-permissions-kit-lib/sh/status-core.sh 644
opencode-permissions-kit-lib/sh/sudoers-deploy.sh 644
opencode-permissions-kit-lib/sh/tui-plugin.sh 644
opencode-permissions-kit-lib/sh/ui.sh 644
# update-check.sh: kit update probes (issue #358), sourced by the
# wrapper (daily banner note) and status.sh (live Core row)
opencode-permissions-kit-lib/sh/update-check.sh 644
# update-core.sh: the update run's phase functions (issue #346), sourced
# checkout-first by management/update.sh
opencode-permissions-kit-lib/sh/update-core.sh 644
opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh 644
# tui/ mode display (internal/records/_archive/design/plan-ui-tui-opencode.md)
opencode-permissions-kit-lib/tui/kit-mode-2x.tsx 644
opencode-permissions-kit-lib/tui/kit-mode.tsx 644
opencode-permissions-kit-lib/tui/opencode-danger.theme.json 644
opencode-permissions-kit-lib/tui/tui-danger.json 644
opencode-permissions-kit-lib/tui/tui.json 644
DL_MANIFEST
    return 0
}
