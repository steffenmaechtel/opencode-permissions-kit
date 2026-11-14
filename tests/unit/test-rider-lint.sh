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
# did. Spliced-quote payloads are PARSED THROUGH since the #488
# shlex port: the payload token is assembled by shlex itself, so a
# concat spelling (sq-dq-sq, sq-sq, dq-opening -- rounds a X2 + b B1
# / c C2) no longer hides the payload's real legs; a spliced STRICT
# absence flags (the escape class closed), a spliced compound still
# stays out (its payload is genuinely multi-leg);
# the payload anchor is the arm anchor -- TOKEN INDEXES (check, desc,
# sh, -c at leg positions 0/1/2/3 in lib/rider_detect.py), immune to
# a desc carrying those bytes (round a X1); an unquoted desc token
# satisfies it too (documented port delta).
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
#     absence payload and a spliced-quote compound stay out (the
#     payload's REAL legs decide, spliced or not -- single-leg
#     conjunct, round a X2/X5)
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
_rule2_detect() { # $1 = suite file -> DIRECT/SHC1/SHCA hits on stdout
    # shlex port (#488 pilot): the quote-tracking phases (split_legs /
    # payload_legs) live in python now (tests/unit/lib/rider_detect.py)
    # -- POSIX shlex parses shell quoting correctly by construction, so
    # the splice/concat escape classes (#487 rounds a X2 / b B1 / c C2)
    # close structurally. Joining and registration are faithful ports;
    # the differential over all suites and the fixture arms pinned the
    # equivalence before the swap.
    python3 "$SCRIPT_DIR/lib/rider_detect.py" "$1"
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
# The #488 shlex row: an sq-sq spliced payload whose VALUE is a clean
# strict absence -- parsed through (the payload's real legs decide),
# flagged since the port; the awk detector escaped this spelling.
printf '%s\n' "check \"spliced strict absence flags (shlex parses through, #488)\" sh -c ${_sq}! grep -qF no${_sq}${_sq}pe \"\$1\"${_sq} _ \"\$SRC\"" \
    >>"$_cell/rule2.sh"
printf '%s\n' 'check "double space payload flags" sh -c  "! grep -qF nope \"\$1\"" _ "$SRC"' \
    >>"$_cell/rule2.sh"
# Round a (#496) rows -- the port-fidelity shapes the review round's
# EXECUTED differential pinned (fix wave a): the bare-EOL && continuation
# (a A1: the joiner dropped the separator bytes, the continuation check
# was invisible), merged-token operands (a A2: the whole-token anchor
# was blind inside $(...) and quote-concat spellings), the
# trailing-comment apostrophe (a C1: the quote raise skipped the whole
# statement where the awk flagged), the escaped positional (a A3: the
# awk byte forms never counted the dq-payload \$1 spelling).
printf '%s\n' \
    'foo bar &&' \
    'check "joined bare-EOL cont flags" grep -qF pat "$SRC"' \
    'check "cmdsub operand flags" grep -qF pat "$(dirname "$SRC")/f"' \
    'check "concat operand flags" grep -qF pat "$SRC"bak' \
    'check "comment apostrophe still flags" grep -qF pat "$SRC" # doesn'\''t ride the comment' \
    'check "esc positional dq payload" sh -c "grep -qF pat \$1" _ "$SRC"' \
    >>"$_cell/rule2.sh"

# one interpreter start for every rule2.sh arm below (#488 pilot):
# the fixture verdicts grep the captured output, not 20 fresh calls
_rule2_out="$(_rule2_detect "$_cell/rule2.sh")"
_n="$(printf '%s\n' "$_rule2_out" | grep -c DIRECT)"
check "planted direct strict shapes flag (8: direct, absence-beside, joined, chained, bare-EOL cont, cmdsub, concat, comment-apostrophe)" test "$_n" = 8
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'direct over registered')"
check "the direct-over-registered arm is one of them" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'inversion-annotated')"
check "inversion-annotated site stays unflagged (comment-literal pin)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'fixture')"
check "direct over a fixture var stays unflagged" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'absence leg')"
check "presence leg beside an absence leg flags (review a X2, #468)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'joined direct')"
check "&&-joined check flags (review a S4, #468)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'bare-EOL cont')"
check "a check on a bare-EOL && continuation flags (joiner keeps the separator bytes, #496 a A1)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'cmdsub operand')"
check "a source var inside a merged \$(...) token flags (operand prefix walk, #496 a A2)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'concat operand')"
check "a quote-concat operand (\"\$SRC\"bak) flags (operand prefix walk, #496 a A2)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'comment apostrophe')"
check "an apostrophe in a trailing comment does not skip the statement (comment re-parse pass, #496 a C1)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'slash-family')"
check "direct over slash-family source stays unflagged (// deferred)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep DIRECT | grep -c 'markdown')"
check "direct over markdown source stays unflagged (headings are not comments, #472)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep -c 'chained')"
check "chained registration flags (transitive derivation)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep -c SHC1)"
check "planted sh -c indirection shape counts (rule 3, 2 rows: dq presence, esc positional)" test "$_n" = 2
_n="$(printf '%s\n' "$_rule2_out" | grep SHC1 | grep -c 'esc positional')"
check "an escaped positional (\$1) in a dq payload counts (documented port delta, #496 a A3)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep SHC1 | grep -c 'shc absence')"
check "sh -c payload with an absence leg stays uncounted (presence-only rule 3)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep -c 'ridden')"
check "a check_live call stays unflagged" test "$_n" = 0

