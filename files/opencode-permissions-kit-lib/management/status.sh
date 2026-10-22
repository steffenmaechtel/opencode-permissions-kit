#!/bin/sh
# opencode permissions kit -- status.sh
# Prints the current protection status. Works whether or not the kit is
# installed, and does not require root. Run directly:
#   /usr/local/lib/opencode-permissions-kit/management/status.sh
# or from a checkout:
#   files/opencode-permissions-kit-lib/management/status.sh
# Deliberately set -u ONLY (no -e/pipefail): status is a read-only report —
# one failing probe must not kill the remaining sections; failures render
# as "unknown" rows instead (same fail-soft class as uninstall.sh).
#
# CLI (issue #158): --short/-s prints only the final verdict line and
# carries it in the exit code (0 all green, 1 alert(s), 2 warning(s)
# only, 64 usage error) — cron/timer friendly.
set -u

# --- CLI (issue #158) ------------------------------------------------------------
# --short/-s: one verdict line. UI_SILENT mutes the ui.sh printers while
# the severity counters keep counting; the verdict line prints at the
# very end (UI_SILENT off again). Usage errors exit 64 (EX_USAGE) so
# they never collide with the verdict codes 1/2.
STATUS_SHORT=false
for _st_arg in "$@"; do
    case "$_st_arg" in
        --short|-s) STATUS_SHORT=true ;;
        *)
            echo "usage: sh $(basename "$0") [--short]" >&2
            exit 64
            ;;
    esac
done
if [ "$STATUS_SHORT" = true ]; then
    UI_SILENT=1
fi

LIBDIR="/usr/local/lib/opencode-permissions-kit"
INSTALL_CONF="/etc/opencode-permissions-kit/install.conf"
PROJECTS_CONF="/etc/opencode-permissions-kit/projects.conf"

# Shared UI helpers (checkout-first, 0.0.46a F4 pattern like ddev-handover
# below): the checkout's status.sh needs its OWN ui.sh — the deployed one
# can predate ui_kv_ok/ui_kv_bad (issue #158) and would drop those rows.
# A deployed run resolves to the identical file anyway.
UI_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/ui.sh"
[ -f "$UI_LIB" ] || UI_LIB="/usr/local/lib/opencode-permissions-kit/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    # shellcheck disable=SC1090
    . "$UI_LIB"
else
    echo "error: ui.sh not found (expected $LIBDIR/sh/ui.sh or next to status.sh in a checkout)" >&2
    exit 1
fi

# Shared git check (issue #118): the soft tested floor for the Core row.
# Checkout-first for the same reason as ui.sh above: an older deployed
# git-check.sh would render its row via plain ui_kv and the summary
# (issue #158) would not count it.
# Missing-lib behavior (issue #165, #199 a W3): the old fail-soft
# contract ("a missing helper just drops the row") is retired — on a
# deployed run both resolution candidates are the same path, so a
# missing file is a broken kit; the call site below renders a counted
# warn row instead of silently dropping the Core git row.
GIT_CHECK_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/git-check.sh"
[ -f "$GIT_CHECK_LIB" ] || GIT_CHECK_LIB="$LIBDIR/sh/git-check.sh"
if [ -f "$GIT_CHECK_LIB" ]; then
    # shellcheck disable=SC1090
    . "$GIT_CHECK_LIB"
fi

VERSION="0.0.0"
DEFAULT_USER=""
OPENCODE_USER="opencode"
OPENCODE_GROUP=""
if [ -f "$INSTALL_CONF" ]; then
    # shellcheck disable=SC1090
    . "$INSTALL_CONF"
fi
# Sharing group: the opencode user's own usergroup; prefer the live value.
OPENCODE_GROUP="${OPENCODE_GROUP:-opencode}"
LIVE_GROUP="$(id -gn "$OPENCODE_USER" 2>/dev/null || true)"
[ -n "$LIVE_GROUP" ] && OPENCODE_GROUP="$LIVE_GROUP"

# installed = the wrapper is active (user + wrapper + library present)
installed=false
if id "$OPENCODE_USER" >/dev/null 2>&1 && [ -x "$LIBDIR/bin/opencode-as-opencode" ] \
    && [ -L /usr/local/bin/opencode ]; then
    installed=true
fi

ui_banner "$VERSION" "protection status"

if [ "$installed" = false ]; then
    if [ "$STATUS_SHORT" = true ]; then
        # Machine mode: one line, verdict in the exit code — "not
        # installed" is the loudest not-green state there is.
        echo "not installed — hardening NOT active (run 'opk status' for the full report)"
        exit 1
    fi
    ui_warn "Hardening NOT active."
    echo ""
    ui_info "Install it with:"
    ui_detail "curl -fsSL https://raw.githubusercontent.com/steffenmaechtel"\
"/opencode-permissions-kit/stable/files/install.sh | sudo env KIT_BRANCH=stable bash"
    echo ""
    # Full mode keeps exit 0 here on purpose: status.sh is a diagnostic
    # that must not "fail" for reporting absence (the summary's exit
    # codes apply to installed reports; --short reports this state as 1).
    exit 0
fi

# --- live progress for the project-root scans (issue #210) ------------------------
# The ddev share scan and the Windows hosts scan below walk every
# registered project root with find — on WSL with many git projects and
# a cold page cache that runs minutes in complete silence right after
# the "ddev settings" row (issue #210). Same live-counter pattern as
# the group baseline's _fsb_count_tee (issue #14, sh/fs-baseline.sh),
# tuned for a report: the tee sits IN the find pipeline (it starts and
# dies with the stream — no background process that could outlive a
# killed status run), rewrites "<label> — N found, M:SS" on stderr
# once a second and ERASES the line at EOF, so the report surface
# itself stays byte-identical. Only an interactive terminal sees
# movement; piped, --short (UI_SILENT) and python3-less runs keep the
# exact output of the bare find.

