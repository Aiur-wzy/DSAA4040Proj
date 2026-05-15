#!/usr/bin/env bash
set -euo pipefail

MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-bookstore-multinode}"
NODES="${NODES:-3}"
CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-3072}"
DRIVER="${DRIVER:-docker}"

cat <<NOTE
Starting Minikube profile '${MINIKUBE_PROFILE}' with ${NODES} Kubernetes nodes.
This is a Minikube multi-node simulation on one host, not a production multi-machine cluster.
Existing profiles are started in place; this script never runs 'minikube delete'.
NOTE

minikube start -p "$MINIKUBE_PROFILE" --driver="$DRIVER" --nodes="$NODES" --cpus="$CPUS" --memory="$MEMORY" --force

minikube -p "$MINIKUBE_PROFILE" status
minikube -p "$MINIKUBE_PROFILE" kubectl -- get nodes -o wide
