# Gotchas — Things That Will Bite You

## 0. Always verify CLI tool behavior before assuming

Claude (or any AI) may state CLI arguments are "required" when they are optional. Example: `helm template` does NOT require a release name — it was stated as mandatory, which led to an unnecessary `serviceName` parameter being threaded through multiple functions.

Rule: if a tool's behavior is claimed but not verified, run a quick test before building on the assumption. One wrong "fact" about a CLI can propagate into architecture decisions.

## 1. Jenkins pipeline sandbox blocks Groovy methods

**Symptom:** `No signature of method` or `SecurityException` in pipeline logs.

**Why:** Jenkins Script Security plugin sandboxes pipeline code. Even shared library `vars/` scripts are affected when operating on objects from the pipeline context.

**Blocked methods and safe alternatives:**

| Blocked | Use instead |
|---|---|
| `new File(x).parent` | `x.substring(0, x.lastIndexOf('/'))` |
| `new File(x).name` | `x.substring(x.lastIndexOf('/') + 1)` |
| `array.getAt(0)` | `array[0]` |
| `new URL()` | `httpRequest` or `sh "curl ..."` |
| `java.io.*` / `java.net.*` | Pipeline steps (`readFile`, `writeFile`, `sh`) |

**Fix:** Check pending approvals at Jenkins > Manage > In-process Script Approval. Or rewrite to avoid blocked methods.

## 2. Keycloak token issuer mismatch

**Symptom:** 401 Unauthorized from hint-service even with valid-looking token.

**Why:** Token `iss` = `http://localhost:8180/realms/lab` but app checks against `AUTH_URL` = `http://keycloak:8080/realms/lab`. Exact match required, including trailing slash.

**Fix:** Run `./scripts/setup-keycloak-lab.sh` — sets Keycloak `frontendUrl` so tokens always use `keycloak:8080` as issuer.

**See:** docs/keycloak-setup.md for full details.

## 3. Keycloak sub claim vs AUTH_USERS

**Symptom:** 403 "Access Denied" (not 401). Token is valid but authorization fails.

**Why:** `getAuthentication().getName()` returns JWT `sub` claim. In Keycloak, `sub` = UUID. In corporate, `sub` = employee ID (S000325). `AUTH_USERS=admin` doesn't match UUID.

**Fix:** `values-lab-tst.yaml` sets `authUsers` to the Keycloak UUID. Not elegant but works.

## 4. K8s Deployment selector immutability

**Symptom:** ArgoCD sync fails with "spec.selector: field is immutable".

**Why:** Switching between values files changes labels (e.g., `external: "true"` → `"false"`). K8s doesn't allow changing Deployment selectors after creation.

**Fix:** Delete the Deployment before switching values: `kubectl -n elpa-elpa4 delete deploy tst-hint`

## 5. kind + arm64 Mac + amd64 base image

**Symptom:** ImagePullBackOff with "no match for platform in manifest".

**Why:** Corporate base image (sda-jre21-alpine) is amd64-only. kind on Mac runs arm64 nodes.

**Fix:** Build with `eclipse-temurin:21-jre-alpine` (multi-arch) for K8s. The real base image works for Docker Compose (Rosetta emulation) but not in kind. See 04-workarounds.md.

## 6. Docker Registry image caching in kind

**Symptom:** Pod runs old image even after pushing new `:latest` to registry.

**Why:** containerd caches images by tag. `imagePullPolicy: IfNotPresent` won't repull `:latest`.

**Fix:** Either:
- Clear cache: `docker exec dev-lab-control-plane crictl rmi registry:5000/image:latest`
- Use `imagePullPolicy: Always` in lab values (already set in values-lab-tst.yaml)

## 7. Helm values path — Docker vs local

**Symptom:** `Error: open values-tst.yaml: no such file or directory`

**Why:** Corporate runs helm inside Docker container where chart root = `/helm`. Lab runs helm from workspace root where chart = `./copsi`. Values paths differ.

**Fix:** `generateTemplate()` in elpa_copsi.groovy auto-prefixes `copsi/` for local helm. Don't change the values file paths in the deploy functions.

## 8. Jenkins BRANCH_NAME not set in pipeline jobs

**Symptom:** Branch is always `develop` even when pointing to a feature branch.

**Why:** `env.BRANCH_NAME` is only set by multibranch pipelines. Regular pipeline jobs don't set it.

**Fix:** Jenkinsfile captures it from `checkout scm` return value:
```groovy
def scmVars = checkout scm
env.BRANCH_NAME = env.BRANCH_NAME ?: scmVars.GIT_BRANCH?.replaceFirst('origin/', '')
```

## 9. Port 5000 conflict on macOS

**Symptom:** Docker Registry fails to start on port 5000.

**Why:** macOS AirPlay Receiver uses port 5000.

**Fix:** Lab uses port 5050 for host mapping. Internally it's still 5000. Push: `localhost:5050`, Pull from K8s: `registry:5000`.

## 10. Docker disk space

**Symptom:** Postgres/Keycloak crash with "No space left on device".

**Why:** Docker Desktop has limited disk. Images + volumes accumulate.

**Fix:** `docker system prune -f` or increase Docker Desktop disk allocation.

## 11. @Library must be on line 1

**Symptom:** `unexpected char: '#'` compilation error in Jenkinsfile.

**Why:** `#!groovy` shebang can't appear after comments. `@Library` annotation must be the first non-comment line.

**Fix:** Put `@Library(['si-dp-shared-libs', 'elpa-shared-lib']) _` on line 1, comments after.

## 12. Postgres/Keycloak IP changes after restart

**Symptom:** K8s pods can't reach Postgres or Keycloak after Docker restart.

**Why:** Docker assigns new IPs on restart. K8s Endpoints have hardcoded IPs.

**Fix:** Re-run the infra setup script to refresh Endpoints with new IPs.

## 13. Jenkins needs reconfiguration after restart

**Symptom:** Shared libraries not found after Jenkins container restart.

**Why:** Global Pipeline Libraries config doesn't persist in the lab setup (no JCasC).

**Fix:** Re-run `./scripts/setup-jenkins-libs.sh` after Jenkins restart.
Also re-run `./scripts/prepare-m2-cache.sh` for mavenLocal deps.
