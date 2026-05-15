#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NODE_PORT="${NODE_PORT:-30080}"
NAMESPACE="bookstore"
DB_MODE="${DB_MODE:-single}"
DB_SERVICE="postgres-service"
[[ "$DB_MODE" == "ha" ]] && DB_SERVICE="bookstore-postgres-rw"

step() { echo; echo "$1"; }
warn() { echo "Warning: $*" >&2; }
fail() { echo "Error: $*" >&2; exit 1; }

check_executable() {
  local script="$1"
  if [[ ! -x "${REPO_ROOT}/${script}" ]]; then
    warn "${script} is not executable. Suggested fix: chmod +x ${script}"
  fi
}

check_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    return 0
  fi
  fail "Docker Compose plugin is required. Install it so 'docker compose version' succeeds."
}

run_required() {
  local description="$1"
  shift
  echo "Running: $*"
  "$@" || fail "${description} failed."
}

preflight() {
  require_cmd docker
  require_minikube
  require_cmd curl
  require_cmd python3
  check_docker_compose
  resolve_kubectl

  docker info >/dev/null 2>&1 || fail "Docker is installed but the Docker daemon is not reachable."
  require_minikube_running
  "${KUBECTL[@]}" get nodes >/dev/null || fail "Kubernetes API is not reachable through ${KUBECTL_MODE}."

  if [[ "${SKIP_HPA_DEPS:-0}" != "1" ]]; then
    if command -v hey >/dev/null 2>&1; then
      echo "hey is installed; HPA demo load generation is available."
    else
      warn "hey is not installed. The full update can continue, but ./scripts/k8s-hpa-demo.sh needs hey for the repeatable HPA demo. Set SKIP_HPA_DEPS=1 to suppress this warning."
    fi
  fi

  for script in \
    scripts/k8s-rebuild-and-deploy.sh \
    scripts/k8s-test-local.sh \
    scripts/k8s-fix-metrics-server.sh \
    scripts/k8s-fix-ingress.sh \
    scripts/test-api.sh \
    scripts/test-admin-api.sh \
    scripts/k8s-status.sh \
    scripts/k8s-expose-demo.sh \
    scripts/k8s-hpa-demo.sh \
    scripts/k8s-install-cnpg.sh \
    scripts/k8s-postgres-ha-status.sh \
    scripts/k8s-postgres-ha-failover-test.sh; do
    check_executable "$script"
  done

  echo "Using Kubernetes command: ${KUBECTL_MODE}"
  echo "Using namespace: ${NAMESPACE}"
  echo "Database mode: ${DB_MODE}; backend DB service: ${DB_SERVICE}; HA enabled=$([[ "$DB_MODE" == "ha" ]] && echo yes || echo no)"
}

api_smoke_tests() {
  local minikube_ip base_url
  minikube_ip="$(minikube ip)"
  base_url="http://${minikube_ip}:${NODE_PORT}"

  if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
    echo "SKIP_TESTS=1 set; skipping test-api.sh and test-admin-api.sh."
  else
    run_required "public API smoke tests" env BASE_URL="$base_url" "${SCRIPT_DIR}/test-api.sh"
    run_required "admin API smoke tests" env BASE_URL="$base_url" "${SCRIPT_DIR}/test-admin-api.sh"
  fi

  echo "Monitoring API response from ${base_url}/api/admin/cluster/status:"
  curl -fsS "${base_url}/api/admin/cluster/status" | python3 -m json.tool || fail "Monitoring API verification failed."
}

hpa_readiness_check() {
  echo "HPA status:"
  "${KUBECTL[@]}" get hpa -n "$NAMESPACE" || fail "Unable to read HPA resources in namespace/${NAMESPACE}."
  if "${KUBECTL[@]}" get hpa public-backend-hpa -n "$NAMESPACE" >/dev/null 2>&1; then
    local targets
    targets="$("${KUBECTL[@]}" get hpa public-backend-hpa -n "$NAMESPACE" -o jsonpath='{.status.currentMetrics[*].resource.current.averageUtilization}' 2>/dev/null || true)"
    if [[ -z "$targets" ]]; then
      warn "public-backend-hpa does not have CPU utilization yet. If it shows <unknown>, run ./scripts/k8s-fix-metrics-server.sh and wait for metrics samples."
    else
      echo "public-backend-hpa has current CPU metric sample(s): ${targets}"
    fi
  else
    fail "public-backend-hpa is missing."
  fi
}

print_next_commands() {
  local minikube_ip
  minikube_ip="$(minikube ip)"
  cat <<EOF_NEXT

Full Kubernetes update completed.

Next demo commands:
  PUBLIC_PORT=3000 NODE_PORT=${NODE_PORT} ./scripts/k8s-expose-demo.sh
  ./scripts/k8s-hpa-demo.sh
  minikube kubectl -- get hpa -n bookstore -w
  minikube kubectl -- get pods -n bookstore -l app=public-backend -w
  curl -i -H "Host: bookstore.local" http://${minikube_ip}/api/books

Skip flags:
  SKIP_METRICS=1 ./scripts/k8s-full-update.sh
  SKIP_INGRESS=1 ./scripts/k8s-full-update.sh
  SKIP_TESTS=1 ./scripts/k8s-full-update.sh
  SKIP_HPA_DEPS=1 ./scripts/k8s-full-update.sh
EOF_NEXT
}

cd "$REPO_ROOT"

step "[1/8] Preflight"
preflight

step "[2/8] Rebuild and deploy bookstore"
run_required "bookstore rebuild/deploy" env DB_MODE="$DB_MODE" "${SCRIPT_DIR}/k8s-rebuild-and-deploy.sh"

step "[3/8] Verify core app routes"
run_required "core Kubernetes NodePort route verification" "${SCRIPT_DIR}/k8s-test-local.sh"

step "[4/8] Repair/check metrics-server"
if [[ "${SKIP_METRICS:-0}" == "1" ]]; then
  echo "SKIP_METRICS=1 set; skipping metrics-server repair/check."
else
  run_required "metrics-server repair/check" "${SCRIPT_DIR}/k8s-fix-metrics-server.sh"
fi

step "[5/8] Repair/check ingress"
if [[ "${SKIP_INGRESS:-0}" == "1" ]]; then
  echo "SKIP_INGRESS=1 set; skipping ingress-nginx repair/check."
else
  run_required "ingress-nginx repair/check" "${SCRIPT_DIR}/k8s-fix-ingress.sh"
fi

step "[6/8] Run API smoke tests"
api_smoke_tests
hpa_readiness_check

step "[7/8] Print cluster status"
run_required "cluster status" env DB_MODE="$DB_MODE" "${SCRIPT_DIR}/k8s-status.sh"

step "[8/8] Print next demo commands"
print_next_commands
