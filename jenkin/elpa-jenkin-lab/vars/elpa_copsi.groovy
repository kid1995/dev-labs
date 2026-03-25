import de.signaliduna.BitbucketRepo
import de.signaliduna.CopsiEnvironment
import groovy.transform.Field

@Field
String DEPLOY_PROJECT = env?.COPSI_DEPLOY_PROJECT ?: "SDASVCDEPLOY"
@Field
String DEPLOY_REPO = env?.COPSI_DEPLOY_REPO ?: "elpa-elpa4"
@Field
String JIRA_PROJECT_PREFIX = "ELPA4"

/**
 * Creates a pull request to deploy a feature branch to a specified environment.
 * The branch name must start with a JIRA ticket identifier (e.g., 'ELPA4-1234').
 *
 * @param serviceName The name of the service to be deployed.
 * @param imageName The Docker image name and tag.
 * @param targetEnv The target deployment environment (e.g., CopsiEnvironment.nop).
 * @return true if the merge was successful, false otherwise.
 */
@SuppressWarnings(["GrUnresolvedAccess", 'unused'])
boolean autoDeployFeatBranch(String serviceName, String imageName, String targetEnv) {
	String branchName = branchNameWithoutPrefix()
	echo "$DEPLOY_PROJECT and $DEPLOY_REPO and $JIRA_PROJECT_PREFIX and $branchName"
	String jiraTicket = branchName.find(/(^${JIRA_PROJECT_PREFIX}-\d+)/)

	if (jiraTicket) {
		echo "jiraTicket: $jiraTicket"
		Map<String, String> pullRequestAttributes = [
			title      : "Autodeploy ${serviceName} for ${jiraTicket}",
			description: "Autodeploy for Service '${serviceName}' with Feature-Branch '${branchName}' (Job: ${BUILD_NUMBER})."
		]

		BitbucketRepo deploymentRepository = new BitbucketRepo(DEPLOY_PROJECT, DEPLOY_REPO)
		Closure<String> autoDeployScript = {
			echo "Führe clean-feature.sh und deploy-feature.sh aus für Feature: ${jiraTicket}"
			sh "chmod +x ./clean-feature.sh"
			sh "chmod +x ./deploy-feature.sh"
			sh "./clean-feature.sh ${serviceName} ${jiraTicket}"
			sh "./deploy-feature.sh ${serviceName} ${jiraTicket} ${imageName}"
			sh "git add ./envs/dev"
			return "${jiraTicket}: Deploy ${serviceName} mit Image ${imageName}"
		}

		def safeBranch = safeBranchName(branchName)
		String prId = si_copsi.createChangeAsPullRequest(
			deploymentRepository,
			"autodeploy/${safeBranch}-job-$BUILD_NUMBER",
			targetEnv,
			pullRequestAttributes,
			autoDeployScript
		)

		echo "created PR with prId: $prId"
		boolean abortBuildOnError = true
		boolean deleteSourceBranch = true
		int timeout = 60
		boolean mergeResult = si_copsi.waitForMergeChecksAndMerge(deploymentRepository, prId, abortBuildOnError, deleteSourceBranch, timeout)

		String mergeResultText = mergeResult ? "success" : "failed"
		echo "Merge Feature-Deployments is ${mergeResultText}."
		return mergeResultText
	} else {
		echo "ERROR: Branch-Name '${branchName}' is invalid. Branch-Name should start with JIRA-Ticket-Pattern (e.g. '${JIRA_PROJECT_PREFIX}-1234')."
		return false
	}
}

boolean deployFeature(String serviceName, List<String> helmOverrides) {
	def stage = CopsiEnvironment.nop
	def branchName = si_git.branchName()
	def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")

	def helmArgs = [
		'--values values-feature.yaml',
	] + helmOverrides

	def manifest = generateTemplate(helmArgs)

	def target = "./services/${serviceName}/features/${jiraTicket}.yaml"
	Closure<String> autoDeployScript = {
		sh "mkdir -p ./services/${serviceName}/features"
		writeFile file: target, text: manifest
		sh "git add ${target}"
		def files = sh(script: "ls ./services/${serviceName}/features/", returnStdout: true)
			.trim()
			.split("\\s+")
			.findAll { it != "kustomization.yaml" }
			.collect { "- ${it}" }
			.join("\n")
		writeFile file: "./services/${serviceName}/features/kustomization.yaml", text: """\
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
${files}
"""
		sh "git add ./services/${serviceName}/features/"
		return "${jiraTicket}: Deploy ${serviceName} feature"
	}

	return handlePR(serviceName, jiraTicket, branchName, stage, autoDeployScript)
}