_st_progress_tee() {
    # _st_progress_tee <label>: NUL-separated stdin -> stdout VERBATIM
    # (a progress display must never corrupt the scan it reports on),
    # plus — when stderr is a tty — a line "<label> — N found, M:SS"
    # rewritten once a second and erased at EOF. Pipeline member like
    # _fsb_count_tee: terminates with the stream. stderr is written as
    # raw UTF-8 bytes — a non-UTF-8 terminal shows mojibake that the
    # next frame or the erase self-heals, and undecodable argv bytes
    # degrade to "?"; never a traceback (#221 a W10).
    # read1, not read (#221 a W1): a full-buffer read waits for 1 MiB
    # or EOF, and real scans stream kilobytes — every frame said
    # "0 found" for the whole walk. read1 returns what is available.
    # Event, not bool+sleep (#221 a W2): join() waited out the in-flight
    # sleep(1) — up to +1 s dead time per scan on every terminal run;
    # wait(1) wakes on set(). KeyboardInterrupt is swallowed with
    # BrokenPipeError (#221 a W6): Ctrl-C must stay as silent as the
    # bare find it replaced (rc of a pipeline member is discarded —
    # status.sh runs without pipefail). Pinned: the SIGINT pin in
    # tests/unit/test-status.sh (#221 b W1) kills the tee's python3
    # mid-stream and asserts zero stderr and a clean exit.
    python3 -c '
import sys, threading, time
label = sys.argv[1]
count = 0
start = time.monotonic()
done = threading.Event()

def out(text):
    sys.stderr.buffer.write(text.encode("utf-8", "replace"))
    sys.stderr.flush()

def draw():
    if not sys.stderr.isatty():
        return
    el = int(time.monotonic() - start)
    line = "  %s — %d found, %d:%02d" % (label, count, el // 60, el % 60)
    if len(line) > 76:
        line = "  …" + line[-73:]
    out("\r%-76s" % line)

def ticker():
    while not done.is_set():
        draw()
        done.wait(1)

draw()  # first frame at once: a slow walk with zero hits still shows life
t = threading.Thread(target=ticker)
t.start()
try:
    while True:
        chunk = sys.stdin.buffer.read1(1 << 20)
        if not chunk:
            break
        count += chunk.count(b"\0")
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
except (BrokenPipeError, KeyboardInterrupt):
    pass
finally:
    done.set()
    t.join()
    if sys.stderr.isatty():
        out("\r" + " " * 76 + "\r")
' "$1"
}

_st_ddev_scan() {
    # _st_ddev_scan <label> <root> <outfile>: every .ddev directory
    # under <root>, one path per line, into <outfile> — with the live
    # progress above on a terminal, and silently otherwise (UI_SILENT,
    # non-tty stderr, or no python3: the scan never depends on its
    # progress display). Same prune rules the handover scan set (issues
    # #21, #29, #112, #94/#149): vendor/, node_modules/, testdata/ and
    # .git/ trees are fixtures or dense non-projects — .git additionally
    # the densest tree in a project, pruned for scan cost too.
    _sts_label="$1"; _sts_root="$2"; _sts_out="$3"
    _sts_expr='-type d ( -name vendor -o -name node_modules -o -name testdata -o -name .git )'
    _sts_expr="$_sts_expr -prune -o -type d -name .ddev -prune"
    # Progress only on an interactive terminal. The python3 check is a
    # HEALTH probe, not just presence (#221 a W3): `command -v` alone
    # accepts a findable-but-broken interpreter (pyenv shim to a removed
    # version, poisoned PYTHONHOME/PYTHONPATH) — the tee would die at
    # startup and hand the consumer loop an EMPTY scan list, a silent
    # false-green over a dead scan. Probed once per run (_st_py_checked
    # caches, _st_py_ok carries the verdict), and only on the tty path —
    # piped/--short runs never start python3.
    _sts_progress=false
    if [ "${UI_SILENT:-0}" != 1 ] && [ -t 2 ] && [ "${_st_py_checked:-0}" != 1 ]; then
        _st_py_checked=1
        _st_py_ok=0
        command -v python3 >/dev/null 2>&1 \
            && python3 -c 'import sys, threading, time' >/dev/null 2>&1 \
            && _st_py_ok=1
    fi
    [ "${UI_SILENT:-0}" != 1 ] && [ -t 2 ] && [ "${_st_py_ok:-0}" = 1 ] && _sts_progress=true
    if [ "$_sts_progress" = true ]; then
        # shellcheck disable=SC2086  # find expression words, built above
        find "$_sts_root" $_sts_expr -print0 2>/dev/null \
            | _st_progress_tee "$_sts_label" \
            | tr '\0' '\n' > "$_sts_out"
    else
        # shellcheck disable=SC2086  # find expression words, built above
        find "$_sts_root" $_sts_expr -print0 2>/dev/null \
            | tr '\0' '\n' > "$_sts_out"
    fi
    return 0
}

# === Core ======================================================================

ui_section "Core"

ui_kv_ok "Mode"     "dedicated user (soft permissions only)"
# Channel stamp (issue #38): the ref installs/updates track. Unstamped =
# installed before the beta channel split — such installs update from
# 'master' until their next opk update re-stamps it.
if [ -n "${KIT_CHANNEL:-}" ]; then
    ui_kv "Channel"  "$KIT_CHANNEL"
else
    ui_kv "Channel"  "master (unstamped — pre-beta install, opk update re-stamps it)"
fi
if id "$OPENCODE_USER" >/dev/null 2>&1; then
    ui_kv "User"  "$OPENCODE_USER — exists"
else
    ui_kv_bad "User"  "$OPENCODE_USER — MISSING"
fi
ui_kv "Wrapper"  "/usr/local/bin/opencode -> $(readlink /usr/local/bin/opencode 2>/dev/null || echo missing)"
ui_kv "Library"  "$LIBDIR"
_occonf="$(ls /home/$OPENCODE_USER/.config/opencode/opencode.jsonc 2>/dev/null \
    || ls /home/$OPENCODE_USER/.config/opencode/opencode.json 2>/dev/null || echo "")"
if [ -n "$_occonf" ]; then
    ui_kv "Config" "$_occonf"
else
    ui_kv_warn "Config" "none"
fi
ui_kv "Sharing"  "group '$OPENCODE_GROUP' (default user: ${DEFAULT_USER:-unknown})"

# OpenChamber state (issue #154, internal/records/openchamber-2x-hardening.md):
# policy pin on the wrapper => secured (leftovers inert); no policy but
# OpenChamber present => advice; bypass files (self-installed binaries,
# settings pin) without the policy => BYPASSED — binaries only count as a
# bypass when OpenChamber is actually installed (0.0.47a F4), and a symlink
# to the kit wrapper is never a bypass binary (wrapper guard semantics,
# 0.0.47a F3). Evaluated for the default user — the kit's model has exactly
# one developer.
_oc_policy="/etc/openchamber/policy.json"
_oc_secured=false
if [ -f "$_oc_policy" ] \
    && [ "$(sed -n 's/.*"opencodeBinary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$_oc_policy" 2>/dev/null | tail -n 1)" = "/usr/local/bin/opencode" ]; then
    _oc_secured=true
fi
# Home via getent, /home/<user> only as fallback (0.0.47b W2, the
# 0.0.43a F12 class — relocated homes must not blank the verdicts).
# Empty-default chain (#211 a F9): under set -u, ${DEFAULT_USER:-$USER}
# aborted with rc 2 when BOTH were unset (cron/timer env + conf without
# the stamp) — colliding with the "2 = warnings only" verdict contract.
_oc_home=$(getent passwd "${DEFAULT_USER:-${USER:-}}" 2>/dev/null | cut -d: -f6 || true)
_oc_home="${_oc_home:-/home/${DEFAULT_USER:-${USER:-}}}"
_oc_kit_wrapper="/usr/local/lib/opencode-permissions-kit/bin/opencode-as-opencode"
_oc_bins=""
for _ocn in opencode opencode2; do
    _ocp="$_oc_home/.opencode/bin/$_ocn"
    if [ -e "$_ocp" ] && { [ ! -L "$_ocp" ] \
        || [ "$(readlink -f "$_ocp" 2>/dev/null || echo "$_ocp")" != "$_oc_kit_wrapper" ]; }; then
        _oc_bins="$_oc_bins ~/.opencode/bin/$_ocn"
    fi
done
_oc_pin=""
if [ -f "$_oc_home/.config/openchamber/settings.json" ]; then
    _oc_pin=$(sed -n 's/.*"opencodeBinary"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        "$_oc_home/.config/openchamber/settings.json" 2>/dev/null | tail -n 1)
    if [ -z "$_oc_pin" ] || [ "$_oc_pin" = "/usr/local/bin/opencode" ]; then
        _oc_pin=""
    fi
fi
# OpenChamber installed at all? (command or config dir — the installation
# markers; without them, binaries are the classic installer shadow)
_oc_present=false
command -v openchamber >/dev/null 2>&1 && _oc_present=true
[ -d "$_oc_home/.config/openchamber" ] && _oc_present=true
if command -v openchamber >/dev/null 2>&1 || [ -n "$_oc_bins" ] || [ -n "$_oc_pin" ] \
    || [ -d "$_oc_home/.config/openchamber" ] || [ "$_oc_secured" = true ]; then
    if [ "$_oc_secured" = true ]; then
        if [ -n "$_oc_bins" ] || [ -n "$_oc_pin" ]; then
            ui_kv_ok "OpenChamber" "secured via policy pin (leftover bypass files present — inert)"
        else
            ui_kv_ok "OpenChamber" "secured via policy pin (/etc/openchamber/policy.json)"
        fi
    elif [ -n "$_oc_pin" ] || { [ -n "$_oc_bins" ] && [ "$_oc_present" = true ]; }; then
        ui_kv_bad "OpenChamber" "BYPASSED — run 'sudo opk openchamber-secure'"
    elif [ -n "$_oc_bins" ]; then
        ui_kv_warn "OpenChamber" "not installed — self-installed opencode present:$_oc_bins (remove it)"
    else
        ui_kv_warn "OpenChamber" "installed, policy pin missing — 'sudo opk openchamber-secure'"
    fi
fi

f="/home/$OPENCODE_USER/.config/opencode/opencode.jsonc"
[ -f "$f" ] || f="/home/$OPENCODE_USER/.config/opencode/opencode.json"
if [ -f "$f" ]; then
    # Wording (issue #158): ON/OFF said nothing about who may do what.
    # ON  = the deny rules are active  -> agent tools never touch it.
    # OFF = a deliberate config choice -> agent tools may edit it
    #       (kept NEUTRAL: a conscious decision is a hint, not a warning).
    # Markers left over (old kit version, hand edit) are NOT a deliberate
    # choice — same neutral row plus the hint line git-config status
    # shows (issue #205: both outputs agree on all three shapes).
    if grep -qE '^[[:space:]]*"\.git/config"' "$f" 2>/dev/null; then
        ui_kv_ok ".git/config" "protected (soft-only — agent tools blocked)"
    elif grep -q '//SECURE_GIT' "$f" 2>/dev/null; then
        ui_kv ".git/config" "access allowed (agent tools may edit git config)"
        ui_detail "$f (markers present, rules inactive)"
    else
        ui_kv ".git/config" "access allowed (agent tools may edit git config)"
    fi
fi

# Host git against the soft tested floor (issue #118): advisory row,
# same source as the install/update warning (sh/git-check.sh).
# Missing-lib fallback (issue #165, #199 a W3): git_status_row is
# undefined when neither the checkout nor the deployed sh/git-check.sh
# delivered it — a broken kit, not an optional feature. Counted warn
# row instead of the old noop stub: the verdict must never stay green
# over a Core check that never ran.
if command -v git_status_row >/dev/null 2>&1; then
    git_status_row
else
    ui_kv_warn "git" "not checked — kit file sh/git-check.sh missing or outdated (fix: sudo opk update)"
fi

# === Security advisories (issue #107) ============================================
# Two sources, two jobs: the SHIPPED database (sh/advisories.sh) is the
# curated truth — channel-qualified, ranges refined to the patched
# version — and the only source that claims "affected". The UPSTREAM feed
# (GitHub, live) is the freshness signal: an advisory upstream that the
# shipped database lacks means the kit release lags, not that this
# install is affected (upstream ranges are channel-blind — a npm-only
# advisory ranges over standalone versions too). The kit installs the
# binary itself, so its install channel is always 'standalone'.
# Missing-lib fallback (issue #165): the guard below must degrade LOUDLY,
# not silently — a missing advisories database means a damaged or partially
# deployed sh/ tree (a broken kit, not an optional feature), and the C1/D1
# managed-binary gates live inside the guarded block. A counted warn row
# instead of a vanished section: the verdict can never stay green over
# security checks that never ran.
if [ ! -f "$LIBDIR/sh/advisories.sh" ]; then
    ui_section "Security advisories"
    ui_kv_warn "advisories database" "missing — security checks skipped (fix: sudo opk update)"
fi
if [ -f "$LIBDIR/sh/advisories.sh" ]; then
    # shellcheck disable=SC1090
    . "$LIBDIR/sh/advisories.sh"
    # Shared never-shadow probe for the xdg-open verdict (0.0.42d S1/C1):
    # optional like the other libs — a missing lib degrades the verdict
    # to the red "missing" branch, never to a false green.
    if [ -f "$LIBDIR/sh/wsl-browser-bridge.sh" ]; then
        # shellcheck disable=SC1090
        . "$LIBDIR/sh/wsl-browser-bridge.sh"
    fi
    ui_section "Security advisories"
    # Installed version: probed fresh through the kit's sudo path (same
    # BOUNDED pattern as the wrapper's check — 0.0.43b W3: a wedged 2.x
    # service can make even --version hang, issue #80, and opk status is
    # the diagnostic for exactly that state; the install.conf stamp would
    # go stale the moment a binary is swapped outside opk). sudo -n never
    # prompts: root needs no password, the developer rides the kit's
    # NOPASSWD rule, anyone else just sees "unknown".
    ADV_VER=""
    # 0.0.48c C1, re-scoped by issue #166: a managed binary NO ONE can
    # execute is a BROKEN KIT, not an unknown — the advisory check cannot
    # run, the wrapper would fail at the first agent session, and no
    # privilege resolves it (not even root: exec needs at least one x
    # bit). Counts; the privilege-unknown shape below does not. "No one"
    # is read from the MODE BITS, caller-independent: [ -x ] speaks for
    # THIS caller, and the deployed binary is 750 root:opencode — a
    # caller outside that audience fails [ -x ] over a healthy kit.
    # That shape is a privilege question (sudo resolves it), not a
    # finding; it falls through to the unknown row below.
    ADV_BIN_ANYX=false
    # stat -L -c %a: TARGET mode bits, octal (GNU coreutils; the kit is
    # Linux/WSL only). -L dereferences (#200 a W1): without it stat
    # reports a symlink's constant 777, so a dangling link or a no-x
    # target reads any-x — silently downgrading a broken kit to the
    # uncounted unknown row. Absent file, dangling symlink, or a stat
    # that cannot answer: empty stays false — the loud direction (a
    # broken kit must not read green). Pure case patterns, no
    # arithmetic: dash has no base#n ($((8#750)) is bash-only), and an
    # octal digit carries the execute bit exactly when it is ODD
    # (1=x 3=wx 5=rx 7=rwx) in one of the
    # last three positions — owner, group, other. The special digit
    # (setuid/setgid/sticky, a 4-digit mode) grants nothing without an
    # x bit and is deliberately not counted.
    ADV_BIN_MODE="$(stat -L -c '%a' "$LIBDIR/bin/opencode" 2>/dev/null || true)"
    case "$ADV_BIN_MODE" in
        *[!0-7]*|'') ;;
        *[1357]|*[1357]?|*[1357]??) ADV_BIN_ANYX=true ;;
    esac
    if [ "$ADV_BIN_ANYX" != true ]; then
        # 0.0.49a W1: upgrade-opencode, not plain update — a plain
        # `opk update` never touches the managed binary (BINARY_UPDATE
        # is opt-in; the deploy manifest ships no bin/opencode), so the
        # old advice dead-ended while update reported success over the
        # broken kit. upgrade-opencode reinstalls in both shapes
        # (missing and corrupt: the major resolves through the
        # install.conf stamp when the probe is empty).
        ui_kv_warn "opencode binary" "missing or not executable — advisory check skipped (fix: sudo opk upgrade-opencode)"
    elif command -v sudo >/dev/null 2>&1; then
        if command -v timeout >/dev/null 2>&1; then
            ADV_VER=$(timeout 10 sudo -n -u "$OPENCODE_USER" "$LIBDIR/bin/opencode" --version 2>/dev/null \
    | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        else
            ADV_VER=$(sudo -n -u "$OPENCODE_USER" "$LIBDIR/bin/opencode" --version 2>/dev/null \
    | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        fi
    fi
    # Issue #201: a caller who can exec the binary directly already
    # holds what the sudo probe could not get — the deployed shape is
    # 750 root:opencode, so root, the sharing group and the agent user
    # (primary group opencode) all pass [ -x ], and --version answers
    # the same version for every one of them (one binary file). #163
    # ran exactly this probe to split corrupt from healthy but
    # DISCARDED the stdout it then reported as "unknown", advising
    # "sudo opk status" — a dead end for a group member without sudo
    # rights (the kit's NOPASSWD rules cover only the developer) over
    # a kit that needs no repair. Capture the output and feed it
    # through the same strict extract as the sudo path: the advisory
    # verdict and every ADV_VER consumer (the browser-bridge row
    # below) then answer at this caller's own privilege. Counting
    # follows the answer, not the caller — a version known at ANY
    # privilege is a real verdict (0.0.48b W3's uncounted rule covers
    # unknowns, and only those stay uncounted). Do NOT infer anything
    # from a failed sudo exit code — sudo -n collapses "refused" and
    # "password required" into rc 1 — the direct probe's own rc is
    # the reliable signal already in hand (bounded like every probe,
    # issue #80).
    ADV_DIRECT_OUT=""
    ADV_DIRECT_RC=""
    if [ -z "$ADV_VER" ] && [ -x "$LIBDIR/bin/opencode" ]; then
        ADV_DIRECT_RC=0
        if command -v timeout >/dev/null 2>&1; then
            ADV_DIRECT_OUT=$(timeout 10 "$LIBDIR/bin/opencode" --version 2>/dev/null) \
                || ADV_DIRECT_RC=$?
        else
            ADV_DIRECT_OUT=$("$LIBDIR/bin/opencode" --version 2>/dev/null) \
                || ADV_DIRECT_RC=$?
        fi
        if [ "$ADV_DIRECT_RC" = 0 ] && [ -n "$ADV_DIRECT_OUT" ]; then
            ADV_VER=$(printf '%s\n' "$ADV_DIRECT_OUT" \
    | grep -m1 -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        fi
    fi
    if [ -n "$ADV_VER" ]; then
        ADV_HITS=$(advisories_matching opencode "$ADV_VER" standalone || true)
        if [ -n "$ADV_HITS" ]; then
            ui_kv_bad "opencode $ADV_VER" "AFFECTED by a known advisory — upgrade now"
            while IFS= read -r ADV_LINE; do
                IFS='|' read -r ADV_PKG ADV_RANGES ADV_PATCHED ADV_CHANNEL ADV_SEV ADV_ID ADV_SUMMARY <<EOF
$ADV_LINE
EOF
                ui_detail "$ADV_ID ($ADV_SEV): $ADV_SUMMARY"
                [ -n "$ADV_PATCHED" ] && ui_detail "patched in: opencode $ADV_PATCHED"
            done <<EOF
$ADV_HITS
EOF
            ui_detail "fix: opk upgrade-opencode"
        else
            ui_kv_ok "opencode $ADV_VER" "no known advisory affects this install (kit $VERSION database)"
        fi
    elif [ -n "${ADV_DIRECT_RC:-}" ] && [ "${ADV_DIRECT_RC:-}" != 0 ]; then
        # Issue #163 (the probe itself moved ahead of this render by
        # #201, which needs its output before the matching): exec-ability
        # is caller-independent — a truncated or wrong-arch binary fails
        # for every user the mode bits admit, while a healthy --version
        # exits 0 for any of them (the kit's own runnability criterion,
        # update.sh's candidate check) — so a non-zero direct rc is a
        # BROKEN binary, not a privilege gap; no sudo resolves it.
        # 0.0.49a W1: the repair command is upgrade-opencode (the
        # AFFECTED row's precedent) — plain update cannot fix this.
        ui_kv_warn "opencode binary" "present but broken — direct probe exited rc $ADV_DIRECT_RC"\
" (fix: sudo opk upgrade-opencode)"
    elif [ "${ADV_DIRECT_RC:-}" = 0 ]; then
        # Issue #201: the binary ran (rc 0) but --version carried no
        # parsable version. Still not a finding (0.0.48b W3 — an
        # agent-user or dev cron must not be permanently non-green),
        # and the old "sudo opk status" advice would dead-end twice
        # over: this caller may hold no sudo rights, and sudo would
        # exec the same binary to the same unparsable answer.
        ui_kv "opencode version" "unknown — binary runs for this caller, --version carries no parsable version"
    elif [ "$ADV_BIN_ANYX" = true ]; then
        # Issue #166: the mode bits promise an audience (root / the
        # opencode group) can execute it — THIS caller cannot. A
        # privilege question, not a finding: sudo renders the verdict,
        # and the corrupt-vs-healthy split (#163) is root's to judge —
        # classifying requires exec'ing it, which this caller lacks.
        # Uncounted (W3's reasoning: a caller outside the audience must
        # not read red over a healthy kit); the counted warn stays for
        # the shapes no privilege resolves (missing / no x bit /
        # corrupt).
        ui_kv "opencode version" "unknown — probe failed (run: sudo opk status)"
    fi
    # Upstream freshness (live, best-effort): GitHub's advisory feed vs
    # the ids the shipped database knows. Never decides affectedness.
    # python3 is required to parse the feed — without it (or offline)
    # the live check reports "unavailable", never a false "ok".
    if command -v curl >/dev/null 2>&1; then
        ADV_FEED=""
        ADV_FEED=$(curl -fsSL --max-time 10 \
    "https://api.github.com/repos/anomalyco/opencode/security-advisories" 2>/dev/null || true)
        ADV_PARSE_OK=false
        ADV_NEW=""
        if [ -n "$ADV_FEED" ] && command -v python3 >/dev/null 2>&1; then
            # advisory ids from the feed (ghsa_id per entry); exit 1 on
            # anything that is not JSON — an unparseable feed is
            # "unavailable", not "no advisories".
            if ADV_IDS=$(printf '%s' "$ADV_FEED" | python3 -c 'import json,sys
try:
    feed = json.load(sys.stdin)
except Exception:
    sys.exit(1)
for entry in feed or []:
    # str(... or ""): a JSON null defeats the .get default (the F7
    # class, 0.0.44a V19 — advisory-watch got the coercion in 0.0.43a;
    # this twin printed the literal string "None").
    print(str(entry.get("ghsa_id") or ""))' 2>/dev/null); then
                ADV_PARSE_OK=true
                ADV_KNOWN=$(advisories_ids opencode || true)
                while IFS= read -r ADV_ID; do
                    [ -n "$ADV_ID" ] || continue
                    printf '%s\n' "$ADV_KNOWN" | grep -qxF "$ADV_ID" && continue
                    ADV_NEW="$ADV_NEW $ADV_ID"
                done <<EOF
$ADV_IDS
EOF
            fi
        fi
        if [ -n "$ADV_NEW" ]; then
            ui_kv_warn "upstream" "new advisory(ies) upstream, not yet in this kit:$ADV_NEW"
            ui_detail "the database travels with kit releases — run: sudo opk update"
            ui_detail "(already current? the entry is being curated — see the upstream advisory page)"
        elif [ "$ADV_PARSE_OK" = true ]; then
            ui_kv_ok "upstream" "live check ok — nothing beyond the shipped database"
        else
            # Uncounted by design (0.0.48b W3, #211 a F8): the caller
            # cannot judge this row (offline, blocked, python3 missing) —
            # a counted warn made every air-gapped/proxied host exit 2
            # forever, which is exactly the "green unattainable, cron
            # alert worthless" case the rule names. Real findings (new
            # advisories, the arm above) stay counted warns.
            ui_kv "upstream" "unknown — live check unavailable (offline, blocked, or python3 missing)"
        fi
    fi
fi

# === Projects ==================================================================

# _st_ancestor_grants_x <dir>: does <dir> let the agent side traverse it?
# Looser than the grant-side check in fs-baseline.sh on purpose
# (report-only): other-x, group-x when the dir's group is the sharing
# group, or ANY named user/group ACL entry with x (the kit only ever
# writes group:<group> entries; a foreign named entry is almost
# certainly a manual traversal fix). Mask reduction is ignored — the
# warning would only be a false negative then.
_st_ancestor_grants_x() {
    _stx_mode=$(stat -c %A "$1" 2>/dev/null) || return 1
    # other x: literal x or the sticky form t (/tmp); group x: literal x
    # or the setgid form s (the kit's own 2775 dirs).
    case "$_stx_mode" in
        ?????????x|?????????t) return 0 ;;
    esac
    getfacl -p "$1" 2>/dev/null | grep -qE '^(user|group):[^:]+:..x' && return 0
    if [ "$(stat -c %G "$1" 2>/dev/null)" = "$OPENCODE_GROUP" ]; then
        case "$_stx_mode" in ??????x???|??????s???) return 0 ;; esac
    fi
    return 1
}

# _st_root_blocker <root>: echoes the first ancestor that blocks
# traversal to <root> (empty when the whole chain is passable).
_st_root_blocker() {
    _str_d=$(dirname "$1")
    while [ -n "$_str_d" ] && [ "$_str_d" != "/" ]; do
        if ! _st_ancestor_grants_x "$_str_d"; then
            echo "$_str_d"
            return 0
        fi
        # Fixed-point guard: a relative root would spin dirname on "."
        # forever (0.0.38 C13) — stop when dirname stops making progress.
        _str_next=$(dirname "$_str_d")
        [ "$_str_next" = "$_str_d" ] && break
        _str_d=$_str_next
    done
    return 0
}

# Count robustly (0.0.43a F8): `grep -c .` on an EMPTY file prints 0 AND
# exits 1 — a bare `|| echo 0` appends a second 0 and the captured
# "0<newline>0" breaks the header across lines. || true keeps the printed
# 0; the default covers a missing file (grep prints nothing, exits 2).
_st_pc=$(grep -c . "$PROJECTS_CONF" 2>/dev/null || true)
: "${_st_pc:=0}"
ui_section "Projects ($_st_pc)"

if [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
    while IFS= read -r root; do
        [ -z "$root" ] && continue
        [ -d "$root" ] || { ui_miss "$root" "directory missing"; continue; }
        # setgid on the root is what keeps new files in the sharing group
        root_mode=$(stat -c %a "$root" 2>/dev/null || echo "?")
        if [ "$root_mode" = "?" ]; then
            ui_atten "$root" "mode unreadable (stat failed) — run config.sh refresh"
        elif [ $((0${root_mode} & 02000)) -ne 0 ]; then
            ui_have "$root" "setgid ($root_mode) + ACLs"
        else
            ui_atten "$root" "missing setgid bit — run config.sh refresh"
        fi
        # Ancestor traversal: the baseline fixes the root DOWN, but a
        # blocked ancestor (0750 developer home) keeps the agent from
        # reaching the root at all (EACCES; ddev then claims "a project
        # cannot be created in the DDEV source code").
        _st_block=$(_st_root_blocker "$root")
        if [ -n "$_st_block" ]; then
            ui_atten "$root" "unreachable for $OPENCODE_USER — $_st_block blocks traversal"\
" (fix: sudo opk config refresh)"
        fi
    done < "$PROJECTS_CONF"
else
    ui_atten "(none configured)" "run config.sh projects add <path>"
fi

# === Container backend ===========================================================

ui_section "Container backend"

case "${CONTAINER_BACKEND:-}" in
    docker-rootless)
        ui_kv_ok "backend" "docker-rootless"
        sock="${OPENCODE_DOCKER_HOST:-}"
        sockpath="$sock"
        case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
        # The opencode user's runtime dir (/run/user/<uid>) is mode 700
        # opencode:opencode, so a non-root status.sh caller cannot stat the
        # socket inside it. Direct stat first; then sudo -n (non-interactive
        # — status.sh must never prompt for a password); when both fail but
        # the runtime dir exists and is NOT traversable by the caller, the
        # state is UNKNOWN, not broken (same wording pattern as the mkcert
        # CA check below — a red "NOT reachable" made users think the
        # daemon was down). A traversable dir without a socket stays red.
        if [ -n "$sock" ]; then
            if [ -S "$sockpath" ] 2>/dev/null || sudo -n test -S "$sockpath" 2>/dev/null; then
                ui_kv_ok "socket" "reachable — $sock"
            elif [ -d "$(dirname "$sockpath")" ] && [ ! -x "$(dirname "$sockpath")" ]; then
                ui_kv "socket" "unknown — needs root to check (run: sudo opk status)"
            else
                ui_kv_bad "socket" "NOT reachable — $sock"
            fi
        else
            ui_kv_warn "socket" "not configured"
        fi
        # linger is best-effort: loginctl may need auth, ignore errors.
        if command -v loginctl >/dev/null 2>&1; then
            linger=$(loginctl show-user "$OPENCODE_USER" 2>/dev/null | sed -n 's/^Linger=//p')
            [ -n "$linger" ] && ui_kv "linger" "$linger"
        fi
        ;;
    podman-rootless)
        ui_kv_ok "backend" "podman-rootless"
        sock="${OPENCODE_PODMAN_SOCKET:-}"
        if [ -n "$sock" ]; then
            # Optional podman docker-CLI-compat socket (see docker-rootless
            # branch for the probe rationale).
            sockpath="$sock"
            case "$sockpath" in unix://*) sockpath="${sockpath#unix://}";; esac
            if [ -S "$sockpath" ] 2>/dev/null || sudo -n test -S "$sockpath" 2>/dev/null; then
                ui_kv_ok "socket" "reachable — $sock"
            elif [ -d "$(dirname "$sockpath")" ] && [ ! -x "$(dirname "$sockpath")" ]; then
                ui_kv "socket" "unknown — needs root to check (run: sudo opk status)"
            else
                ui_kv_bad "socket" "NOT reachable — $sock"
            fi
        elif command -v podman >/dev/null 2>&1; then
            # Daemonless podman-CLI path (no socket needed, §9.8).
            pver=$(podman --version 2>/dev/null | sed -n 's/.*version \([0-9][0-9.]*\).*/\1/p' | head -1)
            ui_kv_ok "podman CLI" "installed${pver:+  ($pver)}"
        else
            ui_kv_bad "podman CLI" "NOT installed"
        fi
        ;;
    *)
        ui_kv_bad "backend" "unknown ('${CONTAINER_BACKEND:-none}')"
        ui_detail "re-run install.sh with a rootless backend:"
        ui_detail "sudo bash files/install.sh --container-backend docker-rootless|podman-rootless"
        ;;
