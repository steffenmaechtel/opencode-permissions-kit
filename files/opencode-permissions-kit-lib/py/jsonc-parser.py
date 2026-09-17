#!/usr/bin/env python3
"""
opencode permissions kit — JSONC Pattern Extractor

Parses opencode.json[c] and extracts deny patterns from permission.read and
permission.edit sections (used by status.sh's report-only leak scan), or
reports which container tools (docker/ddev) a config explicitly enables via
permission.bash (used by the wrapper's container opt-in). Both modes accept
"-" to read JSON from stdin instead of a file — the wrapper pipes
`opencode debug config` output there (the session's final merged config,
global + project; issue #81).

Output: one entry per line to stdout.
Usage:
  python3 jsonc-parser.py /path/to/opencode.json[c]          # deny patterns
  python3 jsonc-parser.py --tools /path/to/opencode.json[c]  # enabled container tools
  (either mode: "-" as the path reads JSON from stdin)
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
    """Normalize JSONC to plain JSON: remove // and /* */ comments and
    trailing commas, ignoring markers inside double-quoted strings (e.g.
    URLs like "https://opencode.ai/..."). Trailing commas (",}") are legal
    JSONC — editors and users rely on them — but strict json.loads rejects
    them, so a comma whose next non-whitespace character closes the object
    or array is dropped."""
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
        if ch == ',':
            # Trailing comma: peek past whitespace AND comments for the
            # closing bracket; drop the comma if one follows.
            j = i + 1
            while j < n:
                if text[j] in ' \t\r\n':
                    j += 1
                elif text[j] == '/' and j + 1 < n and text[j + 1] == '/':
                    while j < n and text[j] != '\n':
                        j += 1
                elif text[j] == '/' and j + 1 < n and text[j + 1] == '*':
                    j += 2
                    while j + 1 < n and not (text[j] == '*' and text[j + 1] == '/'):
                        j += 1
                    j += 2
                else:
                    break
            if j < n and text[j] in '}]':
                i += 1
                continue
        out.append(ch)
        i += 1
    return ''.join(out)


def read_config(config_path):
    """Read the raw config text. "-" means stdin, so callers can pipe in
    `opencode debug config` output — plain JSON whose object key order
    (json.loads preserves insertion order) carries the merged global +
    project rule order that last-match-wins evaluation needs."""
    if config_path == '-':
        return sys.stdin.read()
    with open(config_path, 'r') as f:
        return f.read()


def extract_patterns(config_path):
    raw = read_config(config_path)

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
                if act == 'deny' and pattern != '*':
                    patterns.add(pattern)

    for p in sorted(patterns):
        print(p)


def _debug_entry_rules(config):
    """Extract ordered (pattern, action) rules from `opencode debug config`
    output (opencode 2.x, issue #80): a LIST of entries, lowest priority
    first. Documents carry the normalized `permissions` rule array where the
    v1 permission.bash map was migrated to {action, resource, effect} records
    (action "bash" became "shell"; the config files themselves may still use
    the v1 shape — opencode normalizes on load). Rules from later documents
    win (appended last), matching the session's last-match-wins evaluation."""
    rules = []
    if not isinstance(config, list):
        return rules
    for entry in config:
        if not isinstance(entry, dict) or entry.get('type') != 'document':
            continue
        info = entry.get('info')
        if not isinstance(info, dict):
            continue
        for rule in info.get('permissions', []):
            if not isinstance(rule, dict):
                continue
            if rule.get('action') not in ('shell', 'bash', '*'):
                continue
            resource = rule.get('resource')
            effect = rule.get('effect')
            if isinstance(resource, str) and isinstance(effect, str):
                rules.append((resource, effect))
    return rules


def extract_tools(config_path):
    """Report which container tools (docker, ddev) the config explicitly
    enables. Accepts a config FILE in the v1 shape (permission.bash map,
    evaluated in key order, last matching rule wins — same as opencode) or,
    when config_path is "-", the piped output of `opencode debug config`:
    the 1.x merged config object or the 2.x list of document entries, both
    evaluated with the same last-match-wins semantics. A rule only counts
    if it matches a representative docker/ddev command — subcommand-only
    allows like "ddev composer *" never match "ddev start" and therefore do
    not trigger. Top-level "permission": "allow" and "permission.bash":
    "allow" shorthands count as allowing everything. Prints one tool per
    line."""
    raw = read_config(config_path)

    clean = strip_jsonc_comments(raw)

    try:
        config = json.loads(clean)
    except json.JSONDecodeError as e:
        print(f"Error parsing {config_path}: {e}", file=sys.stderr)
        sys.exit(1)

    if isinstance(config, list):
        rules = _debug_entry_rules(config)
        whole = None
    elif not isinstance(config, dict) or (config_path == '-' and 'permission' not in config and 'permissions' not in config):
        # A piped `opencode debug config` output that is not a dict WITH
        # permission data is not a config at all — most likely an error
        # object from a failed/cold service (1.x merged output and 2.x
        # Entry[] always carry permissions). Exit 3 so the caller can fall
        # back instead of trusting "no tools" (wrapper, issue #80). Plain
        # config FILES may legitimately omit permission — they keep the
        # permissive empty result.
        if config_path == '-':
            print(f"Unrecognized debug-config shape: {config_path}", file=sys.stderr)
            sys.exit(3)
        permission = {}
        whole = None
        rules = []
    else:
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
    if args and args[0] == '--tools':
        mode = 'tools'
        args = args[1:]
    if len(args) < 1:
        print(f"Usage: {sys.argv[0]} [--tools] <path/to/opencode.json[c]|->", file=sys.stderr)
        sys.exit(1)
    if mode == 'tools':
        extract_tools(args[0])
    else:
        extract_patterns(args[0])
