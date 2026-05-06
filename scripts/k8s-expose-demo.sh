#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
SERVICE="frontend-service"
EXPECTED_NODE_PORT="30080"
PUBLIC_PORT="${PUBLIC_PORT:-3000}"

fail() { echo "Error: $1" >&2; exit 1; }
run_iptables() {
  if (( EUID == 0 )); then
    iptables "$@"
  else
    sudo iptables "$@"
  fi
}
ensure_rule() {
  if run_iptables -C "$@" >/dev/null 2>&1; then
    echo "Rule already exists: iptables $*"
  else
    run_iptables -A "$@"
    echo "Added rule: iptables $*"
  fi
}
ensure_nat_rule() {
  if run_iptables -t nat -C "$@" >/dev/null 2>&1; then
    echo "Rule already exists: iptables -t nat $*"
  else
    run_iptables -t nat -A "$@"
    echo "Added rule: iptables -t nat $*"
  fi
}

resolve_kubectl
require_minikube_running
require_cmd iptables
if (( EUID != 0 )); then
  require_cmd sudo
fi

echo "Using Kubernetes command: ${KUBECTL_MODE}"

service_type="$("${KUBECTL[@]}" get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.type}')"
[[ "$service_type" == "NodePort" ]] || fail "$SERVICE is type '$service_type', expected NodePort"

node_port="$("${KUBECTL[@]}" get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')"
[[ "$node_port" == "$EXPECTED_NODE_PORT" ]] || fail "$SERVICE nodePort is '$node_port', expected $EXPECTED_NODE_PORT"

MINIKUBE_IP="$(minikube ip)"

echo "Forwarding public TCP ${PUBLIC_PORT} to ${MINIKUBE_IP}:${EXPECTED_NODE_PORT}."
echo "This script only exposes frontend-service. It does not expose backend-service or postgres-service publicly."

if (( EUID == 0 )); then
  sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
else
  sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
fi

ensure_nat_rule PREROUTING -p tcp --dport "$PUBLIC_PORT" -j DNAT --to-destination "${MINIKUBE_IP}:${EXPECTED_NODE_PORT}"
ensure_nat_rule POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$EXPECTED_NODE_PORT" -j MASQUERADE
ensure_rule FORWARD -p tcp -d "$MINIKUBE_IP" --dport "$EXPECTED_NODE_PORT" -j ACCEPT

cat <<MSG

Demo frontend is forwarded to:
  http://<server-public-ip>:${PUBLIC_PORT}

Minikube NodePort remains available at:
  http://${MINIKUBE_IP}:${EXPECTED_NODE_PORT}

Warning: your cloud security group/firewall must allow inbound TCP ${PUBLIC_PORT}.
MSG
