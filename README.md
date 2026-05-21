# DSAA 4040 Cloud-Native Online Bookstore

## 1. Project Title and Overview

This repository contains a **DSAA 4040 cloud-native online bookstore project**.

It follows a three-tier web architecture:

```text
Browser
  -> Frontend (React + Nginx)
  -> Backend (FastAPI)
  -> PostgreSQL Database
```

The project demonstrates:
- three-tier web application design
- containerized deployment
- Docker Compose local integration
- Kubernetes deployment
- ConfigMap and Secret usage
- Ingress routing
- health checks
- HPA autoscaling
- basic monitoring and performance testing

---

## 2. Repository Structure

```text
database/
backend/
frontend/
docker-compose.yml
k8s/
scripts/
report/
```

- `database/`: PostgreSQL SQL files (`schema.sql`, `seed.sql`, `test.sql`, `place_order.sql`) for schema setup, seed data, and SQL validation/transaction scripts.
- `backend/`: FastAPI backend service source and backend Dockerfile.
- `frontend/`: React/Vite frontend served by Nginx, including frontend Dockerfile and Nginx config.
- `docker-compose.yml`: local full-stack orchestration for `db`, `backend`, and `frontend`; Compose builds `bookstore-backend:latest` and `bookstore-frontend:latest`, matching the Kubernetes Deployment images.
- `k8s/`: Kubernetes manifests (namespace, ConfigMap, Secret, Deployments, PVC, Services, Ingress, HPA, and PostgreSQL init Job).
- `scripts/`: helper scripts for smoke testing, Compose status/logs, Kubernetes apply/status/cleanup, monitoring, and performance testing.
- `report/`: final report scaffold (`report/final_report.md`) for screenshots, command output, and analysis.
- `docs/demo_manual.md`: live demo runbook for final presentation preparation.
- `docs/architecture_and_defense_notes.md`: detailed architecture, design rationale, and defense Q&A notes.

## Final Demo and Defense Preparation

- [Live demo manual](docs/demo_manual.md)
- [Architecture and defense notes](docs/architecture_and_defense_notes.md)

---

## 3. Prerequisites

### For Docker Compose workflow
- Docker
- Docker Compose plugin

### For Kubernetes workflow
- Docker
- Minikube
- optional: `hey` for general performance testing; required for `./scripts/k8s-hpa-demo.sh`

Use `minikube kubectl --` for Kubernetes commands so the guide works on Minikube-only servers where standalone `kubectl` is not installed. Do not rely on interactive shell aliases inside scripts; Bash scripts do not reliably inherit aliases such as `alias kubectl='minikube kubectl --'`.

Verify tools:

```bash
docker --version
docker compose version
minikube version
hey -h
```

> `hey` is required for the repeatable HPA demo because small ad hoc `curl` loops are not enough to demonstrate autoscaling reliably. Other performance scripts may provide fallback behavior if `hey` is not installed.

---

## 4. Updating an Existing Minikube Deployment

### Full Kubernetes Update Workflow

For major code or Kubernetes changes, run the full update workflow:

```bash
./scripts/k8s-full-update.sh
```

This top-level workflow rebuilds and deploys the split-backend bookstore system, repairs/checks `metrics-server`, repairs/checks `ingress-nginx`, verifies NodePort and Ingress routes, runs API smoke tests, prints cluster status, and ends with the next demo commands. It keeps the existing public browser exposure behavior unchanged; the public demo still uses:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh
```

The focused scripts remain available independently:

- `./scripts/k8s-rebuild-and-deploy.sh` rebuilds images and applies only the bookstore app manifests.
- `./scripts/k8s-fix-metrics-server.sh` repairs/checks HPA metrics support.
- `./scripts/k8s-fix-ingress.sh` repairs/checks Minikube Ingress support.

Ingress tests use the Minikube IP plus the host header, for example:

```bash
curl -H "Host: bookstore.local" http://$(minikube ip)/api/books
```

If the ingress addon fails with `ImagePullBackOff`, `ErrImagePull`, or `manifest unknown` for `kube-webhook-certgen` or `nginx-ingress-controller`, run:

```bash
./scripts/k8s-fix-ingress.sh
```

That failure is usually caused by bad tag+digest images from the Minikube addon mirror. The repair script patches ingress-nginx to Aliyun tag-only images and verifies the ingress controller and bookstore routes.

This is the primary workflow for repeated frontend, backend, or Kubernetes configuration changes. Do **not** only run `kubectl apply` after changing frontend or backend code: Minikube can continue running Pods that use stale local images when the Deployment image tag remains `bookstore-frontend:latest` or `bookstore-backend:latest`.

The focused rebuild/deploy command is:

```bash
./scripts/k8s-rebuild-and-deploy.sh
```

The default database mode remains the stable single PostgreSQL deployment (`DB_MODE=single`). An optional CloudNativePG HA experiment is available with `DB_MODE=ha` after installing the operator:

```bash
./scripts/k8s-install-cnpg.sh
DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh
DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh
```

See [PostgreSQL HA experiment](docs/postgres_ha_experiment.md) for the primary/replica design, failover test, idempotent checkout behavior, and limitations.

The script performs the full local-image update workflow:

```text
build backend image
  -> build frontend image
  -> load both images into Minikube
  -> apply Kubernetes manifests and PostgreSQL init ConfigMap/Job logic
  -> restart backend/frontend Deployments
  -> wait for rollouts
  -> print Pods, Services, and verification commands
