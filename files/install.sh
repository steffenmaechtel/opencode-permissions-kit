#!/bin/sh
# opencode permissions kit -- install.sh
# First-time installer for WSL2 + DDEV environments. Asks interactively.
#
# One-liner (fetches this script + all kit files from GitHub at $KIT_BRANCH):
#   curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/stable/files/install.sh \
#       | sudo env KIT_BRANCH=stable bash
#
# From a checkout (same behaviour, uses the local files):
#   sudo bash files/install.sh
#
# To re-deploy the kit without prompts after it is already installed,
# use update.sh instead. To change settings later, use config.sh.
#
# Soft protection model (internal/records/ddev-working.md): no hard ACL denies.
# The kit creates the opencode user, provisions a MANDATORY rootless container
# backend (docker-rootless or podman-rootless), prepares ddev to run as that
# user, and sets up the opencode usergroup as the sharing group.
#
# Options:
#   --yes        Skip all prompts, assume Yes
#   --projects <path...>  Pre-define project roots, skip interactive selection
#   --container-backend <docker-rootless|podman-rootless>  Non-interactive backend choice
#   --secure-git-config   Enable .git/config hardening up front
#   --skip-ddev-migration  Do not export the dev user's ddev databases
#   --ddev-settings <dev-owned|ddev>  Dev-owned mode: kit writes
#                          disable_settings_management: true into each
#                          project's .ddev/config.yaml (default: dev-owned)
#   --force-unsupported-distro  Skip the Ubuntu version whitelist
#                          (22.04/24.04; Debian and other distros are never
#                          version-gated — see the support matrix in
#                          docs/getting-started.md) — at your own risk
#   --openchamber-policy <yes|no>  Pin OpenChamber's opencode spawn to the
#                          kit wrapper via /etc/openchamber/policy.json
#                          (disables OpenChamber's self-update buttons).
#                          Default: asked when OpenChamber is detected,
#                          off under --yes without the flag; later:
#                          sudo opk openchamber-secure
#
# Flags may appear in any order. --projects consumes every following
# non-flag argument as a project root; parsing continues after them.
# Unknown options abort the install (fail fast, no silently ignored typos).
# -u: a typo'd variable expands empty in ROOT context — refuse to run on
# unset references (review 0.0.39a C2). pipefail only where the shell has
# it: bash runs the kit (curl | sudo bash), dash would abort on the option.
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail || true

# Scratch-file cleanup (review 0.0.39a C1): every temp artifact this script
# creates is removed on ANY exit path — failure, Ctrl-C, TERM, and success.
# The backup directory is deliberately NOT touched: it holds pre-install
# copies (sudoers, configs) that are recovery material after a failed run,
# and the user is told where it is. The fetch tree and every tracked
# scratch file are pure scratch and must not leak as root-owned 0700
# leftovers.
_FETCH_TREE=""
# Result dir of a streamed fetch_kit run (set by fetch_kit, read by the
# caller — see the STREAMED block below).
_FK_DIR=""
# Registry for short-lived scratch files created inside functions
# (fetch temps, wsl-browser-bridge rewrites) — the trap empties it on
# every exit path (review 0.0.39e C3).
_TMP_REGISTRY=""
_tmp_track() { _TMP_REGISTRY="$_TMP_REGISTRY $1"; }
cleanup() {
    if [ -n "${_FETCH_TREE:-}" ]; then rm -rf "$_FETCH_TREE"; fi
    # word splitting intended: registry entries are mktemp paths
    # shellcheck disable=SC2086
    if [ -n "${_TMP_REGISTRY:-}" ]; then rm -f $_TMP_REGISTRY; fi
}
# A signal handler must EXIT: without it the interrupted script resumes
# running after cleanup — with its scratch files already deleted
# (fix-wave review). The EXIT trap re-runs cleanup; the rms are
# idempotent.
trap cleanup EXIT
trap 'cleanup; exit 1' INT TERM

# Ref the kit ships from. 'stable' = the release mirror (byte-identical to
# master at release points, docs one-liners use it); 'master' = development
# channel (the in-code default — the copy streamed from a ref must default
# to that ref's own channel so master and stable copies stay identical).
# The actually-used value is stamped as KIT_CHANNEL into install.conf, so
# `opk update` keeps tracking it. Overridable for testing:
#   KIT_BRANCH=my-branch  KIT_BASE_URL=https://example.invalid/<branch>
KIT_BRANCH="${KIT_BRANCH:-master}"
# The ref is stamped as KIT_CHANNEL into install.conf, which privileged
# scripts source wholesale — refuse anything outside a git-ref charset
# instead of persisting shell metacharacters as root (review 0.0.39b S1).
case "$KIT_BRANCH" in
    *[!A-Za-z0-9._/-]* | *..*)
        echo "error: KIT_BRANCH '$KIT_BRANCH' is invalid — a ref is letters, digits, ""\
'.', '_', '/', '-' (no '..'; git refnames cannot carry it)" >&2
        exit 1
        ;;
