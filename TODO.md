# TODO / Final Verification Plan

## Purpose

This document tracks final pre-submission work for the DSAA 4040 Cloud-Native Online Bookstore against:

- project handout/guideline (`DSAA4040_Project_Handout_Original_English.pdf`);
- project proposal (`DSAD4040_Proj_Proposal.pdf`);
- current repository implementation;
- runtime verification evidence from current scripts and docs.

## Status Legend

- [x] Completed and verified
- [~] Implemented but needs final demo/report evidence or polish
- [ ] Pending before submission
- [!] Known limitation / future work

## Requirement Alignment Matrix

| Requirement | Source: Handout / Proposal / Implementation | Current Status | Evidence | Remaining Action |
|---|---|---|---|---|
| Frontend page | Handout Basic + Proposal + Implementation | [x] | `frontend/`, `README.md`, `scripts/test-api.sh` | Capture final report/demo screenshots |
| Backend API | Handout Basic + Proposal + Implementation | [x] | `backend/app/routes/*`, `scripts/test-api.sh`, `scripts/test-admin-api.sh` | Add concise final evidence snippets into report |
| Database | Handout Basic + Proposal + Implementation | [x] | `database/schema.sql`, `database/seed.sql`, `k8s/postgres-init-job.yaml` | Keep final DB correctness summary in report |
| Docker containerization | Handout Basic + Proposal + Implementation | [x] | `backend/Dockerfile`, `frontend/Dockerfile`, `docker-compose.yml` | Re-run compose checklist once before submission |
| Kubernetes Deployment and Service | Handout Basic + Proposal + Implementation | [x] | `k8s/*deployment.yaml`, `k8s/*service.yaml`, `scripts/k8s-test-local.sh` | Paste final `kubectl get` evidence into report |
| Browse/search books | Handout Basic + Proposal + Implementation | [x] | `backend/app/routes/books.py`, `scripts/test-api.sh` | None beyond final report presentation |
| Cart management | Handout Basic + Proposal + Implementation | [x] | `backend/app/routes/cart.py`, `scripts/test-api.sh` | None beyond final report presentation |
| Order placement | Handout Basic + Proposal + Implementation | [x] | `backend/app/routes/orders.py`, `scripts/test-api.sh`, `scripts/test-order-consistency.sh` | Keep idempotency/stock result in report |
| ConfigMap | Handout Standard + Implementation | [x] | `k8s/configmap.yaml` | None |
| Secret | Handout Standard + Implementation | [x] | `k8s/secret.yaml`, `k8s/postgres-ha/app-secret.yaml` | Note demo-only secret scope in limitations |
| Ingress | Handout Standard + Implementation | [x] | `k8s/ingress.yaml`, `scripts/k8s-fix-ingress.sh` | Keep live curl/route proof in final demo appendix |
| Architecture diagram | Handout Standard + Proposal + Docs | [~] | `README.md`, `report/final_report.md`, `docs/distributed_network_flow.md` | Final clean diagram polish in report slides/Overleaf |
| Complete deployment workflow | Handout Standard + Proposal + Implementation | [x] | `scripts/compose-*.sh`, `scripts/k8s-rebuild-and-deploy.sh`, `scripts/k8s-distributed-ha-rebuild-all.sh` | Final pass for README consistency |
| Autoscaling | Handout Advanced + Implementation | [x] | `k8s/hpa.yaml`, `scripts/k8s-hpa-demo.sh`, `scripts/k8s-fix-metrics-server.sh` | Keep scale-out numbers/screenshots in report |
| Basic monitoring/dashboard | Handout Advanced + Implementation | [x] | `backend/app/routes/cluster_status.py`, `frontend/src/components/MonitoringDashboard.jsx` | Emphasize lightweight scope (non-Prometheus) |
| Improved DB schema / API design | Handout Advanced + Proposal + Implementation | [x] | `database/schema.sql`, split public/admin/monitoring backend design | Summarize rationale briefly in final report |
| Small performance test | Handout Advanced + Implementation | [x] | `scripts/perf-test.sh`, `scripts/k8s-hpa-demo.sh` | Include one concise benchmark figure/table |
| Final report/demo | Handout deliverable + Proposal | [~] | `report/final_report.md`, `docs/demo_manual.md` | Final editing, formatting, and live demo playbook polish |

## Completed and Verified

