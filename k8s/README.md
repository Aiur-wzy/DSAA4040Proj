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

The automated workflow builds these stable tags on the host Docker daemon and loads them into Minikube:

```bash
./scripts/k8s-rebuild-and-deploy.sh
```

## Recommended local Minikube workflow (automated)
Run from the repository root for both first-time deployment to an already running Minikube profile and repeated update deployments:

```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-test-local.sh
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

The rebuild/deploy script is the preferred workflow because it:
- builds `bookstore-backend:latest` and `bookstore-frontend:latest`, matching the image tags in the Kubernetes Deployments
- loads both freshly built images into Minikube so the cluster does not keep stale local images
- applies namespace, ConfigMap, Secret, PostgreSQL, backend, frontend, Service, Ingress, HPA, and init Job manifests in the expected order
- preserves the generated `postgres-init-sql` ConfigMap logic before running the `postgres-init` Job
- restarts the backend and frontend Deployments after image loading so Pods use the newly loaded images
- waits for rollout completion and prints final Pods/Services plus verification commands
- works when standalone `kubectl` is unavailable by falling back to `minikube kubectl --`

Manual `kubectl apply` is appropriate only for configuration-only changes such as ConfigMap, Ingress, or HPA edits. If frontend or backend code changes, the update must include image rebuild, `minikube image load`, and Deployment restart; prefer `./scripts/k8s-rebuild-and-deploy.sh` instead of doing those steps by hand.


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

## Apply manifests manually for configuration-only changes
Manual apply can be useful for configuration-only changes that do not alter frontend/backend image contents, such as ConfigMap, Ingress, or HPA changes:

```bash
minikube kubectl -- apply -f k8s/
```

For frontend or backend code changes, prefer `./scripts/k8s-rebuild-and-deploy.sh` so images are rebuilt, loaded into Minikube, and Deployments are restarted.

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

## HPA metrics-server repair and autoscaling demo
Kubernetes HPA requires the Metrics API from `metrics-server` to calculate CPU utilization. If `backend-hpa` shows `cpu: <unknown>/50%`, run the repeatable repair/check workflow from the repository root:

```bash
./scripts/k8s-fix-metrics-server.sh
```

The script enables the Minikube addon, waits for the metrics-server Deployment/Pod, detects `ImagePullBackOff` or `ErrImagePull`, and patches metrics-server away from the bad tag+digest image form to a valid tag-only image when needed. It then restarts metrics-server, waits for rollout, verifies:

```bash
minikube kubectl -- top nodes
minikube kubectl -- top pods -n bookstore
minikube kubectl -- get hpa -n bookstore
```

Run the HPA load demo with:

```bash
./scripts/k8s-hpa-demo.sh
```

Optional custom load example:

```bash
DURATION=240s CONCURRENCY=30 ./scripts/k8s-hpa-demo.sh
```

Expected behavior:

- Before load: backend has 2 replicas, CPU is low, and HPA shows a known value such as `cpu: 3%/50%`.
- During load: CPU rises above the 50% target and backend scales from 2 replicas to 3, 4, or 5 replicas.
- After load: backend eventually scales back down to 2 replicas; scale-down may take several minutes because HPA uses stabilization behavior.

HPA CPU percentages are relative to container CPU requests, not total node CPU. For example, if backend requests `100m` CPU and uses `300m` CPU, HPA can report about `300%`.

Screenshot/evidence checklist for the report:

- HPA before load
- pod CPU before load
- `hey` load generator output
- HPA during load
- backend Deployment scaling from 2 to more replicas
- backend Pods being created (`Pending -> ContainerCreating -> Running -> Ready`)
- pod CPU during load
- `kubectl describe hpa backend-hpa -n bookstore` output
- scale-down evidence if captured

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

## In-app Monitoring / HPA Dashboard
The application includes a lightweight, read-only Monitoring page that supports the HPA autoscaling demo without Prometheus, Grafana, another microservice, or any monitoring database. The flow is:

```text
React frontend -> FastAPI backend -> Kubernetes API inside the cluster
```

The FastAPI backend exposes `GET /api/admin/cluster/status` for the React page. That endpoint reads the backend Deployment, `backend-hpa`, backend Pods, and `metrics.k8s.io` Pod metrics when metrics-server is available. The dashboard displays Deployment replica status, HPA CPU/replica status, backend Pods, and simple frontend-only charts for replica and CPU trends. Chart history is stored only in browser memory and resets on page refresh.

The backend Deployment uses the `bookstore-backend` ServiceAccount from `k8s/backend-rbac.yaml`. The RBAC is namespace-scoped and grants read/list/watch access only to Pods, Deployments, HPAs, and Pod metrics needed by the dashboard.

Recommended demo flow:

```bash
./scripts/k8s-rebuild-and-deploy.sh
./scripts/k8s-fix-metrics-server.sh
```

Open the bookstore frontend in a browser and click **Monitoring**. In another terminal run:

```bash
./scripts/k8s-hpa-demo.sh
```

Expected behavior:
- before load: backend has 2 replicas and low CPU
- during load: CPU rises above the 50% HPA target
- backend replicas increase toward `maxReplicas=5`
- new backend Pods appear in the table
- the replicas chart rises from 2 toward 5
- the CPU chart rises above the target line
- after load stops: CPU decreases, and after the HPA scale-down delay replicas eventually return to 2

Metrics-server is required for CPU and memory values. If metrics are unavailable, run:

```bash
./scripts/k8s-fix-metrics-server.sh
```

Then verify metrics with:

```bash
minikube kubectl -- top pods -n bookstore
```

This dashboard is read-only. It does not scale Deployments, patch the HPA, delete Pods, run load tests, or modify Kubernetes resources.

Screenshot/evidence checklist for the final report:
- Monitoring page before load
- HPA card before load
- replicas chart before load
- load generator terminal
- Monitoring page during load
- replicas chart showing 2 -> 5
- CPU chart showing utilization rising above target
- backend Pods table showing new Pods
- Monitoring page after load showing scale-down if captured
