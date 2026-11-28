# shellcheck shell=sh
# opencode permissions kit -- fs-baseline.sh
#
# Group baseline with live progress (issue #14): chgrp -R + setgid +
# group rw + default ACLs over a project root. First installs on large
# trees (hundreds of repos) take minutes per pass — each pass streams a
# running entry count to stderr so the user sees movement instead of a
# frozen prompt. Paths flow as a NUL stream:
#
#   sudo find <root> <expr> -print0 | _fsb_count_tee <label> | sudo xargs -0 -r <cmd>
#
# _fsb_count_tee forwards the bytes untouched and only COUNTS the NUL
# bytes, so the overhead per entry is a memcmp, not a process or a line
# parser. It uses python3 when python3 is HEALTHY — probed once per run
# (issue #223): an ungated tee in a MUTATING pass died with a missing
# or broken interpreter, xargs -r no-oped green on the empty stream,
# and the baseline was silently not applied. The gate degrades to a
# plain passthrough — the pass never depends on its progress display.
#
# POSIX sh, SOURCED by install.sh, config.sh and update.sh (checkout
# copy first, deployed LIBDIR fallback — same rules as ddev-handover.sh).
# Never executed directly. FS_SUDO overrides the sudo prefix ("" in
# tests; plain find/chgrp/chmod/setfacl for a same-user run). Note the
# plain "-": FS_SUDO="" must stay empty, a ":-" would re-substitute sudo.
# Deployed to /usr/local/lib/opencode-permissions-kit/sh/fs-baseline.sh.

_fsb_sudo() { ${FS_SUDO-sudo} "$@"; }

# _fsb_ancestor_traversable <dir> <group>
# True (0) when <dir> already lets the sharing group's members traverse
# it: other-x, the dir's own group is <group> with group-x, or a named
# group ACL entry grants x. Bit-level only (no probe user) — callers
# that know the agent user may prefer the exact probe in
# fs_ensure_traversable below.
_fsb_ancestor_traversable() {
    _fsba_mode=$(stat -c %A "$1" 2>/dev/null) || return 1
    # other x: the literal x OR the sticky-bit form t (/tmp); group x:
    # the literal x OR the setgid form s (the kit's own 2775 dirs).
    case "$_fsba_mode" in
        ?????????x | ?????????t) return 0 ;;
    esac
    if [ "$(stat -c %G "$1" 2>/dev/null)" = "$2" ]; then
        case "$_fsba_mode" in ??????x??? | ??????s???) return 0 ;; esac
    fi
    getfacl -p "$1" 2>/dev/null | grep -q "^group:$2:..x"
}

# fs_ensure_traversable <root> <group> [user]
# Grants traverse-only access (x — never read, no listing) to every
# ANCESTOR of <root> that blocks the sharing group's members. The
# baseline below fixes <root> downwards only, but a root under the
# developer's home (Ubuntu 24.04 ships $HOME as 0750 dev:dev) would
# stay unreachable for the agent anyway: resolving the root's path from
# / needs +x on EVERY component, so opencode and ddev fail with EACCES
# on the project dir while the root's own bits look perfect. ddev then
# misreports that as "a project cannot be created in the DDEV source
# code" — its fileutil.FileExists() is fail-open and reads EACCES as
# "exists" (pkg/fileutil/file_exists.go).
# Allow-ACL only — g:<group>:X, capital X never adds x to files — fully
# in the soft model: no deny entries, owner/group/mode stay untouched.
# [user] switches the per-ancestor check to an exact probe
# (sudo -u <user> test -x); without it (or with FS_SUDO="", tests) the
# bit-level heuristic above applies. Best-effort: ancestors on ACL-less
# filesystems only warn and never abort the baseline.
fs_ensure_traversable() {
    fsb_root="$1"
    fsb_group="$2"
    fsb_probe="${3:-}"
    [ -n "$fsb_root" ] && [ -d "$fsb_root" ] || return 0
    fsb_d=$(dirname "$fsb_root")
    while [ -n "$fsb_d" ] && [ "$fsb_d" != "/" ]; do
        fsb_need=1
        if [ -n "$fsb_probe" ] && [ "${FS_SUDO-sudo}" != "" ]; then
            # shellcheck disable=SC2086  # FS_SUDO is one word by contract
            ${FS_SUDO-sudo} -u "$fsb_probe" test -x "$fsb_d" 2>/dev/null && fsb_need=0
        else
            _fsb_ancestor_traversable "$fsb_d" "$fsb_group" && fsb_need=0
        fi
        if [ "$fsb_need" = 1 ]; then
            if _fsb_sudo setfacl -m "g:$fsb_group:X" "$fsb_d" 2>/dev/null; then
                printf '%s\n' "  traverse ACL g:$fsb_group on $fsb_d (x only — dir stays non-listable)" >&2
            else
                printf '%s\n' "  WARNING: could not grant traversal on $fsb_d (setfacl failed — ACL support?)""\
 — the agent may not reach $fsb_root" >&2
            fi
        fi
        # Fixed-point guard: a relative root would make dirname spin on
        # "." forever (unreachable via project_path_sane, but a manually
        # edited projects.conf could carry one) — stop when dirname stops
        # making progress (0.0.38 C13).
        _fsb_next=$(dirname "$fsb_d")
        [ "$_fsb_next" = "$fsb_d" ] && break
        fsb_d=$_fsb_next
    done
    return 0
}

# _fsb_py_probe: the health gate for the counter tee (issue #223, the
# _st_ddev_scan gate shape of #221 a W3). The tee sits in the DATA
# pipeline of a MUTATING root pass — an ungated python3 that is missing
# or broken dies at startup, xargs -r no-ops GREEN on the empty stream,
# and the baseline is silently not applied (false-green at a root-run
# site). `command -v` alone accepts a findable-but-broken interpreter
# (a pyenv shim to a removed version, a corrupt install), so the probe
# also RUNS it — isolated: `python3 -I` ignores PYTHONHOME/PYTHONPATH
# (#244 a S1), so neither breaking nor functional (module-shadowing)
# PYTHON* env poison can reach the probe or the tee; the imports are
# exactly the tee's. The -I scope is those env vars, not the whole
# environment — the loader route (LD_PRELOAD/LD_LIBRARY_PATH) and the
# PATH-resolved binary itself stay outside any python flag, root-owned
# trust surface like every root python3 the kit runs (#244 b S1);
# system site-packages stay processed too (-I implies -E -s -P, not
# -S): a .pth there executes at startup — same root-owned residual
# (#244 c S2).
# Probed once per run (_fsb_py_checked caches, _fsb_py_ok
# carries the verdict); on any doubt the pass degrades to a plain
# passthrough — it loses its live counter, never its data. One warn
# line names the degradation.
# Callers: _fsb_pass from the MAIN shell BEFORE the pipeline (a
# pipeline member forks, and a cache written inside the fork dies with
# it — the tee would re-probe and re-warn on every pass), plus
# _fsb_count_tee itself so direct tee calls get the gate too; with the
# cache set, the second call is a no-op.
_fsb_py_probe() {
    if [ "${_fsb_py_checked:-0}" != 1 ]; then
        _fsb_py_checked=1
        _fsb_py_ok=0
        command -v python3 >/dev/null 2>&1 &&
            python3 -I -c 'import os, sys' >/dev/null 2>&1 &&
            _fsb_py_ok=1
        if [ "$_fsb_py_ok" != 1 ]; then
            # The rerun exists for the interpreter's own diagnostic
            # stderr, not its rc (this branch already failed; #244 c
            # S3, the installer gate's #244 b S2 shape): a
            # present-but-broken python3 names its real problem above
            # the warn. An absent one is guarded off — no not-found
            # noise for a legitimate absence.
            command -v python3 >/dev/null 2>&1 &&
                python3 -I -c 'import os, sys' >/dev/null || true
            printf '  warn: live progress unavailable (python3 missing or broken) — passes apply without entry counters\n' >&2
        fi
    fi
}

