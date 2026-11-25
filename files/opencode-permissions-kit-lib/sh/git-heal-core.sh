# shellcheck shell=sh
# opencode permissions kit -- git-heal-core.sh
#
# The `opk git-heal` subcommand's logic (issue #671): the on/off/status
# toggle for the git heal hooks. The hooks themselves (git-heal/hooks/,
# four identical post-* bodies) re-pin the measured operand set
# (index, HEAD, ORIG_HEAD, REBASE_HEAD, packed-refs and the conflict
# pseudo-refs — heal-index-head's header, widened in #678) to the
# agent user after every developer git operation that flipped their
# ownership (git lock+rename -- under the sticky .git of the #651 heal
# the agent can never re-take ownership itself, its main-checkout
# workflow locks out). Sourced (never executed) by bin/opk through its
# $LIBDIR (SELF-resolved, checkout-first); the pairing guard in the
# dispatcher refuses a version-skewed pairing.
#
# POSIX sh, no top-level side effects (definitions and comments only).
# The functions run in the CALLER's shell (bin/opk sets set -u only)
# and read the globals the dispatcher sets: LIBDIR, INSTALL_CONF and
# the ui_* helpers. git_heal_cli parses the subcommand BEFORE the sudo
# hop (usage errors need no elevation), then re-enters bin/opk as root
# (loop-guarded, the #479 a F24 shape) and dispatches.
#
# Explicit consent like wsl-add-opencode-1-fix (the issue #100 consent
# family): install/update never activate the hooks -- only `opk git-heal
# on` does. `on` (idempotent):
#   1. verifies the shipped pieces (heal script + four hooks),
#   2. re-renders the sudoers file from the template (the heal grant
#      line ships there; an install older than #671 would not carry
#      it yet -- this closes that gap without waiting for a kit
#      update),
#   3. sets the developer's global core.hooksPath to the kit hook dir
#      (repo hooks stay disabled for the developer -- the same
#      protective effect secure-git-config.md documents for the
#      /dev/null form, plus the heal),
#   4. heals every kit-managed gitdir once: enumerates every .git
#      under the conf roots RECURSIVELY (roots are scan roots like
#      /var/www/vhosts, the config.sh parent-registration shape --
#      depth-1 <root>/.git would find nothing), BOTH shapes -- the
#      classic directory and the POINTER FILE the git-protection
#      layout seals adopted checkouts into (#704 O4, issue #777: a
#      -type d find never matched the pointer, so the sweep healed
#      nothing on a pointer-shaped host); a pointer resolves through
#      _ghc_pt_target before it reaches the heal list -- after
#      re-validating every conf line reader-side (the files.md
#      root-op contract, #674 a A1: the uninstall-core reader mirror
#      -- a hand-edited system/scratch/agent-home line never steers
#      the root sweep).
# `off` removes ONLY the kit-owned hooksPath value (a foreign value is
# never touched) and leaves the sudoers grant in place (narrow,
# nothing invokes it without the hooksPath). `status` reports the
# state, the pieces and the per-root lockout situation.
#
# Test overrides (unit suite only, never set in production):
#   GH_SUDO     privileged-drop prefix (default sudo; "" runs the
#               developer-side git calls in place)
#   GH_LIBDIR   library base (default $LIBDIR, literal fallback)
#   GH_DEV_HOME developer home (default: getent on the install.conf
#               DEFAULT_USER; the override keeps unit tests off real
#               homes -- the sandbox policy forbids touching /home)

# _ghc_libdir: the library base everything below resolves against.
_ghc_libdir() {
    printf '%s' "${GH_LIBDIR:-${LIBDIR:-/usr/local/lib/opencode-permissions-kit}}"
}

# _ghc_key <key>: read one key from install.conf (doctor-style sed,
# never a source of a root-owned file). Quote-strip like the DOCTOR_USER
# idiom (#785 b A1): a hand-quoted value would keep its quotes through
# the owner compares — false lockout rows on every gitdir.
_ghc_key() {
    sed -n "s/^$1=//p" "$INSTALL_CONF" 2>/dev/null | tail -n 1 | sed 's/^"//;s/"$//'
}

# _ghc_devuser: the developer username; loud empty on a missing key
# (this is a kit-machine command, install.conf must exist).
_ghc_devuser() {
    _ghc_du=$(_ghc_key DEFAULT_USER)
    if [ -z "$_ghc_du" ]; then
        ui_error "DEFAULT_USER not found in $INSTALL_CONF — is the kit installed?"
        exit 1
    fi
    printf '%s' "$_ghc_du"
}

# _ghc_agentuser: the agent username (OPENCODE_USER, canonical
# fallback like every kit lib).
_ghc_agentuser() {
    _ghc_au=$(_ghc_key OPENCODE_USER)
    printf '%s' "${_ghc_au:-opencode}"
}

