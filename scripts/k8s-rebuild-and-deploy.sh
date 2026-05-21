#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="${NAMESPACE:-bookstore}"
POSTGRES_IMAGE="postgres:16"
NODE_PORT="30080"
DB_MODE="${DB_MODE:-single}"
if [[ "$DB_MODE" != "single" && "$DB_MODE" != "ha" ]]; then
  echo "Error: DB_MODE must be single or ha (got $DB_MODE)" >&2
  exit 1
fi
DB_SERVICE="postgres-service"
if [[ "$DB_MODE" == "ha" ]]; then
  DB_SERVICE="bookstore-postgres-rw"
fi
COMMAND="${1:-all}"
VALID_COMMANDS=(all install-cnpg apply-ha-database init-db deploy-app verify-app)
BACKEND_DEPLOYMENTS=(public-backend admin-backend monitoring-backend)
BACKEND_SELECTORS=(app=public-backend app=admin-backend app=monitoring-backend)
declare -A SAFE_DEFAULT_REPLICAS=(
  [public-backend]=2
  [admin-backend]=1
  [monitoring-backend]=1
  [frontend]=2
)
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
  info "DB_MODE=${DB_MODE}; backend DB service=${DB_SERVICE}; HA enabled=$([[ "$DB_MODE" == "ha" ]] && echo yes || echo no); command=${COMMAND}"
  if [[ "$DB_MODE" == "ha" ]]; then
    info "Warning: DB_MODE=ha runs 3 PostgreSQL instances plus the app, ingress, and metrics-server. A single-node Minikube cluster with 4GB memory can be unstable; use 6GB+ memory if available."
  fi
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
  frontend_default="$(manifest_replicas "$FRONTEND_DEPLOYMENT_MANIFEST" "${SAFE_DEFAULT_REPLICAS[frontend]}")"

  for i in "${!BACKEND_DEPLOYMENTS[@]}"; do
    local deployment="${BACKEND_DEPLOYMENTS[$i]}"
    local default_replicas
    default_replicas="$(manifest_replicas "${BACKEND_MANIFESTS[$i]}" "${SAFE_DEFAULT_REPLICAS[$deployment]}")"
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

  local restore_defaults=0
  if [[ "${RESTORE_DEFAULT_REPLICAS:-0}" == "1" ]]; then
    info "RESTORE_DEFAULT_REPLICAS=1 set; restoring safe default replica counts instead of saved counts."
    restore_defaults=1
  elif [[ "${BACKEND_REPLICAS[public-backend]}" == "0" && "${BACKEND_REPLICAS[admin-backend]}" == "0" && "${BACKEND_REPLICAS[monitoring-backend]}" == "0" && "$FRONTEND_REPLICAS" == "0" ]]; then
    info "Saved desired replica counts are all zero; assuming a previous failed refresh left application deployments scaled down. Restoring safe default replica counts."
    restore_defaults=1
  fi

  if [[ "$restore_defaults" == "1" ]]; then
    BACKEND_REPLICAS[public-backend]="${SAFE_DEFAULT_REPLICAS[public-backend]}"
    BACKEND_REPLICAS[admin-backend]="${SAFE_DEFAULT_REPLICAS[admin-backend]}"
    BACKEND_REPLICAS[monitoring-backend]="${SAFE_DEFAULT_REPLICAS[monitoring-backend]}"
    FRONTEND_REPLICAS="${SAFE_DEFAULT_REPLICAS[frontend]}"
  fi

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

