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

---

## 3. Prerequisites

### For Docker Compose workflow
- Docker
- Docker Compose plugin

### For Kubernetes workflow
- Docker
- Minikube
- optional: standalone `kubectl`
- optional: `hey` (for performance testing)

The Kubernetes scripts support Minikube-only servers where `kubectl` is not installed as a standalone binary. If `kubectl` is unavailable, scripts automatically run Kubernetes commands through `minikube kubectl --`. Do not rely on interactive shell aliases inside scripts; Bash scripts do not reliably inherit aliases such as `alias kubectl='minikube kubectl --'`.

Verify tools:

```bash
docker --version
docker compose version
minikube version
# Optional if installed directly:
kubectl version --client
hey -h
```

> `hey` is optional. Performance scripts may provide fallback behavior if `hey` is not installed.

---

## 4. Quick Start: Docker Compose Local Deployment

### 4.1 Start full stack

```bash
docker compose up --build
```

`docker compose build` and `docker compose up --build` now create the same image tags used by Kubernetes: `bookstore-backend:latest` and `bookstore-frontend:latest`. Because these explicit image names are set in `docker-compose.yml`, Compose should no longer create project-prefixed image names such as `dsaa4040proj-main-backend` or `dsaa4040proj-main-frontend` for these services.

or

```bash
./scripts/compose-up.sh
```

### 4.2 Check running services

```bash
docker compose ps
```

or

```bash
./scripts/compose-status.sh
```

### 4.3 Useful URLs

- Frontend: http://localhost:8080
- Backend health: http://localhost:8000/api/health
- Backend DB health: http://localhost:8000/api/health/db
- Backend books API: http://localhost:8000/api/books
- Frontend-proxied backend health: http://localhost:8080/api/health

### 4.4 Verify database initialization

In Docker Compose, `schema.sql` and `seed.sql` are mounted into PostgreSQL's `/docker-entrypoint-initdb.d/` and executed **only when the PostgreSQL data volume is first created**.

Connect to PostgreSQL:

```bash
docker exec -it bookstore-db psql -U bookstore -d bookstore
```

Inside `psql`:

```sql
\dt
SELECT COUNT(*) FROM books;
SELECT * FROM books;
```

Expected result:
- `books`, `carts`, `orders`, `order_items` tables exist
- `books` contains **8** seed records

### 4.5 Run API smoke test

```bash
./scripts/test-api.sh
```

`BASE_URL` override examples:

```bash
BASE_URL=http://localhost:8000 ./scripts/test-api.sh
BASE_URL=http://localhost:8080 ./scripts/test-api.sh
```

### 4.6 Test frontend manually

In a browser:
1. Open http://localhost:8080
2. Check backend and DB status indicators
3. Search books
4. Add a book to cart
5. Update cart quantity
6. Remove cart item
7. Place an order
8. Verify order history
9. Verify stock decreases

### 4.7 Inspect logs

```bash
docker compose logs --tail=100
./scripts/compose-logs.sh
./scripts/compose-logs.sh backend
./scripts/compose-logs.sh frontend
./scripts/compose-logs.sh db
```

### 4.8 Stop services

```bash
docker compose down
```

or

```bash
./scripts/compose-down.sh
```

### 4.9 Reset database

`schema.sql` resets tables and `seed.sql` reinserts demo books only when the PostgreSQL data volume is recreated.

```bash
docker compose down -v
docker compose up --build
```

or

```bash
./scripts/reset-db.sh
```

> Warning: this deletes the local PostgreSQL volume and clears local demo data.

---

## 5. Docker Compose Verification Checklist

- [ ] Docker is installed
- [ ] `docker compose config` succeeds
- [ ] `docker compose build` succeeds
- [ ] all three containers run
- [ ] PostgreSQL healthcheck passes
- [ ] schema tables exist
- [ ] 8 seed books exist
- [ ] backend `/api/health` works
- [ ] backend `/api/health/db` works
- [ ] backend `/api/books` works
- [ ] frontend loads at `localhost:8080`
- [ ] frontend `/api` proxy works
- [ ] smoke test script passes
- [ ] search/add-cart/update-cart/delete-cart/place-order works
- [ ] order history displays
- [ ] stock decreases after order
- [ ] cart clears after order

---

## 6. Kubernetes / Minikube Deployment Guide

### 6.0 Minikube-only kubectl support

This project supports servers where `kubectl` is not installed directly. All Kubernetes-related scripts source a shared resolver in `scripts/lib/k8s.sh`: if standalone `kubectl` exists, scripts use it; otherwise they automatically use `minikube kubectl --`. This matters because Bash scripts do not reliably inherit interactive shell aliases such as `alias kubectl='minikube kubectl --'`.