esac

# === ddev runtime ================================================================

ui_section "ddev runtime (as user $OPENCODE_USER)"

if [ -d "/home/$OPENCODE_USER/.ddev" ]; then
    ui_kv_ok "ddev home" "present — /home/$OPENCODE_USER/.ddev"
else
    ui_kv_warn "ddev home" "missing — created by install.sh / update.sh"
fi
# ddev always runs as the opencode user: the sudoers helper + the shell
# function hooked into the default user's rc files.
if [ -x "$LIBDIR/bin/ddev-as-opencode" ]; then
    ui_kv_ok "helper" "deployed — $LIBDIR/bin/ddev-as-opencode"
else
    ui_kv_warn "helper" "missing — run opk update to deploy"
fi
# ddev() hook row (issue #192): the developer home comes from getent —
# a hardcoded /home/$DEFAULT_USER missed relocated homes and, on the
# root-shell installs the installer now refuses, looked in /home/root
# (never exists): the row degraded to a permanent "not hooked — run opk
# update" warning that opk update could not heal. A uid-0 developer is
# reported as the install defect it is, with the reinstall fix.
if [ -n "$DEFAULT_USER" ] && [ -f "$LIBDIR/sh/ddev-terminal.sh" ]; then
    _st_dev_uid="$(id -u "$DEFAULT_USER" 2>/dev/null || echo 1)"
    _st_home="$(getent passwd "$DEFAULT_USER" 2>/dev/null | cut -d: -f6 || true)"
    [ -n "$_st_home" ] || _st_home="/home/$DEFAULT_USER"
    if [ "$_st_dev_uid" = "0" ]; then
        ui_kv_warn "ddev() hook" "install broken — developer '$DEFAULT_USER' has uid 0"
        ui_detail "the install ran from a root shell (issue #192); reinstall from your"
        ui_detail "normal user — opk update cannot fix this"
    else
        hooked=""
        for cf in "$_st_home/.bashrc" "$_st_home/.zshrc" "$_st_home/.profile"; do
            [ -f "$cf" ] && grep -q 'opencode-permissions-kit/sh/ddev-terminal.sh' "$cf" 2>/dev/null \
                && hooked="$cf" && break
        done
        if [ -n "$hooked" ]; then
            ui_kv_ok "ddev() hook" "active — $hooked"
        elif [ -d "$_st_home" ]; then
            ui_kv_warn "ddev() hook" "not hooked — run opk update"
        else
            ui_kv_warn "ddev() hook" "cannot check — home '$_st_home' of '$DEFAULT_USER' missing"
            ui_detail "if '$DEFAULT_USER' is not your user, the install is broken — reinstall it"
        fi
    fi
