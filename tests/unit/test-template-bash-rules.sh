#!/bin/sh
# tests/unit/test-template-bash-rules.sh -- behavior pins for the bash
# section of the shipped opencode.jsonc template (issue #391).
#
# WHY: opencode matches a bash permission rule against the WHOLE
# per-command text (leading-anchored wildcard, "*" = any run, last
# matching rule wins), and the matched resource includes the redirect.
# A rule like "> /dev/sd*" therefore never matches — no command text
# starts with ">". The template's redirect denies shipped in that dead
# shape until issue #391; these pins keep the corrected shapes in and
# the dead shapes out, and pin the EFFECT of every rule on a command
# matrix (attack shapes must evaluate to deny, everyday shapes must
# not).
#
# HOW: a python replica of opencode's wildcard matcher (upstream
# sources: opencode 1.18.15 packages/opencode/src/util/wildcard.ts and
# 2.x packages/core/src/util/wildcard.ts — translate-anchored-regex,
# escape [.+^${}()|[\]\\], "*" -> ".*", "?" -> ".", trailing " *"
# optional, dot-all; last matching rule wins per v1 permission/index.ts
# evaluate() and v2 core/src/permission.ts) evaluates the REAL template
# (loaded through the kit's own jsonc parser). The replica is anchored
# to reality three ways: the upstream sources, opencode 2.x's own
# shell-parse test (resource "export -p > ~/.bashrc" — redirect
# included), and the maintainer's live tests in issue #391, which the
# selftest mode re-checks on every run. Replica drift against FUTURE
# upstream changes is out of this suite's reach — that is the e2e
# probe's job (tests/e2e, real binary via session.permission.create).
#
# Sabotage discrimination (committed tree, then restore + re-run):
#   - drop a "*>*/dev/sd*" deny from the template -> its matrix rows
#     and the presence pin go red
#   - revert a rule to the dead "> /dev/sd*" shape -> matrix rows red,
#     absence pin red
#   - mangle the replica (drop the dot-all flag) -> selftest red
#
# Run: sh tests/unit/test-template-bash-rules.sh
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib/harness.sh"

TEMPLATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/templates/opencode.jsonc"
PARSER="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/py/jsonc-parser.py"

WORK="$(work_new)"
MATCHER="$WORK/rule_matcher.py"
EFFECTS="$WORK/effects.tsv"
STRIPPED="$WORK/template-stripped.json"

# --- the replica + matrix evaluator (sandboxed at the source) -----------
# Modes:
#   selftest                       replica vs the issue #391 live tests
#   matrix <template> <cmdfile>    prints "want<TAB>got<TAB>command"
#                                  per input line "want<TAB>command"
cat >"$MATCHER" <<'PYEOF'
import importlib.util
import re
import sys


def wildcard_match(value, pattern):
    # 1:1 translation of opencode's Wildcard.match (v1.18.15
    # packages/opencode/src/util/wildcard.ts, v2 packages/core/src/util/
    # wildcard.ts): normalize backslashes, escape regex specials,
    # "*" -> ".*", "?" -> ".", trailing " *" optional, anchored, dot-all.
    text = value.replace("\\", "/")
    expr = pattern.replace("\\", "/")
    expr = re.sub(r"[.+^${}()|[\]\\]", lambda m: "\\" + m.group(0), expr)
    expr = expr.replace("*", ".*").replace("?", ".")
    if expr.endswith(" .*"):
        expr = expr[:-3] + "( .*)?"
    return re.fullmatch(expr, text, re.DOTALL) is not None


# The maintainer's live tests from issue #391 (comment 6716052773):
# "deny" = permission.rejected observed in a real session, "pass" =
# the command ran unprompted. If a future edit to THIS file makes one
# of these flip, the translation is broken — not the template.
GROUND_TRUTH = [
    ("> /tmp/devexample/sd*", 'echo "x" > /tmp/devexample/sda', "pass"),
    ("*> /tmp/devexample/sd*", 'echo "x" > /tmp/devexample/sda', "deny"),
    ("* > /tmp/devexample/sd*", 'echo "x" > /tmp/devexample/sda', "deny"),
]


def selftest():
    ok = True
    for rule, command, live in GROUND_TRUTH:
        got = "deny" if wildcard_match(command, rule) else "pass"
        print(f"{rule!r} vs {command!r}: replica={got} live={live}")
        ok = ok and got == live
    return 0 if ok else 1


