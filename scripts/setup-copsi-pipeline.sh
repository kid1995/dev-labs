#!/bin/bash
set -e

# ================================================================
# setup-copsi-pipeline.sh
# Creates a Jenkins pipeline job for testing CoPSI deployment functions.
# Runs setup-jenkins-libs.sh and setup-deploy-repo.sh first, then
# creates the pipeline job pointing to Jenkinsfile.copsi-test.
#
# Also installs helm in the Jenkins container if not present.
#
# Usage:
#   ./scripts/setup-copsi-pipeline.sh
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
JENKINS_URL="http://localhost:8888"
GITEA_URL="http://localhost:3000"
GITEA_USER="labadmin"
GITEA_PASS="labadmin"

echo
echo "=== Setup CoPSI Test Pipeline ==="
echo

# --- Step 0: Ensure hint-backend repo exists in Gitea ---
echo "--- Step 0: Push hint-backend to Gitea (with copsi/ chart + Jenkinsfile) ---"
HINT_SRC="${PROJECT_DIR}/projects/hint-backend"

HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" \
    "${GITEA_URL}/api/v1/repos/${GITEA_USER}/hint-backend" \
    -u "${GITEA_USER}:${GITEA_PASS}" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" != "200" ]; then
    curl -sf -X POST "${GITEA_URL}/api/v1/user/repos" \
        -H 'Content-Type: application/json' \
        -u "${GITEA_USER}:${GITEA_PASS}" \
        -d "{
            \"name\": \"hint-backend\",
            \"description\": \"Hint service (CoPSI test)\",
            \"auto_init\": false,
            \"private\": false
        }" > /dev/null
fi

TMP_DIR=$(mktemp -d)
cp -r "${HINT_SRC}/." "${TMP_DIR}/"
cd "${TMP_DIR}"
git init -b develop > /dev/null 2>&1
git add -A
git config user.email "jenkins@lab.local"
git config user.name "Jenkins Lab"
git commit -m "hint-backend with copsi chart and Jenkinsfile.copsi-test" > /dev/null 2>&1
git remote add origin "http://${GITEA_USER}:${GITEA_PASS}@localhost:3000/${GITEA_USER}/hint-backend.git"
git push -u origin develop --force > /dev/null 2>&1

# Also create a feature branch for testing
git checkout -b "feature/ELPA4-9999-copsi-test" > /dev/null 2>&1
git commit --allow-empty -m "ELPA4-9999: test feature branch for CoPSI" > /dev/null 2>&1
git push -u origin "feature/ELPA4-9999-copsi-test" --force > /dev/null 2>&1

cd "${PROJECT_DIR}"
rm -rf "${TMP_DIR}"
echo "  ✅ hint-backend pushed to Gitea (branches: develop, feature/ELPA4-9999-copsi-test)"

# --- Step 1: Setup shared libs ---
echo
echo "--- Step 1: Setup shared libraries ---"
"${SCRIPT_DIR}/setup-jenkins-libs.sh"

# --- Step 2: Setup deploy repo ---
echo
echo "--- Step 2: Setup deploy repo ---"
"${SCRIPT_DIR}/setup-deploy-repo.sh"

# --- Step 3: Install helm in Jenkins ---
echo
echo "--- Step 3: Ensure helm is installed in Jenkins ---"
docker exec lab-jenkins bash -c 'command -v helm > /dev/null 2>&1' 2>/dev/null && {
    echo "  ✅ Helm already installed"
} || {
    echo "  Installing helm in Jenkins container..."
    docker exec lab-jenkins bash -c 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash' > /dev/null 2>&1
    echo "  ✅ Helm installed"
}

# --- Step 4: Create Jenkins pipeline job ---
echo
echo "--- Step 4: Create Jenkins pipeline job ---"

JOB_XML=$(cat <<'JOBXML'
<?xml version='1.1' encoding='UTF-8'?>
<flow-definition plugin="workflow-job">
  <description>CoPSI deployment function test pipeline.
Tests elpa_copsi.deployTst/deployAbn/deployFeature against Gitea.</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.ChoiceParameterDefinition>
          <name>TEST_MODE</name>
          <choices class="java.util.Arrays$ArrayList">
            <a class="string-array">
              <string>all</string>
              <string>helm-only</string>
              <string>deploy-tst</string>
              <string>deploy-abn</string>
              <string>deploy-feature</string>
            </a>
          </choices>
          <description>Which CoPSI function to test</description>
        </hudson.model.ChoiceParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>OVERRIDE_BRANCH</name>
          <defaultValue></defaultValue>
          <description>Override branch name (e.g. feature/ELPA4-1234-test)</description>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>http://gitea:3000/labadmin/hint-backend.git</url>
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/develop</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
    </scm>
    <scriptPath>Jenkinsfile.copsi-test</scriptPath>
    <lightweight>true</lightweight>
  </definition>
</flow-definition>
JOBXML
)

# Check if job exists
JOB_HTTP=$(curl -sf -o /dev/null -w "%{http_code}" "${JENKINS_URL}/job/copsi-test/api/json" 2>/dev/null || echo "000")

if [ "$JOB_HTTP" = "200" ]; then
    # Update existing job
    curl -sf -X POST "${JENKINS_URL}/job/copsi-test/config.xml" \
        -H 'Content-Type: application/xml' \
        -d "${JOB_XML}" > /dev/null 2>&1 && echo "  ✅ Updated job: copsi-test" || echo "  ⚠️  Could not update job"
else
    # Create new job
    curl -sf -X POST "${JENKINS_URL}/createItem?name=copsi-test" \
        -H 'Content-Type: application/xml' \
        -d "${JOB_XML}" > /dev/null 2>&1 && echo "  ✅ Created job: copsi-test" || echo "  ⚠️  Could not create job via API. Create manually."
fi

echo
echo "=== Setup Complete ==="
echo
echo "To run the CoPSI test pipeline:"
echo "  1. Open Jenkins: ${JENKINS_URL}/job/copsi-test/"
echo "  2. Click 'Build with Parameters'"
echo "  3. Select TEST_MODE:"
echo "     - 'all'            = test all CoPSI functions"
echo "     - 'helm-only'      = only verify Helm chart rendering"
echo "     - 'deploy-tst'     = test deployTst()"
echo "     - 'deploy-abn'     = test deployAbn()"
echo "     - 'deploy-feature' = test deployFeature()"
echo
echo "After the build, check Gitea for PRs:"
echo "  ${GITEA_URL}/${GITEA_USER}/elpa-elpa4/pulls"
echo
