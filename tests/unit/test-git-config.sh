#!/bin/sh
# Unit tests for config.sh git-config on/off/status toggle.
# Verifies the //SECURE_GIT: sed manipulation in the bundled opencode.jsonc
# template produces a valid, parseable JSONC with .git/config denies
# present (on) or absent (off), and that status detection works.
# Run: ./tests/unit/test-git-config.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/templates/opencode.jsonc"
RENDER="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/render-agent-config.sh"
PARSER="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/py/jsonc-parser.py"

failures=0
passed=0

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

echo ""
echo "Git-Config Toggle (SECURE_GIT) Tests"
echo "====================================="
echo ""

# --- 1. Template has commented-out SECURE_GIT lines ---
if grep -q '//SECURE_GIT:' "$TEMPLATE"; then
    pass "template has //SECURE_GIT: comment markers"
else
    fail "template has //SECURE_GIT: comment markers"
fi

# --- 2. git-config ON: sed 's|//SECURE_GIT: ||' ---
ON_FILE="$TMPDIR/on.jsonc"
sed 's|//SECURE_GIT: ||' "$TEMPLATE" > "$ON_FILE"

if grep -q '"\.git/config"' "$ON_FILE" && ! grep -q '//SECURE_GIT' "$ON_FILE"; then
    pass "git-config ON: .git/config deny rules uncommented"
else
    fail "git-config ON: .git/config deny rules uncommented"
fi

# ON file must parse cleanly and emit .git/config as deny pattern
ON_DENY=$(python3 "$PARSER" "$ON_FILE" 2>/dev/null || true)
if echo "$ON_DENY" | grep -qF '.git/config'; then
    pass "git-config ON: parser emits .git/config in deny patterns"
else
    fail "git-config ON: parser emits .git/config in deny patterns"
fi

# ON file must parse cleanly (parser exits 0)
if python3 "$PARSER" "$ON_FILE" >/dev/null 2>&1; then
    pass "git-config ON: resulting JSONC is valid JSON"
else
    fail "git-config ON: resulting JSONC is valid JSON"
fi

# --- 3. git-config OFF: sed '/\/\/SECURE_GIT:/d' ---
OFF_FILE="$TMPDIR/off.jsonc"
sed '/\/\/SECURE_GIT:/d' "$TEMPLATE" > "$OFF_FILE"

if ! grep -q 'SECURE_GIT' "$OFF_FILE"; then
    pass "git-config OFF: all SECURE_GIT lines removed"
else
    fail "git-config OFF: all SECURE_GIT lines removed"
fi

OFF_DENY=$(python3 "$PARSER" "$OFF_FILE" 2>/dev/null || true)
if ! echo "$OFF_DENY" | grep -qF '.git/config'; then
    pass "git-config OFF: parser does NOT emit .git/config"
else
    fail "git-config OFF: parser does NOT emit .git/config"
fi

if python3 "$PARSER" "$OFF_FILE" >/dev/null 2>&1; then
    pass "git-config OFF: resulting JSONC is valid JSON"
else
    fail "git-config OFF: resulting JSONC is valid JSON"
fi

# --- 4. Status detection logic (matches config.sh git_config_status) ---
# ON  = active .git/config deny rule present (line starts with whitespace + ".git/config")
# OFF = no active .git/config rule (either absent or still a //SECURE_GIT comment)
if grep -qE '^[[:space:]]*"\.git/config"' "$ON_FILE"; then
    pass "status detection: ON file has active .git/config rule"
else
    fail "status detection: ON file has active .git/config rule"
fi

if ! grep -qE '^[[:space:]]*"\.git/config"' "$OFF_FILE"; then
    pass "status detection: OFF file has NO active .git/config rule"
else
    fail "status detection: OFF file has NO active .git/config rule"
fi

# --- 5. Round-trip: ON -> OFF removes the now-active rules ---
# Apply OFF sed to the ON file
ROUNDTRIP="$TMPDIR/roundtrip.jsonc"
sed '/\/\/SECURE_GIT:/d' "$ON_FILE" > "$ROUNDTRIP"
# ON file has no //SECURE_GIT comments (they were uncommented), so OFF sed
# should be a no-op — .git/config rules should survive
if grep -q '"\.git/config"' "$ROUNDTRIP"; then
    pass "round-trip: ON->OFF sed is no-op (rules already active)"