Kubernetes tests also use Minikube service access, not Docker Compose localhost ports. The frontend Kubernetes Service is exposed as a NodePort on `30080`, so the local Kubernetes smoke test uses `http://$(minikube ip):30080` and avoids assuming that `localhost:8000` or `localhost:3000` belongs to Kubernetes.

### Recommended flow (student-friendly)
1. Verify Docker Compose first (`docker compose up --build`, smoke test, then `docker compose down`).
2. Start Minikube and verify cluster health.
3. Run `./scripts/k8s-rebuild-and-deploy.sh` as the recommended one-pass Kubernetes deployment path.
4. Check pod/job status in namespace `bookstore` with `./scripts/k8s-status.sh`.
5. Test the Kubernetes frontend-service NodePort with `./scripts/k8s-test-local.sh`; do not use Docker Compose localhost ports for Kubernetes validation.
6. Optionally expose the frontend demo with `./scripts/k8s-expose-demo.sh`.
7. Optionally enable Ingress and HPA/metrics for extra features.

Recommended Minikube-only demo path:

```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
./scripts/k8s-expose-demo.sh
```

Docker Compose and Kubernetes now share the same application image names: `bookstore-backend:latest` and `bookstore-frontend:latest`. The backend also has a Compose network alias named `backend-service`, matching the Kubernetes Service DNS name, so frontend Nginx can proxy `/api` to `http://backend-service:8000` in both environments without manual retagging or config patching.

> `docker compose down` **does not delete images by default**. Optional cleanup: `docker compose down --rmi local` or `docker compose down --rmi all`.

### 6.1 Start Minikube first (required)

Recommended (normal user in docker group):
```bash
minikube start --driver=docker --memory=4096 --cpus=2
minikube status
minikube kubectl -- get nodes
```

Cloud VM/root troubleshooting (coursework only):
```bash
minikube start --driver=docker --force --memory=2048 --cpus=2
```

If default startup fails in restricted networks (for example China/cloud mirrors), try a mirror-focused command and pin a stable Kubernetes version:
```bash
minikube start   --driver=docker   --force   --kubernetes-version=v1.32.0   --image-mirror-country=cn   --image-repository=registry.cn-hangzhou.aliyuncs.com/google_containers   --registry-mirror=https://wmbakxsu.mirror.aliyuncs.com   --binary-mirror=https://dl.k8s.io/release   --memory=2048 --cpus=2
```

> If Minikube system image pulls fail, that is usually an environment/network mirror issue, not a project YAML issue.

### 6.2 Deploy with helper script (recommended)

```bash
chmod +x scripts/*.sh
./scripts/k8s-rebuild-and-deploy.sh
```

What this script does:
- sets a robust `PATH` and fails fast with `set -euo pipefail`
- checks required commands (`docker`, `minikube`) and the Docker Compose plugin
- resolves the Kubernetes command to either standalone `kubectl` or `minikube kubectl --`
- verifies Minikube is running
- switches back to the host Docker environment and runs `docker compose build`
- verifies `bookstore-backend:latest` and `bookstore-frontend:latest` exist
- loads application images into Minikube and loads `postgres:16` when present on the host
- applies `k8s/namespace.yaml` first and waits for Active
- creates/updates `postgres-init-sql` ConfigMap from `database/schema.sql` and `database/seed.sql`
- creates `postgres-init` Job if missing and only recreates it when it has not completed or `FORCE_POSTGRES_INIT=1` is set
- deploys backend/frontend/services/ingress/hpa, restarts backend/frontend, waits for rollout status, and prints all Kubernetes resources in namespace `bookstore`
- prints the internal Minikube NodePort URL (`http://$(minikube ip):30080`) and the public demo URL format for the expose script

> `postgres-init` rerun may reset demo data depending on SQL logic (for example drop/recreate table behavior). Use `FORCE_POSTGRES_INIT=1 ./scripts/k8s-rebuild-and-deploy.sh` when you explicitly need to recreate the init Job.

### 6.3 Manual deployment/debug flow