# _fsb_count_tee <label>: stdin NUL-separated stream -> stdout (verbatim)
# + a "label: N entries" line on stderr, rewritten every 2000 entries
# and finalized with "— done" (a plain line, not a carriage return, so
# logs stay grep-able). Script via -c, NOT a heredoc: `python3 -` with a
# heredoc would consume stdin for the script itself and the tee would
# read nothing. Gated by _fsb_py_probe above (#223): without a healthy
# python3 the tee is a plain passthrough (cat) that PROPAGATES cat's rc
# (#265: a read error must fail the pass; only SIGPIPE — the consumer
# EPIPE — maps to the documented 0). Runs isolated (`-I`) like the
# probe: PYTHON* env poison cannot shadow the tee's imports either
# (#244 a S1). The -I scope is those env vars plus the user-site
# isolation -s/-P buy; system site-packages stay processed — the
# residual named at the probe above (#244 b S1, c S2). The two output
# streams carry DIFFERENT failure contracts (#265, pr-00263 c C1):
# stdout is the data stream (a consumer EPIPE aborts it, exit 0 per
# #244 a Q1), stderr is progress only (a write failure there — EPIPE
# from a closed sink, ENOSPC from a full device — degrades the counter
# and never touches the data stream).
_fsb_count_tee() {
    _fsb_py_probe
    if [ "${_fsb_py_ok:-0}" != 1 ]; then
        # rc contract (#265, pr-00263 b B2 — the cat arm's mask): the
        # old unconditional `return 0` discarded cat's rc — a read
        # error truncated the operand stream with every pipeline member
        # green and _FSB_ERRORS stayed 0, while callers printed the
        # success line this file's own contract forbids ("must not
        # print over a baseline that did not fully apply"). Propagate:
        # 0 stays 0, a read error fails the pass — in production
        # pipefail fails the pipeline, in _fsb_pass the captured rc
        # feeds _FSB_ERRORS. The ONE rc that must not fail is 141
        # (128+SIGPIPE): the consumer closed early or died — the python
        # arm's documented consumer-EPIPE 0 below (#244 a Q1); a
        # consumer that DIED still fails the pass through its own rc in
        # the pipeline, and pipefail reads that member, not this one.
        # The `|| _fsb_cat_rc=$?` guard is load-bearing (#418 a A4):
        # every shipped caller runs set -e — errexit would fire AT the
        # failing cat (141 included) BEFORE the mapping runs, and the
        # documented consumer-EPIPE 0 would silently degrade to a
        # failed pass (a false RED in degraded-python mode). The
        # ||-context suppresses errexit for cat alone; everything after
        # still runs under set -e. (A process inheriting SIGPIPE
        # ignored — CI runners do — turns the death into cat rc 1
        # "write error"; that path fails loud through pipefail: safe —
        # pinned by the rider's SIG_IGN leg in test-fs-baseline.sh §13
        # (#419).)
        _fsb_cat_rc=0
        cat || _fsb_cat_rc=$?
        if [ "$_fsb_cat_rc" -eq 141 ]; then
            return 0
        fi
        return "$_fsb_cat_rc"
    fi
    python3 -I -c '
import os, sys
# Keep this -c source pure ASCII (#510): a 7-bit locale refuses
# non-ASCII command bytes at decode ("Unable to decode the command
# from the command line"), before any code runs. Comments stay "--";
# the rendered em-dash rides \u2014 (identical stderr).
label = sys.argv[1]
counted = 0
shown = 0
aborted = False
progress_dead = False
try:
    while True:
        chunk = sys.stdin.buffer.read(1 << 20)
        if not chunk:
            break
        counted += chunk.count(b"\0")
        sys.stdout.buffer.write(chunk)
        sys.stdout.buffer.flush()
        if not progress_dead and counted - shown >= 2000:
            shown = counted
            try:
                sys.stderr.write("\r    %-16s %d entries" % (label, counted))
                sys.stderr.flush()
            except OSError:
                # stderr-side failure only (#265, pr-00263 c C1): the
                # PROGRESS sink died -- EPIPE (BrokenPipeError is an
                # OSError subclass; the reader of the sink closed) or
                # e.g. ENOSPC (stderr at a full device) -- never the
                # data consumer. Degrade the progress display alone and
                # keep the data stream alive. Falling through to the
                # outer except here would dup2 stdout to devnull and
                # drop every buffered byte after this chunk for a sink
                # nobody reads (the false-green race: find already
                # finished, buffered bytes lost, every rc 0).
                progress_dead = True
                # And the interpreter shutdown flush must not retry the
                # dead sink either -- it would exit 120 over a progress
                # line (the stdout dup2 idiom below, stderr side).
                os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stderr.fileno())
except (BrokenPipeError, KeyboardInterrupt):
    # A dead consumer (xargs died first -- the pr-00221 W2/W6 sweep
    # recorded this missing clause -- or Ctrl-C hit the whole pipeline,
    # #221 a W6 shape) must not end the tee in a traceback, and an
    # aborted pass must not print its completion line -- counted is
    # bytes READ, not entries applied (#244 a S2/W3/Q4). The
    # interpreter shutdown flush over the broken pipe would print a
    # traceback anyway, so point stdout at devnull before exiting (the
    # CPython SIGPIPE idiom). rc contract, stated truly (#244 a Q1):
    # the production callers run bash WITH pipefail (install.sh:47,
    # config.sh:28, update.sh:41) and the rc of this pipeline lands
    # in the _fsbp_rc capture of _fsb_pass -- exiting 0 on EPIPE is
    # deliberate: a consumer that closed early cannot fail the pass
    # alone, while a consumer that DIED leaves its own rc in the
    # pipeline and pipefail fails the pass through it. Unit tests
    # observe dash (no pipefail); the 11c bash rider pins the
    # production shape.
    aborted = True
    os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
if counted and not aborted and not progress_dead:
    # progress_dead skips the line outright (the sink is known dead);
    # the try is the race belt -- the sink may die between the last
    # progress write and here, with the data already flushed. The lost
    # completion line is cosmetic (#265, pr-00263 c C1).
    try:
        sys.stderr.write("\r    %-16s %d entries \u2014 done\n" % (label, counted))
        sys.stderr.flush()
    except OSError:
        pass
' "$1"
}

