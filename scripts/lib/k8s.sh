#!/usr/bin/env bash
# Shared Kubernetes helpers for scripts that must work when standalone kubectl
# is unavailable and Minikube provides kubectl via `minikube kubectl --`.

minikube_cmd() {
  if [[ -n "${MINIKUBE_PROFILE:-}" ]]; then
    minikube -p "$MINIKUBE_PROFILE" "$@"
  else
    minikube "$@"
  fi
}

minikube_profile_args() {
  if [[ -n "${MINIKUBE_PROFILE:-}" ]]; then
    printf '%s\0%s\0' -p "$MINIKUBE_PROFILE"
  fi
}

kubectl_cmd() {
  "${KUBECTL[@]}" "$@"
}

minikube_ip() {
  minikube_cmd ip
}

minikube_image_load() {
  minikube_cmd image load "$@"
}

minikube_ssh() {
  minikube_cmd ssh -- "$@"
}

minikube_addons_enable() {
  minikube_cmd addons enable "$@"
}

resolve_kubectl() {
  if [[ -n "${MINIKUBE_PROFILE:-}" ]]; then
    require_minikube
    KUBECTL=(minikube -p "$MINIKUBE_PROFILE" kubectl --)
    KUBECTL_MODE="minikube -p ${MINIKUBE_PROFILE} kubectl --"
  elif command -v kubectl >/dev/null 2>&1; then
    KUBECTL=(kubectl)
    KUBECTL_MODE="kubectl"
  else
    if ! command -v minikube >/dev/null 2>&1; then
      echo "Error: neither kubectl nor minikube is available." >&2
      exit 1
    fi
    KUBECTL=(minikube kubectl --)
    KUBECTL_MODE="minikube kubectl --"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Error: required command '$1' not found in PATH" >&2
    exit 1
  }
}

require_minikube() {
  require_cmd minikube
}

require_minikube_running() {
  require_minikube
  minikube_cmd status >/dev/null 2>&1 || {
    echo "Error: Minikube is not running. Start it first with: minikube start --driver=docker --memory=4096 --cpus=2" >&2
    exit 1
  }
}
