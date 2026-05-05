#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

NAMESPACE="bookstore"
PF_PID=""

step() { echo; echo "==== $1 ===="; }
fail() { echo "Error: $1" >&2; exit 1; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || fail "required command '$1' not found in PATH"; }

cleanup() {
  if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" >/dev/null 2>&1; then
    kill "$PF_PID" >/dev/null 2>&1 || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

step "Checking prerequisites"
require_cmd kubectl
require_cmd minikube
require_cmd curl

if ! minikube status --format='{{.Host}} {{.Kubelet}} {{.APIServer}}' 2>/dev/null | grep -Eq 'Running Running Running'; then
  fail "Minikube is not running. Start it first and rerun this script."
fi

kubectl get namespace "$NAMESPACE" >/dev/null || fail "namespace '$NAMESPACE' not found"
kubectl get service -n "$NAMESPACE" backend-service >/dev/null || fail "service/backend-service not found in namespace '$NAMESPACE'"

step "Starting dedicated Kubernetes backend port-forward on localhost:18000"
kubectl port-forward -n "$NAMESPACE" service/backend-service 18000:8000 >/tmp/k8s-port-forward.log 2>&1 &
PF_PID=$!

for _ in $(seq 1 20); do
  if curl -fsS http://localhost:18000/api/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS http://localhost:18000/api/health >/dev/null || {
  echo "Port-forward logs:"
  cat /tmp/k8s-port-forward.log || true
  fail "port-forward/backend health check did not become ready"
}

step "Running direct backend endpoint checks"
curl -fS http://localhost:18000/api/health
curl -fS http://localhost:18000/api/health/db
curl -fS http://localhost:18000/api/books

step "Running API smoke test script against Kubernetes backend"
BASE_URL=http://localhost:18000 ./scripts/test-api.sh

step "Kubernetes local API tests completed"
