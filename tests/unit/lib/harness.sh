# tests/unit/lib/harness.sh -- the shared unit-test harness (issue #255
# stage 2 spike). Sourced by suites, never executed directly. It carries
# exactly the helpers the suites duplicate today (30 byte-identical
# pass()/fail() definitions at spike time) plus the two assertion shapes
# and the summary gate -- no runner, no DSL: the contract stays
# `sh tests/unit/test-*.sh`, each suite directly executable (Makefile
# per-suite targets, CI, kcov via scripts/coverage.sh).
#
# Sourcing contract: the suite computes SCRIPT_DIR (nearly every suite
# already does) and then sources this file:
#
#     SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#     . "$SCRIPT_DIR/lib/harness.sh"
#
# Provides:
#   pass / fail          the counted PASS/FAIL rows -- printf '%b' based,
#                        byte-identical to the old echo definitions under
#                        sh/dash (the suites' runtime) AND under bash
#                        (the coverage shell: scripts/coverage.sh
#                        resolves sh to bash for kcov, and bash echo
#                        does not interpret \033 -- PR #397 CI caught
#                        the echo form differing there)
#   check <desc> cmd...  pass/fail around a command's rc
#   assert_eq <desc> <expected> <actual>
#                        string-equality assertion with expected/got
#                        output on failure
#   live_src <file>...   the canonical comment-strip rider (#460):
#                        prints each file with full-line comments
#                        stripped, concatenated in argument order. A
#                        presence/count pin over a shipped or
#                        repo-internal source observes only LIVE lines
#                        (the survivor trap, #261/#244 g W1: a
#                        temporarily commented-out pinned construct
#                        stops counting). Full-line strip only --
#                        trailing comments after live lines still count
#                        (#244 h W6 residual, deliberate). The strip
#                        is LINE-PRESERVING (comment lines become
#                        empty lines): grep -n extraction legs keep
#                        raw-file line numbers. Loudness is shape-
#                        dependent (round a A1): single-file presence
#                        fails loud on a missing file (sed's own error
#                        surfaces, downstream grep sees empty input and
#                        reds); a MULTI-FILE count pin or any
#                        zero-count pin passes rc-silently on a
#                        missing operand (the historical sed A B C
#                        masked identically) -- such pins need their
#                        own missing-file conjunct when that drift
#                        matters. A call site may add 2>/dev/null; it
#                        owns the muting then (pre-existing shape,
#                        test-install-args).
#   check_live <desc> <file> <grep-args...>
#                        pass/fail around grep over the file's LIVE
#                        lines -- the dominant single-file presence
#                        shape (#460). The grep flags and pattern pass
#                        through verbatim (-qF, -Eq, -c, --, …): call
#                        sites keep their exact matching semantics,
#                        only the rider moves inside. Multi-file
#                        presence stays `live_src "$A" "$B" | grep …`
#                        or per-file conjunctions; compound shapes
#                        keep live_src in the PARENT and pass the
#                        stripped content into the child as an
#                        argument -- sh -c children never source the
#                        harness, live_src must not appear inside
#                        sh -c code (boundary: one canonical
#                        single-file sugar, no separator parsing).
#   extract_func <file> <name>
#                        print a top-level `name() { … }` definition
#                        block from <file> (issue #396 — consolidating
#                        the nine suite-local extractor helpers). Strict
#                        col-0 anchors: `/^name() {/` .. first `/^}/`;
#                        an indented (nested) definition, same name or
#                        not, is invisible by design (over-capture
#                        guard).
#                        Empty output when absent; rc 1 + stderr on a
#                        bad name or missing file. Callers own the
#                        emptiness probe, the eval, and post-pipelines
#                        (the comment-strip rider composes on stdout).
#   suite_done <label>   the summary gate: Passed count, the red Failed
#                        count + exit 1 on any failure, the green
#                        "All <label> passed." line + exit 0 otherwise.
#                        Must stay the suite's LAST call (L4: pins sit
#                        before the summary gate).
#   work_new / work_new_file / work_register / work_register_var
#                        the scratch-receiver registry + central EXIT
#                        INT TERM cleanup (issue #395; own section below)
#
# Deliberately NOT provided: mocking, setup/teardown hooks, filters,
# parallelism -- that is framework territory and was rejected in #255
# (runner lock-in, BDD translation layer in agent review fan-outs).
# Counters (passed/failures) and colors stay globals so existing
# suites read them unchanged.
#
# Standing rules (issue #394 -- the adoption wave's home):
#   1. Rule of three -- a shape moves into the harness at the third
#      real duplication, never speculatively.
#   2. Pin-on-entry -- every function here is pinned by
#      tests/unit/test-harness.sh the moment it lands (counting + rc
#      contracts; the #393 spike's second sabotage arm showed an
#      unpinned harness can print a FAIL row yet exit 0).
#   3. Boundary -- harness = shell test mechanics; suites keep their
#      subject knowledge (drivers, fixtures, seams like run_doctor or
#      run_ui stay local; centralizing them is framework creep, the
#      ShellSpec rejection reason in #255).
#
# Gate scope (review #398 a F4): part of the SHFMT gate -- Makefile
# SHFMT_TEST_FILES covers every tracked tests/*.sh, this file included.
# shellcheck covers files/ + scripts/ only (SHELLCHECK_FILES); this lib
# is NOT in the shellcheck gate.

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

