# Dev-Labs: Local DevOps Lab

A self-contained local DevOps lab that simulates the full Signal Iduna CI/CD and deployment pipeline. Runs real Spring Boot services (hint, dlt-manager), a complete CI/CD toolchain, and a Kubernetes cluster with ArgoCD — all on a single machine using Docker Compose and kind.

## Architecture

```
                          HOST MACHINE (~5 GB RAM)

  ┌──────────────────── Docker Compose ────────────────────┐
  │                                                        │
  │  Gitea ─────── Jenkins ─────── Registry                │
  │  :3000         :8888           :5050                    │
  │  (Bitbucket)   (CI/CD)        (Docker Registry)        │
  │                    │                                    │
  │  Keycloak      Kafka        PostgreSQL                  │
  │  :8180         :19092       :5432                       │
  │  (OIDC)        (KRaft)     (hint + dlt DBs)            │
  │                                                        │
  │  hint-backend  dlt-backend  dlt-frontend  Storybook     │
  │  :8080/:8081   :8082/:8083  :4200         :4201         │
  └────────────────────────────────────────────────────────┘
          │
          │  CoPSI Pipeline: Jenkins renders Helm,
          │  pushes manifest to Gitea, ArgoCD syncs
          ▼
  ┌──────────────── kind Kubernetes Cluster ───────────────┐
  │                                                        │
  │  ArgoCD ──── watches ──── Gitea: elpa-elpa4 repo       │
  │  :30080                   (branch: nop)                 │
  │                                                        │
  │  ┌─ elpa-elpa4 namespace ─────────────────────┐        │
  │  │  tst-hint (Deployment + Service)           │        │
  │  │  abn-hint (Deployment + Service)           │        │
  │  │  VirtualServices (Istio CRDs)              │        │
  │  └────────────────────────────────────────────┘        │
  └────────────────────────────────────────────────────────┘
```

## Corporate-to-Lab Mapping

| Corporate Infrastructure | Lab Replacement | Notes |
|--------------------------|-----------------|-------|
| Bitbucket DC (`git.system.local`) | Gitea | Same git workflow, REST API adapted |
| Jenkins + `si-dp-shared-libs` + `elpa-shared-lib` | Jenkins + lab-adapted shared libs | Gitea API instead of Bitbucket API |
| Nexus (`dev.docker.system.local`) | Docker Registry v2 | Push: `localhost:5050`, Pull (K8s): `registry:5000` |
| OpenShift | kind + ArgoCD | CoPSI GitOps replaces `oc` commands |
| Corporate OIDC | Keycloak | "lab" realm, users: admin/S000325, testuser/U116330 |
| Managed PostgreSQL | Single PostgreSQL container | Databases: `hint`, `dltmanager` |
| Multi-node Kafka (SASL + OAUTHBEARER) | Single-node KRaft (PLAINTEXT) | No Zookeeper |
| SonarQube / OWASP DC | Skipped | Stubs in shared libs |

## Running on Another Machine

The lab is designed to be portable. On a fresh machine you only need Docker and a few CLI tools.

### Minimal setup (CoPSI pipeline testing only)

No Java, no app source code needed — just tests the Jenkins shared libs + ArgoCD flow:

```bash
# 1. Clone the repo
git clone <repo-url> dev-labs && cd dev-labs

# 2. Copy and edit env config
cp .env.example .env

# 3. Start core CI/CD (no Storybook, no Lab Guide)
docker compose -f docker-compose.cicd.yml up -d

# 4. Setup CoPSI pipeline
./scripts/setup-copsi-pipeline.sh

# 5. (Optional) Start K8s + ArgoCD — see "Set up Kubernetes" below
```

### Full setup (with apps + SI UI)

Requires Java 21, app source code in `src/`, and design-system assets:

```bash
# Start everything including Storybook + Lab Guide
docker compose --profile si-ui up -d
```

### Docker Compose Profiles

| Command | What starts |
|---------|------------|
| `docker compose -f docker-compose.cicd.yml up -d` | Gitea, Jenkins, Registry |
| `docker compose -f docker-compose.cicd.yml --profile si-ui up -d` | + Storybook, Lab Guide |
| `docker compose up -d` | Full stack (Gitea, Jenkins, Postgres, Kafka, Keycloak, apps) |
| `docker compose --profile si-ui up -d` | + Storybook, Lab Guide |

### Environment Variables

Copy `.env.example` to `.env` and adjust paths for your machine:

| Variable | Default | Purpose |
|----------|---------|---------|
| `JAVA_HOME` | auto-detected | Java 21 installation |
| `JAVA_LIBS_DIR` | `../java_libs` | Path to jwt-adapter + elpa4-shared-lib |
| `DEPLOY_REPO_SOURCE` | `../combine-hint/elpa-elpa4` | Path to deploy repo content |
| `COMPOSE_PROFILES` | (empty) | Set to `si-ui` for Storybook + Lab Guide |

