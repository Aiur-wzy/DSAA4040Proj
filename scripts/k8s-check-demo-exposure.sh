#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}"
NAMESPACE="${NAMESPACE:-bookstore}"
SERVICE="${SERVICE:-frontend-service}"
PUBLIC_PORT="${PUBLIC_PORT:-3000}"
NODE_PORT="${NODE_PORT:-30080}"

fail() {
  echo "Error: $1" >&2
  exit 1
}

info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command '$1' not found"
}

run_sudo() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

require_cmd minikube
require_cmd curl
require_cmd grep
require_cmd iptables
if (( EUID != 0 )); then
  require_cmd sudo
fi

KUBECTL=(minikube -p "$MINIKUBE_PROFILE" kubectl --)

info "Checking service ${SERVICE} in namespace ${NAMESPACE}"
if ! "${KUBECTL[@]}" get service "$SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
  fail "service '${SERVICE}' not found in namespace '${NAMESPACE}'"
fi

service_type="$("${KUBECTL[@]}" get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.type}')"
[[ "$service_type" == "NodePort" ]] || fail "service '${SERVICE}' type is '${service_type}', expected NodePort"

actual_node_port="$("${KUBECTL[@]}" get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')"
[[ "$actual_node_port" == "$NODE_PORT" ]] || fail "service '${SERVICE}' nodePort is '${actual_node_port}', expected ${NODE_PORT}"

MINIKUBE_IP="$(minikube -p "$MINIKUBE_PROFILE" ip)"
INTERNAL_URL="http://${MINIKUBE_IP}:${NODE_PORT}/"

info "Checking internal NodePort: ${INTERNAL_URL}"
curl -fsSI "$INTERNAL_URL" >/dev/null || fail "internal NodePort check failed: ${INTERNAL_URL}"

info "Checking iptables rules"
run_sudo iptables -t nat -L PREROUTING -n -v --line-numbers | grep "$PUBLIC_PORT" >/dev/null || fail "missing PREROUTING rule for PUBLIC_PORT ${PUBLIC_PORT}"
run_sudo iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "$NODE_PORT" >/dev/null || fail "missing POSTROUTING rule for NODE_PORT ${NODE_PORT}"
run_sudo iptables -L FORWARD -n -v --line-numbers | grep "$NODE_PORT" >/dev/null || fail "missing FORWARD rule for NODE_PORT ${NODE_PORT}"
run_sudo iptables -L DOCKER-USER -n -v --line-numbers | grep "$NODE_PORT" >/dev/null || fail "missing DOCKER-USER rule for NODE_PORT ${NODE_PORT}"

info "Checking localhost public port: http://127.0.0.1:${PUBLIC_PORT}/"
if ! curl -fsSI "http://127.0.0.1:${PUBLIC_PORT}/" >/dev/null; then
  echo "Note: localhost check failed for 127.0.0.1:${PUBLIC_PORT}."
  echo "This may fail if only PREROUTING DNAT is configured; external traffic can still work."
fi

cat <<MSG
Demo exposure checks passed.
Internal NodePort URL: http://${MINIKUBE_IP}:${NODE_PORT}
Public demo URL: http://<server-public-ip>:${PUBLIC_PORT}
MSG
