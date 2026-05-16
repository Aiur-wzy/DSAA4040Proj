#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="${NAMESPACE:-bookstore}"
CNPG_POSTGRES_IMAGE="${CNPG_POSTGRES_IMAGE:-ghcr.io/cloudnative-pg/postgresql:16.4}"
NODE_PORT="${NODE_PORT:-30080}"
BASE_URL="${BASE_URL:-}"
REBUILD_SCRIPT="${SCRIPT_DIR}/k8s-rebuild-and-deploy.sh"
HA_STATUS_SCRIPT="${SCRIPT_DIR}/k8s-postgres-ha-status.sh"
LAST_STAGE_LOG=""
CURRENT_STAGE="preflight checks"

fail() { echo "Error: $*" >&2; exit 1; }
warn() { echo "Warning: $*" >&2; }
info() { printf '%s\n' "$*"; }

optional_diag() {
  local description="$1"
  shift
  if ! "$@"; then
    warn "Diagnostic command failed: ${description}"
  fi
}

print_stage_diagnostics() {
  local stage="$1"

  echo >&2
  echo "Diagnostics for failed stage: ${stage}" >&2
  optional_diag "kubectl get pods -n ${NAMESPACE} -o wide" "${KUBECTL[@]}" get pods -n "${NAMESPACE}" -o wide
  optional_diag "kubectl get events -n ${NAMESPACE}" "${KUBECTL[@]}" get events -n "${NAMESPACE}" --sort-by=.lastTimestamp

  case "$stage" in
    *CloudNativePG*|*CNPG*)
      optional_diag "kubectl get pods -n cnpg-system" "${KUBECTL[@]}" get pods -n cnpg-system -o wide
      optional_diag "kubectl describe deployment/cnpg-controller-manager -n cnpg-system" "${KUBECTL[@]}" describe deployment/cnpg-controller-manager -n cnpg-system
      ;;
    *database*|*PostgreSQL*)
      optional_diag "kubectl get cluster/bookstore-postgres -n ${NAMESPACE}" "${KUBECTL[@]}" get cluster bookstore-postgres -n "${NAMESPACE}" -o wide
      optional_diag "kubectl describe cluster/bookstore-postgres -n ${NAMESPACE}" "${KUBECTL[@]}" describe cluster bookstore-postgres -n "${NAMESPACE}"
      optional_diag "kubectl get pods for bookstore-postgres" "${KUBECTL[@]}" get pods -n "${NAMESPACE}" -l cnpg.io/cluster=bookstore-postgres -o wide
      ;;
    *Initialize*)
      optional_diag "kubectl describe job/postgres-init-ha -n ${NAMESPACE}" "${KUBECTL[@]}" describe job postgres-init-ha -n "${NAMESPACE}"
      optional_diag "kubectl logs job/postgres-init-ha -n ${NAMESPACE}" "${KUBECTL[@]}" logs -n "${NAMESPACE}" -l job-name=postgres-init-ha --all-containers=true --tail=200
      ;;
    *Deploy*|*Verify*)
      optional_diag "kubectl get deployments -n ${NAMESPACE}" "${KUBECTL[@]}" get deployments -n "${NAMESPACE}" -o wide
      optional_diag "kubectl get hpa -n ${NAMESPACE}" "${KUBECTL[@]}" get hpa -n "${NAMESPACE}"
      ;;
  esac
}

run_stage() {
  local label="$1"
  local command="$2"

  CURRENT_STAGE="$label"
  LAST_STAGE_LOG="$(mktemp)"
  printf '\n%s\n' "$label"

  if ! DB_MODE=ha "${REBUILD_SCRIPT}" "$command" 2>&1 | tee "$LAST_STAGE_LOG"; then
    print_stage_diagnostics "$label"
    fail "${label} failed. Review the diagnostics above."
  fi
}

preflight() {
  local minikube_status_output

  require_cmd minikube
  require_cmd curl
  resolve_kubectl

  info "Resource warning: DB_MODE=ha runs 3 PostgreSQL instances plus app, ingress, metrics-server, and HPA. On single-node Minikube, 6GB+ memory is recommended."
  info "MINIKUBE_PROFILE=${MINIKUBE_PROFILE:-default}"
  info "Namespace: ${NAMESPACE}"
  info "CNPG PostgreSQL image: ${CNPG_POSTGRES_IMAGE}"

  if ! minikube_status_output="$(minikube status 2>&1)"; then
    printf '%s\n' "$minikube_status_output" >&2
    fail "Minikube is not running or is unreachable. Start it first, for example: minikube start --driver=docker --memory=6144 --cpus=2"
  fi
  printf '%s\n' "$minikube_status_output"

  if ! grep -Eq 'apiserver:[[:space:]]*Running' <<<"$minikube_status_output"; then
    fail "Minikube apiserver is not running. Start or repair Minikube before running the HA rebuild wrapper."
  fi

  "${KUBECTL[@]}" get nodes
}

