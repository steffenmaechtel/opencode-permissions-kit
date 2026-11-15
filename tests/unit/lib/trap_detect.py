#!/usr/bin/env python3
"""trap_detect.py -- check-4 trap-coverage floor detector for
test-sandbox-policy.sh (#498, the #496 shlex playbook applied to the
sandbox-policy trap-arm analyzer: the last hand-rolled quote-state walk).

Replaces trap_scan's inline awk program. The trap-arm analysis -- four
defect rounds of the quote-tracking class in #287 (b S1 greedy
last-quote strip ate the arms behind a quote-bearing trailing comment,
b C2 comment words satisfied the arms, c S1 escaped-quote miscount cut
at a shell-internal #, d D1 unconditional backslash skip ate an
sq-closing quote) -- now reads the arms from shlex tokens:
rider_detect.tokenize with the COMMENTER PASS FIRST (the awk cut a
trailing comment before reading the arms, so a comment naming arms
must not parse as arm tokens; an apostrophe inside a trailing comment
resolves in that first pass -- the comment is cut before its quote
bytes can wedge the parse). The comment-disabled pass stays the
structural fallback of rider's two-pass doctrine -- in THIS order it
is the fail-still net for shapes the commenter pass cannot parse
whole, not the apostrophe net it is for the rider order. The receiver
regex and the own-call view (workline) are faithful ports -- they
never had the defect history, and the shlex option does not fit them:
the own-call view feeds a structural LINE regex over the sq-blanked
view, not a token walk.

Contract (row-compatible with the awk program it replaces): file
arguments, stdout rows exactly

    <file>|notrap
    <file>|arms <line>:no-ARM[ <line>:no-ARM ...]
    <file>|mixtrap

--batch is accepted for call-shape parity with rider_detect.py (rows
already carry the file path). A missing/unreadable file or an empty
argument list exits nonzero -- the suite's fail-loud sweep guard (#498,
the #496 round-a B1 shape): an empty or dead scan must never pass the
floor vacuously.

Documented deltas vs the awk analyzer (#498 adoption differential: old
awk vs this module produced BYTE-IDENTICAL rows over the whole named
corpus -- tests/unit (55 files) plus the suite's check-4 probe corpus,
independently re-run by review round a; every delta below was measured
on scratch torture shapes, none has a live instance at adoption):

  - an unquoted trap statement reads word 1 as the action now, where
    the awk scanned the whole quote-free line as arm text: `trap EXIT`
    (and the signals-only `trap EXIT INT TERM`) additionally flags
    no-EXIT (shell-true: EXIT is the action there, not an arm;
    a C4, #516). Fail-loud direction.
  - a line no pass parses whole (unterminated quotes both ways) emits
    NO arms row -- where the old awk still emitted rows for such lines
    (it read arms off the broken line's last quote: `trap "x` flagged
    all three arms missing). Fail-still, the #496 port doctrine --
    the SILENCE direction, disclosed here exactly because the old
    detector was loud on these shapes (a B1, #516); realistic only in
    heredoc/fixture text, a documented latent gap of check 4.
  - TWO trap statements on one physical line: the arms walk pools the
    tokens after the FIRST trap's action, so the second statement's
    words satisfy the first's arm check -- `trap 'rm' EXIT; trap 'rm'
    INT TERM` passes where the awk emitted no-EXIT. No live instance;
    shell-arguable (collectively armed) (a C1, #516).
  - the arms are the tokens after the ACTION token (index 1, past a
    `--` separator) instead of the bytes after the line's LAST quote
    character -- mechanism change, no verdict change on the corpus: a
    concat spelling (trap "x"EXIT ...) flagged no-EXIT in the awk too
    (its boundary regex cannot match EXIT at the stripped text's
    start), and the token walk arrives at the same verdict because the
    concat word is action bytes.
"""

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from rider_detect import tokenize  # noqa: E402

