# Architecture — What This Lab Simulates

## Purpose

This lab simulates Signal Iduna's corporate CI/CD and deployment infrastructure on a single machine.
The goal is to test Jenkins shared library changes (especially CoPSI deployment functions) without
touching corporate systems. Everything runs locally via Docker Compose + kind (Kubernetes).

## Corporate → Lab mapping

| Corporate | Lab | Why different |
|---|---|---|
| Bitbucket DC (git.system.local) | Gitea (localhost:3000) | License-free, 50MB RAM vs 3GB |
| Jenkins + si-dp-shared-libs + elpa-shared-lib | Jenkins + lab-adapted shared libs | Gitea API replaces Bitbucket API in si_copsi.groovy |
| Nexus Docker registry (dev.docker.system.local) | Docker Registry v2 (localhost:5050) | 10MB vs 500MB, no auth needed |
| OpenShift (oc CLI, DeploymentConfigs) | kind + ArgoCD | CoPSI replaces OpenShift — this IS the migration |
| Corporate OIDC (employee.login.int.signal-iduna.org) | Keycloak (localhost:8180) | See keycloak-setup.md for complexity |
| Managed PostgreSQL (vipsiae11t.system-a.local) | PostgreSQL in Docker Compose | External to K8s, DNS aliases in cluster |
| Multi-node Kafka (SASL + OAUTHBEARER) | Single-node KRaft in K8s | PLAINTEXT, no auth, same cluster as apps |
| SonarQube, OWASP DC | Skipped | Stubs in shared libs |

## The two repos pattern (CoPSI)

```
CODE REPO (hint-backend)         DEPLOY REPO (elpa-elpa4)          KUBERNETES
┌─────────────────────┐          ┌─────────────────────┐           ┌──────────┐
│ copsi/              │ Jenkins  │ services/hint/      │  ArgoCD   │          │
│   Chart.yaml        │ renders  │   tst.yaml          │  syncs    │  pods    │
│   values-tst.yaml   │ Helm +   │   abn.yaml          │  to K8s   │  running │
│   templates/        │ creates  │   features/          │           │          │
│                     │ PR       │     ELPA4-1234.yaml  │           │          │
└─────────────────────┘          └─────────────────────┘           └──────────┘
```

Jenkins renders Helm chart → pushes YAML to deploy repo via Gitea PR → auto-merges → ArgoCD syncs.

## Key directories

| Path | What |
|---|---|
| jenkin/si-jenkin-lab/ | Lab si-dp-shared-libs (si_copsi, si_git, si_docker, etc.) |
| jenkin/elpa-jenkin-lab/ | Lab elpa-shared-lib (elpa_copsi, elpa_psql) |
| projects/hint-backend/ | Hint service source + copsi/ Helm chart + Jenkinsfile |
| k8s/elpa-elpa4/ | K8s manifests for Kafka, Postgres, Keycloak (lab infra) |
| k8s/argocd/ | ArgoCD Application definitions |
| config/keycloak/ | Keycloak realm export |

## Network topology

```
Docker Compose (lab-net)                    kind cluster (connected to lab-net)
┌────────────────────────┐                  ┌──────────────────────────────┐
│ lab-gitea      :3000   │                  │ ArgoCD        :30080         │
│ lab-jenkins    :8888   │                  │ Kafka pod     (in-cluster)   │
│ lab-registry   :5050   │                  │ tst-hint pod  (Spring Boot)  │
│ lab-postgres   :5432  ←── K8s ExternalName ──→ postgres svc             │
│ lab-keycloak   :8180  ←── K8s ExternalName ──→ keycloak svc             │
└────────────────────────┘                  └──────────────────────────────┘
```

Postgres and Keycloak run in Docker Compose (external to K8s), exposed inside K8s via
headless Services + manual Endpoints. DNS aliases (vipsiae11t, employee-login-int) make
corporate hostnames resolve to lab containers.