ensure_cnpg_postgres_image() {
  info "Checking CNPG PostgreSQL image inside Minikube: ${CNPG_POSTGRES_IMAGE}"
  if minikube ssh -- docker image inspect "${CNPG_POSTGRES_IMAGE}" >/dev/null 2>&1; then
    info "CNPG PostgreSQL image already exists inside Minikube."
    return 0
  fi

  info "CNPG PostgreSQL image is missing inside Minikube; pulling it inside Minikube now..."
  if ! minikube ssh -- docker pull "${CNPG_POSTGRES_IMAGE}"; then
    cat >&2 <<DIAG
Error: Failed to pull CNPG PostgreSQL image inside Minikube: ${CNPG_POSTGRES_IMAGE}
Check network access from the Minikube VM/container and confirm the image tag is available.
You can override the image with CNPG_POSTGRES_IMAGE=<image> if your manifests use a mirrored image.
DIAG
    optional_diag "minikube ssh -- docker info" minikube ssh -- docker info
    optional_diag "minikube ssh -- docker images cloudnative-pg/postgresql" minikube ssh -- docker images ghcr.io/cloudnative-pg/postgresql
    exit 1
  fi
  info "Pulled CNPG PostgreSQL image inside Minikube."
}

check_cnpg_rollout() {
  info "Health check: cnpg-controller-manager rollout"
  "${KUBECTL[@]}" rollout status deployment/cnpg-controller-manager -n cnpg-system --timeout=180s
}

check_ha_database() {
  info "Health check: CloudNativePG HA database status"
  if [[ -x "$HA_STATUS_SCRIPT" ]]; then
    DB_MODE=ha "$HA_STATUS_SCRIPT"
  else
    "${KUBECTL[@]}" get cluster bookstore-postgres -n "$NAMESPACE" -o wide
  fi
}

check_init_db() {
  local succeeded

  info "Health check: postgres-init-ha completed or was safely skipped"
  if "${KUBECTL[@]}" get job postgres-init-ha -n "$NAMESPACE" >/dev/null 2>&1; then
    succeeded="$("${KUBECTL[@]}" get job postgres-init-ha -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null)"
    [[ "$succeeded" == "1" ]] || fail "postgres-init-ha exists but has not completed successfully."
    info "postgres-init-ha completed successfully."
    return 0
  fi

  if [[ -n "$LAST_STAGE_LOG" ]] && grep -Eq 'skipping postgres-init-ha|already contains books/orders/order_items/carts' "$LAST_STAGE_LOG"; then
    info "postgres-init-ha was skipped because the HA schema is already initialized."
    return 0
  fi

  fail "postgres-init-ha was not found and the stage output did not show a safe skip."
}

check_deployments_available() {
  local deployments=(public-backend admin-backend monitoring-backend frontend)
  local deployment replicas available

  info "Health check: application Deployments have nonzero replicas and available Pods"
  "${KUBECTL[@]}" get deployments -n "$NAMESPACE" -o wide
  for deployment in "${deployments[@]}"; do
    replicas="$("${KUBECTL[@]}" get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
    available="$("${KUBECTL[@]}" get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.availableReplicas}')"
    available="${available:-0}"
    [[ "${replicas:-0}" -gt 0 ]] || fail "deployment/${deployment} has zero desired replicas."
    [[ "$available" -gt 0 ]] || fail "deployment/${deployment} has no available replicas."
    info "deployment/${deployment}: replicas=${replicas}, available=${available}"
  done
}

check_application_endpoints() {
  local url

  if [[ -z "$BASE_URL" ]]; then
    BASE_URL="http://$(minikube ip):${NODE_PORT}"
  fi

  info "Health check: application endpoints at ${BASE_URL}"
  for path in /api/health/db /api/admin/cluster/status; do
    url="${BASE_URL}${path}"
    info "GET ${url}"
    curl -fsS "$url" >/dev/null
  done
}

print_post_checks() {
  cat <<'POSTCHECKS'

HA rebuild wrapper complete.

Recommended post-check commands:
  DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh
  MINIKUBE_IP=$(minikube ip)
  DB_MODE=ha BASE_URL=http://$MINIKUBE_IP:30080 ./scripts/test-api.sh
  DB_MODE=ha BASE_URL=http://$MINIKUBE_IP:30080 ./scripts/test-admin-api.sh
  BASE_URL=http://$MINIKUBE_IP:30080 ./scripts/test-order-consistency.sh
  DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
POSTCHECKS
}

main() {
  cd "$REPO_ROOT"
  preflight

  run_stage "[1/5] Install/check CloudNativePG operator" install-cnpg
  check_cnpg_rollout

  ensure_cnpg_postgres_image
  run_stage "[2/5] Apply/check HA PostgreSQL cluster" apply-ha-database
  check_ha_database

  run_stage "[3/5] Initialize HA database" init-db
  check_init_db

  run_stage "[4/5] Deploy application" deploy-app
  check_deployments_available

  run_stage "[5/5] Verify application" verify-app
  check_application_endpoints

  print_post_checks
}

main "$@"
