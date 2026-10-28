#!/bin/sh
# test-sandbox-policy.sh -- unit suites never create, delete or
# re-permission anything outside their scratch space, and never carry
# real-tree path literals at all (0.0.42e C1, hardened 0.0.42f C3).
#
# Policy (agent/conventions.md, "Test sandbox (unit suites)"):
# unit suites operate only on their own scratch ($WORK / mktemp) and the
# sanctioned temp prefixes /tmp, /var/tmp (plus /dev/null). Finding
# history: the ddev-migrate suite once rm -rf'd two real-tree host paths
# in its cleanup and mkdir'd a third in setup (0.0.42e C1 -- executed as
# a live incident on an external review host).
#
# Two checks over the continuation-joined view of each line (full-comment
# lines skipped): check 1 scans the quote-blanked operand view, check 2
# the RAW line (quotes included — see its own header below). Checks 3-5
# each run their own scan (sections 3-5: grep, find+awk, behavioral
# cells):
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
pass() {
    printf '  PASS  %s\n' "$1"
    passed=$((passed + 1))
}
fail() {
    printf '  FAIL  %s\n' "$1"
    failed=$((failed + 1))
}

TMP="$(mktemp)"
VIOL="$(mktemp)"
# _bh_dir is NOT listed here on purpose: the behavioral cells assign it
# only inside command substitution, and dash resets the parent's caught
# traps in $( ) — the cells trap their own scratch instead (#287 b C7).
trap 'rm -f "$TMP" "$VIOL"; [ -n "${PROBE_DIR:-}" ] && rm -rf "$PROBE_DIR"' EXIT INT TERM
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
: >"$VIOL"
scan tests/unit >"$VIOL" || true
if [ -s "$VIOL" ]; then
    while IFS='|' read -r vf vl vk vp; do
        case "$vk" in
            mutate) fail "$vf:$vl mutates a literal host path: $vp (policy: /tmp, /var/tmp and \$WORK only)" ;;
            ratchet) fail "$vf:$vl carries a real-tree literal: $vp (sandbox the fixture or allowlist the policy-INPUT class)" ;;
        esac
    done <"$VIOL"
else
    pass "no unit suite mutates or names a literal host path (sandbox policy holds)"
fi

# --- 2. self-probe: the guard must CATCH (positive controls) ------------------
PROBE_DIR="$(mktemp -d)"
mkdir -p "$PROBE_DIR/unit"
printf '#!/bin/sh\n# probe: continuation-split rm must be caught (0.0.42f C3)\nrm -rf \\\n/var/www/vhosts/probe-evil\n' \
    >"$PROBE_DIR/unit/test-probe-cont.sh"
printf '#!/bin/sh\n# probe: inert real-tree literal must be caught (ratchet)\napproot: /var/www/vhosts/probe-two\n' \
    >"$PROBE_DIR/unit/test-probe-ratchet.sh"
printf '#!/bin/sh\n# probe: QUOTED real-tree literal must be caught too (0.0.42g C2)\nx="/var/www/vhosts/probe-quoted"\n' \
    >"$PROBE_DIR/unit/test-probe-quoted.sh"
printf '#!/bin/sh\n# probe: redirect-glued literal must be caught (0.0.42g C3)\nfoo 2>/var/www/vhosts/probe-redir\n' \
    >"$PROBE_DIR/unit/test-probe-redir.sh"
printf '#!/bin/sh\n# probe: sandboxed fixture passes both checks\napproot: /var/tmp/opencode-ddev-mig-roots/vhosts/x\nrm -rf /var/tmp/opencode-ddev-mig-roots\n' \
    >"$PROBE_DIR/unit/test-probe-clean.sh"
