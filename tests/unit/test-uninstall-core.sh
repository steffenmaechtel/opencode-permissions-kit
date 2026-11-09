#!/bin/sh
# Unit tests for sh/uninstall-core.sh (issue #346, wave 4): the uninstall
# run's section functions, sourced from the lib the way uninstall.sh
# sources it — the log.sh pin pattern (source the lib, call the function,
# stub the environment). This suite is the #396 payoff of wave 4: the
# block-extraction pins test-uninstall.sh used to carry (project loop,
# rc-observing runner, OPENCODE_USER gate, config-dirs section, prompt_yn,
# group/user/audit-log blocks) became sourcing pins here. Two extraction
# pins remain, deliberately (review-concept.md, "Review focus: shipped
# code first, pins at a floor" — the pins work; converting them is
# recorded as pin polish, not owed here): the W2 agents-backup gate (its
# success fixture needs a readable dir at the literal /home/<agent> path —
# the sed scratch rewrite is the only hermetic shape for THAT leg) and the
# F27 bridge consent arm (kept standalone-eval'd with stubs; a grep-shadow
# sourcing drive is feasible but is the same polish class). The root-run rm
# orchestration is e2e territory (category 3, no coverage promise).
# Covers:
#   - sourcing purity: definitions only, zero top-level side effects
#   - all 17 section/helper functions defined by sourcing
#   - the entry resolves the lib checkout-first with the deployed $LIBDIR
#     fallback (the update.sh resolver shape — uninstall.sh runs from the
#     deployed tree via `opk uninstall`, unlike install.sh) and calls the
#     sections in the former top-level order
#   - un_opencode_user_gate: valid/canonical pass, corrupted values fall
#     back loudly (sanitized WARN), pathological spellings refused
#   - un_projects_revert driven REAL through a fixture projects.conf (the
#     screening cluster incl. writer parity, symlink/dot/slash forms,
#     per-root honesty arms, dry-run, agent-home refusal)
#   - un_config_dirs_remove / un_sudoers_remove / un_group_membership_remove
#     / un_user_remove / un_audit_log_remove arms with stubbed sudo
#   - prompt_yn answer semantics + shape under a real pty
# Run: sh tests/unit/test-uninstall-core.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/uninstall-core.sh"
UNINSTALL="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"

# Shared harness (issue #394): pass/fail, colors, counters + the work
# registry (issue #395) — no trap of our own, the harness owns cleanup.
. "$SCRIPT_DIR/lib/harness.sh"

WORK="$(work_new)"

# The lib under test, sourced ONCE here the way the entry sources it: every
# sourcing pin below calls the real functions with per-arm stubs. Purity is
# pinned first — sourcing must not run anything.
# shellcheck disable=SC1090
. "$LIB"

# --- 0. purity + definitions + resolver ----------------------------------------

_purity_out=$(sh -c '. "$1"' _ "$LIB" 2>&1) || _purity_rc=$?
if [ "${_purity_rc:-0}" = 0 ] && [ -z "$_purity_out" ]; then
    pass "sourcing uninstall-core.sh runs nothing, prints nothing"
else
    fail "sourcing uninstall-core.sh must be side-effect free (rc=${_purity_rc:-0} out=$_purity_out)"
fi

_defs="prompt_yn run_q un_rc_q un_opencode_user_gate un_context_load
un_sudoers_remove un_wrapper_remove un_cli_remove un_xdg_open_remove
un_tui_plugins_remove un_wsl_bridge_remove un_library_remove un_umask_remove
un_group_membership_remove un_user_remove un_projects_revert
un_config_dirs_remove un_audit_log_remove"
_missing=""
for _fn in $_defs; do
    sh -c '. "$1" && command -v "$2" >/dev/null' _ "$LIB" "$_fn" 2>/dev/null ||
        _missing="$_missing $_fn"
done
if [ -z "$_missing" ]; then
    pass "all 5 helpers + 13 section functions defined by sourcing"
else
    fail "functions missing after sourcing:$_missing"
fi

# The entry's resolver: checkout-first (the $0-derived caller dir —
# anchored for stdin runs, update.sh parity) WITH the deployed $LIBDIR
# fallback — the update.sh UPDATE_CORE shape, deliberately NOT
# install.sh's kit_source-without-fallback (uninstall.sh runs from the
# deployed tree via `opk uninstall`; install.sh never does). Loud abort
# when both candidates miss.
if grep -qF 'UNINSTALL_CORE="$UN_CALL_DIR/../sh/uninstall-core.sh"' "$UNINSTALL" &&
    grep -qF 'UNINSTALL_CORE="/usr/local/lib/opencode-permissions-kit/sh/uninstall-core.sh"' "$UNINSTALL" &&
    grep -qF 'error: uninstall-core.sh not found' "$UNINSTALL" &&
    ! sed 's/^[[:space:]]*#.*$//' "$UNINSTALL" | grep -q 'kit_source'; then
    pass "entry resolver: checkout-first (anchored caller dir, update.sh parity) + \$LIBDIR fallback, loud abort"
else
    fail "entry resolver shape (checkout-first + LIBDIR fallback)"
fi
# resolver sits before the first section call (order pin)
_res_ln=$(grep -n 'UNINSTALL_CORE="$UN_CALL_DIR/../sh/uninstall-core.sh"' "$UNINSTALL" | cut -d: -f1)
_ctx_ln=$(grep -n '^un_context_load$' "$UNINSTALL" | cut -d: -f1)
_first_sec_ln=$(grep -n '^un_sudoers_remove$' "$UNINSTALL" | cut -d: -f1)
if [ -n "$_res_ln" ] && [ -n "$_ctx_ln" ] && [ -n "$_first_sec_ln" ] &&
    [ "$_res_ln" -lt "$_ctx_ln" ] && [ "$_ctx_ln" -lt "$_first_sec_ln" ]; then
    pass "resolver precedes context load precedes the first section (order pin)"
else
    fail "entry order (resolver=$_res_ln ctx=$_ctx_ln first=$_first_sec_ln)"
fi
# the entry sequences every section in the former top-level order
# (un_projects_revert is indented inside its conf guard — pinned separately
# by the projects-guard pin right below)
_order="un_context_load un_sudoers_remove un_wrapper_remove un_cli_remove
un_xdg_open_remove un_tui_plugins_remove un_wsl_bridge_remove
un_library_remove un_umask_remove un_user_remove
un_config_dirs_remove un_audit_log_remove"
_prev=0
_order_ok=1
for _fn in $_order; do
    _ln=$(grep -n "^$_fn$" "$UNINSTALL" | cut -d: -f1)
    if [ -z "$_ln" ] || [ "$_ln" -le "$_prev" ]; then
        _order_ok=0
        break
    fi
    _prev=$_ln
done
if [ "$_order_ok" -eq 1 ]; then
    pass "entry calls all sections in the former top-level order"
else
    fail "entry section order (first offender: $_fn)"
fi
# the projects guard stays in the entry around the call (the lib function
# reads UNINSTALL_PROJECTS_CONF; the entry owns the conf existence check)
if grep -qF 'if [ -f "$UNINSTALL_PROJECTS_CONF" ]; then' "$UNINSTALL" &&
    grep -qF '    un_projects_revert' "$UNINSTALL" &&
    grep -qF 'done <"$UNINSTALL_PROJECTS_CONF"' "$LIB"; then
    pass "projects guard in the entry, conf redirect in the lib function"
else
    fail "projects guard wiring (entry if + lib redirect)"
fi
# --- 4. system paths in projects.conf are never ACL-cleaned --------------------
# uninstall.sh hardcodes /etc/opencode-permissions-kit/projects.conf (no
# env override), so this is checked by STATIC extraction: pull the pattern
# lines out of the screening case, splice them into a fresh case, and run
# it against representative paths. The real patterns are tested, without
# executing the script against the host's real projects.conf.
# The form gate (#243 a X2) adds earlier `case "$root"` blocks (absolute
# check, dot/empty segments) whose arms are NOT system-path patterns.
# Extraction is keyed to BLOCK IDENTITY, not line shape (#243 b S1: a
# filter that only drops a leading `/*)` line admits the dot arms
# silently the day their pattern line is reordered to start with `/`):
# only the case block whose body echoes "Skipping system path"
# contributes its `/`-leading pattern lines — the form-gate blocks (and
# any future non-blocklist block) are skipped whole, whatever their
# lines look like. The form gate itself is pinned behaviorally in the
# loop driver below (malformed-roots arm). The extractor is a function
# so the block-identity pin right below drives the SAME code, not a
# drifting copy (#243 c S1).
_un_blocklist_tokens() { # <file> — block-identity blocklist extraction
    awk '
        /case "\$root" in[[:space:]]*$/ { inblk=1; keep=0; buf=""; next }
        inblk && /^[[:space:]]*esac[[:space:]]*$/ {
            if (keep && buf != "") printf "%s", buf
            inblk=0; next
        }
        inblk {
            if ($0 ~ /Skipping system path/) keep=1
            line=$0
            sub(/\\$/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            sub(/\)$/, "", line)
            sub(/\|$/, "", line)
            if (line ~ /^\//) buf = buf line "|"
        }
    ' "$1" | sed -e 's/|$//'
}
SCREEN_PATTERNS="$(_un_blocklist_tokens "$LIB")"
if [ -n "$SCREEN_PATTERNS" ]; then
    pass "screening patterns extractable from uninstall-core.sh"
else
    fail "screening patterns extractable from uninstall-core.sh"
fi
# Block-identity pin (#243 c S1): a decoy case block with /-leading
# arms — the #243 b-S1 reorder hazard shape, plus a `/*)` arm and a
# backslash continuation — must contribute nothing; only the block
# whose body echoes "Skipping system path" yields tokens. A reversion
# to a shape-keyed grep pulls the decoy arms in and reds this pin.
_un_s1_fixture="$WORK/un-s1-fixture.sh"
cat >"$_un_s1_fixture" <<'EOF'
case "$root" in
    /*) ;;
    /decoy|/decoy/*|/./|*..*|*/./*)
        echo "  Skipping malformed decoy path: $root"
        ;;
esac
case "$root" in
    /keep|/keep/*|\
    /keep2)
        echo "  Skipping system path: $root"
        ;;
esac
EOF
if [ "$(_un_blocklist_tokens "$_un_s1_fixture")" = "/keep|/keep/*|/keep2" ]; then
    pass "blocklist extraction is block-identity-keyed, decoy arms excluded (#243 c S1)"
else
    fail "blocklist extraction is block-identity-keyed, decoy arms excluded (#243 c S1)"
fi
# Wiring pin (#243 d Q5): the pin above drives the FUNCTION; this one
# guards the WIRED value. SCREEN_PATTERNS as extracted must carry no
# dot-form or double-slash token — the form-gate arms a shape-keyed
# reversion of the wiring assignment would splice in (the function pin
# would stay green: it tests the intact function, not the wiring).
# Legit system-path tokens contain neither shape; a future arm that
# legitimately needs one reds this loudly and gets defanged
# consciously.
case "$SCREEN_PATTERNS" in
    *.* | *//*)
        fail "wired SCREEN_PATTERNS free of dot/double-slash tokens (#243 d Q5)"
        ;;
    *)
        pass "wired SCREEN_PATTERNS free of dot/double-slash tokens (#243 d Q5)"
        ;;
esac

# screen <path>: 0 = screened (skipped by the loop), 1 = allowed.
# eval is required: `|` alternation in case patterns is parsed at parse
# time, NOT re-parsed from a variable expansion — a literal $SCREEN_PATTERNS
# would be one big never-matching pattern. The helper mirrors the
# loop's SCREENING chain in full — dot gate, then strip, then
# blocklist (#243 c X1/d X4, dot gate #243 e X3; scope sharpened per
# review f S3): the loop's earlier gates (agent-home refusal,
# [ ! -d ], absolute-path check) precede screening and are NOT
# mirrored here. Malformed dot/empty-segment forms are screened
# exactly like the loop skips them, THEN the one-trailing-slash
# normalization applies (strip once, `/` stays `/` — the blocklist
# `/` arm), so a static slash-form assertion pins the same screening
# semantics the shipped loop has.
screen() {
    case "$1" in
        *..* | /./ | */./* | ./* | */. | *//*) return 0 ;;
    esac
    _un_scr="${1%/}"
    [ -n "$_un_scr" ] || _un_scr="/"
    eval "case \"\$_un_scr\" in
        $SCREEN_PATTERNS) return 0 ;;
        *) return 1 ;;
    esac"
}

# Static rejected reps. Slash-form choice (#243 e S3): the discriminating
# trailing-slash spellings hit BARE blocklist arms without `/*` siblings
# (/home/, /var/) — a `/*`-sibling form like /etc/ matches its sibling
# arm with or without the strip and proves nothing. /var// pins the
# helper's dot gate (#243 e X3): without it the strip turns /var// into
# /var/ and the form reports allowed.
for syspath in / /etc /home/ /var/ /var// /etc/nginx /usr /usr/share /bin /boot /root /root/x /proc /sys /dev /run /run/x /lib64; do
    if screen "$syspath"; then
        pass "screening rejects $syspath"
    else
        fail "screening rejects $syspath"
    fi
