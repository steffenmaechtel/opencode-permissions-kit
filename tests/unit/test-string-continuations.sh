#!/bin/sh
# test-string-continuations.sh -- guard against the missing-space class at
# adjacent-string line continuations (0.0.39o C1/Q1).
#
# Class: wrapping a long string literal as
#     ui_warn "fragment one."\
#     "fragment two"
# (single-quote style likewise) concatenates WITHOUT any space unless one
# fragment carries it -- the message then renders "fragment one.fragment
# two". The wrap idiom itself is fine (SC2140 is excluded for it,
# Makefile); the JOIN must stay deliberate. This test fails on joins of
# either quote style where prose meets without a space: first fragment
# ending in [.,;:!?] or alnum, second starting with alnum, quote or '('.
# Token concatenation (URL segments, regex alternatives, comma-separated
# lists, option strings) does not match that pattern; the few deliberate
# prose-like no-space joins are allowlisted below with reasons.
#
# Limitation (accepted): a line whose closing quote is itself escaped
# (...\") confuses the seam detection -- none exist in the scope today;
# the allowlist is the escape hatch if one ever does.
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
trap 'rm -f "$TMP"' EXIT

# Paths in this repo contain no spaces (same assumption as the ratchet).
{
    find files -name '*.sh' -type f
    find files/opencode-permissions-kit-lib/bin -type f
} | sort -u | while IFS= read -r f; do
    awk -v f="$f" -v tails='.,;:!?A-Za-z0-9' -v heads="A-Za-z0-9'(" \
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
                }
            }
        }
    { prev = $0 }
        ' "$f" || printf 'AWK-ERROR\t0\t%s\n' "$f"
done > "$TMP"

fails=0
allowed=0
TAB="$(printf '\t')"
while IFS="$TAB" read -r path line seam; do
    [ -n "$path" ] || continue
    ok=""
    while IFS='|' read -r suffix want; do
        case "$suffix" in ''|'#'*) continue ;; esac
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
done < "$TMP"

if [ "$fails" -ne 0 ]; then
    echo "string-continuation guard: FAILED ($fails join(s) without a space)"
    echo "  put the space inside one of the fragments, or allowlist the join"
    echo "  with a reason in tests/unit/test-string-continuations.sh"
    exit 1
fi

echo "string-continuation guard: OK ($allowed allowlisted join(s), no missing-space joins)"
