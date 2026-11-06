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

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/../.."
LIB="$REPO/files/opencode-permissions-kit-lib/sh/update-check.sh"
WRAPPER="$REPO/files/opencode-permissions-kit-lib/bin/opencode-as-opencode"
STATUS="$REPO/files/opencode-permissions-kit-lib/management/status.sh"
STATUS_CORE="$REPO/files/opencode-permissions-kit-lib/sh/status-core.sh"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/opencode-permissions-kit-lib/management/update.sh"
DEPLOYLIB="$REPO/files/opencode-permissions-kit-lib/sh/deploy-lib.sh"
# Shared harness (issue #394): pass/fail, colors, counters
# (and check/assert_eq where present) live in lib/harness.sh now.
. "$SCRIPT_DIR/lib/harness.sh"

if [ -f "$LIB" ]; then
    # shellcheck disable=SC1090  # the shipped lib under test
    . "$LIB"
else
    # Labeled presence pin (review #365 a Q3): the old comment claimed a
    # pin "below" that never existed — a missing lib truncated the suite
    # without a FAIL label.
    fail "shipped lib sh/update-check.sh not found at $LIB (run from the checkout)"
fi

WORK="$(work_new)"

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
# Oversized body is rejected — honest scope (round b R2): this pin
# observes the OUTCOME (rejection), not the buffering bound itself; a
# body that is both oversized AND shape-valid cannot exist (a valid
# VERSION is one short line), so the mechanism is pinned by the
# wiring grep below instead. The shape gate would reject this
# two-line body with or without --max-filesize.
mkdir -p "$WORK/kit/huge"
{
    printf '0.0.59\n'
    head -c 70000 /dev/zero | tr '\0' 'x'
} >"$WORK/kit/huge/VERSION"
if KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version huge >/dev/null 2>&1; then
    fail "fetch: oversized body must be rejected"
else
    pass "fetch: oversized body rejected"
fi
grep -q -- '--max-filesize 65536' "$LIB" &&
    pass "fetch: curl invocation carries the --max-filesize bound (wiring)" ||
    fail "fetch: --max-filesize bound missing from the curl invocation"
# The opt-out self-gates INSIDE the fetch function (round a Q10, pin
# per round b R3): with OPK_UPDATE_CHECK=0 the fetch must refuse even
# against a live, well-formed fixture (a shape-invalid one would fail
# either way and mask the gate).
fixture_channel selfgate 1.2.3
if OPK_UPDATE_CHECK=0 KIT_UPDATE_HOST="$KIT_HOST" kit_update_fetch_version selfgate >/dev/null 2>&1; then
    fail "fetch: OPK_UPDATE_CHECK=0 must refuse the probe (self-gate)"
else
    pass "fetch: OPK_UPDATE_CHECK=0 refuses the probe (self-gate)"
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
# The daily gate, pinned by COUNTING requests (review #365 a Q1): a
# curl stub on PATH serves 0.0.59 and records every invocation. The
# same-day second start must replay the cache WITHOUT refetching. The
# old pin (delete the fixture, assert the note survives) could not
# discriminate — the offline arm KEEPS yesterday's available verdict,
# so even a fully broken gate still printed the note.
rm -rf "${WORK:?}/stubbin" "${WORK:?}/curl-count"
mkdir -p "$WORK/stubbin"
printf '#!/bin/sh\necho x >>"%s/curl-count"\nprintf "0.0.59\\n"\n' "$WORK" >"$WORK/stubbin/curl"
chmod 755 "$WORK/stubbin/curl"
rm -rf "${HOME_FIX:?}"
mkdir -p "$HOME_FIX"
_out=$(PATH="$WORK/stubbin:$PATH" HOME="$HOME_FIX" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 master || true)
case "$_out" in
    *"kit 0.0.59 is available"*) ;;
    *) fail "daily gate: stubbed first start produced no note (got '$_out')" ;;
