#!/usr/bin/env bash
set -euo pipefail

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}"
NAMESPACE="${NAMESPACE:-bookstore}"
STORAGE_CLASS="${STORAGE_CLASS:-bookstore-cnpg-local}"
CLUSTER_NAME="${CLUSTER_NAME:-bookstore-postgres}"
REQUIRED_READY_NODES="${REQUIRED_READY_NODES:-3}"
PV_SIZE="${PV_SIZE:-2Gi}"
BASE_DIR="${BASE_DIR:-/data/bookstore-cnpg}"

info(){ printf '\n[stage] %s\n' "$*"; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v minikube >/dev/null 2>&1 || fail "minikube is required"
KUBECTL=(minikube -p "$MINIKUBE_PROFILE" kubectl --)

nodes=( $("${KUBECTL[@]}" get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}') )
(( ${#nodes[@]} >= REQUIRED_READY_NODES )) || fail "Need at least ${REQUIRED_READY_NODES} nodes; found ${#nodes[@]}"

ready_count="$("${KUBECTL[@]}" get nodes --no-headers | awk '$2=="Ready"{c++} END{print c+0}')"
(( ready_count >= REQUIRED_READY_NODES )) || fail "Need ${REQUIRED_READY_NODES} Ready nodes; found ${ready_count}"

selected=("${nodes[@]:0:$REQUIRED_READY_NODES}")
info "Preparing CNPG local storage for profile=${MINIKUBE_PROFILE}, namespace=${NAMESPACE}, cluster=${CLUSTER_NAME}"

for i in 1 2 3; do
  node="${selected[$((i-1))]}"
  path="${BASE_DIR}/postgres-${i}"
  info "Preparing ${path} on node ${node}"
  minikube -p "$MINIKUBE_PROFILE" ssh --node "$node" -- "sudo mkdir -p '${path}' && sudo chown -R 26:26 '${path}' && sudo chmod -R 770 '${path}'"
done

info "Applying local StorageClass ${STORAGE_CLASS}"
cat <<YAML | "${KUBECTL[@]}" apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${STORAGE_CLASS}
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
YAML

info "Applying static local PVs"
{
cat <<YAML
apiVersion: v1
kind: List
items:
YAML
for i in 1 2 3; do
node="${selected[$((i-1))]}"
cat <<YAML
- apiVersion: v1
  kind: PersistentVolume
  metadata:
    name: bookstore-cnpg-pv-${i}
    labels:
      app.kubernetes.io/name: ${CLUSTER_NAME}
  spec:
    capacity:
      storage: ${PV_SIZE}
    volumeMode: Filesystem
    accessModes:
      - ReadWriteOnce
    persistentVolumeReclaimPolicy: Retain
    storageClassName: ${STORAGE_CLASS}
    local:
      path: ${BASE_DIR}/postgres-${i}
    nodeAffinity:
      required:
        nodeSelectorTerms:
          - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
                  - ${node}
YAML
done
} | "${KUBECTL[@]}" apply -f -

info "Verifying PV availability"
for i in 1 2 3; do
  "${KUBECTL[@]}" wait --for=jsonpath='{.status.phase}'=Available "pv/bookstore-cnpg-pv-${i}" --timeout=60s
  "${KUBECTL[@]}" get "pv/bookstore-cnpg-pv-${i}" -o wide
done

info "CNPG local storage preparation complete."
