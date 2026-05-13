#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
SERVICE="frontend-service"
NODE_PORT="${NODE_PORT:-30080}"
PUBLIC_PORT="${PUBLIC_PORT:-3000}"
CLEANUP=false

fail() { echo "Error: $1" >&2; exit 1; }
usage() {
  cat <<USAGE
Usage: PUBLIC_PORT=3000 NODE_PORT=30080 $0 [--cleanup]

Adds host-level iptables forwarding from public TCP PUBLIC_PORT to
\$(minikube ip):NODE_PORT for the Kubernetes frontend NodePort demo.

Options:
  --cleanup   Remove matching forwarding rules instead of adding them.
  -h, --help  Show this help message.
USAGE
}
run_sudo() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}
run_iptables() {
  run_sudo iptables "$@"
}
ensure_docker_user_chain() {
  if ! run_iptables -L DOCKER-USER -n >/dev/null 2>&1; then
    run_iptables -N DOCKER-USER
    echo "Created filter chain: DOCKER-USER"
  fi
}
delete_filter_rule_once() {
  local chain="$1"
  shift
  run_iptables -D "$chain" "$@" >/dev/null 2>&1
}
delete_nat_rule_once() {
  local chain="$1"
  shift
  run_iptables -t nat -D "$chain" "$@" >/dev/null 2>&1
}
delete_all_filter_rules() {
  local chain="$1"
  shift
  local removed=0
  while delete_filter_rule_once "$chain" "$@"; do
    removed=$((removed + 1))
  done
  echo "Removed ${removed} matching rule(s): iptables -D ${chain} $*"
}
delete_all_nat_rules() {
  local chain="$1"
  shift
  local removed=0
  while delete_nat_rule_once "$chain" "$@"; do
    removed=$((removed + 1))
  done
  echo "Removed ${removed} matching rule(s): iptables -t nat -D ${chain} $*"
}
insert_filter_rule() {
  local chain="$1"
  shift
  delete_all_filter_rules "$chain" "$@"
  run_iptables -I "$chain" 1 "$@"
  echo "Added rule: iptables -I ${chain} 1 $*"
}
insert_nat_rule() {
  local chain="$1"
  shift
  delete_all_nat_rules "$chain" "$@"
  run_iptables -t nat -I "$chain" 1 "$@"
  echo "Added rule: iptables -t nat -I ${chain} 1 $*"
}

for arg in "$@"; do
  case "$arg" in
    --cleanup) CLEANUP=true ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unknown argument: $arg" ;;
  esac
done

resolve_kubectl
require_minikube_running
require_cmd iptables
if (( EUID != 0 )); then
  require_cmd sudo
fi

MINIKUBE_IP="$(minikube ip)"

if [[ "$CLEANUP" == false ]]; then
  echo "Using Kubernetes command: ${KUBECTL_MODE}"

  service_type="$("${KUBECTL[@]}" get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.type}')"
  [[ "$service_type" == "NodePort" ]] || fail "$SERVICE is type '$service_type', expected NodePort"

  actual_node_port="$("${KUBECTL[@]}" get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].nodePort}')"
  [[ "$actual_node_port" == "$NODE_PORT" ]] || fail "$SERVICE nodePort is '$actual_node_port', expected $NODE_PORT"
fi

prerouting_rule=(-p tcp --dport "$PUBLIC_PORT" -j DNAT --to-destination "${MINIKUBE_IP}:${NODE_PORT}")
postrouting_rule=(-p tcp -d "$MINIKUBE_IP" --dport "$NODE_PORT" -j MASQUERADE)
forward_in_rule=(-p tcp -d "$MINIKUBE_IP" --dport "$NODE_PORT" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT)
forward_out_rule=(-p tcp -s "$MINIKUBE_IP" --sport "$NODE_PORT" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT)
docker_user_in_rule=(-p tcp -d "$MINIKUBE_IP" --dport "$NODE_PORT" -j ACCEPT)
docker_user_out_rule=(-p tcp -s "$MINIKUBE_IP" --sport "$NODE_PORT" -j ACCEPT)

if [[ "$CLEANUP" == true ]]; then
  echo "Removing forwarding rules for public TCP ${PUBLIC_PORT} to ${MINIKUBE_IP}:${NODE_PORT}."
  delete_all_nat_rules PREROUTING "${prerouting_rule[@]}"
  delete_all_nat_rules POSTROUTING "${postrouting_rule[@]}"
  delete_all_filter_rules FORWARD "${forward_in_rule[@]}"
  delete_all_filter_rules FORWARD "${forward_out_rule[@]}"
  delete_all_filter_rules DOCKER-USER "${docker_user_in_rule[@]}"
  delete_all_filter_rules DOCKER-USER "${docker_user_out_rule[@]}"
  echo "Cleanup complete."
  exit 0
fi

echo "Forwarding public TCP ${PUBLIC_PORT} to ${MINIKUBE_IP}:${NODE_PORT}."
echo "This script only exposes frontend-service. It does not expose any backend Service or postgres-service publicly."

run_sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null
ensure_docker_user_chain

insert_nat_rule PREROUTING "${prerouting_rule[@]}"
insert_nat_rule POSTROUTING "${postrouting_rule[@]}"
insert_filter_rule FORWARD "${forward_in_rule[@]}"
insert_filter_rule FORWARD "${forward_out_rule[@]}"
insert_filter_rule DOCKER-USER "${docker_user_in_rule[@]}"
insert_filter_rule DOCKER-USER "${docker_user_out_rule[@]}"

cat <<MSG

Verification commands:
  sudo iptables -t nat -L PREROUTING -n -v --line-numbers | grep "${PUBLIC_PORT}"
  sudo iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "${NODE_PORT}"
  sudo iptables -L FORWARD -n -v --line-numbers | grep "${NODE_PORT}"
  sudo iptables -L DOCKER-USER -n -v --line-numbers | grep "${NODE_PORT}"

Optional packet trace while testing from another machine:
  sudo tcpdump -ni any 'tcp port ${PUBLIC_PORT} or tcp port ${NODE_PORT}'

Open: http://<server-public-ip>:${PUBLIC_PORT}
Internal NodePort: http://${MINIKUBE_IP}:${NODE_PORT}

Warning: your cloud security group/firewall must allow inbound TCP ${PUBLIC_PORT}.
Do not use https:// for this demo endpoint.
MSG
