#!/bin/sh
# Unit tests for uninstall.sh (no root, no install needed):
#   - the run() wrapper echoes in dry-run mode instead of executing
#   - root / opencode invocations are refused
#   - project-path screening: system paths from projects.conf are never
#     passed to setfacl/chmod (protects against a tampered conf)
#   - the manual-cleanup hints match what install.sh actually leaves
#     behind (rc lines, deny-all config)
#
# Static extraction where possible; behavioural checks run the script
# with --dry-run against a fake sudo that only logs.
# Run: sh tests/unit/test-uninstall.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh"

failures=0
passed=0
pass() { echo "  ${GREEN}PASS${NC}  $1"; passed=$((passed + 1)); }
fail() { echo "  ${RED}FAIL${NC}  $1"; failures=$((failures + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT INT TERM

# Fake sudo: logs the command line, always succeeds. Keeps the test
# unprivileged while letting uninstall.sh build its full command list.
cat > "$WORK/sudo" <<'EOF'
#!/bin/sh
echo "sudo $*" >> "${FAKE_SUDO_LOG:?}"
exit 0
EOF
chmod +x "$WORK/sudo"

# Fake id: the userdel branch is only entered when the opencode user
# exists — true on a dev host with the kit installed, false on a CI
# runner. Pretend it always exists so the removal plan is complete (and
# the test hermetic) on every host. -u/-g also feed the ownership-revert
# capture (issue #74): uid 60000 must flow into the find; the gids stay
# DISTINCT per user (opencode 60002, dev 60001 — 0.0.42h C2) so
# full-script runs never reshape UN_OC_GID == UN_DEV_GID.
cat > "$WORK/id" <<'EOF'
#!/bin/sh
case "$1" in
    -u)  echo 60000 ;;
    -g)  case "$2" in opencode) echo 60002 ;; *) echo 60001 ;; esac ;;
    -gn) case "$2" in opencode) echo opencodegroup ;; *) echo devgroup ;; esac ;;
    *)   exit 0 ;;
esac
EOF
chmod +x "$WORK/id"

# --- 1. guards: refuses root / opencode --------------------------------------

run_uninstall_as() {
    _user="$1"; shift
    # whoami is hardcoded via a PATH shim; the script reads no other
    # user context before the guard.
    printf '#!/bin/sh\necho %s\n' "$_user" > "$WORK/whoami"
    chmod +x "$WORK/whoami"
    PATH="$WORK:$PATH" FAKE_SUDO_LOG="$WORK/log" sh "$UNINSTALL" --yes "$@" >/dev/null 2>&1
}

if run_uninstall_as root; then
    fail "refuses to run as root"
else
    pass "refuses to run as root"
fi
if run_uninstall_as opencode; then
    fail "refuses to run as the opencode user"
else
    pass "refuses to run as the opencode user"
fi

# --- 2. dry-run executes nothing ----------------------------------------------

printf '#!/bin/sh\necho devuser\n' > "$WORK/whoami"; chmod +x "$WORK/whoami"
rm -f "${WORK:?}/log"
if PATH="$WORK:$PATH" FAKE_SUDO_LOG="$WORK/log" sh "$UNINSTALL" --yes --dry-run >/dev/null 2>&1 \
   && [ ! -e "$WORK/log" ]; then
    pass "--dry-run executes no sudo command (log stayed empty)"
else
    # The credential probe (sudo -n true) is expected and harmless; so are
    # the agents-backup probes (0.0.45c C6 + 0.0.45d W2: sudo ls -A and
    # sudo test -d — read-only, the gate must fail safe in dry-run too),
    # the issue #164 openchamber presence/content probes (sudo test -f +
    # sudo grep -q — read-only, and deliberately OUTSIDE run() so they
    # see the file at the rm's authority), and the #198 a W1 legacy
    # sudoers probes (sudo test -L + sudo readlink — same read-only
    # gate-at-the-write's-authority class); any OTHER sudo command in
    # dry-run mode is a bug.
    _destructive="$(grep -vE '^sudo -n true( |$)|^sudo ls -A /home/[^ ]*/\.(agents|claude)$|^sudo test -d /home/[^ ]*/\.(agents|claude)$|^sudo test -f /etc/openchamber/policy\.json$|^sudo grep -q .* /etc/openchamber/policy\.json$|^sudo test -L /etc/sudoers\.d/opencode$|^sudo readlink /etc/sudoers\.d/opencode$' "$WORK/log" 2>/dev/null || true)"
    if [ -z "$_destructive" ]; then
        pass "--dry-run executes no destructive sudo command (only read-only probes)"
    else
        fail "--dry-run executed commands: $_destructive"
    fi
fi

# Issue #164 behavioral: uninstall.sh runs as the developer (root is
# refused above), so the openchamber gate MUST probe through sudo — an
# admin 0700 /etc/openchamber would otherwise hide a kit pin from
# removal. The fake sudo logs the probe in the real call sequence.
if grep -q '^sudo test -f /etc/openchamber/policy\.json$' "$WORK/log" 2>/dev/null \
    && grep -q '^sudo grep -q .* /etc/openchamber/policy\.json$' "$WORK/log" 2>/dev/null; then
    pass "openchamber gate probes via sudo in the real call sequence (issue #164)"
else
    fail "openchamber gate must probe via sudo, not at developer authority (issue #164)"
fi

# #198 a W1 behavioral: the legacy sudoers gate must probe at the rm's
# authority too — /etc/sudoers.d is 0750 on hardened hosts, and a
# developer-blind dir would hide an ACTIVE kit grant from removal. The
# fake sudo exits 0, so both the -L probe and the readlink fire in the
# real call sequence (a plain [ -L ] re-plant drops them from the log).
if grep -q '^sudo test -L /etc/sudoers\.d/opencode$' "$WORK/log" 2>/dev/null \
    && grep -q '^sudo readlink /etc/sudoers\.d/opencode$' "$WORK/log" 2>/dev/null; then
    pass "legacy sudoers gate probes via sudo in the real call sequence (#198 a W1)"
else
    fail "legacy sudoers gate must probe via sudo, not at developer authority (#198 a W1)"
fi

# --- 3. dry-run plans the removals --------------------------------------------

