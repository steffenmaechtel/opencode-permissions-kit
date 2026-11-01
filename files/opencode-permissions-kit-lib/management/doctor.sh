#!/bin/sh
# opencode permissions kit -- doctor.sh (issue #313, stage 1)
#
# Per-project deep diagnosis for the rootless ownership failure class
# (#312): container processes cannot futimes/chmod/chown files whose
# host uid is UNMAPPED in the daemon's user namespace -- data writes
# still succeed, builds abort with EPERM (gulp/vinyl-fs dest, rsync -t,
# cp -p, tar -xpf). doctor reads the project's opk.json policy (a file
# the project commits; format below and in docs/reference/cli.md) and
# classifies every entry in the declared container trees:
#   mapped-safe  owner is mapped into the daemon userns (the daemon uid
#                or one of its subuid ranges) -> container metadata ops
#                are allowed
#   at-risk      owner unmapped (usually the developer's uid) -> the
#                #312 EPERM class
#
# The mapped ranges come from the LIVE user namespaces, never from
# /etc/subuid -- on the #312 reference host the subuid database is
# empty although the mapping demonstrably exists. Every process carries
# its uid_map in /proc, world-readable; the daemon's own userns and the
# containers nested in it map onto the same host-uid set, so scanning
# the maps whose zero-row points at the daemon user is enough (and it
# needs no docker socket access at all -- #313 open question 2 stays
# open, this is the socket-free primary source). Fallback when no such
# namespace is found (daemon down): daemon-uid-only matching plus an
# explicit "range unverified" warn -- subuid-owned files may then read
# as at-risk until the backend runs again.
#
# Read-only. No sudo: stat, /proc/<pid>/uid_map and install.conf are
# world-readable. Fix rows point at existing commands only
# (sudo opk handover opencode <tree>); doctor itself never changes a
# thing.
#
# opk.json -- strict JSON (JSONC was rejected deliberately: jq and
# other tooling must keep reading it, and strict editor validation
# catches malformed policy files; documentation lives in "note"
# fields, not comments). Tolerant read: unknown keys are ignored,
# "version" is reserved for migrations (only 1 exists today).
#
# CLI:  opk doctor [project-root]      (default: the current directory)
# Exit codes (the status.sh contract): 0 all declared trees healthy,
# 1 at-risk finding(s) or a rejected policy, 2 warning(s) only,
# 64 usage error.
#
# Run directly:
#   /usr/local/lib/opencode-permissions-kit/management/doctor.sh [path]
# or from a checkout:
#   files/opencode-permissions-kit-lib/management/doctor.sh [path]
# Deliberately set -u ONLY (no -e): a read-only report -- one failing
# tree must not kill the remaining verdicts (same fail-soft class as
# status.sh).
set -u

# --- shared UI helpers (checkout-first, status.sh pattern) ------------------------
UI_LIB="$(cd "$(dirname "$0")" && pwd)/../sh/ui.sh"
[ -f "$UI_LIB" ] || UI_LIB="/usr/local/lib/opencode-permissions-kit/sh/ui.sh"
if [ -f "$UI_LIB" ]; then
    # shellcheck disable=SC1090
    . "$UI_LIB"
else
    echo "error: ui.sh not found (expected it next to doctor.sh in a checkout, or in the kit library)" >&2
    exit 1
fi

# --- CLI --------------------------------------------------------------------------
if [ "$#" -gt 1 ]; then
    echo "usage: opk doctor [project-root]   (default: the current directory)" >&2
    exit 64
fi
DOCTOR_ROOT="${1:-.}"
case "$DOCTOR_ROOT" in
    -*)
        echo "usage: opk doctor [project-root]   (default: the current directory)" >&2
        exit 64
        ;;
esac
DOCTOR_ROOT="$(realpath -m "$DOCTOR_ROOT" 2>/dev/null || printf '%s' "$DOCTOR_ROOT")"
if [ ! -d "$DOCTOR_ROOT" ]; then
    ui_error "doctor: no such directory: $DOCTOR_ROOT"
    exit 64
fi

# --- the daemon user (the rootless backend runs as this user) --------------------
INSTALL_CONF="${OPK_INSTALL_CONF:-/etc/opencode-permissions-kit/install.conf}"
if [ ! -f "$INSTALL_CONF" ]; then
    ui_error "doctor: $INSTALL_CONF not found -- is the kit installed?"
    exit 1
