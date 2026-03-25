// Lab-adapted si_git.groovy
// Replaces Bitbucket-specific git operations with Gitea-compatible equivalents.
// Original: combine-hint/jenkin/si-jenkin/vars/si_git.groovy

import de.signaliduna.BitbucketPr
import de.signaliduna.BitbucketRepo
import groovy.json.JsonSlurperClassic

@groovy.transform.Field
def MASTER = 'master'
@groovy.transform.Field
def MAIN = 'main'
@groovy.transform.Field
def DEVELOP = 'develop'
@groovy.transform.Field
def FEATURE_PREFIX = 'feature/'
@groovy.transform.Field
def RELEASE_PREFIX = 'release'
@groovy.transform.Field
def RENOVATE_PREFIX = 'renovate/'

boolean isMaster() { return branchName() == MASTER }
boolean isMain() { return branchName() == MAIN }
boolean isMainOrMaster() { return isMain() || isMaster() }
boolean isDevelop() { return branchName() == DEVELOP }
boolean isFeature() { return branchName().startsWith(FEATURE_PREFIX) }
boolean isRelease() { return branchName().startsWith(RELEASE_PREFIX) }
boolean isRenovate() { return branchName().startsWith(RENOVATE_PREFIX) }

String commitId() {
    return sh(returnStdout: true, script: 'git rev-parse HEAD').trim()
}

String shortCommitId() {
    return sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
}

String branchName() {
    if (env.BRANCH_NAME) return env.BRANCH_NAME
    if (env.GIT_BRANCH) return env.GIT_BRANCH.replaceFirst('origin/', '')
    // Fallback: detect from git (non-multibranch pipelines don't set BRANCH_NAME)
    def branch = sh(script: 'git rev-parse --abbrev-ref HEAD 2>/dev/null || echo detached', returnStdout: true).trim()
    return branch == 'HEAD' || branch == 'detached' ? 'develop' : branch
}

String featureName() {
    if (!isFeature()) return ''
    return branchName().substring(FEATURE_PREFIX.length())
}

String[] currentCommitTags() {
    return sh(returnStdout: true, script: 'git tag -l --points-at HEAD').trim().split('\n')
}

boolean hasTag(String tagName) {
    return currentCommitTags().any { tag -> tag == tagName }
}

Map<String, String> checkoutBranch(String name, Map notificationConfig = [:]) {
    Map<String, String> scmVariables = checkout(scm)
    sh "git fetch -a -p"
    sh "git checkout ${name} || git checkout -b ${name} origin/${name} || true"
    sh 'git clean -ffd'
    return scmVariables
}

void push(String targetBranch) {
    sh "git push --follow-tags origin ${targetBranch}"
}

String emailOfLastCommit() {
    return sh(returnStdout: true, script: "git log -1 --pretty=format:'%ae'").trim()
}

String lastCommitMessage() {
    return sh(returnStdout: true, script: "git log -1 --pretty=format:'%B'").trim()
}

String extractJiraReferenceFromCommit(String jiraProjektPrefix) {
    jiraProjektPrefix = jiraProjektPrefix + "-"
    String commitMessage = lastCommitMessage()
    echo "Extracting jira ticket reference from: ${commitMessage}"

    String lowerCaseMessage = commitMessage.toLowerCase()
    int prefixStart = lowerCaseMessage.indexOf(jiraProjektPrefix.toLowerCase())

    if (prefixStart > -1) {
        def shortenedMessage = lowerCaseMessage.substring(prefixStart + jiraProjektPrefix.length())
        def number = shortenedMessage.replaceAll("\\D", "").trim()
        return jiraProjektPrefix + number
    }

    echo "Failed to identify jira reference for prefix: ${jiraProjektPrefix}"
    return "ELPA4-0000"
}

BitbucketRepo parseGitUrl() {
    def url = sh(script: 'git remote get-url origin', returnStdout: true).trim()
    // Gitea URL format: http://gitea:3000/lab/repo-name.git
    def matcher = url =~ /\/([^\/]+)\/([^\/]+?)(?:\.git)?$/
    if (matcher) {
        return new BitbucketRepo(matcher[0][1], matcher[0][2])
    }
    return new BitbucketRepo("lab", "unknown")
}

void createGitTag(String tagPrefix = "") {
    def now = java.time.LocalDate.now().format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd"))
    sh "git tag -f ${tagPrefix != '' ? tagPrefix + '-' : ''}${now}"
    sh "git push -f --tags"
}