done
# Writer-parity arms (#243 b X1): sh/path-sane.sh project_path_sane
# (config.sh's and install.sh's shared gate since issue #216) refuses
# these system paths; the reader blocklist mirrors them now — pinned
# here lexically, behaviorally in the 4c blocklist arm below, and as a
# set-equality tripwire in the parity pin after the reps.
for syspath in /var /home /libexec/x /opt/x /srv/x /media/x /mnt/x /var/log/x /var/lib/x /var/spool/x; do
    if screen "$syspath"; then
        pass "screening rejects $syspath"
    else
        fail "screening rejects $syspath"
    fi
done
# #377 O1 (review #370 a O1): the completed /var families — behaviorally
# here, as a set by the parity tripwire below.
for syspath in /var/backups/x /var/opt/x /var/crash/x /var/local/x /var/lock/x; do
    if screen "$syspath"; then
        pass "screening rejects $syspath (#377)"
    else
        fail "screening rejects $syspath (#377)"
    fi
done
if printf '%s' "$SCREEN_PATTERNS" | grep -q '/var/www'; then
    fail "screening patterns must not contain /var/www (legit project area)"
else
    pass "screening patterns must not contain /var/www (legit project area)"
fi
# Pinned divergence (#243 b X1): the scratch prefixes stay processable
# by design — the sandbox policy pins unit-fixture roots under /tmp and
# /var/tmp (this suite's own primary root lives there), and a
# temp-prefix conf entry is bounded (uid/gid-matched chown, kit-gid
# ACL strip and one setgid-bit clear (chmod g-s) only). The writer
# refuses them for storage; the uninstaller deliberately does not
# screen them.
for projpath in /var/www/vhosts /var/www /home/dev/x /tmp/x /var/tmp/x; do
    if screen "$projpath"; then
        fail "screening allows $projpath"
    else
        pass "screening allows $projpath"
    fi
done
# Parity pin (#243 b X1): reader blocklist == writer blocklist minus
# the pinned temp-prefix divergence — both sides extracted statically,
# so writer/reader drift redds here instead of silently diverging (the
# b S-axis coverage note: the a-X2 pins are form-enumerative; this is
# the tripwire for the LIST). The writer-side extraction is shape-keyed
# (/-leading lines minus a lone `/*)` arm) — fail-loud by construction:
# any stray /-leading line in project_path_sane breaks the set
# equality; it can never silently pass.
# The writer-side policy lives in sh/path-sane.sh since issue #216
# (sourced by config.sh and install.sh) — extract the blocklist from
# the single copy. Top-level anchored (the lib's definition, like
# config.sh's former one, sits at indent 0).
PATH_SANE_SH="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/sh/path-sane.sh"
WRITER_PATTERNS="$(extract_func "$PATH_SANE_SH" project_path_sane |
    grep -E '^[[:space:]]*/' | grep -vE '^[[:space:]]*/\*\)' |
    sed -e 's/\\$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/)$//' | tr '\n' '|')"
_un_parity_tokens() {
    # Leading AND trailing whitespace stripped: shfmt (#255 stage 0a)
    # re-breaks the blocklists' multi-line case arms per file (indent
    # context), so a token's leading space depends on the break
    # position — the token is the path pattern, wherever the line ends.
    printf '%s\n' "$1" | tr '|' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d' | sort -u
}
READER_SET=$(_un_parity_tokens "$SCREEN_PATTERNS")
# Guarded count (#260, the #244 f W1 class; #280 c S1): grep -v exits 1
# when it filters everything — zero surviving tokens (the writer-parity
# regression this pin exists for) aborted the suite under set -e before
# the set-equality FAIL could record. READER_SET above needs no guard:
# _un_parity_tokens ends in sort -u, rc 0 even on empty input.
WRITER_SET=$(_un_parity_tokens "$WRITER_PATTERNS" | grep -vxF \
    -e '/tmp' -e '/tmp/*' -e '/var/tmp' -e '/var/tmp/*' || true)
if [ -n "$READER_SET" ] && [ "$READER_SET" = "$WRITER_SET" ]; then
    pass "screening blocklist at writer parity, /tmp+/var/tmp pinned out (#243 b X1)"
else
    fail "screening blocklist at writer parity, /tmp+/var/tmp pinned out (#243 b X1)"
fi

# --- 4b. ownership revert (issue #74) ---------------------------------------------
# The kit hands .ddev/ trees, settings dirs and typo3 bootstrap roots to
# the opencode user; the agent/ddev create opencode-owned files on top.
# Uninstall must give ALL of it back to the developer — matched by
# uid/gid, because the user removal above may already have orphaned the
# ids. Functional: the project loop is extracted verbatim (it hardcodes
# the conf path, so it is fed a fake root via stdin) and run with a
# logging sudo() stub; the captured uid 60000 and the DISTINCT gids
# (oc 60002 / dev 60001) must land inside the find and the ACL removal,
# with chown to DEFAULT_USER:<dev-group>. The loop
# is extracted verbatim except for its stdin redirect (the conf path is
# hardcoded) — the fake roots are piped in instead.
# #396 payoff (wave 4): the project loop, the rc-observing runner and the
# OPENCODE_USER gate are FUNCTIONS in the sourced lib now (un_projects_revert,
# un_rc_q, un_opencode_user_gate) — the former extraction pins are the
# sourcing pins below; the loop driver calls the real function with a
# fixture UNINSTALL_PROJECTS_CONF (the function reads the variable its
# `done <` redirect names — no stdin surgery anymore). Comment-strip
# rider on the count (conventions.md, "Source-counting pins").
_unq_all="$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -c 'un_rc_q "' || true)"
if printf '%s' "$_unq_all" | grep -qE '^[0-9]+$' && [ "$_unq_all" -gt 10 ]; then
    pass "rc-observing runner wired across the sections (#218)"
else
    fail "rc-observing runner wiring (#218)"
fi
# Gate pins (#243 e X1): a valid custom name passes through untouched
# (the agent-home refusal keeps working for customized agents — its arm
# feeds /home/untest-agent), the canonical literal passes through, and
# a corrupted value (the trailing-slash spelling that silently defanged
# the refusal in review e) falls back to 'opencode' LOUDLY on stderr.
_ou_new=$(
    OPENCODE_USER=untest-agent
    un_opencode_user_gate 2>"$WORK/un-ouc-err.log"
    printf '%s' "$OPENCODE_USER"
)
_ou_bad=$(
    OPENCODE_USER="untest-agent/"
    un_opencode_user_gate 2>"$WORK/un-ouc-err2.log"
    printf '%s' "$OPENCODE_USER"
)
_ou_canon=$(
    OPENCODE_USER=opencode
    un_opencode_user_gate 2>>"$WORK/un-ouc-err.log"
    printf '%s' "$OPENCODE_USER"
)
if [ "$_ou_new" = "untest-agent" ] && [ "$_ou_canon" = "opencode" ] &&
    [ ! -s "$WORK/un-ouc-err.log" ] &&
    [ "$_ou_bad" = "opencode" ] &&
    grep -q 'WARN: invalid OPENCODE_USER value in install.conf' "$WORK/un-ouc-err2.log"; then
    pass "OPENCODE_USER gate: valid/canonical pass through, corrupted falls back loudly (#243 e X1)"
else
    fail "OPENCODE_USER gate arms (#243 e X1)"
fi
# pr-00263 a F9: the WARN echo is sanitized — a newline-bearing value
# stays exactly one WARN line (the raw echo forged transcript lines).
_ou_nl=$(
    OPENCODE_USER="$(printf 'oco\nd')"
    un_opencode_user_gate 2>"$WORK/un-ouc-nl.log"
    printf '%s' "$OPENCODE_USER"
)
if [ "$_ou_nl" = "opencode" ] &&
    [ "$(grep -c . "$WORK/un-ouc-nl.log")" = 1 ] &&
    grep -q 'oco?d' "$WORK/un-ouc-nl.log"; then
    pass "gate WARN sanitized: newline value = one line, no raw bytes (pr-00263 a F9)"
else
    fail "gate WARN sanitization (pr-00263 a F9)"
fi
# Pathological corpus (#243 f X1): leading dot/hyphen and trailing
# dot are legal in the writer's charset but not agent names — the
# tightened arms must fall them back LOUDLY; internal dot/hyphen (a
# legit custom-name shape) must pass through untouched. Each arm
# carries its own spelling class: `*[.]` alone deleted → `opencode.`
# passes; `[.-]*` alone deleted → `-x`/`--` pass; the whole tightening
# reverted → all five pass (spot-checked). Over-refusal reds on the
# boundary arm (a future arm refusing ALL hyphens/dots would fall
# `untest-x.9`).
_ou_path_ok=1
: >"$WORK/un-ouc-path-err.log"
for _ou_pv in . .. opencode. -x --; do
    _ou_pv_out=$(
        OPENCODE_USER="$_ou_pv"
        un_opencode_user_gate 2>>"$WORK/un-ouc-path-err.log"
        printf '%s' "$OPENCODE_USER"
    )
    [ "$_ou_pv_out" = "opencode" ] || _ou_path_ok=0
done
_ou_keep=$(
    OPENCODE_USER="untest-x.9"
    un_opencode_user_gate 2>"$WORK/un-ouc-err3.log"
    printf '%s' "$OPENCODE_USER"
)
if [ "$_ou_path_ok" -eq 1 ] &&
    [ "$(grep -c 'WARN: invalid OPENCODE_USER value' "$WORK/un-ouc-path-err.log")" -eq 5 ] &&
    [ "$_ou_keep" = "untest-x.9" ] &&
    [ ! -s "$WORK/un-ouc-err3.log" ]; then
    pass "OPENCODE_USER gate: pathological spellings fall back, internal dot/hyphen stay legal (#243 f X1)"
else
    fail "OPENCODE_USER pathological corpus (#243 f X1)"
fi
# Loop driver (#218; channels + extra roots #243 a Q3/S3/X2): real
# loop + real runner, per-command sudo stub (logs the call to the sudo
# log, fails the ops named in <fail-ops> — but ONLY on the primary
# root, boundary-matched: $WORK/fakeproj2 must never match fakeproj).
# Output is split into marked sections: the real log() is FILE-ONLY
# (sh/log.sh — the user never sees log: lines on stdout; the stub
# echoes the argument so the AUDIT-LOG WORDING is pinnable), stderr is
# captured separately so the WARN channel (>&2) is pinnable too — a
# merged 2>&1 cannot detect a channel regression (#243 a Q3).
# Positional args keep every arm hermetic — no knob vars leaking:
#   <fail-ops>  space-separated first args to fail (find/setfacl/chmod)
#   <dry-run>   DRY_RUN for the run (true/false)
#   <uid> <oc-gid> <dev-gid>   the id fixture (empty string = unknown;
#               distinct gids by default — 0.0.42g Q2: UN_OC_GID and
#               UN_DEV_GID must differ so the ACL pins can prove BOTH
#               principals are removed)
#   <extra-roots>  optional space-separated extra roots appended to
#               the fixture after the primary root (storage format is
#               space-free, so word-splitting is safe) — two-root
#               isolation (#243 a S3) and malformed-form feeds (#243
#               a X2). Env pins in the driver (#243 c Q1, wording d
#               Q2/e X1): UN_DEV_GROUP and DEFAULT_USER stay fixed
#               literals; OPENCODE_USER is the seventh parameter
#               (default untest-agent) so the e X1 arm can feed the
#               corrupted trailing-slash spelling — the agent-home
#               refusal is lexical, so no arm needs a host directory.
_un_loop_out() {
    _unlo_fail="$1"
    _unlo_dry="$2"
    _unlo_uid="$3"
    _unlo_ocg="$4"
    _unlo_dg="$5"
    _unlo_extra="${6:-}"
    _unlo_ocu="${7:-untest-agent}"
    : >"$WORK/unloop-sudo.log"
    : >"$WORK/unloop-out.log"
    : >"$WORK/unloop-err.log"
    _unlo_fixture="$WORK/fakeproj"
    for _unlo_x in $_unlo_extra; do
        _unlo_fixture="$_unlo_fixture
$_unlo_x"
    done
    printf '%s\n/etc\n' "$_unlo_fixture" >"$WORK/unloop-roots.conf"
    (
        DRY_RUN="$_unlo_dry"
        _un_partial=""
        _un_revert_failed=0
        UN_OC_UID="$_unlo_uid"
        UN_OC_GID="$_unlo_ocg"
        UN_DEV_GROUP=devgroup
        UN_DEV_GID="$_unlo_dg"
        DEFAULT_USER=devuser
        # Test agent name (#243 c Q1, parameterized e X1): default
        # untest-agent; the shape gate runs BEFORE the loop inside
        # un_context_load at top level — the driver normalizes the same
        # way (real gate, real order: gate right after install.conf
        # sourcing, project loop far below).
        OPENCODE_USER="$_unlo_ocu"
        un_opencode_user_gate
        # Logs to a FILE: the real runner silences its command's stdout
        # and stderr (the shipped behavior), so an echoing stub would
        # be swallowed with them.
        sudo() {
            printf 'sudo %s\n' "$*" >>"$WORK/unloop-sudo.log"
            case " $_unlo_fail " in
                *" $1 "*)
                    # Primary root only, boundary-matched: every op
                    # carries the root as an operand (find/setfacl end
                    # or precede a space, chmod ends it) — fakeproj2
                    # must not match (#243 a S3).
                    case "$*" in
                        *"$WORK/fakeproj "* | *"$WORK/fakeproj") return 1 ;;
                    esac
                    ;;
            esac
            return 0
        }
        log() { echo "log: $*"; }
        UNINSTALL_PROJECTS_CONF="$WORK/unloop-roots.conf"
        un_projects_revert
    ) >"$WORK/unloop-out.log" 2>"$WORK/unloop-err.log"
    echo "--- stdout ---"
    cat "$WORK/unloop-out.log"
    echo "--- stderr ---"
    cat "$WORK/unloop-err.log"
    echo "--- sudo log ---"
    cat "$WORK/unloop-sudo.log"
}
LOOP_OUT=$(mkdir -p "$WORK/fakeproj" && _un_loop_out "" false 60000 60002 60001 || true)
if printf '%s' "$LOOP_OUT" | grep -qF "find $WORK/fakeproj" &&
    ! printf '%s' "$LOOP_OUT" | grep -qF ' -xdev ' &&
    printf '%s' "$LOOP_OUT" | grep -qF -- '-uid 60000' &&
    printf '%s' "$LOOP_OUT" | grep -qF -- '-gid 60002' &&
    printf '%s' "$LOOP_OUT" | grep -qF -- '-print0' &&
    printf '%s' "$LOOP_OUT" | grep -qF 'xargs -0' &&
    printf '%s' "$LOOP_OUT" | grep -qF 'un-revert-chown' &&
    printf '%s' "$LOOP_OUT" | grep -qF 'devuser:devgroup' &&
    printf '%s' "$LOOP_OUT" | grep -qF -- '! -type l'; then
    pass "ownership revert: uid/gid-matched chown to the developer per root (issue #74)"
