// Lab-adapted elpa_psql.groovy
// Stubs PostgreSQL schema management for lab environment.
// Original: combine-hint/jenkin/elpa-jenkin/vars/elpa_psql.groovy

void dropObsoleteSchemas(
    String serviceGroup,
    String postgresUser,
    String postgresPassword,
    String dbHost,
    int dbPort,
    String dbName,
    String prefix
) {
    echo "[LAB] dropObsoleteSchemas called for ${dbName} with prefix '${prefix}'"
    echo "[LAB] In lab, schemas are managed via docker compose PostgreSQL"
    echo "[LAB] Skipping schema cleanup (lab uses single schema)"
}

String normalizeSchemaName(String name) {
    return si_openshift.filterBranchName(name).replaceAll('-', '_')
}
