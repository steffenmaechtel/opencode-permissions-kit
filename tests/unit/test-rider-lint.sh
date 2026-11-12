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
# lands in live_src. Markdown sources (values ending .md) are EXEMPT
# for the OPPOSITE reason -- decided, not deferred (#472): a
# `#`-initial line is a heading there, so the strip deletes live
# content; the canonical docs-pin shape is the raw un-ridden grep
# (conventions.md "Source-counting pins"). Exempt otherwise:
# non-source operands (rendered
# fixtures, stub logs). Negation/absence: an absence leg (`! grep`,
# if-found-then-fail) stays un-ridden by design, and since the review-a
# fix (#468) the exemption is LEG-scoped: the detector splits each
# joined statement quote-aware into legs (on ; | && -- a single & is
# literal, `2>&1` never splits), a check carried on a &&-continuation
# leg is gated like a statement-initial one, and a presence leg beside
# an absence leg is gated like a lone presence pin. Boundary (reviewer
# scope): compound multi-leg shapes inside if-forms (not check-form)
# stay the reviewer's call; the census converted the inventory's
# compound sites to parent-if blocks with live_src pipes.
#
# Rule 3 (gating since the #470 wave, was a down-only ratchet until
# then): the sh -c indirection of the same strict shape (`check "desc"
# sh -c 'grep ... \"$1\"' _ "$SRCVAR"`, single positional file,
# presence-only) must not exist -- 336 sites tree-wide before the #460
# census wave, 304 after it. The #470 wave converted the residual to
# the canonical shapes (check_live for single-leg presence greps,
# parent-if + live_src pipes for multi-leg and extraction pipelines)
# or to their honest non-sh -c equivalents where live_src would change
# semantics: behavioral probes (. source / sh execution / make dry-run)
# unwrap to parent-if probes with the operands substituted (a
# commented-out construct changes the probe's behavior, so the survivor
# trap does not apply); pins over CAPTURED OUTPUT (sh -c "$(…)"
# captures, printf-stdin payloads -- what the process PRINTED carries no
# comment-line structure; the detector's transitive registration
# over-approximates these) unwrap raw, un-ridden -- this exemption does
# NOT cover SOURCE-TEXT captures: an unstripped `sed -n` span or
# extract_func block carries comment lines verbatim, so a raw pin over
# one still matches a commented-out construct (ride live_src, or strip
# the block at capture per the conventions.md block-strip sanction);
# absence legs stay raw per conventions.md. Recorded inversions (the
# #459 a B3 mechanism, registered in conventions.md + the tripwire
# below): TWO marker-mention sites -- the container-backend
# comment-literal pin and test-ddev-as-opencode's browser-arm pin (its
# literal is itself a full-line comment) -- plus the marker-less `#428
# disposition` inversion (test-install-core.sh, annotated in-place).
# Zero is the contract WITHIN the detector's grammar: single
# positional file, presence-only, var-bound (`_ "$VAR"`); sibling
# spellings escape it -- multi-operand payloads, literal-path bindings,
# indirect `$(cd ...)/path`-spelling bindings the registration regex
# cannot see, `;`-statement payloads (the sh -c leg gate never matches
# a check-prefix after a `;` split), numeric-gate second operands
# (lifting the positional count to 2), if-form (non check-form) shapes
# -- and convert on sight like the counted shape did.
#
# Rule 4 (gating since #469, born gated): the sh -c indirection of
# the strict single-target ABSENCE shape (`check "desc" sh -c
# '! grep ... "$1"' _ "$SRCVAR"`, single positional file, one absence
# leg) must be check_absent -- the harness's named raw fail-on-found
# sugar (tests/unit/lib/harness.sh, #469). The census at adoption: 27
# sites converted (12 grep_absent call rows in test-container-backend
# -- the suite-local name that proved the class wanted one; its 13th
# grep_absent line was the removed definition -- plus 15 single-
# target sh -c negations). The grammar mirrors rule 3's binds
# (registration-bound `_ "$VAR"`, single positional, printf-exempt)
# and adds ONE conjunct rule 3 has no counterpart for: the payload
# itself is split quote-aware and must be a SINGLE leg starting
# `! grep` -- rule 3 deliberately flags compound presence payloads,
# rule 4's absence analogue must stay out. Escapes and their
# dispositions: multi-file payloads (`! grep "$1" && ! grep "$2"`),
# compound legs (absence beside presence or a numeric gate),
# in-payload pipes, literal-path and log/fixture binds the
# registration cannot see, if-form spellings -- all stay the
# documented raw shapes (conventions.md "Source-counting pins",
# absence paragraph) and convert on sight like the counted shape
# did. Spliced-quote payloads escape ENTIRELY: any byte other than
# whitespace directly after the closing quote marks a quote
# CONCATENATION (the sq-dq-sq idiom, the sq-sq idiom, the backslash
# spelling -- rounds a X2 + b B1) whose later segments the
# first-segment parser cannot see, and a false flag there demanded
# an impossible conversion; such shapes ride convert-on-sight;
# the payload anchor is the arm anchor (`check "desc" <spaces>
# sh -c `), immune to a desc carrying those bytes (round a X1).
# check_absent itself is never flagged (it IS the name).
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
#   - a planted sh -c indirection shape counts (rule 3) -- and the
#     tree sweep at zero means a NEW one fails loud (gating since #470)
#   - a planted strict sh -c absence shape flags (rule 4), including
#     one whose DESCRIPTION carries the bytes "sh -c " (the payload
#     anchor is the arm anchor, round a X1) -- a single-file compound
#     absence payload and a spliced-quote compound stay out (payload
#     single-leg conjunct / splice escape, round a X2/X5)
#   - a check_absent call stays unflagged
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
    # sq carries the single-quote byte in from the shell layer: the awk
    # program is a single-quoted shell string, so the byte `'` must not
    # appear inside it (split_legs needs to RECOGNIZE that byte).
    awk -v sq="'" '
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
                    own_ex = (r ~ /\.(jsonc|json|tsx|ts|md)("|[[:space:]]|$)/) ? 1 : 0
                    if (r ~ /\$REPO\/|\$FILES\/|\.github\/|\.\.\/e2e\/|\$SCRIPT_DIR\/\.\.\/\.\.|\$SCRIPT_DIR\/\.\.\/sh\//) {
                        marked[v] = 1; exempt[v] = own_ex; changed++
                    } else if (match(r, /\$[A-Za-z_][A-Za-z_0-9]*/)) {
                        ref = substr(r, RSTART + 1, RLENGTH - 1)
                        if (marked[ref]) {
                            marked[v] = 1
                            # own extension WINS over inheritance ("$TS/../sh/y.sh"
                            # is a shell source even though $TS is a .tsx);
                            # extension-less values inherit the parent class
                            if (own_ex) exempt[v] = 1
                            else if (r ~ /\.[a-z0-9]+("|[[:space:]]|$)/) exempt[v] = 0
                            else exempt[v] = exempt[ref]
                            changed++
                        }
                    }
                }
                if (!changed) break
            }
            for (k = 1; k <= n; k++) {
                stmt = S[k]
                # annotation exemption: statement-level -- an in-place
                # `rider-inversion` marker names the sanctioned bare shape
                # (conventions.md "Source-counting pins": a comment-literal
                # presence pin)
                inv = (stmt ~ /#[[:space:]]*rider-inversion/)
                # Per-leg evaluation (review a S4/X2, #468): a check carried
                # on a &&-continuation leg of a compound is gated like a
                # statement-initial one; an absence leg (`! grep`) is its
                # own leg and no longer exempts the check leg beside it.
                # Rule 3 keeps a LEG-level `! grep` exemption: the sweep
                # counts presence-only shapes -- absence stays un-ridden
                # (conventions.md), so a sh -c payload carrying an absence
                # leg stays uncounted.
                nl = split_legs(stmt, leg)
                for (j = 1; j <= nl; j++) {
                    l = leg[j]; sub(/^[[:space:]]+/, "", l)
                    if (l ~ /^check "[^"]*"[[:space:]]+grep / && !inv) {
                        if (has_reg_operand(l)) print "DIRECT\t" L[k] "\t" shorten(stmt)
                    }
                    shcneg = (l ~ /! *grep/)
                    if (l ~ /^check "[^"]*"[[:space:]]+sh -c / && !shcneg && l ~ /_ "\$[A-Za-z_0-9]+"/ &&
                        l !~ /printf "%s" "\$[0-9]"/) {
                        p1 = index(l, "\"$1\"") > 0 || index(l, "\\\"\\$1\\\"") > 0
                        p2 = index(l, "\"$2\"") > 0 || index(l, "\\\"\\$2\\\"") > 0
                        p3 = index(l, "\"$3\"") > 0 || index(l, "\\\"\\$3\\\"") > 0
                        cnt = (p1 ? 1 : 0) + (p2 ? 1 : 0) + (p3 ? 1 : 0)
                        if (cnt == 1 && has_reg_bind(l)) print "SHC1\t" L[k] "\t" shorten(stmt)
                    }
                    # Rule 4 (#469): the same grammar with an absence
                    # leg -- single positional, registration-bound,
                    # AND single-leg: the payload itself is split
                    # quote-aware and must consist of EXACTLY one leg
                    # starting `! grep`. A compound payload (presence
                    # beside absence, an in-payload pipe, a numeric
                    # gate) or a two-file conjunction stays out -- the
                    # documented raw shapes, converted on sight.
                    if (l ~ /^check "[^"]*"[[:space:]]+sh -c / && shcneg && l ~ /_ "\$[A-Za-z_0-9]+"/ &&
                        l !~ /printf "%s" "\$[0-9]"/) {
                        pl = payload_legs(l)
                        p1 = index(l, "\"$1\"") > 0 || index(l, "\\\"\\$1\\\"") > 0
                        p2 = index(l, "\"$2\"") > 0 || index(l, "\\\"\\$2\\\"") > 0
                        p3 = index(l, "\"$3\"") > 0 || index(l, "\\\"\\$3\\\"") > 0
                        cnt = (p1 ? 1 : 0) + (p2 ? 1 : 0) + (p3 ? 1 : 0)
                        if (pl == 1 && ple[1] ~ /^ *! *grep/ && cnt == 1 && has_reg_bind(l)) print "SHCA\t" L[k] "\t" shorten(stmt)
                    }
                }
            }
        }
        # split_legs: quote-aware split of a joined statement into command
        # legs on `;`, `|` runs and `&&`. A single `&` is literal (`2>&1`
        # never splits); `||` splits like `|`. Escapes honored: inside
        # double quotes `\"` is a literal byte, not a terminator; inside
        # single quotes nothing is escapable -- so BRE `\|` inside a
        # quoted grep pattern and the `&&` inside an sh -c payload never
        # split the leg (review a S4, #468).
        func split_legs(s, out,   n, i, c, q, cur) {
            n = 0; q = ""; cur = ""
            for (i = 1; i <= length(s); i++) {
                c = substr(s, i, 1)
                if (q != "") {
                    cur = cur c
                    if (q == "\"" && c == "\\") {
                        i++
                        cur = cur substr(s, i, 1)
                        continue
                    }
                    if (c == q) q = ""
                    continue
                }
                if (c == sq || c == "\"") { q = c; cur = cur c; continue }
                if (c == ";" || c == "|") {
                    while (substr(s, i + 1, 1) == "|") i++
                    n++; out[n] = cur; cur = ""
                    continue
                }
                if (c == "&") {
                    if (substr(s, i + 1, 1) == "&") {
                        while (substr(s, i + 1, 1) == "&") i++
                        n++; out[n] = cur; cur = ""
                        continue
                    }
                    cur = cur c
                    continue
                }
                cur = cur c
            }
            n++; out[n] = cur
            return n
        }
        # payload_legs: the rule-4 strictness guard (#469) -- extract
        # the sh -c payload of a check leg and return its leg count
        # via split_legs; a caller also reads ple[1] for the negated
        # grep anchor. The payload anchor is the ARM anchor itself
        # (`check "desc" <spaces> sh -c ` -- round a X1, #487): the
        # first-`sh -c `-index spelling let a description carrying
        # those bytes (or a double space after them) redirect the
        # extraction and silently unflag a strict row. Quote-
        # CONCATENATED payloads (any spelling: sq-dq-sq, sq-sq,
        # backslash, a dq-opening splice -- rounds a X2 + b B1 + c C2)
        # escape rule 4 ENTIRELY, both quote branches: the first
        # segment alone cannot see the legs behind a concat, and a
        # false flag there demanded an impossible conversion -- the
        # whole concatenated shape rides convert-on-sight, like the
        # sibling spellings of rule 3. Escape valences of the
        # double-quoted form: backslash-quote/-backslash/-dollar
        # reduce to their single bytes (suite-level escapes), other
        # pairs pass verbatim; a payload not starting with a quote
        # char returns 0 legs (no flag).
        func payload_legs(s,   m, q, rest, ei, j, cj, nk, inner) {
            if (!match(s, /^check "[^"]*"[[:space:]]+sh -c[[:space:]]+/)) return 0
            m = RSTART + RLENGTH
            q = substr(s, m, 1)
            inner = ""
            if (q == sq) {
                rest = substr(s, m + 1)
                ei = index(rest, sq)
                if (ei == 0) return 0
                # Quote-CONCATENATED payloads escape entirely (rounds
                # a X2 + b B1): a legitimate single-quoted payload is
                # always followed by whitespace (the ` _ ` binder); any
                # OTHER byte directly after the closing quote is a
                # concat splice -- sq-sq and sq-dq-sq idioms, the
                # backslash spelling -- whose later segments this
                # first-segment parser cannot see. Refusing the whole
                # shape trades the false flag (an impossible
                # conversion demand on a hidden compound) for a
                # documented convert-on-sight miss.
                if (substr(rest, ei + 1, 1) !~ /[ \t]/) return 0
                inner = substr(rest, 1, ei - 1)
            } else if (q == "\"") {
                rest = substr(s, m + 1)
                j = 1
                while (j <= length(rest)) {
                    cj = substr(rest, j, 1)
                    if (cj == "\\") {
                        # The outer suite-level escapes reduce to their
                        # payload bytes (backslash-quote -> quote,
                        # backslash-backslash -> backslash, backslash-
                        # dollar -> dollar): split_legs then runs on the
                        # payload AS SHELL SEES IT, where a backslash-
                        # quote must not wedge its quote state open.
                        nk = substr(rest, j + 1, 1)
                        if (nk == "\"" || nk == "\\" || nk == "$") inner = inner nk
                        else inner = inner cj nk
                        j += 2
                        continue
                    }
                    if (cj == "\"") break
                    inner = inner cj
                    j++
                }
                # Unterminated dq payload: no flag (fail-still).
                if (j > length(rest)) return 0
                # The SAME concat guard as the sq branch (round c C2):
                # a byte other than whitespace directly after the
                # closing quote is a concat splice whose later
                # segments this parser cannot see -- escape.
                if (substr(rest, j + 1, 1) !~ /[ \t]/) return 0
            } else return 0
            return split_legs(inner, ple)
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
                if (marked[name] && !exempt[name]) return 1
                s = substr(s, RSTART + RLENGTH)
            }
            return 0
        }
        func has_reg_bind(s) {
            while (match(s, /"\$[A-Za-z_][A-Za-z_0-9]*"/)) {
                name = substr(s, RSTART + 2, RLENGTH - 3)
                if (marked[name] && !exempt[name]) return 1
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
    'MD="$REPO/docs/reference/cli.md"' \
    'CHK="$TS/../sh/y.sh"' \
    'check "direct over registered" grep -qF pat "$SRC"' \
    'check "direct over fixture stays" grep -qF pat "$FIX"' \
    'check "direct inversion-annotated stays" grep -qF pat "$SRC" # rider-inversion (comment-literal pin)' \
    'check "direct beside absence leg flags" grep -qF pat "$SRC" && ! grep -qF nope "$SRC"' \
    'check "direct over slash-family stays" grep -qF pat "$TS"' \
    'check "direct over markdown stays" grep -qF pat "$MD"' \
    'grep -qF pre "$SRC" && check "joined direct flags" grep -qF pat "$SRC"' \
    'check "shc over registered" sh -c "grep -qF pat \"\$1\"" _ "$SRC"' \
    'check "shc absence strict (rule 4 flags it)" sh -c "! grep -qF nope \"\$1\"" _ "$SRC"' \
    'check "multi-file absence stays" sh -c "! grep -qF nope \"\$1\" && ! grep -qF nope \"\$2\"" _ "$SRC" "$SRC"' \
    'check "single-file compound absence stays" sh -c "! grep -qF nope \"\$1\" && grep -qF pat \"\$1\"" _ "$SRC"' \
    'check "strict absence with sh -c in the desc flags" sh -c "! grep -qF nope \"\$1\"" _ "$SRC"' \
    'check "direct chained var flags" grep -qF pat "$CHK"' \
    'check_live "ridden stays" "$SRC" -qF pat' \
    'check_absent "named absence" "$SRC" -qF nope' \
    >"$_cell/rule2.sh"
# The spliced-quote rows (round a X2 + b B1): SINGLE-quoted payloads
# whose first grep pattern carries an apostrophe ride a quote-CONCAT
# splice -- the sq-dq-sq idiom and the sq-sq idiom -- assembled
# byte-precisely here (a literal single quote cannot occur inside a
# single-quoted printf argument). The double-space row (round a X1)
# sits here for uniformity: shfmt leaves quoted string interiors
# untouched, so the bytes would survive the format gate -- but this
# block owns every byte-fragile fixture row (b B2: the earlier
# "shfmt would collapse it" rationale was wrong).
_sq="'"
printf '%s\n' "check \"spliced compound absence stays out\" sh -c ${_sq}! grep -qF don${_sq}\"${_sq}\"${_sq}t \"\$1\" && grep -qF y \"\$1\"${_sq} _ \"\$SRC\"" \
    >>"$_cell/rule2.sh"
printf '%s\n' "check \"sqsq compound absence stays out\" sh -c ${_sq}! grep -qF don${_sq}${_sq}t \"\$1\" && grep -qF y \"\$1\"${_sq} _ \"\$SRC\"" \
    >>"$_cell/rule2.sh"
printf '%s\n' 'check "dq concat compound stays out" sh -c "! grep -qF nope \"\$1\"'"'"' && grep -qF y \"\$1\"'"'"' _ "$SRC"' \
    >>"$_cell/rule2.sh"
# NOTE (round c sabotage catch): the dq-concat row above must carry
# the SUITE-LEVEL escape bytes backslash-dollar in BOTH segments --
# a printf double-quoted "\$1" emits `$1` without the backslash, the
# positional-count conjunct then sees neither spelling and the row
# flags nowhere: the escape pin goes VACUOUSLY green (caught by the
# per-cycle sabotage run, L4). The single-quoted-with-splices shape
# above is the byte-faithful form.
# The strict SINGLE-quoted row (round c C1): the only fixture row
# exercising the sq branch's FLAG path (every other strict row is
# double-quoted; the sq rows above are concat-escape rows).
printf '%s\n' "check \"strict sq absence flags\" sh -c ${_sq}! grep -qF nope \"\$1\"${_sq} _ \"\$SRC\"" \
    >>"$_cell/rule2.sh"
printf '%s\n' 'check "double space payload flags" sh -c  "! grep -qF nope \"\$1\"" _ "$SRC"' \
    >>"$_cell/rule2.sh"

_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c DIRECT)"
check "planted direct strict shapes flag (4: direct, absence-beside, joined, chained)" test "$_n" = 4
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'direct over registered')"
check "the direct-over-registered arm is one of them" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'inversion-annotated')"
check "inversion-annotated site stays unflagged (comment-literal pin)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'fixture')"
check "direct over a fixture var stays unflagged" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'absence leg')"
check "presence leg beside an absence leg flags (review a X2, #468)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'joined direct')"
check "&&-joined check flags (review a S4, #468)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'slash-family')"
check "direct over slash-family source stays unflagged (// deferred)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep DIRECT | grep -c 'markdown')"
check "direct over markdown source stays unflagged (headings are not comments, #472)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c 'chained')"
check "chained registration flags (transitive derivation)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c SHC1)"
check "planted sh -c indirection shape counts (rule 3)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHC1 | grep -c 'shc absence')"
check "sh -c payload with an absence leg stays uncounted (presence-only rule 3)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c 'ridden')"
check "a check_live call stays unflagged" test "$_n" = 0