# _ghc_devhome <devuser>: home via getent (relocated homes included).
# GH_DEV_HOME is the unit-suite override (sandbox: never touch /home).
_ghc_devhome() {
    if [ -n "${GH_DEV_HOME:-}" ]; then
        printf '%s' "$GH_DEV_HOME"
        return 0
    fi
    getent passwd "$1" 2>/dev/null | cut -d: -f6 || true
}

# _ghc_devgit <devuser> <devhome> <git-args...>: git AS THE DEVELOPER.
# The sudo hop drops to the user with the right HOME; the unit override
# (GH_SUDO set-and-empty) runs git in place with the scratch HOME --
# the -u/env prefix only exists on the sudo leg (an empty expansion
# would otherwise turn -u into the command word).
_ghc_devgit() {
    _gd_user="$1"
    _gd_home="$2"
    shift 2
    if [ -n "${GH_SUDO+x}" ] && [ -z "${GH_SUDO:-}" ]; then
        HOME="$_gd_home" git "$@"
    else
        ${GH_SUDO-sudo} -u "$_gd_user" env HOME="$_gd_home" git "$@"
    fi
}

# _ghc_hooksdir: the kit hook directory core.hooksPath must point at.
_ghc_hooksdir() {
    printf '%s/git-heal/hooks' "$(_ghc_libdir)"
}

# _ghc_dev_hooks_path <devuser>: the developer's current global
# core.hooksPath value ('' when unset or the gitconfig unreadable).
_ghc_dev_hooks_path() {
    _ghc_dh=$(_ghc_devhome "$1")
    [ -n "$_ghc_dh" ] || return 0
    git config -f "$_ghc_dh/.gitconfig" core.hooksPath 2>/dev/null || true
}

# _ghc_state: echoes on | off | foreign | unknown. `foreign` means a
# hooksPath WE did not set (left untouched by `off`, warned about in
# `status`); `unknown` means the developer's gitconfig cannot be read.
_ghc_state() {
    _ghc_st_dev=$(_ghc_devuser)
    _ghc_st_home=$(_ghc_devhome "$_ghc_st_dev")
    [ -n "$_ghc_st_home" ] || {
        echo unknown
        return 0
    }
    _ghc_st_gc="$_ghc_st_home/.gitconfig"
    [ -r "$_ghc_st_gc" ] || {
        echo unknown
        return 0
    }
    _ghc_st_cur=$(_ghc_dev_hooks_path "$_ghc_st_dev")
    if [ -z "$_ghc_st_cur" ]; then
        echo off
    elif [ "$_ghc_st_cur" = "$(_ghc_hooksdir)" ]; then
        echo on
    else
        echo foreign
    fi
}

# _ghc_pieces_ok: rc 0 when heal script + all four hooks exist in the
# library (version-skew guard -- `on` refuses to activate half a kit).
_ghc_pieces_ok() {
    _ghc_pc_dir="$(_ghc_libdir)/git-heal"
    [ -f "$_ghc_pc_dir/heal-index-head" ] || return 1
    [ -d "$_ghc_pc_dir/hooks" ] || return 1
    for _ghc_pc_h in post-merge post-checkout post-rewrite post-index-change; do
        [ -f "$_ghc_pc_dir/hooks/$_ghc_pc_h" ] || return 1
    done
    return 0
}

# _ghc_heal_once <gitdir>: run the root heal on one gitdir (already
# root here; GH_* env overrides pass through for the unit suite).
_ghc_heal_once() {
    "$(_ghc_libdir)/git-heal/heal-index-head" "$1"
}

# _ghc_py_probe: once-per-run python3 health probe (the status-core
# _st_py_ok / fs-baseline _fsb_py_ok shape, #710 a B1): the tee sits on
# the sweeps' DATA path, so a findable-but-broken interpreter (pyenv
# shim to a removed version) or a missing one must degrade LOUDLY to
# the plain cat passthrough — never hand the consumer loops an empty
# list over a dead tee (the silent false-green #221 a W3 exists for).
# The probe runs the SAME invocation shape as the tee it gates, with
# the interpreter's stderr VISIBLE (#244 c S3, the status-core shape;
# #710 b D1: the first probe is the diagnostic surface — a broken
# python3 names its real problem above the warn, an absent one is
# guarded off). No top-level state (definitions only, like the file
# header demands) — the :- guards carry it. Call ONCE from the MAIN
# shell before the sweep loops (#710 b D2): the tee call sites are
# pipeline forks, and a cache written inside a fork dies with it —
# forks inherit the main shell's cache vars.
_ghc_py_probe() {
    if [ "${_ghc_py_checked:-0}" != 1 ]; then
        _ghc_py_checked=1
        _ghc_py_ok=0
        command -v python3 >/dev/null 2>&1 &&
            python3 -I -c 'import sys, threading, time' >/dev/null &&
            _ghc_py_ok=1
        if [ "${_ghc_py_ok:-0}" != 1 ]; then
            printf '  warn: git-heal live progress unavailable (python3 missing or broken) — sweeps run without it\n' >&2
        fi
    fi
}

