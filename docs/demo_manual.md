# DSAA 4040 Bookstore Live Demo Manual

This manual is a practical runbook for the final live demo. It assumes you are running from the repository root on the same server or workstation that has Docker, Minikube, and the project scripts available.

## 1. Demo goal

This demo proves that the DSAA 4040 Online Bookstore is a cloud-native three-tier application: a React/Vite frontend served by Nginx, split FastAPI backends, and PostgreSQL are containerized, deployed on Kubernetes, health-checked, and exercised through real catalog, cart, order, admin inventory, HPA autoscaling, and browser-based Monitoring Dashboard flows. If needed, the same Kubernetes frontend can be exposed publicly through the existing iptables demo script.

## 2. Pre-demo checklist

Run these checks before the presentation window starts:

```bash
cd <repo-root>
chmod +x scripts/*.sh
docker --version
docker compose version
minikube status
minikube kubectl -- get nodes
hey -h
```

Expected results:

- You are in the DSAA 4040 project repository root.
- Docker and Docker Compose are installed and reachable.
- Minikube is running.
- At least one Minikube node is `Ready`.
- `hey` is installed for the HPA load demo.
- Project scripts are executable.

## 3. Standard update before demo

For any frontend, backend, or Kubernetes manifest changes, use the standard rebuild/deploy workflow:

```bash
./scripts/k8s-rebuild-and-deploy.sh
```

Why: the Kubernetes manifests use stable local image tags (`bookstore-backend:latest` and `bookstore-frontend:latest`). A plain `kubectl apply` may leave Minikube running stale same-tag images. The rebuild/deploy script builds fresh images, loads them into Minikube, removes old same-tag images, reapplies manifests, restores replicas for public/admin/monitoring backends plus frontend, and waits for rollouts.

Verify afterward:

```bash
./scripts/k8s-test-local.sh
./scripts/k8s-status.sh
```

## 4. metrics-server and HPA preparation

Prepare Kubernetes metrics before showing HPA autoscaling or the Monitoring Dashboard CPU chart:

```bash
./scripts/k8s-fix-metrics-server.sh
minikube kubectl -- top pods -n bookstore
minikube kubectl -- get hpa -n bookstore
```

Expected results:

- metrics-server is `Running` in `kube-system`.
- `kubectl top pods -n bookstore` returns CPU and memory values.
- `public-backend-hpa` no longer shows `<unknown>` for CPU.

## 5. Public browser demo exposure

Use the existing iptables exposure workflow only. Do not invent a new public exposure method for the demo.

```bash
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

Then open:

```text
http://<server-public-ip>:3000
```

Important notes:

- Use `http://`, not `https://`.
- The cloud firewall or security group must allow inbound TCP `3000`.
- The script exposes the existing Kubernetes `frontend-service` NodePort path; it does not expose PostgreSQL publicly.

Cleanup command:

```bash
PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh --cleanup
```

## 6. Main browser demo script

### Step A: Open the frontend

1. Open the bookstore UI:
   - Local Minikube NodePort: `http://$(minikube ip):30080`
   - Public demo URL if enabled: `http://<server-public-ip>:3000`
2. Show the homepage title and backend/DB status line.
3. Show the book list.
4. Use search if useful; the UI searches by title, author, or category.
5. Explain: the browser loads a React/Vite frontend served by Nginx. Nginx uses path-based routing: `/api/admin/cluster/` to monitoring-backend, `/api/admin/` to admin-backend, and `/api/` to public-backend.

### Step B: Cart and order flow

1. Add a book to the cart.
2. Optionally update quantity or remove an item.
3. Click **Place Order**.
4. Show the order history entry.
5. Explain the backend transaction:
   - reads the current cart,
   - locks the relevant book rows,
   - validates stock,
   - creates `orders` and `order_items`,
   - decrements book stock,
   - clears the cart,
   - commits atomically.

### Step C: Admin Demo

1. Click **Admin Demo**.
2. Add a temporary demo book, for example:
   - Title: `Live Demo Book`
   - Author: `DSAA 4040`
   - Category: `Demo`
   - Price: `9.99`
   - Stock: `5`
3. Increase stock, then decrease stock.
4. Return to the Store page and show that the catalog reflects the change.
5. Go back to Admin Demo and delete the temporary demo book.
6. Explain: this admin page is intentionally unauthenticated for course demo purposes. A production system would require authentication and authorization.