else
    fail "ownership revert loop (out=$(printf '%s' "$LOOP_OUT" | head -5))"
fi
# ! -type l (0.0.42e S1) is the SCAN-time half: it keeps statically
# planted links out of the operand stream — chown follows a symlink
# operand, so an agent-planted link in the project must never make the
# root-run revert chown an arbitrary file OUTSIDE the project. The
# exec-time half (per-operand leaf recheck + component walk inside the
# xargs worker, #267 — `! -type l` classifies at scan time only) is
# pinned functionally in 4b2 below.
# -xdev would stop at mount boundaries — project roots are regularly
# separate mounts (bind mounts, NFS): the revert must follow, like the
# setfacl -R calls in the same loop (checked above via the -xdev grep).
if printf '%s' "$LOOP_OUT" | grep -qF "find \"/etc\""; then
    fail "ownership revert: system paths are never chowned (screened)"
else
    pass "ownership revert: system paths are never chowned (screened)"
fi

# --- 4b2. find-chown worker: exec-time operand recheck (#267) ----------------------
# Functional drive of _un_revert_chown: pass-through sudo stub, PATH-
# stubbed find (streams the NUL operands the scan "found" — all
# classified regular at scan time by the real find's ! -type l, the
# drive's premise) and a logging chown stub. A leaf swapped for a link
# since the scan and an operand whose PARENT is a link NOW must never
# reach chown — and the pass must FAIL on them: entries left behind
# degrade the closing log to PARTIALLY via un_rc_q (the #211 a F14
# honesty class), never a green "ownership reverted".
UNR="$(work_new)"
UNRS="$(work_new)"
mkdir -p "$UNR/root/sub" "$UNR/victim" "$UNRS/bin"
printf 'victim-content\n' >"$UNR/victim/target.conf"
touch "$UNR/root/regular.conf"
ln -s "$UNR/victim/target.conf" "$UNR/root/leaf-link"
ln -s "$UNR/victim" "$UNR/root/sub/link-parent"
cat >"$UNRS/bin/find" <<EOF
#!/bin/sh
# fake find: ignores the expression, streams the three "scanned" NUL
# operands into the helper's temp stream.
printf '%s\\0%s\\0%s\\0' "$UNR/root/regular.conf" "$UNR/root/leaf-link" \\
    "$UNR/root/sub/link-parent/inside.conf"
exit 0
EOF
cat >"$UNRS/bin/chown" <<'EOF'
#!/bin/sh
echo "chown $*" >>"$CHOWN_LOG"
exit 0
EOF
chmod +x "$UNRS/bin/find" "$UNRS/bin/chown"
: >"$WORK/unr-chown.log"
UNR_RC=0
UNR_OUT=$(PATH="$UNRS/bin:$PATH" CHOWN_LOG="$WORK/unr-chown.log" sh -c '
    . "$1"
    sudo() { "$@"; }
    UN_OC_UID=60000
    UN_OC_GID=60002
    DEFAULT_USER=devuser
    UN_DEV_GROUP=devgroup
    _un_revert_chown "$2"
' _ "$LIB" "$UNR/root" 2>&1) || UNR_RC=$?
assert_eq "worker: only the regular operand reaches chown (#267)" \
    "chown devuser:devgroup $UNR/root/regular.conf" "$(cat "$WORK/unr-chown.log")"
check "worker: a swapped leaf link never reaches chown (#267)" \
    sh -c "! grep -q leaf-link \"\$1\"" _ "$WORK/unr-chown.log"
check "worker: an operand behind a symlinked parent never reaches chown (#267)" \
    sh -c "! grep -q link-parent \"\$1\"" _ "$WORK/unr-chown.log"
check "worker: skipped swaps fail the pass — PARTIALLY via un_rc_q, never green (#267)" \
    sh -c "[ \"\$1\" -ne 0 ]" _ "$UNR_RC"

# mktemp failure is loud (the fail-loud pin for the || return 1 arm,
# #420 a A3): the DISTINCT message (not just rc 1 — a silent arm is
# indistinguishable from the find failure below) + rc 1 + find never
# runs. The message is the discriminator: deleting the loud arm leaves
# an accidental rc 1 (the empty redirect fails the find condition) but
# no message — this pin is what reddens.
UNRM="$(work_new)"
mkdir -p "$UNRM/bin"
cat >"$UNRM/bin/mktemp" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$UNRM/bin/mktemp"
: >"$WORK/unr-find.log"
UNRM_RC=0
UNRM_OUT=$(PATH="$UNRM/bin:$PATH" sh -c '
    . "$1"
    _unrm_log="$2"
    sudo() { echo "sudo $*" >>"$_unrm_log"; }
    UN_OC_UID=60000
    UN_OC_GID=60002
    DEFAULT_USER=devuser
    UN_DEV_GROUP=devgroup
    _un_revert_chown "$3"
' _ "$LIB" "$WORK/unr-find.log" "$UNR/root" 2>&1) || UNRM_RC=$?
case "$UNRM_OUT" in
    *"cannot stage the revert operand stream (mktemp failed)"*)
        pass "worker: mktemp failure announces itself with its own cause (#267, #420 a A3)"
        ;;
    *) fail "worker: mktemp failure must announce its cause (got: $UNRM_OUT) (#267, #420 a A3)" ;;
esac
assert_eq "worker: mktemp failure refuses loud (rc 1, #267)" "1" "$UNRM_RC"
check "worker: mktemp failure runs no find at all (#267)" \
    sh -c "! grep -q find \"\$1\"" _ "$WORK/unr-find.log"
# find's own death fails the pass (0.0.43b W4 shape — a wholesale find
# death never counts as a green revert over a half-walked tree): rc 1
# and xargs never runs. Logging pass-through sudo so the absence of the
# xargs line is OBSERVED, not assumed.
UNRF="$(work_new)"
mkdir -p "$UNRF/bin"
cat >"$UNRF/bin/find" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$UNRF/bin/find"
: >"$WORK/unr-find2.log"
UNRF_RC=0
UNRF_OUT=$(PATH="$UNRF/bin:$PATH" sh -c '
    . "$1"
    _unrf_log="$2"
    sudo() { echo "sudo $*" >>"$_unrf_log"; "$@"; }
    UN_OC_UID=60000
    UN_OC_GID=60002
    DEFAULT_USER=devuser
    UN_DEV_GROUP=devgroup
    _un_revert_chown "$3"
' _ "$LIB" "$WORK/unr-find2.log" "$UNR/root" 2>&1) || UNRF_RC=$?
assert_eq "worker: a dead find fails the pass (rc 1, no green revert — 0.0.43b W4 shape)" "1" "$UNRF_RC"
check "worker: a dead find never reaches xargs (#267)" \
    sh -c "! grep -q xargs \"\$1\"" _ "$WORK/unr-find2.log"
rm -rf "${UNR:?}" "${UNRS:?}" "${UNRM:?}" "${UNRF:?}"

# --- 4b3. find-chown worker: scan-root recheck (#421) -------------------------------
# The #421 shape: the 4b2 component walk starts BELOW the scan root,
# so a ROOT swapped for a symlink between find and the worker
# redirected every walk test — and the chown — through it (components
# in the target are real directories, no gate fires). Deterministic
# seam: the stub find streams the "scanned" operand, THEN swaps the
# root, then exits — the worker then starts with a linked root. The
# worker head must refuse the batch LOUD (the distinct message, not a
# bare rc): nothing reaches chown, the pass fails, un_rc_q counts the
# root as left behind.
UNR2="$(work_new)"
UNR2S="$(work_new)"
mkdir -p "$UNR2/root" "$UNR2/victim" "$UNR2S/bin"
printf 'scanned\n' >"$UNR2/root/regular.conf"
printf 'victim\n' >"$UNR2/victim/regular.conf"
cat >"$UNR2S/bin/find" <<EOF
#!/bin/sh
# fake find: streams the "scanned" operand, then swaps the scan root
# itself for a symlink — the scan->worker window, deterministically.
printf '%s\\0' "$UNR2/root/regular.conf"
if [ -d "$UNR2/root" ] && [ ! -L "$UNR2/root" ]; then
    mv "$UNR2/root" "$UNR2/root-moved"
    ln -s "$UNR2/victim" "$UNR2/root"
fi
exit 0
EOF
cat >"$UNR2S/bin/chown" <<'EOF'
#!/bin/sh
echo "chown $*" >>"$CHOWN_LOG"
exit 0
EOF
chmod +x "$UNR2S/bin/find" "$UNR2S/bin/chown"
: >"$WORK/unr2-chown.log"
UNR2_RC=0
UNR2_OUT=$(PATH="$UNR2S/bin:$PATH" CHOWN_LOG="$WORK/unr2-chown.log" sh -c '
    . "$1"
    sudo() { "$@"; }
    UN_OC_UID=60000
    UN_OC_GID=60002
    DEFAULT_USER=devuser
    UN_DEV_GROUP=devgroup
    _un_revert_chown "$2"
' _ "$LIB" "$UNR2/root" 2>&1) || UNR2_RC=$?
if [ -d "$UNR2/root-moved" ] && [ -L "$UNR2/root" ]; then
    pass "worker: root-swap fixture fired (#421 seam)"
else
    fail "worker: root-swap fixture fired (#421 seam — root not swapped)"
fi
check "worker: a swapped scan root never reaches chown (#421)" \
    sh -c '! grep -q . "\$1"' _ "$WORK/unr2-chown.log"
case "$UNR2_OUT" in
    *"scan root $UNR2/root was replaced by a symlink"*)
        pass "worker: the swapped root is refused with its own cause (#421)"
        ;;
    *) fail "worker: the swapped root must be refused with its own cause (got: $UNR2_OUT) (#421)" ;;
esac
check "worker: the refused batch fails the pass — never a green revert (#421)" \
    sh -c '[ "$1" -ne 0 ]' _ "$UNR2_RC"

# --- issue #245: a symlinked conf root is skipped, never operated on ----
# Measured (issue #245 comment, ext4 + overlayfs): a projects.conf entry
# that IS a symlink to a directory passes [ ! -d ] (it follows), and the
# loop-tail ops then dereference the operand — chmod g-s and setfacl
# -R -x land on the TARGET directory while the find-chown walk visits
# nothing. The gate (after the #243 normalization, so a `link/` spelling
# is stripped first — [ -L "path/" ] is false, measured) must skip the
# root loudly and issue NO op on the link OR its target; the primary
# root keeps its full revert (isolation).
mkdir -p "$WORK/faketarget"
ln -s "$WORK/faketarget" "$WORK/fakelink"
UN_SYMLINK_OUT=$(_un_loop_out "" false 60000 60002 60001 "$WORK/fakelink" || true)
if printf '%s' "$UN_SYMLINK_OUT" |
    grep -qF "Skipping symlinked project path (register the target directory instead): $WORK/fakelink" &&
    ! printf '%s' "$UN_SYMLINK_OUT" | grep -q "sudo.*$WORK/fakelink" &&
    ! printf '%s' "$UN_SYMLINK_OUT" | grep -q "sudo.*$WORK/faketarget" &&
    printf '%s' "$UN_SYMLINK_OUT" | grep -qF "find $WORK/fakeproj"; then
    pass "symlinked root: skip echo, no revert op on link or target, primary root intact (#245)"
