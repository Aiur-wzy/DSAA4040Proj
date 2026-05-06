#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
BACKEND_IMAGE="bookstore-backend:latest"
FRONTEND_IMAGE="bookstore-frontend:latest"
POSTGRES_IMAGE="postgres:16"
NODE_PORT="30080"

step() { printf '\n==== %s ====\n' "$1"; }
fail() { echo "Error: $1" >&2; exit 1; }
image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

step "Checking prerequisites"
resolve_kubectl
require_cmd docker
require_minikube
docker compose version >/dev/null 2>&1 || fail "docker compose plugin is required"
echo "Using Kubernetes command: ${KUBECTL_MODE}"

step "Checking Minikube status"
require_minikube_running
"${KUBECTL[@]}" get nodes >/dev/null

step "Using host Docker environment"
eval "$(minikube docker-env -u)"

step "Building Docker Compose images"
docker compose build

step "Verifying expected image tags exist"
image_exists "$BACKEND_IMAGE" || fail "missing image $BACKEND_IMAGE after docker compose build"
image_exists "$FRONTEND_IMAGE" || fail "missing image $FRONTEND_IMAGE after docker compose build"

step "Loading images into Minikube"
minikube image load "$BACKEND_IMAGE"
minikube image load "$FRONTEND_IMAGE"
if image_exists "$POSTGRES_IMAGE"; then
  minikube image load "$POSTGRES_IMAGE"
else
  echo "Warning: host image $POSTGRES_IMAGE not found; Minikube will pull it if needed."
fi

step "Applying namespace first"
"${KUBECTL[@]}" apply -f k8s/namespace.yaml
"${KUBECTL[@]}" wait --for=jsonpath='{.status.phase}'=Active "namespace/${NAMESPACE}" --timeout=60s

step "Creating/updating postgres-init-sql ConfigMap"
"${KUBECTL[@]}" create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

step "Applying database manifests"
"${KUBECTL[@]}" apply -f k8s/configmap.yaml
"${KUBECTL[@]}" apply -f k8s/secret.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-service.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-deployment.yaml

step "Waiting for PostgreSQL readiness"
"${KUBECTL[@]}" wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s

step "Ensuring postgres-init Job has completed"
if "${KUBECTL[@]}" get job postgres-init -n "$NAMESPACE" >/dev/null 2>&1; then
  succeeded="$("${KUBECTL[@]}" get job postgres-init -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
  if [[ "$succeeded" == "1" && "${FORCE_POSTGRES_INIT:-0}" != "1" ]]; then
    echo "postgres-init Job already completed; set FORCE_POSTGRES_INIT=1 to recreate it."
  else
    echo "Recreating postgres-init Job because it has not completed or FORCE_POSTGRES_INIT=1 was set."
    "${KUBECTL[@]}" delete job postgres-init -n "$NAMESPACE" --ignore-not-found
    "${KUBECTL[@]}" apply -f k8s/postgres-init-job.yaml
    "${KUBECTL[@]}" wait --for=condition=complete job/postgres-init -n "$NAMESPACE" --timeout=180s
  fi
else
  "${KUBECTL[@]}" apply -f k8s/postgres-init-job.yaml
  "${KUBECTL[@]}" wait --for=condition=complete job/postgres-init -n "$NAMESPACE" --timeout=180s
fi

step "Applying application manifests"
"${KUBECTL[@]}" apply -f k8s/backend-service.yaml
"${KUBECTL[@]}" apply -f k8s/backend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-service.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/ingress.yaml
"${KUBECTL[@]}" apply -f k8s/hpa.yaml

step "Restarting backend and frontend deployments"
"${KUBECTL[@]}" rollout restart deployment/backend -n "$NAMESPACE"
"${KUBECTL[@]}" rollout restart deployment/frontend -n "$NAMESPACE"

step "Waiting for rollout status"
"${KUBECTL[@]}" rollout status deployment/backend -n "$NAMESPACE" --timeout=240s
"${KUBECTL[@]}" rollout status deployment/frontend -n "$NAMESPACE" --timeout=240s

step "Deployment summary"
"${KUBECTL[@]}" get all -n "$NAMESPACE"
MINIKUBE_IP="$(minikube ip)"
cat <<URLS

Internal Minikube NodePort:
  http://${MINIKUBE_IP}:${NODE_PORT}

Public demo after expose script:
  http://<server-public-ip>:3000
URLS
