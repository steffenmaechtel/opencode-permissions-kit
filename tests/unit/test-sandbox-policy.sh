#!/bin/sh
# test-sandbox-policy.sh -- unit suites never create, delete or
# re-permission anything outside their scratch space, and never carry
# real-tree path literals at all (0.0.42e C1, hardened 0.0.42f C3).
#
# Policy (tests/AGENTS.md, "Test sandbox (unit suites)"):
# unit suites operate only on their own scratch ($WORK / mktemp) and the
# sanctioned temp prefixes /tmp, /var/tmp (plus /dev/null). Finding
# history: the ddev-migrate suite once rm -rf'd two real-tree host paths
# in its cleanup and mkdir'd a third in setup (0.0.42e C1 -- executed as
# a live incident on an external review host).
#
# Two checks over the continuation-joined view of each line (full-comment
# lines skipped): check 1 scans the quote-blanked operand view (a quoted
# run opening with "/" is a LITERAL path and keeps its bytes there, #727
# fix B), check 2 the RAW line (quotes included — see its own header
# below). Checks 3-5
# each run their own scan (sections 3-5: grep, find+python — check 4's
# detector is tests/unit/lib/trap_detect.py since #498 —, behavioral
# cells):
#
# 1. MUTATION: a mutating verb (rm, rmdir, mkdir, ln, cp, mv, chown,
#    chmod, chgrp, setfacl, touch, truncate, tee, install, `sed -i`)
#    whose operand is a literal absolute path outside /tmp, /var/tmp,
#    /dev/null fails. All-operand verbs flag every literal; source-to-
#    destination verbs (cp, mv, ln, install, tee) only the DESTINATION;
#    sed only its last operand with -i. Variables are exempt -- what
#    they hold is the review's job -- and a QUOTED literal operand
#    fails like its unquoted form (#727 fix B: quote-blanking used to
#    hide it, and the raw-view ratchet only knows RATCHET_TREES).
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
#    never executed) are allowlisted below with reasons -- and an ALLOW
#    row can never cover a MUTATION finding: report() consults the
#    allowlist for ratchet findings only (#727 fix A).
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
# or parse-only argument fixtures -- never executed as paths. New rows
# are the LAST resort (#727): write the fixture against a fictional
# open prefix (/home/some-user-max-mustermann/...) instead; a real-tree
# literal earns an entry only where the literal IS the assertion's
# subject (a source pin that must match shipped bytes, a policy control
# row) -- and an ALLOW row can never cover a MUTATION finding (report()
# enforces it, fix A). Shrunk 15 -> 2 rows by the #727 sweep: the
# policy-INPUT classes above moved to fictional prefixes.
ALLOW="
# BOUND (#727): the allows-loop value is the assertion's subject --
# uninstall-core's screening must SPARE the documented project home
# /var/www/vhosts (the screening-allows loop fails when the screener
# rejects it). Not replaceable by a fictional prefix without losing
# the pin.
tests/unit/test-uninstall-core.sh|/var/www/vhosts
# BOUND (#727): default-scan-root source pin over sh/doctor-core.sh
# (#354, #448) -- the literal is a grep PATTERN that must match the
# SHIPPED bytes (the [ -d /var/www/vhosts ] default-scan-root line);
# changing the default root is a product decision, not test hygiene.
tests/unit/test-doctor.sh|/var/www/vhosts
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

# Parse-integrity pin (#727): the ALLOW block above is a double-quoted
# shell string whose reason lines are STRING CONTENT, not comments. A
# double-quoted phrase WITH WHITESPACE inside a reason line splits the
# assignment at the shell level and silently truncates the variable
# (measured: "screening allows" in a reason comment cut both BOUND rows
# and reddened the ratchet with a misleading sweep-regression message,
# one red gate cycle paid -- adjacent quotes without inner spaces
# merely lose their quote bytes, entries intact); an unescaped
# expansion char silently empties into the text (measured: $UNDEFINED
# in a reason line renders blank). The rendered variable must carry
# every BOUND entry verbatim; the count is the allowlist ratchet -- a
# new row is a deliberate edit here (#727: growth stays the
# maintainer's overview, not drift).
_al_entries=$(printf '%s\n' "$ALLOW" | grep -cE '^[a-z].*\|' || true)
if [ "$_al_entries" -eq 2 ]; then
    pass "ALLOW parses clean: 2 BOUND entries render verbatim (#727)"
