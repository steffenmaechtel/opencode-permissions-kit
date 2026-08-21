#!/bin/sh
# Test the CLI dispatcher (files/opencode-permissions-kit-lib/kit).
# Builds a fake library dir with stub scripts, symlinks the dispatcher,
# and checks dispatch, help, error handling, and flag pass-through.
# Run: sh tests/test-kit-cli.sh
set -e
set -u

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT="$SCRIPT_DIR/../files/opencode-permissions-kit-lib/kit"

failures=0
passed=0

assert() {
    desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        expected: [$expected]  got: [$actual]"
        failures=$((failures + 1))
    fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Fake library with stub scripts recording how they were invoked.
LIB="$WORK/lib"
mkdir -p "$LIB"
# install.conf carries the deployed VERSION stamp (a standalone VERSION file
# is NOT deployed to the library — regression guard for the v0.0.0 display).
printf 'DEFAULT_USER=dev\nVERSION=9.9.9\n' > "$WORK/install.conf"
for s in status config update uninstall; do
    cat > "$LIB/$s.sh" <<EOF
#!/bin/sh
echo "$s:euid=\$(id -u):args=\$*"
EOF
done

# Fake sudo: records invocation, then execs the command unchanged. The
# dispatcher's auto-elevation must go through sudo when not root; with the
# fake, the stub still runs as the current user.
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/sudo" <<'EOF'
#!/bin/sh
echo "sudo-called" >> "$(dirname "$0")/../sudo-marker"
exec "$@"
EOF
chmod +x "$FAKEBIN/sudo"
PATH="$FAKEBIN:$PATH"
export PATH

# Dispatch through a symlink like /usr/local/bin does.
BIN="$WORK/bin"
mkdir -p "$BIN"
ln -s "$LIB/kit" "$BIN/opencode-permissions-kit"
cp "$KIT" "$LIB/kit"
chmod +x "$LIB/kit"

run_kit() {
    OPK_INSTALL_CONF="$WORK/install.conf" "$BIN/opencode-permissions-kit" "$@" 2>/dev/null
}

echo "=== CLI dispatcher tests ==="

# help lists every subcommand
out="$(run_kit --help)"
assert "--help exits 0" "0" "$?"
for c in status config update uninstall help; do
    case "$out" in
        *"$c"*) echo "  ${GREEN}PASS${NC}  --help mentions '$c'"; passed=$((passed + 1)) ;;
        *) echo "  ${RED}FAIL${NC}  --help mentions '$c'"; failures=$((failures + 1)) ;;
    esac
done
out_help="$(run_kit help)"
assert "help == --help" "$(run_kit --help)" "$out_help"

# version comes from the library VERSION file
case "$out" in
    *"v9.9.9"*) echo "  ${GREEN}PASS${NC}  version from install.conf stamp"; passed=$((passed + 1)) ;;
    *) echo "  ${RED}FAIL${NC}  version from install.conf stamp (got: $out)"; failures=$((failures + 1)) ;;
esac

# status dispatches without sudo (root test envs: euid matches current)
out="$(run_kit status)"
assert "status dispatches" "status:euid=$(id -u):args=" "$out"

# config/update dispatch with args passed through (fake sudo passes them on;
# stubs run as the current user either way)
out="$(run_kit config projects list)"
assert "config passes args" "config:euid=$(id -u):args=projects list" "$out"
out="$(run_kit update --yes --refresh)"
assert "update passes flags" "update:euid=$(id -u):args=--yes --refresh" "$out"

# upgrade-opencode: binary-only shorthand — injects --yes --only-binary,
# extra flags pass through (issue #24)
out="$(run_kit upgrade-opencode --binary-path /tmp/x)"
assert "upgrade-opencode injects --yes --only-binary (flags pass through)" \
    "update:euid=$(id -u):args=--yes --only-binary --binary-path /tmp/x" "$out"

# non-root invocations of config/update go through sudo
if [ "$(id -u)" -ne 0 ]; then
    if [ -f "$WORK/sudo-marker" ]; then
        echo "  ${GREEN}PASS${NC}  config/update auto-elevate via sudo"; passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  config/update auto-elevate via sudo"; failures=$((failures + 1))
    fi
else
    echo "  ${GREEN}PASS${NC}  config/update auto-elevate (skipped: test runs as root)"; passed=$((passed + 1))
fi

