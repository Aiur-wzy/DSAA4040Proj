# Distributed HA Runbook (Minikube Simulation)

This runbook contains the detailed staged and one-command workflows for `DB_MODE=ha` on profile `bookstore-distributed`, including storage preparation, operator/database bring-up, app deploy/verify, and evidence collection.

## Canonical staged flow

```bash
MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-prepare-cnpg-local-storage.sh
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh apply-ha-database
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh init-db
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh deploy-app
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh verify-app
```

## One-command flow

```bash
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 MINIKUBE_PROFILE=bookstore-distributed NODES=3 CPUS=2 MEMORY=4096 DB_MODE=ha ./scripts/k8s-distributed-ha-rebuild-all.sh
```

Use staged mode for debugging and failure isolation.
