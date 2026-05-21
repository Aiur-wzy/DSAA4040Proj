#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}"
NODES="${NODES:-3}"
CPUS="${CPUS:-4}"
MEMORY="${MEMORY:-6144}"
DRIVER="${DRIVER:-docker}"
DB_MODE="${DB_MODE:-ha}"
CNPG_POSTGRES_IMAGE="${CNPG_POSTGRES_IMAGE:-ghcr.io/cloudnative-pg/postgresql:16.4}"
EXPOSE_DEMO="${EXPOSE_DEMO:-0}"
NAMESPACE="${NAMESPACE:-bookstore}"
SERVICE="${SERVICE:-frontend-service}"
NODE_PORT="${NODE_PORT:-30080}"
PUBLIC_PORT="${PUBLIC_PORT:-3000}"

if [[ "$DB_MODE" != "ha" ]]; then
  echo "Error: Distributed HA workflow requires DB_MODE=ha (got DB_MODE=${DB_MODE})." >&2
  exit 1
fi

info() { printf '\n%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command '$1' not found in PATH" >&2
    exit 1
  }
}

mk() {
  command minikube -p "$MINIKUBE_PROFILE" "$@"
}

run_stage() {
  local stage="$1"
  info "=== ${stage} ==="
  MINIKUBE_PROFILE="$MINIKUBE_PROFILE" DB_MODE=ha AUTO_FIX_CNPG_PVC_PERMISSIONS="${AUTO_FIX_CNPG_PVC_PERMISSIONS:-0}" FORCE_DELETE_DANGLING_CNPG_PVC="${FORCE_DELETE_DANGLING_CNPG_PVC:-0}" ./scripts/k8s-rebuild-and-deploy.sh "$stage"
}

preload_cnpg_postgres_image() {
  info "=== Preload/check CloudNativePG PostgreSQL image (${CNPG_POSTGRES_IMAGE}) ==="

  if command -v docker >/dev/null 2>&1 && docker image inspect "$CNPG_POSTGRES_IMAGE" >/dev/null 2>&1; then
    echo "Host Docker already has ${CNPG_POSTGRES_IMAGE}; loading it into Minikube profile ${MINIKUBE_PROFILE}."
    if mk image load "$CNPG_POSTGRES_IMAGE"; then
      echo "Loaded ${CNPG_POSTGRES_IMAGE} into Minikube."
      return 0
    fi
    warn "minikube image load failed even though the host image exists. Kubernetes may still pull the image if network access is available."
  else
    warn "Host Docker does not currently have ${CNPG_POSTGRES_IMAGE}; trying to pull inside Minikube."
  fi

  if mk ssh -- docker pull "$CNPG_POSTGRES_IMAGE"; then
    echo "Pulled ${CNPG_POSTGRES_IMAGE} inside Minikube."
    return 0
  fi

  warn "Could not preload ${CNPG_POSTGRES_IMAGE}. Diagnostics follow."
  mk status || true
  mk kubectl -- get nodes -o wide || true
  warn "Continuing: CloudNativePG may still pull ${CNPG_POSTGRES_IMAGE} during Pod scheduling if the cluster has registry access."
}

require_cmd minikube

info "=== Start/reuse Minikube multi-node profile ==="
echo "MINIKUBE_PROFILE=${MINIKUBE_PROFILE}"
echo "NODES=${NODES}; CPUS=${CPUS}; MEMORY=${MEMORY}; DRIVER=${DRIVER}; DB_MODE=${DB_MODE}"
mk start --driver="$DRIVER" --nodes="$NODES" --cpus="$CPUS" --memory="$MEMORY" --force

info "=== Minikube status ==="
mk status

info "=== Kubernetes nodes ==="
mk kubectl -- get nodes -o wide

info "=== Install/check CloudNativePG operator ==="
MINIKUBE_PROFILE="$MINIKUBE_PROFILE" DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh install-cnpg

preload_cnpg_postgres_image

