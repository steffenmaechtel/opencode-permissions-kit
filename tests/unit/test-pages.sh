#!/bin/sh
# Unit tests for the GitHub Pages entry site (short one-liner URLs):
#   1. the deploy workflow exists and pins the served script to the
#      `stable` channel (the public entry must never serve dev state),
#      copies install.sh (update.sh is deliberately NOT served — issue
#      #492: `opk update` is the regular update path, streamed updates
#      address the raw refs, see docs/advanced/streamed-install-update.md),
#      and wires the Jekyll build + Pages deployment;
#   2. the landing assets exist (index.md with layout front matter,
#      _config.yml pinning the Cayman theme) and carry the entry URL;
#   3. the stable-channel docs (README, getting-started) use the entry
#      URL, and the advanced streamed paths keep the ref-addressed raw
#      recipes (a channel-fixed entry cannot self-pin a ref);
#   4. issue #492's removal ask: the regular docs carry no curl
#      one-liners, docs/advanced/ carries no baked-in checksums (they
#      would go stale with every branch push — verify manually there);
#   5. issue #492 wave 2: the verified-install variant — marker blocks
#      with exactly one literal hash in README/getting-started, the
#      deploy-time placeholder on the landing page, the render step in
#      the workflow, and the drift pin (hash matches stable or tree —
#      the two sanctioned states; structural only where no stable ref
#      exists, e.g. CI clones).
#   6. issue #721: the agent-notes pointer block — README.md, the
#      landing page and the how-to carry ONE byte-identical marker
#      block naming the deployed host-notes path.
#
# Run: sh tests/unit/test-pages.sh
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WF="$REPO/.github/workflows/pages.yml"
INDEX="$REPO/.github/pages/index.md"
CONFIG="$REPO/.github/pages/_config.yml"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$REPO/tests/unit/lib/harness.sh"

ENTRY_INSTALL="https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh"
ENTRY_UPDATE="https://steffenmaechtel.github.io/opencode-permissions-kit/update.sh"

# --- 1. deploy workflow ---------------------------------------------------

[ -f "$WF" ] && pass "pages.yml exists" || fail "pages.yml missing"

grep -qF 'branches: [stable]' "$WF" &&
    pass "workflow triggers on stable pushes (release signal)" ||
    fail "workflow does not trigger on stable pushes"
grep -qF 'workflow_dispatch:' "$WF" &&
    pass "workflow is manually dispatchable" ||
    fail "workflow lacks workflow_dispatch"

# The load-bearing pin: scripts ALWAYS come from the stable channel.
grep -qF 'ref: stable' "$WF" &&
    pass "served scripts pinned to the stable ref" ||
    fail "scripts not pinned to stable — entry could serve dev state"
grep -qF 'cp stable/files/install.sh site/' "$WF" &&
    pass "install.sh copied from the stable checkout" ||
    fail "install.sh copy from stable missing"
# update.sh is deliberately no longer served (#492). Absence pin: the
# grep matches the actual cp line, so a commented-out copy still fails.
if grep -qF 'cp stable/files/opencode-permissions-kit-lib/management/update.sh site/' "$WF"; then
    fail "pages.yml still serves update.sh (#492: opk update is the path)"
else
    pass "pages.yml no longer serves update.sh"
fi

grep -qF 'jekyll-build-pages' "$WF" &&
    pass "Jekyll build wired (theme landing page)" ||
    fail "jekyll-build-pages step missing"
grep -qF 'deploy-pages' "$WF" &&
    pass "Pages deployment step wired" ||
    fail "deploy-pages step missing"
grep -qF 'pages: write' "$WF" && grep -qF 'id-token: write' "$WF" &&
    pass "deployment permissions declared" ||
    fail "pages/id-token permissions missing"

# --- 2. landing assets ----------------------------------------------------

[ -f "$INDEX" ] && pass ".github/pages/index.md exists" ||
    fail ".github/pages/index.md missing"
grep -qF 'layout: default' "$INDEX" &&
    pass "index.md carries layout front matter (theme renders it)" ||
    fail "index.md lacks layout front matter"
