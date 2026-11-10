# shellcheck shell=sh
# opencode permissions kit -- openchamber-core.sh
#
# The opk openchamber-secure subcommand's logic (#415 wave 1, the
# #346 wave shape): the former case arm of bin/opk, moved verbatim
# (pure code movement -- the normalized body equals the old arm
# modulo indent; in CODE nothing differs at all, and the old arm's
# lead comment was hoisted into this header). The dispatcher
# sources this lib and calls openchamber_core with the args after
# the subcommand. Sourced (never executed) by bin/opk through its
# $LIBDIR (SELF-resolved: the checkout copy when run from a
# checkout, the deployed tree otherwise -- bin/opk always has a
# real $0, no stdin-run anchor needed here), loud abort when the
# lib is missing (the #165 class: no silent arm drop); the pairing
# guard in the dispatcher refuses a version-skewed pairing.
#
# POSIX sh, no top-level side effects (definitions and comments
# only). The function runs in the CALLER's shell (bin/opk sets
# set -u only) and reads the globals the dispatcher sets before
# the call: LIBDIR (the auto-sudo hop re-enters bin/opk through
# it), INSTALL_CONF, the ui_* helpers (or their dispatcher
# fallbacks) and oc_bypass_bin (the bypass-binary probe, which
# stays in bin/opk -- a dispatcher-level helper like the ui
# fallbacks). It exits the script on usage errors and after the
# run (the arm did the same); the flag parse runs BEFORE the
# sudo hop, so usage errors need no elevation.
#
# OpenChamber hardening (issue #154, hoisted from the old arm's
# lead comment, internal/records/openchamber-2x-hardening.md):
# write the admin-owned policy pin (/etc/openchamber/policy.json)
# that makes OpenChamber spawn the kit wrapper -- retroactively
# defusing a one-click settings pin -- record the opt-in (opk
# update re-applies the pin), and with consent remove leftover
# bypass binaries + the settings pin (a pin without binaries
# hangs OpenChamber at startup). Idempotent. Auto-sudo like
# config/update.