esac
KIT_BASE_URL="${KIT_BASE_URL:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH}"

# Downloads every kit file from KIT_BASE_URL into a temp checkout layout
# (files/ + VERSION) and prints the files/ directory. Used when this script
# is streamed via `curl | sudo bash` and has no local siblings.
fetch_kit() {
    local base dir f
    # Guarded (#364 sweep sibling): both hosts call this as
    # `fetch_kit || {...}` — set -e is suppressed in this callee, and an
    # empty base from a dead TMPDIR collapsed every path below onto
    # root-level literals (the pre-create ran mkdir -p /files/... as
    # root, the #360 a F5 class) before the fetch errors blamed curl.
    base="$(mktemp -d)" || {
        echo "error: mktemp failed (is \$TMPDIR writable?) — cannot stage the kit fetch" >&2
        return 1
    }
    # Registered for the EXIT/INT/TERM cleanup: a failed fetch (or an
    # aborted install later on) must not leave the partial tree behind.
    _FETCH_TREE="$base"
    dir="$base/files"
    # Pre-create every subdirectory referenced by the file list (bin/, sh/,
    # py/, tui/): curl -o cannot write into a missing directory and aborts
    # the fetch with error 23 ("Failure writing output to destination").
    mkdir -p "$dir/opencode-permissions-kit-lib/bin" "$dir/opencode-permissions-kit-lib/sh" \
        "$dir/opencode-permissions-kit-lib/py" "$dir/opencode-permissions-kit-lib/tui" \
        "$dir/opencode-permissions-kit-lib/management" "$dir/opencode-permissions-kit-lib/templates" \
        "$dir/etc"
    # Fetch list — FORMAT RULE: one file per line, backslash-continued.
    # Packed multi-name lines make every diff unreadable (test-kit-files
    # compares word-wise and does not care about layout; this format is
    # convention). Keep it when adding files.
    for f in install.sh \
        VERSION \
        opencode-permissions-kit-lib/sh/path-sane.sh \
        opencode-permissions-kit-lib/sh/install-core.sh \
        opencode-permissions-kit-lib/sh/uninstall-core.sh \
        opencode-permissions-kit-lib/management/config.sh \
        opencode-permissions-kit-lib/management/doctor.sh \
        opencode-permissions-kit-lib/management/update.sh \
        opencode-permissions-kit-lib/management/status.sh \
        opencode-permissions-kit-lib/management/uninstall.sh \
        opencode-permissions-kit-lib/templates/opencode.jsonc \
        opencode-permissions-kit-lib/templates/opencode-deny-all.jsonc \
        opencode-permissions-kit-lib/templates/sudoers.template \
        etc/umask.sh \
        opencode-permissions-kit-lib/bin/opencode-as-opencode \
        opencode-permissions-kit-lib/bin/opk \
        opencode-permissions-kit-lib/py/jsonc-parser.py \
        opencode-permissions-kit-lib/py/tui-register.py \
        opencode-permissions-kit-lib/sh/log.sh \
        opencode-permissions-kit-lib/sh/render-agent-config.sh \
        opencode-permissions-kit-lib/sh/tui-plugin.sh \
        opencode-permissions-kit-lib/sh/ui.sh \
        opencode-permissions-kit-lib/sh/update-check.sh \
        opencode-permissions-kit-lib/sh/update-core.sh \
        opencode-permissions-kit-lib/sh/advisories.sh \
        opencode-permissions-kit-lib/sh/shell-warn.sh \
        opencode-permissions-kit-lib/bin/setup-container-backend \
        opencode-permissions-kit-lib/bin/socket-check \
        opencode-permissions-kit-lib/bin/cwd-check \
        opencode-permissions-kit-lib/sh/ddev-terminal.sh \
        opencode-permissions-kit-lib/bin/ddev-as-opencode \
        opencode-permissions-kit-lib/sh/ddev-handover.sh \
        opencode-permissions-kit-lib/sh/ddev-migrate.sh \
        opencode-permissions-kit-lib/bin/ddev-migrate \
        opencode-permissions-kit-lib/sh/ddev-hosts.sh \
        opencode-permissions-kit-lib/sh/fs-baseline.sh \
        opencode-permissions-kit-lib/sh/git-check.sh \
        opencode-permissions-kit-lib/sh/status-core.sh \
        opencode-permissions-kit-lib/sh/staged-write.sh \
        opencode-permissions-kit-lib/sh/sudoers-deploy.sh \
        opencode-permissions-kit-lib/sh/secure-binary.sh \
        opencode-permissions-kit-lib/sh/deploy-lib.sh \
        opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh \
        opencode-permissions-kit-lib/bin/browser-bridge \
        opencode-permissions-kit-lib/bin/xdg-open \
        opencode-permissions-kit-lib/tui/kit-mode.tsx \
        opencode-permissions-kit-lib/tui/kit-mode-2x.tsx \
        opencode-permissions-kit-lib/tui/opencode-danger.theme.json \
        opencode-permissions-kit-lib/tui/tui.json \
        opencode-permissions-kit-lib/tui/tui-danger.json; do
        echo "  fetching $f ..." >&2
        # Fetch to a temp file and refuse anything unsound (0.0.39e C1):
        # an empty-but-200 body (captive portal, broken mirror) previously
        # landed in the deploy tree as root — same guard ensure_local_file
        # already carries; an empty sourced lib degrades to a silent no-op
        # stub via the fallback blocks.
        if [ "$f" = "VERSION" ]; then
            _fk_dst="$base/VERSION"
            _fk_url="$KIT_BASE_URL/VERSION"
        else
            _fk_dst="$dir/$f"
            _fk_url="$KIT_BASE_URL/files/$f"
        fi
        # Same class as the base guard above (#364 sweep sibling): a
        # dead per-file mktemp surfaced as a curl "could not fetch" —
        # name the cause instead.
        _fk_tmp=$(mktemp) || {
            echo "error: mktemp failed (is \$TMPDIR writable?) — aborting" >&2
            return 1
        }
        _tmp_track "$_fk_tmp"
        if ! curl -fsSL "$_fk_url" -o "$_fk_tmp" || [ ! -s "$_fk_tmp" ]; then
            rm -f "$_fk_tmp"
            echo "error: could not fetch $f from $_fk_url (failed or empty) — aborting" >&2
            return 1
        fi
        chmod 644 "$_fk_tmp"
        mv "$_fk_tmp" "$_fk_dst"
    done
    # Global, NOT stdout: the caller must not run this function inside a
    # command substitution — a subshell's variable writes (incl. the
    # _FETCH_TREE registration for the cleanup trap) never reach the
    # parent, silently voiding the trap (wave-f review).
    _FK_DIR="$dir"
}

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
STREAMED=false
if [ ! -f "$SCRIPT_DIR/../VERSION" ]; then
    echo "Not a local checkout — fetching kit files from $KIT_BASE_URL ..."
    # Direct call, NOT SCRIPT_DIR="$(fetch_kit)": command substitution runs
    # in a subshell, where _FETCH_TREE/_TMP_REGISTRY registrations would be
    # lost and the cleanup trap silently void (wave-f review).
    fetch_kit || {
        echo "error: Failed to fetch kit files from $KIT_BASE_URL" >&2
        exit 1
    }
    SCRIPT_DIR="$_FK_DIR"
    STREAMED=true
