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
- optional: `hey` (for performance testing)

Use `minikube kubectl --` for Kubernetes commands so the guide works on Minikube-only servers where standalone `kubectl` is not installed. Do not rely on interactive shell aliases inside scripts; Bash scripts do not reliably inherit aliases such as `alias kubectl='minikube kubectl --'`.

Verify tools:

```bash
docker --version
docker compose version
minikube version
hey -h
```

> `hey` is optional. Performance scripts may provide fallback behavior if `hey` is not installed.

---

## 4. Quick Start: Updating an Existing Minikube Deployment

This is the primary workflow for repeated code/config changes. Do **not** assume each run starts from a clean cluster: Kubernetes can keep running old Pods and old local images even after files change.

Main workflow:

```text
edit code/config
  -> docker compose build on host Docker
  -> minikube image load
  -> verify image inside Minikube
  -> kubectl apply YAML
  -> rollout restart deployments
  -> test NodePort
  -> expose browser demo
```



All Kubernetes commands below use `minikube kubectl --` so they work on servers without standalone `kubectl`.



```bash
chmod +x scripts/*.sh
```


### 4.1 Recommended Update Flow

Run this after frontend/backend/config changes:

```bash
# 1) Build fresh images on the host Docker daemon.
eval $(minikube docker-env -u)
docker compose build backend frontend

# 2) Verify the host frontend image contains the Kubernetes backend proxy.
docker run --rm bookstore-frontend:latest cat /etc/nginx/conf.d/default.conf
# Expected line:
# proxy_pass http://backend-service:8000;

# 3) Load fresh images into Minikube.
minikube image load bookstore-backend:latest
minikube image load bookstore-frontend:latest

# 4) Verify the frontend image inside Minikube too.
eval $(minikube docker-env)
docker run --rm bookstore-frontend:latest cat /etc/nginx/conf.d/default.conf
# Expected line:
# proxy_pass http://backend-service:8000;
eval $(minikube docker-env -u)

# 5) Apply YAML. "unchanged" only means the manifest text did not change.
minikube kubectl -- apply -f k8s/namespace.yaml
minikube kubectl -- apply -f k8s/configmap.yaml
minikube kubectl -- apply -f k8s/secret.yaml
minikube kubectl -- apply -f k8s/postgres-service.yaml
minikube kubectl -- apply -f k8s/postgres-deployment.yaml
minikube kubectl -- apply -f k8s/backend-service.yaml
minikube kubectl -- apply -f k8s/backend-deployment.yaml
minikube kubectl -- apply -f k8s/frontend-service.yaml
minikube kubectl -- apply -f k8s/frontend-deployment.yaml
minikube kubectl -- apply -f k8s/ingress.yaml
minikube kubectl -- apply -f k8s/hpa.yaml

# 6) Force Pods to restart so they use the newly loaded local images.
minikube kubectl -- rollout restart deployment/backend -n bookstore
minikube kubectl -- rollout restart deployment/frontend -n bookstore
minikube kubectl -- rollout status deployment/backend -n bookstore --timeout=180s
minikube kubectl -- rollout status deployment/frontend -n bookstore --timeout=180s

# 7) Test through the Kubernetes NodePort, not Docker Compose localhost ports.
MINIKUBE_IP=$(minikube ip)
curl "http://${MINIKUBE_IP}:30080"
curl "http://${MINIKUBE_IP}:30080/api/health"
curl "http://${MINIKUBE_IP}:30080/api/health/db"
curl "http://${MINIKUBE_IP}:30080/api/books"
```

```bash
#check pods
kubectl get pods -n bookstore -o wide
kubectl get all -n bookstore
```

Important: `minikube kubectl -- apply ...` returning `unchanged` does **not** mean running Pods are using your new image. If the Deployment spec still says `bookstore-frontend:latest` or `bookstore-backend:latest`, Kubernetes may keep existing Pods. Always reload images into Minikube and run `rollout restart` for repeated local-image development.

Shortcut when you want the helper script to do the rebuild/load/apply/restart path:

```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
```

### 4.2 Delete Stale Minikube Images Before Reloading

If Minikube keeps serving an old frontend, remove the stale image from Minikube first, then load the host image again:

```bash
eval $(minikube docker-env)
docker rmi bookstore-frontend:latest || true
eval $(minikube docker-env -u)
minikube image load bookstore-frontend:latest

minikube kubectl -- rollout restart deployment/frontend -n bookstore
minikube kubectl -- rollout status deployment/frontend -n bookstore --timeout=180s
```

Re-check the image contents inside Minikube:

```bash
eval $(minikube docker-env)
docker run --rm bookstore-frontend:latest cat /etc/nginx/conf.d/default.conf
# Expected line:
# proxy_pass http://backend-service:8000;
eval $(minikube docker-env -u)
```

### 4.3 SQL Changes