### Step D: Monitoring Dashboard

1. Click **Monitoring**.
2. Show the **public-backend Deployment** card.
3. Show the **HPA** card.
4. Show the **public-backend Pods** table.
5. Show the replicas chart.
6. Show the CPU chart.
7. Explain: the frontend calls FastAPI at `GET /api/admin/cluster/status`; the monitoring-backend FastAPI Pod uses the Kubernetes Python client and namespace-scoped read-only RBAC to read public-backend Deployment, HPA, Pod, and metrics data.

### Step E: HPA autoscaling demo

Keep the Monitoring Dashboard open. In another terminal, run:

```bash
./scripts/k8s-hpa-demo.sh
```

Optional watch commands in extra terminals:

```bash
minikube kubectl -- get hpa -n bookstore -w
minikube kubectl -- get pods -n bookstore -l app=public-backend -w
```

Expected behavior:

- public-backend replicas start at `2`.
- CPU rises above the `50%` target.
- public-backend scales to `3`, `4`, or `5` replicas depending on load.
- new public-backend Pods appear and move toward `Running`/ready.
- Monitoring Dashboard cards, Pod table, and charts update during auto-refresh.
- after load stops, replicas eventually scale back down to `2`; scale-down can take several minutes because of Kubernetes HPA stabilization behavior.

Useful custom load example if scaling is slow:

```bash
DURATION=240s CONCURRENCY=60 ./scripts/k8s-hpa-demo.sh
```

## 7. Fast verification commands during demo

```bash
curl http://$(minikube ip):30080/api/health
curl http://$(minikube ip):30080/api/books
curl -s http://$(minikube ip):30080/api/admin/cluster/status | python3 -m json.tool
BASE_URL=http://$(minikube ip):30080 ./scripts/test-admin-api.sh
./scripts/k8s-status.sh
```

## 8. Troubleshooting quick fixes

- Browser still shows old UI:

  ```bash
  ./scripts/k8s-rebuild-and-deploy.sh
  ```

  Then hard refresh the browser with `Ctrl+F5`.

- Admin route returns `404`:

  ```bash
  minikube kubectl -- exec -n bookstore deploy/admin-backend -- find / -name admin_books.py
  ./scripts/k8s-rebuild-and-deploy.sh
  ```

- Monitoring route returns `404`:

  ```bash
  minikube kubectl -- exec -n bookstore deploy/monitoring-backend -- find / -name cluster_status.py
  ./scripts/k8s-rebuild-and-deploy.sh
  ```

- Monitoring route returns `403`:

  ```bash
  minikube kubectl -- get serviceaccount,role,rolebinding -n bookstore
  minikube kubectl -- auth can-i get deployments -n bookstore --as=system:serviceaccount:bookstore:bookstore-monitoring-backend
  minikube kubectl -- auth can-i list pods.metrics.k8s.io -n bookstore --as=system:serviceaccount:bookstore:bookstore-monitoring-backend
  ```

- public-backend HPA shows `<unknown>`:

  ```bash
  ./scripts/k8s-fix-metrics-server.sh
  ```

- Metrics unavailable on dashboard:

  ```bash
  minikube kubectl -- top pods -n bookstore
  minikube kubectl -- get hpa -n bookstore
  ```

- HPA does not scale:

  ```bash
  hey -h
  DURATION=240s CONCURRENCY=60 ./scripts/k8s-hpa-demo.sh
  minikube kubectl -- describe hpa public-backend-hpa -n bookstore
  minikube kubectl -- get deployment backend -n bookstore -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}{"\n"}'
  ```

- Public browser cannot open:

  ```bash
  PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
  curl -I http://$(minikube ip):30080/api/health
  curl -I http://<server-public-ip>:3000/api/health
  sudo iptables -t nat -L PREROUTING -n -v --line-numbers | grep 3000
  ```

  Also confirm the cloud firewall/security group allows inbound TCP `3000`.

## 9. Evidence checklist

Collect screenshots or terminal output for:

- frontend homepage,
- cart/order success,
- Admin Demo add/update/delete flow,
- `./scripts/k8s-status.sh` output,
- HPA before load,
- Monitoring Dashboard before load,
- HPA demo terminal output,
- Monitoring Dashboard during load with charts,
- public-backend Pods scaling up,
- scale-down evidence if captured.
