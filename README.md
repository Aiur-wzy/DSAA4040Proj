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

## 7) Distributed System Mode: Multi-node PostgreSQL HA (Optional Experiment)

Use this mode for distributed-system/failover evidence collection.

- Profile: `MINIKUBE_PROFILE=bookstore-distributed`
- Typical target: `NODES=3` (resource permitting)
- Database: CloudNativePG with three PostgreSQL instances
- Requires pre-prepared local storage with UID/GID `26:26` to avoid hostPath permission failures
- Still a **single-host Minikube simulation**, not true physical fault isolation

### Recommended staged workflow (easier debugging)

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

### One-command workflow

```bash
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 MINIKUBE_PROFILE=bookstore-distributed NODES=3 CPUS=2 MEMORY=4096 DB_MODE=ha ./scripts/k8s-distributed-ha-rebuild-all.sh
```

---

## 8) Required Image Loading Notes (HA profile recreation)

If the Minikube profile is deleted/recreated, load required images again:

```bash
minikube -p bookstore-distributed image load ghcr.io/cloudnative-pg/cloudnative-pg:1.24.4
minikube -p bookstore-distributed image load ghcr.io/cloudnative-pg/postgresql:16.4
minikube -p bookstore-distributed image load postgres:16
minikube -p bookstore-distributed image load bookstore-backend:latest
minikube -p bookstore-distributed image load bookstore-frontend:latest
```

- `cloudnative-pg` image: CNPG operator
- `postgresql:16.4`: HA database pods
- `postgres:16`: init job / psql client
- `bookstore-*`: application images

---

## 9) Verification

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
```

Then open: `http://<server-public-ip>:3000`

Cloud firewall/security group must allow inbound **TCP 3000**.

(See `docs/public_exposure.md` and `docs/demo_manual.md` for detailed manual networking guidance.)

---

## 11) Monitoring and HPA Demo (Optional)

```bash
./scripts/k8s-fix-metrics-server.sh
./scripts/k8s-hpa-demo.sh
```

- Monitoring page reads `/api/admin/cluster/status`.
- `metrics-server` is required for CPU/memory metrics and HPA behavior.
- Run HPA demo after core app functionality is confirmed.

---

## 12) Script Reference

| Script | Purpose | Typical mode |
|---|---|---|
| `scripts/k8s-rebuild-and-deploy.sh` | Rebuild images, load to Minikube, apply manifests, verify deployment | Single default / HA staged |
| `scripts/k8s-distributed-ha-rebuild-all.sh` | One-command distributed HA rebuild/deploy flow | HA experiment |
| `scripts/k8s-prepare-cnpg-local-storage.sh` | Prepare local storage permissions for CNPG (`26:26`) | HA experiment |
| `scripts/k8s-install-cnpg.sh` | Install CloudNativePG operator | HA experiment |
| `scripts/k8s-postgres-ha-status.sh` | Print CNPG/HA database status | HA experiment |
| `scripts/k8s-postgres-ha-failover-test.sh` | Controlled primary-pod failover validation | HA experiment |
| `scripts/k8s-distributed-ha-evidence.sh` | Collect distributed/HA evidence snapshot | HA experiment |
| `scripts/k8s-test-local.sh` | Local Kubernetes smoke tests | Single default / HA |
| `scripts/test-api.sh` | Public API tests | Compose / K8s |
| `scripts/test-admin-api.sh` | Admin API tests | Compose / K8s |
| `scripts/test-order-consistency.sh` | Order consistency checks | K8s / HA validation |
| `scripts/k8s-fix-metrics-server.sh` | Repair/check metrics-server | K8s ops |
| `scripts/k8s-expose-demo.sh` | Expose NodePort to public host port for demo | Public demo |
| `scripts/k8s-reset-local.sh` (or reset helpers) | Local reset/cleanup helper | Local recovery |

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

## 15) Documentation Links

- [Demo manual](docs/demo_manual.md)
- [Architecture and defense notes](docs/architecture_and_defense_notes.md)
- [PostgreSQL HA experiment notes](docs/postgres_ha_experiment.md)
- [Distributed HA runbook](docs/distributed_ha_runbook.md)
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
