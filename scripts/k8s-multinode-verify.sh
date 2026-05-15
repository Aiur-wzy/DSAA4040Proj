#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
NODE_PORT="${NODE_PORT:-30080}"
RESTORE_HPA=false

cleanup() {
  if [[ "$RESTORE_HPA" == "true" ]]; then
    echo "Restoring public-backend-hpa minReplicas to 2..."
    "${KUBECTL[@]}" patch hpa public-backend-hpa -n "$NAMESPACE" --type merge -p '{"spec":{"minReplicas":2}}' >/dev/null || true
  fi
}
trap cleanup EXIT

public_backend_node_count() {
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -l app=public-backend -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
    | awk 'NF { nodes[$1]=1 } END { print length(nodes) + 0 }'
}

print_distribution_result() {
  local count
  count="$(public_backend_node_count)"
  if (( count >= 2 )); then
    echo "PASS: public-backend Pods are placed on ${count} distinct nodes."
  else
    echo "WARN: public-backend Pods are currently on one node. This can happen because of resource pressure or scheduler decisions."
  fi
}

resolve_kubectl
require_minikube_running
require_cmd curl
MINIKUBE_IP="$(minikube_ip)"
BASE_URL="http://${MINIKUBE_IP}:${NODE_PORT}"

printf '\n[1/6] Nodes\n'
"${KUBECTL[@]}" get nodes -o wide

printf '\n[2/6] Workloads by node\n'
"${KUBECTL[@]}" get pods -n "$NAMESPACE" -o wide

printf '\n[3/6] public-backend distribution\n'
"${KUBECTL[@]}" get pods -n "$NAMESPACE" -l app=public-backend -o wide
print_distribution_result

printf '\n[4/6] frontend distribution\n'
"${KUBECTL[@]}" get pods -n "$NAMESPACE" -l app=frontend -o wide

printf '\n[5/6] Service, Ingress, and HPA status\n'
"${KUBECTL[@]}" get deploy,svc,hpa,ingress -n "$NAMESPACE"
curl -fsS "${BASE_URL}/api/books" >/dev/null && echo "PASS: NodePort /api/books"
curl -fsS "${BASE_URL}/api/admin/cluster/status" >/dev/null && echo "PASS: NodePort /api/admin/cluster/status"
curl -i -H "Host: bookstore.local" "http://${MINIKUBE_IP}/api/books"
curl -i -H "Host: bookstore.local" "http://${MINIKUBE_IP}/api/admin/cluster/status"

printf '\n[6/6] Optional scale distribution check\n'
if [[ "${MULTINODE_SCALE_TEST:-0}" == "1" ]]; then
  echo "WARN: Temporarily patching public-backend-hpa minReplicas to 5. maxReplicas is unchanged; restoring minReplicas to 2 on exit."
  RESTORE_HPA=true
  "${KUBECTL[@]}" patch hpa public-backend-hpa -n "$NAMESPACE" --type merge -p '{"spec":{"minReplicas":5}}'
  "${KUBECTL[@]}" rollout status deployment/public-backend -n "$NAMESPACE" --timeout=180s
  "${KUBECTL[@]}" wait --for=condition=ready pod -n "$NAMESPACE" -l app=public-backend --timeout=180s
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -l app=public-backend -o wide
  print_distribution_result
else
  echo "Skipping scale test. Set MULTINODE_SCALE_TEST=1 to temporarily raise public-backend-hpa minReplicas to 5."
fi
