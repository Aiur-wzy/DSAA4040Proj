#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}"
DB_MODE="${DB_MODE:-ha}"
NAMESPACE="${NAMESPACE:-bookstore}"
CLUSTER_NAME="${CNPG_CLUSTER_NAME:-bookstore-postgres}"
NODE_PORT="${NODE_PORT:-30080}"

if [[ "$DB_MODE" != "ha" ]]; then
  echo "Error: Distributed HA evidence requires DB_MODE=ha (got DB_MODE=${DB_MODE})." >&2
  exit 1
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command '$1' not found in PATH" >&2
    exit 1
  }
}

mk() {
  command minikube -p "$MINIKUBE_PROFILE" "$@"
}

section() {
  printf '\n[%s] %s\n' "$1" "$2"
}

count_distinct_nodes() {
  awk 'NF && $1 != "<none>" { seen[$1]=1 } END { print length(seen) + 0 }'
}

list_pod_nodes() {
  local selector="$1"
  mk kubectl -- get pods -n "$NAMESPACE" -l "$selector" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.nodeName}{"\n"}{end}' 2>/dev/null || true
}

require_cmd minikube
require_cmd curl

BASE_URL="${BASE_URL:-http://$(mk ip):${NODE_PORT}}"

printf 'MINIKUBE_PROFILE=%s\nDB_MODE=%s\nNamespace=%s\nCluster=%s\nBASE_URL=%s\n' \
  "$MINIKUBE_PROFILE" "$DB_MODE" "$NAMESPACE" "$CLUSTER_NAME" "$BASE_URL"

section "1/7" "Kubernetes nodes"
mk kubectl -- get nodes -o wide

section "2/7" "Bookstore pods with node placement"
mk kubectl -- get pods -n "$NAMESPACE" -o wide

section "3/7" "CloudNativePG HA status"
MINIKUBE_PROFILE="$MINIKUBE_PROFILE" DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh

section "4/7" "PostgreSQL primary/replica node distribution"
postgres_nodes_table="$(list_pod_nodes "cnpg.io/cluster=${CLUSTER_NAME}")"
printf '%s\n' "${postgres_nodes_table:-No PostgreSQL pods found}"
postgres_node_count="$(printf '%s\n' "$postgres_nodes_table" | awk '{ print $2 }' | count_distinct_nodes)"
public_backend_nodes_table="$(list_pod_nodes "app=public-backend")"
echo "public-backend pods:"
printf '%s\n' "${public_backend_nodes_table:-No public-backend pods found}"
public_backend_node_count="$(printf '%s\n' "$public_backend_nodes_table" | awk '{ print $2 }' | count_distinct_nodes)"
printf 'postgresDistinctNodes=%s\n' "$postgres_node_count"
printf 'publicBackendDistinctNodes=%s\n' "$public_backend_node_count"

section "5/7" "rw/ro EndpointSlices"
for service in "${CLUSTER_NAME}-rw" "${CLUSTER_NAME}-ro"; do
  echo "--- ${service} ---"
  mk kubectl -- get endpointslices -n "$NAMESPACE" -l "kubernetes.io/service-name=${service}" -o wide
  mk kubectl -- get endpointslices -n "$NAMESPACE" -l "kubernetes.io/service-name=${service}" \
    -o jsonpath='{range .items[*].endpoints[*]}{.targetRef.name}{"\t"}{.nodeName}{"\t"}{.conditions.ready}{"\n"}{end}' || true
  echo
done

section "6/7" "Application health and DB health"
echo "--- /api/health ---"
curl -fsS "${BASE_URL}/api/health"
echo

echo "--- /api/health/db ---"
curl -fsS "${BASE_URL}/api/health/db"
echo

echo "--- /api/admin/cluster/status ---"
curl -fsS "${BASE_URL}/api/admin/cluster/status"
echo

section "7/7" "Evidence summary"
printf 'Kubernetes profile: %s\n' "$MINIKUBE_PROFILE"
printf 'PostgreSQL HA pods distinct nodes: %s\n' "$postgres_node_count"
printf 'public-backend pods distinct nodes: %s\n' "$public_backend_node_count"
if (( postgres_node_count >= 3 )); then
  echo "STRONG PASS: PostgreSQL HA pods use 3 distinct Kubernetes nodes."
elif (( postgres_node_count >= 2 )); then
  echo "PASS: PostgreSQL HA pods use at least 2 distinct Kubernetes nodes."
else
  echo "WARN: PostgreSQL HA pods are all on one Kubernetes node."
  echo "WARN: This does not fail the evidence script because Minikube scheduling can be resource constrained."
  echo "Inspect scheduler constraints with:"
  echo "  MINIKUBE_PROFILE=${MINIKUBE_PROFILE} minikube kubectl -- describe pods -n ${NAMESPACE} -l cnpg.io/cluster=${CLUSTER_NAME}"
  echo "  MINIKUBE_PROFILE=${MINIKUBE_PROFILE} minikube kubectl -- get events -n ${NAMESPACE} --sort-by=.lastTimestamp"
fi
