# DSAA 4040 Cloud-Native Online Bookstore

## 1) Project Overview

**DSAA 4040 Cloud-Native Online Bookstore** is an educational cloud-native online bookstore project for the DSAA 4040 course. It demonstrates Docker Compose, Kubernetes, split backend services, PostgreSQL, optional CloudNativePG-based HA, monitoring, HPA, and failover validation.

- **Stable default mode:** `DB_MODE=single`
- **Optional distributed-system experiment:** `DB_MODE=ha`

> Project status: course project / educational demo, not production-ready.

---

## 2) Architecture

```text
Browser
  -> Frontend React/Nginx
  -> path-based routing
      /api -> public-backend
      /api/admin -> admin-backend
      /api/admin/cluster -> monitoring-backend
  -> PostgreSQL
      single mode: postgres Deployment
      HA mode: CloudNativePG bookstore-postgres cluster
```

### Components

- **frontend**: React/Vite app served by Nginx.
- **public-backend**: public APIs (`health`, `books`, `cart`, `orders`).
- **admin-backend**: admin catalog and stock management APIs.
- **monitoring-backend**: read-only cluster/HA status APIs.
- **database**:
  - single mode: one PostgreSQL Deployment.
  - HA mode: CloudNativePG cluster with primary/replica and `rw`/`ro` services.
- **ConfigMap / Secret**: runtime config and demo secrets.
- **PVC / local storage**: persistent data (including CNPG local storage prep in HA mode).
- **HPA + metrics-server**: optional autoscaling demo.

### Naming clarity

- `bookstore-distributed` = Minikube **profile**
- `bookstore` = Kubernetes **namespace**
- `bookstore-postgres` = CloudNativePG **Cluster** name

---

## 3) Repository Layout

- `backend/`
- `frontend/`
- `database/`
- `k8s/`
- `k8s/postgres-ha/`
- `scripts/`
- `docs/`
- `report/`

---

## 4) Prerequisites

- Docker
- Docker Compose plugin
- Minikube
- Optional: `hey` (for HPA/load demo)
- Optional: standalone `kubectl` (scripts support `minikube kubectl --` fallback)

Tested environments can use the **Minikube Docker driver**.

---

## 5) Quick Start: Docker Compose

```bash
docker compose up --build
./scripts/test-api.sh
./scripts/test-admin-api.sh
docker compose down
```

---

## 6) Quick Start: Kubernetes Single-DB Mode (Default)

```bash
chmod +x scripts/*.sh
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
./scripts/k8s-status.sh
```

Notes:
- Default mode is `DB_MODE=single` (stable path).
- Uses `bookstore-backend:latest` and `bookstore-frontend:latest`.
- `k8s-rebuild-and-deploy.sh` rebuilds images, loads them into Minikube, applies manifests, restarts pods, and verifies stale-image conditions.

---

## 7) Distributed System Mode: Multi-node PostgreSQL HA

Use this mode for distributed-system/failover evidence collection. For final demo and final verification, prefer the one-command workflow first, and use the staged workflow as a debugging path when you need to isolate a failing step.

- Profile: `MINIKUBE_PROFILE=bookstore-distributed`
- Typical target: `NODES=3` (resource permitting)
- Database: CloudNativePG with three PostgreSQL instances
- Requires pre-prepared local storage with UID/GID `26:26` to avoid hostPath permission failures
- Still a **single-host Minikube simulation**, not true physical fault isolation

### 7.1 One-command distributed HA workflow

Recommended for demo/final verification:

```bash
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 \
EXPOSE_DEMO=1 \
PUBLIC_PORT=3000 \
NODE_PORT=30080 \
MINIKUBE_PROFILE=bookstore-distributed \
NODES=3 \
CPUS=2 \
MEMORY=4096 \
DB_MODE=ha \
./scripts/k8s-distributed-ha-rebuild-all.sh
```

This workflow performs:
1. start/reuse Minikube multi-node profile;
2. run image preflight;
3. install/check CloudNativePG operator;
4. prepare CNPG local storage;
5. create HA PostgreSQL;
6. init DB;
7. deploy app;
8. verify app;
9. collect distributed HA evidence;
10. optionally expose frontend demo.

### 7.2 Staged distributed HA workflow

Use staged execution when debugging specific failures.

```bash
MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-prepare-cnpg-local-storage.sh
```

```bash
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh apply-ha-database
```

```bash
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh init-db
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh deploy-app
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh verify-app
```

### 7.3 Safe fresh rebuild without deleting Minikube

For a clean HA re-run, prefer deleting only the `bookstore` namespace and preserving the Minikube profile.

