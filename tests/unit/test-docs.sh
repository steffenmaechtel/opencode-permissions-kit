#!/bin/sh
# test-docs.sh -- documentation link checker (no external dependencies)
#
# Fails when any Markdown file under docs/, .agents/, plus README.md,
# CONTRIBUTING.md and AGENTS.md, contains a broken relative link or a
# dangling in-page anchor. HTTP(S)/mailto links are skipped (no network
# access).
#
# Run: sh tests/unit/test-docs.sh

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT INT TERM

# GitHub anchor normalization: lowercase; remove anything that is not a
# letter, number, space, or hyphen; spaces -> hyphens; trim edge hyphens.
github_anchor() {
    printf '%s\n' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | tr -d "!\"#\$%&'()*+,./:;<=>?@[\\]^_\`{|}~" \
        | sed -e 's/[[:space:]][[:space:]]*/-/g' -e 's/^-//' -e 's/-$//'
}

# Strip fenced code blocks so links inside them are ignored.
strip_fences() {
    awk '/^```/ { infence = !infence; next } !infence { print }'
}

# headings of a file -> normalized anchors
file_anchors() {
    strip_fences < "$1" | grep -E '^#{1,6} ' | sed -E 's/^#{1,6} //'
}

# Frozen-history exemption (structure wave 2026-10): immutable review
# snapshots and archived records may reference paths that later moved —
# history is not rewritten for link hygiene. Living docs (resolutions,
# READMEs, records, user docs) must stay fully linked.
is_frozen() {
    case "$1" in
        internal/reviews/*/pr-*/review-*.md) return 0 ;;
        internal/records/_archive/*) return 0 ;;
    esac
    return 1
}

check_file() {
    f="$1"
    is_frozen "$f" && return 0
    strip_fences < "$f" | grep -oE '\]\([^)]+\)' | sed -e 's/^](//' -e 's/)$//' | while IFS= read -r target; do
        # strip optional link title after the path
        target="${target%% *}"
        case "$target" in
            http://*|https://*|mailto:*|tel:*) continue ;;
        esac

        fragment=""
        case "$target" in
            *\#*) fragment="${target#*#}"; path="${target%%#*}" ;;
            *)    path="$target" ;;
        esac

        if [ -z "$path" ]; then
            base="$f"
        else
            case "$path" in
                /*) base="${path#/}" ;;
                *)  base="$(dirname "$f")/$path" ;;
            esac
            if [ ! -e "$base" ]; then
                echo "FAIL $f -> $target (file missing)" >> "$TMP"
                continue
            fi
            if [ -d "$base" ]; then
                # review case folders link to the listing itself: lint
                # forbids any extra file inside a case (no README.md can
                # ever exist there)
                case "$base" in
                    internal/reviews/[0-9]/[0-9]/[0-9]/[0-9]/pr-[0-9][0-9][0-9][0-9][0-9]) continue ;;
                esac
                # directory link: GitHub renders its README.md
                if [ ! -e "$base/README.md" ]; then
                    echo "FAIL $f -> $target (directory has no README.md)" >> "$TMP"
                fi
                continue
            fi
        fi

        if [ -n "$fragment" ]; then
            want="$(github_anchor "$fragment")"
            found=0
            while IFS= read -r h; do
                [ -n "$h" ] || continue
                if [ "$(github_anchor "$h")" = "$want" ]; then
                    found=1
                    break
                fi
            done <<EOF
$(file_anchors "$base")
EOF
            if [ "$found" -ne 1 ]; then
                echo "FAIL $f -> $target (anchor '##$want' not found)" >> "$TMP"
            fi
        fi
    done
}

for f in README.md CONTRIBUTING.md AGENTS.md; do
    [ -e "$f" ] || continue
    check_file "$f"
done
# Docs scope (structure wave 2026-10): user docs stay under docs/, internal
# areas live at agent/ and internal/ (process/records/reviews/reviews-meta),
# agent skills at .agents/skills/ (issue #178).
for dir in docs agent internal .agents; do
    find "$dir" -name '*.md' -type f
done | sort | while IFS= read -r f; do
    check_file "$f"
done

# Records status consistency (structure wave 2026-10, PR 3): every
# internal/records/*.md carries a "> Status: **WORD**" line (corpus
# vocabulary IMPLEMENTED | CURRENT | SUPERSEDED) and the records index
# README shows the same word in that record's table row.
records_status_check() {
    for f in internal/records/*.md; do
        case "$f" in */README.md) continue ;; esac
        base=$(basename "$f")
        word=$(sed -n 's/^> Status: \*\*\([A-Z][A-Z]*\).*/\1/p' "$f" | head -n 1)
        if [ -z "$word" ]; then
            echo "FAIL $base: no '> Status: **WORD**' line" >> "$TMP"
            continue
        fi
        case "$word" in
            IMPLEMENTED|CURRENT|SUPERSEDED) ;;
            *) echo "FAIL $base: status word '$word' outside the vocabulary" >> "$TMP" ;;
        esac
        row=$(grep -F "]($base)" internal/records/README.md)
        if [ -z "$row" ]; then
            echo "FAIL $base: no records/README index row" >> "$TMP"
        elif ! printf '%s\n' "$row" | grep -Fq "| $word |"; then
            echo "FAIL $base: file says $word, README row differs" >> "$TMP"
        fi
    done
}
records_status_check