fi
# sed, not source: doctor needs one key, and a sourced conf must not be
# able to shadow the script's own variables. Quotes are stripped in case
# a future writer quotes the value (handover reads it unquoted today).
DOCTOR_USER="$(sed -n 's/^OPENCODE_USER=//p' "$INSTALL_CONF" | tail -1 | sed 's/^"//;s/"$//')"
if [ -z "$DOCTOR_USER" ]; then
    ui_error "doctor: install.conf has no OPENCODE_USER -- is the kit installed?"
    exit 1
fi
DOCTOR_DAEMON_UID="$(id -u "$DOCTOR_USER" 2>/dev/null || true)"
if [ -z "$DOCTOR_DAEMON_UID" ]; then
    ui_error "doctor: user '$DOCTOR_USER' (OPENCODE_USER) does not exist"
    exit 1
fi

# --- resolve the mapped host-uid set ----------------------------------------------
# Test seam (unit tests fixture the pid tree; production always reads
# the live /proc -- same override pattern as OPK_INSTALL_CONF).
DOCTOR_PROC="${OPK_DOCTOR_PROC_ROOT:-/proc}"

WORK="$(mktemp -d)"
# Signal handlers EXIT (#344 a C1): a non-exiting INT/TERM handler runs the
# cleanup and dash RESUMES the script — with $WORK already deleted, every
# later redirect fails and the remaining trees render cascade garbage. The
# house shape (install.sh, update.sh, config.sh): cleanup on EXIT, cleanup
# PLUS exit on the signals.
# shellcheck disable=SC2317  # invoked via trap only
_doctor_cleanup() { rm -rf "$WORK"; }
trap _doctor_cleanup EXIT
trap '_doctor_cleanup; exit 1' INT TERM

# doctor_userns_ranges <proc_root> <daemon_uid>
# Prints one "start:count" line per mapped host-uid range found in any
# live user namespace whose zero row maps to the daemon user. Shape
# rules (validated per row, the whole file is dropped on any violation):
#   - rows are three integers: ns-uid, host-uid, count
#   - the FIRST row must map ns-uid 0 to the daemon uid (the daemon's
#     own userns and its containers do; a foreign user's namespace does
#     not -- its 0 maps to THEIR uid)
#   - the full map (count 4294967295) is the init namespace: skipped
# Buffer-then-emit: rows of a file that violates later must not leak.
doctor_userns_ranges() {
    _du_root="$1"
    _du_uid="$2"
    for _du_map in "$_du_root"/[0-9]*/uid_map; do
        [ -f "$_du_map" ] || continue
        _du_ok=1
        _du_row0=0
        _du_buf=""
        while read -r _du_in _du_out _du_cnt _du_extra; do
            [ -n "$_du_in" ] || continue
            # kernel writes these files; still, only digits ever reach
            # the buffer (the ranges feed awk as data)
            case "${_du_in}${_du_out}${_du_cnt}" in
                *[!0-9]*)
                    _du_ok=0
                    break
                    ;;
            esac
            if [ -z "$_du_out" ] || [ -z "$_du_cnt" ] || [ -n "$_du_extra" ]; then
                _du_ok=0
                break
            fi
            if [ "$_du_row0" = 0 ]; then
                if [ "$_du_in" != 0 ] || [ "$_du_out" != "$_du_uid" ]; then
                    _du_ok=0
                    break
                fi
                # the init namespace maps everything -- not a daemon userns
                [ "$_du_cnt" = 4294967295 ] && _du_ok=0
                _du_row0=1
            fi
            _du_buf="$_du_buf $_du_out:$_du_cnt"
        done <"$_du_map" 2>/dev/null || continue
        if [ "$_du_ok" = 1 ] && [ -n "$_du_buf" ]; then
            # shellcheck disable=SC2086  # buffer charset: [0-9: ] only, validated above
            printf '%s\n' $_du_buf
        fi
    done
}

doctor_userns_ranges "$DOCTOR_PROC" "$DOCTOR_DAEMON_UID" | sort -u >"$WORK/ranges.raw"
DOCTOR_RANGE_VERIFIED=0
[ -s "$WORK/ranges.raw" ] && DOCTOR_RANGE_VERIFIED=1
# The daemon uid itself is always mapped (container root is the daemon
# user host-side) -- the fallback floor when no namespace was found.
# Appended only when no live range already starts at the daemon uid
# (#344 a C5): a daemon namespace mapping count>1 there would otherwise
# survive sort -u next to the floor row and display the uid twice.
if ! awk -F: -v u="$DOCTOR_DAEMON_UID" '$1 == u { found = 1 } END { exit !found }' "$WORK/ranges.raw"; then
    printf '%s:1\n' "$DOCTOR_DAEMON_UID" >>"$WORK/ranges.raw"
