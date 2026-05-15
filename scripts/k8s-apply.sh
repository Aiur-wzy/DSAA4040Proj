#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

resolve_kubectl
require_minikube_running

echo "Using Kubernetes command: ${KUBECTL_MODE}"

"${KUBECTL[@]}" apply -f k8s/namespace.yaml
"${KUBECTL[@]}" wait --for=jsonpath='{.status.phase}'=Active namespace/bookstore --timeout=60s
"${KUBECTL[@]}" apply -f k8s/configmap.yaml
"${KUBECTL[@]}" apply -f k8s/secret.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-service.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-init-job.yaml
"${KUBECTL[@]}" apply -f k8s/monitoring-backend-rbac.yaml
"${KUBECTL[@]}" apply -f k8s/public-backend-service.yaml
"${KUBECTL[@]}" apply -f k8s/admin-backend-service.yaml
"${KUBECTL[@]}" apply -f k8s/monitoring-backend-service.yaml
"${KUBECTL[@]}" apply -f k8s/public-backend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/public-backend-pdb.yaml
"${KUBECTL[@]}" apply -f k8s/admin-backend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/monitoring-backend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-service.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-pdb.yaml
"${KUBECTL[@]}" apply -f k8s/ingress.yaml
"${KUBECTL[@]}" apply -f k8s/hpa.yaml

# Remove legacy shared-backend resources after the split is applied.
"${KUBECTL[@]}" delete hpa backend-hpa -n bookstore --ignore-not-found
"${KUBECTL[@]}" delete deployment backend -n bookstore --ignore-not-found
"${KUBECTL[@]}" delete service backend-service -n bookstore --ignore-not-found
"${KUBECTL[@]}" delete rolebinding bookstore-backend-readonly -n bookstore --ignore-not-found
"${KUBECTL[@]}" delete role bookstore-backend-readonly -n bookstore --ignore-not-found
"${KUBECTL[@]}" delete serviceaccount bookstore-backend -n bookstore --ignore-not-found