- Delete only namespace `bookstore` and re-run the deployment flow.
- Do **not** run `minikube delete` for normal fresh rebuilds.
- Optionally clean demo PV/local data only when no real data needs to be preserved.

### 7.4 Optional public demo exposure

The one-command workflow can expose the frontend automatically when `EXPOSE_DEMO=1` is set.

Manual exposure/check commands are still available:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-expose-demo.sh
MINIKUBE_PROFILE=bookstore-distributed PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-check-demo-exposure.sh
```

Then open: `http://<server-public-ip>:3000`

Cloud firewall/security group must allow inbound **TCP 3000**.
Use `http://`, not `https://`, for this demo endpoint.

---

## 8) Image Preflight and Minikube Image Loading

A Docker image existing on the host does **not** mean the same image is already available inside Minikube.

The deployment workflow now runs image preflight automatically. You can also run it manually:

```bash
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-preload-images.sh
```

Optional auto-pull for missing images:

```bash
PULL_MISSING_IMAGES=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-preload-images.sh
```

Required images:
- `bookstore-backend:latest`
- `bookstore-frontend:latest`
- `postgres:16`
- `ghcr.io/cloudnative-pg/cloudnative-pg:1.24.4`
- `ghcr.io/cloudnative-pg/postgresql:16.4`

---

## 9) Verification

After `k8s-distributed-ha-rebuild-all.sh` completes successfully, the main application should already be running.

Failover, HPA, order consistency, and API/Admin tests are evaluation/demo scripts that you run separately after the core deployment is confirmed.

### Basic checks

```bash
MINIKUBE_IP=$(minikube -p bookstore-distributed ip)
curl -s http://$MINIKUBE_IP:30080/api/health
curl -s http://$MINIKUBE_IP:30080/api/health/db
curl -s http://$MINIKUBE_IP:30080/api/books | head
```

### Full tests

```bash
./scripts/test-api.sh
./scripts/test-admin-api.sh
./scripts/test-order-consistency.sh
```

### Distributed HA evidence

```bash
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
```

Failover test behavior summary:
- detect current primary
- write pre-failover marker
- delete only primary pod
- wait for new primary
- verify `rw` service recovery
- verify pre-failover data persists
- verify post-failover write succeeds
- report old/new primary node and failover duration

---

## 10) Browser Access

- Local Minikube NodePort:
  - `http://$(minikube -p bookstore-distributed ip):30080`
- Public cloud demo:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-expose-demo.sh
MINIKUBE_PROFILE=bookstore-distributed PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-check-demo-exposure.sh
```

Then open: `http://<server-public-ip>:3000`

Cloud firewall/security group must allow inbound **TCP 3000**.
Use `http://`, not `https://`, for this demo endpoint.

Public exposure scope/safety:
- Exposes only `frontend-service` NodePort through the selected public port.
- Does **not** expose backend services or PostgreSQL publicly.
- If internal NodePort works but public access fails, check cloud firewall/security-group rules and iptables packet counters.

(See `docs/public_exposure.md` and `docs/demo_manual.md` for detailed manual networking guidance.)

---

## 11) Monitoring and HPA Demo (Optional)

```bash
./scripts/k8s-fix-metrics-server.sh
./scripts/k8s-hpa-demo.sh
```

- Monitoring page reads `/api/admin/cluster/status`.
- Monitoring Dashboard auto-refreshes every **2 seconds**.
- `metrics-server` is required for CPU/memory metrics and HPA behavior.
- HPA scale-up still may take tens of seconds because `metrics-server` and the HPA controller use their own sampling/reconciliation loops.
- Run HPA demo after core app functionality is confirmed.

Recommended demo sequence:

```bash
MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-fix-metrics-server.sh
MINIKUBE_PROFILE=bookstore-distributed DURATION=240s CONCURRENCY=30 ./scripts/k8s-hpa-demo.sh
```

Then open the Monitoring page in the frontend UI.

---

## Appendix A: Script List