PostgreSQL SQL files are mounted into the `postgres-init-sql` ConfigMap and executed by the `postgres-init` Job. After editing `database/schema.sql` or `database/seed.sql`, recreate the ConfigMap and rerun the Job:

```bash
minikube kubectl -- create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n bookstore --dry-run=client -o yaml | minikube kubectl -- apply -f -

minikube kubectl -- delete job postgres-init -n bookstore --ignore-not-found
minikube kubectl -- apply -f k8s/postgres-init-job.yaml
minikube kubectl -- wait --for=condition=complete job/postgres-init -n bookstore --timeout=180s
minikube kubectl -- logs job/postgres-init -n bookstore
```

Depending on SQL logic, rerunning the init Job may reset demo data.

### 4.4 Test the NodePort

`frontend-service` is a NodePort service on port `30080`.

```bash
MINIKUBE_IP=$(minikube ip)
curl "http://${MINIKUBE_IP}:30080"
curl "http://${MINIKUBE_IP}:30080/api/health"
curl "http://${MINIKUBE_IP}:30080/api/books"
```

### 4.5 Expose Browser Demo

Forward public host port `3000` to `$(minikube ip):30080`. The helper script adds the required iptables forwarding rules:
```bash
MINIKUBE_IP=$(minikube ip)
nohup sudo socat TCP-LISTEN:3000,fork,reuseaddr,bind=0.0.0.0 TCP:${MINIKUBE_IP}:30080 > socat-demo.log 2>&1 &
```
暴露接口，然后后面的有bug不管了
```bash
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

Manual equivalent:

```bash
MINIKUBE_IP=$(minikube ip)
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A PREROUTING -p tcp --dport 3000 -j DNAT --to-destination "${MINIKUBE_IP}:30080"
sudo iptables -t nat -A POSTROUTING -p tcp -d "${MINIKUBE_IP}" --dport 30080 -j MASQUERADE
sudo iptables -A FORWARD -p tcp -d "${MINIKUBE_IP}" --dport 30080 -j ACCEPT
```

Your cloud firewall/security group must allow inbound TCP `3000`. Then open:

```text
http://<server-public-ip>:3000
```

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

Manual first-time sequence if you are not using the helper script:

```bash
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

minikube kubectl -- apply -f k8s/backend-service.yaml
minikube kubectl -- apply -f k8s/backend-deployment.yaml
minikube kubectl -- apply -f k8s/frontend-service.yaml
minikube kubectl -- apply -f k8s/frontend-deployment.yaml
minikube kubectl -- apply -f k8s/ingress.yaml
minikube kubectl -- apply -f k8s/hpa.yaml
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

Inspect logs when a Compose check fails:

```bash
./scripts/compose-logs.sh
./scripts/compose-logs.sh backend
```

Stop the Compose stack when finished:

```bash
./scripts/compose-down.sh
```

### 6.3 Kubernetes deployment verification

After Minikube is running, use the rebuild/deploy helper for the full local-image Kubernetes workflow:

```bash
./scripts/k8s-rebuild-and-deploy.sh
```

This script checks prerequisites, builds Docker Compose images on the host Docker daemon, verifies `bookstore-backend:latest` and `bookstore-frontend:latest`, loads them into Minikube, creates or updates the `postgres-init-sql` ConfigMap from `database/schema.sql` and `database/seed.sql`, applies the Kubernetes manifests, restarts the backend and frontend deployments, waits for rollout completion, and prints the Minikube NodePort URL.

Then verify the deployed Kubernetes application:

```bash
./scripts/k8s-test-local.sh
```

`k8s-test-local.sh` verifies that Minikube is running, the `bookstore` namespace exists, Pods are `Running` or `Completed`, `frontend-service` is a `NodePort` on port `30080`, and the Minikube NodePort responds successfully for:

- `/`
- `/api/health`
- `/api/health/db`
- `/api/books`

For a detailed Kubernetes resource snapshot, run:

```bash
./scripts/k8s-status.sh
```

`k8s-status.sh` prints Minikube status, Minikube IP, the resolved Kubernetes command mode (`kubectl` or `minikube kubectl --`), all resources in the `bookstore` namespace, Pods, Services, Ingress, HPA, and backend/frontend service endpoints.

### 6.4 Public browser demo verification

To expose the Kubernetes frontend outside the host, run:

```bash
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

The expose script verifies that `frontend-service` is a NodePort service using nodePort `30080`, then adds `iptables` forwarding from the host public TCP port (`PUBLIC_PORT`, default `3000`) to `$(minikube ip):30080`. It only exposes `frontend-service`; it does not publicly expose `backend-service` or `postgres-service`.

After running it, verify the browser demo at:

```text
http://<server-public-ip>:3000
```

Your cloud firewall or security group must allow inbound TCP `3000` or whichever `PUBLIC_PORT` you choose.

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
