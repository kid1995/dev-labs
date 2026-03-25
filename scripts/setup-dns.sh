#!/usr/bin/env bash
# Manage local DNS and nginx proxy config from config/proxy/routes.yaml
#
# Usage:
#   sudo ./scripts/setup-dns.sh              # Add /etc/hosts entries
#   sudo ./scripts/setup-dns.sh --remove     # Remove /etc/hosts entries
#   ./scripts/setup-dns.sh --regenerate      # Regenerate nginx.conf + update /etc/hosts
#   ./scripts/setup-dns.sh --list            # Show current routes
#
# Dependencies (install via brew):
#   yq  — YAML parser/processor, used to read routes.yaml (brew install yq)

set -euo pipefail
cd "$(dirname "$0")/.."

ROUTES_FILE="config/proxy/routes.yaml"
NGINX_CONF="config/proxy/nginx.conf"
HOSTS_FILE="/etc/hosts"
MARKER="# dev-labs"

# ── Preflight checks ──────────────────────────────────────────────
if ! command -v yq &>/dev/null; then
  echo "Error: yq is required. Install with: brew install yq"
  exit 1
fi

if [[ ! -f "$ROUTES_FILE" ]]; then
  echo "Error: $ROUTES_FILE not found"
  exit 1
fi

# ── Commands ──────────────────────────────────────────────────────

cmd_list() {
  echo "Routes from $ROUTES_FILE:"
  echo ""
  printf "  %-32s %-28s %s\n" "HOSTNAME" "TARGET" "DESCRIPTION"
  printf "  %-32s %-28s %s\n" "--------" "------" "-----------"

  local count
  count=$(yq '.routes | length' "$ROUTES_FILE")
  for ((i = 0; i < count; i++)); do
    local hostname target desc
    hostname=$(yq ".routes[$i].hostname" "$ROUTES_FILE")
    target=$(yq ".routes[$i].target" "$ROUTES_FILE")
    desc=$(yq ".routes[$i].description" "$ROUTES_FILE")
    printf "  %-32s %-28s %s\n" "http://$hostname" "$target" "$desc"
  done
}

cmd_generate_nginx() {
  echo "Generating $NGINX_CONF from $ROUTES_FILE..."

  {
    echo "# AUTO-GENERATED from routes.yaml — do not edit manually"
    echo "# Regenerate with: ./scripts/setup-dns.sh --regenerate"
    echo ""

    local count
    count=$(yq '.routes | length' "$ROUTES_FILE")
    for ((i = 0; i < count; i++)); do
      local hostname target desc max_body
      hostname=$(yq ".routes[$i].hostname" "$ROUTES_FILE")
      target=$(yq ".routes[$i].target" "$ROUTES_FILE")
      desc=$(yq ".routes[$i].description" "$ROUTES_FILE")
      max_body=$(yq ".routes[$i].client_max_body_size // \"\"" "$ROUTES_FILE")

      echo "# $desc"
      echo "server {"
      echo "    listen 80;"
      echo "    server_name $hostname;"
      if [[ -n "$max_body" ]]; then
        echo "    client_max_body_size $max_body;"
      fi
      echo "    location / {"
      echo "        proxy_pass http://$target;"
      echo "        proxy_set_header Host \$host;"
      echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;"
      echo "        proxy_set_header X-Forwarded-Proto \$scheme;"
      echo "    }"
      echo "}"
      echo ""
    done
  } > "$NGINX_CONF"

  echo "Done. Restart proxy: docker compose restart proxy"
}

cmd_add_hosts() {
  if grep -q "$MARKER" "$HOSTS_FILE" 2>/dev/null; then
    echo "Entries already exist in $HOSTS_FILE. Use --remove first or --regenerate."
    exit 0
  fi

  echo "Adding entries to $HOSTS_FILE..."
  echo "" >> "$HOSTS_FILE"

  local count
  count=$(yq '.routes | length' "$ROUTES_FILE")
  for ((i = 0; i < count; i++)); do
    local hostname desc
    hostname=$(yq ".routes[$i].hostname" "$ROUTES_FILE")
    desc=$(yq ".routes[$i].description" "$ROUTES_FILE")
    printf "127.0.0.1  %-32s %s\n" "$hostname" "$MARKER — $desc" >> "$HOSTS_FILE"
  done

  echo "Done."
  cmd_list
}

cmd_remove_hosts() {
  echo "Removing dev-labs entries from $HOSTS_FILE..."
  # Use grep to filter out lines instead of sed -i (more portable)
  grep -v "$MARKER" "$HOSTS_FILE" > "${HOSTS_FILE}.tmp" || true
  mv "${HOSTS_FILE}.tmp" "$HOSTS_FILE"
  echo "Done."
}

cmd_regenerate() {
  cmd_generate_nginx
  if [[ -w "$HOSTS_FILE" ]] || [[ "$EUID" -eq 0 ]]; then
    cmd_remove_hosts
    cmd_add_hosts
  else
    echo ""
    echo "Note: Run with sudo to also update /etc/hosts"
  fi
}

# ── Main ──────────────────────────────────────────────────────────
case "${1:-}" in
  --list)       cmd_list ;;
  --remove)     cmd_remove_hosts ;;
  --regenerate) cmd_regenerate ;;
  *)            cmd_add_hosts ;;
esac