else
    fail "symlinked root must be skipped without ops on link/target (#245; out=$(printf '%s' "$UN_SYMLINK_OUT" | head -8))"
fi
# The trailing-slash spelling feeds the same gate through the #243
# normalization: ops would receive the stripped form (measured: with
# the slash, the find-chown walk and setfacl -R recurse the WHOLE
# target tree) — the skip echo names the normalized path.
UN_SYMLINK_SLASH_OUT=$(_un_loop_out "" false 60000 60002 60001 "$WORK/fakelink/" || true)
if printf '%s' "$UN_SYMLINK_SLASH_OUT" |
    grep -qF "Skipping symlinked project path (register the target directory instead): $WORK/fakelink" &&
    ! printf '%s' "$UN_SYMLINK_SLASH_OUT" | grep -q "sudo.*$WORK/fakelink" &&
    ! printf '%s' "$UN_SYMLINK_SLASH_OUT" | grep -q "sudo.*$WORK/faketarget" &&
    printf '%s' "$UN_SYMLINK_SLASH_OUT" | grep -qF "find $WORK/fakeproj"; then
    pass "symlinked root, trailing-slash spelling: normalized, skipped, no ops (#245)"
else
    fail "trailing-slash symlink root must be normalized and skipped (#245)"
fi

# The uid/gid capture must happen BEFORE the user removal: after userdel
# the name no longer resolves and only the numeric ids can still match
# the orphaned files. (Comment-stripped operands, #385.)
CAPTURE_LINE=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n 'UN_OC_UID=' | head -1 | cut -d: -f1)
USERDEL_LINE=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -n 'sudo userdel -r' | head -1 | cut -d: -f1)
if [ -n "$CAPTURE_LINE" ] && [ -n "$USERDEL_LINE" ] && [ "$CAPTURE_LINE" -lt "$USERDEL_LINE" ]; then
    pass "ownership revert: ids captured before userdel (orphan-proof)"
else
    fail "ownership revert: ids must be captured before userdel (capture=$CAPTURE_LINE userdel=$USERDEL_LINE)"
fi

# 0.0.45c C6: the agents-backup gate probes with sudo and fails SAFE —
# the old unprivileged `ls -A` silently skipped the whole backup block
# when the invoking user could not read the agent home (group dropped,
# different DEFAULT_USER), and userdel -r then deleted .agents/.claude
# without the warning. An unreadable dir counts as NON-EMPTY now.
if grep -qF 'sudo ls -A "$_un_ag_src"' "$LIB" &&
    grep -qF '_un_ag_ls="probe-failed"' "$LIB"; then
    pass "agents-backup gate: privileged probe + fail-safe on unreadable (C6)"
else
    fail "agents-backup gate: privileged probe + fail-safe on unreadable (C6)"
fi

# 0.0.45d W2: the EXISTENCE probe must be privileged too — the 0.0.45c
# fix kept an unprivileged `[ -d ]` in front of the sudo listing, but
# that stat needs search on /home/<opencode> (2750 opencode:<sharing
# group>) and fails for exactly the invokers C6 exists to protect
# (different DEFAULT_USER, dropped membership in a fresh session): the
# block was skipped silently and userdel -r deleted the resources with
# no backup and no warning. Static pin: the privileged existence gate
# is in, the unprivileged one is gone.
if grep -qF 'if sudo test -d "$_un_ag_src"; then' "$LIB" &&
    ! grep -qF 'if [ -d "$_un_ag_src" ]; then' "$LIB"; then
    pass "agents-backup gate: existence probe rides sudo (W2)"
else
    fail "agents-backup gate: existence probe must be privileged, not [ -d ] (W2)"
fi

# W2 behavioral pin: run the REAL extracted gate loop (paths swapped
# onto scratch) with a logging sudo that degrades to the current user.
# Fixture one: the agent home is mode 000 — the unprivileged stat fails
# exactly as in the C6 scenarios; what is pinned is that the privileged
# existence probe is still ISSUED (logged). With the old unprivileged
# [ -d ] short-circuiting, no sudo call happens at all and the block
# skips silently. Fixture two: a readable .agents arms the backup branch
# (test -d, ls -A, mkdir, cp all logged). Fixture three: a nonexistent
# home enters none of them (no WARNING noise for what does not exist).
_un_w2="$(work_new)"
mkdir -p "$_un_w2/fake-home/opencodeux/.agents" "$_un_w2/fake-home/opencodeux2" "$_un_w2/backups"
echo skills >"$_un_w2/fake-home/opencodeux/.agents/agents.md"
printf '#!/bin/sh\necho "sudo $*" >> "%s/log"\nexec "$@"\n' "$_un_w2" >"$_un_w2/sudo"
chmod +x "$_un_w2/sudo"
_un_w2_gate() {
    {
        printf 'DRY_RUN=false\nlog() { :; }\nDEFAULT_USER=%s\nOPENCODE_USER=%s\nPATH="%s:$PATH"\n' \
            "$2" "$1" "$_un_w2"
        sed -n '/^            for _un_ag_dirname in \.agents \.claude; do$/,/^            done$/p' "$LIB" |
            sed -e "s#/home/#$_un_w2/fake-home/#g" -e "s#/var/backups/opencode-permissions-kit#$_un_w2/backups#"
    } >"$_un_w2/run.sh"
    : >"$_un_w2/log"
    sh "$_un_w2/run.sh" >/dev/null 2>&1 || true
    cat "$_un_w2/log" 2>/dev/null || true
}
chmod 000 "$_un_w2/fake-home/opencodeux2"
# #430 mode pin prep: the source .agents gets the WORST agent-settable
# mode (777) — `cp -a src/. dst/` propagates it onto the leaf (observed:
# the mkdir -m 700 alone left a 775 leaf past the copy), so the leaf
# pin below discriminates the trailing chmod, not just the mkdir -m.
chmod 777 "$_un_w2/fake-home/opencodeux/.agents"
_un_w2_log="$(_un_w2_gate opencodeux2 devuser)"
if printf '%s\n' "$_un_w2_log" | grep -q '^sudo test -d '; then
    pass "agents-backup gate: privileged existence probe issued despite unreadable home (W2)"
else
    fail "agents-backup gate: no privileged probe against the unreadable home (W2 log: $_un_w2_log)"
fi
_un_w2_log="$(_un_w2_gate opencodeux devuser)"
if printf '%s\n' "$_un_w2_log" | grep -q '^sudo test -d .*agents$' &&
    printf '%s\n' "$_un_w2_log" | grep -q '^sudo ls -A .*agents$' &&
    printf '%s\n' "$_un_w2_log" | grep -q '^sudo mkdir -p .*backups$' &&
    printf '%s\n' "$_un_w2_log" | grep -q '^sudo mkdir -m 700 .*agents-backup-' &&
    printf '%s\n' "$_un_w2_log" | grep -q '^sudo cp -a .*agents' &&
    printf '%s\n' "$_un_w2_log" | grep -q '^sudo chmod 700 .*agents-backup-'; then
    pass "agents-backup gate: readable .agents arms the backup branch (W2)"
else
    fail "agents-backup gate: readable .agents must issue test-d/ls-A/mkdir/cp (W2 log: $_un_w2_log)"
fi
# LOWS-6 (#430): the leaf on the shared backup root follows the -m 700
# doctrine (install-core.sh / update-core.sh siblings) — the W2 gate's
# sudo stub EXECs, so the leaf is a REAL dir here: pin its mode. The
# 777 source (prep above) makes this pin discriminate the post-copy
# chmod re-assert; the mkdir -m 700 guard is discriminated by the
# log-grep pin above (the pair covers both — deleting only the -m 700
# leaves the re-assert producing 700, #438 a A4). The root stays at
# umask (world-traversable by design — the DEFAULT_USER must reach
# their own chowned leaf).
_un_w2_leaf=$(ls -d "$_un_w2/backups/.agents-backup-"* 2>/dev/null | head -n 1)
if [ -n "$_un_w2_leaf" ] && [ "$(stat -c %a "$_un_w2_leaf" 2>/dev/null)" = "700" ]; then
    pass "agents-backup leaf dir is 700 despite a 777 source (#430)"
else
    fail "agents-backup leaf not 700 (leaf=${_un_w2_leaf:-none} mode=$(stat -c %a "$_un_w2_leaf" 2>/dev/null)) (#430)"
fi
_un_w2_log="$(_un_w2_gate opencodeux-missing devuser)"
if ! printf '%s\n' "$_un_w2_log" | grep -q 'mkdir -p' &&
    ! printf '%s\n' "$_un_w2_log" | grep -q 'cp -a'; then
    pass "agents-backup gate: nonexistent home enters no backup call (W2)"
else
    fail "agents-backup gate: nonexistent home must skip the backup branch (W2 log: $_un_w2_log)"
fi
chmod 700 "$_un_w2/fake-home/opencodeux2" 2>/dev/null || true
rm -rf "${_un_w2:?}"

# ACL removal is targeted, not a wipe (0.0.42e C4): the kit baseline adds
# access entries g:<dev-group> and default entries g:<dev-group>:rwx —
# `setfacl -R -b/-k` removed EVERY extended ACL incl. pre-existing user
# entries the kit never owned. -x is a no-op rc 0 on absent entries.
# Qualifiers use the NUMERIC gid (0.0.42f C2): name qualifiers die at
# setfacl parse time when the name does not resolve, silently disabling
# the cleanup; the capture feeds a fallback branch when even the gid is
# unknown.
if printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -x g:60002' &&
    printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -d -x g:60002' &&
    printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -x g:60001' &&
    printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -d -x g:60001' &&
    ! printf '%s' "$LOOP_OUT" | grep -qF 'unknown' &&
    ! printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -b' &&
    ! printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -k'; then
    pass "ACL revert: both kit principals removed via numeric gids, no skip hints (0.0.42g S1 + 0.0.42i Q3)"
else
    fail "ACL revert must remove BOTH principals (opencode group + dev group) via numeric gids (0.0.42g S1)"
fi
if grep -qF 'UN_DEV_GID=$(id -g "$DEFAULT_USER"' "$LIB" &&
    grep -qF 'for _un_acl_pair in "opencode group:$UN_OC_GID" "dev group:$UN_DEV_GID"' "$LIB" &&
    grep -qF 'project revert PARTIALLY completed' "$LIB" &&
    grep -qF 'id unknown — its ACL entries left in place' "$LIB"; then
    pass "ACL revert: both gids captured, principal loop, loud per-principal skip + partial log (0.0.42f C2 + 0.0.42g S1 + 0.0.42h S1 + #218)"
else
    fail "ACL revert: principal loop + loud skip + partial-log branch required (0.0.42h S1, #218)"
fi

# --- 4c. revert-loop closing log honesty (#218) ----------------------------------
# The closing log used to claim "project ownership reverted + kit ACL
# entries removed" over rc-blind run_q ops — the deferred #211 c W1
# class sweep. The real loop + runner are driven through the
# per-command sudo stub above; every arm asserts the closing-log
# WORDING (the log() argument — the real log() is file-only, the stub
# echoes what the audit log would record) and, where a WARN exists,
# its CHANNEL: stderr is captured separately, so a WARN that migrates
# to stdout is caught (#243 a Q3; degraded wording #243 a X1).
_unarm_show() {
    # Red-arm diagnostics (#243 a Q4, families completed #243 b Q1,
    # window removed #243 c Q2): surface the line families the arms
    # actually assert — log:/WARN: records, PARTIALLY degradation,
    # Removed. closings, [DRY] echoes, skip echoes in both spellings
    # (Skipping gate / skipped/unknown id notes), and sudo-log lines.
    # No tail window: red arms with many sudo lines (system-path,
    # two-roots) must not push the asserted discriminator out of the
    # shown output. Pinned family-by-family below (#243 c S2).
    printf '%s' "$1" |
        grep -E 'log:|WARN:|PARTIALLY|Removed\.|\[DRY\]|Skipping|skipped|unknown|^sudo '
}
# _unarm_show family pin (#243 c S2): the helper never executes on a
# green run — it lives inside fail messages only — so without this
# pin, a dropped family regresses red-arm diagnostics invisibly. Every
# family line fed here must surface, in order, complete — and every
# regex alternative is isolated by at least one line that matches it
# ALONE (#243 d S1): dropping ANY alternative from the regex reds the
# identity compare (before d S1, `skipped` had no line and `PARTIALLY`
# was dominated by `log:` — both deletions kept the pin green).
_un_s2_in="log: project ownership reverted
WARN: could not fully remove
log: config dirs PARTIALLY removed
Removed.
  [DRY] sudo rm /run/opencode-permissions-kit
  Skipping system path: /var
    opencode group id unknown — hint
sudo chmod g-s /var
revert PARTIALLY completed (chmod g-s failed)
  skipped reverting ownership (not kit-owned)"
if [ "$(_unarm_show "$_un_s2_in")" = "$_un_s2_in" ]; then
    pass "_unarm_show surfaces every asserted family, no window (#243 c S2/Q2)"
else
    fail "_unarm_show surfaces every asserted family, no window (#243 c S2/Q2)"
