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

boolean deployFeature(String serviceName, String schemaPrefix, List<String> helmOverrides) {
	def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")
	def branchName = branchNameWithoutPrefix()
	def stageName = "feat-${branchName}".toLowerCase()
	def schemaName = si_psql.normalizeSchemaName("${schemaPrefix}${si_git.branchName()}")
	def dir = "./services/${serviceName}/features"

	def manifest = generateTemplate([
		'--values values-feature.yaml',
		"--set stage=${stageName}",
		"--set postgres.schema=${schemaName}",
	] + helmOverrides)

	return deployManifest(serviceName, jiraTicket, "feature", manifest, "${dir}/${stageName}.yaml") {
		rebuildKustomization(dir)
		sh "git add ${dir}/"
	}
}

boolean deployTst(String serviceName, List<String> helmOverrides) {
	def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")
	def manifest = generateTemplate(['--values values-tst.yaml'] + helmOverrides)

	return deployManifest(serviceName, jiraTicket, "tst", manifest, "./services/${serviceName}/tst.yaml")
}

boolean deployLabTst(String serviceName, String imageTag, List<String> helmOverrides) {
	def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")
	def manifest = generateTemplate(['--values values-lab-tst.yaml', "--set image.tag=${imageTag}"] + helmOverrides)

	return deployManifest(serviceName, jiraTicket, "tst", manifest, "./services/${serviceName}/tst.yaml")
}

/**
 * Deploys to ABN and cleans up obsolete feature deployments.
 *
 * When a feature branch merges into develop, the branch gets deleted.
 * This function detects feature deployment files whose branch no longer exists
 * in git remote, removes them, and deploys ABN — all in one PR so ArgoCD
 * removes stale features and deploys ABN atomically.
 */
boolean deployAbn(String serviceName, List<String> helmOverrides) {
	def jiraTicket = si_git.extractJiraReferenceFromCommit("ELPA4")
	def manifest = generateTemplate(['--values values-abn.yaml'] + helmOverrides)
	def featuresDir = "./services/${serviceName}/features"
	def abnTarget = "./services/${serviceName}/abn.yaml"

	def branchName = si_git.branchName()

	Closure<String> autoDeployScript = {
		// 1. Write ABN manifest
		// "./services/hint/abn.yaml" → "./services/hint"
		sh "mkdir -p ${abnTarget.substring(0, abnTarget.lastIndexOf('/'))}"
		writeFile file: abnTarget, text: manifest
		sh "git add ${abnTarget}"

		// 2. Clean up obsolete feature deployments
		cleanupObsoleteFeatures(serviceName, featuresDir)

		return "${jiraTicket}: Deploy ${serviceName} abn + cleanup features"
	}

	return handlePR(serviceName, jiraTicket, branchName, CopsiEnvironment.nop, autoDeployScript)
}

/**
 * Removes feature deployment files whose branch no longer exists in git remote.
 *
 * Compares feature YAML filenames (e.g., ELPA4-1234.yaml) against existing
 * remote branches. If no branch contains that ticket, the file is obsolete.
 *
 * When all features are removed, the features/ directory and its kustomization.yaml
 * are also removed to avoid an empty resources list that breaks kustomize.
 */