fi
# A streamed install's stdin IS the script body (curl | sudo bash): the
# prompt helpers must never fall back to reading it — they would consume
# script bytes as the answer (review 0.0.39b C6). See _ui_read in ui.sh.
if [ "$STREAMED" = true ]; then UI_NO_STDIN_FALLBACK=1; fi
VERSION=$(cat "$SCRIPT_DIR/../VERSION" 2>/dev/null || echo "0.0.0")
# Install target (deployed in Step 7). Defined early: steps before Step 7
# (e.g. the container-backend fallback path) already need it.
LIBDIR="/usr/local/lib/opencode-permissions-kit"

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). No-op if
# the helper is missing — logging must never break the install.
log() { :; }
if [ -f "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/log.sh" ]; then
    . "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/log.sh"
fi

# Source a shipped library or die loudly: under set -e a missing file in
# the old `[ -f x ] && . x` pattern aborted the WHOLE install silently
# (the failed test's exit status trips errexit) — a diagnostic beats a
# mysterious early exit (review 0.0.39b C2).
kit_source() {
    if [ -f "$1" ]; then
        . "$1"
    else
        echo "error: missing kit library: $1 (incomplete checkout or broken fetch)" >&2
        exit 1
    fi
}

# Shared ddev handover helpers (.ddev + settings dirs -> opencode user).
# install.sh always runs from a checkout or a fully fetched temp dir, so the
# helper sits right next to log.sh.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/ddev-handover.sh"
command -v ddev_handover_root >/dev/null 2>&1 || ddev_handover_root() { :; }
command -v ddev_handover_stamp_write >/dev/null 2>&1 || ddev_handover_stamp_write() { :; }

# Shared ddev database-migration helpers (dev-user registry -> SQL dumps,
# issue #15). Same sourcing rules as ddev-handover.sh.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/ddev-migrate.sh"
command -v ddev_migrate_registry >/dev/null 2>&1 || {
    ddev_migrate_registry() { :; }
    ddev_migrate_projects() { :; }
    ddev_migrate_done() { return 1; }
}

