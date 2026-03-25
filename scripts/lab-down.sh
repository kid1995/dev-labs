#!/usr/bin/env bash
# Shut down the dev-labs environment quickly
# Usage: ./scripts/lab-down.sh         (preserve data)
#        ./scripts/lab-down.sh --clean  (destroy volumes too)

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--clean" ]]; then
  echo "Stopping all services and removing volumes..."
  docker compose down -v --remove-orphans
  echo "Done. All data destroyed."
else
  echo "Stopping all services (data preserved in volumes)..."
  docker compose down --remove-orphans
  echo "Done. Run './scripts/lab-up.sh' to restart."
fi
