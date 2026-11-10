#!/bin/sh
# opencode permissions kit -- update.sh
# Re-deploys the KIT onto a system that has already been installed via
# install.sh: the wrapper and cli symlinks, the full library via the
# deploy-lib.sh manifest (~40 files — layout and modes live there),
# sudoers, the umask profile and the agent/binary state. Does NOT touch:
#   - existing /etc/opencode-permissions-kit/projects.conf
#   - existing /etc/opencode-permissions-kit/install.conf (except the
#     keys this script writes: the VERSION stamp, KIT_CHANNEL,
#     DDEV_VERSION and the OPENCODE_MAJOR stamp (own blocks), and the
#     OPENCODE_GROUP re-base)
#   - existing /home/opencode/.config/opencode/opencode.json[c]
#   - the DEFAULT user's existing opencode config (a deny-all config is only
#     deployed when that user has no opencode.jsonc yet)
#   - the opencode binary at /usr/local/lib/opencode-permissions-kit/bin/opencode — UNLESS
#     --binary is given (fetch the latest release and install it) or
#     --binary-path <file> (install the given binary without downloading).
#
# Supported upgrade floor: the installed kit must be >= 0.0.14. Older
# installs abort with instructions (re-run install.sh).
#
# One-liner (fetches the new update.sh + all kit files at $KIT_BRANCH) —
# the URL is split at the repo boundary; join it when copying:
#   curl -fsSL https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit\
# /stable/files/opencode-permissions-kit-lib/management/update.sh | sudo env KIT_BRANCH=stable bash
#
# From a checkout (uses the local files):
#   sudo bash files/opencode-permissions-kit-lib/management/update.sh --yes     # skip prompts
#   sudo bash files/opencode-permissions-kit-lib/management/update.sh --refresh # re-apply group baseline
#   sudo bash files/opencode-permissions-kit-lib/management/update.sh --binary  # upgrade the opencode binary
#
# `opencode upgrade` cannot work behind the wrapper (the binary is root-owned
# and opencode runs as an unprivileged user), so this script is the upgrade
# entry point. Binary upgrades are best-effort: a download/verify failure warns
# and leaves the current binary in place — the kit update still completes.
#
# Use install.sh for the very first setup (it asks the questions).
# Use config.sh to change project roots or git-config hardening.
# -u/pipefail rationale: see install.sh (review 0.0.39a C2).
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail || true

# Scratch-file cleanup (review 0.0.39a C1): temp artifacts are removed on
# ANY exit path — failure, Ctrl-C, TERM, and success. The upgrade backup
# directory is deliberately kept (recovery material, reported to the
# user). _FETCH_TREE survives the self re-exec below via the environment,
# so the re-exec'd copy cleans the tree its parent fetched.
_FETCH_TREE="${_FETCH_TREE:-}"
# Result dir of a fetched tree — set by fetch_kit, read by the caller
# below (never stdout: the export + trap registration must happen in THIS
# shell, and a command substitution would void both; wave-f review).
_FK_DIR="${_FK_DIR:-}"
_BIN_TMP=""
# Registry for short-lived scratch files created inside functions
# (ensure_local_file fetch temps, wsl-browser-bridge rewrites) — the
# trap empties it on every exit path (review 0.0.39e C3).
_TMP_REGISTRY=""
_tmp_track() { _TMP_REGISTRY="$_TMP_REGISTRY $1"; }
cleanup() {
    if [ -n "${_FETCH_TREE:-}" ]; then rm -rf "$_FETCH_TREE"; fi
    if [ -n "${_BIN_TMP:-}" ]; then rm -rf "$_BIN_TMP"; fi
    # word splitting intended: registry entries are mktemp paths
    # shellcheck disable=SC2086
    if [ -n "${_TMP_REGISTRY:-}" ]; then rm -f $_TMP_REGISTRY; fi
}
# A signal handler must EXIT (see install.sh); the EXIT trap re-runs the
# idempotent cleanup.
trap cleanup EXIT
trap 'cleanup; exit 1' INT TERM

# Ref the kit updates from. Resolution (issue #38, internal/process/
# release-handling.md): --channel flag (pre-scanned below) > explicit
# KIT_BRANCH env > KIT_CHANNEL stamp in install.conf (the channel this
# machine installed/last updated from) > master (development channel;
# 'stable' is the release mirror the docs one-liners use). Must run BEFORE
# the self-fetch below. Overridable for testing:
# KIT_BASE_URL=https://example.invalid/<branch>
#
# --channel <ref> pre-scan: 'opk update --channel <ref>' switches the
# tracking ref for THIS update and every future one — update.sh re-stamps
# KIT_CHANNEL at the end, so the switch persists. The scan must happen
# before the resolution below and before the fetch; the regular arg loop
# below consumes and validates the flag again.
_prev_arg=""
for _arg in "$@"; do
    if [ "$_prev_arg" = "--channel" ]; then
        [ -n "$_arg" ] || {
            echo "error: --channel requires a ref (stable, master, a branch, or a tag)" >&2
            exit 1
        }
        KIT_BRANCH="$_arg"
    fi
    _prev_arg="$_arg"
