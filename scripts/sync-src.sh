#!/bin/bash
set -euo pipefail

# Sync source projects from github-buffer into dev-labs/src/.
# Each entry maps a src/ directory name to its github-buffer source.
# The inner .git directories are preserved so Gitea remotes keep working.
#
# Usage:
#   ./scripts/sync-src.sh            # sync all projects
#   ./scripts/sync-src.sh hint-backend  # sync one project

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$ROOT_DIR/src"
BUFFER_DIR="$(dirname "$ROOT_DIR")"   # github-buffer/

# ---- Project mapping: src_name -> github-buffer directory ----
# Add new projects here. Format: "src_name:buffer_name"
PROJECTS=(
  "hint-backend:combine-hint"
  "dlt-manager:dlt-manager"
  "design-system:design-system"
)

sync_project() {
  local src_name="$1"
  local buffer_name="$2"
  local source="$BUFFER_DIR/$buffer_name"
  local target="$SRC_DIR/$src_name"

  if [ ! -d "$source" ]; then
    echo "  SKIP  $src_name — source not found: $source"
    return 1
  fi

  echo "  SYNC  $src_name <- $buffer_name"

  # Preserve inner .git if it exists (Gitea remotes)
  local git_backup=""
  if [ -d "$target/.git" ]; then
    git_backup="$(mktemp -d)"
    mv "$target/.git" "$git_backup/.git"
  fi

  # rsync files, excluding .git from source
  mkdir -p "$target"
  rsync -a --delete \
    --exclude '.git' \
    --exclude '.gradle' \
    --exclude 'build' \
    --exclude 'node_modules' \
    --exclude '.angular' \
    "$source/" "$target/"

  # Restore inner .git
  if [ -n "$git_backup" ]; then
    mv "$git_backup/.git" "$target/.git"
    rm -rf "$git_backup"
  fi

  echo "         done"
}

# ---- Main ----
echo "============================================"
echo "  Syncing src/ from github-buffer"
echo "============================================"
echo ""

filter="${1:-}"

synced=0
for entry in "${PROJECTS[@]}"; do
  src_name="${entry%%:*}"
  buffer_name="${entry##*:}"

  # If a filter was given, only sync that project
  if [ -n "$filter" ] && [ "$src_name" != "$filter" ]; then
    continue
  fi

  sync_project "$src_name" "$buffer_name" && ((synced++)) || true
done

echo ""
if [ "$synced" -eq 0 ]; then
  echo "No projects synced. Check project names or github-buffer directory."
  echo "Available: ${PROJECTS[*]}"
  exit 1
fi
echo "$synced project(s) synced."
echo ""
echo "To add a new project, edit the PROJECTS array in this script."
