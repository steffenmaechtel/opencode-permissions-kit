#!/bin/sh
# test-string-continuations.sh -- guard against the missing-space class at
# adjacent-string line continuations (0.0.39o C1/Q1).
#
# Class: a long string literal wrapped across lines concatenates WITHOUT
# any space unless one fragment carries it -- the message then renders
# "fragment one.fragment two". The wrap idiom itself is fine (SC2140 is
# excluded for it, Makefile); the JOIN must stay deliberate. This test
# fails on joins of either quote style where prose meets without a
# space: first fragment ending in [.,;:!?, em-dash] or alnum, second
# starting with alnum, quote, '(' or em-dash (review a C2, #301: the
# kit's prose uses spaced em-dashes daily -- an ASCII-only alphabet was
# blind exactly at that border).
#
# Two wrap shapes are detected (review a C3, #301 -- the header used to
# describe only the first):
#   classic (hand-written, no longer canonical on-tree since shfmt):
#     ui_warn "fragment one."\
#     "fragment two"
#   shfmt splice (the canonical form since #255 stage 0a -- the frag2
#   opening quote sits at EOL, closer and opener adjacent):
#     ui_warn "fragment one.end.""\
#     next fragment here"
# The splice head is read from the RAW next line: a deliberate join
# space may open frag2 (canonical continuations are col-0 or exactly
# one leading space).
#
# Limitations (accepted, named):
#   - a line whose closing quote is itself escaped (...\") confuses
#     the seam detection -- none exist in the scope today; the
#     allowlist is the escape hatch if one ever does.
#   - a splice continuation indented >= 2 whitespace chars is read as
#     indentation and slips through -- only reachable in a hand-written
#     tree; the shfmt format gate (make lint) rejects those.
#
# Token concatenation (URL segments, regex alternatives, comma-separated
# lists, option strings) does not match that pattern; the few deliberate
# prose-like no-space joins are allowlisted below with reasons.
#
# Scope: the shipped shell (files/**/*.sh incl. files/etc/umask.sh and
# files/install.sh, plus the extensionless scripts under
# files/opencode-permissions-kit-lib/bin/) -- same scope as the
# line-length ratchet minus the workflows.
#
# Run: sh tests/unit/test-string-continuations.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Deliberate no-space joins, one entry per line: path-suffix | seam text.
# A reason line starts with '#' and sits above its entry.
ALLOW="
# update.sh mount-option list: uid=(...),gid=(...) -- the comma separates
# options; no prose space
management/update.sh|'),gid=
"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM

# Paths in this repo contain no spaces (same assumption as the ratchet).
{
    find files -name '*.sh' -type f
    find files/opencode-permissions-kit-lib/bin -type f
} | sort -u | while IFS= read -r f; do
    awk -v f="$f" -v tails='.,;:!?—A-Za-z0-9' -v heads="—A-Za-z0-9'(" \
        -v sq="'" -v dq='"' '
        NR > 1 {
            plen = length(prev)
            if (plen >= 2 && substr(prev, plen) == "\\") {
                q = substr(prev, plen - 1, 1)
                if (q == dq || q == sq) {
                    l = $0
                    sub(/^[ \t]+/, "", l)
                    c1 = substr(l, 1, 1)
                    if (c1 == dq || c1 == sq) {
                        content = substr(prev, 1, plen - 2)
                        tail = substr(content, length(content), 1)
                        head = substr(l, 2, 1)
                        if (tail != " " && head != " " &&
                            tail ~ "[" tails "]" && head ~ "[" heads "]") {
                            start = length(content) - 15
                            if (start < 1) start = 1
                            seam = substr(content, start) substr(l, 2, 16)
                            printf "%s\t%d\t%s\n", f, NR - 1, seam
                        }
                    }
                    # shfmt splice shape (#255 stage 0a): the canonical
                    # reformat of the wrap idiom puts the frag2 OPENING
                    # quote at EOL — "tail"...\<newline>content — so the
                    # line below starts with frag2 CONTENT. Observed
                    # canonical continuation shapes: column 0, or exactly
                    # one leading space (a deliberate join space opening
                    # frag2 — read head from the RAW line, never
                    # leading-space-stripped). LIMITATION (review a C3,
                    # #301): a hand-written splice continuation indented
                    # by >= 2 whitespace chars is indistinguishable from
                    # indentation here and slips through — the format
                    # gate rejects such trees, so the hole is reachable
                    # only pre-format.
                    if (plen >= 3 && substr(prev, plen - 2, 1) == q) {
                        tail = substr(prev, plen - 3, 1)
                        head = substr($0, 1, 1)
                        if (tail != " " && head != " " &&
                            tail ~ "[" tails "]" && head ~ "[" heads "]") {
                            start = plen - 18
                            if (start < 1) start = 1
                            # drop the closer+opener+backslash suffix
                            # uniformly (both quote styles, review a C1,
                            # #301 — a dq-only sub left an sq seam
                            # carrying its quote bytes)
                            seam = substr(prev, start, plen - 2 - start)
                            seam = seam substr($0, 1, 16)
                            printf "%s\t%d\t%s\n", f, NR - 1, seam
                        }
                    }
                }
            }
        }
    { prev = $0 }
        ' "$f" || printf 'AWK-ERROR\t0\t%s\n' "$f"