disable_hpa_before_image_replacement() {
  if "${KUBECTL[@]}" get hpa public-backend-hpa -n "$NAMESPACE" >/dev/null 2>&1; then
    info "Deleting public-backend-hpa before image replacement so HPA cannot recreate public-backend Pods with the old same-tag image."
    "${KUBECTL[@]}" delete hpa public-backend-hpa -n "$NAMESPACE" --ignore-not-found
  else
    info "public-backend-hpa is not present; no HPA can recreate public-backend during image replacement."
  fi
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


render_init_job_manifest() {
  local init_job_name="$1"

  awk -v init_job_name="$init_job_name" '
    !renamed && $0 == "  name: postgres-init" {
      print "  name: " init_job_name
      renamed = 1
      next
    }
    { print }
  ' k8s/postgres-init-job.yaml
}

apply_init_job_manifest() {
  local init_job_name="$1"

  render_init_job_manifest "$init_job_name" | "${KUBECTL[@]}" apply -f -
}


report_cnpg_permission_issue_hint() {
  info "CloudNativePG Ready wait timed out; collecting diagnostics..."
  local cluster_desc cluster_events initdb_pods initdb_logs stuck_dangling no_initdb_job no_primary_pod

  "${KUBECTL[@]}" get pods,pvc,job -n "$NAMESPACE" || true
  "${KUBECTL[@]}" get cluster bookstore-postgres -n "$NAMESPACE" || true

  cluster_desc="$("${KUBECTL[@]}" describe cluster/bookstore-postgres -n "$NAMESPACE" 2>&1 || true)"
  printf '%s
' "$cluster_desc"

  cluster_events="$("${KUBECTL[@]}" get events -n "$NAMESPACE" --sort-by=.lastTimestamp 2>&1 || true)"
  printf '%s
' "$cluster_events"

  initdb_pods="$("${KUBECTL[@]}" get pods -n "$NAMESPACE" -o name 2>/dev/null | grep 'bookstore-postgres-1-initdb-' || true)"
  initdb_logs=""
  if [[ -n "$initdb_pods" ]]; then
    while IFS= read -r pod; do
      [[ -z "$pod" ]] && continue
      info "Recent logs from ${pod}:"
      local pod_logs
      pod_logs="$("${KUBECTL[@]}" logs -n "$NAMESPACE" "$pod" --all-containers=true --tail=200 2>&1 || true)"
      printf '%s
' "$pod_logs"
      initdb_logs+="$pod_logs"$'
'
    done <<< "$initdb_pods"
  fi

  if printf '%s
%s
' "$cluster_desc" "$initdb_logs" | grep -F 'Permission denied' >/dev/null      && printf '%s
%s
' "$cluster_desc" "$initdb_logs" | grep -F '/var/lib/postgresql/data/pgdata' >/dev/null; then
    info "Detected CloudNativePG hostPath PVC permission issue."
    if [[ "${AUTO_FIX_CNPG_PVC_PERMISSIONS:-0}" == "1" ]]; then
      info "AUTO_FIX_CNPG_PVC_PERMISSIONS=1 set; invoking CNPG PVC permission repair helper."
      MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}" DB_MODE=ha NAMESPACE="$NAMESPACE" CLUSTER_NAME="bookstore-postgres" CNPG_POSTGRES_IMAGE="${CNPG_POSTGRES_IMAGE:-ghcr.io/cloudnative-pg/postgresql:16.4}" FORCE_DELETE_DANGLING_CNPG_PVC="${FORCE_DELETE_DANGLING_CNPG_PVC:-0}" ./scripts/k8s-fix-cnpg-pvc-permissions.sh
      info "Re-waiting for CloudNativePG Cluster/bookstore-postgres to report Ready=True after repair..."
      "${KUBECTL[@]}" wait --for=condition=Ready cluster/bookstore-postgres -n "$NAMESPACE" --timeout=300s
      return 0
    fi
  fi

  stuck_dangling="$("${KUBECTL[@]}" get cluster bookstore-postgres -n "$NAMESPACE" -o jsonpath='{.status.danglingPVC}' 2>/dev/null || true)"
  no_initdb_job="$("${KUBECTL[@]}" get jobs -n "$NAMESPACE" -o name 2>/dev/null | grep -F 'bookstore-postgres-1-initdb' || true)"
  no_primary_pod="$("${KUBECTL[@]}" get pod -n "$NAMESPACE" bookstore-postgres-1 -o name 2>/dev/null || true)"

  if [[ "$stuck_dangling" == *bookstore-postgres-1* && -z "$no_initdb_job" && -z "$no_primary_pod" ]]; then
    if [[ "${FORCE_DELETE_DANGLING_CNPG_PVC:-0}" == "1" ]]; then
      info "Detected dangling failed-new-init PVC and FORCE_DELETE_DANGLING_CNPG_PVC=1 is set; invoking repair helper."
      MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}" DB_MODE=ha NAMESPACE="$NAMESPACE" CLUSTER_NAME="bookstore-postgres" CNPG_POSTGRES_IMAGE="${CNPG_POSTGRES_IMAGE:-ghcr.io/cloudnative-pg/postgresql:16.4}" FORCE_DELETE_DANGLING_CNPG_PVC=1 ./scripts/k8s-fix-cnpg-pvc-permissions.sh
      info "Re-waiting for CloudNativePG Cluster/bookstore-postgres to report Ready=True after dangling PVC recovery..."
      "${KUBECTL[@]}" wait --for=condition=Ready cluster/bookstore-postgres -n "$NAMESPACE" --timeout=300s
      return 0
    fi

    info "Detected dangling failed-new-init PVC recovery condition. Run exactly:"
    info "FORCE_DELETE_DANGLING_CNPG_PVC=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-fix-cnpg-pvc-permissions.sh"
    info "This force-delete path is only safe for failed brand-new initialization, never for real databases with data."
  fi

  return 1
}
print_init_job_diagnostics() {
  local init_job_name="$1"

  info "${init_job_name} did not complete before the timeout; collecting diagnostics..."
  "${KUBECTL[@]}" describe job "$init_job_name" -n "$NAMESPACE" || true
  "${KUBECTL[@]}" describe pod -n "$NAMESPACE" -l "job-name=${init_job_name}" || true
  "${KUBECTL[@]}" logs -n "$NAMESPACE" -l "job-name=${init_job_name}" --all-containers=true --tail=200 || true
  "${KUBECTL[@]}" get events -n "$NAMESPACE" --sort-by=.lastTimestamp || true
}

