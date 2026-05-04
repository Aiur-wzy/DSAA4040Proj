# Final Project Report (Scaffold)

> Status: All results in this document are pending runtime verification.

## 1. Project Overview
Brief summary of the cloud-native online bookstore project goals and deliverables.

- TODO: Add final project summary paragraph.
- TODO: Add architecture overview screenshot.
- TODO: Add runtime verification note and evidence links.

## 2. Requirements and Scope
Define the implemented scope and non-goals for this course project.

- TODO: List completed requirements.
- TODO: List out-of-scope items.
- TODO: Attach command/output evidence.

## 3. System Architecture
Describe the end-to-end architecture: frontend, backend API, and PostgreSQL.

- TODO: Insert architecture diagram.
- TODO: Add container and Kubernetes view.
- TODO: Add runtime evidence (compose/k8s status output).

## 4. Database Design
Summarize schema and seed strategy.

- TODO: Add ER/table summary screenshot.
- TODO: Add SQL verification output (`\dt`, sample SELECT results).
- TODO: Add notes on reset behavior and initialization.

## 5. Backend API Design
Describe backend endpoints and data flow.

- TODO: Add endpoint list table.
- TODO: Add health check response screenshots.
- TODO: Add smoke test command output snippet.

## 6. Frontend Design
Summarize frontend structure and user interactions.

- TODO: Add UI screenshots (books/cart/orders/health).
- TODO: Add notes on API proxy behavior.
- TODO: Add known UI limitations.

## 7. Docker Compose Integration
Describe local full-stack orchestration with Docker Compose.

- TODO: Include `docker compose ps` output.
- TODO: Include helper script usage and outputs.
- TODO: Add troubleshooting notes.

## 8. Kubernetes Deployment
Describe namespace, workloads, services, and deployment process.

- TODO: Include `kubectl get all -n bookstore` output.
- TODO: Include deployment rollout screenshots/logs.
- TODO: Document runtime verification steps and outcomes.

## 9. ConfigMap and Secret Management
Explain how non-sensitive and sensitive config is managed.

- TODO: Add ConfigMap/Secret manifest references.
- TODO: Add safe verification commands and outputs.
- TODO: Note security considerations for course environment.

## 10. Health Checks
Document liveness/readiness/health endpoint checks.

- TODO: Add probe settings summary.
- TODO: Add API health command outputs.
- TODO: Add observed behavior under restart/failure tests.

## 11. Ingress Routing
Document ingress host/path routing for frontend and backend API.

- TODO: Add ingress YAML summary.
- TODO: Add `bookstore.local` test evidence.
- TODO: Add screenshot of successful routing.

## 12. Autoscaling with HPA
Describe backend HPA setup and scaling thresholds.

- TODO: Add `kubectl get hpa -n bookstore` output.
- TODO: Add load-triggered scaling experiment notes.
- TODO: Add observed min/max replica behavior.

## 13. Monitoring and Performance Testing
Summarize basic monitoring and performance testing method/results.

- TODO: Add `monitor-k8s.sh` output.
- TODO: Add `perf-test.sh` command and output.
- TODO: Add interpreted metrics/latency summary.

## 14. Problems Encountered and Solutions
List implementation/deployment issues and how they were resolved.

- TODO: Record at least 3 concrete issues.
- TODO: Provide root cause + fix per issue.
- TODO: Include command/output proof where relevant.

## 15. Conclusion
Provide final evaluation of project completion and learning outcomes.

- TODO: Add completion assessment against requirements.
- TODO: Add limitations and future improvements.
- TODO: Confirm pending/finished verification items.

## 16. Appendix: Useful Commands
Keep a reference of operational commands used during verification.

- TODO: Add Docker Compose commands.
- TODO: Add Kubernetes apply/status/log/exec commands.
- TODO: Add smoke/performance test commands.
- TODO: Add representative command outputs.
