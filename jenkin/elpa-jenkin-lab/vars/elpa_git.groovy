import groovy.transform.Field

@Field
String JIRA_PROJECT_PREFIX = "ELPA4"

/**
 * Verifies that a JIRA ticket ID exists in the branch name or commit message.
 * Fails the build early (before Docker build / Helm render) if missing.
 * Warns if branch and commit reference different tickets.
 *
 * Call this at the start of your Jenkinsfile, after checkout:
 *   elpa_git.verifyJiraTicket()
 *
 * @return The JIRA ticket ID found (e.g., 'ELPA4-1234')
 */
String verifyJiraTicket() {
	def branch = si_git.branchName()
	// Only first line — commit messages can be multiline, ticket should be in the subject
	def commitSubject = si_git.lastCommitMessage()?.split('\n')?.getAt(0) ?: ''
	def ticketPattern = /(?i)(${JIRA_PROJECT_PREFIX}-\d+)/

	def branchMatch = (branch =~ ticketPattern)
	def commitMatch = (commitSubject =~ ticketPattern)
	def branchTicket = branchMatch ? branchMatch[0][1].toUpperCase() : null
	def commitTicket = commitMatch ? commitMatch[0][1].toUpperCase() : null

	echo "Branch: ${branch} -> ${branchTicket ?: 'NO TICKET'}"
	echo "Commit: ${commitSubject} -> ${commitTicket ?: 'NO TICKET'}"

	if (!branchTicket && !commitTicket) {
		error "VERIFY FAILED: branch name and commit message do not contain JIRA TICKET. Fix: git checkout -b feature/${JIRA_PROJECT_PREFIX}-XXXX-description"
	}
	if (branchTicket && commitTicket && branchTicket != commitTicket) {
		echo "VERIFY WARNING: jira ticket in branch name (${branchTicket}) and commit message (${commitTicket}) are not equal"
	}

	def ticket = branchTicket ?: commitTicket
	echo "VERIFY SUCCESS: Jira Ticket ${ticket} existed"
	return ticket
}
