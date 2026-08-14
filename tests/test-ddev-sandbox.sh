#!/bin/sh
# Unit tests for the sandbox ddev mode (docs/design/DDEV-SANDBOX.md).
#
# Static structure + wiring checks (no Docker, no sudo, no npm):
#   (1) ddev-transaction.sh — validation, no-eval policy, OPEN/RUN/CLOSE
#       structure, stamp + trap handling, root-owned rewrite list.
#   (2) bin/ddev shim — mode switch, read-only fast path, root resolution,
#       transaction exec, delegated fallback.
#   (3) sudoers.template — mutually exclusive ddev blocks.
#   (4) install.sh / update.sh / config.sh / status.sh wiring — DDEV_MODE
#       write/render/deploy/report, provisioning, heal gate.
#   (5) CI chmod lists in BOTH workflow files.
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$SCRIPT_DIR/.."
TXN="$REPO/files/opencode-permissions-kit-lib/ddev-transaction.sh"
SHIM="$REPO/files/opencode-permissions-kit-lib/bin/ddev"
INSTALL="$REPO/files/install.sh"
UPDATE="$REPO/files/update.sh"
CONFIG="$REPO/files/config.sh"
STATUS="$REPO/files/status.sh"
PROTECT="$REPO/files/opencode-permissions-kit-lib/protect-projects.sh"
SUDOERS="$REPO/files/sudoers.template"
TEST_YML="$REPO/.github/workflows/test.yml"
E2E_YML="$REPO/.github/workflows/e2e.yml"

failures=0
passed=0

check() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        failures=$((failures + 1))
    fi
}

check_fail() {
    local desc="$1"
    shift
    if "$@"; then
        echo "  ${RED}FAIL${NC}  $desc (expected failure, got success)"
        failures=$((failures + 1))
    else
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    fi
}

echo ""
echo "ddev Sandbox Mode Tests"
echo "======================="
echo ""

echo "-- ddev-transaction.sh structure --"
check "transaction helper exists"              [ -f "$TXN" ]
check "transaction helper has shebang"         sh -c 'test "$(head -1 "$1")" = "#!/bin/sh"' _ "$TXN"
check "requires DDEV_MODE=sandbox"             grep -Fq "DDEV_MODE is not 'sandbox'" "$TXN"
check "requires >= 2 argv"                     grep -Fq 'usage: ddev-transaction.sh <project-root>' "$TXN"
check "root charset validation"                grep -Fq '*[!A-Za-z0-9._/-]*)' "$TXN"
check "root must be exact projects.conf entry" grep -Fq 'grep -qx -- "$ROOT"' "$TXN"
check "mutating subcommand allowlist"          grep -Fq 'start|restart|stop|pause|poweroff' "$TXN"
check "subcommand charset validation"          grep -Fq '*[!a-z0-9-]*|"") die "invalid ddev subcommand' "$TXN"
check "rejects absolute rewrite entries"       grep -Fq 'rewrite entry must be relative' "$TXN"
check "rejects bad rewrite charset"            grep -Fq 'rewrite entry has forbidden characters' "$TXN"
check "runs ddev as the opencode user"         grep -Fq 'runuser -u "$OPENCODE_USER" -- env -i' "$TXN"
check "RUN uses a clean environment"           grep -Fq 'HOME="/home/$OPENCODE_USER"' "$TXN"
check "CLOSE removes u:opencode grants"        grep -Fq 'setfacl -x "u:$OPENCODE_USER"' "$TXN"
check "CLOSE chowns .ddev back"                grep -Fq 'chown -R "$DEFAULT_USER:$WWW_GROUP"' "$TXN"
check "CLOSE re-runs protect-projects --force" grep -Fq -- '--force --cwd "$ROOT"' "$TXN"
check "stamp is written under /run"            grep -Fq '/run/opencode-permissions-kit/ddev-txn' "$TXN"
check "EXIT trap closes the transaction"       grep -Fq "trap 'rc=\$?; close_transaction; exit \$rc' EXIT" "$TXN"
check "TERM/INT trapped"                       grep -Fq "'exit 143' TERM" "$TXN"
check "flock guard against parallel txns"      grep -Fq 'flock -n 9' "$TXN"
check "logs via shared log.sh (no-op first)"   grep -Fq 'log() { :; }' "$TXN"
echo "  (no eval policy)"
check_fail "no eval in transaction helper"     grep -n 'eval ' "$TXN"
check_fail "helper refuses to run unconfigured (exit non-zero)" \
    sh -c 'sh "$1" /tmp x >/dev/null 2>&1' _ "$TXN"

