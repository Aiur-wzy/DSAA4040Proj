# Kubernetes Manifests

This folder contains the Kubernetes deployment for the DSAA 4040 bookstore system. The backend tier is split by responsibility while still reusing the same `bookstore-backend:latest` image for all backend Pods.

## Manifests

- `namespace.yaml`: Creates the `bookstore` namespace.
- `configmap.yaml`: Creates `bookstore-config` with non-sensitive runtime configuration.
- `secret.yaml`: Creates `bookstore-secret` with demo credentials for local/course-project use.
- `postgres-deployment.yaml`: Creates PostgreSQL `Deployment` and `postgres-pvc` PersistentVolumeClaim.
- `postgres-service.yaml`: Exposes PostgreSQL internally as `postgres-service` (ClusterIP).
- `postgres-init-job.yaml`: Runs a one-time PostgreSQL initialization Job using SQL files from a ConfigMap.
- `public-backend-deployment.yaml` and `public-backend-service.yaml`: Run and expose the public/store API backend (`app=public-backend`) with 2 replicas.
- `admin-backend-deployment.yaml` and `admin-backend-service.yaml`: Run and expose the admin catalog/inventory API backend (`app=admin-backend`) with 1 replica.
- `monitoring-backend-deployment.yaml` and `monitoring-backend-service.yaml`: Run and expose the monitoring API backend (`app=monitoring-backend`) with 1 replica.
- `monitoring-backend-rbac.yaml`: Gives only `ServiceAccount/bookstore-monitoring-backend` namespace-scoped read-only access to Pods, Deployments, HPAs, and Pod metrics.
- `frontend-deployment.yaml`: Deploys the React build served through Nginx.
- `frontend-service.yaml`: Exposes frontend as `frontend-service` (NodePort 30080) for Minikube demo testing.
- `ingress.yaml`: Routes `bookstore.local` by API path.
- `hpa.yaml`: Adds `public-backend-hpa`, which targets `Deployment/public-backend`.

## Backend responsibility split

Phase 1 intentionally keeps a single backend image:

- image: `bookstore-backend:latest`
- container port: `8000`
- shared PostgreSQL database
- shared `bookstore-config` and `bookstore-secret`

The split is done at Kubernetes Deployment, Service, Ingress, and Nginx-proxy levels:

| Responsibility | Deployment | Service | Selector | Paths |
| --- | --- | --- | --- | --- |
| Store/public API | `public-backend` | `public-backend-service` | `app=public-backend` | `/api/health`, `/api/health/db`, `/api/books`, `/api/cart`, `/api/orders` |
| Admin API | `admin-backend` | `admin-backend-service` | `app=admin-backend` | `/api/admin/books`, `/api/admin/books/{book_id}/stock` |
| Monitoring API | `monitoring-backend` | `monitoring-backend-service` | `app=monitoring-backend` | `/api/admin/cluster/status` |

`BACKEND_MODE` route gating is enabled in Kubernetes (`public`, `admin`, and `monitoring` respectively). Docker Compose/local development keeps the default `BACKEND_MODE=all`, so one local backend still registers all routes.

## Path-based routing

Ingress for `bookstore.local` uses most-specific-prefix-first routing:

1. `/api/admin/cluster` -> `monitoring-backend-service:8000`
2. `/api/admin` -> `admin-backend-service:8000`
3. `/api` -> `public-backend-service:8000`
4. `/` -> `frontend-service:80`

The frontend Nginx config mirrors this split for NodePort access through `frontend-service`:

1. `/api/admin/cluster/` -> `monitoring-backend-service:8000`
2. `/api/admin/` -> `admin-backend-service:8000`
3. `/api/` -> `public-backend-service:8000`
4. `/` -> React SPA fallback (`try_files $uri /index.html`)

This means both `http://bookstore.local/...` and `http://$(minikube ip):30080/...` exercise the same backend responsibility split.

## RBAC isolation

Only `monitoring-backend` uses `serviceAccountName: bookstore-monitoring-backend`. `public-backend` and `admin-backend` do not use a Kubernetes-readable ServiceAccount.

The monitoring Role is namespace-scoped and grants only `get`, `list`, and `watch` for:

- Pods
- Deployments
- HorizontalPodAutoscalers
- `metrics.k8s.io` Pods

No broad ClusterRoleBinding is required for the app monitoring endpoint.

## Local image names required

- `bookstore-backend:latest`
- `bookstore-frontend:latest`

The automated workflow builds these stable tags on the host Docker daemon and loads them into Minikube:

