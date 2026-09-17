#!/usr/bin/env python3
"""
opencode permissions kit -- cli.json plugin registration (opencode 2.x)

Manages the kit's TUI mode plugin entry in ~/.config/opencode/cli.json:
opencode 2.x moved terminal-client config from layered tui.json(c) files
to one global cli.json, and v1 plugin implementations do not run there —
the kit-mode-2x.tsx port is registered as a `plugins` entry instead.
cli.json is user-owned state (the TUI persists preferences there), so this
is strictly ADDITIVE: only entries whose package path points into the
kit's LIBDIR/tui directory are ever added, rewritten, or removed — every
other key and entry survives byte-order-preserving round-trips.

Usage:
  tui-register.py <cli.json> register <plugin-path> [--drop <path>]...
  tui-register.py <cli.json> unregister <plugin-path> [--drop <path>]...

`register` appends {"package": <plugin-path>} unless an entry with that
package already exists. `--drop` additionally removes entries for a
legacy path (used to clean the auto-migrated v1 kit-mode.tsx entry that
2.x carried over from tui.json). `unregister` removes the entry again.
Missing files are created on register (with a minimal {"plugins": []}),
left alone on unregister. Idempotent: unchanged content is not rewritten.
Exit 0 on success or no-op, 1 on usage/IO/parse errors (to stderr).
"""
import importlib.util
import json
import os
import sys

# Never drop __pycache__ beside the kit's scripts when importing the
# parser (happened on first use; the files tree must stay clean).
sys.dont_write_bytecode = True

# Comment-tolerant load (cli.json should be plain JSON, but the kit's own
# configs are JSONC — tolerate the same here). The parser lives beside
# this file; its dash-named module needs a spec-based import.
_PARSER_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "jsonc-parser.py")
if os.path.exists(_PARSER_PATH):
    _spec = importlib.util.spec_from_file_location("opk_jsonc_parser", _PARSER_PATH)
    _parser = importlib.util.module_from_spec(_spec)
    try:
        _spec.loader.exec_module(_parser)
        _strip = _parser.strip_jsonc_comments
    except Exception:
        _strip = None
else:
    _strip = None


def load(path):
    with open(path, "r") as f:
        raw = f.read()
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        if _strip is None:
            raise
        return json.loads(_strip(raw))


def entry_package(entry):
    """The package specifier of a plugins entry (string or object form)."""
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict) and isinstance(entry.get("package"), str):
        return entry["package"]
    return None


def main(argv):
    args = argv[1:]
    drops = []
    while "--drop" in args:
        i = args.index("--drop")
        if i + 1 >= len(args):
            print("tui-register: --drop requires a path", file=sys.stderr)
            return 1
        drops.append(args[i + 1])
        del args[i : i + 2]
    if len(args) != 3 or args[1] not in ("register", "unregister"):
        print(f"Usage: {argv[0]} <cli.json> register|unregister <plugin-path> [--drop <path>]...", file=sys.stderr)
        return 1
    path, mode, plugin = args

    data = {}
    if os.path.exists(path):
        try:
            data = load(path)
        except (OSError, ValueError) as e:
            print(f"tui-register: cannot parse {path}: {e}", file=sys.stderr)
            return 1
    if not isinstance(data, dict):
        print(f"tui-register: {path} is not a JSON object, refusing to touch it", file=sys.stderr)
        return 1

    plugins = data.get("plugins")
    if plugins is None:
        plugins = []
    if not isinstance(plugins, list):
        print(f"tui-register: {path} has a non-list plugins key, refusing to touch it", file=sys.stderr)
        return 1

    ours = {"package": plugin}
    changed = False
    if mode == "register":
        if not any(entry_package(e) == plugin for e in plugins):
            plugins.append(ours)
            changed = True
    else:
        keep = [e for e in plugins if entry_package(e) != plugin]
        if len(keep) != len(plugins):
            plugins = keep
            changed = True
    for legacy in drops:
        keep = [e for e in plugins if entry_package(e) != legacy]
        if len(keep) != len(plugins):
            plugins = keep
            changed = True

    if not changed:
        return 0
    if plugins:
        data["plugins"] = plugins
    else:
        data.pop("plugins", None)
    try:
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
    except OSError as e:
        print(f"tui-register: cannot write {path}: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
