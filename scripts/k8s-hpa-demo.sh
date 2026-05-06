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
BACKEND_DEPLOYMENT="backend"
BACKEND_HPA="backend-hpa"
BACKEND_SELECTOR="app=backend"
NODE_PORT="30080"
DURATION="${DURATION:-180s}"
CONCURRENCY="${CONCURRENCY:-50}"
WATCH_INTERVAL="${WATCH_INTERVAL:-10}"
OBSERVE_SCALE_DOWN="${OBSERVE_SCALE_DOWN:-true}"
SCALE_DOWN_WAIT="${SCALE_DOWN_WAIT:-300}"
TARGET_URL="${TARGET_URL:-}"
HEY_LOG=""
HEY_PID=""

step() { echo; echo "==== $1 ===="; }
fail() { echo "Error: $*" >&2; exit 1; }

cleanup() {
  if [[ -n "${HEY_PID}" ]] && kill -0 "$HEY_PID" >/dev/null 2>&1; then
    kill "$HEY_PID" >/dev/null 2>&1 || true
    wait "$HEY_PID" >/dev/null 2>&1 || true
  fi
  if [[ -n "${HEY_LOG}" && -f "${HEY_LOG}" ]]; then
    rm -f "$HEY_LOG"
  fi
}
trap cleanup EXIT

need_metrics_fix() {
  cat >&2 <<'EOF_FIX'
Metrics API or HPA CPU metrics are not ready.
Run the repair/check workflow first:
  ./scripts/k8s-fix-metrics-server.sh
EOF_FIX
}

hpa_output_has_unknown() {
  local output
  output="$("${KUBECTL[@]}" get hpa "$BACKEND_HPA" -n "$NAMESPACE")" || return 0
  grep -q '<unknown>' <<<"$output"
}

current_replicas() {
  local replicas
  replicas="$("${KUBECTL[@]}" get deployment "$BACKEND_DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.replicas}' 2>/dev/null || true)"
  if [[ -z "$replicas" ]]; then
    replicas="$("${KUBECTL[@]}" get deployment "$BACKEND_DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || true)"
  fi
  echo "${replicas:-0}"
}

print_evidence_snapshot() {
  "${KUBECTL[@]}" get hpa -n "$NAMESPACE"
  echo
  "${KUBECTL[@]}" get deployment "$BACKEND_DEPLOYMENT" -n "$NAMESPACE"
  echo
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -l "$BACKEND_SELECTOR"
  echo
  "${KUBECTL[@]}" top pods -n "$NAMESPACE"
}

print_scale_down_snapshot() {
  "${KUBECTL[@]}" get hpa -n "$NAMESPACE"
  echo
  "${KUBECTL[@]}" get deployment "$BACKEND_DEPLOYMENT" -n "$NAMESPACE"
  echo
  "${KUBECTL[@]}" get pods -n "$NAMESPACE" -l "$BACKEND_SELECTOR"
}

validate_positive_integer() {
  local name="$1"
  local value="$2"
  [[ "$value" =~ ^[0-9]+$ ]] && (( value > 0 )) || fail "${name} must be a positive integer, got '${value}'."
}

step "Checking prerequisites"
resolve_kubectl
require_minikube_running
if ! command -v hey >/dev/null 2>&1; then
  fail "hey is required for the HPA demo. Install it or provide an equivalent load generator."
fi
validate_positive_integer "CONCURRENCY" "$CONCURRENCY"
validate_positive_integer "WATCH_INTERVAL" "$WATCH_INTERVAL"
validate_positive_integer "SCALE_DOWN_WAIT" "$SCALE_DOWN_WAIT"

if [[ -z "$TARGET_URL" ]]; then
  TARGET_URL="http://$(minikube ip):${NODE_PORT}/api/books"
fi

echo "Using Kubernetes command: ${KUBECTL_MODE}"
echo "Target URL: ${TARGET_URL}"
echo "Duration: ${DURATION}"
echo "Concurrency: ${CONCURRENCY}"
echo "Watch interval: ${WATCH_INTERVAL}s"
echo "Observe scale down: ${OBSERVE_SCALE_DOWN}"

