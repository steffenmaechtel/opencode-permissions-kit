#!/bin/sh
# test-docs.sh -- documentation link checker (no external dependencies)
#
# Fails when any Markdown file under docs/, .agents/, plus README.md,
# CONTRIBUTING.md and AGENTS.md, contains a broken relative link or a
# dangling in-page anchor. HTTP(S)/mailto links are skipped (no network
# access).
#
# Run: sh tests/unit/test-docs.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

# Shared harness (issue #417 adoption, scoped): this suite is a FAIL-
# rows checker, not a pass/fail-row suite -- it has no local rows or
# counters to migrate, so adoption here covers what it DOES duplicate:
# extract_func for the parse_args extraction legs and the work
# registry (issue #395) for the scratch receiver (the local trap is
# gone; a local trap would disarm the harness registry). The FAIL-file
# gate and the one-line verdict output stay the suite's own.
. "$SCRIPT_DIR/lib/harness.sh"

# Loud scratch guard (#441 a B1): this suite has no set -e (its checks
# accumulate FAIL rows across legitimately failing probes), so a failed
# work_new_file left TMP empty -- every FAIL writer degraded to stderr
# noise and the [ -s "$TMP" ] gate read false: "docs link check: OK"
# with detection disabled (the master shape, silently green). Abort
# loud instead; the pin at the bottom drives this path hermetically.
TMP="$(work_new_file)" || {
    echo "docs link check: FAILED - scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}

# GitHub anchor normalization: lowercase; remove anything that is not a
# letter, number, space, or hyphen; spaces -> hyphens; trim edge hyphens.
github_anchor() {
    printf '%s\n' "$1" |
        tr '[:upper:]' '[:lower:]' |
        tr -d "!\"#\$%&'()*+,./:;<=>?@[\\]^_\`{|}~" |
        sed -e 's/[[:space:]][[:space:]]*/-/g' -e 's/^-//' -e 's/-$//'
}

# Strip fenced code blocks so links inside them are ignored.
strip_fences() {
    awk '/^```/ { infence = !infence; next } !infence { print }'
}

# headings of a file -> normalized anchors
file_anchors() {
    strip_fences <"$1" | grep -E '^#{1,6} ' | sed -E 's/^#{1,6} //'
}

# Frozen-history exemption (structure wave 2026-10): archived records
# may reference paths that later moved — history is not rewritten for
# link hygiene. Living docs (READMEs, records, user docs) must stay
# fully linked. (The immutable review snapshots joined the frozen
# archive at tag review-corpus, issue #290 — they no longer live in
# the tree.)
is_frozen() {
    case "$1" in
        internal/records/_archive/*) return 0 ;;
    esac
    return 1
}

check_file() {
    f="$1"
    is_frozen "$f" && return 0
    strip_fences <"$f" | grep -oE '\]\([^)]+\)' | sed -e 's/^](//' -e 's/)$//' | while IFS= read -r target; do
        # strip optional link title after the path
        target="${target%% *}"
        case "$target" in
            http://* | https://* | mailto:* | tel:*) continue ;;
        esac

        fragment=""
        case "$target" in
            *\#*)
                fragment="${target#*#}"
                path="${target%%#*}"
                ;;
            *) path="$target" ;;
        esac

        if [ -z "$path" ]; then
            base="$f"
        else
            case "$path" in
                /*) base="${path#/}" ;;
                *) base="$(dirname "$f")/$path" ;;
            esac
            if [ ! -e "$base" ]; then
                echo "FAIL $f -> $target (file missing)" >>"$TMP"
                continue
            fi
            if [ -d "$base" ]; then
                # directory link: GitHub renders its README.md
                if [ ! -e "$base/README.md" ]; then
                    echo "FAIL $f -> $target (directory has no README.md)" >>"$TMP"
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
                echo "FAIL $f -> $target (anchor '##$want' not found)" >>"$TMP"
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
# Scope-collection guard (#519, from #516 a A5 -- the same class as the
# #441 a B1 scratch guard above): the old inline `for dir ...; find ...
# done | sort | while` shape swallowed find's rc in the pipe -- a find
# death (vanished or unreadable scope dir) degraded the file list
# silently: a SINGLE dead dir left the survivors' files flowing
# (check_file green over missing coverage), all four dead read as
# "docs link check: OK" with detection disabled. The collector guards
# both legs (per-dir rc) and the empty-set leg (four checked-in scope
# dirs hold hundreds of .md files -- zero means the scan never ran);
# the guard arms at the bottom drive the death and empty paths
# hermetically.
_docs_collect() { # $@ = scope dirs -> file list on stdout; loud on death/empty
    _dc_tmp="$(work_new_file)" || return 1
    for _dc_dir; do
        find "$_dc_dir" -name '*.md' -type f >>"$_dc_tmp" || {
            echo "docs link check: scope scan died on '$_dc_dir' (rc=$?) -- link check output unreliable (#519)" >&2
            return 1
        }
    done
    if [ ! -s "$_dc_tmp" ]; then
        echo "docs link check: empty scope scan -- link check output unreliable (#519)" >&2
        return 1
    fi
    cat "$_dc_tmp"
}
_docs_list="$(work_new_file)" || {
    echo "docs link check: FAILED - scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
if ! _docs_collect docs agent internal .agents >"$_docs_list"; then
    echo "docs link check: FAILED - scope collection unreliable (#519)" >&2
    exit 1
fi
sort "$_docs_list" | while IFS= read -r f; do
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
            echo "FAIL $base: no '> Status: **WORD**' line" >>"$TMP"
            continue
        fi
        case "$word" in
            IMPLEMENTED | CURRENT | SUPERSEDED) ;;
            *) echo "FAIL $base: status word '$word' outside the vocabulary" >>"$TMP" ;;
        esac
        row=$(grep -F "]($base)" internal/records/README.md)
        if [ -z "$row" ]; then
            echo "FAIL $base: no records/README index row" >>"$TMP"
        elif ! printf '%s\n' "$row" | grep -Fq "| $word |"; then
            echo "FAIL $base: file says $word, README row differs" >>"$TMP"
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
_f36_flags="$(extract_func "$REPO_ROOT/files/install.sh" parse_args |
    grep -oE '\-\-[a-z0-9-]+' | sort -u)"
if [ -z "$_f36_flags" ]; then
    echo "FAIL cli.md: parse_args extraction empty — anchor drift? (#211 b W28)" >>"$TMP"
fi
for _f36_flag in $_f36_flags; do
    if ! grep -qF -e "$_f36_flag" "$_cli_md"; then
        echo "FAIL cli.md: install flag '$_f36_flag' missing from the reference" >>"$TMP"
    fi
done
# Reverse: the install table sits under '## install.sh' (## section,
# table rows `| \`--flag\`, \`-y\` | ...`).
_f36_docflags="$(sed -n '/^## install.sh/,/^## /p' "$_cli_md" |
    grep '^| ' | grep -v '^| Flag' |
    sed -n 's/^| \([^|]*\) |.*/\1/p' | tr -d '`,' | tr -s ' ' '\n' | grep -E '^-.-?' | sort -u)"
# Tripwire (#211 c W4 — the W28 class on the reverse direction): a
# drifted '## install.sh' heading must not silently iterate zero flags
# and pass.
if [ -z "$_f36_docflags" ]; then
    echo "FAIL cli.md: install-table extraction empty — '## install.sh' anchor drift? (#211 c W4)" >>"$TMP"
fi
for _f36_df in $_f36_docflags; do
    case "$_f36_df" in
        --*)
            printf '%s\n' "$_f36_flags" | grep -qxF -- "$_f36_df" ||
                echo "FAIL cli.md: documented install flag '$_f36_df' not in the parser (#211 b W30)" >>"$TMP"
            ;;
        -?)
            extract_func "$REPO_ROOT/files/install.sh" parse_args |
                grep -qF -- "| $_f36_df)" ||
                echo "FAIL cli.md: documented alias '$_f36_df' not in the parser (#211 b W30)" >>"$TMP"
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
_w1_types="$(awk '/^[[:space:]]*codeigniter[[:space:]]*\|/{f=1}
f {
    if ($0 ~ /^[[:space:]]*[a-z0-9| ]+\)[[:space:]]*$/) {
        line=$0; gsub(/[[:space:]]|\)/, "", line); printf "%s ", line
    }
    if ($0 ~ /;;/) exit
}' "$_w1_lib" | tr '|' ' ')"
if [ -z "$_w1_types" ]; then
    echo "FAIL ddev-integration.md: root-file matcher extraction empty — anchor drift? (#256 a W1)" >>"$TMP"
fi
for _w1_t in codeigniter $_w1_types; do
    grep -qF "\`$_w1_t\`" "$_w1_doc" ||
        echo "FAIL ddev-integration.md: root-file type '$_w1_t' missing from the docs (#256 a W1)" >>"$TMP"
done
# #256 b B2: reverse direction — every type the docs paragraph lists must
# exist in the code matcher (the addition direction of the #256 a W1 class, the
# #211 b W30 shape). Wildcard forms count too: the matcher arms are literal,
# so a `drupal*`-style token in the root-file paragraph is drift by
# definition. Tripwire: a drifted paragraph anchor must not silently
# iterate zero types.
_w1_doctypes="$(grep -o '\*\*Root-file types ([^)]*' "$_w1_doc" | grep -oE '`[a-z0-9*]+`' | tr -d '`')"
if [ -z "$_w1_doctypes" ]; then
    echo "FAIL ddev-integration.md: docs root-file-type extraction empty — anchor drift? (#256 b B2)" >>"$TMP"
fi
for _w1_dt in $_w1_doctypes; do
    case " codeigniter $_w1_types " in
        *" $_w1_dt "*) ;;
        *) echo "FAIL ddev-integration.md: docs root-file type '$_w1_dt' not in the code matcher (#256 b B2)" >>"$TMP" ;;
    esac