fi
if printf '%s' "$LOOP_OUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj" &&
    ! printf '%s' "$LOOP_OUT" | grep -qF 'PARTIALLY' &&
    ! printf '%s' "$LOOP_OUT" | grep -qF 'WARN:' &&
    ! printf '%s' "$LOOP_OUT" | grep -qF 'revert FAILED'; then
    pass "revert all ok: full-success closing log, no partial/WARN noise (#218)"
else
    fail "revert all ok: full-success closing log required (out=$(_unarm_show "$LOOP_OUT")) (#218)"
fi
FOUT=$(_un_loop_out "find" false 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF "log: project revert PARTIALLY completed (find-chown failed): $WORK/fakeproj" &&
    printf '%s' "$FOUT" | grep -qF "WARN: could not fully revert $WORK/fakeproj (find-chown failed)" &&
    printf '%s' "$FOUT" | grep -qF "log: project revert FAILED for: $WORK/fakeproj (find-chown failed)" &&
    printf '%s' "$FOUT" | sed -n '/^--- stderr ---$/,/^--- sudo log ---$/p' | grep -qF 'WARN: could not fully revert' &&
    ! printf '%s' "$FOUT" | sed -n '1,/^--- stderr ---$/p' | grep -qF 'WARN:' &&
    ! printf '%s' "$FOUT" | grep -qF 'ownership reverted' &&
    ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "find-chown failure: degraded closing names the failed op, WARN stays on stderr, no false completion (#218, #243 a X1/Q3)"
else
    fail "find-chown failure arms (out=$(_unarm_show "$FOUT")) (#218, #243 a X1/Q3)"
fi
FOUT=$(_un_loop_out "setfacl" false 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF 'setfacl -x g:60002 failed' &&
    printf '%s' "$FOUT" | grep -qF 'setfacl -d -x g:60001 failed' &&
    ! printf '%s' "$FOUT" | grep -qF 'find-chown failed' &&
    ! printf '%s' "$FOUT" | grep -qF 'chmod g-s failed' &&
    ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "setfacl failure: both principals' ops named, other ops not (#218)"
else
    fail "setfacl failure arms — names must discriminate (out=$(_unarm_show "$FOUT")) (#218)"
fi
FOUT=$(_un_loop_out "chmod" false 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF 'PARTIALLY completed (chmod g-s failed)' &&
    printf '%s' "$FOUT" | grep -qF 'WARN: could not fully revert' &&
    ! printf '%s' "$FOUT" | grep -qF 'find-chown failed' &&
    ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "chmod g-s failure: named in degraded closing + WARN (#218)"
else
    fail "chmod g-s failure arms (out=$(_unarm_show "$FOUT")) (#218)"
fi
# Unknown opencode gid (0.0.42h S1 semantics, now in the unified
# partial mechanism): loud per-principal skip, dev-group removal still
# runs, closing degrades to PARTIALLY — but a skip is not a failure:
# no WARN, no FAILED log. The chown skip lands in the same list (uid
# and gid are captured together — an unknown gid skips the chown too).
# The manual-hint template is pinned too (#243 a Q1: docs describe it
# as a template with a <gid> placeholder — never as an exact call).
FOUT=$(_un_loop_out "" false 60000 "" 60001) || true
if printf '%s' "$FOUT" | grep -qF 'PARTIALLY completed (opencode user unknown (chown skipped), opencode group id unknown)' &&
    printf '%s' "$FOUT" | grep -qF 'opencode group id unknown — its ACL entries left in place' &&
    printf '%s' "$FOUT" | grep -qF 'remove manually: setfacl -R -x g:<gid> -d -x g:<gid>' &&
    printf '%s' "$FOUT" | grep -qF -- 'setfacl -R -x g:60001' &&
    ! printf '%s' "$FOUT" | grep -qF 'WARN:' &&
    ! printf '%s' "$FOUT" | grep -qF 'revert FAILED' &&
    ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "opencode gid unknown: loud skip + template hint + degraded closing, no failure WARN (#218, #243 a Q1)"
else
    fail "opencode gid unknown arms (out=$(_unarm_show "$FOUT")) (#218, #243 a Q1)"
fi
# Unknown uid: chown skipped loudly, ACL ops still run, degraded
# closing names the skip — same not-attempted-is-not-failed rule.
FOUT=$(_un_loop_out "" false "" 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF 'PARTIALLY completed (opencode user unknown (chown skipped))' &&
    printf '%s' "$FOUT" | grep -qF 'chown manually if files are locked' &&
    printf '%s' "$FOUT" | grep -qF -- 'setfacl -R -x g:60002' &&
    ! printf '%s' "$FOUT" | grep -qF 'WARN:' &&
    ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "uid unknown: chown skip lands in degraded closing, ACL ops still run (#218)"
else
    fail "uid unknown arms (out=$(_unarm_show "$FOUT")) (#218)"
fi
# Dry run: [DRY] echoes and the success lines despite failing ops —
# the run_q convention since #211 b W1 (dry reports the intended
# outcome; nothing executes, so nothing can fail). Nothing executes =
# the sudo log stays EMPTY — pinned (#243 a Q5): a refactor that
# executes in dry mode while dropping rc observation would otherwise
# stay green.
FOUT=$(_un_loop_out "find setfacl chmod" true 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF '[DRY] sudo find' &&
    printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj" &&
    ! printf '%s' "$FOUT" | grep -qF 'PARTIALLY' &&
    ! printf '%s' "$FOUT" | grep -qF 'WARN:' &&
    ! printf '%s' "$FOUT" | sed -n '/^--- sudo log ---$/,$p' | grep -q '^sudo '; then
    pass "dry run: [DRY] echo + full-success closing, sudo log empty despite failing stub (#218, #243 a Q5)"
else
    fail "dry run arms (out=$(_unarm_show "$FOUT")) (#218, #243 a Q5)"
fi
# Per-root reset isolation (#243 a S3): two unscreened roots, find
# fails on the PRIMARY root only (the stub boundary-matches fakeproj,
# never fakeproj2) — root 2's closing must be full success with no
# root-1 causes. A reset moved out of the loop accumulates causes and
# turns root 2's line degraded → red.
mkdir -p "$WORK/fakeproj2"
FOUT=$(_un_loop_out "find" false 60000 60002 60001 "$WORK/fakeproj2") || true
if printf '%s' "$FOUT" | grep -qF "log: project revert PARTIALLY completed (find-chown failed): $WORK/fakeproj" &&
    printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj2" &&
    ! printf '%s' "$FOUT" | grep -qF "PARTIALLY completed (find-chown failed): $WORK/fakeproj2" &&
    printf '%s' "$FOUT" | grep -qF "sudo chmod g-s $WORK/fakeproj2"; then
    pass "two roots: root 1 degraded, root 2 closes clean — reset is per-root (#243 a S3)"
else
    fail "two-roots isolation arms (out=$(_unarm_show "$FOUT")) (#243 a S3)"
fi
# Malformed root forms never reach the root-run ops (#243 a X2): the
# reader-side gate mirrors the writer's project_path_sane arms —
# `//etc` (empty segment, bypasses the system-path blocklist
# lexically), `/var/.` (dot segment) and `.` (relative) are skipped
# loudly; the primary root is still processed normally. Op negatives
# cover every op verb (#243 d Q3): find, both setfacl spellings and
# chmod g-s.
FOUT=$(_un_loop_out "" false 60000 60002 60001 "//etc /var/. .") || true
if printf '%s' "$FOUT" | grep -qF 'Skipping malformed project path (dot, empty segment, or whitespace): //etc' &&
    printf '%s' "$FOUT" | grep -qF 'Skipping malformed project path (dot, empty segment, or whitespace): /var/.' &&
    printf '%s' "$FOUT" | grep -qF 'Skipping non-absolute project path: .' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo find //etc' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo setfacl -R -x g:60002 //etc' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo setfacl -R -d -x g:60002 //etc' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo chmod g-s //etc' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo find /var/.' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo chmod g-s /var/.' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo find . !' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo chmod g-s .' &&
    printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj"; then
    pass "malformed roots (//etc, /var/., .) skipped loudly, no root ops on them (#243 a X2)"
else
    fail "malformed-root screening arms (out=$(_unarm_show "$FOUT")) (#243 a X2)"
fi
# Whitespace arm (#418 a A2 — the #247 mirror-or-scope resolution): a
# spaced line naming an EXISTING directory used to pass every gate in
# this loop (the #243 a X2 scope-out) and reach the root-run revert
# ops while the docs claimed loud skips; the arm is mirrored now
# (writer + update-core + config.sh refresh parity — the comment at
# the case arm carries the full history). The spaced root must EXIST:
# the [ ! -d ] gate sits before the form gates and would silently eat
# a nonexistent one (the same ordering the files.md sentence names).
mkdir -p "$WORK/has space"
printf '%s\n/etc\n%s\n' "$WORK/fakeproj" "$WORK/has space" >"$WORK/unloop-ws.conf"
: >"$WORK/unloop-ws-sudo.log"
(
    DRY_RUN=false
    _un_partial=""
    _un_revert_failed=0
    UN_OC_UID=60000
    UN_OC_GID=60002
    UN_DEV_GROUP=devgroup
    UN_DEV_GID=60001
    DEFAULT_USER=devuser
    OPENCODE_USER=untest-agent
    un_opencode_user_gate
    sudo() {
        printf 'sudo %s\n' "$*" >>"$WORK/unloop-ws-sudo.log"
        return 0
    }
    log() { echo "log: $*"; }
    UNINSTALL_PROJECTS_CONF="$WORK/unloop-ws.conf"
    un_projects_revert
) >"$WORK/unloop-ws.log" 2>&1 || true
FOUT=$(cat "$WORK/unloop-ws.log")
if printf '%s' "$FOUT" | grep -qF "Skipping malformed project path (dot, empty segment, or whitespace): $WORK/has space" &&
    ! grep -qF "sudo find $WORK/has space" "$WORK/unloop-ws-sudo.log" &&
    ! grep -qF "sudo setfacl -R -x g:60002 $WORK/has space" "$WORK/unloop-ws-sudo.log" &&
    ! grep -qF "sudo chmod g-s $WORK/has space" "$WORK/unloop-ws-sudo.log" &&
    printf '%s' "$FOUT" | grep -qF 'Skipping system path: /etc' &&
    printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj"; then
    pass "spaced existing root skipped loudly, no revert ops on it (#418 a A2)"
else
    fail "whitespace screening arm (out=$(_unarm_show "$FOUT")) (#418 a A2)"
fi
# _un_exist_roots <root...> — host-existence-filtered feed set (#243
# c Q3): each feed form passes when its once-stripped form is an
# existing directory (the loop's [ ! -d ] gate would silently skip a
# nonexistent root and defang the arm — so only dirs that can actually
# be skipped are fed). One helper for both arms, and pinned below:
# deleting the filter reds the pin HOST-INDEPENDENTLY (#243 d S2 —
# before, the red condition existed only on hosts missing a fed dir).
_un_exist_roots() {
    _un_er_out=""
    for _un_er in "$@"; do
        [ -d "${_un_er%/}" ] && _un_er_out="${_un_er_out:+$_un_er_out }$_un_er"
    done
    printf '%s' "$_un_er_out"
}
if [ "$(_un_exist_roots "$WORK" /opk-243d-nonexistent-root)" = "$WORK" ]; then
    pass "existence filter feeds only host dirs, deletion-red host-independent (#243 c Q3, d S2)"
else
    fail "existence filter feeds only host dirs, deletion-red host-independent (#243 c Q3, d S2)"
fi
# System-path blocklist, behaviorally (#243 b X1): extra roots the
# writer refuses must be screened loudly and no root op may touch
# them, while the primary root — under the sanctioned /tmp scratch —
# still processes (the pinned divergence). Only host-existent dirs
# feed the driver (#243 c Q3): [ ! -d ] runs BEFORE the blocklist and
# would skip a nonexistent path silently, defanging the arm — and
# /srv, /media are not FHS-mandatory — so the fed set is built by
# existence and every assertion names only fed roots (the pass line
# discloses the fed set; a missing dir degrades coverage, never
# truth). Op negatives cover find, setfacl and chmod (#243 d Q3).
_un_sysroots=$(_un_exist_roots /var /home /opt /srv /media /mnt)
FOUT=$(_un_loop_out "" false 60000 60002 60001 "$_un_sysroots") || true
_un_sys_ok=1
for _un_sys in $_un_sysroots; do
    printf '%s' "$FOUT" | grep -qF "Skipping system path: $_un_sys" || _un_sys_ok=0
    printf '%s' "$FOUT" | grep -qF "sudo find $_un_sys " && _un_sys_ok=0
    printf '%s' "$FOUT" | grep -qF "sudo setfacl -R -x g:60002 $_un_sys" && _un_sys_ok=0
    printf '%s' "$FOUT" | grep -qF "sudo chmod g-s $_un_sys" && _un_sys_ok=0
done
printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj" ||
    _un_sys_ok=0
if [ "$_un_sys_ok" -eq 1 ]; then
    pass "system-path roots (${_un_sysroots:-none fed}) screened, no root ops, primary root processes (#243 b X1, c Q3)"
else
    fail "system-path blocklist arms (out=$(_unarm_show "$FOUT")) (#243 b X1, c Q3)"
fi
# Trailing-slash normalization, behaviorally (#243 c X1): the bare
# arms' /-suffix spellings must be screened after the writer-parity
# strip — /var/ and /home/ normalize onto the bare arms the case
# refuses (pre-fix they passed gate + blocklist lexically while the
# writer refuses the stripped form, sh/path-sane.sh `_pp="${1%/}"`). The
# same arm pins the two hazards the strip could itself create:
# /var// must stay the DOT GATE's catch (a strip placed before the
# gate would turn it into /var/ and open the blocklist hole back
# up), and / must normalize onto the blocklist's `/` arm, never to
# an empty operand. Find negatives are ANCHORED with the op line's
# ` !` continuation (#243 d Q4: the old unanchored `sudo find /var/`
# over-matched any longer /var-prefixed operand) and cover both the
# normalized leak (`sudo find /var !`) and the raw one (strip
# deleted, `sudo find /var/ !`); setfacl/chmod negatives per d Q3,
# line-end anchored (#243 e S5: the root is their LAST operand, so a
# `$` binds each negative to its own spelling — the unanchored forms
# also matched the same-arm /var// op lines and misattributed the
# failure to the trailing-slash arm instead of the dot gate).
_un_tsroots=$(_un_exist_roots /var/ /home/)
FOUT=$(_un_loop_out "" false 60000 60002 60001 "$_un_tsroots / /var//") || true
_un_ts_ok=1
for _un_ts in $_un_tsroots; do
    printf '%s' "$FOUT" | grep -qF "Skipping system path: ${_un_ts%/}" || _un_ts_ok=0
    printf '%s' "$FOUT" | grep -qF "sudo find ${_un_ts%/} !" && _un_ts_ok=0
    printf '%s' "$FOUT" | grep -qF "sudo find ${_un_ts%/}/ !" && _un_ts_ok=0
    printf '%s' "$FOUT" | grep -q "sudo setfacl -R -x g:60002 ${_un_ts%/}\$" && _un_ts_ok=0
    printf '%s' "$FOUT" | grep -q "sudo setfacl -R -x g:60002 ${_un_ts%/}/\$" && _un_ts_ok=0
    printf '%s' "$FOUT" | grep -q "sudo chmod g-s ${_un_ts%/}\$" && _un_ts_ok=0
    printf '%s' "$FOUT" | grep -q "sudo chmod g-s ${_un_ts%/}/\$" && _un_ts_ok=0
done
printf '%s' "$FOUT" | grep -q 'Skipping system path: /$' || _un_ts_ok=0
printf '%s' "$FOUT" | grep -qE 'Reverting kit ownership in: *$' && _un_ts_ok=0
printf '%s' "$FOUT" | grep -qF 'sudo find / !' && _un_ts_ok=0
printf '%s' "$FOUT" | grep -qF 'Skipping malformed project path (dot, empty segment, or whitespace): /var//' || _un_ts_ok=0
printf '%s' "$FOUT" | grep -qF 'sudo find /var// !' && _un_ts_ok=0
printf '%s' "$FOUT" | grep -q 'sudo setfacl -R -x g:60002 /var//$' && _un_ts_ok=0
printf '%s' "$FOUT" | grep -q 'sudo chmod g-s /var//$' && _un_ts_ok=0
printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj" ||
    _un_ts_ok=0
if [ "$_un_ts_ok" -eq 1 ]; then
    pass "trailing-slash spellings (${_un_tsroots:-none fed} / //) screened; // stays the dot gate's catch (#243 c X1)"
else
    fail "trailing-slash normalization arms (out=$(_unarm_show "$FOUT")) (#243 c X1)"
fi
# Agent-home refusal, behaviorally (#243 c Q1, both spellings #243
# d X2): the driver pins OPENCODE_USER=untest-agent, so the fed
# roots /home/untest-agent (raw) AND /home/untest-agent/ (trailing
# slash — the once-stripped comparator's case, unpinned before d
# X2) hit the mirrored writer refusal — the check is lexical and
# before the [ -d ] gate, so no host dir is needed; no root op may
# touch either form (op negatives incl. both setfacl spellings, d
# Q3). The skip echo prints the RAW root, so each form's echo is
# asserted verbatim — the raw assertion is END-ANCHORED (#243 e S2):
# the raw pattern is a strict prefix of the trailing-slash echo, so
# an unanchored grep is satisfied by either line and cannot red on a
# raw-echo-only omission.
FOUT=$(_un_loop_out "" false 60000 60002 60001 "/home/untest-agent /home/untest-agent/") || true
if printf '%s' "$FOUT" | grep -q 'Skipping agent home (never a project root): /home/untest-agent$' &&
    printf '%s' "$FOUT" | grep -qF 'Skipping agent home (never a project root): /home/untest-agent/' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo find /home/untest-agent' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo setfacl -R -x g:60002 /home/untest-agent' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo setfacl -R -d -x g:60002 /home/untest-agent' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo chmod g-s /home/untest-agent' &&
    printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj"; then
    pass "agent home refused lexically before [ -d ] (raw + trailing slash), no root ops, primary root processes (#243 c Q1, d X2)"
else
    fail "agent-home refusal arms (out=$(_unarm_show "$FOUT")) (#243 c Q1, d X2)"
fi
# Corrupted-conf chain (#243 e X1): OPENCODE_USER arrives carrying a
# trailing slash (hand-edited install.conf) — the shape gate must
# normalize it to 'opencode' BEFORE the loop, so BOTH /home/opencode
# spellings hit the agent-home refusal and no root op runs. Without
# the gate the single stripped compare misses the trailing-slash
# spelling (the compare TARGET itself carries the slash) and the
# root-run revert ops run over the agent home — the SKIP→OPS flip
# review e probed old-vs-new. Host-independent: the refusal is
# lexical, before the [ -d ] gate.
FOUT=$(_un_loop_out "" false 60000 60002 60001 "/home/opencode /home/opencode/" "opencode/") || true
if printf '%s' "$FOUT" | grep -qF 'WARN: invalid OPENCODE_USER value in install.conf' &&
    printf '%s' "$FOUT" | grep -q 'Skipping agent home (never a project root): /home/opencode$' &&
    printf '%s' "$FOUT" | grep -qF 'Skipping agent home (never a project root): /home/opencode/' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo find /home/opencode' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo setfacl -R -x g:60002 /home/opencode' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo setfacl -R -d -x g:60002 /home/opencode' &&
    ! printf '%s' "$FOUT" | grep -qF 'sudo chmod g-s /home/opencode' &&
    printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj"; then
    pass "corrupted OPENCODE_USER gated back to canonical, agent home refused, no root ops (#243 e X1)"
else
    fail "corrupted-conf agent-home arms (out=$(_unarm_show "$FOUT")) (#243 e X1)"
fi

# --- 4d. config-dirs + openchamber closing-log honesty (#243 a S1/S2) -------------
# The config-dirs section used to run rc-blind `run` rm ops into an
# unconditional "Removed." + success log — the same c W1 class, the
# site the snapshot-a class sweep surfaced. The section is extracted
# and driven REAL (real un_rc_q + real section text) through a
# per-command sudo stub; <fail-spec> entries are "name:substring"
# pairs — fail when the command's first word is <name> AND the full
# command contains <substring> (space-free paths make word-splitting
# safe). The openchamber guard probes (test/grep) can pass while the
# rm fails — exactly the discrimination S2 needs.
# #396 payoff: the section is un_config_dirs_remove now — sourced and
# called below; the extraction pin became this def+content check.
if command -v un_config_dirs_remove >/dev/null &&
    grep -qF 'un_rc_q "rm /etc/opencode-permissions-kit"' "$LIB" &&
    grep -qF 'openchamber policy pin removal FAILED' "$LIB"; then
    pass "config-dirs section present + rc-observing (#243 a S1/S2)"
else
    fail "config-dirs section content/rc observation (#243 a S1/S2)"
fi
_un_cfg_out() {
    _unc_fail="$1"
    _unc_dry="$2"
    : >"$WORK/uncfg-sudo.log"
    : >"$WORK/uncfg-out.log"
    : >"$WORK/uncfg-err.log"
    (
        DRY_RUN="$_unc_dry"
        # Stale pre-state (#243 b S2): on a real run the project loop
        # executes BEFORE this section and leaves its partial state
        # behind — the section's OWN reset must clear it. Planting a
        # dirty pre-state (instead of the former clean pre-init, which
        # masked a deleted reset) makes every cfg arm discriminate:
        # without the shipped reset the stale cause leaks into the
        # closing and the all-ok/dry arms go red.
        _un_partial="find-chown failed (stale from the project loop)"
        _un_revert_failed=1
        sudo() {
            printf 'sudo %s\n' "$*" >>"$WORK/uncfg-sudo.log"
            for _unc_s in $_unc_fail; do
                if [ "$1" = "${_unc_s%%:*}" ]; then
                    case "$*" in
                        *"${_unc_s#*:}"*) return 1 ;;
                    esac
                fi
            done
            return 0
        }
        log() { echo "log: $*"; }
        un_config_dirs_remove
    ) >"$WORK/uncfg-out.log" 2>"$WORK/uncfg-err.log"
    echo "--- stdout ---"
    cat "$WORK/uncfg-out.log"
    echo "--- stderr ---"
    cat "$WORK/uncfg-err.log"
    echo "--- sudo log ---"
    cat "$WORK/uncfg-sudo.log"
}
COUT=$(_un_cfg_out "" false) || true
if printf '%s' "$COUT" | grep -qF 'Removed.' &&
    printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts removed (/etc/opencode-permissions-kit, /run/opencode-permissions-kit, 99-ddev-rootless.conf)' &&
    printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removed (kit-owned content only)' &&
    ! printf '%s' "$COUT" | grep -qF 'WARN:' &&
    ! printf '%s' "$COUT" | grep -qF 'PARTIALLY' &&
    ! printf '%s' "$COUT" | grep -qF 'stale from the project loop'; then
    pass "config-dirs all ok: Removed. + success logs, stale pre-state cleared, no partial/WARN noise (#243 a S1/S2, b S2)"
else
    fail "config-dirs all-ok arms (out=$(_unarm_show "$COUT")) (#243 a S1/S2, b S2)"
fi
# Openchamber pin rm fails (S2): its success log must NOT fire; the
# failure WARNs on stderr (channel pinned) and lands in the section's
# partial list, degrading the section closing.
COUT=$(_un_cfg_out "rm:/etc/openchamber/policy.json" false) || true
if printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removal FAILED (rm)' &&
    printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts PARTIALLY removed (openchamber policy pin rm failed)' &&
    printf '%s' "$COUT" | sed -n '/^--- stderr ---$/,/^--- sudo log ---$/p' | grep -qF 'WARN: could not remove the openchamber policy pin (rm failed)' &&
    printf '%s' "$COUT" | sed -n '/^--- stderr ---$/,/^--- sudo log ---$/p' | grep -qF 'WARN: could not fully remove config dirs + runtime artifacts (openchamber policy pin rm failed)' &&
    ! printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removed' &&
    ! printf '%s' "$COUT" | grep -qF 'artifacts removed ('; then
    pass "openchamber rm failure: FAILED log + both WARNs on stderr, section closing degrades (#243 a S2, b Q2)"
else
    fail "openchamber rm failure arms (out=$(_unarm_show "$COUT")) (#243 a S2, b Q2)"
fi
# Two section rms fail (S1): both named in the degraded closing, in
# section order; the surviving openchamber pin still logs its success.
COUT=$(_un_cfg_out "rm:99-ddev-rootless.conf rm:/etc/opencode-permissions-kit" false) || true
if printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts PARTIALLY removed (rm 99-ddev-rootless.conf failed, rm /etc/opencode-permissions-kit failed)' &&
    printf '%s' "$COUT" | grep -qF 'WARN: could not fully remove config dirs + runtime artifacts' &&
    printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removed (kit-owned content only)' &&
    ! printf '%s' "$COUT" | grep -qF 'Removed.'; then
    pass "section rm failures: both named in degraded closing + WARN, no false Removed. (#243 a S1)"
else
    fail "section rm failure arms (out=$(_unarm_show "$COUT")) (#243 a S1)"
fi
# Dry run: [DRY] echoes and the success lines despite the failing
# stub — the run_q convention (#211 b W1). The guard probes
# (test/grep) legitimately execute as reads; no rm ever runs.
COUT=$(_un_cfg_out "rm:/etc/opencode-permissions-kit" true) || true
if printf '%s' "$COUT" | grep -qF '[DRY] sudo rm -rf /run/opencode-permissions-kit' &&
    printf '%s' "$COUT" | grep -qF '[DRY] sudo rm -f /etc/openchamber/policy.json' &&
    printf '%s' "$COUT" | grep -qF 'Removed.' &&
    printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts removed' &&
    ! printf '%s' "$COUT" | grep -qF 'PARTIALLY'; then
    pass "config-dirs dry: [DRY] echoes + success lines, no partial noise (#243 a S1)"
else
    fail "config-dirs dry arms (out=$(_unarm_show "$COUT")) (#243 a S1)"
fi

# --- prompt_yn: answer semantics + shape (issue #187 A/B) -----------------------
# Extract-and-run under a real pty (script(1), like test-browser-bridge):
# prompt_yn hard-exits without a terminal (by design), so the setsid
# pattern of test-ui.sh cannot drive it. Unknown input must fall back
# to the DEFAULT — the 0.0.44a V17 sweep fixed ui.sh's ui_confirm but
# missed this standalone sibling; mixed-case answers are honored; the
# prompt renders the shared marker-less shape.
# #396 payoff: prompt_yn is sourced from the lib (PY_SRC below) — the
# pty driver calls the real function; the [y/n] arms are pinned by the
# py_pin legs. The [?] marker sweep covers BOTH files now (prompt_yn
# lives in the lib; the entry must stay marker-free too).
if grep -qF 'n | no)' "$LIB" && ! grep -qF '[?]' "$LIB" && ! grep -qF '[?]' "$UNINSTALL"; then
    pass "prompt_yn in the lib with n|no arm, no [?] marker anywhere"
else
    fail "prompt_yn arms / [?] marker sweep (lib+entry)"
fi
cat >"$WORK/py-driver.sh" <<'PYEOF'
#!/bin/sh
# $1 = default; prints prompt_yn's answer on stdout
RED='' NC='' YES=false
trace() { :; }
. "${PY_SRC:?}"
prompt_yn "Delete audit log too?" "${1:?}"
PYEOF
py_ask() { # <typed-line> <default> -> last pty line (prompt + answer)
    printf '%s\n' "$1" | PY_SRC="$LIB" \
        script -qec "sh '$WORK/py-driver.sh' '$2'" /dev/null 2>/dev/null |
        tr -d '\r' | tail -1
}
py_pin() { # <desc> <typed> <default> <expected answer y|n>
    _pyline=$(py_ask "$2" "$3")
    case "$_pyline" in
        *" $4") pass "$1" ;;
        *) fail "$1 (got: $_pyline)" ;;
    esac
}
py_pin "prompt_yn: unknown input falls back to a y default (issue #187 A)" j y y
py_pin "prompt_yn: unknown input falls back to an n default (issue #187 A)" j n n
py_pin "prompt_yn: mixed-case Yes accepted under an n default (issue #187 C class)" Yes n y
py_pin "prompt_yn: mixed-case No declines under a y default (issue #187 C class)" No y n
py_pin "prompt_yn: padded ' y' accepted under an n default (#189 a W2 — pins the pre-existing trim)" " y" n y
py_pin "prompt_yn: trailing-space 'no ' declines under a y default (#189 a W2)" "no " y n
py_pin "prompt_yn: Enter accepts the y default (regression guard)" "" y y
# Shape (issue #187 B): two-space indent, no [?] marker, capital default.
_pyline=$(py_ask "" n)
if printf '%s' "$_pyline" | grep -qF '  Delete audit log too? [y/N] ' &&
    ! printf '%s' "$_pyline" | grep -qF '[?]'; then
    pass "prompt_yn shape: '  <question> [y/N] ' — no marker (issue #187 B)"
else
    fail "prompt_yn shape: '  <question> [y/N] ' — no marker (got: $_pyline)"
fi

# --- F27: bridge removal honesty (#211 a F27) ---------------------------------------
# The silent noop stub + unconditional echo claimed a removal that never
# ran when the helper was missing. Extract the real consent block and
# drive both arms with a stubbed browser_bridge_remove + auto-yes prompt.
# Retargeted extraction, deliberately kept (review-concept.md, "Review
# focus: shipped code first, pins at a floor"): the obstacle is the
# marker GUARD's hardcoded /etc/wsl.conf grep — a whole-section sourcing
# drive would need a grep shadow to stay hermetic (feasible, but that
# conversion is recorded pin polish, not owed here); the standalone block
# with stubbed helpers stays hermetic as-is. Its declined arm still greps
# the host's /etc/wsl.conf, silenced — assertions are substring-based and
# survive marker-carrying hosts. Anchors moved with the section into
# un_wsl_bridge_remove (end anchor one level deeper now); over-capture
# after future indent drift stays syntactically consumable — the
# block-identity upgrade rides the same polish order.
_f27_block="$(sed -n "/Remove the kit's wsl.conf bridge block/,/^            fi$/p" \
    "$LIB")"
if [ -n "$_f27_block" ] && printf '%s' "$_f27_block" | grep -q 'browser_bridge_remove'; then
    pass "bridge removal block extractable (#211 a F27)"
    _f27_run() {
        (
            prompt_yn() { printf 'y'; }
            log() { echo "log: $*"; }
            # #211 b W14: the extract spans the declined-consent arm's
            # live `sudo rm -rf` — stub sudo so no future drive can
            # execute it for real on a kit-managed host.
            sudo() {
                echo "sudo: $*"
                return 0
            }
            browser_bridge_remove() {
                [ "$F27MODE" = ok ] && return 0
                return 1
            }
            eval "$_f27_block"
        ) 2>&1
    }
    _out=$(F27MODE=ok _f27_run 0) || true
    case "$_out" in
        *"WSL browser bridge removed"*) pass "helper present: removal reported (#211 a F27)" ;;
        *) fail "helper present: removal reported (got: $_out)" ;;
    esac
    _out=$(F27MODE=fail _f27_run 1) || true
    case "$_out" in
        *"WARN: could not remove the wsl.conf bridge block"*) pass "helper missing: warn, no false removed (#211 a F27)" ;;
        *) fail "helper missing: warn, no false removed (got: $_out)" ;;
    esac
    # (#370 a D2): the WARN names the real arm (helper or staging
    # mktemp -- the log always said so), and the by-hand hint covers
    # BOTH shapes the marker gate serves: the comment block AND the
    # legacy [opencode-permissions-kit] section (the same gate serves
    # both; "comment-only" was false for the section shape).
    case "$_out" in
        *"helper or staging mktemp failed)"*) pass "fail arm names the real cause (#370 a D2)" ;;
        *) fail "fail arm names the real cause (got: $_out) (#370 a D2)" ;;
    esac
    case "$_out" in
        *"[opencode-permissions-kit] section"*) pass "by-hand hint covers the legacy section too (#370 a D2)" ;;
        *) fail "by-hand hint covers the legacy section too (got: $_out) (#370 a D2)" ;;
    esac
    case "$_out" in
        *"comment-only"*) fail "false 'comment-only' claim gone (#370 a D2)" ;;
        *) pass "false 'comment-only' claim gone (#370 a D2)" ;;
    esac
    # (#370 a D1): the consent prompt defaults to n (the conventions'
    # system-change default, agent/conventions.md "Interactive
    # prompts" — a change
    # to the user-owned wsl.conf; the DRY row says the same). Source
    # pins: the marker-guarded arm is not hermetically driveable (the
    # guard greps the host's /etc/wsl.conf, see the F27 note above) --
    # the call spans the dq splice, so the second line carries the
    # default. Comment-strip ridden.
    if printf '%s' "$_f27_block" | sed 's/^[[:space:]]*#.*$//' |
        grep -qF 'kit-owned lines only; your own entries stay)" "n"'; then
        pass "wsl.conf consent defaults to n (#370 a D1)"
    else
        fail "wsl.conf consent defaults to n (#370 a D1)"
    fi
    if sed 's/^[[:space:]]*#.*$//' "$LIB" |
        grep -qF '[DRY] ask: remove the kit-owned wsl.conf bridge block? (default: no)'; then
        pass "DRY row states the default: no (#370 a D1)"
    else
        fail "DRY row states the default: no (#370 a D1)"
    fi