PLAN="$(PATH="$WORK:$PATH" FAKE_SUDO_LOG="$WORK/log" sh "$UNINSTALL" --yes --dry-run 2>/dev/null || true)"
for want in \
    "/etc/sudoers.d/opencode-permissions-kit" \
    "/usr/local/bin/opencode" \
    "/usr/local/bin/opk" \
    "/usr/local/lib/opencode-permissions-kit" \
    "/etc/profile.d/opencode-permissions-kit-umask.sh" \
    "/etc/opencode-permissions-kit"; do
    if printf '%s' "$PLAN" | grep -qF -- "$want"; then
        pass "dry-run plans removal of $want"
    else
        fail "dry-run plans removal of $want"
    fi
done
if printf '%s' "$PLAN" | grep -qF 'userdel -r'; then
    pass "dry-run plans user removal (userdel -r)"
else
    fail "dry-run plans user removal (userdel -r)"
fi

# --- 3b. legacy pre-0.0.10 artifacts (0.0.43a F5) --------------------------------
# Kits before v0.0.10 wrote /etc/sudoers.d/opencode -> /etc/opencode/sudoers,
# /etc/profile.d/opencode-umask.sh and /usr/local/lib/opencode (with the
# root-runnable protect-projects.sh + its /usr/local/sbin symlink). `opk
# update` refuses pre-0.0.14, so this cohort never migrated names — the
# uninstall must take the legacy names down with the current ones.
if printf '%s' "$PLAN" | grep -qF -- "/etc/profile.d/opencode-umask.sh"; then
    pass "dry-run plans removal of the legacy umask profile"
else
    fail "dry-run plans removal of the legacy umask profile"
fi
# The gated legacy removals (sudoers symlink, /etc/opencode conf files,
# legacy lib dir, sbin helper symlink) branch on the REAL /etc state and
# cannot be staged hermetically — their names and marker gates are pinned
# statically here (the behavior ships via the e2e suites).
for _pin in \
    'sudo test -L /etc/sudoers.d/opencode' \
    '/etc/sudoers.d/opencode' \
    'case "$_un_leg_link" in' \
    '/etc/opencode/*)' \
    'for _un_leg in sudoers install.conf projects.conf setup.conf' \
    '/usr/local/lib/opencode/wrapper' \
    '/usr/local/lib/opencode/protect-projects.sh' \
    'case "$_un_pp_link" in'; do
    if grep -qF -- "$_pin" "$UNINSTALL"; then
        pass "legacy removal pinned: $_pin"
    else
        fail "legacy removal pinned: $_pin"
    fi
done
# The generic legacy names must stay MARKER-GATED, never blanket-removed:
# anything else living at /etc/sudoers.d/opencode or /usr/local/lib/opencode
# is not kit-owned.
if grep -qF 'not kit-owned — left untouched' "$UNINSTALL" \
   && ! grep -Eq 'rm -rf /etc/opencode($|[^-])' "$UNINSTALL"; then
    pass "legacy names are marker-gated (foreign content survives)"
else
    fail "legacy names are marker-gated (foreign content survives)"
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
# loop driver below (malformed-roots arm).
SCREEN_PATTERNS="$(awk '
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
' "$UNINSTALL" | sed -e 's/|$//')"
if [ -n "$SCREEN_PATTERNS" ]; then
    pass "screening patterns extractable from uninstall.sh"
else
    fail "screening patterns extractable from uninstall.sh"
fi

# screen <path>: 0 = screened (system path, skipped), 1 = allowed.
# eval is required: `|` alternation in case patterns is parsed at parse
# time, NOT re-parsed from a variable expansion — a literal $SCREEN_PATTERNS
# would be one big never-matching pattern.
screen() {
    eval "case \"\$1\" in
        $SCREEN_PATTERNS) return 0 ;;
        *) return 1 ;;
    esac"
}

for syspath in / /etc /etc/nginx /usr /usr/share /bin /boot /root /root/x /proc /sys /dev /run /run/x /lib64; do
    if screen "$syspath"; then
        pass "screening rejects $syspath"
    else
        fail "screening rejects $syspath"
    fi
done
# Writer-parity arms (#243 b X1): config.sh project_path_sane refuses
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
if printf '%s' "$SCREEN_PATTERNS" | grep -q '/var/www'; then
    fail "screening patterns must not contain /var/www (legit project area)"
else
    pass "screening patterns must not contain /var/www (legit project area)"
fi
# Pinned divergence (#243 b X1): the scratch prefixes stay processable
# by design — the sandbox policy pins unit-fixture roots under /tmp and
# /var/tmp (this suite's own primary root lives there), and a
# temp-prefix conf entry is bounded (uid/gid-matched chown + kit-gid
# ACL strip only). The writer refuses them for storage; the uninstaller
# deliberately does not screen them.
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
CONFIG_SH="$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/config.sh"
WRITER_PATTERNS="$(sed -n '/^project_path_sane()/,/^}/p' "$CONFIG_SH" \
    | grep -E '^[[:space:]]*/' | grep -vE '^[[:space:]]*/\*\)' \
    | sed -e 's/\\$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/)$//' | tr '\n' '|')"
_un_parity_tokens() {
    printf '%s\n' "$1" | tr '|' '\n' | sed -e 's/[[:space:]]*$//' -e '/^$/d' | sort -u
}
READER_SET=$(_un_parity_tokens "$SCREEN_PATTERNS")
WRITER_SET=$(_un_parity_tokens "$WRITER_PATTERNS" | grep -vxF -e '/tmp' -e '/tmp/*' -e '/var/tmp' -e '/var/tmp/*')
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
# logging run() stub; the captured uid 60000 and the DISTINCT gids
# (oc 60002 / dev 60001) must land inside the find and the ACL removal,
# with chown to DEFAULT_USER:<dev-group>. The loop
# is extracted verbatim except for its stdin redirect (the conf path is
# hardcoded) — the fake roots are piped in instead.
PROJECT_LOOP="$(sed -n '/while IFS= read -r root; do/,/done < /p' "$UNINSTALL" | sed 's|done < "$UNINSTALL_PROJECTS_CONF"|done|')"
if [ -n "$PROJECT_LOOP" ] && printf '%s' "$PROJECT_LOOP" | grep -q 'find'; then
    pass "project loop with ownership revert extractable from uninstall.sh"
else
    fail "project loop with ownership revert extractable from uninstall.sh"
