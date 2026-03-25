// Lab-adapted si_jenkins.groovy
// Strips Bitbucket/RocketChat notifications, keeps structure for compatibility.
// Original: combine-hint/jenkin/si-jenkin/vars/si_jenkins.groovy

void notify(Map config, Closure buildProcess) {
    try {
        buildProcess()
        currentBuild.result = 'SUCCESS'
    } catch (Throwable exception) {
        currentBuild.result = 'FAILURE'
        throw exception
    } finally {
        echo "[LAB] Build result: ${currentBuild.result}"
    }
}

void notifyInProgress(Map config) {
    echo "[LAB] Build in progress"
}

void addLinkToDescription(String name, String url) {
    String newLine = "<a href=${url}>${name}</a>"
    if (currentBuild.description == null) {
        currentBuild.description = newLine
    } else {
        currentBuild.description += "<br />" + newLine
    }
}

boolean requestPrdDeploymentDecision(int time = 2) {
    echo "[LAB] Auto-approving PRD deployment decision"
    return true
}