# _fsb_pass <label> <root> <find-expr...> -- <cmd...>: one baseline pass
# over the NUL stream. The find expression comes through verbatim, the
# command after "--" receives the paths via xargs -0 (-r: no empty run).
#
# The consumer is a recheck loop, NOT a direct xargs exec (0.0.39e S1):
# find classifies each entry at SCAN time, and the scanned trees are
# group-writable by the semi-trusted agent — a file swapped for a symlink
# in the scan->exec window would be dereferenced by chgrp/chmod/setfacl
# on the operand, reaching outside the tree (the old chgrp -R never did:
# its traversal skipped symlinks by default). Every path is re-tested
# with [ -L ] immediately before its command runs; anything that is a
# symlink NOW is skipped. The command words are kit-fixed and space-free
# by construction (same contract as the find expression above).
# Component walk (#211 a F1, the 0.0.39h F2 class): a gate on the LEAF
# alone is bypassed by a PARENT directory swapped for a symlink inside
# the window — the whole find output is replayed from a temp file, so
# the window spans the full walk (minutes on large trees), and an
# operand whose parent is a link NOW resolves outside the tree. The
# worker therefore re-tests EVERY component between the scan root and
# the operand (chain-walker shape of agent_home_sane, staged-write.sh)
# and skips the operand when any of them is a symlink — including the
# SCAN ROOT itself (#421): the walk proper starts below it, so a root
# swapped between find and a batch would redirect every walk test and
# the command through it; the worker-head recheck fails the batch
# loud (_FSB_ERRORS counts it at the pass bookkeeping). Residual
# window (#420 a A4, mirrored from _un_revert_chown's header): the
# per-operand recheck->command gap is microsecond-scale and
# undetectable — the same accepted shape as the handover pair's
# gate->op residual.
_fsb_pass() {
    _fsbp_label="$1"
    _fsbp_root="$2"
    _fsbp_orig_root="$2"
    shift 2
    # Normalize the root's form (#211 b W7): find emits children without
    # the root's trailing slash, so a slashed root never matched the
    # worker's "$_root"/* walk pattern — the component walk silently
    # voided for the whole pass. Shipped callers feed project_path_sane'd
    # roots; this is defense in depth for future callers. '/' normalizes
    # to the empty string: a recursive baseline over the whole filesystem
    # is never legitimate (project_path_sane blocklists it) — refuse
    # loud rather than degrade the walk silently.
    while [ "${_fsbp_root%/}" != "$_fsbp_root" ]; do
        _fsbp_root="${_fsbp_root%/}"
    done
    if [ -z "$_fsbp_root" ]; then
        # The ORIGINAL root, captured before the shift (#211 c W2): the
        # positionals are renumbered by now, so $2 would name a find
        # expression word, never the refused root.
        echo "fs-baseline: refusing scan root '$_fsbp_orig_root' (the whole filesystem is never a baseline root)" >&2
        return 1
    fi
    _fsbp_expr=""
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        _fsbp_expr="$_fsbp_expr $1"
        shift
    done
    shift # consume --
    [ $# -gt 0 ] || return 0
    _fsbp_rc=0
    # Health probe from the MAIN shell (#223): _fsb_count_tee runs as a
    # pipeline member (a fork) — only here does the once-per-run cache
    # stick across the four passes.
    _fsb_py_probe
    # Named-cause mktemp guard (#431, the #429 B4 class beyond the
    # update scope): every shipped caller (config.sh, update.sh,
    # install.sh) runs set -eu — a raw failure aborted the pass
    # mid-run with only mktemp's own diagnostic. Counted like a
    # failed pass (the 0.0.43a F10 bookkeeping below): the summary
    # in fs_baseline_root fails the whole baseline loud instead of
    # letting the callers print "applied".
    _fsbp_nul="$(mktemp "${TMPDIR:-/tmp}/opk-fsb-pass.XXXXXXXX")" || {
        printf '  error: mktemp failed (is $TMPDIR writable?) — baseline pass "%s" under %s cannot run\n' \
            "$_fsbp_label" "$_fsbp_root" >&2
        _FSB_ERRORS=$((_FSB_ERRORS + 1))
        return 0
    }
    # Scratch registered with the caller's cleanup trap (#211 a F12,
    # staged-write.sh:44 shape): an aborted pass (Ctrl-C on a large
    # tree, minutes per pass) used to leave the root-owned NUL file
    # behind in /tmp. The plain rm below still covers the normal path.
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_fsbp_nul"
    fi
    # find's own status must survive into the pass bookkeeping (0.0.43b
    # W4): POSIX sh has no pipefail, a pipeline's rc is the LAST
    # command's alone, and xargs -r no-ops GREEN on an empty stream — a
    # find that died wholesale mid-walk still printed "applied". Walk
    # into a temp file first and track find's rc; its stderr stays
    # visible (the why behind the rc below). Live counting is
    # unaffected: the counter streams from the file while xargs chews it.
    # shellcheck disable=SC2086  # find expression built word-wise above
    _fsb_sudo find "$_fsbp_root" $_fsbp_expr -print0 >"$_fsbp_nul" || _fsbp_rc=$?
    if [ "$_fsbp_rc" -eq 0 ]; then
        _fsb_count_tee "$_fsbp_label" <"$_fsbp_nul" |
            _fsb_sudo xargs -0 -r sh -c '
                # $1 = arity of the fixed command, $2 = the scan root (for
                # the component walk below), then the kit-fixed command
                # words, then the batch of NUL-separated paths xargs
                # appended.
                _n=$1; shift
                _root=$1; shift
                # Scan-root recheck (#421): the component walk below
                # starts BELOW the root — a root swapped for a symlink
                # between find and this batch redirects every walk
                # test (and the command) through it, where components
                # are real directories and no gate fires. Fail the
                # batch loud; the pass bookkeeping counts it.
                if [ -L "$_root" ]; then
                    echo "  warn: scan root $_root was replaced by a symlink — baseline batch refused" >&2
                    exit 1
                fi
                _c=""
                while [ "$_n" -gt 0 ]; do _c="$_c $1"; shift; _n=$((_n - 1)); done
                # _fail accumulates across the WHOLE batch (0.0.44a V9):
                # a for-loop status alone is the LAST command executed, so
                # a chgrp/chmod/setfacl failure on any entry but the final
                # one left rc 0 — xargs green, the caller printed "applied"
                # over an incomplete baseline, the falsified W5 premise of
                # review 0.0.43b. Any failing entry fails the batch now.
                _fail=0
                for _p in "$@"; do
                    [ -L "$_p" ] && continue
                    # Parent-component recheck (#211 a F1): skip operands
                    # whose path crosses a symlinked DIRECTORY below the
                    # scan root — [ -L ] on the leaf alone misses a parent
                    # swapped in the scan->act window. String ops only
                    # (no word splitting): entries with spaces survive.
                    case "$_p" in
                    "$_root"/*)
                        _pre="$_root"
                        _rest="${_p#"$_root"/}"
                        while [ -n "$_rest" ]; do
                            case "$_rest" in
                                */*) _pre="$_pre/${_rest%%/*}"
                                     _rest="${_rest#*/}" ;;
                                *)   _pre="$_p"; _rest="" ;;
                            esac
                            [ -L "$_pre" ] && continue 2
                        done
                        ;;
                    esac
                    # Nailed .git pointer (#704/#754, issue #758): a
                    # regular file named .git carrying the immutable
                    # inode flag refuses chgrp/chmod even for root
                    # (EPERM — the seal IS the protection), which
                    # failed the chgrp and files passes wholesale on
                    # every git-protection project. The migration
                    # writes pointers dev:opencode 664 BEFORE chattr +i,
                    # so the target state of these passes holds
                    # already — skip instead of failing the batch.
                    # lsattr-gated: an unnailed pointer or a worktree
                    # registration (plain files, never sealed) stays a
                    # normal operand; -f-gated: a .git DIRECTORY is
                    # never skipped (only the pointer FILE layout
                    # carries +i). A missing lsattr leaves the skip
                    # inert — the old fail-loud behavior applies.
                    case "$_p" in
                    */.git)
                        if [ -f "$_p" ]; then
                            _lsv=$(lsattr "$_p" 2>/dev/null)
                            _lsv=${_lsv%% *}
                            case "$_lsv" in
                            *i*) continue ;;
                            esac
                        fi
                        ;;
                    esac
                    # shellcheck disable=SC2086  # kit-fixed, space-free words
                    $_c "$_p" || _fail=1
                done
                [ "$_fail" -eq 0 ]
              ' xargs-sh "$#" "$_fsbp_root" "$@" || _fsbp_rc=$?
    fi
    rm -f "$_fsbp_nul"
    # Per-pass failure tracking (0.0.43a F10): without pipefail the old
    # unconditional `return 0` made a wholesale pass failure (rc 123 =
    # xargs had failing batches, 125/126/127 = xargs/interpreter trouble)
    # invisible — callers printed "applied" regardless. Counted here,
    # summarized and propagated by fs_baseline_root below.
    if [ "$_fsbp_rc" -ne 0 ]; then
        _FSB_ERRORS=$((_FSB_ERRORS + 1))
        printf '  warn: baseline pass "%s" hit errors (rc %s) under %s — see the messages above\n' \
            "$_fsbp_label" "$_fsbp_rc" "$_fsbp_root" >&2
    fi
    return 0
}