done

# --- a W2 (pr-00256): security-model keeps the dev-owned flag-write TOCTOU ---
# disclosure (residual-gaps honesty guard). Sabotage: delete the bullet —
# this goes red.
grep -q 'flag-write TOCTOU' "$REPO_ROOT/docs/concepts/security-model.md" ||
    echo "FAIL security-model.md: dev-owned flag-write TOCTOU disclosure missing (#256 a W2)" >>"$TMP"

# --- #483 (PR #479 round a): the six snapshot-review residual findings ---
# stay disclosed, and the F11 rework names BOTH callers (the opencode-uid
# cap claim alone was the finding). One distinctive literal per entry;
# sabotage: delete any bullet -- this goes red.
# #506 round a additions: the F13 rework's deployed-default +
# global-gitconfig truth (B1/B2), the F14 socket-resolving arms (B3),
# and the guarantee bullet's env_keep exception pointer (B4).
for _i483_lit in \
    'scratch re-open windows' \
    'performs the same write as root' \
    'Git diff drivers render denied files' \
    'a default install renders them active' \
    'global gitconfig' \
    'rides env_keep' \
    'OPENCODE_PODMAN_SOCKET' \
    'env_keep exception' \
    'Agent-authored container opt-in' \
    'runs checkout code as root'; do
    grep -qF -- "$_i483_lit" "$REPO_ROOT/docs/concepts/security-model.md" ||
        echo "FAIL security-model.md: residual-gap disclosure '$_i483_lit' missing (#483)" >>"$TMP"