esac
_out=$(PATH="$WORK/stubbin:$PATH" HOME="$HOME_FIX" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 master || true)
case "$_out" in
    *"kit 0.0.59 is available"*)
        pass "daily note: same-day start replays the cache"
        ;;
    *)
        fail "daily note: same-day start replay broken (got '$_out')"
        ;;
esac
if [ "$(wc -l <"$WORK/curl-count" 2>/dev/null || echo 0)" = 1 ]; then
    pass "daily gate: second same-day start does not refetch (1 request counted)"
else
    fail "daily gate: expected exactly 1 request, got $(wc -l <"$WORK/curl-count" 2>/dev/null || echo 0)"
fi
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
# available without a usable VER must not replay — re-aimed at the
# CONSTRUCT (review #365 a Q2): the old pin asserted empty output,
# which the replay guard's -n check makes output-inert either way (a
# deleted reset shipped green). The construct's observable is the
# STAMPED STATE: with the reset present, a failed refresh normalizes
# the unusable verdict to unknown; with it deleted, the offline arm
# keeps 'available'. Stale DATE = deterministic, no live clock.
printf 'DATE=2000-01-01\nSTATE=available\nVER=\n' >"$_cache"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 stable || true)
[ -z "$_out" ] &&
    pass "available without VER: no replay, no note" ||
    fail "available without VER: replayed a versionless note (got '$_out')"
_state=$(sed -n 's/^STATE=//p' "$_cache" 2>/dev/null | tail -1)
[ "$_state" = "unknown" ] &&
    pass "available without VER: unusable verdict normalized to unknown in the stamp" ||
    fail "available without VER: stamp says STATE='$_state' (want unknown — reset construct broken?)"

echo "-- failure arms (review #365 a M1) --"
# date failing: today resolves empty -> the refresh gate stays closed
# and yesterday's verdict replays verbatim (no crash, no refetch).
rm -rf "${HOME_FIX:?}" "${WORK:?}/stubdate"
mkdir -p "$HOME_FIX/.cache/opencode-permissions-kit" "$WORK/stubdate"
printf '#!/bin/sh\nexit 1\n' >"$WORK/stubdate/date"
chmod 755 "$WORK/stubdate/date"
printf 'DATE=2000-01-01\nSTATE=available\nVER=9.9.9\n' >"$_cache"
_out=$(PATH="$WORK/stubdate:$PATH" HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" \
    OPK_UPDATE_CHECK=1 kit_update_daily_note 0.0.58 master || true)
case "$_out" in
    *"kit 9.9.9 is available"*)
        pass "date failing: stale verdict replays, no crash"
        ;;
    *)
        fail "date failing: expected stale-verdict replay (got '$_out')"
        ;;
esac
# Unwritable cache, root-proof variant: a path component exists as a
# FILE, so mkdir -p fails — run 1 must still render the note and stay
# silent on stderr (dash prints 'cannot create ...' past a trailing
# 2>/dev/null; the redirect order in the lib is the fix); run 2 the
# same day re-checks (nothing could be stamped) and goes quiet without
# a working mirror — the documented degradation, now pinned.
rm -rf "${HOME_FIX:?}" "${WORK:?}/kit"
mkdir -p "$HOME_FIX"
fixture_channel stable 0.0.59
: >"$HOME_FIX/.cache"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 stable 2>"$WORK/arm-stderr1" || true)
case "$_out" in
    *"kit 0.0.59 is available"*)
        pass "unwritable cache (mkdir fails): first start still renders the note"
        ;;
    *)
        fail "unwritable cache (mkdir fails): no note on first start (got '$_out')"
        ;;
esac
[ ! -s "$WORK/arm-stderr1" ] &&
    pass "unwritable cache: no stray stderr on the failed stamp write" ||
    fail "unwritable cache: stderr leaked: $(cat "$WORK/arm-stderr1")"
rm -rf "${WORK:?}/kit"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 stable 2>"$WORK/arm-stderr2" || true)
[ -z "$_out" ] &&
    pass "unwritable cache: re-checks next start (unstamped), quiet without a mirror" ||
    fail "unwritable cache: second start produced '$_out'"