elif [ -n "$DEFAULT_USER" ]; then
    # Issue #165: the terminal-hook lib ships with the kit — a stamped
    # developer plus a missing lib is a damaged tree (broken kit), not an
    # unconfigured feature. Counted warn, never a silently skipped row;
    # the guard stays compound so an unstamped install stays row-free.
    ui_kv_warn "ddev() hook" "not checked — kit file sh/ddev-terminal.sh missing (fix: sudo opk update)"
fi
# Dev-owned mode (internal/records/ddev-dev-owned-projects.md): on = the kit
# writes disable_settings_management: true into projects' .ddev/config.yaml
# and keeps settings dirs + project root developer-owned; off = ddev
# manages settings (handover model). install.conf is world-readable.
_dv_stamp=$(sed -n 's/^DDEV_DEV_OWNED=//p' /etc/opencode-permissions-kit/install.conf 2>/dev/null | tail -1)
case "${_dv_stamp:-}" in
    true|TRUE|1|yes)
        ui_kv_ok "ddev settings" "dev-owned — kit writes disable_settings_management (permanent 2775/664)"
        ;;
    false|FALSE|0|no|"")
        ui_kv "ddev settings" "ddev-managed — handover model (config.sh ddev-settings on to switch)"
        ;;
esac
# Group-write gaps in .ddev trees (issue #94's edge case, issue #149
# finding 2): ddev's hardcoded 0755/0644 modes cap the ACL mask below
# g+w, and runs from AGENT sessions get none of the ddev() hook's
# automatic heals — the developer then fails `git pull` on .ddev/ content
# with "permission denied". Report-only detection per registered root,
# same prune rules as the handover scan (vendor/, node_modules/,
# testdata/ and .git/ trees are fixtures/dense, never projects).
# 0.0.46a F4: resolve the detection lib like ui.sh/git-check.sh above,
# but CHECKOUT-FIRST — a checkout status.sh must render its own
# detection even when the deployed kit is older and its lib still
# lacks ddev_reshare_needed (deployed-first would leave that case
# swallowed by the `|| continue` below); deployed mode resolves to the
# identical file anyway.
_st_dhl="$(cd "$(dirname "$0")" && pwd)/../sh/ddev-handover.sh"
[ -f "$_st_dhl" ] || _st_dhl="$LIBDIR/sh/ddev-handover.sh"
if [ -f "$_st_dhl" ] && [ "$(id -u)" != "$(id -u "$OPENCODE_USER" 2>/dev/null || echo 1)" ]; then
    # shellcheck disable=SC1090  # checkout or deployed lib, resolved above
    . "$_st_dhl"
    if [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
        while IFS= read -r _st_root; do
            [ -z "$_st_root" ] && continue
            [ -d "$_st_root" ] || continue
            # Findings print in the MAIN shell (issue #158): ui_kv_warn
            # inside a `find | while` pipeline would bump the summary's
            # severity counter inside the pipe's subshell, and the tally
            # would silently lose it. The find output goes to a temp
            # file; the reporting loop reads it via redirect.
            # 0.0.48b W2: mktemp failure skips the scan LOUDLY — the old
            # /dev/null fallback died silently (tally saw nothing, the
            # verdict could be "All green" over a dead scan) and its
            # cleanup rm -f'd the device node when root ran it.
            _st_share_list=$(mktemp) || _st_share_list=""
            if [ -z "$_st_share_list" ]; then
                ui_kv_warn "ddev share" "scan skipped for $_st_root — mktemp failed (check TMPDIR / /tmp)"
                continue
            fi
            # Live progress (issue #210): on a terminal the scan helper
            # streams a found-count + elapsed line while the walk runs —
            # minutes on a WSL host with many projects and a cold cache;
            # piped runs stay byte-identical to a bare find.
            _st_ddev_scan "ddev share: scanning $_st_root" "$_st_root" "$_st_share_list"
            while IFS= read -r _st_d; do
                ddev_reshare_needed "$_st_d" "$OPENCODE_USER" || continue
                ui_kv_warn "ddev share" "$(dirname "$_st_d")/.ddev: group-write missing (agent-side ddev run without the heal)"
                ui_detail "fix: a tree-creating ddev command (config/get/start/restart — your hook heals), or:"
                # Short form since issue #159 — the dispatcher's ensure-shared
                # subcommand wraps the sudo -u ddev-as-opencode heal.
                ui_detail "      opk ensure-shared \"$_st_d\""
            done < "$_st_share_list"
            rm -f "$_st_share_list"
        done < "$PROJECTS_CONF"
    fi
elif [ "$(id -u)" != "$(id -u "$OPENCODE_USER" 2>/dev/null || echo 1)" ]; then
    # Issue #165 (#199 a W1): same broken-kit class as the other lib
    # guards. Checkout-first covers version skew for checkout runs, but a
    # deployed run resolves both candidates to the same path — a
    # non-agent-uid run (developer or root via sudo, the row's two
    # realistic callers) with the detection lib gone is a damaged tree
    # and the resharde scan must not vanish silently behind its guard.
    # The guard stays compound so agent-uid runs stay row-free.
    ui_kv_warn "ddev share" "not checked — kit file sh/ddev-handover.sh missing (fix: sudo opk update)"
fi
# Router-port readiness: rootless ddev-router cannot bind 80/443 unless
# ip_unprivileged_port_start <= 80. Shows the HOST value (the docker-rootless
# daemon netns inherits it at start; the daemon may need a restart if it
# started before the sysctl was applied).
port_start=$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start 2>/dev/null || echo "?")
if [ "$port_start" = "?" ]; then
    # Uncounted unknown (0.0.48b W3, #211 a F25): an unreadable sysctl
    # used to land in the else-arm as a counted ui_kv_bad "(? > 80)" —
    # a false alarm the caller cannot act on.
    ui_kv "router ports" "unknown — cannot read ip_unprivileged_port_start"
