# shellcheck shell=sh
# opencode permissions kit -- update-core.sh
#
# The update run's phase logic (issue #346, wave 2): every phase section
# of management/update.sh as a function — pure code movement, output
# byte-identical. Sourced (never executed) by update.sh, checkout-first;
# POSIX sh, no top-level side effects (definitions and comments only).
# The functions run in the CALLER's shell under its `set -eu`: they read
# the globals update.sh's main flow sets (YES, REFRESH, BINARY_UPDATE,
# ONLY_BINARY, BINARY_PATH, UPGRADE_MAJOR, UPGRADE_VERSION, VERSION,
# KIT_BRANCH, LIBDIR, CONFDIR, PROJECTS_CONF, FILES_ROOT, INSTALL_CONF,
# DEFAULT_USER, DEFAULT_HOME, OPENCODE_USER, NEW_OPENCODE_GROUP) and call
# the entry's helpers (ui_* from sh/ui.sh, log from sh/log.sh, die,
# _tmp_track) plus the shared libs update.sh sources before the phases
# (lib_deploy, sudoers_deploy, copy_file_atomic, copy_binary_atomic,
# secure_binary, staged_write, agent_home_sane, tui_plugin_sync_user).
# update.sh sequences the sections in run order; cross-phase state stays
# global by design: update_binary_resecure sets SYSTEM_BIN/BINARY_GROUP
# (read by the helpers below it and update_binary_upgrade), and
# update_finalize_ddev_stamp sets NEW_DDEV_VERSION (read by
# update_finalize_install_conf's re-stamp).

# --- kit re-deploy sections (update.sh skips this whole area under --only-binary)

update_redeploy_library() {
    # --- re-deploy library files (skipped by --only-binary) ------------------------

    ui_section "Re-deploying library files"

    # Deploy via the shared manifest (sh/deploy-lib.sh): the single source
    # of truth for what ships into $LIBDIR — layout, file set and modes
    # live there, enforced against the fetch lists by test-kit-files. The
    # browser-bridge stand-in tree + wsl.conf carrier are re-applied below,
    # after the library is in place.
    lib_deploy "$FILES_ROOT" "$LIBDIR"

    # --- old-layout cleanup (0.0.29 streamline, internal/records/streamline.md §5) --------
    # Remove the union of pre-0.0.29 deployed paths after the new layout is in
    # place. Idempotent rm -f — covers every historical location since 0.0.14.
    for _opk_old in \
        "$LIBDIR/wrapper" "$LIBDIR/kit" "$LIBDIR/jsonc-parser.py" \
        "$LIBDIR/bin/socket-check.sh" "$LIBDIR/bin/cwd-check.sh" \
        "$LIBDIR/log.sh" "$LIBDIR/ui.sh" "$LIBDIR/shell-warn.sh" \
        "$LIBDIR/setup-container-backend.sh" "$LIBDIR/ddev-as-opencode.sh" \
        "$LIBDIR/ddev-handover.sh" "$LIBDIR/ddev-migrate.sh" \
        "$LIBDIR/ddev-hosts.sh" "$LIBDIR/fs-baseline.sh" \
        "$LIBDIR/config.sh" "$LIBDIR/update.sh" "$LIBDIR/status.sh" "$LIBDIR/uninstall.sh" \
        "$LIBDIR/sudoers.template" "$LIBDIR/opencode.jsonc" "$LIBDIR/opencode-deny-all.jsonc" \
        "$LIBDIR/migrate-denies.sh"; do
        [ -e "$_opk_old" ] && sudo rm -f "$_opk_old" && ui_detail "removed old file: $_opk_old"
    done
    ui_success "library re-deployed: $LIBDIR"
    log "library re-deployed: $LIBDIR (old-layout cleanup applied)"
}

update_redeploy_wsl_bridge() {
    # --- WSL browser bridge (issues #91, #100) -------------------------------------
    # (Re)apply the stand-in tree and strip the legacy 0.0.36 section (kit-owned
    # regression cleanup). The /etc/wsl.conf carrier is NEVER written here —
    # the kit does not edit wsl.conf implicitly (internal/records/wsl-conf-consent.md);
    # the user opts in via 'sudo opk wsl-add-opencode-1-fix'. An existing
    # carrier stays untouched and keeps working.
    # First-wins lookup (#211 a F5, wsl-browser-bridge site): the old
    # back-to-back sourcing let the deployed LIBDIR copy override the
    # checkout copy — the documented "prefer the checkout vintage" was
    # inverted in code. Sibling shape: config.sh's helper lookups.
    for cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh" "$LIBDIR/sh/wsl-browser-bridge.sh"; do
        if [ -f "$cand" ]; then
            . "$cand"
            break
        fi
    done
    command -v browser_bridge_is_wsl >/dev/null 2>&1 || browser_bridge_is_wsl() { return 1; }
    # Guard, not a mutator path (#211 b W22): unreachable in silence — the
    # is_wsl stub above keeps the re-apply block below closed when the lib
    # is missing from both lookup sites.
    command -v browser_bridge_install >/dev/null 2>&1 || browser_bridge_install() { :; }
    # Fail-safe stub (#211 a F7): if the never-shadow probe itself is
    # unavailable (wsl-browser-bridge.sh missing from both lookup sites),
    # both call sites below must err on the never-shadow side — rc 0
    # ("a real one might exist") removes/withholds the shim instead of
    # shadowing one. Sibling guard: status.sh wraps its call in
    # command -v (0.0.46a F4); update.sh was the unswept twin.
    command -v xdg_open_real_exists >/dev/null 2>&1 || xdg_open_real_exists() { return 0; }
    if browser_bridge_is_wsl; then
        # Failure-honest since 0.0.45c C4: browser_bridge_install propagates a
        # failed stand-in deploy or legacy strip — the old unconditional
        # success line reported "re-applied" even when nothing was written.
        if browser_bridge_install "$FILES_ROOT" "$LIBDIR"; then
            if grep -q '^# opencode permissions kit browser bridge -- begin$' /etc/wsl.conf 2>/dev/null; then
                ui_success "WSL browser bridge re-applied (carrier present — fully active)"
                log "wsl browser bridge re-applied: $LIBDIR/wsl (carrier present)"
            else
                ui_success "WSL browser bridge stand-in re-applied (no wsl.conf carrier)"
                ui_detail "enable the opencode 1.x login fix yourself (the kit does not edit /etc/wsl.conf):"
                ui_detail "  sudo opk wsl-add-opencode-1-fix"
                log "wsl browser bridge stand-in re-applied: $LIBDIR/wsl (carrier left to 'opk wsl-add-opencode-1-fix')"
            fi
        else
            ui_warn "WSL browser bridge: stand-in deploy or legacy wsl.conf strip FAILED"
            ui_detail "see the errors above; re-run the update or fix /etc/wsl.conf manually"
            log "wsl browser bridge re-apply FAILED (deploy/strip)"
        fi
    fi
}

update_redeploy_cli_links() {
    # --- re-link wrapper + cli dispatcher ------------------------------------------

    sudo ln -sf "$LIBDIR/bin/opencode-as-opencode" /usr/local/bin/opencode
    ui_success "wrapper symlink refreshed: /usr/local/bin/opencode -> $LIBDIR/bin/opencode-as-opencode"
    sudo rm -f /usr/local/bin/opencode-permissions-kit
    sudo ln -sf "$LIBDIR/bin/opk" /usr/local/bin/opk
    ui_success "cli symlink refreshed: /usr/local/bin/opk -> $LIBDIR/bin/opk (legacy name removed)"
}

