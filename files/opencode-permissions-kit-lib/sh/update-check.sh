#!/bin/sh
# opencode permissions kit -- sh/update-check.sh
# Kit update check helpers (issue #358): compare the installed VERSION
# against the tracking channel's VERSION file, plus the once-per-day
# cache the wrapper's banner notice rides on. Sourced lib — no set -e:
# the wrapper's hot path fails open (agent/conventions.md "Shell
# security", fail loud vs fail open); every function returns 0 unless
# its contract says otherwise.
#
# Consumers:
#   bin/opencode-as-opencode  daily check on the first interactive start
#                            of the day, note in the banner (headless
#                            starts never reach it)
#   management/status.sh      live row in the Core section (no caching —
#                            status must not write the invoking user's
#                            cache; root runs would create root-owned
#                            state in the developer's $HOME)
#
# OPK_UPDATE_CHECK=0 disables every network probe and state write in
# this lib (e2e hermeticity, air-gapped hosts); callers render their
# "disabled" shape instead.

# Mirror base the channel ref resolves against. Overridable for tests —
# file:// fixtures work, curl reads them like any URL. Deliberate test
# seam, honored wherever the lib is sourced: a stale export in a user
# environment overrides the documented default (accepted residual,
# review #365 a S2 — no privilege boundary: the wrapper runs as the
# invoking user).
KIT_UPDATE_HOST="${KIT_UPDATE_HOST:-https://raw.githubusercontent.com/steffenmaechtel/opencode-permissions-kit}"
# One bounded request per day (wrapper) or per run (status): 3 s covers
# DNS + TLS + a ~10-byte body generously; offline the bound caps the
# cost of the silence (precedent: the advisory probes' bounds). Same
# seam status as KIT_UPDATE_HOST above.
KIT_UPDATE_TIMEOUT="${KIT_UPDATE_TIMEOUT:-3}"

# kit_update_version_cmp <a> <b>: gt | lt | eq. Own copy of the sort -V
# idiom, not a dependency on advisories.sh: status.sh sources this lib
# in its Core section, BEFORE its advisory block sources that database —
# pulling it in here would load the advisory data twice (and make the
# Core row fail on a missing advisory lib it never needed).
kit_update_version_cmp() {
    _kuvc_hi=$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)
    if [ "$_kuvc_hi" = "$1" ] && [ "$_kuvc_hi" = "$2" ]; then
        printf 'eq\n'
    elif [ "$_kuvc_hi" = "$1" ]; then
        printf 'gt\n'
    else
        printf 'lt\n'
    fi
}

# kit_update_is_tag <ref>: rc 0 when the channel is an exact version pin
# (repo tags are bare x.y.z, no 'v' prefix). A pin never moves — no
# fetch can ever report anything new, so callers skip the request.
kit_update_is_tag() {
    printf '%s' "$1" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+'
}

# kit_update_fetch_version <channel>: the channel's remote VERSION on
# stdout, or empty + rc 1 (offline, blocked, malformed). The body is
# untrusted network data: shape-gated to exactly one bare x.y.z line
# here, so no caller can print raw bytes into a banner or a report row
# (grep -x alone is not enough — it matches PER LINE, so a two-line
# body of two versions passed). The channel reaches a URL path segment
# — charset-gated first (update.sh validates the stamp on write; this
# covers a hand-edited install.conf).
kit_update_fetch_version() {
    # Self-gated (review #365 a Q10): the header promises the opt-out
    # disables every network probe IN THIS LIB — it must hold per
    # function, not per call site, or a future direct caller bypasses
    # it silently.
    [ "${OPK_UPDATE_CHECK:-1}" = 0 ] && return 1
    _kufv_channel="$1"
    printf '%s' "$_kufv_channel" | grep -qxE '[A-Za-z0-9][A-Za-z0-9._/-]*' || return 1
    case "$_kufv_channel" in *..*) return 1 ;; esac
    # --max-filesize bounds the body BEFORE it is buffered into the
    # shell variable (review #365 a S1): the shape gates below reject
    # oversized content, but without the bound a hostile mirror's huge
    # body is paid in memory first (a VERSION file is ~10 bytes; 64 KiB
    # is generous).
    _kufv_ver=$(curl -fsSL --max-time "$KIT_UPDATE_TIMEOUT" --max-filesize 65536 \
        "$KIT_UPDATE_HOST/$_kufv_channel/VERSION" 2>/dev/null || true)
    _kufv_nl='
'
    _kufv_ver=${_kufv_ver%"$_kufv_nl"}
    case "$_kufv_ver" in *"$_kufv_nl"*) return 1 ;; esac
    printf '%s' "$_kufv_ver" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' || return 1
    printf '%s\n' "$_kufv_ver"
}

# kit_update_state_path: the invoking user's daily cache. Per user, not
# per machine: the wrapper runs as whoever typed `opencode`, and a
# shared file would race root and developer writes (see header).
kit_update_state_path() {
    printf '%s\n' "${HOME:-}/.cache/opencode-permissions-kit/update-check"
}