: >"$VIOL"
scan "$PROBE_DIR/unit" >"$VIOL" || true
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
# cannot match. The DOT-suffix forms ("$V.name", "${V}.name" —
# #287 a C4) degenerate to a relative path in the CWD instead of a
# fixed absolute one, but all three guarded suites cd to the repo root
# (reviews-parity, rules-index-parity, reviews-lint), so the
# empty-var operand still names a real location — guarded the same way.
# Pure-variable operands (`rm -rf "$VAR"`) are exempt —
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
        grep -HnE 'rm( -[A-Za-z]+| "[^"]*"| [^";&| ]+)*( "\$[A-Za-z_][A-Za-z0-9_]*/| "\$\{[A-Za-z_][A-Za-z0-9_]*\}/| "\$[A-Za-z_][A-Za-z0-9_]*"/| \$[A-Za-z_][A-Za-z0-9_]*/| "\$[A-Za-z_][A-Za-z0-9_]*\.| "\$\{[A-Za-z_][A-Za-z0-9_]*\}\.| \$[A-Za-z_][A-Za-z0-9_]*\.)' "$f" | grep -Ev ':[0-9]+:[[:space:]]*#' || true
    done
}
: >"$VIOL"
sfx_scan tests/unit >"$VIOL" || true
sfx_scan tests/e2e '*.sh' >>"$VIOL" || true
if [ -s "$VIOL" ]; then
    while IFS= read -r vrow; do
        fail "$vrow  <-- rm on a var+suffix operand without the :? empty-var guard"
    done <"$VIOL"
else
    pass "every rm suffix operand carries the :? empty-var guard"
fi
# self-probe: the unguarded shapes must be caught (flag orders, bare rm,
# multi-operand, and the 0.0.45c C3 forms — braced, slash-outside-quotes,
# unquoted), the guarded and pure-variable ones pass
printf '#!/bin/sh\n# probe: unguarded rm suffix variants must be caught (check 3)\nrm -rf "$PX/evil"\nrm -fr "$PX/evil2"\nrm "$PX/evil3"\nrm -rf "$PX/ok" "$PX/evil4"\nrm "${PX:?}/fine"\nrm -f "${PX:?}/fine2"\nrm -rf "${PX}/evil5"\nrm -rf "$PX"/evil6\nrm -rf $PX/evil7\nrm -rf "${PX:?}/sub/fine3"\nrm -f "$PX"\nrm -f "$PX.evil8"\nrm -f "${PX:?}.fine8"\nrm -f $PX.evil9\n' \
    >"$PROBE_DIR/unit/test-probe-sfx.sh"
: >"$VIOL"
sfx_scan "$PROBE_DIR/unit" >"$VIOL" || true
# Guarded count (#260, the #244 f W1 class): grep -c exits 1 on zero
# matches (the scanner regressing to no rows). This suite runs without
# set -e, so the zero path records rather than aborts today — guarded
# for uniformity with the swept family.
_sfx_rows=$(grep -c 'test-probe-sfx.sh' "$VIOL" || true)
if [ "$_sfx_rows" -eq 9 ] && grep -q 'PX/evil' "$VIOL" && grep -q 'PX/evil2' "$VIOL" &&
    grep -q 'PX/evil3' "$VIOL" && grep -q 'PX/evil4' "$VIOL" &&
    grep -q 'PX}/evil5' "$VIOL" && grep -q 'PX./evil6' "$VIOL" &&
    grep -q 'PX/evil7' "$VIOL" && grep -q 'PX.evil8' "$VIOL" &&
    grep -q 'PX.evil9' "$VIOL"; then
    pass "self-probe: unguarded suffix forms caught (rf, fr, bare rm, multi-operand, braced, slash-outside, unquoted, dot quoted+unquoted), guarded/pure pass"
else
    fail "self-probe: check 3 must catch the unguarded suffix variants only (rows=$_sfx_rows)"
    grep 'test-probe-sfx.sh' "$VIOL" || true
fi

