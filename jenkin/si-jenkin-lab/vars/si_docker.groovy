// Lab-adapted si_docker.groovy
// Uses local Docker socket + lab registry (registry:5000) instead of remote Docker build farm.
// Original: combine-hint/jenkin/si-jenkin/vars/si_docker.groovy
//
// Registry mapping:
//   Corporate: dev.docker.system.local / prod.docker.system.local (Nexus)
//   Lab:       registry:5000 (from containers) / localhost:5050 (from host)

import de.signaliduna.TargetSegment
import groovy.transform.Field

@Field
String LAB_REGISTRY = "registry:5000"

String buildImage(String appFolder, String serviceGroup, String serviceName, String imageName, TargetSegment targetSegment) {
    def commitId = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
    def imageTag = "${commitId}.${env.BUILD_NUMBER}"
    def localTag = "lab/${serviceGroup}-${serviceName}-${targetSegment}/${imageName}:${imageTag}"
    def registryTag = "${LAB_REGISTRY}/${serviceGroup}-${serviceName}-${targetSegment}/${imageName}:${imageTag}"

    echo "[LAB] Building Docker image: ${registryTag}"
    dir(appFolder) {
        if (fileExists('Dockerfile.lab')) {
            sh "docker build -f Dockerfile.lab -t ${localTag} ."
        } else if (fileExists('Dockerfile')) {
            sh "docker build -t ${localTag} ."
        } else {
            echo "[LAB] No Dockerfile found in ${appFolder}, skipping Docker build"
            return registryTag
        }
    }

    // Tag and push to lab registry
    sh "docker tag ${localTag} ${registryTag}"
    sh "docker push ${registryTag}"
    echo "[LAB] Pushed: ${registryTag}"

    return registryTag
}

String buildImageWithDockerfile(String appFolder, String dockerfile, String serviceGroup, String serviceName, String imageName, TargetSegment targetSegment) {
    def commitId = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
    def imageTag = "${commitId}.${env.BUILD_NUMBER}"
    def localTag = "lab/${serviceGroup}-${serviceName}-${targetSegment}/${imageName}:${imageTag}"
    def registryTag = "${LAB_REGISTRY}/${serviceGroup}-${serviceName}-${targetSegment}/${imageName}:${imageTag}"

    echo "[LAB] Building Docker image: ${registryTag} with ${dockerfile}"
    sh "docker build -f ${dockerfile} -t ${localTag} ${appFolder}"
    sh "docker tag ${localTag} ${registryTag}"
    sh "docker push ${registryTag}"
    echo "[LAB] Pushed: ${registryTag}"

    return registryTag
}

void publishImageAbnToPrd(String serviceGroup, String serviceName, String imageName) {
    // In lab, ABN and PRD use the same registry — just retag
    echo "[LAB] Promoting ABN image to PRD (same registry, retag only)"
    def abnImage = "${LAB_REGISTRY}/${serviceGroup}-${serviceName}-abn/${imageName}"
    def prdImage = "${LAB_REGISTRY}/${serviceGroup}-${serviceName}-prd/${imageName}"

    // Get latest ABN tag
    def latestTag = sh(
        script: "curl -sf http://${LAB_REGISTRY}/v2/${serviceGroup}-${serviceName}-abn/${imageName}/tags/list | python3 -c \"import sys,json; tags=json.load(sys.stdin).get('tags',[]); print(tags[-1] if tags else 'latest')\"",
        returnStdout: true
    ).trim()

    sh "docker pull ${abnImage}:${latestTag} || true"
    sh "docker tag ${abnImage}:${latestTag} ${prdImage}:${latestTag} || true"
    sh "docker push ${prdImage}:${latestTag} || true"
}

String execContainer(String serviceGroup, String label, String image, String command) {
    echo "[LAB] Executing container: ${image}"
    return sh(returnStdout: true, script: "docker run --rm --network lab-net ${image} ${command} || echo 'container execution failed'").trim()
}
