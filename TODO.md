# TODO / Verification Plan

This checklist replaces the old early-stage TODO and is aligned with the project proposal in
`DSAD4040_Proj_Proposal.pdf` plus the current repository implementation.

Status labels:

- `[x]` Completed / implemented in the repository.
- `[~]` Needs runtime verification or final demo evidence.
- `[ ]` Pending implementation work.
- `[!]` Known limitation / future work.

## Proposal Alignment Summary

The proposal requires a cloud-native online bookstore with a frontend, backend API, and
relational database; book browsing/search; shopping cart management; order placement with
persistent data and correctness; containerization; Kubernetes Deployment/Service,
ConfigMap, Secret, Ingress, autoscaling, health checks, basic monitoring, and lightweight
performance testing; plus README/report/demo deliverables.

Repository status at this update:

- [x] Three-tier bookstore architecture is implemented.
  Evidence: `frontend/`, `backend/app/`, `database/`, `docker-compose.yml`, and `k8s/`.
- [x] Kubernetes backend has evolved from one backend Deployment into split public, admin,
  and monitoring Deployments/Services.
  Evidence: `k8s/public-backend-deployment.yaml`, `k8s/admin-backend-deployment.yaml`,
  `k8s/monitoring-backend-deployment.yaml`, and matching Service manifests.
- [x] HPA now targets `Deployment/public-backend` through `public-backend-hpa`.
  Evidence: `k8s/hpa.yaml`.
- [x] Kubernetes monitoring access is isolated to `monitoring-backend` through dedicated
  read-only RBAC.
  Evidence: `k8s/monitoring-backend-rbac.yaml`.