done
# || true on the optional-file reads: with pipefail the sed failure on a
# missing install.conf must not abort (the old tail-masking hid it).
_kit_stamped_channel="$(sed -n 's/^KIT_CHANNEL=//p' /etc/opencode-permissions-kit/install.conf \
    2>/dev/null | tail -1 || true)"
KIT_BRANCH="${KIT_BRANCH:-${_kit_stamped_channel:-master}}"
# The resolved ref is re-stamped as KIT_CHANNEL into install.conf, which
# privileged scripts source wholesale — refuse anything outside a git-ref
# charset, whatever its source (--channel flag, env, or a stale stamp)
# (review 0.0.39b S1).
case "$KIT_BRANCH" in
    *[!A-Za-z0-9._/-]* | *..*)
        echo "error: channel ref '$KIT_BRANCH' is invalid — a ref is letters, digits, ""\
'.', '_', '/', '-' (no '..'; git refnames cannot carry it)" >&2
        exit 1
        ;;
esac
KIT_BASE_URL="${KIT_BASE_URL:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/$KIT_BRANCH}"

# Canonical kit file list. Single source of truth shared by fetch_kit() and
# the pre-deploy verification (ensure_local_file), so the two can never drift
# and a stale installed update.sh fetching an incomplete temp dir is healed
# before the deploy cp's run.
# Layout (internal/records/streamline.md): bin/ = commands, sh/ = sourced libs,
# py/ = python, tui/ = assets; the management scripts and templates keep
# their files/ root paths (streamed entry points) and deploy into
# management/ and templates/.
# BREAKING (0.0.29): the pre-0.0.29 flat layout moved — `opk update` from
# an older install aborts on the old fetch list (404); migrate once via
#   curl -fsSL .../files/opencode-permissions-kit-lib/management/update.sh | sudo bash
# which deploys the new layout and removes the old files (see the cleanup
# section below). No compatibility stubs are kept for the old paths.
#
# FORMAT RULE: one file per line, backslash-continued — packed multi-name
# lines make every diff unreadable (test-kit-files compares word-wise and
# does not care about layout; this format is convention). Keep it when
# adding files. install.sh's fetch_kit list follows the same rule.
KIT_FILES="install.sh \
VERSION \
opencode-permissions-kit-lib/sh/path-sane.sh \
opencode-permissions-kit-lib/sh/install-core.sh \
opencode-permissions-kit-lib/sh/uninstall-core.sh \
opencode-permissions-kit-lib/sh/handover-core.sh \
opencode-permissions-kit-lib/sh/openchamber-core.sh \
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
opencode-permissions-kit-lib/sh/doctor-core.sh \
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
opencode-permissions-kit-lib/tui/tui-danger.json"

# Downloads every kit file from KIT_BASE_URL into a temp checkout layout
# (files/ + VERSION) and prints the files/ directory. Used when this script
# is streamed via `curl | sudo bash` or run from the installed library
# (which only holds the previously deployed, possibly older, files).
fetch_kit() {
    local base dir f
    # Guarded (#364 sweep sibling): the caller runs `fetch_kit || {...}`
    # — set -e is suppressed in this callee, and an empty base from a
    # dead TMPDIR collapsed every path below onto root-level literals
    # (the pre-create ran mkdir -p /files/... as root, the #360 a F5
    # class) before the fetch errors blamed curl.
    base="$(mktemp -d)" || {
        echo "error: mktemp failed (is \$TMPDIR writable?) — cannot stage the kit fetch" >&2
        return 1
    }
    # Registered for the EXIT/INT/TERM cleanup (survives the re-exec via
    # the export below): a failed fetch must not leave the partial tree.
    _FETCH_TREE="$base"
    dir="$base/files"
    # Pre-create every subdirectory referenced by KIT_FILES (bin/, sh/,
    # py/, tui/): curl -o cannot write into a missing directory and aborts
    # the fetch with error 23 ("Failure writing output to destination").
    mkdir -p "$dir/opencode-permissions-kit-lib/bin" "$dir/opencode-permissions-kit-lib/sh" \
        "$dir/opencode-permissions-kit-lib/py" "$dir/opencode-permissions-kit-lib/tui" \
        "$dir/opencode-permissions-kit-lib/management" "$dir/opencode-permissions-kit-lib/templates" \
        "$dir/etc"
    for f in $KIT_FILES; do
        echo "  fetching $f ..." >&2
        # Fetch to a temp file and refuse anything unsound (0.0.39e C1):
        # an empty-but-200 body landed in the deploy tree as root before —
        # the same guard ensure_local_file already carries.
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
    # Global, NOT stdout — see install.sh's copy (subshell registrations
    # would void the cleanup trap; wave-f review).
    _FK_DIR="$dir"
}

