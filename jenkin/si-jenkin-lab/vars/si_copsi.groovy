// Lab-adapted si_copsi.groovy
// Replaces Bitbucket REST API with Gitea REST API.
// Original: combine-hint/jenkin/si-jenkin/vars/si_copsi.groovy
//
// Key differences:
//   - Bitbucket REST API -> Gitea REST API (v1)
//   - git.system.local -> gitea:3000 (internal) / localhost:3000 (external)
//   - Credentials: jenkins_git_http -> labadmin:labadmin (Gitea basic auth)

import de.signaliduna.BitbucketRepo
import de.signaliduna.CopsiEnvironment
import groovy.json.JsonOutput
import groovy.json.JsonSlurperClassic
import groovy.transform.Field

@Field
String GIT_CLONE_DIR = "cd-repos"

@Field
String GITEA_INTERNAL_URL = "http://gitea:3000"

@Field
String GITEA_API_BASE = "${GITEA_INTERNAL_URL}/api/v1"

@Field
String GITEA_CREDENTIALS_ID = "gitea-lab"

String getSealedSecretCertFile(CopsiEnvironment clusterName) {
    echo "[LAB] SealedSecret cert file not available in lab — returning placeholder"
    return "/dev/null"
}

void writeSealedSecretFile(Map config) {
    echo "[LAB] writeSealedSecretFile skipped (no kubeseal in lab)"
    echo "[LAB] Would write sealed secret '${config.name}' to ${config.outputFile}"
}

/**
 * Creates a change directly on a branch in the deploy repo via Gitea.
 * Lab equivalent of the original createChange that uses Bitbucket.
 */
boolean createChange(BitbucketRepo repo, String targetBranch, Closure<String> updater) {
    sh "mkdir -p ${GIT_CLONE_DIR}"
    dir(GIT_CLONE_DIR) {
        def gitUrl = "${GITEA_INTERNAL_URL}/${repo.projectName}/${repo.repoName}.git"
        sh "rm -rf ${repo.repoName}"
        sh "git clone ${gitUrl} --depth 1 -b '${targetBranch}'"
        dir(repo.repoName) {
            sh "git config user.email 'jenkins@lab.local'"
            sh "git config user.name 'Jenkins Lab'"
            String commitMessage = updater()
            sh "git commit --allow-empty -m '${commitMessage}'"

            String changedFiles = sh(
                script: "git diff --name-only HEAD~1 HEAD",
                returnStdout: true
            ).trim()

            if (changedFiles) {
                echo "Changed files:\n${changedFiles}"
                sh 'git push origin HEAD'
                return true
            } else {
                echo "No changes detected."
                return false
            }
        }
    }
}

/**
 * Creates a PR in Gitea for the deploy repo changes.
 * Lab equivalent of the original createChangeAsPullRequest that uses Bitbucket.
 */
String createChangeAsPullRequest(
    BitbucketRepo repo,
    String sourceBranch = "autodeploy/job-${BUILD_NUMBER}",
    String targetBranch,
    Map pullRequestAttributes,
    Closure<String> updater
) {
    sh "mkdir -p ${GIT_CLONE_DIR}"
    String prId = ""
    dir(GIT_CLONE_DIR) {
        def gitUrl = "${GITEA_INTERNAL_URL}/${repo.projectName}/${repo.repoName}.git"
        sh "rm -rf ${repo.repoName}"

        // Sanitize branch name for git
        def safeBranch = sourceBranch.replaceAll('[^a-zA-Z0-9/_.-]', '-')

        sh "git clone ${gitUrl} --depth 1 -b '${targetBranch}'"
        dir(repo.repoName) {
            sh "git config user.email 'jenkins@lab.local'"
            sh "git config user.name 'Jenkins Lab'"
            sh "git checkout -b '${safeBranch}'"

            String commitMessage = updater()
            sh "git commit --allow-empty -m '${commitMessage}'"

            String changedFiles = sh(
                script: "git diff --name-only ${safeBranch} origin/${targetBranch}",
                returnStdout: true
            ).trim()

            if (changedFiles) {
                echo "Changed files:\n${changedFiles}"
                sh "git push -u origin '${safeBranch}'"
                prId = createGiteaPullRequest(repo, safeBranch, targetBranch, pullRequestAttributes)
            } else {
                echo "No changes between branches."
            }
        }
    }
    return prId
}

/**
 * Creates a pull request via Gitea REST API.
 */
String createGiteaPullRequest(BitbucketRepo repo, String sourceBranch, String targetBranch, Map pullRequestAttributes) {
    def defaultAttrs = [
        title: "Autodeploy ${BUILD_NUMBER}",
        description: "Autodeploy for build number ${BUILD_NUMBER}"
    ]
    def attrs = defaultAttrs + pullRequestAttributes

    def requestBody = JsonOutput.toJson([
        title: attrs.title,
        body : attrs.description ?: attrs.body ?: "",
        head : sourceBranch,
        base : targetBranch
    ])

    def apiUrl = "${GITEA_API_BASE}/repos/${repo.projectName}/${repo.repoName}/pulls"
    echo "[LAB] Creating PR via Gitea API: ${apiUrl}"

    def response = sh(
        script: """curl -s -X POST '${apiUrl}' \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json' \
            -u 'labadmin:labadmin' \
            -d '${requestBody}'""",
        returnStdout: true
    ).trim()

    def parsed = new JsonSlurperClassic().parseText(response)
    if (parsed.id) {
        echo "[LAB] PR created: #${parsed.number} - ${parsed.title}"
        return parsed.number.toString()
    } else {
        echo "[LAB] PR creation response: ${response}"
        return ""
    }
}

/**
 * Waits for merge checks and merges a Gitea PR.
 * In lab, there are no merge checks — we merge immediately.
 */
boolean waitForMergeChecksAndMerge(
    BitbucketRepo repo,
    String prNumber,
    boolean abortBuildOnError = false,
    boolean deleteSourceBranch = true,
    int maxAttempts = 30
) {
    sleep(time: 2, unit: "SECONDS")

    def apiUrl = "${GITEA_API_BASE}/repos/${repo.projectName}/${repo.repoName}/pulls/${prNumber}/merge"
    echo "[LAB] Merging PR #${prNumber} via Gitea API"

    def mergeBody = JsonOutput.toJson([
        Do                  : "merge",
        delete_branch_after_merge: deleteSourceBranch
    ])

    def response = sh(
        script: """curl -s -X POST '${apiUrl}' \
            -H 'Content-Type: application/json' \
            -H 'Accept: application/json' \
            -u 'labadmin:labadmin' \
            -d '${mergeBody}'""",
        returnStdout: true
    ).trim()

    if (response == "" || response.contains('"sha"')) {
        echo "[LAB] PR #${prNumber} merged successfully"
        return true
    } else {
        echo "[LAB] PR merge response: ${response}"
        if (abortBuildOnError) {
            error("Failed to merge PR #${prNumber}")
        }
        return false
    }
}

/**
 * Gitea-compatible buildGitUrl — no credential injection needed in lab.
 */
String buildGitUrl(String gitUrl) {
    return gitUrl
}
