#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
DELETE_NAMESPACE="${1:-}"

resolve_kubectl
require_minikube_running

echo "Using Kubernetes command: ${KUBECTL_MODE}"
echo "WARNING: This removes Kubernetes demo data and may delete PVC-backed PostgreSQL data in namespace '$NAMESPACE'."

echo
echo "==== Deleting resources defined in k8s/ ===="
"${KUBECTL[@]}" delete -f k8s/ --ignore-not-found=true
"${KUBECTL[@]}" delete hpa backend-hpa -n bookstore --ignore-not-found=true
"${KUBECTL[@]}" delete deployment backend -n bookstore --ignore-not-found=true
"${KUBECTL[@]}" delete service backend-service -n bookstore --ignore-not-found=true
"${KUBECTL[@]}" delete rolebinding bookstore-backend-readonly -n bookstore --ignore-not-found=true
"${KUBECTL[@]}" delete role bookstore-backend-readonly -n bookstore --ignore-not-found=true
"${KUBECTL[@]}" delete serviceaccount bookstore-backend -n bookstore --ignore-not-found=true

echo
echo "==== Deleting postgres-init-sql ConfigMap if it exists ===="
"${KUBECTL[@]}" delete configmap postgres-init-sql -n "$NAMESPACE" --ignore-not-found=true

if [[ "$DELETE_NAMESPACE" == "--delete-namespace" ]]; then
  echo
  echo "==== Deleting namespace '$NAMESPACE' ===="
  "${KUBECTL[@]}" delete namespace "$NAMESPACE" --ignore-not-found=true
else
  echo
  echo "Namespace '$NAMESPACE' kept. Pass --delete-namespace to remove it too."
fi