info "=== Prepare CNPG local storage ==="
MINIKUBE_PROFILE="$MINIKUBE_PROFILE" NAMESPACE="${NAMESPACE:-bookstore}" STORAGE_CLASS="${STORAGE_CLASS:-bookstore-cnpg-local}" CLUSTER_NAME="${CLUSTER_NAME:-bookstore-postgres}" ./scripts/k8s-prepare-cnpg-local-storage.sh

if ! run_stage apply-ha-database; then
  exit 1
fi
run_stage init-db
run_stage deploy-app
run_stage verify-app

info "=== Distributed HA evidence ==="
MINIKUBE_PROFILE="$MINIKUBE_PROFILE" DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh

if [[ "${EXPOSE_DEMO}" == "1" ]]; then
  info "=== expose-demo ==="
  echo "Validating preconditions before public demo exposure..."
  if ! mk kubectl -- get service "${SERVICE}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: service '${SERVICE}' not found in namespace '${NAMESPACE}'. Aborting public demo exposure." >&2
    exit 1
  fi

  service_type="$(mk kubectl -- get service "${SERVICE}" -n "${NAMESPACE}" -o jsonpath='{.spec.type}')"
  if [[ "${service_type}" != "NodePort" ]]; then
    echo "Error: service '${SERVICE}' type is '${service_type}', expected 'NodePort'. Aborting public demo exposure." >&2
    exit 1
  fi

  actual_node_port="$(mk kubectl -- get service "${SERVICE}" -n "${NAMESPACE}" -o jsonpath='{.spec.ports[0].nodePort}')"
  if [[ "${actual_node_port}" != "${NODE_PORT}" ]]; then
    echo "Error: service '${SERVICE}' nodePort is '${actual_node_port}', expected '${NODE_PORT}'. Aborting public demo exposure." >&2
    exit 1
  fi

  MINIKUBE_IP_FOR_DEMO="$(mk ip)"
  INTERNAL_URL="http://${MINIKUBE_IP_FOR_DEMO}:${NODE_PORT}/"
  if ! curl -fsSI "${INTERNAL_URL}" >/dev/null; then
    echo "Error: internal NodePort check failed (${INTERNAL_URL}). Aborting public demo exposure." >&2
    exit 1
  fi
  echo "Internal NodePort check passed: ${INTERNAL_URL}"

  MINIKUBE_PROFILE="$MINIKUBE_PROFILE" PUBLIC_PORT="${PUBLIC_PORT}" NODE_PORT="${NODE_PORT}" ./scripts/k8s-expose-demo.sh

  cat <<EOF_EXPOSE
Post-exposure verification:
  Internal NodePort URL: http://${MINIKUBE_IP_FOR_DEMO}:${NODE_PORT}
  Public demo URL: http://<server-public-ip>:${PUBLIC_PORT}

Running iptables checks:
EOF_EXPOSE

  sudo iptables -t nat -L PREROUTING -n -v --line-numbers | grep "${PUBLIC_PORT}" || true
  sudo iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "${NODE_PORT}" || true
  sudo iptables -L FORWARD -n -v --line-numbers | grep "${NODE_PORT}" || true
  sudo iptables -L DOCKER-USER -n -v --line-numbers | grep "${NODE_PORT}" || true

  echo "Cloud firewall/security group must allow inbound TCP ${PUBLIC_PORT}."
  echo "Use http://, not https://, for this demo endpoint."
else
  echo "Skipping public demo exposure. Set EXPOSE_DEMO=1 to expose frontend-service."
fi

MINIKUBE_IP="$(mk ip)"
cat <<EOF_NEXT

Next verification commands:
  MINIKUBE_PROFILE=${MINIKUBE_PROFILE} DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
  MINIKUBE_PROFILE=${MINIKUBE_PROFILE} BASE_URL=http://${MINIKUBE_IP}:30080 ./scripts/test-order-consistency.sh

Notes:
  - This workflow preserves PVCs.
  - Database initialization is skipped when existing HA schema is detected unless FORCE_POSTGRES_INIT=1 is explicitly set.
EOF_NEXT
