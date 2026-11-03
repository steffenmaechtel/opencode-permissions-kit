#!/bin/sh
# Unit tests for sh/update-check.sh (issue #358):
#   - version compare (sort -V), tag-pin detection, shape-gated fetch
#     (file:// fixtures stand in for the mirror — no network)
#   - the once-per-day banner-note cache: first-start fetch, same-day
#     replay from cache, next-day refetch, offline keep-verdict,
#     tag-pin skip, OPK_UPDATE_CHECK=0, missing curl, missing HOME,
#     garbage cache contents
#   - wiring: wrapper banner note, status.sh Core row, install/update
#     fetch lists, deploy-lib manifest, docs pages
# No root, no network — the mirror is a file:// fixture; the offline
# legs point at a closed port on loopback.
# Run: sh tests/unit/test-update-check.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/../.."
LIB="$REPO/files/opencode-permissions-kit-lib/sh/update-check.sh"
WRAPPER="$REPO/files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
STATUS="$REPO/files/opencode-permissions-kit-lib/management/status.sh"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"

failures=0
passed=0
pass() {
    echo "  ${GREEN}PASS${NC}  $1"
    passed=$((passed + 1))
}
fail() {
    echo "  ${RED}FAIL${NC}  $1"
    failures=$((failures + 1))
}

# shellcheck disable=SC1090  # the shipped lib, presence pinned below
[ -f "$LIB" ] && . "$LIB"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Mirror fixture: KIT_UPDATE_HOST=file://$WORK/kit makes the lib fetch
# $WORK/kit/<channel>/VERSION — curl reads file:// URLs like any other.
KIT_HOST="file://$WORK/kit"
OFFLINE_HOST="https://127.0.0.1:1"
HOME_FIX="$WORK/home"
mkdir -p "$HOME_FIX"
_cache="$HOME_FIX/.cache/opencode-permissions-kit/update-check"

fixture_channel() {
    _fx_channel="$1"
    _fx_ver="$2"
    mkdir -p "$WORK/kit/$_fx_channel"
    printf '%s\n' "$_fx_ver" >"$WORK/kit/$_fx_channel/VERSION"
}

# note_run <home> <local> <channel>: daily note with the fixture mirror.
note_run() {
    _nr_home="$1"
    _nr_local="$2"
    _nr_channel="$3"
    HOME="$_nr_home" KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK=1 \
        kit_update_daily_note "$_nr_local" "$_nr_channel" || true
}

echo ""
echo "Update-Check Tests"
echo "==================="
echo ""

echo "-- version compare --"
[ "$(kit_update_version_cmp 0.0.59 0.0.58)" = gt ] &&
    pass "cmp: 0.0.59 > 0.0.58" ||
    fail "cmp: 0.0.59 > 0.0.58 (got '$(kit_update_version_cmp 0.0.59 0.0.58)')"
[ "$(kit_update_version_cmp 0.0.58 0.0.59)" = lt ] &&
    pass "cmp: 0.0.58 < 0.0.59" ||
    fail "cmp: 0.0.58 < 0.0.59"
[ "$(kit_update_version_cmp 1.2.3 1.2.3)" = eq ] &&
    pass "cmp: 1.2.3 = 1.2.3" ||
    fail "cmp: 1.2.3 = 1.2.3"
[ "$(kit_update_version_cmp 0.0.100 0.0.99)" = gt ] &&
    pass "cmp: multi-digit fields compare numerically (0.0.100 > 0.0.99)" ||
    fail "cmp: multi-digit fields compare numerically (got '$(kit_update_version_cmp 0.0.100 0.0.99)')"

echo "-- tag-pin detection --"
kit_update_is_tag 0.0.29 &&
    pass "is_tag: bare version tag" ||
    fail "is_tag: bare version tag not detected"
kit_update_is_tag 10.20.30 &&
    pass "is_tag: multi-digit tag" ||
    fail "is_tag: multi-digit tag not detected"
if kit_update_is_tag stable; then
    fail "is_tag: channel name must not be a tag"
else
    pass "is_tag: channel name is not a tag"
fi
if kit_update_is_tag feature/x; then
    fail "is_tag: branch must not be a tag"
else
    pass "is_tag: branch is not a tag"
fi
if kit_update_is_tag v0.0.29; then
    fail "is_tag: v-prefixed ref must not be a tag (repo tags have no prefix)"
