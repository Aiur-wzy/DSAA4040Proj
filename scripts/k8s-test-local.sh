#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
EXPECTED_NODE_PORT="30080"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
step() { echo; echo "==== $1 ===="; }

http_body() {
  local url="$1"
  curl -fsS --max-time 15 "$url"
}

expect_http_200() {
  local url="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$url")" || fail "$url did not respond"
  [[ "$code" == "200" ]] || fail "$url returned HTTP $code, expected 200"
  pass "$url returned HTTP 200"
}

expect_body_contains() {
  local url="$1"
  local pattern="$2"
  local description="$3"
  local body
  body="$(http_body "$url")" || fail "$url request failed"
  if grep -Eqi "$pattern" <<<"$body"; then
    pass "$description"
  else
    echo "Response body from $url:" >&2
    echo "$body" >&2
    fail "$description"
  fi
}

step "Checking prerequisites"
resolve_kubectl
require_minikube_running
require_cmd curl
echo "Using Kubernetes command: ${KUBECTL_MODE}"
pass "required commands are available"

step "Checking Kubernetes namespace and resources"
"${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null || fail "namespace '$NAMESPACE' not found"
pass "namespace '$NAMESPACE' exists"

pod_report="$("${KUBECTL[@]}" get pods -n "$NAMESPACE" --no-headers 2>/dev/null || true)"
[[ -n "$pod_report" ]] || fail "no pods found in namespace '$NAMESPACE'"
not_ready="$(awk '$3 != "Running" && $3 != "Completed" {print}' <<<"$pod_report")"
if [[ -n "$not_ready" ]]; then
  echo "$not_ready" >&2
  fail "one or more pods are not Running or Completed"
fi
pass "pods are Running or Completed"

"${KUBECTL[@]}" get service -n "$NAMESPACE" frontend-service >/dev/null || fail "service/frontend-service not found in namespace '$NAMESPACE'"
pass "frontend-service exists"

service_type="$("${KUBECTL[@]}" get service frontend-service -n "$NAMESPACE" -o jsonpath='{.spec.type}')"
[[ "$service_type" == "NodePort" ]] || fail "frontend-service is type '$service_type', expected NodePort"
pass "frontend-service is NodePort"

node_port="$("${KUBECTL[@]}" get service frontend-service -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')"
[[ "$node_port" == "$EXPECTED_NODE_PORT" ]] || fail "frontend-service nodePort is '$node_port', expected $EXPECTED_NODE_PORT"
pass "frontend-service nodePort is $EXPECTED_NODE_PORT"

MINIKUBE_IP="$(minikube ip)"
BASE_URL="http://${MINIKUBE_IP}:${EXPECTED_NODE_PORT}"
pass "testing Kubernetes frontend-service at ${BASE_URL}"

step "Running Minikube NodePort smoke checks"
expect_http_200 "${BASE_URL}/"
expect_body_contains "${BASE_URL}/api/health" '"status"[[:space:]]*:[[:space:]]*"ok"' "/api/health reports backend ok"
expect_body_contains "${BASE_URL}/api/health/db" '"database"[[:space:]]*:[[:space:]]*"connected"' "/api/health/db reports database ok"
expect_body_contains "${BASE_URL}/api/books" '"title"|"author"' "/api/books returns book data"

echo
echo "PASS: Kubernetes Minikube service tests completed successfully"
