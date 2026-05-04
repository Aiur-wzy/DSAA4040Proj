#!/usr/bin/env bash
set -euo pipefail

echo "=== Kubernetes resources (bookstore namespace) ==="
kubectl get all -n bookstore

echo
kubectl get pvc -n bookstore

echo
kubectl get ingress -n bookstore

echo
kubectl get hpa -n bookstore
