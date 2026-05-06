# Implementation Gap Analysis

## 1. Current Implementation Summary

The repository implements a functional three-tier DSAA4040 cloud-native online bookstore baseline: a React/Vite frontend served by Nginx, a FastAPI backend, and PostgreSQL storage. Core demo flows exist for catalog browsing/search, cart operations, order placement, order history, stock deduction, Docker Compose deployment, and Minikube/Kubernetes deployment. The main remaining work is hardening final-demo workflows, collecting runtime evidence, improving initialization safety, validating autoscaling/Ingress in the target environment, and documenting reliable public exposure using the verified iptables DNAT approach with Docker-aware forwarding rules.

## 2. Completed Features

### Application Features

- [x] Book catalog display and search/filter implemented  
  Evidence: `backend/app/routes/books.py` (`GET /api/books?search=...`), `frontend/src/api.js`, `frontend/src/components/BookList.jsx`
- [x] Cart add/update/remove/read operations implemented for a demo user  
  Evidence: `backend/app/routes/cart.py`, `backend/app/schemas.py`, `frontend/src/components/Cart.jsx`
- [x] Place-order flow creates order records, order items, deducts stock, and clears cart  
  Evidence: `backend/app/routes/orders.py`, `database/place_order.sql`, `frontend/src/App.jsx`
- [x] Order history display implemented  
  Evidence: `backend/app/routes/orders.py` (`GET /api/orders`), `frontend/src/components/OrderHistory.jsx`

### Backend API

- [x] FastAPI app registers all required routers under `/api`  
  Evidence: `backend/app/main.py`
- [x] Backend health endpoint implemented  
  Evidence: `backend/app/routes/health.py`, endpoint `/api/health`
- [x] Database health endpoint implemented  
  Evidence: `backend/app/routes/health.py`, endpoint `/api/health/db`
- [x] PostgreSQL connection uses environment-based configuration  
  Evidence: `backend/app/db.py`, `docker-compose.yml`, `k8s/configmap.yaml`, `k8s/secret.yaml`
- [x] Transactional order placement uses row locking and commits only after all order steps succeed  
  Evidence: `backend/app/routes/orders.py` (`FOR UPDATE OF b`, stock checks, insert/update/delete in one connection transaction)

### Frontend UI

- [x] React UI calls backend APIs for health, catalog, cart, orders, and place order  
  Evidence: `frontend/src/api.js`, `frontend/src/App.jsx`
- [x] Frontend has separate components for book list, cart, order history, and status messages  
  Evidence: `frontend/src/components/BookList.jsx`, `frontend/src/components/Cart.jsx`, `frontend/src/components/OrderHistory.jsx`, `frontend/src/components/StatusMessage.jsx`
- [x] Nginx serves the SPA and proxies `/api/` to the backend service name  
  Evidence: `frontend/nginx.conf`

### Database

- [x] PostgreSQL schema contains `books`, `carts`, `orders`, and `order_items` tables  
  Evidence: `database/schema.sql`
- [x] Seed catalog data exists  
  Evidence: `database/seed.sql`
- [x] SQL-level order transaction script exists  
  Evidence: `database/place_order.sql`
- [x] Basic SQL validation script exists  
  Evidence: `database/test.sql`

### Docker Compose

- [x] Full-stack local Compose deployment exists with db, backend, and frontend services  
  Evidence: `docker-compose.yml`
- [x] Backend and frontend images are built with stable local tags used by Kubernetes too  
  Evidence: `docker-compose.yml`, `backend/Dockerfile`, `frontend/Dockerfile`
- [x] Compose database initialization mounts schema and seed SQL into `/docker-entrypoint-initdb.d/`  
  Evidence: `docker-compose.yml`
- [x] Compose backend waits for PostgreSQL health before starting  
  Evidence: `docker-compose.yml`

### Kubernetes

- [x] Namespace manifest exists  
  Evidence: `k8s/namespace.yaml`
- [x] ConfigMap and Secret manifests exist  
  Evidence: `k8s/configmap.yaml`, `k8s/secret.yaml`
- [x] PostgreSQL Deployment, PVC, and Service exist  
  Evidence: `k8s/postgres-deployment.yaml`, `k8s/postgres-service.yaml`
- [x] Backend Deployment and Service exist  
  Evidence: `k8s/backend-deployment.yaml`, `k8s/backend-service.yaml`
- [x] Frontend Deployment and NodePort Service exist  
  Evidence: `k8s/frontend-deployment.yaml`, `k8s/frontend-service.yaml`
- [x] Ingress manifest exists for `bookstore.local` and `/api` routing  
  Evidence: `k8s/ingress.yaml`
- [x] Backend HPA manifest exists  
  Evidence: `k8s/hpa.yaml`
- [x] PostgreSQL init Job exists and uses a SQL ConfigMap created by the deploy script  
  Evidence: `k8s/postgres-init-job.yaml`, `scripts/k8s-rebuild-and-deploy.sh`