# Re-fetch any single kit file that is missing under $FILES_ROOT (best-effort).
# Heals an incomplete temp-fetch when an older installed update.sh re-exec'd
# this freshly fetched copy with a smaller file list. For a real local
# checkout every file is present and this is a no-op.
ensure_local_file() {
    local f="$1"
    [ -f "$FILES_ROOT/$f" ] && return 0
    mkdir -p "$(dirname "$FILES_ROOT/$f")"
    echo "  re-fetching missing $f ..." >&2
    # A failed fetch must never leave a partial (empty or HTML-error-body)
    # file in place — it would be deployed with sudo cp further down
    # (review 0.0.39a S3). Fetch to a temp file, move in only when sound.
    local _elf_tmp
    # Named-cause guard (#376 B4, review #370 a B4): the #364 sweep
    # guarded both fetch_kit mktemps with kit diagnostics but left this
    # one bare — set -e aborts on the raw failure; the guard names the
    # file that could not be re-fetched (same wording family as the
    # fetch_kit siblings above).
    if ! _elf_tmp="$(mktemp)"; then
        echo "error: mktemp failed (is \$TMPDIR writable?) — cannot re-fetch $f" >&2
        return 1
    fi
    _tmp_track "$_elf_tmp"
    if ! curl -fsSL "$KIT_BASE_URL/files/$f" -o "$_elf_tmp" 2>/dev/null || [ ! -s "$_elf_tmp" ]; then
        rm -f "$_elf_tmp"
        echo "error: could not fetch $f from $KIT_BASE_URL — aborting (partial files are never deployed)" >&2
        return 1
    fi
    chmod 644 "$_elf_tmp"
    mv "$_elf_tmp" "$FILES_ROOT/$f"
}

# The readlink fallback (#437 a B1) keeps a degraded readlink from
# resolving the dir to the invoking cwd. Two degraded shapes (#437 c
# E1, measured): a $0 through a broken INTERMEDIATE component fails
# LOUD via the cd under set -e (deliberate, #437 b D2); a dangling
# FINAL symlink -- readlink -f refuses to resolve it -- degrades
# silently to the LINK'S OWN dir, still not the cwd. Both are
# strictly narrower than the old spelling's silent cwd trust.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")" && pwd)"
# Streamed stdin runs (curl ... | sudo bash, issue #405): $0 is the
# interpreter, not this script — readlink resolves it against the
# INVOKING cwd, so SCRIPT_DIR above is cwd-derived and every
# checkout-first lookup below (ui.sh through update-core.sh) would
# source whatever sibling files the cwd happens to sit next to, as
# root, with no vintage pinning. Detect the shape once, for the whole
# class of lookups (#433 hardening, same discriminator at all six
# #405 anchors): a streamed run's $0 IS the interpreter's own argv[0]
# — /proc/$$/cmdline's first field names exactly that, so a planted
# cwd FILE named like the interpreter no longer defeats the check
# (the #405 file probe alone resolved it to an existing file and
# re-opened the cwd trust). Without /proc the file probe remains the
# fallback (best effort, the pre-#433 surface).
_opk_stdin=false
_opk_argv0="$(tr '\0' '\n' 2>/dev/null </proc/$$/cmdline | head -n 1)"
if [ -n "$_opk_argv0" ]; then
    if [ "$0" = "$_opk_argv0" ]; then
        _opk_stdin=true
    fi
elif ! [ -f "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")" ]; then
    _opk_stdin=true
fi
# Binary-only mode (--only-binary) needs no kit FETCH — when running
# from the installed library, skip the self-fetch (and the per-file heal
# loop below, which would re-fetch the whole kit for the deployed
# layout). Since #346 wave 2 the phase functions live in
# sh/update-core.sh, so binary-only still needs that lib present next to
# this script or in $LIBDIR (the resolver below fails loud otherwise —
# run one full update first when upgrading from a pre-wave library).
# --binary-path ALONE does a full update PLUS the binary swap, so it must NOT
# skip the fetch (review 0.0.29: from the installed library it would have
# crashed the deploy section with FILES_ROOT=/usr/local/lib).
_opk_binonly=false
for _opk_a in "$@"; do
    case "$_opk_a" in
        --only-binary)
            _opk_binonly=true
            break
            ;;
    esac
done
# Stdin runs never trust the cwd-derived checkout test below (#405): a
# kit checkout adjacent to the invoking cwd would pass it spuriously
# and run an unpinned local vintage. The fetch re-pins the vintage
# (KIT_BASE_URL) and the re-exec gives the fetched copy a real $0.
if [ "$_opk_binonly" != true ] && { [ "$_opk_stdin" = true ] ||
    [ ! -f "$SCRIPT_DIR/../../../VERSION" ]; }; then
    echo "No local checkout — fetching kit files from $KIT_BASE_URL ..."
    # Direct call, NOT SCRIPT_DIR="$(fetch_kit)" — a subshell's variable
    # writes (incl. the _FETCH_TREE export below and the trap
    # registrations) never reach this shell (wave-f review).
    fetch_kit || {
        echo "error: Failed to fetch kit files from $KIT_BASE_URL" >&2
        exit 1
    }
    SCRIPT_DIR="$_FK_DIR"
    # A streamed update's stdin IS the script body (curl | sudo bash):
    # the prompt helpers must never fall back to reading it — they would
    # consume script bytes as the confirm answer and unknown input
    # silently resolves to the default y, an update without any consent
    # on the record (review 0.0.39b C6 closed this for install.sh; the
    # update path lacked it — 0.0.45c S8). See _ui_read in sh/ui.sh.
    # Exported: the re-exec'd copy below inherits it.
    UI_NO_STDIN_FALLBACK=1
    export UI_NO_STDIN_FALLBACK
    # Do NOT continue executing this (installed, possibly older) copy: the
    # deploy below overwrites $LIBDIR/management/update.sh with the freshly fetched one,
    # which would replace the very file we are still running from. bash reads
    # a script incrementally, so a self-modifying script corrupts its parser
    # mid-run ("syntax error near unexpected token '('"). Re-exec the fetched
    # copy instead — its own overwrite of $LIBDIR/management/update.sh is then harmless.
    # exec replaces this shell, so the EXIT trap cannot fire here — hand the
    # fetched tree to the new process via the environment; its own cleanup
    # trap removes it on exit.
    export _FETCH_TREE
    exec bash "$SCRIPT_DIR/opencode-permissions-kit-lib/management/update.sh" "$@"
