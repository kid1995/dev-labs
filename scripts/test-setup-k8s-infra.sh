#!/bin/bash
set -e
# Test: verify k8s infra prerequisites
PASS=0; FAIL=0
check() { if eval "$1" > /dev/null 2>&1; then echo "  ok: $2"; PASS=$((PASS+1)); else echo "  FAIL: $2"; FAIL=$((FAIL+1)); fi; }
check "kubectl --context kind-dev-lab get ns elpa-elpa4" "namespace exists"
check "docker inspect lab-postgres --format '{{.State.Running}}' | grep true" "lab-postgres running"
check "docker network inspect lab-net -f '{{range .Containers}}{{.Name}} {{end}}' | grep dev-lab-control-plane" "kind on lab-net"
check "test -f /Users/thekietdang/Downloads/github-buffer/dev-labs/k8s/elpa-elpa4/kafka.yaml" "kafka manifest"
check "test -f /Users/thekietdang/Downloads/github-buffer/dev-labs/k8s/elpa-elpa4/postgres-external.yaml" "postgres manifest"
echo "=== ${PASS} passed, ${FAIL} failed ==="