else
    fail "bridge removal block extractable (#211 a F27)"
fi

# --- F28: group removal exact + honest (#211 a F28) --------------------------------
# The membership probe was a substring grep (a group 'opencode2' matched
# 'opencode') and the success echo printed over a silenced gpasswd
# failure. Extract the real block; stub id/run_q/log; drive all arms.
# #396 payoff: the block is un_group_membership_remove now — sourced and
# called; id/sudo stubs keep every arm hermetic.
if command -v un_group_membership_remove >/dev/null; then
    pass "group removal function present (#211 a F28)"
    _f28_run() {
        # $1 = groups-print, $2 = gpasswd rc — sudo stubbed (#211 b W1):
        # the block calls sudo directly now (run_q is rc-blind by design
        # and must not be faked into propagating), so the pin drives the
        # real shipped wiring at the real seam.
        (
            DEFAULT_USER=dev
            OPENCODE_GROUP=opencode
            DRY_RUN="${DRY_RUN:-false}"
            id() {
                printf '%s\n' "uid=1(dev) gid=1(dev) groups=1(dev),$F28GRPS"
                return 0
            }
            sudo() { return "$F28GP"; }
            log() { echo "log: $*"; }
            un_group_membership_remove
        )
    }
    _out=$(F28GP=0 F28GRPS="50(opencode)" _f28_run) || true
    case "$_out" in
        *"Removed dev from group opencode."*) pass "member + gpasswd ok: removed reported (#211 a F28)" ;;
        *) fail "member + gpasswd ok: removed reported (got: $_out)" ;;
    esac
    _out=$(F28GP=1 F28GRPS="50(opencode)" _f28_run 2>&1) || true
    case "$_out" in
        *"WARN: could not remove dev from group opencode"*) pass "gpasswd failure: warn, no false removed (#211 a F28)" ;;
        *) fail "gpasswd failure: warn (got: $_out)" ;;
    esac
    _out=$(F28GP=0 F28GRPS="50(opencode2)" _f28_run) || true
    case "$_out" in
        *"Removed"*) fail "opencode2 must NOT count as membership (#211 a F28)" ;;
        *) pass "exact-name match: opencode2 is not opencode (#211 a F28)" ;;
    esac
    _out=$(F28GP=1 F28GRPS="50(opencode)" DRY_RUN=true _f28_run 2>&1) || true
    case "$_out" in
        *"[DRY] sudo gpasswd"*"Removed dev from group opencode."*)
            pass "dry run: [DRY] echo + success lines despite rc (#211 b W1)"
            ;;
        *) fail "dry run: [DRY] echo + success lines (got: $_out)" ;;
    esac