wait_for_init_job_complete() {
  local init_job_name="$1"

  if ! "${KUBECTL[@]}" wait --for=condition=complete "job/${init_job_name}" -n "$NAMESPACE" --timeout=180s; then
    if [[ "$init_job_name" == "postgres-init-ha" ]]; then
      print_init_job_diagnostics "$init_job_name"
    fi
    return 1
  fi
}

cnpg_client_pod() {
  "${KUBECTL[@]}" get pod -n "$NAMESPACE" -l cnpg.io/cluster=bookstore-postgres \
    -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | awk '{print $1}'
}

ha_schema_initialized() {
  local pod
  local db_user
  local db_password
  local table_count

  pod="$(cnpg_client_pod)"
  if [[ -z "$pod" ]]; then
    info "Could not find a running CloudNativePG Pod to check HA schema; init Job decision will use Job state."
    return 1
  fi

  db_user="$("${KUBECTL[@]}" get secret bookstore-secret -n "$NAMESPACE" -o jsonpath='{.data.DB_USER}' 2>/dev/null | base64 --decode || true)"
  db_password="$("${KUBECTL[@]}" get secret bookstore-secret -n "$NAMESPACE" -o jsonpath='{.data.DB_PASSWORD}' 2>/dev/null | base64 --decode || true)"
  db_user="${db_user:-bookstore}"
  if [[ -z "$db_password" ]]; then
    info "Could not read bookstore-secret DB_PASSWORD to check HA schema; init Job decision will use Job state."
    return 1
  fi

  table_count="$("${KUBECTL[@]}" exec -n "$NAMESPACE" "$pod" -- env PGPASSWORD="$db_password" \
    psql -h "$DB_SERVICE" -p 5432 -U "$db_user" -d bookstore -tAc \
    "select count(*) from information_schema.tables where table_schema='public' and table_name in ('books','orders','order_items','carts');" 2>/dev/null | tr -d '[:space:]' || true)"

  if [[ "$table_count" == "4" ]]; then
    info "HA database already contains books/orders/order_items/carts; skipping postgres-init-ha. Set FORCE_POSTGRES_INIT=1 to recreate the init Job."
    return 0
  fi

  info "HA schema check found ${table_count:-0}/4 expected tables; init Job is required."
  return 1
}