# --- .git metadata heal (issue #644, wave #651) ---------------------------------
#
# The shared-tree execution gap (#644, confirmed on a kit-managed machine
# 2026-11-18): the DEVELOPER's git executes from agent-writable surfaces.
# A hook planted into .git/hooks, or a repo-config arm (core.fsmonitor,
# core.hooksPath override, diff-driver registration, core.pager/editor),
# runs with the developer's uid, groups and HOME on the next commit or
# `git status`. The four passes above share .git wholesale (issue #17 —
# the agent must be able to commit); the heal narrows exactly the
# execution-bearing metadata, OS-side, while the agent's git workflow
# stays intact (verified live: add, commit, branch ops and a push
# --dry-run all green under the healed state; planted-hook,
# git-config-write and rename-away probes all blocked — evidence in
# issue #644):
#
#   <project root>   NO sticky bit (#702/#703 — the #655 a C1 root and
#                     ancestor stickies are REMOVED, and a legacy bit
#                     from an earlier heal is stripped as migration:
#                     installed bases carry it). Measured on kit-managed
#                     hosts, the sticky's everyday costs (#699 developer
#                     O_CREAT writes, #682 rc-0 stale-dirty checkouts,
#                     #701 tooling renames dying fail-open, #697
#                     handback wipes) outweighed the wholesale-swap
#                     prevention; W1/W2 (stealth .git swap, project-dir
#                     swap) are accepted residuals — see
#                     docs/concepts/security-model.md and the detection
#                     row in opk status/doctor (#653/#703).
#   .git              sticky +t only — mode and group stay (the agent
#                     keeps creating lockfiles, objects, refs and worktree
#                     registrations; it can no longer unlink or rename
#                     over the developer-owned entries below)
#   .git/config       developer-owned 644, ACLs stripped — plain
#                     commits/pushes only READ it (the first-push `-u`
#                     tracking write is a documented cost below); any
#                     write goes through lock+rename, and the sticky
#                     bit kills the rename
#   .git/hooks        developer-owned 755, ACLs stripped — no planting;
#                     the .sample files stay readable for everyone. The
#                     directory setgid bit SURVIVES a numeric chmod on
#                     Linux (measured — root included): harmless here,
#                     it only steers group inheritance of NEW entries,
#                     and without group write there are none.
#   .git/modules      the container and every gitdir beneath it pinned
#                     developer-owned with NO GROUP WRITE — that lost
#                     write is what blocks wholesale-replacing a child
#                     gitdir (#655 b Q4: the sticky bit only
#                     restricts users who still have directory write;
#                     post-pin the agent has none — sticky is
#                     load-bearing where group write REMAINS, i.e. on
#                     .git itself). Every DIRECT child dir of any dir
#                     named modules pinned marker-free (a hooks-less
#                     planted gitdir is pinned too, #655 a C3): dir
#                     3755-in-practice (setgid rides along, see hooks
#                     above), config 644, hooks 755, hookwarn and the
#                     worktree arm included; nested modules
#                     (modules/<a>/modules/<b>) ride the same find.
#                     A SYMLINKED container or child is never followed
#                     — surfaced as a warn (#655 b C3).
#   .git/worktrees    sticky +t only (registrations stay
#                     agent-manageable — `git worktree add` by the agent
#                     keeps working); each registration's commondir and
#                     gitdir POINTER FILES are pinned developer-owned 644
#                     — the repointing arm dies, the workflow lives.
#                     The registration dirs themselves keep group write:
#                     merge-state files (MERGE_HEAD and friends) must
#                     keep appearing for agent worktree merges.
#
# Owner derivation: the project root's owner is the developer in the kit
# model. A root owned by the agent user is an agent-created tree — the
# heal still runs (pinning to that owner), it just buys nothing there;
# that class is a documented residual (#652). And chmod alone is not the
# mechanism (git writes through lock+rename, which needs directory
# write, not file write — measured in the #644 probe): OWNERSHIP is what
# the heal pins.
#
# Accepted workflow costs (shipped with #651): repo-scope `git config`
# and `git submodule add` fail for the agent (both write .git/config) —
# including the tracking write of a first `git push -u`, so agents push
# without -u (git push origin <branch>; the transfer itself completes —
# field-reported 2026-11-18 and recorded in issue #644); agent-side
# `git gc` can hit the sticky bit
# renaming packed-refs (with the #678-heal hooks on, that flip heals
# on the next developer git operation — the cost is then a window,
# not a state); merges inside agent-created worktrees keep
# working (their gitdir retains create rights — only the pointer
# files and the gitdir's own metadata are pinned); a repo the agent
# cloned INTO a developer-owned
# project tree is healed to the root's owner as well — the agent loses
# repo-config writes in its own nested clone (#655 a S3; work in the
# main checkout or an agent-owned root instead).
# REMOVED cost (#702/#703): the agent once could not rename or delete
# developer-owned TOP-LEVEL entries (project root sticky, #655 a C1) —
# the root/ancestor sticky is gone, so that friction is gone with it;
# the flip side (the agent CAN rename/unlink dev-owned top-level
# entries, W3) is an accepted residual like W1/W2 above.
# Heal-operand lockout (#671, widened #678): the heal's operand
# metadata (.git/index, .git/HEAD and the #678 carriers) stays
# deliberately UNpinned here — git rewrites it via lock+rename, so
# ownership floats with the last writer, and after a developer
# checkout/pull the files land developer-owned: the sticky .git then
# blocks the agent's staging and branch operations (git add, git
# switch) until ownership returns.
# The baseline cannot close that (every developer git op re-flips it);
# the git heal hooks close it instead — maintainer-side post-merge/
# post-checkout/post-rewrite/post-index-change hooks that re-pin the
# measured operand set (index, HEAD and the widened #678 carriers,
# incl. packed-refs: a dev gc flip soft-breaks agent gc the same way
# and heals on the same cadence) to the agent user after every
# developer git operation
# (`opk git-heal on`, git-heal/heal-index-head + git-heal-core.sh).
# Residual: the .git POINTER FILE inside agent worktree trees stays
# agent-writable (a delete+recreate sidesteps any pin) — #652 documents,
# #653 detects. Same for content planted BEFORE the heal: metadata
# pinning preserves a planted hook file's exec bit and content (the
# heal warns about non-sample entries it finds; removal is a human
# decision), and a .git.old-style pre-existing swap is not detected
# here — #653's detection arm covers both. This is a deliberate scoped
# exception to the repo's
# soft-only security rule (AGENTS.md, Rules): OS-level narrowing on .git
# internals ddev
# never touches, decided with the maintainer in #651.