# --- 4. trap coverage floor: receivers must sit under an armed trap ------------
# (issue #283; the sibling idiom — test-project-paths.sh #280 c C1 /
# #280 d S2, test-fs-baseline.sh issue #14): a suite with mktemp scratch
# must register a trap on EXIT AND the signal arms INT TERM — a set -e abort
# or a Ctrl-C between a receiver's creation and its inline rm leaked the
# scratch in /tmp. This is the FLOOR check, a lint shape: it pins
# that every receiver-carrying suite HAS a trap statement and that every
# trap statement carries all three arms. Whether the trap's action LIST
# every receiver (variable-level completeness) cannot be grepped — that
# stays the review's job, pinned behaviorally by section 5's mechanism
# cells. Receiver detection: a live assignment whose value starts with
# an UNESCAPED $(mktemp (comment lines skipped), an optional `command `
# prefix included ($(command mktemp …)); heredoc-embedded child
# scripts carry \$ ( — escaped, excluded by design: child scripts own
# their cleanup. The function form (trap _cleanup EXIT INT TERM) is
# accepted: the arms live on the trap line, the rm lives in the
# function. Line-based like check 3: a trap statement split across a
# backslash continuation hides its arms from the scan — keep the arms
# on the trap's physical line (the self-probes pin the shape). Arms are
# read AFTER the action's closing quote, so action text (kill -TERM, an
# in-action comment naming the arms) cannot satisfy the arm check.
# Known latent shape gaps, documented not scanned (no live instance;
# heredoc-aware scanning needs a parser the floor deliberately avoids):
# prefixed receivers (local/readonly/export V=…), trap lines inside
# heredocs counting as the suite's trap, and unescaped line-start
# receivers inside quoted heredocs. Substitution-INTERIOR receiver
# shapes are equally latent (#287 b C3/S4): `$( command mktemp)`
# (leading space), `$(env mktemp …)`, `$(command -p mktemp …)`,
# `$(sudo mktemp …)`, backtick forms — the optional `command ` prefix
# covers the one shape the corpus uses (test-status's _w2_dir).
# This suite excludes itself like checks 1-2 (its own trap is pinned by
# shipping the guard, not by scanning itself).
trap_scan() {
    find "$1" -name "${2:-test-*.sh}" ! -name 'test-sandbox-policy.sh' | sort | while IFS= read -r f; do
        awk -v f="$f" -v dq='"' -v sq="'" '
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*="?[$][(](command[[:space:]]+)?mktemp/ { recv++ }
            /^[[:space:]]*trap[[:space:]].*/ {
                traps++
                _ln = NR
                # cut a trailing comment FIRST (#287 b S1: the greedy
                # last-quote strip alone ate the ARMS whenever the comment
                # carried a quote — an apostrophe is ordinary comment text),
                # quote-aware so an in-action # survives (#287 b C2: comment
                # words must not satisfy the arms either); backslash-aware
                # so an escaped \" never toggles the state (#287 c S1: an
                # odd escaped-quote count cut at a shell-internal # and
                # false-flagged all three arms) — but ONLY outside single
                # quotes, where backslash is a literal, not an escape
                # (#287 d D1: the unconditional skip ate an sq-closing
                # quote after a trailing \ and let a trailing comment
                # satisfy the arms — fail-open)
                _ap = $0
                _ins = 0; _ind = 0; _cut = 0
                for (_i = 1; _i <= length(_ap); _i++) {
                    _ch = substr(_ap, _i, 1)
                    if (!_ins && _ch == "\\") { _i++; continue }
                    if (_ch == sq && !_ind) _ins = !_ins
                    else if (_ch == dq && !_ins) _ind = !_ind
                    else if (_ch == "#" && !_ins && !_ind) { _cut = _i; break }
                }
                if (_cut) _ap = substr(_ap, 1, _cut - 1)
                sub(".*[" dq sq "]", "", _ap)
                if (_ap !~ /[^A-Za-z]EXIT([^A-Za-z]|$)/) arms = arms " " _ln ":no-EXIT"
                if (_ap !~ /[^A-Za-z]INT([^A-Za-z]|$)/) arms = arms " " _ln ":no-INT"
                if (_ap !~ /[^A-Za-z]TERM([^A-Za-z]|$)/) arms = arms " " _ln ":no-TERM"
            }
            END {
                if (recv > 0 && traps == 0) print f "|notrap"
                if (arms != "") print f "|arms" arms
            }
        ' "$f"
    done
}
# The scan target must exist and hold at least one suite OTHER than this
# guard itself — an absent, emptied or guard-only tests/unit would leave
# $VIOL empty and green the floor vacuously (#287 a S3; #287 b C6 closes
# the guard-only variant: the assert used to count this file). A
# SYMLINKED tests/unit also reds the assert, deliberately: find does not
# descend a symlinked start point, so every scan in this suite would be
# blind there — red beats a silent vacuous green (#287 b C5, kept).
_ts_assert_dir() {
    [ -d "$1" ] && [ -n "$(find "$1" -name 'test-*.sh' ! -name 'test-sandbox-policy.sh' -print -quit 2>/dev/null)" ]
}
_ts_bad=0
_ts_assert_dir tests/unit || _ts_bad=1
if [ "$_ts_bad" -eq 0 ]; then
    pass "scan target present: tests/unit holds unit suites"
else
    fail "scan target missing: tests/unit must exist and hold test-*.sh (floor cannot run)"