```

It also uses the shared Kubernetes helper so environments without standalone `kubectl` can fall back to `minikube kubectl --`.

After the update completes, verify the deployment with:

```bash
./scripts/k8s-test-local.sh
./scripts/k8s-status.sh
```

If the browser still shows an old frontend or backend version, check that:

- the relevant Docker image was rebuilt on the host Docker daemon
- the rebuilt image was loaded into Minikube with `minikube image load`
- the frontend and split backend Deployments were restarted after the image load
- Pods were recreated after the restart
- image tags in `docker-compose.yml`, the split backend deployment manifests, and `k8s/frontend-deployment.yaml` still match the stable local tags used by the project

### 4.1 Optional PostgreSQL init rerun

The rebuild/deploy script preserves the `postgres-init-sql` ConfigMap logic and does **not** rerun a completed `postgres-init` Job by default. If SQL changes require the init Job to run again, use:

```bash
FORCE_POSTGRES_INIT=1 ./scripts/k8s-rebuild-and-deploy.sh
```

> Warning: depending on the SQL in `database/schema.sql` and `database/seed.sql`, rerunning the init Job may reset demo data.

### 4.2 Advanced/manual update steps

Manual commands are useful for debugging, but the script above is the recommended default workflow. If you manually update code images, include **all** of these steps; `kubectl apply` alone is not enough for frontend/backend code changes:

```bash
# Build fresh stable local image tags on the host Docker daemon.
eval $(minikube docker-env -u)
docker compose build backend frontend

# Load the images that the Kubernetes Deployments reference.
minikube image load bookstore-backend:latest
minikube image load bookstore-frontend:latest

# Apply manifests. "unchanged" only means manifest text did not change.
minikube kubectl -- apply -f k8s/namespace.yaml
minikube kubectl -- apply -f k8s/configmap.yaml
minikube kubectl -- apply -f k8s/secret.yaml
minikube kubectl -- apply -f k8s/postgres-service.yaml
minikube kubectl -- apply -f k8s/postgres-deployment.yaml
minikube kubectl -- apply -f k8s/monitoring-backend-rbac.yaml
minikube kubectl -- apply -f k8s/public-backend-service.yaml
minikube kubectl -- apply -f k8s/admin-backend-service.yaml
minikube kubectl -- apply -f k8s/monitoring-backend-service.yaml
minikube kubectl -- apply -f k8s/public-backend-deployment.yaml
minikube kubectl -- apply -f k8s/admin-backend-deployment.yaml
minikube kubectl -- apply -f k8s/monitoring-backend-deployment.yaml
minikube kubectl -- apply -f k8s/frontend-service.yaml
minikube kubectl -- apply -f k8s/frontend-deployment.yaml
minikube kubectl -- apply -f k8s/ingress.yaml
minikube kubectl -- apply -f k8s/hpa.yaml

# Restart Pods so the stable local tags resolve to the newly loaded images.
minikube kubectl -- rollout restart deployment/public-backend deployment/admin-backend deployment/monitoring-backend -n bookstore
minikube kubectl -- rollout restart deployment/frontend -n bookstore
minikube kubectl -- rollout status deployment/public-backend -n bookstore --timeout=240s
minikube kubectl -- rollout status deployment/admin-backend -n bookstore --timeout=240s
minikube kubectl -- rollout status deployment/monitoring-backend -n bookstore --timeout=240s
minikube kubectl -- rollout status deployment/frontend -n bookstore --timeout=240s
```

Manual `kubectl apply` without rebuilding/loading/restarting is appropriate only for configuration-only changes such as ConfigMap, Ingress, or HPA edits that do not change frontend/backend container contents.

### 4.3 Test the NodePort

`frontend-service` is a NodePort service on port `30080`.

```bash
MINIKUBE_IP=$(minikube ip)
curl "http://${MINIKUBE_IP}:30080"
curl "http://${MINIKUBE_IP}:30080/api/health"
curl "http://${MINIKUBE_IP}:30080/api/books"
```

### 4.4 Expose Browser Demo

`frontend-service` is exposed inside Kubernetes as a NodePort on `30080`. In this Minikube-on-cloud-server setup, `$(minikube ip)` is an internal Minikube address, so public browser access should continue to use the existing iptables-based expose script from public host port `3000` to `$(minikube ip):30080` when needed.

```bash
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

