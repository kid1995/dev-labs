#!/bin/bash
set -e

# ================================================================
# setup-deploy-repo.sh
# Pushes the elpa-elpa4 deploy repo to Gitea.
# This simulates the SDASVCDEPLOY/elpa-elpa4 Bitbucket repo.
#
# The deploy repo is where CoPSI Jenkins functions push rendered
# Helm manifests via PRs for ArgoCD to pick up.
#
# Usage:
#   ./scripts/setup-deploy-repo.sh
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GITEA_URL="http://localhost:3000"
GITEA_USER="labadmin"
GITEA_PASS="labadmin"

# Source: combine-hint/elpa-elpa4 (the real deploy repo content)
SOURCE_DIR="/Users/thekietdang/Downloads/github-buffer/combine-hint/elpa-elpa4"
REPO_NAME="elpa-elpa4"

# CoPSI uses CopsiEnvironment.nop as the target branch
TARGET_BRANCH="nop"

echo
echo "=== Setup Deploy Repo: ${REPO_NAME} ==="
echo

# Check Gitea
if ! curl -sf "${GITEA_URL}/api/v1/version" > /dev/null; then
    echo "  ❌ Gitea not running"
    exit 1
fi

# Check source exists
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "  ❌ Source not found: ${SOURCE_DIR}"
    exit 1
fi

# Create repo in Gitea
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
    "${GITEA_URL}/api/v1/repos/${GITEA_USER}/${REPO_NAME}" \
    -u "${GITEA_USER}:${GITEA_PASS}" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
    curl -sf -X POST "${GITEA_URL}/api/v1/user/repos" \
        -H 'Content-Type: application/json' \
        -u "${GITEA_USER}:${GITEA_PASS}" \
        -d "{
            \"name\": \"${REPO_NAME}\",
            \"description\": \"CoPSI deploy repo (lab simulation of SDASVCDEPLOY/elpa-elpa4)\",
            \"auto_init\": false,
            \"default_branch\": \"${TARGET_BRANCH}\",
            \"private\": false
        }" > /dev/null
    echo "  ✅ Created Gitea repo: ${GITEA_USER}/${REPO_NAME}"
else
    echo "  ✅ Repo already exists: ${GITEA_USER}/${REPO_NAME}"
fi

# Push content
TMP_DIR=$(mktemp -d)
cp -r "${SOURCE_DIR}/." "${TMP_DIR}/"
cd "${TMP_DIR}"
git init -b "${TARGET_BRANCH}" > /dev/null 2>&1
git add -A
git config user.email "jenkins@lab.local"
git config user.name "Jenkins Lab"
git commit -m "Initial: CoPSI deploy repo for elpa-elpa4 namespace" > /dev/null 2>&1
git remote add origin "http://${GITEA_USER}:${GITEA_PASS}@localhost:3000/${GITEA_USER}/${REPO_NAME}.git"
git push -u origin "${TARGET_BRANCH}" --force > /dev/null 2>&1
cd "${PROJECT_DIR}"
rm -rf "${TMP_DIR}"

FILE_COUNT=$(find "${SOURCE_DIR}" -type f | wc -l | tr -d ' ')
echo "  ✅ Pushed ${FILE_COUNT} files to ${GITEA_USER}/${REPO_NAME} (branch: ${TARGET_BRANCH})"

echo
echo "=== Done ==="
echo
echo "Deploy repo available at:"
echo "  Gitea UI:  ${GITEA_URL}/${GITEA_USER}/${REPO_NAME}"
echo "  Git clone: http://gitea:3000/${GITEA_USER}/${REPO_NAME}.git (from containers)"
echo "  Branch:    ${TARGET_BRANCH}"
echo