# _fsb_comp_clear <root> <path>: the L5 component-walk gate for the
# heal's root ops — true when no component between <root> (exclusive)
# and <path> (inclusive) is a symlink. Same walk shape as the _fsb_pass
# worker above; a standalone function because the heal acts from the
# main shell, not from an xargs worker string.
_fsb_comp_clear() {
    case "$2" in
        "$1"/*) ;;
        *) return 1 ;;
    esac
    _fscc_pre=$1
    _fscc_rest=${2#"$1"/}
    while [ -n "$_fscc_rest" ]; do
        case "$_fscc_rest" in
            */*)
                _fscc_pre=$_fscc_pre/${_fscc_rest%%/*}
                _fscc_rest=${_fscc_rest#*/}
                ;;
            *) _fscc_pre=$2 _fscc_rest="" ;;
        esac
        [ -L "$_fscc_pre" ] && return 1
    done
    return 0
}

# _fsb_heal_skip <path>: a symlinked operand (or a path whose components
# turned into links under us — the agent-writable tree moved between
# scan and act) is skipped with a warn, NOT a baseline failure: parity
# with the _fsb_pass worker, which skips symlinked operands the same
# way. The #653 detection surface reports planted hooks and heal drift.
_fsb_heal_skip() {
    printf '  warn: git heal skipped %s (symlinked path — not followed)\n' "$1" >&2
}

# _fsb_heal_err <path> <what>: a failed op counts into _FSB_ERRORS and
# fails the baseline loud through the summary gate in fs_baseline_root —
# "agent cannot commit" weeks later is the worse failure mode.
_fsb_heal_err() {
    printf '  warn: git heal: %s failed on %s — see the message above\n' "$2" "$1" >&2
    _FSB_ERRORS=$((_FSB_ERRORS + 1))
}

# _fsb_heal_sticky <root> <path>: add the sticky bit to ONE directory
# that must keep its sharing mode (component walk + leaf recheck first —
# L5; missing dirs are a no-op: a pristine repo has no worktrees dir).
_fsb_heal_sticky() {
    _fshs_p=$2
    [ -L "$_fshs_p" ] && {
        _fsb_heal_skip "$_fshs_p"
        return 0
    }
    [ -d "$_fshs_p" ] || return 0
    _fsb_comp_clear "$1" "$_fshs_p" || {
        _fsb_heal_skip "$_fshs_p"
        return 0
    }
    _fsb_sudo chmod +t "$_fshs_p" || _fsb_heal_err "$_fshs_p" "chmod +t"
    return 0
}

# _fsb_heal_unsticky <root> <path>: STRIP the sticky bit from ONE
# directory (#702/#703 — the #655 root/ancestor sticky is removed;
# installed bases carry the bit, so the strip is the migration). Twin
# of _fsb_heal_sticky with identical gates (component walk + leaf
# recheck first — L5; missing dirs a no-op), so the same enumeration
# that once added the bit now takes it back. Symlinked operands skip
# with the same warn, never a follow.
_fsb_heal_unsticky() {
    _fshu_p=$2
    [ -L "$_fshu_p" ] && {
        _fsb_heal_skip "$_fshu_p"
        return 0
    }
    [ -d "$_fshu_p" ] || return 0
    _fsb_comp_clear "$1" "$_fshu_p" || {
        _fsb_heal_skip "$_fshu_p"
        return 0
    }
    _fsb_sudo chmod -t "$_fshu_p" || _fsb_heal_err "$_fshu_p" "chmod -t"
    return 0
}

# _fsb_heal_pin <root> <owner> <group> <path> <mode>: pin ONE entry
# developer-owned with a fixed mode and no extended ACLs (chown ->
# chmod -> setfacl -b, the pilot-verified sequence). Missing entries are
# a clean no-op — a bare `git init` carries config and hooks, but a
# damaged or foreign gitdir may not.
_fsb_heal_pin() {
    _fshp_p=$4
    [ -L "$_fshp_p" ] && {
        _fsb_heal_skip "$_fshp_p"
        return 0
    }
    [ -e "$_fshp_p" ] || return 0
    _fsb_comp_clear "$1" "$_fshp_p" || {
        _fsb_heal_skip "$_fshp_p"
        return 0
    }
    _fsb_sudo chown "$2:$3" "$_fshp_p" || _fsb_heal_err "$_fshp_p" "chown $2"
    _fsb_sudo chmod "$5" "$_fshp_p" || _fsb_heal_err "$_fshp_p" "chmod $5"
    _fsb_sudo setfacl -b "$_fshp_p" || _fsb_heal_err "$_fshp_p" "setfacl -b"
    return 0
}

# Loop discipline for the two scans below (and the driver): find output
# goes through a temp file and a redirect-while, never a pipeline while
# — _FSB_ERRORS increments inside a pipe member die with its subshell
# (the pipeline-tally class, agent/conventions.md "Script output style").

# _fsb_heal_hookwarn <gitdir>: content-persistence visibility (#644,
# #655 a C1/b S3) for ONE gitdir's hooks dir — the heal pins METADATA, a
# hook planted before it keeps its exec bit and content. Informational
# and uncounted (removal stays a human decision; the #653 detection
# surface automates the report). Called for the main gitdir AND every
# module gitdir. The wc guard degrades on a missing wc OR a failed find
# (both stderr-suppressed) to "no warn" instead of aborting the
# caller's set -e — the warn is informational, never load-bearing
# (#655 b S1 pins the degraded branch).
_fsb_heal_hookwarn() {
    _fshw_gd=$1
    [ -d "$_fshw_gd/hooks" ] && [ ! -L "$_fshw_gd/hooks" ] || return 0
    # One TYPE line per entry (#785 a A1 sweep, the status/doctor twins'
    # class): a newline inside an entry's name cannot inflate the count.
    _fshw_ns=$(_fsb_sudo find "$_fshw_gd/hooks" -mindepth 1 -maxdepth 1 \
        ! -name '*.sample' -printf '%y\n' 2>/dev/null | wc -l 2>/dev/null || printf '0')
    if [ "${_fshw_ns:-0}" -gt 0 ] 2>/dev/null; then
        printf '  warn: git heal: %s non-sample entries in %s/hooks — remove manually\n' \
            "$_fshw_ns" "$_fshw_gd" >&2
    fi
    return 0
}

# _fsb_heal_worktrees <root> <owner> <group> <gitdir>: the worktree arm
# (#655 b C4 — used for the MAIN gitdir and every module gitdir):
# sticky over the collection (an agent may add its own registrations
# and remove its own — sticky keeps every developer-owned registration
# un-replaceable), and the two repointing pointer files pinned per
# registration. The registration dirs themselves stay group-writable:
# `git worktree add` by the agent must keep creating them, and
# merge-state files inside them (MERGE_HEAD and friends) must keep
# appearing.
_fsb_heal_worktrees() {
    _fshw_wt=$4/worktrees
    [ -d "$_fshw_wt" ] || return 0
    _fsb_heal_sticky "$1" "$_fshw_wt"
    _fshw_hl=$(mktemp "${TMPDIR:-/tmp}/opk-fsb-heal.XXXXXXXX") || {
        printf '  error: mktemp failed (is $TMPDIR writable?) — the git heal cannot scan %s\n' \
            "$_fshw_wt" >&2
        _FSB_ERRORS=$((_FSB_ERRORS + 1))
        return 0
    }
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_fshw_hl"
    fi
    _fsb_sudo find "$_fshw_wt" -mindepth 1 -maxdepth 1 -type d -print >"$_fshw_hl" ||
        _fsb_heal_err "$_fshw_wt" "the worktree scan (find)"
    while IFS= read -r _fshw_w; do
        [ -n "$_fshw_w" ] || continue
        _fsb_heal_pin "$1" "$2" "$3" "$_fshw_w/commondir" 644
        _fsb_heal_pin "$1" "$2" "$3" "$_fshw_w/gitdir" 644
    done <"$_fshw_hl"
    rm -f "$_fshw_hl"
    return 0
}

