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
  MINIKUBE_PROFILE="$MINIKUBE_PROFILE" DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh "$stage"
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

run_stage apply-ha-database
run_stage init-db
run_stage deploy-app
run_stage verify-app

info "=== Distributed HA evidence ==="
MINIKUBE_PROFILE="$MINIKUBE_PROFILE" DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh

MINIKUBE_IP="$(mk ip)"
cat <<EOF_NEXT

Next verification commands:
  MINIKUBE_PROFILE=${MINIKUBE_PROFILE} DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
  MINIKUBE_PROFILE=${MINIKUBE_PROFILE} BASE_URL=http://${MINIKUBE_IP}:30080 ./scripts/test-order-consistency.sh

Notes:
  - This workflow preserves PVCs.
  - Database initialization is skipped when existing HA schema is detected unless FORCE_POSTGRES_INIT=1 is explicitly set.
EOF_NEXT