fi
# The rc-observing runner (#218) is extracted and driven REAL — the
# loop's ops go through it, so the honesty pins below exercise the
# shipped wiring, not a stub that fakes rc propagation.
UN_RC_Q="$(sed -n '/^un_rc_q() {/,/^}$/p' "$UNINSTALL")"
if [ -n "$UN_RC_Q" ] && printf '%s' "$UN_RC_Q" | grep -q 'failed'; then
    pass "rc-observing revert runner extractable (#218)"
else
    fail "rc-observing revert runner extractable (#218)"
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
#               a X2)
_un_loop_out() {
    _unlo_fail="$1"; _unlo_dry="$2"; _unlo_uid="$3"; _unlo_ocg="$4"; _unlo_dg="$5"
    _unlo_extra="${6:-}"
    : > "$WORK/unloop-sudo.log"
    : > "$WORK/unloop-out.log"
    : > "$WORK/unloop-err.log"
    _unlo_fixture="$WORK/fakeproj"
    for _unlo_x in $_unlo_extra; do
        _unlo_fixture="$_unlo_fixture
$_unlo_x"
    done
    printf '%s\n/etc\n' "$_unlo_fixture" | (
        DRY_RUN="$_unlo_dry"
        _un_partial=""
        _un_revert_failed=0
        UN_OC_UID="$_unlo_uid"
        UN_OC_GID="$_unlo_ocg"
        UN_DEV_GROUP=devgroup
        UN_DEV_GID="$_unlo_dg"
        DEFAULT_USER=devuser
        eval "$UN_RC_Q"
        # Logs to a FILE: the real runner silences its command's stdout
        # and stderr (the shipped behavior), so an echoing stub would
        # be swallowed with them.
        sudo() {
            printf 'sudo %s\n' "$*" >> "$WORK/unloop-sudo.log"
            case " $_unlo_fail " in
                *" $1 "*)
                    # Primary root only, boundary-matched: every op
                    # carries the root as an operand (find/setfacl end
                    # or precede a space, chmod ends it) — fakeproj2
                    # must not match (#243 a S3).
                    case "$*" in
                        *"$WORK/fakeproj "*|*"$WORK/fakeproj") return 1 ;;
                    esac
                    ;;
            esac
            return 0
        }
        log() { echo "log: $*"; }
        eval "$PROJECT_LOOP"
    ) > "$WORK/unloop-out.log" 2> "$WORK/unloop-err.log"
    echo "--- stdout ---"
    cat "$WORK/unloop-out.log"
    echo "--- stderr ---"
    cat "$WORK/unloop-err.log"
    echo "--- sudo log ---"
    cat "$WORK/unloop-sudo.log"
}
LOOP_OUT=$(mkdir -p "$WORK/fakeproj" && _un_loop_out "" false 60000 60002 60001 || true)
if printf '%s' "$LOOP_OUT" | grep -qF "find $WORK/fakeproj" \
   && ! printf '%s' "$LOOP_OUT" | grep -qF ' -xdev ' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '-uid 60000' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '-gid 60002' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '-exec chown devuser:devgroup {} +' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- '! -type l'; then
    pass "ownership revert: uid/gid-matched chown to the developer per root (issue #74)"
else
    fail "ownership revert loop (out=$(printf '%s' "$LOOP_OUT" | head -5))"
fi
# ! -type l (0.0.42e S1): chown follows a symlink operand — without the
# exclusion, an opencode-planted link inside a project makes the root-run
# revert chown an arbitrary file OUTSIDE the project to the developer.
if printf '%s' "$LOOP_OUT" | grep -qF -- '! -type l'; then
    pass "ownership revert: symlinks excluded from the chown find (0.0.42e S1)"
else
    fail "ownership revert: chown find must exclude symlinks (0.0.42e S1)"
fi
# -xdev would stop at mount boundaries — project roots are regularly
# separate mounts (bind mounts, NFS): the revert must follow, like the
# setfacl -R calls in the same loop (checked above via the -xdev grep).
if printf '%s' "$LOOP_OUT" | grep -qF "find \"/etc\""; then
    fail "ownership revert: system paths are never chowned (screened)"
else
    pass "ownership revert: system paths are never chowned (screened)"
fi

# The uid/gid capture must happen BEFORE the user removal: after userdel
# the name no longer resolves and only the numeric ids can still match
# the orphaned files.
CAPTURE_LINE=$(grep -n 'UN_OC_UID=' "$UNINSTALL" | head -1 | cut -d: -f1)
USERDEL_LINE=$(grep -n 'sudo userdel -r' "$UNINSTALL" | head -1 | cut -d: -f1)
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
if grep -qF 'sudo ls -A "$_un_ag_src"' "$UNINSTALL" \
   && grep -qF '_un_ag_ls="probe-failed"' "$UNINSTALL"; then
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
if grep -qF 'if sudo test -d "$_un_ag_src"; then' "$UNINSTALL" \
   && ! grep -qF 'if [ -d "$_un_ag_src" ]; then' "$UNINSTALL"; then
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
_un_w2="$(mktemp -d)"
mkdir -p "$_un_w2/fake-home/opencodeux/.agents" "$_un_w2/fake-home/opencodeux2" "$_un_w2/backups"
echo skills > "$_un_w2/fake-home/opencodeux/.agents/agents.md"
printf '#!/bin/sh\necho "sudo $*" >> "%s/log"\nexec "$@"\n' "$_un_w2" > "$_un_w2/sudo"
chmod +x "$_un_w2/sudo"
_un_w2_gate() {
    {
        printf 'DRY_RUN=false\nlog() { :; }\nDEFAULT_USER=%s\nOPENCODE_USER=%s\nPATH="%s:$PATH"\n' \
            "$2" "$1" "$_un_w2"
        sed -n '/^        for _un_ag_dirname in \.agents \.claude; do$/,/^        done$/p' "$UNINSTALL" \
            | sed -e "s#/home/#$_un_w2/fake-home/#g" -e "s#/var/backups/opencode-permissions-kit#$_un_w2/backups#"
    } > "$_un_w2/run.sh"
    : > "$_un_w2/log"
    sh "$_un_w2/run.sh" >/dev/null 2>&1 || true
    cat "$_un_w2/log" 2>/dev/null || true
}
chmod 000 "$_un_w2/fake-home/opencodeux2"
_un_w2_log="$(_un_w2_gate opencodeux2 devuser)"
if printf '%s\n' "$_un_w2_log" | grep -q '^sudo test -d '; then
    pass "agents-backup gate: privileged existence probe issued despite unreadable home (W2)"