else
    fail "ALLOW broke while parsing or grew -- reason lines must carry no double quotes/expansions, growth is a conscious count bump (entries=$_al_entries, #727)"
fi

# scan <dir> -- writes "file|line|kind|token" violation rows to $VIOL.
# The sourced test lib (tests/unit/lib/*.sh) is scanned like a suite --
# it is runtime part of every suite that sources it (review #398 a F9:
# the name glob alone let the lib escape the policy scan).
# #519 (from #516 a A2): the old find|sort|while pipeline swallowed a
# per-file awk death (the || true call sites read green over partial
# or empty output); the scan now runs per-file with an rc guard and
# fails loud on any detector death or an empty scan set.
scan() {
    _sc_dir="$1"
    _sc_list="$(mktemp)"
    find "$_sc_dir" \( -name 'test-*.sh' -o -path '*/lib/*.sh' \) ! -name 'test-sandbox-policy.sh' |
        sort >"$_sc_list"
    set --
    while IFS= read -r _sc_f; do
        set -- "$@" "$_sc_f"
    done <"$_sc_list"
    command rm -f "$_sc_list"
    if [ "$#" -eq 0 ]; then
        echo "sandbox-policy tests: scan found no suites in '$_sc_dir' -- checks 1-2 output unreliable (#519)" >&2
        return 1
    fi
    _sc_bad=0
    for _sc_f; do
        awk -v f="$_sc_f" -v allow="$ALLOW" -v trees="$RATCHET_TREES" -v dq='"' -v sq="'" '
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
                # #727 fix A: the allowlist exists for policy-INPUT
                # strings -- ratchet findings -- ONLY. A mutation
                # finding fails the suite whatever the allowlist says:
                # no ALLOW row can ever hide an rm -rf class operand
                # behind an inert-string exception (probe: the
                # test-probe-allowmut block below).
                if (kind == "ratchet" && allowed(tok)) return
                printf "%s|%d|%s|%s\n", f, NR, kind, tok
            }
            # #727 fix B: a quoted run that opens with "/" is a LITERAL
            # path operand, not a variable -- keep its bytes so check 1
            # sees them (rm -rf "/srv/x" was invisible: blanked here and
            # not a ratchet tree). Variable runs keep the X placeholder
            # (what a variable holds is for the review, tests/AGENTS.md
            # Test sandbox section).
            function quote_out(q) {
                if (substr(q, 1, 1) == "/") return q
                return "X"
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
                # a documented limitation, none in scope). A run opening
                # with "/" is a LITERAL path: its bytes stay visible for
                # check 1 (#727 fix B, quote_out above). The unquoted
                # trailing comment is cut inside the walk now -- kept
                # literal bytes may carry "#", so ops is no longer
                # #-free and a post-hoc index() strip would truncate the
                # line at a quoted "#".
                ops = ""; indq = 0; insq = 0; qrun = ""
                L = length(orig)
                for (p = 1; p <= L; p++) {
                    ch = substr(orig, p, 1)
                    if (!insq && ch == dq) {
                        if (indq) { indq = 0; ops = ops quote_out(qrun) } else { indq = 1; qrun = "" }
                        continue
                    }
                    if (!indq && ch == sq) {
                        if (insq) { insq = 0; ops = ops quote_out(qrun) } else { insq = 1; qrun = "" }
                        continue
                    }
                    if (indq || insq) { qrun = qrun ch; continue }
                    if (ch == "#") break
                    ops = ops ch
                }

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
        ' "$_sc_f" || {
            echo "sandbox-policy tests: scan died on '$_sc_f' (rc=$?) -- checks 1-2 output unreliable (#519)" >&2
            _sc_bad=1
        }
    done
    [ "$_sc_bad" -eq 0 ]
}

