#!/bin/bash
set -e

# ================================================================
# setup-jenkins-libs.sh
# Pushes lab-adapted shared libraries to Gitea and configures
# Jenkins to load them as Global Pipeline Libraries.
#
# After running this script, Jenkinsfiles can use:
#   @Library(['si-dp-shared-libs', 'elpa-shared-lib']) _
#
# Platform: macOS (Darwin) and Linux
# Requires: git, curl, docker (for Jenkins)
# ================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

GITEA_URL="http://localhost:3000"
GITEA_USER="labadmin"
GITEA_PASS="labadmin"
JENKINS_URL="http://localhost:8888"

SI_LIB_DIR="${PROJECT_DIR}/jenkin/si-jenkin-lab"
ELPA_LIB_DIR="${PROJECT_DIR}/jenkin/elpa-jenkin-lab"

echo
echo "=== Setup Jenkins Shared Libraries ==="
echo

# --- Step 1: Check Gitea ---
echo "--- Step 1: Check Gitea ---"
if ! curl -sf "${GITEA_URL}/api/v1/version" > /dev/null; then
    echo "  ❌ Gitea not running at ${GITEA_URL}"
    exit 1
fi
echo "  ✅ Gitea is running"

# --- Step 2: Push shared libs to Gitea ---
echo
echo "--- Step 2: Push shared libraries to Gitea ---"

push_lib_to_gitea() {
    local lib_name="$1"
    local lib_dir="$2"
    local repo_name="$3"

    echo "  Pushing ${lib_name}..."

    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
        "${GITEA_URL}/api/v1/repos/${GITEA_USER}/${repo_name}" \
        -u "${GITEA_USER}:${GITEA_PASS}" 2>/dev/null || echo "000")

    if [ "$http_code" != "200" ]; then
        curl -sf -X POST "${GITEA_URL}/api/v1/user/repos" \
            -H 'Content-Type: application/json' \
            -u "${GITEA_USER}:${GITEA_PASS}" \
            -d "{
                \"name\": \"${repo_name}\",
                \"description\": \"Lab-adapted ${lib_name}\",
                \"auto_init\": false,
                \"private\": false
            }" > /dev/null
        echo "    Created repo: ${GITEA_USER}/${repo_name}"
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    cp -r "${lib_dir}/." "${tmp_dir}/"
    cd "${tmp_dir}"
    git init -b main > /dev/null 2>&1
    git add -A
    git config user.email "jenkins@lab.local"
    git config user.name "Jenkins Lab"
    git commit -m "Initial: ${lib_name} lab-adapted shared library" > /dev/null 2>&1
    git remote add origin "http://${GITEA_USER}:${GITEA_PASS}@localhost:3000/${GITEA_USER}/${repo_name}.git"
    git push -u origin main --force > /dev/null 2>&1
    cd "${PROJECT_DIR}"
    rm -rf "${tmp_dir}"
    echo "    ✅ ${GITEA_USER}/${repo_name} (main)"
}

push_lib_to_gitea "si-dp-shared-libs" "${SI_LIB_DIR}" "si-dp-shared-libs"
push_lib_to_gitea "elpa-shared-lib" "${ELPA_LIB_DIR}" "elpa-shared-lib"

# --- Step 3: Configure Jenkins ---
echo
echo "--- Step 3: Configure Jenkins shared libraries ---"

if ! curl -sf "${JENKINS_URL}/login" > /dev/null; then
    echo "  ❌ Jenkins not running at ${JENKINS_URL}"
    exit 1
fi
echo "  ✅ Jenkins is running"

GROOVY_SCRIPT='
import jenkins.model.Jenkins
import jenkins.plugins.git.GitSCMSource
import org.jenkinsci.plugins.workflow.libs.GlobalLibraries
import org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
import org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever

def jenkins = Jenkins.get()

def createLib(String name, String gitUrl, String defaultVersion = "main") {
    def scmSource = new GitSCMSource(gitUrl)
    scmSource.setCredentialsId("")
    def retriever = new SCMSourceRetriever(scmSource)
    def lib = new LibraryConfiguration(name, retriever)
    lib.setDefaultVersion(defaultVersion)
    lib.setImplicit(false)
    lib.setAllowVersionOverride(true)
    return lib
}

def siLib = createLib("si-dp-shared-libs", "http://gitea:3000/labadmin/si-dp-shared-libs.git")
def elpaLib = createLib("elpa-shared-lib", "http://gitea:3000/labadmin/elpa-shared-lib.git")

def globalLibs = jenkins.getDescriptor(GlobalLibraries.class)
globalLibs.get().setLibraries([siLib, elpaLib])
globalLibs.save()

println "OK: si-dp-shared-libs + elpa-shared-lib configured"
'

HTTP_CODE=$(curl -sf -o /tmp/jenkins-groovy-result.txt -w "%{http_code}" \
    -X POST "${JENKINS_URL}/scriptText" \
    --data-urlencode "script=${GROOVY_SCRIPT}" 2>/dev/null || echo "000")

if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ $(cat /tmp/jenkins-groovy-result.txt | tr -d '\n')"
else
    echo "  ⚠️  Auto-config failed (HTTP ${HTTP_CODE}). Manual setup:"
    echo "     Jenkins > Manage Jenkins > System > Global Pipeline Libraries"
    echo "     Name: si-dp-shared-libs  Git: http://gitea:3000/labadmin/si-dp-shared-libs.git  Branch: main"
    echo "     Name: elpa-shared-lib    Git: http://gitea:3000/labadmin/elpa-shared-lib.git    Branch: main"
fi

echo
echo "=== Done ==="
echo
echo "Pipelines can now use:"
echo "  @Library(['si-dp-shared-libs', 'elpa-shared-lib']) _"
echo
