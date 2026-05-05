#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }

kubectl apply -f k8s/namespace.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/bookstore --timeout=60s
kubectl apply -f k8s/