```bash
# Pick a command that works in Minikube-only environments.
if command -v kubectl >/dev/null 2>&1; then
  KUBECTL=(kubectl)
else
  KUBECTL=(minikube kubectl --)
fi

# 1) namespace first
"${KUBECTL[@]}" apply -f k8s/namespace.yaml
"${KUBECTL[@]}" wait --for=jsonpath='{.status.phase}'=Active namespace/bookstore --timeout=60s

# 2) core config + db
"${KUBECTL[@]}" apply -f k8s/configmap.yaml
"${KUBECTL[@]}" apply -f k8s/secret.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-service.yaml
"${KUBECTL[@]}" apply -f k8s/postgres-deployment.yaml

# 3) create SQL ConfigMap before init job
"${KUBECTL[@]}" create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n bookstore --dry-run=client -o yaml | "${KUBECTL[@]}" apply -f -

# 4) rerun init job explicitly only when needed
"${KUBECTL[@]}" delete job postgres-init -n bookstore --ignore-not-found
"${KUBECTL[@]}" apply -f k8s/postgres-init-job.yaml
"${KUBECTL[@]}" wait --for=condition=complete job/postgres-init -n bookstore --timeout=180s

# 5) app layer
"${KUBECTL[@]}" apply -f k8s/backend-service.yaml
"${KUBECTL[@]}" apply -f k8s/backend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-service.yaml
"${KUBECTL[@]}" apply -f k8s/frontend-deployment.yaml
"${KUBECTL[@]}" apply -f k8s/ingress.yaml
"${KUBECTL[@]}" apply -f k8s/hpa.yaml
```

### 6.4 Image build/load troubleshooting

Kubernetes manifests use local image names with `imagePullPolicy: IfNotPresent`, so images must exist in Minikube runtime. Prefer `./scripts/k8s-rebuild-and-deploy.sh`; it builds the Compose services with the same `bookstore-*` tags that the Kubernetes manifests use, verifies the tags exist, and loads them into Minikube.

Option A (build in Minikube Docker env):
```bash
eval $(minikube docker-env)
docker build -t bookstore-backend:latest ./backend
docker build -t bookstore-frontend:latest ./frontend
```

Option B (build on host with Compose and load to Minikube):
```bash
eval $(minikube docker-env -u)
docker compose build backend frontend
docker image inspect bookstore-backend:latest bookstore-frontend:latest
minikube image load bookstore-backend:latest
minikube image load bookstore-frontend:latest
```

If Minikube-side build cannot pull Docker Hub base images (`python:3.12-slim`, `node:20-alpine`, `nginx:alpine`, `postgres:16`), pull on host first then `minikube image load`, or configure mirrors.

### 6.5 Test Kubernetes services correctly (avoid Compose false positives)

Compose test target:
```bash
BASE_URL=http://localhost:8000 ./scripts/test-api.sh
```
(works only when Compose backend is mapped to host)

Kubernetes test target (recommended):
```bash
./scripts/k8s-test-local.sh
```
This script checks Minikube, verifies the `bookstore` namespace and pods, confirms `frontend-service` is a NodePort service on port `30080`, and tests the Kubernetes service through `http://$(minikube ip):30080`. It does not assume `localhost:8000` or `localhost:3000`, because those ports may belong to Docker Compose or another local process.

Manual Kubernetes equivalent:
```bash
MINIKUBE_IP=$(minikube ip)
curl "http://${MINIKUBE_IP}:30080"
curl "http://${MINIKUBE_IP}:30080/api/health"
curl "http://${MINIKUBE_IP}:30080/api/health/db"
curl "http://${MINIKUBE_IP}:30080/api/books"
```

If you need local debugging with port-forward, keep it explicit and avoid Compose conflicts:
```bash
# Local debugging only; not the standalone demo path.
minikube kubectl -- port-forward -n bookstore service/backend-service 18000:8000
minikube kubectl -- port-forward -n bookstore service/frontend-service 13000:80
```

Before claiming Kubernetes success, verify:
```bash
./scripts/k8s-status.sh
```
Expected essentials:
- postgres Pod: Running
- postgres-init Job: Completed
- backend/frontend Pods: Running
- frontend-service: NodePort `30080`

### 6.6 Public demo exposure

The standalone demo path exposes only `frontend-service` publicly. The service is a NodePort service on `30080`, and the expose helper forwards `PUBLIC_PORT` (default `3000`) on the server to the Minikube NodePort. It does not expose `backend-service` or `postgres-service` directly.