update_redeploy_xdg_shim() {
    # --- xdg-open fallback shim (opencode 1.18.33+ / 2.0.18+ login fix) -------------

    # Deploy only while no real xdg-open exists; heal the shadow case (a real
    # one appeared since install -> the kit stands back). Guards share the
    # never-shadow probe with install.sh (0.0.42d S1/C1): xdg_open_real_exists
    # scans the whole PATH except /usr/local/bin (our shim's slot) — a real
    # xdg-open under /usr/sbin or /snap/bin no longer gets shadowed.
    if [ -L /usr/local/bin/xdg-open ] &&
        [ "$(readlink /usr/local/bin/xdg-open 2>/dev/null || true)" = "$LIBDIR/bin/xdg-open" ]; then
        if xdg_open_real_exists; then
            sudo rm -f /usr/local/bin/xdg-open
            ui_detail "xdg-open fallback removed: a real xdg-open on PATH took over"
            log "xdg-open shim removed: real xdg-open present on PATH"
        else
            ui_detail "xdg-open fallback active: /usr/local/bin/xdg-open -> $LIBDIR/bin/xdg-open"
            log "xdg-open shim active: /usr/local/bin/xdg-open"
        fi
    elif ! [ -e /usr/local/bin/xdg-open ] && ! [ -L /usr/local/bin/xdg-open ] &&
        ! xdg_open_real_exists; then
        sudo ln -s "$LIBDIR/bin/xdg-open" /usr/local/bin/xdg-open
        ui_success "xdg-open fallback installed: /usr/local/bin/xdg-open -> $LIBDIR/bin/xdg-open"
        log "xdg-open shim symlink: /usr/local/bin/xdg-open -> $LIBDIR/bin/xdg-open"
    fi
}

update_redeploy_sudoers() {
    # --- re-deploy sudoers -------------------------------------------------------

    # Shared pipeline (sh/sudoers-deploy.sh): charset gate, render, visudo
    # validation BEFORE anything is deployed, install mode 440, sudoers.d
    # link, legacy-name cleanup.
    if [ -f "$FILES_ROOT/opencode-permissions-kit-lib/templates/sudoers.template" ]; then
        sudoers_deploy "$FILES_ROOT/opencode-permissions-kit-lib/templates/sudoers.template" "$DEFAULT_USER" ||
            die "sudoers re-deploy failed — nothing was re-deployed (user '$DEFAULT_USER')."
        ui_success "sudoers re-deployed + validated (DEFAULT_USER=$DEFAULT_USER)"
        log "sudoers re-deployed (DEFAULT_USER=$DEFAULT_USER)"
    else
        # Conservative skip (0.0.41f S2): the existing validated sudoers stays
        # active — near-unreachable (fetch list + heal guarantee the file),
        # but the skip must not be silent. pr-00263 a F7: log() alone is the
        # no-op stub when log.sh is missing from both roots — the skip also
        # needs a terminal line.
        ui_detail "sudoers re-deploy skipped: template missing (existing sudoers kept)"
        log "sudoers re-deploy skipped: template missing from $FILES_ROOT (existing sudoers kept)"
    fi
}

update_redeploy_umask() {
    # --- re-deploy umask profile -------------------------------------------------

    if [ -f "$FILES_ROOT/etc/umask.sh" ]; then
        # 0.0.49b C1: atomic re-deploy — a plain in-place cp killed
        # mid-write leaves a truncated profile with intact mode bits,
        # sourced at every login (the #163 class on a protection layer).
        # Same shape as the lib deploys (0.0.49a W2): sibling temp in the
        # target dir, mode 644 before the mv.
        copy_file_atomic "$FILES_ROOT/etc/umask.sh" \
            /etc/profile.d/opencode-permissions-kit-umask.sh 644 ||
            die "umask profile re-deploy failed (atomic deploy)"
        # Remove the pre-0.0.10 umask profile so only the new name is loaded.
        sudo rm -f /etc/profile.d/opencode-umask.sh 2>/dev/null || true
        ui_success "umask profile re-deployed"
        log "umask profile re-deployed: /etc/profile.d/opencode-permissions-kit-umask.sh"
    else
        # Conservative skip, loud like the sudoers twin above (0.0.41f S2
        # shape, #211 a F6): near-unreachable (fetch list + heal guarantee
        # the file), but the skip must not be silent — an update that
        # quietly dropped a protection-layer deploy is undebuggable.
        # pr-00263 a F7: terminal line too (log() alone degrades to the
        # no-op stub when log.sh is missing from both roots).
        ui_detail "umask profile re-deploy skipped: source file missing (existing profile kept)"
        log "umask profile re-deploy skipped: $FILES_ROOT/etc/umask.sh missing (existing profile kept)"
    fi
}

update_redeploy_openchamber() {
    # --- OpenChamber policy pin (issue #154) ---------------------------------------
    # Re-apply only when the install opted in (install.conf
    # OPENCHAMBER_POLICY=yes — sourced above). A policy.json without the opt-in
    # is admin-owned and never touched here; without the opt-in the file is
    # also never created (opt-in only, see the design record).
    # 0.0.47a F1: the re-apply is additionally gated on the file still being
    # kit-shaped (byte-identical to the one-liner the kit writes) — a file the
    # admin extended or replaced is NEVER overwritten; the skip is loud.
    # Issue #164: the presence probe runs at the write's authority (sudo) —
    # an admin 0700 /etc/openchamber must not read as "absent" to a direct
    # non-root run and slip the branch into the sudo write.
    if [ "${OPENCHAMBER_POLICY:-}" = "yes" ]; then
        _oc_expected='{ "opencodeBinary": "/usr/local/bin/opencode" }'
        if sudo test -f /etc/openchamber/policy.json &&
            [ "$(sudo cat /etc/openchamber/policy.json 2>/dev/null)" != "$_oc_expected" ]; then
            ui_warn "openchamber policy pin NOT re-applied: /etc/openchamber/policy.json"
            ui_warn "diverges from the kit pin (admin-owned content) — left untouched"
            ui_detail "force it with: sudo opk openchamber-secure (replaces the file)"
            log "openchamber policy pin NOT re-applied: existing file diverges (admin-owned)"
        else
            sudo mkdir -p /etc/openchamber
            # Atomic stage+mv (#211 a F17, opk twin): the live policy.json
            # flips via rename only — a kill mid-tee used to leave a
            # truncated file and a silently inactive pin.
            _ocp_tmp="/etc/openchamber/policy.json.opk-new.$$"
            # Registered BEFORE staging (#211 b W8, order per #211 c W3):
            # the trap's rm -f tolerates an absent path, so an abort DURING
            # the tee (temp created, write fails — ENOSPC under set -e) is
            # covered too, not just aborts between staging and the flip.
            _tmp_track "$_ocp_tmp"
            printf '{ "opencodeBinary": "/usr/local/bin/opencode" }\n' |
                sudo tee "$_ocp_tmp" >/dev/null
            sudo chown root:root "$_ocp_tmp" 2>/dev/null || true
            sudo chmod 644 "$_ocp_tmp"
            # mv replaces a symlink at policy.json rather than writing
            # through it (#211 b W19) — the announced replace is this
            # block's documented job.
            sudo mv -f "$_ocp_tmp" /etc/openchamber/policy.json
            ui_success "openchamber policy pin re-applied: /etc/openchamber/policy.json"
            log "openchamber policy pin re-applied: /etc/openchamber/policy.json"
        fi
    fi
}

