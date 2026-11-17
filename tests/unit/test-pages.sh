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
#      would go stale with every branch push — verify manually there).
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

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All pages entry tests passed.$NC"
exit 0
