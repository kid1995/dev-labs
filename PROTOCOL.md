# PROTOCOL.md — DevOps Lab Build Protocol

**Date**: 2026-03-21
**Operator**: Claude Code (Opus 4.6)

---

## Summary

Built a fully local DevOps lab from three enterprise applications:

- **hint-backend** — Spring Boot 4.0 backend (Java 21, Gradle, PostgreSQL + Kafka)
- **dlt-manager backend** — Spring Boot 4.0 backend (Java 21, Gradle, PostgreSQL + Kafka)
- **dlt-manager frontend** — Angular 21 SPA (Node 22, nginx serving, OIDC login)

The lab replaces all internal corporate infrastructure (Bitbucket DC, Nexus, OpenShift, corporate OIDC) with local open-source equivalents (Gitea, mavenLocal, Docker Compose, Keycloak). Source code was cloned into `src/` — original repositories were never modified after an early mistake (Error #3). Nine Docker containers provide the full stack: 3 applications + 3 infrastructure services + 3 tooling services.

---

## Phase 0: Project Analysis

**Actions:**
1. Created directory structure: `projects/`, `analysis/`, `docs/`, `config/`, `scripts/`, `helm/`, `k8s/`, `src/`
2. Created symlinks in `projects/` pointing to `src/` clones
3. Analyzed both projects (build systems, dependencies, infrastructure needs)
4. Generated analysis JSON files:
   - `analysis/hint-backend-deps.json`
   - `analysis/dlt-backend-deps.json`
   - `analysis/dlt-frontend-deps.json`
   - `analysis/infra-manifest.json`

**Findings:**
- Both backends: Java 21, Spring Boot 4.0.3, Gradle, PostgreSQL + Kafka
- Frontend: Angular 21.2.4, Node 22, nginx serving
- Both backends depend on internal Nexus libraries (`jwt-adapter`, `elpa4-model`)
- Frontend depends on internal npm packages (`@signal-iduna/ui`, `@signal-iduna/ui-angular`)
- All three use OAuth2/OIDC authentication against internal IdP

**Errors:** None

---

## Phase 1: Fix Hint Backend Build

**Actions:**
1. Built `jwt-adapter` library from source and published to mavenLocal (version 2.5.1-SNAPSHOT)
2. Built `elpa4-model` library from source and published to mavenLocal (version 1.1.1-SNAPSHOT)
3. Attempted `./gradlew build -x check` for hint project

**Error #1** encountered and fixed (see Error Log).

4. Re-ran build — **BUILD SUCCESSFUL** (20 tasks, 8s)
5. Ran `./gradlew :hint-service:installDist` — **BUILD SUCCESSFUL**

---

## Phase 2: Fix DLT-Manager Backend Build

**Actions:**
1. Attempted `./gradlew build -x check -x dependencyCheckAnalyze -x rewriteRun`

**Error #2** encountered and fixed (see Error Log).

2. Re-ran build — **BUILD SUCCESSFUL** (16 tasks, 13s)
3. Ran `./gradlew :backend:installDist` — **BUILD SUCCESSFUL**

---

## Phase 3: Fix DLT-Manager Frontend Build

**Actions:**
1. Verified `@signal-iduna/ui` and `@signal-iduna/ui-angular` packages exist in `node_modules/` (previously installed via local Verdaccio at `localhost:4873`)
2. Ran `npx ng build --configuration production`

**Warnings (non-blocking):**
- Sass `@import` deprecation warning (Dart Sass 3.0.0) in `login.component.scss`
- Bundle size exceeded budget by 93.63 kB (2.09 MB vs 2.00 MB limit)

**Result:** **BUILD SUCCESSFUL** (2.979 seconds)
- Output: `dist/dltmanager-ui/browser/`

---

## Phase 4: Create Dockerfiles

**Actions:**
1. Created pre-built Dockerfiles in `docker/`:
   - `docker/hint-backend.Dockerfile` — eclipse-temurin:21-jre-alpine
   - `docker/dlt-backend.Dockerfile` — eclipse-temurin:21-jre-alpine
   - `docker/dlt-frontend.Dockerfile` — nginx:1-alpine with SPA routing
2. Created full multi-stage Dockerfiles in `src/*/Dockerfile.lab` (build from source inside Docker)
3. Frontend Dockerfile includes runtime env variable substitution via `sed` in nginx entrypoint script

**Error #3** (modifying original source) discovered and fixed during this phase.

---

## Phase 5: Kubernetes Manifests

**Actions:**
1. Created namespace definitions: `k8s/namespaces.yaml` (apps-dev, apps-staging, monitoring)
2. Created infrastructure:
   - `k8s/apps-dev/infra/postgres.yaml` — PostgreSQL 15 with init scripts
   - `k8s/apps-dev/infra/kafka.yaml` — Apache Kafka 3.7 (KRaft) + topic init job
   - `k8s/apps-dev/infra/keycloak.yaml` — Keycloak 24 for local OIDC
   - `k8s/apps-dev/infra/secrets.yaml` — All secrets
3. Created application deployments:
   - `k8s/apps-dev/backend/hint-deployment.yaml` — ConfigMap + Deployment + Service
   - `k8s/apps-dev/backend/dlt-deployment.yaml` — ConfigMap + Deployment + Service
   - `k8s/apps-dev/frontend/dlt-frontend-deployment.yaml` — ConfigMap + Deployment + Service
4. Created Istio resources:
   - `k8s/gateway/istio-gateway.yaml` — Gateway for *.lab.local hosts
   - `k8s/gateway/virtual-services.yaml` — Routing for hint, dlt, dlt-ui, keycloak
   - `k8s/gateway/destination-rules.yaml` — Connection pool settings

---

## Phase 6: Docker Compose, Scripts & Bruno Collection

**Actions:**
1. Created `docker-compose.yml` with all 9 services
2. Created `config/postgres/init-databases.sql` — Creates hint + dltmanager databases with schemas
3. Created `config/keycloak/lab-realm.json` — Realm with users and OIDC client
4. Created `scripts/bootstrap.sh` — Full build + docker compose up
5. Created `scripts/setup-k8s.sh` — k3d cluster + Istio + deploy all K8s manifests
6. Created `scripts/prepare-m2-cache.sh` — Copies mavenLocal deps for multi-stage Docker builds
7. Created Bruno API collection in `config/bruno/lab-api/`
8. Created `.env.example`

---

## Phase 7: Bitbucket DC / GitLab CE / Gitea — Git Server Selection

**Goal:** Replace internal Bitbucket DC (`git.system.local`) with a local git server.

### Attempt 1: Bitbucket Data Center
- Required Atlassian license (even trial needs registration)
- Minimum 3 GB RAM for a single node
- **Error #6** (HV000149 validation error) made it unusable — abandoned

### Attempt 2: GitLab CE
- **Error #7** — wrong platform image (amd64 on arm64 Mac), OOM with 4 GB+ RAM, password rejection on first login
- Abandoned due to excessive resource requirements

### Attempt 3: Gitea (chosen)
- Lightweight (50 MB RAM), no license required, SQLite storage
- Same git push/pull workflow as Bitbucket
- Configured with `INSTALL_LOCK=true` for zero-setup start
- Runs at `http://localhost:3000`

---

## Phase 8: Jenkins CI/CD

**Actions:**
1. Added Jenkins LTS (JDK 21) container to `docker-compose.yml` at port 8888
2. Created `Jenkinsfile.lab` for both projects:
   - `src/hint-backend/Jenkinsfile.lab` — 6 stages: Checkout, Build, Verify, Analyze, Docker, Deploy
   - `src/dlt-manager/Jenkinsfile.lab` — 6 stages: same pattern, backend-only (frontend skipped)
3. Replaced all internal shared library calls (`si_git`, `si_java`, `si_npm`, `si_docker`, `si_openshift`, `si_jenkins`) with standard declarative pipeline steps
4. Jenkins runs as root with Docker socket mounted for image builds
5. Setup wizard disabled via `JAVA_OPTS`

---

## Phase 9: Frontend Fixes (Errors #8, #9, #10, #11, #12)

**Goal:** Get the DLT-Manager Angular frontend fully working in Docker.

### Error #8: Unexpected token 'export' in scripts bundle
- Angular CLI output the design system's scripts bundle with `export` statements but `<script defer>` does not support ES modules
- **Fix:** In `Dockerfile.lab`, sed-replace `defer` with `type="module"` on the scripts tag

### Error #9: CustomElementRegistry double registration
- Both the scripts bundle and Angular chunks called `customElements.define()` for the same web component names
- **Fix:** In `Dockerfile.lab`, inject an idempotent `customElements.define` guard into `<head>` via sed

### Error #10: OIDC invalid issuer (trailing slash)
- Keycloak issuer URL `http://keycloak:8080/realms/lab` vs app config `http://keycloak:8080/realms/lab/` — trailing slash mismatch caused token validation failure
- **Fix:** Ensured consistent issuer URL (with trailing slash) in both Keycloak realm config and Spring Boot `AUTH_URL` env var

### Error #11: OIDC invalid scopes — `si_common`
- The Angular OIDC config requested scope `si_common` which was not in the Keycloak client's allowed scopes
- **Fix:** Added `si_common` as a client scope in `config/keycloak/lab-realm.json`, or removed it from the Angular OIDC config via runtime sed substitution

### Error #12: si-button unstyled (the biggest mistake)
- The `<si-button>` web component rendered as an unstyled rectangle — no padding, color, border-radius, or cursor
- **Root cause:** The `SiButtonNg` Angular wrapper slots a `<span>` but the shadow DOM CSS uses `::slotted(button)` selectors that only match native `<button>` elements
- **Wrong fix applied:** Created `si-patch.js` — a 105-line MutationObserver script that injects compiled SCSS into every `<si-base-button>` shadow root at runtime. This was fragile, version-coupled, and fundamentally wrong.
- **Correct approach (discovered later):** The design system's `<si-button>` already accepts a native `<button>` child element. The Angular template should use `<si-button><button>Login with SSO</button></si-button>` instead of `<si-button>Login with SSO</si-button>`. The `::slotted(button)` CSS then matches correctly with zero patches.
- **Lesson:** Read the component API docs before inventing workarounds. The shadow DOM was working as designed.

---

## Phase 10: Storybook (Design System)

**Actions:**
1. Cloned the Signal Iduna design system into `src/design-system/`
2. Built Storybook from `libs/storybook-host` in the Nx workspace
3. Added `storybook` container to `docker-compose.yml` — nginx serving built Storybook at port 4201
4. Storybook provides a visual reference for all `<si-*>` web components

---

## Phase 11: Lab Guide & Test Scripts

**Actions:**
1. Created `docs/lab-guide/index.html` — single-page documentation site served by nginx at port 4202
2. Created `scripts/test-frontend.mjs` — Playwright headless browser test (checks for JS errors, page load, Angular bootstrap)
3. Created `scripts/test-login.mjs` — Playwright test for SSO login flow (clicks Login button, verifies Keycloak redirect)

---

## Phase 12: .gitignore Fix (Error #13)

**Error #13** encountered and fixed — the `.gitignore` in the dlt-manager clone was too aggressive, excluding Gradle build files and wrapper needed for Jenkins builds. Fixed across multiple commits.

---

## Complete Error Log

### Error #1: downloadSuppression fails at Gradle config time

| Field | Value |
|-------|-------|
| **Chronological order** | 1 of 13 |
| **Phase** | 1 — Hint Backend Build |
| **Error message** | `A problem occurred evaluating root project 'hint' > git.system.local` |
| **Root cause** | The `dependencyCheck` block in `hint/build.gradle` (line 181) calls `downloadSuppression()` which reaches out to internal Bitbucket (`git.system.local`) during Gradle's **configuration phase**. Even `-x dependencyCheckAnalyze` cannot skip it because the call happens before task execution. |
| **Fix applied** | Wrapped both `downloadSuppression()` calls in try-catch blocks to gracefully handle network failures |
| **Lesson learned** | Gradle configuration-phase code runs unconditionally. Side-effecting calls (network, file I/O) in plugin configuration blocks must be guarded or deferred to task execution. |

### Error #2: Version mismatch for mavenLocal deps

| Field | Value |
|-------|-------|
| **Chronological order** | 2 of 13 |
| **Phase** | 2 — DLT-Manager Backend Build |
| **Error message** | `Could not find de.signaliduna.elpa:jwt-adapter:2.5.0` / `Could not find de.signaliduna.elpa:elpa4-model:1.1.1` |
| **Root cause** | Libraries were published to mavenLocal as `2.5.1-SNAPSHOT` and `1.1.1-SNAPSHOT`, but dlt-manager requires exact versions `2.5.0` and `1.1.1`. Gradle does not treat SNAPSHOT as a match for release versions. |
| **Fix applied** | Re-published with exact version overrides: `./gradlew publishToMavenLocal -Pversion=2.5.0` and `-Pversion=1.1.1` |
| **Lesson learned** | When building internal dependencies from source, always check what version the consumer expects and publish that exact version string. |

### Error #3: Modified original source code

| Field | Value |
|-------|-------|
| **Chronological order** | 3 of 13 |
| **Phase** | 4 — Dockerfiles |
| **Error message** | N/A (process error, not build error) |
| **Root cause** | Early in the lab setup, modifications were made directly to the original project repositories (e.g., `combine-hint/hint/build.gradle`) instead of working on copies. This pollutes the original repos with lab-specific changes. |
| **Fix applied** | Reverted all changes to originals. Cloned projects into `src/` directory (`src/hint-backend/`, `src/dlt-manager/`). All subsequent modifications target only the clones. Symlinks in `projects/` point to `src/` clones. |
| **Lesson learned** | Never modify source-of-truth repositories for environment-specific changes. Always clone/fork first, then modify the copy. |

### Error #4: Kafka healthcheck path wrong

| Field | Value |
|-------|-------|
| **Chronological order** | 4 of 13 |
| **Phase** | 6 — Docker Compose |
| **Error message** | Kafka container stuck in `unhealthy` state; healthcheck command not found |
| **Root cause** | The `apache/kafka:3.7.0` image places Kafka binaries at `/opt/kafka/bin/`, not on `$PATH`. The initial healthcheck used `kafka-broker-api-versions.sh` without the full path. |
| **Fix applied** | Changed healthcheck to use full path: `/opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092` |
| **Lesson learned** | Always verify binary paths inside third-party Docker images. The `apache/kafka` image layout differs from Confluent and Bitnami images. |

### Error #5: Kafka internal/external listener confusion

| Field | Value |
|-------|-------|
| **Chronological order** | 5 of 13 |
| **Phase** | 6 — Docker Compose |
| **Error message** | Backend containers fail to connect to Kafka: `Connection to node -1 (localhost:9092) could not be established` |
| **Root cause** | Kafka was configured with a single `PLAINTEXT://localhost:9092` listener. Other Docker containers resolve `kafka:9092` but Kafka advertises `localhost:9092`, causing clients to connect to their own loopback. |
| **Fix applied** | Added separate internal (`PLAINTEXT://0.0.0.0:9092`, advertised as `kafka:9092`) and external (`EXTERNAL://0.0.0.0:19092`, advertised as `localhost:19092`) listeners with proper `LISTENER_SECURITY_PROTOCOL_MAP` |
| **Lesson learned** | Kafka in Docker always needs separate internal (container-to-container) and external (host-to-container) listeners with different advertised addresses. This is the single most common Kafka-in-Docker mistake. |

### Error #6: Bitbucket DC HV000149 validation error

| Field | Value |
|-------|-------|
| **Chronological order** | 6 of 13 |
| **Phase** | 7 — Git Server Selection |
| **Error message** | `HV000149: An exception occurred during message interpolation` on Bitbucket DC setup page |
| **Root cause** | Bitbucket Data Center's setup wizard threw a Hibernate Validator error during initial configuration. Likely a version incompatibility or missing database prerequisite. |
| **Fix applied** | Abandoned Bitbucket DC entirely. Chose Gitea instead. |
| **Lesson learned** | Bitbucket DC is designed for enterprise clusters with dedicated infrastructure. It is not suitable for lightweight local labs. Use Gitea or Forgejo for local git server needs. |

### Error #7: GitLab CE wrong platform + OOM + password rejection

| Field | Value |
|-------|-------|
| **Chronological order** | 7 of 13 |
| **Phase** | 7 — Git Server Selection |
| **Error message** | Multiple: (1) `exec format error` (amd64 image on arm64), (2) OOM killed with 4 GB RAM, (3) password rejected on first login even with correct `GITLAB_ROOT_PASSWORD` |
| **Root cause** | (1) No native arm64 GitLab CE image. (2) GitLab bundles PostgreSQL, Redis, Sidekiq, Puma, Gitaly — minimum 4 GB RAM for a single instance. (3) The root password env var is only used on first `reconfigure`; if the DB was initialized in a previous failed attempt, the password is already set differently. |
| **Fix applied** | Abandoned GitLab CE. Chose Gitea instead. |
| **Lesson learned** | GitLab CE is a monolith that consumes 4+ GB RAM. For a lab that already runs PostgreSQL, Kafka, Keycloak, Jenkins, and 3 application containers, adding GitLab would push total memory past 12 GB. Gitea uses 50 MB. |

### Error #8: Frontend — Unexpected token 'export' (scripts bundle)

| Field | Value |
|-------|-------|
| **Chronological order** | 8 of 13 |
| **Phase** | 9 — Frontend Fixes |
| **Error message** | `Uncaught SyntaxError: Unexpected token 'export'` in `scripts-XXXX.js` |
| **Root cause** | Angular CLI builds the `@signal-iduna/ui` design system scripts bundle with ES module `export` statements, but the `<script>` tag in `index.html` uses `defer` (classic script mode). Classic scripts do not support `export`/`import`. |
| **Fix applied** | In `Dockerfile.lab`, sed-replace `<script src="scripts-*.js" defer>` with `<script src="scripts-*.js" type="module">` |
| **Lesson learned** | When bundling web component libraries that use ES module syntax, ensure the script tag uses `type="module"`. Angular CLI's `scripts` array in `angular.json` defaults to classic script injection. |

### Error #9: Frontend — CustomElementRegistry double registration

| Field | Value |
|-------|-------|
| **Chronological order** | 9 of 13 |
| **Phase** | 9 — Frontend Fixes |
| **Error message** | `DOMException: Failed to execute 'define' on 'CustomElementRegistry': the name "si-icon" has already been used` |
| **Root cause** | The design system scripts bundle calls `customElements.define('si-icon', ...)` and then an Angular lazy chunk also tries to define the same element. The browser's `CustomElementRegistry` does not allow re-registration. |
| **Fix applied** | In `Dockerfile.lab`, inject an idempotent guard into `<head>`: override `customElements.define` to no-op when the name is already registered (`if (!customElements.get(n)) _origDefine(n, c, o)`) |
| **Lesson learned** | When mixing web component libraries loaded both as global scripts and as Angular module imports, double-registration is inevitable. An idempotent define guard is the standard workaround. |

### Error #10: OIDC — Invalid issuer (trailing slash)

| Field | Value |
|-------|-------|
| **Chronological order** | 10 of 13 |
| **Phase** | 9 — Frontend Fixes |
| **Error message** | `invalid_issuer` error during OIDC token validation |
| **Root cause** | Keycloak's OIDC discovery returns issuer as `http://keycloak:8080/realms/lab` (no trailing slash), but the application config had `http://keycloak:8080/realms/lab/` (with trailing slash). The issuer comparison is exact string match per RFC 8414. |
| **Fix applied** | Ensured consistent issuer URL (with trailing slash) in `AUTH_URL` env var across all services |
| **Lesson learned** | OIDC issuer comparison is an exact string match. A single trailing slash difference causes validation failure. Always copy the issuer URL from Keycloak's `.well-known/openid-configuration` endpoint. |

### Error #11: OIDC — Invalid scopes `si_common`

| Field | Value |
|-------|-------|
| **Chronological order** | 11 of 13 |
| **Phase** | 9 — Frontend Fixes |
| **Error message** | `Invalid scopes: si_common` — scope not in client's `defaultScopes` |
| **Root cause** | The Angular OIDC configuration requests a custom scope `si_common` that exists in the corporate IdP but was not defined in the local Keycloak realm. Keycloak rejects unknown scopes. |
| **Fix applied** | Added `si_common` as a client scope in `config/keycloak/lab-realm.json` and assigned it to the OIDC client's default scopes |
| **Lesson learned** | When replacing a corporate IdP with Keycloak, audit all custom scopes the application requests and create matching scope definitions in the Keycloak realm. |

### Error #12: si-button unstyled — invented own CSS patch instead of using `<button>`

| Field | Value |
|-------|-------|
| **Chronological order** | 12 of 13 |
| **Phase** | 9 — Frontend Fixes |
| **Error message** | N/A (visual bug — login button rendered as unstyled text) |
| **Root cause** | The `<si-button>` web component's shadow DOM uses `::slotted(button)` CSS selectors to style a native `<button>` child. The Angular template slotted a `<span>` instead of a `<button>`, so the CSS selectors never matched. The button had no padding, background, border-radius, or cursor. |
| **Wrong fix applied** | Created `si-patch.js` (105 lines) — a MutationObserver that injects compiled SCSS from `base-button-shared.component.scss` into every `<si-base-button>` shadow root at runtime. This involved reverse-engineering the design system's SCSS token values, hardcoding color hex codes, and running the patch on every DOM mutation. |
| **Correct approach** | Use `<si-button><button>Login with SSO</button></si-button>`. The component's `::slotted(button)` CSS then matches the native button element. Zero custom CSS needed. |
| **Lesson learned** | **This was the biggest mistake of the entire lab build.** Before writing any workaround for a web component, check its documented API and slot contract. Shadow DOM CSS is intentionally scoped — fighting it with runtime injection is always wrong. The time spent reverse-engineering SCSS tokens, debugging shadow DOM pierce selectors, and writing MutationObserver hacks far exceeded what a 30-second API doc check would have cost. |

### Error #13: .gitignore too aggressive in dlt-manager clone

| Field | Value |
|-------|-------|
| **Chronological order** | 13 of 13 |
| **Phase** | 12 — Jenkins Integration |
| **Error message** | Jenkins build fails: Gradle wrapper jar and build files not found after `checkout scm` |
| **Root cause** | The original `.gitignore` contained patterns like `**/build/` and `.gradle/` which are correct for development (exclude build outputs), but when the repo was cloned into the lab and committed to Gitea, these patterns also excluded `gradle/wrapper/gradle-wrapper.jar` and Gradle build scripts needed for Jenkins. |
| **Fix applied** | Rewrote `.gitignore` across multiple commits: (1) included Gradle wrapper, (2) included Gradle build files, (3) included all source files. Final `.gitignore` is minimal and explicit. |
| **Lesson learned** | When importing a project into a new git server, review `.gitignore` carefully. Patterns that work with a pre-existing CI cache (where the Gradle wrapper is already present) will break in a fresh `checkout scm`. |

---

## Files Created

```
dev-labs/
├── PROTOCOL.md                          <- this file
├── CLAUDE.md                            <- setup instructions for Claude Code
├── README.md
├── .env.example
├── docker-compose.yml                   <- all 9 services
├── projects/
│   ├── hint-backend -> ../src/hint-backend
│   ├── dlt-backend -> ../src/dlt-manager/backend
│   └── dlt-frontend -> ../src/dlt-manager/frontend
├── analysis/
│   ├── hint-backend-deps.json
│   ├── dlt-backend-deps.json
│   ├── dlt-frontend-deps.json
│   └── infra-manifest.json
├── docker/
│   ├── hint-backend.Dockerfile
│   ├── dlt-backend.Dockerfile
│   └── dlt-frontend.Dockerfile
├── config/
│   ├── postgres/init-databases.sql
│   ├── keycloak/lab-realm.json
│   └── bruno/lab-api/
│       ├── bruno.json
│       ├── keycloak-get-token.bru
│       ├── hint-health.bru
│       ├── hint-get-hints.bru
│       ├── dlt-health.bru
│       └── dlt-get-events.bru
├── docs/
│   └── lab-guide/index.html             <- documentation site
├── k8s/
│   ├── namespaces.yaml
│   ├── gateway/
│   │   ├── istio-gateway.yaml
│   │   ├── virtual-services.yaml
│   │   └── destination-rules.yaml
│   └── apps-dev/
│       ├── infra/
│       │   ├── secrets.yaml
│       │   ├── postgres.yaml
│       │   ├── kafka.yaml
│       │   └── keycloak.yaml
│       ├── backend/
│       │   ├── hint-deployment.yaml
│       │   └── dlt-deployment.yaml
│       └── frontend/
│           └── dlt-frontend-deployment.yaml
├── helm/
│   ├── backend/                         <- empty, placeholder
│   └── frontend/                        <- empty, placeholder
├── scripts/
│   ├── bootstrap.sh
│   ├── setup-k8s.sh
│   ├── prepare-m2-cache.sh
│   ├── test-frontend.mjs                <- Playwright browser test
│   └── test-login.mjs                   <- Playwright login flow test
└── src/
    ├── CONTRIBUTING.md
    ├── hint-backend/                    <- cloned from combine-hint/hint
    ├── dlt-manager/                     <- cloned from dlt-manager
    └── design-system/                   <- cloned for Storybook
```

---

## Files Modified (in src/ clones only — originals untouched)

| File | Change | Reason |
|------|--------|--------|
| `src/hint-backend/build.gradle` | Wrapped `downloadSuppression()` in try-catch | Internal Bitbucket not reachable (Error #1) |
| `src/hint-backend/Dockerfile.lab` | Created — multi-stage Docker build | Lab Docker image |
| `src/hint-backend/Jenkinsfile.lab` | Created — declarative pipeline without shared libs | Lab CI/CD |
| `src/dlt-manager/build.gradle` | Skips for OWASP/OpenRewrite tasks | Internal infra not reachable |
| `src/dlt-manager/Dockerfile.lab` | Created — multi-stage Docker build | Lab Docker image (backend) |
| `src/dlt-manager/backend/Dockerfile.lab` | Created — backend-specific Dockerfile | Jenkins Docker build stage |
| `src/dlt-manager/frontend/Dockerfile.lab` | Created — nginx with sed fixes for ES modules, double-registration guard, and runtime env substitution | Errors #8, #9, #10 |
| `src/dlt-manager/frontend/si-patch.js` | Created — MutationObserver shadow DOM style injection | Error #12 (wrong fix, should use `<button>` slot) |
| `src/dlt-manager/Jenkinsfile.lab` | Created — declarative pipeline without shared libs | Lab CI/CD |
| `src/dlt-manager/.gitignore` | Rewritten to not exclude Gradle wrapper/build files | Error #13 |

---

## Current Running Services

| # | Container | Image | Port | Purpose |
|---|-----------|-------|------|---------|
| 1 | lab-postgres | postgres:15-alpine | 5432 | PostgreSQL (hint + dltmanager databases) |
| 2 | lab-kafka | apache/kafka:3.7.0 | 19092 (external), 9092 (internal) | Kafka (KRaft, single node) |
| 3 | lab-keycloak | keycloak:24.0 | 8180 | OIDC Identity Provider |
| 4 | lab-hint-backend | lab/hint-backend:latest | 8080 (API), 8081 (health) | Hint Spring Boot backend |
| 5 | lab-dlt-backend | lab/dlt-backend:latest | 8082 (API), 8083 (health) | DLT-Manager Spring Boot backend |
| 6 | lab-dlt-frontend | lab/dlt-frontend:latest | 4200 | DLT-Manager Angular frontend |
| 7 | lab-gitea | gitea/gitea:1.22 | 3000 (HTTP), 2222 (SSH) | Git server (replaces Bitbucket DC) |
| 8 | lab-jenkins | jenkins/jenkins:lts-jdk21 | 8888 | CI/CD (replaces corporate Jenkins) |
| 9 | lab-storybook | nginx:1-alpine | 4201 | Design System Storybook |
| 10 | lab-guide | nginx:1-alpine | 4202 | Lab documentation site |

Note: 10 containers total (9 services + 1 documentation).

---

## How to Run

### Option A: Docker Compose (simpler)

```bash
# 1. Start Docker Desktop
# 2. Build Java backends (requires Java 21 + mavenLocal deps)
cd dev-labs/src/hint-backend && ./gradlew :hint-service:installDist
cd dev-labs/src/dlt-manager && ./gradlew :backend:installDist
# 3. Build frontend (requires Node 22 + npm packages already installed)
cd dev-labs/src/dlt-manager/frontend && npx ng build --configuration production
# 4. Build Docker images
cd dev-labs
docker compose build
# 5. Start all services
docker compose up -d
```

Or use the bootstrap script:

```bash
cd dev-labs
./scripts/bootstrap.sh
```

**Endpoints:**

| Service | URL |
|---------|-----|
| Hint Backend API | http://localhost:8080/api/hints |
| Hint Swagger | http://localhost:8080/api/docs/rest |
| Hint Health | http://localhost:8081/health |
| DLT Backend API | http://localhost:8082/api/events/overview |
| DLT Swagger | http://localhost:8082/api/docs/rest |
| DLT Health | http://localhost:8083/health |
| DLT Frontend | http://localhost:4200 |
| Keycloak | http://localhost:8180 |
| Gitea | http://localhost:3000 |
| Jenkins | http://localhost:8888 |
| Storybook | http://localhost:4201 |
| Lab Guide | http://localhost:4202 |

### Option B: Kubernetes (k3d + Istio)

```bash
# 1. Install prerequisites: docker, kubectl, k3d, istioctl
# 2. Run bootstrap first to build Docker images
./scripts/bootstrap.sh
# 3. Deploy to k3d
./scripts/setup-k8s.sh
# 4. Add to /etc/hosts
echo "127.0.0.1  hint.lab.local dlt.lab.local dlt-ui.lab.local keycloak.lab.local" | sudo tee -a /etc/hosts
```

### Testing with Bruno

1. Open Bruno
2. Import collection from `config/bruno/lab-api/`
3. Select environment `local-docker`
4. Run "Get Access Token" first
5. Then test any API endpoint

### Testing with Playwright

```bash
# Headless browser test (requires playwright installed)
node scripts/test-frontend.mjs         # checks page load + JS errors
node scripts/test-login.mjs            # tests SSO login button flow
```

---

## Credentials

| Service | Username | Password | Notes |
|---------|----------|----------|-------|
| Keycloak Admin Console | admin | admin | http://localhost:8180/admin |
| Keycloak Lab Realm — admin user | admin | admin | sub=S000325 |
| Keycloak Lab Realm — test user | testuser | test | sub=U116330 |
| PostgreSQL | db_user | db_password | Databases: hint, dltmanager |
| Gitea | (create on first visit) | (create on first visit) | http://localhost:3000 |
| Jenkins | (no auth) | (no auth) | Setup wizard disabled |
| OIDC Client ID | 8d12476c2684592b12515daab4ca0ddb72007118-E | (public client) | Same ID as production |

---

## Prerequisites

| Tool | Required Version | Purpose |
|------|-----------------|---------|
| Java (Temurin) | 21 | Build backends |
| Gradle | 8.14.2 (via wrapper) | Build system |
| Node.js | 22.x | Build frontend |
| Docker | 29.x | Container runtime |
| kubectl | 1.28+ | K8s CLI (Option B only) |
| k3d | 5.x | Local K8s cluster (Option B only) |
| istioctl | 1.21+ | Istio service mesh (Option B only) |
| Bruno | any | API testing (optional) |
| Playwright | any | Frontend testing (optional) |
