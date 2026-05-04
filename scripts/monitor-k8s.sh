#!/usr/bin/env bash
set -euo pipefail

echo "=== Pods ==="
kubectl get pods -n bookstore

echo

echo "=== HPA ==="
kubectl get hpa -n bookstore

echo

echo "=== Node metrics ==="
kubectl top nodes

echo

echo "=== Pod metrics ==="
kubectl top pods -n bookstore

echo

echo "Hint: if kubectl top fails, enable metrics-server:"
echo "minikube addons enable metrics-server"
