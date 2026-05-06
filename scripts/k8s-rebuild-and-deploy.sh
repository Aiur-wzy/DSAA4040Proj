#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
POSTGRES_IMAGE="postgres:16"
NODE_PORT="30080"
BACKEND_DEPLOYMENT_MANIFEST="${REPO_ROOT}/k8s/backend-deployment.yaml"
FRONTEND_DEPLOYMENT_MANIFEST="${REPO_ROOT}/k8s/frontend-deployment.yaml"
CURRENT_STAGE="preflight checks"

trap 'echo "Error: ${CURRENT_STAGE} failed at line ${LINENO}. See the command output above for details." >&2' ERR

fail() { echo "Error: $1" >&2; exit 1; }
info() { printf '%s\n' "$1"; }
image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

manifest_first_value() {
  local file="$1"
  local key="$2"
  awk -v wanted="${key}:" '$1 == wanted { print $2; exit }' "$file"
}

compose_service_image() {
  local service="$1"
  awk -v service="${service}:" '
    $1 == service { in_service = 1; next }
    in_service && $0 ~ /^[^[:space:]]/ { exit }
    in_service && $1 == "image:" { print $2; exit }
  ' "${REPO_ROOT}/docker-compose.yml"
}

verify_image_match() {
  local service_name="$1"
  local compose_image="$2"
  local k8s_image="$3"

  [[ -n "$compose_image" ]] || fail "Could not determine ${service_name} image from docker-compose.yml"
  [[ -n "$k8s_image" ]] || fail "Could not determine ${service_name} image from Kubernetes manifest"
  [[ "$compose_image" == "$k8s_image" ]] || fail "${service_name} image mismatch: docker-compose.yml uses '${compose_image}', but Kubernetes uses '${k8s_image}'. Standardize these tags before deploying."
}

run_stage() {
  local message="$1"
  shift
  CURRENT_STAGE="$message"
  printf '\n%s\n' "$message"
  "$@"
}

preflight() {
  CURRENT_STAGE="preflight checks"
  info "Checking prerequisites..."

  require_cmd docker
  require_minikube
  resolve_kubectl

  docker info >/dev/null 2>&1 || fail "Docker is installed but the Docker daemon is not reachable. Start Docker and retry."
  docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin is required."

  require_minikube_running
  "${KUBECTL[@]}" get nodes >/dev/null

  [[ -d "${REPO_ROOT}/k8s" ]] || fail "Required k8s directory not found at ${REPO_ROOT}/k8s"
  [[ -f "${REPO_ROOT}/backend/Dockerfile" ]] || fail "Required backend Dockerfile not found at ${REPO_ROOT}/backend/Dockerfile"
  [[ -f "${REPO_ROOT}/frontend/Dockerfile" ]] || fail "Required frontend Dockerfile not found at ${REPO_ROOT}/frontend/Dockerfile"
  [[ -f "$BACKEND_DEPLOYMENT_MANIFEST" ]] || fail "Missing backend deployment manifest: $BACKEND_DEPLOYMENT_MANIFEST"
  [[ -f "$FRONTEND_DEPLOYMENT_MANIFEST" ]] || fail "Missing frontend deployment manifest: $FRONTEND_DEPLOYMENT_MANIFEST"

  BACKEND_DEPLOYMENT="$(manifest_first_value "$BACKEND_DEPLOYMENT_MANIFEST" "name")"
  FRONTEND_DEPLOYMENT="$(manifest_first_value "$FRONTEND_DEPLOYMENT_MANIFEST" "name")"
  BACKEND_IMAGE="$(awk '$1 == "image:" { print $2; exit }' "$BACKEND_DEPLOYMENT_MANIFEST")"
  FRONTEND_IMAGE="$(awk '$1 == "image:" { print $2; exit }' "$FRONTEND_DEPLOYMENT_MANIFEST")"
  COMPOSE_BACKEND_IMAGE="$(compose_service_image backend)"
  COMPOSE_FRONTEND_IMAGE="$(compose_service_image frontend)"

  verify_image_match "backend" "$COMPOSE_BACKEND_IMAGE" "$BACKEND_IMAGE"
  verify_image_match "frontend" "$COMPOSE_FRONTEND_IMAGE" "$FRONTEND_IMAGE"

  info "Using Kubernetes command: ${KUBECTL_MODE}"
  info "Using namespace: ${NAMESPACE}"
  info "Backend deployment/image: ${BACKEND_DEPLOYMENT} -> ${BACKEND_IMAGE}"
  info "Frontend deployment/image: ${FRONTEND_DEPLOYMENT} -> ${FRONTEND_IMAGE}"
}

build_backend() {
  (cd "$REPO_ROOT" && eval "$(minikube docker-env -u)" && docker compose build backend)
  image_exists "$BACKEND_IMAGE" || fail "Missing image ${BACKEND_IMAGE} after backend build."
}