# --- 1c. rule-4 discrimination arms (#469: strict sh -c absence -> check_absent)
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c SHCA)"
check "planted strict sh -c absence shapes flag (4: plain, desc carrying sh -c, double space, strict sq)" test "$_n" = 4
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'shc absence')"
check "the rule-3 absence arm is exactly rule 4's flag (SHCA names it)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'strict sq')"
check "a strict single-quoted payload flags (the sq branch flag path, c C1)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'desc flags')"
check "a desc carrying the sh -c bytes still flags (payload anchor = arm anchor, a X1)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'double space')"
check "a double-space payload still flags ([[:space:]]+ anchor, a X1)" test "$_n" = 1
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'multi-file absence')"
check "multi-file absence conjunction stays out (positional-count guard)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'single-file compound')"
check "single-file compound absence stays out (payload single-leg conjunct, a X5)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'spliced compound')"
check "spliced-quote compound absence stays out (splice escape, a X2)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'sqsq compound')"
check "sq-sq compound absence stays out (concat escape, b B1)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep SHCA | grep -c 'dq concat compound')"
check "dq-opening concat compound stays out (dq-branch guard, c C2)" test "$_n" = 0
_n="$(_rule2_detect "$_cell/rule2.sh" | grep -c 'named absence')"
check "a check_absent call stays unflagged (it is the name)" test "$_n" = 0

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