private void cleanupObsoleteFeatures(String serviceName, String featuresDir) {
	if (!fileExists(featuresDir)) {
		echo "No features directory — nothing to clean"
		return
	}

	// Get remote branches from the CODE repo (not the deploy repo we're inside).
	// WORKSPACE points to the Jenkins workspace where the code repo is checked out.
	def remoteBranches = sh(
		script: "git -C '${env.WORKSPACE}' ls-remote --heads origin 2>/dev/null || true",
		returnStdout: true
	).trim().split('\n').collect { it.replaceAll(/.*refs\/heads\//, '') }.findAll { it }

	echo "Remote branches: ${remoteBranches.size()}"

	// Get all feature deployment files
	def featureFiles = sh(script: "ls ${featuresDir}/*.yaml 2>/dev/null || true", returnStdout: true)
		.trim()
		.split("\\s+")
		// "./services/hint/features/feat-elpa4-123.yaml" → "feat-elpa4-123.yaml"
		.collect { it.substring(it.lastIndexOf('/') + 1) }
		.findAll { it && it != "kustomization.yaml" }

	if (!featureFiles) {
		echo "No feature deployments found"
		return
	}

	// Check each feature file: does any remote branch still contain that ticket?
	def obsolete = []
	featureFiles.each { fileName ->
		def ticket = fileName.replace('.yaml', '').toUpperCase()
		def branchExists = remoteBranches.any { branch ->
			branch.toUpperCase().contains(ticket)
		}
		if (!branchExists) {
			obsolete << fileName
			echo "Obsolete: ${fileName} (no branch with ${ticket})"
		}
	}

	if (!obsolete) {
		echo "All ${featureFiles.size()} feature deployments still have active branches"
		return
	}

	// Remove obsolete files
	obsolete.each { fileName ->
		sh "rm -f ${featuresDir}/${fileName}"
		echo "Removed: ${featuresDir}/${fileName}"
	}
	sh "git add ${featuresDir}/"

	// Check if any features remain
	def remaining = featureFiles - obsolete

	if (remaining) {
		rebuildKustomization(featuresDir)
	} else {
		// No features left — write an empty kustomization so the parent
		// reference to features/ stays valid and kustomize build won't fail.
		writeFile file: "${featuresDir}/kustomization.yaml", text: """\
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: []
"""
	}
	sh "git add ${featuresDir}/"

	echo "Cleanup: removed ${obsolete.size()} obsolete, ${remaining.size()} remaining"
}

/**
 * Removes 'features' or 'features/' entry from parent kustomization.yaml resources list.
 * Prevents kustomize build failure when features/ directory no longer exists.
 */
/**
 * Writes a rendered manifest to the deploy repo and creates a merge PR.
 * Optional afterWrite closure for extra steps (e.g., rebuilding kustomization.yaml).
 */
private boolean deployManifest(String serviceName, String jiraTicket, String env, String manifest, String target, Closure afterWrite = null) {
	def branchName = si_git.branchName()

	Closure<String> autoDeployScript = {
		// "./services/hint/features/feat-elpa4-123.yaml" → "./services/hint/features"
		sh "mkdir -p ${target.substring(0, target.lastIndexOf('/'))}"
		writeFile file: target, text: manifest
		sh "git add ${target}"
		if (afterWrite) afterWrite()
		return "${jiraTicket}: Deploy ${serviceName} ${env}"
	}

	return handlePR(serviceName, jiraTicket, branchName, CopsiEnvironment.nop, autoDeployScript)
}

/**
 * Rebuilds kustomization.yaml from all YAML files in a directory.
 */
private void rebuildKustomization(String dir) {
	sh "rm -f ${dir}/kustomization.yaml"
	sh "cd ${dir} && /tools/kustomize create --autodetect"
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
 *
 * Strategy:
 *   1. If helm CLI is installed locally on Jenkins → use it directly
 *   2. Otherwise → use si_docker.withContainer to run helm via Docker
 *      (same pattern as corporate Jenkins, uses HELM_IMAGE or default alpine/helm:3)
 *
 * When running via Docker (withContainer), the workspace is copied into the container
 * and helm runs from /workspace — values files are relative to copsi/ chart.
 * When running locally, same layout — values files need copsi/ prefix.
 */
private String generateTemplate(List<String> args) {
	def serviceGroup = env.COPSI_SERVICE_GROUP ?: "elpa"
	def helmAvailable = sh(script: 'command -v helm > /dev/null 2>&1', returnStatus: true) == 0
	def helmCommand = "cd copsi && helm template ${args.join(' ')} ."

	if (helmAvailable) {
		echo "Executing: ${helmCommand}"
		return sh(script: helmCommand, returnStdout: true).trim()
	} else {
		def helmImage = env.HELM_IMAGE ?: 'registry:5000/toolimages-alpine-helm-kustomize:3'
		def result = ""
		si_docker.withContainer(serviceGroup, helmImage) { runCmd ->
			echo "Executing: ${helmCommand}"
			result = runCmd(helmCommand)
		}
		return result.trim()
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
