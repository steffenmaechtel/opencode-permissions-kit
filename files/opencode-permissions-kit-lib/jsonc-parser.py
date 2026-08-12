#!/usr/bin/env python3
"""
opencode permissions kit — JSONC Pattern Extractor

Parses opencode.json[c] and extracts deny or allow patterns from
permission.read and permission.edit sections, or reports which container
tools (docker/ddev) a project explicitly enables via permission.bash.

Output: one glob pattern per line to stdout.
Usage:
  python3 jsonc-parser.py /path/to/opencode.json[c]          # deny patterns (default)
  python3 jsonc-parser.py --allow /path/to/opencode.json[c]  # allow patterns
  python3 jsonc-parser.py --tools /path/to/opencode.json[c]  # enabled container tools
"""
import fnmatch
import json
import re
import sys

# Candidate commands used to detect a broad docker/ddev allow in the project's
# own permission.bash. Invocations ("docker ps", "ddev start") mirror real
# usage; bare names ("docker", "ddev") only count via an exact pattern like
# "docker": "allow" (last match wins). "docker-compose" (legacy binary) counts
# as docker; "docker compose" and "sudo docker" do not.
TOOL_BARE = {
    "docker": ("docker", "docker-compose"),
    "ddev": ("ddev",),
}
TOOL_COMMANDS = {
    "docker": ("docker ps", "docker-compose --version"),
    "ddev": ("ddev start",),
}

def _last_match(command, rules):
    """Last rule whose glob matches command (opencode semantics)."""
    match = None
    for pattern, act in rules:
        if fnmatch.fnmatch(command, pattern):
            match = (pattern, act)
    return match

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


def extract_tools(config_path):
    """Report which container tools (docker, ddev) the project explicitly
    enables. Evaluates ONLY the project config's own permission.bash rules in
    file order (last matching rule wins, same as opencode). A rule only counts
    if it matches a representative docker/ddev command — subcommand-only allows
    like "ddev composer *" never match "ddev start" and therefore do not
    trigger. Top-level "permission": "allow" and "permission.bash": "allow"
    shorthands count as allowing everything. Prints one tool per line."""
    with open(config_path, 'r') as f:
        raw = f.read()

    clean = strip_jsonc_comments(raw)

    try:
        config = json.loads(clean)
    except json.JSONDecodeError as e:
        print(f"Error parsing {config_path}: {e}", file=sys.stderr)
        sys.exit(1)

    permission = config.get('permission', {})

    # Top-level shorthand: "permission": "allow" -> everything allowed.
    whole = permission if isinstance(permission, str) else None

    rules = []
    if isinstance(permission, dict):
        bash = permission.get('bash')
        if isinstance(bash, str):
            rules = [('*', bash)]
        elif isinstance(bash, dict):
            rules = [(p, a) for p, a in bash.items()]

    for tool in ('docker', 'ddev'):
        granted = (whole == 'allow')
        if not granted:
            for cmd in TOOL_COMMANDS[tool]:
                match = _last_match(cmd, rules)
                if match and match[1] == 'allow':
                    granted = True
                    break
        if not granted:
            # Bare tool name as an exact pattern, e.g. "docker": "allow".
            for bare in TOOL_BARE[tool]:
                match = _last_match(bare, rules)
                if match and match[0] in TOOL_BARE[tool] and match[1] == 'allow':
                    granted = True
                    break
        if granted:
            print(tool)


if __name__ == '__main__':
    mode = 'deny'
    args = sys.argv[1:]
    if args and args[0] == '--allow':
        mode = 'allow'
        args = args[1:]
    elif args and args[0] == '--tools':
        mode = 'tools'
        args = args[1:]
    if len(args) < 1:
        print(f"Usage: {sys.argv[0]} [--allow|--tools] <path/to/opencode.json[c]>", file=sys.stderr)
        sys.exit(1)
    if mode == 'tools':
        extract_tools(args[0])
    else:
        extract_patterns(args[0], action=mode)
