#!/usr/bin/env bash
set -euo pipefail

echo "Applying Kubernetes manifests from k8s/ ..."
echo "Reminder: create ConfigMap 'postgres-init-sql' before running postgres-init-job.yaml."
echo "If missing, the postgres-init Job may fail until the ConfigMap is created."

kubectl apply -f k8s/
