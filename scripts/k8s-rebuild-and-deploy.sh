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
BACKEND_DEPLOYMENTS=(public-backend admin-backend monitoring-backend)
BACKEND_SELECTORS=(app=public-backend app=admin-backend app=monitoring-backend)
BACKEND_MANIFESTS=(
  "${REPO_ROOT}/k8s/public-backend-deployment.yaml"
  "${REPO_ROOT}/k8s/admin-backend-deployment.yaml"
  "${REPO_ROOT}/k8s/monitoring-backend-deployment.yaml"
)
PUBLIC_BACKEND_DEPLOYMENT_MANIFEST="${REPO_ROOT}/k8s/public-backend-deployment.yaml"
FRONTEND_DEPLOYMENT_MANIFEST="${REPO_ROOT}/k8s/frontend-deployment.yaml"
CURRENT_STAGE="preflight checks"

declare -A BACKEND_REPLICAS

trap 'echo "Error: ${CURRENT_STAGE} failed at line ${LINENO}. See the command output above for details." >&2' ERR

fail() { echo "Error: $1" >&2; exit 1; }
info() { printf '%s\n' "$1"; }
image_exists() { docker image inspect "$1" >/dev/null 2>&1; }

manifest_first_value() {
  local file="$1"
  local key="$2"
  awk -v wanted="${key}:" '$1 == wanted { print $2; exit }' "$file"
}

manifest_replicas() {
  local file="$1"
  local fallback="$2"
  local replicas

  replicas="$(awk '$1 == "replicas:" { print $2; exit }' "$file")"
  printf '%s\n' "${replicas:-$fallback}"
}