- [x] Backend and frontend readiness/liveness probes exist  
  Evidence: `k8s/backend-deployment.yaml`, `k8s/frontend-deployment.yaml`
- [x] PostgreSQL readiness probe exists  
  Evidence: `k8s/postgres-deployment.yaml`

### Scripts and Testing

- [x] Docker Compose helper scripts exist  
  Evidence: `scripts/compose-up.sh`, `scripts/compose-down.sh`, `scripts/compose-status.sh`, `scripts/compose-logs.sh`
- [x] API smoke-test script covers health, books, cart, order placement, and orders  
  Evidence: `scripts/test-api.sh`
- [x] Kubernetes rebuild/load/apply/restart workflow exists and handles stale local images by loading images and restarting deployments  
  Evidence: `scripts/k8s-rebuild-and-deploy.sh`
- [x] Kubernetes NodePort smoke-test script exists  
  Evidence: `scripts/k8s-test-local.sh`
- [x] Kubernetes status, cleanup, reset, monitoring, and performance helper scripts exist  
  Evidence: `scripts/k8s-status.sh`, `scripts/k8s-cleanup.sh`, `scripts/k8s-reset-local.sh`, `scripts/monitor-k8s.sh`, `scripts/perf-test.sh`
- [x] Shared Kubernetes helper falls back to `minikube kubectl --` when standalone `kubectl` is unavailable  
  Evidence: `scripts/lib/k8s.sh`

### Documentation

- [x] Main README explains architecture, quick-start workflows, Minikube image loading, stale-image restarts, NodePort testing, and external demo notes  
  Evidence: `README.md`
- [x] Kubernetes README describes manifests and operational commands  
  Evidence: `k8s/README.md`
- [x] Backend, frontend, and database README files summarize component usage  
  Evidence: `backend/README.md`, `frontend/README.md`, `database/README.md`
- [x] Final report scaffold exists  
  Evidence: `report/final_report.md`

## 3. Partially Completed Features

- [x] External browser demo exposure
  - What exists now: `scripts/k8s-expose-demo.sh` validates the NodePort service and inserts verified iptables DNAT/MASQUERADE, bidirectional `FORWARD`, and bidirectional `DOCKER-USER` rules.
  - Remaining evidence work: run the script on the target cloud server, test from another machine, and save browser/curl, tcpdump, and iptables counter output.
  - Documented command:
    ```bash
    PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh
    ```
  - Files updated: `scripts/k8s-expose-demo.sh`, `README.md`, `k8s/README.md`.

- [ ] Ingress usability in Minikube/cloud demo  
  - What exists now: `k8s/ingress.yaml` routes `bookstore.local` to frontend and `/api` to backend.
  - What is missing: runtime proof that the ingress addon is enabled, host DNS/`/etc/hosts` is configured, and access works from the final demo environment.
  - Files needing changes: `README.md`, `k8s/README.md`, `report/final_report.md`.

- [ ] HPA is declared but not proven under load  
  - What exists now: `k8s/hpa.yaml` targets backend CPU utilization; backend resources are set in `k8s/backend-deployment.yaml`.
  - What is missing: metrics-server enablement and load-test evidence showing HPA metrics or scaling behavior.
  - Files needing changes: `report/final_report.md`; optionally `scripts/perf-test.sh` or a new HPA verification script.

- [ ] Database initialization is automated but reset behavior is risky  
  - What exists now: Compose init mounts `schema.sql` and `seed.sql`; Kubernetes init Job runs SQL from `postgres-init-sql` ConfigMap.
  - What is missing: `database/schema.sql` starts with `DROP TABLE IF EXISTS`, so re-running the Kubernetes init Job with `FORCE_POSTGRES_INIT=1` can delete orders/cart data. Seed SQL is not idempotent if schema is changed to preserve tables.
  - Files needing changes: `database/schema.sql`, `database/seed.sql`, `k8s/postgres-init-job.yaml`, `scripts/k8s-rebuild-and-deploy.sh`, docs.

- [ ] Testing exists but final evidence is not collected  
  - What exists now: scripts exist for API, Kubernetes NodePort, monitoring, and performance.
  - What is missing: captured command outputs, screenshots, latency/performance summary, HPA output, and Ingress/public demo proof in the report.
  - Files needing changes: `report/final_report.md` and possibly an `evidence/` directory.

- [ ] Frontend API routing works for current Compose/Kubernetes paths but is tightly coupled to service aliases  
  - What exists now: browser calls relative `/api/...`; Nginx proxies to `backend-service:8000`; Compose gives backend the `backend-service` network alias.
  - What is missing: clearer documentation of why this works in both Compose and Kubernetes, and a dev-mode fallback using `VITE_API_BASE_URL` or Vite proxy if running frontend outside Nginx.
  - Files needing changes: `frontend/README.md`, `README.md`, optionally `frontend/vite.config.js`.

## 4. Missing or Weak Features Compared with Proposal

