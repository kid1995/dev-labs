# Dev-Labs — Local DevOps Lab

## Lab Overview

This is a self-contained local DevOps lab that runs 2 real Spring Boot backends (hint, dlt-manager),
an Angular frontend, and supporting infrastructure via Docker Compose. It simulates a corporate
Signal Iduna development environment (Bitbucket, Jenkins, Keycloak OIDC, Kafka, PostgreSQL)
using lightweight local replacements. Everything runs on `docker compose up -d`.

## Running Services (9 containers)

| Service | Container | Host Port(s) | Credentials / Notes |
|---|---|---|---|
| Gitea (git server) | lab-gitea | :3000, :2222 (SSH) | labadmin / labadmin — repos: hint-backend, dlt-manager, design-system |
| Jenkins | lab-jenkins | :8888 | No auth (setup wizard disabled) — 2 pipeline jobs |
| Keycloak (OIDC) | lab-keycloak | :8180 | admin / admin — "lab" realm, users: admin(S000325), testuser/test(U116330) |
| PostgreSQL | lab-postgres | :5432 | db_user / db_password — databases: `hint`, `dltmanager` |
| Kafka (KRaft) | lab-kafka | :9092 (internal) / :19092 (host) | PLAINTEXT, no auth, single node |
| Hint Backend | lab-hint-backend | :8080 (API) / :8081 (mgmt) | Swagger: http://localhost:8080/api/docs/rest |
| DLT Backend | lab-dlt-backend | :8082 (API) / :8083 (mgmt) | Swagger: http://localhost:8082/api/docs/rest |
| DLT Frontend | lab-dlt-frontend | :4200 | Angular SPA, proxies to DLT backend |
| Storybook | lab-storybook | :4201 | Signal Iduna design-system component library |
| Lab Guide | lab-guide | :4202 | Documentation site (nginx serving static HTML) |

Kafka listeners: `PLAINTEXT://kafka:9092` for inter-container traffic, `EXTERNAL://localhost:19092` for host access.

## Directory Structure

```
dev-labs/
├── src/
│   ├── hint-backend/        # Cloned hint project (build.gradle modified for lab)
│   ├── dlt-manager/         # Cloned dlt-manager (gitignore + login template modified)
│   │   ├── backend/         # Spring Boot backend module
│   │   └── frontend/        # Angular frontend module
│   └── design-system/       # Cloned design system (Storybook pre-built in dist/)
├── docker/
│   ├── hint-backend.Dockerfile
│   ├── dlt-backend.Dockerfile
│   └── dlt-frontend.Dockerfile
├── config/
│   ├── postgres/            # init-databases.sql (creates hint + dltmanager DBs)
│   ├── keycloak/            # lab-realm.json (pre-configured realm export)
│   └── bruno/               # API collection for Bruno HTTP client
├── projects/
│   ├── hint-backend/        # Jenkins pipeline project config
│   ├── dlt-backend/
│   └── dlt-frontend/
├── k8s/                     # Kubernetes manifests (apps-dev, apps-staging, argocd, gateway, istio, observability)
├── helm/                    # Helm charts (backend, frontend)
├── scripts/
│   ├── bootstrap.sh         # Full rebuild: libs -> backends -> frontend -> Docker images -> compose up
│   ├── prepare-m2-cache.sh  # Copy mavenLocal to Jenkins container
│   ├── setup-k8s.sh         # Kubernetes setup
│   ├── test-frontend.mjs    # Headless Playwright test for DLT frontend
│   └── test-login.mjs       # Headless Playwright login flow test
├── docs/lab-guide/          # Static HTML served at :4202
├── analysis/                # Dependency analysis JSON files
├── docker-compose.yml       # All 9+ services
└── CLAUDE.md                # This file
```

## Build Commands

### Prerequisites

```bash
export JAVA_HOME="/Users/thekietdang/Library/Java/JavaVirtualMachines/temurin-21.0.8/Contents/Home"
```

Internal libraries MUST be published to mavenLocal before building backends:
- `jwt-adapter` 2.5.0 and 2.5.1-SNAPSHOT — source at `~/Downloads/github-buffer/java_libs/jwt-adapter`
- `elpa4-model` 1.1.1 and 1.1.1-SNAPSHOT — source at `~/Downloads/github-buffer/java_libs/elpa4-shared-lib/elpa4-model`

```bash
# Publish libs (run once)
cd ~/Downloads/github-buffer/java_libs/jwt-adapter
./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze -Pversion=2.5.0 --no-daemon
./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze --no-daemon

cd ~/Downloads/github-buffer/java_libs/elpa4-shared-lib/elpa4-model
./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze -Pversion=1.1.1 --no-daemon
./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze --no-daemon
```

### Build Backends