elif [ "${port_start:-1024}" -le 80 ] 2>/dev/null; then
    ui_kv_ok "router ports" "ready (ip_unprivileged_port_start=$port_start)"
else
    ui_kv_bad "router ports" "NOT ready (ip_unprivileged_port_start=$port_start > 80)"
    ui_detail "ddev-router cannot bind 80/443 — fix: sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
fi
# mkcert CAROOT readiness for the opencode user (ddev HTTPS).
ca="/home/$OPENCODE_USER/.local/share/mkcert/rootCA.pem"
if [ -f "$ca" ]; then
    ui_kv_ok "mkcert CA" "present — $ca"
    # Mismatch check (report-only): if a Windows mkcert CA exists but the
    # opencode CAROOT holds a DIFFERENT CA, Windows browsers trust the
    # Windows one and ddev's certs show as "not secure". Happens when the
    # CA was reused from the wrong source (e.g. a second WSL distro).
    win_ca=""
    if [ -d /mnt/c/Users ]; then
        for wca in /mnt/c/Users/*/AppData/Local/mkcert/rootCA.pem; do
            [ -f "$wca" ] && { win_ca="$wca"; break; }
        done
    fi
    if [ -n "$win_ca" ]; then
        oc_fp=$(openssl x509 -in "$ca" -noout -fingerprint -sha256 2>/dev/null || true)
        win_fp=$(openssl x509 -in "$win_ca" -noout -fingerprint -sha256 2>/dev/null || true)
        if [ -n "$oc_fp" ] && [ -n "$win_fp" ] && [ "$oc_fp" != "$win_fp" ]; then
            ui_kv_bad "mkcert CA" "MISMATCH — opencode CA != Windows CA ($win_ca)"
            ui_detail "Windows browsers will show ddev sites as not-secure."
            ui_detail "fix: copy the Windows CA (rootCA.pem + rootCA-key.pem) to"
            ui_detail "$ca's directory, then remove ~/.ddev/traefik/certs/* and 'ddev restart'"
        fi
    fi
else
    # The CA lives under opencode-only dirs (typically 700) — a non-root
    # caller cannot stat the file, so "missing" may just mean "unchecked".
    # Only root can genuinely confirm absence.
    if [ "$(id -u)" -ne 0 ] && [ -d "/home/$OPENCODE_USER" ]; then
        # 0.0.48b W3: same rule as the socket/version unknowns — an
        # unprivileged caller cannot judge this, so it must not count.
        ui_kv "mkcert CA" "unknown — needs root to check (run: sudo opk status)"
    else
        # 0.0.48b W3: "optional" in the text means exactly that — ddev
        # HTTPS only; not a finding for the verdict.
        ui_kv "mkcert CA" "missing (optional — ddev HTTPS will need a trusted CA)"
    fi
fi
# Migration dumps (issue #15): databases exported from the developer's
# daemon at install time wait here until they are imported into the
# opencode daemon. Read-only listing — importing is the user's call.
_mig_root="/var/backups/opencode-permissions-kit"
_mig_dir=$(ls -1d "$_mig_root"/ddev-migration-* 2>/dev/null | sort | tail -1 || true)
if [ -n "$_mig_dir" ] && [ -f "$_mig_dir/manifest.conf" ]; then
    _mig_ok=$(grep -c '^OK|' "$_mig_dir/manifest.conf" 2>/dev/null || true)
    _mig_ok=${_mig_ok:-0}
    if [ "$_mig_ok" -gt 0 ]; then
        _mig_imported=0
        if [ -d "/home/$OPENCODE_USER/.ddev" ]; then
            # ddev >= 1.23 registers into project_list.yaml, older into
            # the project_info: block of global_config.yaml — either
            # means the opencode side already has projects.
            if [ -f "/home/$OPENCODE_USER/.ddev/project_list.yaml" ] \
                && grep -q 'approot:' "/home/$OPENCODE_USER/.ddev/project_list.yaml" 2>/dev/null; then
                _mig_imported=1
            else
                _mig_imported=$(grep -c '^project_info:' \
    "/home/$OPENCODE_USER/.ddev/global_config.yaml" 2>/dev/null || true)
                _mig_imported=${_mig_imported:-0}
            fi
        fi
        if [ "$_mig_imported" -gt 0 ]; then
            ui_kv_ok "db dumps" "$_mig_ok dump(s) — ${_mig_dir##*/}"
            ui_detail "if some databases are missing in the opencode projects, import manually:"
            ui_detail "  sudo $LIBDIR/bin/ddev-migrate import"
        else
            ui_kv_warn "db dumps" "$_mig_ok dump(s) waiting for import — ${_mig_dir##*/}"
            ui_detail "import all: sudo $LIBDIR/bin/ddev-migrate import  (first start pulls images)"
            ui_detail "or per project: ddev start <name> && ddev import-db <name> --file=<dump>.sql.gz"
        fi
    fi