openchamber_core() {
    OC_YES=false
    for _oca in "$@"; do
        case "$_oca" in
            --yes) OC_YES=true ;;
            *)
                ui_error "unknown flag for openchamber-secure: $_oca (only --yes)"
                exit 1
                ;;
        esac
    done
    if [ "$(id -u)" -ne 0 ]; then
        exec sudo sh "$LIBDIR/bin/opk" openchamber-secure "$@"
    fi
    # Running as root from here.
    _oc_duser=$(sed -n 's/^DEFAULT_USER=//p' "$INSTALL_CONF" 2>/dev/null | tail -1)
    if [ -z "$_oc_duser" ]; then
        ui_error "DEFAULT_USER not found in $INSTALL_CONF — is the kit installed?"
        exit 1
    fi
    ui_info "Writing the OpenChamber policy pin ..."
    # 0.0.47a F1: this explicit command DOES replace divergent content
    # (that is its job) — but never silently: announce the replacement.
    _oc_expected='{ "opencodeBinary": "/usr/local/bin/opencode" }'
    if [ -f /etc/openchamber/policy.json ] &&
        [ "$(cat /etc/openchamber/policy.json 2>/dev/null)" != "$_oc_expected" ]; then
        ui_info "existing /etc/openchamber/policy.json diverges from the kit pin — replacing it"
    fi
    mkdir -p /etc/openchamber
    # Atomic stage+mv (#211 a F17, the 0.0.44a V10 sibling gap): a
    # kill mid-redirect used to leave a truncated/empty policy.json
    # and silently deactivate the pin — the live file now flips via
    # rename only, the truncate window sits on the pid-suffixed
    # temp (0.0.42e C5 shape).
    _ocp_tmp="/etc/openchamber/policy.json.opk-new.$$"
    # The write's rc is gated too (#211 c W7): opk carries no set -e,
    # so a partially-written temp (create ok, write fails — ENOSPC)
    # flowed through chown || true and chmod+mv — both succeed on the
    # truncated file — installing a broken pin under ui_success.
    # (Deliberately an `|| { …; }` one-liner: the F17 pin's extract
    # ends at this block's first 4-space `fi` — a second one would
    # truncate it.)
    printf '{ "opencodeBinary": "/usr/local/bin/opencode" }\n' >"$_ocp_tmp" ||
        {
            rm -f "$_ocp_tmp"
            ui_error "could not stage the policy pin (write to the temp failed)"
            exit 1
        }
    chown root:root "$_ocp_tmp" 2>/dev/null || true
    # Failure path cleans the staged temp (#211 b W8): opk carries
    # no cleanup trap, and the pid suffix means a stranded
    # root-owned .opk-new.$$ in /etc is never cleaned by a later
    # run. mv -f replaces a symlink at policy.json rather than
    # writing through it (#211 b W19) — the announced replace is
    # this command's documented job.
    if ! { chmod 644 "$_ocp_tmp" && mv -f "$_ocp_tmp" /etc/openchamber/policy.json; }; then
        rm -f "$_ocp_tmp"
        ui_error "could not install the policy pin (chmod/mv on the staged temp failed)"
        exit 1
    fi
    ui_success "policy pin active: /etc/openchamber/policy.json -> /usr/local/bin/opencode"
    # Record the opt-in so update.sh keeps re-applying the pin.
    if grep -q '^OPENCHAMBER_POLICY=' "$INSTALL_CONF" 2>/dev/null; then
        sed -i 's/^OPENCHAMBER_POLICY=.*/OPENCHAMBER_POLICY=yes/' "$INSTALL_CONF"
    else
        printf '\nOPENCHAMBER_POLICY=yes\n' >>"$INSTALL_CONF"
    fi
    # Leftover bypass files: inert under the policy, but removing them
    # now avoids the startup hang if the policy ever disappears.
    # HOME via getent, not /home/<user> (0.0.43b W1 class); a kit
    # symlink to the wrapper is never a bypass binary (0.0.47a F3).
    _oc_home=$(getent passwd "$_oc_duser" 2>/dev/null | cut -d: -f6 || true)
    if [ -z "$_oc_home" ]; then
        ui_detail "could not resolve the home of '$_oc_duser' — leftover scan skipped"
        ui_detail "restart OpenChamber if it is running (full stop + start)"
        exit 0
    fi
    _oc_found=""
    for _ocn in opencode opencode2; do
        if oc_bypass_bin "$_oc_home/.opencode/bin/$_ocn"; then
            _oc_found="x"
        fi
    done
    _oc_settings="$_oc_home/.config/openchamber/settings.json"
    if grep -q '"opencodeBinary"' "$_oc_settings" 2>/dev/null; then
        _oc_found="x$_oc_found"
    fi
    if [ -z "$_oc_found" ]; then
        ui_detail "no leftover bypass files found"
        ui_detail "restart OpenChamber if it is running (full stop + start)"
        exit 0
    fi
    echo ""
    ui_info "Leftover bypass files found (inert under the policy):"
    for _ocn in opencode opencode2; do
        oc_bypass_bin "$_oc_home/.opencode/bin/$_ocn" &&
            ui_detail "  $_oc_home/.opencode/bin/$_ocn"
    done
    grep -q '"opencodeBinary"' "$_oc_settings" 2>/dev/null &&
        ui_detail "  settings pin: \"opencodeBinary\" in $_oc_settings"
    if [ "$OC_YES" != true ]; then
        # (#370 a E3): default n (the conventions' system-change
        # direction, agent/conventions.md "Interactive prompts" —
        # removal changes the system). Under the old y default an unattended EOF (the
        # fallback confirm follows the caller's default) REMOVED
        # the bypass files; scripted callers use --yes.
        if ! ui_confirm "Remove them now?" "n"; then
            ui_detail "kept — 'sudo opk openchamber-secure' removes them later"
            ui_detail "restart OpenChamber if it is running (full stop + start)"
            exit 0
        fi
    fi
    for _ocn in opencode opencode2; do
        oc_bypass_bin "$_oc_home/.opencode/bin/$_ocn" &&
            rm -f "$_oc_home/.opencode/bin/$_ocn"
    done
    ui_success "bypass binaries removed (if present)"
    if grep -q '"opencodeBinary"' "$_oc_settings" 2>/dev/null; then
        # Guard and execution share ONE resolution context (#244 f W2,
        # the e-S1 class): the guard runs inside the sudo context, so
        # a secure_path that differs from the caller's PATH cannot make
        # the two disagree (not-found noise on one arm, a skipped edit
        # sudo could perform on the other). Operands pass as argv to
        # the inner sh; the heredoc feeds python3's stdin through it.
        # -I (#249, review a C2): the tui-plugin twin's shape — the
        # edit must not follow a poisoned PYTHONHOME/PYTHONPATH
        # (sudo's env_reset strips them today; env_keep re-opens it).
        if sudo -u "$_oc_duser" sh -c 'command -v python3 >/dev/null 2>&1 && exec python3 -I "$@"' \
            opk-settings-edit - "$_oc_settings" <<'PYEOF'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
try:
    d = json.loads(p.read_text())
except ValueError:
    sys.exit(1)
if isinstance(d, dict) and "opencodeBinary" in d:
    del d["opencodeBinary"]
    p.write_text(json.dumps(d, indent=2) + "\n")
else:
    # No key removed (#244 g S1): the caller's grep hit the literal
    # as a VALUE — report failure instead of a false success.
    sys.exit(1)
PYEOF
        then
            ui_success "settings pin removed from $_oc_settings"
        else
            # Four rc-1 causes share this branch, deliberately
            # (#244 h S3): no key removed (g S1), unparseable
            # JSON, python3 missing, write failure — all fail
            # closed; the unit pin separates via empty stderr.
            # pr-00263 c C2: failing closed includes the rc — the
            # branch used to fall through to exit 0.
            ui_error "could not update $_oc_settings — remove the \"opencodeBinary\""
            ui_error "entry (key or value) by hand — docs/how-to/openchamber.md"
            exit 1
        fi
    fi
    ui_detail "restart OpenChamber if it is running (full stop + start)"
}
