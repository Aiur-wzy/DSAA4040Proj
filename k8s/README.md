# Kubernetes Manifests (Initial Foundation)

This folder contains a simple Kubernetes baseline for the DSAA 4040 bookstore system.

## Manifests
- `namespace.yaml`: Creates the `bookstore` namespace.
- `configmap.yaml`: Creates `bookstore-config` with non-sensitive runtime configuration.
- `secret.yaml`: Creates `bookstore-secret` with demo credentials for local/course-project use.
- `postgres-deployment.yaml`: Creates PostgreSQL `Deployment` and `postgres-pvc` PersistentVolumeClaim.
- `postgres-service.yaml`: Exposes PostgreSQL internally as `postgres-service` (ClusterIP).
- `backend-deployment.yaml`: Deploys backend API with 2 replicas, env from ConfigMap/Secret, probes, and resources.
- `backend-service.yaml`: Exposes backend internally as `backend-service` (ClusterIP).
- `frontend-deployment.yaml`: Deploys frontend with 2 replicas and HTTP probes.
- `frontend-service.yaml`: Exposes frontend as `frontend-service` (NodePort 30080) for Minikube demo testing.
- `ingress.yaml`: Routes `bookstore.local` traffic (`/api` to backend, `/` to frontend).
- `hpa.yaml`: Adds HPA (`backend-hpa`) for backend CPU autoscaling.
- `postgres-init-job.yaml`: Runs a one-time PostgreSQL initialization Job using SQL files from a ConfigMap.

## Local image names required
- `bookstore-backend:latest`
- `bookstore-frontend:latest`

For Minikube image builds:
```bash
eval $(minikube docker-env)
docker compose build backend frontend
```

## Recommended local Minikube workflow (automated)
Run from repository root:
```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
./scripts/k8s-expose-demo.sh
```

This workflow is recommended for local rebuild/redeploy because it:
- works when standalone `kubectl` is unavailable by falling back to `minikube kubectl --`
- tests the Minikube NodePort service instead of Docker Compose localhost ports
- avoids Docker Hub pull failures inside Minikube by loading `postgres:16` from host Docker cache when available
- ensures `postgres-init-sql` ConfigMap exists before running `postgres-init` Job
- avoids manual image tagging/loading mistakes for backend and frontend images

## Apply manifests
```bash
minikube kubectl -- apply -f k8s/
```

## Inspect resources
```bash
minikube kubectl -- get all -n bookstore
minikube kubectl -- get pvc -n bookstore
minikube kubectl -- describe pod -n bookstore
```

## Check services
```bash
minikube kubectl -- get svc -n bookstore
```

## Enable ingress (Minikube)
```bash
minikube addons enable ingress
minikube ip
```
Add `"<minikube-ip> bookstore.local"` to `/etc/hosts` (or Windows hosts file).

## Useful URLs
- http://bookstore.local
- http://bookstore.local/api/health
- http://bookstore.local/api/books

## Check HPA
```bash
minikube addons enable metrics-server
minikube kubectl -- get hpa -n bookstore
minikube kubectl -- top pods -n bookstore
```

## PostgreSQL initialization Job
Create a ConfigMap that mounts SQL files into the Job container:
```bash
minikube kubectl -- create configmap postgres-init-sql \
  --from-file=01-schema.sql=database/schema.sql \
  --from-file=02-seed.sql=database/seed.sql \
  -n bookstore
```

Apply the Job:
```bash
minikube kubectl -- apply -f k8s/postgres-init-job.yaml
```

Check Job status and logs:
```bash
minikube kubectl -- get jobs -n bookstore
minikube kubectl -- logs job/postgres-init -n bookstore
```

Verify tables and seed data from inside PostgreSQL pod:
```bash
minikube kubectl -- exec -it -n bookstore deploy/postgres -- \
  psql -U bookstore -d bookstore -c "\dt"

minikube kubectl -- exec -it -n bookstore deploy/postgres -- \
  psql -U bookstore -d bookstore -c "SELECT COUNT(*) FROM books;"
```

> Warning: `schema.sql` resets tables. Re-running `postgres-init` can clear existing demo data.

## Pending verification checklist
- [ ] namespace created
- [ ] ConfigMap and Secret created
- [ ] PostgreSQL pod running
- [ ] PVC bound
- [ ] backend pods running
- [ ] frontend pods running
- [ ] services created
- [ ] ingress routes frontend and /api correctly
- [ ] HPA created
- [ ] health probes work
- [ ] PostgreSQL init Job executed and verified at runtime