Your cloud firewall/security group must allow inbound TCP `3000`. Then open the demo with HTTP, not HTTPS:

```text
http://<server-public-ip>:3000
```

Manual equivalent for the verified iptables method:

```bash
MINIKUBE_IP=$(minikube ip)

sudo sysctl -w net.ipv4.ip_forward=1

sudo iptables -t nat -I PREROUTING 1 \
  -p tcp --dport 3000 \
  -j DNAT --to-destination "${MINIKUBE_IP}:30080"

sudo iptables -t nat -I POSTROUTING 1 \
  -p tcp -d "${MINIKUBE_IP}" --dport 30080 \
  -j MASQUERADE

sudo iptables -I FORWARD 1 \
  -p tcp -d "${MINIKUBE_IP}" --dport 30080 \
  -m conntrack --ctstate NEW,ESTABLISHED,RELATED \
  -j ACCEPT

sudo iptables -I FORWARD 1 \
  -p tcp -s "${MINIKUBE_IP}" --sport 30080 \
  -m conntrack --ctstate ESTABLISHED,RELATED \
  -j ACCEPT

sudo iptables -I DOCKER-USER 1 \
  -p tcp -d "${MINIKUBE_IP}" --dport 30080 \
  -j ACCEPT

sudo iptables -I DOCKER-USER 1 \
  -p tcp -s "${MINIKUBE_IP}" --sport 30080 \
  -j ACCEPT
```

This is a demo exposure method for a single-node Minikube environment. In production Kubernetes, a cloud `LoadBalancer` Service or an Ingress controller backed by a public load balancer is more standard.

To remove the demo forwarding rules, run cleanup with the same ports:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh --cleanup
```


## 4.5 Admin Demo catalog test case

The frontend includes a simple **Admin Demo** page for catalog and inventory management. It is intentionally unauthenticated for course/demo simplicity; do not treat it as a production admin surface. The page supports adding books, deleting books, and increasing or decreasing stock while preventing negative inventory values.

This feature is useful as a practical test case when verifying that frontend and backend code changes were rebuilt, loaded into Minikube, and rolled out correctly. After changing the Admin Demo or its API, use the standardized workflow:

```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
./scripts/k8s-status.sh
```

To exercise the admin API directly against a running backend, run:

```bash
./scripts/test-admin-api.sh
```

`test-admin-api.sh` uses `BASE_URL=http://localhost:8000` by default. Override `BASE_URL` to test through the frontend proxy or Minikube NodePort, for example:

```bash
BASE_URL=http://localhost:8080 ./scripts/test-admin-api.sh
BASE_URL=http://$(minikube ip):30080 ./scripts/test-admin-api.sh
```

If a newly added route still returns `404` after a rebuild/deploy, verify that the running backend Pod actually contains the new route file before debugging application routing. For the admin API route, for example:

```bash
ADMIN_BACKEND_POD=$(minikube kubectl -- get pod -n bookstore -l app=admin-backend -o jsonpath='{.items[0].metadata.name}')
minikube kubectl -- exec -n bookstore "$ADMIN_BACKEND_POD" -- find / -name "admin_books.py" 2>/dev/null
```

No output means the Pod is still running a stale image or the file was not copied into the image. Re-run `./scripts/k8s-rebuild-and-deploy.sh`; it should fail clearly if the host image or running Pod is missing `admin_books.py`.

Book deletion may return a clear conflict error when the book is referenced by historical `order_items`; the demo preserves historical orders instead of deleting them.


## 4.6 HPA metrics-server repair and autoscaling demo

Kubernetes HPA needs the Metrics API from `metrics-server` before it can calculate CPU utilization. The HPA is now `public-backend-hpa` and targets `Deployment/public-backend`. If it shows `cpu: <unknown>/50%`, repair and verify metrics-server with:

```bash
./scripts/k8s-fix-metrics-server.sh
```

The repair script enables the Minikube metrics-server addon, checks for image pull failures, replaces a bad tag+digest image with a valid tag-only metrics-server image when needed, waits for rollout completion, verifies `kubectl top nodes` and `kubectl top pods -n bookstore`, and confirms HPA no longer reports `<unknown>`.

Run the repeatable HPA demo with:

```bash
./scripts/k8s-hpa-demo.sh
```

Optional custom load example:

```bash
DURATION=240s CONCURRENCY=30 ./scripts/k8s-hpa-demo.sh
```

Expected behavior:

- Before load: public-backend has 2 replicas, CPU is low, and HPA shows a known value such as `cpu: 3%/50%`.
- During load: CPU rises above the 50% target and public-backend scales from 2 replicas to 3, 4, or 5 replicas.
- After load: public-backend eventually scales back down to 2 replicas; scale-down may take several minutes because HPA uses stabilization behavior.

