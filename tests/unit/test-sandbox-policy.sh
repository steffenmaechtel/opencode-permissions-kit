#!/bin/sh
# test-sandbox-policy.sh -- unit suites never create, delete or
# re-permission anything outside their scratch space, and never carry
# real-tree path literals at all (0.0.42e C1, hardened 0.0.42f C3).
#
# Policy (docs/design/conventions.md, "Test sandbox (unit suites)"):
# unit suites operate only on their own scratch ($WORK / mktemp) and the
# sanctioned temp prefixes /tmp, /var/tmp (plus /dev/null). Finding
# history: the ddev-migrate suite once rm -rf'd two real-tree host paths
# in its cleanup and mkdir'd a third in setup (0.0.42e C1 -- executed as
# a live incident on an external review host).
#
# Two checks over the continuation-joined view of each line (full-comment
# lines skipped): check 1 scans the quote-blanked operand view, check 2
# the RAW line (quotes included — see its own header below). Check 3
# runs its own grep (section 3):
#
# 1. MUTATION: a mutating verb (rm, rmdir, mkdir, ln, cp, mv, chown,
#    chmod, chgrp, setfacl, touch, truncate, tee, install, `sed -i`)
#    whose operand is a literal absolute path outside /tmp, /var/tmp,
#    /dev/null fails. All-operand verbs flag every literal; source-to-
#    destination verbs (cp, mv, ln, install, tee) only the DESTINATION;
#    sed only its last operand with -i. Variables are exempt -- what
#    they hold is the review's job.
#
# 2. RATCHET (0.0.42f C3, maintainer directive; raw view 0.0.42g C2):
#    a literal absolute token STARTING with a real-tree prefix (listed
#    in RATCHET_TREES below) fails even in inert or QUOTED fixture
#    strings — the ratchet scans the RAW line (quotes stripped from
#    token edges), only full-comment lines are skipped. Inert literals
#    are one broken rewrite away from live (the migrate fixtures
#    carried them for months behind a sed). Tokens under /tmp or
#    /var/tmp are exempt (sandboxed fixtures are the point); a leading
#    redirection (2>/path) is stripped before matching (0.0.42g C3).
#    Policy-INPUT classes (values fed to screening/parsing functions,
#    never executed) are allowlisted below with reasons.
#
# Backslash-continued commands are joined before scanning (0.0.42f C3:
# `rm -rf \` + path-on-next-line was invisible to the line-based scan);
# a joined command reports the LAST physical line's number (awk NR at
# completion — the self-probes pin the actual behavior).
#
# Run: sh tests/unit/test-sandbox-policy.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Real trees that must never appear as literals in unit suites.
RATCHET_TREES="/var/www/vhosts /srv/other/outside"

# Allowlist for the ratchet: one "file|token" entry per line, a reason
# comment above it (house style of the string-continuations guard).
# Policy-INPUT class only: values handed to screening/parsing functions
# or parse-only argument fixtures -- never executed as paths.
ALLOW="
# parse_args argument fixtures (parse-only suite -- the values are
# parsed, never run; the quoted glob probe token extracts to the
# trailing-slash form, hence the second entry below)
tests/unit/test-install-args.sh|/var/www/vhosts
tests/unit/test-install-args.sh|/var/www/vhosts/
# project_path_sane screening inputs + expected-verdict call fixtures
# (ACCEPT list carries the bare and trailing-slash form, :147 the
# space-suffixed client form)
tests/unit/test-project-paths.sh|/var/www/vhosts
tests/unit/test-project-paths.sh|/var/www/vhosts/
tests/unit/test-project-paths.sh|/var/www/vhosts/client
tests/unit/test-project-paths.sh|/var/www/vhosts/client1
# screening-pattern loop values fed to greps against uninstall.sh
tests/unit/test-uninstall.sh|/var/www/vhosts
"