else
    pass "is_tag: v-prefixed ref is not a tag"
fi
if kit_update_is_tag 0.0.29-beta; then
    fail "is_tag: suffixed ref must not be a tag"
else
    pass "is_tag: suffixed ref is not a tag"
fi

echo "-- fetch: shape gates --"
fixture_channel stable 0.0.59
[ "$(KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version stable)" = "0.0.59" ] &&
    pass "fetch: well-formed VERSION body" ||
    fail "fetch: well-formed VERSION body (got '$(KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version stable)')"
fixture_channel stable "not-a-version"
if KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version stable >/dev/null 2>&1; then
    fail "fetch: garbage body must be rejected"
else
    pass "fetch: garbage body rejected"
fi
[ -z "$(KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version stable 2>/dev/null || true)" ] &&
    pass "fetch: garbage body yields no output" ||
    fail "fetch: garbage body leaked output"
fixture_channel stable "0.0.59 trailing-words"
if KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version stable >/dev/null 2>&1; then
    fail "fetch: body with trailing words must be rejected"
else
    pass "fetch: body with trailing words rejected"
fi
mkdir -p "$WORK/kit/twolines"
printf '0.0.59\n0.0.60\n' >"$WORK/kit/twolines/VERSION"
if KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version twolines >/dev/null 2>&1; then
    fail "fetch: multi-line body must be rejected"
else
    pass "fetch: multi-line body rejected"
fi
if KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version no-such-channel >/dev/null 2>&1; then
    fail "fetch: missing channel file must fail"
else
    pass "fetch: missing channel file fails"
fi
# Channel reaches a URL path segment: a hostile install.conf value must
# be refused before any request (marker proof: nothing executed).
rm -f "${WORK:?}/pwned"
if KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version 'stable && touch '"$WORK"'/pwned' >/dev/null 2>&1; then
    fail "fetch: channel with shell metacharacters must be rejected"
else
    pass "fetch: channel with shell metacharacters rejected"
fi
[ ! -e "$WORK/pwned" ] &&
    pass "fetch: hostile channel executed nothing (marker absent)" ||
    fail "fetch: hostile channel EXECUTED something (marker present)"
if KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version '../master' >/dev/null 2>&1; then
    fail "fetch: dotdot channel must be rejected"
else
    pass "fetch: dotdot channel rejected"
fi

echo "-- daily note: available / cache / refetch --"
rm -rf "${WORK:?}/kit"
fixture_channel stable 0.0.59
_out=$(note_run "$HOME_FIX" 0.0.58 stable)
case "$_out" in
    *"kit 0.0.59 is available"*"sudo opk update"*)
        pass "daily note: newer remote renders the update note"
        ;;
    *)
        fail "daily note: newer remote renders the update note (got '$_out')"
        ;;
esac
[ -f "$HOME_FIX/.cache/opencode-permissions-kit/update-check" ] &&
    pass "daily note: verdict cached in ~/.cache" ||
    fail "daily note: no cache file written"
# The daily gate: with today already stamped, the fixture can vanish —
# the cached verdict must still render (a broken gate would refetch,
# fail on the missing mirror, and go silent).
rm -rf "${WORK:?}/kit"
_out=$(note_run "$HOME_FIX" 0.0.58 stable)
case "$_out" in
    *"kit 0.0.59 is available"*)
        pass "daily note: same-day start replays the cache (no refetch)"
        ;;
    *)
        fail "daily note: same-day start replay broken (got '$_out')"
        ;;
esac
# Next day (stale DATE): refetch and pick up the newer remote.
fixture_channel stable 0.0.60
printf 'DATE=2000-01-01\nSTATE=available\nVER=0.0.59\n' >"$_cache"
_out=$(note_run "$HOME_FIX" 0.0.58 stable)
case "$_out" in
    *"kit 0.0.60 is available"*)
        pass "daily note: next day refetches and reports the new version"
        ;;
    *)
        fail "daily note: next-day refetch broken (got '$_out')"
        ;;
esac

echo "-- daily note: quiet arms --"
rm -rf "${WORK:?}/kit" "${HOME_FIX:?}"
mkdir -p "$HOME_FIX"
fixture_channel stable 0.0.58
[ -z "$(note_run "$HOME_FIX" 0.0.58 stable)" ] &&
    pass "daily note: equal remote stays quiet (current)" ||
    fail "daily note: equal remote produced a note"