update_redeploy_shell_hooks() {
    # --- shell-startup hooks (rewrite old paths, append when missing) ---------------
    # Older installs lack the interactive-shell hooks — append them idempotently
    # so a self-installed opencode binary is reported and `ddev()` stays wrapped.
    # 0.0.29 moved the hooked files (shell-warn.sh, ddev-as-opencode.sh ->
    # sh/ddev-terminal.sh): the rc lines reference them by absolute path, and
    # their [ -f ... ] guard would silently disable the hook after the move.
    # The kit-owned line is therefore REWRITTEN in place (exact path match —
    # user lines are never touched, the guard keeps the line harmless after
    # uninstall); the hook is only appended when no kit hook line exists at all.
    # Root-shell installs (issue #192) registered root as the developer:
    # update must not paper over that by provisioning root's rc files — the
    # real developer still gets nothing. Warn loudly and skip; a missing
    # home gets the same loud skip instead of the old silent one (the row in
    # status.sh told users "run opk update", which this very section then
    # skipped without a word).
    if [ -n "$DEFAULT_USER" ]; then
        _du_uid="$(id -u "$DEFAULT_USER" 2>/dev/null || echo 1)"
        if [ "$_du_uid" = "0" ]; then
            ui_warn "shell-startup hooks skipped: the install recorded '$DEFAULT_USER' (uid 0)"
            ui_warn "as the developer — a root-shell install cannot be updated into shape"
            ui_detail "reinstall from your normal user (issue #192): opk update cannot fix this"
            log "shell-startup hooks skipped: DEFAULT_USER=$DEFAULT_USER is uid 0 (issue #192)"
        elif [ -d "$DEFAULT_HOME" ]; then
            for cf in "$DEFAULT_HOME/.bashrc" "$DEFAULT_HOME/.zshrc" "$DEFAULT_HOME/.profile"; do
                [ -f "$cf" ] || continue
                if sudo grep -q 'opencode-permissions-kit/sh/shell-warn.sh\|opencode-permissions-kit/shell-warn.sh' \
                    "$cf" 2>/dev/null; then
                    sudo sed -i "s|/usr/local/lib/opencode-permissions-kit/shell-warn\.sh""\
|/usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh|g" "$cf"
                else
                    echo "[ -f /usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh ] && . ""\
/usr/local/lib/opencode-permissions-kit/sh/shell-warn.sh  # opencode permissions kit""\
 (wrapper bypass warning)" | sudo tee -a "$cf" >/dev/null
                    ui_success "wrapper-bypass warning hooked into $cf"
                    log "shell-startup warning hook appended: $cf"
                fi
                # ddev always runs as the opencode user: hook the `ddev()` shell
                # function (sudoers helper). Only the DEFAULT user — the opencode
                # session must never be wrapped (the function's id check is the guard).
                if sudo grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh\|opencode-permissions-kit/ddev-as-opencode.sh' \
                    "$cf" 2>/dev/null; then
                    sudo sed -i "s|/usr/local/lib/opencode-permissions-kit/ddev-as-opencode\.sh""\
|/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh|g" "$cf"
                else
                    echo "[ -f /usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh ] && . ""\
/usr/local/lib/opencode-permissions-kit/sh/ddev-terminal.sh  # opencode permissions kit""\
 (ddev always runs as opencode)" | sudo tee -a "$cf" >/dev/null
                    ui_success "ddev terminal hook installed into $cf"
                    log "ddev-terminal hook appended: $cf"
                fi
            done
        else
            ui_warn "shell-startup hooks skipped: home '$DEFAULT_HOME' of '$DEFAULT_USER' does not exist"
            log "shell-startup hooks skipped: missing developer home $DEFAULT_HOME"
        fi
    fi
}

