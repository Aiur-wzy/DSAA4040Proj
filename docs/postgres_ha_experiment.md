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

3. Deploy the bookstore in HA mode:

   ```bash
   DB_MODE=ha ./scripts/k8s-rebuild-and-deploy.sh
   ```

4. Inspect HA status:

   ```bash
   DB_MODE=ha ./scripts/k8s-postgres-ha-status.sh
   ```

5. Run the failover test:

   ```bash
   DB_MODE=ha ./scripts/k8s-postgres-ha-failover-test.sh
   ```

## DB_MODE behavior

- `DB_MODE=single` is the default. It applies the existing single PostgreSQL Deployment/PVC/service and uses `postgres-service`.
- `DB_MODE=ha` applies `k8s/postgres-ha/`, waits for CloudNativePG `Cluster/bookstore-postgres`, initializes schema/seed data through the HA read-write service, and configures backends to use `bookstore-postgres-rw`.
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
