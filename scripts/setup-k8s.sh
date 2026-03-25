#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "============================================"
echo "  K8s Lab Setup (k3d + Istio)"
echo "============================================"

# ---- Prerequisites check ----
echo ""
echo "=== Checking prerequisites ==="
for cmd in docker kubectl k3d istioctl helm; do
    if command -v "$cmd" &>/dev/null; then
        echo "  $cmd: $(command -v "$cmd")"
    else
        echo "  ERROR: $cmd not found. Please install it first."
        exit 1
    fi
done

# ---- Step 1: Create k3d cluster ----
echo ""
echo "=== Step 1: Creating k3d cluster ==="
k3d cluster delete lab 2>/dev/null || true
k3d cluster create lab \
    --api-port 6550 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --agents 2 \
    --k3s-arg "--disable=traefik@server:*"
echo "  k3d cluster 'lab' created"

# ---- Step 2: Load Docker images into k3d ----
echo ""
echo "=== Step 2: Loading Docker images into k3d ==="
k3d image import lab/hint-backend:latest lab/dlt-backend:latest lab/dlt-frontend:latest -c lab
echo "  Images loaded"

# ---- Step 3: Install Istio ----
echo ""
echo "=== Step 3: Installing Istio ==="
istioctl install --set profile=demo -y
echo "  Istio installed"

# ---- Step 4: Create namespaces ----
echo ""
echo "=== Step 4: Creating namespaces ==="
kubectl apply -f "$ROOT_DIR/k8s/namespaces.yaml"
echo "  Namespaces created"

# ---- Step 5: Deploy infrastructure ----
echo ""
echo "=== Step 5: Deploying infrastructure (Postgres, Kafka, Keycloak) ==="
kubectl apply -f "$ROOT_DIR/k8s/apps-dev/infra/secrets.yaml"
kubectl apply -f "$ROOT_DIR/k8s/apps-dev/infra/postgres.yaml"
kubectl apply -f "$ROOT_DIR/k8s/apps-dev/infra/kafka.yaml"
kubectl apply -f "$ROOT_DIR/k8s/apps-dev/infra/keycloak.yaml"

echo "  Waiting for Postgres to be ready..."
kubectl wait --for=condition=ready pod -l app=postgres -n apps-dev --timeout=120s
echo "  Waiting for Kafka to be ready..."
kubectl wait --for=condition=ready pod -l app=kafka -n apps-dev --timeout=120s
echo "  Infrastructure deployed"

# ---- Step 6: Deploy applications ----
echo ""
echo "=== Step 6: Deploying applications ==="
kubectl apply -f "$ROOT_DIR/k8s/apps-dev/backend/hint-deployment.yaml"
kubectl apply -f "$ROOT_DIR/k8s/apps-dev/backend/dlt-deployment.yaml"
kubectl apply -f "$ROOT_DIR/k8s/apps-dev/frontend/dlt-frontend-deployment.yaml"
echo "  Applications deployed"

# ---- Step 7: Configure Istio gateway ----
echo ""
echo "=== Step 7: Configuring Istio gateway & routing ==="
kubectl apply -f "$ROOT_DIR/k8s/gateway/istio-gateway.yaml"
kubectl apply -f "$ROOT_DIR/k8s/gateway/virtual-services.yaml"
kubectl apply -f "$ROOT_DIR/k8s/gateway/destination-rules.yaml"
echo "  Gateway configured"

# ---- Step 8: Wait for apps ----
echo ""
echo "=== Step 8: Waiting for applications to be ready ==="
kubectl wait --for=condition=ready pod -l app=hint-backend -n apps-dev --timeout=180s 2>/dev/null || echo "  hint-backend still starting..."
kubectl wait --for=condition=ready pod -l app=dlt-backend -n apps-dev --timeout=180s 2>/dev/null || echo "  dlt-backend still starting..."
kubectl wait --for=condition=ready pod -l app=dlt-frontend -n apps-dev --timeout=60s 2>/dev/null || echo "  dlt-frontend still starting..."

echo ""
echo "============================================"
echo "  K8s Lab is ready!"
echo "============================================"
echo ""
echo "Add to /etc/hosts:"
echo "  127.0.0.1  hint.lab.local dlt.lab.local dlt-ui.lab.local keycloak.lab.local"
echo ""
echo "Access:"
echo "  Hint API:       http://hint.lab.local/api/hints"
echo "  DLT API:        http://dlt.lab.local/api/events/overview"
echo "  DLT Frontend:   http://dlt-ui.lab.local"
echo "  Keycloak:       http://keycloak.lab.local (admin/admin)"
echo ""
echo "Port-forward (alternative):"
echo "  kubectl port-forward svc/hint-backend -n apps-dev 8080:8080"
echo "  kubectl port-forward svc/dlt-backend -n apps-dev 8082:8080"
echo "  kubectl port-forward svc/dlt-frontend -n apps-dev 4200:80"
echo ""
echo "Bruno: Use port-forwarded URLs for testing"