# uninstall dispatches as the current user (no forced sudo)
out="$(run_kit uninstall --dry-run)"
assert "uninstall passes flags" "uninstall:euid=$(id -u):args=--dry-run" "$out"

# unknown command fails with exit 1
if run_kit frobnicate >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  unknown command exits non-zero"; failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  unknown command exits non-zero"; passed=$((passed + 1))
fi

# no command fails with exit 1
if run_kit >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  no command exits non-zero"; failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  no command exits non-zero"; passed=$((passed + 1))
fi

# missing script -> clear error, non-zero
rm "$LIB/update.sh"
if run_kit update >/dev/null 2>&1; then
    echo "  ${RED}FAIL${NC}  missing script exits non-zero"; failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  missing script exits non-zero"; passed=$((passed + 1))
fi
errout="$("$BIN/opencode-permissions-kit" update 2>&1 >/dev/null || true)"
case "$errout" in
    *"not found"*) echo "  ${GREEN}PASS${NC}  missing script names the problem"; passed=$((passed + 1)) ;;
    *) echo "  ${RED}FAIL${NC}  missing script names the problem (got: $errout)"; failures=$((failures + 1)) ;;
esac

# List drift guard: install.sh's fetch_kit() list and update.sh's KIT_FILES
# must carry the same file set — a missing entry means streamed installs
# fetch an incomplete kit and crash at deploy time (set -e).
install_list="$(sed -n '/^fetch_kit() {/,/^}/p' "$SCRIPT_DIR/../files/install.sh" \
    | grep -v 'mkdir' \
    | grep -oE '(install|config|update|uninstall|status)\.sh|opencode(-deny-all)?\.jsonc|sudoers\.template|umask\.sh|VERSION|opencode-permissions-kit-lib/[a-zA-Z0-9./_-]+' | sort -u)"
update_list="$(awk '/^KIT_FILES=/{flag=1} flag{printf "%s ", $0} flag && /"[[:space:]]*$/{exit}' "$SCRIPT_DIR/../files/update.sh" \
    | sed -e 's/^KIT_FILES="//' -e 's/"[[:space:]]*$//' -e 's/\\//g' | tr ' ' '\n' | grep -v '^$' | sort -u)"
if [ "$install_list" = "$update_list" ]; then
    echo "  ${GREEN}PASS${NC}  install.sh fetch list == update.sh KIT_FILES"; passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  install.sh fetch list == update.sh KIT_FILES"
    echo "        only in install.sh: $(printf '%s\n' "$install_list" | grep -vxF "$(printf '%s\n' "$update_list")" | tr '\n' ' ')"
    echo "        only in update.sh: $(printf '%s\n' "$update_list" | grep -vxF "$(printf '%s\n' "$install_list")" | tr '\n' ' ')"
    failures=$((failures + 1))
fi

# Compat-stub guard: while the upgrade floor is 0.0.14, the pre-0.0.15
# update.sh file lists still fetch migrate-denies.sh — a 404 would abort
# their update before the new update.sh takes over. The stub is never
# deployed (not in the current KIT_FILES).
floor_line="$(grep -o 'floor_check "0\.[0-9]*\.[0-9]*"' "$SCRIPT_DIR/../files/update.sh" | head -1)"
case "$floor_line" in
    *0.0.14*)
        if [ -f "$SCRIPT_DIR/../files/opencode-permissions-kit-lib/migrate-denies.sh" ]; then
            echo "  ${GREEN}PASS${NC}  compat stub present while floor is 0.0.14"; passed=$((passed + 1))
        else
            echo "  ${RED}FAIL${NC}  compat stub present while floor is 0.014 (0.0.14 update.sh fetches it — 404 aborts the update)"; failures=$((failures + 1))
        fi
        ;;
esac
if sed -n 's/^KIT_FILES="\(.*\)"$/\1/p' "$SCRIPT_DIR/../files/update.sh" | grep -q 'opencode-permissions-kit-lib/migrate-denies.sh'; then
    echo "  ${RED}FAIL${NC}  stub must NOT be in KIT_FILES (never deployed)"; failures=$((failures + 1))
else
    echo "  ${GREEN}PASS${NC}  stub not in KIT_FILES (never deployed)"; passed=$((passed + 1))
fi

echo ""
if [ "$failures" -gt 0 ]; then
    echo "${RED}$failures test(s) failed${NC}"
    exit 1
fi
echo "${GREEN}All CLI dispatcher tests passed.${NC}"
exit 0