# --- F36: cli.md's install flag table tracks the parser (#211 a F36) --------------
# Claim-drift guard: every flag install.sh's parse_args accepts must
# appear in docs/reference/cli.md (the table F23 filled). Sabotage:
# delete a row or add a parser flag — this goes red.
# #211 b W28: tripwire — a drifted parse_args anchor must not silently
# iterate zero flags and pass.
# #211 b W30: reverse direction — every flag documented in cli.md's
# install table must exist in the parser. The original one-directional
# pin shipped W2 exactly this way: a documented `-y` the parser
# rejected was invisible to it.
_cli_md="$REPO_ROOT/docs/reference/cli.md"
_f36_flags="$(sed -n '/^parse_args()/,/^}/p' "$REPO_ROOT/files/install.sh" \
    | grep -oE '\-\-[a-z0-9-]+' | sort -u)"
if [ -z "$_f36_flags" ]; then
    echo "FAIL cli.md: parse_args extraction empty — anchor drift? (#211 b W28)" >> "$TMP"
fi
for _f36_flag in $_f36_flags; do
    if ! grep -qF -e "$_f36_flag" "$_cli_md"; then
        echo "FAIL cli.md: install flag '$_f36_flag' missing from the reference" >> "$TMP"
    fi
done
# Reverse: the install table sits under '## install.sh' (## section,
# table rows `| \`--flag\`, \`-y\` | ...`).
_f36_docflags="$(sed -n '/^## install.sh/,/^## /p' "$_cli_md" \
    | grep '^| ' | grep -v '^| Flag' \
    | sed -n 's/^| \([^|]*\) |.*/\1/p' | tr -d '`,' | tr -s ' ' '\n' | grep -E '^-.-?' | sort -u)"
# Tripwire (#211 c W4 — the W28 class on the reverse direction): a
# drifted '## install.sh' heading must not silently iterate zero flags
# and pass.
if [ -z "$_f36_docflags" ]; then
    echo "FAIL cli.md: install-table extraction empty — '## install.sh' anchor drift? (#211 c W4)" >> "$TMP"
fi
for _f36_df in $_f36_docflags; do
    case "$_f36_df" in
        --*)
            printf '%s\n' "$_f36_flags" | grep -qxF -- "$_f36_df" \
                || echo "FAIL cli.md: documented install flag '$_f36_df' not in the parser (#211 b W30)" >> "$TMP"
            ;;
        -?)
            sed -n '/^parse_args()/,/^}/p' "$REPO_ROOT/files/install.sh" \
                | grep -qF -- "|$_f36_df)" \
                || echo "FAIL cli.md: documented alias '$_f36_df' not in the parser (#211 b W30)" >> "$TMP"
            ;;
    esac
done