fi
: >"$VIOL"
trap_scan tests/unit >"$VIOL" || true
if [ -s "$VIOL" ]; then
    while IFS='|' read -r tf tk; do
        case "$tk" in
            notrap) fail "$tf has mktemp receiver(s) but no trap statement (#283: register one, arms EXIT INT TERM)" ;;
            arms*) fail "$tf trap statement missing arms:${tk#arms } (#283: every trap needs EXIT INT TERM)" ;;
        esac
    done <"$VIOL"
else
    pass "every receiver-carrying suite traps its scratch with EXIT INT TERM arms (trap-coverage floor)"
fi
# self-probe: the notrap and half-armed shapes must be caught, the full
# line-form and function-form fixtures must pass
printf '#!/bin/sh\n# probe: receiver without any trap must be caught (check 4)\nP4A="$(mktemp -d)"\n' \
    >"$PROBE_DIR/unit/test-probe-trap-none.sh"
printf '#!/bin/sh\n# probe: EXIT-only trap must be caught (missing signal arms)\nP4B="$(mktemp -d)"\ntrap "rm -rf \"$P4B\"" EXIT\n' \
    >"$PROBE_DIR/unit/test-probe-trap-exit.sh"
printf '#!/bin/sh\n# probe: full line form passes\nP4C="$(mktemp -d)"\ntrap "rm -rf \"${P4C:-}\"" EXIT INT TERM\n' \
    >"$PROBE_DIR/unit/test-probe-trap-line.sh"
printf '#!/bin/sh\n# probe: function form passes (arms on the trap line, rm in the function)\nP4D="$(mktemp -d)"\n_p4clean() { rm -rf "${P4D:-}"; }\ntrap _p4clean EXIT INT TERM\n' \
    >"$PROBE_DIR/unit/test-probe-trap-func.sh"
printf '#!/bin/sh\n# probe: heredoc-escaped receiver (child script) is not a suite receiver\n_cat > /dev/null <<EOF\n_h = \\$(mktemp -d)\nEOF\n' \
    >"$PROBE_DIR/unit/test-probe-trap-heredoc.sh"
: >"$VIOL"
trap_scan "$PROBE_DIR/unit" >"$VIOL" || true
if grep -q 'test-probe-trap-none.sh|notrap' "$VIOL"; then
    pass "self-probe: trapless receiver suite is caught"
else
    fail "self-probe: trapless receiver suite must be caught (check 4)"
fi
if grep -q 'test-probe-trap-exit.sh|arms.*no-INT' "$VIOL" && grep -q 'test-probe-trap-exit.sh|arms.*no-TERM' "$VIOL"; then
    pass "self-probe: EXIT-only trap flagged for missing signal arms"
else
    fail "self-probe: EXIT-only trap must be flagged for missing INT/TERM arms (check 4)"
fi
if grep -qE 'test-probe-trap-(line|func|heredoc)\.sh\|' "$VIOL"; then
    fail "self-probe: full line/function-form and heredoc fixtures must pass clean"
    grep -E 'test-probe-trap-(line|func|heredoc)' "$VIOL" || true
else
    pass "self-probe: line form, function form and heredoc fixtures pass clean"
fi
# $(command mktemp …) receivers count too (#287 a C1); action text must
# NOT satisfy the arm check (#287 a C2): the kill -TERM action and the
# in-action comment would arm an EXIT-only trap if arms were read from
# the whole line.
printf '#!/bin/sh\n# probe: command-prefixed receiver without a trap must be caught\nP4E="$(command mktemp -d)"\n' \
    >"$PROBE_DIR/unit/test-probe-trap-cmd.sh"
printf '#!/bin/sh\n# probe: action text must not satisfy the arm check\nP4F="$(mktemp -d)"\ntrap "kill -TERM \\"\\$P4F.child\\"" EXIT\n' \
    >"$PROBE_DIR/unit/test-probe-trap-act.sh"
printf '#!/bin/sh\n# probe: arms named inside an in-action comment must not count\nP4G="$(mktemp -d)"\ntrap "rm -rf \\"\\$P4G\\" # EXIT INT TERM" EXIT\n' \
    >"$PROBE_DIR/unit/test-probe-trap-cmt.sh"
printf '#!/bin/sh\n# probe: a trailing comment carrying quotes must not eat the arms (#287 b S1)\nP4H="$(mktemp -d)"\ntrap "rm -rf \\"\\$P4H\\"" EXIT INT TERM # see "notes"\n' \
    >"$PROBE_DIR/unit/test-probe-trap-tcmt.sh"
