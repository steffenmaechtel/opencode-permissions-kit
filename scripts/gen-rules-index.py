#!/usr/bin/env python3
"""Generate internal/rules-meta/INDEX.md from the rule metas.

One table row per meta (RM-NNNN), grouped by source file + section —
both derived from each meta's `rule:` back-reference; the section
title is resolved from the target file's heading. Leads with an
Actionable section (review-pending, overdue). Stdlib only.

Structural sanity is fail-loud: a meta with missing frontmatter
fields, duplicate frontmatter keys (#321), a filename that disagrees
with its `id:`, a file outside its ID-derived shard bucket, or an
unlistable bucket directory (#322) aborts generation — the INDEX is
never built from a broken tree.

Usage: python3 scripts/gen-rules-index.py   (from the repo root)
Writes internal/rules-meta/INDEX.md. Hand edits are pointless — the
parity test (tests/unit/test-rules-index-parity.sh) regenerates and
compares.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RMROOT = os.path.join(ROOT, 'internal', 'rules-meta')
REQUIRED = ('id', 'rule', 'quote', 'created', 'status',
            'revisit-interval', 'next-revisit')
TODAY = os.environ.get('FORCE_TODAY', '') or None  # tests may pin the date
MAXDESC = 48


def die(msg):
    print('gen-rules-index: %s' % msg, file=sys.stderr)
    sys.exit(1)


def read(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def parse_meta(path):
    lines = read(path).splitlines()
    if not lines or lines[0].strip() != '---':
        die('%s: no frontmatter' % path)
    fm = {}
    dupes = []
    for ln in lines[1:]:
        if ln.strip() == '---':
            break
        m = re.match(r'^([A-Za-z-]+):\s*(.*)$', ln)
        if m:
            key = m.group(1)
            if key in fm and key not in dupes:
                dupes.append(key)
            val = m.group(2).strip()
            if len(val) >= 2 and val[0] == val[-1] and val[0] in '"\'':
                val = val[1:-1]
            # #321: FIRST wins, the canonical rule shared with the shell
            # extractors (head -1); duplicate keys die below.
            fm.setdefault(key, val)
    if dupes:
        die('%s: duplicate frontmatter key(s): %s'
            % (path, ', '.join(dupes)))
    missing = [f for f in REQUIRED if f not in fm]
    if missing:
        die('%s: missing frontmatter field(s): %s' % (path, ', '.join(missing)))
    return fm


def bucket_rel(rmid):
    """RM-NNNN -> N/N/N/RM-NNNN.md (first three digits, one per level)."""
    digs = rmid[3:]
    return '%s/%s/%s/%s.md' % (digs[0], digs[1], digs[2], rmid)


def slugify(text):
    text = re.sub(r'[^a-z0-9 -]', '', text.lower()).strip()
    return re.sub(r'\s+', '-', text)


def headings(path):
    """[(slug, heading text)] in document order; [] if file missing."""
    if not os.path.exists(path):
        return []
    out = []
    for ln in read(path).splitlines():
        m = re.match(r'^(#{1,6})\s+(.+?)\s*#*$', ln)
        if m:
            out.append((slugify(m.group(2)), m.group(2).strip()))
    return out


def desc(quote):
    quote = quote.replace('|', '/')
    if len(quote) <= MAXDESC:
        return quote
    cut = quote[:MAXDESC].rsplit(' ', 1)[0]
    return cut + '…'


def _listdir_loud(path):
    """sorted listdir that dies loud on an unlistable directory.

    glob.glob silently suppresses PermissionError/OSError under the
    hood (python 3.12 scandir behavior): a permission-broken bucket
    dir produced a short INDEX with rc 0 (#322). The explicit walk
    closes the docstring promise — the INDEX is never built from a
    broken tree.
    """
    try:
        return sorted(os.listdir(path))
    except OSError as exc:
        die('%s: cannot list bucket directory (%s) -- the INDEX '
            'would be partial, no INDEX written' % (path, exc.strerror))


def iter_metas():
    """RM-*.md paths under the digit buckets, replacing the silent
    glob walk: every directory level is listed explicitly and dies
    loud when unreadable (#322). Trees that are readable AND free of
    digit-named non-directories yield exactly the glob's set
    ([0-9] = one ASCII digit per level); a digit-named stray FILE
    dies loud too -- fail-loud on a structurally broken tree, same
    spirit as the shard-bucket rule."""
    for d1 in _listdir_loud(RMROOT):
        if len(d1) != 1 or d1 not in '0123456789':
            continue
        l1 = os.path.join(RMROOT, d1)
        for d2 in _listdir_loud(l1):
            if len(d2) != 1 or d2 not in '0123456789':
                continue
            l2 = os.path.join(l1, d2)
            for d3 in _listdir_loud(l2):
                if len(d3) != 1 or d3 not in '0123456789':
                    continue
                l3 = os.path.join(l2, d3)
                for name in _listdir_loud(l3):
                    if name.startswith('RM-') and name.endswith('.md'):
                        yield os.path.join(l3, name)


def main():
    today = TODAY
    metas = []
    for path in sorted(iter_metas()):
        fm = parse_meta(path)
        base = os.path.basename(path)[:-3]
        if base != fm['id']:
            die('%s: filename != id %s' % (path, fm['id']))
        rel = os.path.relpath(path, RMROOT)
        if rel != bucket_rel(fm['id']):
            die('%s: outside its shard bucket (%s)' % (path, bucket_rel(fm['id'])))
        metas.append((rel, fm))

    head_cache = {}

    def section_for(rule_ref):
        path, _, anchor = rule_ref.partition('#')
        if path not in head_cache:
            head_cache[path] = headings(os.path.join(ROOT, path))
        for order, (slug, text) in enumerate(head_cache[path]):
            if slug == anchor:
                return (path, 0, order, text)
        return (path, 1, 0, '(unresolved section: %s)' % (anchor or path))

    groups = {}
    for rel, fm in metas:
        src, unres, order, title = section_for(fm['rule'])
        groups.setdefault(src, {}).setdefault((unres, order, title), []).append((rel, fm))

    active = [fm for _, fm in metas if fm['status'] == 'active']
    retired = [fm for _, fm in metas if fm['status'] == 'retired']
    # approval-queue membership (#233): approved iff reviewed: carries
    # a non-empty value (any value; date-ness is the audit's inv-9
    # log-line pairing, not membership) -- a bare 'reviewed:' line
    # (key without value) counts as PENDING, the same
    # key-presence-with-value rule as rules-report.sh and
    # rules-audit.sh invariant 9.
    pending = sorted(fm['id'] for _, fm in metas if not fm.get('reviewed'))
    dates = sorted(fm['next-revisit'] for _, fm in metas
                   if fm['status'] == 'active' and fm['next-revisit'])
    overdue = sorted((d, fm['id']) for _, fm in metas
                     for d in [fm['next-revisit']]
                     if fm['status'] == 'active' and d and today and d < today)

    lines = [
        '# Rule-Meta Index',
        '',
        '> GENERATED FILE — do not edit by hand. Regenerated by',
        '> scripts/gen-rules-index.py; the parity test',
        '> (tests/unit/test-rules-index-parity.sh) regenerates and',
        '> compares. Grouped by source file + section, derived from',
        "> each meta's `rule:` back-reference.",
        '',
        '**%d metas · %d active · %d retired · %d review-pending · next due %s**'
        % (len(metas), len(active), len(retired), len(pending),
           dates[0] if dates else '—'),
        '',
        '## Actionable',
        '',
        '- **Review pending:** %s' % (', '.join(pending) if pending else 'none'),
        '- **Overdue:** %s'
        % (', '.join('%s (%s)' % (rid, d) for d, rid in overdue) if overdue
           else 'none'),
        '',
    ]
    for src in sorted(groups):
        lines.append('## %s' % src)
        lines.append('')
        for (unres, order, title) in sorted(groups[src]):
            lines.append('### %s' % title)
            lines.append('')
            lines.append('| Meta | Rule | Status | Review | Cycle | Next revisit |')
            lines.append('|---|---|---|---|---|---|')
            for rel, fm in groups[src][(unres, order, title)]:
                lines.append('| [%s](%s) | %s | %s | %s | %s | %s |' % (
                    fm['id'], rel, desc(fm['quote']), fm['status'],
                    'approved' if fm.get('reviewed') else '**pending**',
                    fm['revisit-interval'], fm['next-revisit']))
            lines.append('')
    out = os.path.join(RMROOT, 'INDEX.md')
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines).rstrip() + '\n')
    print('INDEX.md: %d metas' % len(metas))


if __name__ == '__main__':
    main()