done
# --- #652: the post-heal git-execution residual inventory stays ---
# disclosed (agent-controlled gitdirs, nuisance arms, pre-heal context
# + complete closure) and the heal section keeps pointing at it.
# One distinctive literal per entry, including the nested sub-bullets
# (fix #689 a A2: "delete any bullet" overstated flat-bullet coverage);
# sabotage: delete any PINNED bullet -- this goes red.
for _i652_lit in \
    'Git execution in agent-controlled gitdirs' \
    'the developer works in the protected main' \
    'an **agent-owned tree as a whole**' \
    '**state created between heal runs:**' \
    '**content planted before the heal**' \
    'tracks report-only detection' \
    'Nuisance arms of the shared `.git`' \
    'closure remains a separate agent' \
    'post-heal residual inventory'; do
    grep -qF -- "$_i652_lit" "$REPO_ROOT/docs/concepts/security-model.md" ||
        echo "FAIL security-model.md: post-heal residual disclosure '$_i652_lit' missing (#652)" >>"$TMP"
done
# The F13 siblings (the class sweep carried the evasion list into the
# how-to and the glossary too) -- pinned since #506 round a A1.
grep -qF -- 'planted git diff driver' "$REPO_ROOT/docs/how-to/customize-deny-list.md" ||
    echo "FAIL customize-deny-list.md: diff-driver disclosure missing (#483/#506 a A1)" >>"$TMP"