# --- 3b. rider-inversion tripwire (review a X3, #468): the marker
# exempts a strict shape from rule 2, so appending it must stay a
# conscious, reviewable act -- the detector cannot verify the inversion
# claim (that the pinned literal is a full-line comment), so the COUNT
# is the control. Two marker-mention sites are sanctioned outside this
# suite today (the container-backend comment-literal pin; the
# ddev-as-opencode browser-arm pin since #470); this suite's own
# planted arm is machinery and rides the same self-allowlist as the
# sweeps above. Precision note (review b B1, #468): the count pattern
# matches a marker mention ANYWHERE on a live (non-comment-initial)
# line, not only in trailing position -- it can only over-count (fail
# loud), never false-pass. A new marker (or one stamped onto a live
# pin) fails loud here until the site carries a conventions.md
# "Source-counting pins" justification in the same diff.
_inv_expected=2
_inv_found=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _inv_found=$((_inv_found + $(grep -cE '^[^#].*# rider-inversion' "$_f")))
done
check "rider-inversion markers stay a registered exception ($_inv_found/$_inv_expected)" \
    test "$_inv_found" = "$_inv_expected"

# --- 4. rule-3 sweep (gating since #470, was a ratchet until then):
# sh -c single-file presence shapes must not exist ------------------------
_total=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _hits="$(_rule2_detect "$_f" | grep SHC1)"
    if [ -n "$_hits" ]; then
        fail "sh -c single-file presence shape in $(basename "$_f") -- use check_live / parent-if + live_src pipes (rule 3, #470)"
        echo "$_hits" | sed 's/^/        /'
        _total=$((_total + 1))
    fi
done
if [ "$_total" -eq 0 ]; then
    pass "no sh -c single-file presence shapes in tests/unit (rule 3, #470)"
fi

# --- 5. rule-4 sweep (gating since #469, born gated): the strict sh -c
# absence shape must be check_absent -- the named raw fail-on-found
# sugar. Grammar: rule 3's binds plus the payload-single-leg conjunct
# (header); the escapes (multi-file conjunctions, compound legs,
# in-payload pipes, spliced quotes, literal-path / log / fixture
# binds, if-forms) stay the documented raw shapes and convert on
# sight (header, conventions.md).
_total=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _hits="$(_rule2_detect "$_f" | grep SHCA)"
    if [ -n "$_hits" ]; then
        fail "strict sh -c absence shape in $(basename "$_f") -- use check_absent (rule 4, #469)"
        echo "$_hits" | sed 's/^/        /'
        _total=$((_total + 1))
    fi
done
if [ "$_total" -eq 0 ]; then
    pass "no strict sh -c absence shapes in tests/unit (rule 4, #469)"
fi

suite_done "rider lint tests"