update_redeploy_project_roots() {
    # --- .ddev + settings-dir handover (ddev always runs as the opencode user) -----
    # ddev chmods .ddev and the app-type's settings directories unconditionally,
    # and chmod is owner-only — they must belong to the opencode user or
    # `ddev start` fails with "operation not permitted". Searched at ANY depth
    # under each registered root (a root is often a parent of several projects).
    # Unconditional (not just inside the migration) so installs that already
    # migrated — the common upgrade path — are healed too. .git dirs are
    # never chowned — they stay developer-owned (the group baseline makes
    # them group-accessible).
    # Issue #112: the ROUTINE update skips roots whose scan-skip stamp still
    # matches (ddev_handover_stamp_valid — user/group/dev user/dev-owned
    # mode/scan rev), because re-scanning every large tree on every update cost
    # minutes while nothing had changed. Anything doubtful falls back to the
    # full scan; --refresh and every explicit config path (projects add,
    # refresh, handover) always scan and re-stamp.
    if [ -f "$PROJECTS_CONF" ] && [ -n "$NEW_OPENCODE_GROUP" ]; then
        # Shared helper: prefer the copy next to this script (checkout — same
        # vintage as the running update.sh), fall back to the deployed library.
        # First-wins lookup (#211 a F5, ddev-handover site): same fix as the
        # wsl-browser-bridge site above — LIBDIR must never shadow a checkout
        # copy that is present.
        for cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/ddev-handover.sh" "$LIBDIR/sh/ddev-handover.sh"; do
            if [ -f "$cand" ]; then
                . "$cand"
                break
            fi
        done
        command -v ddev_handover_root >/dev/null 2>&1 || ddev_handover_root() {
            # Loud like config.sh's stubs (#211 a F2 sweep): a silent no-op
            # let the loop below log "ddev handover pass completed" over a
            # pass that never ran. Near-unreachable (lib_deploy refreshed
            # the library above) — the contract is what matters: fail loud,
            # let set -e stop the update instead of lying in the audit log.
            echo "error: ddev_handover_root unavailable (ddev-handover.sh missing)" >&2
            return 1
        }
        command -v ddev_handover_stamp_valid >/dev/null 2>&1 || ddev_handover_stamp_valid() { return 1; }
        command -v ddev_handover_stamp_write >/dev/null 2>&1 || ddev_handover_stamp_write() { :; }
        # Single project-root pass (issue #219): --refresh used to pay a
        # second full scan — this loop (stamp-skip opened under REFRESH)
        # already ran ddev_handover_root over every root, then a separate
        # end-of-run block re-scanned the same roots for the group baseline
        # AND the handover again. The baseline arm now rides this loop;
        # per-root order matches the old refresh block (baseline first,
        # handover second, stamp last — the stamp records a completed
        # pass). .ddev ownership comes from the handover's chown alone
        # (ddev-handover.sh) — the baseline's chgrp never re-owns, so the
        # per-root end state does not depend on this order.
        if [ "$REFRESH" = true ]; then
            ui_section "Refreshing group baseline"
            # Shared helper with live per-pass progress (issue #14 — large trees
            # used to run minutes in silence during --refresh).
            _fsbl=""
            for _fsbl_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/fs-baseline.sh" "$LIBDIR/sh/fs-baseline.sh"; do
                if [ -f "$_fsbl_cand" ]; then
                    . "$_fsbl_cand"
                    _fsbl="$_fsbl_cand"
                    break
                fi
            done
            # Loud like the config.sh twin and the ddev_handover_root stub above
            # (#211 b W3 — the a F2 sweep stopped at this file's handover stub):
            # a silent no-op let --refresh log "group baseline refreshed" over a
            # pass that never ran. Fail loud, let set -e stop the update.
            command -v fs_baseline_root >/dev/null 2>&1 || fs_baseline_root() {
                echo "error: fs_baseline_root unavailable (fs-baseline.sh missing)" >&2
                return 1
            }
        fi
        _ho_skip=0
        _ho_announced=false
        while IFS= read -r root; do
            [ -z "$root" ] && continue
            # Form gate, writer parity (review a S1/S2, completed b X1,
            # issue #245): `link/.` dodges the [ -L ] gate below and
            # the helper belt's strip (recursive baseline on the link's
            # target); `link//` reaches the belt as `link/` and its
            # rc-1 refusal aborts the whole update under set -e; a bare
            # `.` or relative spelling would hand fs_baseline_root the
            # invoking CWD (measured, b X1). Absolute first, then
            # dots/empty segments, then whitespace — the writer's arm
            # order (path-sane.sh); the blocklist rides #247.
            case "$root" in
                /*) ;;
                *)
                    ui_warn "skip $root (not an absolute project path)"
                    continue
                    ;;
            esac
            case "$root" in
                *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]*)
                    ui_warn "skip $root (malformed project path — dot, empty segment, or whitespace)"
                    continue
                    ;;
            esac
            root="${root%/}"
            [ -n "$root" ] || continue
            # Symlinked root gate (issue #245), before [ -d ] (review
            # a S3): a dangling link is a symlink first — [ -d ] would
            # swallow it silently under the green summary lines.
            if [ -L "$root" ]; then
                ui_warn "skip $root (symlink — register the target directory instead)"
                continue
            fi
            [ -d "$root" ] || continue
            if [ "$REFRESH" != true ] &&
                ddev_handover_stamp_valid "$root" "$OPENCODE_USER" "$NEW_OPENCODE_GROUP" "$DEFAULT_USER"; then
                _ho_skip=$((_ho_skip + 1))
                continue
            fi
            if [ "$_ho_announced" = false ]; then
                ui_detail "scanning project roots for ddev directories (large trees: this can take a while) ..."
                _ho_announced=true
            fi
            if [ "$REFRESH" = true ]; then
                fs_baseline_root "$root" "$NEW_OPENCODE_GROUP" "$OPENCODE_USER"
            fi
            ddev_handover_root "$root" "$OPENCODE_USER" "$NEW_OPENCODE_GROUP" "$DEFAULT_USER"
            ddev_handover_stamp_write "$root" "$OPENCODE_USER" "$NEW_OPENCODE_GROUP" "$DEFAULT_USER"
            log "ddev handover pass completed under $root"
        done <"$PROJECTS_CONF"
        if [ "$_ho_skip" -gt 0 ]; then
            ui_detail "skipped the ddev handover rescan for $_ho_skip root(s) — nothing changed since the last pass"
            ui_detail "force it with 'sudo opk update --refresh' or 'sudo opk config handover <path>'"
            log "ddev handover rescan skipped for $_ho_skip root(s) (issue #112 stamps)"
        fi
        if [ "$REFRESH" = true ]; then
            ui_success "group baseline refreshed (chgrp + setgid + g+rw + default ACLs)"
            log "group baseline refresh requested (--refresh)"
        else
            ui_detail "skipped group-baseline refresh (use --refresh to re-apply chgrp/setgid/default ACLs)"
        fi
    fi
}

update_redeploy_git_safe() {
    # git "dubious ownership" exception for the opencode user (issue #17) —
    # every registered project root is developer-owned, the agent's git needs
    # safe.directory to run there. Unconditional so existing installs get it
    # on the first update; the get guard keeps it idempotent.
    # -C / (issue #116): sudo keeps the invoking user's CWD — run from an
    # unreadable developer home (mode 750), git >= 2.55 dies with
    # "fatal: error reading '<cwd>/.git'" before touching the global config,
    # and safe.directory is never ensured. chdir to / first; --global ignores
    # the worktree anyway.
    # The audit line must match reality (#211 a F4): a failed --add used to
    # print nothing while the log claimed "ensured" — agent git then failed
    # with 'dubious ownership' long after, with nothing in the audit trail
    # pointing at the cause.
    if command -v git >/dev/null 2>&1; then
        if sudo -u "$OPENCODE_USER" -H git -C / config --global --get-all safe.directory \
            2>/dev/null | grep -qFx '*'; then
            log "git safe.directory ensured for $OPENCODE_USER (already set)"
        elif sudo -u "$OPENCODE_USER" -H git -C / config --global --add safe.directory '*'; then
            ui_success "git safe.directory '*' set for $OPENCODE_USER (agent git access)"
            log "git safe.directory ensured for $OPENCODE_USER"
        else
            ui_warn "could not set git safe.directory '*' for $OPENCODE_USER — agent git may fail""\
 with 'dubious ownership' (git config --global --add failed)"
            log "git safe.directory NOT ensured for $OPENCODE_USER (git config --add failed)"
        fi
    fi
}

update_redeploy_wsl_mntc() {
    # --- WSL2 /mnt/c restriction (report-only — update.sh stays prompt-free) -------
    # The drvfs mount runs with the Windows session token; NTFS ACLs do not
    # distinguish WSL users, so a world-readable /mnt/c exposes the whole
    # Windows profile to every WSL user incl. the agent's. Hint when open,
    # remind about the pending 'wsl --shutdown' when the restriction is
    # configured but not applied yet.
    if [ -d /mnt/c ]; then
        mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
        if [ -n "$mnt_mode" ] && [ $((0$mnt_mode & 0004)) -ne 0 ]; then
            if grep -q '^options *=.*dmask' /etc/wsl.conf 2>/dev/null; then
                ui_warn "/mnt/c restriction configured but still pending 'wsl --shutdown' (Windows)"
                ui_warn "the mount stays world-readable (mode $mnt_mode)""\
 and opencode warns on every start until the distro is reopened."
            else
                ui_warn "/mnt/c is world-readable (mode $mnt_mode) — every WSL user incl. the agent""\
 can read the Windows profile."
                ui_warn "opencode warns on every start until fixed. Recommended fix in /etc/wsl.conf:"
                ui_detail "[automount]"
                ui_detail "enabled = true"
                ui_detail "options = \"uid=$(id -u "$DEFAULT_USER" 2>/dev/null || echo '<uid>'),""\
gid=$(id -g "$DEFAULT_USER" 2>/dev/null || echo '<gid>'),dmask=027,fmask=037\""
                ui_warn "then 'wsl --shutdown' from Windows. The kit never edits /etc/wsl.conf""\
 — apply the snippet yourself."
            fi
        fi
    fi
}

# --- opencode binary upgrade (--binary / --binary-path) ----------------------

update_binary_resecure() {
    SYSTEM_BIN="/usr/local/lib/opencode-permissions-kit/bin/opencode"

    # --- re-assert opencode binary permissions ------------------------------------
    # root:$BINARY_GROUP mode 750 lets the opencode user run the binary and
    # keeps unrelated users out — but it is NOT a developer-side bypass guard:
    # the developer is in the sharing group and CAN exec this path directly;
    # the soft layer (deny-all config + warnings) is what deters that, per the
    # kit's declared model. Shared fail-loud helper (was a silent `|| true`
    # pair here — a failed re-assert continued the update with an unsecured
    # binary, the exact 0.0.39e C4 shape).
    BINARY_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"
    if [ -x "$SYSTEM_BIN" ]; then
        secure_binary "$SYSTEM_BIN" "$BINARY_GROUP" ||
            die "cannot re-secure $SYSTEM_BIN — update aborted."
    fi
}

# Detect the opencode release target for this host (mirrors the official
# installer; the same string is the npm package suffix, see
# tests/e2e/lib.sh).
detect_target() {
    local os arch target
    os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        darwin*) os="darwin" ;;
        linux*) os="linux" ;;
        *) return 1 ;;
    esac
    arch=$(uname -m)
    if [ "$arch" = "aarch64" ]; then arch="arm64"; fi
    if [ "$arch" = "x86_64" ]; then arch="x64"; fi
    target="$os-$arch"
    if [ "$arch" = "x64" ] && [ "$os" = "linux" ] && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
        target="$target-baseline"
    fi
    if [ "$os" = "linux" ] && { [ -f /etc/alpine-release ] ||
        { command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; }; }; then
        target="$target-musl"
    fi
    echo "$target"
}

# Verify a candidate binary actually runs, then install it over $SYSTEM_BIN.
# Bounded `--version` probe (0.0.43b W3): a wedged 2.x service can make
# even --version hang (issue #80) — the update paths, including the
# pre-upgrade major resolution, must never block on it. Empty output
# means unknown, never a guess.
opencode_version_line() {
    if command -v timeout >/dev/null 2>&1; then
        timeout 10 "$SYSTEM_BIN" --version 2>/dev/null | head -1 || true
    else
        "$SYSTEM_BIN" --version 2>/dev/null | head -1 || true
    fi
}

install_binary() {
    local src="$1" current new
    if command -v timeout >/dev/null 2>&1; then
        timeout 30 "$src" --version >/dev/null 2>&1 || return 1
    else
        "$src" --version >/dev/null 2>&1 || return 1
    fi
    # opencode 2.x keeps a background service daemon running the binary
    # (issue #80): replacing it while the daemon lives fails with "Text
    # file busy". Stop the service best-effort first — 2.x answers the
    # graceful stop, 1.x reports an unknown command and both errors are
    # ignored; the pkill is the belt to that braces (also catches a
    # wedged daemon). The next 2.x command re-ensures the service.
    sudo -u "$OPENCODE_USER" "$SYSTEM_BIN" service stop >/dev/null 2>&1 || true
    sudo pkill -u "$OPENCODE_USER" -f "serve --servic[e]" >/dev/null 2>&1 || true
    current=$(opencode_version_line)
    [ -n "$current" ] || current="unknown"
    copy_binary_atomic "$src" "$SYSTEM_BIN" || return 1
    if ! secure_binary "$SYSTEM_BIN" "$BINARY_GROUP"; then
        # rc 2, not 1 (0.0.43a F9): the new binary is ALREADY deployed —
        # the caller must restore from the backup (or report the partial
        # state), never claim "left untouched". The stderr note names the
        # failed step (0.0.44b W7): rc 2 now has more than one source.
        echo "  error: hardening (secure_binary) failed on the deployed candidate" >&2
        return 2
    fi
    new=$(opencode_version_line)
    [ -n "$new" ] || new="unknown"
    # Re-stamp the major so the wrapper's 2.x --standalone gating follows
    # the binary. ONLY when the probe actually returned a line (0.0.44a
    # V5): an empty/failed probe used to persist major 1 over a known-
    # good 2 stamp — the wrapper prefers the stamp, and a 1-stamped 2.x
    # binary attaches sessions to the shared service (the issue-#80 env
    # breakage --standalone exists to prevent). A RETURNED line is always
    # a major (0.0.44b W4): 2.x prints "opencode v2...", 1.x prints the
    # bare version — same parity as current_opencode_major. The old gate
    # treated 1.x lines as "undetermined" and kept a stale 2-stamp across
    # the documented `--major 1` downgrade, so the wrapper passed the
    # 2.x-only --standalone to a 1.x binary on every start.
    # The stamp writes fail loud (0.0.44a V20): rc 2 = post-copy failure,
    # the caller restores from the backup instead of printing "upgraded"
    # over a stale stamp.
    if [ "$new" != "unknown" ]; then
        _new_major=$(printf '%s' "$new" | sed -n 's/^opencode v\([0-9][0-9]*\).*/\1/p')
        if [ -n "$_new_major" ]; then
            : # "opencode v2..." — the 2.x shape
        elif printf '%s' "$new" | grep -qE '^[0-9]+(\.[0-9]+)*$'; then
            _new_major=1 # bare version line = 1.x (current_opencode_major
            # parity; FULL-LINE anchored, 0.0.44d F3: "2.0.11-
            # dev" and digit-leading noise like "404 not
            # found" are unparseable, not major 1)
        else
            # Neither shape (0.0.44c C6): a stdout warning line grabbed by
            # head -1, an exotic prefix — unparseable. Treat like an empty
            # probe: keep the previous stamp rather than defaulting to 1
            # over a known-good 2.
            _new_major=""
        fi
        if [ -n "$_new_major" ]; then
            if [ -f "$CONFDIR/install.conf" ] && grep -q '^OPENCODE_MAJOR=' "$CONFDIR/install.conf" 2>/dev/null; then
                sudo sed -i "s/^OPENCODE_MAJOR=.*/OPENCODE_MAJOR=$_new_major/" "$CONFDIR/install.conf" ||
                    {
                        echo "  error: OPENCODE_MAJOR stamp write failed" >&2
                        return 2
                    }
            elif [ -f "$CONFDIR/install.conf" ]; then
                echo "OPENCODE_MAJOR=$_new_major" | sudo tee -a "$CONFDIR/install.conf" >/dev/null ||
                    {
                        echo "  error: OPENCODE_MAJOR stamp write failed" >&2
                        return 2
                    }
            fi
        else
            echo "  warn: new binary's version line is unparseable — OPENCODE_MAJOR stamp left unchanged" >&2
            log "opencode binary upgraded but major unparseable; OPENCODE_MAJOR stamp kept"
        fi
    else
        echo "  warn: new binary's version could not be probed — OPENCODE_MAJOR stamp left unchanged" >&2
        log "opencode binary upgraded but major unknown; OPENCODE_MAJOR stamp kept"
    fi
    echo "  opencode binary upgraded: ${current} -> ${new}"
    log "opencode binary upgraded: ${current} -> ${new}"
}

