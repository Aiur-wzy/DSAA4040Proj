#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

NAMESPACE="bookstore"
BACKEND_IMAGE="bookstore-backend:latest"
FRONTEND_IMAGE="bookstore-frontend:latest"

step() { printf '\n==== %s ====\n' "$1"; }
fail() { echo "Error: $1" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "required command '$1' not found in PATH"; }
image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

step "Checking prerequisites"
require_cmd docker
require_cmd minikube
require_cmd kubectl
docker compose version >/dev/null 2>&1 || fail "docker compose plugin is required"

step "Checking Minikube status"
if ! minikube status --format='{{.Host}} {{.Kubelet}} {{.APIServer}}' 2>/dev/null | grep -Eq '^Running Running Running$'; then
  fail "Minikube is not running. Start it first, for example: minikube start --driver=docker"
fi
kubectl get nodes >/dev/null

step "Using host Docker environment"
eval "$(minikube docker-env -u)"

step "Building Docker Compose images"
docker compose build backend frontend

step "Verifying expected image tags exist"
image_exists "$BACKEND_IMAGE" || fail "missing image $BACKEND_IMAGE after docker compose build"
image_exists "$FRONTEND_IMAGE" || fail "missing image $FRONTEND_IMAGE after docker compose build"

step "Loading images into Minikube"
minikube image load "$BACKEND_IMAGE"
minikube image load "$FRONTEND_IMAGE"

step "Applying namespace first"
kubectl apply -f k8s/namespace.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Active "namespace/${NAMESPACE}" --timeout=60s

step "Creating/updating postgres-init-sql ConfigMap"
kubectl create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

step "Applying Kubernetes manifests"
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml

step "Waiting for PostgreSQL readiness"
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s

step "Re-running postgres-init Job"
kubectl delete job postgres-init -n "$NAMESPACE" --ignore-not-found
kubectl apply -f k8s/postgres-init-job.yaml
kubectl wait --for=condition=complete job/postgres-init -n "$NAMESPACE" --timeout=180s

step "Applying application manifests"
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml

step "Restarting backend and frontend deployments"
kubectl rollout restart deployment/backend -n "$NAMESPACE"
kubectl rollout restart deployment/frontend -n "$NAMESPACE"

step "Waiting for rollout status"
kubectl rollout status deployment/backend -n "$NAMESPACE" --timeout=240s
kubectl rollout status deployment/frontend -n "$NAMESPACE" --timeout=240s

step "Deployment summary"
kubectl get all -n "$NAMESPACE"