run_init_job_if_needed() {
  local init_job_name="$1"
  local succeeded

  if [[ "$init_job_name" == "postgres-init-ha" && "${FORCE_POSTGRES_INIT:-0}" != "1" ]] && ha_schema_initialized; then
    return 0
  fi

  if "${KUBECTL[@]}" get job "$init_job_name" -n "$NAMESPACE" >/dev/null 2>&1; then
    succeeded="$("${KUBECTL[@]}" get job "$init_job_name" -n "$NAMESPACE" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
    if [[ "$succeeded" == "1" && "${FORCE_POSTGRES_INIT:-0}" != "1" ]]; then
      info "${init_job_name} Job already completed; database init will not be rerun. Set FORCE_POSTGRES_INIT=1 to recreate it."
    else
      if [[ "${FORCE_POSTGRES_INIT:-0}" != "1" ]]; then
        info "${init_job_name} exists but has not completed. Leaving it in place because FORCE_POSTGRES_INIT is not set; delete/fix it manually or rerun with FORCE_POSTGRES_INIT=1 after reviewing diagnostics."
        print_init_job_diagnostics "$init_job_name"
        return 1
      fi
      info "Recreating ${init_job_name} Job because FORCE_POSTGRES_INIT=1 was set. This may reset demo data depending on the SQL files."
      "${KUBECTL[@]}" delete job "$init_job_name" -n "$NAMESPACE" --ignore-not-found
      apply_init_job_manifest "$init_job_name"
      wait_for_init_job_complete "$init_job_name"
    fi
  else
    info "${init_job_name} Job does not exist; creating it now. Set FORCE_POSTGRES_INIT=1 on later runs to force recreation."
    apply_init_job_manifest "$init_job_name"
    wait_for_init_job_complete "$init_job_name"
  fi
}

apply_namespace_and_init_sql_config() {
  cd "$REPO_ROOT"

  "${KUBECTL[@]}" apply -f k8s/namespace.yaml
  "${KUBECTL[@]}" wait --for=jsonpath='{.status.phase}'=Active "namespace/${NAMESPACE}" --timeout=60s

  info "Creating/updating postgres-init-sql ConfigMap with keys expected by postgres-init Job: 01-schema.sql and 02-seed.sql..."
  "${KUBECTL[@]}" create configmap postgres-init-sql \
    --from-file=01-schema.sql=database/schema.sql \
    --from-file=02-seed.sql=database/seed.sql \
    -n "$NAMESPACE" \
    --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

  "${KUBECTL[@]}" apply -f k8s/secret.yaml
}

configure_ha_database() {
  cd "$REPO_ROOT"

  info "Configuring bookstore-config for CloudNativePG HA service ${DB_SERVICE}..."
  "${KUBECTL[@]}" create configmap bookstore-config \
    --from-literal=DB_MODE=ha \
    --from-literal=DB_HOST="${DB_SERVICE}" \
    --from-literal=DB_WRITE_HOST="${DB_SERVICE}" \
    --from-literal=DB_READ_HOST=bookstore-postgres-ro \
    --from-literal=DB_PORT=5432 \
    --from-literal=DB_NAME=bookstore \
    --from-literal=APP_USER_ID=demo-user \
    -n "$NAMESPACE" --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
  if deployment_exists postgres; then
    info "DB_MODE=ha selected; scaling legacy single PostgreSQL Deployment to 0 without deleting its PVC."
    "${KUBECTL[@]}" scale deployment/postgres -n "$NAMESPACE" --replicas=0
  fi
  "${KUBECTL[@]}" apply -f k8s/postgres-ha/app-secret.yaml
  "${KUBECTL[@]}" apply -f k8s/postgres-ha/cluster.yaml
  info "Waiting for CloudNativePG Cluster/bookstore-postgres to report Ready=True..."
  if ! "${KUBECTL[@]}" wait --for=condition=Ready cluster/bookstore-postgres -n "$NAMESPACE" --timeout=300s; then
    report_cnpg_permission_issue_hint || return 1
  fi
}

configure_single_database() {
  cd "$REPO_ROOT"

  "${KUBECTL[@]}" apply -f k8s/configmap.yaml
  "${KUBECTL[@]}" apply -f k8s/postgres-service.yaml
  "${KUBECTL[@]}" apply -f k8s/postgres-deployment.yaml

  info "Waiting for PostgreSQL readiness before the init Job..."
  "${KUBECTL[@]}" wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s
}

run_database_init() {
  if [[ "$DB_MODE" == "ha" ]]; then
    run_init_job_if_needed postgres-init-ha
  else
    run_init_job_if_needed postgres-init
  fi
}

