#!/bin/sh
# test-coverage.sh -- pins for the kcov coverage runner (issue #255, stage
# 0b). The runner lives in scripts/coverage.sh (invoked via `make
# coverage`, CI job `coverage`); this suite pins its load-bearing
# properties so the report cannot silently degrade to plausible garbage:
#
#   1. Wiring: Makefile target + CI job + artifact upload + this suite's
#      own CI run step exist (a dropped wiring makes the report vanish).
#   2. Image pin: the kcov image is digest-pinned (sha256, 64 hex) --
#      report reproducibility rides on it.
#   3. Method contract: NO --bash-method override in the runner. The
#      default PS4 method traces child `sh` processes; the DEBUG-trap
#      method does not (its helper unsets BASH_ENV -- children go dark;
#      measured as the 11-file/41.8% illusion vs the real 27-file/52.7%).
#   4. The PS4 collision shields across EVERY suite and EVERY -c form:
#      every `sh -c`/`bash -c` body that sets -u carries `PS4="+ "` as
#      its first line — without it, coverage runs abort those blocks on
#      PS4's ${BASH_SOURCE} expansion under set -u (issue #255 stage 0b,
#      widened by #369 from test-install-args-only to all suites/forms).
#   5. Exclusion discipline: the runner's exclusion list is empty —
#      every entry needs an open issue naming the delta (#342, the last
#      entry, closed).
#   6. Runner mechanics: relative suite paths (absolute argv = empty
#      report), the quoted-heredoc sh->bash shim, the include surface
#      (files/ + scripts/), and the :? guards on scratch cleanup.
#
# No docker needed here -- these are structure pins; the runner itself is
# exercised by the CI coverage job (and locally via `make coverage`).
# Run: sh tests/unit/test-coverage.sh
set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$REPO_ROOT/tests/unit/lib/harness.sh"
cd "$REPO_ROOT" || exit 1
RUNNER="scripts/coverage.sh"
WF=".github/workflows/test-unit.yml"
# Loud scratch guard (#441 a B1 / #454 a C1 class): no set -e here -- a
# failed work_new must abort instead of degenerating fixture writes.
WORK="$(work_new)" || {
    echo "coverage tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

_strip() { live_src "$1"; }

# --- 1. wiring ----------------------------------------------------------------
if [ -f "$RUNNER" ] && _strip Makefile | grep -qE '^coverage:' &&
    _strip Makefile | grep -qF './scripts/coverage.sh'; then
    pass "runner exists and is wired as \`make coverage\`"
else
    fail "runner or Makefile coverage target missing"
fi
if _strip "$WF" | grep -qE '^  coverage:' &&
    _strip "$WF" | grep -qF 'actions/upload-artifact@'; then
    pass "CI: coverage job present and uploads an artifact"
else
    fail "test-unit.yml lost the coverage job or its artifact upload"
fi
if _strip "$WF" | grep -qF './tests/unit/test-coverage.sh'; then
    pass "CI: this pin suite has its own run step"
else
    fail "test-unit.yml has no run step for test-coverage.sh"
fi

# --- 2. image digest pin --------------------------------------------------------
_img="$(sed -n 's/^KCOV_IMAGE="\(.*\)"$/\1/p' "$RUNNER" | head -1)"
case "$_img" in
    kcov/kcov:latest@sha256:[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
        _hex="${_img##*sha256:}"
        if [ "${#_hex}" -eq 64 ] &&
            ! printf '%s' "$_hex" | grep -qE '[^0-9a-f]'; then
            pass "kcov image digest-pinned (64-hex sha256)"
        else
            fail "KCOV_IMAGE digest is not 64 hex chars: $_img"
        fi
        ;;
    *) fail "KCOV_IMAGE not digest-pinned (got: ${_img:-none})" ;;
esac

# --- 3. method contract (absence pin: a commented override still counts) -------
if ! grep -q -- '--bash-method' "$RUNNER"; then
    pass "runner uses kcov's default PS4 method (children traced)"
else
    fail "runner overrides --bash-method -- DEBUG leaves child shells untraced (see the record)"
fi

# --- 4. PS4 shields across EVERY suite and EVERY -c form (#369) ------------------
# The old pin counted `bash -c '` blocks in test-install-args.sh only:
# five of the six shields sat in blocks it never counted (sh -c after a
# line continuation in test-browser-bridge.sh, an env-prefixed sh -c in
# test-status.sh), and a future unshielded set -u/-eu block in any -c
# form in any other suite drifted green — the PR #367 a A1 shape. The
# awk block scanner below walks every tests/unit/test-*.sh (this suite
# excepted: the pin's own pattern literals would self-match) and
# extracts each -c body — single- or double-quoted, quote glued to -c,
# quote on the next line after a backslash continuation, env-prefixed
# openers — up to its FIRST closing quote. Contract, exact on today's
# baseline (7 blocks / 7 shields / 4 suites — #479 b B5 added the
# stdin-anchor 1d block): every -c body that sets
# -u carries the house shield PS4="+ " as its FIRST body line (a
# shield after set -u is too late — kcov's PS4 ${BASH_SOURCE}
# expansion aborts the first traced command under set -u), and every
# shield line sits in such a block (no dead shields). Discriminates
# both ways: a deleted shield or a new unshielded set -u block drops
# OK below BLOCKS; a shield in a block without set -u raises LINES
# above OK.
#
# Sweep record (#369, the class-sweep rule — reproduce before trusting
# a no-siblings claim): enumeration via this scanner plus
# `sed 's/^[[:space:]]*#.*$//' tests/unit/*.sh | grep -cE "(bash|sh) +-c"`
# (measured 950 opener lines comment-stripped / 961 bare at 82389230 —
# the counts drift with the tree, re-derive them; the stripped-vs-bare
# distinction is the point — #439 a Q1, corrected by #439 b B1). Checked and out of class: set -e-only bodies
# (test-ddev-migrate.sh :835, test-kit-cli.sh :1123,
# test-project-paths.sh :506/:508 — no -u); variable-interpreted bodies
# sh -c "$body" (test-fs-baseline.sh :236-243 — the extracted
# fs-baseline.sh batch body sets no -u; test-kit-cli.sh :499/:570 —
# printf + extract_func payloads, no -u); ~18 subshell
# `( set -u ... )` sites in test-status.sh (BASH_SOURCE always defined
# there); `set -o nounset` appears in code nowhere (this comment is the
# only tree hit).
#
# Scanner limits (accepted, #439 a C1/Q2 — each named with its sites
# and its miscount direction): ONE opener per line; no $()-nested quote
# tracking — test-kit-cli.sh :499/:570 ARE $()-spanning -c bodies where
# the scanner closes at the first inner unescaped quote (verified
# harmless: no set -u in those payloads); and the `'"'"'` idiom —
# test-container-backend.sh :248 embeds it in a real -c body and the
# first-closing-quote rule truncates it (verified harmless today: no
# set -u; test-sandbox-policy.sh :682 is the trap-string variant). A
# future set -u/-eu body written in either form is INVISIBLE to the
# scanner (false green, no UNSHIELDED line) — house style for new
# shielded blocks is the multiline single-quoted body, which the
# scanner reads exactly. Cross-checked against an independent perl
# scan over the same first-closing-quote rule (same limits by
# construction).
_sh_b=0
_sh_ok=0
_sh_lines=0
_sh_unsh=""
for _s in tests/unit/test-*.sh; do
    case "$_s" in
        tests/unit/test-coverage.sh) continue ;;
    esac
    _o="$(awk '
