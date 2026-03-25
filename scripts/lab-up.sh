#!/usr/bin/env bash
# Start the dev-labs environment and wait for services to be healthy
# Usage: ./scripts/lab-up.sh

set -euo pipefail
cd "$(dirname "$0")/.."

echo "Starting all services..."
docker compose up -d

echo ""
echo "Waiting for services to become healthy..."

services=(lab-gitea lab-jenkins lab-keycloak lab-postgres lab-kafka lab-hint-backend lab-dlt-backend lab-dlt-frontend lab-storybook lab-guide)

max_wait=180
elapsed=0

while (( elapsed < max_wait )); do
  all_healthy=true
  for svc in "${services[@]}"; do
    status=$(docker inspect --format='{{.State.Health.Status}}' "$svc" 2>/dev/null || echo "missing")
    if [[ "$status" != "healthy" ]]; then
      all_healthy=false
      break
    fi
  done

  if $all_healthy; then
    echo ""
    echo "All services healthy!"
    echo ""
    echo "  Gitea:          http://localhost:3000    (labadmin/labadmin)"
    echo "  Jenkins:        http://localhost:8888"
    echo "  Keycloak:       http://localhost:8180    (admin/admin)"
    echo "  Hint Swagger:   http://localhost:8080/api/docs/rest"
    echo "  DLT Swagger:    http://localhost:8082/api/docs/rest"
    echo "  DLT Frontend:   http://localhost:4200"
    echo "  Storybook:      http://localhost:4201"
    echo "  Lab Guide:      http://localhost:4202"
    exit 0
  fi

  sleep 5
  elapsed=$((elapsed + 5))
  # Show progress every 15 seconds
  if (( elapsed % 15 == 0 )); then
    echo "  [${elapsed}s] Waiting... ($(docker compose ps --format '{{.Name}} {{.Status}}' | grep -c healthy || true) healthy so far)"
  fi
done

echo ""
echo "Warning: Timed out after ${max_wait}s. Some services may still be starting."
echo "Check status with: docker compose ps"
exit 1