# Shared group-baseline helper with live progress (issue #14). Same
# sourcing rules as ddev-handover.sh.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/fs-baseline.sh"
command -v fs_baseline_root >/dev/null 2>&1 || fs_baseline_root() { :; }

# Shared project-root policy gate (issue #216): bounds the group
# baseline above — one implementation with config.sh (the old verbatim
# duplicate; see sh/path-sane.sh for the deploy-order evaluation).
# kit_source aborts when the lib is missing outright; the stub covers a
# present-but-incomplete copy and fails CLOSED — every caller of this
# gate treats rc 1 as "refuse", so a damaged library must never widen
# into "allow".
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/path-sane.sh"
command -v project_path_sane >/dev/null 2>&1 ||
    project_path_sane() {
        echo "error: project_path_sane unavailable (path-sane.sh missing) — refusing every project path" >&2
        return 1
    }

# Shared git presence/version check (soft floor, issue #118): one
# implementation for the pre-flight here, update.sh and status.sh.
# kit_source above already aborts when the file is missing outright —
# the stub covers a present-but-incomplete copy: the check is advisory
# by design, a broken helper must not abort the install (see
# git-check.sh's header).
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/git-check.sh"
command -v git_check_report >/dev/null 2>&1 || git_check_report() { :; }

# Shared symlink-safe privileged write helper (review 0.0.39g S1): every
# root write into the agent-owned home goes through staged_write — stage
# in CONFDIR, chown/chmod there, mv onto the destination (rename replaces
# a planted link instead of following it). Same sourcing rules as above.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/staged-write.sh"
command -v staged_write >/dev/null 2>&1 ||
    staged_write() {
        echo "error: staged_write unavailable (staged-write.sh missing)" >&2
        return 1
    }

# Shared sudoers pipeline (charset gate, render, visudo validation,
# install, sudoers.d link, legacy cleanup): one implementation for
# install.sh, config.sh and update.sh.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/sudoers-deploy.sh"
command -v sudoers_deploy >/dev/null 2>&1 ||
    sudoers_deploy() {
        echo "error: sudoers_deploy unavailable (sudoers-deploy.sh missing)" >&2
        return 1
    }

# Shared binary hardening + atomic deploys (chown root:<group>
# best-effort + the load-bearing chmod 750, fail-loud; the temp+mv
# binary replacement, issue #163): one implementation for
# install.sh and update.sh.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/secure-binary.sh"
command -v secure_binary >/dev/null 2>&1 ||
    secure_binary() {
        echo "error: secure_binary unavailable (secure-binary.sh missing)" >&2
        return 1
    }
command -v copy_binary_atomic >/dev/null 2>&1 ||
    copy_binary_atomic() {
        echo "error: copy_binary_atomic unavailable (secure-binary.sh missing)" >&2
        return 1
    }
command -v copy_file_atomic >/dev/null 2>&1 ||
    copy_file_atomic() {
        echo "error: copy_file_atomic unavailable (secure-binary.sh missing)" >&2
        return 1
    }

# Shared library deployment manifest: what ships into
# /usr/local/lib/opencode-permissions-kit, from ONE list (install.sh
# and update.sh deploy through it).
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/deploy-lib.sh"
command -v lib_deploy >/dev/null 2>&1 ||
    lib_deploy() {
        echo "error: lib_deploy unavailable (deploy-lib.sh missing)" >&2
        return 1
    }

# Shared agent-config template render (the SECURE_GIT sed pair): one
# implementation for install.sh and config.sh's git-config toggle.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/render-agent-config.sh"
command -v agent_config_render >/dev/null 2>&1 ||
    agent_config_render() {
        echo "error: agent_config_render unavailable (render-agent-config.sh missing)" >&2
        return 1
    }

# Shared TUI 2.x plugin registration (per-user plugin-dir sync): one
# implementation for install.sh Step 8c and update.sh's
# sync_tui_registration.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/tui-plugin.sh"
command -v tui_plugin_sync_user >/dev/null 2>&1 ||
    tui_plugin_sync_user() {
        echo "error: tui_plugin_sync_user unavailable (tui-plugin.sh missing)" >&2
        return 1
    }

# Shared WSL browser bridge helper (issues #91, #100): deploys the
# powershell.exe stand-in + /etc/wsl.conf comment block that keep opencode's
# device logins alive on a hardened /mnt/c. Same sourcing rules as
# ddev-handover.sh.
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/wsl-browser-bridge.sh"
command -v browser_bridge_is_wsl >/dev/null 2>&1 || browser_bridge_is_wsl() { return 1; }
command -v browser_bridge_install >/dev/null 2>&1 || browser_bridge_install() { :; }