passed=0
failures=0

pass() {
    printf '  %bPASS%b  %s\n' "$GREEN" "$NC" "$1"
    passed=$((passed + 1))
}
fail() {
    printf '  %bFAIL%b  %s\n' "$RED" "$NC" "$1"
    failures=$((failures + 1))
}

check() {
    local desc="$1"
    shift
    # review #398 a F6: an empty command must fail loud, not silently
    # pass (a conversion slip dropping the command word would otherwise
    # record a vacuous PASS).
    if [ "$#" -eq 0 ]; then
        fail "$desc (check: no command given)"
        return
    fi
    if "$@"; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

assert_eq() {
    _d="$1" _e="$2" _a="$3"
    if [ "$_e" = "$_a" ]; then pass "$_d"; else fail "$_d (expected [$_e] got [$_a])"; fi
}

# --- live_src / check_live (#460) ------------------------------------------------
#
# The comment-strip rider the conventions rule "Source-counting pins"
# names canonical: BEFORE #460 the rider was a 40-byte magic sed string
# duplicated inline at 200+ pin sites -- unauditable (the round-a
# census needed a joined-continuation parser to find ~40 true positives
# among 411 raw candidates), and every future rider-semantics change
# (the deferred JSONC `//` decision) would have been another
# cross-suite sweep. One named primitive makes the un-ridden census
# class greppable and the semantics changeable in one place.
live_src() {
    # $@ = source files, stripped and concatenated in argument order.
    # The strip expression is byte-identical to the historical inline
    # rider; the multi-file loop concatenates so `grep -qF pat` matches
    # if ANY file carries the live construct (presence semantics of
    # `grep -qF pat A B`). A concatenation SUMS per-file counts: a
    # multi-file count pin asserts on the union; per-file counts need
    # per-file calls. No-args guard (round a A4): a conversion slip
    # dropping the file must fail loud, never pass vacuously.
    local _ls_f
    if [ "$#" -eq 0 ]; then
        echo "live_src: no files given" >&2
        return 1
    fi
    for _ls_f in "$@"; do
        sed 's/^[[:space:]]*#.*$//' "$_ls_f"
    done
}

check_live() {
    # Arg-count guards BEFORE any shift (round a A5): dash aborts the
    # whole suite on `shift 2` overflow (rc 2, no fail row, no summary
    # gate), and an unbound $2 under set -u kills the 0-arg shape --
    # both slip shapes must land in a counted FAIL row instead.
    if [ "$#" -eq 0 ]; then
        fail "check_live: no arguments given (desc and file required)"
        return
    fi
    if [ "$#" -lt 2 ]; then
        fail "$1 (check_live: file argument missing)"
        return
    fi
    local _cl_desc="$1" _cl_file="$2"
    shift 2
    # Mirror of check's F6 guard: a conversion slip dropping the grep
    # arguments must fail loud, never vacuously pass.
    if [ "$#" -eq 0 ]; then
        fail "$_cl_desc (check_live: no grep arguments given)"
        return
    fi
    if live_src "$_cl_file" | grep "$@"; then
        pass "$_cl_desc"
    else
        fail "$_cl_desc"
    fi
}

test_chain() {
    # $1 = Makefile path. Prints the test: prerequisite chain one token
    # per line, the `test:` head token stripped. The awk span reads the
    # head line plus the space-indented continuation block up to the
    # first recipe line -- the wrapped one-prerequisite-per-line chain
    # layout of issue #464. Callers pin chain membership with
    # `test_chain ... | grep -qxF <target>`; a bare grep over the raw
    # Makefile would also match the suite's .PHONY continuation line and
    # pass without chain membership (the stray-dog class this replaced).
    if [ "$#" -ne 1 ]; then
        echo "test_chain: exactly one Makefile path required" >&2
        return 1
    fi
    if [ ! -f "$1" ]; then
        echo "test_chain: no such file: $1" >&2
        return 1
    fi
    awk '/^test:/{_in=1; sub(/^test:[ \t]*/, ""); if (length($0)) print; next}
        _in && /^\t/{_in=0} _in{print}' "$1" | tr -d '\n\\' | tr -s ' \t' '\n'
}

extract_func() {
    # $1 = subject file, $2 = function name. Prints the block; the
    # caller owns the emptiness probe, the eval, and any post-pipeline
    # (comment-strip rider, inner-range, normalize). Strict col-0
    # anchors are the contract: an shfmt'd `name() {` at column 0,
    # closed by the first `^}` -- for a top-level function that first
    # col-0 close is its own closing brace. Indented (nested)
    # definitions, same name or not, are deliberately invisible: a
    # name-keyed helper that tolerates indent recreates the
    # over-capture anchor class (the fold-comment lesson on #396) --
    # sites needing indent tolerance keep a local extractor (boundary
    # rule, test-project-paths).
    case "$2" in
        '' | *[!A-Za-z0-9_]*)
            echo "extract_func: not a function name: [$2]" >&2
            return 1
            ;;
    esac
    if [ ! -f "$1" ]; then
        echo "extract_func: not a regular file: [$1]" >&2
        return 1
    fi
    sed -n "/^$2() {/,/^}/p" "$1"
}

