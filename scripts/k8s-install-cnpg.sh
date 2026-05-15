#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

CNPG_MINOR="${CNPG_MINOR:-1.24}"
CNPG_VERSION="${CNPG_VERSION:-1.24.4}"
CNPG_MANIFEST_URL="${CNPG_MANIFEST_URL:-https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-${CNPG_MINOR}/releases/cnpg-${CNPG_VERSION}.yaml}"

fail() { echo "FAIL: $*" >&2; exit 1; }
info() { echo "INFO: $*"; }

require_minikube_running
resolve_kubectl

info "Installing CloudNativePG operator ${CNPG_VERSION}"
info "Using Kubernetes command: ${KUBECTL_MODE}"
info "MINIKUBE_PROFILE=${MINIKUBE_PROFILE:-default}"
info "Manifest: ${CNPG_MANIFEST_URL}"

if ! "${KUBECTL[@]}" apply --server-side -f "${CNPG_MANIFEST_URL}"; then
  cat >&2 <<DIAG
FAIL: CloudNativePG operator installation failed.
If this environment cannot pull GitHub manifests or official images, download the
manifest from the URL above, mirror only the official images you trust, and rerun
with CNPG_MANIFEST_URL=/path/to/local-cnpg.yaml.
DIAG
  exit 1
fi

info "Waiting for cnpg-controller-manager rollout..."
"${KUBECTL[@]}" rollout status deployment/cnpg-controller-manager -n cnpg-system --timeout=180s || fail "cnpg-controller-manager did not become ready. Check: ${KUBECTL_MODE} get pods -n cnpg-system"

info "CloudNativePG operator is ready."