# Major of an opencode --version line (issue #99): 2.x prints
# "opencode v2.0.11" -> 2; 1.x prints the bare version ("1.18.31") -> 1.
version_major() {
    printf '%s' "$1" | sed -n 's/^opencode v\([0-9][0-9]*\).*/\1/p'
}

# Major of the currently installed binary — the source of truth; the
# install.conf stamp is the fallback (older kits), 1 the last resort.
current_opencode_major() {
    _com_ver=$(opencode_version_line)
    if [ -n "$_com_ver" ]; then
        _com_maj=$(version_major "$_com_ver")
        if [ -n "$_com_maj" ]; then
            : # "opencode v2..." — the 2.x shape
        elif printf '%s' "$_com_ver" | grep -qE '^[0-9]+(\.[0-9]+)*$'; then
            _com_maj=1 # bare version line = 1.x, full-line anchored —
            # parity with install_binary's re-stamp (0.0.44e
            # E2: this value picks the UPGRADE CHANNEL, a
            # misparsed probe on a 2.x host must not resolve
            # the 1.x channel)
        else
            # unparseable probe line: fall through to the install.conf
            # stamp instead of guessing major 1 (the old mapping would
            # have installed 1.x over a 2.x host on a warning line)
            _com_maj=""
        fi
        if [ -n "$_com_maj" ]; then
            echo "$_com_maj"
            return 0
        fi
    fi
    _com_maj=$(sed -n 's/^OPENCODE_MAJOR=//p' "$CONFDIR/install.conf" 2>/dev/null | tail -1 || true)
    echo "${_com_maj:-1}"
}