HPA CPU percentages are relative to each container's CPU request, not total node CPU. For example, if public-backend requests `100m` CPU and uses `300m` CPU, HPA can report about `300%`.

Screenshot/evidence checklist for the final report:

- HPA before load
- pod CPU before load
- `hey` load generator output
- HPA during load
- public-backend Deployment scaling from 2 to more replicas
- public-backend Pods being created (`Pending -> ContainerCreating -> Running -> Ready`)
- pod CPU during load
- `kubectl describe hpa public-backend-hpa -n bookstore` output
- scale-down evidence if captured

## 5. First-Time Deployment

Use this only for a clean cluster or a fresh Minikube profile.

```bash
minikube start --driver=docker --memory=4096 --cpus=2
minikube status
minikube kubectl -- get nodes

chmod +x scripts/*.sh
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
```

Manual first-time sequence if you are not using the helper script. Prefer the script above; if you do this manually, still build and load the local images before applying manifests:

```bash
eval $(minikube docker-env -u)
docker compose build backend frontend
minikube image load bookstore-backend:latest
minikube image load bookstore-frontend:latest

minikube kubectl -- apply -f k8s/namespace.yaml
minikube kubectl -- wait --for=jsonpath='{.status.phase}'=Active namespace/bookstore --timeout=60s

minikube kubectl -- apply -f k8s/configmap.yaml
minikube kubectl -- apply -f k8s/secret.yaml
minikube kubectl -- apply -f k8s/postgres-service.yaml
minikube kubectl -- apply -f k8s/postgres-deployment.yaml

minikube kubectl -- create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n bookstore --dry-run=client -o yaml | minikube kubectl -- apply -f -
minikube kubectl -- apply -f k8s/postgres-init-job.yaml
minikube kubectl -- wait --for=condition=complete job/postgres-init -n bookstore --timeout=180s

minikube kubectl -- apply -f k8s/monitoring-backend-rbac.yaml
minikube kubectl -- apply -f k8s/public-backend-service.yaml
minikube kubectl -- apply -f k8s/admin-backend-service.yaml
minikube kubectl -- apply -f k8s/monitoring-backend-service.yaml
minikube kubectl -- apply -f k8s/public-backend-deployment.yaml
minikube kubectl -- apply -f k8s/admin-backend-deployment.yaml
minikube kubectl -- apply -f k8s/monitoring-backend-deployment.yaml
minikube kubectl -- apply -f k8s/frontend-service.yaml
minikube kubectl -- apply -f k8s/frontend-deployment.yaml
minikube kubectl -- apply -f k8s/ingress.yaml
minikube kubectl -- apply -f k8s/hpa.yaml

minikube kubectl -- rollout restart deployment/public-backend deployment/admin-backend deployment/monitoring-backend -n bookstore
minikube kubectl -- rollout restart deployment/frontend -n bookstore
minikube kubectl -- rollout status deployment/public-backend -n bookstore --timeout=240s
minikube kubectl -- rollout status deployment/admin-backend -n bookstore --timeout=240s
minikube kubectl -- rollout status deployment/monitoring-backend -n bookstore --timeout=240s
minikube kubectl -- rollout status deployment/frontend -n bookstore --timeout=240s
```

## 6. Testing and Verification

Use the scripts in `scripts/` to verify the same deployment features consistently after either a Docker Compose run or a Minikube deployment. All commands below should be run from the repository root.

### 6.1 Permission setup

Make the top-level helper scripts executable before running them:

```bash
chmod +x scripts/*.sh
```

The shared helper file `scripts/lib/k8s.sh` is sourced by Kubernetes scripts; it does not need to be executed directly.

### 6.2 Docker Compose verification

Use Docker Compose for local full-stack integration before or separate from Kubernetes:

```bash
./scripts/compose-up.sh
```

`compose-up.sh` runs `docker compose up --build`, so it builds and starts the database, backend, and frontend services in the foreground. In another terminal, verify service status and useful local URLs:

```bash
./scripts/compose-status.sh
```

The status script prints `docker compose ps` and these expected local endpoints:

- Frontend: `http://localhost:8080`
- Backend health: `http://localhost:8000/api/health`
- Backend DB health: `http://localhost:8000/api/health/db`
- Backend books API: `http://localhost:8000/api/books`
- Frontend-proxied API route: `http://localhost:8080/api/health`

Run the API smoke test against the backend default URL:

```bash
./scripts/test-api.sh
```

`test-api.sh` uses `BASE_URL=http://localhost:8000` by default and checks this flow: `/api/health`, `/api/health/db`, `/api/books`, `/api/cart`, add to cart, cart after add, create order, and order history. To test a different endpoint, override `BASE_URL`:

