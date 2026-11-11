#!/bin/sh
# test-rider-lint.sh -- invariant suite (#460): the comment-strip
# rider idiom lives in exactly one place.
#
# Rule 1 (gating): no file-operand inline strip rider in
# tests/unit/test-*.sh. Every `sed 's/^[[:space:]]*#.*$//' <operand>`
# (or its double-quoted sh -c variant) re-introduces the pre-#460
# idiom that accumulated 223 inline sites before centralization; the
# canonical rider is live_src / check_live (tests/unit/lib/harness.sh,
# conventions.md "Source-counting pins"). Sanctioned non-live_src
# shapes, not flagged:
#   - stdin/block strips: `... | sed 'STRIP'` with NO file operand --
#     stripping an extracted block (extract_func output) rides inline;
#     live_src is files-only by design
#   - full-comment lines (documentation mentions)
#   - lib/harness.sh (the helper itself) and this suite's own detector
#     definitions (self-allowlist, the same exception every invariant
#     suite grants its own machinery)
#
# Rule 2 (gating since the #460 census wave, was grandfathered until
# then): the strict single-file presence shape must be check_live --
# `check "desc" grep ... "$SRCVAR"` where $SRCVAR resolves to a
# shipped or repo-internal source. Registration is derived, not
# listed: a suite variable is a registered source-path variable when
# its value references the repo/shipped tree ($REPO/, $FILES/,
# $SCRIPT_DIR/../../, $SCRIPT_DIR/../sh/, ../e2e/, .github/) directly
# or through another registered variable (PLUGIN="$TUIDIR/x" with
# TUIDIR="$REPO/files/..." registers PLUGIN). Slash-comment sources
# (values ending .jsonc/.json/.ts/.tsx) register but are EXEMPT: the
# rider strips `#` lines only, so riding them is an identity no-op
# until the deferred JSONC `//` decision (#460 rules of engagement)
# lands in live_src. Exempt otherwise: negated bodies (`! grep` --
# absence pins stay un-ridden by design) and non-source operands
# (rendered fixtures, stub logs). Boundary (reviewer scope): a check
# whose command carries multiple grep legs joined by && -- whether
# direct or inside an sh -c child -- is a compound shape; the census
# converted the inventory's compound sites to parent-if blocks with
# live_src pipes; new compound shapes stay the reviewer's call.
#
# Rule 3 (measured 2026-11-11, deliberately NOT gating): the sh -c
# indirection of the same strict shape (`check "desc" sh -c 'grep ...
# \"$1\"' _ "$SRCVAR"`, single positional file, presence-only) -- 336
# sites tree-wide before the census wave, 304 after it converted the
# inventory suites' sites (bypass-guard, container-backend, kit-cli
# fetch twins, mkcert-reuse, staged-write, tui-mode's uninstall pin,
# update-flags' #164 twins). The residual sits in suites the round-a
# census never named (ddev-as-opencode, ddev-hosts, ddev-migrate,
# wsl-exposure, ui, and update-flags' openchamber/#163 blocks). Same
# survivor trap, same conversion path (check_live for single legs,
# parent-if + live_src pipes for multi-leg). Recorded as a ratchet:
# the count must only go DOWN; the wave that drives it to zero flips
# it to a gating zero-count (the same path rule 2 took).
#
# Discrimination arms (scratch fixtures, run BEFORE the tree sweep):
#   - a planted single-quoted file-operand rider -> flagged
#   - a planted double-quoted rider (both $ variants) -> flagged
#   - a stdin-pipe strip, a full-comment rider line, a live_src call
#     -> not flagged
#   - a planted direct strict check-grep over a registered var ->
#     flagged (rule 2)
#   - the same over a fixture var, negated, or a slash-family var
#     -> not flagged (rule 2 exemptions)
#   - a chained-var registration flags (rule 2 transitivity)
# Sabotage (committed tree, then restore + re-run green): delete the
# hit arm from a detector -> the planted-rider arms go red while
# the sweep passes vacuously only if the arms are gone too.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/harness.sh"

# Built from pieces so this suite's own source avoids contiguous
# rider bytes where it can: p1 is fully piece-built; p2/p3 carry
# their full prefixes as literals -- both are covered by the
# self-allowlist below, which skips this whole file by exact
# basename (the trust boundary is the file, tighter scoping would
# sweep detector lines).
_rh_core='s/^[[:space:]]*#.*'
_rh_p1="sed '"${_rh_core}'$//'"' "
_rh_p2='sed "s/^[[:space:]]*#.*\$//" '
_rh_p3='sed "s/^[[:space:]]*#.*$//" '

