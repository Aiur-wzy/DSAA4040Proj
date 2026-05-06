#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

resolve_kubectl
require_minikube_running

echo "Using Kubernetes command: ${KUBECTL_MODE}"
echo "WARNING: This deletes Kubernetes resources in namespace 'bookstore'."
"${KUBECTL[@]}" delete -f k8s/ --ignore-not-found=true
"${KUBECTL[@]}" delete configmap postgres-init-sql -n bookstore --ignore-not-found=true