fi
# --only-binary skips the fetch by design, so a stdin run gets no
# fetch-and-re-exec to re-anchor SCRIPT_DIR: pin it to the DEPLOYED
# library (the installed vintage, root-owned) instead of the invoking
# cwd, and refuse loudly when nothing is installed — a cwd-sibling
# update-core.sh is not a substitute (#405).
if [ "$_opk_stdin" = true ] && [ "$_opk_binonly" = true ]; then
    if [ -f /usr/local/lib/opencode-permissions-kit/sh/update-core.sh ]; then
        # The DEPLOYED management dir on the flat library layout — a
        # stdin run then resolves exactly like a deployed run (every
        # checkout-first candidate misses, the LIBDIR fallbacks hit;
        # review a B1: the repo-layout path does not exist deployed).
        SCRIPT_DIR="/usr/local/lib/opencode-permissions-kit/management"
    else
        echo "error: streamed --only-binary run found no installed kit library at" >&2
        echo "       /usr/local/lib/opencode-permissions-kit — install the kit first," >&2
        echo "       or run a full streamed update without --only-binary" >&2
        exit 1
    fi
fi
# The files/ root this update deploys from: after the fetch+re-exec above
# $SCRIPT_DIR is the fetched files/ directory itself; run from a checkout it
# is files/opencode-permissions-kit-lib/management (two levels down).
FILES_ROOT="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd -P)"

# Heal an incomplete fetched temp dir (see ensure_local_file above) before we
# touch any of the files. No-op for a real local checkout; skipped entirely
# for binary-only runs from the installed library.
if [ "$_opk_binonly" != true ]; then
    for f in $KIT_FILES; do
        [ "$f" = "VERSION" ] && continue
        ensure_local_file "$f"
    done
fi
# Library runs have no ../VERSION — fall back to the installed stamp so the
# banner/summary show the real version (binary-only runs never re-stamp it).
# The empty-output case is closed explicitly: sed "succeeding" with no
# match would otherwise leave VERSION empty instead of "0.0.0"
# (review 0.0.39b Q3).
if [ "$_opk_binonly" != true ] && [ -f "$FILES_ROOT/../VERSION" ]; then
    # || true (pr-00429 a B2): an existing-but-unreadable file makes cat
    # fail — the bare assignment would die silently under set -e; the
    # || true routes it into the empty-content arm of the gate (named
    # abort with got '<empty>').
    VERSION="$(cat "$FILES_ROOT/../VERSION" 2>/dev/null)" || true
    # Shape gate (#376 B3, review #370 a B3): the fetched VERSION is
    # remote-mirror content that ends up re-stamped into install.conf
    # (sourced by root) — previously only non-empty was checked, while
    # sh/update-check.sh gates the same remote file to exactly x.y.z.
    # Fail closed on ANY deviation (empty, multi-line, suffixed, a
    # mirror's HTML error body) BEFORE anything is fetched onward or
    # deployed; the install.conf fallback below stays local,
    # root-owned input. Newline reject FIRST (the update-check.sh
    # two-step): grep -x alone would accept "1.2.3\njunk" — any single
    # fully-matching line passes -q, interior garbage rides along.
    _vsg_nl='
'
    case "$VERSION" in
        *"$_vsg_nl"*)
            echo "error: fetched VERSION file is malformed (multi-line, expected one x.y.z line) — aborting" >&2
            exit 1
            ;;
    esac
    if ! printf '%s\n' "$VERSION" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+'; then
        echo "error: fetched VERSION file is malformed (expected x.y.z, got '${VERSION:-<empty>}') — aborting" >&2
        exit 1
    fi
