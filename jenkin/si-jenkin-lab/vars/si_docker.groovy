// Lab-adapted si_docker.groovy
// Uses local Docker socket instead of remote Docker build farm.
// Original: combine-hint/jenkin/si-jenkin/vars/si_docker.groovy

import de.signaliduna.TargetSegment

String buildImage(String appFolder, String serviceGroup, String serviceName, String imageName, TargetSegment targetSegment) {
    def commitId = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
    def imageTag = "${commitId}.${env.BUILD_NUMBER}"
    def fullImage = "lab/${serviceGroup}-${serviceName}-${targetSegment}/${imageName}:${imageTag}"

    echo "[LAB] Building Docker image: ${fullImage}"
    dir(appFolder) {
        if (fileExists('Dockerfile.lab')) {
            sh "docker build -f Dockerfile.lab -t ${fullImage} ."
        } else if (fileExists('Dockerfile')) {
            sh "docker build -t ${fullImage} ."
        } else {
            echo "[LAB] No Dockerfile found in ${appFolder}, skipping Docker build"
        }
    }
    return fullImage
}

String buildImageWithDockerfile(String appFolder, String dockerfile, String serviceGroup, String serviceName, String imageName, TargetSegment targetSegment) {
    def commitId = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
    def imageTag = "${commitId}.${env.BUILD_NUMBER}"
    def fullImage = "lab/${serviceGroup}-${serviceName}-${targetSegment}/${imageName}:${imageTag}"

    echo "[LAB] Building Docker image: ${fullImage} with ${dockerfile}"
    sh "docker build -f ${dockerfile} -t ${fullImage} ${appFolder}"
    return fullImage
}

void publishImageAbnToPrd(String serviceGroup, String serviceName, String imageName) {
    echo "[LAB] Skipping ABN->PRD image promotion (no remote registry)"
}

String execContainer(String serviceGroup, String label, String image, String command) {
    echo "[LAB] Executing container: ${image} with command: ${command}"
    return sh(returnStdout: true, script: "docker run --rm --network lab-net ${image} ${command} || echo 'container execution failed'").trim()
}
