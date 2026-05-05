#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }
echo "WARNING: This deletes Kubernetes resources in namespace 'bookstore'."
kubectl delete -f k8s/ --ignore-not-found=true
kubectl delete configmap postgres-init-sql -n bookstore --ignore-not-found=true
