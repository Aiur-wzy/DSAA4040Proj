#!/usr/bin/env bash
set -euo pipefail

echo "WARNING: This deletes Kubernetes resources in namespace 'bookstore'."
kubectl delete -f k8s/ --ignore-not-found=true