```bash
BASE_URL=http://localhost:8080 ./scripts/test-api.sh
```

Run the admin API smoke test to create a temporary book, increase stock, decrease stock, delete the temporary book, and list books again:

```bash
./scripts/test-admin-api.sh
BASE_URL=http://localhost:8080 ./scripts/test-admin-api.sh
```

Inspect logs when a Compose check fails:

```bash
./scripts/compose-logs.sh
./scripts/compose-logs.sh backend
```

Stop the Compose stack when finished:

```bash
./scripts/compose-down.sh
```


### Kubernetes backend split and path routing

Kubernetes no longer runs one shared backend Deployment for every API path. Phase 1 uses three Deployments that all reuse `bookstore-backend:latest` while keeping PostgreSQL and the React/Nginx frontend shared:

- `public-backend` / `public-backend-service`: store APIs (`/api/health`, `/api/health/db`, `/api/books`, `/api/cart`, `/api/orders`) and the HPA target.
- `admin-backend` / `admin-backend-service`: admin catalog and stock APIs under `/api/admin/books`.
- `monitoring-backend` / `monitoring-backend-service`: `GET /api/admin/cluster/status`; this is the only backend Deployment with Kubernetes read-only RBAC.

Both `k8s/ingress.yaml` and `frontend/nginx.conf` use the same path split: `/api/admin/cluster` routes to monitoring, `/api/admin` routes to admin, `/api` routes to public, and `/` serves the React SPA. This keeps direct Ingress access through `bookstore.local` and NodePort access through frontend Nginx consistent.

## Distributed System Mode: Multi-node PostgreSQL HA

This is the recommended mode when you need clear distributed-system evidence for the bookstore project. It keeps `DB_MODE=single` as the stable default and adds an explicit multi-node experiment workflow instead of changing every Kubernetes script implicitly.

Run the one-command workflow:

```bash
./scripts/k8s-distributed-ha-rebuild-all.sh
```

By default, the script uses:

```bash
MINIKUBE_PROFILE=bookstore-distributed
NODES=3
DB_MODE=ha
```

The workflow starts or reuses a three-node Minikube profile, deploys the CloudNativePG PostgreSQL HA cluster, deploys the application, and runs the distributed evidence script. It verifies:

- multiple Kubernetes nodes with `kubectl get nodes -o wide`
- PostgreSQL primary/replica Pod placement across Kubernetes nodes
- CloudNativePG `bookstore-postgres-rw` and `bookstore-postgres-ro` EndpointSlices
- failover evidence that reports the old primary Pod/node and new primary Pod/node
- API health, database health, and cluster status endpoints
- idempotent checkout behavior with `Idempotency-Key` via `scripts/test-order-consistency.sh`

Useful follow-up checks after the workflow completes:

```bash
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
MINIKUBE_PROFILE=bookstore-distributed BASE_URL=http://$(minikube -p bookstore-distributed ip):30080 ./scripts/test-order-consistency.sh
```

This is still a Minikube multi-node simulation on one host. It improves the evidence by showing multiple Kubernetes Nodes and preferred PostgreSQL Pod spreading, but it does not provide real physical fault isolation. Ideal evidence is three PostgreSQL Pods on three Kubernetes Nodes; two or more distinct nodes is acceptable under local resource constraints, and the evidence script warns rather than fails if the local scheduler places all instances together.

For production, migrate to real multi-VM Kubernetes or managed Kubernetes with CSI-backed storage, backups, TLS, a real image registry, monitoring/alerting, and disaster recovery planning. Keep `DB_MODE=single` as the stable default for normal local development. Keep `DB_MODE=ha` on the default profile as a lighter HA-mechanism test when you do not need multi-node placement evidence.

## Distributed System Mode: PostgreSQL HA

### Purpose

`DB_MODE=ha` turns the database layer into an optional distributed, stateful high-availability experiment. The default workflow remains `DB_MODE=single`; use HA mode when you want to demonstrate PostgreSQL leader/follower replication, automatic failover, and retry-safe order placement.

### Architecture

```text
Browser / API client
  -> Ingress / Frontend Nginx
  -> public-backend / admin-backend / monitoring-backend
  -> bookstore-postgres-rw
  -> CloudNativePG PostgreSQL HA cluster
       primary: bookstore-postgres-1
       replicas: bookstore-postgres-2, bookstore-postgres-3
```

In HA mode, CloudNativePG manages the `bookstore-postgres` cluster with three PostgreSQL instances: one primary and two replicas. The backend uses `DB_WRITE_HOST=bookstore-postgres-rw`, a stable read-write service that follows the current primary. CloudNativePG also exposes `bookstore-postgres-ro` for read-only replica traffic and `bookstore-postgres-r` across all instances; read splitting to `bookstore-postgres-ro` is a future optimization.

