#!/bin/bash
set -e

# Test: Verify elpa-elpa4 source content exists for deploy repo seeding

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="/Users/thekietdang/Downloads/github-buffer/combine-hint/elpa-elpa4"

PASS=0
FAIL=0

assert_exists() {
    if [ -e "$1" ]; then
        echo "  ✅ EXISTS: $(basename "$1")"
        PASS=$((PASS + 1))
    else
        echo "  ❌ MISSING: $1"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Test: deploy repo source content ==="
echo
assert_exists "${SOURCE_DIR}/services"
assert_exists "${SOURCE_DIR}/envs"
assert_exists "${SOURCE_DIR}/clean-feature.sh"
assert_exists "${SOURCE_DIR}/deploy-feature.sh"
assert_exists "${SOURCE_DIR}/init-service.sh"
assert_exists "${SOURCE_DIR}/services/hint"
assert_exists "${SOURCE_DIR}/envs/dev"

echo
echo "--- Simulate: git init as deploy repo ---"
TMP_DIR=$(mktemp -d)
cp -r "${SOURCE_DIR}/." "${TMP_DIR}/"
cd "${TMP_DIR}"
git init -b nop > /dev/null 2>&1
git add -A
git config user.email "test@lab.local"
git config user.name "Test"
git commit -m "test" > /dev/null 2>&1
TRACKED=$(git ls-files | wc -l | tr -d ' ')
echo "  ✅ ${TRACKED} files tracked in deploy repo"
PASS=$((PASS + 1))
cd /tmp
rm -rf "${TMP_DIR}"

echo
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] && echo "All checks passed."
