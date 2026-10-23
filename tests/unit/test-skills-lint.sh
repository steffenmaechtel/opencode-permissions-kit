#!/bin/sh
# test-skills-lint.sh -- structural lint over .agents/skills/
#
# opencode loads skills from .agents/skills/<name>/SKILL.md and silently
# SKIPS any file whose frontmatter does not parse (SkillFile.parse ->
# "Skipped", debug log only — verified against the pinned opencode 2.x
# source, v2.1.4: packages/core/src/config/plugin/skill-file.ts; the
# 1.x loader v1.18.x skips even more silently, a bare continue with no
# log: packages/core/src/skill.ts). A skill that stops loading
# therefore fails SILENTLY: nothing red anywhere, the sessions just
# fall back to long-form docs. This lint is the fail-loud pin for that
# class (L1).
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
#     most 400 BYTES (measured with wc -c: byte semantics are
#     deterministic across dash and bash — ${#var} counts bytes in
#     dash but chars in bash, #235 a X3) — the description is the ONLY
#     router signal a session sees before invoking (issue #178: "the
#     loader needs to pick them reliably")
#   - no workspace `local/` references — workspace rule (AGENTS.md,
#     global): repo content must never point into the disposable
#     workspace. Matched shapes: `local/…` and `../local/…` (relative
#     from workspace root / repo), the dot-slash family `./local/…`
#     (incl. `x/./local/`, `.././local/`), prose-prefixed occurrences,
#     and this checkout's absolute workspace-local path (computed at
#     runtime below). NOT matched, deliberately: `~/.local/` (XDG),
#     `/usr/local/` (system prefix), identifier-embedded shapes
#     (`opencode-local/`, `foo.local/`) and repo-internal segments
#     (`x/local/`) — none of those resolve into the disposable dir
#     (#235 a S3/X1, #235 b B1). A scan ERROR is a FAIL at BOTH
#     stages — grep rc 2 (dangling or unreadable operand) and find
#     rc > 0 (unreadable subdir) — never a silent clean (#235 a X2,
#     #235 b S4/B2). The hit:/err: sentinels are matched as path
#     text; a `:`-bearing path would false-FAIL — fail-loud by
#     design (#235 b B6).
#
# Frontmatter fields are read only BETWEEN the opening and closing ---
# (body lines cannot satisfy them) and the close search has no head
# window (#235 a S4/X4).
#
# The lint function takes the skills root as its argument so the
# fixture pins below exercise every failure path against scratch
# copies.
#
# Run: sh tests/unit/test-skills-lint.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# This checkout's absolute workspace-local path (sibling of repo/):
# matched literally so absolute references into the disposable dir
# are caught without flagging /usr/local (system prefix). Escaped for
# ERE; the fixtures below generate their reference dynamically too,
# so pattern and pins move together across checkouts (#235 b B1).
WS_LOCAL="$(cd "$REPO_ROOT/.." && pwd)/local"
WS_LOCAL_ESC="$(printf '%s' "$WS_LOCAL" | sed 's/[.\^$()*+?[|\\]/\\&/g')"
LOCAL_SHAPES="(^|[^.[:alnum:]_/-])local/|\.\./local/|\./local/|$WS_LOCAL_ESC"

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
        # frontmatter block: first line ---, closes somewhere later in
        # the file (no head window); fields are read only inside the
        # block, so body text cannot satisfy them (#235 a S4/X4)
        head -n 1 "$_f" | grep -qxF -- '---' || \
            echo "FAIL $_name: frontmatter must open with ---"
        _close=$(awk 'NR > 1 && $0 == "---" { print NR; exit }' "$_f")
        [ -n "$_close" ] || echo "FAIL $_name: frontmatter never closes"
        if [ -n "$_close" ]; then
            # name: non-empty, equals directory
            _nm=$(awk -v c="$_close" 'NR > 1 && NR < c && /^name:/ { sub(/^name:[[:space:]]*/, ""); print; exit }' "$_f")
            case "$_nm" in
                "$_name") ;;
                *) echo "FAIL $_name: name '$_nm' != directory '$_name'" ;;
            esac
            # description: non-empty, single line, <= 400 bytes
            _desc=$(awk -v c="$_close" 'NR > 1 && NR < c && /^description:/ { sub(/^description:[[:space:]]*/, ""); print; exit }' "$_f")
            [ -n "$_desc" ] || echo "FAIL $_name: empty or missing description"
            if [ -n "$_desc" ]; then
                _dlen=$(printf '%s' "$_desc" | wc -c | tr -d ' ')
                [ "$_dlen" -gt 400 ] && \
                    echo "FAIL $_name: description $_dlen bytes > 400"
            fi
        fi
        # no workspace local/ references (disposable dir next to
        # repo/): shapes documented in the header. Per-file grep so a
        # symlink operand reliably reports rc 2 (grep -r skips
        # dir-internal symlinks entirely). BOTH stages must be loud:
        # find rc > 0 (unreadable subdir -- its entries are invisible
        # to the scan) becomes an err: sentinel too, never a silent
        # clean (#235 b S4/B2).
        _flist=$(find "$_d" \( -type f -o -type l \) -print 2>/dev/null)
        _frc=$?
        _scan=$(printf '%s\n' "$_flist" | while IFS= read -r _p; do
                  [ -n "$_p" ] || continue
                  grep -qE "$LOCAL_SHAPES" "$_p" 2>/dev/null
                  _rc=$?
                  [ "$_rc" -eq 0 ] && printf 'hit:%s\n' "$_p"
                  [ "$_rc" -gt 1 ] && printf 'err:%s\n' "$_p"
              done)
        [ "$_frc" -eq 0 ] || _scan="$_scan