else
    fail "round-trip: ON->OFF sed is no-op (rules already active)"
fi

# --- 6. install.sh git semantics (regression: 2026-08-16 live-test bugs) ---
# SECURE_GIT_CONFIG=true means the deny rules are ACTIVE = git BLOCKED.
# A live install run revealed three inversions/gaps that must never return:
#   a) the Standard question mapped "allow" to true (= block),
#   b) the completion panel showed the mapping backwards,
#   c) a re-install silently ignored the choice (config never re-rendered).
INSTALL="$SCRIPT_DIR/../../files/install.sh"
UPDATE="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/update.sh"

# issue #116: sudo keeps the invoking user's CWD — a `git config --global`
# as the opencode user from an unreadable developer home (mode 750) dies
# on git >= 2.55 with "fatal: error reading '<cwd>/.git'" and
# safe.directory is never ensured. Every such call must chdir first
# (`git -C /`). Verified live: -C / returns rc 0 where the bare call
# fatals (alpine/git 2.55, unreadable CWD).
# 0.0.39n review hardening: the extraction joins backslash continuations
# (a wrapped call must not escape either check) and drops comment lines
# (a commented example must not trip the negative check); the counts are
# scoped to the safe.directory calls (the --list backups must not
# satisfy the threshold); `|| true` keeps set -e from aborting the suite
# on a zero count instead of failing the check.
_opk_install_j=$(sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' "$INSTALL" | grep -v '^[[:space:]]*#' || true)
_opk_update_j=$(sed -e ':a' -e '/\\$/N; s/\\\n/ /; ta' "$UPDATE" | grep -v '^[[:space:]]*#' || true)
_git_sd_install=$(printf '%s\n' "$_opk_install_j" | grep -c 'git -C / config --global --get-all safe.directory\|git -C / config --global --add safe.directory' || true)
_git_sd_update=$(printf '%s\n' "$_opk_update_j" | grep -c 'git -C / config --global --get-all safe.directory\|git -C / config --global --add safe.directory' || true)
if [ "$_git_sd_install" -ge 2 ] && [ "$_git_sd_update" -ge 2 ]; then
    pass "issue #116: safe.directory git calls are CWD-safe (git -C /)"
else
    fail "issue #116: safe.directory git calls are CWD-safe (git -C /): install=$_git_sd_install update=$_git_sd_update"
fi
if ! printf '%s\n' "$_opk_install_j" | grep -qE '(sudo -u "[^"]+"|sudo -u [A-Za-z_$]+) (-H )?git config --global' \
    && ! printf '%s\n' "$_opk_update_j" | grep -qE '(sudo -u "[^"]+"|sudo -u [A-Za-z_$]+) (-H )?git config --global'; then
    pass "issue #116: no bare (CWD-inheriting) git config --global calls remain"
else
    fail "issue #116: bare git config --global call remains (CWD-inheriting)"
fi

if grep -q '^SECURE_GIT_CONFIG=true' "$INSTALL"; then
    pass "install.sh: default is git BLOCKED (SECURE_GIT_CONFIG=true)"
else
    fail "install.sh: default is git BLOCKED (SECURE_GIT_CONFIG=true)"
fi

if grep -q 'yes" \]; then SECURE_GIT_CONFIG=false' "$INSTALL" \
   || grep -Eq '=\s*"yes"\s*\]\s*&&\s*SECURE_GIT_CONFIG=false' "$INSTALL"; then
    pass "install.sh: Standard 'allow git' maps to SECURE_GIT_CONFIG=false"
else
    fail "install.sh: Standard 'allow git' maps to SECURE_GIT_CONFIG=false"
fi

if grep -q 'ui_kv "Git".*blocked for the agent' "$INSTALL" \
   && ! grep -q 'ui_kv "Git".*allowed (soft-only' "$INSTALL"; then
    pass "install.sh: completion panel maps true=blocked / false=allowed"
else
    fail "install.sh: completion panel maps true=blocked / false=allowed"
fi

# The re-install path must back up + re-render the agent config with the
# chosen git setting (never silently keep a stale one).
if grep -q 'opencode.jsonc-existing' "$INSTALL" \
   && grep -q 'config re-applied' "$INSTALL"; then
    pass "install.sh: re-install re-renders the agent config (backup kept)"
else
    fail "install.sh: re-install re-renders the agent config (backup kept)"
fi

# The config.sh toggle must have the same data-safety: back up an existing
# agent config before the template overwrite (review 0.0.39a D1 / 0.0.39b D3).
CONFIG="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
if grep -q '\.bak-' "$CONFIG" \
   && grep -q 'previous config backed up' "$CONFIG"; then
    pass "config.sh: git-config toggle backs up the existing agent config"
else
    fail "config.sh: git-config toggle backs up the existing agent config"
fi

# Plan numbering must be dynamic (_plan helper) — a skipped optional step
# must not leave a gap in the numbered plan the user confirms.
if grep -q '_plan()' "$INSTALL" && ! grep -Eq 'ui_plan [0-9]' "$INSTALL"; then
    pass "install.sh: plan numbering is dynamic (no gaps when steps are skipped)"
else
    fail "install.sh: plan numbering is dynamic (no gaps when steps are skipped)"
fi

# --- shared render helper (sh/render-agent-config.sh, 0.0.41e wave) -------------
# agent_config_render replaces the SECURE_GIT sed pair that lived in
# install.sh's _oc_install_agent_config and config.sh's git_config_apply.
# Lives under $TMPDIR so the suite's EXIT trap covers the cleanup (a
# second trap would REPLACE it); the expected-failure cases wrap the
# call in if/else — under set -e a bare failing call would abort the
# command substitution before "rc=" is echoed.
ACRWORK="$TMPDIR/acr"
mkdir -p "$ACRWORK"

acr_out=$( . "$RENDER"
    if agent_config_render "$TEMPLATE" "$ACRWORK/on.jsonc" on 2>&1; then _acr_rc=0; else _acr_rc=$?; fi
    echo "rc=$_acr_rc" )
case "$acr_out" in *rc=0*) pass "render on: rc=0" ;; *) fail "render on: rc (got [$acr_out])" ;; esac
grep -qE '^[[:space:]]*"\.git/config"' "$ACRWORK/on.jsonc" \
    && pass "render on: .git/config deny rule active (uncommented)" \
    || fail "render on: deny rule not active"