else
    fail "group removal block extractable (#211 a F28)"
fi

# --- c W1: userdel + audit-log arms honest (#211 c W1) ------------------------------
# The b W1 sweep claim called the remaining run_q uses "bare best-effort
# cleanup" — userdel (the primary destructive op) and the audit-log rm
# both lied in the gpasswd shape: rc-blind call, unconditional success
# echo/log. Extract both real blocks; stub sudo (the REAL seam — run_q
# is rc-blind by design and must not be faked into propagating) and
# drive every arm.
# #396 payoff: the block is un_user_remove now — sourced and called
# (banner + delegated group removal + the userdel flow). The group
# membership probe inside fires first with the stubbed id; its output
# rides along (the assertions below grep their specific lines).
if command -v un_user_remove >/dev/null; then
    pass "user removal function present (#211 c W1)"
    _cw1_udel_run() {
        (
            OPENCODE_USER=oc
            DEFAULT_USER=dev
            DRY_RUN="${CW1DRY:-false}"
            id() {
                [ "$1" = "-u" ] && printf '900\n'
                return 0
            }
            prompt_yn() { printf 'y\n'; }
            sleep() { :; }
            sudo() {
                case "$1" in userdel) return "$CW1UDEL" ;; esac
                return 0
            }
            # run_q comes REAL from the lib (sourced) — the stub the
            # extraction era needed is gone; its calls go to the stubbed
            # sudo like every other op.
            log() { echo "log: $*"; }
            un_user_remove
        )
    }
    _out=$(CW1UDEL=0 _cw1_udel_run) || true
    case "$_out" in
        *"User 'oc' removed."*"log: user removed: oc"*)
            pass "userdel ok: removal reported (#211 c W1)"
            ;;
        *) fail "userdel ok: removal reported (got: $_out) (#211 c W1)" ;;
    esac
    _out=$(CW1UDEL=1 _cw1_udel_run 2>&1) || true
    _cw1_ok=0
    case "$_out" in *"WARN: could not remove user 'oc' (userdel failed)"*) ;; *) _cw1_ok=1 ;; esac
    case "$_out" in *"log: user removal FAILED for oc (userdel)"*) ;; *) _cw1_ok=1 ;; esac
    case "$_out" in *"User 'oc' removed."*) _cw1_ok=1 ;; esac
    if [ "$_cw1_ok" -eq 0 ]; then
        pass "userdel failure: warn + FAILED log, no false removed (#211 c W1)"
    else
        fail "userdel failure arms (got: $_out) (#211 c W1)"
    fi
    _out=$(CW1UDEL=1 CW1DRY=true _cw1_udel_run 2>&1) || true
    case "$_out" in
        *"[DRY] sudo userdel -r oc"*"User 'oc' removed."*)
            pass "userdel dry run: [DRY] echo + success lines despite rc (#211 c W1)"
            ;;
        *) fail "userdel dry run: [DRY] echo + success lines (got: $_out) (#211 c W1)" ;;
    esac
else
    fail "user removal block extractable (#211 c W1)"
