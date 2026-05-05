#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="bookstore"
DELETE_NAMESPACE="${1:-}"

echo "WARNING: This removes Kubernetes demo data and may delete PVC-backed PostgreSQL data in namespace '$NAMESPACE'."

echo
 echo "==== Deleting resources defined in k8s/ ===="
kubectl delete -f k8s/ --ignore-not-found=true

echo
 echo "==== Deleting postgres-init-sql ConfigMap if it exists ===="
kubectl delete configmap postgres-init-sql -n "$NAMESPACE" --ignore-not-found=true

if [[ "$DELETE_NAMESPACE" == "--delete-namespace" ]]; then
  echo
  echo "==== Deleting namespace '$NAMESPACE' ===="
  kubectl delete namespace "$NAMESPACE" --ignore-not-found=true
else
  echo
  echo "Namespace '$NAMESPACE' kept. Pass --delete-namespace to remove it too."
fi
