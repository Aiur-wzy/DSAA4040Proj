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
docker-compose.yaml
k8s/
scripts/
report/
```

- `database/`: PostgreSQL SQL files (`schema.sql`, `seed.sql`, `test.sql`, `place_order.sql`) for schema setup, seed data, and SQL validation/transaction scripts.
- `backend/`: FastAPI backend service source and backend Dockerfile.
- `frontend/`: React/Vite frontend served by Nginx, including frontend Dockerfile and Nginx config.
- `docker-compose.yaml`: local full-stack orchestration for `db`, `backend`, and `frontend`.
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
- kubectl
- optional: `hey` (for performance testing)

Verify tools:

```bash
docker --version
docker compose version
minikube version
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

### 6.1 Start Minikube

```bash
minikube start
kubectl get nodes
```

### 6.2 Build images inside Minikube

Because manifests use `imagePullPolicy: IfNotPresent` with local image names, build images inside Minikube's Docker environment:

```bash
eval $(minikube docker-env)
docker build -t bookstore-backend:latest ./backend
docker build -t bookstore-frontend:latest ./frontend
docker images | grep bookstore
```

> Windows PowerShell uses a different environment setup command. Run `minikube docker-env` and follow the PowerShell output.

### 6.3 Apply base Kubernetes manifests

```bash
kubectl apply -f k8s/
```

`kubectl apply` creates or updates resources from YAML files.

### 6.4 Inspect resources

```bash
kubectl get all -n bookstore
kubectl get pvc -n bookstore
kubectl get svc -n bookstore
kubectl get ingress -n bookstore
kubectl get hpa -n bookstore
```

or

```bash
./scripts/k8s-status.sh
```

### 6.5 Kubernetes database initialization

PostgreSQL starts via Deployment/PVC, but schema + seed data require the `postgres-init` Job.

```bash
kubectl create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n bookstore

kubectl apply -f k8s/postgres-init-job.yaml

kubectl get jobs -n bookstore
kubectl logs job/postgres-init -n bookstore
```

Verify database:

```bash
kubectl get pods -n bookstore -l app=postgres
```

Then:

```bash
kubectl exec -it -n bookstore <postgres-pod-name> -- psql -U bookstore -d bookstore -c "\dt"
kubectl exec -it -n bookstore <postgres-pod-name> -- psql -U bookstore -d bookstore -c "SELECT COUNT(*) FROM books;"
```

Expected result:
- four tables exist
- `books` count is 8

> Warning: `schema.sql` drops and recreates tables. Re-running the Job can reset demo data.

### 6.6 Test backend service with port-forward

```bash
kubectl port-forward -n bookstore service/backend-service 8000:8000
```

In another terminal:

```bash
curl http://localhost:8000/api/health
curl http://localhost:8000/api/health/db
curl http://localhost:8000/api/books
```

### 6.7 Enable Ingress

```bash
minikube addons enable ingress
```

Get Minikube IP:

```bash
minikube ip
```

Add hosts entry:

```text
<minikube-ip> bookstore.local
```

Windows hosts file path:

```text
C:\Windows\System32\drivers\etc\hosts
```

### 6.8 Test Ingress

```bash
curl http://bookstore.local/api/health
curl http://bookstore.local/api/books
```

Open in browser:

```text
http://bookstore.local
```

Run smoke test through Ingress:

```bash
BASE_URL=http://bookstore.local ./scripts/test-api.sh
```

### 6.9 Enable metrics-server and check HPA

```bash
minikube addons enable metrics-server

kubectl top nodes
kubectl top pods -n bookstore
kubectl get hpa -n bookstore
```

or

```bash
./scripts/monitor-k8s.sh
```

Metrics may take time to appear after enabling metrics-server.

### 6.10 Run performance test

```bash
TARGET_URL=http://bookstore.local/api/books ./scripts/perf-test.sh
```

Stronger load example:

```bash
TARGET_URL=http://bookstore.local/api/books DURATION=2m CONCURRENCY=50 ./scripts/perf-test.sh
```

Observe scaling:

```bash
kubectl get hpa -n bookstore -w
kubectl get pods -n bookstore -w
```

### 6.11 Cleanup Kubernetes resources

```bash
kubectl delete -f k8s/
```

or

```bash
./scripts/k8s-cleanup.sh
```

---

## 7. Kubernetes Verification Checklist

- [ ] Minikube starts
- [ ] kubectl can access cluster
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
- [ ] backend-service works through port-forward
- [ ] ingress addon enabled
- [ ] `bookstore.local` routes `/` to frontend
- [ ] `bookstore.local` routes `/api` to backend
- [ ] smoke test passes through Ingress
- [ ] metrics-server enabled
- [ ] `kubectl top` works
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
- In Compose, backend service name must be `backend`.
- In Kubernetes, Ingress `/api` should route to `backend-service:8000`.
- Test with `curl /api/health`.

### Problem: `kubectl top` shows metrics unavailable
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
  kubectl logs job/postgres-init -n bookstore
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
- `kubectl get all -n bookstore`
- `kubectl get pvc -n bookstore`
- `kubectl get ingress -n bookstore`
- `kubectl get hpa -n bookstore`
- `postgres-init` Job logs
- `bookstore.local` frontend page
- smoke test through Ingress

### Monitoring/performance evidence
- `kubectl top pods -n bookstore`
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
