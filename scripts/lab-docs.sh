#!/usr/bin/env bash
# Start only the documentation services (Lab Guide + Storybook)
# Usage: ./scripts/lab-docs.sh
#        ./scripts/lab-docs.sh --stop

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--stop" ]]; then
  echo "Stopping Lab Guide and Storybook..."
  docker compose stop lab-guide storybook
  echo "Done."
  exit 0
fi

echo "Starting Lab Guide and Storybook..."
docker compose up -d lab-guide storybook

echo ""
echo "  Storybook:   http://localhost:4201"
echo "  Lab Guide:   http://localhost:4202"
