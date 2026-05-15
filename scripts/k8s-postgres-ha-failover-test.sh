#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="${NAMESPACE:-bookstore}"
CLUSTER_NAME="${CNPG_CLUSTER_NAME:-bookstore-postgres}"
DB_MODE="${DB_MODE:-single}"
FAILOVER_TIMEOUT="${FAILOVER_TIMEOUT:-240}"
SKIP_WRITE_TEST="${SKIP_WRITE_TEST:-0}"
NODE_PORT="${NODE_PORT:-30080}"

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ "$DB_MODE" == "ha" ]] || fail "DB_MODE=$DB_MODE. Refusing failover test unless DB_MODE=ha."
require_minikube_running
resolve_kubectl
require_cmd curl
require_cmd python3

BASE_URL="${BASE_URL:-http://$(minikube ip):${NODE_PORT}}"
marker="ha-failover-$(date +%s)"

echo "DB_MODE=${DB_MODE}"
echo "MINIKUBE_PROFILE=${MINIKUBE_PROFILE:-default}"
echo "Cluster=${CLUSTER_NAME}; namespace=${NAMESPACE}; BASE_URL=${BASE_URL}"

"${KUBECTL[@]}" wait --for=condition=Ready "cluster/${CLUSTER_NAME}" -n "$NAMESPACE" --timeout=120s
pass "CloudNativePG cluster is initially Ready"

curl -fsS "${BASE_URL}/api/health/db" >/dev/null
pass "Backend DB health is initially OK"

old_primary="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentPrimary}')"
[[ -n "$old_primary" ]] || fail "Could not identify current primary pod"
echo "Current primary: ${old_primary}"

if [[ "$SKIP_WRITE_TEST" != "1" ]]; then
  sql="CREATE TABLE IF NOT EXISTS ha_failover_markers (id text PRIMARY KEY, created_at timestamptz DEFAULT now()); INSERT INTO ha_failover_markers(id) VALUES ('${marker}') ON CONFLICT DO NOTHING;"
  "${KUBECTL[@]}" exec -n "$NAMESPACE" "$old_primary" -- psql -U bookstore -d bookstore -c "$sql" >/dev/null
  pass "Inserted pre-failure marker ${marker}"
else
  warn "SKIP_WRITE_TEST=1 set; skipping marker write before failover."
fi

start_epoch="$(date +%s)"
"${KUBECTL[@]}" delete pod "$old_primary" -n "$NAMESPACE"
pass "Deleted only primary pod ${old_primary}; PVCs were not touched"

echo "Waiting for a new primary promotion..."
deadline=$((start_epoch + FAILOVER_TIMEOUT))
new_primary=""
while (( $(date +%s) < deadline )); do
  new_primary="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentPrimary}' 2>/dev/null || true)"
  ready="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.readyInstances}' 2>/dev/null || true)"
  if [[ -n "$new_primary" && "$new_primary" != "$old_primary" && "${ready:-0}" -ge 1 ]]; then
    break
  fi
  sleep 3
done
[[ -n "$new_primary" && "$new_primary" != "$old_primary" ]] || fail "Timed out waiting for new primary after ${FAILOVER_TIMEOUT}s"
pass "New primary promoted: ${new_primary}"

"${KUBECTL[@]}" wait --for=condition=Ready pod -l "cnpg.io/cluster=${CLUSTER_NAME}" -n "$NAMESPACE" --timeout="${FAILOVER_TIMEOUT}s" || warn "Not all PostgreSQL pods are Ready yet; continuing to check rw service/backend."
"${KUBECTL[@]}" get endpointslices -n "$NAMESPACE" -l "kubernetes.io/service-name=${CLUSTER_NAME}-rw" -o wide

until curl -fsS "${BASE_URL}/api/health/db" >/dev/null; do
  (( $(date +%s) < deadline )) || fail "Backend /api/health/db did not recover within ${FAILOVER_TIMEOUT}s"
  sleep 3
done
pass "Backend DB health recovered through ${CLUSTER_NAME}-rw"

if [[ "$SKIP_WRITE_TEST" != "1" ]]; then
  count="$(${KUBECTL[@]} exec -n "$NAMESPACE" "$new_primary" -- psql -U bookstore -d bookstore -tAc "SELECT count(*) FROM ha_failover_markers WHERE id='${marker}'")"
  [[ "$count" == "1" ]] || fail "Pre-failure marker ${marker} was not found after failover"
  pass "Pre-failure data remains after failover"

  post_marker="${marker}-post"
  "${KUBECTL[@]}" exec -n "$NAMESPACE" "$new_primary" -- psql -U bookstore -d bookstore -c "INSERT INTO ha_failover_markers(id) VALUES ('${post_marker}') ON CONFLICT DO NOTHING;" >/dev/null
  pass "New write succeeds after failover (${post_marker})"
fi

end_epoch="$(date +%s)"
echo "Failover duration: $((end_epoch - start_epoch)) seconds"
pass "CloudNativePG HA failover test completed"
