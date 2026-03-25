// Lab-adapted elpa-copsi.groovy (note: underscore for Jenkins var compatibility)
// Tests CoPSI deployment functions against Gitea.
// Original: combine-hint/jenkin/elpa-jenkin/vars/elpa-copsi.groovy
//
// NOTE: Jenkins shared library vars must use underscores, not hyphens.
// The original file is named elpa-copsi.groovy but Jenkins loads it as elpa_copsi.
// In the original Jenkinsfile it's called via implicit hyphen-to-underscore mapping.

import de.signaliduna.BitbucketRepo
import de.signaliduna.CopsiEnvironment
import groovy.transform.Field

@Field
String DEPLOY_PROJECT = "lab"

@Field
String DEPLOY_REPO = "elpa-elpa4"

@Field
String JIRA_PROJECT_PREFIX = "ELPA4"

/**
 * Auto-deploys a feature branch by creating a PR in the deploy repo.
 */
boolean autoDeployFeatBranch(String serviceName, String imageName, String targetEnv) {
    String branchName = branchNameWithoutPrefix()
    echo "Deploy config: project=${DEPLOY_PROJECT} repo=${DEPLOY_REPO} prefix=${JIRA_PROJECT_PREFIX} branch=${branchName}"
    String jiraTicket = branchName.find(/(^${JIRA_PROJECT_PREFIX}-\d+)/)

    if (jiraTicket) {
        echo "jiraTicket: ${jiraTicket}"
        Map<String, String> pullRequestAttributes = [
            title      : "Autodeploy ${serviceName} for ${jiraTicket}",
            description: "Autodeploy for Service '${serviceName}' with Feature-Branch '${branchName}' (Job: ${BUILD_NUMBER})."
        ]

        BitbucketRepo deploymentRepository = new BitbucketRepo(DEPLOY_PROJECT, DEPLOY_REPO)

        // Truncate branch name safely
        def safeBranchSuffix = branchName.length() > 32 ? branchName[0..31] : branchName

        Closure<String> autoDeployScript = {
            echo "Running clean-feature.sh and deploy-feature.sh for: ${jiraTicket}"
            sh "chmod +x ./clean-feature.sh"
            sh "chmod +x ./deploy-feature.sh"
            sh "./clean-feature.sh ${serviceName} ${jiraTicket}"
            sh "./deploy-feature.sh ${serviceName} ${jiraTicket} ${imageName}"
            sh "git add ./envs/dev"
            return "${jiraTicket}: Deploy ${serviceName} mit Image ${imageName}"
        }

        String prId = si_copsi.createChangeAsPullRequest(
            deploymentRepository,
            "autodeploy/${safeBranchSuffix}-job-${BUILD_NUMBER}",
            targetEnv,
            pullRequestAttributes,
            autoDeployScript
        )

        echo "Created PR: #${prId}"
        boolean mergeResult = si_copsi.waitForMergeChecksAndMerge(
            deploymentRepository, prId, true, true, 60
        )

        String mergeResultText = mergeResult ? "success" : "failed"
        echo "Merge result: ${mergeResultText}"
        return mergeResult
    } else {
        echo "ERROR: Branch '${branchName}' does not match JIRA pattern (${JIRA_PROJECT_PREFIX}-XXXX)."
        return false
    }
}

/**
 * Deploys a feature branch using Helm template rendered into the deploy repo.
 */