BEGIN { SQ = sprintf("%c", 39); DQ = sprintf("%c", 34); blocks = 0; ok = 0 }
function dqclose(s, pos, i, j, bs) {
    pos = 1
    while ((i = index(substr(s, pos), DQ)) > 0) {
        i += pos - 1
        bs = 0
        for (j = i - 1; j >= 1 && substr(s, j, 1) == "\\"; j--) bs++
        if (bs % 2 == 0) return i
        pos = i + 1
    }
    return 0
}
function shielded_at_start(s, i, c) {
    # first non-blank body char must begin the shield literal (#439 a C2:
    # "shield anywhere in a single-line body" passed the old firstline
    # check; the anchor enforces the FIRST-body-line contract for inline
    # bodies too)
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == "\n") continue
        return (substr(s, i, 8) == "PS4=\"+ \"")
    }
    return 0
}
function judge() {
    if (body ~ /(^|[^A-Za-z0-9_])set[ \t]+-[A-Za-z]*u/) {
        blocks++
        if (shielded_at_start(body)) ok++
        else printf "UNSHIELDED %s line %d\n", FILENAME, opline
    }
}
function startbody(seg, q, op, p) {
    collect = 1
    bq = q
    opline = op
    if (q == SQ) p = index(seg, SQ)
    else p = dqclose(seg)
    if (p > 0) {
        body = substr(seg, 1, p - 1)
        collect = 0
        judge()
    } else {
        body = seg
    }
}
/^[ \t]*#/ { next }
{
    if (collect) {
        if (bq == SQ) {
            p = index($0, SQ)
            if (p > 0) {
                body = body "\n" substr($0, 1, p - 1)
                collect = 0
                judge()
                next
            }
        } else {
            p = dqclose($0)
            if (p > 0) {
                body = body "\n" substr($0, 1, p - 1)
                collect = 0
                judge()
                next
            }
        }
        body = body "\n" $0
        next
    }
    if (awaitq) {
        t = $0
        sub(/^[ \t]+/, "", t)
        c = substr(t, 1, 1)
        if (c == SQ || c == DQ) {
            awaitq = 0
            startbody(substr(t, 2), c, NR)
            next
        }
        if (t ~ /\\[ \t]*$/) next
        awaitq = 0
        # not a quote bearer: fall through, the line may carry its own opener
    }
    if (match($0, /(^|[^A-Za-z0-9_])(da|ba|z)?sh[ \t]+-c/)) {
        rest = substr($0, RSTART + RLENGTH)
        sub(/^[ \t]+/, "", rest)
        c = substr(rest, 1, 1)
        if (c == SQ || c == DQ) {
            startbody(substr(rest, 2), c, NR)
        } else if (rest == "" || rest ~ /^\\[ \t]*$/) {
            awaitq = 1
        }
    }
}
END { printf "TOTAL %d %d\n", blocks, ok }
' "$_s")"
    set -- $(printf '%s\n' "$_o" | tail -1)
    _sh_b=$((_sh_b + $2))
    _sh_ok=$((_sh_ok + $3))
    if [ -z "$_sh_unsh" ]; then
        _sh_unsh="$(printf '%s\n' "$_o" | grep '^UNSHIELDED ' | head -1 || true)"
    fi
    _n=$(_strip "$_s" | grep -cF 'PS4="+ "' || true)
    _sh_lines=$((_sh_lines + $_n))
