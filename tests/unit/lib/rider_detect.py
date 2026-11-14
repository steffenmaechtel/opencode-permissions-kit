#!/usr/bin/env python3
"""rider_detect.py -- rules 2/3/4 detector for test-rider-lint.sh (#488 pilot).

Replaces the hand-rolled awk quote tracking (split_legs / payload_legs)
with shlex: POSIX-mode shlex with punctuation_chars tokenizes shell
quoting correctly by construction, so the quote-tracking escape classes
of the #487 loop (sq-dq-sq / sq-sq splices, the dq-opening concat --
rounds a X2 / b B1 / c C2) become structurally invisible instead of
guarded round by round. Statement joining and source-variable
registration are faithful ports of the awk phases (they never tracked
quotes).

Contract (byte-compatible with the awk detector it replaces): one file
argument, stdout lines

    DIRECT\\t<start-line>\\t<shortened statement>
    SHC1\\t<start-line>\\t<shortened statement>
    SHCA\\t<start-line>\\t<shortened statement>

--batch mode takes many file arguments and prefixes every line with
"<file>\\t" (one interpreter start for a whole sweep).

Documented deltas vs the awk detector (behavior changes the shlex parse
buys; each pinned by a discrimination arm in the suite):
  - quote-concatenated sh -c payloads are parsed THROUGH: a spliced
    STRICT absence shape now flags (the awk escape class closes); the
    spliced COMPOUND rows still stay out -- the payload's real legs
    decide, not the spelling.
  - an unbalanced quote no longer skips the statement wholesale: pass 1
    parses with commenters disabled; on its quote raise pass 2 re-parses
    with '#' as a commenter, truncating a trailing unquoted comment whose
    English (apostrophes) would otherwise wedge the quote state (round a
    C1, #496 -- the awk flagged such rows; the naive port went blind).
    Only when BOTH passes raise is the statement skipped (fail-still,
    the awk payload extractor's unterminated branch).
  - the rule-2 operand conjunct walks each token's $NAME references
    longest-prefix-first instead of anchoring the whole token: a $NAME
    inside a merged token ('"$(dirname "$SRC")/f"', '"$SRC"bak') flags
    again like the awk's raw scan, and dot-suffixed references
    ('"$SRC".bak', awk-silent) now flag too -- the fail-loud direction
    (round a A2, #496).
  - the positional conjunct counts backslash-escaped and word-suffix
    spellings ('\\$1', 'f\\$1') the awk's byte forms never saw -- the
    escaped positional IS the rule-3/4 shape (round a A3, #496).
  - an UNQUOTED desc token satisfies the token anchor where the awk
    regex demanded quotes (no live rows shape that way).
"""

import re
import shlex
import sys

SEPS = (';', '|', '||', '&&')

RE_COMMENT_LINE = re.compile(r'^\s*#')
RE_END_BACKSLASH = re.compile(r'\\$')
RE_END_AND = re.compile(r'&&\s*$')
RE_END_OROR = re.compile(r'\|\|\s*$')
RE_END_PIPE = re.compile(r'\|\s*$')
# round a A1 (#496): a bare trailing && / || keeps its SEPARATOR BYTES
# in the joined statement (the awk stripped whitespace only) -- the legs
# still split there, so a check on the continuation line stays visible.
RE_TRAIL_WS = re.compile(r'\s+$')
RE_ASSIGN = re.compile(r'^([A-Za-z_][A-Za-z_0-9]*)=(.*)$', re.S)
RE_REGISTERED = re.compile(
    r'\$REPO/|\$FILES/|\.github/|\.\./e2e/'
    r'|\$SCRIPT_DIR/\.\./\.\.|\$SCRIPT_DIR/\.\./sh/')
