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
echo "9.9.9" > "$LIB/VERSION"
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
    "$BIN/opencode-permissions-kit" "$@" 2>/dev/null
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
    *"v9.9.9"*) echo "  ${GREEN}PASS${NC}  version from LIBDIR/VERSION"; passed=$((passed + 1)) ;;
    *) echo "  ${RED}FAIL${NC}  version from LIBDIR/VERSION (got: $out)"; failures=$((failures + 1)) ;;
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

echo ""
if [ "$failures" -gt 0 ]; then
    echo "${RED}$failures test(s) failed${NC}"
    exit 1
fi
echo "${GREEN}All CLI dispatcher tests passed.${NC}"
exit 0