boolean deployFeature(String serviceName, List<String> helmOverrides) {
    def branchName = si_git.branchName()
    def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")

    def helmArgs = ['--values values-feature.yaml'] + helmOverrides
    def manifest = generateTemplate(serviceName, helmArgs)

    def target = "./services/${serviceName}/features/${jiraTicket}.yaml"
    Closure<String> autoDeployScript = {
        sh "mkdir -p ./services/${serviceName}/features"
        writeFile file: target, text: manifest
        sh "git add ${target}"

        // Generate kustomization.yaml for features dir
        def files = sh(
            script: "ls ./services/${serviceName}/features/ | grep -v kustomization.yaml",
            returnStdout: true
        ).trim().split('\n').collect { "- ${it}" }.join('\n')

        writeFile file: "./services/${serviceName}/features/kustomization.yaml", text: """apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
${files}
"""
        sh "git add ./services/${serviceName}/features/"
        return "${jiraTicket}: Deploy ${serviceName} feature"
    }

    return handlePR(serviceName, jiraTicket, branchName, CopsiEnvironment.nop.name(), autoDeployScript)
}

/**
 * Deploys to TST environment using Helm template.
 */
boolean deployTst(String serviceName, List<String> helmOverrides) {
    def branchName = si_git.branchName()
    def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")

    def helmArgs = ['--values values-tst.yaml'] + helmOverrides
    def manifest = generateTemplate(serviceName, helmArgs)

    def target = "./services/${serviceName}/tst.yaml"
    Closure<String> autoDeployScript = {
        sh "mkdir -p ./services/${serviceName}"
        writeFile file: target, text: manifest
        sh "git add ${target}"
        return "${jiraTicket}: Deploy ${serviceName} tst"
    }

    return handlePR(serviceName, jiraTicket, branchName, CopsiEnvironment.nop.name(), autoDeployScript)
}

/**
 * Deploys to ABN environment using Helm template.
 */
boolean deployAbn(String serviceName, List<String> helmOverrides) {
    def branchName = si_git.branchName()
    def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")

    def helmArgs = ['--values values-abn.yaml'] + helmOverrides
    def manifest = generateTemplate(serviceName, helmArgs)

    def target = "./services/${serviceName}/abn.yaml"
    Closure<String> autoDeployScript = {
        sh "mkdir -p ./services/${serviceName}"
        writeFile file: target, text: manifest
        sh "git add ${target}"
        return "${jiraTicket}: Deploy ${serviceName} abn"
    }

    return handlePR(serviceName, jiraTicket, branchName, CopsiEnvironment.nop.name(), autoDeployScript)
}

/**
 * Handles the PR creation and merge flow for CoPSI deployments.
 */
private boolean handlePR(String serviceName, String jiraTicket, String branchName, String targetEnv, Closure<String> deploymentAction) {
    echo "jiraTicket: ${jiraTicket}"
    Map<String, String> pullRequestAttributes = [
        title      : "CoPSI Deploy ${serviceName} for ${jiraTicket}",
        description: "CoPSI deployment for '${serviceName}' branch '${branchName}' (Job: ${BUILD_NUMBER})."
    ]

    BitbucketRepo deploymentRepository = new BitbucketRepo(DEPLOY_PROJECT, DEPLOY_REPO)

    // Truncate branch name safely
    def safeBranchSuffix = branchName.length() > 32 ? branchName[0..31] : branchName

    String prId = si_copsi.createChangeAsPullRequest(
        deploymentRepository,
        "autodeploy/${safeBranchSuffix}-job-${BUILD_NUMBER}",
        targetEnv,
        pullRequestAttributes,
        deploymentAction
    )

    echo "Created PR: #${prId}"
    boolean mergeResult = si_copsi.waitForMergeChecksAndMerge(
        deploymentRepository, prId, true, true, 60
    )

    String mergeResultText = mergeResult ? "success" : "failed"
    echo "CoPSI deployment ${mergeResultText}."
    return mergeResult
}

/**
 * Generates Helm template output.
 * In lab: runs helm directly (not via Docker container like production).
 */
private String generateTemplate(String serviceName, List<String> args) {
    def helmCommand = "helm template ${serviceName} ./copsi ${args.join(' ')}"
    echo "Executing: ${helmCommand}"
    return sh(script: helmCommand, returnStdout: true).trim()
}

private String branchNameWithoutPrefix() {
    return si_git.branchName().split('/').last()
}