## Quick Start

### Prerequisites

- Docker Desktop with ~6 GB RAM allocated
- `kind`, `kubectl`, `helm` CLI tools
- Java 21 (only for full app builds, not needed for CoPSI testing)

### 1. Start the tooling + app stack

```bash
# Core CI/CD only (works on any machine)
docker compose -f docker-compose.cicd.yml up -d

# Full stack (needs app images built)
docker compose up -d

# With SI UI components
docker compose --profile si-ui up -d
```

### 2. Set up Jenkins shared libraries + CoPSI pipeline

```bash
# One command: pushes shared libs to Gitea, configures Jenkins,
# creates deploy repo, creates pipeline job, installs helm in Jenkins
./scripts/setup-copsi-pipeline.sh
```

### 3. Set up Kubernetes + ArgoCD

```bash
# Create kind cluster and connect to lab-net
kind create cluster --config k8s/kind-config.yaml
docker network connect lab-net dev-lab-control-plane

# Install ArgoCD (minimal, no Dex)
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml --server-side=true --force-conflicts
kubectl -n argocd scale deploy argocd-dex-server --replicas=0
kubectl -n argocd patch svc argocd-server --type merge -p '{"spec":{"type":"NodePort","ports":[{"name":"https","port":443,"targetPort":8080,"nodePort":30080}]}}'

# Install Istio CRDs (no control plane, just CRDs for VirtualService support)
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm install istio-base istio/base -n istio-system --create-namespace --set defaultRevision=default

# Create namespace + service account for apps
kubectl create namespace elpa-elpa4
kubectl -n elpa-elpa4 create serviceaccount identity
kubectl -n elpa-elpa4 create secret generic lab-postgres-secret \
    --from-literal=USER=db_user --from-literal=PASSWORD=db_password

# Deploy ArgoCD Application (watches deploy repo)
kubectl apply -f k8s/argocd/hint-app.yaml

# Get ArgoCD admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### 4. Run the full GitOps loop

```bash
# Open Jenkins: http://localhost:8888/job/copsi-test/
# Click "Build with Parameters" → TEST_MODE = deploy-lab-tst → Build
#
# This triggers:
#   1. Helm template renders with lab values (registry:5000 images)
#   2. Manifest pushed to elpa-elpa4 deploy repo via Gitea PR
#   3. PR auto-merged
#   4. ArgoCD detects new commit → syncs to K8s
#   5. Pod pulls image from registry:5000
```

## URLs

| Service | URL | Credentials |
|---------|-----|-------------|
| Hint API | http://localhost:8080/api/docs/rest | — |
| Hint Health | http://localhost:8081/health | — |
| DLT Manager API | http://localhost:8082/api/docs/rest | — |
| DLT Frontend | http://localhost:4200 | — |
| Storybook | http://localhost:4201 | — |
| Lab Guide | http://localhost:4202 | — |
| Gitea | http://localhost:3000 | labadmin / labadmin |
| Jenkins | http://localhost:8888 | no auth |
| Keycloak | http://localhost:8180 | admin / admin |
| ArgoCD | https://localhost:30080 | admin / (see secret) |
| Docker Registry | http://localhost:5050/v2/_catalog | — |

## CoPSI Deployment Pipeline

CoPSI (Container Platform Service Integration) is the GitOps deployment pattern replacing OpenShift `oc` commands. Each service has a `copsi/` folder with a Helm chart, and a deploy repo receives rendered manifests via PRs.

### Flow

```
  Code repo (hint-backend)          Deploy repo (elpa-elpa4)        Kubernetes
  ┌──────────────────────┐          ┌──────────────────────┐        ┌──────────┐
  │ copsi/               │  Jenkins │ services/hint/       │ ArgoCD │ Pods     │
  │   Chart.yaml         │ ──────► │   tst.yaml           │ ─────► │ running  │
  │   values-lab-tst.yaml│  render  │   abn.yaml           │  sync  │ in K8s   │
  │   templates/         │  + PR    │   features/           │        │          │
  └──────────────────────┘          └──────────────────────┘        └──────────┘
