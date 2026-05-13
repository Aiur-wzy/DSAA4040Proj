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

INGRESS_NAMESPACE="ingress-nginx"
BOOKSTORE_NAMESPACE="bookstore"
BOOKSTORE_INGRESS="bookstore-ingress"
CONTROLLER_DEPLOYMENT="ingress-nginx-controller"
ADMISSION_SECRET="ingress-nginx-admission"
ADMISSION_CREATE_JOB="ingress-nginx-admission-create"
ADMISSION_PATCH_JOB="ingress-nginx-admission-patch"
INGRESS_CONTROLLER_IMAGE="${INGRESS_CONTROLLER_IMAGE:-registry.cn-hangzhou.aliyuncs.com/google_containers/nginx-ingress-controller:v1.14.3}"
INGRESS_WEBHOOK_CERTGEN_IMAGE="${INGRESS_WEBHOOK_CERTGEN_IMAGE:-registry.cn-hangzhou.aliyuncs.com/google_containers/kube-webhook-certgen:v1.6.7}"
ADDON_ENABLE_TIMEOUT="${ADDON_ENABLE_TIMEOUT:-180s}"

step() { echo; echo "$1"; }
warn() { echo "Warning: $*" >&2; }

print_troubleshooting() {
  cat >&2 <<EOF_DIAG

Troubleshooting commands:
  minikube kubectl -- get pods -n ingress-nginx -o wide
  minikube kubectl -- describe pod -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
  minikube kubectl -- get jobs -n ingress-nginx
  minikube kubectl -- describe job -n ingress-nginx ingress-nginx-admission-create
  minikube kubectl -- describe job -n ingress-nginx ingress-nginx-admission-patch
  minikube kubectl -- get secret -n ingress-nginx ingress-nginx-admission
  minikube kubectl -- logs -n ingress-nginx deployment/ingress-nginx-controller --tail=100

Manual recovery commands if admission Jobs are stuck on bad tag+digest images:
  minikube kubectl -- delete job -n ingress-nginx ingress-nginx-admission-create ingress-nginx-admission-patch --ignore-not-found
  minikube kubectl -- delete pod -n ingress-nginx -l app.kubernetes.io/component=admission-webhook --ignore-not-found
  INGRESS_CONTROLLER_IMAGE="${INGRESS_CONTROLLER_IMAGE}" INGRESS_WEBHOOK_CERTGEN_IMAGE="${INGRESS_WEBHOOK_CERTGEN_IMAGE}" ./scripts/k8s-fix-ingress.sh
EOF_DIAG
}

fail() {
  echo "Error: $*" >&2
  print_troubleshooting
  exit 1
}

kubectl_get() {
  "${KUBECTL[@]}" get "$@" >/dev/null 2>&1
}

wait_for_namespace() {
  local elapsed=0
  while (( elapsed < 90 )); do
    if kubectl_get namespace "$INGRESS_NAMESPACE"; then
      return 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  return 1
}

image_of_deployment_container() {
  local deployment="$1"
  local container="$2"
  "${KUBECTL[@]}" get deployment "$deployment" -n "$INGRESS_NAMESPACE" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name==\"${container}\")].image}" 2>/dev/null || true
}

image_of_job_container() {
  local job="$1"
  local container="$2"
  "${KUBECTL[@]}" get job "$job" -n "$INGRESS_NAMESPACE" \
    -o jsonpath="{.spec.template.spec.containers[?(@.name==\"${container}\")].image}" 2>/dev/null || true
}

pod_pull_status() {
  "${KUBECTL[@]}" get pods -n "$INGRESS_NAMESPACE" \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\tphase="}{.status.phase}{"\treason="}{range .status.containerStatuses[*]}{.state.waiting.reason}{" "}{end}{"\tmessage="}{range .status.containerStatuses[*]}{.state.waiting.message}{" "}{end}{"\n"}{end}' 2>/dev/null || true
}

