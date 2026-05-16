# PostgreSQL HA Experiment with CloudNativePG

This project keeps `DB_MODE=single` as the stable default and adds an optional `DB_MODE=ha` experiment that runs PostgreSQL as an operator-managed primary/replica cluster.

## Why stateful data is harder than stateless scaling

Stateless frontend and backend Pods can be recreated or horizontally scaled because any healthy replica can serve the next request. Stateful databases are different: data must be durable, replicated in order, recovered safely, and protected from split-brain writes. A database failover can also leave clients unsure whether an in-flight write committed before a timeout.

## CAP choice for the bookstore

For orders and inventory, the bookstore chooses **CP/ACID** behavior over accepting writes during database uncertainty. It is better for checkout to be briefly unavailable during failover than to create duplicate orders or oversell inventory. Book browsing can later use read replicas, but asynchronous replicas may be stale and must not be used for checkout decisions unless consistency is explicitly handled.

## CloudNativePG mapping to distributed-system concepts

- **Primary = leader:** all writes go to the current PostgreSQL primary through `bookstore-postgres-rw`.
- **Replicas = followers:** standby instances receive changes from the primary.
- **WAL streaming = log replication:** PostgreSQL streams write-ahead log records to replicas.
- **Failover = new leader promotion:** CloudNativePG promotes a healthy replica when the primary fails.
- **Operator/controller = failover management:** Kubernetes plus CloudNativePG manage reconciliation, promotion, and service endpoints instead of custom ad-hoc failover code.

## How to run the HA experiment

1. Start Minikube with enough resources for three PostgreSQL instances.
2. Install the CloudNativePG operator:

   ```bash
   ./scripts/k8s-install-cnpg.sh
   ```

   The script uses a pinned CloudNativePG release URL by default and applies it with `kubectl apply --server-side`. Override with `CNPG_VERSION` or `CNPG_MANIFEST_URL` if your environment needs a locally downloaded manifest.

3. Deploy the bookstore in HA mode using staged commands. This is safer on single-node Minikube because it avoids combining operator install, three PostgreSQL instances, init, image replacement, app rollout, ingress, and metrics-server pressure in one run. A 4GB Minikube profile may be unstable; use 6GB+ memory if available.

   ```bash
   DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh install-cnpg
   DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh apply-ha-database
   DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh init-db
   DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh deploy-app
   DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh verify-app
   ```

   The `init-db` stage checks the HA database for `books`, `orders`, `order_items`, and `carts` and skips `postgres-init-ha` when those tables already exist. It recreates a previous init Job only when `FORCE_POSTGRES_INIT=1` is set.

4. Inspect HA status:

   ```bash
   DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh
   ```

5. Run the failover test:

   ```bash
   DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
   ```

## Multi-node Minikube evidence workflow

Use this workflow when the goal is distributed-system evidence rather than only validating HA mechanics on a single Minikube node. It starts or reuses a dedicated three-node profile and then runs the HA deployment stages with `DB_MODE=ha`.

### Commands

```bash
./scripts/k8s-distributed-ha-rebuild-all.sh

MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh
MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
MINIKUBE_PROFILE=bookstore-distributed BASE_URL=http://$(minikube -p bookstore-distributed ip):30080 ./scripts/test-order-consistency.sh
```

The default profile settings are:

```bash
MINIKUBE_PROFILE=bookstore-distributed
NODES=3
CPUS=4
MEMORY=6144
DRIVER=docker
DB_MODE=ha
```

### Expected outputs

The evidence script prints seven staged sections:

1. `[1/7] Kubernetes nodes` with three Minikube Kubernetes Nodes in `kubectl get nodes -o wide`.
2. `[2/7] Bookstore pods with node placement` with application and PostgreSQL Pods plus their `NODE` column.
3. `[3/7] CloudNativePG HA status` with the current primary, ready instances, services, and EndpointSlices.
4. `[4/7] PostgreSQL primary/replica node distribution` with each `bookstore-postgres-*` Pod and its Kubernetes node.
5. `[5/7] rw/ro EndpointSlices` showing `bookstore-postgres-rw` for the writable primary and `bookstore-postgres-ro` for read-only replicas.
6. `[6/7] Application health and DB health` showing successful responses from `/api/health`, `/api/health/db`, and `/api/admin/cluster/status`.
7. `[7/7] Evidence summary` with `STRONG PASS` when PostgreSQL uses three distinct nodes, `PASS` when it uses at least two, and `WARN` when all PostgreSQL Pods are on one node.

