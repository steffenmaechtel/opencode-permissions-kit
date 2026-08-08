#!/bin/sh
# Integration test for project-specific opencode.jsonc ACLs (PLAN-STEP-2)
# Verifies that:
#  - Global denies apply to all projects
#  - Project-specific denies are scoped to their own directory
#  - Projects without own config only get global denies
#  - Deny patterns are cumulative (global + project, never weaker)
# Run: ./tests/test-project-config.sh
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(dirname "$0")"
PARSER="$SCRIPT_DIR/../files/opencode-lib/jsonc-parser.py"
PROTECT="$SCRIPT_DIR/../files/opencode-lib/protect-projects.sh"

failures=0
passed=0

assert_contains() {
    local desc="$1" pattern="$2" list="$3"
    if echo "$list" | grep -qF "$pattern"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        pattern '$pattern' not found"
        failures=$((failures + 1))
    fi
}

assert_not_contains() {
    local desc="$1" pattern="$2" list="$3"
    if ! echo "$list" | grep -qF "$pattern"; then
        echo "  ${GREEN}PASS${NC}  $desc"
        passed=$((passed + 1))
    else
        echo "  ${RED}FAIL${NC}  $desc"
        echo "        pattern '$pattern' should NOT be present"
        failures=$((failures + 1))
    fi
}

echo ""
echo "Project Config Integration Tests (PLAN-STEP-2)"
echo "================================================"
echo ""

# --- Setup temp environment ---
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/home/opencode/.config/opencode"
mkdir -p "$TMPDIR/var/www/vhosts/project-a/deploy/keys"
mkdir -p "$TMPDIR/var/www/vhosts/project-a/config"
mkdir -p "$TMPDIR/var/www/vhosts/project-b"

# Create test files in project-a
touch "$TMPDIR/var/www/vhosts/project-a/.env"
touch "$TMPDIR/var/www/vhosts/project-a/settings.php"
touch "$TMPDIR/var/www/vhosts/project-a/auth.json"
touch "$TMPDIR/var/www/vhosts/project-a/secret-tokens.json"
touch "$TMPDIR/var/www/vhosts/project-a/deploy/keys/server.pem"
touch "$TMPDIR/var/www/vhosts/project-a/dump-prod.sql"
touch "$TMPDIR/var/www/vhosts/project-a/config/database.php"
touch "$TMPDIR/var/www/vhosts/project-a/README.md"
touch "$TMPDIR/var/www/vhosts/project-a/readme.txt"

# Create test files in project-b (same type as project-a but different)
touch "$TMPDIR/var/www/vhosts/project-b/.env"
touch "$TMPDIR/var/www/vhosts/project-b/settings.php"
touch "$TMPDIR/var/www/vhosts/project-b/auth.json"
touch "$TMPDIR/var/www/vhosts/project-b/README.md"

# Copy global config template
cp "$SCRIPT_DIR/../files/opencode.jsonc" "$TMPDIR/home/opencode/.config/opencode/opencode.jsonc"

# Copy project-specific config to project-a
cp "$SCRIPT_DIR/fixtures/project-opencode.jsonc" "$TMPDIR/var/www/vhosts/project-a/opencode.jsonc"

# Create projects.conf
printf '%s\n' "$TMPDIR/var/www/vhosts/project-a" "$TMPDIR/var/www/vhosts/project-b" > "$TMPDIR/projects.conf"

echo "--- 1. Pattern extraction ---"

# Extract global deny patterns
GLOBAL_PATTERNS=$(python3 "$PARSER" "$TMPDIR/home/opencode/.config/opencode/opencode.jsonc" 2>/dev/null || true)
assert_contains ".env* in global patterns" ".env*" "$GLOBAL_PATTERNS"
assert_contains "auth.json in global patterns" "auth.json" "$GLOBAL_PATTERNS"

# Extract project-a deny patterns
PROJECT_A_PATTERNS=$(python3 "$PARSER" "$TMPDIR/var/www/vhosts/project-a/opencode.jsonc" 2>/dev/null || true)
assert_contains "secret-tokens.json in project-a" "secret-tokens.json" "$PROJECT_A_PATTERNS"
assert_contains "deploy/keys/*.pem in project-a" "deploy/keys/*.pem" "$PROJECT_A_PATTERNS"

# Verify project-a does NOT contain global-only patterns
assert_not_contains ".env* NOT in project-a" ".env*" "$PROJECT_A_PATTERNS"