fi
# Partial-export detector (production finding: 1 of 12 databases
# exported, every retry silently skipped). Compares the dev user's
# CURRENT registry under the configured roots against the newest
# manifest — warns when databases are still missing, with or without a
# manifest. Needs the deployed lib's parser; silently skipped when the
# registry is unreadable for the caller.
if [ -n "$DEFAULT_USER" ] && [ -f "$LIBDIR/sh/ddev-migrate.sh" ]; then
    # shellcheck disable=SC1090
    . "$LIBDIR/sh/ddev-migrate.sh"
    # Roots ride positional parameters, one per line from projects.conf
    # (0.0.44a V18): the old `tr '\n' ' '` + unquoted call word-split a
    # spaced root (hand-edited conf) into bogus "roots" and spurious
    # INCOMPLETE/NONE diagnostics. ddev_migrate_gap/ddev_migrate_projects
    # take roots one-per-argument; the function keeps the script's own
    # "$@" intact and skips empty lines.
    _st_dbdump_gap() {
        _stg_user="$1"
        while IFS= read -r _stg_root; do
            [ -n "$_stg_root" ] || continue
            set -- "$@" "$_stg_root"
        done
        [ "$#" -gt 1 ] || return 0
        shift  # drop _stg_user; "$@" now holds the roots
        if _mig_gap=$(DDEV_MIG_BACKUP_ROOT="$_mig_root" ddev_migrate_gap "$_stg_user" "$@"); then
            _mig_have=${_mig_gap%% *}
            _mig_rest=${_mig_gap#* }
            _mig_now=${_mig_rest%% *}
            ui_kv_warn "db dumps" "INCOMPLETE — registry lists $_mig_now project(s), only $_mig_have dump(s) recorded"
            ui_detail "missing databases stay in the old daemon — bridge them (docs/troubleshooting.md,"
            ui_detail "'My databases are gone after the install'); check:"
            ui_detail "  $LIBDIR/bin/ddev-migrate registry $_stg_user <configured-root>"
        elif [ -z "$_mig_dir" ] || [ ! -f "$_mig_dir/manifest.conf" ]; then
            # no manifest at all: warn only when the registry HAS projects
            _mig_reg=$(ddev_migrate_projects "$(ddev_migrate_home "$_stg_user")/.ddev" "$@" 2>/dev/null \
    | grep -c . || true)
            _mig_reg=${_mig_reg:-0}
            if [ "$_mig_reg" -gt 0 ]; then
                ui_kv_warn "db dumps" "NONE — but the ddev registry lists $_mig_reg project(s)"
                ui_detail "the install-time export did not run or found nothing; bridge manually:"
                ui_detail "  sudo $LIBDIR/bin/ddev-migrate export $_stg_user <configured-root>"
            fi
        fi
    }
    if [ -f "$PROJECTS_CONF" ]; then
        # Redirect, not a pipe (issue #158): _st_dbdump_gap's ui_kv_warn
        # rows must run in the MAIN shell so the summary's severity
        # counters see them — a `grep | _st_dbdump_gap` pipeline would
        # count inside the pipe's subshell and lose the tally.
        # 0.0.48b W2: same fail-loud rule as the share scan — never a
        # /dev/null fallback for a failed mktemp.
        _st_gap_roots=$(mktemp) || _st_gap_roots=""
        if [ -z "$_st_gap_roots" ]; then
            ui_kv_warn "db dumps" "gap scan skipped — mktemp failed (check TMPDIR / /tmp)"
        else
            grep -v '^[[:space:]]*$' "$PROJECTS_CONF" 2>/dev/null > "$_st_gap_roots" || true
            _st_dbdump_gap "$DEFAULT_USER" < "$_st_gap_roots" || true
            rm -f "$_st_gap_roots"
        fi
    fi
elif [ -n "$DEFAULT_USER" ]; then
    # Issue #165: same broken-kit class as the other lib guards — the
    # migration-gap check must not vanish silently behind its guard; a
    # stamped developer plus a missing lib is a damaged tree. The row
    # stays away for unstamped installs (guard stays compound).
    ui_kv_warn "db dumps" "not checked — kit file sh/ddev-migrate.sh missing (fix: sudo opk update)"
fi
# Live ddev version (issues #56, #72): DDEV_VERSION from install.conf is
# an install-time stamp and goes stale the moment the developer upgrades
# ddev — `sudo opk status` kept showing the old version while the
# terminal's `ddev --version` already answered with the new one. Probe
# the real binary instead, in two tiers:
#   1. the binary resolved the SAME way bin/ddev-as-opencode does (PATH,
#      then the two standard locations), run as the current user —
#      `--version` is a local-only flag (no daemon, no HOME writes), so
#      this is safe and covers plain `opk status` and checkout runs.
#   2. ddev >= 1.25.4 refuses root outright ("DDEV is not designed to be
#      run with root privileges", exit 1 before printing anything), so
#      under `sudo opk status` tier 1 is silent even though the binary
#      exists. Ask the kit's own helper instead: it runs ddev exactly
#      the way the kit does (as the opencode user, HOME/DOCKER_HOST
#      re-set) — the most truthful version there is. sudo -n never
#      prompts: root needs no password, the developer hits the kit's
#      NOPASSWD sudoers rule, anyone else fails fast into the fallback.
# The stamp stays the fallback for hosts where no binary answers at all.
_st_bin=""
for _st_cand in "$(command -v ddev 2>/dev/null || true)" /usr/local/bin/ddev /usr/bin/ddev; do
    [ -n "$_st_cand" ] && [ -x "$_st_cand" ] && { _st_bin="$_st_cand"; break; }
done
_st_ver=""
[ -n "$_st_bin" ] && _st_ver=$("$_st_bin" --version 2>/dev/null \
    | grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
_st_helper="${LIBDIR:-/usr/local/lib/opencode-permissions-kit}/bin/ddev-as-opencode"
if [ -z "$_st_ver" ] && [ -x "$_st_helper" ] && command -v sudo >/dev/null 2>&1; then
    _st_ver=$(sudo -n -u "${OPENCODE_USER:-opencode}" "$_st_helper" --version 2>/dev/null \
    | grep -m1 -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/^v//')
fi
if [ -n "$_st_ver" ]; then
    ddev_low=$(awk -v v="$_st_ver" 'BEGIN{split(v,a,"."); \
    if(a[1]+0<1 || (a[1]+0==1 && a[2]+0<25)) print "yes"; else print "no"}' 2>/dev/null)
    if [ "$ddev_low" = yes ]; then
        ui_kv_bad "ddev version" "$_st_ver (ddev < 1.25 — rootless needs ddev >= 1.25, upgrade ddev)"
    else
        ui_kv "ddev version" "$_st_ver"
    fi
elif [ -n "${DDEV_VERSION:-}" ]; then
    ui_kv_warn "ddev version" "$DDEV_VERSION (recorded at install time — ddev binary not found now)"
fi
# Windows hosts readiness (WSL2): custom-tld projects need their hostnames
# in the Windows hosts file for the browser; ddev (running as opencode)
# cannot manage that file. Report-only, per project root.
# Readiness split (issue #165): host preconditions and the lib guard are
# separate conditions now — a missing lib on an otherwise-ready host is a
# broken kit (counted warn), not a silently skipped check, while every
# unmet host precondition (no /mnt/c, agent-uid run, no developer) stays
# row-free as before.
_st_hosts_ready=false
if [ -d /mnt/c ] && [ -f /mnt/c/Windows/System32/drivers/etc/hosts ] \
   && [ -n "${DEFAULT_USER:-}" ] && [ "$(id -u)" != "$(id -u "$OPENCODE_USER" 2>/dev/null || echo 1)" ]; then
    _st_hosts_ready=true
fi
if [ "$_st_hosts_ready" = true ] && [ -f "$LIBDIR/sh/ddev-hosts.sh" ]; then
    # shellcheck disable=SC1091  # deployed lib, checked above
    . "$LIBDIR/sh/ddev-hosts.sh"
    if [ -f "$PROJECTS_CONF" ] && [ -s "$PROJECTS_CONF" ]; then
        while IFS= read -r _st_root; do
            [ -z "$_st_root" ] && continue
            [ -d "$_st_root" ] || continue
            # vendor/, node_modules/, testdata/ and .git/ pruned (issues
            # #21, #29, #112): composer/npm packages and test fixtures
            # (e.g. a checkout of ddev's own repository) ship their own
            # .ddev dirs — they are not the user's projects and their
            # hostnames must never hit the Windows hosts file. .git is
            # additionally the densest tree in a project and never holds
            # a real project — pruned for scan cost too.
            # 0.0.48b W2: fail-loud mktemp (no /dev/null fallback — see
            # the ddev share scan above for the rationale).
            _st_hosts_list=$(mktemp) || _st_hosts_list=""
            if [ -z "$_st_hosts_list" ]; then
                ui_kv_warn "hosts (win)" "scan skipped for $_st_root — mktemp failed (check TMPDIR / /tmp)"
                continue
            fi
            # Shared scan helper (see the ddev share scan above): same
            # prune rules, same live progress line (issue #210).
            _st_ddev_scan "win hosts: scanning $_st_root" "$_st_root" "$_st_hosts_list"
            # Main-shell loop via redirect (issue #158 — the summary's
            # severity counters must see the ui_kv_warn rows; see the
            # ddev share scan above).
            while IFS= read -r _st_d; do
                _st_m=$(ddev_hosts_missing "$(dirname "$_st_d")")
                [ -n "$_st_m" ] || continue
                ui_kv_warn "hosts (win)" "$(dirname "$_st_d"): missing $(printf '%s' "$_st_m" | tr '\n' ' ')"
                for _st_h in $_st_m; do
                    ui_detail "add: opk ddev-hosts-add $_st_h"
                done
            done < "$_st_hosts_list"
            rm -f "$_st_hosts_list"
        done < "$PROJECTS_CONF"
    fi
elif [ "$_st_hosts_ready" = true ]; then
    # Issue #165: readiness held, only the kit file is missing — broken
    # kit, counted warn (see the readiness split above).
    ui_kv_warn "hosts (win)" "not checked — kit file sh/ddev-hosts.sh missing (fix: sudo opk update)"
fi

# === WSL2 /mnt/c exposure (drvfs world-readable by default) =====================
# The 9p/drvfs server runs with the Windows session token, so NTFS ACLs do
# NOT distinguish WSL users — the Linux mode bits are the only filter, and
# the WSL default mounts C: world-readable. Every WSL user (including the
# agent's) can then read the whole Windows profile (.ssh, NTUSER.DAT, ...).
# Report-only; the fix is a host-level wsl.conf change.
if [ -d /mnt/c ]; then
    ui_section "WSL2 /mnt/c exposure"
    mnt_mode=$(stat -c %a /mnt/c 2>/dev/null || echo "")
    if [ -n "$mnt_mode" ] && [ $((0$mnt_mode & 0004)) -ne 0 ]; then
        if grep -q '^options *=.*dmask' /etc/wsl.conf 2>/dev/null; then
            ui_kv_warn "/mnt/c" "fix configured, pending"
            ui_detail "wsl.conf carries the restriction — run 'wsl --shutdown' from Windows to apply"
        else
            ui_kv_bad "/mnt/c" "world-readable (mode $mnt_mode)"
            ui_detail "the agent user can read the whole Windows profile"
            ui_detail "fix: restrict the drvfs mount to the developer in /etc/wsl.conf:"
            ui_detail "  [automount]"
            ui_detail "  enabled = true"
            ui_detail "  options = \"uid=1000,gid=1000,dmask=027,fmask=037\""
            ui_detail "(replace uid/gid with the default user's; install.sh asks)"\
" and run 'wsl --shutdown' from Windows."
        fi
    else
        if [ -n "$mnt_mode" ]; then
            ui_kv_ok "/mnt/c" "restricted (mode $mnt_mode)"
        else
            # Uncounted unknown (0.0.48b W3, #211 a F25): a failing
            # stat used to land here as a counted ui_kv_ok
            # "restricted (mode ?)" — a false green.
            ui_kv "/mnt/c" "unknown — cannot stat the mount"
        fi
        # Browser bridge (issues #91, #100): on the restricted mount the
        # opencode user cannot execute powershell.exe — without the bridge,
        # device logins (`console login` / `auth login`) die on the spawn
        # error. The wsl.conf carrier is an explicit opt-in (the kit never
        # edits wsl.conf implicitly).
        # opencode 1.18.33+ / 2.0.18+ (upstream PR #51414) bundle `open`
        # 11.x: powershell access is checked BEFORE spawning with an
        # xdg-open fallback — no bridge needed there (the kit's xdg-open
        # shim covers that fallback). 2.0.2-2.0.17 bundle open@10.1.2,
        # like 1.x < 1.18.33, and need the carrier. An unknown version
        # (probe failed) keeps the old verdicts (safe side).
        _st_bridge_unneeded=0
        if [ -n "${ADV_VER:-}" ] && command -v advisories_version_cmp >/dev/null 2>&1; then
            case "$ADV_VER" in
                1.*) if [ "$(advisories_version_cmp "$ADV_VER" 1.18.33)" != lt ]; then _st_bridge_unneeded=1; fi ;;
                2.*) if [ "$(advisories_version_cmp "$ADV_VER" 2.0.18)" != lt ]; then _st_bridge_unneeded=1; fi ;;
            esac
        fi
        if [ "$_st_bridge_unneeded" -eq 1 ]; then
            ui_kv_ok "browser bridge" "not needed — opencode $ADV_VER ships a WSL-safe opener"
            ui_detail "kit carrier serves 1.x < 1.18.33 and 2.x < 2.0.18 only"
        elif [ -x "$LIBDIR/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ] \
           && grep -q '^# opencode permissions kit browser bridge -- begin$' /etc/wsl.conf 2>/dev/null; then
            ui_kv_ok "browser bridge" "deployed (opencode logins survive the hardened mount)"
        elif [ -x "$LIBDIR/wsl/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
            ui_kv_bad "browser bridge" "stand-in only — no wsl.conf carrier ('console login' fails on this mount)"
            ui_detail "fix: sudo opk wsl-add-opencode-1-fix (explicit consent — the kit never edits wsl.conf itself)"
        else
            ui_kv_bad "browser bridge" "missing — 'console login'/'auth login' fails on this mount"
            ui_detail "fix: sudo opk update (deploys the stand-in),"\
" then sudo opk wsl-add-opencode-1-fix (wsl.conf carrier)"
        fi
        # xdg-open fallback shim (bin/xdg-open): open@11's fallback path
        # crashes opencode 2.x device logins when no xdg-open exists.
        # Dangling-target check (0.0.42d C2): readlink alone reports a
        # kit symlink whose library copy is gone as healthy.
        if [ -L /usr/local/bin/xdg-open ] \
           && [ "$(readlink /usr/local/bin/xdg-open 2>/dev/null || true)" = "$LIBDIR/bin/xdg-open" ]; then
            if [ -x "$LIBDIR/bin/xdg-open" ]; then
                ui_kv_ok "xdg-open fallback" "deployed (kit shim at /usr/local/bin/xdg-open)"
            else
                ui_kv_bad "xdg-open fallback" "broken — shim symlink dangles (library copy missing)"
                ui_detail "fix: sudo opk update (re-deploys the library)"
            fi
        elif { command -v xdg_open_real_exists >/dev/null 2>&1 && xdg_open_real_exists; } \
           || [ -x /usr/local/bin/xdg-open ]; then
            ui_kv_ok "xdg-open fallback" "not needed — real xdg-open present"
        else
            ui_kv_bad "xdg-open fallback" "missing — opencode 1.18.33+ / 2.0.18+ device logins crash"
            ui_detail "fix: sudo opk update (deploys the shim when no real xdg-open exists)"
        fi
    fi
fi

# === Root-equivalent access audit (issue #37) ====================================
# Root-equivalent surfaces BEYOND the kit's own backends: a rootful docker
# daemon or containerd, LXD/libvirt — and, very common on WSL2, the Docker
# Desktop / Rancher Desktop integration sockets under /mnt/wsl, which the
# distro mounts world-usable. Any of these reachable by the agent user
# breaks the "containers ≠ root" guarantee as thoroughly as a root docker
# group membership. All checks are report-only stat math — no privileged
# probe, no prompt, no fix (removing access is the admin's decision).

# status_groups_hits <groups-list> <danger-list>: prints every group from
# <danger-list> that appears in <groups-list> (word match).
# shellcheck disable=SC2086  # word splitting intended: both are group lists
status_groups_hits() {
    for sgh_g in $2; do
        case " $1 " in *" $sgh_g "*) printf '%s\n' "$sgh_g" ;; esac
    done
    return 0
}

# status_sock_agent_reachable <socket-path> <agent-groups>: exit 0 when the
# agent user can plausibly connect — socket world-writable, or group-writable
# with its group among <agent-groups>. Pure stat math, works unprivileged.
status_sock_agent_reachable() {
    ssr_mode=$(stat -c %a "$1" 2>/dev/null) || return 1
    [ $((0$ssr_mode & 0002)) -ne 0 ] && return 0
    if [ $((0$ssr_mode & 0020)) -ne 0 ]; then
        ssr_grp=$(stat -c %G "$1" 2>/dev/null)
        case " $2 " in *" $ssr_grp "*) return 0 ;; esac
    fi
    return 1
}

ui_section "Root-equivalent access (audit)"

# Groups that are root-equivalent (or credential-equivalent) if the AGENT
# user is a member. The kit never adds them — this catches later manual
# grants (usermod -aG docker opencode "to make something work").
sra_groups=$(id -nG "$OPENCODE_USER" 2>/dev/null || true)
sra_finding=false
# shellcheck disable=SC2086  # word splitting intended: group lists
sra_red=$(status_groups_hits "$sra_groups" \
    "docker containerd lxd libvirt libvirt-qemu snap disk sudo admin wheel" | tr '\n' ' ')
# shellcheck disable=SC2086  # word splitting intended: group lists
sra_yellow=$(status_groups_hits "$sra_groups" "wireshark adm systemd-journal" | tr '\n' ' ')
sra_red=${sra_red% } ; sra_yellow=${sra_yellow% }
if [ -n "$sra_red" ]; then
    ui_kv_bad "groups (root-equiv)" \
    "$OPENCODE_USER in: $sra_red — full root, remove with: sudo gpasswd -d $OPENCODE_USER <group>"
    sra_finding=true
fi
if [ -n "$sra_yellow" ]; then
    ui_kv_warn "groups (sensitive)" "$OPENCODE_USER in: $sra_yellow — log/packet access can leak credentials"
    sra_finding=true
fi

# Root-equivalent daemon sockets: system-wide paths plus everything the
# WSL2 desktop integrations mount under /mnt/wsl (Docker Desktop exposes
# its daemon socket world-usable to every WSL distro user by default).
# Override the list via ROOT_EQUIV_SOCKS (same pattern as LEAK_SCAN_DIRS).
sra_sock_list="/var/run/docker.sock /run/containerd/containerd.sock /var/lib/lxd/unix.socket /run/libvirt/libvirt-sock"
sra_sock_list="${ROOT_EQUIV_SOCKS:-$sra_sock_list}"
if [ -d /mnt/wsl ]; then
    sra_sock_list="$sra_sock_list $(find /mnt/wsl -maxdepth 4 \( -type s -o -type l \) \( -name docker.sock \
        -o -name podman.sock -o -name containerd.sock -o -name crio.sock \) 2>/dev/null)"
fi
sra_seen=""
for sra_s in $sra_sock_list; do
    [ -S "$sra_s" ] || continue
    # dedup (symlinked paths resolve to the same socket)
    sra_r=$(readlink -f "$sra_s" 2>/dev/null || echo "$sra_s")
    case " $sra_seen " in *" $sra_r "*) continue ;; esac
    sra_seen="$sra_seen $sra_r"
    if status_sock_agent_reachable "$sra_s" "$sra_groups"; then
        ui_kv_bad "socket" "$sra_s — AGENT-REACHABLE (root-equivalent daemon)"
        sra_finding=true
    else
        ui_kv_ok "socket" "$sra_s — present, not agent-reachable"
    fi
