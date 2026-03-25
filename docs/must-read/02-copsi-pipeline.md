# CoPSI Pipeline — How It Works

## What is CoPSI

CoPSI (Container Platform Service Integration) is the new deployment pattern replacing OpenShift.
Each service has a `copsi/` folder with a Helm chart. Jenkins renders it and pushes the output
to a deploy repo. ArgoCD watches the deploy repo and syncs to Kubernetes.

## Jenkins shared libraries

Two libraries, same names as corporate (so @Library annotation works unchanged):

| Library | Lab location | Key file | What it does |
|---|---|---|---|
| si-dp-shared-libs | jenkin/si-jenkin-lab/ | si_copsi.groovy | Git platform adapter (Bitbucket ↔ Gitea) |
| elpa-shared-lib | jenkin/elpa-jenkin-lab/ | elpa_copsi.groovy | CoPSI deployment functions |

### si_copsi.groovy — the platform adapter

This is the ONLY file that must differ between lab and corporate. It has private adapter methods
that switch based on `isGitea()`:

- `buildPullRequestBody()` — Bitbucket nested fromRef/toRef vs Gitea flat head/base
- `buildMergeBody()` — Bitbucket version-based merge vs Gitea simple merge
- `buildPullRequestUrl()` — Different REST API paths
- `buildGitUrl()` — Gitea /scm/ rewrite vs Bitbucket credential injection

Public functions have identical signatures: `createChangeAsPullRequest()`, `waitForMergeChecksAndMerge()`.
Code that calls these (elpa_copsi.groovy) works unchanged in both environments.

### elpa_copsi.groovy — the deployment functions

This file should be IDENTICAL between lab and corporate. Changes made here are bug fixes
or improvements that go directly to production.

Key functions:
- `deployTst(serviceName, helmOverrides)` — deploy to TST
- `deployAbn(serviceName, helmOverrides)` — deploy to ABN + cleanup obsolete features
- `deployFeature(serviceName, helmOverrides)` — deploy feature branch
- `deployLabTst(serviceName, imageTag, helmOverrides)` — lab-only, uses values-lab-tst.yaml

### Environment detection

Lab vs corporate is controlled by Jenkins global env vars, NOT code changes:

| Env var | Lab value | Corporate (default) |
|---|---|---|
| GIT_API_BASE | http://gitea:3000/api/v1 | (not set → Bitbucket) |
| GIT_SERVER_URL | http://gitea:3000 | (not set → git.system.local) |
| COPSI_DEPLOY_PROJECT | labadmin | SDASVCDEPLOY |
| HELM_IMAGE | (not set → local helm) | corporate-registry/helm:3.x |

## Editing and testing workflow

```bash
# 1. Edit the shared lib
vim jenkin/elpa-jenkin-lab/vars/elpa_copsi.groovy

# 2. Push to Gitea (Jenkins loads from there)
cp -r jenkin/elpa-jenkin-lab/* /tmp/elpa-shared-lib/
cd /tmp/elpa-shared-lib && git add -A && git commit -m "update" && git push

# 3. Trigger build
# Open http://localhost:8888/job/copsi-test/ → Build with Parameters
```

## Feature cleanup on ABN deploy

When `deployAbn()` runs, it also cleans up obsolete feature deployments:

1. Lists remote branches in the code repo (`git ls-remote`)
2. Compares against `services/hint/features/*.yaml` files
3. Removes files whose JIRA ticket branch no longer exists
4. If no features remain → writes empty `kustomization.yaml` (`resources: []`)
5. All changes in one PR → ArgoCD removes stale features + deploys ABN atomically