# kit_update_daily_note <local-version> <channel>: the banner note line
# (no colors — the wrapper adds them), or nothing. Network at most once
# per day: the first start of the day re-checks and re-stamps the cache,
# every later start replays the cached verdict. Fail-open everywhere —
# a missing HOME, an unwritable cache, a missing curl, or a dead network
# means no note, never a blocked or delayed start.
kit_update_daily_note() {
    _kudn_local="$1"
    _kudn_channel="${2:-master}"
    # Operator opt-out (e2e, air-gapped hosts): no fetch, no state read
    # or write, no note.
    [ "${OPK_UPDATE_CHECK:-1}" = 0 ] && return 0
    _kudn_today=$(date +%Y-%m-%d 2>/dev/null || printf '')
    _kudn_path=""
    _kudn_state=""
    _kudn_ver=""
    _kudn_date=""
    if [ -n "${HOME:-}" ]; then
        _kudn_path=$(kit_update_state_path)
        if [ -f "$_kudn_path" ]; then
            # The cache is user-writable data, not kit state — shape-gate
            # every field (a garbaged file degrades to a fresh check).
            _kudn_s=$(sed -n 's/^STATE=//p' "$_kudn_path" 2>/dev/null | tail -1)
            case "$_kudn_s" in
                current | available | unknown | pinned) _kudn_state=$_kudn_s ;;
            esac
            _kudn_d=$(sed -n 's/^DATE=//p' "$_kudn_path" 2>/dev/null | tail -1)
            printf '%s' "$_kudn_d" | grep -qxE '[0-9]{4}-[0-9]{2}-[0-9]{2}' && _kudn_date=$_kudn_d
            _kudn_v=$(sed -n 's/^VER=//p' "$_kudn_path" 2>/dev/null | tail -1)
            printf '%s' "$_kudn_v" | grep -qxE '[0-9]+\.[0-9]+\.[0-9]+' && _kudn_ver=$_kudn_v
            # a verdict without its version, or vice versa, is unusable
            [ "$_kudn_state" = available ] && [ -z "$_kudn_ver" ] && _kudn_state=""
        fi
    fi
    if [ -n "$_kudn_today" ] && [ "$_kudn_date" != "$_kudn_today" ]; then
        # First start of the day: re-check, re-stamp.
        if kit_update_is_tag "$_kudn_channel"; then
            _kudn_state=pinned
            _kudn_ver=""
        elif command -v curl >/dev/null 2>&1; then
            _kudn_remote=$(kit_update_fetch_version "$_kudn_channel" || printf '')
            if [ -n "$_kudn_remote" ]; then
                if [ "$(kit_update_version_cmp "$_kudn_remote" "$_kudn_local")" = gt ]; then
                    _kudn_state=available
                    _kudn_ver=$_kudn_remote
                else
                    # equal or behind: a channel that moved backwards
                    # after a channel switch is not an update
                    _kudn_state=current
                    _kudn_ver=""
                fi
            else
                # Offline or blocked today: keep yesterday's verdict (a
                # known-available note stays visible), else unknown;
                # never retry within the day when the cache is writable
                # — an offline host must not pay the bound on every
                # start. (An UNWRITABLE cache cannot be stamped and
                # degrades to a re-check on every start — still no
                # note, never a blocked start; review #365 a M1/Q6.)
                if [ "$_kudn_state" != available ]; then
                    _kudn_state=unknown
                    _kudn_ver=""
                fi
            fi
        fi
        # No curl on PATH: keep the old verdict and DON'T stamp the day
        # (the presence probe is free — retry on the next start).
        if [ -n "$_kudn_path" ] && command -v curl >/dev/null 2>&1; then
            if mkdir -p "${_kudn_path%/*}" 2>/dev/null; then
                # 2>/dev/null BEFORE the target redirect: dash processes
                # redirections left to right, so with the old order the
                # open error of >"$path" escaped to the terminal
                # ("cannot create ...") — a stray line on the banner of
                # a degraded host (review #365 a M1, verifier-evidenced).
                printf 'DATE=%s\nSTATE=%s\nVER=%s\n' "$_kudn_today" "$_kudn_state" "$_kudn_ver" \
                    2>/dev/null >"$_kudn_path" || true
            fi
        fi
    fi
    if [ "$_kudn_state" = available ] && [ -n "$_kudn_ver" ]; then
        # Replay guard (review #365 a S3): a cached verdict from BEFORE
        # a same-day `opk update` must not advertise a version the
        # install no longer lacks — compare the cached remote against
        # the CURRENT local version (equal or older = nothing to show).
        if [ "$(kit_update_version_cmp "$_kudn_ver" "$_kudn_local")" = gt ]; then
            printf 'kit %s is available (installed: %s) — update with: sudo opk update\n' \
                "$_kudn_ver" "$_kudn_local"
        fi
    fi
    return 0
}

return 0
