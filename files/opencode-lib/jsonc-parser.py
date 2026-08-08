#!/usr/bin/env python3
"""
opencode Permission-Control Setup-Kit — JSONC Pattern Extractor

Parses opencode.json[c] and extracts deny or allow patterns from
permission.read and permission.edit sections.

Output: one glob pattern per line to stdout.
Usage:
  python3 jsonc-parser.py /path/to/opencode.json[c]          # deny patterns (default)
  python3 jsonc-parser.py --allow /path/to/opencode.json[c]  # allow patterns
"""
import json
import re
import sys

def strip_jsonc_comments(text):
    """Remove // and /* */ comments, ignoring comment markers inside
    double-quoted strings (e.g. URLs like "https://opencode.ai/...")."""
    out = []
    i = 0
    n = len(text)
    in_string = False
    while i < n:
        ch = text[i]
        if in_string:
            out.append(ch)
            if ch == '\\' and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if ch == '"':
                in_string = False
            i += 1
            continue
        if ch == '"':
            in_string = True
            out.append(ch)
            i += 1
            continue
        if ch == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                i += 1
            continue
        if ch == '/' and i + 1 < n and text[i + 1] == '*':
            i += 2
            while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                i += 1
            i += 2
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def extract_patterns(config_path, action='deny'):
    with open(config_path, 'r') as f:
        raw = f.read()

    clean = strip_jsonc_comments(raw)

    try:
        config = json.loads(clean)
    except json.JSONDecodeError as e:
        print(f"Error parsing {config_path}: {e}", file=sys.stderr)
        sys.exit(1)

    patterns = set()
    permission = config.get('permission', {})

    for tool in ('read', 'edit'):
        rules = permission.get(tool, {})
        if isinstance(rules, dict):
            for pattern, act in rules.items():
                if act == action and pattern != '*':
                    patterns.add(pattern)

    for p in sorted(patterns):
        print(p)


if __name__ == '__main__':
    mode = 'deny'
    args = sys.argv[1:]
    if args and args[0] == '--allow':
        mode = 'allow'
        args = args[1:]
    if len(args) < 1:
        print(f"Usage: {sys.argv[0]} [--allow] <path/to/opencode.json[c]>", file=sys.stderr)
        sys.exit(1)
    extract_patterns(args[0], action=mode)
