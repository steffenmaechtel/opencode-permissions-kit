#!/bin/sh
# Unit tests for the agent host notes (#721): the prose file the kit
# ships for AI agents on installed hosts
# (templates/AGENTS-HOST.md) and the pointer block that leads them
# there.
#   1. the file ships: both fetch lists (update.sh KIT_FILES,
#      install.sh), the lib_deploy manifest (mode 644) and SHA256SUMS
#      carry it
#   2. the agent can read it under its own permission layer: the read
#      rules of the shipped opencode.jsonc template evaluate to allow
#      for the deployed path (a README.md at the same spot is DENIED
#      by the template's "*README.md" rule -- the naming constraint)
#   3. the notes carry every failure-mode -> workaround pair
#   4. the pointer block in README.md names exactly the file the
#      deploy manifest and the fetch lists ship under LIBDIR (the
#      stability contract between a copied block and the deployed
#      file: a rename on either side reddens here)
#   5. voluntary by design: no shipped script names the agent's
#      AGENTS.md -- the kit never writes the file the block goes into
#   6. docs wiring: the files.md row and the how-to in the docs index
# The three rendered copies of the pointer block (README, landing
# page, how-to) are pinned byte-identical in tests/unit/test-pages.sh;
# the deployed mode is pinned by tests/unit/test-deploy-lib.sh.
# The file NAME is a stability contract (docs/how-to/agent-host-notes.md):
# users copy the absolute path into their AGENTS.md, where no kit update
# can reach it. Every pin below spells the name on purpose -- a rename
# reddens this suite until the wave either reverts it or ships a stub at
# the old path (#770 a C2).
# Sabotage (committed tree, then restore + re-run green): drop the
# entry from one fetch list -> the list-drift guards in
# tests/unit/test-kit-files.sh AND section 1 go red; rename the file
# -> sections 1, 2 and 4 go red; delete a pair from the notes ->
# section 3 goes red.
# Run: sh tests/unit/test-agents-host-notes.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
TEMPLATE="$REPO/files/opencode-permissions-kit-lib/templates/opencode.jsonc"
PARSER="$REPO/files/opencode-permissions-kit-lib/py/jsonc-parser.py"
NOTES_MD="$REPO/files/opencode-permissions-kit-lib/templates/AGENTS-HOST.md"
README_MD="$REPO/README.md"
FILES_MD="$REPO/docs/reference/files.md"
DOCS_INDEX_MD="$REPO/docs/README.md"
HOWTO_MD="$REPO/docs/how-to/agent-host-notes.md"
SUMS="$REPO/SHA256SUMS"
FILES_DIR="$REPO/files"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$REPO/tests/unit/lib/harness.sh"

# The manifest/fetch-list spelling of the shipped file: deploy-lib.sh
# deploys <entry> to <LIBDIR>/<entry without the lib prefix>.
NOTES_ENTRY='opencode-permissions-kit-lib/templates/AGENTS-HOST.md'
SNIP_START='<!-- opk-agents-snippet:start -->'
SNIP_END='<!-- opk-agents-snippet:end -->'

# --- 1. the file ships ------------------------------------------------------

echo "-- 1. the file ships --"

if [ -f "$NOTES_MD" ]; then
    pass "host notes exist in the checkout"
else
    fail "host notes missing from the checkout: $NOTES_MD"
fi
check_live "update.sh KIT_FILES ships the host notes" "$UPDATE" -qF "$NOTES_ENTRY"
check_live "install.sh fetch list ships the host notes" "$INSTALL" -qF "$NOTES_ENTRY"
check_live "lib_deploy manifest deploys the host notes mode 644 (agent-readable)" \
    "$DEPLOYLIB" -qF "$NOTES_ENTRY 644"
check_live "SHA256SUMS carries the host notes" "$SUMS" -qF "  files/$NOTES_ENTRY"

# --- 2. the agent's permission layer allows the read -------------------------

echo "-- 2. the agent's permission layer allows the read --"