```bash
# Hint backend
cd src/hint-backend
./gradlew build -x check -x dependencyCheckAnalyze --no-daemon
./gradlew :hint-service:installDist --no-daemon

# DLT Manager backend
cd src/dlt-manager
./gradlew build -x check -x dependencyCheckAnalyze -x rewriteRun -x rewriteDryRun --no-daemon
./gradlew :backend:installDist --no-daemon
```

### Build Frontend

```bash
cd src/dlt-manager/frontend
npx ng build --configuration production
```

### Build Docker Images

```bash
# From project root
cd src/hint-backend && docker build -f ../../docker/hint-backend.Dockerfile -t lab/hint-backend:latest .
cd src/dlt-manager && docker build -f ../../docker/dlt-backend.Dockerfile -t lab/dlt-backend:latest .
cd src/dlt-manager/frontend && docker build -f ../../../docker/dlt-frontend.Dockerfile -t lab/dlt-frontend:latest .
```

### Full Bootstrap (everything at once)

```bash
./scripts/bootstrap.sh
```

### Start / Restart Services

```bash
docker compose up -d          # Start all
docker compose restart <svc>  # Restart one service
docker compose down            # Stop all (data preserved in volumes)
docker compose down -v         # Stop all and destroy volumes
```

## Critical Rules

1. **NEVER modify files in `combine-hint/` or `dlt-manager/` originals** — only modify clones under `src/`.

2. **ALWAYS test frontend changes with headless browser** after rebuilding:
   ```bash
   node scripts/test-frontend.mjs          # default: http://localhost:4200
   node scripts/test-login.mjs             # tests OIDC login flow
   ```

3. **si-button requires a native `<button>` element as slotted content** — always check Storybook at :4201 before modifying design-system components.

4. **After Jenkins container restart**, you must:
   - Re-copy mavenLocal dependencies: `./scripts/prepare-m2-cache.sh`
   - Re-install Docker CLI inside the container: `docker exec lab-jenkins apt-get update && docker exec lab-jenkins apt-get install -y docker.io`

5. **Kafka listener mapping**:
   - Inter-container (from backends): `kafka:9092` (PLAINTEXT)
   - From host machine: `localhost:19092` (EXTERNAL)
   - Do NOT use `localhost:9092` from inside containers or `kafka:9092` from host.

6. **Gradle flags** — always exclude these tasks to avoid failures:
   - hint: `-x check -x dependencyCheckAnalyze`
   - dlt-manager: `-x check -x dependencyCheckAnalyze -x rewriteRun -x rewriteDryRun`

## Key Simulations

This lab replaces corporate infrastructure with local equivalents:

- **Bitbucket DC** -> Gitea (same git push/pull workflow)
- **Corporate Jenkins** -> Jenkins LTS with JDK 21 (no shared libs)
- **Corporate OIDC (employee.login.int.signal-iduna.org)** -> Keycloak with "lab" realm
- **Managed PostgreSQL** -> Single PostgreSQL container with both DBs
- **Multi-node Kafka (SASL_PLAINTEXT + OAUTHBEARER)** -> Single-node KRaft (PLAINTEXT)
- **OpenShift deployments** -> Docker Compose / Kubernetes manifests in k8s/
- **Artifactory/Nexus** -> mavenLocal for Java libs, local npm for frontend

See the full lab guide at http://localhost:4202 for detailed simulation mappings.

## Known Issues

- **Jenkins tests are UNSTABLE**: Testcontainers-based integration tests require Docker-in-Docker networking that does not work reliably inside the Jenkins container. Use `-x check` to skip.
- **Frontend npm install needs Verdaccio**: `@signal-iduna/*` packages come from a private registry. The frontend build in `src/dlt-manager/frontend` already has `node_modules` — avoid running `npm install` unless you have Verdaccio configured.
- **Keycloak startup is slow**: The health check has `start_period: 60s` and may take up to 2 minutes on first boot. Backends that depend on it will retry.
- **Storybook is pre-built**: The static build lives at `src/design-system/dist/storybook/storybook-host`. To rebuild, you would need the full design-system workspace with its dependencies.

## Useful URLs

| URL | Purpose |
|---|---|
| http://localhost:8080/api/docs/rest | Hint Swagger UI |
| http://localhost:8080/api/hints | Hint API |
| http://localhost:8081/health | Hint health check |
| http://localhost:8082/api/docs/rest | DLT Manager Swagger UI |
| http://localhost:8082/api/events/overview | DLT events API |
| http://localhost:8083/health | DLT health check |
| http://localhost:4200 | DLT Frontend (Angular) |
| http://localhost:4201 | Storybook (design system) |
| http://localhost:4202 | Lab Guide documentation |
| http://localhost:3000 | Gitea (labadmin/labadmin) |
| http://localhost:8888 | Jenkins (no auth) |
| http://localhost:8180 | Keycloak (admin/admin) |