else
    fail "agents-backup gate: no privileged probe against the unreadable home (W2 log: $_un_w2_log)"
fi
_un_w2_log="$(_un_w2_gate opencodeux devuser)"
if printf '%s\n' "$_un_w2_log" | grep -q '^sudo test -d .*agents$' \
   && printf '%s\n' "$_un_w2_log" | grep -q '^sudo ls -A .*agents$' \
   && printf '%s\n' "$_un_w2_log" | grep -q '^sudo mkdir -p .*agents-backup-' \
   && printf '%s\n' "$_un_w2_log" | grep -q '^sudo cp -a .*agents'; then
    pass "agents-backup gate: readable .agents arms the backup branch (W2)"
else
    fail "agents-backup gate: readable .agents must issue test-d/ls-A/mkdir/cp (W2 log: $_un_w2_log)"
fi
_un_w2_log="$(_un_w2_gate opencodeux-missing devuser)"
if ! printf '%s\n' "$_un_w2_log" | grep -q 'mkdir -p' \
   && ! printf '%s\n' "$_un_w2_log" | grep -q 'cp -a'; then
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
if printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -x g:60002' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -d -x g:60002' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -x g:60001' \
   && printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -d -x g:60001' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF 'unknown' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -b' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF -- 'setfacl -R -k'; then
    pass "ACL revert: both kit principals removed via numeric gids, no skip hints (0.0.42g S1 + 0.0.42i Q3)"
else
    fail "ACL revert must remove BOTH principals (opencode group + dev group) via numeric gids (0.0.42g S1)"
fi
if grep -qF 'UN_DEV_GID=$(id -g "$DEFAULT_USER"' "$UNINSTALL" \
   && grep -qF 'for _un_acl_pair in "opencode group:$UN_OC_GID" "dev group:$UN_DEV_GID"' "$UNINSTALL" \
   && grep -qF 'project revert PARTIALLY completed' "$UNINSTALL" \
   && grep -qF 'id unknown — its ACL entries left in place' "$UNINSTALL"; then
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
    # Red-arm diagnostics (#243 a Q4, families completed #243 b Q1):
    # surface the line families the arms actually assert — log:/WARN:
    # records, PARTIALLY degradation, Removed. closings, [DRY] echoes,
    # skip echoes in both spellings (Skipping gate / skipped/unknown
    # id notes), and sudo-log lines. The old tail -N showed only the
    # appended sudo-call log, never the lines an arm checks.
    printf '%s' "$1" \
        | grep -E 'log:|WARN:|PARTIALLY|Removed\.|\[DRY\]|Skipping|skipped|unknown|^sudo ' \
        | tail -6
}
if printf '%s' "$LOOP_OUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj" \
   && ! printf '%s' "$LOOP_OUT" | grep -qF 'PARTIALLY' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF 'WARN:' \
   && ! printf '%s' "$LOOP_OUT" | grep -qF 'revert FAILED'; then
    pass "revert all ok: full-success closing log, no partial/WARN noise (#218)"
else
    fail "revert all ok: full-success closing log required (out=$(_unarm_show "$LOOP_OUT")) (#218)"