# Latest version for a major (issue #99): upgrades never hop majors
# silently. 1.x resolves through GitHub releases/latest (still the 1.x
# channel), 2.x through the npm dist-tag `latest` of @opencode/cli-<target>
# — the channel the official v2 installer resolves through; 2.x ships no
# GitHub release assets (internal/records/opencode-2x.md §8). A resolution
# outside the requested major fails loudly instead of crossing majors.
resolve_latest_opencode_version() {
    _rlov_major="$1"
    _rlov_target=$(detect_target) || return 1
    if [ "$_rlov_major" = 2 ]; then
        # python3 is the kit's canonical JSON parser (grep/sed on a
        # packument can match an earlier "latest": occurrence elsewhere).
        # Interpreter stderr passes through on the failure path (#244 c
        # S3): an unparseable registry body stays silent (the except
        # path is the expected failure), a broken interpreter names
        # itself before the caller's resolve warn. An ABSENT interpreter
        # stays silent too (#244 d Q1): absence is legitimate
        # mid-lifecycle, not a diagnostic event — guarded off; resolve
        # refuses rc 1 either way.
        _rlov_ver=""
        if command -v python3 >/dev/null 2>&1; then
            _rlov_ver=$(curl -fsSL --max-time 10 "https://registry.npmjs.org/@opencode/cli-$_rlov_target" 2>/dev/null |
                python3 -c 'import json,sys
try:
    dist = json.load(sys.stdin)["dist-tags"]
    print(dist["latest"])
except Exception:
    sys.exit(1)
' || true)
        fi
        case "$_rlov_ver" in
            2.*)
                echo "$_rlov_ver"
                return 0
                ;;
            *) return 1 ;;
        esac
    else
        _rlov_ver=$(curl -fsSL --max-time 10 \
            https://api.github.com/repos/anomalyco/opencode/releases/latest 2>/dev/null |
            sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' || true)
        case "$_rlov_ver" in
            1.*)
                echo "$_rlov_ver"
                return 0
                ;;
            *) return 1 ;;
        esac
    fi
}

# Download + extract one exact opencode version into <dir> (channel by
# version prefix, same split as tests/e2e/lib.sh): 2.* from the npm
# registry (legacy @opencode-ai scope as fallback for pre-migration
# versions, tarball layout package/bin/opencode), 1.x from GitHub release
# assets. Prints the candidate binary path on success, nothing on failure.
# The CALLER owns <dir> — cleanup happens only after the install attempt
# (issue #24).
fetch_opencode_version() {
    _fov_dst="$1" _fov_ver="$2"
    [ -n "$_fov_dst" ] && [ -d "$_fov_dst" ] || return 1
    _fov_target=$(detect_target) || return 1
    case "$_fov_ver" in
        2.*)
            if ! curl -fsSL --max-time 240 \
                "https://registry.npmjs.org/@opencode/cli-$_fov_target/-/cli-$_fov_target-$_fov_ver.tgz" \
                -o "$_fov_dst/opencode.tar.gz" 2>/dev/null; then
                curl -fsSL --max-time 240 \
                    "https://registry.npmjs.org/@opencode-ai/cli-$_fov_target/-/cli-$_fov_target-$_fov_ver.tgz" \
                    -o "$_fov_dst/opencode.tar.gz" || return 1
            fi
            mkdir -p "$_fov_dst/npmx" || return 1
            tar -xzf "$_fov_dst/opencode.tar.gz" -C "$_fov_dst/npmx" || return 1
            [ -x "$_fov_dst/npmx/package/bin/opencode" ] || return 1
            mv "$_fov_dst/npmx/package/bin/opencode" "$_fov_dst/opencode" || return 1
            rm -rf "${_fov_dst:?}/npmx" "${_fov_dst:?}/opencode.tar.gz"
            ;;
        *)
            curl -fsSL --max-time 240 \
                "https://github.com/anomalyco/opencode/releases/download/v$_fov_ver/opencode-$_fov_target.tar.gz" \
                -o "$_fov_dst/opencode.tar.gz" || return 1
            tar -xzf "$_fov_dst/opencode.tar.gz" -C "$_fov_dst" || return 1
            rm -f "${_fov_dst:?}/opencode.tar.gz"
            ;;
    esac
    [ -x "$_fov_dst/opencode" ] || return 1
    echo "$_fov_dst/opencode"
    return 0
}

# TUI mode display per major (issue #80): the 1.x artifacts (tui.json +
# danger theme) are major-agnostic — 2.x ignores them and they make a 1.x
# swap work instantly. Only the 2.x CLI-plugin dir flips: present on 2.x
# (symlink to kit-mode-2x.tsx, LIBDIR stays the source of truth), removed
# on 1.x. Inert file-path entries from pre-0.0.35 kits are unregistered
# best-effort on both paths.
sync_tui_registration() {
    _str_major="$1"
    for _str_dir_user in "/home/$OPENCODE_USER/.config/opencode:$OPENCODE_USER" \
        "$DEFAULT_HOME/.config/opencode:$DEFAULT_USER"; do
        _str_user_dir="${_str_dir_user%%:*}"
        _str_dir_owner="${_str_dir_user#*:}"
        # Shared per-user sync (sh/tui-plugin.sh): chain gate, plugins
        # gate, plugin dir + symlink + chowns, inert-entry unregister.
        # Skips (rc 2/3) are logged by the helper; rc 1 dies (the old
        # inline body aborted via set -e, now with a message). The
        # explicit if/fi (0.0.41f C1) keeps skip rcs from leaking as the
        # loop's last status — a bare `[ … ] && die` tail would return 1
        # and silently abort the whole update via set -e AFTER it applied.
        if tui_plugin_sync_user "$_str_major" "$_str_user_dir" "$_str_dir_owner" \
            "$NEW_OPENCODE_GROUP" "$LIBDIR" "$OPENCODE_USER"; then
            :
        else
            _str_tps_rc=$?
            if [ "$_str_tps_rc" -eq 1 ]; then
                die "TUI plugin registration failed for $_str_user_dir"
            fi
        fi
    done
    return 0
}

