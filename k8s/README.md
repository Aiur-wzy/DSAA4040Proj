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
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

This workflow is recommended for local rebuild/redeploy because it:
- works when standalone `kubectl` is unavailable by falling back to `minikube kubectl --`
- tests the Minikube NodePort service instead of Docker Compose localhost ports
- avoids Docker Hub pull failures inside Minikube by loading `postgres:16` from host Docker cache when available
- ensures `postgres-init-sql` ConfigMap exists before running `postgres-init` Job
- avoids manual image tagging/loading mistakes for backend and frontend images


## Public browser demo from a cloud-hosted Minikube node
`frontend-service` is a NodePort on `30080`. On a cloud server running Docker-backed Minikube, `$(minikube ip)` is usually internal to the host, so the public demo uses host iptables forwarding from `PUBLIC_PORT` (default `3000`) to `$(minikube ip):30080`:

```bash
./scripts/k8s-test-local.sh
PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh
```

Allow inbound TCP `3000` in the cloud firewall/security group, then open `http://<server-public-ip>:3000` (HTTP, not HTTPS). The script inserts DNAT and forwarding rules at position `1` so they are evaluated before Docker-managed chains, and it also adds bidirectional `DOCKER-USER` allow rules.

Verify from another machine, not with loopback on the server:

```bash
curl -v http://<server-public-ip>:3000/api/health
sudo tcpdump -ni any 'tcp port 3000 or tcp port 30080'
sudo iptables -L FORWARD -n -v --line-numbers | grep "30080"
```

Expected behavior is that the external SYN reaches `server:3000`, the host responds with a SYN-ACK, and iptables packet counters increase. Remove rules with:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh --cleanup
```

This is a single-node Minikube demo method. Production Kubernetes should normally use a cloud `LoadBalancer` Service or an Ingress controller backed by a public load balancer.

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
