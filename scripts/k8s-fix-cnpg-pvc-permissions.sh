#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh" || true

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}"
NAMESPACE="${NAMESPACE:-bookstore}"
CLUSTER_NAME="${CLUSTER_NAME:-bookstore-postgres}"
PVC_NAME="${PVC_NAME:-${CLUSTER_NAME}-1}"
CNPG_POSTGRES_IMAGE="${CNPG_POSTGRES_IMAGE:-ghcr.io/cloudnative-pg/postgresql:16.4}"
KEEP_REPAIR_JOB="${KEEP_REPAIR_JOB:-0}"
FORCE_CNPG_PVC_REPAIR="${FORCE_CNPG_PVC_REPAIR:-0}"
FORCE_DELETE_DANGLING_CNPG_PVC="${FORCE_DELETE_DANGLING_CNPG_PVC:-0}"
CLUSTER_MANIFEST="${CLUSTER_MANIFEST:-k8s/postgres-ha/cluster.yaml}"
if [[ "${DISTRIBUTED_HA_MODE:-0}" == "1" ]]; then
  CLUSTER_MANIFEST="k8s/postgres-ha/cluster-distributed.yaml"
fi

info(){ printf '\n[stage] %s\n' "$*"; }
warn(){ printf 'WARN: %s\n' "$*" >&2; }
fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if declare -f resolve_kubectl >/dev/null 2>&1; then
  resolve_kubectl
else
  KUBECTL=(minikube -p "$MINIKUBE_PROFILE" kubectl --)
  KUBECTL_MODE='minikube kubectl --'
fi

if [[ "${KUBECTL_MODE:-}" != "kubectl" ]]; then
  KUBECTL=(minikube -p "$MINIKUBE_PROFILE" kubectl --)
  KUBECTL_MODE='minikube kubectl --'
fi

job_name="cnpg-pvc-permission-repair-${CLUSTER_NAME}-$(date +%s)"

info "Using Kubernetes command: ${KUBECTL_MODE}"
info "Namespace=${NAMESPACE} Cluster=${CLUSTER_NAME} PVC=${PVC_NAME} Image=${CNPG_POSTGRES_IMAGE}"

if ! "${KUBECTL[@]}" get namespace "$NAMESPACE" >/dev/null 2>&1; then
  info "Run apply-ha-database first."
  exit 0
fi

info "Checking CNPG cluster and PVC state"
"${KUBECTL[@]}" get cluster "$CLUSTER_NAME" -n "$NAMESPACE" >/dev/null || fail "Cluster/$CLUSTER_NAME not found in namespace $NAMESPACE"
ready="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)"
phase="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
status_blob="$(${KUBECTL[@]} get cluster "$CLUSTER_NAME" -n "$NAMESPACE" -o jsonpath='{.status}' 2>/dev/null || true)"

[[ "$ready" == "True" ]] && fail "Cluster is already Ready=True. Refusing repair; set FORCE_CNPG_PVC_REPAIR=1 if you are absolutely sure."
"${KUBECTL[@]}" get pvc "$PVC_NAME" -n "$NAMESPACE" >/dev/null || fail "PVC/$PVC_NAME not found"
pvc_phase="$(${KUBECTL[@]} get pvc "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}')"
[[ "$pvc_phase" == "Bound" ]] || fail "PVC/$PVC_NAME is not Bound (current: $pvc_phase)"

pod_phase="$(${KUBECTL[@]} get pod "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
pod_ready="$(${KUBECTL[@]} get pod "$PVC_NAME" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null || true)"
if [[ "$pod_phase" == "Running" || "$pod_ready" == "true" ]]; then
  fail "Pod $PVC_NAME appears Running/Ready. Refusing to modify PVC without FORCE_CNPG_PVC_REPAIR=1."
fi

if [[ "$phase" != "Setting up primary" && "$status_blob" != *Dangling* && "$status_blob" != *initializing* ]]; then
  warn "Cluster phase/status is not the typical stuck initializer pattern (phase='$phase'). Proceeding cautiously."
fi

info "Checking for existing PG_VERSION in PVC"
probe_job="${job_name}-probe"
cat <<YAML | "${KUBECTL[@]}" apply -n "$NAMESPACE" -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${probe_job}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: probe
        image: ${CNPG_POSTGRES_IMAGE}
        imagePullPolicy: IfNotPresent
        command: ["/bin/bash","-c"]
        args: ["set -euo pipefail; if [ -f /var/lib/postgresql/data/pgdata/PG_VERSION ]; then echo HAS_PG_VERSION; else echo NO_PG_VERSION; fi"]
        securityContext:
          runAsUser: 0
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${PVC_NAME}
YAML
"${KUBECTL[@]}" wait --for=condition=complete "job/${probe_job}" -n "$NAMESPACE" --timeout=120s >/dev/null
probe_logs="$(${KUBECTL[@]} logs -n "$NAMESPACE" "job/${probe_job}" 2>/dev/null || true)"
"${KUBECTL[@]}" delete job -n "$NAMESPACE" "$probe_job" --ignore-not-found >/dev/null || true
if [[ "$probe_logs" == *HAS_PG_VERSION* && "$FORCE_CNPG_PVC_REPAIR" != "1" ]]; then
  fail "PVC has pgdata/PG_VERSION (possible initialized DB). Refusing repair unless FORCE_CNPG_PVC_REPAIR=1."