# === Shared UI helpers ===
# The kit files sit next to this script (checkout or fully fetched temp dir).
# The fallback covers the OUTPUT helpers only — the interactive prompts
# (ui_ask/ui_confirm/ui_menu) come solely from ui.sh, so a ui.sh-less run
# proceeds only up to its first prompt and dies there (set -e). A --yes
# run never prompts: it needs every OUTPUT helper below for its whole
# run — ui_have/ui_atten/ui_add/ui_miss included (0.0.45c C5: the old
# fallback lacked them and a ui.sh-less --yes died at the inventory's
# first ui_have, "command not found", before any prompt).
UI_LIB="$SCRIPT_DIR/opencode-permissions-kit-lib/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    . "$UI_LIB"
else
    ui_info() { echo "  info     $1"; }
    ui_success() { echo "  success  $1"; }
    ui_warn() { echo "  warn     $1"; }
    ui_error() { echo "  error    $1" >&2; }
    ui_detail() { echo "     $1"; }
    ui_section() {
        echo ""
        echo "  --- $1 ---"
        echo ""
    }
    ui_banner() {
        echo ""
        echo "  opencode permissions kit  v${1:-}"
        echo ""
    }
    ui_kv() { printf '  %-14s %s\n' "$1" "$2"; }
    ui_kv_warn() { printf '  %-14s %s\n' "$1" "$2"; }
    ui_plan() { printf '    %s  %s\n' "$1" "$2"; }
    ui_have() { echo "  ok        $1  ${2:-}"; }
    ui_atten() { echo "  warn      $1  ${2:-}"; }
    ui_add() { echo "  add       $1  ${2:-}"; }
    ui_miss() { echo "  miss      $1  ${2:-}"; }
    UI_GREEN=''
    UI_RED=''
    UI_YELLOW=''
    UI_CYAN=''
    UI_BLUE=''
    UI_NC=''
fi

OPENCODE_USER="opencode"
# The sharing group is the opencode user's own primary usergroup (created by
# useradd -m). Resolved after the user exists; "opencode" is only the default.
OPENCODE_GROUP="opencode"

SKIP_PROMPTS=false
PREDEFINED_PROJECTS=""
# Default true = .git/config deny rules active = git blocked for the agent
# (the recommended, pre-Phase-4 --yes behavior). The questions below and
# the --secure-git-config flag set it explicitly.
SECURE_GIT_CONFIG=true
CONTAINER_BACKEND_OPT=""
# ddev database export (issue #15): default on — the dumps are the only
# portable copy once ddev switches to the opencode user's daemon.
SKIP_DDEV_MIGRATION=false
# ~/.agents migration (issue #19): empty = decide via prompt (--yes takes
# the recommended "move"); --migrate-agents forces move|copy|skip.
MIGRATE_AGENTS_OPT=""
# Dev-owned mode (internal/records/ddev-dev-owned-projects.md): true = the kit
# writes disable_settings_management: true into each project's committed
# .ddev/config.yaml; settings dirs + project root stay developer-owned
# (recommended default). false = ddev keeps managing settings (handover
# model). --ddev-settings forces dev-owned|ddev.
DDEV_DEV_OWNED=true
DDEV_SETTINGS_GIVEN=false
GIT_FLAG_GIVEN=false
# Distro whitelist override (see _distro_gate): explicit user opt-in to
# install on a distro outside the support matrix.
FORCE_UNSUPPORTED_DISTRO=false
# OpenChamber policy pin (issue #154, internal/records/openchamber-2x-hardening.md):
# opt-in — write /etc/openchamber/policy.json pinning OpenChamber's opencode
# spawn to the kit wrapper. It changes third-party app behavior (OpenChamber's
# self-update affordances stop working), hence never silently on. "" = decide
# via detection + prompt below (an earlier opt-in stays); --openchamber-policy
# forces yes|no.
OPENCHAMBER_POLICY=""
OPENCHAMBER_POLICY_OPT=""
OPENCHAMBER_POLICY_GIVEN=false

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            # -y alias (#211 b W2): update/config/uninstall accept it;
            # cli.md documents it for install too — the family stays
            # uniform.
            --yes | -y) SKIP_PROMPTS=true ;;
            --secure-git-config)
                SECURE_GIT_CONFIG=true
                GIT_FLAG_GIVEN=true
                ;;
            --skip-ddev-migration) SKIP_DDEV_MIGRATION=true ;;
            --force-unsupported-distro) FORCE_UNSUPPORTED_DISTRO=true ;;
            --openchamber-policy)
                if [ $# -lt 2 ]; then
                    echo "error: --openchamber-policy requires a value (yes|no)" >&2
                    exit 1
                fi
                case "$2" in
                    yes | no)
                        OPENCHAMBER_POLICY_OPT="$2"
                        OPENCHAMBER_POLICY_GIVEN=true
                        ;;
                    *)
                        echo "error: --openchamber-policy must be yes or no (got: $2)" >&2
                        exit 1
                        ;;
                esac
                shift
                ;;
            --migrate-agents)
                if [ $# -lt 2 ]; then
                    echo "error: --migrate-agents requires a value (move|copy|skip)" >&2
                    exit 1
                fi
                case "$2" in
                    move | copy | skip) MIGRATE_AGENTS_OPT="$2" ;;
                    *)
                        echo "error: --migrate-agents must be move, copy or skip (got: $2)" >&2
                        exit 1
                        ;;
                esac
                shift
                ;;
            --container-backend)
                if [ $# -lt 2 ]; then
                    echo "error: --container-backend requires a value (docker-rootless|podman-rootless)" >&2
                    exit 1
                fi
                CONTAINER_BACKEND_OPT="$2"
                shift
                ;;
            --ddev-settings)
                if [ $# -lt 2 ]; then
                    echo "error: --ddev-settings requires a value (dev-owned|ddev)" >&2
                    exit 1
                fi
                case "$2" in
                    dev-owned) DDEV_DEV_OWNED=true ;;
                    ddev) DDEV_DEV_OWNED=false ;;
                    *)
                        echo "error: --ddev-settings must be dev-owned or ddev (got: $2)" >&2
                        exit 1
                        ;;
                esac
                DDEV_SETTINGS_GIVEN=true
                shift
                ;;
            --projects)
                shift
                while [ $# -gt 0 ] && [ "${1#-}" = "$1" ]; do
                    # Glob metacharacters are rejected on the RAW
                    # argument (0.0.42f S2): any later unquoted
                    # iteration would pathname-expand a matching glob
                    # into a different root set than the user typed —
                    # an in-loop gate runs after that expansion and
                    # never sees the characters.
                    case "$1" in
                        *[\*\?\[]*)
                            echo "error: --projects value contains glob characters: $1" >&2
                            exit 1
                            ;;
                    esac
                    PREDEFINED_PROJECTS="$PREDEFINED_PROJECTS $1"
                    shift
                done
                continue
                ;;
            *)
                echo "error: unknown option: $1 (see the script header for usage)" >&2
                exit 1
                ;;
        esac
        shift
    done
}
parse_args "$@"

