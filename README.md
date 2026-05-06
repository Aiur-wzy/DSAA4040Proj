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

## 6. Docker Compose Local Check

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

## 7. Evidence Collection for Final Report

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

## 8. Current Runtime Status

- The project contains deployment and testing support files for Docker Compose and Kubernetes.
- Runtime verification should be performed locally in your environment.
- Do not claim test results until commands are actually executed.
- `report/final_report.md` contains placeholders that should be filled with real screenshots and outputs.

> This README is a practical deployment/test guide and intentionally separates **expected results** from actual runtime outcomes.