grep -qF -- 'planted git diff drivers' "$REPO_ROOT/docs/reference/glossary.md" ||
    echo "FAIL glossary.md: diff-driver disclosure missing (#483/#506 a A1)" >>"$TMP"
# F16's contributor-side warning: bound to the SECTION (heading + the
# self-elevation claim), not to the shared 'agent-group-writable'
# vocabulary term (#506 round a A2/C2).
grep -qF -- 'Checkout scripts run as root' "$REPO_ROOT/CONTRIBUTING.md" ||
    echo "FAIL CONTRIBUTING.md: checkout-root warning section missing (#483 F16)" >>"$TMP"
grep -qF -- 'self-elevate' "$REPO_ROOT/CONTRIBUTING.md" ||
    echo "FAIL CONTRIBUTING.md: self-elevation warning missing (#506 a C2)" >>"$TMP"

# --- a W3 (pr-00256): cli.md keeps the advisories exception ------------------
# The missing-library claim must keep its exception clause (status.sh's
# advisories row names the skipped checks, not the file). Sabotage: shorten
# the sentence back to the blanket claim — this goes red.
grep -q 'skipped security checks instead' "$REPO_ROOT/docs/reference/cli.md" ||
    echo "FAIL cli.md: advisories exception clause missing from the missing-library claim (#256 a W3)" >>"$TMP"

# --- a W5 (pr-00256): getting-started's agent-resources Enter default -------
# tracks the ui_menu default letter in the installer (claim-drift guard,
# both directions: flipping the menu default or the docs word goes red).
# The menu call lives in do_deploy_phase — install-core.sh since #346
# wave 3.
# #256 b B1: the capture is [a-z], NOT the mapped set — an out-of-vocabulary
# default letter must land in the unmapped guard below with the right
# message; with [mcs] the sed stopped matching and the guard was dead code
# (the drift misfired the anchor-drift tripwire instead).
_w5_def="$(sed -n 's/.*ui_menu "Bring the developer.s agent resources over?" "\([a-z]\)".*/\1/p' "$REPO_ROOT/files/opencode-permissions-kit-lib/sh/install-core.sh" | head -n 1)"
if [ -z "$_w5_def" ]; then
    echo "FAIL getting-started.md: agent-resources menu default extraction empty — anchor drift? (#256 a W5)" >>"$TMP"
fi
_w5_word=""
case "$_w5_def" in
    m) _w5_word="move" ;;
    c) _w5_word="copy" ;;
    s) _w5_word="skip" ;;
esac
if [ -n "$_w5_def" ] && [ -z "$_w5_word" ]; then
    echo "FAIL getting-started.md: unmapped agent-resources menu default '$_w5_def' (#256 a W5)" >>"$TMP"