```

### Jenkins Pipeline Modes

The `copsi-test` pipeline job supports these TEST_MODE values:

| Mode | What it tests |
|------|---------------|
| `all` | All 3 CoPSI functions (deployTst + deployAbn + deployFeature) |
| `helm-only` | Only renders Helm templates, no deploy repo interaction |
| `deploy-tst` | `elpa_copsi.deployTst()` — corporate values |
| `deploy-abn` | `elpa_copsi.deployAbn()` — corporate values |
| `deploy-feature` | `elpa_copsi.deployFeature()` — feature branch deploy |
| `deploy-lab-tst` | `elpa_copsi.deployLabTst()` — lab values with `registry:5000` images |

### Jenkins Shared Libraries

Lab-adapted versions of the corporate shared libraries:

| Library | Corporate Name | Lab Location | Key Adaptations |
|---------|---------------|--------------|-----------------|
| `si-dp-shared-libs` | `si-dp-shared-libs` | `jenkin/si-jenkin-lab/` | `si_copsi`: Bitbucket API → Gitea API |
| | | | `si_docker`: build farm → local Docker + registry:5000 |
| | | | `si_openshift`: stubbed (CoPSI replaces) |
| `elpa-shared-lib` | `elpa-shared-lib` | `jenkin/elpa-jenkin-lab/` | `elpa_copsi`: CoPSI deploy functions |
| | | | `elpa_psql`: schema management stubs |

## Directory Structure

```
dev-labs/
├── config/
│   ├── bruno/             # Bruno API test collections
│   ├── jenkins/           # Jenkins init scripts
│   ├── keycloak/          # lab-realm.json (pre-configured OIDC)
│   ├── postgres/          # init-databases.sql
│   └── proxy/             # nginx reverse proxy config
├── docker/
│   ├── hint-backend.Dockerfile
│   ├── dlt-backend.Dockerfile
│   └── dlt-frontend.Dockerfile
├── jenkin/
│   ├── si-jenkin-lab/     # Lab-adapted si-dp-shared-libs
│   │   ├── vars/          # si_copsi, si_git, si_docker, si_java, ...
│   │   └── src/           # BitbucketRepo, CopsiEnvironment, TargetSegment, ...
│   └── elpa-jenkin-lab/   # Lab-adapted elpa-shared-lib
│       ├── vars/          # elpa_copsi, elpa_psql
│       └── src/           # BitbucketRepo
├── k8s/
│   ├── kind-config.yaml   # kind cluster configuration
│   ├── namespaces.yaml    # K8s namespaces
│   ├── argocd/            # ArgoCD Application definitions
│   ├── apps-dev/          # Dev environment manifests
│   ├── gateway/           # Istio gateway + virtual services
│   └── observability/     # (placeholder for Prometheus/Grafana)
├── projects/
│   ├── hint-backend/      # Hint service (with copsi/ chart + Jenkinsfile.copsi-test)
│   ├── dlt-backend/
│   └── dlt-frontend/
├── scripts/
│   ├── bootstrap.sh               # Full lab rebuild
│   ├── setup-copsi-pipeline.sh    # One-command CoPSI setup
│   ├── setup-jenkins-libs.sh      # Push shared libs to Gitea + configure Jenkins
│   ├── setup-deploy-repo.sh       # Push elpa-elpa4 to Gitea
│   ├── prepare-m2-cache.sh        # Copy mavenLocal to Jenkins container
│   └── test-*.sh / test-*.mjs     # Validation scripts
├── src/                   # Cloned app sources (modified for lab)
│   ├── hint-backend/
│   ├── dlt-manager/
│   └── design-system/
├── docker-compose.yml             # All services
├── docker-compose.cicd.yml        # CI/CD tooling only
├── docker-compose.apps.yml        # Apps + infra only
└── CLAUDE.md                      # AI assistant instructions
```

## Resource Usage

| Component | RAM | When |
|-----------|-----|------|
| Docker Compose stack | ~3 GB | Always (Gitea, Jenkins, Kafka, Postgres, Keycloak, apps) |
| Docker Registry | ~10 MB | Always |
| kind cluster | ~300 MB | When K8s/ArgoCD needed |
| ArgoCD | ~300 MB | When K8s/ArgoCD needed |
| App pods in K8s | ~500 MB each | When deployed via ArgoCD |
| **Total** | **~4-5 GB** | Full lab running |

## Kafka

- Inter-container: `kafka:9092` (PLAINTEXT)
- From host: `localhost:19092` (EXTERNAL)
- Do NOT use `localhost:9092` from inside containers or `kafka:9092` from host.

## Known Limitations

- **Jenkins integration tests**: Testcontainers-based tests require Docker-in-Docker networking and may fail inside Jenkins. Use `-x check` to skip.
- **Frontend npm install**: `@signal-iduna/*` packages need Verdaccio. The frontend build in `src/dlt-manager/frontend` ships with `node_modules` — avoid `npm install` unless Verdaccio is configured.
- **abn-hint pods**: The `abn` deployment uses corporate registry URLs (`dev.docker.system.local`). Use `deploy-lab-tst` mode for deployable images. Create a `values-lab-abn.yaml` following the same pattern.
- **ArgoCD poll interval**: Default is 3 minutes. Use the ArgoCD UI refresh button or `kubectl patch` for faster feedback.
- **Istio**: Only CRDs installed (no control plane). VirtualService resources are accepted but not routed. Install `istioctl` + `istiod` for full mesh.

## Teardown

```bash
# Stop Docker Compose services
docker compose down           # keep volumes
docker compose down -v        # destroy volumes

# Delete kind cluster
kind delete cluster --name dev-lab
```