# --- a W1 (pr-00256): ddev-integration root-file types track the code -------
# matcher (claim-drift guard, the W1 rename class): every arm of the
# root-file case in ddev-handover.sh must appear backticked in the docs
# page. pr-00263 a F18: the extraction collects ALL arms of that case
# (the old head -n 1 let a future second arm escape direction A).
# Sabotage: rename `shopware6` to `shopware` in the docs — this goes red.
_w1_doc="$REPO_ROOT/docs/concepts/ddev-integration.md"
_w1_lib="$REPO_ROOT/files/opencode-permissions-kit-lib/sh/ddev-handover.sh"
_w1_types="$(awk '/^[[:space:]]*codeigniter\|/{f=1}
f {
    if ($0 ~ /^[[:space:]]*[a-z0-9|]+\)[[:space:]]*$/) {
        line=$0; gsub(/[[:space:]]|\)/, "", line); printf "%s ", line
    }
    if ($0 ~ /;;/) exit
}' "$_w1_lib" | tr '|' ' ')"
if [ -z "$_w1_types" ]; then
    echo "FAIL ddev-integration.md: root-file matcher extraction empty — anchor drift? (#256 a W1)" >> "$TMP"
fi
for _w1_t in codeigniter $_w1_types; do
    grep -qF "\`$_w1_t\`" "$_w1_doc" \
        || echo "FAIL ddev-integration.md: root-file type '$_w1_t' missing from the docs (#256 a W1)" >> "$TMP"
done
# #256 b B2: reverse direction — every type the docs paragraph lists must
# exist in the code matcher (the addition direction of the #256 a W1 class, the
# #211 b W30 shape). Wildcard forms count too: the matcher arms are literal,
# so a `drupal*`-style token in the root-file paragraph is drift by
# definition. Tripwire: a drifted paragraph anchor must not silently
# iterate zero types.
_w1_doctypes="$(grep -o '\*\*Root-file types ([^)]*' "$_w1_doc" | grep -oE '`[a-z0-9*]+`' | tr -d '`')"
if [ -z "$_w1_doctypes" ]; then
    echo "FAIL ddev-integration.md: docs root-file-type extraction empty — anchor drift? (#256 b B2)" >> "$TMP"
fi
for _w1_dt in $_w1_doctypes; do
    case " codeigniter $_w1_types " in
        *" $_w1_dt "*) ;;
        *) echo "FAIL ddev-integration.md: docs root-file type '$_w1_dt' not in the code matcher (#256 b B2)" >> "$TMP" ;;
    esac
done

# --- a W2 (pr-00256): security-model keeps the dev-owned flag-write TOCTOU ---
# disclosure (residual-gaps honesty guard). Sabotage: delete the bullet —
# this goes red.
grep -q 'flag-write TOCTOU' "$REPO_ROOT/docs/concepts/security-model.md" \
    || echo "FAIL security-model.md: dev-owned flag-write TOCTOU disclosure missing (#256 a W2)" >> "$TMP"

# --- a W3 (pr-00256): cli.md keeps the advisories exception ------------------
# The missing-library claim must keep its exception clause (status.sh's
# advisories row names the skipped checks, not the file). Sabotage: shorten
# the sentence back to the blanket claim — this goes red.
grep -q 'skipped security checks instead' "$REPO_ROOT/docs/reference/cli.md" \
    || echo "FAIL cli.md: advisories exception clause missing from the missing-library claim (#256 a W3)" >> "$TMP"

# --- a W5 (pr-00256): getting-started's agent-resources Enter default -------
# tracks the ui_menu default letter in install.sh (claim-drift guard, both
# directions: flipping the menu default or the docs word goes red).
# #256 b B1: the capture is [a-z], NOT the mapped set — an out-of-vocabulary
# default letter must land in the unmapped guard below with the right
# message; with [mcs] the sed stopped matching and the guard was dead code
# (the drift misfired the anchor-drift tripwire instead).
_w5_def="$(sed -n 's/.*ui_menu "Bring the developer.s agent resources over?" "\([a-z]\)".*/\1/p' "$REPO_ROOT/files/install.sh" | head -n 1)"
if [ -z "$_w5_def" ]; then
    echo "FAIL getting-started.md: agent-resources menu default extraction empty — anchor drift? (#256 a W5)" >> "$TMP"
fi
_w5_word=""
case "$_w5_def" in
    m) _w5_word="move" ;;
    c) _w5_word="copy" ;;
    s) _w5_word="skip" ;;
esac
if [ -n "$_w5_def" ] && [ -z "$_w5_word" ]; then
    echo "FAIL getting-started.md: unmapped agent-resources menu default '$_w5_def' (#256 a W5)" >> "$TMP"
fi
if [ -n "$_w5_word" ]; then
    grep -qF "defaults to **$_w5_word**" "$REPO_ROOT/docs/getting-started.md" \
        || echo "FAIL getting-started.md: agent-resources Enter default does not track install.sh ('$_w5_def' => $_w5_word) (#256 a W5)" >> "$TMP"