printf '#!/bin/sh\n# probe: a trailing comment NAMING the arms must not satisfy them (#287 b C2)\nP4I="$(mktemp -d)"\ntrap "rm -rf \\"\\$P4I\\"" EXIT # TODO: add INT TERM arms\n' \
    >"$PROBE_DIR/unit/test-probe-trap-todo.sh"
printf '#!/bin/sh\n# probe: escaped quotes around an in-action # must not cut the comment scan (#287 c S1)\nP4J="$(mktemp -d)"\ntrap "rm -rf \\"\\$P4J\\" # \\"a # b\\"" EXIT INT TERM\n' \
    >"$PROBE_DIR/unit/test-probe-trap-esc.sh"
printf '#!/bin/sh\n# probe: sq action ending in a backslash — the skip must not eat the closing quote (#287 d D1)\nP4K="$(mktemp -d)"\ntrap '"'"'rm -rf "$P4K" \\'"'"' EXIT # add INT TERM arms\n' \
    >"$PROBE_DIR/unit/test-probe-trap-sqbs.sh"
: >"$VIOL"
trap_scan "$PROBE_DIR/unit" >"$VIOL" || true
if grep -q 'test-probe-trap-cmd.sh|notrap' "$VIOL"; then
    pass "self-probe: command-prefixed receiver caught"
else
    fail "self-probe: command-prefixed receiver must be caught (#287 a C1)"
fi
if grep -q 'test-probe-trap-act.sh|arms.*no-INT' "$VIOL" && grep -q 'test-probe-trap-act.sh|arms.*no-TERM' "$VIOL" &&
    grep -q 'test-probe-trap-cmt.sh|arms.*no-INT' "$VIOL" && grep -q 'test-probe-trap-cmt.sh|arms.*no-TERM' "$VIOL"; then
    pass "self-probe: action text does not satisfy the arm check (TERM/INT named in action flagged)"
else
    fail "self-probe: action-text traps must be flagged for the arms they only name (#287 a C2)"
fi
if grep -q 'test-probe-trap-todo.sh|arms.*no-INT' "$VIOL" && grep -q 'test-probe-trap-todo.sh|arms.*no-TERM' "$VIOL"; then
    pass "self-probe: trailing comment naming arms does not satisfy them (#287 b S1/C2)"
else
    fail "self-probe: trailing comment naming arms must be flagged (#287 b C2)"
fi
if grep -q 'test-probe-trap-tcmt.sh|' "$VIOL"; then
    fail "self-probe: armed trap with a quote-bearing trailing comment must pass clean (#287 b S1)"
    grep 'test-probe-trap-tcmt' "$VIOL" || true
else
    pass "self-probe: quote-bearing trailing comment does not eat the arms (#287 b S1)"
fi
if grep -q 'test-probe-trap-esc.sh|' "$VIOL"; then
    fail "self-probe: escaped quotes around an in-action # must not cut the scan (#287 c S1)"
    grep 'test-probe-trap-esc' "$VIOL" || true
else
    pass "self-probe: escaped-quote action with in-action # passes clean (#287 c S1)"
fi
if grep -q 'test-probe-trap-sqbs.sh|arms.*no-INT' "$VIOL" && grep -q 'test-probe-trap-sqbs.sh|arms.*no-TERM' "$VIOL"; then
    pass "self-probe: sq-final-backslash action — trailing comment does not satisfy arms (#287 d D1)"
else
    fail "self-probe: sq-final-backslash + arm-naming comment must be flagged (#287 d D1)"
fi
# scan-target assert must fail loudly on a vanished directory (#287 a S3)
_ts_probe=0
_ts_assert_dir "$PROBE_DIR/unit/no-such-dir-$$" || _ts_probe=1
if [ "$_ts_probe" -eq 1 ]; then
    pass "self-probe: absent scan target fails the assert (no vacuous floor pass)"
else
    fail "self-probe: absent scan target must fail the assert (#287 a S3)"
fi
# ...and on a present-but-empty one (#287 b C6: guard-only/emptied trees
# must not pass the assert)
_ts_empty="$(mktemp -d)"
_ts_probe2=0
_ts_assert_dir "$_ts_empty" || _ts_probe2=1
command rm -rf "${_ts_empty:?}"
if [ "$_ts_probe2" -eq 1 ]; then
    pass "self-probe: empty scan target fails the assert (guard-only trees cannot pass)"
else
    fail "self-probe: empty scan target must fail the assert (#287 b C6)"
fi