done

# Windows interop: with a world-executable /mnt/c the agent can run Windows
# binaries as the Windows session user (no Linux root, but full Windows
# profile access). The /mnt/c restriction above (fmask) also blocks this
# exec path — this probe makes the interop outcome explicit.
if [ -e /mnt/c/Windows/System32 ]; then
    sra_mode=$(stat -c %a /mnt/c/Windows/System32/cmd.exe 2>/dev/null || true)
    if [ -n "$sra_mode" ] && [ $((0$sra_mode & 0001)) -ne 0 ]; then
        ui_kv_bad "win interop" "agent can execute Windows binaries (/mnt/c world-executable)"
        sra_finding=true
    else
        ui_kv_ok "win interop" "blocked for the agent (/mnt/c restricted)"
    fi
fi

# The agent user itself must have NO sudo rules (the kit grants rules only
# to the developer, RunAs opencode). Only checkable when status.sh runs as
# root; otherwise silent. The check keys on the listing HEADER, not on any
# runas spec (0.0.45c S3): the old regex matched only (ALL...) and
# (opencode...) runas specs — a manual `(root)` or `(dev)` grant, exactly
# the "later manual grant" class this row exists to surface, printed the
# green "none" verdict. 0.0.45d W3: the header grep alone was locale-
# fragile — sudo localizes the -l listing (gettext catalogs) and its
# default env_keep preserves LANG/LC_*, so a translated header escaped
# the English pattern. LC_ALL=C pins the listing's language, and a
# structural runas-spec disjunct (any indented `(...) ...` listing line)
# flags grants even where the locale survives (belt and braces — it is
# the old syntax-based idea, widened to every runas).
if [ "$(id -u)" -eq 0 ] && command -v sudo >/dev/null 2>&1; then
    # LC_ALL=C pins the listing's language (W3: sudo localizes the -l
    # listing and its default env_keep preserves LANG/LC_*); the runas
    # disjunct is the structural belt-and-braces for any locale that
    # survives anyway.
    _sra_pat='may run the following commands|^[[:space:]]*\([^)]+\)'
    if LC_ALL=C sudo -n -l -U "$OPENCODE_USER" 2>/dev/null | grep -Eq "$_sra_pat"; then
        ui_kv_bad "sudo rules" "$OPENCODE_USER may run sudo — the kit grants it none (investigate)"
        sra_finding=true
    else
        ui_kv_ok "sudo rules" "none for $OPENCODE_USER"
    fi