echo ""
echo "-- shim mode switch --"
check "shim reads DDEV_MODE from install.conf" \
    grep -Fq 'DDEV_MODE=$(sed -n '"'"'s/^DDEV_MODE=//p'"'"' "$_conf")' "$SHIM"
check "shim defaults to delegated"             grep -Fq 'DDEV_MODE="${DDEV_MODE:-delegated}"' "$SHIM"
check "shim branches on sandbox mode"          grep -Fq '"$DDEV_MODE" = "sandbox"' "$SHIM"
check "read-only subcommands skip the transaction" \
    grep -Fq 'describe|list|logs|exec|ssh|composer|launch|version|help' "$SHIM"
check "mutating path resolves the projects.conf root" \
    grep -Fq 'grep -qx -- "$walk" "$PROJECTS_CONF"' "$SHIM"
check "mutating path execs the transaction helper" \
    grep -Fq 'ddev-transaction.sh "$root" "$@"' "$SHIM"
check "delegated fallback preserved"           grep -Fq 'sudo -u "$DEFAULT_USER" "$DDEV_BIN" "$@"' "$SHIM"
check "passthrough for non-opencode users is intact" \
    tail -1 "$SHIM" | grep -Eq '^exec "\$DDEV_BIN" "\$@"'

echo ""
echo "-- sudoers template --"
check "delegated block marker begin"   grep -Fq '#@ddev-delegated-begin' "$SUDOERS"
check "delegated block marker end"     grep -Fq '#@ddev-delegated-end' "$SUDOERS"
check "sandbox block marker begin"     grep -Fq '#@ddev-sandbox-begin' "$SUDOERS"
check "sandbox block marker end"       grep -Fq '#@ddev-sandbox-end' "$SUDOERS"
check "sandbox rule grants root txn helper" \
    grep -Fq 'opencode     ALL=(root) NOPASSWD: /usr/local/lib/opencode-permissions-kit/ddev-transaction.sh *' "$SUDOERS"

echo ""
echo "-- install.sh wiring --"
check "install.sh fetches ddev-transaction.sh" \
    grep -Fq 'opencode-permissions-kit-lib/ddev-transaction.sh' "$INSTALL"
check "install.sh deploys ddev-transaction.sh" \
    grep -Fq '"$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-transaction.sh" "$LIBDIR/ddev-transaction.sh"' "$INSTALL"
check "install.sh chmods ddev-transaction.sh" \
    grep -Fq '"$LIBDIR/ddev-transaction.sh"' "$INSTALL"
check "install.sh preserves DDEV_MODE on reinstall" \
    grep -Fq '_dm=$(sed -n '"'"'s/^DDEV_MODE=//p'"'"' "$_c"' "$INSTALL"
check "install.sh writes DDEV_MODE to install.conf" \
    grep -Fq 'DDEV_MODE=$DDEV_MODE' "$INSTALL"
check "install.sh gates sandbox on rootless backend" \
    grep -Fq 'DDEV_MODE=sandbox requires a rootless container backend' "$INSTALL"
check "install.sh provisions /home/<oc>/.ddev" \
    grep -Fq 'mkdir -p "/home/$OPENCODE_USER/.ddev"' "$INSTALL"
check "install.sh ships the rewrite list" \
    grep -Fq '/etc/opencode-permissions-kit/ddev-rewrites.conf' "$INSTALL"
check "install.sh renders ddev blocks (sandbox branch)" \
    grep -Fq '/^#@ddev-delegated-begin$/,/^#@ddev-delegated-end$/d' "$INSTALL"
check "install.sh renders ddev blocks (delegated branch)" \
    grep -Fq '/^#@ddev-sandbox-begin$/,/^#@ddev-sandbox-end$/d' "$INSTALL"
check "install.sh deploys sudoers.template to the library (installed config.sh needs it)" \
    grep -Fq '"$SCRIPT_DIR/sudoers.template"                 "$LIBDIR/sudoers.template"' "$INSTALL"

echo ""
echo "-- update.sh wiring --"
check "update.sh fetch list includes ddev-transaction.sh" \
    grep -Fq 'opencode-permissions-kit-lib/ddev-transaction.sh' "$UPDATE"
check "update.sh deploys ddev-transaction.sh" \
    grep -Fq '"$SCRIPT_DIR/opencode-permissions-kit-lib/ddev-transaction.sh" "$LIBDIR/ddev-transaction.sh"' "$UPDATE"
check "update.sh chmods ddev-transaction.sh" \
    grep -Fq '"$LIBDIR/ddev-transaction.sh"' "$UPDATE"
check "update.sh renders ddev blocks by DDEV_MODE" \
    grep -Fq '${DDEV_MODE:-delegated}' "$UPDATE"