update_binary_upgrade() {
    ui_section "Upgrading opencode binary"
    SRC=""
    TMP=""
    if [ -n "$BINARY_PATH" ]; then
        if [ -x "$BINARY_PATH" ]; then
            SRC="$BINARY_PATH"
        else
            ui_warn "binary path not found or not executable: $BINARY_PATH — left untouched"
            log "opencode binary upgrade skipped: --binary-path not executable"
        fi
    else
        # Version resolution (issue #99): --version pin > --major switch >
        # stay on the current major. Never crosses majors silently.
        _up_ver=""
        if [ -n "$UPGRADE_VERSION" ]; then
            _up_ver="$UPGRADE_VERSION"
            ui_detail "target version pinned: $_up_ver"
        else
            _up_major="${UPGRADE_MAJOR:-$(current_opencode_major)}"
            ui_detail "resolving the latest opencode $_up_major.x release"
            if ! _up_ver=$(resolve_latest_opencode_version "$_up_major"); then
                ui_warn "could not resolve the latest opencode $_up_major.x release — binary left untouched"
                if [ -z "$UPGRADE_MAJOR" ]; then
                    ui_detail "to switch the opencode major run: opk upgrade-opencode --major 1|2"
                fi
                log "opencode binary upgrade skipped: no $_up_major.x release resolved"
            fi
        fi
        if [ -n "$_up_ver" ]; then
            TMP="$(mktemp -d)"
            _BIN_TMP="$TMP"
            if ! SRC=$(fetch_opencode_version "$TMP" "$_up_ver"); then
                ui_warn "download of opencode $_up_ver failed — binary left untouched"
                log "opencode binary upgrade skipped: download of $_up_ver failed"
                rm -rf "$TMP"
                TMP=""
                _BIN_TMP=""
                SRC=""
            fi
        fi
    fi
    if [ -n "$SRC" ]; then
        BACKUP_DIR="$(mktemp -d /tmp/opencode-upgrade-backup.XXXXXX)"
        if [ -x "$SYSTEM_BIN" ]; then
            copy_binary_atomic "$SYSTEM_BIN" "$BACKUP_DIR/opencode.current"
        fi
        _maj_before=$(current_opencode_major)
        if install_binary "$SRC"; then
            ui_detail "backup kept in $BACKUP_DIR (remove once you are satisfied)"
            # A major flip (v1 <-> v2, issue #99) must re-anchor the TUI
            # registration even in --only-binary runs — the plugin dir is
            # binary-coupled, not kit-coupled.
            _maj_after=$(current_opencode_major)
            if [ "$_maj_before" != "$_maj_after" ]; then
                sync_tui_registration "$_maj_after"
                ui_detail "opencode major changed ($_maj_before -> $_maj_after): TUI registration flipped"
                log "opencode major flipped: $_maj_before -> $_maj_after (tui registration synced)"
            fi
        else
            _ib_rc=$?
            if [ "$_ib_rc" = 2 ]; then
                # Post-copy failure (0.0.43a F9): the candidate IS
                # deployed (unhardened, major not re-stamped). Restore
                # the previous binary so "left untouched" becomes true
                # again; only when that is impossible keep the backup
                # and report the partial state honestly — the backup is
                # the recovery material, it must survive this path.
                if [ -f "$BACKUP_DIR/opencode.current" ] &&
                    copy_binary_atomic "$BACKUP_DIR/opencode.current" "$SYSTEM_BIN" 2>/dev/null &&
                    secure_binary "$SYSTEM_BIN" "$BINARY_GROUP" >/dev/null 2>&1; then
                    ui_warn "candidate installed but a post-install step failed — previous binary restored"
                    ui_warn "(the step's own error line above names it: hardening or the OPENCODE_MAJOR stamp)"
                    log "opencode binary upgrade failed post-copy; previous binary restored from $BACKUP_DIR"
                else
                    ui_warn "candidate installed but a post-install step FAILED — installed binary is NOT verified"
                    ui_warn "(the step's own error line above names it: hardening or the OPENCODE_MAJOR stamp)"
                    if [ -f "$BACKUP_DIR/opencode.current" ]; then
                        ui_warn "previous binary kept at $BACKUP_DIR/opencode.current — restore manually:"
                        ui_warn "  sudo cp $BACKUP_DIR/opencode.current ${SYSTEM_BIN}.tmp"
                        ui_warn "  sudo mv ${SYSTEM_BIN}.tmp $SYSTEM_BIN"
                        log "opencode binary upgrade failed post-copy; PARTIAL state (unhardened), backup kept: $BACKUP_DIR"
                    else
                        # 0.0.43b W6: no binary was executable before the
                        # upgrade, so nothing was copied to the backup —
                        # the restore instruction would name a file that
                        # never existed.
                        ui_warn "no previous binary was backed up (none was installed before this"
                        ui_warn "upgrade) — the unhardened candidate is the only binary present"
                        log "opencode binary upgrade failed post-copy; PARTIAL state (unhardened), no backup existed"
                    fi
                    BACKUP_DIR=""
                fi
            else
                ui_warn "candidate binary failed verification/install — binary left untouched"
                log "opencode binary upgrade skipped: candidate failed verification/install"
            fi
            [ -n "$BACKUP_DIR" ] && rm -rf "$BACKUP_DIR"
        fi
        # Candidate dir cleanup AFTER the install attempt — never before
        # verification (issue #24).
        [ -n "$TMP" ] && rm -rf "$TMP"
    fi
}

# --- finalize sections (update.sh skips this whole area under --only-binary)

update_finalize_opencode_home() {
    # --- ensure default user can access the opencode home -------------------------
    # The home belongs to the opencode user's own usergroup; older installs had it
    # in www-data with mode 750. Apply the current ownership/mode.
    if [ -d "/home/$OPENCODE_USER" ]; then
        sudo chown "$OPENCODE_USER:$NEW_OPENCODE_GROUP" "/home/$OPENCODE_USER"
        sudo chmod 2750 "/home/$OPENCODE_USER"
        ui_success "/home/$OPENCODE_USER re-based to group $NEW_OPENCODE_GROUP (mode 2750)"
    fi
}

update_finalize_default_config() {
    # --- ensure default-user deny-all config (self-update bypass protection) ------
    # Older installs predate this config. Deploy it only if the default user has
    # no config yet — update.sh must not silently clobber an existing one.
    if [ -n "$DEFAULT_USER" ] && [ -d "$DEFAULT_HOME" ]; then
        DEFAULT_OC_CONF="$DEFAULT_HOME/.config/opencode/opencode.jsonc"
        if [ ! -f "$DEFAULT_OC_CONF" ]; then
            sudo mkdir -p "$(dirname "$DEFAULT_OC_CONF")"
            sudo cp "$FILES_ROOT/opencode-permissions-kit-lib/templates/opencode-deny-all.jsonc" "$DEFAULT_OC_CONF"
            sudo chown "$DEFAULT_USER:$NEW_OPENCODE_GROUP" "$DEFAULT_OC_CONF"
            sudo chmod 664 "$DEFAULT_OC_CONF"
            ui_success "deny-all config installed for default user: $DEFAULT_OC_CONF"
            log "deny-all config installed for default user: $DEFAULT_OC_CONF"
        else
            ui_detail "default-user config exists — left untouched (re-run install.sh to back it up)"
        fi
    fi
}

update_finalize_ddev_stamp() {
    # --- live ddev version for the install.conf refresh (issue #72) ------------------
    # DDEV_VERSION is an install-time stamp; a ddev upgrade leaves it behind.
    # Re-probe on every update so the stamp fallback stays honest. Ask the
    # kit's own helper first: ddev >= 1.25.4 refuses to run as root ("DDEV is
    # not designed to be run with root privileges", exit 1 before any output)
    # and updates run as root — the helper runs ddev exactly the way the kit
    # does (as the opencode user, HOME/DOCKER_HOST re-set). The direct binary
    # (PATH, then the two standard locations) is the fallback; when neither
    # answers, the old stamp survives.
    NEW_DDEV_VERSION="$(sed -n 's/^DDEV_VERSION=//p' "$INSTALL_CONF" 2>/dev/null | tail -1 || true)"
    _ddev_probe=""
    if [ -x "$LIBDIR/bin/ddev-as-opencode" ] && id "$OPENCODE_USER" >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
        _ddev_probe=$(sudo -n -u "$OPENCODE_USER" "$LIBDIR/bin/ddev-as-opencode" --version 2>/dev/null |
            grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed "s/^v//" || true)
    fi
    if [ -z "$_ddev_probe" ]; then
        _ddev_bin=""
        for _ddev_cand in "$(command -v ddev 2>/dev/null || true)" /usr/local/bin/ddev /usr/bin/ddev; do
            [ -n "$_ddev_cand" ] && [ -x "$_ddev_cand" ] && {
                _ddev_bin="$_ddev_cand"
                break
            }
        done
        if [ -n "$_ddev_bin" ]; then
            # pr-309 b M1 (consistency): root-run fallback probe — root never
            # walks (verified round b), the neutral cwd is uniformity only.
            _ddev_probe=$( (cd / && "$_ddev_bin" --version) 2>/dev/null |
                grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed "s/^v//" || true)
        fi
    fi
    if [ -n "$_ddev_probe" ]; then
        NEW_DDEV_VERSION="$_ddev_probe"
    fi
}

