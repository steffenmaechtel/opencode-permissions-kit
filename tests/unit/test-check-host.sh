#!/bin/sh
# test-check-host.sh — gh version warning arms in check-host.sh (issue #335).
# MINI pin by maintainer direction: behavioral arms only.
# Run: sh tests/unit/test-check-host.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}"' EXIT INT TERM
fails=0

arm() { # <fake-gh-version> <want: warn|ok>
    printf '#!/bin/sh\necho "gh version %s (2026-02-23)"\n' "$1" >"$WORK/gh"
    chmod +x "$WORK/gh"
    out="$(PATH="$WORK:$PATH" sh "$REPO_ROOT/tests/check-host.sh" 2>&1)"
    hits() { printf '%s\n' "$out" | grep -qF -- "$1"; }
    if [ "$2" = warn ]; then
        if ! hits "issue #335" || ! hits "--json" ||
            printf '%s\n' "$out" | grep -q "missing:.*gh"; then rc=1; else rc=0; fi
    elif hits "agent issue/PR workflow ($1 >= 2.87)"; then rc=0; else rc=1; fi
    if [ "$rc" -eq 0 ]; then
        echo "ok:   gh $1 -> $2"
    else
        echo "FAIL: gh $1 should report '$2'"
        fails=$((fails + 1))
    fi
}

arm 2.45.0 warn # the Ubuntu-ESM version on this host
arm 2.10.0 warn # numeric compare: 10 < 87 (string compare would pass it)
arm devel warn  # unparseable version -> the 2>/dev/null probe's failure path
arm 2.87 ok     # the minimum itself
arm 2.87.3 ok

[ "$fails" -eq 0 ] && echo "test-check-host: passed" || exit 1