```bash
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

Your cloud security group/firewall must allow inbound TCP `3000` (or the custom `PUBLIC_PORT`). After exposure, browse to:

```text
http://<server-public-ip>:3000
```

### 6.7 Ingress testing

Enable and verify ingress controller:
```bash
minikube addons enable ingress
minikube kubectl -- get pods -n ingress-nginx
minikube kubectl -- get ingress -n bookstore
```

Test from server:
```bash
curl -H "Host: bookstore.local" http://$(minikube ip)/api/health
```

In cloud VM/headless environments, browser access from your laptop may require hosts/DNS mapping or SSH tunnel.

### 6.8 HPA / metrics-server testing

HPA may show `cpu: <unknown>/50%` until metrics-server is enabled and data is collected.

```bash
minikube addons enable metrics-server
minikube kubectl -- top pods -n bookstore
minikube kubectl -- get hpa -n bookstore
```

### 6.9 Cleanup

```bash
# delete app resources
./scripts/k8s-cleanup.sh

# full reset helper (optional namespace deletion)
./scripts/k8s-reset-local.sh
./scripts/k8s-reset-local.sh --delete-namespace

# stop Minikube
minikube stop
```

## 7. Kubernetes Verification Checklist

- [ ] Minikube starts
- [ ] Kubernetes command resolver can access cluster (`kubectl` or `minikube kubectl --`)
- [ ] backend image built in Minikube
- [ ] frontend image built in Minikube
- [ ] namespace `bookstore` created
- [ ] ConfigMap and Secret created
- [ ] PostgreSQL pod Running/Ready
- [ ] PVC Bound
- [ ] `postgres-service` created
- [ ] `postgres-init-sql` ConfigMap created
- [ ] `postgres-init` Job completed
- [ ] database tables exist
- [ ] seed books count is 8
- [ ] backend pods Running/Ready
- [ ] frontend pods Running/Ready
- [ ] frontend-service works through Minikube NodePort 30080
- [ ] ingress addon enabled
- [ ] `bookstore.local` routes `/` to frontend
- [ ] `bookstore.local` routes `/api` to backend
- [ ] smoke test passes through Minikube NodePort
- [ ] metrics-server enabled
- [ ] `minikube kubectl -- top` works
- [ ] HPA shows CPU metrics
- [ ] performance test runs
- [ ] backend replicas can be observed during load

---

## 8. Troubleshooting Guide

### Problem: `docker` command not found
**Fix:** install/start Docker Desktop or Docker Engine.

### Problem: `npm install` fails during frontend build
**Fix:** check network/npm registry; retry `docker compose build`.

### Problem: backend cannot connect to database
**Fix:**
- In Docker Compose, `DB_HOST` should be `db`.
- In Kubernetes, `DB_HOST` should be `postgres-service`.
- Check `/api/health/db`.
- Check database logs.

### Problem: database tables do not exist
**Fix:**
- For Docker Compose, run `docker compose down -v` and `docker compose up --build`.
- For Kubernetes, create `postgres-init-sql` ConfigMap and run `postgres-init` Job.

### Problem: frontend loads but API fails
**Fix:**
- Check frontend Nginx `/api` proxy.
- In Compose, frontend Nginx uses the backend network alias `backend-service`.
- In Kubernetes, Ingress `/api` should route to `backend-service:8000`.
- Test with `curl /api/health`.

### Problem: standalone `kubectl` is not installed
**Fix:** this project does not require standalone `kubectl` for scripts. Install/start Minikube and run the project scripts; they automatically fall back to `minikube kubectl --` when `kubectl` is unavailable. Do not depend on interactive shell aliases inside scripts.

### Problem: metrics command shows metrics unavailable
**Fix:**
- enable metrics-server:
  ```bash
  minikube addons enable metrics-server
  ```
- wait and retry.

### Problem: `bookstore.local` does not resolve
**Fix:**
- check `minikube ip`
- add hosts entry
- verify ingress addon
- use Host header if needed:
  ```bash
  curl -H "Host: bookstore.local" http://<minikube-ip>/api/health
  ```

### Problem: HPA shows `<unknown>`
**Fix:**
- check metrics-server
- check backend CPU requests
- wait for metrics to populate.

### Problem: `postgres-init` Job fails
**Fix:**
- inspect:
  ```bash
  minikube kubectl -- logs job/postgres-init -n bookstore
  ```
- verify `postgres-init-sql` ConfigMap exists
- verify `postgres-service` is reachable
- verify Secret contains `DB_PASSWORD`

---

## 9. Evidence Collection for Final Report

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

## 10. Current Runtime Status

- The project contains deployment and testing support files for Docker Compose and Kubernetes.
- Runtime verification should be performed locally in your environment.
- Do not claim test results until commands are actually executed.
- `report/final_report.md` contains placeholders that should be filled with real screenshots and outputs.

> This README is a practical deployment/test guide and intentionally separates **expected results** from actual runtime outcomes.
