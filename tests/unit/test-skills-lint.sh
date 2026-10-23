#!/bin/sh
# test-skills-lint.sh -- structural lint over .agents/skills/
#
# opencode loads skills from .agents/skills/<name>/SKILL.md and silently
# SKIPS any file whose frontmatter does not parse (SkillFile.parse ->
# "Skipped", debug log only — verified against the pinned opencode
# source). A skill that stops loading therefore fails SILENTLY: nothing
# red anywhere, the sessions just fall back to long-form docs. This lint
# is the fail-loud pin for that class (L1).
#
# Rules:
#   - every entry under .agents/skills/ is a skill directory with a
#     SKILL.md (a bare .md at the skills root would load too, but the
#     house shape is one directory per skill)
#   - skill directories carry the house namespace prefix `opk-`: global
#     maintainer skills (ddev-*, typo3-*, ...) and project skills share
#     one skill list per session — the prefix keeps IDs collision-free
#     and marks the origin (the loader keys skills by ID; two skills
#     with the same ID overwrite each other)
#   - SKILL.md starts with a `---` frontmatter block that closes
#   - frontmatter carries a non-empty `name:` equal to the directory
#     name (the loader IDs a skill by its directory; a diverging name
#     makes the system prompt list and the file tree disagree)
#   - frontmatter carries a non-empty single-line `description:` of at
#     most 400 chars — the description is the ONLY router signal a
#     session sees before invoking (issue #178: "the loader needs to
#     pick them reliably")
#   - no `local/` path references — workspace rule (AGENTS.md, global):
#     repo content must never point into the disposable workspace
#
# The lint function takes the skills root as its argument so the
# fixture pins below exercise the failure paths against scratch copies.
#
# Run: sh tests/unit/test-skills-lint.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# lint_skills <dir> -- prints FAIL lines, empty output = clean
lint_skills() {
    _root="$1"
    [ -d "$_root" ] || { echo "FAIL skills root missing: $_root"; return; }
    for _d in "$_root"/*/; do
        [ -d "$_d" ] || continue
        _name=$(basename "$_d")
        case "$_name" in
            opk-*) ;;
            *) echo "FAIL $_name: missing opk- namespace prefix" ;;
        esac
        _f="$_d/SKILL.md"
        if [ ! -f "$_f" ]; then
            echo "FAIL $_name: no SKILL.md"
            continue
        fi
        # frontmatter block: first line ---, a closing --- within the head
        head -n 1 "$_f" | grep -qxF -- '---' || \
            echo "FAIL $_name: frontmatter must open with ---"
        _close=$(sed -n '2,20p' "$_f" | grep -n -- '^---$' | head -1 | cut -d: -f1)
        [ -n "$_close" ] || echo "FAIL $_name: frontmatter never closes"
        # name: non-empty, equals directory
        _nm=$(sed -n '2,20p' "$_f" | sed -n 's/^name:[[:space:]]*//p' | head -1)
        case "$_nm" in
            "$_name") ;;
            *) echo "FAIL $_name: name '$_nm' != directory '$_name'" ;;
        esac
        # description: non-empty, single line, <= 400 chars
        _desc=$(sed -n '2,20p' "$_f" | sed -n 's/^description:[[:space:]]*//p' | head -1)
        [ -n "$_desc" ] || echo "FAIL $_name: empty or missing description"
        [ -n "$_desc" ] && [ "${#_desc}" -gt 400 ] && \
            echo "FAIL $_name: description ${#_desc} chars > 400"
        # no local/ references anywhere in the skill directory
        if grep -rn 'local/' "$_d" >/dev/null 2>&1; then
            echo "FAIL $_name: references local/ (disposable workspace)"
        fi
    done
}

# --- fixture pins: the lint must discriminate (L4) ---------------------
# A broken skill is silently skipped by the loader -- if this lint
# cannot tell broken from valid, it pins nothing. Pins run against a
# scratch copy BEFORE the real-tree check and the summary gate.

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}" "$TMP"' EXIT

mkdir -p "$WORK/skills/opk-good-skill" "$WORK/skills/opk-no-desc" \
         "$WORK/skills/opk-wrong-name" "$WORK/skills/opk-local-ref" \
         "$WORK/skills/opk-no-skill-md" "$WORK/skills/no-prefix"
cat > "$WORK/skills/opk-good-skill/SKILL.md" <<'EOF'
---
name: opk-good-skill
description: Valid fixture skill used only by the skills lint self-test.
---
Body.
EOF
cat > "$WORK/skills/opk-no-desc/SKILL.md" <<'EOF'
---
name: opk-no-desc
---
Body.
EOF
cat > "$WORK/skills/opk-wrong-name/SKILL.md" <<'EOF'
---
name: something-else
description: Fixture whose name diverges from its directory.
---
Body.
EOF
cat > "$WORK/skills/opk-local-ref/SKILL.md" <<'EOF'
---
name: opk-local-ref
description: Fixture that references the disposable workspace.
---
See local/legacy-2026-10/restructure-docs.
EOF
echo "not a skill" > "$WORK/skills/opk-no-skill-md/note.txt"
cat > "$WORK/skills/no-prefix/SKILL.md" <<'EOF'
---
name: no-prefix
description: Fixture that lacks the house namespace prefix.
---
Body.
EOF

_out=$(lint_skills "$WORK/skills")
case "$_out" in
    *"FAIL no-prefix"*) echo "  pin ok: missing opk- prefix caught" ;;
    *) echo "  PIN BROKEN: missing opk- prefix not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-no-desc"*) echo "  pin ok: missing description caught" ;;
    *) echo "  PIN BROKEN: missing description not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-wrong-name"*) echo "  pin ok: name mismatch caught" ;;
    *) echo "  PIN BROKEN: name mismatch not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-local-ref"*) echo "  pin ok: local/ reference caught" ;;
    *) echo "  PIN BROKEN: local/ reference not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-no-skill-md"*) echo "  pin ok: missing SKILL.md caught" ;;
    *) echo "  PIN BROKEN: missing SKILL.md not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"opk-good-skill"*) echo "  PIN BROKEN: valid fixture flagged" >> "$TMP" ;;
    *) echo "  pin ok: valid fixture passes clean" ;;
esac

# --- real tree ----------------------------------------------------------

lint_skills .agents/skills >> "$TMP" 2>&1

if [ -s "$TMP" ]; then
    echo "FAIL skills lint:"
    cat "$TMP"
    exit 1
fi
echo "  ok  .agents/skills lint clean ($(ls .agents/skills | tr '\n' ' '))"
exit 0
