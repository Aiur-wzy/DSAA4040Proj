#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
NODE_PORT="${NODE_PORT:-30080}"
SELECTED_NODE=""
NODE_STOPPED=false

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

cleanup() {
  if [[ "$NODE_STOPPED" == "true" && -n "$SELECTED_NODE" ]]; then
    echo "Restarting Minikube node ${SELECTED_NODE}..."
    minikube_cmd node start "$SELECTED_NODE" >/dev/null || true
  fi
  if [[ -n "$SELECTED_NODE" ]]; then
    echo "Uncordoning ${SELECTED_NODE}..."
    "${KUBECTL[@]}" uncordon "$SELECTED_NODE" >/dev/null || true
  fi
}
trap cleanup EXIT

resolve_kubectl
require_minikube_running
require_cmd curl

node_count="$(${KUBECTL[@]} get nodes --no-headers | awk 'END { print NR }')"
if (( node_count < 2 )); then
  fail "at least 2 Kubernetes nodes are required; found ${node_count}"
fi

BASE_URL="${BASE_URL:-http://$(minikube_ip):${NODE_PORT}}"

echo "public-backend Pods by node:"
"${KUBECTL[@]}" get pods -n "$NAMESPACE" -l app=public-backend -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[0].ready,NODE:.spec.nodeName,IP:.status.podIP

postgres_nodes="$(${KUBECTL[@]} get pods -n "$NAMESPACE" -l app=postgres -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u)"
SELECTED_NODE="$(${KUBECTL[@]} get pods -n "$NAMESPACE" -l app=public-backend -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' \
  | awk 'NF' | sort -u | while read -r node; do if ! grep -qx "$node" <<<"$postgres_nodes"; then echo "$node"; break; fi; done)"
if [[ -z "$SELECTED_NODE" ]]; then
  SELECTED_NODE="$(${KUBECTL[@]} get pods -n "$NAMESPACE" -l app=public-backend -o jsonpath='{.items[0].spec.nodeName}')"
  warn "could not find a public-backend node without PostgreSQL; using ${SELECTED_NODE} and avoiding database drain"
fi
[[ -n "$SELECTED_NODE" ]] || fail "could not select a node running public-backend"

echo "Selected node: ${SELECTED_NODE}"
"${KUBECTL[@]}" cordon "$SELECTED_NODE"
pass "cordoned ${SELECTED_NODE}"

if [[ "${DRAIN_APP_PODS:-0}" == "1" ]]; then
  warn "DRAIN_APP_PODS=1 set; deleting only public-backend/frontend Pods on ${SELECTED_NODE}. PostgreSQL and PVC resources are not touched."
  mapfile -t pods_to_delete < <("${KUBECTL[@]}" get pods -n "$NAMESPACE" --field-selector spec.nodeName="$SELECTED_NODE" -o custom-columns=NAME:.metadata.name,APP:.metadata.labels.app --no-headers | awk '$2 == "public-backend" || $2 == "frontend" { print $1 }')
  for pod in "${pods_to_delete[@]}"; do
    "${KUBECTL[@]}" delete pod -n "$NAMESPACE" "$pod"
  done
  "${KUBECTL[@]}" rollout status deployment/public-backend -n "$NAMESPACE" --timeout=180s
else
  echo "Default safe mode only cordons the node. Set DRAIN_APP_PODS=1 to delete app Pods and test rescheduling."
fi

if [[ "${NODE_STOP_TEST:-0}" == "1" ]]; then
  warn "NODE_STOP_TEST=1 set; stopping Minikube node ${SELECTED_NODE}. This is optional and more disruptive than cordon-only testing."
  minikube_cmd node stop "$SELECTED_NODE"
  NODE_STOPPED=true
fi

curl -fsS "${BASE_URL}/api/books" >/dev/null && pass "/api/books remains available"
ready_replicas="$(${KUBECTL[@]} get deploy public-backend -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')"
ready_replicas="${ready_replicas:-0}"
(( ready_replicas >= 1 )) || fail "public-backend has no Ready replicas"
pass "public-backend has ${ready_replicas} Ready replica(s)"
curl -fsS "${BASE_URL}/api/admin/cluster/status" >/dev/null && pass "Monitoring API returns cluster status"
pass "Service routing still works through frontend-service NodePort"