WORK="$(work_new)" || {
    echo "agent host notes tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
READ_EFFECT="$WORK/read_effect.py"
# Prints the effect the template's read rules resolve to for one path
# (last matching rule wins), through the kit's own jsonc parser. The
# wildcard translation is the one tests/unit/test-template-bash-rules.sh
# anchors to the upstream matcher and to live tests, the trailing-" *"
# branch included; `selftest` pins that translation here (#770 a S2).
cat >"$READ_EFFECT" <<'PYEOF'
import importlib.util
import re
import sys


def wildcard_match(value, pattern):
    text = value.replace("\\", "/")
    expr = pattern.replace("\\", "/")
    expr = re.sub(r"[.+^${}()|[\]\\]", lambda m: "\\" + m.group(0), expr)
    expr = expr.replace("*", ".*").replace("?", ".")
    if expr.endswith(" .*"):
        expr = expr[:-3] + "( .*)?"
    return re.fullmatch(expr, text, re.DOTALL) is not None


def selftest():
    # Ground truth for the translation (opencode's matcher): "*" spans
    # "/" and matches the empty run; a pattern ending in " *" also
    # matches the bare value. A row that flips means THIS translation
    # broke -- not the template.
    rows = [
        ("git status", "git status *", True),
        ("git status -s", "git status *", True),
        ("git statusx", "git status *", False),
        ("/x/README.md", "*README.md", True),
        ("/x/AGENTS-HOST.md", "*README.md", False),
    ]
    ok = True
    for value, pattern, want in rows:
        got = wildcard_match(value, pattern)
        if got != want:
            print(f"selftest: {pattern!r} vs {value!r}: replica={got} want={want}", file=sys.stderr)
            ok = False
    return 0 if ok else 1


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "selftest":
        sys.exit(selftest())
    if len(sys.argv) != 4:
        sys.exit("usage: read_effect.py selftest | <jsonc-parser.py> <opencode.jsonc> <path>")
    spec = importlib.util.spec_from_file_location("jsonc_parser", sys.argv[1])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    rules = module.load_config(sys.argv[2])["permission"]["read"]
    effect = "no-rule"
    for pattern, action in rules.items():
        if wildcard_match(sys.argv[3], pattern):
            effect = action
    print(effect)


main()
PYEOF

# The replica proves its own translation before any template claim:
# without the trailing-" *" branch the first selftest row flips.
check 'replica selftest: trailing-" *" optional, anchored, "*" spans "/"' \
    python3 "$READ_EFFECT" selftest

# The deployed location derives from install.sh's own LIBDIR literal --
# never a second spelling of the path.
LIBDIR="$(live_src "$INSTALL" | sed -n 's/^LIBDIR="\([^"]*\)"$/\1/p' | head -n 1)"
if [ -n "$LIBDIR" ]; then
    pass "install.sh LIBDIR literal extracted ($LIBDIR)"
else
    fail "install.sh LIBDIR literal not found (anchor drift?)"
fi
NOTES_DEPLOYED="$LIBDIR/templates/AGENTS-HOST.md"

_rc=0
_effect="$(python3 "$READ_EFFECT" "$PARSER" "$TEMPLATE" "$NOTES_DEPLOYED")" || _rc=$?
if [ "$_rc" -eq 0 ] && [ "$_effect" = "allow" ]; then
    pass "agent read rules allow the deployed host notes (effect=$_effect)"
else
    fail "agent read rules must ALLOW $NOTES_DEPLOYED (rc=$_rc effect=$_effect)"
fi
# Canary: the same evaluation must DENY a README.md at the same spot --
# an evaluator that answered allow for everything would pass the pin
# above vacuously.
_rc=0
_effect="$(python3 "$READ_EFFECT" "$PARSER" "$TEMPLATE" "$LIBDIR/templates/README.md")" || _rc=$?
if [ "$_rc" -eq 0 ] && [ "$_effect" = "deny" ]; then
    pass "canary: a README.md at the same spot is denied (the replica discriminates)"
else
    fail "canary: a README.md at the same spot must evaluate deny (rc=$_rc effect=$_effect)"
fi

# --- 3. the notes carry every failure-mode -> workaround pair ----------------

echo "-- 3. the notes carry every failure-mode -> workaround pair --"

# Docs-pin shape (agent/conventions.md "Source-counting pins"): raw
# greps over markdown, each literal a single-line fragment chosen
# against the file's wrap. One literal per pair plus its workaround.
for _lit in \
    'whoami' \
    'opk status' \
    'could not write config file' \
    'git push origin <branch>' \
    '--no-track' \
    'unable to write new index file' \
    "couldn't set 'HEAD'" \
    'update_ref failed' \
    'sudo opk git-heal on' \
    'git-protection' \
    'git worktree add <dir> -b <branch>'; do
    check "host notes carry: $_lit" grep -qF -- "$_lit" "$NOTES_MD"
done

# --- 4. the pointer block names the shipped file ----------------------------

echo "-- 4. the pointer block names the shipped file --"

# pointer_names_shipped_file <readme-copy> -- rc 0 when the pointer
# block names EXACTLY ONE absolute path and that path is a file the
# deploy manifest and the fetch lists ship under LIBDIR. Shared by the
# real-tree pin and the canary below (the same extraction, the same
# verdict -- not a re-implementation).
pointer_names_shipped_file() {
    _pn_block="$(sed -n "/^${SNIP_START}\$/,/^${SNIP_END}\$/p" "$1")"
    _pn_paths="$(printf '%s\n' "$_pn_block" | grep -E '^/[A-Za-z0-9._/-]+$')"
    [ "$(printf '%s\n' "$_pn_paths" | grep -c .)" -eq 1 ] || return 1
    case "$_pn_paths" in
        "$LIBDIR"/*) _pn_entry="opencode-permissions-kit-lib/${_pn_paths#"$LIBDIR"/}" ;;
        *) return 1 ;;
    esac
    # Trailing space: the exact manifest/fetch-list entry, never a
    # longer name that merely starts with it.
    live_src "$DEPLOYLIB" | grep -qF "$_pn_entry " &&
        live_src "$UPDATE" | grep -qF "$_pn_entry " &&
        [ -f "$FILES_DIR/$_pn_entry" ]
}

if pointer_names_shipped_file "$README_MD"; then
    pass "README pointer block names a file the kit ships under $LIBDIR"
else
    fail "README pointer block does not name exactly one shipped file under $LIBDIR"
fi
# Canary: the same check over a COPY of the README whose pointer
# target is renamed must fail -- a contract pin that cannot see a
# rename is decoration. The rename replaces whatever path line the
# block carries (not a second spelling of the path), so the canary
# stays meaningful while the pin above is red for a wrong path.
sed "s|^${LIBDIR}/templates/[^ ]*|${LIBDIR}/templates/RENAMED-NOTES.md|" \
    "$README_MD" >"$WORK/readme-renamed.md"
if cmp -s "$README_MD" "$WORK/readme-renamed.md"; then
    fail "canary: the renamed-pointer fixture did not change the README copy"
elif pointer_names_shipped_file "$WORK/readme-renamed.md"; then
    fail "canary: a renamed pointer target is NOT detected (contract pin is blind!)"
else
    pass "canary: a renamed pointer target is detected"
fi

# --- 5. voluntary by design -------------------------------------------------

echo "-- 5. the kit never writes an AGENTS.md --"

# Absence pin over every shipped non-markdown file: none may name the
# agent's AGENTS.md path -- the file the pointer block goes into is
# the user's, install and update leave it alone. check_absent is RAW
# and loud on purpose: a commented-out write still counts, and a
# missing tree fails instead of passing as absent. (Comments citing
# this repo's own rule file as "AGENTS.md, Rules" carry no path and
# stay outside the pattern.) Lexical by nature: a target assembled
# from parts escapes it -- the pin narrows the class, it does not
# close it.
check_absent "no shipped file names the agent's AGENTS.md path" \
    "$FILES_DIR" -rlF --exclude='*.md' -- 'opencode/AGENTS.md'
# Canary: the same grep over a scratch tree with one planted writer
# must find it (an absence leg that cannot fire is decoration). Direct
# rc observation -- check_absent reports through its row, not its rc.
mkdir -p "$WORK/ship/lib"
printf '#!/bin/sh\ncp notes.md /example/home/opencode/.config/opencode/AGENTS.md\n' \
    >"$WORK/ship/lib/writer.sh"
check "canary: the planted AGENTS.md writer is found" \
    grep -rlqF --exclude='*.md' -- 'opencode/AGENTS.md' "$WORK/ship"

# --- 6. docs wiring ---------------------------------------------------------

echo "-- 6. docs wiring --"

check "files.md lists the deployed host notes" grep -qF -- "$NOTES_DEPLOYED" "$FILES_MD"
check "docs index lists the how-to" grep -qF -- 'how-to/agent-host-notes.md' "$DOCS_INDEX_MD"
if [ -f "$HOWTO_MD" ]; then
    pass "how-to page exists (docs/how-to/agent-host-notes.md)"
else
    fail "how-to page missing: $HOWTO_MD"
fi
# The how-to tells users to expect an approval request for the read
# (the notes file lies outside the project) -- that sentence holds only
# while the agent template keeps the ask, and only on an install whose
# agent config IS the kit's: a config the user wrote is left alone by
# the installer and decides on its own (#770 a C1).
check "agent template keeps external_directory at ask (the how-to's approval note)" \
    grep -qF -- '"external_directory": "ask"' "$TEMPLATE"

suite_done "agent host notes tests"