# --- 1. the real tree ---------------------------------------------------------
: >"$VIOL"
if ! scan tests/unit >"$VIOL"; then
    fail "scan died on tests/unit -- checks 1-2 cannot run (#519)"
fi
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
if ! scan "$PROBE_DIR/unit" >"$VIOL"; then
    fail "scan died on the probe scan -- checks 1-2 self-probes unreliable (#519)"
fi
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

# --- 2b. self-probe: an ALLOW row can never suppress a mutation (#727) -------
# report() consults the allowlist for ratchet findings only (fix A). The
# probe token carries a dedicated ALLOW row for this scan, so the ratchet
# row must vanish while the mutate row survives: the exception channel
# cannot hide an rm -rf class operand, however long the list grows.
printf '#!/bin/sh\n# probe: allowlisted token as rm operand must still fail\nrm -rf /var/www/vhosts/probe-allow\n' \
    >"$PROBE_DIR/unit/test-probe-allowmut.sh"
: >"$VIOL"
if ! (
    ALLOW="$ALLOW
$PROBE_DIR/unit/test-probe-allowmut.sh|/var/www/vhosts/probe-allow"
    scan "$PROBE_DIR/unit" >"$VIOL"
); then
    fail "scan died on the allow-mutate probe -- #727 self-probe unreliable (#519)"
fi
if grep -q "test-probe-allowmut.sh|3|mutate|/var/www/vhosts/probe-allow" "$VIOL" &&
    ! grep -q "test-probe-allowmut.sh|3|ratchet|/var/www/vhosts/probe-allow" "$VIOL"; then
    pass "self-probe: ALLOW suppresses the ratchet row, never the mutate row (#727)"
else
    fail "self-probe: an ALLOW row must never suppress a mutation finding (#727)"
fi

# --- 2c. self-probe: a quoted literal operand outside the ratchet trees -----
# (#727 fix B): quote-blanking used to hide quoted literal operands from
# check 1, and the raw-view ratchet only knows RATCHET_TREES -- an
# rm -rf "/srv/x"-style line was fully green. The first probe line must
# flag as mutate; the second (a quoted VARIABLE operand) must stay
# exempt -- what a variable holds is the review's job (tests/AGENTS.md,
# Test sandbox section).
printf '#!/bin/sh\n# probe: quoted literal (#727)\nrm -rf "/home/some-user-max-mustermann/probe-qlit"\nrm -rf "$PWQLIT"\n' \
    >"$PROBE_DIR/unit/test-probe-qlit.sh"
: >"$VIOL"
if ! scan "$PROBE_DIR/unit" >"$VIOL"; then
    fail "scan died on the quoted-literal probe -- #727 self-probe unreliable (#519)"
fi
_qlit_rows=$(grep -c 'test-probe-qlit.sh' "$VIOL" || true)
if [ "$_qlit_rows" -eq 1 ] &&
    grep -q "test-probe-qlit.sh|3|mutate|/home/some-user-max-mustermann/probe-qlit" "$VIOL"; then
    pass "self-probe: quoted literal rm operand caught, quoted variable stays exempt (#727)"
else
    fail "self-probe: quoted non-tree literal must be caught as mutate only (rows=$_qlit_rows, #727)"
fi

# --- 2d. self-probe: a quoted "#" must not cut the operand view -------------
# (#727 fix B rider): kept literal bytes may carry "#" -- a quoted
# program glued to a later command is the house shape (grep "/a#b" x
# && rm ...) -- so the unquoted comment cut happens INSIDE the quote
# walk and the rm segment behind a quoted "#"-bearing literal stays
# visible to check 1 (a post-hoc index("#") strip over ops would
# truncate the line exactly there).
printf '#!/bin/sh\n# probe: quoted hash (#727)\ngrep "/a#b" x && rm -rf /home/some-user-max-mustermann/probe-hash\n' \
    >"$PROBE_DIR/unit/test-probe-qhash.sh"
: >"$VIOL"
if ! scan "$PROBE_DIR/unit" >"$VIOL"; then
    fail "scan died on the quoted-hash probe -- #727 self-probe unreliable (#519)"