# === Helpers ===

# confirm "Question?" — conventions.md prompt shape ([y/N], Enter = no;
# y/yes case-insensitive). Exit status 0 = yes. --yes/SKIP_PROMPTS
# answers yes (same as the old prompt() helper).
confirm() {
    if [ "$SKIP_PROMPTS" = true ]; then
        return 0
    fi
    ui_confirm "$1" n
}

# _yes_no_backup_menu "Question?" — a choice beyond yes/no becomes a keyed
# menu (conventions.md); prints y, n or b (backup first, then yes).
# Enter/EOF = No; --yes/SKIP_PROMPTS = yes.
_yes_no_backup_menu() {
    if [ "$SKIP_PROMPTS" = true ]; then
        echo y
        return
    fi
    ui_menu "$1" "n" "y|Yes" "n|No" "b|Backup first, then yes"
}

# === Distro whitelist gate ======================================================
# The kit supports Ubuntu 22.04, Ubuntu 24.04 and Debian 12+ (untested) —
# see the support matrix in docs/getting-started.md. Every OTHER Ubuntu
# version aborts BEFORE the first prompt: Ubuntu 26.04 ships sudo-rs 0.2.13
# (interactive streamed installs freeze permanently, sudo-rs#1598) and
# systemd 259 (per-boot user-manager EBUSY lottery, systemd#41278) — both
# tracked in issue #145. --force-unsupported-distro overrides at the
# user's explicit risk. Non-Ubuntu distros pass unchanged (the two known
# blockers are Ubuntu-specific); an os-release without an ID passes too
# (exotic system, previous behavior).
_distro_gate() {
    case "$1" in
        ubuntu)
            case "$2" in
                22.04 | 24.04) return 0 ;;
            esac
            ;;
        *)
            return 0
            ;;
    esac
    _dg_v="$2"
    [ -n "$_dg_v" ] || _dg_v="(unknown version)"
    if [ "${FORCE_UNSUPPORTED_DISTRO:-false}" = true ]; then
        ui_warn "unsupported distro: Ubuntu $_dg_v — continuing (--force-unsupported-distro,""\
 at your own risk)"
        ui_detail "known blockers: sudo-rs freezes streamed installs, systemd fails user"
        ui_detail "managers per boot — issue #145; there is no support for this combination"
        log "distro gate OVERRIDDEN (--force-unsupported-distro): Ubuntu $_dg_v"
        return 0
    fi
    ui_error "Ubuntu $_dg_v is not supported by the kit."
    ui_error "Supported: Ubuntu 22.04, Ubuntu 24.04 — Debian 12+ works (untested)."
    ui_error "Ubuntu 26.04 has known errors:"
    ui_error "  https://github.com/steffenmaechtel/opencode-permissions-kit/issues/145"
    ui_info "to install anyway at your own risk, re-run with --force-unsupported-distro"
    log "distro gate: refused install on Ubuntu $_dg_v"
    exit 1
}

