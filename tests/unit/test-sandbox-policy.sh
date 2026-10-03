#!/bin/sh
# test-sandbox-policy.sh -- unit suites never create, delete or
# re-permission anything outside their scratch space (0.0.42e C1).
#
# Policy (docs/design/conventions.md, "Test sandbox (unit suites)"):
# unit suites operate only on their own scratch ($WORK / mktemp) and the
# sanctioned temp prefixes /tmp, /var/tmp (plus /dev/null). A literal
# absolute operand of a mutating command pointing anywhere else -- above
# all real project trees like /var/www/vhosts, /home, /srv, /etc -- fails
# this guard, in setup and teardown alike. Finding history: the
# ddev-migrate suite once `rm -rf`'d /var/www/vhosts/alpha and
# /var/www/vhosts/sub in its cleanup and mkdir'd /srv/other/outside in
# its setup (0.0.42e C1 -- the rm executed as a live incident on an
# external review host; paths absent there afterwards, pre-run state
# unknown).
#
# Detection, per command segment of a line:
#   - comment lines are skipped; everything inside "..." or '...' is
#     blanked first (assertion payloads and grep patterns are data, not
#     operands -- escaped quotes are a documented limitation, none in
#     scope; none may be introduced without an allowlist entry below);
#   - a mutating verb is one of rm, rmdir, mkdir, ln, cp, mv, chown,
#     chmod, chgrp, setfacl, touch, truncate, tee, install, sed;
#   - all-operand verbs (rm, mkdir, chown, chmod, ...) flag EVERY literal
#     absolute token outside the sanctioned prefixes;
#   - source-to-destination verbs (cp, mv, ln, install, tee) flag only
#     the DESTINATION (last non-option operand) -- a literal source is a
#     read, not a mutation;
#   - sed flags its last operand only when it carries -i.
# Variables ($WORK, $TMP, ...) are exempt -- what they hold is the
# review's job; this guard catches the literal slip.
#
# Deliberate exceptions, one "file|token" entry per line with a reason
# comment above it (house style of the string-continuations guard):
ALLOW=""

# Run: sh tests/unit/test-sandbox-policy.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

passed=0
failed=0
pass() { printf '  PASS  %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; failed=$((failed + 1)); }

TMP="$(mktemp)"
trap 'rm -f "$TMP" "$VIOL"' EXIT
VIOL="$(mktemp)"

# Every unit suite except this guard itself.
find tests/unit -name 'test-*.sh' ! -name 'test-sandbox-policy.sh' | sort > "$TMP"
if [ ! -s "$TMP" ]; then
    printf '  FAIL  no unit suites found to scan\n'
    exit 1
fi

while IFS= read -r f; do
    awk -v f="$f" -v allow="$ALLOW" -v dq='"' -v sq="'" '
        function isbad(t) {
            if (substr(t, 1, 1) != "/") return 0
            if (t ~ /^\/(tmp\/|var\/tmp\/|dev\/null$)/) return 0
            if (t !~ /^\/[A-Za-z0-9._\/-]*$/) return 0
            return 1
        }
        function allowed(tok) {
            if (allow == "") return 0
            return index("\n" allow "\n", "\n" f "|" tok "\n") > 0
        }
        {
            orig = $0
            probe = orig; sub(/^[ \t]+/, "", probe)
            if (substr(probe, 1, 1) == "#") next
            # blank quoted regions: operands-only view of the line. A
            # quoted run collapses into one placeholder token (X) so a
            # quoted variable destination still counts as an operand.
            ops = ""; indq = 0; insq = 0
            L = length(orig)
            for (p = 1; p <= L; p++) {
                ch = substr(orig, p, 1)
                if (!insq && ch == dq) {
                    if (indq) { indq = 0; ops = ops "X" } else indq = 1
                    continue
                }
                if (!indq && ch == sq) {
                    if (insq) { insq = 0; ops = ops "X" } else insq = 1
                    continue
                }
                if (indq || insq) continue
                ops = ops ch
            }
            # strip an unquoted trailing comment (ops is quote-free now)
            hp = index(ops, "#")
            if (hp > 0) ops = substr(ops, 1, hp - 1)
            # split on unquoted command separators
            gsub(/\|\|/, "\n", ops); gsub(/&&/, "\n", ops)
            gsub(/;/, "\n", ops); gsub(/\|/, "\n", ops)
            m = split(ops, segs, "\n")
            for (s = 1; s <= m; s++) {
                n = split(segs[s], tk, /[ \t]+/)
                if (n == 0) continue
                vi = 1
                while (vi <= n && (tk[vi] == "" || tk[vi] ~ /^[A-Za-z_][A-Za-z0-9_]*=/)) vi++
                if (vi > n) continue
                verb = tk[vi]
                if (verb !~ /^(rm|rmdir|mkdir|ln|cp|mv|chown|chmod|chgrp|setfacl|touch|truncate|tee|install|sed)$/) continue
                if (verb == "cp" || verb == "mv" || verb == "ln" || verb == "install" || verb == "tee") {
                    last = ""
                    for (i = n; i > vi; i--) {
                        if (tk[i] == "") continue
                        if (tk[i] ~ /^[0-9]{0,2}>/) continue
                        if (substr(tk[i], 1, 1) == "-") continue
                        last = tk[i]; break
                    }
                    if (last != "") {
                        t = last; sub(/^[(=]+/, "", t); sub(/[,;)&|*]+$/, "", t)
                        if (isbad(t) && !allowed(t)) printf "%s|%d|%s\n", f, NR, t
                    }
                } else if (verb == "sed") {
                    hasi = 0
                    for (i = vi + 1; i <= n; i++) if (tk[i] ~ /^-[A-Za-z]*i/) hasi = 1
                    if (!hasi) continue
                    last = ""
                    for (i = n; i > vi; i--) {
                        if (tk[i] == "") continue
                        if (tk[i] ~ /^[0-9]{0,2}>/) continue
                        last = tk[i]; break
                    }
                    if (last != "") {
                        t = last; sub(/^[(=]+/, "", t); sub(/[,;)&|*]+$/, "", t)
                        if (isbad(t) && !allowed(t)) printf "%s|%d|%s\n", f, NR, t
                    }
                } else {
                    for (i = vi + 1; i <= n; i++) {
                        if (tk[i] == "") continue
                        t = tk[i]; sub(/^[(=]+/, "", t); sub(/[,;)&|*]+$/, "", t)
                        if (isbad(t) && !allowed(t)) printf "%s|%d|%s\n", f, NR, t
                    }
                }
            }
        }
    ' "$f"
done < "$TMP" > "$VIOL" || true

if [ -s "$VIOL" ]; then
    while IFS='|' read -r vf vl vp; do
        fail "$vf:$vl mutates a literal host path: $vp (policy: /tmp, /var/tmp and \$WORK only -- docs/design/conventions.md)"
    done < "$VIOL"
else
    pass "no unit suite mutates a literal host path (sandbox policy holds)"
fi

echo ""
echo "========================================"
if [ "$failed" -gt 0 ]; then
    echo "  FAILED: $failed violation(s)"
    echo "========================================"
    exit 1
fi
echo "  All sandbox-policy checks passed."
echo "========================================"
