#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Auto-detect JAVA_HOME if not set
if [ -z "${JAVA_HOME:-}" ]; then
    if command -v java >/dev/null 2>&1; then
        export JAVA_HOME=$(java -XshowSettings:properties -version 2>&1 | grep 'java.home' | awk '{print $NF}')
    fi
fi

# Java library paths — override via env vars for other machines
JAVA_LIBS_DIR="${JAVA_LIBS_DIR:-${ROOT_DIR}/../java_libs}"

echo "============================================"
echo "  Local DevOps Lab — Full Bootstrap"
echo "============================================"
echo ""
echo "  JAVA_HOME:     ${JAVA_HOME:-not set}"
echo "  JAVA_LIBS_DIR: ${JAVA_LIBS_DIR}"
echo "  ROOT_DIR:      ${ROOT_DIR}"
echo ""

# ---- Step 1: Build internal libraries ----
echo "=== Step 1: Building internal Java libraries ==="

if [ -d "${JAVA_LIBS_DIR}/jwt-adapter" ]; then
    echo "  Building jwt-adapter (2.5.0 + 2.5.1-SNAPSHOT)..."
    cd "${JAVA_LIBS_DIR}/jwt-adapter"
    ./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze -Pversion=2.5.0 --no-daemon -q
    ./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze --no-daemon -q
    echo "  jwt-adapter installed to mavenLocal"
else
    echo "  Skipping jwt-adapter (not found at ${JAVA_LIBS_DIR}/jwt-adapter)"
fi

if [ -d "${JAVA_LIBS_DIR}/elpa4-shared-lib/elpa4-model" ]; then
    echo "  Building elpa4-model (1.1.1 + 1.1.1-SNAPSHOT)..."
    cd "${JAVA_LIBS_DIR}/elpa4-shared-lib/elpa4-model"
    ./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze -Pversion=1.1.1 --no-daemon -q
    ./gradlew publishToMavenLocal -x check -x test -x dependencyCheckAnalyze --no-daemon -q
    echo "  elpa4-model installed to mavenLocal"
else
    echo "  Skipping elpa4-model (not found at ${JAVA_LIBS_DIR}/elpa4-shared-lib/elpa4-model)"
fi

# ---- Step 2: Build hint backend ----
echo ""
echo "=== Step 2: Building hint backend ==="
cd "$ROOT_DIR/src/hint-backend"
./gradlew build -x check -x test -x dependencyCheckAnalyze --no-daemon -q
./gradlew :hint-service:installDist --no-daemon -q
echo "  hint-service built and installDist complete"

# ---- Step 3: Build dlt-manager backend ----
echo ""
echo "=== Step 3: Building dlt-manager backend ==="
cd "$ROOT_DIR/src/dlt-manager"
./gradlew build -x check -x test -x dependencyCheckAnalyze -x rewriteRun -x rewriteDryRun --no-daemon -q
./gradlew :backend:installDist --no-daemon -q
echo "  dlt-manager backend built and installDist complete"

# ---- Step 4: Build dlt-manager frontend ----
echo ""
echo "=== Step 4: Building dlt-manager frontend ==="
cd "$ROOT_DIR/src/dlt-manager/frontend"
npx ng build --configuration production 2>&1 | tail -5
echo "  dlt-manager frontend built"

# ---- Step 5: Build Docker images ----
echo ""
echo "=== Step 5: Building Docker images ==="

echo "  Building lab/hint-backend..."
cd "$ROOT_DIR/src/hint-backend"
docker build -f "$ROOT_DIR/docker/hint-backend.Dockerfile" -t lab/hint-backend:latest . -q

echo "  Building lab/dlt-backend..."
cd "$ROOT_DIR/src/dlt-manager"
docker build -f "$ROOT_DIR/docker/dlt-backend.Dockerfile" -t lab/dlt-backend:latest . -q

echo "  Building lab/dlt-frontend..."
cd "$ROOT_DIR/src/dlt-manager/frontend"
docker build -f "$ROOT_DIR/docker/dlt-frontend.Dockerfile" -t lab/dlt-frontend:latest . -q

echo "  All Docker images built"

# ---- Step 6: Start with docker-compose ----
echo ""
echo "=== Step 6: Starting services with Docker Compose ==="
cd "$ROOT_DIR"
docker compose up -d
echo ""
echo "============================================"
echo "  Lab is starting up!"
echo "============================================"
echo ""
echo "Services:"
echo "  Hint Backend API:    http://localhost:8080/api/hints"
echo "  Hint Swagger:        http://localhost:8080/api/docs/rest"
echo "  Hint Health:         http://localhost:8081/health"
echo "  DLT Backend API:     http://localhost:8082/api/events/overview"
echo "  DLT Swagger:         http://localhost:8082/api/docs/rest"
echo "  DLT Health:          http://localhost:8083/health"
echo "  DLT Frontend:        http://localhost:4200"
echo "  Keycloak:            http://localhost:8180 (admin/admin)"
echo "  PostgreSQL:          localhost:5432 (db_user/db_password)"
echo "  Kafka:               localhost:9092"
echo ""
echo "Bruno collection: import from config/bruno/"