fi
if grep -q "test-probe-qhash.sh|3|mutate|/home/some-user-max-mustermann/probe-hash" "$VIOL"; then
    pass "self-probe: a quoted # keeps the later rm segment visible (#727)"
else
    fail "self-probe: a quoted # must not truncate the operand view (#727)"
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
# #519 (from #516 a A2): same restructure as scan() -- the per-file
# grep rc is captured directly (rc 1 = no suffix match, the normal
# clean case; rc >= 2 = detector death, loud); the || true call sites
# read green over partial or empty output before.
sfx_scan() {
    _sx_dir="$1"
    _sx_list="$(mktemp)"
    # #596: prune basename dumps from the traversal — e2e run evidence
    # (tests/e2e/dumps/<label>-<ts>/, the container's whole /tmp via
    # docker cp) holds dumped .sh files of exactly the name class this
    # walk collects. The walk has READ the dumps on rootless/local
    # checkouts all along (opencode-owned, world-readable here) — what
    # kept check 3 green was content: no dumped .sh carried an
    # unguarded rm-suffix shape yet (#628 a M2), not the container
    # ownership that shields rootful-CI hosts. The find filters below
    # select what is PRINTED, not what is descended. Basename-scoped at
    # any depth, mirroring pin10 lane c's --exclude-dir=dumps
    # (#587, PR #593): living e2e scripts stay in the walk.
    find "$_sx_dir" -name dumps -prune -o \
        \( -name "${2:-test-*.sh}" -o -path '*/lib/*.sh' \) ! -name 'test-sandbox-policy.sh' -print |
        sort >"$_sx_list"
    set --
    while IFS= read -r _sx_f; do
        set -- "$@" "$_sx_f"
    done <"$_sx_list"
    command rm -f "$_sx_list"
    if [ "$#" -eq 0 ]; then
        echo "sandbox-policy tests: sfx_scan found no suites in '$_sx_dir' -- check 3 output unreliable (#519)" >&2
        return 1
    fi
    _sx_bad=0
    for _sx_f; do
        _sx_rc=0
        _sx_out="$(grep -HnE 'rm( -[A-Za-z]+| "[^"]*"| [^";&| ]+)*( "\$[A-Za-z_][A-Za-z0-9_]*/| "\$\{[A-Za-z_][A-Za-z0-9_]*\}/| "\$[A-Za-z_][A-Za-z0-9_]*"/| \$[A-Za-z_][A-Za-z0-9_]*/| "\$[A-Za-z_][A-Za-z0-9_]*\.| "\$\{[A-Za-z_][A-Za-z0-9_]*\}\.| \$[A-Za-z_][A-Za-z0-9_]*\.)' "$_sx_f" 2>/dev/null)" || _sx_rc=$?
        if [ "$_sx_rc" -gt 1 ]; then
            echo "sandbox-policy tests: sfx_scan died on '$_sx_f' (rc=$_sx_rc) -- check 3 output unreliable (#519)" >&2
            _sx_bad=1
            continue
        fi
        if [ -n "$_sx_out" ]; then
            printf '%s\n' "$_sx_out" | grep -Ev ':[0-9]+:[[:space:]]*#' || true
        fi
    done
    [ "$_sx_bad" -eq 0 ]
}
: >"$VIOL"
if ! sfx_scan tests/unit >"$VIOL"; then
    fail "sfx_scan died on tests/unit -- check 3 cannot run (#519)"
fi
if ! sfx_scan tests/e2e '*.sh' >>"$VIOL"; then
    fail "sfx_scan died on tests/e2e -- check 3 cannot run (#519)"
fi
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
if ! sfx_scan "$PROBE_DIR/unit" >"$VIOL"; then
    fail "sfx_scan died on the probe scan -- check 3 self-probes unreliable (#519)"
fi
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

# self-probe (#596): dumps run evidence is pruned from the tests/e2e
# walk. A readable dumps/<label>-<ts>/ carrying a dumped .sh with the
# offending shape must NOT land in the violation list, while a living
# e2e script with the SAME shape still must — the pair discriminates
# the prune from both directions (a scan death fails loud above).
mkdir -p "$PROBE_DIR/e2e/dumps/run-20260101-000000"
printf '#!/bin/sh\n# probe: living e2e script, unguarded suffix -- must be caught\nrm -f "$PX/live-evil"\n' \
    >"$PROBE_DIR/e2e/section-probe.sh"
printf '#!/bin/sh\n# probe: dumped copy, same shape -- must NOT be caught (#596)\nrm -f "$PX/dumped-evil"\n' \
    >"$PROBE_DIR/e2e/dumps/run-20260101-000000/dumped.sh"
: >"$VIOL"
if ! sfx_scan "$PROBE_DIR/e2e" '*.sh' >"$VIOL"; then
    fail "sfx_scan died on the e2e dumps probe scan -- check 3 self-probes unreliable (#519)"
fi
if grep -q 'section-probe.sh' "$VIOL" && grep -q 'PX/live-evil' "$VIOL" &&
    ! grep -q 'dumps/run-20260101' "$VIOL"; then
    pass "self-probe: dumps run evidence pruned from the walk, living e2e scripts kept (#596)"
else
    fail "self-probe: check 3 must scan living e2e scripts but prune dumps run evidence (#596)"
    grep -E 'section-probe|dumps/run' "$VIOL" || true
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
# cells. (Check 4b, further below: work_* call + local trap in one
# suite = mix — the local trap disarms the harness work registry, #395.) Receiver detection: a live assignment whose value starts with
# an UNESCAPED $(mktemp (comment lines skipped), an optional `command `
# prefix included ($(command mktemp …)); heredoc-embedded child
# scripts carry \$ ( — escaped, excluded by design: child scripts own
# their cleanup. The function form (trap _cleanup EXIT INT TERM) is
# accepted: the arms live on the trap line, the rm lives in the
# function. Line-based like check 3: a trap statement split across a
# backslash continuation hides its arms from the scan — keep the arms
# on the trap's physical line (the self-probes pin the shape). Arms are
# the TOKENS AFTER the action word (shlex, since #498 — see the
# detector note below), so action text (kill -TERM, an in-action
# comment naming the arms) and trailing-comment arm words cannot
# satisfy the arm check — the four #287 defect rounds (b S1/C2, c S1,
# d D1) were exactly this quote-tracking class in the former awk walk.
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
# The detector itself lives in tests/unit/lib/trap_detect.py since
# #498 -- the shlex port of this check's awk program: the trap-arm
# analyzer reads arms from shlex tokens (rider_detect.tokenize with the
# commenter pass first), the receiver regex and the own-call view
# (sq-blanked line, escaped \$( mangled, work_* call shapes) are
# faithful ports -- their latent-shape documentation above carries
# over unchanged. This wrapper is the fail-loud seam: a detector death
# (unreadable file, an EMPTY scan set -- a vanished start point or a
# TOTAL find error, which both yield an empty file list -- or a python
# start failure) returns nonzero with the guard message on stderr, and
# the callers below fail the suite instead of scanning green over
# missing rows (the #496 round-a B1 vacuity class; the guard arm after
# the probe scans executes the death path). Scope note (a A4, #516): a
# PARTIAL find failure (unreadable subtree mid-traversal) yields a
# reduced list and a silent rc-0 scan -- pre-existing semantics, the
# old find|sort|while pipeline behaved identically.
trap_scan() {
    _ts_list="$(mktemp)"
    find "$1" \( -name "${2:-test-*.sh}" -o -path '*/lib/*.sh' \) ! -name 'test-sandbox-policy.sh' |
        sort >"$_ts_list"
    set --
    while IFS= read -r _ts_f; do
        set -- "$@" "$_ts_f"
    done <"$_ts_list"
    python3 "$REPO_ROOT/tests/unit/lib/trap_detect.py" --batch "$@" || {
        echo "sandbox-policy tests: trap_detect failed (rc=$?) -- trap floor output unreliable (#498)" >&2
        command rm -f "$_ts_list"
        return 1
    }
    command rm -f "$_ts_list"
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
if ! trap_scan tests/unit >"$VIOL"; then
    fail "trap_scan died on tests/unit -- check 4 floor cannot run (#498)"
fi
if [ -s "$VIOL" ]; then
    while IFS='|' read -r tf tk; do
        case "$tk" in
            notrap) fail "$tf has mktemp receiver(s) but no trap statement (#283: register one, arms EXIT INT TERM)" ;;
            arms*) fail "$tf trap statement missing arms:${tk#arms } (#283: every trap needs EXIT INT TERM)" ;;
            mixtrap) fail "$tf mixes work_* calls with a local trap (#395: the local trap disarms the harness registry -- drop one)" ;;
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
if ! trap_scan "$PROBE_DIR/unit" >"$VIOL"; then
    fail "trap_scan died on the probe scan -- check 4 self-probes unreliable (#498)"