fi
if [ -n "$_w5_word" ]; then
    grep -qF "defaults to **$_w5_word**" "$REPO_ROOT/docs/getting-started.md" ||
        echo "FAIL getting-started.md: agent-resources Enter default does not track install.sh ('$_w5_def' => $_w5_word) (#256 a W5)" >>"$TMP"
fi

# --- pr-00263 a F5 (c C8): getting-started's python3 prerequisite must
# state the installer's HARD gate — both _py3_health_probe arms exit 1 —
# not install-time survival (claim-drift guard, both directions: the abort
# claim disappearing reds, the old "still applies without it" survival
# claim returning reds; code-side anchors trip on probe rewording).
if ! grep -q 'installer aborts if `python3` is' "$REPO_ROOT/docs/getting-started.md"; then
    echo "FAIL getting-started.md: python3 prerequisite lost the abort claim (#263 a F5)" >>"$TMP"
fi
if grep -q 'baseline still applies without it' "$REPO_ROOT/docs/getting-started.md"; then
    echo "FAIL getting-started.md: python3 prerequisite claims install-time survival — the installer aborts (#263 a F5)" >>"$TMP"
fi
if ! grep -q 'python3 is required but not installed' "$REPO_ROOT/files/install.sh" ||
    ! grep -q 'python3 is present but broken' "$REPO_ROOT/files/install.sh"; then
    echo "FAIL install.sh: python3 probe abort messages drifted — docs claim and code disagree (#263 a F5)" >>"$TMP"
fi

# --- pr-00263 docs one-liners (#268-#273, maintainer-commissioned) ---------------
# Each fix is one sentence (the #252 brevity policy holds); every new
# anchor is pinned present, every removed lie pinned absent.
grep -q 'an existing `daemon.json` is overwritten' "$REPO_ROOT/docs/troubleshooting.md" ||
    echo "FAIL troubleshooting.md: daemon.json tee overwrite truth missing (#268 b B3)" >>"$TMP"
grep -q 'gets the key merged in' "$REPO_ROOT/docs/troubleshooting.md" &&
    echo "FAIL troubleshooting.md: the merge-promise lie is back (#268 b B3)" >>"$TMP"
grep -q 'pre-arranged group/world-writable paths survive' "$REPO_ROOT/docs/reference/cli.md" ||
    echo "FAIL cli.md: handover residual caveat missing (#269 c C4)" >>"$TMP"
grep -q 'every path component is re-checked' "$REPO_ROOT/docs/reference/cli.md" &&
    echo "FAIL cli.md: the per-component claim is back (#269 c C3)" >>"$TMP"
grep -q 'opencode.ai/v2/install' "$REPO_ROOT/docs/concepts/security-model.md" ||
    echo "FAIL security-model.md: trust list lost the root-run sources (#270 c C5)" >>"$TMP"
grep -q -- '--skip-ddev-migration' "$REPO_ROOT/docs/getting-started.md" ||
    echo "FAIL getting-started.md: export conditions missing (#271 c C6)" >>"$TMP"
grep -q 'databases were exported' "$REPO_ROOT/docs/getting-started.md" &&
    echo "FAIL getting-started.md: unconditional export claim is back (#271 c C6)" >>"$TMP"
grep -q 'only the project config' "$REPO_ROOT/docs/how-to/container-tools.md" ||
    echo "FAIL container-tools.md: probe-fallback caveat missing (#272 b B5)" >>"$TMP"
for _d1p in docs/troubleshooting.md docs/concepts/ddev-integration.md; do
    grep -q '127.0.0.1 <project>.<tld>' "$REPO_ROOT/$_d1p" ||
        echo "FAIL $_d1p: hosts mapping form missing (#272 b B6)" >>"$TMP"
done
grep -q 'never overwritten by install or' "$REPO_ROOT/docs/reference/files.md" ||
    echo "FAIL files.md: never-overwritten scope missing (#273 c C9)" >>"$TMP"