# _fsb_heal_gitdir <root> <owner> <group> <gitdir>: heal one .git
# directory (only dirs NAMED .git are enumerated — a bare repo with
# config/hooks at its root is a different shape and stays shared).
_fsb_heal_gitdir() {
    _fshg_gd=$4
    _fsb_heal_sticky "$1" "$_fshg_gd"
    _fsb_heal_pin "$1" "$2" "$3" "$_fshg_gd/config" 644
    _fsb_heal_pin "$1" "$2" "$3" "$_fshg_gd/hooks" 755
    _fsb_heal_hookwarn "$_fshg_gd"
    # Submodule gitdirs, marker-free (#655 a C3): every dir named
    # `modules` under the gitdir is a container (nested modules
    # modules/<a>/modules/<b> ride the same find); each container is
    # PINNED 1755 — post-pin it has no group write, and THAT is what
    # blocks wholesale-replacing a child (#655 b Q4: the sticky bit
    # only restricts writers, and the agent has none left; sticky is
    # load-bearing where group write REMAINS, like .git itself) — and
    # every DIRECT child dir of a container is pinned gitdir-style
    # (dir 1755, config 644, hooks 755 when present, hookwarn, the
    # worktree arm). Marker-free on purpose: keying on a hooks dir let
    # a hooks-less planted gitdir escape pinning silently. A SYMLINKED
    # container or child dodges every -type d scan — surfaced as a
    # warn, never followed (#655 b C3).
    _fshg_ml=$(mktemp "${TMPDIR:-/tmp}/opk-fsb-heal.XXXXXXXX") ||
        _fshg_ml=""
    # The symlink scans' sidecar is its own mktemp file (#818 a S1):
    # it used to be opened by plain `>` at a name nobody had created
    # (base + l) — in a 1777 TMPDIR any local user can watch the base
    # appear and plant a symlink at exactly that sidecar name, and the
    # root-run redirect then truncated THROUGH the link (arbitrary
    # file corruption). A redirect into a file THIS run created with
    # O_EXCL is the same trust the base lists always had.
    _fshg_mls=$(mktemp "${TMPDIR:-/tmp}/opk-fsb-heal.XXXXXXXX") ||
        _fshg_mls=""
    if [ -z "$_fshg_ml" ] || [ -z "$_fshg_mls" ]; then
        printf '  error: mktemp failed (is $TMPDIR writable?) — the git heal cannot scan %s\n' \
            "$_fshg_gd" >&2
        _FSB_ERRORS=$((_FSB_ERRORS + 1))
        # #818 b S1: a PARTIAL pair failure strands the survivor (the
        # combined guard sat before registration and removal) —
        # remove both; the empty one is a verified rm -f no-op.
        rm -f "$_fshg_ml" "$_fshg_mls" 2>/dev/null
        return 0
    fi
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_fshg_ml"
        # the sidecar registers under its own real name now (#655 c S2
        # abort-leak class, re-anchored by #818 a S1): the old base+l
        # spelling tracked a name that did not even exist yet.
        _tmp_track "$_fshg_mls"
    fi
    _fsb_sudo find "$_fshg_gd" -type d -name modules -print >"$_fshg_ml" ||
        _fsb_heal_err "$_fshg_gd" "the modules scan (find)"
    _fsb_sudo find "$_fshg_gd" -type l -name modules -print 2>/dev/null >"$_fshg_mls" &&
        while IFS= read -r _fshg_sl; do
            [ -n "$_fshg_sl" ] || continue
            printf '  warn: git heal: symlinked modules dir not followed — %s (its gitdirs are outside this heal)\n' \
                "$_fshg_sl" >&2
        done <"$_fshg_mls"
    rm -f "$_fshg_mls"
    while IFS= read -r _fshg_m; do
        [ -n "$_fshg_m" ] || continue
        _fsb_heal_pin "$1" "$2" "$3" "$_fshg_m" 1755
        _fshg_cl=$(mktemp "${TMPDIR:-/tmp}/opk-fsb-heal.XXXXXXXX") ||
            _fshg_cl=""
        # Sidecar twin of the container scan (#818 a S1 — same class
        # the _fshg_mls comment above carries): mktemp-created, never
        # a plain-`>` open at an unclaimed name.
        _fshg_cls=$(mktemp "${TMPDIR:-/tmp}/opk-fsb-heal.XXXXXXXX") ||
            _fshg_cls=""
        if [ -z "$_fshg_cl" ] || [ -z "$_fshg_cls" ]; then
            printf '  error: mktemp failed (is $TMPDIR writable?) — the git heal cannot scan %s\n' \
                "$_fshg_m" >&2
            _FSB_ERRORS=$((_FSB_ERRORS + 1))
            # #818 b S1: partial pair failure strands no survivor
            rm -f "$_fshg_cl" "$_fshg_cls" 2>/dev/null
            continue
        fi
        if command -v _tmp_track >/dev/null 2>&1; then
            _tmp_track "$_fshg_cl"
            _tmp_track "$_fshg_cls"
        fi
        _fsb_sudo find "$_fshg_m" -mindepth 1 -maxdepth 1 -type d -print >"$_fshg_cl" ||
            _fsb_heal_err "$_fshg_m" "the module-gitdir scan (find)"
        _fsb_sudo find "$_fshg_m" -mindepth 1 -maxdepth 1 -type l -print 2>/dev/null >"$_fshg_cls" &&
            while IFS= read -r _fshg_sl; do
                [ -n "$_fshg_sl" ] || continue
                printf '  warn: git heal: symlinked module entry not followed — %s\n' "$_fshg_sl" >&2
            done <"$_fshg_cls"
        rm -f "$_fshg_cls"
        while IFS= read -r _fshg_c; do
            [ -n "$_fshg_c" ] || continue
            _fsb_heal_pin "$1" "$2" "$3" "$_fshg_c" 1755
            _fsb_heal_pin "$1" "$2" "$3" "$_fshg_c/config" 644
            _fsb_heal_pin "$1" "$2" "$3" "$_fshg_c/hooks" 755
            _fsb_heal_hookwarn "$_fshg_c"
            _fsb_heal_worktrees "$1" "$2" "$3" "$_fshg_c"
        done <"$_fshg_cl"
        rm -f "$_fshg_cl"
    done <"$_fshg_ml"
    rm -f "$_fshg_ml"
    _fsb_heal_worktrees "$1" "$2" "$3" "$_fshg_gd"
    return 0
}