fi
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
if ! trap_scan "$PROBE_DIR/unit" >"$VIOL"; then
    fail "trap_scan died on the probe scan -- check 4 self-probes unreliable (#498)"
fi
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
# work_* call + local trap must be caught (#395 check 4b): the local
# trap statement replaces the harness registry's central trap -- every
# registered receiver leaks (the #283 class re-entered from the other
# side). The work-only probe passes clean: no literal mktemp receiver
# (work_new lives in the harness), the registry owns the cleanup.
printf '#!/bin/sh\n# probe: work_new call + local trap must be caught (check 4b)\nW="$(work_new)"\ntrap "rm -rf \\"$W\\"" EXIT INT TERM\n' \
    >"$PROBE_DIR/unit/test-probe-trap-mix.sh"
printf '#!/bin/sh\n# probe: work_new without a local trap passes (registry owns cleanup)\nW="$(work_new)"\n' \
    >"$PROBE_DIR/unit/test-probe-work-only.sh"
printf '#!/bin/sh\n# probe: a trailing comment naming work_new must not count as a call\nW=1 # migrated via work_new in #395\ntrap "rm -rf \\"$W\\"" EXIT INT TERM\n' \
    >"$PROBE_DIR/unit/test-probe-work-cmt.sh"
printf '#!/bin/sh\n# probe: the function definition form is not a call\nwork_new() { :; }\n' \
    >"$PROBE_DIR/unit/test-probe-work-def.sh"
