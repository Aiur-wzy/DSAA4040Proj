import os
from datetime import timezone

from fastapi import APIRouter
from kubernetes import client, config
from kubernetes.config.config_exception import ConfigException

router = APIRouter()

NAMESPACE = os.getenv("BOOKSTORE_NAMESPACE", os.getenv("POD_NAMESPACE", "bookstore"))
BACKEND_DEPLOYMENT = os.getenv("BOOKSTORE_BACKEND_DEPLOYMENT", "public-backend")
BACKEND_HPA = os.getenv("BOOKSTORE_BACKEND_HPA", "public-backend-hpa")
BACKEND_POD_SELECTOR = os.getenv("BOOKSTORE_BACKEND_POD_SELECTOR", "app=public-backend")
METRICS_WARNING = (
    "Metrics API is unavailable. Run ./scripts/k8s-fix-metrics-server.sh "
    "and verify kubectl top pods."
)
KUBERNETES_UNAVAILABLE_WARNING = (
    "Kubernetes status is unavailable. The backend may not be running inside "
    "Kubernetes or kubeconfig is missing."
)

_kubernetes_config_loaded = False


def _empty_status(warnings=None, error=None):
    status = {
        "namespace": NAMESPACE,
        "deployment": {
            "name": BACKEND_DEPLOYMENT,
            "desiredReplicas": None,
            "readyReplicas": None,
            "availableReplicas": None,
            "updatedReplicas": None,
        },
        "hpa": {
            "name": BACKEND_HPA,
            "minReplicas": None,
            "maxReplicas": None,
            "currentReplicas": None,
            "desiredReplicas": None,
            "currentCPUUtilization": None,
            "targetCPUUtilization": None,
        },
        "pods": [],
        "metricsAvailable": False,
        "warnings": warnings or [],
    }
    if error:
        status["error"] = error
    return status


def _load_kubernetes_config():
    global _kubernetes_config_loaded

    if _kubernetes_config_loaded:
        return True, None

    try:
        config.load_incluster_config()
        _kubernetes_config_loaded = True
        return True, None
    except ConfigException as incluster_error:
        try:
            config.load_kube_config()
            _kubernetes_config_loaded = True
            return True, None
        except ConfigException as kubeconfig_error:
            error = (
                f"in-cluster config failed: {incluster_error}; "
                f"kubeconfig failed: {kubeconfig_error}"
            )
            return False, error


def _isoformat(value):
    if not value:
        return None
    if getattr(value, "tzinfo", None) is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.isoformat()


def _pod_ready(pod):
    for condition in pod.status.conditions or []:
        if condition.type == "Ready":
            return condition.status == "True"
    return False


def _pod_restart_count(pod):
    return sum(status.restart_count or 0 for status in pod.status.container_statuses or [])


def _error_reason(exc):
    return getattr(exc, "reason", str(exc))


def _deployment_summary(apps_api, warnings):
    try:
        deployment = apps_api.read_namespaced_deployment(BACKEND_DEPLOYMENT, NAMESPACE)
        return {
            "name": deployment.metadata.name,
            "desiredReplicas": deployment.spec.replicas or 0,
            "readyReplicas": deployment.status.ready_replicas or 0,
            "availableReplicas": deployment.status.available_replicas or 0,
            "updatedReplicas": deployment.status.updated_replicas or 0,
        }
    except Exception as exc:
        warnings.append(f"Unable to read Deployment {BACKEND_DEPLOYMENT}: {_error_reason(exc)}")
        return _empty_status()["deployment"]


def _hpa_cpu_current(hpa):
    for metric in hpa.status.current_metrics or []:
        if metric.type == "Resource" and metric.resource and metric.resource.name == "cpu":
            return metric.resource.current.average_utilization
    return None


def _hpa_cpu_target(hpa):
    for metric in hpa.spec.metrics or []:
        if metric.type == "Resource" and metric.resource and metric.resource.name == "cpu":
            return metric.resource.target.average_utilization
    return None


def _hpa_summary(autoscaling_api, warnings):
    try:
        hpa = autoscaling_api.read_namespaced_horizontal_pod_autoscaler(BACKEND_HPA, NAMESPACE)
        return {
            "name": hpa.metadata.name,
            "minReplicas": hpa.spec.min_replicas,
            "maxReplicas": hpa.spec.max_replicas,
            "currentReplicas": hpa.status.current_replicas or 0,
            "desiredReplicas": hpa.status.desired_replicas or 0,
            "currentCPUUtilization": _hpa_cpu_current(hpa),
            "targetCPUUtilization": _hpa_cpu_target(hpa),
        }
    except Exception as exc:
        warnings.append(f"Unable to read HPA {BACKEND_HPA}: {_error_reason(exc)}")
        return _empty_status()["hpa"]


def _pod_metrics(custom_api, warnings):
    try:
        response = custom_api.list_namespaced_custom_object(
            group="metrics.k8s.io",
            version="v1beta1",
            namespace=NAMESPACE,
            plural="pods",
            label_selector=BACKEND_POD_SELECTOR,
        )
    except Exception:
        warnings.append(METRICS_WARNING)
        return {}, False

    metrics_by_pod = {}
    for item in response.get("items", []):
        cpu = None
        memory = None
        containers = item.get("containers", [])
        if containers:
            usage = containers[0].get("usage", {})
            cpu = usage.get("cpu")
            memory = usage.get("memory")
        metrics_by_pod[item.get("metadata", {}).get("name")] = {
            "cpu": cpu,
            "memory": memory,
        }
    return metrics_by_pod, True


def _pod_summaries(core_api, metrics_by_pod, warnings):
    try:
        pod_list = core_api.list_namespaced_pod(NAMESPACE, label_selector=BACKEND_POD_SELECTOR)
    except Exception as exc:
        warnings.append(f"Unable to list monitored backend Pods: {_error_reason(exc)}")
        return []

    pods = []
    for pod in pod_list.items:
        usage = metrics_by_pod.get(pod.metadata.name, {})
        pods.append(
            {
                "name": pod.metadata.name,
                "phase": pod.status.phase,
                "ready": _pod_ready(pod),
                "restartCount": _pod_restart_count(pod),
                "startTime": _isoformat(pod.status.start_time),
                "cpu": usage.get("cpu"),
                "memory": usage.get("memory"),
            }
        )
    return sorted(pods, key=lambda item: item["name"])


@router.get("/status")
def get_cluster_status():
    loaded, error = _load_kubernetes_config()
    if not loaded:
        return _empty_status(warnings=[KUBERNETES_UNAVAILABLE_WARNING], error=error)

    warnings = []
    apps_api = client.AppsV1Api()
    autoscaling_api = client.AutoscalingV2Api()
    core_api = client.CoreV1Api()
    custom_api = client.CustomObjectsApi()

    deployment = _deployment_summary(apps_api, warnings)
    hpa = _hpa_summary(autoscaling_api, warnings)
    metrics_by_pod, metrics_available = _pod_metrics(custom_api, warnings)
    pods = _pod_summaries(core_api, metrics_by_pod, warnings)

    return {
        "namespace": NAMESPACE,
        "deployment": deployment,
        "hpa": hpa,
        "pods": pods,
        "metricsAvailable": metrics_available,
        "warnings": warnings,
    }
