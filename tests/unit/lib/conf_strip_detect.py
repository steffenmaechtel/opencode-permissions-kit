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
- an extraction site is `sed -n 's/^KEY=//p'` (single- or
  double-quoted, the "s/^$1=//p" helper spelling included);
- every site must carry `sed 's/^"//;s/"$//'` in the SAME joined line;
- out-of-class sites (a different input file, quote-safe by other
  means) are allowlisted by (basename, key); a stale allowlist entry
  (site gone from the scanned corpus) is reported as a row -- the
  allowlist must not outlive its sites;
- tui/kit-mode*.tsx: regex conf reads must strip through the val()
  helper -- a bare `.exec(conf)` chain without .replace( is a row.

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

EXTRACT = re.compile(r"""sed -n (['"])s/\^([A-Za-z_][A-Za-z0-9_]*|\$1)=//p\1""")
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
            if ('.exec(conf)' in line and '.trim()' in line
                    and '.replace(' not in line):
                rows.append('%s\t%d\ttsx-read\tunstripped conf regex read'
                            % (path, idx))
            continue
        m = EXTRACT.search(line)
        if not m:
            continue
        key = m.group(2)
        sites += 1
        if key in allow_keys:
            allow_seen.add(key)
            continue
        if STRIP not in line:
            rows.append('%s\t%d\t%s\tunstripped conf extraction'
                        % (path, idx, key))
    for key in sorted(allow_keys - allow_seen):
        rows.append('%s\t-\t%s\tstale allowlist entry' % (base, key))
    return rows, sites, len(allow_seen)


def main(argv):
    args = argv[1:]
    stats = False
    if '--stats' in args:
        stats = True
        args = [a for a in args if a != '--stats']
    if not args:
        sys.stderr.write('conf_strip_detect.py: no files given\n')
        return 1
    out = []
    nfiles = nsites = nallow = 0
    for path in args:
        rows, sites, allow = detect_file(path)
        nfiles += 1
        nsites += sites
        nallow += allow
        out.extend(rows)
    if stats:
        sys.stdout.write('files %d\nsites %d\nallow %d\n'
                         % (nfiles, nsites, nallow))
    else:
        sys.stdout.write(''.join(row + '\n' for row in out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