# escaped heredoc/dq child code must not count as the suite's call
# (round A C1): both the receiver check's documented \$ ( shape and its
# dq variant, alongside a local trap -- the pre-C1 scanner flagged this
# mix spuriously.
printf '#!/bin/sh\n# probe: escaped child code is not the parent call (C1)\n_h = \\$(work_new)\nW="\\$(work_new_file)"\ntrap "rm -rf \\"$H\\" \\"$W\\"" EXIT INT TERM\n' \
    >"$PROBE_DIR/unit/test-probe-work-esc.sh"
: >"$VIOL"
if ! trap_scan "$PROBE_DIR/unit" >"$VIOL"; then
    fail "trap_scan died on the probe scan -- check 4 self-probes unreliable (#498)"
fi
if grep -q 'test-probe-trap-mix.sh|mixtrap' "$VIOL"; then
    pass "self-probe: work_new + local trap mix is caught"
else
    fail "self-probe: work_new + local trap must be caught (check 4b)"
fi
if grep -qE 'test-probe-(work-only|work-cmt|work-def|work-esc)\.sh\|' "$VIOL"; then
    fail "self-probe: work-only, comment-only, definition and escaped-child forms must pass clean"
    grep -E 'test-probe-(work-only|work-cmt|work-def|work-esc)' "$VIOL" || true
else
    pass "self-probe: work-only, comment-only, definition and escaped-child forms pass clean"
fi
# detector-death guard arm (#498, the #496 a B1/b D3 shape): one
# executed death through the wrapper -- a scan target whose file list
# comes back empty (vanished dir, find error) reaches the detector with
# no operands; the wrapper must fail loud with the guard message on
# stderr and a nonzero rc, observed the way a failing sweep observes it
# (stderr captured, stdout discarded). Without the guard an empty or
# dead scan writes zero rows and every check-4 verdict below greps an
# empty file green.
_tsg_rc=0
_tsg_err="$( (trap_scan "$PROBE_DIR/no-such-dir-$$") 2>&1 >/dev/null)" || _tsg_rc=$?
if [ "$_tsg_rc" -ne 0 ] && printf '%s\n' "$_tsg_err" | grep -q 'trap floor output unreliable'; then
    pass "self-probe: a trap_detect death fails loud (guard message + rc, #498)"