done
if [ "$_sh_b" -eq 7 ] && [ "$_sh_ok" -eq 7 ] && [ "$_sh_lines" -eq 7 ] &&
    [ -z "$_sh_unsh" ]; then
    pass "every set -u -c block in every suite carries the first-line PS4 shield (blocks=$_sh_b shielded=$_sh_ok lines=$_sh_lines)"
else
    fail "PS4 shield coverage drifted (set -u -c blocks=$_sh_b, shielded=$_sh_ok, shield lines=$_sh_lines${_sh_unsh:+, first: $_sh_unsh})"
fi

# --- 5. exclusion discipline ----------------------------------------------------
# The list must be EMPTY: every entry needs an open issue naming the
# delta and tracking the fix — the last entry (#342, the dash-only stamp
# pin) was lifted when it closed. The assignment count proves EXCLUSIVITY
# (a second EXCLUDED= line would drift the list while the literal pin
# stayed green — #343 a C3 — and the count leg matches the EXCLUDED+=
# append idiom too, which contains no EXCLUDED= substring and would
# otherwise slip past both legs — #349 a Q1); the literal
# proves emptiness.
_excl_n=$(_strip "$RUNNER" | grep -cE 'EXCLUDED[+]?=' || true)
if [ "$_excl_n" = 1 ] &&
    _strip "$RUNNER" | grep -qF 'EXCLUDED=""'; then
    pass "exclusion list is empty (no open-issue deltas left)"
else
    fail "exclusion list drifted (assignments=$_excl_n, expected exactly one empty list)"
fi

# --- 6. runner mechanics ---------------------------------------------------------
if _strip "$RUNNER" | grep -qF 'for suite in tests/unit/test-*.sh; do'; then
    pass "suites are passed to kcov as RELATIVE paths"
else
    fail "relative-path contract gone (absolute argv yields an empty report)"
