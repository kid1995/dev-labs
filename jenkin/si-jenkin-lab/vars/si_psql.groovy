// Lab-adapted si_psql.groovy
// Stubs PostgreSQL operations for lab environment.

String normalizeSchemaName(String name) {
    return si_openshift.filterBranchName(name).replaceAll('-', '_')
}
