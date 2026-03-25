# Active Workarounds

Things that work but aren't ideal. Each has a reason and a "proper fix" path.

## 1. arm64 base image substitute

**What:** K8s pods use `eclipse-temurin:21-jre-alpine` instead of corporate `sda-jre21-alpine:100`.

**Why:** Corporate image is amd64-only. kind on Mac runs arm64 nodes. Can't pull amd64 images.

**Impact:** Slightly different JRE config. Corporate image has proxy settings, `/tmp/setPermissions.sh`, and `java` user. Lab image recreates these manually.

**Proper fix:** Corporate provides multi-arch base image, or lab uses a QEMU-based amd64 kind node.

## 2. AUTH_USERS uses Keycloak UUID

**What:** `values-lab-tst.yaml` has `authUsers: "08210d1d-6dc7-4bd0-8231-8f9749d3671d"` (UUID).

**Why:** Keycloak `sub` claim = UUID. Corporate `sub` = employee ID (S000325). The app checks `sub` for authorization. Keycloak dev mode doesn't persist user attribute changes (employee_id).

**Impact:** If Keycloak data is lost (volume recreated), the UUID changes and AUTH_USERS breaks.

**Proper fix:** Bake user attributes into `lab-realm.json` so they survive reimport. Or use a sub-override mapper with persistent storage.

## 3. Postgres/Keycloak IPs in K8s Endpoints

**What:** K8s Endpoints for external services use hardcoded Docker container IPs.

**Why:** Headless Service + manual Endpoints is how K8s connects to non-K8s services. Docker IPs change on restart.

**Impact:** After Docker restart, must re-apply manifests with fresh IPs.

**Proper fix:** Run Postgres and Keycloak inside K8s too. Or use a sidecar/init container that resolves the Docker DNS name.

## 4. Jenkins config lost on restart

**What:** Global Pipeline Libraries and credentials must be reconfigured after Jenkins restart.

**Why:** Jenkins LTS with no JCasC plugin. Config is in-memory for some settings.

**Impact:** Run `setup-jenkins-libs.sh` after every Jenkins restart.

**Proper fix:** Install JCasC plugin and mount a `jenkins.yaml` config file.

## 5. Keycloak frontendUrl side effect

**What:** After setting `frontendUrl=http://keycloak:8080`, the admin console may redirect to `keycloak:8080` which doesn't resolve from the browser.

**Why:** Keycloak uses frontendUrl for all redirects, including admin console.

**Impact:** Minor annoyance. Access admin via `localhost:8180` and ignore bad redirects.

**Proper fix:** Use separate hostname settings for admin vs frontend in Keycloak 24+.

## 6. Empty features/ kustomization

**What:** When all feature deployments are cleaned up, `features/kustomization.yaml` has `resources: []`.

**Why:** Parent kustomization references `features/`. Deleting the directory would break kustomize. Empty `resources: []` is valid kustomize.

**Impact:** None — works correctly. ArgoCD syncs fine with empty resources.

**Proper fix:** This IS the proper fix. No change needed.

## 7. si_copsi.groovy is a full rewrite for Gitea

**What:** The lab si_copsi.groovy rewrites all Bitbucket API calls to Gitea API calls using `isGitea()` switch.

**Why:** Bitbucket and Gitea have completely different REST API formats. No abstraction layer exists in the corporate code.

**Impact:** Changes to corporate si_copsi.groovy must be manually ported to the lab version.

**Proper fix:** Extract a `GitPlatform` interface in corporate code. Implement `BitbucketPlatform` and `GiteaPlatform`. But this requires corporate team buy-in.
