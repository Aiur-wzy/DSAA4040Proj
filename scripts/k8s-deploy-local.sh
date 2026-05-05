#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

NAMESPACE="bookstore"

step() { echo; echo "==== $1 ===="; }
fail() { echo "Error: $1" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "required command '$1' not found in PATH"; }
image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

step "Checking prerequisites"
require_cmd docker
require_cmd minikube
require_cmd kubectl
require_cmd curl

docker compose version >/dev/null 2>&1 || fail "docker compose plugin is required"

step "Checking Minikube status"
if ! minikube status --format='{{.Host}} {{.Kubelet}} {{.APIServer}}' 2>/dev/null | grep -Eq 'Running Running Running'; then
  fail "Minikube is not running. Start it first (example: minikube start --driver=docker) and verify with 'minikube status'"
fi

step "Verifying kubectl context"
kubectl get nodes >/dev/null

step "Switching to host Docker environment"
eval "$(minikube docker-env -u)"

step "Ensuring local project images exist"
if ! image_exists "dsaa4040proj-main-backend:latest" || ! image_exists "dsaa4040proj-main-frontend:latest"; then
  echo "Compose-tagged project images not found; building backend/frontend with docker compose ..."
  docker compose build backend frontend
fi

step "Tagging project images for Kubernetes manifests"
docker tag dsaa4040proj-main-backend:latest bookstore-backend:latest
docker tag dsaa4040proj-main-frontend:latest bookstore-frontend:latest

step "Loading images into Minikube"
minikube image load bookstore-backend:latest
minikube image load bookstore-frontend:latest
if image_exists postgres:16; then
  minikube image load postgres:16
else
  echo "Warning: postgres:16 not found on host Docker cache; Minikube will try to pull it at runtime."
fi

step "Applying namespace first"
kubectl apply -f k8s/namespace.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/${NAMESPACE} --timeout=60s

step "Applying shared config and data services"
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml

step "Waiting for PostgreSQL Pod readiness"
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s

step "Creating/updating postgres-init-sql ConfigMap"
kubectl create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

step "Re-running postgres-init Job to apply current schema/seed"
kubectl delete job postgres-init -n "$NAMESPACE" --ignore-not-found
kubectl apply -f k8s/postgres-init-job.yaml
kubectl wait --for=condition=complete job/postgres-init -n "$NAMESPACE" --timeout=180s
kubectl logs job/postgres-init -n "$NAMESPACE"

step "Applying app workloads and networking"
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml

step "Waiting for backend/frontend deployments"
kubectl wait --for=condition=available deployment/backend -n "$NAMESPACE" --timeout=240s
kubectl wait --for=condition=available deployment/frontend -n "$NAMESPACE" --timeout=240s

step "Smoke-checking Kubernetes backend via temporary port-forward"
kubectl port-forward -n "$NAMESPACE" service/backend-service 18000:8000 >/tmp/k8s-deploy-port-forward.log 2>&1 &
PF_PID=$!
sleep 3
curl -fsS http://localhost:18000/api/health >/dev/null || { kill "$PF_PID" || true; fail "backend /api/health check failed"; }
kill "$PF_PID" >/dev/null 2>&1 || true
wait "$PF_PID" 2>/dev/null || true

step "Deployment summary"
kubectl get all -n "$NAMESPACE"
kubectl get ingress -n "$NAMESPACE"
kubectl get hpa -n "$NAMESPACE"

echo
echo "Kubernetes deployment completed successfully."
echo "Run: ./scripts/k8s-test-local.sh"