[ ! -s "$WORK/arm-stderr2" ] &&
    pass "unwritable cache: second start also silent on stderr" ||
    fail "unwritable cache: second start leaked stderr: $(cat "$WORK/arm-stderr2")"
# chmod-dependent arms (write-open failure, unreadable sed): mode bits
# do not stop root, and the suite may run as root on some hosts — these
# two arms are non-root only and say so when skipped (environment-
# dependent pin, marked).
if [ "$(id -u)" -ne 0 ]; then
    rm -rf "${HOME_FIX:?}" "${WORK:?}/kit"
    mkdir -p "$HOME_FIX/.cache/opencode-permissions-kit"
    chmod 555 "$HOME_FIX/.cache/opencode-permissions-kit"
    fixture_channel stable 0.0.59
    _out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK=1 \
        kit_update_daily_note 0.0.58 stable 2>"$WORK/arm-stderr3" || true)
    case "$_out" in
        *"kit 0.0.59 is available"*)
            pass "unwritable cache (open fails): note renders, no crash"
            ;;
        *)
            fail "unwritable cache (open fails): got '$_out'"
            ;;
    esac
    [ ! -s "$WORK/arm-stderr3" ] &&
        pass "unwritable cache (open fails): stray stderr suppressed (redirect order)" ||
        fail "unwritable cache (open fails): stderr leaked: $(cat "$WORK/arm-stderr3")"
    chmod 755 "$HOME_FIX/.cache/opencode-permissions-kit"
    # Unreadable cache file (write-only, mode 200): every field parse
    # degrades to empty -> fresh check names the FETCHED version.
    printf 'DATE=2000-01-01\nSTATE=available\nVER=9.9.9\n' >"$_cache"
    chmod 200 "$_cache"
    _out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK=1 \
        kit_update_daily_note 0.0.58 stable || true)
    case "$_out" in
        *"kit 0.0.59 is available"*)
            pass "unreadable cache: degrades to a fresh check (fetched version, not 9.9.9)"
            ;;
        *"kit 9.9.9 is available"*)
            fail "unreadable cache: replayed the UNREADABLE verdict (9.9.9) — sed arm broken"
            ;;
        *)
            fail "unreadable cache: got '$_out'"
            ;;
    esac
    chmod 600 "$_cache"
else
    echo "  (skip) chmod-based unwritable/unreadable arms: suite runs as root (mode bits cannot fail for root)"
fi

echo "-- replay guard (review #365 a S3) --"
# A same-day `opk update` re-stamps install.conf's VERSION; the cached
# verdict must not advertise what the install no longer lacks. Offline
# mirror + today's stamp = pure replay, deterministic even across
# midnight (a re-opened gate would fetch, fail, and KEEP the verdict).
rm -rf "${HOME_FIX:?}"
mkdir -p "$HOME_FIX/.cache/opencode-permissions-kit"
printf 'DATE=%s\nSTATE=available\nVER=0.0.59\n' "$(date +%Y-%m-%d)" >"$_cache"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.60 master || true)
[ -z "$_out" ] &&
    pass "replay guard: quiet after updating PAST the cached version" ||
    fail "replay guard: advertised an outdated update (got '$_out')"
printf 'DATE=%s\nSTATE=available\nVER=0.0.59\n' "$(date +%Y-%m-%d)" >"$_cache"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.59 master || true)
[ -z "$_out" ] &&
    pass "replay guard: quiet after updating TO the advertised version" ||
    fail "replay guard: advertised an already-installed version (got '$_out')"
printf 'DATE=%s\nSTATE=available\nVER=0.0.59\n' "$(date +%Y-%m-%d)" >"$_cache"
_out=$(HOME="$HOME_FIX" KIT_UPDATE_HOST="$OFFLINE_HOST" OPK_UPDATE_CHECK=1 \
    kit_update_daily_note 0.0.58 master || true)