| Area | Expected in Proposal | Current Status | Gap | Recommended Fix |
|------|----------------------|----------------|-----|-----------------|
| External demo exposure | Browser-accessible demo from cloud server | Verified iptables DNAT script exists | Needs final runtime evidence from target cloud server | Run `scripts/k8s-expose-demo.sh`, test from another machine, and save tcpdump/counter evidence |
| Ingress usability | Working Ingress route for frontend and API | Manifest exists for `bookstore.local` | Needs addon/hosts setup and runtime proof | Enable ingress addon, test `Host: bookstore.local`, add evidence to report |
| HPA real functionality | Autoscaling under load | HPA manifest exists | Needs metrics-server and observed metrics/scaling output | Add metrics-server step and capture `get hpa` before/during load |
| Metrics-server dependency | Clear prerequisite for HPA/top commands | Mentioned in docs/scripts | Not enforced or verified by deploy/test scripts | Add a preflight warning/check in `monitor-k8s.sh` or HPA verification docs |
| Performance testing | Load/performance test evidence | `scripts/perf-test.sh` exists with `hey` fallback | No saved results or analysis | Run against Compose and/or NodePort; summarize latency, error rate, throughput |
| Monitoring/dashboard | Basic monitoring/dashboard evidence | `monitor-k8s.sh` prints pods/HPA/top | No dashboard or screenshots | Use `minikube dashboard` or command output screenshots in report |
| DB initialization repeatability | Safe, repeatable DB initialization | Init Job exists; Compose init works on fresh volume | `schema.sql` drops tables; forced rerun clears data | Split destructive reset from safe migration/seed, or document reset-only behavior clearly |
| SQL reset/init safety | Avoid accidental data loss | Destructive schema by default | Unsafe for repeated final-demo initialization | Create `schema-reset.sql` for destructive reset and make default schema idempotent |
| Frontend API proxy | Works in Compose and Kubernetes | Nginx proxy plus Compose alias works | Dev server path still needs `VITE_API_BASE_URL`; behavior should be documented | Document all modes and optionally add Vite dev proxy |
| Script kubectl behavior | Use standalone `kubectl` or `minikube kubectl --` correctly | Shared helper supports fallback | README still contains at least one plain `kubectl get pods` example | Standardize docs/scripts on helper or `minikube kubectl --` |
| Stale image handling | Avoid stale local images in Minikube | Rebuild script loads images and restarts deployments | Manual workflow can still forget this | Keep using `scripts/k8s-rebuild-and-deploy.sh`; add evidence checklist |
| Public exposure reliability | Repeatable public demo URL | Script uses Docker-aware iptables insertion and cleanup | Needs final runtime proof | Capture external curl/browser result plus iptables counters |
| Final report evidence | Completed final report | Scaffold only | Most sections are TODO | Fill `report/final_report.md` with screenshots and command outputs |
| Automated tests | Repeatable verification | Smoke scripts only | No pytest/unit tests or CI | Add lightweight backend API tests with mocked/test DB or Compose-based CI notes |

## 5. What Still Needs to Be Improved Before Final Submission

- [x] Update external exposure workflow to use the verified Docker-aware iptables DNAT method; keep `socat` only as an optional fallback/debugging method.
- [ ] Run and record Docker Compose smoke tests:
  - [ ] `docker compose up --build`
  - [ ] `./scripts/test-api.sh`
  - [ ] frontend browser screenshot at `http://localhost:8080`
- [ ] Run and record Kubernetes smoke tests:
  - [ ] `./scripts/k8s-rebuild-and-deploy.sh`
  - [ ] `./scripts/k8s-test-local.sh`
  - [ ] `./scripts/k8s-status.sh`
- [ ] Verify and document Ingress with `bookstore.local` or explicitly state NodePort is the main demo path.
- [ ] Enable metrics-server and collect HPA/`kubectl top` output.
- [ ] Run `scripts/perf-test.sh` against a real target URL and summarize results.
- [ ] Fill `report/final_report.md` with actual evidence instead of TODO placeholders.
- [ ] Make database initialization safer or clearly document that schema/init scripts are destructive reset scripts.
- [ ] Review README command snippets and replace remaining plain `kubectl` commands with `minikube kubectl --` or script-based equivalents.

## 6. Practical Next-Step Priorities

1. **Capture final demo exposure evidence first.** Run `PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh`, test from another machine, and save browser/curl, tcpdump, and iptables counter output.
2. **Generate final evidence.** Run Compose and Kubernetes smoke scripts, save terminal output, and take frontend/API screenshots.
3. **Validate HPA honestly.** Enable metrics-server, run load test, and document whether scaling actually occurs or only HPA creation is demonstrated.
4. **Harden database init story.** Decide whether the project uses destructive reset scripts for demos or idempotent initialization for repeatable deployments; document the choice clearly.
5. **Complete final report.** Replace scaffold TODOs with architecture, endpoint table, manifests summary, evidence, problems/solutions, and limitations.
6. **Polish docs and commands.** Keep the Minikube workflow consistent: build images, load images, apply manifests, restart deployments, test NodePort, then expose with the verified iptables script.