passed=0
failed=0
pass() { printf '  PASS  %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf '  FAIL  %s\n' "$1"; failed=$((failed + 1)); }

TMP="$(mktemp)"
VIOL="$(mktemp)"
trap 'rm -f "$TMP" "$VIOL"; [ -n "${PROBE_DIR:-}" ] && rm -rf "$PROBE_DIR"' EXIT
PROBE_DIR=""

# scan <dir> -- writes "file|line|kind|token" violation rows to $VIOL.
scan() {
    _scan_dir="$1"
    find "$_scan_dir" -name 'test-*.sh' ! -name 'test-sandbox-policy.sh' | sort | while IFS= read -r f; do
        awk -v f="$f" -v allow="$ALLOW" -v trees="$RATCHET_TREES" -v dq='"' -v sq="'" '
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
            function ratchet_hit(tok) {
                if (substr(tok, 1, 1) != "/") return 0
                if (tok ~ /^\/(tmp\/|var\/tmp\/)/) return 0
                n = split(trees, tr, " ")
                for (i = 1; i <= n; i++)
                    if (substr(tok, 1, length(tr[i])) == tr[i]) return 1
                return 0
            }
            function report(tok, kind) {
                if (allowed(tok)) return
                printf "%s|%d|%s|%s\n", f, NR, kind, tok
            }
            {
                # join backslash continuations into logical lines (the
                # reported line number is the LAST physical line — NR at
                # completion; the self-probes pin this behavior)
                if (length($0) > 0 && substr($0, length($0)) == "\\") {
                    pending = pending substr($0, 1, length($0) - 1)
                    next
                }
                orig = pending $0
                pending = ""
                probe = orig; sub(/^[ \t]+/, "", probe)
                if (substr(probe, 1, 1) == "#") next
                # blank quoted regions: operands-only view (a quoted run
                # collapses into one placeholder token so quoted variable
                # destinations still count as operands; escaped quotes are
                # a documented limitation, none in scope)
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
                # strip an unquoted trailing comment (ops is quote-free)
                hp = index(ops, "#")
                if (hp > 0) ops = substr(ops, 1, hp - 1)

                # --- check 2: real-tree literal ratchet (verb-independent;
                # RAW view so quoted literals count -- 0.0.42g C2).
                # Path-shaped substrings are extracted anywhere in the
                # line -- token-edge prefixes (x=", 2>, ...) must not
                # hide the literal (0.0.42g C3).
                rest = orig
                while (match(rest, /\/[A-Za-z0-9._][A-Za-z0-9._\/-]*/)) {
                    t = substr(rest, RSTART, RLENGTH)
                    sub(/[.,;)&|*]+$/, "", t)
                    if (ratchet_hit(t)) report(t, "ratchet")
                    rest = substr(rest, RSTART + RLENGTH)
                }

                # --- check 1: mutation operand scan (per command segment)
                segs = ops
                gsub(/\|\|/, "\n", segs); gsub(/&&/, "\n", segs)
                gsub(/;/, "\n", segs); gsub(/\|/, "\n", segs)
                m = split(segs, segsArr, "\n")
                for (s = 1; s <= m; s++) {
                    n = split(segsArr[s], tk, /[ \t]+/)
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
                            if (isbad(t)) report(t, "mutate")
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
                            if (isbad(t)) report(t, "mutate")
                        }
                    } else {
                        for (i = vi + 1; i <= n; i++) {
                            if (tk[i] == "") continue
                            t = tk[i]; sub(/^[(=]+/, "", t); sub(/[,;)&|*]+$/, "", t)
                            if (isbad(t)) report(t, "mutate")
                        }
                    }
                }
            }
        ' "$f"
    done
}

# --- 1. the real tree ---------------------------------------------------------
: > "$VIOL"
scan tests/unit > "$VIOL" || true
if [ -s "$VIOL" ]; then
    while IFS='|' read -r vf vl vk vp; do
        case "$vk" in
            mutate) fail "$vf:$vl mutates a literal host path: $vp (policy: /tmp, /var/tmp and \$WORK only)" ;;
            ratchet) fail "$vf:$vl carries a real-tree literal: $vp (sandbox the fixture or allowlist the policy-INPUT class)" ;;
        esac
    done < "$VIOL"
else
    pass "no unit suite mutates or names a literal host path (sandbox policy holds)"
fi

# --- 2. self-probe: the guard must CATCH (positive controls) ------------------
PROBE_DIR="$(mktemp -d)"
mkdir -p "$PROBE_DIR/unit"
printf '#!/bin/sh\n# probe: continuation-split rm must be caught (0.0.42f C3)\nrm -rf \\\n/var/www/vhosts/probe-evil\n' \
    > "$PROBE_DIR/unit/test-probe-cont.sh"
printf '#!/bin/sh\n# probe: inert real-tree literal must be caught (ratchet)\napproot: /var/www/vhosts/probe-two\n' \
    > "$PROBE_DIR/unit/test-probe-ratchet.sh"
printf '#!/bin/sh\n# probe: QUOTED real-tree literal must be caught too (0.0.42g C2)\nx="/var/www/vhosts/probe-quoted"\n' \
    > "$PROBE_DIR/unit/test-probe-quoted.sh"
printf '#!/bin/sh\n# probe: redirect-glued literal must be caught (0.0.42g C3)\nfoo 2>/var/www/vhosts/probe-redir\n' \
    > "$PROBE_DIR/unit/test-probe-redir.sh"
printf '#!/bin/sh\n# probe: sandboxed fixture passes both checks\napproot: /var/tmp/opencode-ddev-mig-roots/vhosts/x\nrm -rf /var/tmp/opencode-ddev-mig-roots\n' \
    > "$PROBE_DIR/unit/test-probe-clean.sh"
: > "$VIOL"
scan "$PROBE_DIR/unit" > "$VIOL" || true
if grep -q "test-probe-cont.sh|4|mutate|/var/www/vhosts/probe-evil" "$VIOL"; then
    pass "self-probe: continuation-split rm -rf is caught"
else
    fail "self-probe: continuation-split rm -rf must be caught (0.0.42f C3)"
fi
if grep -q "test-probe-ratchet.sh|3|ratchet|/var/www/vhosts/probe-two" "$VIOL"; then
    pass "self-probe: inert real-tree literal is caught (ratchet)"
else
    fail "self-probe: inert real-tree literal must be caught (0.0.42f C3)"