# --- 1c. rule-4 discrimination arms (#469: strict sh -c absence -> check_absent)
_n="$(printf '%s\n' "$_rule2_out" | grep -c SHCA)"
check "planted strict sh -c absence shapes flag (5: plain, desc carrying sh -c, double space, strict sq, spliced strict)" test "$_n" = 5
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'spliced strict')"
check "a spliced STRICT absence flags (the concat escape class closes, #488)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'shc absence')"
check "the rule-3 absence arm is exactly rule 4's flag (SHCA names it)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'strict sq')"
check "a strict single-quoted payload flags (the sq branch flag path, c C1)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'desc flags')"
check "a desc carrying the sh -c bytes still flags (payload anchor = arm anchor, a X1)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'double space')"
check "a double-space payload still flags ([[:space:]]+ anchor, a X1)" test "$_n" = 1
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'multi-file absence')"
check "multi-file absence conjunction stays out (positional-count guard)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'single-file compound')"
check "single-file compound absence stays out (payload single-leg conjunct, a X5)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'spliced compound')"
check "spliced compound absence stays out (real multi-leg payload, a X2 row)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'sqsq compound')"
check "sq-sq compound absence stays out (real multi-leg payload, b B1 row)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep SHCA | grep -c 'dq concat compound')"
check "dq-opening concat compound stays out (real multi-leg payload, c C2 row)" test "$_n" = 0
_n="$(printf '%s\n' "$_rule2_out" | grep -c 'named absence')"
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
# One interpreter start for ALL three rule sweeps (#488 pilot): the
# detector's --batch mode prefixes every hit with its file; the loops
# below grep the capture (per-file fail rows, self-allowlist and hit
# format unchanged -- the prefix is cut away again).
_TAB="$(printf '\t')"
_BATCH_OUT="$(work_new_file)" || {
    echo "rider lint tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
set --
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    set -- "$@" "$_f"
done
# Fail-loud (round a B1, #496): the detector buffers ALL batch output
# and writes it once at the END -- any batch-mode death (unreadable
# file, a future parse bug) leaves the capture at ZERO bytes, and the
# three sweeps below would grep an empty file and pass VACUOUSLY
# green. The rc guard turns a detector death into a hard suite
# failure; the arm below executes the failure path through the guard
# message, observed on stderr the way a real run observes it.
_rule2_batch() { # $@ = suite files -> $_BATCH_OUT; loud on death
    python3 "$SCRIPT_DIR/lib/rider_detect.py" --batch "$@" \
        >"$_BATCH_OUT" || {
        echo "rider lint tests: rider-detect --batch failed (rc=$?) -- rules 2-4 sweep output unreliable" >&2
        return 1
    }
}
_b1_rc=0
_b1_err="$( (_rule2_batch "$_cell/no-such-sweep-file.sh") 2>&1 >/dev/null)" || _b1_rc=$?
_n="$(printf '%s\n' "$_b1_err" | grep -c 'rules 2-4 sweep output unreliable')"
check "a rider-detect --batch death fails loud with the guard message (round a B1, #496)" test "$_n" = 1
check "a rider-detect --batch death returns nonzero (guard rc wiring, #496 b D3)" test "$_b1_rc" -ne 0
_rule2_batch "$@" || exit 1
_total=0
for _f in "$SCRIPT_DIR"/test-*.sh; do
    [ "$(basename "$_f")" = "test-rider-lint.sh" ] && continue
    _hits="$(grep -F "${_f}${_TAB}DIRECT${_TAB}" "$_BATCH_OUT" | cut -d "$_TAB" -f2-)"
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
    _hits="$(grep -F "${_f}${_TAB}SHC1${_TAB}" "$_BATCH_OUT" | cut -d "$_TAB" -f2-)"
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
    _hits="$(grep -F "${_f}${_TAB}SHCA${_TAB}" "$_BATCH_OUT" | cut -d "$_TAB" -f2-)"
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
