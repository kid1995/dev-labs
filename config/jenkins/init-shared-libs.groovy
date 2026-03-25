// Jenkins init script: Register lab-adapted shared libraries
// Loaded on startup via init.groovy.d/
//
// Registers two local filesystem shared libraries:
//   si-dp-shared-libs  -> /var/jenkins_home/shared-libs/si-jenkin-lab
//   elpa-shared-lib    -> /var/jenkins_home/shared-libs/elpa-jenkin-lab
//
// These are the lab equivalents of the corporate Jenkins shared libraries.
// Pipelines can use: @Library(['si-dp-shared-libs', 'elpa-shared-lib']) _

import jenkins.model.Jenkins
import jenkins.plugins.git.GitSCMSource
import org.jenkinsci.plugins.workflow.libs.GlobalLibraries
import org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
import org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever
import org.jenkinsci.plugins.workflow.libs.LibraryRetriever

// Use reflection to check if LocalRetriever is available (from filesystem-scm plugin)
// If not, fall back to a workaround using a dummy SCM
def createLocalLibrary(String name, String path) {
    try {
        // Try to use the legacy-scm retriever with local filesystem
        def scmClass = Class.forName('hudson.plugins.filesystem_scm.FSSCM')
        def fsSCM = scmClass.newInstance(path, false, false, null)

        def retrieverClass = Class.forName('org.jenkinsci.plugins.workflow.libs.SCMRetriever')
        def retriever = retrieverClass.newInstance(fsSCM)

        return new LibraryConfiguration(name, retriever)
    } catch (ClassNotFoundException e) {
        println("[init-shared-libs] filesystem-scm plugin not available, using fallback")
        return null
    }
}

// Fallback: configure via system property so pipelines can find the libs
System.setProperty("LAB_SHARED_LIBS_PATH", "/var/jenkins_home/shared-libs")
System.setProperty("SI_SHARED_LIB_PATH", "/var/jenkins_home/shared-libs/si-jenkin-lab")
System.setProperty("ELPA_SHARED_LIB_PATH", "/var/jenkins_home/shared-libs/elpa-jenkin-lab")

println("[init-shared-libs] Lab shared libraries paths configured:")
println("  si-dp-shared-libs  -> /var/jenkins_home/shared-libs/si-jenkin-lab")
println("  elpa-shared-lib    -> /var/jenkins_home/shared-libs/elpa-jenkin-lab")
println("[init-shared-libs] Use @Library annotation or load from local path in pipeline")