build_frontend() {
  (cd "$REPO_ROOT" && eval "$(minikube docker-env -u)" && docker compose build frontend)
  image_exists "$FRONTEND_IMAGE" || fail "Missing image ${FRONTEND_IMAGE} after frontend build."
}

load_images() {
  minikube image load "$BACKEND_IMAGE"
  minikube image load "$FRONTEND_IMAGE"
  if image_exists "$POSTGRES_IMAGE"; then
    minikube image load "$POSTGRES_IMAGE"
  else
    info "Warning: host image ${POSTGRES_IMAGE} not found; Minikube will pull it if needed."
  fi
}

apply_manifests() {
  cd "$REPO_ROOT"

  "${KUBECTL[@]}" apply -f k8s/namespace.yaml
  "${KUBECTL[@]}" wait --for=jsonpath='{.status.phase}'=Active "namespace/${NAMESPACE}" --timeout=60s

  info "Creating/updating postgres-init-sql ConfigMap from database/schema.sql and database/seed.sql..."
  "${KUBECTL[@]}" create configmap postgres-init-sql \
    --from-file=01-schema.sql=database/schema.sql \
    --from-file=02-seed.sql=database/seed.sql \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

  "${KUBECTL[@]}" apply -f k8s/configmap.yaml
  "${KUBECTL[@]}" apply -f k8s/secret.yaml
  "${KUBECTL[@]}" apply -f k8s/postgres-service.yaml
  "${KUBECTL[@]}" apply -f k8s/postgres-deployment.yaml

  info "Waiting for PostgreSQL readiness before the init Job..."
  "${KUBECTL[@]}" wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s

  if "${KUBECTL[@]}" get job postgres-init -n "$NAMESPACE" >/dev/null 2>&1; then
    succeeded="$("${KUBECTL[@]}" get job postgres-init -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    if [[ "$succeeded" == "1" && "${FORCE_POSTGRES_INIT:-0}" != "1" ]]; then
      info "postgres-init Job already completed; database init will not be rerun. Set FORCE_POSTGRES_INIT=1 to recreate it."
    else
      info "Recreating postgres-init Job because it has not completed or FORCE_POSTGRES_INIT=1 was set. This may reset demo data depending on the SQL files."
      "${KUBECTL[@]}" delete job postgres-init -n "$NAMESPACE" --ignore-not-found
      "${KUBECTL[@]}" apply -f k8s/postgres-init-job.yaml
      "${KUBECTL[@]}" wait --for=condition=complete job/postgres-init -n "$NAMESPACE" --timeout=180s
    fi
  else
    info "postgres-init Job does not exist; creating it now. Set FORCE_POSTGRES_INIT=1 on later runs to force recreation."
    "${KUBECTL[@]}" apply -f k8s/postgres-init-job.yaml
    "${KUBECTL[@]}" wait --for=condition=complete job/postgres-init -n "$NAMESPACE" --timeout=180s
  fi

  "${KUBECTL[@]}" apply -f k8s/backend-service.yaml
  "${KUBECTL[@]}" apply -f k8s/backend-deployment.yaml
  "${KUBECTL[@]}" apply -f k8s/frontend-service.yaml
  "${KUBECTL[@]}" apply -f k8s/frontend-deployment.yaml
  "${KUBECTL[@]}" apply -f k8s/ingress.yaml
  "${KUBECTL[@]}" apply -f k8s/hpa.yaml
}

restart_deployments() {
  "${KUBECTL[@]}" rollout restart "deployment/${BACKEND_DEPLOYMENT}" -n "$NAMESPACE"
  "${KUBECTL[@]}" rollout restart "deployment/${FRONTEND_DEPLOYMENT}" -n "$NAMESPACE"
}

wait_for_rollout() {
  "${KUBECTL[@]}" rollout status "deployment/${BACKEND_DEPLOYMENT}" -n "$NAMESPACE" --timeout=240s
  "${KUBECTL[@]}" rollout status "deployment/${FRONTEND_DEPLOYMENT}" -n "$NAMESPACE" --timeout=240s
}

print_summary() {
  printf '\nDeployment complete. Final cluster status:\n\n'
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -o wide
  printf '\n'
  "${KUBECTL[@]}" get services -n "$NAMESPACE"

  cat <<SUMMARY

Suggested verification commands:
  ./scripts/k8s-test-local.sh
  ./scripts/k8s-status.sh

If you need public browser access for the demo, continue using the existing iptables-based expose script:
  PUBLIC_PORT=3000 NODE_PORT=${NODE_PORT} ./scripts/k8s-expose-demo.sh
SUMMARY
}

preflight
run_stage "[1/6] Building backend image..." build_backend
run_stage "[2/6] Building frontend image..." build_frontend
run_stage "[3/6] Loading images into Minikube..." load_images
run_stage "[4/6] Applying Kubernetes manifests..." apply_manifests
run_stage "[5/6] Restarting deployments to avoid stale images..." restart_deployments
run_stage "[6/6] Waiting for rollout..." wait_for_rollout
print_summary