| Script | Purpose | Typical Usage |
|---|---|---|
| `scripts/k8s-distributed-ha-rebuild-all.sh` | One-command distributed HA rebuild/deploy/verification flow | `DB_MODE=ha` final demo or verification |
| `scripts/k8s-preload-images.sh` | Image preflight and Minikube image loading | Before HA deploy, or standalone image checks |
| `scripts/k8s-prepare-cnpg-local-storage.sh` | Prepare local storage permissions for CNPG (`26:26`) | HA staged/debug path |
| `scripts/k8s-rebuild-and-deploy.sh` | Rebuild images, load to Minikube, apply manifests, verify deployment | Single mode default path / HA staged path |
| `scripts/k8s-install-cnpg.sh` | Install/check CloudNativePG operator | HA setup and troubleshooting |
| `scripts/k8s-expose-demo.sh` | Expose NodePort to public host port for demo | Public demo exposure |
| `scripts/k8s-check-demo-exposure.sh` | Validate exposure path and forwarding rules | Public demo verification |
| `scripts/k8s-distributed-ha-evidence.sh` | Collect distributed/HA evidence snapshot | Demo/report evidence collection |
| `scripts/k8s-postgres-ha-status.sh` | Print CNPG/HA database status | HA runtime checks |
| `scripts/k8s-postgres-ha-failover-test.sh` | Controlled primary-pod failover validation | Failover evaluation demo |
| `scripts/k8s-fix-metrics-server.sh` | Repair/check metrics-server | HPA prerequisites |
| `scripts/k8s-hpa-demo.sh` | Run HPA load demonstration | Optional autoscaling demo |
| `scripts/k8s-test-local.sh` | Local Kubernetes smoke tests | Post-deploy sanity checks |
| `scripts/k8s-status.sh` | Quick Kubernetes deployment status checks | Daily ops/status snapshots |
| `scripts/test-api.sh` | Public API tests | Compose/K8s functional checks |
| `scripts/test-admin-api.sh` | Admin API tests | Compose/K8s functional checks |
| `scripts/test-order-consistency.sh` | Order consistency checks | HA/data consistency evaluation |
| `scripts/compose-up.sh` | Docker Compose start helper | Local compose bring-up |
| `scripts/compose-status.sh` | Docker Compose status helper | Local compose inspection |
| `scripts/compose-down.sh` | Docker Compose teardown helper | Local compose shutdown |

---

## 13) Troubleshooting (Concise)

- **Stale `latest` image**: rebuild, `minikube image load`, rollout restart. Prefer `./scripts/k8s-rebuild-and-deploy.sh`.
- **CNPG `initdb` permission denied**:
  - Preferred: pre-prepare storage before cluster creation:
    - `MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-prepare-cnpg-local-storage.sh`
  - Fallback: `AUTO_FIX_CNPG_PVC_PERMISSIONS=1 ...`
  - **Warning**: `FORCE_DELETE_DANGLING_CNPG_PVC` is **last-resort fresh-init only**, not for real data preservation.
- **ImagePullBackOff**: identify missing image; `docker pull`/`minikube -p bookstore-distributed image load`.
- **metrics-server unavailable**: run `./scripts/k8s-fix-metrics-server.sh`.
- **public access unavailable**: verify NodePort first, then expose script, then cloud firewall.

---

## 14) Evidence Collection Checklist

- Kubernetes resource snapshot
- Pods distribution across nodes
- HA status output
- Failover test output
- API test output
- Frontend screenshot
- Monitoring/HPA screenshot (if HPA demo included)

---

## Appendix B: Demo Command Quick Reference

Distributed HA full build:

```bash
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 EXPOSE_DEMO=1 PUBLIC_PORT=3000 NODE_PORT=30080 MINIKUBE_PROFILE=bookstore-distributed NODES=3 CPUS=2 MEMORY=4096 DB_MODE=ha ./scripts/k8s-distributed-ha-rebuild-all.sh
```

Status commands:

```bash
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-status.sh
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh
```

Failover command:

```bash
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
```

HPA command:

```bash
MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-fix-metrics-server.sh
MINIKUBE_PROFILE=bookstore-distributed DURATION=240s CONCURRENCY=30 ./scripts/k8s-hpa-demo.sh
```

Public exposure command:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-expose-demo.sh
MINIKUBE_PROFILE=bookstore-distributed PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-check-demo-exposure.sh
```

---

## Appendix C: Additional Documentation

- [Demo manual](docs/demo_manual.md)
- [Architecture and defense notes](docs/architecture_and_defense_notes.md)
- [PostgreSQL HA experiment notes](docs/postgres_ha_experiment.md)
- [Distributed HA runbook](docs/distributed_ha_runbook.md)
- [Distributed network flow](docs/distributed_network_flow.md)
- [Troubleshooting details](docs/troubleshooting.md)
- [Public exposure guide](docs/public_exposure.md)
- [HPA demo guide](docs/hpa_demo.md)

---

## Security Note

- Demo admin APIs are unauthenticated by design for coursework demo simplicity.
- Demo Secrets/configuration are **not production-grade**.

## Production Migration Note

For production-like deployment, use managed Kubernetes or multi-VM Kubernetes, CSI-backed storage, real image registry, backups, TLS, external secret management, and monitoring/alerting.

## Runtime Results Warning

Do not claim command outputs, screenshots, or performance results unless they were actually executed/collected in your environment.

## Acknowledgements

DSAA 4040 Cloud Computing & Big Data Systems course project.

## License

Course project / not specified.