err:find-rc=$_frc $_d"
        case "$_scan" in
            *hit:*) echo "FAIL $_name: references local/ (disposable workspace)" ;;
        esac
        case "$_scan" in
            *err:*) echo "FAIL $_name: local/ scan errored (unreadable path)" ;;
        esac
    done
}

# --- fixture pins: the lint must discriminate (L4) ---------------------
# A broken skill is silently skipped by the loader -- if this lint
# cannot tell broken from valid, it pins nothing. Pins run against a
# scratch copy BEFORE the real-tree check and the summary gate; every
# FAIL branch of lint_skills has a fixture that executes it (#235 a
# S2: four branches used to have none).

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK:?}" "$TMP"' EXIT

mkdir -p "$WORK/skills/opk-good-skill" "$WORK/skills/opk-no-desc" \
         "$WORK/skills/opk-wrong-name" "$WORK/skills/opk-local-ref" \
         "$WORK/skills/opk-no-skill-md" "$WORK/skills/no-prefix" \
         "$WORK/skills/opk-broken-open" "$WORK/skills/opk-unclosed" \
         "$WORK/skills/opk-long-desc" "$WORK/skills/opk-legit-paths" \
         "$WORK/skills/opk-body-field" "$WORK/skills/opk-scan-err" \
         "$WORK/skills/opk-dot-local" "$WORK/skills/opk-abs-local" \
         "$WORK/skills/opk-find-err/sub"
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
See local/legacy-2026-10/restructure-docs and ../local/notes.md.
EOF
echo "not a skill" > "$WORK/skills/opk-no-skill-md/note.txt"
cat > "$WORK/skills/no-prefix/SKILL.md" <<'EOF'
---
name: no-prefix
description: Fixture that lacks the house namespace prefix.
---
Body.
EOF
cat > "$WORK/skills/opk-broken-open/SKILL.md" <<'EOF'
name: opk-broken-open
description: Fixture whose frontmatter does not open with ---.
---
Body.
EOF
cat > "$WORK/skills/opk-unclosed/SKILL.md" <<'EOF'
---
name: opk-unclosed
description: Fixture whose frontmatter never closes.
Body.
EOF
LONG_DESC="$(printf 'd%.0s' $(seq 1 401))"
cat > "$WORK/skills/opk-long-desc/SKILL.md" <<EOF
---
name: opk-long-desc
description: $LONG_DESC
---
Body.
EOF
cat > "$WORK/skills/opk-legit-paths/SKILL.md" <<'EOF'
---
name: opk-legit-paths
description: Fixture naming system and XDG local paths that stay legal.
---
Deploys to /usr/local/lib/opencode-permissions-kit/ and reads
~/.local/share/opencode — neither is the disposable workspace.
Repo-internal segments like tests/fixtures/local/demo resolve inside
the repo, not into the workspace — unflagged by design (#235 b B1).
EOF
cat > "$WORK/skills/opk-body-field/SKILL.md" <<'EOF'
---
name: opk-body-field
---
The shape this file must have, documented in the body:

name: anything
description: max 400 bytes
EOF
cat > "$WORK/skills/opk-scan-err/SKILL.md" <<'EOF'
---
name: opk-scan-err
description: Fixture with an unreadable path in its file scan.
---
Body.
EOF
ln -s /nonexistent-target-for-skills-lint "$WORK/skills/opk-scan-err/dangling"
cat > "$WORK/skills/opk-dot-local/SKILL.md" <<'EOF'
---
name: opk-dot-local
description: Fixture referencing the workspace via dot-slash shapes.
---
See ./local/notes.md and .././local/scratch — both resolve into the
disposable workspace (#235 b B1).
EOF
{
    printf -- '---\nname: opk-abs-local\ndescription: %s\n---\n' \
        "Fixture using the checkout-absolute workspace-local path."
    printf 'Archive at %s/scratch — the disposable workspace.\n' "$WS_LOCAL"
} > "$WORK/skills/opk-abs-local/SKILL.md"
# find-stage error: valid frontmatter, but the unreadable subdir makes
# find itself fail (rc > 0) with its entries invisible to the scan --
# only the err sentinel may report that (#235 b S4/B2). Root reads
# through mode 000, so the pin below is uid-guarded (L4:
# environment-dependent pins are marked).
cat > "$WORK/skills/opk-find-err/SKILL.md" <<'EOF'
---
name: opk-find-err
description: Fixture whose scan dies inside an unreadable subdir.
---
Body.
EOF
chmod 000 "$WORK/skills/opk-find-err/sub"

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
    *"FAIL opk-body-field: empty or missing description"*) echo "  pin ok: body description: line does not satisfy the check" ;;
    *) echo "  PIN BROKEN: body-field extraction leak (X4)" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-wrong-name"*) echo "  pin ok: name mismatch caught" ;;
    *) echo "  PIN BROKEN: name mismatch not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-local-ref"*) echo "  pin ok: workspace local/ reference caught" ;;
    *) echo "  PIN BROKEN: workspace local/ reference not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-no-skill-md"*) echo "  pin ok: missing SKILL.md caught" ;;
    *) echo "  PIN BROKEN: missing SKILL.md not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-broken-open: frontmatter must open"*) echo "  pin ok: missing opening --- caught" ;;
    *) echo "  PIN BROKEN: missing opening --- not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-unclosed: frontmatter never closes"*) echo "  pin ok: unclosed frontmatter caught" ;;
    *) echo "  PIN BROKEN: unclosed frontmatter not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-long-desc: description 401 bytes > 400"*) echo "  pin ok: oversized description caught (bytes)" ;;
    *) echo "  PIN BROKEN: oversized description not caught" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-scan-err: local/ scan errored"*) echo "  pin ok: scan error is a FAIL, not a clean" ;;
    *) echo "  PIN BROKEN: scan error silently clean" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-scan-err: references local/"*)
        echo "  PIN BROKEN: scan-err fixture also trips the hit branch (b S3)" >> "$TMP" ;;
    *) echo "  pin ok: scan-err fixture exercises the err path alone" ;;