grep -qF "$ENTRY_INSTALL" "$INDEX" &&
    pass "landing page shows the entry install one-liner" ||
    fail "landing page lacks the entry install URL"
grep -qF 'sudo opk update' "$INDEX" &&
    pass "landing page names sudo opk update as the update path" ||
    fail "landing page lacks sudo opk update"
if grep -qF "$ENTRY_UPDATE" "$INDEX"; then
    fail "landing page still shows the curl update URL"
else
    pass "landing page omits the curl update URL (opk update is primary)"
fi
if grep -qF 'raw.githubusercontent.com' "$INDEX"; then
    fail "landing page shows raw ref URLs (channel detail belongs in docs)"
else
    pass "landing page omits raw ref URLs (channel detail lives in docs)"
fi

[ -f "$CONFIG" ] && pass ".github/pages/_config.yml exists" ||
    fail ".github/pages/_config.yml missing"
grep -qF 'theme: jekyll-theme-cayman' "$CONFIG" &&
    pass "Cayman theme pinned" ||
    fail "Cayman theme not pinned in _config.yml"

# --- 3. stable-channel docs use the entry, advanced keeps raw recipes ---------

# Entry-install URL only (#492 a A1): update.sh is no longer served, so
# the dead update URL must NOT satisfy this pin — a regular doc citing
# it is drift, not an entry use. The landing-page omission pin above
# (section 2) still asserts index.md never shows it.
for f in README.md docs/getting-started.md; do
    grep -qF "$ENTRY_INSTALL" "$REPO/$f" &&
        pass "$f uses the Pages entry URL" ||
        fail "$f carries no Pages entry URL"
done

# --- 4. advanced streamed paths + the #492 removal ask -----------------------

ADV="$REPO/docs/advanced/streamed-install-update.md"

[ -f "$ADV" ] && pass "docs/advanced/streamed-install-update.md exists" ||
    fail "advanced streamed page missing"
grep -qF 'refs/heads/<branch>/' "$ADV" &&
    pass "advanced page keeps the ref-addressed raw recipes" ||
    fail "advanced page lost its ref-addressed raw recipes"
grep -q 'advanced/streamed-install-update' "$REPO/docs/README.md" &&
    pass "docs index lists the advanced page" ||
    fail "docs index misses the advanced page"

# Removal ask (#492): the regular docs carry no curl one-liners — the
# stable entry stays in README/getting-started, every other streaming
# recipe lives under docs/advanced/.
for f in docs/reference/cli.md docs/how-to/update.md \
    docs/how-to/secure-git-config.md; do
    # Existence first (#492 a A2): grep rc 2 on a missing file would
    # land in the else arm below and pass vacuously.
    [ -f "$REPO/$f" ] ||
        fail "$f missing — curl-absence pin cannot run"
    if grep -q 'curl -fsSL' "$REPO/$f"; then
        fail "$f still carries a curl one-liner (#492 removal ask)"
    else
        pass "$f carries no curl one-liner"
    fi
done

# Checksum policy (#492): nothing under docs/advanced/ bakes in a
# literal sha256 — no release-time regen ever touches advanced/, so a
# hash there would go stale silently and fail honest verifications.
# (grep rc 2 — advanced/ missing entirely — cannot reach the pass
# branch silently: the existence pin above already failed the suite.)
if grep -rEq '[a-fA-F0-9]{64}' "$REPO/docs/advanced/" 2>/dev/null; then
    fail "docs/advanced/ bakes in a literal sha256 (policy: verify manually)"
else
    pass "docs/advanced/ carries no baked-in sha256"
fi

# --- 5. verified-install variant + entry-checksum discipline (#492 wave 2) ----

CKSUM_FILES="README.md docs/getting-started.md"

