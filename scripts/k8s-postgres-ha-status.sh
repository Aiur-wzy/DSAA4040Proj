#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="${NAMESPACE:-bookstore}"
CLUSTER_NAME="${CNPG_CLUSTER_NAME:-bookstore-postgres}"
DB_MODE="${DB_MODE:-ha}"

fail() { echo "FAIL: $*" >&2; exit 1; }
section() { echo; echo "=== $* ==="; }

[[ "$DB_MODE" == "ha" ]] || fail "DB_MODE=$DB_MODE. This script is for DB_MODE=ha; rerun with DB_MODE=ha if intentional."
require_minikube_running
resolve_kubectl

echo "DB_MODE=${DB_MODE}"
echo "MINIKUBE_PROFILE=${MINIKUBE_PROFILE:-default}"
echo "Kubernetes command: ${KUBECTL_MODE}"
echo "Namespace: ${NAMESPACE}"
echo "CloudNativePG cluster: ${CLUSTER_NAME}"

section "CloudNativePG Cluster"
"${KUBECTL[@]}" get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o wide

section "Current primary / ready instances"
primary="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
ready="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)"
instances="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.instances}' 2>/dev/null || true)"
echo "primary=${primary:-unknown}"
echo "readyInstances=${ready:-unknown}/${instances:-unknown}"

section "PostgreSQL pods with node placement"
"${KUBECTL[@]}" get pods -n "$NAMESPACE" -l "cnpg.io/cluster=${CLUSTER_NAME}" -o wide

section "Replicas"
"${KUBECTL[@]}" get pods -n "$NAMESPACE" -l "cnpg.io/cluster=${CLUSTER_NAME}" -o jsonpath='{range .items[*]}{.metadata.name}{"\trole="}{.metadata.labels.role}{"\tinstanceRole="}{.metadata.labels.cnpg\.io/instanceRole}{"\n"}{end}' || true

section "Services"
"${KUBECTL[@]}" get services -n "$NAMESPACE" -l "cnpg.io/cluster=${CLUSTER_NAME}" -o wide

section "EndpointSlices"
for service in "${CLUSTER_NAME}-rw" "${CLUSTER_NAME}-ro" "${CLUSTER_NAME}-r"; do
  echo "--- ${service} ---"
  "${KUBECTL[@]}" get endpointslices -n "$NAMESPACE" -l "kubernetes.io/service-name=${service}" -o wide || true
done

section "Recent events"
"${KUBECTL[@]}" get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 30