fi
if _strip "$RUNNER" | grep -qF "cat >\"\$OUT/shim/sh\" <<'EOF'" &&
    _strip "$RUNNER" | grep -qF 'exec /usr/bin/bash "$@"'; then
    pass "sh->bash shim written via quoted heredoc (survives shell layers)"
else
    fail "shim construction drifted off the quoted-heredoc form"
fi
if _strip "$RUNNER" | grep -qF -- '--include-pattern="$REPO/files/,$REPO/scripts/"'; then
    pass "report surface = files/ + scripts/ (the review surface)"
else
    fail "include-pattern no longer covers files/ + scripts/"
fi
if _strip "$RUNNER" | grep -qF 'rm -rf "${OUT:?}'; then
    pass "scratch cleanup carries :? empty-variable guards"
else
    fail "rm on \$OUT lost its :? guard"
fi
# Stamp-guard + absolute-OUT contract (#343 a A1/A2): the cleanup must be
# refused under a foreign non-empty OUT, and OUT must never resolve inside
# the repo.
if _strip "$RUNNER" | grep -qF 'refusing to clean' &&
    _strip "$RUNNER" | grep -qF '.opk-kcov-out' &&
    _strip "$RUNNER" | grep -qF 'must live outside the repo'; then
    pass "scratch cleanup is stamp-guarded; OUT refuses the repo tree"
else
    fail "OUT/cleanup guards drifted (absolute OUT, stamp, repo refusal)"
fi
if _strip "$RUNNER" | grep -qF '[ "$count" -eq 1 ]'; then
    pass "single-suite runs skip the merge (single-source merge emits nothing)"
else
    fail "single-source merge guard gone (filtered runs would report empty)"
fi

# --- 7. stamp write dies with the runner's own message (#350) -------------------
# `: >file` is a POSIX special-builtin redirection: under dash (sh) a
# failed write aborts the shell BEFORE `|| die` can run, so a
# foreign-owned OUT ended in a raw "cannot create" error. The stamp
# rewrite must use a catchable, non-special-builtin form (#350).
if _strip "$RUNNER" | grep -qF 'printf "" >"$OUT/.opk-kcov-out" ||' &&
    _strip "$RUNNER" | grep -qF 'cannot stamp $OUT (foreign-owned?)'; then
    pass "stamp write is a catchable redirection carrying its own die"
else
    fail "stamp write drifted back to the dash-uncatchable ': >' form (#350)"
fi
# Behavioral, observed like production (terminal = both streams): a
# foreign-owned stamped OUT dies rc 1 with "cannot stamp" — dash's raw
# abort is rc 2 WITHOUT the die line. Injection: an unwritable stamp
# FILE (the incident's dev-owned 644 stamp seen by the opencode user);
# needs a non-root uid (CI's ubuntu runners are non-root), root gets a
# loud skip. On FAIL the log CONTENT is inlined — the EXIT trap deletes
# $WORK at exit, so a cited path would be gone before triage (round a
# A2).
if [ "$(id -u)" -eq 0 ]; then
    echo "  SKIP  foreign-OUT behavioral pin (root cannot inject EACCES)"
else
    _w="$WORK/guard"
    _img="$(sed -n 's/^KCOV_IMAGE="\(.*\)"$/\1/p' "$RUNNER" | head -1)"
    _kd="$_w/home/.cache/opk-kcov/kcov-${_img##*:}"
    mkdir -p "$_kd/bin"
    printf '#!/bin/sh\nexit 0\n' >"$_kd/bin/kcov"
    chmod +x "$_kd/bin/kcov"
    mkdir -p "$_w/out"
    : >"$_w/out/.opk-kcov-out"
    chmod 444 "$_w/out/.opk-kcov-out"
    env HOME="$_w/home" COVERAGE_OUT="$_w/out" sh "$RUNNER" >"$_w/log" 2>&1
    _rc=$?
    if [ "$_rc" -eq 1 ] && grep -qF 'cannot stamp' "$_w/log"; then
        pass "foreign-owned OUT dies 'cannot stamp' with rc 1"
    else
        fail "foreign-owned OUT did not die with the runner's message (rc=$_rc, log: $(cat "$_w/log"))"
    fi
fi

# Summary gate LAST (agent/conventions.md L4)
echo ""
if [ "$failures" -gt 0 ]; then
    echo "  $failures test(s) failed."
    exit 1
fi
echo "  All coverage-runner pins passed."
exit 0