### Distributed system concept mapping

| Concept | Project implementation |
| --- | --- |
| Leader | CloudNativePG PostgreSQL primary |
| Followers | PostgreSQL replicas |
| Log replication | PostgreSQL WAL streaming |
| Stable write endpoint | `bookstore-postgres-rw` |
| Read-only replica endpoint | `bookstore-postgres-ro` |
| Failover controller | CloudNativePG operator |
| Partial failure retry protection | `Idempotency-Key` on `POST /api/orders` |
| Strong consistency boundary | PostgreSQL transaction for order placement |

### Consistency model

Order placement, stock decrement, `order_items` creation, and cart cleanup are handled atomically by PostgreSQL transactions. `Idempotency-Key` prevents duplicate orders and duplicate stock decrement when a client retries after timeout, failover, or ambiguous partial failure. To preserve strong consistency for the demo, all application queries currently use the read-write service; read replica usage is future work because replicas may lag.

### How to run HA mode

Install the CloudNativePG operator before deploying with `DB_MODE=ha`:

```bash
./scripts/k8s-install-cnpg.sh
```

Optionally pre-pull the CloudNativePG PostgreSQL image into Minikube:

```bash
minikube ssh -- docker image inspect ghcr.io/cloudnative-pg/postgresql:16.4 >/dev/null 2>&1 \
  && echo "OK: CNPG PostgreSQL image exists" \
  || minikube ssh -- docker pull ghcr.io/cloudnative-pg/postgresql:16.4
```

Deploy HA mode with the staged workflow:

```bash
DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh install-cnpg
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh apply-ha-database
DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh init-db
DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh deploy-app
DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh verify-app
DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh
```

#### One-command HA rebuild

For convenience, the same safe HA stages can be run in order with one explicit wrapper:

```bash
./scripts/k8s-ha-rebuild-all.sh
```

The wrapper installs/checks CloudNativePG, applies/checks the HA PostgreSQL cluster, initializes the database only when needed, deploys the application, and verifies the application. It is still heavier than `DB_MODE=single`: HA mode runs three PostgreSQL instances plus the app, Ingress, metrics-server, and HPA, so 6GB+ Minikube memory is recommended. For debugging or lower-resource environments, run the staged commands individually. The wrapper preserves PVCs and does not reset the database unless you explicitly set `FORCE_POSTGRES_INIT=1`.

### Verification commands

```bash
MINIKUBE_IP=$(minikube ip)

curl -s http://$MINIKUBE_IP:30080/api/health
curl -s http://$MINIKUBE_IP:30080/api/health/db
curl -s http://$MINIKUBE_IP:30080/api/admin/cluster/status | python3 -m json.tool

DB_MODE=ha BASE_URL=http://$MINIKUBE_IP:30080 ./scripts/test-api.sh
DB_MODE=ha BASE_URL=http://$MINIKUBE_IP:30080 ./scripts/test-admin-api.sh
BASE_URL=http://$MINIKUBE_IP:30080 ./scripts/test-order-consistency.sh
DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
```

### Expected evidence

- CloudNativePG `Cluster` is healthy.
- Three PostgreSQL instances are ready.
- One instance is primary and two instances are replicas.
- `bookstore-postgres-rw` points to the current primary.
- `bookstore-postgres-ro` points to replicas.
- `/api/health/db` returns `connected`.
- `GET /api/admin/cluster/status` shows `db.mode=ha` and no DB warnings.
- The idempotency test passes.
- The failover test shows the old primary, new primary promotion, DB health recovery, preserved data, and post-failover write success.

### Limitations and production migration

Minikube is a resource-limited demo environment, not production-grade distributed infrastructure. Three PostgreSQL HA pods plus the application, Ingress, and `metrics-server` may require more memory, preferably 6GB+ if available, and Minikube may still place all PostgreSQL instances on one node without real production fault domains.


### CloudNativePG initdb permission denied on Minikube hostPath PVC

On some Minikube hostPath-backed volumes, the initial CloudNativePG data path can be created as `root:root`. CloudNativePG PostgreSQL runs as UID/GID `26`, so `initdb` can fail with:

```text
initdb: error: could not create directory "/var/lib/postgresql/data/pgdata": Permission denied
```

Preferred self-contained command (auto-detects permission issue and runs the repair helper automatically):

```bash
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh apply-ha-database
```

If this is a failed brand-new initialization and CloudNativePG gets stuck with a dangling initializing PVC, use one-command recovery mode:

```bash
AUTO_FIX_CNPG_PVC_PERMISSIONS=1 FORCE_DELETE_DANGLING_CNPG_PVC=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh apply-ha-database
```

This mode creates namespace/Cluster/PVC, detects permission failure, runs the repair Job with `ghcr.io/cloudnative-pg/postgresql:16.4`, handles failed-new-init dangling PVC only when `FORCE_DELETE_DANGLING_CNPG_PVC=1`, and then waits again for `Cluster/bookstore-postgres` to become Ready.