else
    # || true (pr-00429 a B1, the :96-98 pattern): with pipefail the sed
    # failure on a missing/unreadable install.conf must not abort — the
    # old chain's `|| echo "0.0.0"` protected exactly this arm, and the
    # preflight's named "Not installed yet" die (not a silent rc 1
    # before the banner) is the contract.
    VERSION=$(sed -n 's/^VERSION=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null | tail -1 || true)
    [ -n "$VERSION" ] || VERSION="0.0.0"
fi
LIBDIR="/usr/local/lib/opencode-permissions-kit"
CONFDIR="/etc/opencode-permissions-kit"
PROJECTS_CONF="$CONFDIR/projects.conf"

# === Shared UI helpers ===
# Checkout copy first, then the deployed library; a plain fallback keeps
# update.sh working on an install whose library predates ui.sh.
UI_LIB=""
for _cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/ui.sh" "$LIBDIR/sh/ui.sh"; do
    if [ -f "$_cand" ]; then
        UI_LIB="$_cand"
        break
    fi
done
if [ -n "$UI_LIB" ]; then
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
    # 0.0.45d W4: the body's confirm() calls ui_confirm — without a
    # stub a ui.sh-less update died rc 127 at the confirm prompt
    # instead of failing with a re-deploy hint (0.0.45c C9 fixed the
    # same class in config.sh; the C9 sweep missed this fallback).
    # Loud-fail stub: non-interactive paths keep working, the one
    # prompt fails with a message instead of "command not found".
    _ui_no_prompt() {
        echo "error: this prompt needs sh/ui.sh — library too old, re-deploy with 'sudo opk update'" >&2
        return 1
    }
    ui_confirm() { _ui_no_prompt; }
    UI_GREEN=''
    UI_RED=''
    UI_YELLOW=''
    UI_CYAN=''
    UI_BLUE=''
    UI_NC=''
fi

# === Audit log ===
# Best-effort shared logger (/var/log/opencode-permissions-kit/). Covers all
# three run modes: repo checkout, streamed temp dir, installed library.
log() { :; }
for cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/log.sh" "$LIBDIR/sh/log.sh"; do
    if [ -f "$cand" ]; then
        . "$cand"
        break
    fi
done

# install.conf (upgrade floor 0.0.14: the canonical path always exists)
INSTALL_CONF="$CONFDIR/install.conf"

# Shared symlink-safe privileged-write helper (review 0.0.39g S1) +
# agent-home link gates (review 0.0.39h F1/F2): the tui.json refresh and
# sync_tui_registration below write into the AGENT-owned
# ~/.config/opencode — root cp/chown must never follow a planted symlink
# there, and a linked PARENT (~/.config, ~/.config/opencode) must never
# redirect the writes. Sourced EARLY (moved from the tui.json section,
# 0.0.39h): sync_tui_registration also runs from the binary-upgrade
# section above that old point. Same lookup order as ui.sh.
_swl=""
for _swl_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/staged-write.sh" "$LIBDIR/sh/staged-write.sh"; do
    if [ -f "$_swl_cand" ]; then
        . "$_swl_cand"
        _swl="$_swl_cand"
        break
    fi
done
[ -n "$_swl" ] || staged_write() {
    echo "error: staged_write unavailable (staged-write.sh missing)" >&2
    return 1
}
# Old-library fallback (pre-0.0.39h deployed copy): no walker yet — fail
# open like the pre-gate behavior, the writes above still refuse via
# staged_write itself.
command -v agent_home_sane >/dev/null 2>&1 || agent_home_sane() { return 0; }

# Shared sudoers pipeline (render + visudo validation + install): one
# implementation for install.sh, config.sh and update.sh. Same lookup
# order as staged-write.sh.
_sdl=""
for _sdl_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/sudoers-deploy.sh" "$LIBDIR/sh/sudoers-deploy.sh"; do
    if [ -f "$_sdl_cand" ]; then
        . "$_sdl_cand"
        _sdl="$_sdl_cand"
        break
    fi
done
[ -n "$_sdl" ] ||
    sudoers_deploy() {
        echo "error: sudoers_deploy unavailable (sudoers-deploy.sh missing)" >&2
        return 1
    }

# Shared binary hardening (chown root:<group> best-effort + the
# load-bearing chmod 750, fail-loud): one implementation for
# install.sh and update.sh. Same lookup order as staged-write.sh.
_sbl=""
for _sbl_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/secure-binary.sh" "$LIBDIR/sh/secure-binary.sh"; do
    if [ -f "$_sbl_cand" ]; then
        . "$_sbl_cand"
        _sbl="$_sbl_cand"
        break
    fi
done
[ -n "$_sbl" ] ||
    secure_binary() {
        echo "error: secure_binary unavailable (secure-binary.sh missing)" >&2
        return 1
    }
[ -n "$_sbl" ] ||
    copy_binary_atomic() {
        echo "error: copy_binary_atomic unavailable (secure-binary.sh missing)" >&2
        return 1
    }
[ -n "$_sbl" ] ||
    copy_file_atomic() {
        echo "error: copy_file_atomic unavailable (secure-binary.sh missing)" >&2
        return 1
    }

# Shared library deployment manifest (what ships into $LIBDIR, from
# ONE list — install.sh deploys through it too). Same lookup order as
# staged-write.sh.
_dll=""
for _dll_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/deploy-lib.sh" "$LIBDIR/sh/deploy-lib.sh"; do
    if [ -f "$_dll_cand" ]; then
        . "$_dll_cand"
        _dll="$_dll_cand"
        break
    fi
done
[ -n "$_dll" ] ||
    lib_deploy() {
        echo "error: lib_deploy unavailable (deploy-lib.sh missing)" >&2
        return 1
    }

# Shared TUI 2.x plugin registration (per-user plugin-dir sync): one
# implementation for update.sh's sync_tui_registration and install.sh
# Step 8c. Same lookup order as staged-write.sh.
_tpl=""
for _tpl_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/tui-plugin.sh" "$LIBDIR/sh/tui-plugin.sh"; do
    if [ -f "$_tpl_cand" ]; then
        . "$_tpl_cand"
        _tpl="$_tpl_cand"
        break
    fi
done
[ -n "$_tpl" ] ||
    tui_plugin_sync_user() {
        echo "error: tui_plugin_sync_user unavailable (tui-plugin.sh missing)" >&2
        return 1
    }

# Shared git presence/version check (soft floor, issue #118): same
# advisory as install.sh's pre-flight — #116 surfaced during `opk
# update`, so the upgrade path warns here too. No-op stub keeps an
# old-library update running when neither copy is around (the check is
# advisory by design, see git-check.sh's header). Same lookup order as
# staged-write.sh.
_tgc=""
for _tgc_cand in "$FILES_ROOT/opencode-permissions-kit-lib/sh/git-check.sh" "$LIBDIR/sh/git-check.sh"; do
    if [ -f "$_tgc_cand" ]; then
        . "$_tgc_cand"
        _tgc="$_tgc_cand"
        break
    fi
done
[ -n "$_tgc" ] || git_check_report() { :; }

DEFAULT_USER=""
OPENCODE_USER="opencode"
INSTALLED_VERSION=""
# Save the version from the VERSION file (read above) before sourcing
# install.conf, which also has a VERSION= line (the old stamp). We don't
# want install.conf to overwrite the freshly-read VERSION from the repo.
KIT_VERSION="$VERSION"
if [ -f "$INSTALL_CONF" ]; then
    INSTALLED_VERSION=$(sed -n 's/^VERSION=//p' "$INSTALL_CONF" | tail -1)
    . "$INSTALL_CONF"
fi
VERSION="$KIT_VERSION"
DEFAULT_USER="${DEFAULT_USER:-${SUDO_USER:-$(whoami)}}"
OPENCODE_USER="${OPENCODE_USER:-opencode}"
# Shape-gate the sourced value (#243 e X1 mirror, pr-00263 a F2b): the
# conf is root-owned but hand-editable; a shape-invalid value feeds the
# id check, the sudo -u hop and the ddev-handover argv over the
# projects.conf roots below — fall back to the canonical literal,
# loudly; the WARN is sanitized (pr-00263 a F9 class).
case "$OPENCODE_USER" in
    '' | *[!A-Za-z0-9_.-]* | [.-]* | *[.])
        _ou_bad="$(printf '%s' "$OPENCODE_USER" | tr -c 'A-Za-z0-9_.-' '?')"
        echo "WARN: invalid OPENCODE_USER value in install.conf ('$_ou_bad') — falling back to 'opencode'" >&2
        OPENCODE_USER=opencode
        ;;