fi
if grep -q "test-probe-quoted.sh|3|ratchet|/var/www/vhosts/probe-quoted" "$VIOL"; then
    pass "self-probe: quoted real-tree literal is caught (raw view)"
else
    fail "self-probe: quoted real-tree literal must be caught (0.0.42g C2)"
fi
if grep -q "test-probe-redir.sh|3|ratchet|/var/www/vhosts/probe-redir" "$VIOL"; then
    pass "self-probe: redirect-glued literal is caught"
else
    fail "self-probe: redirect-glued literal must be caught (0.0.42g C3)"
fi
if grep -q "test-probe-clean.sh" "$VIOL"; then
    fail "self-probe: sandboxed probe must not be flagged"
else
    pass "self-probe: sandboxed probe passes clean"
fi

# --- 3. rm suffix form: :? empty-var guard (2026-10-06) -----------------------
# ANY rm invocation (flag form and operand position aware) on a variable
# with a literal suffix: an empty/unset var degenerates the operand to a
# fixed absolute path (rm -rf "$HWORK/proj/vendor" with empty HWORK
# attempts /proj/vendor) instead of the verified no-op of the
# pure-variable form. ALL spelling forms of the suffix operand are
# flagged (0.0.45c C3): quoted unbraced ("$V/x"), quoted braced
# ("${V}/x"), slash OUTSIDE the quotes ("$V"/x) and unquoted ($V/x)
# degenerate identically; the guarded "${V:?}" carries the colon and
# cannot match. Pure-variable operands (`rm -rf "$VAR"`) are exempt —
# an empty operand is a verified rm no-op; the dangerous shape is the
# suffix. The pattern chains rm + flags + complete arguments (quoted or
# unquoted) only — an unquoted `;`/redirect boundary breaks the chain,
# so var+suffix operands of OTHER statements on the same line are not
# flagged (the printf-embedded fixture in test-staged-write must stay
# green).
# Scope (0.0.45b C1, closed 0.0.45d): the unit suites AND the e2e
# helper scripts — the three host-side e2e sites of exactly this shape
# carried no :? while the scan stopped at tests/unit. Checks 1/2 stay
# unit-scoped: e2e scripts legitimately name container paths
# (/var/www/vhosts fixtures) that the real-tree ratchet would flag.
sfx_scan() {
    find "$1" -name "${2:-test-*.sh}" ! -name 'test-sandbox-policy.sh' | sort | while IFS= read -r f; do
        grep -HnE 'rm( -[A-Za-z]+| "[^"]*"| [^";&| ]+)*( "\$[A-Za-z_][A-Za-z0-9_]*/| "\$\{[A-Za-z_][A-Za-z0-9_]*\}/| "\$[A-Za-z_][A-Za-z0-9_]*"/| \$[A-Za-z_][A-Za-z0-9_]*/)' "$f" | grep -Ev ':[0-9]+:[[:space:]]*#' || true
    done
}
: > "$VIOL"
sfx_scan tests/unit > "$VIOL" || true
sfx_scan tests/e2e '*.sh' >> "$VIOL" || true
if [ -s "$VIOL" ]; then
    while IFS= read -r vrow; do
        fail "$vrow  <-- rm on a var+suffix operand without the :? empty-var guard"
    done < "$VIOL"
else
    pass "every rm suffix operand carries the :? empty-var guard"
fi
# self-probe: the unguarded shapes must be caught (flag orders, bare rm,
# multi-operand, and the 0.0.45c C3 forms — braced, slash-outside-quotes,
# unquoted), the guarded and pure-variable ones pass
printf '#!/bin/sh\n# probe: unguarded rm suffix variants must be caught (check 3)\nrm -rf "$PX/evil"\nrm -fr "$PX/evil2"\nrm "$PX/evil3"\nrm -rf "$PX/ok" "$PX/evil4"\nrm "${PX:?}/fine"\nrm -f "${PX:?}/fine2"\nrm -rf "${PX}/evil5"\nrm -rf "$PX"/evil6\nrm -rf $PX/evil7\nrm -rf "${PX:?}/sub/fine3"\nrm -f "$PX"\n' \
    > "$PROBE_DIR/unit/test-probe-sfx.sh"
: > "$VIOL"
sfx_scan "$PROBE_DIR/unit" > "$VIOL" || true
_sfx_rows=$(grep -c 'test-probe-sfx.sh' "$VIOL")
if [ "$_sfx_rows" -eq 7 ] && grep -q 'PX/evil' "$VIOL" && grep -q 'PX/evil2' "$VIOL" \
    && grep -q 'PX/evil3' "$VIOL" && grep -q 'PX/evil4' "$VIOL" \
    && grep -q 'PX}/evil5' "$VIOL" && grep -q 'PX./evil6' "$VIOL" \
    && grep -q 'PX/evil7' "$VIOL"; then
    pass "self-probe: unguarded suffix forms caught (rf, fr, bare rm, multi-operand, braced, slash-outside, unquoted), guarded/pure pass"
else
    fail "self-probe: check 3 must catch the unguarded suffix variants only (rows=$_sfx_rows)"
    grep 'test-probe-sfx.sh' "$VIOL" || true
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
