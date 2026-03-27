# User Intent and Design Decisions

What the user is trying to achieve and why things are built this way.

## Primary goal

Test Jenkins shared library changes (especially CoPSI deployment functions) locally
before deploying to corporate Jenkins. The user modifies `elpa-copsi.groovy` in the lab,
verifies it works, then puts the same file in the corporate repo.

## Key design principle: minimal diff from corporate

The user explicitly requested that changes be as small as possible so the Jenkinsfile
and shared libs work in both lab and corporate without modification.

- `elpa_copsi.groovy` — IDENTICAL in lab and corporate. Bug fixes go directly to production.
- `si_copsi.groovy` — the ONLY file that must differ (Bitbucket vs Gitea API adapter).
- `Jenkinsfile` — IDENTICAL. No `if (isLab())` branches.
- Environment differences handled via Jenkins global env vars, not code.

## CoP Migration context

The company (Signal Iduna) is migrating from OpenShift to on-premises Kubernetes with ArgoCD.
"CoP" = Container Platform. The migration replaces:
- `si_openshift.deployApplication()` → CoPSI Helm render + PR to deploy repo
- OpenShift DeploymentConfigs → Kubernetes Deployments
- `oc` CLI → ArgoCD auto-sync

This lab simulates the target state. The CoPSI functions being tested ARE the migration.

## Why Gitea (not mock)

The user wants real Git operations (clone, push, PR, merge) — not mocks.
Gitea provides a real Git server + REST API that behaves like Bitbucket
but with a different API format. This catches real integration issues.

## Why ArgoCD + kind (not just Docker Compose)

The deployment target is Kubernetes with ArgoCD. Testing only with Docker Compose
would miss ArgoCD sync behavior, Kustomize validation, and K8s-specific issues
(selector immutability, secret references, health probes).

## Why Kafka in K8s but Postgres external

Matches production topology:
- Kafka runs in the same K8s cluster as services (shared namespace)
- PostgreSQL is managed externally (corporate managed DB)

The lab simulates this: Kafka as a pod in elpa-elpa4 namespace, Postgres in Docker Compose
exposed via K8s ExternalName services.

## Feature cleanup design

When a feature branch merges to develop, `deployAbn()` should clean up the feature deployment.
The user's requirement: one atomic PR that deploys ABN AND removes stale features.
ArgoCD then prunes the deleted feature pods in a single sync.

Empty features/ directory uses `resources: []` kustomization to keep the parent reference valid.

## Portability

The user wants other team members to use this lab. Key decisions:
- Docker Compose profiles (`--profile si-ui`) for optional Storybook/Lab Guide
- `.env.example` for configurable paths
- No hardcoded paths in scripts (use env vars with defaults)
- README has "Running on Another Machine" section

## Workflow: lab first, real project second

All changes to Jenkins shared libs or Jenkinsfiles MUST follow this order:
1. Edit in `dev-labs/jenkin/elpa-jenkin-lab/` (or `si-jenkin-lab/`)
2. Push to Gitea, trigger Jenkins job, verify it works
3. Only then copy to `combine-hint/jenkin/elpa-jenkin/`
4. Keep both versions in sync

Never write untested code to combine-hint or sda-service repos. The lab exists to prevent this.

Services that use these shared libs:
- `combine-hint/hint/` — hint service (primary)
- Future: dlt-manager, application-service, other sda-services
- Each has its own `copsi/` Helm chart and Jenkinsfile

## What NOT to add

- No git commit hooks — user explicitly removed them, prefers Jenkins-level validation
- No SonarQube/OWASP — stubs are sufficient, not testing code quality
- No full Istio mesh — CRDs only, VirtualServices accepted but not routed
- No Nexus — Docker Registry v2 is sufficient for image hosting
