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
"${KUBECTL[@]}" apply -f k8s/postgres-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-service.yaml
"${KUBECTL[@]}" apply -f k8s/backend-service.yaml
"${KUBECTL[@]}" apply -f k8s/backend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-service.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/ingress.yaml
"${KUBECTL[@]}" apply -f k8s/hpa.yaml