```bash
./scripts/k8s-rebuild-and-deploy.sh
```

## Recommended local Minikube workflow

Run from the repository root for first-time deployment to an already running Minikube profile and repeated update deployments:

```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

The rebuild/deploy script is the preferred workflow because it:

- builds one backend image (`bookstore-backend:latest`) and one frontend image (`bookstore-frontend:latest`)
- saves/restores replica counts for `public-backend`, `admin-backend`, `monitoring-backend`, and `frontend`
- scales those application Deployments to zero before replacing same-tag images in Minikube
- waits for old Pods with selectors `app=public-backend`, `app=admin-backend`, `app=monitoring-backend`, and `app=frontend` to exit
- removes and loads `bookstore-backend:latest` once even though three Deployments reuse it
- does not stop PostgreSQL
- applies namespace, ConfigMap, Secret, PostgreSQL, monitoring RBAC, split backend Services/Deployments, frontend, Ingress, HPA, and init Job resources
- waits for all backend and frontend rollouts
- verifies a running Pod from each backend Deployment contains the expected backend files

Manual `kubectl apply` is appropriate only for configuration-only changes. If frontend or backend code changes, prefer the rebuild/deploy script so images are rebuilt, loaded into Minikube, and Pods are recreated.

## Public browser demo from a cloud-hosted Minikube node

`frontend-service` is a NodePort on `30080`. On a cloud server running Docker-backed Minikube, `$(minikube ip)` is usually internal to the host, so the public demo uses host iptables forwarding from `PUBLIC_PORT` (default `3000`) to `$(minikube ip):30080`:

```bash
./scripts/k8s-test-local.sh
PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh
```

The public exposure behavior is unchanged: only the frontend NodePort is exposed. Nginx inside the frontend Pod forwards API traffic to the correct internal backend Service by path.

## Ingress access

Enable the Minikube ingress addon and map `bookstore.local` to the Minikube IP:

```bash
minikube addons enable ingress
minikube ip
```

Add `"<minikube-ip> bookstore.local"` to `/etc/hosts` (or the Windows hosts file), then use:

- `http://bookstore.local/`
- `http://bookstore.local/api/health`
- `http://bookstore.local/api/books`
- `http://bookstore.local/api/admin/cluster/status`

## HPA metrics-server repair and autoscaling demo

Kubernetes HPA requires the Metrics API from `metrics-server` to calculate CPU utilization. If `public-backend-hpa` shows `cpu: <unknown>/50%`, run:

```bash
./scripts/k8s-fix-metrics-server.sh
```

The HPA demo now targets `public-backend`:

```bash
./scripts/k8s-hpa-demo.sh
```

Defaults:

- `BACKEND_DEPLOYMENT=public-backend`
- `BACKEND_HPA=public-backend-hpa`
- `BACKEND_SELECTOR=app=public-backend`
- `TARGET_URL=http://$(minikube ip):30080/api/books`

Evidence to capture:

- HPA before load
- public-backend Pod CPU before load
- load generator output
- HPA during load
- public-backend Deployment scaling from 2 to more replicas
- new public-backend Pods being created
- public-backend Pod CPU during load
- `kubectl describe hpa public-backend-hpa -n bookstore` output
- scale-down evidence if captured

## Monitoring Dashboard

The React Monitoring Dashboard continues to call:

```text
GET /api/admin/cluster/status
```

Routing sends that request to `monitoring-backend`. The monitoring Deployment sets:

- `BOOKSTORE_BACKEND_DEPLOYMENT=public-backend`
- `BOOKSTORE_BACKEND_HPA=public-backend-hpa`
- `BOOKSTORE_BACKEND_POD_SELECTOR=app=public-backend`

Therefore the dashboard reports the public-backend Deployment, public-backend HPA, public-backend Pods, and metrics-server Pod metrics when available. Missing CPU/memory samples are reported as warnings and `metricsAvailable: false`; the route itself should still return JSON.

## Useful inspection commands

```bash
minikube kubectl -- get deploy,svc,hpa,ingress -n bookstore
minikube kubectl -- get endpoints -n bookstore public-backend-service admin-backend-service monitoring-backend-service
minikube kubectl -- auth can-i get deployments -n bookstore --as=system:serviceaccount:bookstore:bookstore-monitoring-backend
minikube kubectl -- auth can-i get pods.metrics.k8s.io -n bookstore --as=system:serviceaccount:bookstore:bookstore-monitoring-backend
```
