#!/usr/bin/env python3
"""Conf-reader quote-strip detector (issue #786).

Every sed-extraction of a KEY=VALUE line in shipped files/** must strip
surrounding quotes in the same pipeline -- the DOCTOR_USER idiom
doctor-core.sh has carried since PR #785 (a B5), extended to the
extraction helpers (b A1) and the remaining readers (#786, this wave).
The class survived three review rounds because each wave's sweep key
found only its own sites; this detector turns the invariant into a
gate (agent/learnings.md "When a rule fails": escalate to a test that
fails the suite).

Mechanics (the trap_detect.py shape):
- backslash continuations are JOINED before matching -- the house wrap
  puts the operand and the strip on the second physical line, so a
  single-line grep sees only the first (PR #642 round b S1);
- an extraction site is `sed ['\"]s/^KEY=//p['\"]` with optional -n /
  -e flags in any order/spacing (single- or double-quoted, the
  "s/^$1=//p" helper spelling included), OR an anchored-grep value
  read -- `grep ... '^KEY=…$'` anchored at BOTH ends over one literal
  (presence checks anchor only at ^ and are out of class; the live
  instance was ddev-handover.sh's DDEV_DEV_OWNED grep, #790 a A1);
- every site must carry `sed 's/^"//;s/"$//'` in the SAME joined line;
- out-of-class sites (a different input file, quote-safe by other
  means) are allowlisted by (basename, key); a stale allowlist entry
  (site gone from a still-scanned file) is reported as a row, and
  `--strict-allowlist` additionally reports an allowlisted BASENAME
  absent from the scanned corpus -- a renamed or deleted allowlisted
  file can no longer leave its entries silently exempt (#790 a C2);
- tui/kit-mode*.tsx: regex conf reads must strip through the val()
  helper -- a bare `.exec(conf)` chain without .replace( is a row,
  with or without a trailing .trim().

Findings go to stdout as rows (file, joined-line-no, key, reason);
rc 0 even with findings (the consumer suite decides); rc 1 with a
stderr message only for the empty scan set (trap_detect's "no files
given" reference shape). --stats prints corpus counts instead of rows.
"""
import pathlib
import re
import sys

# (basename, key, reason) -- extraction sites that are NOT install.conf
# value readers. Each entry is asserted to still exist in the scanned
# corpus (a site gone leaves the entry stale and the gate red).
ALLOW = [
    ("install-core.sh", "ID",
     "os-release reader -- strips quotes via tr -d (equivalent)"),
    ("install-core.sh", "VERSION_ID",
     "os-release reader -- strips quotes via tr -d (equivalent)"),
    ("update-check.sh", "STATE",
     "kit-owned decline-note file (single kit writer, never quoted)"),
    ("update-check.sh", "DATE",
     "kit-owned decline-note file (single kit writer, never quoted)"),
    ("update-check.sh", "VER",
     "kit-owned decline-note file (single kit writer, never quoted)"),
    ("config.sh", "OPENCODE_DOCKER_HOST",
     "parses setup-container-backend stdout, not install.conf"),
    ("status-core.sh", "Linger",
     "parses loginctl show-user stdout, not install.conf"),
]

EXTRACT = re.compile(
    r"""sed (?:-n\s+)?(?:-e\s+)?(['"])s/\^([A-Za-z_][A-Za-z0-9_]*|\$1)=//p\1""")
GREP_VALUE = re.compile(
    r"""grep\b[^|]*['\"]\^[A-Za-z_][A-Za-z0-9_]*=[^'\"]*\$['\"]""")
STRIP = 's/^"//;s/"$//'
RE_COMMENT_LINE = re.compile(r'^\s*#')


def joined_lines(text):
    """Backslash-continuation join: line N ending in backslash merges
    with line N+1 (leading whitespace of the tail dropped)."""
    out = []
    for line in text.splitlines():
        if out and out[-1].endswith('\\'):
            out[-1] = out[-1][:-1] + line.lstrip()
        else:
            out.append(line)
    return out


def detect_file(path):
    """Returns (rows, sites_seen, allow_seen) for one file."""
    rows = []
    sites = 0
    allow_seen = set()
    text = pathlib.Path(path).read_text(encoding='utf-8', errors='replace')
    base = pathlib.Path(path).name
    allow_keys = {k for b, k, _r in ALLOW if b == base}
    for idx, line in enumerate(joined_lines(text), 1):
        if RE_COMMENT_LINE.match(line):
            continue
        if base.endswith('.tsx'):
            if '.exec(conf)' in line and '.replace(' not in line:
                rows.append('%s\t%d\ttsx-read\tunstripped conf regex read'
                            % (path, idx))
            continue
        m = EXTRACT.search(line)
        if m:
            key = m.group(2)
            sites += 1
            if key in allow_keys:
                allow_seen.add(key)
                continue
            if STRIP not in line:
                rows.append('%s\t%d\t%s\tunstripped conf extraction'
                            % (path, idx, key))
            continue
        if GREP_VALUE.search(line):
            sites += 1
            rows.append('%s\t%d\tgrep-read\tanchored-grep conf value read '
                        '(extract-then-case with the strip)'
                        % (path, idx))
    for key in sorted(allow_keys - allow_seen):
        rows.append('%s\t-\t%s\tstale allowlist entry' % (base, key))
    return rows, sites, len(allow_seen)


def main(argv):
    args = argv[1:]
    stats = False
    strict = False
    if '--stats' in args:
        stats = True
        args = [a for a in args if a != '--stats']
    if '--strict-allowlist' in args:
        strict = True
        args = [a for a in args if a != '--strict-allowlist']
    if not args:
        sys.stderr.write('conf_strip_detect.py: no files given\n')
        return 1
    out = []
    nfiles = nsites = nallow = 0
    scanned = set()
    for path in args:
        rows, sites, allow = detect_file(path)
        nfiles += 1
        nsites += sites
        nallow += allow
        scanned.add(pathlib.Path(path).name)
        out.extend(rows)
    if strict:
        # C2 (#790 round a): the per-file stale check above fires only
        # for files the scan still SEES — a renamed or deleted
        # allowlisted file would leave its entries silently exempt
        # forever. Under this flag an allowlisted basename absent from
        # the scanned corpus is reported, so the allowlist cannot
        # outlive its files either.
        for b, _k, _r in ALLOW:
            if b not in scanned:
                out.append('%s\t-\t-\tstale allowlist file' % b)
    if stats:
        sys.stdout.write('files %d\nsites %d\nallow %d\n'
                         % (nfiles, nsites, nallow))
    else:
        sys.stdout.write(''.join(row + '\n' for row in out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