for f in $CKSUM_FILES; do
    _starts=$(grep -c '^<!-- opk-checksum:start -->$' "$REPO/$f")
    _ends=$(grep -c '^<!-- opk-checksum:end -->$' "$REPO/$f")
    [ "$_starts" -eq 1 ] && [ "$_ends" -eq 1 ] &&
        pass "$f carries exactly one checksum marker block" ||
        fail "$f marker block count wrong (start=$_starts end=$_ends)"
    _hashes="$(sed -n '/^<!-- opk-checksum:start -->$/,/^<!-- opk-checksum:end -->$/p' "$REPO/$f" |
        sed -n 's/^echo "\([0-9a-f]\{64\}\)  \/tmp\/opk-install.sh" | sha256sum -c - &&$/\1/p')"
    [ -n "$_hashes" ] && [ "$(printf '%s\n' "$_hashes" | grep -c .)" -eq 1 ] &&
        pass "$f marker block carries exactly one echo-hash line" ||
        fail "$f marker block echo-hash line count != 1"
    # A 64-hex run OUTSIDE the block would be an unmanaged stale copy
    # (nothing regenerates it) — the same drift the block exists to avoid.
    _outside=$(sed -e '/^<!-- opk-checksum:start -->$/,/^<!-- opk-checksum:end -->$/d' \
        "$REPO/$f" | grep -c '[a-fA-F0-9]\{64\}')
    [ "$_outside" -eq 0 ] &&
        pass "$f carries no stray 64-hex outside the marker block" ||
        fail "$f carries stray 64-hex outside the marker block ($_outside)"
done

# Landing page: the placeholder the workflow substitutes at deploy time
# (the literal hash there is rendered, never committed).
grep -qF '__OPK_INSTALL_SHA256__' "$INDEX" &&
    pass "landing page carries the deploy-time checksum placeholder" ||
    fail "landing page lacks the deploy-time checksum placeholder"

# The workflow computes the hash from the exact served bytes and fails
# loudly when the placeholder is missing (a bare sed would serve the
# raw token silently).
grep -qF "grep -F '__OPK_INSTALL_SHA256__' site/index.md" "$WF" &&
    pass "workflow guards the placeholder before substitution" ||
    fail "workflow lacks the placeholder guard grep"
grep -qF 'sha256sum site/install.sh' "$WF" &&
    pass "workflow hashes the served install.sh bytes" ||
    fail "workflow does not hash the served install.sh bytes"
grep -qF 's/__OPK_INSTALL_SHA256__/' "$WF" &&
    pass "workflow substitutes the rendered hash" ||
    fail "workflow lacks the hash substitution"
# The render pipeline must fail loudly on a sha256sum failure (a A5):
# without pipefail the empty-hash substitution deploys green. The pin
# scopes to the assemble block (the artifact-delete block sets it too).
grep -A6 'name: Assemble site' "$WF" | grep -qF 'set -euo pipefail' &&
    pass "assemble block fails loudly on hash pipeline failure (a A5)" ||
    fail "assemble block lacks set -euo pipefail (a A5)"

# Drift pin: the committed hash must describe either the bytes stable
# serves (mid-cycle state) or this tree's install.sh (release-PR state)
# — the two sanctioned states of the release-only regen discipline. In
# clones without a stable ref (CI) the value pin cannot run; the
# structural pins above stay, and make release pre-flights freshness.
_ck_ref=""
if git -C "$REPO" rev-parse --verify -q origin/stable >/dev/null 2>&1; then
    _ck_ref=origin/stable
elif git -C "$REPO" rev-parse --verify -q stable >/dev/null 2>&1; then
    _ck_ref=stable
fi
if [ -n "$_ck_ref" ]; then
    _stable_sha=$(git -C "$REPO" show "$_ck_ref:files/install.sh" |
        sha256sum | cut -d' ' -f1)
    _tree_sha=$(sha256sum "$REPO/files/install.sh" | cut -d' ' -f1)
    for f in $CKSUM_FILES; do
        _h="$(sed -n '/^<!-- opk-checksum:start -->$/,/^<!-- opk-checksum:end -->$/p' \
            "$REPO/$f" |
            sed -n 's/^echo "\([0-9a-f]\{64\}\)  \/tmp\/opk-install.sh" | sha256sum -c - &&$/\1/p')"
        if [ "$_h" = "$_stable_sha" ] || [ "$_h" = "$_tree_sha" ]; then
            pass "$f entry checksum matches $_ck_ref or the tree (sanctioned)"
        else
            fail "$f entry checksum matches neither $_ck_ref nor the tree"
        fi
    done