fi
# #396 payoff: the block is un_audit_log_remove now — sourced and called.
if command -v un_audit_log_remove >/dev/null; then
    pass "audit-log function present (#211 c W1)"
    _cw1_al_run() {
        (
            DRY_RUN="${CW1DRY:-false}"
            prompt_yn() { printf 'y\n'; }
            sudo() { return "$CW1AL"; }
            log() { echo "log: $*"; }
            un_audit_log_remove
        )
    }
    _out=$(CW1AL=0 _cw1_al_run) || true
    case "$_out" in
        *"Audit log removed."*"log: audit log removed: /var/log/opencode-permissions-kit"*)
            pass "audit rm ok: removal reported after the act (#211 c W1)"
            ;;
        *) fail "audit rm ok: removal reported (got: $_out) (#211 c W1)" ;;
    esac
    _out=$(CW1AL=1 _cw1_al_run 2>&1) || true
    _cw1_ok=0
    case "$_out" in *"WARN: could not remove the audit log"*) ;; *) _cw1_ok=1 ;; esac
    # The arm names the failing command like its siblings (#211 e W3);
    # the log line's changed tail is pinned too, mirroring the userdel
    # sibling's full-wording arm (#211 f W1).
    case "$_out" in *"(rm failed)"*) ;; *) _cw1_ok=1 ;; esac
    case "$_out" in *"log: audit log removal FAILED for /var/log/opencode-permissions-kit (rm)"*) ;; *) _cw1_ok=1 ;; esac
    case "$_out" in *"Audit log removed."*) _cw1_ok=1 ;; esac
    if [ "$_cw1_ok" -eq 0 ]; then
        pass "audit rm failure: warn + FAILED log, no false removed (#211 c W1)"
    else
        fail "audit rm failure arms (got: $_out) (#211 c W1)"
    fi
    _out=$(CW1AL=1 CW1DRY=true _cw1_al_run 2>&1) || true
    case "$_out" in
        *"[DRY] sudo rm -rf /var/log/opencode-permissions-kit"*"Audit log removed."*)
            pass "audit rm dry run: [DRY] echo + success lines despite rc (#211 c W1)"
            ;;
        *) fail "audit rm dry run: [DRY] echo + success lines (got: $_out) (#211 c W1)" ;;
    esac
else
    fail "audit-log block extractable (#211 c W1)"
fi

# --- agents-backup failure arm names the failing commands (#211 f W2) ----------
# Retargeted extraction, deliberately kept (review-concept.md, "Review
# focus: shipped code first, pins at a floor"): this driver stubs
# sudo (test/ls/mkdir/cp) — the /home/<agent> literals are never executed
# as paths, so no rewrite is needed and the failure arm pins verbatim; a
# whole-function sourcing drive (un_user_remove with the same stubs) has
# suite precedent but is recorded pin polish, not owed here. The W2 gate
# pin above is the one that genuinely needs the sed scratch rewrite (its
# sudo stub EXECs, so the readable-.agents fixture must live at a
# rewritable path). Anchors: 12-space nesting inside un_user_remove.
_f2_bak_block="$(sed -n '/^            for _un_ag_dirname in \.agents \.claude; do$/,/^            done$/p' "$LIB")"
if [ -n "$_f2_bak_block" ]; then
    pass "agents-backup loop extractable (#211 f W2)"
    _f2_bak_run() {
        (
            OPENCODE_USER=oc
            DRY_RUN="${F2DRY:-false}"
            sudo() {
                case "$1" in
                    test) return 0 ;;
                    ls)
                        echo "agent-resource"
                        return 0
                        ;;
                    mkdir | cp) return "${F2BAKRC:-1}" ;;
                    chmod) return "${F2CHMODRC:-0}" ;;
                    *) return 0 ;;
                esac
            }
            log() { echo "log: $*"; }
            eval "$_f2_bak_block"
        )
    }
    _out=$(F2BAKRC=1 _f2_bak_run 2>&1) || true
    _f2_ok=0
    case "$_out" in *"WARNING: could not back up /home/oc/.agents"*) ;; *) _f2_ok=1 ;; esac
    case "$_out" in *"(mkdir/cp failed)"*) ;; *) _f2_ok=1 ;; esac
    case "$_out" in *"log: agents backup FAILED before userdel: .agents (mkdir/cp)"*) ;; *) _f2_ok=1 ;; esac
    case "$_out" in *"Agent resources backed up:"*) _f2_ok=1 ;; esac
    if [ "$_f2_ok" -eq 0 ]; then
        pass "backup failure: warning names mkdir/cp, no false backed-up (#211 f W2)"
    else
        fail "backup failure arm (got: $_out) (#211 f W2)"
    fi
    # LOWS-6 (#430): the mode re-assert sits in the THEN body, after the
    # ownership handover — its failure must degrade LOUD without
    # falsifying the backup claim (the copy already succeeded; routing
    # it to the "could not back up" arm would be the false claim, and
    # set -e would abort the whole uninstall past a made backup).
    # Drive: mkdir/cp succeed (F2BAKRC=0), chmod fails (F2CHMODRC=1).
    _out=$(F2BAKRC=0 F2CHMODRC=1 _f2_bak_run 2>&1) || true
    _f2_ok=0
    case "$_out" in *"WARNING: could not enforce mode 700 on "*) ;; *) _f2_ok=1 ;; esac
    case "$_out" in *"log: agents backup mode assert failed: "*) ;; *) _f2_ok=1 ;; esac
    case "$_out" in *"Agent resources backed up:"*) ;; *) _f2_ok=1 ;; esac
    case "$_out" in *"could not back up"*) _f2_ok=1 ;; esac
    if [ "$_f2_ok" -eq 0 ]; then
        pass "mode-assert failure degrades loud, backup claim stays true (#430)"
    else
        fail "mode-assert failure arm (got: $_out) (#430)"
    fi
    # (#438 a A5): the ordering claim — ownership handover BEFORE the
    # chmod re-assert — was behaviorally unobserved (both W2 and the
    # F2 drives skip the chown: absent devuser / unset DEFAULT_USER).
    # Drive the extracted block with id() stubbed so the handover
    # EXECUTES; assert the sudo log ORDER (chown strictly before
    # chmod). (#438 a A2) rides the same driver with id() failing:
    # the skip must be LOUD (WARNING + log) while the backup claim
    # stays true. sudo logs without executing — no real paths run.
    _f2ord_run() {
        (
            OPENCODE_USER=oc
            DEFAULT_USER=dev
            DRY_RUN=false
            id() { return "${F2ORDID:-0}"; }
            sudo() {
                case "$1" in
                    ls) echo "agent-resource" ;;
                    *) echo "sudo $*" ;;
                esac
                return 0
            }
            log() { echo "log: $*"; }
            eval "$_f2_bak_block"
        )
    }
    _f2ord_out=$(F2ORDID=0 _f2ord_run 2>&1) || true
    _f2ord_log=$(printf '%s\n' "$_f2ord_out" | grep '^sudo ')
    _f2ord_chn=$(printf '%s\n' "$_f2ord_log" | grep -n 'chown -R' | head -n 1 | cut -d: -f1)
    _f2ord_chm=$(printf '%s\n' "$_f2ord_log" | grep -n 'chmod 700' | head -n 1 | cut -d: -f1)
    if [ -n "$_f2ord_chn" ] && [ -n "$_f2ord_chm" ] &&
        [ "$_f2ord_chn" -lt "$_f2ord_chm" ]; then
        pass "handover executes and precedes the chmod re-assert (#438 a A5)"
    else
        fail "handover order unobserved (chown=${_f2ord_chn:-none} chmod=${_f2ord_chm:-none} log=$_f2ord_log) (#438 a A5)"
    fi
    _f2ord_out=$(F2ORDID=1 _f2ord_run 2>&1) || true
    _f2_ok=0
    case "$_f2ord_out" in *"WARNING: developer 'dev' not found"*) ;; *) _f2_ok=1 ;; esac
    case "$_f2ord_out" in *"restoring needs sudo"*) ;; *) _f2_ok=1 ;; esac
    case "$_f2ord_out" in *"log: agents backup owner handover skipped: DEFAULT_USER 'dev' missing"*) ;; *) _f2_ok=1 ;; esac
    case "$_f2ord_out" in *"Agent resources backed up:"*) ;; *) _f2_ok=1 ;; esac
    case "$_f2ord_out" in *"could not back up"*) _f2_ok=1 ;; esac
    if [ "$_f2_ok" -eq 0 ]; then
        pass "chown-skip is loud, restore hint names sudo, backup claim stays true (#438 a A2)"
    else
        fail "chown-skip arm (got: $_f2ord_out) (#438 a A2)"
    fi
else
    fail "agents-backup loop extractable (#211 f W2)"
fi

# --- sudoers section arms, sourcing pin (moved from test-uninstall.sh) --------
# pr-00263 a F3: the sudoers section routes through un_rc_q; driven REAL
# with a stubbed sudo — failure WARNs + FAILED log, no success echo; a
# succeeding stub keeps the success lines. The stale pre-state proves the
# section's own reset. The legacy arms below the first block read host
# state read-only ([ -d /etc/opencode ] — absent on test hosts, the loop
# skips; every rm rides the stubbed sudo either way).
_un_f3_out() { # <sudo-rc> — drive the section REAL with a stubbed sudo
    (
        DRY_RUN=false
        _un_partial="stale"
        _un_revert_failed=1
        _un_f3_rc="$1"
        log() { echo "LOG:$*"; }
        sudo() { return "$_un_f3_rc"; }
        un_sudoers_remove
    ) 2>&1
}
_f3fail="$(_un_f3_out 1)" || true
_f3ok="$(_un_f3_out 0)" || true
if printf '%s' "$_f3fail" | grep -q 'WARN: sudoers removal failed' &&
    printf '%s' "$_f3fail" | grep -q 'LOG:sudoers removal FAILED' &&
    ! printf '%s' "$_f3fail" | grep -q 'sudoers removed\.' &&
    printf '%s' "$_f3ok" | grep -q 'sudoers removed\.' &&
    printf '%s' "$_f3ok" | grep -q 'LOG:sudoers removed'; then
    pass "sudoers section arms: failure WARNs, success echoes (pr-00263 a F3)"
else
    fail "sudoers section arms (pr-00263 a F3, fail-out: $_f3fail / ok-out: $_f3ok)"
fi

# --- pairing guard (#413, the finding's own entry): skewed pairing dies loud --------
# uninstall is fail-soft (no set -e) — an undefined section call does
# NOT abort: it rc-127s, the removal is silently skipped and the run
# still prints "Uninstall complete." (the #413 mechanism verbatim).
# Both directions in fresh children + completeness rider.
_pg_src="$(extract_func "$UNINSTALL" un_pairing_guard)"
_pg_full=$(sh -c 'eval "$1"; . "$2"; un_pairing_guard; echo "rc=$?"' _ "$_pg_src" "$LIB" 2>&1)
_pg_tr_rc=0
_pg_tr_out="$(sh -c 'eval "$1"; un_pairing_guard' _ "$_pg_src" 2>&1)" || _pg_tr_rc=$?
if printf '%s' "$_pg_full" | grep -q 'rc=0'; then
    pass "pairing guard: real lib passes (every section defined) (#413)"
else
    fail "pairing guard must pass against the real lib (out=$_pg_full) (#413)"
fi
if [ "$_pg_tr_rc" -eq 1 ] &&
    printf '%s' "$_pg_tr_out" | grep -qF "section 'un_context_load' missing from uninstall-core.sh" &&
    printf '%s' "$_pg_tr_out" | grep -qF "version-skewed entry/lib pairing"; then
    pass "pairing guard: truncated lib dies loud before the first prompt (#413)"
else
    fail "pairing guard must refuse a skewed pairing (rc=$_pg_tr_rc out=$_pg_tr_out) (#413)"
fi
if sed 's/^[[:space:]]*#.*$//' "$UNINSTALL" | grep -qF 'un_pairing_guard || exit 1'; then
    pass "uninstall.sh wires the guard right after the resolver (#413)"
else
    fail "uninstall.sh must call the guard after sourcing uninstall-core.sh (#413)"
fi
_pg_missing=""
for _fn in $(grep -oE '^[[:space:]]*(un_[a-z_0-9]+|prompt_yn)[[:space:]]*$' "$UNINSTALL" |
    awk '{gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' | sort -u); do
    printf '%s\n' "$_pg_src" | grep -qF "$_fn" || _pg_missing="$_pg_missing $_fn"
done
if [ -z "$_pg_missing" ]; then
    pass "pairing guard list covers every core call the entry makes (#413)"
else
    fail "core calls in uninstall.sh but absent from the guard:$_pg_missing (#413)"
fi

_unc_pi=$(sed 's/^[[:space:]]*#.*$//' "$LIB" | grep -c 'python3 -I' || true)
if [ "${_unc_pi:-0}" -ge 1 ]; then
    echo "  ${GREEN}PASS${NC}  tui unregister runs python3 -I ($_unc_pi found) (#249)"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  the tui unregister must run python3 -I (#249)"
    failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All uninstall-core tests passed.${NC}"
exit 0