fixture_channel stable 0.0.57
[ -z "$(note_run "$HOME_FIX" 0.0.58 stable)" ] &&
    pass "daily note: behind remote stays quiet (channel switched back)" ||
    fail "daily note: behind remote produced a note"
# Tag pin: no request at all — a closed port stands in for "any network
# error would have been heard"; the pin needs the offline host because
# a pinned channel must not even fetch.
rm -rf "$HOME_FIX"
mkdir -p "$HOME_FIX"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 0.0.58 || true)
[ -z "$_out" ] &&
    pass "daily note: tag pin stays quiet without a request" ||
    fail "daily note: tag pin produced output (got '$_out')"
# OPK_UPDATE_CHECK=0: no fetch, no state write — with a LIVE fixture.
rm -rf "$HOME_FIX"
mkdir -p "$HOME_FIX"
fixture_channel stable 0.0.59
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK=0 \
    kit_update_daily_note 0.0.58 stable || true)
[ -z "$_out" ] &&
    pass "opt-out: OPK_UPDATE_CHECK=0 prints nothing" ||
    fail "opt-out: OPK_UPDATE_CHECK=0 printed '$_out'"
[ ! -e "$HOME_FIX/.cache/opencode-permissions-kit/update-check" ] &&
    pass "opt-out: no cache file written" ||
    fail "opt-out: cache file written despite OPK_UPDATE_CHECK=0"

echo "-- daily note: offline and degraded environments --"
# Offline on the first start of the day: no note, verdict unknown,
# exactly one attempt stamped for today.
rm -rf "$HOME_FIX"
mkdir -p "$HOME_FIX"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 stable || true)
[ -z "$_out" ] &&
    pass "offline first start: no note, no crash" ||
    fail "offline first start: got '$_out'"
_state=$(sed -n 's/^STATE=//p' "$HOME_FIX/.cache/opencode-permissions-kit/update-check" 2>/dev/null | tail -1)
[ "$_state" = "unknown" ] &&
    pass "offline first start: verdict stamped unknown" ||
    fail "offline first start: verdict stamped '$_state' (want unknown)"
# Offline the day AFTER a known-available verdict: the note survives.
printf 'DATE=2000-01-01\nSTATE=available\nVER=0.0.59\n' >"$_cache"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 stable || true)
case "$_out" in
    *"kit 0.0.59 is available"*)
        pass "offline next day: yesterday's available note survives"
        ;;
    *)
        fail "offline next day: available note lost (got '$_out')"
        ;;
esac
# No curl on PATH: quiet, no crash, nothing stamped (retry next start).
rm -rf "${HOME_FIX:?}" "${WORK:?}/nobin"
mkdir -p "$HOME_FIX" "$WORK/nobin"
for _t in sh date sed tail grep mkdir sort; do
    ln -s "$(command -v "$_t")" "$WORK/nobin/$_t"
done
_out=$(PATH="$WORK/nobin" HOME="$HOME_FIX" KIT_UPDATE_HOST="$KIT_HOST" \
    OPK_UPDATE_CHECK=1 sh -c '. "$1"; kit_update_daily_note 0.0.58 stable' _ "$LIB" 2>/dev/null || true)
[ -z "$_out" ] &&
    pass "curl missing: no note, no crash" ||
    fail "curl missing: got '$_out'"
[ ! -e "$HOME_FIX/.cache/opencode-permissions-kit/update-check" ] &&
    pass "curl missing: nothing stamped (retries next start)" ||
    fail "curl missing: state written without curl"
# No HOME: quiet, no crash (offline mirror — without a cache the check
# would fetch on EVERY start; the quiet arm is the contract here).
_out=$(env -u HOME KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    sh -c '. "$1"; kit_update_daily_note 0.0.58 stable; echo "rc=$?"' _ "$LIB" 2>/dev/null || true)
[ "$_out" = "rc=0" ] &&
    pass "HOME unset: no note, clean rc" ||
    fail "HOME unset: got '$_out'"

