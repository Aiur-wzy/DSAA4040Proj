#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

resolve_kubectl
require_minikube_running

echo "Using Kubernetes command: ${KUBECTL_MODE}"

echo "=== Pods ==="
"${KUBECTL[@]}" get pods -n bookstore

echo
echo "=== HPA ==="
"${KUBECTL[@]}" get hpa -n bookstore

echo
echo "=== Node metrics ==="
"${KUBECTL[@]}" top nodes

echo
echo "=== Pod metrics ==="
"${KUBECTL[@]}" top pods -n bookstore

echo
echo "Hint: if metrics are unavailable, enable metrics-server:"
echo "minikube addons enable metrics-server"
