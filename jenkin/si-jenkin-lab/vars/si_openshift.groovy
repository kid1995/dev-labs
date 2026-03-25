// Lab-adapted si_openshift.groovy
// Stubs OpenShift operations — CoPSI replaces these in the new deployment model.
// Original: combine-hint/jenkin/si-jenkin/vars/si_openshift.groovy

import de.signaliduna.TargetSegment

String getServiceNamespace(String serviceGroup, String serviceName, TargetSegment targetSegment) {
    return "${serviceGroup}-${serviceName}-${targetSegment}"
}

String getProjectUrl(String serviceGroup, String serviceName, TargetSegment targetSegment) {
    return "${serviceGroup}-${serviceName}-${targetSegment}.lab.local"
}

void login(String serviceGroup, String serviceName, TargetSegment targetSegment) {
    echo "[LAB] OpenShift login skipped — using CoPSI/ArgoCD deployment model"
}

void deployApplication(String serviceGroup, String serviceName, String imageName, TargetSegment targetSegment, Map additionalParams = [:]) {
    echo "[LAB] OpenShift deployApplication skipped — use CoPSI deployment instead"
    echo "[LAB] Would deploy ${imageName} to ${getServiceNamespace(serviceGroup, serviceName, targetSegment)}"
    echo "[LAB] Params: ${additionalParams}"
}

String filterBranchName(String name) {
    // DNS-1035 label: lower case alphanumeric + '-', max 63 chars
    def filtered = name.toLowerCase()
        .replaceAll('[^a-z0-9-]', '-')
        .replaceAll('-+', '-')
        .replaceAll('^-|-$', '')
    return filtered.length() > 63 ? filtered.substring(0, 63) : filtered
}