- [~] Final report/demo evidence still needs to be captured from a live Minikube run.
  Verify with the commands in [Final Runtime Verification](#final-runtime-verification).

## Core Bookstore Functionality

- [x] Book browsing and search are implemented.
  Evidence: `backend/app/routes/books.py`, `frontend/src/components/BookList.jsx`.
  Verify with: `BASE_URL=http://$(minikube ip):30080 ./scripts/test-api.sh`.
- [x] Shopping cart add/update/delete/view flow is implemented.
  Evidence: `backend/app/routes/cart.py`, `frontend/src/components/Cart.jsx`.
  Verify with: `BASE_URL=http://$(minikube ip):30080 ./scripts/test-api.sh`.
- [x] Order placement and order history are implemented.
  Evidence: `backend/app/routes/orders.py`, `frontend/src/components/OrderHistory.jsx`.
  Verify with: `BASE_URL=http://$(minikube ip):30080 ./scripts/test-api.sh`.
- [!] This is a course-demo bookstore, not a production commerce system.
  Future work: real authentication, user accounts, payment, tax, shipping, email, and fraud
  workflows.

## Database Design and Transaction Correctness

- [x] PostgreSQL schema and constraints are implemented.
  Evidence: `database/schema.sql`.
- [x] Seed data is implemented.
  Evidence: `database/seed.sql`.
- [x] SQL transaction demo for order placement exists.
  Evidence: `database/place_order.sql`.
- [x] Kubernetes database initialization is implemented as an init Job, not a manual primary
  setup path.
  Evidence: `k8s/postgres-init-job.yaml`.
- [x] Docker Compose initializes schema and seed automatically through PostgreSQL
  entrypoint mounts.
  Evidence: `docker-compose.yml`.
- [~] Live transaction behavior should be verified before the final demo.
  Verify with: `./scripts/test-api.sh` after starting Docker Compose or Kubernetes.

## Backend API

- [x] FastAPI application is implemented with route registration controlled by
  `BACKEND_MODE`.
  Evidence: `backend/app/main.py`.
- [x] Public APIs are implemented for health, books, cart, and orders.
  Evidence: `backend/app/routes/health.py`, `backend/app/routes/books.py`,
  `backend/app/routes/cart.py`, `backend/app/routes/orders.py`.
- [x] Admin catalog APIs are implemented.
  Evidence: `backend/app/routes/admin_books.py`.
  Verify with: `BASE_URL=http://$(minikube ip):30080 ./scripts/test-admin-api.sh`.
- [x] Kubernetes status API exists at `GET /api/admin/cluster/status`.
  Evidence: `backend/app/routes/cluster_status.py`.
  Verify with: `curl -s http://$(minikube ip):30080/api/admin/cluster/status | python3 -m json.tool`.
- [!] Admin APIs are intentionally unauthenticated for the demo.
  Future work: production authentication, authorization, audit logs, and stricter admin RBAC.

## Frontend UI

- [x] React/Vite storefront is implemented.
  Evidence: `frontend/src/App.jsx`, `frontend/src/components/BookList.jsx`,
  `frontend/src/components/Cart.jsx`, `frontend/src/components/OrderHistory.jsx`.
- [x] Admin Demo page is implemented.
  Evidence: `frontend/src/components/AdminBooks.jsx`.
- [x] Monitoring Dashboard page is implemented.
  Evidence: `frontend/src/components/MonitoringDashboard.jsx`.
- [x] Frontend Nginx mirrors Kubernetes route splitting for NodePort/public demo paths.
  Evidence: `frontend/nginx.conf`.
- [~] Final browser screenshots should be captured for Store, Admin Demo, Monitoring
  Dashboard, and public demo exposure.

## Docker and Docker Compose

- [x] Backend Dockerfile is implemented.
  Evidence: `backend/Dockerfile`.
- [x] Frontend Dockerfile is implemented.
  Evidence: `frontend/Dockerfile`.
- [x] Docker Compose workflow is implemented for `db`, `backend`, and `frontend`.
  Evidence: `docker-compose.yml`, `scripts/compose-up.sh`, `scripts/compose-down.sh`,
  `scripts/compose-status.sh`, `scripts/compose-logs.sh`.
- [~] Compose should be smoke-tested before submission if the local environment has Docker.
  Verify with: `./scripts/compose-up.sh`, then `./scripts/test-api.sh` and
  `BASE_URL=http://localhost:8000 ./scripts/test-admin-api.sh`.

## Kubernetes Deployment

- [x] Namespace, PostgreSQL, frontend, and split backend Kubernetes manifests are
  implemented.
  Evidence: `k8s/namespace.yaml`, `k8s/postgres-deployment.yaml`,
  `k8s/frontend-deployment.yaml`, `k8s/public-backend-deployment.yaml`,
  `k8s/admin-backend-deployment.yaml`, `k8s/monitoring-backend-deployment.yaml`.
- [x] Public backend Service is implemented.
  Evidence: `k8s/public-backend-service.yaml`.
- [x] Admin backend Service is implemented.
  Evidence: `k8s/admin-backend-service.yaml`.
- [x] Monitoring backend Service is implemented.
  Evidence: `k8s/monitoring-backend-service.yaml`.
- [x] Frontend NodePort Service is implemented for local/demo access.
  Evidence: `k8s/frontend-service.yaml`.
- [~] Final Kubernetes runtime state should be captured.
  Verify with: `kubectl get deploy,svc,hpa,ingress -n bookstore`.

## ConfigMap, Secret, and Persistent Storage

- [x] Non-secret configuration is stored in a ConfigMap.
  Evidence: `k8s/configmap.yaml`.
- [x] Demo database credentials are stored in a Kubernetes Secret.
  Evidence: `k8s/secret.yaml`.
- [x] PostgreSQL persistent storage is implemented with a PVC.
  Evidence: `k8s/postgres-deployment.yaml`.
- [!] Secret usage is demo-level only.
  Future work: external secret management, rotation, environment-specific credentials, and
  sealed/encrypted secret workflows.

## Ingress Routing and Public Demo Exposure

- [x] Kubernetes Ingress path routing is implemented:
  - `/api/admin/cluster` -> `monitoring-backend-service`
  - `/api/admin` -> `admin-backend-service`
  - `/api` -> `public-backend-service`
  - `/` -> `frontend-service`
  Evidence: `k8s/ingress.yaml`.
- [x] Ingress repair/check script is implemented.
  Evidence: `scripts/k8s-fix-ingress.sh`.
- [x] Public demo exposure script is implemented.
  Evidence: `scripts/k8s-expose-demo.sh`.
- [~] Ingress and public demo routes need live evidence.
  Verify with the Ingress and public exposure commands below.
- [!] Public iptables/port exposure is demo-only.
  Future work: cloud LoadBalancer, TLS, DNS, and production ingress hardening.

## HPA Autoscaling and Metrics Server

- [x] HPA is implemented for `public-backend` with min/max replicas.
  Evidence: `k8s/hpa.yaml`.
- [x] metrics-server repair/check script exists.
  Evidence: `scripts/k8s-fix-metrics-server.sh`.
- [x] Repeatable HPA demo script exists.
  Evidence: `scripts/k8s-hpa-demo.sh`.
- [~] HPA before/under-load/after-load evidence still needs to be captured from a live
  Minikube run.
  Verify with: `./scripts/k8s-hpa-demo.sh`.
- [~] metrics-server working evidence still needs to be captured.
  Verify with: `./scripts/k8s-fix-metrics-server.sh` and `kubectl top pods -n bookstore`.

## Monitoring Dashboard and Admin Demo

- [x] Monitoring backend exposes public-backend Deployment, HPA, Pod, and metrics status.
  Evidence: `backend/app/routes/cluster_status.py`.
- [x] Monitoring backend uses a dedicated read-only ServiceAccount/Role/RoleBinding.
  Evidence: `k8s/monitoring-backend-rbac.yaml`.
- [x] Monitoring Dashboard is implemented in the frontend.
  Evidence: `frontend/src/components/MonitoringDashboard.jsx`.
- [x] Admin Demo frontend and backend routes are implemented.
  Evidence: `frontend/src/components/AdminBooks.jsx`, `backend/app/routes/admin_books.py`.
- [!] Monitoring Dashboard is lightweight and frontend-history based, not a Prometheus or
  Grafana deployment.
  Future work: Prometheus, Grafana, alerting, persistent metrics, and SLO dashboards.

## Testing, Verification, and Documentation

- [x] API smoke test script is implemented.
  Evidence: `scripts/test-api.sh`.
- [x] Admin API smoke test script is implemented.
  Evidence: `scripts/test-admin-api.sh`.
- [x] Kubernetes full update script is implemented.
  Evidence: `scripts/k8s-full-update.sh`.
- [x] Kubernetes status/test helper scripts are implemented.
  Evidence: `scripts/k8s-status.sh`, `scripts/k8s-test-local.sh`, `scripts/monitor-k8s.sh`.
- [x] Demo and architecture documentation exists.
  Evidence: `README.md`, `k8s/README.md`, `docs/demo_manual.md`,
  `docs/architecture_and_defense_notes.md`.
- [~] Final report evidence should be copied into `report/final_report.md` before
  submission.

## Final Runtime Verification

Run these commands from the repository root when Minikube is available. Do not run the heavy
Kubernetes scripts during simple documentation edits unless a live cluster is intentionally
being tested.

```bash
./scripts/k8s-full-update.sh

BASE_URL=http://$(minikube ip):30080 ./scripts/test-api.sh

BASE_URL=http://$(minikube ip):30080 ./scripts/test-admin-api.sh

curl -s http://$(minikube ip):30080/api/admin/cluster/status | python3 -m json.tool

./scripts/k8s-fix-metrics-server.sh

./scripts/k8s-fix-ingress.sh

./scripts/k8s-hpa-demo.sh

PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh

curl -i -H "Host: bookstore.local" http://$(minikube ip)/
curl -i -H "Host: bookstore.local" http://$(minikube ip)/api/books
curl -i -H "Host: bookstore.local" http://$(minikube ip)/api/admin/cluster/status
```

## Final Screenshot / Evidence Checklist

- [~] Store page screenshot.
- [~] Admin page screenshot.
- [~] Monitoring Dashboard screenshot.
- [~] `kubectl get deploy,svc,hpa,ingress -n bookstore` output.
- [~] Ingress route `curl` output.
- [~] HPA before-load, under-load, and after-load output.
- [~] `public-backend` scaling evidence.
- [~] metrics-server working evidence.
- [~] ingress-nginx-controller running evidence.
- [~] Public browser demo screenshot.
- [~] API smoke test output.

## Known Limitations / Future Work

- [!] Admin Demo is unauthenticated and intended for controlled course-demo use only.
- [!] Monitoring Dashboard is lightweight and frontend-history only, not Prometheus/Grafana.
- [!] The target runtime is a Minikube single-node demo environment, not a multi-node
  production cluster.
- [!] Public iptables/port exposure is demo-only and should be replaced with a cloud
  LoadBalancer or production ingress setup for real deployment.
- [!] Kubernetes Secret usage is demo-level, not production-grade external secret management.
- [!] The bookstore does not include real payment, shipping, production auth, or account
  management.
- [!] Future improvements: CI/CD, TLS, cloud LoadBalancer, Prometheus/Grafana, production
  auth/RBAC, NetworkPolicy, backup/restore, and stronger database migration tooling.

## Optional Multi-Node and Failure Experiments

- [~] Minikube multi-node experiment runtime verification.
  Evidence checklist: `kubectl get nodes -o wide`, `MINIKUBE_PROFILE=bookstore-multinode ./scripts/k8s-multinode-verify.sh`.
- [~] public-backend pod distribution evidence across nodes.
  Evidence checklist: `kubectl get pods -n bookstore -l app=public-backend -o wide`.
- [~] Monitoring Dashboard node column screenshot.
  Evidence checklist: browser screenshot showing Node and Pod IP columns.
- [~] HPA scale-out evidence in the multi-node profile.
  Evidence checklist: `MINIKUBE_PROFILE=bookstore-multinode MULTINODE_SCALE_TEST=1 ./scripts/k8s-multinode-verify.sh`.
- [~] Order consistency stress/edge-case test evidence.
  Evidence checklist: `./scripts/test-order-consistency.sh` output showing 409 insufficient stock and non-negative final stock.
- [~] PostgreSQL Pod recovery evidence.
  Evidence checklist: `MINIKUBE_PROFILE=bookstore-multinode ./scripts/k8s-db-recovery-test.sh` output showing PVC-backed data after Pod restart.
- [~] Safe stateless node cordon/failure evidence.
  Evidence checklist: `MINIKUBE_PROFILE=bookstore-multinode ./scripts/k8s-node-failure-test.sh` output showing API availability and uncordon cleanup.
- [!] PostgreSQL HA remains future work, not implemented in this demo.
  Future work: managed PostgreSQL or PostgreSQL Operator with failover, backup/restore, and read replicas if needed.
- [!] Real multi-VM Kubernetes deployment remains future work.
  Future work: kubeadm/k3s/managed Kubernetes, production Ingress/LoadBalancer, external registry, CSI storage, TLS, NetworkPolicy, and CI/CD.