fi
FOUT=$(_un_loop_out "find" false 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF "log: project revert PARTIALLY completed (find-chown failed): $WORK/fakeproj" \
   && printf '%s' "$FOUT" | grep -qF "WARN: could not fully revert $WORK/fakeproj (find-chown failed)" \
   && printf '%s' "$FOUT" | grep -qF "log: project revert FAILED for: $WORK/fakeproj (find-chown failed)" \
   && printf '%s' "$FOUT" | sed -n '/^--- stderr ---$/,/^--- sudo log ---$/p' | grep -qF 'WARN: could not fully revert' \
   && ! printf '%s' "$FOUT" | sed -n '1,/^--- stderr ---$/p' | grep -qF 'WARN:' \
   && ! printf '%s' "$FOUT" | grep -qF 'ownership reverted' \
   && ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "find-chown failure: degraded closing names the failed op, WARN stays on stderr, no false completion (#218, #243 a X1/Q3)"
else
    fail "find-chown failure arms (out=$(_unarm_show "$FOUT")) (#218, #243 a X1/Q3)"
fi
FOUT=$(_un_loop_out "setfacl" false 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF 'setfacl -x g:60002 failed' \
   && printf '%s' "$FOUT" | grep -qF 'setfacl -d -x g:60001 failed' \
   && ! printf '%s' "$FOUT" | grep -qF 'find-chown failed' \
   && ! printf '%s' "$FOUT" | grep -qF 'chmod g-s failed' \
   && ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "setfacl failure: both principals' ops named, other ops not (#218)"
else
    fail "setfacl failure arms — names must discriminate (out=$(_unarm_show "$FOUT")) (#218)"
fi
FOUT=$(_un_loop_out "chmod" false 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF 'PARTIALLY completed (chmod g-s failed)' \
   && printf '%s' "$FOUT" | grep -qF 'WARN: could not fully revert' \
   && ! printf '%s' "$FOUT" | grep -qF 'find-chown failed' \
   && ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
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
if printf '%s' "$FOUT" | grep -qF 'PARTIALLY completed (opencode user unknown (chown skipped), opencode group id unknown)' \
   && printf '%s' "$FOUT" | grep -qF 'opencode group id unknown — its ACL entries left in place' \
   && printf '%s' "$FOUT" | grep -qF 'remove manually: setfacl -R -x g:<gid> -d -x g:<gid>' \
   && printf '%s' "$FOUT" | grep -qF -- 'setfacl -R -x g:60001' \
   && ! printf '%s' "$FOUT" | grep -qF 'WARN:' \
   && ! printf '%s' "$FOUT" | grep -qF 'revert FAILED' \
   && ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "opencode gid unknown: loud skip + template hint + degraded closing, no failure WARN (#218, #243 a Q1)"
else
    fail "opencode gid unknown arms (out=$(_unarm_show "$FOUT")) (#218, #243 a Q1)"
fi
# Unknown uid: chown skipped loudly, ACL ops still run, degraded
# closing names the skip — same not-attempted-is-not-failed rule.
FOUT=$(_un_loop_out "" false "" 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF 'PARTIALLY completed (opencode user unknown (chown skipped))' \
   && printf '%s' "$FOUT" | grep -qF 'chown manually if files are locked' \
   && printf '%s' "$FOUT" | grep -qF -- 'setfacl -R -x g:60002' \
   && ! printf '%s' "$FOUT" | grep -qF 'WARN:' \
   && ! printf '%s' "$FOUT" | grep -qF 'kit ACL entries removed:'; then
    pass "uid unknown: chown skip lands in degraded closing, ACL ops still run (#218)"
else
    fail "uid unknown arms (out=$(_unarm_show "$FOUT")) (#218)"
fi
# Dry run: [DRY] echoes and the success lines despite failing ops —
# the run/run_q convention since #211 b W1 (dry reports the intended
# outcome; nothing executes, so nothing can fail). Nothing executes =
# the sudo log stays EMPTY — pinned (#243 a Q5): a refactor that
# executes in dry mode while dropping rc observation would otherwise
# stay green.
FOUT=$(_un_loop_out "find setfacl chmod" true 60000 60002 60001) || true
if printf '%s' "$FOUT" | grep -qF '[DRY] sudo find' \
   && printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj" \
   && ! printf '%s' "$FOUT" | grep -qF 'PARTIALLY' \
   && ! printf '%s' "$FOUT" | grep -qF 'WARN:' \
   && ! printf '%s' "$FOUT" | sed -n '/^--- sudo log ---$/,$p' | grep -q '^sudo '; then
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
if printf '%s' "$FOUT" | grep -qF "log: project revert PARTIALLY completed (find-chown failed): $WORK/fakeproj" \
   && printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj2" \
   && ! printf '%s' "$FOUT" | grep -qF "PARTIALLY completed (find-chown failed): $WORK/fakeproj2" \
   && printf '%s' "$FOUT" | grep -qF "sudo chmod g-s $WORK/fakeproj2"; then
    pass "two roots: root 1 degraded, root 2 closes clean — reset is per-root (#243 a S3)"
else
    fail "two-roots isolation arms (out=$(_unarm_show "$FOUT")) (#243 a S3)"
fi
# Malformed root forms never reach the root-run ops (#243 a X2): the
# reader-side gate mirrors the writer's project_path_sane arms —
# `//etc` (empty segment, bypasses the system-path blocklist
# lexically), `/var/.` (dot segment) and `.` (relative) are skipped
# loudly; the primary root is still processed normally.
FOUT=$(_un_loop_out "" false 60000 60002 60001 "//etc /var/. .") || true
if printf '%s' "$FOUT" | grep -qF 'Skipping malformed project path (dot or empty segment): //etc' \
   && printf '%s' "$FOUT" | grep -qF 'Skipping malformed project path (dot or empty segment): /var/.' \
   && printf '%s' "$FOUT" | grep -qF 'Skipping non-absolute project path: .' \
   && ! printf '%s' "$FOUT" | grep -qF 'sudo find //etc' \
   && printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj"; then
    pass "malformed roots (//etc, /var/., .) skipped loudly, no root ops on them (#243 a X2)"
else
    fail "malformed-root screening arms (out=$(_unarm_show "$FOUT")) (#243 a X2)"
fi
# System-path blocklist, behaviorally (#243 b X1): extra roots the
# writer refuses must be screened loudly and no root op may touch
# them, while the primary root — under the sanctioned /tmp scratch —
# still processes (the pinned divergence). Only host-existent dirs
# feed the driver: [ ! -d ] runs BEFORE the blocklist and would skip
# a nonexistent path silently, defanging the arm.
FOUT=$(_un_loop_out "" false 60000 60002 60001 "/var /home /opt /srv /media /mnt") || true
if printf '%s' "$FOUT" | grep -qF 'Skipping system path: /var' \
   && printf '%s' "$FOUT" | grep -qF 'Skipping system path: /home' \
   && printf '%s' "$FOUT" | grep -qF 'Skipping system path: /opt' \
   && printf '%s' "$FOUT" | grep -qF 'Skipping system path: /srv' \
   && printf '%s' "$FOUT" | grep -qF 'Skipping system path: /media' \
   && printf '%s' "$FOUT" | grep -qF 'Skipping system path: /mnt' \
   && ! printf '%s' "$FOUT" | grep -qF 'sudo find /var' \
   && ! printf '%s' "$FOUT" | grep -qF 'sudo find /home' \
   && ! printf '%s' "$FOUT" | grep -qF 'sudo chmod g-s /srv' \
   && ! printf '%s' "$FOUT" | grep -qF 'sudo setfacl -R -x g:60002 /mnt' \
   && printf '%s' "$FOUT" | grep -qF "log: project ownership reverted + kit ACL entries removed: $WORK/fakeproj"; then
    pass "system-path roots (/var /home /opt /srv /media /mnt) screened, no root ops, primary root processes (#243 b X1)"
else
    fail "system-path blocklist arms (out=$(_unarm_show "$FOUT")) (#243 b X1)"
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
CFG_SECTION="$(sed -n '/^echo "--- Removing kit config directories/,/^echo ""$/p' "$UNINSTALL")"
if [ -n "$CFG_SECTION" ] \
   && printf '%s' "$CFG_SECTION" | grep -qF 'un_rc_q "rm /etc/opencode-permissions-kit"' \
   && printf '%s' "$CFG_SECTION" | grep -qF 'openchamber policy pin removal FAILED'; then
    pass "config-dirs section extractable + rc-observing (#243 a S1/S2)"
else
    fail "config-dirs section extraction/rc observation (#243 a S1/S2)"
fi
_un_cfg_out() {
    _unc_fail="$1"; _unc_dry="$2"
    : > "$WORK/uncfg-sudo.log"
    : > "$WORK/uncfg-out.log"
    : > "$WORK/uncfg-err.log"
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
        eval "$UN_RC_Q"
        sudo() {
            printf 'sudo %s\n' "$*" >> "$WORK/uncfg-sudo.log"
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
        eval "$CFG_SECTION"
    ) > "$WORK/uncfg-out.log" 2> "$WORK/uncfg-err.log"
    echo "--- stdout ---"
    cat "$WORK/uncfg-out.log"
    echo "--- stderr ---"
    cat "$WORK/uncfg-err.log"
    echo "--- sudo log ---"
    cat "$WORK/uncfg-sudo.log"
}
COUT=$(_un_cfg_out "" false) || true
if printf '%s' "$COUT" | grep -qF 'Removed.' \
   && printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts removed (/etc/opencode-permissions-kit, /run/opencode-permissions-kit, 99-ddev-rootless.conf)' \
   && printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removed (kit-owned content only)' \
   && ! printf '%s' "$COUT" | grep -qF 'WARN:' \
   && ! printf '%s' "$COUT" | grep -qF 'PARTIALLY' \
   && ! printf '%s' "$COUT" | grep -qF 'stale from the project loop'; then
    pass "config-dirs all ok: Removed. + success logs, stale pre-state cleared, no partial/WARN noise (#243 a S1/S2, b S2)"
else
    fail "config-dirs all-ok arms (out=$(_unarm_show "$COUT")) (#243 a S1/S2, b S2)"
fi
# Openchamber pin rm fails (S2): its success log must NOT fire; the
# failure WARNs on stderr (channel pinned) and lands in the section's
# partial list, degrading the section closing.
COUT=$(_un_cfg_out "rm:/etc/openchamber/policy.json" false) || true
if printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removal FAILED (rm)' \
   && printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts PARTIALLY removed (openchamber policy pin rm failed)' \
   && printf '%s' "$COUT" | sed -n '/^--- stderr ---$/,/^--- sudo log ---$/p' | grep -qF 'WARN: could not remove the openchamber policy pin (rm failed)' \
   && printf '%s' "$COUT" | sed -n '/^--- stderr ---$/,/^--- sudo log ---$/p' | grep -qF 'WARN: could not fully remove config dirs + runtime artifacts (openchamber policy pin rm failed)' \
   && ! printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removed' \
   && ! printf '%s' "$COUT" | grep -qF 'artifacts removed ('; then
    pass "openchamber rm failure: FAILED log + both WARNs on stderr, section closing degrades (#243 a S2, b Q2)"
else
    fail "openchamber rm failure arms (out=$(_unarm_show "$COUT")) (#243 a S2, b Q2)"
fi
# Two section rms fail (S1): both named in the degraded closing, in
# section order; the surviving openchamber pin still logs its success.
COUT=$(_un_cfg_out "rm:99-ddev-rootless.conf rm:/etc/opencode-permissions-kit" false) || true
if printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts PARTIALLY removed (rm 99-ddev-rootless.conf failed, rm /etc/opencode-permissions-kit failed)' \
   && printf '%s' "$COUT" | grep -qF 'WARN: could not fully remove config dirs + runtime artifacts' \
   && printf '%s' "$COUT" | grep -qF 'log: openchamber policy pin removed (kit-owned content only)' \
   && ! printf '%s' "$COUT" | grep -qF 'Removed.'; then
    pass "section rm failures: both named in degraded closing + WARN, no false Removed. (#243 a S1)"
else
    fail "section rm failure arms (out=$(_unarm_show "$COUT")) (#243 a S1)"
fi
# Dry run: [DRY] echoes and the success lines despite the failing
# stub — the run/run_q convention (#211 b W1). The guard probes
# (test/grep) legitimately execute as reads; no rm ever runs.
COUT=$(_un_cfg_out "rm:/etc/opencode-permissions-kit" true) || true
if printf '%s' "$COUT" | grep -qF '[DRY] sudo rm -rf /run/opencode-permissions-kit' \
   && printf '%s' "$COUT" | grep -qF '[DRY] sudo rm -f /etc/openchamber/policy.json' \
   && printf '%s' "$COUT" | grep -qF 'Removed.' \
   && printf '%s' "$COUT" | grep -qF 'log: config dirs + runtime artifacts removed' \
   && ! printf '%s' "$COUT" | grep -qF 'PARTIALLY'; then
    pass "config-dirs dry: [DRY] echoes + success lines, no partial noise (#243 a S1)"
else
    fail "config-dirs dry arms (out=$(_unarm_show "$COUT")) (#243 a S1)"
fi

# --- 5. cleanup hints match what install.sh leaves behind ----------------------

if grep -qF "still contain" "$UNINSTALL" && grep -qF 'opencode permissions kit' "$UNINSTALL"; then
    pass "manual-cleanup section mentions the rc lines"
else
    fail "manual-cleanup section mentions the rc lines"
fi
if grep -qF '.config/opencode/opencode.jsonc' "$UNINSTALL"; then
    pass "manual-cleanup section mentions the default-user config"
else
    fail "manual-cleanup section mentions the default-user config"
fi
# The backup path hint must match install.sh's mktemp shape
if grep -qF '/tmp/opencode-install-backup' "$UNINSTALL" \
   && ! grep -qF 'opencode-install-backup-<timestamp>' "$UNINSTALL"; then
    pass "backup hint matches the mktemp path shape"
else
    fail "backup hint matches the mktemp path shape"
fi
# Session hint (issue #73): the running shell keeps the ddev function
# (helper deleted), PATH/umask and group membership — the uninstall must
# tell the user to restart the terminal.
if grep -q 'Restart your terminal' "$UNINSTALL"; then
    pass "final output tells the user to restart the terminal (issue #73)"
else
    fail "final output tells the user to restart the terminal (issue #73)"
fi

# Unknown options are rejected loudly (0.0.44a V7): `--dryrun --yes`
# (typo) used to silently drop --dryrun and run a REAL unprompted
# uninstall — the arg loop now dies on unknowns like every sibling.
u7_rc=0
u7_out=$(PATH="$WORK:$PATH" sh "$UNINSTALL" --dryrun --yes 2>&1 >/dev/null) || u7_rc=$?
if [ "$u7_rc" -eq 1 ] && printf '%s' "$u7_out" | grep -q 'unknown option: --dryrun'; then
    pass "unknown option aborts before anything runs (V7)"
else
    fail "unknown option aborts before anything runs (V7, rc=$u7_rc out=$u7_out)"
fi

# uninstall side of the conf-user homes (0.0.44b W16)
grep -q '"/home/$OPENCODE_USER/.config/opencode"' "$UNINSTALL" \
    && pass "uninstall plugin-unregister rides the conf user (V16)" \
    || fail "uninstall plugin-unregister rides the conf user (V16)"

# OpenChamber policy pin removal (issue #154, Tier 2): kit-owned content
# only — the policy.json goes when (and only when) it pins OUR wrapper;
# any other content is admin-owned and must survive the uninstall.
# Issue #164: presence + content run at the rm's authority (sudo) — the
# script runs as the developer, an admin 0700 /etc/openchamber must not
# hide a kit pin from removal.
if grep -q 'grep -q .\"opencodeBinary\".*\"/usr/local/bin/opencode\"' "$UNINSTALL" \
    && grep -q 'rm -f /etc/openchamber/policy.json' "$UNINSTALL" \
    && grep -q 'rmdir /etc/openchamber' "$UNINSTALL" \
    && grep -qF 'sudo test -f /etc/openchamber/policy.json' "$UNINSTALL" \
    && grep -qF 'sudo grep -q ' "$UNINSTALL"; then
    pass "openchamber policy removed marker-gated (kit content only)"
else
    fail "openchamber policy removal lost its marker gate"
fi

# --- prompt_yn: answer semantics + shape (issue #187 A/B) -----------------------
# Extract-and-run under a real pty (script(1), like test-browser-bridge):
# prompt_yn hard-exits without a terminal (by design), so the setsid
# pattern of test-ui.sh cannot drive it. Unknown input must fall back
# to the DEFAULT — the 0.0.44a V17 sweep fixed ui.sh's ui_confirm but
# missed this standalone sibling; mixed-case answers are honored; the
# prompt renders the shared marker-less shape.
PROMPT_YN="$(sed -n '/^prompt_yn() {/,/^}/p' "$UNINSTALL")"
if [ -n "$PROMPT_YN" ] && printf '%s' "$PROMPT_YN" | grep -qF 'n|no)'; then
    pass "prompt_yn extractable from uninstall.sh (n|no arm present)"
else
    fail "prompt_yn extractable from uninstall.sh (n|no arm present)"
fi
printf '%s\n' "$PROMPT_YN" > "$WORK/prompt-yn.sh"
cat > "$WORK/py-driver.sh" <<'PYEOF'
#!/bin/sh
# $1 = default; prints prompt_yn's answer on stdout
RED='' NC='' YES=false
trace() { :; }
. "${PY_SRC:?}"
prompt_yn "Delete audit log too?" "${1:?}"
PYEOF
py_ask() { # <typed-line> <default> -> last pty line (prompt + answer)
    printf '%s\n' "$1" | PY_SRC="$WORK/prompt-yn.sh" \
        script -qec "sh '$WORK/py-driver.sh' '$2'" /dev/null 2>/dev/null \
        | tr -d '\r' | tail -1
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
if printf '%s' "$_pyline" | grep -qF '  Delete audit log too? [y/N] ' \
    && ! printf '%s' "$_pyline" | grep -qF '[?]'; then
    pass "prompt_yn shape: '  <question> [y/N] ' — no marker (issue #187 B)"
else
    fail "prompt_yn shape: '  <question> [y/N] ' — no marker (got: $_pyline)"
fi
# Static sweep: the removed marker must not creep back into the script.
if grep -qF '[?]' "$UNINSTALL"; then
    fail "uninstall.sh is free of the removed [?] marker"
else
    pass "uninstall.sh is free of the removed [?] marker"
fi

# --- developer home via getent (issue #192, V14 sibling) ---------------------------
# The plugin-cleanup loop must reach the REAL developer home: a root-shell
# install recorded root as the developer, and the hardcoded
# /home/$DEFAULT_USER dir never exists — the cleanup silently missed
# root's config dir. Shape pins (execution needs the tui-register gate).
# Negative sweep tightened (#196 a T1; braced spelling added by
# #196 b B2, survivor diagnostic by #196 b B7; survivor list completed
# by #196 c C1): flag every slash form of the literal
# /home/$DEFAULT_USER spelling, braced included — not just the
# trailing-slash form. Survivors allowed are comment lines, the
# getent-failure fallback (`|| var="/home/$DEFAULT_USER"`), and the
# braced self-default fallback (`var="${var:-/home/${DEFAULT_USER:-$USER}}"`
# — sanctioned shape, status.sh's openchamber home).
_un_bad="$(grep -e '/home/\$DEFAULT_USER' -e '/home/\${DEFAULT_USER' "$UNINSTALL" 2>/dev/null \
    | grep -v '^[[:space:]]*#' \
    | grep -v '|| [[:alnum:]_]\{1,\}="/home/\$DEFAULT_USER"$' \
    | grep -v '[[:alnum:]_]\{1,\}="\${[[:alnum:]_]\{1,\}:-/home/\${DEFAULT_USER:-\$USER}}"$' || true)"
if grep -qF '_un_dev_home="$(getent passwd "$DEFAULT_USER" 2>/dev/null | cut -d: -f6 || true)"' "$UNINSTALL" \
   && grep -qF '"$_un_dev_home/.config/opencode"' "$UNINSTALL" \
   && [ -z "$_un_bad" ]; then
    pass "uninstall.sh resolves the developer home via getent for the cleanup loop"
else
    fail "uninstall.sh resolves the developer home via getent for the cleanup loop (${_un_bad:-no getent})"
fi

echo ""
# --- F27: bridge removal honesty (#211 a F27) ---------------------------------------
# The silent noop stub + unconditional echo claimed a removal that never
# ran when the helper was missing. Extract the real consent block and
# drive both arms with a stubbed browser_bridge_remove + auto-yes prompt.
_f27_block="$(sed -n "/Remove the kit's wsl.conf bridge block/,/^        fi$/p" \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh")"
if [ -n "$_f27_block" ] && printf '%s' "$_f27_block" | grep -q 'browser_bridge_remove'; then
    pass "bridge removal block extractable (#211 a F27)"
    _f27_run() {
        (
            prompt_yn() { printf 'y'; }
            log() { echo "log: $*"; }
            # #211 b W14: the extract spans the declined-consent arm's
            # live `sudo rm -rf` — stub sudo so no future drive can
            # execute it for real on a kit-managed host.
            sudo() { echo "sudo: $*"; return 0; }
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
else
    fail "bridge removal block extractable (#211 a F27)"
fi

# --- F28: group removal exact + honest (#211 a F28) --------------------------------
# The membership probe was a substring grep (a group 'opencode2' matched
# 'opencode') and the success echo printed over a silenced gpasswd
# failure. Extract the real block; stub id/run_q/log; drive all arms.
_f28_block="$(sed -n '/^if id "\$DEFAULT_USER" >\/dev\/null 2>&1 \\/,/^fi$/p' \
    "$SCRIPT_DIR/../../files/opencode-permissions-kit-lib/management/uninstall.sh")"
if [ -n "$_f28_block" ]; then
    pass "group removal block extractable (#211 a F28)"
    _f28_run() {
        # $1 = groups-print, $2 = gpasswd rc — sudo stubbed (#211 b W1):
        # the block calls sudo directly now (run_q is rc-blind by design
        # and must not be faked into propagating), so the pin drives the
        # real shipped wiring at the real seam.
        (
            DEFAULT_USER=dev
            OPENCODE_GROUP=opencode
            DRY_RUN="${DRY_RUN:-false}"
            id() { printf '%s\n' "uid=1(dev) gid=1(dev) groups=1(dev),$F28GRPS"; return 0; }
            sudo() { return "$F28GP"; }
            log() { echo "log: $*"; }
            eval "$_f28_block"
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
            pass "dry run: [DRY] echo + success lines despite rc (#211 b W1)" ;;
        *) fail "dry run: [DRY] echo + success lines (got: $_out)" ;;
    esac
else
    fail "group removal block extractable (#211 a F28)"
fi

# --- W11: the no-markers bridge arm follows the helper's rc (#211 b W11) ----------
# The consent arm went honest in a F27; this sibling arm (no wsl.conf
# markers found — library wsl/ tree drop only) kept its unconditional
# success log. Wiring pin (F14's sites-2/3 precedent: the arm is the
# near-unreachable stub path): the call is if-wrapped and the FAILED
# log line exists.
if grep -q 'if browser_bridge_remove "/usr/local/lib/opencode-permissions-kit"; then' "$UNINSTALL" \
   && grep -q 'wsl browser bridge removal FAILED (helper unavailable, no wsl.conf content found)' "$UNINSTALL"; then
    pass "no-markers bridge arm conditions its log on the rc (#211 b W11)"
else
    fail "no-markers bridge arm conditions its log on the rc (#211 b W11)"
fi

# --- c W1: userdel + audit-log arms honest (#211 c W1) ------------------------------
# The b W1 sweep claim called the remaining run_q uses "bare best-effort
# cleanup" — userdel (the primary destructive op) and the audit-log rm
# both lied in the gpasswd shape: rc-blind call, unconditional success
# echo/log. Extract both real blocks; stub sudo (the REAL seam — run_q
# is rc-blind by design and must not be faked into propagating) and
# drive every arm.
_cw1_udel_block="$(sed -n '/^if id "\$OPENCODE_USER" >\/dev\/null 2>&1; then$/,/^fi$/p' "$UNINSTALL")"
if [ -n "$_cw1_udel_block" ]; then
    pass "user removal block extractable (#211 c W1)"
    _cw1_udel_run() {
        (
            OPENCODE_USER=oc
            DEFAULT_USER=dev
            DRY_RUN="${CW1DRY:-false}"
            id() { [ "$1" = "-u" ] && printf '900\n'; return 0; }
            prompt_yn() { printf 'y\n'; }
            sleep() { :; }
            sudo() { case "$1" in userdel) return "$CW1UDEL";; esac; return 0; }
            run_q() {
                if [ "$DRY_RUN" = true ]; then echo "  [DRY] $*"; else "$@" >/dev/null 2>&1 || true; fi
            }
            log() { echo "log: $*"; }
            eval "$_cw1_udel_block"
        )
    }
    _out=$(CW1UDEL=0 _cw1_udel_run) || true
    case "$_out" in
        *"User 'oc' removed."*"log: user removed: oc"*)
            pass "userdel ok: removal reported (#211 c W1)" ;;
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
            pass "userdel dry run: [DRY] echo + success lines despite rc (#211 c W1)" ;;
        *) fail "userdel dry run: [DRY] echo + success lines (got: $_out) (#211 c W1)" ;;
    esac
else
    fail "user removal block extractable (#211 c W1)"
fi
_cw1_al_block="$(sed -n '/^if \[ "\$(prompt_yn "Delete audit log too/,/^fi$/p' "$UNINSTALL")"
if [ -n "$_cw1_al_block" ]; then
    pass "audit-log block extractable (#211 c W1)"
    _cw1_al_run() {
        (
            DRY_RUN="${CW1DRY:-false}"
            prompt_yn() { printf 'y\n'; }
            sudo() { return "$CW1AL"; }
            log() { echo "log: $*"; }
            eval "$_cw1_al_block"
        )
    }
    _out=$(CW1AL=0 _cw1_al_run) || true
    case "$_out" in
        *"Audit log removed."*"log: audit log removed: /var/log/opencode-permissions-kit"*)
            pass "audit rm ok: removal reported after the act (#211 c W1)" ;;
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
            pass "audit rm dry run: [DRY] echo + success lines despite rc (#211 c W1)" ;;
        *) fail "audit rm dry run: [DRY] echo + success lines (got: $_out) (#211 c W1)" ;;
    esac
else
    fail "audit-log block extractable (#211 c W1)"
fi

# --- agents-backup failure arm names the failing commands (#211 f W2) ----------
_f2_bak_block="$(sed -n '/^        for _un_ag_dirname in \.agents \.claude; do$/,/^        done$/p' "$UNINSTALL")"
if [ -n "$_f2_bak_block" ]; then
    pass "agents-backup loop extractable (#211 f W2)"
    _f2_bak_run() {
        (
            OPENCODE_USER=oc
            DRY_RUN="${F2DRY:-false}"
            sudo() {
                case "$1" in
                    test) return 0 ;;
                    ls) echo "agent-resource"; return 0 ;;
                    mkdir|cp) return "${F2BAKRC:-1}" ;;
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
else
    fail "agents-backup loop extractable (#211 f W2)"
fi

if [ "$failures" -gt 0 ]; then
    echo "  ${RED}$failures test(s) failed.${NC}"
    exit 1
fi
echo "  ${GREEN}All uninstall tests passed.${NC}"
exit 0
