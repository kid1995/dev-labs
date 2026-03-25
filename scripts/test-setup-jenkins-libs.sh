#!/bin/bash
set -e

# ================================================================
# test-setup-jenkins-libs.sh
# Validates that setup-jenkins-libs.sh preconditions are met
# and simulates the library push flow.
#
# Platform: macOS (Darwin) and Linux
# Requires: git, curl
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS=0
FAIL=0

assert_exists() {
    if [ -e "$1" ]; then
        echo "  ✅ EXISTS: $1"
        PASS=$((PASS + 1))
    else
        echo "  ❌ MISSING: $1"
        FAIL=$((FAIL + 1))
    fi
}

assert_file_has() {
    if grep -q "$2" "$1" 2>/dev/null; then
        echo "  ✅ CONTAINS '$2': $1"
        PASS=$((PASS + 1))
    else
        echo "  ❌ MISSING '$2' in: $1"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Test: setup-jenkins-libs.sh prerequisites ==="
echo

echo "--- Shared lib directory structure ---"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_git.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_copsi.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_jenkins.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_java.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_docker.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_openshift.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_psql.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_its360.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/src/de/signaliduna/BitbucketRepo.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/src/de/signaliduna/CopsiEnvironment.groovy"
assert_exists "${PROJECT_DIR}/jenkin/si-jenkin-lab/src/de/signaliduna/TargetSegment.groovy"

echo
echo "--- ELPA shared lib ---"
assert_exists "${PROJECT_DIR}/jenkin/elpa-jenkin-lab/vars/elpa_copsi.groovy"
assert_exists "${PROJECT_DIR}/jenkin/elpa-jenkin-lab/vars/elpa_psql.groovy"
assert_exists "${PROJECT_DIR}/jenkin/elpa-jenkin-lab/src/de/signaliduna/BitbucketRepo.groovy"

echo
echo "--- Key content checks ---"
assert_file_has "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_copsi.groovy" "GITEA"
assert_file_has "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_copsi.groovy" "createChangeAsPullRequest"
assert_file_has "${PROJECT_DIR}/jenkin/si-jenkin-lab/vars/si_copsi.groovy" "waitForMergeChecksAndMerge"
assert_file_has "${PROJECT_DIR}/jenkin/elpa-jenkin-lab/vars/elpa_copsi.groovy" "deployFeature"
assert_file_has "${PROJECT_DIR}/jenkin/elpa-jenkin-lab/vars/elpa_copsi.groovy" "deployTst"
assert_file_has "${PROJECT_DIR}/jenkin/elpa-jenkin-lab/vars/elpa_copsi.groovy" "deployAbn"
assert_file_has "${PROJECT_DIR}/jenkin/elpa-jenkin-lab/vars/elpa_copsi.groovy" "generateTemplate"

echo
echo "--- Simulate: git init as shared lib repo ---"
TMP_DIR=$(mktemp -d)
cp -r "${PROJECT_DIR}/jenkin/si-jenkin-lab/." "${TMP_DIR}/"
cd "${TMP_DIR}"
git init -b main > /dev/null 2>&1
git add -A > /dev/null 2>&1
git config user.email "test@lab.local"
git config user.name "Test"
git commit -m "test commit" > /dev/null 2>&1

# Verify vars/ and src/ are committed
if git ls-files --error-unmatch vars/si_copsi.groovy > /dev/null 2>&1; then
    echo "  ✅ si_copsi.groovy tracked in git"
    PASS=$((PASS + 1))
else
    echo "  ❌ si_copsi.groovy NOT tracked"
    FAIL=$((FAIL + 1))
fi

if git ls-files --error-unmatch src/de/signaliduna/BitbucketRepo.groovy > /dev/null 2>&1; then
    echo "  ✅ BitbucketRepo.groovy tracked in git"
    PASS=$((PASS + 1))
else
    echo "  ❌ BitbucketRepo.groovy NOT tracked"
    FAIL=$((FAIL + 1))
fi

cd "${PROJECT_DIR}"
rm -rf "${TMP_DIR}"

echo
echo "--- Docker compose volume mount check ---"
assert_file_has "${PROJECT_DIR}/docker-compose.cicd.yml" "si-jenkin-lab"
assert_file_has "${PROJECT_DIR}/docker-compose.cicd.yml" "elpa-jenkin-lab"
assert_file_has "${PROJECT_DIR}/docker-compose.cicd.yml" "init-shared-libs.groovy"

echo
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
echo "All checks passed."