done >"$TMP"

fails=0
allowed=0
TAB="$(printf '\t')"
while IFS="$TAB" read -r path line seam; do
    [ -n "$path" ] || continue
    ok=""
    while IFS='|' read -r suffix want; do
        case "$suffix" in '' | '#'*) continue ;; esac
        case "$path" in
            *"$suffix")
                case "$seam" in
                    *"$want"*) ok=1 ;;
                esac
                ;;
        esac
    done <<EOF
$ALLOW
EOF
    if [ -n "$ok" ]; then
        allowed=$((allowed + 1))
    else
        echo "FAIL $path:$line: adjacent-string join lost its space: ...$seam"
        fails=$((fails + 1))
    fi
done <"$TMP"

if [ "$fails" -ne 0 ]; then
    echo "string-continuation guard: FAILED ($fails join(s) without a space)"
    echo "  put the space inside one of the fragments, or allowlist the join"
    echo "  with a reason in tests/unit/test-string-continuations.sh"
    exit 1
fi

# --- probes (review a C1/C2, #301): the shapes the alphabet + seam
# normalization fixes cover, executed the way production observes the
# guard -- a full suite run on a scratch mini-repo (the suite resolves
# REPO_ROOT from its own location; the copy in the scratch dir scans
# the probe files). Both probes MUST fail with the expected seams.
_pdir="$(mktemp -d)"
mkdir -p "$_pdir/files/etc" "$_pdir/files/opencode-permissions-kit-lib/bin" \
    "$_pdir/tests/unit"
cp "$0" "$_pdir/tests/unit/test-string-continuations.sh"
# C1: single-quote splice -- detected AND the seam text must be
# normalized (no quote bytes between the fragments).
printf '#!/bin/sh\nui_warn %sfragment one.end.%s%s\\\nnext fragment here%s\n' \
    "'" "'" "'" "'" >"$_pdir/files/install.sh"
# C2: em-dash border in the classic shape -- invisible to an
# ASCII-only alphabet, caught since review a.
printf '#!/bin/sh\nui_warn "failed %s"\\\n"retry now"\n' \
    "$(printf '\342\200\224')" >"$_pdir/files/etc/umask.sh"
if sh "$_pdir/tests/unit/test-string-continuations.sh" >"$_pdir/out" 2>&1; then
    echo "  FAIL  probe: sq-splice / em-dash joins went undetected"
    rm -rf "$_pdir"
    exit 1
fi
if grep -q 'one.end.next fragment' "$_pdir/out" &&
    ! grep -qF "end.''next" "$_pdir/out" &&
    grep -q 'retry now' "$_pdir/out"; then
    echo "  PASS  probes: sq-splice seam normalized; em-dash border detected"
else
    echo "  FAIL  probe seams wrong (normalization or alphabet regressed):"
    cat "$_pdir/out"
    rm -rf "$_pdir"
    exit 1
fi
rm -rf "$_pdir"

echo "string-continuation guard: OK ($allowed allowlisted join(s), no missing-space joins)"
