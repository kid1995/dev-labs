// Lab-adapted si_its360.groovy
// Stubs ITS360 release notification.

void notifyReleaseDeployment(String serviceGroup, String serviceName, Closure deployAction) {
    echo "[LAB] ITS360 release notification skipped"
    deployAction()
}
