# Minikube Multi-Node Experiment

## A. Current Implementation

The stable demo remains the default single-node Minikube workflow:

```bash
./scripts/k8s-full-update.sh
```

The application already uses a standard Kubernetes architecture: split public, admin, and monitoring backends; Service-based routing; Ingress path routing; HPA for `public-backend`; read-only RBAC for the monitoring backend; and a single PostgreSQL Deployment with PVC-backed storage.

PostgreSQL is intentionally a single-instance demo database. This repository does not implement PostgreSQL HA, a PostgreSQL Operator, multi-primary database writes, or distributed consensus storage.

## B. Multi-Node Experiment Purpose

The optional experiment verifies cloud-native scheduling behavior under Minikube multi-node when the project server cannot host a real multi-VM cluster. Minikube multi-node is a simulation on one host: it creates multiple Kubernetes nodes, but those nodes still share the same underlying physical or VM resources.

This experiment is useful for verifying Kubernetes scheduling, Service routing, Ingress routing, HPA scaling, and Pod distribution across Kubernetes nodes. It must not be described as production-grade distributed infrastructure.

## What This Experiment Can Verify

- Pod scheduling across Kubernetes nodes.
- `public-backend` replica distribution.
- `frontend` replica distribution.
- Service routing through Kubernetes Services and NodePort.
- Ingress routing with the `bookstore.local` host header.
- HPA scale-out behavior for `public-backend`.
- Monitoring API and dashboard visibility of Pod node placement.
- PVC-backed PostgreSQL Pod restart recovery.
- Conservative stateless node maintenance behavior with cordon/uncordon.

## What This Experiment Cannot Prove

- True physical fault isolation.
- Real multi-machine network latency, partitions, or CNI behavior.
- Production-grade distributed storage.
- Database HA, replica promotion, or automatic failover.
- Cloud LoadBalancer behavior.

## Commands

Start the multi-node profile:

```bash
NODES=3 CPUS=2 MEMORY=3072 ./scripts/k8s-multinode-start.sh
```

Deploy the same Kubernetes manifests into the multi-node profile:

```bash
MINIKUBE_PROFILE=bookstore-multinode ./scripts/k8s-full-update.sh
```

Verify scheduling, Services, Ingress, HPA, and monitoring routes:

```bash
MINIKUBE_PROFILE=bookstore-multinode ./scripts/k8s-multinode-verify.sh
```

Optional HPA scale distribution test:

```bash
MINIKUBE_PROFILE=bookstore-multinode MULTINODE_SCALE_TEST=1 ./scripts/k8s-multinode-verify.sh
```

Order consistency transaction test:

```bash
MINIKUBE_PROFILE=bookstore-multinode ./scripts/test-order-consistency.sh
```

PostgreSQL PVC-backed Pod recovery test:

```bash
MINIKUBE_PROFILE=bookstore-multinode ./scripts/k8s-db-recovery-test.sh
```

Safe stateless node cordon availability test:

```bash
MINIKUBE_PROFILE=bookstore-multinode ./scripts/k8s-node-failure-test.sh
```

Optional app-Pod rescheduling during node maintenance:

```bash
MINIKUBE_PROFILE=bookstore-multinode DRAIN_APP_PODS=1 ./scripts/k8s-node-failure-test.sh
```

`NODE_STOP_TEST=1` is intentionally opt-in because stopping a Minikube node is more disruptive than cordon-only testing.

## Consistency Model

Current implemented consistency is handled by PostgreSQL transactions and row-level locking. During order placement, stock checks, stock decrement, order creation, order item creation, and cart cleanup happen inside one transaction. If stock is insufficient, the order fails with a conflict response and the cart is not cleared.

Monitoring metrics are near-real-time and refreshed periodically by the dashboard. If a book list cache is added later, it should be treated as eventually consistent unless explicit cache invalidation is implemented.

## Database Failure Model

Current demo recovery is single-instance PostgreSQL with a PVC. A PostgreSQL Pod crash or deletion can recover by recreating the Pod and reattaching the persistent volume.

Not implemented:

- Multi-primary PostgreSQL.
- Automatic database failover.
- PostgreSQL replica promotion.
- Distributed consensus database behavior.

Production path:

- Managed PostgreSQL or a PostgreSQL Operator.
- Primary/replica configuration with failover.
- Backup and restore procedures.
- Read replicas if the workload needs them.

## Node Failure Model

Stateless services can remain available during node maintenance if replicas are distributed across nodes. `public-backend` is the main HPA target and has topology spread preferences and preferred anti-affinity so Kubernetes can spread replicas when multiple nodes exist while still supporting single-node Minikube.

PostgreSQL remains a single-instance dependency in the demo and is not treated as HA. Node-level database HA is future work.

## Production Migration Mapping

| Demo / Minikube item | Production migration path |
| --- | --- |
| Minikube multi-node | kubeadm, k3s, managed Kubernetes, or another real multi-VM cluster |
| NodePort + host iptables | Cloud LoadBalancer and production Ingress Controller |
| Local image load | Container registry with immutable tags |
| hostPath/PVC demo storage | CSI storage, managed PostgreSQL, or production-grade persistent volumes |
| Demo Secret | External secret manager and rotation workflow |
| metrics-server/dashboard | Prometheus, Grafana, alerting, and persistent metrics |
| Single PostgreSQL | Managed PostgreSQL or PostgreSQL Operator |
| Basic Ingress | TLS, DNS, NetworkPolicy, WAF or ingress hardening as needed |
| Manual scripts | CI/CD pipeline with deployment gates and rollback |

## Real Multi-VM Deployment Mapping

Minikube multi-node simulates Kubernetes scheduling. A real deployment should use multiple VMs, real CNI networking, cloud LoadBalancer integration, CSI storage, external image registry, production database HA, TLS, NetworkPolicy, and CI/CD automation.

## Report Wording

Because of resource limits, the project uses an optional Minikube multi-node experiment to demonstrate Kubernetes scheduling, Service routing, Ingress routing, HPA behavior, and Pod placement visibility across simulated Kubernetes nodes. This is not a production distributed cluster because all Minikube nodes share one host. The manifests use standard Kubernetes objects, so the same architecture can migrate to a real multi-VM Kubernetes environment such as kubeadm, k3s, or managed Kubernetes, with production replacements for image registry, ingress, storage, secrets, observability, and PostgreSQL HA.

## Evidence Checklist

- `kubectl get nodes -o wide` showing multiple nodes.
- `kubectl get pods -n bookstore -l app=public-backend -o wide` showing node placement.
- Monitoring Dashboard screenshot showing Node and Pod IP columns.
- HPA scale-out evidence in the multi-node profile.
- `scripts/test-order-consistency.sh` output.
- `scripts/k8s-db-recovery-test.sh` output.
- `scripts/k8s-node-failure-test.sh` output.