grep -q 'checked helper families' "$REPO_ROOT/docs/reference/cli.md" ||
    echo "FAIL cli.md: missing-library scope missing (#273 c C10)" >>"$TMP"
grep -q 'pre-install exception: full mode exits 0' "$REPO_ROOT/docs/reference/cli.md" ||
    echo "FAIL cli.md: pre-install exit-code exception missing (#273 c C11)" >>"$TMP"

# --- #441 a B1: scratch-creation failure fails loud, not silent-green -----------
# Hermetic self-re-execution: the suite as a child process under a
# dead TMPDIR must abort rc 1 with the loud guard message above (the
# child stops at the guard, before any check -- the re-run is cheap).
# Sabotage discriminator: with the guard deleted the child exits 0 and
# prints the silent OK -- exactly the silent-green this pin forbids.
# The OPK_DOCS_B1_CHILD marker is the recursion break (#441 b D1):
# with the guard deleted -- or the sentinel dir accidentally existing
# -- the child would otherwise reach THIS pin and spawn another child
# forever (the round-a draft hang; each level is a full suite run).
if [ -z "${OPK_DOCS_B1_CHILD:-}" ]; then
    _b1_rc=0
    _b1_out="$(OPK_DOCS_B1_CHILD=1 TMPDIR="$REPO_ROOT/.no-such-tmp-opk-441" \
        sh "$SCRIPT_DIR/test-docs.sh" 2>&1)" || _b1_rc=$?
    if [ "$_b1_rc" -ne 1 ] ||
        ! printf '%s' "$_b1_out" | grep -qF 'scratch creation failed'; then
        echo "FAIL test-docs itself: dead-TMPDIR run must abort loud, not pass silently (rc=$_b1_rc out=$_b1_out) (#441 a B1)" >>"$TMP"
    fi
fi

# --- #519 guard arms: executed death paths for the scope collector -------------
# Death leg: the collector on a vanished scope dir must return nonzero
# with the guard message on stderr, observed the way a failing
# collection observes it (stdout discarded, stderr captured). Empty
# leg: an existing but empty scope dir must fail loud too -- zero
# collected files must never read as a clean check.
_dr_rc=0
_dr_err="$( (_docs_collect "$REPO_ROOT/.no-such-dir-opk-519") 2>&1 >/dev/null)" || _dr_rc=$?
if [ "$_dr_rc" -ne 0 ] && printf '%s\n' "$_dr_err" | grep -q 'scope scan died'; then
    :
else
    echo "FAIL test-docs itself: a scope-collection death must fail loud (rc=$_dr_rc err=$_dr_err) (#519)" >>"$TMP"
fi
_dr_empty="$(work_new)"
_dr_rc=0
_dr_err="$( (_docs_collect "$_dr_empty") 2>&1 >/dev/null)" || _dr_rc=$?
if [ "$_dr_rc" -ne 0 ] && printf '%s\n' "$_dr_err" | grep -q 'empty scope scan'; then
    :
else
    echo "FAIL test-docs itself: an empty scope scan must fail loud (rc=$_dr_rc err=$_dr_err) (#519)" >>"$TMP"
fi