# _ghc_progress_tee <label>: newline-separated stdin -> stdout verbatim,
# plus — when stderr is a tty AND python3 is healthy — a "<label> — N
# done, M:SS" line rewritten once a second and erased at EOF. The
# status-core _st_progress_tee shape, line-based here (issue #695: the
# sweeps read newline lists, not NUL streams — the long walks used to
# run silent for minutes). python3 -I like every kit inline (a poisoned
# PYTHONHOME must not kill the display); non-tty stderr (pipes,
# captured output) sees the plain stream only, so nothing downstream
# parses progress frames. A failed health probe degrades to the plain
# passthrough (#710 a B1): the data path keeps its pre-#695 shape —
# zero python3 dependency — and the warn above names the reason.
_ghc_progress_tee() {
    _ghc_py_probe
    if [ "${_ghc_py_ok:-0}" != 1 ]; then
        # Bare cat: rc-preserving passthrough (the #265 class; #710 b
        # INFO adoption) — no call site observes the tee's rc today,
        # the honesty is free.
        cat
        return
    fi
    python3 -I -c '
import sys, threading, time
# Pure-ASCII source, glyphs via \u escapes (the argv-decode rule every
# kit python inline follows on 7-bit locales).
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
    line = "  %s \u2014 %d done, %d:%02d" % (label, count, el // 60, el % 60)
    if len(line) > 76:
        line = "  \u2026" + line[-73:]
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
        line = sys.stdin.buffer.readline()
        if not line:
            break
        count += 1
        sys.stdout.buffer.write(line)
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

# _ghc_root_ok <line>: reader-side conf-line gate for the on-sweep
# (files.md contract — every consumer that runs root operations over
# the roots re-validates each line; the uninstall-core reader mirror,
# #674 a A1). rc 0: usable root, trailing-slash-stripped form in
# _ghc_root_norm. rc 1: refused, form (non-absolute, dot/empty
# segment, whitespace, glob character #665); rc 2: refused,
# agent home; rc 3: refused, system path (incl. the bare "/"
# that strips to empty, #674 b D1) —
# the caller maps each rc to its skip line.
# The system-path and agent-home arms sit behind GH_CONF_RELAX (unit
# scratch zones live under /tmp); the form arms never relax.
_ghc_root_ok() {
    _ghc_ro="$1"
    case "$_ghc_ro" in
        /*) ;;
        *) return 1 ;;
    esac
    case "$_ghc_ro" in
        *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]* | *[\*\?\[]*) return 1 ;;
    esac
    while :; do
        case "$_ghc_ro" in
            */) _ghc_ro="${_ghc_ro%/}" ;;
            *) break ;;
        esac
    done
    # "/" strips to empty: rc 3 (system path), never the generic rc 1
    # form message — "/" is absolute and not malformed (#674 b D1).
    [ -n "$_ghc_ro" ] || return 3
    if [ "${GH_CONF_RELAX:-}" != "1" ]; then
        _ghc_ah=$(getent passwd "$(_ghc_agentuser)" 2>/dev/null | cut -d: -f6) ||
            true
        if [ "$_ghc_ro" = "/home/$(_ghc_agentuser)" ] ||
            { [ -n "$_ghc_ah" ] && [ "$_ghc_ro" = "$_ghc_ah" ]; }; then
            return 2
        fi
        case "$_ghc_ro" in
            # The writer's FHS-complete blocklist (sh/path-sane.sh
            # project_path_sane — same arms as every reader mirror).
            / | /bin | /bin/* | /boot | /boot/* | /dev | /dev/* | /etc | /etc/* | /home | /lib* | \
                /media | /media/* | /mnt | /mnt/* | /opt | /opt/* | /proc | /proc/* | /root | /root/* | \
                /run | /run/* | /sbin | /sbin/* | /srv | /srv/* | /sys | /sys/* | /tmp | /tmp/* | /var/tmp/* | \
                /usr | /usr/* | /var | /var/tmp | /var/account | /var/account/* | /var/backups | \
                /var/backups/* | /var/cache | /var/cache/* | /var/crash | /var/crash/* | /var/games | \
                /var/games/* | /var/lib | /var/lib/* | /var/local | /var/local/* | /var/lock | \
                /var/lock/* | /var/log | /var/log/* | /var/mail | /var/mail/* | /var/opt | \
                /var/opt/* | /var/run | /var/run/* | /var/spool | /var/spool/* | /var/yp | /var/yp/*)
                return 3
                ;;
        esac
    fi
    _ghc_root_norm="$_ghc_ro"
    return 0
}

# _ghc_pt_target <file>: validate a .git POINTER FILE and derive the
# gitdir its heal-worthy operands live in (issue #777: the #704 O4
# layout seals every kit-managed checkout as `gitdir: <storage>/
# <name>.git` -- a FILE the sweeps' old -type d find never matched --
# and plain linked worktrees carry the same shape pointing at
# <gitdir>/worktrees/<id>). rc 0: candidate in _ghc_pt_out. rc 1:
# refused -- every arm except the regular-file gate rides a ui_detail
# skip note. Semantics:
#   - a REGULAR file only (review a C2): an entry swapped to a FIFO
#     in the find->resolve window is refused without a read -- the
#     one SILENT refusal class (a vanished or swapped entry is
#     attacker noise, no row -- the git-protection doctrine), and the
#     check->open window stays bounded, not eliminated (the pin
#     covers the pre-gate case; the race itself is the L5
#     accepted-window class);
#   - the first `gitdir: ` line wins (git writes exactly one);
#   - targets are ABSOLUTE, carry no control byte (a crafted target
#     must not reach report rows raw -- the _gp_rowkey class,
#     git-protection-core) and are form-gated after trailing-slash
#     normalization (the _ghc_root_ok arms, parity made true);
#   - the relative spelling is the submodule form (gitdir: ../.git/
#     modules/<name>), and .git/modules is developer-pinned with no
#     group write by the fs baseline (#655 b Q4) -- healing into it
#     would fight the baseline, so the submodule class is out of the
#     sweep's scope by design;
#   - a NOMINATION restriction (review a C1): the resolved target
#     must be a child of the git-protection storage root or a
#     `.git`-named directory. Pointer files sit in agent-writable
#     trees, and heal-index-head's gates pass ANY HEAD+objects-shaped
#     directory under an allowlisted root -- without this restriction
#     a planted pointer could nominate, say, a developer's bare
#     `mirror.git` for a root chown of its operand set, a target the
#     pre-#777 -type d walk could never reach. The two accepted
#     classes are exactly the ones the kit itself deploys: storage
#     children (the sticky, dev-owned storage -- the agent cannot
#     plant one) and `.git`-named gitdirs (which the find already
#     enumerates as directories under the conf roots -- no widening).
#     Storage resolves like heal-index-head's own allowlist leg
#     (GH_STORAGE seam, then GITDIR_STORAGE from install.conf,
#     reader-side validated through _ghc_root_ok with its
#     trailing-slash normalization -- review b B1/B2);
#   - a worktree registration target collapses to its COMMON gitdir
#     first (the hooks' --git-common-dir parity); a registration whose
#     common dir the pattern cannot recognize (a bare repo not named
#     *.git) is a foreign nomination and refused here, not by the
#     downstream shape gate;
#   - everything downstream (allowlist, realpath, shape) stays
#     heal-index-head's own gate: this is enumeration hygiene only --
#     nothing here authorizes a heal.
_ghc_pt_target() {
    _ghc_pt_file=$1
    [ -f "$_ghc_pt_file" ] || return 1
    _ghc_pt_t=$(sed -n 's/^gitdir: //p' "$_ghc_pt_file" 2>/dev/null | head -n 1)
    case "$_ghc_pt_t" in
        '')
            ui_detail "skip (pointer): no gitdir: line: $_ghc_pt_file"
            return 1
            ;;
    esac
    case "$_ghc_pt_t" in
        /*) ;;
        *)
            ui_detail "skip (pointer): relative target (submodule form -- .git/modules is developer-pinned,""\
 never healed): $_ghc_pt_file"
            return 1
            ;;
    esac
    case "$_ghc_pt_t" in
        *[[:cntrl:]]*)
            ui_detail "skip (pointer): target carries a control byte: $_ghc_pt_file"
            return 1
            ;;
    esac
    while :; do
        case "$_ghc_pt_t" in
            ?*/) _ghc_pt_t="${_ghc_pt_t%/}" ;;
            *) break ;;
        esac
    done
    [ -n "$_ghc_pt_t" ] || {
        ui_detail "skip (pointer): target is the filesystem root: $_ghc_pt_file"
        return 1
    }
    case "$_ghc_pt_t" in
        *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]* | *[\*\?\[]*)
            ui_detail "skip (pointer): malformed target (dot, empty segment, whitespace, or glob): $_ghc_pt_file"
            return 1
            ;;
    esac
    case "$_ghc_pt_t" in
        *.git/worktrees/*) _ghc_pt_t="${_ghc_pt_t%/worktrees/*}" ;;
    esac
    # nomination gate (review a C1): storage child or `.git`-named.
    case "${_ghc_pt_t##*/}" in
        .git)
            _ghc_pt_out="$_ghc_pt_t"
            return 0
            ;;
    esac
    _ghc_pt_stor="${GH_STORAGE:-$(_ghc_key GITDIR_STORAGE)}"
    # Storage validation — heal-index-head's own leg's parity (review
    # b B1/B2): the value is reader-side re-validated through
    # _ghc_root_ok (absolute, form-clean, no system path or agent
    # home — the #674 a A1 reader mirror; _ghc_root_norm carries the
    # trailing-slash strip, #765 a M2). An empty (missing key — the
    # DEFAULT, non-adopted host), relative, `none`-marked or refused
    # storage DISABLES the storage arm entirely: an unvalidated empty
    # pattern would degenerate to `/*` and accept EVERY absolute
    # target (review b B1), and a hand-edited value would steer the
    # read-only report surfaces (B2). `.git`-named targets stay the
    # only accepted class without a storage.
    _ghc_pt_stor_ok=0
    _ghc_pt_rk=0
    _ghc_root_ok "$_ghc_pt_stor" || _ghc_pt_rk=$?
    if [ "$_ghc_pt_rk" -eq 0 ] && [ -n "$_ghc_root_norm" ]; then
        _ghc_pt_stor="$_ghc_root_norm"
        _ghc_pt_stor_ok=1
    fi
    if [ "$_ghc_pt_stor_ok" = 1 ]; then
        case "$_ghc_pt_t" in
            "$_ghc_pt_stor"/*)
                _ghc_pt_out="$_ghc_pt_t"
                return 0
                ;;
        esac
    fi
    ui_detail "skip (pointer): target outside the storage root and not a .git dir (foreign or planted): $_ghc_pt_file"
    return 1
}

_git_heal_on() {
    _ghc_on_dev=$(_ghc_devuser)
    _ghc_on_home=$(_ghc_devhome "$_ghc_on_dev")
    if [ -z "$_ghc_on_home" ] || [ ! -d "$_ghc_on_home" ]; then
        ui_error "git-heal: no home for user $_ghc_on_dev — cannot set core.hooksPath"
        exit 1
    fi
    if ! _ghc_pieces_ok; then
        ui_error "git-heal: heal hooks incomplete under $(_ghc_libdir)/git-heal — run 'opk update' first"
        exit 1
    fi
    # Sudoers first: without the grant the hooks would fire but the
    # heal could never elevate (a kit installed before #671 carries a
    # template without the line). Sudoers_deploy validates with visudo
    # and stages atomically; it refuses loud on any failure.
    if [ -f "$(_ghc_libdir)/sh/sudoers-deploy.sh" ] &&
        [ -f "$(_ghc_libdir)/templates/sudoers.template" ]; then
        # shellcheck disable=SC1090
        SD_SUDO="" . "$(_ghc_libdir)/sh/sudoers-deploy.sh" ||
            {
                ui_error "git-heal: could not source sudoers-deploy.sh"
                exit 1
            }
        if ! SD_SUDO="" sudoers_deploy "$(_ghc_libdir)/templates/sudoers.template" "$_ghc_on_dev"; then
            ui_error "git-heal: sudoers re-render failed — nothing else was changed"
            exit 1
        fi
    else
        ui_error "git-heal: sudoers-deploy.sh or sudoers.template missing under $(_ghc_libdir) — run 'opk update' first"
        exit 1
    fi
    ui_info "Setting the developer's global core.hooksPath to the kit heal hooks ..."
    if ! _ghc_devgit "$_ghc_on_dev" "$_ghc_on_home" \
        config --global core.hooksPath "$(_ghc_hooksdir)"; then
        ui_error "git-heal: could not write core.hooksPath for $_ghc_on_dev"
        exit 1
    fi
    # Heal every kit-managed gitdir once: enumerate the .git dirs
    # under each projects.conf root (the same universe the hook
    # allowlist covers — roots are SCAN roots like /var/www/vhosts,
    # not project dirs, so depth-1 would find nothing), with every
    # conf line re-validated reader-side first (files.md contract,
    # #674 a A1). No path-sane sourcing here by design: the reader
    # mirror is the house shape (uninstall-core, update-core, config
    # refresh, bin/opk handover all ship inline mirrors).
    _ghc_on_conf="${GH_PROJECTS_CONF:-/etc/opencode-permissions-kit/projects.conf}"
    if [ -f "$_ghc_on_conf" ]; then
        # Main-shell pre-probe (#710 b D2): the tee call sites below
        # are pipeline forks — without this the probe re-runs and the
        # warn re-prints once per root (N+1 on a broken-python3 host).
        # Forks inherit the cache the main shell just wrote.
        _ghc_py_probe
        _ghc_on_list=$(mktemp) || {
            ui_error "git-heal: mktemp failed — cannot enumerate heal targets"
            exit 1
        }
        # Raw .git entries stage separately from the resolved candidate
        # list (#777): the resolver's skip notes ride ui_detail (stdout)
        # and must never leak into the data list a pipeline feeds.
        _ghc_on_raw=$(mktemp) || {
            ui_error "git-heal: mktemp failed — cannot stage the .git scan"
            rm -f "$_ghc_on_list"
            exit 1
        }
        while IFS= read -r _ghc_on_root; do
            case "$_ghc_on_root" in '' | '#'*) continue ;; esac
            _ghc_rk_rc=0
            _ghc_root_ok "$_ghc_on_root" || _ghc_rk_rc=$?
            if [ "$_ghc_rk_rc" -ne 0 ]; then
                case "$_ghc_rk_rc" in
                    2) _ghc_on_why="agent home is never a project root" ;;
                    3) _ghc_on_why="system path is never a project root" ;;
                    *) _ghc_on_why="not an absolute root, or malformed (dot, empty segment, whitespace, or glob)" ;;
                esac
                ui_detail "skip (conf): $_ghc_on_why: $_ghc_on_root"
                continue
            fi
            _ghc_on_root="$_ghc_root_norm"
            [ -d "$_ghc_on_root" ] || continue
            # rc contract (#710 a B2): the pipeline's rc is the tee's —
            # the cat fallback passes find's stream through unchanged,
            # and find's own rc (partial walk on an unreadable subtree)
            # was already swallowed by the pre-#695 `|| true` shape.
            # BOTH .git shapes (#777): the classic directory and the
            # pointer FILE — the _gp_projects spelling.
            find "$_ghc_on_root" -name .git \( -type d -o -type f \) 2>/dev/null |
                _ghc_progress_tee "finding .git entries" >>"$_ghc_on_raw" || true
        done <"$_ghc_on_conf"
        # Resolve in the MAIN shell (#777): directories pass through,
        # pointer files through _ghc_pt_target (a worktree pointer
        # contributes its common gitdir — the same target the main
        # checkout's pointer names, so dedup follows). Main shell on
        # purpose: skip notes are ui_detail calls, and a pipeline fork
        # would fold them into the data list.
        while IFS= read -r _ghc_on_e; do
            [ -n "$_ghc_on_e" ] || continue
            if [ -d "$_ghc_on_e" ]; then
                printf '%s\n' "$_ghc_on_e" >>"$_ghc_on_list"
                continue
            fi
            if _ghc_pt_target "$_ghc_on_e"; then
                printf '%s\n' "$_ghc_pt_out" >>"$_ghc_on_list"
            fi
        done <"$_ghc_on_raw"
        rm -f "$_ghc_on_raw"
        LC_ALL=C sort -u -o "$_ghc_on_list" "$_ghc_on_list" 2>/dev/null ||
            ui_detail "git-heal: dedup sort failed — duplicate candidates may heal twice"
        _ghc_progress_tee "re-pinning operands" <"$_ghc_on_list" |
            while IFS= read -r _ghc_on_gd; do
                if _ghc_heal_once "$_ghc_on_gd"; then
                    # rc-true is "the heal ran", not "every chown
                    # succeeded": the heal exits 0 even when an operand's
                    # chown failed (it must never break a git op), so the
                    # detail line names the run, not a per-file result
                    # (#674 a A2 — the audit log carries those).
                    ui_detail "operand set re-pinned for $_ghc_on_gd"
                else
                    ui_detail "operand heal skipped for $_ghc_on_gd (see messages above)"
                fi
            done
        # Layer separation (issue #695: the old "heal ran for" wording
        # read as "this .git is healed now" while only the operand set
        # was re-pinned): name what the sweep did NOT do, and where
        # those bits come from — the fs baseline, which a plain
        # `opk update` re-applies when its semantics change (issue #696),
        # and for adopted checkouts the git-protection heal, whose own
        # pass re-applies them since #779 (the storage reheal sweep).
        if [ -s "$_ghc_on_list" ]; then
            # Wrap discipline (#782): quoted commands never break across
            # output lines — "'sudo opk / update'" read as two commands.
            # The "issue #779" tail is gone with this re-wrap: #695's
            # no-issue-IDs-in-user-facing-output sweep missed this site
            # (it shipped after that sweep); the row names the thing.
            ui_detail "operand sweep only: the gitdir-level bits (sticky .git,"
            ui_detail "dev-owned config/hooks) ride the group baseline — re-applied"
            ui_detail "by 'sudo opk update' when its semantics change; for adopted"
            ui_detail "(pointer-file) checkouts those bits live on the storage"
            ui_detail "gitdir — the git-protection heal sets them at adoption time"
            ui_detail "and re-applies them on every 'sudo opk update' /"
            ui_detail "'opk git-protection on' (the storage reheal sweep)"
        fi
        rm -f "$_ghc_on_list"
    fi
    ui_success "git heal hooks active — developer git operations now re-pin"
    ui_success "the measured operand set (.git/index, .git/HEAD and the widened"
    ui_success "operand carriers, each only when present) to the agent user (repo"
    ui_success "hooks stay off for the developer; hooksPath=$(_ghc_hooksdir))"
}

_git_heal_off() {
    _ghc_off_dev=$(_ghc_devuser)
    _ghc_off_home=$(_ghc_devhome "$_ghc_off_dev")
    if [ -z "$_ghc_off_home" ] || [ ! -d "$_ghc_off_home" ]; then
        ui_error "git-heal: no home for user $_ghc_off_dev — cannot unset core.hooksPath"
        exit 1
    fi
    _ghc_off_cur=$(_ghc_dev_hooks_path "$_ghc_off_dev")
    if [ "$_ghc_off_cur" = "$(_ghc_hooksdir)" ]; then
        if _ghc_devgit "$_ghc_off_dev" "$_ghc_off_home" \
            config --global --unset core.hooksPath; then
            ui_success "git heal hooks off — core.hooksPath unset for $_ghc_off_dev"
        else
            ui_error "git-heal: could not unset core.hooksPath for $_ghc_off_dev"
            exit 1
        fi
    elif [ -z "$_ghc_off_cur" ]; then
        ui_success "git heal hooks already off (no core.hooksPath set)"
    else
        # Kit-owned bytes only (the issue #100 consent discipline): a
        # foreign value is never modified, only reported.
        ui_success "git heal hooks off — core.hooksPath holds a foreign value"
        ui_detail "($_ghc_off_cur) — left untouched"
    fi
}

_git_heal_status() {
    _ghc_stt_dev=$(_ghc_devuser)
    _ghc_stt_agent=$(_ghc_agentuser)
    _ghc_stt_state=$(_ghc_state)
    case "$_ghc_stt_state" in
        on)
            ui_info "git-heal: ON — heal hooks active (core.hooksPath=$(_ghc_hooksdir))"
            ;;
        off)
            ui_info "git-heal: OFF — run 'sudo opk git-heal on' to keep the agent's"
            ui_info "        main-checkout git workflow (git add / git switch) green"
            ;;
        foreign)
            # Same state word the opk status / doctor rows render for a
            # foreign hooksPath ("OFF — ...", #674 a C6): one vocabulary
            # across the two surfaces the how-to documents as parallel.
            ui_info "git-heal: OFF — core.hooksPath holds a foreign value"
            ui_info "        ($(_ghc_dev_hooks_path "$_ghc_stt_dev")) — heal hooks not in effect;"
            ui_info "        'sudo opk git-heal on' would retake the path"
            ;;
        unknown)
            ui_info "git-heal: UNKNOWN — cannot read the developer's gitconfig"
            ;;
    esac
    if _ghc_pieces_ok; then
        ui_detail "kit pieces present (heal script + four hooks)"
    else
        ui_detail "kit pieces INCOMPLETE under $(_ghc_libdir)/git-heal — run 'opk update'"
    fi
    # Per-gitdir lockout rows: dev-owned operands under a sticky .git
    # lock the agent out until the heal hooks fire (off/foreign) or
    # the next developer git operation re-pins them (on: transient —
    # the same classification the opk status / doctor rows render,
    # #674 a C7). The row set mirrors heal-index-head's operand list
    # (#678 widening; existence-gated — absent files render nothing). The enumeration mirrors the on-sweep's RECURSION
    # (#674 a C3: every .git under each conf root — conf roots are
    # scan roots, config.sh parent registration; the literal
    # <root>/.git would miss every nested repo), deliberately NOT its
    # conf-line reader gate (#674 b D2): status is display-only, no
    # root operation — it renders the conf as written, so a
    # hand-edited line the sweep refuses loudly can still show rows
    # here (a bounded display residual; the sanctioned writer refuses
    # such lines, and the rows say something is off).
    _ghc_stt_conf="${GH_PROJECTS_CONF:-/etc/opencode-permissions-kit/projects.conf}"
    [ -f "$_ghc_stt_conf" ] || return 0
    # Loud but never fatal (#674 b D3): status must not die, but a
    # swallowed mktemp failure would silently drop the lockout rows
    # this section exists to show (the on-sweep twin fails loud).
    _ghc_stt_list=$(mktemp) || {
        ui_detail "git-heal: lockout rows unavailable (mktemp failed)"
        return 0
    }
    _ghc_stt_raw=$(mktemp) || {
        ui_detail "git-heal: lockout rows unavailable (mktemp failed)"
        rm -f "$_ghc_stt_list"
        return 0
    }
    # Fix-all-hint counter (#782): the lockout loop prints inside the
    # tee's pipeline FORK, so a main-shell counter variable would die
    # with the fork (the pipeline-tally class, conventions.md "Script
    # output style") — findings ride this temp file back instead. A
    # failed mktemp drops only the hint (loud), never the rows.
    _ghc_stt_cnt=$(mktemp) || {
        ui_detail "git-heal: fix-all hint unavailable (mktemp failed)"
        _ghc_stt_cnt=""
    }
    ui_detail "git-heal: scanning conf roots for .git entries (dirs and pointer"
    ui_detail "files — large trees: this can take a while) ..."
    # Main-shell pre-probe (#710 b D2): the lockout row loop's tee is a
    # pipeline fork — probe here so the cache survives into the forks.
    _ghc_py_probe
    while IFS= read -r _ghc_stt_root; do
        case "$_ghc_stt_root" in '' | '#'*) continue ;; esac
        [ -d "$_ghc_stt_root" ] || continue
        # Loud on partial failure (#674 c E4): an unreadable subtree
        # silently loses its lockout rows otherwise — one notice per
        # affected root keeps the section honest (find rc 1 = errors
        # encountered, output still collected). BOTH .git shapes
        # (#777): classic directories and pointer FILES.
        find "$_ghc_stt_root" -name .git \( -type d -o -type f \) >>"$_ghc_stt_raw" 2>/dev/null ||
            ui_detail "git-heal: lockout rows may be incomplete under $_ghc_stt_root (unreadable)"
    done <"$_ghc_stt_conf"
    # Resolve in the MAIN shell (the on-sweep twin's #777 shape):
    # directories pass through, pointer files through _ghc_pt_target,
    # dedup on the resolved list (a worktree pointer and its main
    # checkout's pointer name the same common gitdir).
    while IFS= read -r _ghc_stt_e; do
        [ -n "$_ghc_stt_e" ] || continue
        if [ -d "$_ghc_stt_e" ]; then
            printf '%s\n' "$_ghc_stt_e" >>"$_ghc_stt_list"
            continue
        fi
        if _ghc_pt_target "$_ghc_stt_e"; then
            printf '%s\n' "$_ghc_pt_out" >>"$_ghc_stt_list"
        fi
    done <"$_ghc_stt_raw"
    rm -f "$_ghc_stt_raw"
    LC_ALL=C sort -u -o "$_ghc_stt_list" "$_ghc_stt_list" 2>/dev/null ||
        ui_detail "git-heal: dedup sort failed — rows may render duplicated"
    _ghc_progress_tee "checking lockouts" <"$_ghc_stt_list" |
        while IFS= read -r _ghc_stt_gd; do
            [ -n "$_ghc_stt_gd" ] || continue
            for _ghc_stt_f in index HEAD ORIG_HEAD REBASE_HEAD packed-refs \
                MERGE_HEAD MERGE_MSG MERGE_MODE AUTO_MERGE \
                CHERRY_PICK_HEAD REVERT_HEAD; do
                _ghc_stt_own=$(stat -c %U "$_ghc_stt_gd/$_ghc_stt_f" 2>/dev/null) || continue
                if [ "$_ghc_stt_own" != "$_ghc_stt_agent" ]; then
                    if [ "$_ghc_stt_state" = on ]; then
                        # #782: the label line stays whole, the operand
                        # line carries path + owner — the old wrap broke
                        # the sentence mid-verb ("operation / heals it):").
                        ui_detail "lockout (transient — the next developer git operation heals it):"
                        ui_detail "$_ghc_stt_gd/$_ghc_stt_f is $_ghc_stt_own-owned"
                    else
                        ui_detail "lockout risk: $_ghc_stt_gd/$_ghc_stt_f is $_ghc_stt_own-owned —"
                        ui_detail "'sudo opk git-heal on' heals and keeps it healed"
                    fi
                    # Hint counter (the temp file above): one mark per
                    # rendered row; a write failure past a successful
                    # mktemp is an accepted residual (disk full between
                    # the two) — the rows above are the finding, the
                    # hint is a nicety.
                    if [ -n "$_ghc_stt_cnt" ]; then
                        printf 'x\n' >>"$_ghc_stt_cnt" 2>/dev/null || true
                    fi
                fi
            done
        done
    rm -f "$_ghc_stt_list"
    # #782: ONE fix-all hint for the whole row set (blank line + two
    # rows), rendered only when lockout rows did — the state row above
    # already names the command when nothing is locked out.
    if [ -n "$_ghc_stt_cnt" ] && [ -s "$_ghc_stt_cnt" ]; then
        [ "${UI_SILENT:-0}" = 1 ] || printf '\n'
        ui_info "git-heal: fix all lockouts with:"
        ui_detail "sudo opk git-heal on"
    fi
    # rc-neutral tail (#785 a A2): an AND-list here would return 1 when
    # the counter mktemp failed -- and the display command's exit code
    # would claim a failure its complete, loud report does not contain.
    if [ -n "$_ghc_stt_cnt" ]; then
        rm -f "$_ghc_stt_cnt"
    fi
}

git_heal_cli() {
    _ghc_cmd="${1:-}"
    [ $# -gt 0 ] && shift
    if [ "$_ghc_cmd" != "on" ] && [ "$_ghc_cmd" != "off" ] &&
        [ "$_ghc_cmd" != "status" ]; then
        ui_error "usage: opk git-heal <on|off|status>"
        exit 64
    fi
    [ $# -eq 0 ] || {
        ui_error "usage: opk git-heal <on|off|status>"
        exit 64
    }
    if [ "$(id -u)" -ne 0 ]; then
        # Loop guard (#479 a F24, the openchamber shape): the re-exec
        # enters bin/opk again, which dispatches back into this arm --
        # a sudo that exits 0 without actually elevating (fake or
        # broken sudo) would exec this cycle forever. Refuse on the
        # marker the re-exec itself carries.
        if [ "${OPK_GITHEAL_ROOT:-}" = "1" ]; then
            ui_error "git-heal: sudo did not elevate — giving up"
            exit 1
        fi
        exec ${GH_SUDO-sudo} env OPK_GITHEAL_ROOT=1 sh "$(_ghc_libdir)/bin/opk" git-heal "$_ghc_cmd"
    fi
    # Running as root from here.
    case "$_ghc_cmd" in
        on) _git_heal_on "$@" ;;
        off) _git_heal_off "$@" ;;
        status) _git_heal_status "$@" ;;
    esac
}