suite_done() {
    _label="$1"
    echo ""
    echo "===================================="
    printf '  %bPassed: %s%b\n' "$GREEN" "$passed" "$NC"
    if [ "$failures" -gt 0 ]; then
        printf '  %bFailed: %s%b\n' "$RED" "$failures" "$NC"
        exit 1
    fi
    echo "  All $_label passed."
    exit 0
}

# --- work registry (issue #395) -------------------------------------------------
#
# One central trap structurally ends the #283 leak class: receivers
# register at CREATION time into a per-process registry, and the single
# trap below iterates it on EXIT INT TERM -- no per-suite trap widening
# (test-status's nine-receiver _trap_cleanup was the largest of 22
# hand-rolled scaffolds at spike time).
#
# The registry is a FILE, not a shell variable: registration from inside
# command substitution (test-status's _w2_dir shape) must reach the
# parent's trap, and variable appends die with the subshell. The file is
# created lazily by the first append -- a suite that never registers
# (not yet converted, or one whose own trap replaced the harness trap)
# leaves nothing behind. Its name embeds $$; a PID-recycled run appending
# to a crashed run's leftover self-heals (stale paths are rm no-ops, the
# file is removed afterwards).
#
# API (rule of three: ~25 dir + 8 file receivers + 6 custom traps):
#   work_new [template-args...]   mktemp -d + register, prints the path.
#                                 The idiom for every NEW receiver: there
#                                 is no window between creation and
#                                 registration (the #283 window).
#   work_new_file [template-args...]  same for file receivers (mktemp).
#   work_register <path>...       register pre-existing receivers.
#   work_register_var <NAME>...   register variable NAMES, expanded
#                                 unset-safe at exit -- the migration
#                                 shape for custom _trap_cleanup suites:
#                                 their receiver lists collapse to one
#                                 line, same unset-skip semantics.
#
# set -e interplay (the original #283 trigger): a failed mktemp returns
# 1 BEFORE anything exists to leak; a failed registry append removes the
# receiver and returns 1; any later abort fires the EXIT trap, which
# iterates whatever is registered by then. Suite rc is preserved: the
# cleanup is errexit-safe (a receiver it cannot remove is reported on
# stderr and skipped, never fatal) and ends in `return 0`, so the
# pending exit status stands (round A A2 -- under set -e a bare failing
# rm in the trap used to flip the rc AND leak the registry file).
#
# TMPDIR reassignment (round A A6): the registry path freezes at SOURCE
# time -- harmless, appends and cleanup agree on the frozen path. But a
# suite that reassigns TMPDIR after sourcing (the git-config /
# mkcert-reuse / wsl-exposure / ddev-as-opencode shape) must make the
# NEW TMPDIR's scratch a work_new/work_register receiver if its old
# trap covered it: the registry does not auto-adopt it. The reverse
# shape (TMPDIR set before sourcing) embeds the registry inside that
# scratch -- do not rm it mid-suite.
#
# The registry never re-arms itself. A suite that keeps its own trap
# statement after a work_* call silently disarms the central cleanup
# (its trap replaces ours) -- the sandbox floor flags exactly that mix
# (test-sandbox-policy.sh, check 4b). Converted suites carry no trap line
# of their own; unconverted suites keep theirs (they never register, so
# nothing leaks through the lazy file).
_WORK_REG="${TMPDIR:-/tmp}/opk-work-reg.$$"

