#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"

resolve_kubectl
require_minikube

echo "=== Minikube status ==="
if minikube status; then
  MINIKUBE_RUNNING=true
else
  MINIKUBE_RUNNING=false
fi

echo
echo "=== Minikube IP ==="
if [[ "$MINIKUBE_RUNNING" == "true" ]]; then
  minikube ip
else
  echo "Unavailable because Minikube is not running."
fi

echo
echo "=== Kubernetes command mode ==="
echo "$KUBECTL_MODE"

if [[ "$MINIKUBE_RUNNING" != "true" ]]; then
  echo
  echo "Error: Minikube is not running. Start it first with: minikube start --driver=docker --memory=4096 --cpus=2" >&2
  exit 1
fi

echo
echo "=== All resources in namespace '${NAMESPACE}' ==="
"${KUBECTL[@]}" get all -n "$NAMESPACE"

echo
echo "=== Pods ==="
"${KUBECTL[@]}" get pods -n "$NAMESPACE" -o wide

echo
echo "=== Services ==="
"${KUBECTL[@]}" get services -n "$NAMESPACE" -o wide

echo
echo "=== Ingress ==="
"${KUBECTL[@]}" get ingress -n "$NAMESPACE"

echo
echo "=== HPA ==="
"${KUBECTL[@]}" get hpa -n "$NAMESPACE"

print_service_endpoints() {
  local service="$1"

  echo "=== ${service} EndpointSlices ==="
  if "${KUBECTL[@]}" get endpointslices -n "$NAMESPACE" -l "kubernetes.io/service-name=${service}" -o wide >/tmp/k8s-status-endpointslices.$$ 2>/dev/null; then
    cat /tmp/k8s-status-endpointslices.$$
    rm -f /tmp/k8s-status-endpointslices.$$
  else
    rm -f /tmp/k8s-status-endpointslices.$$
    echo "EndpointSlice lookup unavailable; falling back to legacy Endpoints API."
    "${KUBECTL[@]}" get endpoints "$service" -n "$NAMESPACE" -o wide
  fi
}

echo
for service in public-backend-service admin-backend-service monitoring-backend-service frontend-service; do
  print_service_endpoints "$service"
  echo
done
