#!/usr/bin/env bash
# Lab Git helper — safe wrapper for Gitea operations
# Prevents accidental pushes to wrong remotes
#
# Usage:
#   ./scripts/lab-git.sh status                  # Show all lab repos status
#   ./scripts/lab-git.sh push <repo>             # Push lab repo to Gitea
#   ./scripts/lab-git.sh push-all                # Push all lab repos to Gitea
#   ./scripts/lab-git.sh diff <repo>             # Show diff between lab (main) and original (si)
#   ./scripts/lab-git.sh log <repo>              # Show recent commits
#   ./scripts/lab-git.sh open <repo>             # Open repo in Gitea browser
#   ./scripts/lab-git.sh repos                   # List Gitea repos via API
#
# Dependencies:
#   jq  — JSON processor, used to parse Gitea API responses (brew install jq)

set -euo pipefail
cd "$(dirname "$0")/.."

GITEA_URL="http://localhost:3000"
GITEA_API="${GITEA_URL}/api/v1"
GITEA_AUTH="labadmin:labadmin"

# Known lab repos under src/
REPOS=("hint-backend" "dlt-manager" "design-system")

# ── Preflight ─────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

resolve_repo() {
  local name="$1"
  local repo_path="src/$name"
  if [[ ! -d "$repo_path/.git" ]]; then
    echo "Error: $repo_path is not a git repo"
    exit 1
  fi
  echo "$repo_path"
}

# ── Commands ──────────────────────────────────────────────────────

cmd_status() {
  printf "%-18s %-10s %-40s %s\n" "REPO" "BRANCH" "LAST COMMIT" "DIRTY?"
  printf "%-18s %-10s %-40s %s\n" "----" "------" "-----------" "------"

  for repo in "${REPOS[@]}"; do
    local path="src/$repo"
    if [[ ! -d "$path/.git" ]]; then
      printf "%-18s %s\n" "$repo" "(not cloned)"
      continue
    fi

    local branch last_commit dirty
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "detached")
    last_commit=$(git -C "$path" log -1 --format="%s" 2>/dev/null || echo "no commits")
    last_commit="${last_commit:0:38}"

    if git -C "$path" diff --quiet 2>/dev/null && git -C "$path" diff --cached --quiet 2>/dev/null; then
      dirty="clean"
    else
      dirty="DIRTY"
    fi

    printf "%-18s %-10s %-40s %s\n" "$repo" "$branch" "$last_commit" "$dirty"
  done
}

cmd_push() {
  local repo_path
  repo_path=$(resolve_repo "$1")

  local remote_url
  remote_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || echo "")

  if [[ "$remote_url" != *"localhost:3000"* && "$remote_url" != *"git.labs.local"* ]]; then
    echo "SAFETY: origin of $repo_path points to '$remote_url' — not Gitea!"
    echo "        Refusing to push. Fix with: git -C $repo_path remote set-url origin <gitea-url>"
    exit 1
  fi

  echo "Pushing $1 to Gitea..."
  git -C "$repo_path" push origin --all
  echo "Done."
}

cmd_push_all() {
  for repo in "${REPOS[@]}"; do
    if [[ -d "src/$repo/.git" ]]; then
      cmd_push "$repo"
    fi
  done
}

cmd_diff() {
  local repo_path
  repo_path=$(resolve_repo "$1")

  local has_si
  has_si=$(git -C "$repo_path" branch -a 2>/dev/null | grep -c "si" || true)

  if [[ "$has_si" -eq 0 ]]; then
    echo "No 'si' branch found in $1. Push original code first."
    exit 1
  fi

  echo "=== Changes: main (lab) vs si (original) in $1 ==="
  git -C "$repo_path" diff si..main --stat
}

cmd_log() {
  local repo_path
  repo_path=$(resolve_repo "$1")
  git -C "$repo_path" log --oneline -15
}

cmd_open() {
  local url="${GITEA_URL}/lab/$1"
  echo "Opening $url"
  open "$url" 2>/dev/null || xdg-open "$url" 2>/dev/null || echo "Visit: $url"
}

cmd_repos() {
  echo "Gitea repos (lab org):"
  echo ""
  curl -s -u "$GITEA_AUTH" "${GITEA_API}/orgs/lab/repos" \
    | jq -r '.[] | "  \(.name)\t\(.html_url)\tbranches: \(.default_branch)"'
}

cmd_help() {
  echo "lab-git — safe Gitea operations for dev-labs"
  echo ""
  echo "Usage: ./scripts/lab-git.sh <command> [repo]"
  echo ""
  echo "Commands:"
  echo "  status             Show all lab repos status"
  echo "  push <repo>        Push repo to Gitea (with safety check)"
  echo "  push-all           Push all lab repos"
  echo "  diff <repo>        Diff between main (lab) and si (original)"
  echo "  log <repo>         Show recent commits"
  echo "  open <repo>        Open repo in browser"
  echo "  repos              List Gitea repos via API"
  echo ""
  echo "Repos: ${REPOS[*]}"
}

# ── Main ──────────────────────────────────────────────────────────
case "${1:-help}" in
  status)    cmd_status ;;
  push)      cmd_push "${2:?Usage: lab-git.sh push <repo>}" ;;
  push-all)  cmd_push_all ;;
  diff)      cmd_diff "${2:?Usage: lab-git.sh diff <repo>}" ;;
  log)       cmd_log "${2:?Usage: lab-git.sh log <repo>}" ;;
  open)      cmd_open "${2:?Usage: lab-git.sh open <repo>}" ;;
  repos)     cmd_repos ;;
  *)         cmd_help ;;
esac