echo "-- daily note: untrusted cache contents --"
rm -rf "${WORK:?}/kit" "${HOME_FIX:?}"
mkdir -p "$HOME_FIX/.cache/opencode-permissions-kit"
fixture_channel stable 0.0.59
printf 'STATE=$(touch %s/pwned)\nDATE=garbage\nVER=99.99.99\n' "$WORK" >"$_cache"
rm -f "${WORK:?}/pwned"
_out=$(note_run "$HOME_FIX" 0.0.58 stable)
case "$_out" in
    *"kit 0.0.59 is available"*)
        pass "garbage cache: degrades to a fresh check"
        ;;
    *)
        fail "garbage cache: fresh check broken (got '$_out')"
        ;;
esac
[ ! -e "$WORK/pwned" ] &&
    pass "garbage cache: payload fields never execute (marker absent)" ||
    fail "garbage cache: payload EXECUTED (marker present)"
# available without a usable VER must not replay (a note needs a version).
printf 'DATE=%s\nSTATE=available\nVER=\n' "$(date +%Y-%m-%d)" >"$_cache"
[ -z "$(note_run "$HOME_FIX" 0.0.58 stable)" ] &&
    pass "available without VER: no replay, no note" ||
    fail "available without VER: replayed a versionless note"

echo "-- wiring: wrapper banner --"
grep -q 'sh/update-check.sh' "$WRAPPER" &&
    pass "wrapper: sources the update-check lib" ||
    fail "wrapper: update-check lib not wired"
grep -q 'KIT_UPDATE_NOTE=\$(kit_update_daily_note' "$WRAPPER" &&
    pass "wrapper: banner note rides kit_update_daily_note" ||
    fail "wrapper: banner note call missing"
grep -q '\[ "\$HEADLESS" != true \] && \[ -f /usr/local/lib/opencode-permissions-kit/sh/update-check.sh \]' "$WRAPPER" &&
    pass "wrapper: check guarded to interactive starts (headless never runs it)" ||
    fail "wrapper: interactive guard missing"

echo "-- wiring: status.sh Core row --"
grep -q 'ui_kv_warn "kit update" "new kit' "$STATUS" &&
    pass "status: available update renders a counted warn row" ||
    fail "status: counted warn row missing"
grep -q 'ui_kv "kit update" "unknown — live check unavailable (offline or blocked)"' "$STATUS" &&
    pass "status: offline renders an uncounted unknown row" ||
    fail "status: uncounted unknown row missing"
grep -q 'ui_kv "kit update" "pinned to' "$STATUS" &&
    pass "status: tag pin renders a neutral row" ||
    fail "status: tag-pin row missing"
grep -q 'ui_kv "kit update" "checks disabled (OPK_UPDATE_CHECK=0)"' "$STATUS" &&
    pass "status: opt-out renders a disabled row" ||
    fail "status: disabled row missing"
grep -q 'ui_kv_warn "kit update" "not checked — kit file sh/update-check.sh missing' "$STATUS" &&
    pass "status: missing lib renders a counted broken-kit warn" ||
    fail "status: missing-lib warn missing"

echo "-- wiring: manifests and docs --"
grep -q 'opencode-permissions-kit-lib/sh/update-check.sh' "$INSTALL" &&
    pass "install.sh: fetch list carries the lib" ||
    fail "install.sh: lib missing from fetch list"
grep -q 'opencode-permissions-kit-lib/sh/update-check.sh' "$UPDATE" &&
    pass "update.sh: KIT_FILES carries the lib" ||
    fail "update.sh: lib missing from KIT_FILES"
grep -q 'opencode-permissions-kit-lib/sh/update-check.sh 644' "$DEPLOYLIB" &&
    pass "deploy-lib: manifest deploys the lib as a sourced 644" ||
    fail "deploy-lib: manifest row missing or wrong mode"
grep -q 'sh/update-check.sh' "$REPO/docs/reference/files.md" &&
    pass "docs: files.md lists the lib" ||
    fail "docs: files.md row missing"
grep -q 'update-check\|OPK_UPDATE_CHECK' "$REPO/docs/how-to/update.md" &&
    pass "docs: update.md documents the check" ||
    fail "docs: update.md mention missing"
grep -q 'update-check' "$REPO/docs/concepts/wrapper.md" &&
    pass "docs: wrapper.md mentions the daily note" ||
    fail "docs: wrapper.md mention missing"

echo ""
if [ "$failures" -eq 0 ]; then
    echo "  ${GREEN}All update-check tests passed.${NC}"
    exit 0
fi
echo "  ${RED}$failures update-check test(s) failed.${NC}"
exit 1