# _rider_hits <file>: prints "<file>:<NR>: <line>" for every file-operand
# inline rider. Full-comment lines are skipped; an operand start is
# any next byte except the command terminators and EOL -- the
# stdin/block-strip shapes, including output redirection into a
# file (round a C2: `>` and backtick join the terminator class).
# awk -v processes backslash escapes in assigned values, so
# backslashes are doubled on the way in (the \$ byte of the sh -c
# form survives as \$). KNOWN BOUNDARY (round a C3): the detector
# is byte-form-exact -- a TAB after the expression, `sed -e`/
# `--expression` forms, a `g` suffix, or an operand on a
# continuation line escape rule 1; conventions.md scopes the
# finding claim accordingly.
_rh_av() { printf '%s' "$1" | sed 's/\\/\\\\/g'; }
_rider_hits() {
    awk -v p1="$(_rh_av "$_rh_p1")" -v p2="$(_rh_av "$_rh_p2")" \
        -v p3="$(_rh_av "$_rh_p3")" '
        /^[[:space:]]*#/ { next }
        {
            hit = 0
            if (i = index($0, p1)) {
                c = substr($0, i + length(p1), 1)
                if (c != "" && c !~ /[|);&>`]/) hit = 1
            }
            if (!hit && (i = index($0, p2))) {
                c = substr($0, i + length(p2), 1)
                if (c != "" && c !~ /[|);&>`]/) hit = 1
            }
            if (!hit && (i = index($0, p3))) {
                c = substr($0, i + length(p3), 1)
                if (c != "" && c !~ /[|);&>`]/) hit = 1
            }
            if (hit) printf "%s:%d: %s\n", FILENAME, NR, $0
        }
    ' "$1"
}

# _rule2_detect <file>: prints "<file>:<start-line>: DIRECT <stmt>"
# for every strict single-file direct presence shape over a
# registered source variable, and "... SHC1 <stmt>" for the sh -c
# indirection presence shape (rule 3, counted not gated). Two-phase
# in-memory pass: slurp, join statements (backslash, trailing
# && / || / | continuations), collect assignments, derive the
# registered source variables transitively, then flag.
_rule2_detect() {
    awk '
        { lines[NR] = $0 }
        END {
            total = NR
            n = 0; i = 1
            while (i <= total) {
                ln = lines[i]
                if (ln ~ /^[[:space:]]*#/) { i++; continue }
                stmt = ln; start = i
                while (stmt ~ /\\$/ || stmt ~ /&&[[:space:]]*$/ || stmt ~ /\|\|[[:space:]]*$/ || stmt ~ /\|[[:space:]]*$/) {
                    if (stmt ~ /\\$/) sub(/\\$/, "", stmt)
                    else if (stmt ~ /&&[[:space:]]*$/) sub(/[[:space:]]*$/, "", stmt)
                    else if (stmt ~ /\|\|[[:space:]]*$/) sub(/[[:space:]]*$/, "", stmt)
                    # a trailing single pipe STAYS -- the next line joins
                    # after it (a | b must not reconstruct as "a b")
                    i++
                    if (i > total) break
                    nxt = lines[i]
                    sub(/^[[:space:]]+/, "", nxt)
                    if (nxt ~ /^[[:space:]]*#/) break
                    stmt = stmt nxt
                }
                i++
                n++; S[n] = stmt; L[n] = start
            }
            nv = 0
            for (k = 1; k <= n; k++) {
                if (S[k] ~ /^[A-Za-z_][A-Za-z_0-9]*=/) {
                    v = S[k]; sub(/=.*/, "", v)
                    r = S[k]; sub(/^[^=]*=/, "", r)
                    nv++; vname[nv] = v; vval[v] = r
                }
            }
            for (round = 1; round <= 4; round++) {
                changed = 0
                for (k = 1; k <= nv; k++) {
                    v = vname[k]
                    if (marked[v]) continue
                    r = vval[v]
                    own_slash = (r ~ /\.(jsonc|json|tsx|ts)("|[[:space:]]|$)/) ? 1 : 0
                    if (r ~ /\$REPO\/|\$FILES\/|\.github\/|\.\.\/e2e\/|\$SCRIPT_DIR\/\.\.\/\.\.|\$SCRIPT_DIR\/\.\.\/sh\//) {
                        marked[v] = 1; slashy[v] = own_slash; changed++
                    } else if (match(r, /\$[A-Za-z_][A-Za-z_0-9]*/)) {
                        ref = substr(r, RSTART + 1, RLENGTH - 1)
                        if (marked[ref]) {
                            marked[v] = 1
                            # own extension WINS over inheritance ("$TS/../sh/y.sh"
                            # is a shell source even though $TS is a .tsx);
                            # extension-less values inherit the parent class
                            if (own_slash) slashy[v] = 1
                            else if (r ~ /\.[a-z0-9]+("|[[:space:]]|$)/) slashy[v] = 0
                            else slashy[v] = slashy[ref]
                            changed++
                        }
                    }
                }
                if (!changed) break
            }
            for (k = 1; k <= n; k++) {
                stmt = S[k]
                neg = (stmt ~ /! *grep/)
                # annotation exemption: an in-place `rider-inversion`
                # marker names the sanctioned bare shape (conventions.md
                # "Source-counting pins": a comment-literal presence pin)
                inv = (stmt ~ /#[[:space:]]*rider-inversion/)
                if (stmt ~ /^check "[^"]*"[[:space:]]+grep / && !neg && !inv) {
                    if (has_reg_operand(stmt)) print "DIRECT\t" L[k] "\t" shorten(stmt)
                }
                if (stmt ~ /^check "[^"]*"[[:space:]]+sh -c / && !neg && stmt ~ /_ "\$[A-Za-z_0-9]+"/ &&
                    stmt !~ /printf "%s" "\$[0-9]"/) {
                    p1 = index(stmt, "\"$1\"") > 0 || index(stmt, "\\\"\\$1\\\"") > 0
                    p2 = index(stmt, "\"$2\"") > 0 || index(stmt, "\\\"\\$2\\\"") > 0
                    p3 = index(stmt, "\"$3\"") > 0 || index(stmt, "\\\"\\$3\\\"") > 0
                    cnt = (p1 ? 1 : 0) + (p2 ? 1 : 0) + (p3 ? 1 : 0)
                    if (cnt == 1 && has_reg_bind(stmt)) print "SHC1\t" L[k] "\t" shorten(stmt)
                }
            }
        }
        # Static regex operands ONLY: a regex constant used as an
        # expression (a ternary branch) evaluates as $0 ~ /re/ -- 0 or 1
        # -- and match() then hunts the digit "1" forever while the
        # cursor keeps the matched byte (the spin this detector shipped
        # with once; killed at 100% CPU four minutes in).
        func has_reg_operand(s) {
            while (match(s, /"\$[A-Za-z_][A-Za-z_0-9]*(\/[^"]*)?"/)) {
                name = substr(s, RSTART + 2, RLENGTH - 3)
                sub(/\/.*/, "", name)
                if (marked[name] && !slashy[name]) return 1
                s = substr(s, RSTART + RLENGTH)
            }
            return 0
        }
        func has_reg_bind(s) {
            while (match(s, /"\$[A-Za-z_][A-Za-z_0-9]*"/)) {
                name = substr(s, RSTART + 2, RLENGTH - 3)
                if (marked[name] && !slashy[name]) return 1
                s = substr(s, RSTART + RLENGTH)
            }
            return 0
        }
        func shorten(s) { sub(/^[[:space:]]+/, "", s); return substr(s, 1, 160) }
    ' "$1"
}

echo ""
echo "Rider Lint (comment-strip idiom, issue #460)"
echo "============================================"
echo ""

# --- 1. discrimination arms (scratch fixtures) ---------------------------------
_cell="$(work_new)"
_rh_oper='$F'
printf '%s\n' "if sed '${_rh_core}\$//' \"${_rh_oper}\" | grep -q x; then :; fi" \
    >"$_cell/single.sh"
printf '%s\n' "sh -c 'sed \"s/^[[:space:]]*#.*\\\$//\" \"\$1\" | grep -qF p' _ \"\$F\"" \
    >"$_cell/doublesh.sh"
printf '%s\n' "sh -c 'sed \"s/^[[:space:]]*#.*\$//\" \"\$1\" | grep -qF p' _ \"\$F\"" \
    >"$_cell/dollar.sh"
printf '%s\n' "_blk=\$(printf '%s\n' \"\$B\" | sed '${_rh_core}\$//')" \
    >"$_cell/stdin.sh"
printf '%s\n' "_blk=\$(printf '%s\n' \"\$B\" | sed '${_rh_core}\$//' > \"\$cell/o.txt\")" \
    >"$_cell/stdinredir.sh"
printf '%s\n' "# doc: sed '${_rh_core}\$//' \"\$F\" | grep -q x" \
    >"$_cell/comment.sh"
printf '%s\n' 'live_src "$F" | grep -q x' >"$_cell/livesrc.sh"

_n="$(_rider_hits "$_cell/single.sh" | wc -l | tr -d ' ')"
check "planted single-quoted rider flags (1 hit)" test "$_n" = 1
_n="$(_rider_hits "$_cell/doublesh.sh" | wc -l | tr -d ' ')"
check "planted double-quoted \\\$ rider flags (1 hit)" test "$_n" = 1
_n="$(_rider_hits "$_cell/dollar.sh" | wc -l | tr -d ' ')"
check "planted double-quoted \$ rider flags (1 hit)" test "$_n" = 1
_n="$(_rider_hits "$_cell/stdin.sh" | wc -l | tr -d ' ')"
check "stdin/block strip stays unflagged" test "$_n" = 0
_n="$(_rider_hits "$_cell/stdinredir.sh" | wc -l | tr -d ' ')"
check "stdin strip with output redirect stays unflagged (a C2)" test "$_n" = 0
_n="$(_rider_hits "$_cell/comment.sh" | wc -l | tr -d ' ')"
check "full-comment rider mention stays unflagged" test "$_n" = 0
_n="$(_rider_hits "$_cell/livesrc.sh" | wc -l | tr -d ' ')"
check "a live_src call stays unflagged" test "$_n" = 0

# --- 1b. rule-2 discrimination arms --------------------------------------------
# A synthetic mini-suite: SRC resolves into the repo tree, FIX into a
# work dir, TS into the tree with a slash-comment extension, CHK chains
# off SRC. Each planted shape exercises one registration/exemption rule.
printf '%s\n' \
    'SRC="$REPO/files/opencode-permissions-kit-lib/sh/x.sh"' \
    'FIX="$WORK/fixture.log"' \
    'TS="$REPO/files/opencode-permissions-kit-lib/tui/x.tsx"' \
    'CHK="$TS/../sh/y.sh"' \
    'check "direct over registered" grep -qF pat "$SRC"' \
    'check "direct over fixture stays" grep -qF pat "$FIX"' \
    'check "direct inversion-annotated stays" grep -qF pat "$SRC" # rider-inversion (comment-literal pin)' \
    'check "direct negated stays" grep -qF pat "$SRC" && ! grep -qF nope "$SRC"' \
    'check "direct over slash-family stays" grep -qF pat "$TS"' \
    'check "shc over registered" sh -c "grep -qF pat \"\$1\"" _ "$SRC"' \
    'check "direct chained var flags" grep -qF pat "$CHK"' \
    'check_live "ridden stays" "$SRC" -qF pat' \
    >"$_cell/rule2.sh"

_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c DIRECT)"
check "planted direct strict shapes flag (2 hits: direct + chained)" test "$_n" = 2
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'direct over registered')"
check "the direct-over-registered arm is one of them" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'inversion-annotated')"
check "inversion-annotated site stays unflagged (comment-literal pin)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'fixture')"
check "direct over a fixture var stays unflagged" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'negated')"
check "negated direct body stays unflagged (absence legs)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'slash-family')"
check "direct over slash-family source stays unflagged (// deferred)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c 'chained')"
check "chained registration flags (transitive derivation)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c SHC1)"
check "planted sh -c indirection shape counts (rule 3)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c 'ridden')"
check "a check_live call stays unflagged" test "$_n" = 0

# --- 2. tree sweep --------------------------------------------------------------
# Every suite except this one (self-allowlist, header). lib/ is not
# matched by the glob.
_total=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _hits="$(_rider_hits "$_f")"
    if [ -n "$_hits" ]; then
        fail "inline file-operand rider(s) in $(basename "$_f") -- use live_src"
        echo "$_hits" | sed 's/^/        /'
        _total=$((_total + 1))
    fi
done
if [ "$_total" -eq 0 ]; then
    pass "no inline file-operand riders in tests/unit (rule 1, #460)"
fi

# --- 3. rule-2 tree sweep (gating): strict direct shape -------------------------
_total=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _hits="$(_rule2_detect "$_f" | grep DIRECT)"
    if [ -n "$_hits" ]; then
        fail "strict direct check-grep over a registered source var in $(basename "$_f") -- use check_live (rule 2, #460)"
        echo "$_hits" | sed 's/^/        /'
        _total=$((_total + 1))
    fi
done
if [ "$_total" -eq 0 ]; then
    pass "no strict direct check-greps over source vars in tests/unit (rule 2, #460)"
fi

# --- 4. rule-3 ratchet (measured, NOT gating): sh -c single-file presence -------
_r3=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _n="$(_rule2_detect "$_f" | grep -c SHC1)"
    _r3=$((_r3 + _n))
done
# Ratchet baseline: the census wave (#460 PR 2) converted the
# inventory suites' sh -c sites (336 -> 304); the residual sits in the
# suites the round-a inventory never named (ddev-as-opencode,
# ddev-hosts, ddev-migrate, wsl-exposure, ui). Only downward motion is
# legal; the wave that reaches zero flips this ratchet into a gating
# zero-count.
check "sh -c single-file presence ratchet (rule 3, census residual: $_r3)" test "$_r3" -le 304

suite_done "rider lint tests"
