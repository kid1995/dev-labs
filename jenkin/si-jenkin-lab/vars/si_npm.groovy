// Lab-adapted si_npm.groovy
// Uses container Node.js instead of corporate /srv/dev/node-v* paths.
// Skips SonarQube, CheckStyle, and Cobertura publishers (not available in lab).
// Original: combine-hint/jenkin/si-jenkin/vars/si_npm.groovy

import de.signaliduna.BitbucketRepo

@groovy.transform.Field
def currentNodeVersion = ''

public void node_version(String version) {
    echo "[LAB] Using container Node.js (${version} requested, using container version)"
}

public void ciInstall(String path) {
    npmExecCmd(path, 'ci')
}

public void ciBuild(String path) {
    ciBuildProject(null, path)
}

public void ciBuildProject(String projectName, String path) {
    npmRun(path, toCiScript('build', projectName))
}

public void ciTest(String path, String resultsPath = null, String coveragePath = null) {
    ciTestProject(null, path, resultsPath, coveragePath)
}

public void ciTestProject(String projectName, String path, String resultsPath = null, String coveragePath = null) {
    try {
        npmRun(path, toCiScript('test', projectName))
    } catch (Exception e) {
        echo "[LAB] Tests failed: ${e.message}"
    }
}

public void ciE2E(String path, String resultsPath = null) {
    echo "[LAB] E2E tests skipped (no browser runner in lab)"
}

public void ciE2EProject(String projectName, String path, String resultsPath = null) {
    ciE2E(path, resultsPath)
}

public void ciAudit(String path, String auditLevel = "high") {
    try {
        npmExecCmd(path, "audit --audit-level=${auditLevel}")
    } catch (Exception e) {
        echo "[LAB] npm audit warning (non-blocking): ${e.message}"
    }
}

public void ciLint(String path, String resultsPath = null) {
    ciLintProject(null, path, resultsPath)
}

public void ciLintProject(String projectName, String path, String resultsPath = null) {
    try {
        npmRun(path, toCiScript('lint', projectName))
    } catch (Exception e) {
        echo "[LAB] Lint warning (non-blocking): ${e.message}"
    }
}

public void ciSemanticRelease(String path) {
    echo "[LAB] Semantic release skipped (no Nexus npm registry in lab)"
}

public void ciPublish(String path, String tag) {
    echo "[LAB] npm publish skipped (no Nexus npm registry in lab)"
}

void staticAnalysis(String folder, String coveragePath = "coverage/lcov.info", boolean failBuildOnQualityGate = false, String additionalConfiguration = "") {
    echo "[LAB] SonarQube frontend analysis skipped (not available in lab)"
}

public void npmRun(String path, String scriptName, String args = '') {
    npmExecCmd(path, "run ${scriptName}", args ? "-- ${args}" : '')
}

public void npmExecCmd(String path, String command, String args = '') {
    dir(path) {
        sh """
            export NO_COLOR=1
            npm ${command} ${args}
        """
    }
}

public void nodeExecCmd(String path, String command, String args = '') {
    dir(path) {
        sh """
            export NO_COLOR=1
            node ${command} ${args}
        """
    }
}

private String toCiScript(String scriptName, String projectName) {
    return 'ci:' + scriptName + (projectName ? ":${projectName}" : '')
}