# --- #542: indented fence pairing in agent/*.md rule files --------------------
# The #526 class: a fix wave deleted an indented fence's OPENING
# line inside a rule bullet; every suite stayed green because all
# fence-aware tooling (strip_fences above, the rules-audit unit
# parser) anchors at column 0 and never sees an indented fence. This
# pin is the structural version of the manual render/balance check
# (agent/conventions.md "Rule-file markdown structure"): every fence
# marker line -- column 0 or indented -- must strictly pair per file.
# Strict pairing, not a CommonMark renderer emulation: a stray marker
# must red even when a later block's fences would "absorb" it into a
# giant mis-paired fence (the #526 damage rendered as one huge code
# block -- a toggle that treats an info-string marker inside an open
# fence as content silently re-pairs the stray and stays green, the
# exact blindness this pin exists to remove). Corpus conventions the
# invariant encodes: openers may carry info strings, closers are
# bare, and no fence-marker-as-content inside a fence -- showing a
# fence inside a fence needs a ~~~ or 4+-backtick block instead
# (none exist in agent/ today). Simplification: only three-backtick
# markers, the closing fence's indent is not compared to the opener's.
_fence_pairing_rows() { # $@ = md files -> FAIL rows on stdout, loud on death
    [ $# -gt 0 ] || {
        echo "fence pairing: empty agent/*.md scope -- the check never ran (#542)" >&2
        return 1
    }
    for _fp_f; do
        [ -r "$_fp_f" ] || {
            echo "fence pairing: cannot read '$_fp_f' -- scope glob or tree broken (#542)" >&2
            return 1
        }
        _fp_rc=0
        awk -v f="$_fp_f" '
            /^[[:space:]]*```/ {
                if (!open) {
                    open = 1
                    oline = NR
                } else {
                    open = 0
                }
            }
            END {
                if (open)
                    printf "FAIL %s: fence marker at line %d has no partner (#542)\n", f, oline
            }
        ' "$_fp_f" || _fp_rc=$?
        if [ "$_fp_rc" -ne 0 ]; then
            echo "fence pairing: awk died on '$_fp_f' (rc=$_fp_rc) -- output unreliable (#542)" >&2
            return 1
        fi
    done
}
_fp_rows="$(work_new_file)" || {
    echo "docs link check: FAILED - scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
if ! _fence_pairing_rows agent/*.md >"$_fp_rows"; then
    echo "docs link check: FAILED - fence pairing scan unreliable (#542)" >&2
    exit 1
fi
cat "$_fp_rows" >>"$TMP"

# Discrimination arms (a pin that cannot red is decoration): the
# exact #526 shape reds, balanced indented and col-0 fences stay
# clean, and an empty scope aborts loud. Fixture markers use the
# corpus conventions only (openers may carry info strings, closers
# bare) -- no marker-as-content shape exists in the corpus, so none
# is fixture-tested; the strict-vs-absorbing-stray distinction rides
# on the wired real-tree scan over agent/*.md.
_fp_dir="$(work_new)" || {
    echo "docs link check: FAILED - scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
printf '%s\n' \
    '- rule bullet with a fence whose opening line got deleted' \
    '  fence body line' \
    '  ```' \
    '- trailing bullet' >"$_fp_dir/unbalanced.md"
_fp_arm="$(_fence_pairing_rows "$_fp_dir/unbalanced.md")"
case "$_fp_arm" in
    *"FAIL $_fp_dir/unbalanced.md: fence marker at line 3"*) ;;
    *)
        echo "FAIL test-docs itself: the #526 deleted-opening fixture must red (got: $_fp_arm) (#542)" >>"$TMP"
        ;;
esac
printf '%s\n' \
    '- bullet with a balanced indented fence' \
    '  ```sh' \
    '  run $(true)' \
    '  ```' \
    '' \
    '```markdown' \
    'col-0 pair content' \
    '```' >"$_fp_dir/balanced.md"
_fp_arm="$(_fence_pairing_rows "$_fp_dir/balanced.md")"
if [ -n "$_fp_arm" ]; then
    echo "FAIL test-docs itself: balanced fixtures must stay clean (got: $_fp_arm) (#542)" >>"$TMP"
fi
_fp_rc=0
_fp_err="$(_fence_pairing_rows 2>&1 >/dev/null)" || _fp_rc=$?
if [ "$_fp_rc" -ne 0 ] && printf '%s\n' "$_fp_err" | grep -q 'empty agent'; then
    :
else
    echo "FAIL test-docs itself: an empty fence scope must fail loud (rc=$_fp_rc err=$_fp_err) (#542)" >>"$TMP"
fi

if [ -s "$TMP" ]; then
    echo "docs link check: FAILED"
    cat "$TMP"
    exit 1
fi

echo "docs link check: OK"