apply_app_manifests_only() {
  cd "$REPO_ROOT"

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

apply_ha_database_only() {
  apply_namespace_and_init_sql_config
  configure_ha_database
}

apply_ha_init_only() {
  apply_ha_database_only
  run_database_init
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

  "${KUBECTL[@]}" apply -f k8s/secret.yaml
  if [[ "$DB_MODE" == "ha" ]]; then
    info "Configuring bookstore-config for CloudNativePG HA service ${DB_SERVICE}..."
    "${KUBECTL[@]}" create configmap bookstore-config \
      --from-literal=DB_MODE=ha \
      --from-literal=DB_HOST="${DB_SERVICE}" \
      --from-literal=DB_WRITE_HOST="${DB_SERVICE}" \
      --from-literal=DB_READ_HOST=bookstore-postgres-ro \
      --from-literal=DB_PORT=5432 \
      --from-literal=DB_NAME=bookstore \
      --from-literal=APP_USER_ID=demo-user \
      -n "$NAMESPACE" --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -
    if deployment_exists postgres; then
      info "DB_MODE=ha selected; scaling legacy single PostgreSQL Deployment to 0 without deleting its PVC."
      "${KUBECTL[@]}" scale deployment/postgres -n "$NAMESPACE" --replicas=0
    fi
    "${KUBECTL[@]}" apply -f k8s/postgres-ha/app-secret.yaml
    "${KUBECTL[@]}" apply -f k8s/postgres-ha/cluster.yaml
    info "Waiting for CloudNativePG Cluster/bookstore-postgres to report Ready=True..."
    "${KUBECTL[@]}" wait --for=condition=Ready cluster/bookstore-postgres -n "$NAMESPACE" --timeout=300s
    init_job_name="postgres-init-ha"
  else
    "${KUBECTL[@]}" apply -f k8s/configmap.yaml
    "${KUBECTL[@]}" apply -f k8s/postgres-service.yaml
    "${KUBECTL[@]}" apply -f k8s/postgres-deployment.yaml

    info "Waiting for PostgreSQL readiness before the init Job..."
    "${KUBECTL[@]}" wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=180s
    init_job_name="postgres-init"
  fi

  run_init_job_if_needed "$init_job_name"

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

force_app_rollout_restart() {
  local deployments=("${BACKEND_DEPLOYMENTS[@]}" "$FRONTEND_DEPLOYMENT")
  for deployment in "${deployments[@]}"; do
    if deployment_exists "$deployment"; then
      "${KUBECTL[@]}" rollout restart "deployment/${deployment}" -n "$NAMESPACE"
    fi
  done
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
      info "Stale image diagnostics for ${deployment}/${backend_pod}:"
      "${KUBECTL[@]}" get pod "$backend_pod" -n "$NAMESPACE" -o jsonpath='{range .status.containerStatuses[*]}container={.name} image={.image} imageID={.imageID}{"\n"}{end}' || true
      "${KUBECTL[@]}" describe pod "$backend_pod" -n "$NAMESPACE" || true
      minikube ssh -- docker images "${BACKEND_IMAGE%:*}" || true
      fail "Stale Minikube image detected: ${deployment} Pod ${backend_pod} does not contain admin_books.py after loading ${BACKEND_IMAGE}. This workflow deletes public-backend-hpa before replacement, removes same-tag Minikube images, reloads images, forces rollout restart, and uses imagePullPolicy=Never; review diagnostics above for imageID/runtime cache problems."
    fi

    info "Verified running ${deployment} Pod ${backend_pod} contains admin_books.py:"
    printf '%s\n' "$found"
  done
}

print_summary() {
  printf "\nDeployment complete. DB_MODE=%s, backend DB service=%s. Final cluster status:\n\n" "$DB_MODE" "$DB_SERVICE"
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -o wide
  printf '\n'
  "${KUBECTL[@]}" get services -n "$NAMESPACE"
  printf '\n'
  "${KUBECTL[@]}" get hpa -n "$NAMESPACE"

  cat <<SUMMARY

Suggested verification commands:
  ./scripts/k8s-test-local.sh
  DB_MODE=${DB_MODE} ./scripts/k8s-status.sh
  DB_MODE=${DB_MODE} ./scripts/k8s-postgres-ha-status.sh  # HA mode only

If you need public browser access for the demo, continue using the existing iptables-based expose script:
  PUBLIC_PORT=3000 NODE_PORT=${NODE_PORT} ./scripts/k8s-expose-demo.sh
SUMMARY
}

main_all() {
  run_stage "[1/12] Building backend image..." build_backend
  run_stage "[2/12] Verifying backend image contents..." verify_backend_host_image
  run_stage "[3/12] Building frontend image..." build_frontend
  run_stage "[4/12] Saving current replica counts..." save_replica_counts
  run_stage "[5/12] Disabling HPA before replacing stable tags..." disable_hpa_before_image_replacement
  run_stage "[6/12] Scaling backend/frontend to zero before replacing stable tags..." scale_deployments_to_zero
  run_stage "[7/12] Removing old same-tag images inside Minikube..." remove_old_minikube_images
  run_stage "[8/12] Loading fresh images into Minikube..." load_images
  run_stage "[9/12] Applying Kubernetes manifests..." apply_manifests
  run_stage "[10/12] Forcing app rollout restart after image load..." force_app_rollout_restart
  run_stage "[11/12] Restoring replica counts and waiting for rollout..." restore_replica_counts
  wait_for_rollout
  run_stage "[12/12] Verifying running backend image contents..." verify_running_backend_image
  print_summary
}

preflight
if [[ "$DB_MODE" == "ha" && "$COMMAND" == "all" && "${HA_ALLOW_ALL_IN_ONE:-0}" != "1" ]]; then
  cat >&2 <<HA_PLAN
Error: DB_MODE=ha no longer runs the heavy all-in-one workflow by default.
Run the HA deployment in smaller stages to reduce pressure on resource-limited single-node Minikube clusters:
  DB_MODE=ha ${0} install-cnpg
  DB_MODE=ha ${0} apply-ha-database
  DB_MODE=ha ${0} init-db
  DB_MODE=ha ${0} deploy-app
  DB_MODE=ha ${0} verify-app

Preferred one-command HA wrapper that runs those same safe stages in order:
  ./scripts/k8s-ha-rebuild-all.sh

If you intentionally want the old combined path, rerun with HA_ALLOW_ALL_IN_ONE=1.
HA_PLAN
  exit 1
fi

case "$COMMAND" in
  all)
    main_all
    ;;
  install-cnpg)
    [[ "$DB_MODE" == "ha" ]] || fail "install-cnpg command is only valid with DB_MODE=ha."
    run_stage "Installing CloudNativePG operator..." "${SCRIPT_DIR}/k8s-install-cnpg.sh"
    ;;
  apply-ha-database)
    [[ "$DB_MODE" == "ha" ]] || fail "apply-ha-database command is only valid with DB_MODE=ha."
    run_stage "Applying HA database manifests without app rebuild/deploy or init Job recreation..." apply_ha_database_only
    ;;
  init-db)
    [[ "$DB_MODE" == "ha" ]] || fail "init-db command is only valid with DB_MODE=ha."
    run_stage "Running/skipping HA database init only..." apply_ha_init_only
    ;;
  deploy-app)
    run_stage "Building backend image..." build_backend
    run_stage "Verifying backend image contents..." verify_backend_host_image
    run_stage "Building frontend image..." build_frontend
    run_stage "Saving current replica counts..." save_replica_counts
    run_stage "Disabling HPA before replacing stable tags..." disable_hpa_before_image_replacement
    run_stage "Scaling backend/frontend to zero before replacing stable tags..." scale_deployments_to_zero
    run_stage "Removing old same-tag images inside Minikube..." remove_old_minikube_images
    run_stage "Loading fresh images into Minikube..." load_images
    if [[ "$DB_MODE" == "ha" ]]; then
      run_stage "Applying app manifests only; use apply-ha-database and init-db stages for HA database work..." apply_app_manifests_only
    else
      run_stage "Applying app/database manifests..." apply_manifests
    fi
    run_stage "Forcing app rollout restart after image load..." force_app_rollout_restart
    run_stage "Restoring replica counts and waiting for rollout..." restore_replica_counts
    wait_for_rollout
    ;;
  verify-app)
    run_stage "Verifying app rollout..." wait_for_rollout
    run_stage "Verifying running backend image contents..." verify_running_backend_image
    print_summary
    ;;
  *)
    fail "Unknown command '${COMMAND}'. Valid commands: ${VALID_COMMANDS[*]}"
    ;;
esac