RE_OWN_EXEMPT_EXT = re.compile(r'\.(jsonc|json|tsx|ts|md)($|\s|")')
RE_REF = re.compile(r'\$([A-Za-z_][A-Za-z_0-9]*)')
RE_CHAINED_EXT = re.compile(r'\.[a-z0-9]+($|\s|")')
RE_INVERSION = re.compile(r'#\s*rider-inversion')
# Anchors are TOKEN-INDEX checks (the awk regex `^check "[^"]*"<ws>grep`
# requires the command word directly after the one-token quoted desc):
# leg[0] == 'check', leg[1] = the desc token, leg[2] the command word.
# Documented delta: an UNQUOTED desc token satisfies the token anchor
# where the awk regex demanded quotes (no live rows shape that way).
RE_BIND = re.compile(r'^\$([A-Za-z_][A-Za-z_0-9]*)$')
RE_POSITIONAL = re.compile(r'"?\\?\$([0-9])"?\b')
RE_PRINTF_EXEMPT = re.compile(r'printf "?%s"? "?\\?\$[0-9]')
RE_BANG_GREP = re.compile(r'(^|\s)! ?grep(\s|$)')


def join_statements(text):
    """Phase A -- faithful port of the awk joiner. Returns [(startline,
    stmt)] with 1-based start lines; full-comment lines never join."""
    lines = text.split('\n')
    stmts = []
    i, total = 0, len(lines)
    while i < total:
        ln = lines[i]
        if RE_COMMENT_LINE.match(ln):
            i += 1
            continue
        stmt, start = ln, i
        while True:
            if RE_END_BACKSLASH.search(stmt):
                stmt = RE_END_BACKSLASH.sub('', stmt)
            elif RE_END_AND.search(stmt):
                stmt = RE_TRAIL_WS.sub('', stmt)
            elif RE_END_OROR.search(stmt):
                stmt = RE_TRAIL_WS.sub('', stmt)
            elif RE_END_PIPE.search(stmt):
                pass  # a trailing single pipe stays in the statement
            else:
                break
            i += 1
            if i > total - 1:
                break
            nxt = re.sub(r'^\s+', '', lines[i])
            if RE_COMMENT_LINE.match(nxt):
                break
            stmt = stmt + nxt
        i += 1
        stmts.append((start + 1, stmt))
    return stmts


def derive_registration(stmts):
    """Phase B -- faithful port of the awk registration derivation
    (first $ref per value per round, four rounds, exemption chains)."""
    marked, exempt = {}, {}
    assigns = []
    for _start, stmt in stmts:
        m = RE_ASSIGN.match(stmt)
        if m:
            assigns.append((m.group(1), m.group(2)))
    for _round in range(4):
        changed = 0
        for name, val in assigns:
            if name in marked:
                continue
            own_ex = bool(RE_OWN_EXEMPT_EXT.search(val))
            if RE_REGISTERED.search(val):
                marked[name] = True
                exempt[name] = own_ex
                changed += 1
            else:
                m = RE_REF.search(val)
                if m and m.group(1) in marked:
                    ref = m.group(1)
                    marked[name] = True
                    if own_ex:
                        exempt[name] = True
                    elif RE_CHAINED_EXT.search(val):
                        exempt[name] = False
                    else:
                        exempt[name] = exempt[ref]
                    changed += 1
        if not changed:
            break
    return marked, exempt