"${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null || fail "namespace/${NAMESPACE} does not exist. Deploy the app first."
"${KUBECTL[@]}" get deployment "$BACKEND_DEPLOYMENT" -n "$NAMESPACE" >/dev/null || fail "deployment/${BACKEND_DEPLOYMENT} does not exist in namespace/${NAMESPACE}."
"${KUBECTL[@]}" get hpa "$BACKEND_HPA" -n "$NAMESPACE" >/dev/null || fail "hpa/${BACKEND_HPA} does not exist in namespace/${NAMESPACE}."
if ! "${KUBECTL[@]}" top pods -n "$NAMESPACE" >/dev/null; then
  need_metrics_fix
  exit 1
fi
if hpa_output_has_unknown; then
  need_metrics_fix
  exit 1
fi

echo
echo "CPU utilization note: HPA CPU percentage is relative to each container's CPU request, not total node CPU."
echo "For example, if backend requests 100m CPU and uses 300m CPU, HPA can report about 300%."
echo "This script verifies and demonstrates the existing HPA; it does not modify HPA configuration."

INITIAL_REPLICAS="$(current_replicas)"
SCALED_UP=false

echo "Initial backend replica count: ${INITIAL_REPLICAS}"

step "Baseline evidence before load"
print_evidence_snapshot

step "Starting sustained load with hey"
HEY_LOG="$(mktemp -t bookstore-hpa-hey.XXXXXX.log)"
echo "Running: hey -z ${DURATION} -c ${CONCURRENCY} ${TARGET_URL}"
hey -z "$DURATION" -c "$CONCURRENCY" "$TARGET_URL" >"$HEY_LOG" 2>&1 &
HEY_PID="$!"

while kill -0 "$HEY_PID" >/dev/null 2>&1; do
  step "Monitoring HPA while load is running ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))"
  print_evidence_snapshot || true
  replicas="$(current_replicas)"
  if [[ "$replicas" =~ ^[0-9]+$ ]] && (( replicas > INITIAL_REPLICAS )); then
    if [[ "$SCALED_UP" != "true" ]]; then
      echo
      echo "SUCCESS: backend replicas increased from ${INITIAL_REPLICAS} to ${replicas}."
      SCALED_UP=true
    fi
  else
    echo "HPA has not increased replicas yet. This can take 1-2 minutes after CPU rises."
  fi
  sleep "$WATCH_INTERVAL"
done

HEY_EXIT=0
wait "$HEY_PID" || HEY_EXIT="$?"
HEY_PID=""

step "Load generator output"
cat "$HEY_LOG"
if [[ "$HEY_EXIT" != "0" ]]; then
  fail "hey exited with status ${HEY_EXIT}. Check the load generator output above."
fi

step "Final scale-up evidence after load"
print_evidence_snapshot
printf '\n'
"${KUBECTL[@]}" describe hpa "$BACKEND_HPA" -n "$NAMESPACE"

FINAL_REPLICAS="$(current_replicas)"
if [[ "$FINAL_REPLICAS" =~ ^[0-9]+$ ]] && (( FINAL_REPLICAS > INITIAL_REPLICAS )); then
  SCALED_UP=true
  echo
  echo "SUCCESS: backend replicas increased from ${INITIAL_REPLICAS} to ${FINAL_REPLICAS}."
elif [[ "$SCALED_UP" != "true" ]]; then
  echo
  echo "Warning: backend replicas did not increase above ${INITIAL_REPLICAS} during this run."
  echo "Check HPA events above, backend CPU usage, and whether the load target reached the backend."
fi

if [[ "$OBSERVE_SCALE_DOWN" == "true" ]]; then
  step "Observing possible scale-down"
  echo "HPA scale-down can take several minutes because Kubernetes applies stabilization behavior after load stops."
  echo "Observing for ${SCALE_DOWN_WAIT}s; use OBSERVE_SCALE_DOWN=false to skip this phase."
  elapsed=0
  while (( elapsed < SCALE_DOWN_WAIT )); do
    print_scale_down_snapshot || true
    sleep "$WATCH_INTERVAL"
    elapsed=$((elapsed + WATCH_INTERVAL))
  done
else
  echo
  echo "Skipping scale-down observation because OBSERVE_SCALE_DOWN=${OBSERVE_SCALE_DOWN}."
fi

step "Evidence checklist for final report"
cat <<'EOF_CHECKLIST'
- HPA before load
- pod CPU before load
- load generator output
- HPA during load
- backend Deployment scaling from 2 to more replicas
- backend Pods being created
- pod CPU during load
- HPA describe output
- scale-down evidence if captured
EOF_CHECKLIST

echo
echo "HPA demo completed. Review the snapshots above for your report evidence."
