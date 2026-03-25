#!/bin/bash
set -euo pipefail

# Copies internal mavenLocal dependencies into .m2-cache folders
# so Docker builds can find jwt-adapter, elpa4-model etc.

M2_REPO="$HOME/.m2/repository"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Preparing .m2-cache for Docker builds ==="

# Helper: copy a maven artifact group/artifact/version into target .m2-cache
copy_artifact() {
    local group_path="$1"
    local artifact="$2"
    local version="$3"
    local target_dir="$4"

    local src="$M2_REPO/$group_path/$artifact/$version"
    local dst="$target_dir/.m2-cache/$group_path/$artifact/$version"

    if [ -d "$src" ]; then
        mkdir -p "$dst"
        cp -r "$src/"* "$dst/"
        echo "  Copied $group_path/$artifact/$version"
    else
        echo "  WARNING: $src not found — run publishToMavenLocal first"
    fi
}

# Hint backend needs jwt-adapter 2.5.1-SNAPSHOT
HINT_DIR="$ROOT_DIR/projects/hint-backend"
echo ""
echo "--- Hint Backend ---"
copy_artifact "de/signaliduna/elpa" "jwt-adapter" "2.5.1-SNAPSHOT" "$HINT_DIR"

# DLT-Manager backend needs jwt-adapter 2.5.0 and elpa4-model 1.1.1
DLT_DIR="$ROOT_DIR/projects/dlt-backend"
echo ""
echo "--- DLT-Manager Backend ---"
copy_artifact "de/signaliduna/elpa" "jwt-adapter" "2.5.0" "$DLT_DIR"
copy_artifact "de/signaliduna/elpa" "elpa4-model" "1.1.1" "$DLT_DIR"

echo ""
echo "=== Done ==="