update_finalize_install_conf() {
    # --- refresh install.conf (version stamp + group key) --------------------------
    # Atomic re-stamp (review 0.0.39h F6 — the C5 twin site: install.sh's stamp
    # got temp+mv in 0.0.39g, this rewrite still deployed via truncate-in-place
    # `sudo cp`): render the new content BESIDE the target, then mv it in — a
    # mid-write crash never leaves a partial install.conf. The sibling temp is
    # registered in the scratch registry. The grep guard is narrowed (0.0.39h
    # F4): rc 1 (empty result) stays benign, rc 2 (real read error) now dies
    # BEFORE any write — the old `|| true` masked it into a rewrite keeping
    # only the 4 re-stamped keys. The rc is captured OUTSIDE the write
    # pipeline: dash has no pipefail, `|| rc=$?` on the pipeline would only
    # ever see tee's 0.
    # Keys this update owns: VERSION (re-stamped), OPENCODE_GROUP (re-based to
    # the opencode usergroup), KIT_CHANNEL (re-stamped to the ref just updated
    # from), DDEV_VERSION (re-probed above — the fallback stays fresh).
    # Per-process suffix (0.0.42f C1): the fixed name let concurrent runs
    # clobber each other's staging file (root-created by the tee below —
    # mktemp cannot create in the root-only conf dir).
    _INSTALL_CONF_TMP="$CONFDIR/install.conf.opk-new.$$"
    _tmp_track "$_INSTALL_CONF_TMP"
    _ic_rc=0
    _ic_keep=$(grep -v -e '^VERSION=' -e '^OPENCODE_GROUP=' -e '^KIT_CHANNEL=' \
        -e '^DDEV_VERSION=' "$INSTALL_CONF" 2>/dev/null) || _ic_rc=$?
    [ "$_ic_rc" -le 1 ] || die "cannot read $INSTALL_CONF (grep rc $_ic_rc) — install.conf left untouched"
    {
        if [ -n "$_ic_keep" ]; then printf '%s\n' "$_ic_keep"; fi
        echo "OPENCODE_GROUP=$NEW_OPENCODE_GROUP"
        echo "KIT_CHANNEL=$KIT_BRANCH"
        echo "VERSION=$VERSION"
        echo "DDEV_VERSION=$NEW_DDEV_VERSION"
    } | sort -u | sudo tee "$_INSTALL_CONF_TMP" >/dev/null
    sudo chmod 644 "$_INSTALL_CONF_TMP"
    sudo mv -f "$_INSTALL_CONF_TMP" "$CONFDIR/install.conf"
    ui_success "install.conf updated: VERSION=$VERSION CHANNEL=$KIT_BRANCH""\
 OPENCODE_GROUP=$NEW_OPENCODE_GROUP DDEV_VERSION=$NEW_DDEV_VERSION"
    log "install.conf updated: VERSION=$VERSION CHANNEL=$KIT_BRANCH""\
 OPENCODE_GROUP=$NEW_OPENCODE_GROUP DDEV_VERSION=$NEW_DDEV_VERSION"
}

update_finalize_tui_files() {
    # --- TUI mode display user files (internal/records/_archive/design/plan-ui-tui-opencode.md) ---------
    # Same only-if-absent-or-kit-written policy as install.sh (marker key
    # _opencode_permissions_kit): user edits survive updates. The write goes
    # through the shared staged_write helper (review 0.0.39g S1 — sourced
    # early, see the top of this script): the target dir is agent-owned, root
    # cp/chown must never follow a planted symlink; a user-managed symlink at
    # the destination is skipped, never written through.
    OC_TUI_DIR="/home/$OPENCODE_USER/.config/opencode"
    OC_TUI_CONF="$OC_TUI_DIR/tui.json"
    # Chain gate BEFORE mkdir -p (review 0.0.39h F2): a linked PARENT
    # (~/.config, ~/.config/opencode) or a linked .config/opencode leaf
    # passes `sudo mkdir -p` silently and would redirect the staged_write mv
    # into the link target. Skip loudly (user-managed).
    if ! agent_home_sane "$OPENCODE_USER" "$OC_TUI_DIR"; then
        ui_detail "the chain to $OC_TUI_CONF contains a symlink — TUI mode display NOT refreshed (user-managed)"
        log "tui mode display skipped: symlink in the chain to $OC_TUI_CONF"
    else
        sudo mkdir -p "$OC_TUI_DIR"
        if [ -L "$OC_TUI_CONF" ]; then
            log "tui mode display skipped: $OC_TUI_CONF is a symlink (user-managed)"
        elif [ ! -f "$OC_TUI_CONF" ] || grep -q '"_opencode_permissions_kit"' "$OC_TUI_CONF" 2>/dev/null; then
            staged_write 664 "$OPENCODE_USER:$NEW_OPENCODE_GROUP" "$LIBDIR/tui/tui.json" "$OC_TUI_CONF"
            log "tui mode display refreshed: $OC_TUI_CONF"
        fi
    fi
    DEFAULT_TUI_CONF="$DEFAULT_HOME/.config/opencode/tui.json"
    DEFAULT_THEME_DIR="$DEFAULT_HOME/.config/opencode/themes"
    if [ ! -f "$DEFAULT_TUI_CONF" ] || grep -q '"_opencode_permissions_kit"' "$DEFAULT_TUI_CONF" 2>/dev/null; then
        sudo mkdir -p "$DEFAULT_THEME_DIR"
        sudo cp "$LIBDIR/tui/opencode-danger.theme.json" "$DEFAULT_THEME_DIR/opencode-danger.json"
        sudo cp "$LIBDIR/tui/tui-danger.json" "$DEFAULT_TUI_CONF"
        sudo chown -R "$DEFAULT_USER:$NEW_OPENCODE_GROUP" "$DEFAULT_THEME_DIR"
        sudo chown "$DEFAULT_USER:$NEW_OPENCODE_GROUP" "$DEFAULT_TUI_CONF"
        sudo chmod 664 "$DEFAULT_TUI_CONF" "$DEFAULT_THEME_DIR/opencode-danger.json"
        log "tui danger theme refreshed: $DEFAULT_TUI_CONF"
    fi

    # opencode 2.x (issue #80, #99): keep the TUI mode registration anchored
    # to the installed major — register the kit-mode-2x.tsx plugin dir on 2.x,
    # remove it on 1.x (the 1.x tui.json/danger theme are major-agnostic and
    # stay). The major comes from the install.conf stamp, freshly re-stamped
    # by any binary upgrade above.
    _oc_major=$(sed -n 's/^OPENCODE_MAJOR=//p' "$CONFDIR/install.conf" 2>/dev/null | tail -1 || true)
    [ -n "$_oc_major" ] || _oc_major=1
    sync_tui_registration "$_oc_major"
}