grep -q '//SECURE_GIT' "$ACRWORK/on.jsonc" \
    && fail "render on: leftover SECURE_GIT markers" \
    || pass "render on: no leftover markers"

acr_out=$( . "$RENDER"
    if agent_config_render "$TEMPLATE" "$ACRWORK/off.jsonc" off 2>&1; then _acr_rc=0; else _acr_rc=$?; fi
    echo "rc=$_acr_rc" )
case "$acr_out" in *rc=0*) pass "render off: rc=0" ;; *) fail "render off: rc (got [$acr_out])" ;; esac
grep -qE '^[[:space:]]*"\.git/config"' "$ACRWORK/off.jsonc" \
    && fail "render off: deny rule must be gone" \
    || pass "render off: deny rule gone"

acr_out=$( . "$RENDER"
    if agent_config_render "$TEMPLATE" "$ACRWORK/bad.jsonc" maybe 2>&1; then _acr_rc=0; else _acr_rc=$?; fi
    echo "rc=$_acr_rc" )
case "$acr_out" in *rc=1*) pass "render: unknown mode rejected (rc=1)" ;; *) fail "render: unknown mode (got [$acr_out])" ;; esac
[ ! -e "$ACRWORK/bad.jsonc" ] && pass "render: nothing written on rejection" || fail "render: file written on rejection"

# --- Summary ---
echo ""
echo "===================================="
echo "  ${GREEN}Passed: $passed${NC}"
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
else
    echo "  All tests passed."
fi
echo ""