The failover test additionally prints `oldPrimaryNode=<nodeName>`, `newPrimaryNode=<nodeName>`, and a final old/new primary summary. A different old/new node is strong node-level failover evidence; the test still passes with a warning if the scheduler used the same node because that still verifies CloudNativePG promotion and the `bookstore-postgres-rw` service path.

### Screenshot checklist

Capture screenshots or terminal excerpts for:

- `minikube -p bookstore-distributed status`
- `minikube -p bookstore-distributed kubectl -- get nodes -o wide`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-distributed-ha-evidence.sh` sections `[3/7]` through `[7/7]`
- `MINIKUBE_PROFILE=bookstore-distributed DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh` showing old/new primary Pods and nodes
- `MINIKUBE_PROFILE=bookstore-distributed BASE_URL=http://$(minikube -p bookstore-distributed ip):30080 ./scripts/test-order-consistency.sh` showing idempotency success

### Limitations

Minikube multi-node still runs on one host, so it is a simulation of Kubernetes node placement rather than real machine, rack, zone, or regional isolation. Local CPU, memory, storage, and image-pull pressure can cause Kubernetes to place multiple PostgreSQL Pods on the same node even though the CloudNativePG manifest prefers anti-affinity on `kubernetes.io/hostname`. Ideal demo evidence is three PostgreSQL Pods on three nodes; two or more distinct nodes is acceptable under local resource constraints. Production requires real multi-VM Kubernetes or managed Kubernetes, CSI storage, backups, TLS, a registry, monitoring, alerting, and disaster recovery procedures.

## DB_MODE behavior

- `DB_MODE=single` is the default. It applies the existing single PostgreSQL Deployment/PVC/service and uses `postgres-service`.
- `DB_MODE=ha` should be run with the staged commands above. The HA database stage applies `k8s/postgres-ha/`, waits for CloudNativePG `Cluster/bookstore-postgres`, the init stage initializes or skips schema/seed data through the HA read-write service, and the app stage configures backends to use `bookstore-postgres-rw`.
- `bookstore-postgres-ro` is available for future read-only browsing experiments, but the app currently routes all queries to the write service for strong consistency.

If your environment cannot pull official CloudNativePG or PostgreSQL images, mirror the official images into a trusted registry and update the operator/cluster manifests. Do not hardcode unverified mirrors.

## Idempotent checkout under partial failure ambiguity

`POST /api/orders` accepts `Idempotency-Key`. The database stores the key in `orders.idempotency_key` and enforces uniqueness per `(user_id, idempotency_key)`. Retrying the same key returns the existing order, does not decrement stock again, does not duplicate order items, and does not clear the cart a second time. Legacy clients without the header still work, but only clients that send the header get retry safety.

## What the failover test verifies

The failover script deletes only the current primary Pod, never PVCs. It verifies:

- data can be written before failure
- CloudNativePG promotes a new primary automatically
- the `bookstore-postgres-rw` service follows the primary
- backend `/api/health/db` recovers through the service
- old data remains after failover
- new writes succeed after failover

## What this does not prove

- production multi-region HA
- true physical fault isolation in Minikube
- zero data loss unless synchronous replication is configured and verified
- backup/restore or disaster recovery readiness
- production security hardening

Minikube is useful for a course experiment, not proof of production-grade distributed infrastructure.

## Production migration checklist

A production version should use real multi-VM Kubernetes or a managed Kubernetes service, a cloud LoadBalancer/Ingress, a container registry, CSI-backed storage, managed PostgreSQL or production CloudNativePG, automated backups, TLS, secret rotation, Prometheus/Grafana monitoring, alerts, and disaster recovery runbooks.