# _fsb_heal_git <root> <group>: strip the legacy root/ancestor sticky
# (#702/#703), enumerate every .git directory under the root and heal
# it. Newline-separated iteration (find -print):
# the kit's root gates reject whitespace roots; a newline inside a path
# below the root splits into two halves, and BOTH die as counted errors
# in the un-gated scans (the modules find ENOENTs on each garbage half
# — simulated, #655 b Q3): the baseline reddens, fail-loud, never a
# silent skip (or, against an attacker-created sibling dir, heals
# IN-TREE: the attacker loses its own plant). Attacker noise either
# way, never a legit checkout.
_fsb_heal_git() {
    # Root normalization (#655 a C4, the _fsb_pass shape): the belt
    # accepts a single-trailing-slash spelling, and the component walk
    # strips the root prefix by string match — with the slash kept, the
    # walk silently voided for every operand. A root that normalizes to
    # the empty string (`/` — the belt admits it, #655 b S2/C7) is the
    # whole filesystem: refuse loud, never heal it.
    _fsh_root=$1
    while [ "${_fsh_root%/}" != "$_fsh_root" ]; do
        _fsh_root=${_fsh_root%/}
    done
    if [ -z "$_fsh_root" ]; then
        _fsb_heal_err "/" "the heal root recheck (the whole filesystem is never a heal root)"
        return 0
    fi
    # Heal-entry root recheck (#655 a C5): a root swapped for a symlink
    # between the passes and the heal turns the scan into an empty
    # silent no-op — refuse that loud instead (parity with the passes'
    # #421 batch-head recheck).
    if [ -L "$_fsh_root" ]; then
        _fsb_heal_err "$_fsh_root" "the heal entry recheck (root became a symlink)"
        return 0
    fi
    if ! _fsh_owner=$(_fsb_sudo stat -c %u "$_fsh_root" 2>/dev/null); then
        # Diagnostic rerun (#244 c S3 shape): stderr flows to the user,
        # the rc is discarded — the counted error below is the loud
        # part (#655 a S1).
        _fsb_sudo stat -c %u "$_fsh_root" >/dev/null || true
        _fsb_heal_err "$_fsh_root" "the owner probe (stat)"
        return 0
    fi
    # Project-root sticky STRIP (#702/#703 — migration): the #655 a C1
    # bit is removed, and installed bases carry it from earlier heals,
    # so the strip runs even when no .git is found (uniform — same
    # enumeration discipline the add once had). Sharing mode and group
    # stay; only the sticky column goes. The wholesale mv-.git arm
    # (W1) reopens deliberately — measured everyday costs (#699/#682/
    # #701/#697) outweighed it; the #653/#703 detection row in opk
    # status/doctor reports owner(.git) != owner(project root) as the
    # compensating control.
    _fsb_sudo chmod -t "$_fsh_root" || _fsb_heal_err "$_fsh_root" "chmod -t (project root strip)"
    _fsh_list=$(mktemp "${TMPDIR:-/tmp}/opk-fsb-heal.XXXXXXXX") || {
        printf '  error: mktemp failed (is $TMPDIR writable?) — the git heal cannot run under %s\n' "$_fsh_root" >&2
        _FSB_ERRORS=$((_FSB_ERRORS + 1))
        return 0
    }
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_fsh_list"
    fi
    _fsb_sudo find "$_fsh_root" -type d -name .git -print >"$_fsh_list" ||
        _fsb_heal_err "$_fsh_root" "the .git scan (find)"
    while IFS= read -r _fsh_gd; do
        [ -n "$_fsh_gd" ] || continue
        printf '  git heal: %s (hooks/config pinned developer-owned)\n' "$_fsh_gd" >&2
        # Ancestor-chain sticky STRIP (#702/#703 — migration): the
        # #655 a C1/b C1 bits are removed with the SAME enumeration
        # that once added them (every directory from the root,
        # exclusive — the driver strips the root itself — down to the
        # .git's parent, inclusive), so previously healed ancestor
        # chains lose the bit again. The wholesale project-dir swap
        # (W2) reopens deliberately — see the project-root strip above.
        # Corner residual: an ancestor stickied for a .git that has
        # since been DELETED is outside every current walk — the bit
        # lingers until the dir itself goes; strip manually if that
        # tree still sees #699-style friction.
        _fshg_parent=$(dirname "$_fsh_gd")
        # Ancestor walk only for parents INSIDE the root (#655 c S1,
        # d S4): parent == root needs no walk (the driver stripped the
        # root), and a parent outside the root entirely (a heal root
        # that is itself a dir named .git — plausible misconfiguration)
        # must not make the walk chew the parent's absolute-path
        # segments: an in-tree dir named after a root segment could
        # take an unintended strip.
        case "$_fshg_parent" in
            "$_fsh_root"/*)
                _fshg_anc=$_fsh_root
                _fshg_rest=${_fshg_parent#"$_fsh_root"/}
                while [ -n "$_fshg_rest" ]; do
                    case "$_fshg_rest" in
                        */*)
                            _fshg_anc=$_fshg_anc/${_fshg_rest%%/*}
                            _fshg_rest=${_fshg_rest#*/}
                            ;;
                        *) _fshg_anc=$_fshg_parent _fshg_rest="" ;;
                    esac
                    _fsb_heal_unsticky "$_fsh_root" "$_fshg_anc"
                done
                ;;
        esac
        _fsb_heal_gitdir "$_fsh_root" "$_fsh_owner" "$2" "$_fsh_gd"
    done <"$_fsh_list"
    rm -f "$_fsh_list"
    # Symlinked .git entries (#655 b C2): invisible to the -type d scan
    # above, so a plant predating the first heal (or any repo-less
    # dev-owned dir) would point the developer's git at an agent-owned
    # gitdir OUTSIDE this tree — never healed, never mentioned. A
    # worktree pointer .git is a regular FILE (legitimate); a symlinked
    # .git is always foreign. Warn loudly, never follow. #653's report
    # walk matches dirs and pointer files only — a REGISTERED
    # worktree's symlinked .git pointer surfaces through #653's
    # back-reference row (the registration's gitdir file still names
    # it); an UNREGISTERED symlinked .git stays this scan's warn (a
    # documented residual — the status walk cannot see it).
    # Sidecar twin of the .git-symlink scan (#818 a S1 — same class
    # the _fshg_mls comment in _fsb_heal_gitdir carries): its own
    # mktemp file, never a plain-`>` open at an unclaimed (base + l)
    # name. The base list above is already consumed and removed by the
    # time this scan runs, so the sidecar stands on its own here.
    _fsh_lists=$(mktemp "${TMPDIR:-/tmp}/opk-fsb-heal.XXXXXXXX") || {
        printf '  error: mktemp failed (is $TMPDIR writable?) — the git heal cannot run the symlinked-.git scan under %s\n' \
            "$_fsh_root" >&2
        _FSB_ERRORS=$((_FSB_ERRORS + 1))
        return 0
    }
    if command -v _tmp_track >/dev/null 2>&1; then
        _tmp_track "$_fsh_lists"
    fi
    if _fsb_sudo find "$_fsh_root" -type l -name .git -print 2>/dev/null >"$_fsh_lists"; then
        while IFS= read -r _fsh_sl; do
            [ -n "$_fsh_sl" ] || continue
            printf '  warn: git heal: symlinked .git not followed — %s (its hooks/config are outside this heal)\n' \
                "$_fsh_sl" >&2
        done <"$_fsh_lists"
    fi
    rm -f "$_fsh_lists"
    return 0
}