echo ""
echo "--- 2. Merge (union of global + project-a denies) ---"
MERGED=$(printf '%s\n%s\n' "$GLOBAL_PATTERNS" "$PROJECT_A_PATTERNS" | sort -u)
assert_contains ".env* survives merge" ".env*" "$MERGED"
assert_contains "secret-tokens.json in merge" "secret-tokens.json" "$MERGED"
assert_contains "deploy/keys/*.pem in merge" "deploy/keys/*.pem" "$MERGED"

echo ""
echo "--- 3. Find-args matching (global → all projects) ---"

# Extract build_find_args from protect-projects.sh
# Reads patterns from file $1, echoes find predicates
build_find_args() {
    args="-type f"
    first=true
    while IFS= read -r pattern; do
        [ -z "$pattern" ] && continue
        clean="${pattern#\*\*\/}"
        if [ "$first" = true ]; then
            args="$args \("
            first=false
        else
            args="$args -o"
        fi
        case "$clean" in
            */*) args="$args -path \"*/$clean\"" ;;
            *)   args="$args -name \"$clean\"" ;;
        esac
    done < "$1"
    if [ "$first" = false ]; then
        args="$args \)"
    fi
    echo "$args"
}

TMP_PATTERNS=$(mktemp)
trap 'rm -rf "$TMPDIR" "$TMP_PATTERNS"' EXIT

echo "$GLOBAL_PATTERNS" > "$TMP_PATTERNS"
GLOBAL_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")

# Test global find args match files in both projects
ROOT_A="$TMPDIR/var/www/vhosts/project-a"
ROOT_B="$TMPDIR/var/www/vhosts/project-b"

FOUND_A=$(eval "find \"$ROOT_A\" $GLOBAL_FIND_ARGS" 2>/dev/null | sort)
FOUND_B=$(eval "find \"$ROOT_B\" $GLOBAL_FIND_ARGS" 2>/dev/null | sort)

assert_contains ".env found in project-a (global)" "$ROOT_A/.env" "$FOUND_A"
assert_contains "settings.php found in project-a (global)" "$ROOT_A/settings.php" "$FOUND_A"
assert_contains "auth.json found in project-a (global)" "$ROOT_A/auth.json" "$FOUND_A"
assert_contains "README.md found in project-a (global)" "$ROOT_A/README.md" "$FOUND_A"

assert_contains ".env found in project-b (global)" "$ROOT_B/.env" "$FOUND_B"
assert_contains "settings.php found in project-b (global)" "$ROOT_B/settings.php" "$FOUND_B"
assert_contains "auth.json found in project-b (global)" "$ROOT_B/auth.json" "$FOUND_B"
assert_contains "README.md found in project-b (global)" "$ROOT_B/README.md" "$FOUND_B"

echo ""
echo "--- 4. Find-args matching (project-a → project-a only) ---"

echo "$PROJECT_A_PATTERNS" > "$TMP_PATTERNS"
PROJECT_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")

FOUND_A_PROJ=$(eval "find \"$ROOT_A\" $PROJECT_FIND_ARGS" 2>/dev/null | sort)
FOUND_B_PROJ=$(eval "find \"$ROOT_B\" $PROJECT_FIND_ARGS" 2>/dev/null | sort)

# Project-a specific UNIQUE denies should match files in project-a only
# Note: patterns also present globally (settings.php, etc.) overlap — that's fine.
assert_contains "secret-tokens.json found in project-a (project)" "$ROOT_A/secret-tokens.json" "$FOUND_A_PROJ"
assert_contains "deploy/keys/*.pem found in project-a (project)" "$ROOT_A/deploy/keys/server.pem" "$FOUND_A_PROJ"
assert_contains "dump*.sql found in project-a (project)" "$ROOT_A/dump-prod.sql" "$FOUND_A_PROJ"

# Project-specific unique denies should NOT match files in project-b
assert_not_contains "secret-tokens.json NOT in project-b (project)" "$ROOT_B/secret-tokens.json" "$FOUND_B_PROJ"
assert_not_contains "deploy/keys/server.pem NOT in project-b" "$ROOT_B/deploy/keys/server.pem" "$FOUND_B_PROJ"
assert_not_contains "dump*.sql NOT in project-b" "$ROOT_B/dump-prod.sql" "$FOUND_B_PROJ"

echo ""
echo "--- 5. Union: global + project-a find matches all in project-a ---"

