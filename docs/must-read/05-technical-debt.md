# Technical Debt

Known issues ranked by impact. Fix when time allows.

## High — breaks things regularly

### Jenkins config persistence
Jenkins Global Pipeline Libraries, credentials, and env vars are lost on restart.
Need JCasC plugin with a mounted `jenkins.yaml`.

### Keycloak realm completeness
The `lab-realm.json` import doesn't include:
- Protocol mappers (preferred_username, sub-override)
- User attributes (employee_id)
- Frontend URL setting

Must run `setup-keycloak-lab.sh` after every Keycloak restart.
Fix: export a complete realm JSON with all mappers and reimport.

### Docker container IP drift
Postgres and Keycloak Endpoints in K8s use hardcoded IPs.
After Docker restart, IPs change and K8s can't reach them.
Need a refresh script or move these services into K8s.

## Medium — causes confusion

### extractJiraReferenceFromCommit bug
The original `si_git.extractJiraReferenceFromCommit()` strips ALL non-digits from the
remainder after finding the prefix. `"ELPA4-123 fix for ELPA4-456"` returns `"ELPA4-123456"`.
Should stop at the first non-digit after the number.

### elpa-copsi.groovy filename vs Jenkins var name
File is `elpa-copsi.groovy` (with hyphen) but Jenkins loads it as `elpa_copsi` (with underscore).
The lab version uses `elpa_copsi.groovy` directly. This works but confuses newcomers.

### abn-hint pod still uses corporate values
Only `values-lab-tst.yaml` exists. No `values-lab-abn.yaml`.
The abn-hint deployment uses corporate Kafka (OAUTHBEARER) which doesn't work in lab.
Need to create lab ABN values and a `deployLabAbn()` function.

### Verify stage in Jenkinsfile runs for all branches
The JIRA ticket verification in Jenkinsfile.copsi-test checks every branch.
In the real Jenkinsfile, trunk branches (master/develop) should skip this
because they deploy via merge, not direct commit.

## Low — nice to have

### No automated test for setup scripts
The `test-*.sh` scripts validate prerequisites but don't test the actual setup flow.
Could add integration tests that spin up everything and verify end-to-end.

### README.md and CLAUDE.md out of sync
The README was updated with ArgoCD and registry info, but CLAUDE.md still describes
the original Docker Compose-only setup. Should converge or make CLAUDE.md reference README.

### No Istio control plane
Only Istio CRDs are installed (for VirtualService definitions). No actual service mesh.
VirtualServices are accepted but traffic isn't routed through sidecars.
Low priority — CoPSI testing doesn't need actual mesh routing.

### base image not in lab-realm.json
The sda-jre21-alpine:100 base image is manually loaded from a tar.gz.
Should document where to get it and how to update it.