else
    fail "self-probe: a trap_scan death must fail loud with the guard message (#498)"
fi
# detector-death guard arms for scan/sfx_scan (#519, the a A2
# residual): one executed death each -- a scratch scan set holding an
# unreadable suite file; the wrappers must fail loud (guard message on
# stderr + nonzero rc) instead of letting the callers read green over
# the missing rows (the old || true call sites did).
# The greps are leg-specific (#522, from #520 review a B1): both guard
# messages share their "output unreliable" suffix with the empty-set
# message, so the old suffix greps stayed green when a one-token
# refactor rerouted the death scenario into the empty guard (the #520
# review-a B-axis ran exactly that -readable patch as an executed
# false-pass proof -- PR #520 timeline, finding a B1). The death arms
# grep 'died on', the empty arms 'found no suites' -- one phrase per
# leg, the discrimination convention the wave's sibling suites follow
# with their own pairs (test-docs.sh: 'scope scan died' / 'empty scope
# scan'; test-rules-meta.sh: 'lane b scan died' / 'lane b scan empty').
# Root-context caveat (#520 a B4): these deaths are DAC-enforced
# (chmod 000) -- as root awk/grep read through and these arms
# false-red; no root invocation path exists for this suite today (CI
# runner user, no e2e/kit-script call site; the vanished-dir arms
# elsewhere in this suite are root-safe).
_dg_dir="$(mktemp -d)"
printf '#!/bin/sh\n# probe: unreadable file kills the scan detectors\n_dg="$(mktemp -d)"\n' \
    >"$_dg_dir/test-probe-dying.sh"
chmod 000 "$_dg_dir/test-probe-dying.sh"
_dg_rc=0
_dg_err="$( (scan "$_dg_dir") 2>&1 >/dev/null)" || _dg_rc=$?
if [ "$_dg_rc" -ne 0 ] && printf '%s\n' "$_dg_err" | grep -q 'scan died on'; then
    pass "self-probe: a scan detector death fails loud (#519)"
else
    fail "self-probe: a scan death must fail loud with the guard message (#519)"
fi
_dg_rc=0
_dg_err="$( (sfx_scan "$_dg_dir") 2>&1 >/dev/null)" || _dg_rc=$?
chmod 755 "$_dg_dir/test-probe-dying.sh"
command rm -rf "${_dg_dir:?}"
if [ "$_dg_rc" -ne 0 ] && printf '%s\n' "$_dg_err" | grep -q 'sfx_scan died on'; then
    pass "self-probe: an sfx_scan detector death fails loud (#519)"
else
    fail "self-probe: an sfx_scan death must fail loud with the guard message (#519)"
fi
# empty-scan-set legs: a vanished scan dir must fail loud too (zero
# scanned suites must never read as a clean verdict)
_dg_rc=0
_dg_err="$( (scan "$PROBE_DIR/no-such-dir-$$") 2>&1 >/dev/null)" || _dg_rc=$?
if [ "$_dg_rc" -ne 0 ] && printf '%s\n' "$_dg_err" | grep -q 'found no suites'; then
    pass "self-probe: an empty scan set fails loud (#519)"
else
    fail "self-probe: an empty scan set must fail loud with the guard message (#519)"
fi
_dg_rc=0
_dg_err="$( (sfx_scan "$PROBE_DIR/no-such-dir-$$") 2>&1 >/dev/null)" || _dg_rc=$?
if [ "$_dg_rc" -ne 0 ] && printf '%s\n' "$_dg_err" | grep -q 'found no suites'; then
    pass "self-probe: an empty sfx_scan set fails loud (#519)"
else
    fail "self-probe: an empty sfx_scan set must fail loud with the guard message (#519)"
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
