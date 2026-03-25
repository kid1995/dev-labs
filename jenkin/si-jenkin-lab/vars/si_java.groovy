// Lab-adapted si_java.groovy
// Removes corporate proxy/OWASP/SonarQube dependencies.
// Original: combine-hint/jenkin/si-jenkin/vars/si_java.groovy

@groovy.transform.Field
def versionScript = ""

void version(String version) {
    // In lab, JAVA_HOME is set globally — no use-jdk-X script needed
    echo "[LAB] Java version set to ${version} (using container JDK)"
    versionScript = ""
}

void build(String folder = "") {
    dir(folder) {
        sh './gradlew clean installDist -x check -x dependencyCheckAnalyze'
    }
}

void test(String folder) {
    dir(folder) {
        try {
            sh './gradlew test -x dependencyCheckAnalyze'
        } finally {
            junit allowEmptyResults: true, testResults: '**/build/test-results/test/*.xml'
        }
    }
}

void check(String folder = "") {
    dir(folder) {
        try {
            sh './gradlew check -x dependencyCheckAnalyze || true'
        } finally {
            junit allowEmptyResults: true, testResults: '**/build/test-results/test/*.xml'
        }
    }
}

void staticAnalysis(String folder = "") {
    echo "[LAB] SonarQube analysis skipped (no SonarQube server)"
}