esac
case "$_out" in
    *"FAIL opk-dot-local: references local/"*) echo "  pin ok: dot-slash workspace refs caught" ;;
    *) echo "  PIN BROKEN: ./local/ reference not caught (b B1)" >> "$TMP" ;;
esac
case "$_out" in
    *"FAIL opk-abs-local: references local/"*) echo "  pin ok: absolute workspace-local ref caught" ;;
    *) echo "  PIN BROKEN: absolute workspace-local reference not caught (b B1)" >> "$TMP" ;;
esac
if [ "$(id -u)" -eq 0 ]; then
    echo "  pin skipped: find-error needs a non-root uid (root reads through 000)"
else
    case "$_out" in
        *"FAIL opk-find-err: local/ scan errored"*) echo "  pin ok: find-stage error is a FAIL, not a clean" ;;
        *) echo "  PIN BROKEN: find error silently clean (b S4/B2)" >> "$TMP" ;;
    esac
fi
case "$_out" in
    *"FAIL opk-legit-paths"*) echo "  PIN BROKEN: legit /usr/local or ~/.local path flagged" >> "$TMP" ;;
    *) echo "  pin ok: system/XDG local paths not flagged" ;;
esac
case "$_out" in
    *"opk-good-skill"*) echo "  PIN BROKEN: valid fixture flagged" >> "$TMP" ;;
    *) echo "  pin ok: valid fixture passes clean" ;;
esac
_out2=$(lint_skills "$WORK/skills-root-absent")
case "$_out2" in
    *"FAIL skills root missing"*) echo "  pin ok: missing skills root caught" ;;
    *) echo "  PIN BROKEN: missing skills root not caught" >> "$TMP" ;;
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