esac
# Developer home via getent (issue #192, the 0.0.44a V14 class in the
# sibling management scripts): /home/$DEFAULT_USER is a guess that misses
# relocated homes — and on a root-shell install (DEFAULT_USER=root) it
# points at /home/root, which never exists, so whole sections silently
# skipped. Resolved once here, used by every developer-side site below.
DEFAULT_HOME="$(getent passwd "$DEFAULT_USER" 2>/dev/null | cut -d: -f6 || true)"
[ -n "$DEFAULT_HOME" ] || DEFAULT_HOME="/home/$DEFAULT_USER"

# --- upgrade floor: >= 0.0.14 -------------------------------------------------
# Updates are only supported from 0.0.14 onwards (all older migrations were
# removed). Compare numerically: major*1000000 + minor*1000 + patch.
floor_check() {
    _fv="${1%%-*}" _av="${2%%-*}"
    _f1=${_fv%%.*}
    _rest=${_fv#*.}
    _f2=${_rest%%.*}
    _f3=${_rest#*.}
    _a1=${_av%%.*}
    _rest=${_av#*.}
    _a2=${_rest%%.*}
    _a3=${_rest#*.}
    _f1=${_f1:-0}
    _f2=${_f2:-0}
    _f3=${_f3:-0}
    _a1=${_a1:-0}
    _a2=${_a2:-0}
    _a3=${_a3:-0}
    [ $((_a1 * 1000000 + _a2 * 1000 + _a3)) -ge $((_f1 * 1000000 + _f2 * 1000 + _f3)) ]
}
if [ -f "$INSTALL_CONF" ]; then
    if [ -z "$INSTALLED_VERSION" ] || ! floor_check "0.0.14" "$INSTALLED_VERSION"; then
        ui_error "Unsupported upgrade path: installed kit version is '${INSTALLED_VERSION:-unknown}'."
        echo ""
        echo "  Updates are only supported from kit 0.0.14 onwards (older"
        echo "  migrations have been removed). Re-run install.sh instead:"
        echo "    curl -fsSL https://raw.githubusercontent.com/steffenmaechtel""\
/opencode-permissions-kit/stable/files/install.sh | sudo env KIT_BRANCH=stable bash"
        echo ""
        exit 1
    fi
fi

YES=false
REFRESH=false
BINARY_UPDATE=false
ONLY_BINARY=false
BINARY_PATH=""
UPGRADE_MAJOR=""
UPGRADE_VERSION=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes | -y) YES=true ;;
        --refresh) REFRESH=true ;;
        --binary) BINARY_UPDATE=true ;;
        --only-binary)
            # issue #24: skip every kit step, only upgrade the binary
            ONLY_BINARY=true
            BINARY_UPDATE=true
            ;;
        --binary-path)
            [ "$#" -ge 2 ] || {
                echo "error: --binary-path requires a file path" >&2
                exit 1
            }
            BINARY_UPDATE=true
            BINARY_PATH="$2"
            shift
            ;;
        --channel)
            # consumed by the pre-scan above (before the self-fetch);
            # accepted here so it never reaches the unknown-option trap
            [ "$#" -ge 2 ] ||
                {
                    echo "error: --channel requires a ref (stable, master, a feature branch, or a tag)" >&2
                    exit 1
                }
            shift
            ;;
        --major)
            # issue #99: switch the opencode major (1 <-> 2); without it
            # upgrades stay within the current major
            [ "$#" -ge 2 ] || {
                echo "error: --major requires a number (1 or 2)" >&2
                exit 1
            }
            case "$2" in
                1 | 2) UPGRADE_MAJOR="$2" ;;
                *)
                    echo "error: --major must be 1 or 2" >&2
                    exit 1
                    ;;
            esac
            shift
            ;;
        --version)
            # issue #99: pin an exact opencode version; the download
            # channel follows the version prefix (2.* npm, 1.x GitHub)
            [ "$#" -ge 2 ] || {
                echo "error: --version requires an opencode version (e.g. 2.0.11)" >&2
                exit 1
            }
            UPGRADE_VERSION="$2"
            shift
            ;;
        -h | --help)
            cat <<EOF