is_single_component_image() {
  local image="$1"
  local image_without_digest="${image%%@*}"
  local image_without_tag="$image_without_digest"

  if [[ "$image_without_tag" == *":"* && "$image_without_tag" != *"/"* ]]; then
    image_without_tag="${image_without_tag%%:*}"
  elif [[ "$image_without_tag" == */* ]]; then
    local last_component="${image_without_tag##*/}"
    local prefix="${image_without_tag%/*}"
    if [[ "$last_component" == *":"* ]]; then
      image_without_tag="${prefix}/${last_component%%:*}"
    fi
  fi

  [[ "$image_without_tag" != */* ]]
}

docker_library_alias() {
  local image="$1"

  if is_single_component_image "$image"; then
    printf 'docker.io/library/%s\n' "$image"
  fi
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
  [[ -f "$PUBLIC_BACKEND_DEPLOYMENT_MANIFEST" ]] || fail "Missing public backend deployment manifest: $PUBLIC_BACKEND_DEPLOYMENT_MANIFEST"
  [[ -f "$FRONTEND_DEPLOYMENT_MANIFEST" ]] || fail "Missing frontend deployment manifest: $FRONTEND_DEPLOYMENT_MANIFEST"
  for manifest in "${BACKEND_MANIFESTS[@]}"; do
    [[ -f "$manifest" ]] || fail "Missing backend deployment manifest: $manifest"
  done

  BACKEND_IMAGE="$(awk '$1 == "image:" { print $2; exit }' "$PUBLIC_BACKEND_DEPLOYMENT_MANIFEST")"
  FRONTEND_DEPLOYMENT="$(manifest_first_value "$FRONTEND_DEPLOYMENT_MANIFEST" "name")"
  FRONTEND_IMAGE="$(awk '$1 == "image:" { print $2; exit }' "$FRONTEND_DEPLOYMENT_MANIFEST")"
  COMPOSE_BACKEND_IMAGE="$(compose_service_image backend)"
  COMPOSE_FRONTEND_IMAGE="$(compose_service_image frontend)"

  for manifest in "${BACKEND_MANIFESTS[@]}"; do
    local image
    image="$(awk '$1 == "image:" { print $2; exit }' "$manifest")"
    [[ "$image" == "$BACKEND_IMAGE" ]] || fail "Backend split must reuse one image. ${manifest} uses '${image}', expected '${BACKEND_IMAGE}'."
  done

  verify_image_match "backend" "$COMPOSE_BACKEND_IMAGE" "$BACKEND_IMAGE"
  verify_image_match "frontend" "$COMPOSE_FRONTEND_IMAGE" "$FRONTEND_IMAGE"

  info "Using Kubernetes command: ${KUBECTL_MODE}"
  info "Using namespace: ${NAMESPACE}"
  info "Backend image reused by deployments: ${BACKEND_DEPLOYMENTS[*]} -> ${BACKEND_IMAGE}"
  info "Frontend deployment/image: ${FRONTEND_DEPLOYMENT} -> ${FRONTEND_IMAGE}"
}

build_backend() {
  (cd "$REPO_ROOT" && eval "$(minikube docker-env -u)" && docker compose build backend)
  image_exists "$BACKEND_IMAGE" || fail "Missing image ${BACKEND_IMAGE} after backend build."
}

verify_backend_host_image() {
  local found

  found="$(docker run --rm "$BACKEND_IMAGE" find / -name "admin_books.py" 2>/dev/null || true)"
  if [[ -z "$found" ]]; then
    fail "Host backend image ${BACKEND_IMAGE} does not contain admin_books.py. Check backend/Dockerfile, docker-compose.yml build context, and .dockerignore, then rebuild."
  fi

  info "Verified host backend image contains admin_books.py:"
  printf '%s\n' "$found"
}

build_frontend() {
  (cd "$REPO_ROOT" && eval "$(minikube docker-env -u)" && docker compose build frontend)
  image_exists "$FRONTEND_IMAGE" || fail "Missing image ${FRONTEND_IMAGE} after frontend build."
}

deployment_exists() {
  local deployment="$1"
  "${KUBECTL[@]}" get "deployment/${deployment}" -n "$NAMESPACE" >/dev/null 2>&1
}

save_replica_counts() {
  local frontend_default
  frontend_default="$(manifest_replicas "$FRONTEND_DEPLOYMENT_MANIFEST" 2)"

  for i in "${!BACKEND_DEPLOYMENTS[@]}"; do
    local deployment="${BACKEND_DEPLOYMENTS[$i]}"
    local default_replicas
    default_replicas="$(manifest_replicas "${BACKEND_MANIFESTS[$i]}" 1)"
    if deployment_exists "$deployment"; then
      BACKEND_REPLICAS[$deployment]="$("${KUBECTL[@]}" get "deployment/${deployment}" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
    else
      BACKEND_REPLICAS[$deployment]="$default_replicas"
    fi
    BACKEND_REPLICAS[$deployment]="${BACKEND_REPLICAS[$deployment]:-$default_replicas}"
  done

  if deployment_exists "$FRONTEND_DEPLOYMENT"; then
    FRONTEND_REPLICAS="$("${KUBECTL[@]}" get "deployment/${FRONTEND_DEPLOYMENT}" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')"
  else
    FRONTEND_REPLICAS="$frontend_default"
  fi
  FRONTEND_REPLICAS="${FRONTEND_REPLICAS:-$frontend_default}"

  info "Saved desired replica counts: public-backend=${BACKEND_REPLICAS[public-backend]}, admin-backend=${BACKEND_REPLICAS[admin-backend]}, monitoring-backend=${BACKEND_REPLICAS[monitoring-backend]}, ${FRONTEND_DEPLOYMENT}=${FRONTEND_REPLICAS}"
}

wait_for_pods_gone() {
  local label_selector="$1"
  local description="$2"
  local timeout_seconds=180
  local elapsed=0
  local pods
  local pods_display

  while (( elapsed < timeout_seconds )); do
    pods="$("${KUBECTL[@]}" get pods -n "$NAMESPACE" -l "$label_selector" -o name 2>/dev/null || true)"
    if [[ -z "$pods" ]]; then
      info "All ${description} Pods are gone."
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done

  pods_display="$(printf '%s' "$pods" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  fail "Timed out waiting for old ${description} Pods to terminate before replacing same-tag images. Remaining Pods: ${pods_display}"
}

scale_deployments_to_zero() {
  for i in "${!BACKEND_DEPLOYMENTS[@]}"; do
    local deployment="${BACKEND_DEPLOYMENTS[$i]}"
    local selector="${BACKEND_SELECTORS[$i]}"
    if deployment_exists "$deployment"; then
      "${KUBECTL[@]}" scale "deployment/${deployment}" -n "$NAMESPACE" --replicas=0
      wait_for_pods_gone "$selector" "$deployment"
    else
      info "Backend deployment ${deployment} does not exist yet; skipping scale-down."
    fi
  done

  # Also retire the legacy shared backend if this cluster was deployed before the split.
  if deployment_exists backend; then
    "${KUBECTL[@]}" scale deployment/backend -n "$NAMESPACE" --replicas=0
    wait_for_pods_gone "app=backend" "legacy backend"
  fi

  if deployment_exists "$FRONTEND_DEPLOYMENT"; then
    "${KUBECTL[@]}" scale "deployment/${FRONTEND_DEPLOYMENT}" -n "$NAMESPACE" --replicas=0
    wait_for_pods_gone "app=frontend" "frontend"
  else
    info "Frontend deployment ${FRONTEND_DEPLOYMENT} does not exist yet; skipping scale-down."
  fi
}

remove_minikube_image() {
  local image="$1"
  local alias

  minikube ssh -- docker rmi -f "$image" || true
  alias="$(docker_library_alias "$image" || true)"
  if [[ -n "$alias" && "$alias" != "$image" ]]; then
    minikube ssh -- docker rmi -f "$alias" || true
  fi
}

remove_old_minikube_images() {
  remove_minikube_image "$BACKEND_IMAGE"
  remove_minikube_image "$FRONTEND_IMAGE"
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

  "${KUBECTL[@]}" apply -f k8s/monitoring-backend-rbac.yaml
  "${KUBECTL[@]}" apply -f k8s/public-backend-service.yaml
  "${KUBECTL[@]}" apply -f k8s/admin-backend-service.yaml
  "${KUBECTL[@]}" apply -f k8s/monitoring-backend-service.yaml
  "${KUBECTL[@]}" apply -f k8s/public-backend-deployment.yaml
  "${KUBECTL[@]}" apply -f k8s/admin-backend-deployment.yaml
  "${KUBECTL[@]}" apply -f k8s/monitoring-backend-deployment.yaml
  "${KUBECTL[@]}" apply -f k8s/frontend-service.yaml
  "${KUBECTL[@]}" apply -f k8s/frontend-deployment.yaml
  "${KUBECTL[@]}" apply -f k8s/ingress.yaml
  "${KUBECTL[@]}" apply -f k8s/hpa.yaml

  "${KUBECTL[@]}" delete hpa backend-hpa -n "$NAMESPACE" --ignore-not-found
  "${KUBECTL[@]}" delete deployment backend -n "$NAMESPACE" --ignore-not-found
  "${KUBECTL[@]}" delete service backend-service -n "$NAMESPACE" --ignore-not-found
  "${KUBECTL[@]}" delete rolebinding bookstore-backend-readonly -n "$NAMESPACE" --ignore-not-found
  "${KUBECTL[@]}" delete role bookstore-backend-readonly -n "$NAMESPACE" --ignore-not-found
  "${KUBECTL[@]}" delete serviceaccount bookstore-backend -n "$NAMESPACE" --ignore-not-found
}

restore_replica_counts() {
  for deployment in "${BACKEND_DEPLOYMENTS[@]}"; do
    "${KUBECTL[@]}" scale "deployment/${deployment}" -n "$NAMESPACE" --replicas="${BACKEND_REPLICAS[$deployment]}"
  done
  "${KUBECTL[@]}" scale "deployment/${FRONTEND_DEPLOYMENT}" -n "$NAMESPACE" --replicas="$FRONTEND_REPLICAS"
}

wait_for_rollout() {
  for deployment in "${BACKEND_DEPLOYMENTS[@]}"; do
    "${KUBECTL[@]}" rollout status "deployment/${deployment}" -n "$NAMESPACE" --timeout=240s
  done
  "${KUBECTL[@]}" rollout status "deployment/${FRONTEND_DEPLOYMENT}" -n "$NAMESPACE" --timeout=240s
}

verify_running_backend_image() {
  for i in "${!BACKEND_DEPLOYMENTS[@]}"; do
    local deployment="${BACKEND_DEPLOYMENTS[$i]}"
    local selector="${BACKEND_SELECTORS[$i]}"
    local backend_pod
    local found

    backend_pod="$("${KUBECTL[@]}" get pod -n "$NAMESPACE" -l "$selector" -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | awk '{print $1}')"
    [[ -n "$backend_pod" ]] || fail "Could not find a running ${deployment} Pod to verify admin_books.py after rollout."

    found="$("${KUBECTL[@]}" exec -n "$NAMESPACE" "$backend_pod" -- find / -name "admin_books.py" 2>/dev/null || true)"
    if [[ -z "$found" ]]; then
      fail "Stale Minikube image detected: ${deployment} Pod ${backend_pod} does not contain admin_books.py after loading ${BACKEND_IMAGE}. Scale backend/frontend to 0, remove old same-tag images inside Minikube, reload images, and redeploy."
    fi

    info "Verified running ${deployment} Pod ${backend_pod} contains admin_books.py:"
    printf '%s\n' "$found"
  done
}

print_summary() {
  printf '\nDeployment complete. Final cluster status:\n\n'
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -o wide
  printf '\n'
  "${KUBECTL[@]}" get services -n "$NAMESPACE"
  printf '\n'
  "${KUBECTL[@]}" get hpa -n "$NAMESPACE"

  cat <<SUMMARY

Suggested verification commands:
  ./scripts/k8s-test-local.sh
  ./scripts/k8s-status.sh

If you need public browser access for the demo, continue using the existing iptables-based expose script:
  PUBLIC_PORT=3000 NODE_PORT=${NODE_PORT} ./scripts/k8s-expose-demo.sh
SUMMARY
}

preflight
run_stage "[1/10] Building backend image..." build_backend
run_stage "[2/10] Verifying backend image contents..." verify_backend_host_image
run_stage "[3/10] Building frontend image..." build_frontend
run_stage "[4/10] Saving current replica counts..." save_replica_counts
run_stage "[5/10] Scaling backend/frontend to zero before replacing stable tags..." scale_deployments_to_zero
run_stage "[6/10] Removing old same-tag images inside Minikube..." remove_old_minikube_images
run_stage "[7/10] Loading fresh images into Minikube..." load_images
run_stage "[8/10] Applying Kubernetes manifests..." apply_manifests
run_stage "[9/10] Restoring replica counts and waiting for rollout..." restore_replica_counts
wait_for_rollout
run_stage "[10/10] Verifying running backend image contents..." verify_running_backend_image
print_summary