fi

# --- pr-00263 a F5 (c C8): getting-started's python3 prerequisite must
# state the installer's HARD gate — both _py3_health_probe arms exit 1 —
# not install-time survival (claim-drift guard, both directions: the abort
# claim disappearing reds, the old "still applies without it" survival
# claim returning reds; code-side anchors trip on probe rewording).
if ! grep -q 'installer aborts if `python3` is' "$REPO_ROOT/docs/getting-started.md"; then
    echo "FAIL getting-started.md: python3 prerequisite lost the abort claim (#263 a F5)" >> "$TMP"
fi
if grep -q 'baseline still applies without it' "$REPO_ROOT/docs/getting-started.md"; then
    echo "FAIL getting-started.md: python3 prerequisite claims install-time survival — the installer aborts (#263 a F5)" >> "$TMP"
fi
if ! grep -q 'python3 is required but not installed' "$REPO_ROOT/files/install.sh" \
   || ! grep -q 'python3 is present but broken' "$REPO_ROOT/files/install.sh"; then
    echo "FAIL install.sh: python3 probe abort messages drifted — docs claim and code disagree (#263 a F5)" >> "$TMP"
fi

# --- pr-00263 docs one-liners (#268-#273, maintainer-commissioned) ---------------
# Each fix is one sentence (the #252 brevity policy holds); every new
# anchor is pinned present, every removed lie pinned absent.
grep -q 'an existing `daemon.json` is overwritten' "$REPO_ROOT/docs/troubleshooting.md" \
    || echo "FAIL troubleshooting.md: daemon.json tee overwrite truth missing (#268 b B3)" >> "$TMP"
grep -q 'gets the key merged in' "$REPO_ROOT/docs/troubleshooting.md" \
    && echo "FAIL troubleshooting.md: the merge-promise lie is back (#268 b B3)" >> "$TMP"
grep -q 'pre-arranged group/world-writable paths survive' "$REPO_ROOT/docs/reference/cli.md" \
    || echo "FAIL cli.md: handover residual caveat missing (#269 c C4)" >> "$TMP"
grep -q 'every path component is re-checked' "$REPO_ROOT/docs/reference/cli.md" \
    && echo "FAIL cli.md: the per-component claim is back (#269 c C3)" >> "$TMP"
grep -q 'opencode.ai/v2/install' "$REPO_ROOT/docs/concepts/security-model.md" \
    || echo "FAIL security-model.md: trust list lost the root-run sources (#270 c C5)" >> "$TMP"
grep -q -- '--skip-ddev-migration' "$REPO_ROOT/docs/getting-started.md" \
    || echo "FAIL getting-started.md: export conditions missing (#271 c C6)" >> "$TMP"
grep -q 'databases were exported' "$REPO_ROOT/docs/getting-started.md" \
    && echo "FAIL getting-started.md: unconditional export claim is back (#271 c C6)" >> "$TMP"
grep -q 'only the project config' "$REPO_ROOT/docs/how-to/container-tools.md" \
    || echo "FAIL container-tools.md: probe-fallback caveat missing (#272 b B5)" >> "$TMP"
for _d1p in docs/troubleshooting.md docs/concepts/ddev-integration.md; do
    grep -q '127.0.0.1 <project>.<tld>' "$REPO_ROOT/$_d1p" \
        || echo "FAIL $_d1p: hosts mapping form missing (#272 b B6)" >> "$TMP"
done
grep -q 'never overwritten by install or' "$REPO_ROOT/docs/reference/files.md" \
    || echo "FAIL files.md: never-overwritten scope missing (#273 c C9)" >> "$TMP"
grep -q 'checked helper families' "$REPO_ROOT/docs/reference/cli.md" \
    || echo "FAIL cli.md: missing-library scope missing (#273 c C10)" >> "$TMP"
grep -q 'pre-install exception: full mode exits 0' "$REPO_ROOT/docs/reference/cli.md" \
    || echo "FAIL cli.md: pre-install exit-code exception missing (#273 c C11)" >> "$TMP"

if [ -s "$TMP" ]; then
    echo "docs link check: FAILED"
    cat "$TMP"
    exit 1
fi

echo "docs link check: OK"