job_failed_or_bad_image() {
  local job="$1"
  local container="$2"
  local image status failed

  kubectl_get job "$job" -n "$INGRESS_NAMESPACE" || return 1
  image="$(image_of_job_container "$job" "$container")"
  failed="$("${KUBECTL[@]}" get job "$job" -n "$INGRESS_NAMESPACE" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
  status="$(pod_pull_status)"

  [[ "$image" == *"@sha256:"* ]] && return 0
  [[ "$failed" =~ ^[1-9][0-9]*$ ]] && return 0
  grep -Eqi 'ImagePullBackOff|ErrImagePull|manifest unknown|secret "ingress-nginx-admission" not found|not found|pull access denied' <<<"$status"
}

create_admission_rbac_and_jobs() {
  cat <<EOF_MANIFEST | "${KUBECTL[@]}" apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ingress-nginx-admission
  namespace: ${INGRESS_NAMESPACE}
  labels:
    app.kubernetes.io/component: admission-webhook
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ingress-nginx-admission
  namespace: ${INGRESS_NAMESPACE}
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ingress-nginx-admission
  namespace: ${INGRESS_NAMESPACE}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ingress-nginx-admission
subjects:
  - kind: ServiceAccount
    name: ingress-nginx-admission
    namespace: ${INGRESS_NAMESPACE}
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ingress-nginx-admission
rules:
  - apiGroups: ["admissionregistration.k8s.io"]
    resources: ["validatingwebhookconfigurations"]
    verbs: ["get", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ingress-nginx-admission
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ingress-nginx-admission
subjects:
  - kind: ServiceAccount
    name: ingress-nginx-admission
    namespace: ${INGRESS_NAMESPACE}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ${ADMISSION_CREATE_JOB}
  namespace: ${INGRESS_NAMESPACE}
  labels:
    app.kubernetes.io/component: admission-webhook
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        app.kubernetes.io/component: admission-webhook
        app.kubernetes.io/instance: ingress-nginx
        app.kubernetes.io/name: ingress-nginx
    spec:
      restartPolicy: OnFailure
      serviceAccountName: ingress-nginx-admission
      containers:
        - name: create
          image: ${INGRESS_WEBHOOK_CERTGEN_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - create
            - --host=ingress-nginx-controller-admission,ingress-nginx-controller-admission.${INGRESS_NAMESPACE}.svc
            - --namespace=${INGRESS_NAMESPACE}
            - --secret-name=${ADMISSION_SECRET}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: ${ADMISSION_PATCH_JOB}
  namespace: ${INGRESS_NAMESPACE}
  labels:
    app.kubernetes.io/component: admission-webhook
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
spec:
  backoffLimit: 3
  template:
    metadata:
      labels:
        app.kubernetes.io/component: admission-webhook
        app.kubernetes.io/instance: ingress-nginx
        app.kubernetes.io/name: ingress-nginx
    spec:
      restartPolicy: OnFailure
      serviceAccountName: ingress-nginx-admission
      containers:
        - name: patch
          image: ${INGRESS_WEBHOOK_CERTGEN_IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - patch
            - --webhook-name=ingress-nginx-admission
            - --namespace=${INGRESS_NAMESPACE}
            - --patch-mutating=false
            - --secret-name=${ADMISSION_SECRET}
            - --patch-failure-policy=Fail
EOF_MANIFEST
}

enable_ingress_addon() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$ADDON_ENABLE_TIMEOUT" minikube addons enable ingress
  else
    minikube addons enable ingress
  fi
}

patch_controller_image() {
  if kubectl_get deployment "$CONTROLLER_DEPLOYMENT" -n "$INGRESS_NAMESPACE"; then
    local image
    image="$(image_of_deployment_container "$CONTROLLER_DEPLOYMENT" controller)"
    echo "Controller image: ${image:-unknown}"
    if [[ "$image" != "$INGRESS_CONTROLLER_IMAGE" || "$image" == *"@sha256:"* ]]; then
      echo "Patching controller image to ${INGRESS_CONTROLLER_IMAGE}"
      "${KUBECTL[@]}" set image "deployment/${CONTROLLER_DEPLOYMENT}" -n "$INGRESS_NAMESPACE" \
        "controller=${INGRESS_CONTROLLER_IMAGE}"
    fi
  else
    fail "deployment/${CONTROLLER_DEPLOYMENT} does not exist after enabling the ingress addon."
  fi
}

repair_admission_jobs() {
  local recreate_jobs=false create_image patch_image

  create_image="$(image_of_job_container "$ADMISSION_CREATE_JOB" create)"
  patch_image="$(image_of_job_container "$ADMISSION_PATCH_JOB" patch)"
  echo "Admission create Job image: ${create_image:-missing}"
  echo "Admission patch Job image: ${patch_image:-missing}"

  if ! kubectl_get job "$ADMISSION_CREATE_JOB" -n "$INGRESS_NAMESPACE"; then
    recreate_jobs=true
  elif job_failed_or_bad_image "$ADMISSION_CREATE_JOB" create; then
    recreate_jobs=true
  fi

  if ! kubectl_get job "$ADMISSION_PATCH_JOB" -n "$INGRESS_NAMESPACE"; then
    recreate_jobs=true
  elif job_failed_or_bad_image "$ADMISSION_PATCH_JOB" patch; then
    recreate_jobs=true
  fi

  if [[ -n "$create_image" && "$create_image" != "$INGRESS_WEBHOOK_CERTGEN_IMAGE" ]]; then
    recreate_jobs=true
  fi
  if [[ -n "$patch_image" && "$patch_image" != "$INGRESS_WEBHOOK_CERTGEN_IMAGE" ]]; then
    recreate_jobs=true
  fi
  if [[ "$create_image" == *"@sha256:"* || "$patch_image" == *"@sha256:"* ]]; then
    recreate_jobs=true
  fi

  if [[ "$recreate_jobs" == "true" ]]; then
    echo "Deleting immutable admission Jobs so they can be recreated with tag-only Aliyun images."
    "${KUBECTL[@]}" delete job -n "$INGRESS_NAMESPACE" "$ADMISSION_CREATE_JOB" "$ADMISSION_PATCH_JOB" --ignore-not-found
    "${KUBECTL[@]}" delete pod -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/component=admission-webhook --ignore-not-found || true
    create_admission_rbac_and_jobs
  else
    echo "Admission Jobs do not show failed or digest-pinned image state."
  fi
}

print_ingress_diagnostics() {
  echo
  echo "=== bookstore ingress diagnostics ===" >&2
  "${KUBECTL[@]}" describe ingress "$BOOKSTORE_INGRESS" -n "$BOOKSTORE_NAMESPACE" >&2 || true
  echo
  echo "=== bookstore services ===" >&2
  "${KUBECTL[@]}" get svc -n "$BOOKSTORE_NAMESPACE" >&2 || true
  echo
  echo "=== bookstore EndpointSlices ===" >&2
  "${KUBECTL[@]}" get endpointslices -n "$BOOKSTORE_NAMESPACE" >&2 || true
  echo
  echo "=== ingress controller logs ===" >&2
  "${KUBECTL[@]}" logs -n "$INGRESS_NAMESPACE" "deployment/${CONTROLLER_DEPLOYMENT}" --tail=100 >&2 || true
  echo
  echo "=== ingress-nginx pod descriptions ===" >&2
  "${KUBECTL[@]}" describe pod -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx >&2 || true
}

curl_expect() {
  local path="$1"
  local description="$2"
  local body_file code
  body_file="$(mktemp)"
  code="$(curl -sS -i -H "Host: bookstore.local" --max-time 20 -o "$body_file" -w '%{http_code}' "http://${MINIKUBE_IP}${path}" || true)"
  echo "${path} -> HTTP ${code} (${description})"
  sed -n '1,20p' "$body_file"
  rm -f "$body_file"

  if [[ "$code" != "200" ]]; then
    return 1
  fi
  if [[ "$path" == "/api/admin/cluster/status" && "$code" == "404" ]]; then
    return 1
  fi
  return 0
}

resolve_kubectl
require_minikube_running
require_cmd curl

echo "Using Kubernetes command: ${KUBECTL_MODE}"
echo "Using ingress controller image: ${INGRESS_CONTROLLER_IMAGE}"
echo "Using ingress webhook certgen image: ${INGRESS_WEBHOOK_CERTGEN_IMAGE}"

step "[1/7] Enabling ingress addon"
if ! enable_ingress_addon; then
  warn "minikube addons enable ingress did not complete successfully. Continuing because partial addon resources may have been created and can often be repaired."
fi
wait_for_namespace || fail "namespace/${INGRESS_NAMESPACE} was not created by the ingress addon."

step "[2/7] Inspecting ingress-nginx images and Pods"
"${KUBECTL[@]}" get pods -n "$INGRESS_NAMESPACE" -o wide || true
pod_pull_status || true

step "[3/7] Repairing bad digest/image pull issues"
patch_controller_image
repair_admission_jobs
"${KUBECTL[@]}" delete pod -n "$INGRESS_NAMESPACE" -l app.kubernetes.io/name=ingress-nginx --field-selector=status.phase=Failed --ignore-not-found || true

step "[4/7] Ensuring admission webhook Secret exists"
if ! kubectl_get secret "$ADMISSION_SECRET" -n "$INGRESS_NAMESPACE"; then
  echo "Waiting for ${ADMISSION_CREATE_JOB} to create secret/${ADMISSION_SECRET}..."
  "${KUBECTL[@]}" wait --for=condition=complete "job/${ADMISSION_CREATE_JOB}" -n "$INGRESS_NAMESPACE" --timeout=180s || fail "${ADMISSION_CREATE_JOB} did not complete."
fi
kubectl_get secret "$ADMISSION_SECRET" -n "$INGRESS_NAMESPACE" || fail "secret/${ADMISSION_SECRET} is still missing."
"${KUBECTL[@]}" wait --for=condition=complete "job/${ADMISSION_PATCH_JOB}" -n "$INGRESS_NAMESPACE" --timeout=180s || fail "${ADMISSION_PATCH_JOB} did not complete."
"${KUBECTL[@]}" get secret -n "$INGRESS_NAMESPACE" "$ADMISSION_SECRET"

step "[5/7] Waiting for ingress controller"
"${KUBECTL[@]}" rollout status "deployment/${CONTROLLER_DEPLOYMENT}" -n "$INGRESS_NAMESPACE" --timeout=240s || fail "ingress controller rollout did not complete."
"${KUBECTL[@]}" get pods -n "$INGRESS_NAMESPACE"

step "[6/7] Checking bookstore Ingress resource"
"${KUBECTL[@]}" get ingress -n "$BOOKSTORE_NAMESPACE" || warn "namespace/${BOOKSTORE_NAMESPACE} or ingress resources are not present yet."
if ! kubectl_get ingress "$BOOKSTORE_INGRESS" -n "$BOOKSTORE_NAMESPACE"; then
  warn "ingress/${BOOKSTORE_INGRESS} is not present; skipping bookstore.local route verification. Run ./scripts/k8s-rebuild-and-deploy.sh first if application manifests have not been applied."
  echo "Ingress controller is running, but bookstore.local routes were not checked because bookstore-ingress is missing."
  exit 0
fi

step "[7/7] Verifying bookstore.local routes"
MINIKUBE_IP="$(minikube ip)"
route_failures=0
curl_expect "/" "frontend HTML" || route_failures=$((route_failures + 1))
curl_expect "/api/health" "backend health JSON" || route_failures=$((route_failures + 1))
curl_expect "/api/books" "books JSON" || route_failures=$((route_failures + 1))
curl_expect "/api/admin/cluster/status" "cluster status JSON or metrics warning" || route_failures=$((route_failures + 1))

if (( route_failures > 0 )); then
  print_ingress_diagnostics
  fail "${route_failures} bookstore.local route check(s) failed."
fi

echo
echo "Ingress is running and bookstore.local routes are working."
