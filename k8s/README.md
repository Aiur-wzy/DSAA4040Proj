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
- `frontend-service.yaml`: Exposes frontend internally as `frontend-service` (ClusterIP).
- `ingress.yaml`: Routes `bookstore.local` traffic (`/api` to backend, `/` to frontend).
- `hpa.yaml`: Adds HPA (`backend-hpa`) for backend CPU autoscaling.

## Local image names required
- `bookstore-backend:latest`
- `bookstore-frontend:latest`

For Minikube image builds:
```bash
eval $(minikube docker-env)
docker build -t bookstore-backend:latest ./backend
docker build -t bookstore-frontend:latest ./frontend
```

## Apply manifests
```bash
kubectl apply -f k8s/
```

## Inspect resources
```bash
kubectl get all -n bookstore
kubectl get pvc -n bookstore
kubectl describe pod -n bookstore
```

## Check services
```bash
kubectl get svc -n bookstore
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
kubectl get hpa -n bookstore
kubectl top pods -n bookstore
```

## Database initialization note
For simplicity, `schema.sql` and `seed.sql` are not auto-mounted/applied in this initial Kubernetes setup.
Database initialization can be done manually or added later using a Kubernetes Job/InitContainer.

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
- [ ] database initialization strategy verified later