fi
sort -u "$WORK/ranges.raw" >"$WORK/ranges"
# one "start count" pair list for awk ("1001 1 165536 65536")
DOCTOR_RANGES="$(awk -F: '{ printf "%s %s ", $1, $2 }' "$WORK/ranges")"

# --- report header ----------------------------------------------------------------
ui_section "Doctor -- container-tree ownership (#312 class)"
ui_kv "project root" "$DOCTOR_ROOT"
ui_kv "daemon user" "$DOCTOR_USER (uid $DOCTOR_DAEMON_UID)"
if [ "$DOCTOR_RANGE_VERIFIED" = 1 ]; then
    ui_kv "mapped range" "$(awk -F: '
        { if ($2 == 1) printf "%s%s", sep, $1
          else printf "%s%s-%s", sep, $1, $1 + $2 - 1
          sep = ", " }' "$WORK/ranges") -- live uid_map"
else
    ui_kv_warn "mapped range" "unverified -- no user namespace of '$DOCTOR_USER' found (backend down?)"
    ui_detail "matching the daemon uid only; subuid-owned files may classify at-risk"
    ui_detail "until the backend runs -- re-run doctor with the containers up"
fi

# --- load the policy ---------------------------------------------------------------
if [ ! -f "$DOCTOR_ROOT/opk.json" ]; then
    ui_warn "no opk.json found in $DOCTOR_ROOT -- nothing to check"
    ui_detail "declare the trees your container builds write to (docs/reference/cli.md, 'doctor')"
    exit 2
fi
ui_kv "policy" "$DOCTOR_ROOT/opk.json"

# doctor_load_policy <root>
# Validates opk.json (strict JSON) and prints one "path<TAB>note" line
# per declared container tree. python3 does shape validation -- the
# paths reach find as argv below, so they are allowlisted here, not
# just read (shell-security convention). Failures print "opk.json: ..."
# to stderr and exit non-zero.
doctor_load_policy() {
    python3 - "$1/opk.json" <<'PYEOF'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        doc = json.load(f)
except OSError as e:
    sys.stderr.write("opk.json: unreadable: %s\n" % e)
    sys.exit(1)
except ValueError as e:
    sys.stderr.write("opk.json: not valid JSON: %s\n" % e)
    sys.exit(1)

def bad(msg):
    sys.stderr.write("opk.json: %s\n" % msg)
    sys.exit(1)

if not isinstance(doc, dict):
    bad("top level must be a JSON object")
# Strict version typing (#344 a C4): Python coerces True == 1 and 1.0 == 1,
# so a bare != would accept JSON true/1.0 as "version 1"
version = doc.get("version", 1)
if isinstance(version, bool) or not isinstance(version, int) or version != 1:
    bad("unsupported version %r -- this kit reads version 1" % (version,))
trees = doc.get("containerTrees", [])
if not isinstance(trees, list):
    bad("containerTrees must be an array")

def path_error(p):
    if not isinstance(p, str) or not p:
        return "tree path must be a non-empty string"
    if p.startswith("/") or p == ".":
        return "tree path %r must be relative to the project root" % p
    if "\\" in p:
        return "tree path %r must not contain backslashes" % p
    for ch in p:
        if ord(ch) < 32:
            return "tree path %r must not contain control characters" % p
    # Shell-significant characters (#344 a S3): the fix hints interpolate
    # the path into a copy-paste sudo command — a committed opk.json must
    # never be able to steer that command
    if any(c in p for c in "'\"`$;"):
        return "tree path %r must not contain shell-significant characters: quotes, backtick, dollar, semicolon" % p
    for comp in p.split("/"):
        if comp in ("", ".", ".."):
            return "tree path %r must not contain empty, '.' or '..' components" % p
        if any(c in comp for c in "*?["):
            return "tree path %r must not contain glob characters (no wildcards)" % p
    return None

for i, entry in enumerate(trees):
    if isinstance(entry, str):
        rel, note = entry, ""
    elif isinstance(entry, dict):
        rel, note = entry.get("path"), entry.get("note", "")
        if rel is None:
            bad('containerTrees[%d]: missing "path"' % i)
    else:
        bad("containerTrees[%d]: must be a string or an object" % i)
    err = path_error(rel)
    if err:
        bad("containerTrees[%d]: %s" % (i, err))
    if not isinstance(note, str):
        bad('containerTrees[%d]: "note" must be a string' % i)
    # Collapse first (tabs/newlines would break the TSV round-trip), then
    # gate control characters (#344 a S4): the surviving non-whitespace
    # control chars (ESC, BEL, ...) reach the terminal via ui_detail —
    # the same gate the path has, now on both fields
    note = " ".join(note.split())
    for ch in note:
        if ord(ch) < 32:
            bad('containerTrees[%d]: "note" must not contain control characters' % i)
    sys.stdout.write("%s\t%s\n" % (rel, note))
PYEOF
}