_work_cleanup() {
    [ -f "$_WORK_REG" ] || return 0
    while IFS= read -r _we; do
        case "$_we" in
            '$'*)
                # Round A A1 hardening: a malformed $-line (stale
                # registry, corruption) must SKIP with a warning, never
                # abort the loop -- eval is a special builtin; a syntax
                # error in it used to kill the cleanup mid-loop in dash
                # (even without set -e), leaking every later receiver.
                _we2="${_we#\$}"
                case "$_we2" in
                    '' | *[!A-Za-z0-9_]*)
                        echo "work registry: skipping malformed entry [$_we]" >&2
                        continue
                        ;;
                esac
                eval "_we=\${$_we2:-}"
                ;;
        esac
        # Round A A2: errexit-safe AND fail-loud -- a receiver that
        # cannot be removed is reported and skipped; a bare failing rm
        # here used to flip the suite rc under set -e and leak the
        # registry file.
        if [ -n "$_we" ]; then
            rm -rf -- "$_we" 2>/dev/null ||
                echo "work registry: could not remove [$_we]" >&2
        fi
    done <"$_WORK_REG"
    rm -f -- "$_WORK_REG" 2>/dev/null ||
        echo "work registry: could not remove the registry file [$_WORK_REG]" >&2
    return 0
}
trap _work_cleanup EXIT INT TERM

_work_emit() {
    # $1 = caller name (the error message prefix), $2 = the freshly
    # created receiver: register it, print it. On a failed append the
    # receiver is removed again -- no unregistered scratch may survive
    # a work_new call.
    printf '%s\n' "$2" >>"$_WORK_REG" 2>/dev/null || {
        echo "$1: registry append failed ($_WORK_REG)" >&2
        rm -rf -- "$2"
        return 1
    }
    printf '%s\n' "$2"
}

work_new() {
    local _wn
    _wn="$(mktemp -d "$@")" || return 1
    _work_emit work_new "$_wn"
}

work_new_file() {
    local _wn
    _wn="$(mktemp "$@")" || return 1
    _work_emit work_new_file "$_wn"
}

work_register() {
    local _wr
    for _wr in "$@"; do
        # Round A A1/A3: paths only -- a "$"-prefixed argument is the
        # work_register_var contract (or a quoting slip); letting it
        # through put an eval target in the registry (late-bound
        # deletion) or a syntax-error bomb for the cleanup.
        case "$_wr" in
            '$'*)
                echo "work_register takes paths, not \$names: [$_wr] (use work_register_var NAME)" >&2
                return 1
                ;;
        esac
        printf '%s\n' "$_wr" >>"$_WORK_REG" 2>/dev/null || {
            echo "work_register: registry append failed ($_WORK_REG)" >&2
            return 1
        }
    done
    return 0
}

work_register_var() {
    local _wv
    for _wv in "$@"; do
        case "$_wv" in
            '' | *[!A-Za-z0-9_]*)
                echo "work_register_var: not a variable name: [$_wv]" >&2
                return 1
                ;;
        esac
        printf '$%s\n' "$_wv" >>"$_WORK_REG" 2>/dev/null || {
            echo "work_register_var: registry append failed ($_WORK_REG)" >&2
            return 1
        }
    done
    return 0
}