# _py3_health_probe: loud abort when python3 is missing or broken.
# Presence alone (`command -v`) accepts a findable-but-broken
# interpreter — a pyenv shim to a removed version installs green and
# every later consumer fails attributelessly (update's version
# resolution degrades to "could not resolve", opk ddev URL opening
# silently downgrades; #244 a W1). The health arm RUNS the interpreter
# isolated (`-I`): PYTHONHOME/PYTHONPATH poison cannot reach it
# (#244 a S1) — the -I scope is those env vars, not the whole
# environment: the loader route (LD_PRELOAD/LD_LIBRARY_PATH) and the
# PATH-resolved binary itself stay outside any python flag (#244 b
# S1), and system site-packages stay processed (-I implies -E -s -P,
# not -S): a .pth there executes at startup — root-owned trust, the
# residual the b-S1 finding named (#244 c S2). Running it is the installer's first EXECUTION of python3 as
# root (#244 b S3) — the same binary and trust as every root python3
# the installed kit runs, one moment earlier. The import list is the
# union of the kit's shipped python import surface (enumerated at the
# assignment below; a drift pin asserts every shipped python import
# appears there, #244 b Q1). Two distinct errors name the failure
# classes, and a failed probe first surfaces the interpreter's own
# stderr — a python3 that only works via PYTHONHOME/PYTHONPATH names
# its real problem there (#244 b S2). Functional matrix + verbatim
# wiring pin: tests/unit/test-install-args.sh.
_py3_health_probe() {
    # The union of the kit's shipped python import surface (#244 b Q1):
    # jsonc parser fnmatch/json/re/sys — fs-baseline probe+tee os/sys
    # — ddev describe, update resolve and status feed json/sys — the
    # status progress tee sys/threading/time — the opk settings edit
    # json/sys/pathlib — tui-register importlib.util/json/os/stat/sys/
    # tempfile. Drift-pinned: every shipped python import must appear
    # here (tests/unit/test-install-args.sh).
    _py3_imports='import fnmatch, importlib.util, json, os, pathlib, re, stat, sys, tempfile, threading, time'
    if ! command -v python3 >/dev/null 2>&1; then
        ui_error "python3 is required but not installed (apt install python3)."
        exit 1
    fi
    if ! python3 -I -c "$_py3_imports" >/dev/null 2>&1; then
        # The rerun exists for the interpreter's own diagnostic stderr,
        # not for its rc (this branch already failed) — the rc guard is
        # deliberate; the noisy-shim matrix case pins the passthrough
        # (#244 b S2).
        python3 -I -c "$_py3_imports" >/dev/null || true
        ui_error "python3 is present but broken (shim? corrupt install? needs PYTHONHOME/PYTHONPATH?) — fix it and re-run."
        exit 1
    fi
}

banner() {
    ui_banner "$VERSION" "installs opencode as its own user behind rootless containers"
}

# Root-shell guard (issue #192): a root login (wsl -u root, su -, a root
# ssh session) has no SUDO_USER, so whoami wins and the developer would
# resolve to root. Every developer-side provision then targets root (rc
# hooks into /root, sharing-group membership for root, sudoers with root
# as the developer) while the real developer gets nothing — a defect
# status.sh/update.sh can only report, never repair. Abort before the
# first prompt, fail-closed like the charset gate that calls this.
# Trust model (#196 a S1): `sudo env SUDO_USER=... bash install.sh`
# overrides the variable after sudo sets it — that operator already has
# root and deceives only themselves; deliberately not defended.
_root_user_gate() {
    _rug_name="$1"
    _rug_uid="$(id -u "$_rug_name" 2>/dev/null || true)"
    if [ "$_rug_name" != "root" ] && [ "$_rug_uid" != "0" ]; then
        return 0
    fi
    ui_error "The installer must run from your normal user account with sudo,"
    ui_error "not from a root shell (DEFAULT_USER resolved to '$_rug_name')."
    ui_error "Open a shell as your regular user and re-run the install command:"
    ui_error "  curl ... | sudo env KIT_BRANCH=stable bash"
    ui_detail "background: https://github.com/steffenmaechtel/opencode-permissions-kit/issues/192"
    log "root-user gate: refused install (DEFAULT_USER=$_rug_name uid=${_rug_uid:-unknown})"
    exit 1
}