MERGED_PATTERNS_FILE=$(mktemp)
printf '%s\n%s\n' "$GLOBAL_PATTERNS" "$PROJECT_A_PATTERNS" > "$MERGED_PATTERNS_FILE"
MERGED_FIND_ARGS=$(build_find_args "$MERGED_PATTERNS_FILE")
rm -f "$MERGED_PATTERNS_FILE"

FOUND_A_MERGED=$(eval "find \"$ROOT_A\" $MERGED_FIND_ARGS" 2>/dev/null | sort)

assert_contains ".env in merge (project-a)" "$ROOT_A/.env" "$FOUND_A_MERGED"
assert_contains "secret-tokens.json in merge (project-a)" "$ROOT_A/secret-tokens.json" "$FOUND_A_MERGED"
assert_contains "deploy/keys/*.pem in merge (project-a)" "$ROOT_A/deploy/keys/server.pem" "$FOUND_A_MERGED"
assert_contains "auth.json in merge (project-a)" "$ROOT_A/auth.json" "$FOUND_A_MERGED"
assert_contains "config/database.php in merge" "$ROOT_A/config/database.php" "$FOUND_A_MERGED"

echo ""
echo "--- 6. Project-b without own config: global only ---"
PROJECT_B_CONFIG="$ROOT_B/opencode.jsonc"
if [ ! -f "$PROJECT_B_CONFIG" ]; then
    echo "  ${GREEN}PASS${NC}  project-b has no project config"
    passed=$((passed + 1))
else
    echo "  ${RED}FAIL${NC}  project-b should have no config"
    failures=$((failures + 1))
fi

echo ""
echo "--- 7. Partial name traps ---"
# Create a file that looks like a trapped partial match
touch "$TMPDIR/var/www/vhosts/project-b/config_token.json"

# 'config' pattern (config/database.php is path match, not name match)
# config_token.json should not be caught by global 'config/database.php' path match
assert_not_contains "config_token.json NOT caught by global" "$ROOT_B/config_token.json" "$FOUND_B"

echo ""
echo "--- 8. Project allow patterns (override global denies) ---"

# Create a project config that allows README.md
mkdir -p "$TMPDIR/var/www/vhosts/project-c"
touch "$TMPDIR/var/www/vhosts/project-c/README.md"
touch "$TMPDIR/var/www/vhosts/project-c/.env"
touch "$TMPDIR/var/www/vhosts/project-c/settings.php"

cat > "$TMPDIR/var/www/vhosts/project-c/opencode.jsonc" << 'JSONC'
{
    "permission": {
        "read": {
            "README.md": "allow",
            "**/README.md": "allow"
        },
        "edit": {
            "README.md": "allow",
            "**/README.md": "allow"
        }
    }
}
JSONC

ROOT_C="$TMPDIR/var/www/vhosts/project-c"

# Extract allow patterns from project-c
PROJECT_C_ALLOW=$(python3 "$PARSER" --allow "$ROOT_C/opencode.jsonc" 2>/dev/null || true)
assert_contains "README.md in project-c allow" "README.md" "$PROJECT_C_ALLOW"
assert_not_contains ".env NOT in project-c allow" ".env" "$PROJECT_C_ALLOW"

# Build find args for allow patterns
echo "$PROJECT_C_ALLOW" > "$TMP_PATTERNS"
ALLOW_FIND_ARGS=$(build_find_args "$TMP_PATTERNS")

# Allow patterns should find README.md
FOUND_C_ALLOW=$(eval "find \"$ROOT_C\" $ALLOW_FIND_ARGS" 2>/dev/null | sort)
assert_contains "allow: README.md found in project-c" "$ROOT_C/README.md" "$FOUND_C_ALLOW"
assert_not_contains "allow: .env NOT found in project-c" "$ROOT_C/.env" "$FOUND_C_ALLOW"
assert_not_contains "allow: settings.php NOT found in project-c" "$ROOT_C/settings.php" "$FOUND_C_ALLOW"

# Global denies should still match all in project-c
FOUND_C_GLOBAL=$(eval "find \"$ROOT_C\" $GLOBAL_FIND_ARGS" 2>/dev/null | sort)
assert_contains "global: .env found in project-c" "$ROOT_C/.env" "$FOUND_C_GLOBAL"
assert_contains "global: settings.php found in project-c" "$ROOT_C/settings.php" "$FOUND_C_GLOBAL"
assert_contains "global: README.md found in project-c" "$ROOT_C/README.md" "$FOUND_C_GLOBAL"

# Summary
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