RE_COMMENT_LINE = re.compile(r'^\s*#')
RE_TRAP_LINE = re.compile(r'^[ \t]*trap[ \t]')
# faithful port of the awk receiver pattern: a live assignment whose
# value starts with an UNESCAPED $(mktemp (optional `command ` prefix)
RE_RECV = re.compile(
    r'^[ \t]*[A-Za-z_][A-Za-z0-9_]*="?[$][(](command[ \t]+)?mktemp')
WNAMES = 'work_new|work_new_file|work_register|work_register_var'
RE_WORKCALL = re.compile(
    r'(\$\(|^[ \t]*|;[ \t]*|&&[ \t]*|\|\|[ \t]*)(' + WNAMES + r')([ \t]|\))')
ARMS = ('EXIT', 'INT', 'TERM')
RE_ARM = {a: re.compile('[^A-Za-z]' + a + '([^A-Za-z]|$)') for a in ARMS}


def own_call_view(s):
    """Faithful port of the awk workline(): the own-call view for the
    work_* detection -- single-quoted spans blanked (child-code strings
    run in children), trailing comment cut, double quotes kept; an
    escaped \\$ placeholder-mangled to break the \\$( adjacency (the
    documented child-script shape), backslash folded outside quotes,
    literal inside single quotes."""
    out = []
    ins = ind = False
    i, n = 0, len(s)
    while i < n:
        ch = s[i]
        if not ins and ch == '\\' and i + 1 < n and s[i + 1] == '$':
            out.append('#')
            i += 2
            continue
        if not ins and not ind and ch == '\\':
            out.append(ch)
            i += 1
            if i < n:
                out.append(s[i])
                i += 1
            continue
        if ch == "'" and not ind:
            ins = not ins
            i += 1
            continue
        if ins:
            i += 1
            continue
        if ch == '"':
            ind = not ind
            out.append(ch)
            i += 1
            continue
        if ch == '#' and not ind:
            break
        out.append(ch)
        i += 1
    return ''.join(out)


def trap_missing(line):
    """shlex port of the trap-arm analyzer. Returns the list of missing
    'no-ARM' entries ([] = armed) or None when no pass parses the line
    whole. Arms = the tokens after the action token (index 1, past a
    `--` separator); the joined text is space-padded so the awk's
    word-boundary regex applies verbatim -- in-action arm words and
    trailing-comment arm words cannot satisfy the check on the primary
    (commenter) pass (the #287 b C2/S1 shapes); on lines only the
    fallback pass parses, comment bytes can become tokens and satisfy
    the regex -- verdict-identical to the replaced awk, which matched
    arms in whole-line text on those shapes (a A3, #516)."""
    toks = tokenize(line, passes=('#', ''))
    if toks is None:
        return None
    if len(toks) > 1 and toks[1] == '--':
        toks = toks[1:]
    arms_text = ' ' + ' '.join(toks[2:]) + ' '
    return ['no-' + a for a in ARMS if not RE_ARM[a].search(arms_text)]


def detect_file(path):
    """One suite file -> its check-4 rows (awk END block port)."""
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        text = f.read()
    lines = text.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    recv = traps = workcall = 0
    arms_bits = []
    for idx, ln in enumerate(lines, 1):
        if RE_COMMENT_LINE.match(ln):
            continue
        if RE_RECV.search(ln):
            recv += 1
        if RE_WORKCALL.search(own_call_view(ln)):
            workcall += 1
        if RE_TRAP_LINE.match(ln):
            traps += 1
            missing = trap_missing(ln)
            if missing:
                arms_bits.extend(' %d:%s' % (idx, m) for m in missing)
    rows = []
    if recv > 0 and traps == 0:
        rows.append('%s|notrap' % path)
    if arms_bits:
        rows.append('%s|arms%s' % (path, ''.join(arms_bits)))
    if workcall > 0 and traps > 0:
        rows.append('%s|mixtrap' % path)
    return rows


def main(argv):
    args = argv[1:]
    if args and args[0] == '--batch':
        args = args[1:]
    if not args:
        sys.stderr.write('trap_detect.py: no files given\n')
        return 1
    out = []
    for path in args:
        out.extend(detect_file(path))
    sys.stdout.write(''.join(row + '\n' for row in out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
