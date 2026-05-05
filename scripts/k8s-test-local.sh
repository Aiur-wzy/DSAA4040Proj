#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="bookstore"
PF_PID=""

step() {
  echo
  echo "==== $1 ===="
}

cleanup() {
  if [[ -n "$PF_PID" ]] && kill -0 "$PF_PID" >/dev/null 2>&1; then
    kill "$PF_PID" >/dev/null 2>&1 || true
    wait "$PF_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

step "Starting backend port-forward"
kubectl port-forward -n "$NAMESPACE" service/backend-service 8000:8000 >/tmp/k8s-port-forward.log 2>&1 &
PF_PID=$!
sleep 3

step "Running direct backend endpoint checks"
curl -fS http://localhost:8000/api/health
curl -fS http://localhost:8000/api/health/db
curl -fS http://localhost:8000/api/books

step "Running API smoke test script"
BASE_URL=http://localhost:8000 ./scripts/test-api.sh

step "Kubernetes local API tests completed"