# --- 5. behavioral: the trap idiom collects scratch on abort and signal --------
# (#283 representative pin, the issue's fix sketch): a generated
# mini-suite runs with an ISOLATED TMPDIR (its mktemp receiver can only
# land there), a forced set -e abort inside the receiver window must
# leave ZERO entries behind; the trap-gone control arm must leave the
# scratch BEHIND — the cell pair proves the pin discriminates through
# the trap, not through the abort. The signal cells drive SIGTERM into
# the window via a session-group kill (setsid; the sleep must die with
# the shell or the trap waits out the window), with an elapsed-time
# guard: a kill that never landed would let the child finish normally
# and green the cell through the EXIT arm — the wrong mechanism
# (0.0.46a F2 vacuity class). Known caveats, recorded (#287 b Q3): the
# <10 s bound leaves ~9 s of slack beyond the mandatory 1 s sleep — a
# heavily loaded host can false-red a cell (loud, self-diagnosing); and
# a FAST-exiting child (sleep missing from PATH — not realistic on CI)
# would green the armed cell through the EXIT arm with elapsed ~0; the
# elapsed guard catches only the slow misses.
_bh_cell() {
    # $1 = armed|gone, $2 = abort|term -- prints "<leftovers> <elapsed>"
    _bh_dir="$(mktemp -d)"
    # The cell runs inside command substitution, and dash resets the
    # parent's caught traps in $( ) — the SUITE trap can never see this
    # _bh_dir (its top-level copy stays empty; #287 b C7 refuted the
    # round-a suite-trap operand). The cell subshell catches its own
    # signals instead — w2_run's idiom — and the EXIT arm owns the
    # normal path (no tail rm).
    trap 'command rm -rf "${_bh_dir:-}"' EXIT INT TERM
    _bh_start=$(date +%s)
    case "$1:$2" in
        armed:abort | armed:term)
            _bh_trap='trap '"'"'rm -rf "${BHW:-}"'"'"' EXIT INT TERM'
            ;;
        gone:abort | gone:term)
            _bh_trap=':'
            ;;
    esac
    if [ "$2" = abort ]; then
        TMPDIR="$_bh_dir" sh -c "
            set -e
            $_bh_trap
            BHW=\"\$(mktemp -d)\"
            exit 3
        " _ >/dev/null 2>&1 || :
    else
        TMPDIR="$_bh_dir" setsid sh -c "
            $_bh_trap
            BHW=\"\$(mktemp -d)\"
            sleep 30
        " _ >/dev/null 2>&1 &
        _bh_pid=$!
        sleep 1
        kill -TERM "-$_bh_pid" 2>/dev/null || :
        wait "$_bh_pid" 2>/dev/null || :
    fi
    _bh_left=$(find "$_bh_dir" -mindepth 1 | wc -l | tr -d ' ')
    _bh_el=$(($(date +%s) - _bh_start))
    # no tail rm — the cell trap above owns every path (normal, abort,
    # signal; the EXIT arm fires on subshell return)
    printf '%s %s' "$_bh_left" "$_bh_el"
}
_bh_abort_armed=$(_bh_cell armed abort)
_bh_abort_gone=$(_bh_cell gone abort)
_bh_term_armed=$(_bh_cell armed term)
_bh_term_gone=$(_bh_cell gone term)
if [ "${_bh_abort_armed%% *}" = 0 ]; then
    pass "abort window: armed trap leaves zero leftovers"
else
    fail "abort window: armed trap must leave zero leftovers (got $_bh_abort_armed)"
fi
if [ "${_bh_abort_gone%% *}" -ge 1 ]; then
    pass "abort window: trap-gone control leaks (pin discriminates)"
else
    fail "abort window: trap-gone control must leak — otherwise the abort cell is vacuous (got $_bh_abort_gone)"
fi
if [ "${_bh_term_armed%% *}" = 0 ] && [ "${_bh_term_armed##* }" -lt 10 ]; then
    pass "signal window: armed trap leaves zero leftovers, TERM landed (<10s)"
else
    fail "signal window: armed trap must collect within the kill window (got $_bh_term_armed; elapsed must be <10)"
fi
if [ "${_bh_term_gone%% *}" -ge 1 ] && [ "${_bh_term_gone##* }" -lt 10 ]; then
    pass "signal window: trap-gone control leaks, TERM landed (pin discriminates)"
else
    fail "signal window: trap-gone control must leak within the kill window (got $_bh_term_gone; elapsed must be <10)"
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