opencode permissions kit -- update.sh  v$VERSION
Re-deploys the kit on an already-installed system. Asks one confirmation
question unless --yes is given (tty-less streamed runs without --yes fail
the prompt loudly instead of reading script bytes — 0.0.45c S8).
Usage: ./update.sh [--yes] [--refresh] [--binary] [--only-binary] [--binary-path <file>]
                  [--channel <ref>] [--major 1|2] [--version <ver>]
  --yes            skip the confirmation prompt
  --refresh        also re-apply the group baseline (chgrp/setgid/default ACLs)
  --binary         also upgrade the opencode binary to the latest release
                   of the CURRENT major (issue #99: never crosses majors)
  --only-binary    skip every kit step, ONLY upgrade the opencode binary
  --binary-path    install the given binary file instead of downloading
  --channel        switch the tracking ref for this and every future update
                   (stable, master, a feature branch, or a pinned tag)
  --major          switch the opencode major: 1 or 2 (default: stay on the
                   current major; the TUI registration flips with it)
  --version        upgrade to exactly this opencode version (channel by
                   prefix: 2.* from npm, 1.x from GitHub)
EOF
            exit 0
            ;;
        *)
            echo "error: unknown option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

banner() {
    ui_banner "$VERSION" "update — channel '$KIT_BRANCH' — re-deploys the kit, keeps your configuration"
}

die() {
    ui_error "$*"
    exit 1
}

confirm() {
    # Convention: agent/conventions.md — [Y/n] default capital,
    # Enter accepts it, y/yes/n/no case-insensitive.
    # The y default is deliberate (#428 disposition, uniform with
    # install-core.sh's re-configure ask): `opk update` is an explicit
    # invocation whose yes IS the command's purpose — this prompt is
    # its final confirmation, so "no" is the surprising answer (it
    # leaves the declared intent half-done). The conventions' carve-
    # out applies ("y only where no is the surprising/riskier
    # answer", agent/conventions.md "Interactive prompts", like the
    # audit-log deletion): the action touches kit-owned files only —
    # the message itself promises configs stay untouched — and
    # unattended runs pass --yes and never see it.
    [ "$YES" = true ] && return 0
    ui_confirm "$1" "y"
}

# --- phase logic: sh/update-core.sh (issue #346, wave 2) -----------------------
# Every phase section below lives in the sourced lib — checkout-first
# like status.sh's status-core.sh (a checkout update.sh runs its own
# phases; an older deployed lib could predate one). A deployed run
# resolves both candidates to the same path, so a missing lib is a
# broken kit (issue #165 class): loud error, no silent phase drops.
UPDATE_CORE="$SCRIPT_DIR/../sh/update-core.sh"
[ -f "$UPDATE_CORE" ] || UPDATE_CORE="$LIBDIR/sh/update-core.sh"
if [ -f "$UPDATE_CORE" ]; then
    # shellcheck disable=SC1090
    . "$UPDATE_CORE"