check "update.sh deploys sudoers.template to the library" \
    grep -Fq '"$SCRIPT_DIR/sudoers.template"                 "$LIBDIR/sudoers.template"' "$UPDATE"
check "update.sh keeps DDEV_MODE in install.conf (not filtered)" \
    sh -c '! grep -Fq -- "grep -v -e '"'"'^VERSION='"'"' -e '"'"'^DDEV_BIN='"'"' -e '"'"'^DDEV_MODE='"'"'" "$1"' _ "$UPDATE"

echo ""
echo "-- config.sh wiring --"
check "config.sh accepts ddev-mode action" \
    grep -Fq 'projects|git-config|refresh|status|container-backend|ddev-mode' "$CONFIG"
check "config.sh ddev-mode status implemented"  grep -Fq 'ddev_mode_status()' "$CONFIG"
check "config.sh ddev-mode apply implemented"   grep -Fq 'ddev_mode_apply()' "$CONFIG"
check "config.sh hard-gates sandbox on rootless" \
    grep -Fq "ddev mode 'sandbox' requires a rootless container backend" "$CONFIG"
check "config.sh --yes overrides the ddev version gate only" \
    grep -Fq "needs ddev >= 1.25" "$CONFIG"
check "config.sh provisions the rewrite list" \
    grep -Fq 'REWRITES_CONF' "$CONFIG"
check "config.sh updates DDEV_MODE in install.conf" \
    grep -Fq 'update_install_conf_ddev_mode()' "$CONFIG"
check "config.sh render_sudoers takes the ddev mode" \
    grep -Fq 'render_sudoers "$new_backend" "${DDEV_MODE:-delegated}"' "$CONFIG"
check "backend switch to docker-group falls back to delegated" \
    grep -Fq 'falling back to '"'"'delegated'"'"'' "$CONFIG"
check "sandbox switch offers the router-port sysctl" \
    grep -Fq 'net.ipv4.ip_unprivileged_port_start' "$CONFIG"
check "sysctl persisted via sysctl.d" \
    grep -Fq '/etc/sysctl.d/99-ddev-rootless.conf' "$CONFIG"
check "sysctl activation failure is non-fatal (warning + manual cmd)" \
    grep -Fq 'sysctl persisted but not activated live' "$CONFIG"
check "sandbox switch creates the mkcert CA best-effort" \
    grep -Fq 'rootCA.pem' "$CONFIG"
check "mkcert manual fallback printed when the binary is absent" \
    grep -Fq 'mkcert not downloaded yet' "$CONFIG"
check "sandbox re-apply is idempotent (runs setup even when already sandbox)" \
    grep -Fq 're-applying $new_mode setup (idempotent)' "$CONFIG"
check "sandbox switch restarts the rootless docker daemon after the sysctl" \
    grep -Fq 'restarted the opencode rootless docker daemon' "$CONFIG"
check "setup-container-backend applies the sysctl before the daemon start" \
    grep -Fq 'ip_unprivileged_port_start=80 applied before daemon start' "$REPO/files/opencode-permissions-kit-lib/setup-container-backend.sh"
check "status.sh reports router-port readiness" \
    grep -Fq 'router ports:' "$STATUS"

echo ""
echo "-- status.sh wiring --"
check "status.sh reports sandbox mode"          grep -Fq 'mode: ${GREEN}sandbox${NC}' "$STATUS"
check "status.sh reports delegated mode"        grep -Fq 'mode: delegated' "$STATUS"
check "status.sh surfaces open transaction stamps" \
    grep -Fq '/run/opencode-permissions-kit/ddev-txn/*.open' "$STATUS"

echo ""
echo "-- protect-projects.sh transaction heal --"
check "heal hands stranded .ddev files back" \
    grep -Fq 'ddev txn heal' "$PROTECT"
check "heal is gated on the transaction stamp" \
    grep -Fq '/run/opencode-permissions-kit/ddev-txn/${stamp_name}.open' "$PROTECT"

echo ""
echo "-- CI chmod lists --"
check "test.yml chmods ddev-transaction.sh" \
    grep -Fq 'files/opencode-permissions-kit-lib/ddev-transaction.sh' "$TEST_YML"
check "test.yml chmods test-ddev-sandbox.sh" \
    grep -Fq 'tests/test-ddev-sandbox.sh' "$TEST_YML"
check "e2e.yml chmods ddev-transaction.sh" \
    grep -Fq 'files/opencode-permissions-kit-lib/ddev-transaction.sh' "$E2E_YML"

echo ""
echo "===================================="
if [ "$failures" -gt 0 ]; then
    echo "  ${RED}Failed: $failures${NC}"
    exit 1
fi
echo "  ${GREEN}Passed: $passed${NC}"
echo "  All tests passed."