# --- phase logic: sh/install-core.sh (issue #346, wave 3) -----------------------
# The three phase functions live in the sourced lib, resolved from the
# SAME tree this script runs out of: $SCRIPT_DIR is the checkout, or the
# streamed fetch tree (re-pointed at $_FK_DIR above, before the first
# kit_source) — the fetched lib tree is complete or the fetch died loud.
# Unlike update.sh's UPDATE_CORE there is deliberately NO deployed
# $LIBDIR fallback: install.sh never runs from the installed tree
# (re-deploys go through update.sh), and a stale deployed lib must never
# feed phases to a newer streamed script — a missing lib here is an
# incomplete checkout or broken fetch, and kit_source dies loud (the
# #165 class: no silent phase drops).
kit_source "$SCRIPT_DIR/opencode-permissions-kit-lib/sh/install-core.sh"

# === Main ===
# The install as a linear phase list; everything above is bootstrap,
# helpers and the phase-lib resolver (the definitions live in
# sh/install-core.sh). The calls are plain statements on purpose: under
# failing phase aborts the install exactly like the former top-level code
# (no `|| true`, no condition context — that would silence set -e for the
# whole phase body).
do_plan_phase
do_ddev_phase
do_deploy_phase

# === Done ===

ui_section "Installation complete"
ui_kv "Kit" "v$VERSION"
ui_kv "Channel" "$KIT_BRANCH (updates track it: opk update)"
ui_kv "Backend" "$CONTAINER_BACKEND (owned by 'opencode')"
[ -n "$PROJECTS_ROOTS" ] && ui_kv "Projects" "$PROJECTS_ROOTS"
if [ -n "$DD_MIG_DUMP_DIR" ]; then
    ui_kv_warn "Ddev dumps" \
        "$DD_MIG_DUMP_DIR — import: sudo /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate import"
fi
if [ "$SECURE_GIT_CONFIG" = true ]; then
    ui_kv "Git" "blocked for the agent (.git/config deny active)"
else
    ui_kv "Git" "allowed"
fi
if [ "$OPENCHAMBER_POLICY" = yes ]; then
    ui_kv "OpenChamber" "policy pin active (sessions secured, self-update off)"
fi
if [ -z "${_BK_FAIL:-}" ]; then
    ui_kv "Backup" "$BACKUP_DIR"
else
    ui_kv "Backup" "$BACKUP_DIR (INCOMPLETE: $_BK_FAIL)"
fi
echo ""
# WSL2 final exposure warning: a manually-applied wsl.conf restriction only
# takes effect after 'wsl --shutdown' — until then /mnt/c stays
# world-readable and the wrapper warns on every opencode start.
if [ -d /mnt/c ]; then
    mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -n "$mnt_mode" ] && [ $((0$mnt_mode & 0004)) -ne 0 ]; then
        ui_warn "/mnt/c is still world-readable (mode $mnt_mode) — the agent can read your Windows profile."
        ui_warn "If you just applied the [automount] snippet to /etc/wsl.conf, it needs 'wsl --shutdown' from Windows"
        ui_warn "+ reopening the distro to take effect — opencode will warn on every start until then."
        echo ""
    fi
fi
# A shell that already ran 'opencode' has the old user-local binary hashed
# (and ~/.opencode/bin still first in its $PATH — the rc cleanup above only
# affects NEW shells). A child process cannot fix the parent shell, so tell
# the user to restart the terminal.
if [ -x "$DEV_HOME/.opencode/bin/opencode" ]; then
    ui_warn "IMPORTANT: open a NEW terminal before running 'opencode'."
    echo "  Your current shell still resolves the old, unwrapped binary from"
    echo "  ~/.opencode/bin (bash caches the path, and it is still first in \$PATH"
    echo "  of this shell). Until you restart, 'opencode' would bypass the wrapper"
    echo "  and the 'opencode' user."
    echo ""
fi
# Session hint (issue #73): everything below only reaches sessions started
# AFTER this install — the sharing-group membership (usermod -aG above)
# takes effect on the next login and without it the current session has no
# file access via the group, the ddev() hook is not sourced yet (ddev in
# an old terminal would run as the developer, unable to see the rootless
# daemon), and the PATH/umask profile additions are not applied.
ui_warn "Restart your terminal (or log in again) — the current session has no sharing-group"
ui_warn "membership yet, no ddev shell function and no PATH/umask additions; a fresh"
ui_warn "session starts with all of them."
echo ""
echo ""
ui_info "Next:"
ui_detail "opencode                       start the agent (new terminal!)"
[ -n "$DD_MIG_DUMP_DIR" ] && ui_detail \
    "sudo /usr/local/lib/opencode-permissions-kit/bin/ddev-migrate import  re-import your ddev databases"
ui_detail "opk status   verify the protection"
ui_detail "opk config   change settings later (or update/uninstall)"
ui_detail "Docs:  https://github.com/steffenmaechtel/opencode-permissions-kit/blob/master/docs/README.md"
log "install complete"