⚠️ `FORCE_DELETE_DANGLING_CNPG_PVC=1` must **not** be used for real databases with data. It is intended only for recovery from failed brand-new initialization.

For production, migrate to real multi-VM Kubernetes or managed Kubernetes with production-grade `LoadBalancer`/Ingress exposure, CSI storage, DNS/TLS, production secrets, an external image registry, backup/restore, Prometheus/Grafana monitoring, and disaster recovery planning. `DB_MODE=single` remains the stable default workflow.

For deeper details, see [PostgreSQL HA experiment](docs/postgres_ha_experiment.md).

### 6.3 Kubernetes deployment verification

After Minikube is running, use the rebuild/deploy helper for the full local-image Kubernetes workflow:

```bash
./scripts/k8s-rebuild-and-deploy.sh
```

This script checks prerequisites, builds one shared backend image (`bookstore-backend:latest`) and one frontend image (`bookstore-frontend:latest`) on the host Docker daemon, confirms that the host backend image contains the admin route file, and then performs a safe stable-tag refresh for Minikube. Because this demo intentionally uses stable local image tags such as `:latest`, the script saves replica counts for `public-backend`, `admin-backend`, `monitoring-backend`, and `frontend`, temporarily scales only those application Deployments down to zero, waits for their old Pods to exit, removes the old same-tag backend/frontend images inside Minikube, loads the freshly built images, applies the Kubernetes manifests, restores the saved replica counts, waits for rollout completion, verifies that each backend Deployment has a running Pod containing `admin_books.py`, and prints the Minikube NodePort URL.

The safe refresh does **not** stop PostgreSQL. The PostgreSQL Deployment, Service, PVC-backed data, `postgres-init-sql` ConfigMap update, and `FORCE_POSTGRES_INIT` behavior remain unchanged; only the split backend and frontend application Pods are temporarily stopped while their same-tag local images are replaced.

Then verify the deployed Kubernetes application:

```bash
./scripts/k8s-test-local.sh
```

`k8s-test-local.sh` verifies that Minikube is running, the `bookstore` namespace exists, Pods are `Running` or `Completed`, `frontend-service` is a `NodePort` on port `30080`, and the Minikube NodePort responds successfully for:

- `/`
- `/api/health`
- `/api/health/db`
- `/api/books`
- `/api/admin/cluster/status`

For a detailed Kubernetes resource snapshot, run:

```bash
./scripts/k8s-status.sh
```

`k8s-status.sh` prints Minikube status, Minikube IP, the resolved Kubernetes command mode (`kubectl` or `minikube kubectl --`), all resources in the `bookstore` namespace, Pods, Services, Ingress, HPA, and public-backend/admin-backend/monitoring-backend/frontend service endpoints.

### 6.4 Public browser demo verification

Verify the local Kubernetes NodePort first, then expose the public demo port:

```bash
./scripts/k8s-test-local.sh
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

The expose script verifies that `frontend-service` is a NodePort service using nodePort `30080`, then inserts iptables DNAT/MASQUERADE, bidirectional `FORWARD`, and bidirectional `DOCKER-USER` allow rules for Docker/Minikube environments. It forwards host public TCP `PUBLIC_PORT` (default `3000`) to `$(minikube ip):30080` and only exposes `frontend-service`.

Your cloud firewall or security group must allow inbound TCP `3000` or whichever `PUBLIC_PORT` you choose. Test DNAT forwarding from an external browser or another machine:

```bash
curl -v http://<server-public-ip>:3000/api/health
sudo tcpdump -ni any 'tcp port 3000 or tcp port 30080'
```

Expected packet behavior: the external request reaches `server:3000`, the server replies with `SYN-ACK`, and the forwarding rule packet counters increase. Do not use `curl http://127.0.0.1:3000` to test DNAT because local loopback traffic does not go through `PREROUTING`.

Open the browser demo with HTTP, not HTTPS:

```text
http://<server-public-ip>:3000
```

### 6.5 Monitoring and performance verification

Check Kubernetes runtime metrics with:

```bash
./scripts/monitor-k8s.sh
```

The monitoring script prints Pods, HPA status, node metrics, and pod metrics for the `bookstore` namespace. If metrics are unavailable, enable the Minikube metrics server:

```bash
minikube addons enable metrics-server
```

Run a load test with:

```bash
TARGET_URL=http://$(minikube ip):30080/api/books DURATION=60s CONCURRENCY=20 ./scripts/perf-test.sh
```

`perf-test.sh` uses `hey` when it is installed. If `hey` is not available, it falls back to a 20-request `curl` loop. By default, without environment overrides, it targets `http://localhost:8080/api/books` for `60s` at concurrency `20`.