if ! doctor_load_policy "$DOCTOR_ROOT" >"$WORK/trees"; then
    ui_error "doctor: the policy file was rejected -- fix opk.json (format: docs/reference/cli.md)"
    exit 1
fi

# --- scan each declared tree --------------------------------------------------------
# doctor_classify <uids-file> <daemon-uid> <ranges>
# Counts owners from a UID-ONLY stream (find -printf '%U\n'): exactly one
# numeric line per entry, so a filename containing a newline cannot
# corrupt the counts or invent uids (#344 a S1). Emits
# "SUM<TAB>safe<TAB>risk" and one "UID<TAB>uid<TAB>count" per unmapped uid.
doctor_classify() {
    awk -v daemon="$2" -v ranges="$3" '
        BEGIN {
            n = split(ranges, r, " ")
            for (i = 1; i + 1 <= n; i += 2) {
                rs[++m] = r[i] + 0
                rc[m] = r[i + 1] + 0
            }
        }
        {
            uid = $1 + 0
            if (uid == daemon + 0) { safe++; next }
            ok = 0
            for (j = 1; j <= m; j++)
                if (uid >= rs[j] && uid < rs[j] + rc[j]) { ok = 1; break }
            if (ok) { safe++; next }
            risk++
            uids[uid]++
        }
        END {
            print "SUM\t" safe + 0 "\t" risk + 0
            for (u in uids) print "UID\t" u "\t" uids[u]
        }
    ' "$1"
}

# doctor_examples <tsv-file> <daemon-uid> <ranges>
# Display-only companion pass over "uid<TAB>path" lines: prints the
# paths of the first three at-risk entries. Paths render truncated at
# the first whitespace run (awk default FS) -- deliberate and harmless:
# examples point a human at the tree; the counts come from the
# newline-safe uid stream (#344 a S1/S2).
doctor_examples() {
    awk -v daemon="$2" -v ranges="$3" '
        BEGIN {
            n = split(ranges, r, " ")
            for (i = 1; i + 1 <= n; i += 2) {
                rs[++m] = r[i] + 0
                rc[m] = r[i + 1] + 0
            }
        }
        {
            uid = $1 + 0
            if (uid == daemon + 0) next
            ok = 0
            for (j = 1; j <= m; j++)
                if (uid >= rs[j] && uid < rs[j] + rc[j]) { ok = 1; break }
            if (ok) next
            if (exn < 3) { exn++; print $2 }
            if (exn >= 3) exit
        }
    ' "$1"
}