fi

if [ "$sra_finding" = false ]; then
    ui_kv_ok "result" "no root-equivalent access found for $OPENCODE_USER"
fi

# === Sensitive-file leak scan (report-only) =====================================
# Name-based sweep of scratch directories for files matching the global deny
# patterns. The kit protects storage locations, not information flows: a copy
# that left the project roots (cp .env /tmp/backup) is outside every future
# scan. This surfaces such leftovers for manual inspection. REPORT-ONLY —
# no ACL is ever changed outside the project roots, and false positives (a
# developer's own /tmp/foo.env.example) are expected. Renamed copies stay
# invisible: this is a name tripwire, not content DLP. Runs unprivileged;
# copies hidden in 0700 directories are only visible when run as root.
# Override the directories via LEAK_SCAN_DIRS="/tmp /some/dir".
# Noop stub first: log() must exist even when the library (and log.sh with
# it) is already gone — the scan itself never depends on it.
log() { :; }
[ -f "$LIBDIR/sh/log.sh" ] && . "$LIBDIR/sh/log.sh"
LEAK_DIRS="${LEAK_SCAN_DIRS:-/tmp /var/tmp /dev/shm}"
PARSER="$LIBDIR/py/jsonc-parser.py"
SCAN_CFG="/home/$OPENCODE_USER/.config/opencode/opencode.jsonc"
[ -f "$SCAN_CFG" ] || SCAN_CFG="/home/$OPENCODE_USER/.config/opencode/opencode.json"

ui_section "Leak scan (report-only)"

if [ -f "$SCAN_CFG" ] && [ -x "$PARSER" ] && command -v python3 >/dev/null 2>&1; then
    # The parser's rc matters (0.0.44a V8): a non-dict top level used to
    # crash into this `|| true`, and empty output then printed the GREEN
    # "no matches" — the F13 false-green class. rc != 0 now renders as
    # "unscannable", never as clean.
    scan_unscannable=false
    if scan_patterns=$(python3 "$PARSER" "$SCAN_CFG" 2>/dev/null); then
        :
    else
        scan_patterns=""
        scan_unscannable=true
    fi
    scan_hits=""
    if [ -n "$scan_patterns" ]; then
        scan_hits=$(
            for scan_dir in $LEAK_DIRS; do
                [ -d "$scan_dir" ] || continue
                while IFS= read -r scan_pat; do
                    [ -z "$scan_pat" ] && continue
                    case "$scan_pat" in
                        */*)
                            find "$scan_dir" -maxdepth 4 -type f -path "*/$scan_pat" -print 2>/dev/null
                            # "*/<pat>" needs a deeper hierarchy — a leading
                            # "**/" pattern must ALSO hit files directly in
                            # the scan dir (same coverage as the -name branch).
                            scan_tail=${scan_pat#\*\*/}
                            if [ "$scan_tail" != "$scan_pat" ] && [ -n "$scan_tail" ]; then
                                case "$scan_tail" in
                                    */*) find "$scan_dir" -maxdepth 4 -type f -path "$scan_dir/$scan_tail" \
                                        -print 2>/dev/null ;;
                                    *)   find "$scan_dir" -maxdepth 4 -type f -name "$scan_tail" -print 2>/dev/null ;;
                                esac
                            fi
                            ;;
                        *)   find "$scan_dir" -maxdepth 4 -type f -name "$scan_pat" -print 2>/dev/null ;;
                    esac
                done <<EOF
$scan_patterns
EOF
            done | grep -v -e '/systemd-private-' -e '/snap-private-tmp/' | sort -u
        )
    fi
    scan_count=$(printf '%s\n' "$scan_hits" | grep -c . || true)
    if [ "$scan_unscannable" = true ]; then
        ui_kv_warn "result" "skipped — agent config unscannable (top level is not an object?)"
        log "leak scan: skipped, parser rejected $SCAN_CFG"
    elif [ "${scan_count:-0}" -gt 0 ]; then
        ui_warn "$scan_count match(es) — deny-pattern files outside the protected roots:"
        # Hit list prints in full mode only — --short reduces the report
        # to the verdict line (the warn row above already counted).
        if [ "$STATUS_SHORT" = false ]; then
            printf '%s\n' "$scan_hits" | head -20 | sed 's/^/     /'
            [ "$scan_count" -gt 20 ] && ui_detail "... and $((scan_count - 20)) more"
        fi
        ui_detail "inspect and remove manually (report-only; renamed copies stay invisible)"
        log "leak scan: $scan_count deny-pattern match(es) in scratch dirs (report-only)"
    else
        ui_kv_ok "result" "no matches in: $LEAK_DIRS"
    fi
else
    ui_kv_warn "result" "skipped (global config or parser not available)"
fi

# === Management ==================================================================

# Management hints use the opk shorthand (issue #62): shorter than the
# library paths, and the dispatcher elevates itself where needed.
# --short skips the block: one verdict line means one line (issue #158).
if [ "$STATUS_SHORT" = false ]; then
    echo ""
    ui_info "Management (run in a terminal):"
    ui_detail "sudo opk config      change settings"
    ui_detail "sudo opk update      re-deploy kit after an update"
    ui_detail "opk uninstall        remove the kit"
    echo ""
fi

# === Summary (issue #158) ========================================================
# One verdict line at the end: instead of scrolling the whole report, the
# eye (and cron) gets "All green" or the alert/warning tally. Severities
# are counted BY CALL in the semantic ui helpers (ui_kv_ok/ui_kv_warn/
# ui_kv_bad, ui_have/ui_atten/ui_miss, ui_warn/ui_error) — color bytes
# are empty under NO_COLOR/piping and could not be counted. The tally
# only sees MAIN-shell rows: the scans above feed their reporting loops
# from temp files for exactly that reason (a `cmd | while` pipeline
# bumps counters in a subshell, where they die). The counts snapshot
# BEFORE the verdict row prints, so the row itself never counts.
# NOT counted by design (0.0.48b W3): rows the caller cannot judge at
# their own privilege ("unknown — needs root") and optional-feature rows
# ("missing (optional …") — unknown ≠ finding, and a permanent warn for
# every unprivileged or HTTPS-less host would make green unattainable
# and the cron alert worthless. They stay visible as plain ui_kv rows.
# Exit code carries the verdict for callers and cron:
#   0 all green · 1 alert(s) · 2 warning(s) only · 64 usage error.
_st_alerts=$UI_ROWS_BAD
_st_warns=$UI_ROWS_WARN
_st_passes=$UI_ROWS_OK
if [ "$STATUS_SHORT" = true ]; then
    UI_SILENT=0
    _st_tail="— run 'opk status' for the full report"
else
    ui_section "Summary"
    _st_tail="— see the sections above"
fi
if [ "$_st_alerts" -gt 0 ]; then
    ui_kv_bad "result" "$_st_alerts alert(s), $_st_warns warning(s) $_st_tail"
    _st_rc=1
elif [ "$_st_warns" -gt 0 ]; then
    ui_kv_warn "result" "$_st_warns warning(s) $_st_tail"
    _st_rc=2
else
    ui_kv_ok "result" "All green — $_st_passes checks passed, no alerts, no warnings"
    _st_rc=0
fi
exit "$_st_rc"
