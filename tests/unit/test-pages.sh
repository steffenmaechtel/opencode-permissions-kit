#!/bin/sh
# Unit tests for the GitHub Pages entry site (short one-liner URLs):
#   1. the deploy workflow exists and pins the served scripts to the
#      `stable` channel (the public entry must never serve dev state),
#      copies install.sh + update.sh, and wires the Jekyll build +
#      Pages deployment;
#   2. the landing assets exist (index.md with layout front matter,
#      _config.yml pinning the Cayman theme) and carry the entry URLs;
#   3. the user-facing docs use the entry URLs for the stable channel
#      and keep the ref-addressed raw URLs for master/branch/tag pins
#      (a channel-fixed entry cannot self-pin a ref).
#
# Run: sh tests/unit/test-pages.sh
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
WF="$REPO/.github/workflows/pages.yml"
INDEX="$REPO/.github/pages/index.md"
CONFIG="$REPO/.github/pages/_config.yml"

ENTRY_INSTALL="https://steffenmaechtel.github.io/opencode-permissions-kit/install.sh"
ENTRY_UPDATE="https://steffenmaechtel.github.io/opencode-permissions-kit/update.sh"
RAW_BRANCH="https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit/refs/heads/<branch>/"

failures=0
passed=0

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

# --- 1. deploy workflow ---------------------------------------------------

[ -f "$WF" ] && pass "pages.yml exists" || fail "pages.yml missing"

grep -qF 'branches: [stable]' "$WF" \
    && pass "workflow triggers on stable pushes (release signal)" \
    || fail "workflow does not trigger on stable pushes"
grep -qF 'workflow_dispatch:' "$WF" \
    && pass "workflow is manually dispatchable" \
    || fail "workflow lacks workflow_dispatch"

# The load-bearing pin: scripts ALWAYS come from the stable channel.
grep -qF 'ref: stable' "$WF" \
    && pass "served scripts pinned to the stable ref" \
    || fail "scripts not pinned to stable — entry could serve dev state"
grep -qF 'cp stable/files/install.sh site/' "$WF" \
    && pass "install.sh copied from the stable checkout" \
    || fail "install.sh copy from stable missing"
grep -qF 'cp stable/files/opencode-permissions-kit-lib/management/update.sh site/' "$WF" \
    && pass "update.sh copied from the stable checkout" \
    || fail "update.sh copy from stable missing"

grep -qF 'jekyll-build-pages' "$WF" \
    && pass "Jekyll build wired (theme landing page)" \
    || fail "jekyll-build-pages step missing"
grep -qF 'deploy-pages' "$WF" \
    && pass "Pages deployment step wired" \
    || fail "deploy-pages step missing"
grep -qF 'pages: write' "$WF" && grep -qF 'id-token: write' "$WF" \
    && pass "deployment permissions declared" \
    || fail "pages/id-token permissions missing"

# --- 2. landing assets ----------------------------------------------------

[ -f "$INDEX" ] && pass ".github/pages/index.md exists" \
    || fail ".github/pages/index.md missing"
grep -qF 'layout: default' "$INDEX" \
    && pass "index.md carries layout front matter (theme renders it)" \
    || fail "index.md lacks layout front matter"
grep -qF "$ENTRY_INSTALL" "$INDEX" \
    && pass "landing page shows the entry install one-liner" \
    || fail "landing page lacks the entry install URL"
grep -qF 'sudo opk update' "$INDEX" \
    && pass "landing page names sudo opk update as the update path" \
    || fail "landing page lacks sudo opk update"
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

[ -f "$CONFIG" ] && pass ".github/pages/_config.yml exists" \
    || fail ".github/pages/_config.yml missing"
grep -qF 'theme: jekyll-theme-cayman' "$CONFIG" \
    && pass "Cayman theme pinned" \
    || fail "Cayman theme not pinned in _config.yml"

# --- 3. docs use the entry for stable, raw refs for pins ------------------

for f in README.md docs/getting-started.md docs/reference/cli.md \
         docs/how-to/secure-git-config.md docs/how-to/update.md; do
    grep -q "$ENTRY_INSTALL\|$ENTRY_UPDATE" "$REPO/$f" \
        && pass "$f uses the Pages entry URL" \
        || fail "$f carries no Pages entry URL"
done

# The pin recipe must survive on the ref-addressed raw URLs.
grep -qF "$RAW_BRANCH" "$REPO/docs/how-to/update.md" \
    && pass "branch-pin recipe keeps the ref-addressed raw URL" \
    || fail "branch-pin recipe lost its raw URL"

echo ""
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All pages entry tests passed.$NC"
exit 0
