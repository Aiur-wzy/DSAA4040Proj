#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="bookstore"

step() {
  echo
  echo "==== $1 ===="
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found in PATH."
    exit 1
  fi
}

image_exists() {
  docker image inspect "$1" >/dev/null 2>&1
}

step "Checking prerequisites"
require_cmd minikube
require_cmd kubectl
require_cmd docker

if ! docker compose version >/dev/null 2>&1; then
  echo "Error: docker compose plugin is required."
  exit 1
fi

step "Starting Minikube if needed"
if ! minikube status >/dev/null 2>&1; then
  minikube start
fi

step "Switching to host Docker environment"
eval "$(minikube docker-env -u)" || true

step "Ensuring local images exist"
if ! image_exists "dsaa4040proj-main-backend:latest" || ! image_exists "dsaa4040proj-main-frontend:latest"; then
  echo "Compose images missing; running docker compose build ..."
  docker compose build backend frontend
fi

if ! image_exists "postgres:16"; then
  echo "Error: postgres:16 image not found in host Docker cache."
  echo "Please pull it once from host (e.g. docker pull postgres:16) and rerun this script."
  exit 1
fi

step "Tagging compose images for Kubernetes"
docker tag dsaa4040proj-main-backend:latest bookstore-backend:latest
docker tag dsaa4040proj-main-frontend:latest bookstore-frontend:latest

step "Loading images into Minikube"
minikube image load bookstore-backend:latest
minikube image load bookstore-frontend:latest
minikube image load postgres:16

step "Verifying images in Minikube"
minikube image ls | grep bookstore
minikube image ls | grep postgres

step "Applying core Kubernetes resources in safe order"
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/secret.yaml
kubectl apply -f k8s/postgres-deployment.yaml
kubectl apply -f k8s/postgres-service.yaml

step "Waiting for PostgreSQL readiness"
kubectl wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s

step "Creating/updating postgres-init-sql ConfigMap"
kubectl create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

step "Running postgres-init Job"
kubectl delete job postgres-init -n "$NAMESPACE" --ignore-not-found=true
kubectl apply -f k8s/postgres-init-job.yaml
kubectl wait --for=condition=complete job/postgres-init -n "$NAMESPACE" --timeout=180s
kubectl logs job/postgres-init -n "$NAMESPACE"

step "Verifying database"
POSTGRES_POD="$(kubectl get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')"
kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U bookstore -d bookstore -c "\\dt"
kubectl exec -n "$NAMESPACE" "$POSTGRES_POD" -- psql -U bookstore -d bookstore -c "SELECT COUNT(*) FROM books;"

step "Applying application Kubernetes resources"
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/hpa.yaml

step "Waiting for backend and frontend deployments"
kubectl wait --for=condition=available deployment/backend -n "$NAMESPACE" --timeout=180s
kubectl wait --for=condition=available deployment/frontend -n "$NAMESPACE" --timeout=180s

step "Cluster status"
kubectl get all -n "$NAMESPACE"
kubectl get pvc -n "$NAMESPACE"
kubectl get ingress -n "$NAMESPACE"
kubectl get hpa -n "$NAMESPACE"

step "Next-step test commands"
echo "kubectl port-forward -n bookstore service/backend-service 8000:8000"
echo "curl http://localhost:8000/api/health"
echo "curl http://localhost:8000/api/health/db"
echo "curl http://localhost:8000/api/books"