DOCTOR_TAB="$(printf '\t')"
while IFS="$DOCTOR_TAB" read -r DOCTOR_PATH DOCTOR_NOTE; do
    # Belt over the python allowlist: the forms that must never reach
    # find as an operand (absolute, trailing slash, dot/dotdot
    # components in every position, interior empty components,
    # backslash) are re-checked in shell -- defense in depth, not the
    # primary gate (#344 a S5, b R3).
    case "$DOCTOR_PATH" in
        /* | */ | . | ./* | .. | ../* | */. | */./* | */.. | */../* | *//* | *\\*)
            ui_kv_warn "container tree" "$DOCTOR_PATH -- rejected path form, skipped"
            continue
            ;;
    esac
    DOCTOR_TREE="$DOCTOR_ROOT/$DOCTOR_PATH"
    if [ ! -e "$DOCTOR_TREE" ]; then
        ui_kv_warn "container tree" "$DOCTOR_PATH -- declared but missing (fresh clone? build or create it first)"
        continue
    fi
    if [ -L "$DOCTOR_TREE" ]; then
        ui_kv_warn "container tree" "$DOCTOR_PATH -- a symlink, skipped (declare the real tree)"
        continue
    fi
    if [ ! -d "$DOCTOR_TREE" ]; then
        ui_kv_warn "container tree" "$DOCTOR_PATH -- not a directory, skipped"
        continue
    fi

    # Pass 1 (authoritative counts): the uid-only stream is newline-safe
    # by construction -- a filename containing a newline cannot split a
    # numeric uid line (#344 a S1).
    find "$DOCTOR_TREE" -printf '%U\n' >"$WORK/uids" 2>"$WORK/scan.err"
    if [ -s "$WORK/scan.err" ]; then
        # fail loud, not fail absent: unreadable entries would silently
        # shrink the tree and could turn a red verdict green (#312 class
        # feeds on exactly such partial views)
        ui_kv_warn "container tree" "$DOCTOR_PATH -- scan incomplete: $(wc -l <"$WORK/scan.err") unreadable entries"
        ui_detail "run doctor as the tree owner (or with sudo) to get a complete verdict"
    fi
    doctor_classify "$WORK/uids" "$DOCTOR_DAEMON_UID" "$DOCTOR_RANGES" >"$WORK/cls"

    _cl_safe=0
    _cl_risk=0
    _cl_uids=""
    _cl_uidn=0
    while IFS="$DOCTOR_TAB" read -r _cl_tag _cl_a _cl_b; do
        case "$_cl_tag" in
            SUM)
                _cl_safe="$_cl_a"
                _cl_risk="$_cl_b"
                ;;
            UID)
                _cl_uidn=$((_cl_uidn + 1))
                [ "$_cl_uidn" -le 4 ] && _cl_uids="$_cl_uids$_cl_a ($_cl_b), "
                ;;
        esac
    done <"$WORK/cls"
    _cl_total=$((_cl_safe + _cl_risk))

    # Pass 2 (examples): display-only, run just when there is something
    # to show -- see doctor_examples for the truncation contract.
    # stderr deliberately NOT suppressed (#344 b R4): a tree that turns
    # unreadable between the passes degrades the examples, and the raw
    # find error on the terminal is that degradation's visibility (the
    # counts stay authoritative -- pass 1 warns loudly). A deterministic
    # failure-path pin would need mid-scan timing injection (~30+ lines
    # for a LOW) -- declined per the pin-cost budget, recorded as an
    # accepted residual in round b.
    _cl_ex=""
    if [ "$_cl_risk" -gt 0 ]; then
        find "$DOCTOR_TREE" -printf '%U\t%p\n' >"$WORK/extsv"
        : >"$WORK/ex"
        doctor_examples "$WORK/extsv" "$DOCTOR_DAEMON_UID" "$DOCTOR_RANGES" >>"$WORK/ex"
        while IFS= read -r _ex_p; do
            [ -n "$_ex_p" ] || continue
            [ -n "$_cl_ex" ] && _cl_ex="$_cl_ex, "
            _cl_ex="$_cl_ex${_ex_p#"$DOCTOR_ROOT"/}"
        done <"$WORK/ex"
    fi

    if [ "$_cl_risk" -gt 0 ]; then
        ui_kv_bad "container tree" "$DOCTOR_PATH -- $_cl_risk of $_cl_total entries at-risk (unmapped owners)"
        [ -n "$_cl_uids" ] && ui_detail "at-risk owners: uid ${_cl_uids%, }"
        [ -n "$_cl_ex" ] && ui_detail "examples: $_cl_ex"
        ui_detail "container metadata ops (futimes/chmod/chown) EPERM on these -- the #312 build-breaker class"
        ui_detail "fix: sudo opk handover opencode '$DOCTOR_TREE'"
        ui_detail "or rebuild the affected outputs clean (docs/troubleshooting.md, EPERM entry)"
    elif [ "$_cl_total" -gt 0 ]; then
        ui_kv_ok "container tree" "$DOCTOR_PATH -- $_cl_total entries mapped-safe"
    else
        ui_kv "container tree" "$DOCTOR_PATH -- empty (nothing classified)"
    fi
    # the policy note is the tree's own documentation -- surface it so
    # the verdict row carries its context (SC2034 drove the decision to
    # display rather than drop it)
    [ -n "$DOCTOR_NOTE" ] && ui_detail "declared: $DOCTOR_NOTE"
done <"$WORK/trees"

# --- summary (status.sh contract) ---------------------------------------------------
# Counts snapshot BEFORE the verdict row prints, so the row itself
# never counts. Exit code: 0 all green, 1 alert(s), 2 warning(s) only.
if [ "$UI_ROWS_BAD" -gt 0 ]; then
    ui_kv_bad "result" "$UI_ROWS_BAD alert(s), $UI_ROWS_WARN warning(s) -- fix with the handover commands above"
    exit 1
fi
if [ "$UI_ROWS_WARN" -gt 0 ]; then
    ui_kv_warn "result" "$UI_ROWS_WARN warning(s), no at-risk findings"
    exit 2
fi
ui_kv_ok "result" "all declared container trees mapped-safe"
exit 0