def tokenize(s):
    """POSIX shlex with punctuation chars; None when no pass parses the
    statement whole. Two passes (round a C1, #496): pass 1 keeps
    commenters DISABLED -- '#' is a word byte, so ${VAR#x} and mid-word
    hashes parse whole. An apostrophe inside a TRAILING COMMENT is the
    realistic unbalanced-quote shape ('# doesn't ...'), and skipping
    the whole statement there blinded rules 2-4 on rows the awk still
    flagged. Pass 2 re-parses with '#' as a commenter: shlex discards
    the rest of the (single-line, joined) statement from the hash on --
    the trailing-comment approximation; its collateral (a mid-word hash
    truncating the token) only fires on statements pass 1 already
    rejected. Both passes raising -> None (fail-still: the awk payload
    extractor's unterminated branch)."""
    for commenters in ('', '#'):
        lex = shlex.shlex(s, posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        lex.commenters = commenters
        toks = []
        while True:
            try:
                t = lex.get_token()
            except ValueError:
                break  # unbalanced quote: try the next pass
            if t == lex.eof:
                return toks
            toks.append(t)
    return None


def split_legs(toks):
    """Quote-aware leg split on ; | || && -- separators come as their
    own tokens (&& and || grouped), quote state handled by shlex."""
    legs, cur = [], []
    for t in toks:
        if t in SEPS:
            legs.append(cur)
            cur = []
        else:
            cur.append(t)
    legs.append(cur)
    return legs


def shorten(s):
    s = re.sub(r'^\s+', '', s)
    return s[:160]


def has_reg_operand(leg, marked, exempt):
    """Rule-2 operand conjunct (round a A2, #496): does any leg token
    reference a registered, non-exempt source variable? Unanchored with
    a longest-first prefix walk over each $NAME run: shlex assembles
    '"$(dirname "$SRC")/f"' into ONE token (the old whole-token anchor
    never matched) and '"$SRC"bak' into '$SRCbak' (the greedy name run
    swallows the suffix); the prefix walk resolves both toward flagging
    -- the fail-loud direction (a false flag converts on sight; a
    missed flag rides silently). Dot-suffixed references flag too (the
    awk's quote-delimited byte scan stayed silent on '"$SRC".bak')."""
    for t in leg:
        for m in RE_REF.finditer(t):
            name = m.group(1)
            while name:
                if marked.get(name) and not exempt.get(name):
                    return True
                name = name[:-1]
    return False


def detect_file(path):
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()
    stmts = join_statements(text)
    marked, exempt = derive_registration(stmts)
    hits = []
    for start, stmt in stmts:
        inv = bool(RE_INVERSION.search(stmt))
        toks = tokenize(stmt)
        if toks is None:
            continue
        for leg in split_legs(toks):
            joined = ' '.join(leg)
            # rule 2: strict direct check-grep over a registered source
            if len(leg) > 2 and leg[0] == 'check' and leg[2] == 'grep' \
                    and not inv:
                if has_reg_operand(leg, marked, exempt):
                    hits.append(('DIRECT', start, shorten(stmt)))
            if not (len(leg) > 3 and leg[0] == 'check' and
                    leg[2] == 'sh' and leg[3] == '-c'):
                continue
            bang = bool(RE_BANG_GREP.search(joined))
            # the binder: a `_` token directly followed by a registered
            # source variable (the awk grammar's `_ "$VAR"` conjunct)
            has_binder = any(
                leg[i] == '_' and (m := RE_BIND.match(leg[i + 1]))
                and marked.get(m.group(1)) and not exempt.get(m.group(1))
                for i in range(len(leg) - 1)
            )
            if not has_binder:
                continue
            if RE_PRINTF_EXEMPT.search(joined):
                continue
            positionals = set(
                m.group(1) for m in RE_POSITIONAL.finditer(joined)
                if m.group(1) in ('1', '2', '3')
            )
            if len(positionals) != 1:
                continue
            if not bang:
                # rule 3: presence-only sh -c indirection -- the awk
                # grammar checks the bind and the positional count, not
                # the payload's shape (that is rule 4's stricter ask)
                hits.append(('SHC1', start, shorten(stmt)))
                continue
            # rule 4: strict absence -- the payload is exactly one
            # token between `sh -c` and the `_` binder (a spliced
            # payload is ONE token by construction; an unquoted
            # multi-word payload is many and stays out), and it splits
            # into exactly one leg starting `! grep`
            try:
                c_idx = leg.index('-c')
            except ValueError:
                continue
            binder_idx = leg.index('_') if '_' in leg else None
            if binder_idx is None or binder_idx <= c_idx + 1:
                continue
            payload_toks = leg[c_idx + 1:binder_idx]
            if len(payload_toks) != 1:
                continue
            ptoks = tokenize(payload_toks[0])
            if ptoks is None:
                continue
            plegs = split_legs(ptoks)
            if len(plegs) == 1 and len(plegs[0]) >= 2 and \
                    plegs[0][0] == '!' and plegs[0][1] == 'grep':
                hits.append(('SHCA', start, shorten(stmt)))
    return hits


def main(argv):
    batch = False
    args = argv[1:]
    if args and args[0] == '--batch':
        batch = True
        args = args[1:]
    if not args:
        sys.stderr.write('rider_detect.py: no files given\n')
        return 1
    out = []
    for path in args:
        for kind, line, stmt in detect_file(path):
            if batch:
                out.append('%s\t%s\t%d\t%s' % (path, kind, line, stmt))
            else:
                out.append('%s\t%d\t%s' % (kind, line, stmt))
    sys.stdout.write(''.join(line + '\n' for line in out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