def load_bash_rules(parser_path, template_path):
    spec = importlib.util.spec_from_file_location("jsonc_parser", parser_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    config = module.load_config(template_path)
    return config["permission"]["bash"]


def evaluate(rules, command):
    # Last matching rule wins (v1 evaluate() findLast over config
    # order via fromConfig, v2 core/src/permission.ts evaluate()).
    effect = None
    for pattern, action in rules.items():
        if wildcard_match(command, pattern):
            effect = action
    return effect or "ask"


def matrix(parser_path, template_path, command_file):
    rules = load_bash_rules(parser_path, template_path)
    with open(command_file, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line:
                continue
            want, _, command = line.partition("\t")
            got = evaluate(rules, command)
            print(f"{want}\t{got}\t{command}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: rule_matcher.py selftest | matrix <template> <cmds>")
    if sys.argv[1] == "selftest":
        sys.exit(selftest())
    if sys.argv[1] == "matrix" and len(sys.argv) == 5:
        matrix(sys.argv[2], sys.argv[3], sys.argv[4])
        sys.exit(0)
    sys.exit("usage: rule_matcher.py selftest | matrix <template> <cmds>")
PYEOF

# --- replica selftest (fail loud before any template claim) -------------
check "replica reproduces the issue #391 live tests" python3 "$MATCHER" selftest

# --- the command matrix ---------------------------------------------------
# want: "deny" = the rule set MUST deny it; "!" = must NOT deny (any
# other effect); an explicit "allow"/"ask" pins that exact effect.
# Probe strings are DATA for the matcher — nothing here ever executes.
cat >"$WORK/commands.tsv" <<'CMDS'
deny	echo "x" > /dev/sda
deny	echo "x" >> /dev/sdb
deny	echo "x" >| /dev/sda
deny	echo "x" >/dev/sda
deny	echo "x" >>/dev/sdb
deny	echo "x" >|/dev/sda
deny	echo "x" &> /dev/sda
deny	echo "x" &>>/dev/sda
deny	echo "x" 2> /dev/sda
deny	echo "x" 2>>/dev/nvme0n1
deny	echo "x" > /dev/mmcblk0
deny	echo "x" > /dev/vda
deny	echo "x" > /dev/xvda
deny	echo "x" > /dev/hda
deny	echo "x" > /etc/passwd
deny	echo "x" >> /etc/shadow
deny	> /etc/passwd
deny	ls > /dev/sda
deny	dd of=/dev/sda
deny	sudo dd if=/dev/zero of=/dev/nvme0n1
deny	dd if=/dev/zero of=/dev/mmcblk0
deny	dd if=/dev/zero of=/dev/vda
!	echo "x" > /dev/null
!	echo "x" >/dev/null 2>&1
!	echo "x" 2>/dev/null
!	echo "x" > /tmp/out.txt
!	cat /dev/sda > /tmp/disk.img
!	strings /dev/sda > /tmp/disk.txt
!	echo x > /dev/shm/cache
!	echo x > /dev/stdout
allow	ls -la
allow	git diff HEAD
CMDS

python3 "$MATCHER" matrix "$PARSER" "$TEMPLATE" "$WORK/commands.tsv" >"$EFFECTS"

# Rows feed the loop from a FILE (conventions.md, "Script output
# style": a pipe would count the assert rows in a subshell and lose
# the tally).
while IFS="$(printf '\t')" read -r want got command; do
    case "$want" in
        "!")
            if [ "$got" = "deny" ]; then
                fail "must not deny: $command (got deny)"
            else
                pass "not denied: $command ($got)"
            fi
            ;;
        *)
            assert_eq "bash rule effect: $command" "$want" "$got"
            ;;
    esac
done <"$EFFECTS"

# --- presence / absence pins (#378 waived shape) --------------------------
# Presence: fixed strings over the comment-stripped template (a
# commented-out rule must not anchor a present pin). Absence: fixed
# strings over the RAW template (a commented-out dead form must STILL
# count — it would come back with one keystroke).
python3 - "$PARSER" "$TEMPLATE" >"$STRIPPED" <<'PYEOF'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("jsonc_parser", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
print(module.strip_jsonc_comments(module.read_config(sys.argv[2])))
PYEOF

for rule in \
    '*>*/dev/sd*": "deny"' \
    '*>*/dev/nvme*": "deny"' \
    '*>*/dev/mmcblk*": "deny"' \
    '*>*/dev/vd*": "deny"' \
    '*>*/dev/xvd*": "deny"' \
    '*>*/dev/hd*": "deny"' \
    '*>*/etc/*": "deny"' \
    '*dd*of=/dev/sd*": "deny"' \
    '*dd*of=/dev/nvme*": "deny"' \
    '*dd*of=/dev/mmcblk*": "deny"' \
    '*dd*of=/dev/vd*": "deny"' \
    '*dd*of=/dev/xvd*": "deny"' \
    '*dd*of=/dev/hd*": "deny"'; do
    check "redirect/dd deny present: $rule" grep -qF "$rule" "$STRIPPED"
done

for dead in \
    '">: /dev/sd*"' \
    '"> /dev/sd*": "deny"' \
    '">> /dev/sd*": "deny"' \
    '"dd of=/dev/sd*": "deny"' \
    '"> /etc/*": "deny"' \
    '">> /etc/*": "deny"'; do
    if grep -qF "$dead" "$TEMPLATE"; then
        fail "dead redirect shape gone: $dead"
    else
        pass "dead redirect shape gone: $dead"
    fi
done

suite_done "template bash rule pins"