else
    echo "error: update-core.sh not found (expected $LIBDIR/sh/update-core.sh or next to update.sh in a checkout)" >&2
    exit 1
fi

# Pairing guard (#413, PR #412 round a S2): the resolver dies loud on a
# missing FILE; this closes the missing-FUNCTION twin — a version-skewed
# entry/lib pairing (a core missing one renamed or newly-added section)
# makes the bare section calls below fail with rc 127, and under set -e
# that aborts cryptically mid-update ("not found", no named cause) after
# earlier sections already ran. The guard converts it into a diagnosed
# abort BEFORE any section runs and pins the section list the entry
# expects (a section added to the core without the entry calling it is
# equally a wiring bug this list makes reviewable).
update_pairing_guard() {
    for _upg in update_redeploy_library update_redeploy_wsl_bridge \
        update_redeploy_cli_links \
        update_redeploy_sudoers update_redeploy_umask \
        update_redeploy_openchamber update_redeploy_shell_hooks \
        update_redeploy_project_roots update_redeploy_git_safe \
        update_redeploy_wsl_mntc update_binary_resecure \
        update_binary_upgrade update_redeploy_xdg_shim \
        update_finalize_opencode_home \
        update_finalize_default_config update_finalize_ddev_stamp \
        update_finalize_install_conf update_finalize_tui_files; do
        command -v "$_upg" >/dev/null 2>&1 || {
            echo "error: section '$_upg' missing from update-core.sh — version-skewed entry/lib pairing, aborting" >&2
            return 1
        }
    done
}
update_pairing_guard || exit 1

# --- pre-flight ---------------------------------------------------------------

banner
log "update started (version $VERSION, refresh=$REFRESH)"

# Soft git floor advisory (issue #118): same warn-only check as the
# install pre-flight — right behind the banner so it is seen with the
# confirmation prompt, before any git-touching phase runs (#116
# surfaced during an update).
git_check_report

if [ ! -f "$INSTALL_CONF" ]; then
    die "Not installed yet. Run install.sh first."
fi

if ! id "$OPENCODE_USER" >/dev/null 2>&1; then
    die "User '$OPENCODE_USER' missing. Run install.sh first."
fi

# The new sharing group: the opencode user's primary usergroup.
NEW_OPENCODE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || echo "$OPENCODE_USER")"

if [ "$ONLY_BINARY" = true ]; then
    _uc_msg="Only upgrade the opencode binary (kit files untouched)?"
else
    _uc_msg="Re-deploy kit files (existing configs will NOT be touched)?"
fi
if ! confirm "$_uc_msg"; then
    echo "Aborted."
    exit 0
fi

# #211 a F33: the group-baseline refresh lives in the kit (non-
# only-binary) block below — the combination used to drop --refresh
# without a word.
if [ "$ONLY_BINARY" = true ] && [ "$REFRESH" = true ]; then
    ui_detail "note: --refresh is skipped under --only-binary (no kit state is touched)"
    log "update --refresh --only-binary: refresh skipped by design"
fi

# --- phases, in run order (the sections live in sh/update-core.sh) -------------
# Kit re-deploy is skipped under --only-binary (issue #24); the binary
# re-assert and the optional upgrade always run; the finalize sections
# re-stamp state only a full update touches.
if [ "$ONLY_BINARY" != true ]; then
    update_redeploy_library
    update_redeploy_wsl_bridge
    update_redeploy_cli_links
    update_redeploy_sudoers
    update_redeploy_umask
    update_redeploy_openchamber
    update_redeploy_shell_hooks
    update_redeploy_project_roots
    update_redeploy_git_safe
    update_redeploy_wsl_mntc
fi

update_binary_resecure
if [ "$BINARY_UPDATE" = true ]; then
    update_binary_upgrade
else
    ui_detail "opencode binary left untouched (use --binary to upgrade)"
fi

if [ "$ONLY_BINARY" != true ]; then
    # After the optional binary swap by design (#257): the shim gate
    # reads the DEPLOYED binary's version — a downgrade + full update
    # re-deploys the shim in the same run, an upgrade past the fix
    # removes it. (Full updates and --binary runs only: under
    # --only-binary this block is skipped by design — review a B5 —
    # so `opk upgrade-opencode` alone leaves a stale shim until the
    # next full update, matching that mode's "kit files untouched"
    # contract and the docs' full-update advice.)
    update_redeploy_xdg_shim
    update_finalize_opencode_home
    update_finalize_default_config
    update_finalize_ddev_stamp
    update_finalize_install_conf
    update_finalize_tui_files
fi

# --- done --------------------------------------------------------------------

ui_section "Update complete"

if [ "$ONLY_BINARY" = true ]; then
    ui_kv "Mode" "binary-only (kit files untouched)"
else
    ui_kv "Kit" "v$VERSION"
    ui_kv "Configs" "projects.conf and opencode.jsonc untouched"
fi
[ "$BINARY_UPDATE" = true ] || ui_kv "Binary" "untouched (use --binary to upgrade)"
ui_info "Next:"
ui_detail "opk status   verify the protection"
ui_detail "opk upgrade-opencode    upgrade the opencode binary"
log "update complete (version $VERSION)"
