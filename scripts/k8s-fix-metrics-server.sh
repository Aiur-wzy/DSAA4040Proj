#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/lib/k8s.sh" ]]; then
  # shellcheck source=scripts/lib/k8s.sh
  source "${SCRIPT_DIR}/lib/k8s.sh"
else
  resolve_kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
      KUBECTL=(kubectl)
      KUBECTL_MODE="kubectl"
    elif command -v minikube >/dev/null 2>&1; then
      KUBECTL=(minikube kubectl --)
      KUBECTL_MODE="minikube kubectl --"
    else
      echo "Error: neither kubectl nor minikube is available." >&2
      exit 1
    fi
  }
  require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
      echo "Error: required command '$1' not found in PATH" >&2
      exit 1
    }
  }
  require_minikube() { require_cmd minikube; }
  require_minikube_running() {
    require_minikube
    minikube status >/dev/null 2>&1 || {
      echo "Error: Minikube is not running. Start it first with: minikube start --driver=docker --memory=4096 --cpus=2" >&2
      exit 1
    }
  }
fi

NAMESPACE="bookstore"
METRICS_NAMESPACE="kube-system"
METRICS_DEPLOYMENT="metrics-server"
METRICS_LABEL="k8s-app=metrics-server"
PRIMARY_IMAGE="registry.k8s.io/metrics-server/metrics-server:v0.8.1"
FALLBACK_IMAGE="registry.cn-hangzhou.aliyuncs.com/google_containers/metrics-server:v0.8.1"

step() { echo; echo "$1"; }
warn() { echo "Warning: $*" >&2; }

print_troubleshooting() {
  cat >&2 <<'EOF_DIAG'

Troubleshooting commands:
  minikube kubectl -- describe pod -n kube-system -l k8s-app=metrics-server
  minikube kubectl -- logs -n kube-system deploy/metrics-server
  minikube kubectl -- describe apiservice v1beta1.metrics.k8s.io
EOF_DIAG
}

fail() {
  echo "Error: $*" >&2
  print_troubleshooting
  exit 1
}

retry() {
  local attempts="$1"
  local sleep_seconds="$2"
  local description="$3"
  shift 3

  local attempt
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    if "$@"; then
      return 0
    fi
    if (( attempt < attempts )); then
      echo "${description} not ready yet; retrying in ${sleep_seconds}s (${attempt}/${attempts})..."
      sleep "$sleep_seconds"
    fi
  done
  return 1
}

wait_for_metrics_deployment() {
  "${KUBECTL[@]}" get deployment "$METRICS_DEPLOYMENT" -n "$METRICS_NAMESPACE" >/dev/null 2>&1
}

wait_for_metrics_pod() {
  local pods
  pods="$("${KUBECTL[@]}" get pods -n "$METRICS_NAMESPACE" -l "$METRICS_LABEL" --no-headers 2>/dev/null || true)"
  [[ -n "$pods" ]]
}

metrics_pod_status() {
  "${KUBECTL[@]}" get pods -n "$METRICS_NAMESPACE" -l "$METRICS_LABEL" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\tphase="}{.status.phase}{"\treason="}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}{"\tmessage="}{range .status.containerStatuses[*]}{.state.waiting.message}{" "}{end}{"\n"}{end}' 2>/dev/null || true
}

metrics_image() {
  "${KUBECTL[@]}" get deployment "$METRICS_DEPLOYMENT" -n "$METRICS_NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="metrics-server")].image}' 2>/dev/null || true
}

image_pull_is_failing() {
  local status image
  status="$(metrics_pod_status)"
  image="$(metrics_image)"

  echo "Current metrics-server image: ${image:-unknown}"
  if [[ -n "$status" ]]; then
    echo "Current metrics-server Pod status:"
    echo "$status"
  fi

  if grep -Eq 'ImagePullBackOff|ErrImagePull|manifest unknown|not found|pull access denied|failed to pull|Failed to pull image' <<<"$status"; then
    return 0
  fi

  if [[ "$image" == *"@sha256:"* ]]; then
    warn "metrics-server image uses a pinned digest (${image}); replacing it with a tag-only image to avoid manifest unknown errors."
    return 0
  fi

  return 1
}

rollout_metrics_server() {
  local image="$1"
  echo "Setting metrics-server image to ${image}"
  "${KUBECTL[@]}" set image "deployment/${METRICS_DEPLOYMENT}" "metrics-server=${image}" -n "$METRICS_NAMESPACE"
  "${KUBECTL[@]}" rollout restart "deployment/${METRICS_DEPLOYMENT}" -n "$METRICS_NAMESPACE"
  "${KUBECTL[@]}" rollout status "deployment/${METRICS_DEPLOYMENT}" -n "$METRICS_NAMESPACE" --timeout=180s
}

repair_metrics_image_if_needed() {
  if image_pull_is_failing; then
    echo "Detected a metrics-server image pull/digest problem. Repairing with a valid tag-only image."
    if rollout_metrics_server "$PRIMARY_IMAGE"; then
      echo "metrics-server rolled out successfully with ${PRIMARY_IMAGE}"
    else
      warn "Rollout with ${PRIMARY_IMAGE} failed. Trying regional fallback image ${FALLBACK_IMAGE}."
      rollout_metrics_server "$FALLBACK_IMAGE" || fail "metrics-server rollout failed after trying both supported images."
    fi
  else
    echo "No image pull failure detected. Waiting for the existing metrics-server rollout."
    "${KUBECTL[@]}" rollout status "deployment/${METRICS_DEPLOYMENT}" -n "$METRICS_NAMESPACE" --timeout=180s || fail "metrics-server rollout did not complete."
  fi
}

verify_top_nodes() {
  "${KUBECTL[@]}" top nodes
}

verify_top_pods() {
  "${KUBECTL[@]}" top pods -n "$NAMESPACE"
}

hpa_has_known_metrics() {
  local output
  output="$("${KUBECTL[@]}" get hpa -n "$NAMESPACE")" || return 1
  echo "$output"
  ! grep -q '<unknown>' <<<"$output"
}

resolve_kubectl
require_minikube_running

echo "Using Kubernetes command: ${KUBECTL_MODE}"

step "[1/5] Enabling metrics-server"
minikube addons enable metrics-server

step "[2/5] Checking metrics-server Pod status"
retry 24 5 "metrics-server Deployment" wait_for_metrics_deployment || fail "metrics-server Deployment did not appear in kube-system."
retry 24 5 "metrics-server Pod" wait_for_metrics_pod || fail "metrics-server Pod did not appear in kube-system."
metrics_pod_status || true

step "[3/5] Repairing image if needed"
repair_metrics_image_if_needed

step "[4/5] Verifying Metrics API"
echo "metrics-server may need time to collect its first samples."
retry 18 10 "kubectl top nodes" verify_top_nodes || fail "Metrics API did not become available for nodes."
retry 18 10 "kubectl top pods -n ${NAMESPACE}" verify_top_pods || fail "Metrics API did not become available for namespace '${NAMESPACE}'."

step "[5/5] Checking HPA CPU metrics"
retry 18 10 "HPA CPU metrics" hpa_has_known_metrics || fail "public-backend HPA still shows <unknown> CPU metrics after retries. Confirm public-backend HPA target Pods are Running and have CPU requests."

echo
echo "Metrics-server is running and the public-backend HPA can read CPU metrics."