# fs_baseline_root <root> <group>: the full recursive baseline —
#   1. chgrp every entry to the sharing group
#   2. setgid + group rwx on every directory (new files anywhere in the
#      tree inherit the group; both sides can create entries)
#   3. group rw on every file (developer and agent edit each other's
#      pre-install files; .git included, issue #17)
#   4. default ACLs g:<group>:rwx on every directory (governs new files)
#   5. the .git metadata heal (#644/#651) — the execution-bearing
#      entries above are re-narrowed after the sharing passes: .git
#      sticky, config/hooks (and the submodule/worktree arms) pinned
#      developer-owned without group write. The passes and the heal run
#      in this order every time, so a re-run re-shares and re-heals in
#      one idempotent cycle.
# The sharing passes SKIP nailed .git POINTER FILES (#704/#754, issue
# #758): a pointer sealed with chattr +i refuses chgrp/chmod even for
# root (EPERM by design), and the migration writes the pointer
# dev:opencode 664 BEFORE the nail — the passes' target state holds
# without touching it (the lsattr gate in the _fsb_pass worker; a .git
# DIRECTORY is never skipped, and an unnailed pointer stays a normal
# operand).
# Idempotent; re-runs on install, `config.sh projects add` / `refresh`
# and `update.sh --refresh`. Ancestors come first (fs_ensure_traversable
# above): the passes below fix <root> down, but without traversable
# ancestors the agent cannot resolve paths into the tree at all.
# Issue #14: prints a heads-up for large trees and a live per-pass
# counter to stderr.
# The chgrp pass skips symlinks (! -type l): a bare `chgrp <link>`
# dereferences the TARGET — outside the tree — while `chgrp -R` (the
# code this replaces) never did (default -P). chmod passes are type-
# filtered anyway; setfacl touches dirs only.
fs_baseline_root() {
    fsb_root="$1"
    fsb_group="$2"
    # Root-form refusal (review c X1, issue #245): the belt below
    # strips ONE trailing slash — `link//` lands on `link/` where
    # [ -L ] is false, `link/.` has nothing to strip, and [ -d ]
    # follows both (executed in review c: the FULL baseline ran
    # through `link/.` onto the target, rc 0). No valid stored root
    # carries these forms — the writer refuses them, the reader loops
    # skip them — so the belt for direct and future callers refuses
    # them outright: the writer's form set (absolute, no dot/empty
    # segments, no whitespace, no glob metacharacters — #665 adds the
    # glob class at belt AND writer after the config.sh projects add
    # route measured storing it; the system-path blocklist rides #247).
    case "$fsb_root" in
        /*) ;;
        *)
            printf '  error: %s is not an absolute path — refusing the group baseline\n' "$fsb_root" >&2
            return 1
            ;;
    esac
    # Whole-filesystem refusal (#655 b S2/C7): the form arms below
    # admit a bare `/` — the sharing passes would run filesystem-wide
    # before any downstream gate noticed. Unreachable via shipped
    # writers (path-sane blocklists `/`), exactly the direct/future
    # caller class this belt exists for.
    if [ "$fsb_root" = "/" ]; then
        printf '  error: / is never a baseline root (the whole filesystem is out of scope)\n' >&2
        return 1
    fi
    case "$fsb_root" in
        *..* | /./ | */./* | ./* | */. | *//* | *[[:space:]]* | *[\*\?\[]*)
            printf '  error: %s is a malformed root (dot/empty segment, whitespace, or glob) — refusing the group baseline\n' \
                "$fsb_root" >&2
            return 1
            ;;
    esac
    # Symlinked root refusal (issue #245), BEFORE the [ -n ] && [ -d ]
    # arm (review b X4): that arm follows a link and returns 0 — a
    # dangling link was a completely silent no-op for exactly the
    # direct/future callers the belt exists for. [ -L ] is true for a
    # dangling link too (lstat sees the link itself), so a bare link
    # spelling — live or dangling — refuses loudly here; the slash/dot
    # spellings that dodge [ -L ] are the form arms' catch above.
    # Every pass below the old position would have been a silent
    # no-op on a live link — the find walks start at the link itself
    # and visit nothing (measured, issue #245) — while the callers
    # print "baseline applied" over a tree that got NOTHING. Fail
    # loud: rc 1 plus the reason line — under the shipped set -e
    # callers (config.sh, update.sh, install.sh all run set -eu) the
    # rc aborts before any success line; the loop-side gates keep
    # those flows from reaching the belt at all. Not a guarantee for
    # future NON-set-e callers: they receive the rc and the reason, a
    # caller that ignores both can still print its own success line
    # (review a Q2). The trailing-slash strip is dodge-proofing:
    # [ -L "path/" ] is false (kernel resolution through the slash —
    # measured), and a raw-conf caller may hand the stored spelling
    # through.
    if [ -L "${fsb_root%/}" ]; then
        printf '  error: %s is a symlink — refusing the group baseline (register the target directory instead)\n' \
            "$fsb_root" >&2
        return 1
    fi
    [ -n "$fsb_root" ] && [ -d "$fsb_root" ] || return 0
    # Wholesale-failure detection part 1 (0.0.43a F10): a missing tool
    # used to die silently inside the pipeline (find's stderr is
    # redirected, xargs -r succeeds on empty input) and the passes
    # "completed" with nothing applied. Probe BEFORE walking. cat is
    # probed with the rest since #223: the python3-less fallback of
    # _fsb_count_tee pipes the pass through it — a missing cat would
    # rebuild the exact empty-stream false-green the gate closes.
    # Wholesale-failure detection part 2: probe chown and dirname too —
    # chown is heal-only (the sharing passes chgrp), dirname feeds the
    # ancestor-chain rider unguarded (#655 b C6); both must fail BEFORE
    # the walk, not abort mid-baseline under the callers' set -e.
    for _fsb_tool in find cat chgrp chmod setfacl chown dirname; do
        if ! command -v "$_fsb_tool" >/dev/null 2>&1; then
            printf '  error: required tool missing for the group baseline: %s\n' "$_fsb_tool" >&2
            return 1
        fi
    done
    _FSB_ERRORS=0
    fs_ensure_traversable "$fsb_root" "$fsb_group" "${3:-}"
    printf '%s\n' "  group baseline on $fsb_root (group $fsb_group) — large trees can take several minutes;""\
 progress per pass:" >&2
    _fsb_pass "chgrp" "$fsb_root" ! -type l -- chgrp "$fsb_group"
    _fsb_pass "dirs g+rwxs" "$fsb_root" -type d -- chmod g+rwxs
    _fsb_pass "files g+rw" "$fsb_root" -type f -- chmod g+rw
    _fsb_pass "default ACLs" "$fsb_root" -type d -- setfacl -d -m "g:$fsb_group:rwx"
    # The heal AFTER the sharing passes, every run (#644/#651): the
    # passes above re-grant group write on .git/config and .git/hooks
    # (files g+rw / dirs g+rwxs / default ACLs) — this is by design,
    # the pinning below re-narrows them in the same breath. Ordering is
    # load-bearing: a heal run before the passes would be undone by
    # them.
    _fsb_heal_git "$fsb_root" "$fsb_group"
    # Wholesale-failure detection part 2: propagate the per-pass error
    # count (0.0.43a F10). Fail-loud on purpose — the callers' success
    # lines ("group + setgid + default ACLs applied") must not print
    # over a baseline that did not fully apply; "agent cannot write
    # project files" weeks later is the worse failure mode.
    if [ "$_FSB_ERRORS" -gt 0 ]; then
        printf '  error: %s baseline pass(es) failed on %s — the group baseline may be incomplete\n' \
            "$_FSB_ERRORS" "$fsb_root" >&2
        return 1
    fi
    return 0
}
