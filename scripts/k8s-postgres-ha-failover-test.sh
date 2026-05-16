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
DB_HOST="${DB_HOST:-${CLUSTER_NAME}-rw}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-bookstore}"
DB_USER="${DB_USER:-bookstore}"
DB_APP_SECRET="${DB_APP_SECRET:-${CLUSTER_NAME}-app}"
PSQL_CLIENT_IMAGE="${PSQL_CLIENT_IMAGE:-postgres:16}"

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

sql_literal() {
  python3 -c "import sys; print(\"'\" + sys.argv[1].replace(\"'\", \"''\") + \"'\")" "$1"
}

trim_psql_output() {
  python3 -c 'import sys; print(sys.stdin.read().strip())'
}

psql_rw() {
  local sql="$1"
  local client_pod="psql-rw-check-${RANDOM}-${RANDOM}"

  "${KUBECTL[@]}" run "$client_pod" \
    -n "$NAMESPACE" \
    --rm \
    -i \
    --restart=Never \
    --image="$PSQL_CLIENT_IMAGE" \
    --env="PGPASSWORD=${DB_PASSWORD}" \
    --command -- \
    psql \
      -h "$DB_HOST" \
      -p "$DB_PORT" \
      -U "$DB_USER" \
      -d "$DB_NAME" \
      -X \
      -v ON_ERROR_STOP=1 \
      -q \
      -t \
      -A \
      -c "$sql"
}

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
echo "SQL checks use ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME} via temporary ${PSQL_CLIENT_IMAGE} client pods"

DB_PASSWORD="$(${KUBECTL[@]} get secret "$DB_APP_SECRET" -n "$NAMESPACE" -o jsonpath='{.data.password}' | base64 -d)"
[[ -n "$DB_PASSWORD" ]] || fail "Could not read password key from secret ${DB_APP_SECRET} in namespace ${NAMESPACE}"

"${KUBECTL[@]}" wait --for=condition=Ready "cluster/${CLUSTER_NAME}" -n "$NAMESPACE" --timeout=120s
pass "CloudNativePG cluster is initially Ready"

curl -fsS "${BASE_URL}/api/health/db" >/dev/null
pass "Backend DB health is initially OK"

old_primary="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.currentPrimary}')"
[[ -n "$old_primary" ]] || fail "Could not identify current primary pod"
echo "Old primary: ${old_primary}"

pre_write_result="skipped"
post_read_result="skipped"
post_write_result="skipped"

if [[ "$SKIP_WRITE_TEST" != "1" ]]; then
  marker_sql="$(sql_literal "$marker")"
  sql="SET client_min_messages TO warning; CREATE TABLE IF NOT EXISTS ha_failover_markers (id text PRIMARY KEY, created_at timestamptz DEFAULT now()); INSERT INTO ha_failover_markers(id) VALUES (${marker_sql}) ON CONFLICT DO NOTHING; SELECT 'pre_marker=' || id || ' created_at=' || created_at FROM ha_failover_markers WHERE id=${marker_sql};"
  pre_write_result="$(psql_rw "$sql")"
  [[ -n "$pre_write_result" ]] || fail "Pre-failover marker write did not return evidence for ${marker}"
  echo "Pre-failover write result: ${pre_write_result}"
  pass "Inserted pre-failure marker ${marker} through ${DB_HOST}"
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
echo "New primary: ${new_primary}"
pass "New primary promoted: ${new_primary}"

"${KUBECTL[@]}" wait --for=condition=Ready "pod/${new_primary}" -n "$NAMESPACE" --timeout="${FAILOVER_TIMEOUT}s"
pass "Current primary pod ${new_primary} is Ready"

"${KUBECTL[@]}" wait --for=condition=Ready "cluster/${CLUSTER_NAME}" -n "$NAMESPACE" --timeout="${FAILOVER_TIMEOUT}s"
pass "CloudNativePG cluster is Ready after failover"

"${KUBECTL[@]}" wait --for=condition=Ready pod -l "cnpg.io/cluster=${CLUSTER_NAME}" -n "$NAMESPACE" --timeout="${FAILOVER_TIMEOUT}s" || warn "Not all PostgreSQL pods are Ready yet; continuing to check rw service/backend."
"${KUBECTL[@]}" get endpointslices -n "$NAMESPACE" -l "kubernetes.io/service-name=${DB_HOST}" -o wide

until curl -fsS "${BASE_URL}/api/health/db" >/dev/null; do
  (( $(date +%s) < deadline )) || fail "Backend /api/health/db did not recover within ${FAILOVER_TIMEOUT}s"
  sleep 3
done
pass "Backend DB health recovered through ${DB_HOST}"

if [[ "$SKIP_WRITE_TEST" != "1" ]]; then
  marker_sql="$(sql_literal "$marker")"
  post_read_raw="$(psql_rw "SELECT COUNT(*) FROM ha_failover_markers WHERE id=${marker_sql};")"
  post_read_count="$(printf '%s' "$post_read_raw" | trim_psql_output)"
  post_read_result="post_read_count=${post_read_count}"
  if ! [[ "$post_read_count" =~ ^[0-9]+$ ]] || (( post_read_count < 1 )); then
    {
      echo "DEBUG: raw psql output: ${post_read_raw}"
      echo "DEBUG: parsed count: ${post_read_count}"
      echo "DEBUG: marker value: ${marker}"
    } >&2
    fail "Pre-failure marker ${marker} was not found after failover; got: ${post_read_result}"
  fi
  echo "Post-failover read result: ${post_read_result}"
  pass "Pre-failure data remains after failover"

  post_marker="${marker}-post"
  post_marker_sql="$(sql_literal "$post_marker")"
  post_write_result="$(psql_rw "INSERT INTO ha_failover_markers(id) VALUES (${post_marker_sql}) ON CONFLICT DO NOTHING; SELECT 'post_marker=' || id || ' created_at=' || created_at FROM ha_failover_markers WHERE id=${post_marker_sql};")"
  [[ -n "$post_write_result" ]] || fail "Post-failover marker write did not return evidence for ${post_marker}"
  echo "Post-failover write result: ${post_write_result}"
  pass "New write succeeds after failover through ${DB_HOST} (${post_marker})"
fi

end_epoch="$(date +%s)"
failover_duration="$((end_epoch - start_epoch))"
echo "Old primary: ${old_primary}"
echo "New primary: ${new_primary}"
echo "Failover duration: ${failover_duration} seconds"
echo "Pre-failover write result: ${pre_write_result}"
echo "Post-failover read result: ${post_read_result}"
echo "Post-failover write result: ${post_write_result}"
pass "CloudNativePG HA failover test completed"