case "$_out" in
    *"kit 0.0.59 is available"*)
        pass "replay guard: a genuinely newer cached version still renders"
        ;;
    *)
        fail "replay guard: legit note suppressed (got '$_out')"
        ;;
esac

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
grep -q 'ui_kv_warn "kit update" "new kit' "$STATUS_CORE" &&
    pass "status: available update renders a counted warn row" ||
    fail "status: counted warn row missing"
grep -q 'ui_kv "kit update" "unknown — live check unavailable (offline or blocked)"' "$STATUS_CORE" &&
    pass "status: offline renders an uncounted unknown row" ||
    fail "status: uncounted unknown row missing"
grep -q 'ui_kv "kit update" "pinned to' "$STATUS_CORE" &&
    pass "status: tag pin renders a neutral row" ||
    fail "status: tag-pin row missing"
grep -q 'ui_kv "kit update" "checks disabled (OPK_UPDATE_CHECK=0)"' "$STATUS_CORE" &&
    pass "status: opt-out renders a disabled row" ||
    fail "status: disabled row missing"
grep -q 'ui_kv_warn "kit update" "not checked — kit file sh/update-check.sh missing' "$STATUS_CORE" &&
    pass "status: missing lib renders a counted broken-kit warn" ||
    fail "status: missing-lib warn missing"

# Behavioral counting pin (review #365 a M2): drive the SHIPPED
# kit-update block with the SHIPPED ui.sh counters — an available
# update must bump UI_ROWS_WARN (the exit-2 cron contract rides on
# ui_kv_warn; a plain-ui_kv regression would pass every grep pin
# above while silently uncounting the row). Extract-block pattern
# per test-status.sh; the extraction ends just before the following
# `if id` line, so nested fi's stay intact.
rm -rf "${WORK:?}/kit" "${WORK:?}/m2"
mkdir -p "$WORK/m2"
fixture_channel master 0.0.59
(
    UI_SILENT=1
    export UI_SILENT
    . "$REPO/files/opencode-permissions-kit-lib/sh/ui.sh"
    . "$LIB"
    LIBDIR="$REPO/files/opencode-permissions-kit-lib"
    VERSION=0.0.58
    KIT_CHANNEL=master
    OPK_UPDATE_CHECK=1
    export KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK
    eval "$(awk '/^ *# Kit update row \(issue #358\)/{f=1} f && /^ *if id "\$OPENCODE_USER" >/{exit} f' "$STATUS_CORE")"
    printf 'warn=%s ok=%s\n' "${UI_ROWS_WARN:-0}" "${UI_ROWS_OK:-0}"
) >"$WORK/m2/out" 2>"$WORK/m2/err" || true
grep -q 'warn=1 ok=0' "$WORK/m2/out" &&
    pass "status row counts behaviorally: available update bumps the warn counter" ||
    fail "status row counting broken (got '$(cat "$WORK/m2/out")', err '$(cat "$WORK/m2/err")')"
fixture_channel master 0.0.58
(
    UI_SILENT=1
    export UI_SILENT
    . "$REPO/files/opencode-permissions-kit-lib/sh/ui.sh"
    . "$LIB"
    LIBDIR="$REPO/files/opencode-permissions-kit-lib"
    VERSION=0.0.58
    KIT_CHANNEL=master
    OPK_UPDATE_CHECK=1
    export KIT_UPDATE_HOST="$KIT_HOST" OPK_UPDATE_CHECK
    eval "$(awk '/^ *# Kit update row \(issue #358\)/{f=1} f && /^ *if id "\$OPENCODE_USER" >/{exit} f' "$STATUS_CORE")"
    printf 'warn=%s ok=%s\n' "${UI_ROWS_WARN:-0}" "${UI_ROWS_OK:-0}"
) >"$WORK/m2/out2" 2>>"$WORK/m2/err" || true
grep -q 'warn=0 ok=1' "$WORK/m2/out2" &&
    pass "status row counts behaviorally: current install bumps the ok counter" ||
    fail "ok-row counting broken (got '$(cat "$WORK/m2/out2")')"

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
