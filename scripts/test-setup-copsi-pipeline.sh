#!/bin/bash
set -e

# Test: Verify Jenkinsfile.copsi-test and all referenced files exist

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HINT_DIR="${PROJECT_DIR}/projects/hint-backend"

PASS=0
FAIL=0

assert_exists() {
    if [ -e "$1" ]; then echo "  ✅ $(basename "$1")"; PASS=$((PASS+1))
    else echo "  ❌ $1"; FAIL=$((FAIL+1)); fi
}
assert_contains() {
    if grep -q "$2" "$1" 2>/dev/null; then echo "  ✅ '$2' in $(basename "$1")"; PASS=$((PASS+1))
    else echo "  ❌ '$2' missing from $1"; FAIL=$((FAIL+1)); fi
}

echo "=== Test: CoPSI pipeline prerequisites ==="
echo
echo "--- Jenkinsfile ---"
assert_exists "${HINT_DIR}/Jenkinsfile.copsi-test"
assert_contains "${HINT_DIR}/Jenkinsfile.copsi-test" "si-dp-shared-libs"
assert_contains "${HINT_DIR}/Jenkinsfile.copsi-test" "elpa-shared-lib"
assert_contains "${HINT_DIR}/Jenkinsfile.copsi-test" "elpa_copsi.deployTst"
assert_contains "${HINT_DIR}/Jenkinsfile.copsi-test" "elpa_copsi.deployAbn"
assert_contains "${HINT_DIR}/Jenkinsfile.copsi-test" "elpa_copsi.deployFeature"

echo
echo "--- Copsi Helm chart ---"
assert_exists "${HINT_DIR}/copsi/Chart.yaml"
assert_exists "${HINT_DIR}/copsi/values-tst.yaml"
assert_exists "${HINT_DIR}/copsi/values-abn.yaml"
assert_exists "${HINT_DIR}/copsi/values-feature.yaml"
assert_exists "${HINT_DIR}/copsi/templates/deployment.yaml"

echo
echo "--- Setup scripts ---"
assert_exists "${PROJECT_DIR}/scripts/setup-jenkins-libs.sh"
assert_exists "${PROJECT_DIR}/scripts/setup-deploy-repo.sh"

echo
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
[ "$FAIL" -eq 0 ] && echo "All checks passed."
