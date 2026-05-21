#!/usr/bin/env bash
set -euo pipefail

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-distributed}"
NAMESPACE="${NAMESPACE:-bookstore}"

KUBECTL=(minikube -p "$MINIKUBE_PROFILE" kubectl --)

echo "Resetting application namespace only: ${NAMESPACE}"
echo "This does NOT delete Minikube profile, cnpg-system, CNPG operator, or images."
"${KUBECTL[@]}" delete namespace "$NAMESPACE" --ignore-not-found
"${KUBECTL[@]}" wait --for=delete "namespace/${NAMESPACE}" --timeout=180s || true
"${KUBECTL[@]}" apply -f k8s/namespace.yaml
"${KUBECTL[@]}" wait --for=jsonpath='{.status.phase}'=Active "namespace/${NAMESPACE}" --timeout=60s