else
    pass "no stable ref in this clone (CI) — structural checksum pins only"
fi

# --- 6. the agent-notes pointer block (#721) ---------------------------------
# The block that points an agent at the shipped host notes
# (templates/AGENTS-HOST.md) is rendered in THREE places — the repo
# README, this landing page and the how-to — because each audience has
# its own entry surface, and a copied block cannot be updated by the
# kit. Three copies are one block: the bytes between the markers must
# be IDENTICAL everywhere (a hand-edited copy would quietly name a
# path the kit does not deploy). test-agents-host-notes.sh owns the
# contract between the block's path and the deploy manifest; this
# section owns copy identity, marker shape and block presence.
SNIP_START='<!-- opk-agents-snippet:start -->'
SNIP_END='<!-- opk-agents-snippet:end -->'
SNIP_PATH='/usr/local/lib/opencode-permissions-kit/templates/AGENTS-HOST.md'
HOWTO="$REPO/docs/how-to/agent-host-notes.md"

# snippet_block <file> — the marker-delimited block, markers included.
snippet_block() {
    sed -n "/^${SNIP_START}\$/,/^${SNIP_END}\$/p" "$1"
}

# Reference first, with the emptiness tripwire: with the markers gone
# from EVERY copy the identity comparisons below would see empty ==
# empty and pass — the block must exist, and it must name the path
# the kit deploys (one line, exactly the path).
_ref="$(snippet_block "$REPO/README.md")"
if [ -n "$_ref" ] && printf '%s\n' "$_ref" | grep -qxF "$SNIP_PATH"; then
    pass "README.md snippet block exists and names the deployed host-notes path"
else
    fail "README.md snippet block is empty or lacks the path line $SNIP_PATH"
fi

for _f in "$REPO/README.md" "$INDEX" "$HOWTO"; do
    [ -f "$_f" ] || {
        fail "${_f#"$REPO"/} missing — snippet pin cannot run"
        continue
    }
    # Occurrences, not lines: a second marker glued onto the same
    # physical line must not slip past a line count.
    _s=$(grep -oF "$SNIP_START" "$_f" | wc -l)
    _e=$(grep -oF "$SNIP_END" "$_f" | wc -l)
    if [ "$_s" -eq 1 ] && [ "$_e" -eq 1 ]; then
        pass "${_f#"$REPO"/} carries exactly one snippet marker pair"
    else
        fail "${_f#"$REPO"/} snippet marker count wrong (start=$_s end=$_e)"
    fi
    [ "$_f" = "$REPO/README.md" ] && continue
    if [ "$(snippet_block "$_f")" = "$_ref" ]; then
        pass "${_f#"$REPO"/} snippet block is byte-identical to README.md"
    else
        fail "${_f#"$REPO"/} snippet block DIFFERS from README.md"
    fi
done

# Canary: the identity check must SEE a drift — a copy of the README
# whose block names a different file has to differ from the reference
# (a comparison that cannot fail is decoration). Scratch via the work
# registry (no local trap: it would disarm the harness cleanup).
WORK="$(work_new)" || {
    echo "pages tests: scratch creation failed (TMPDIR=${TMPDIR:-unset})" >&2
    exit 1
}
sed "s|${SNIP_PATH}|${SNIP_PATH%.md}.RENAMED.md|" "$REPO/README.md" >"$WORK/readme-drift.md"
if [ "$(snippet_block "$WORK/readme-drift.md")" = "$_ref" ]; then
    fail "canary: a drifted snippet copy is NOT detected (identity check is blind!)"
else
    pass "canary: a drifted snippet copy is detected"
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All pages entry tests passed.$NC"
exit 0