boolean deployTst(String serviceName, List<String> helmOverrides) {
	def stage = CopsiEnvironment.nop
	def branchName = si_git.branchName()
	def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")

	def helmArgs = [
		'--values values-tst.yaml',
	] + helmOverrides

	def manifest = generateTemplate(helmArgs)

	def target = "./services/${serviceName}/tst.yaml"
	Closure<String> autoDeployScript = {
		sh "mkdir -p ./services/${serviceName}"
		writeFile file: target, text: manifest
		sh "git add ${target}"
		return "${jiraTicket}: Deploy ${serviceName} tst"
	}

	return handlePR(serviceName, jiraTicket, branchName, stage, autoDeployScript)
}

boolean deployAbn(String serviceName, List<String> helmOverrides) {
	def stage = CopsiEnvironment.nop
	def branchName = si_git.branchName()
	def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")

	def helmArgs = [
		'--values values-abn.yaml',
	] + helmOverrides

	def manifest = generateTemplate(helmArgs)

	def target = "./services/${serviceName}/abn.yaml"
	Closure<String> autoDeployScript = {
		sh "mkdir -p ./services/${serviceName}"
		writeFile file: target, text: manifest
		sh "git add ${target}"
		return "${jiraTicket}: Deploy ${serviceName} abn"
	}

	return handlePR(serviceName, jiraTicket, branchName, stage, autoDeployScript)
}

/**
 * Handles PR creation and merge for CoPSI deployments.
 */
private boolean handlePR(String serviceName, String jiraTicket, String branchName, def targetEnv, Closure<String> deploymentAction) {
	echo "jiraTicket: $jiraTicket"
	Map<String, String> pullRequestAttributes = [
		title      : "Autodeploy ${serviceName} for ${jiraTicket}",
		description: "Autodeploy for Service '${serviceName}' with Feature-Branch '${branchName}' (Job: ${BUILD_NUMBER})."
	]

	BitbucketRepo deploymentRepository = new BitbucketRepo(DEPLOY_PROJECT, DEPLOY_REPO)
	def safeBranch = safeBranchName(branchName)
	String prId = si_copsi.createChangeAsPullRequest(
		deploymentRepository,
		"autodeploy/${safeBranch}-${serviceName}-job-$BUILD_NUMBER",
		"${targetEnv}",
		pullRequestAttributes,
		deploymentAction
	)

	echo "created PR with prId: $prId"
	boolean abortBuildOnError = true
	boolean deleteSourceBranch = true
	int timeout = 60
	boolean mergeResult = si_copsi.waitForMergeChecksAndMerge(deploymentRepository, prId, abortBuildOnError, deleteSourceBranch, timeout)

	String mergeResultText = mergeResult ? "success" : "failed"
	echo "Merge Feature-Deployments is ${mergeResultText}."
	return mergeResult
}

/**
 * Generates Helm template output.
 * Uses HELM_IMAGE env var for Docker-based helm (corporate),
 * falls back to local helm CLI (lab).
 */
private String generateTemplate(List<String> args) {
	if (env.HELM_IMAGE) {
		def dockerCommand = """
			docker run --rm \
				-v "${env.WORKSPACE}/copsi":/helm \
				${env.HELM_IMAGE} \
				template /helm ${args.join(' ')}
		""".trim()
		echo "Executing: ${dockerCommand}"
		return sh(script: dockerCommand, returnStdout: true).trim()
	} else {
		def helmCommand = "helm template release-name ./copsi ${args.join(' ')}"
		echo "Executing: ${helmCommand}"
		return sh(script: helmCommand, returnStdout: true).trim()
	}
}

/**
 * Extracts the branch name without any prefix (e.g., 'feature/', 'bugfix/' ).
 * @return The plain branch name.
 */
@SuppressWarnings('GrMethodMayBeStatic')
private String branchNameWithoutPrefix() {
	return si_git.branchName().split('/').last()
}

/**
 * Safely truncates a branch name for use in git branch refs.
 */
private String safeBranchName(String name) {
	return name.length() > 32 ? name[0..31] : name
}