fi

if [[ "$FORCE_DELETE_DANGLING_CNPG_PVC" == "1" ]]; then
  warn "Last-resort recovery for FAILED BRAND-NEW initialization only. This path recreates Cluster/${CLUSTER_NAME}; do not use on real data."
  [[ "$ready" != "True" ]] || fail "Refusing recovery: cluster Ready=True"
  [[ "$probe_logs" != *HAS_PG_VERSION* || "$FORCE_CNPG_PVC_REPAIR" == "1" ]] || fail "Refusing recovery: DB appears initialized"

  info "Deleting Cluster/${CLUSTER_NAME} to recover from unrecoverable dangling-PVC state"
  "${KUBECTL[@]}" delete cluster -n "$NAMESPACE" "$CLUSTER_NAME" --ignore-not-found

  info "Waiting for related CNPG resources to disappear"
  "${KUBECTL[@]}" wait --for=delete pod -l "cnpg.io/cluster=${CLUSTER_NAME}" -n "$NAMESPACE" --timeout=240s || true
  "${KUBECTL[@]}" wait --for=delete job -l "cnpg.io/cluster=${CLUSTER_NAME}" -n "$NAMESPACE" --timeout=240s || true
  "${KUBECTL[@]}" wait --for=delete pvc -l "cnpg.io/cluster=${CLUSTER_NAME}" -n "$NAMESPACE" --timeout=240s || true

  info "Reapplying ${CLUSTER_MANIFEST}"
  "${KUBECTL[@]}" apply -f "$CLUSTER_MANIFEST"
  info "Waiting for Cluster/${CLUSTER_NAME} Ready=True"
  "${KUBECTL[@]}" wait --for=condition=Ready "cluster/${CLUSTER_NAME}" -n "$NAMESPACE" --timeout=300s
  info "Cluster recreation recovery completed."
  exit 0
fi

info "Running temporary permission repair job"
cat <<YAML | "${KUBECTL[@]}" apply -n "$NAMESPACE" -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${job_name}
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: repair
        image: ${CNPG_POSTGRES_IMAGE}
        imagePullPolicy: IfNotPresent
        securityContext:
          runAsUser: 0
        command: ["/bin/bash","-c"]
        args:
          - |
            set -eux
            id
            ls -la /var/lib/postgresql || true
            ls -la /var/lib/postgresql/data || true
            chown -R 26:26 /var/lib/postgresql/data
            chmod -R u+rwX,g+rwX /var/lib/postgresql/data
            ls -la /var/lib/postgresql/data
        volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ${PVC_NAME}
YAML

"${KUBECTL[@]}" wait --for=condition=complete "job/${job_name}" -n "$NAMESPACE" --timeout=300s
info "Repair job logs"
"${KUBECTL[@]}" logs -n "$NAMESPACE" "job/${job_name}" --tail=200 || true

ts="$(date -u +%Y%m%dT%H%M%SZ)"
info "Annotating cluster to trigger reconcile"
"${KUBECTL[@]}" annotate cluster -n "$NAMESPACE" "$CLUSTER_NAME" "cnpg-reconcile-at=${ts}" --overwrite

info "Waiting briefly for new initdb Job or primary Pod"
if ! "${KUBECTL[@]}" get jobs -n "$NAMESPACE" | grep -E "${CLUSTER_NAME}.*(initdb|join)" >/dev/null 2>&1; then
  "${KUBECTL[@]}" get pod -n "$NAMESPACE" "$PVC_NAME" >/dev/null 2>&1 || warn "No new initdb job/pod yet. If still stuck, restart the CNPG operator deployment and re-check."
fi

if [[ "$KEEP_REPAIR_JOB" == "1" ]]; then
  info "KEEP_REPAIR_JOB=1 set. Leaving repair Job ${job_name}."
else
  "${KUBECTL[@]}" delete job -n "$NAMESPACE" "$job_name" --ignore-not-found >/dev/null || true
  info "Deleted repair Job ${job_name}."
fi

info "Completed CNPG PVC permission recovery workflow (non-destructive by default)."