### 6.6 Cleanup and reset helpers

Use cleanup when you want to remove Kubernetes resources defined under `k8s/` without deleting the namespace:

```bash
./scripts/k8s-cleanup.sh
```

Use reset when you want to remove Kubernetes demo data and potentially PVC-backed PostgreSQL data in the `bookstore` namespace:

```bash
./scripts/k8s-reset-local.sh
```

By default, `k8s-reset-local.sh` keeps the namespace. To delete the namespace too, run:

```bash
./scripts/k8s-reset-local.sh --delete-namespace
```

### 6.7 Script behavior notes

The Kubernetes helper scripts source `scripts/lib/k8s.sh`. That helper resolves standalone `kubectl` when available and otherwise falls back to `minikube kubectl --`; it also enforces required commands and ensures Minikube is running where needed. This means the scripts should work on Minikube-only servers without requiring a shell alias for `kubectl`.

## 7. Docker Compose Local Check

Docker Compose is useful for local integration before loading images into Minikube:

```bash
docker compose up --build
./scripts/test-api.sh
docker compose down
```

Useful Compose URLs:

- Frontend: http://localhost:8080
- Backend health: http://localhost:8000/api/health
- Backend DB health: http://localhost:8000/api/health/db
- Backend books API: http://localhost:8000/api/books

## 8. Evidence Collection for Final Report

Collect screenshots and command outputs for `report/final_report.md`.

### Docker Compose evidence
- `docker compose ps`
- frontend page at `http://localhost:8080`
- `/api/books` output
- smoke test output
- database table count

### Kubernetes evidence
- `./scripts/k8s-status.sh`
- `minikube kubectl -- get pvc -n bookstore`
- `minikube kubectl -- get ingress -n bookstore`
- `minikube kubectl -- get hpa -n bookstore`
- `postgres-init` Job logs
- `bookstore.local` frontend page
- smoke test through Minikube NodePort with `./scripts/k8s-test-local.sh`

### Monitoring/performance evidence
- `minikube kubectl -- top pods -n bookstore`
- performance test output
- HPA before/during load
- backend replica count under load

### Application evidence
- book list
- cart operation
- order placement
- order history
- stock decrease

---

## 9. Current Runtime Status

- The project contains deployment and testing support files for Docker Compose and Kubernetes.
- Runtime verification should be performed locally in your environment.
- Do not claim test results until commands are actually executed.
- `report/final_report.md` contains placeholders that should be filled with real screenshots and outputs.

> This README is a practical deployment/test guide and intentionally separates **expected results** from actual runtime outcomes.

## In-app Monitoring / HPA Dashboard
The bookstore includes a lightweight, read-only Monitoring page for the Kubernetes HPA demo. The Kubernetes backend tier is split into `public-backend`, `admin-backend`, and `monitoring-backend` Deployments that all reuse the same `bookstore-backend:latest` image. The React frontend still calls `GET /api/admin/cluster/status`; path-based routing sends that request to `monitoring-backend`, which reads public-backend Deployment, HPA, Pod, and metrics status with the Kubernetes API. The browser never calls the Kubernetes API directly.

The dashboard shows:
- public-backend Deployment desired, ready, available, and updated replicas
- public-backend HPA min/max replicas, current/desired replicas, current CPU utilization, and target CPU utilization
- public-backend Pods with phase, readiness, restart count, start time, CPU, and memory when metrics are available
- frontend-only time-series charts for public-backend replicas and HPA CPU utilization

The dashboard does not add Prometheus, Grafana, another microservice, a database, or any Kubernetes mutation controls. Its chart history is kept only in browser memory and resets when the page refreshes.

Recommended HPA demo flow:

```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-fix-metrics-server.sh
```

Then open the bookstore frontend in the browser and click **Monitoring**. In another terminal, run:

```bash
./scripts/k8s-hpa-demo.sh
```

Expected behavior:
- before load: public-backend has 2 replicas and low CPU
- during load: CPU rises above the 50% HPA target
- public-backend replicas increase toward `maxReplicas=5`
- new public-backend Pods appear in the Pods table
- the replicas chart rises from 2 toward 5
- the CPU chart rises above the target line
- after load stops: CPU decreases, and after the HPA scale-down delay replicas eventually return to 2

Metrics-server is required for CPU and memory values. If the dashboard says metrics are unavailable, run:

```bash
./scripts/k8s-fix-metrics-server.sh
```

Then verify metrics with `kubectl top pods` or the Minikube equivalent.

Screenshot/evidence checklist for the final report:
- Monitoring page before load
- HPA card before load
- replicas chart before load
- load generator terminal
- Monitoring page during load
- replicas chart showing 2 -> 5
- CPU chart showing utilization rising above target
- public-backend Pods table showing new Pods
- Monitoring page after load showing scale-down if captured
