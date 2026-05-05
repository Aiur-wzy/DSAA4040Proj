#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }

echo "=== Kubernetes resources (bookstore namespace) ==="
kubectl get all -n bookstore

echo
kubectl get pvc -n bookstore

echo
kubectl get ingress -n bookstore

echo
kubectl get hpa -n bookstore
