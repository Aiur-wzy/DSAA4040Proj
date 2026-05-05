#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl not found"; exit 1; }

echo "=== Pods ==="
kubectl get pods -n bookstore

echo
echo "=== HPA ==="
kubectl get hpa -n bookstore

echo
echo "=== Node metrics ==="
kubectl top nodes

echo
echo "=== Pod metrics ==="
kubectl top pods -n bookstore

echo
echo "Hint: if kubectl top fails, enable metrics-server:"
echo "minikube addons enable metrics-server"