- [x] Three-tier bookstore architecture.
- [x] Docker Compose workflow.
- [x] Kubernetes deployment workflow.
- [x] Split backend deployments (`public-backend`, `admin-backend`, `monitoring-backend`).
- [x] Public bookstore API.
- [x] Admin API.
- [x] Monitoring API (`/api/admin/cluster/status`).
- [x] PostgreSQL schema and seed data.
- [x] Order transaction logic.
- [x] Idempotency-key behavior verified.
- [x] Kubernetes NodePort access verified.
- [x] ConfigMap and Secret.
- [x] HPA declaration and successful runtime scale-out.
- [x] Metrics-server repair workflow.
- [x] CloudNativePG HA mode.
- [x] Three-node PostgreSQL HA placement evidence.
- [x] PostgreSQL failover test.
- [x] Distributed network flow documentation.
- [x] Optional public demo exposure script.
- [x] Fresh-image verification in deployment script/workflow.

## Implemented but Still Needs Final Evidence / Polishing

- [~] Final report polishing.
- [~] Final demo script/playbook.
- [~] Final browser demo access from public IP (only if required by presentation environment).
- [~] Final Overleaf report formatting.
- [~] Final README consistency check after recent workflow changes.
- [~] Optional new experiment: concurrent order stock consistency (`scripts/test-order-consistency.sh` exists; optional rerun for final appendix).
- [ ] Optional new experiment: application-level order after DB failover (`scripts/test-order-after-failover.sh` not found).
- [ ] Optional new experiment: split backend routing identity test (`scripts/test-routing-split.sh` not found).

## Pending Implementation Work

- [ ] `scripts/test-concurrent-orders.sh` (absent).
- [ ] `scripts/test-order-after-failover.sh` (absent).
- [ ] `scripts/test-routing-split.sh` (absent).
- [x] `scripts/k8s-check-demo-exposure.sh` exists.
- [~] Check and add any missing README/docs links if new verification scripts are added.
- [~] Ensure final report sections are fully updated with latest HA/HPA/demo exposure evidence.

## Known Limitations / Future Work

- [!] Minikube multi-node is simulated on one VM, not real physical multi-machine fault isolation.
- [!] Admin API has no production authentication.
- [!] Demo Secrets are not production-grade secret management.
- [!] Public exposure through iptables/socat is demo-only.
- [!] No TLS/HTTPS in demo endpoint.
- [!] No production Ingress controller / LoadBalancer setup.
- [!] No Prometheus/Grafana stack; monitoring dashboard is lightweight.
- [!] Application currently uses PostgreSQL `rw` service for queries; `ro` read splitting is future work.
- [!] No backup/restore disaster recovery workflow.
- [!] No CI/CD image registry pipeline.
- [!] No payment, shipping, real users, or commerce-grade security.

## Final Verification Checklist

### Compose

- `./scripts/compose-up.sh`
- `./scripts/compose-status.sh`
- `./scripts/test-api.sh`
- `./scripts/test-admin-api.sh`
- `./scripts/compose-down.sh`

### Kubernetes single/default

- `./scripts/k8s-rebuild-and-deploy.sh`
- `./scripts/k8s-test-local.sh`
- `./scripts/k8s-status.sh`

### Distributed HA

- `MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-prepare-cnpg-local-storage.sh`
- `AUTO_FIX_CNPG_PVC_PERMISSIONS=1 MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh apply-ha-database`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh init-db`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh deploy-app`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh verify-app`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh`

### HPA

- `MINIKUBE_PROFILE=bookstore-distributed ./scripts/k8s-fix-metrics-server.sh`
- `MINIKUBE_PROFILE=bookstore-distributed DURATION=240s CONCURRENCY=30 ./scripts/k8s-hpa-demo.sh`

### Public demo exposure

- `EXPOSE_DEMO=1 ... ./scripts/k8s-distributed-ha-rebuild-all.sh`
- or:
- `MINIKUBE_PROFILE=bookstore-distributed PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh`
- `MINIKUBE_PROFILE=bookstore-distributed PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-check-demo-exposure.sh`

## Report/Demo Checklist

- [ ] Architecture summary.
- [ ] Request/network flow summary.
- [ ] Functional API results.
- [ ] Admin API results.
- [ ] Idempotency result.
- [ ] Kubernetes status result.
- [ ] HA placement result.
- [ ] Failover result.
- [ ] HPA result.
- [ ] Limitations section.

## Safety Rules

- Do not run `minikube delete` unless intentionally rebuilding a profile.
- Do not delete PVCs or CloudNativePG clusters with real data.
- `FORCE_DELETE_DANGLING_CNPG_PVC` is only for failed fresh initialization.
- Public exposure should expose only `frontend-service`, not PostgreSQL or backend ClusterIP services.
