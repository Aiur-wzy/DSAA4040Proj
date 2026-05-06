# DSAA 4040 Bookstore Architecture and Defense Notes

These notes are designed for final presentation preparation and defense questions. They summarize what the current repository implements and explain the technical decisions behind the demo.

## 1. Project overview

The project is a cloud-native online bookstore. Users can browse books, search the catalog, add books to a cart, place orders, and view order history. A demo admin page supports catalog and stock changes. A lightweight in-app Monitoring Dashboard shows Kubernetes backend Deployment, HPA, Pod, and metrics status during the autoscaling demo.

It is cloud-native because it uses containerized services, declarative Kubernetes manifests, ConfigMaps and Secrets, health probes, a persistent database volume, a PostgreSQL initialization Job, Services, Ingress routing, Horizontal Pod Autoscaling, and automation scripts for repeatable deployment, verification, and demo operations.

## 2. System architecture

The application follows a three-tier architecture:

- **Browser**: user interface entry point.
- **React/Vite frontend**: bookstore UI, cart, order history, Admin Demo, and Monitoring Dashboard.
- **Nginx**: serves the built frontend and proxies `/api` requests to the backend.
- **FastAPI backend**: REST API for health, books, cart, orders, admin book operations, and Kubernetes cluster status.
- **PostgreSQL database**: persistent catalog, cart, order, and order item data.

```text
+---------+
| Browser |
+----+----+
     |
     | HTTP
     v
+-------------------------------+
| Frontend Pod                  |
| React/Vite static app + Nginx |
| /api proxy                    |
+----+--------------------------+
     |
     | /api/*
     v
+----------------+
| Backend Pod(s) |
| FastAPI        |
+----+-----------+
     |
     | SQL
     v
+----------------+
| PostgreSQL     |
| PVC-backed DB  |
+----------------+

Monitoring path:
React Monitoring page -> FastAPI /api/admin/cluster/status -> Kubernetes API
```

## 3. Frontend implementation

- **Framework**: React with Vite.
- **Static serving**: frontend container builds the React app and serves it through Nginx.
- **Main app structure**:
  - `frontend/src/App.jsx` owns top-level state: books, cart, orders, search text, health status, messages, and current page.
  - `frontend/src/components/BookList.jsx` renders the catalog and search form.
  - `frontend/src/components/Cart.jsx` renders cart items, quantity updates, removal, and the place-order button.
  - `frontend/src/components/OrderHistory.jsx` renders historical orders and their items.
  - `frontend/src/components/AdminBooks.jsx` renders the Admin Demo catalog/inventory operations.
  - `frontend/src/components/MonitoringDashboard.jsx` renders Kubernetes Deployment, HPA, Pod, replica chart, and CPU chart data.
  - `frontend/src/api.js` centralizes HTTP calls and error handling.
- **Navigation**: the app uses simple React state (`page`) for Store, Admin Demo, and Monitoring views instead of React Router. This keeps the demo small and avoids route/server refresh complexity.
- **Store page/book list**: supports displaying books and searching by title, author, or category through `GET /api/books?search=...`.
- **Cart UI**: supports add, update quantity, remove, and place order.
- **Order history**: displays recent orders, total, status, creation time, and item price snapshots.
- **Admin Demo page**: supports adding books, changing stock by deltas, and deleting unreferenced books.
- **Monitoring Dashboard**:
  - auto-refreshes every 5 seconds,
  - calls `GET /api/admin/cluster/status`,
  - stores rolling chart samples only in browser memory,
  - resets chart history on browser refresh.
- **Why the frontend does not call the Kubernetes API directly**:
  - browsers should not receive Kubernetes credentials,
  - Kubernetes API access should be controlled server-side,
  - backend RBAC can restrict exactly what is readable,
  - the backend can normalize Kubernetes client responses into simple JSON for the UI.

## 4. Backend implementation

- **Framework**: FastAPI.
- **Route organization**:
  - `backend/app/main.py` creates the app and includes route modules.
  - `backend/app/routes/health.py`: `GET /api/health`, `GET /api/health/db`.
  - `backend/app/routes/books.py`: `GET /api/books` with optional search.
  - `backend/app/routes/cart.py`: `GET /api/cart`, `POST /api/cart`, `PUT /api/cart/{book_id}`, `DELETE /api/cart/{book_id}`.
  - `backend/app/routes/orders.py`: `POST /api/orders`, `GET /api/orders`.
  - `backend/app/routes/admin_books.py`: `POST /api/admin/books`, `PATCH /api/admin/books/{book_id}/stock`, `DELETE /api/admin/books/{book_id}`.
  - `backend/app/routes/cluster_status.py`: `GET /api/admin/cluster/status`.
- **Database access**:
  - `backend/app/db.py` reads DB settings from environment variables.
  - The backend opens psycopg connections with `dict_row` so route code can return dictionary-like rows.
  - There is no long-lived connection pool in the current code; each operation uses a new connection context.
- **Schemas and validation**:
  - `backend/app/schemas.py` uses Pydantic models for cart quantities, book creation, and stock deltas.
  - Pydantic field constraints prevent invalid negative prices, negative initial stock, and non-positive cart quantities.
- **Error handling style**:
  - expected business conflicts use `HTTPException` with `400`, `404`, or `409`,
  - unexpected database errors are returned as `500` with a database error message,
  - health DB failures return `503`.
- **Why backend is the right place to read Kubernetes API**:
  - it can use in-cluster ServiceAccount credentials,
  - it can fall back to local kubeconfig for development,
  - RBAC is namespace-scoped and read-only,
  - the browser receives safe aggregated status instead of Kubernetes credentials.

## 5. Database design

The schema is in `database/schema.sql`.

### `books`

- Primary key: `id SERIAL PRIMARY KEY`.
- Fields: `title`, `author`, `category`, `price`, `stock`, `created_at`.
- Constraints: `title` is required, `price >= 0`, `stock >= 0`.
- Purpose: catalog and inventory source of truth.

### `carts`

- Primary key: `id SERIAL PRIMARY KEY`.
- Foreign key: `book_id REFERENCES books(id) ON DELETE CASCADE`.
- Unique key: `(user_id, book_id)` so one user cannot have duplicate rows for the same book.
- Constraint: `quantity > 0`.
- Purpose: current demo user's cart.

### `orders`

- Primary key: `id SERIAL PRIMARY KEY`.
- Fields: `user_id`, `total_price`, `status`, `created_at`.
- Constraint: `total_price >= 0`.
- Default status: `CREATED`.
- Purpose: order-level record.

### `order_items`

- Primary key: `id SERIAL PRIMARY KEY`.
- Foreign keys:
  - `order_id REFERENCES orders(id) ON DELETE CASCADE`,
  - `book_id REFERENCES books(id)`.
- Fields: `quantity`, `price`.
- Constraints: `quantity > 0`, `price >= 0`.
- Purpose: item-level historical order detail.

### Important design decisions

- **Price snapshot**: `order_items.price` stores the purchase-time price, so historical orders remain accurate even if the catalog price changes later.
- **Stock field**: `books.stock` enables inventory validation and HPA-friendly read paths on the catalog.
- **Historical order preservation**: `order_items` references `books` without cascade delete. This prevents accidental removal of catalog rows that historical order records depend on.
- **Delete conflicts**: the admin delete API returns conflict if a book is referenced by `order_items`, because deleting it would break historical order joins.

## 6. Transaction consistency

The place-order flow in `backend/app/routes/orders.py` is transactional:

1. Read the current cart for the demo user.
2. Join cart items to books.
3. Lock relevant book rows with `FOR UPDATE OF b`.
4. Validate that every book has enough stock.
5. Create an `orders` row.
6. Create `order_items` rows using the purchase-time item price.
7. Decrement `books.stock` for each item.
8. Clear the cart.
9. Commit the transaction.
10. Roll back automatically if an exception escapes before commit.

Why this matters:

- prevents negative stock when concurrent orders occur,
- avoids partial order creation,
- keeps inventory and orders consistent,
- ensures the cart is cleared only after order data and stock updates succeed.

## 7. Docker Compose workflow

`docker-compose.yml` defines local full-stack development services:

- **`db`**:
  - image `postgres:16`,
  - publishes host port `5432`,
  - mounts `database/schema.sql` and `database/seed.sql` into PostgreSQL initialization,
  - uses a health check with `pg_isready`.
- **`backend`**:
  - builds `./backend`,
  - image `bookstore-backend:latest`,
  - publishes host port `8000`,
  - uses DB environment variables and waits for the DB health condition.
- **`frontend`**:
  - builds `./frontend`,
  - image `bookstore-frontend:latest`,
  - publishes host port `8080`,
  - depends on the backend.

Local URLs:

- Frontend: `http://localhost:8080`
- Backend health: `http://localhost:8000/api/health`
- Frontend-proxied health: `http://localhost:8080/api/health`

Smoke tests:

```bash
./scripts/test-api.sh
BASE_URL=http://localhost:8000 ./scripts/test-admin-api.sh
```

## 8. Kubernetes deployment

Kubernetes manifests are in `k8s/`.

| Object | File | Why it exists |
|---|---|---|
| Namespace | `k8s/namespace.yaml` | Isolates project resources under `bookstore`. |
| ConfigMap | `k8s/configmap.yaml` | Stores non-secret app configuration such as DB host, port, DB name, and demo user id. |
| Secret | `k8s/secret.yaml` | Stores demo DB username/password separately from non-secret config. |
| PostgreSQL Deployment | `k8s/postgres-deployment.yaml` | Runs PostgreSQL in Kubernetes. |
| PVC | `k8s/postgres-deployment.yaml` | Persists PostgreSQL data across Pod restarts. |
| PostgreSQL Service | `k8s/postgres-service.yaml` | Provides stable in-cluster DNS name `postgres-service`. |
| PostgreSQL init Job | `k8s/postgres-init-job.yaml` | Runs schema and seed SQL after PostgreSQL is ready. |
| Backend Deployment | `k8s/backend-deployment.yaml` | Runs two FastAPI backend replicas with probes and resource requests/limits. |
| Backend Service | `k8s/backend-service.yaml` | Provides stable in-cluster backend access on port `8000`. |
| Frontend Deployment | `k8s/frontend-deployment.yaml` | Runs two Nginx/React frontend replicas with probes. |
| Frontend Service | `k8s/frontend-service.yaml` | Exposes frontend as NodePort `30080`. |
| Ingress | `k8s/ingress.yaml` | Optional host-based `bookstore.local` routing for `/` and `/api`. |
| HPA | `k8s/hpa.yaml` | Autos-scales backend Deployment based on CPU utilization. |
| RBAC | `k8s/backend-rbac.yaml` | Gives backend read-only access to Pods, Deployments, HPAs, and Pod metrics. |

## 9. Image update strategy in Minikube

The project uses stable local tags:

- `bookstore-backend:latest`
- `bookstore-frontend:latest`

That is convenient for a course project, but it creates a stale image risk in Minikube. If a Pod already has a same-tag image and `imagePullPolicy: IfNotPresent`, `kubectl apply` alone may not replace the running code.

`./scripts/k8s-rebuild-and-deploy.sh` handles this correctly:

1. verifies prerequisites,
2. builds backend image,
3. verifies backend image contains `admin_books.py`,
4. builds frontend image,
5. saves current backend/frontend replica counts,
6. scales backend/frontend Deployments to zero,
7. removes old same-tag images inside Minikube,
8. loads fresh backend/frontend images into Minikube,
9. applies manifests and PostgreSQL init ConfigMap/Job logic,
10. restores backend/frontend replica counts,
11. waits for rollouts,
12. verifies a running backend Pod contains `admin_books.py`.

PostgreSQL is not scaled down by this workflow, so demo data is preserved unless the init Job is explicitly forced with `FORCE_POSTGRES_INIT=1`.

This is an important defense point: declarative manifests describe desired Kubernetes objects, but local image lifecycle still matters when reusing stable tags in Minikube.

## 10. HPA autoscaling

The HPA is defined in `k8s/hpa.yaml`:

- target: backend Deployment,
- metric: CPU utilization,
- `minReplicas: 2`,
- `maxReplicas: 5`,
- target average CPU utilization: `50%`.

The backend Deployment defines CPU requests (`100m`). This is required because HPA utilization is calculated relative to requested CPU, not total node CPU.

Why HPA CPU can exceed `100%`:

- If a container requests `100m` CPU and uses `300m`, Kubernetes can report about `300%` utilization for HPA purposes.
- This does not mean the node is at 300% CPU; it means the container is using three times its requested CPU.

Expected behavior:

- Before load: backend runs at 2 replicas and HPA has a known CPU value.
- During load: CPU rises above 50%, desired replicas increase, and new backend Pods are created.
- After load: HPA eventually scales back toward 2 replicas.
- Scale-down can take several minutes because Kubernetes intentionally stabilizes scale-down decisions to avoid flapping.

## 11. metrics-server repair script

`./scripts/k8s-fix-metrics-server.sh` exists because HPA depends on the Kubernetes Metrics API. In Minikube, metrics-server can fail if the addon uses a bad tag+digest image or cannot pull the selected image. When that happens:

- metrics-server may show `ImagePullBackOff` or `ErrImagePull`,
- `kubectl top` fails,
- HPA displays `<unknown>` CPU values.

The script:

1. enables the Minikube metrics-server addon,
2. waits for metrics-server Deployment and Pod objects,
3. detects image pull or pinned digest problems,
4. patches metrics-server to a valid tag-only image (`registry.k8s.io/metrics-server/metrics-server:v0.8.1`) with a regional fallback,
5. waits for rollout,
6. verifies `kubectl top nodes`,
7. verifies `kubectl top pods -n bookstore`,
8. verifies HPA no longer shows `<unknown>`.

## 12. HPA demo script

`./scripts/k8s-hpa-demo.sh` is the repeatable autoscaling demo workflow.

It:

- requires `hey`,
- defaults to `TARGET_URL=http://$(minikube ip):30080/api/books`,
- defaults to `DURATION=180s` and `CONCURRENCY=50`,
- verifies namespace, backend Deployment, HPA, and metrics readiness,
- prints baseline HPA, Deployment, Pod, and `top pods` evidence,
- runs sustained load with `hey`,
- monitors HPA/Deployment/Pods/metrics while load is running,
- detects replica increases,
- prints `hey` output,
- prints final HPA evidence and `describe hpa`,
- optionally observes scale-down for `SCALE_DOWN_WAIT=300` seconds.

Useful customization:

```bash
DURATION=240s CONCURRENCY=60 ./scripts/k8s-hpa-demo.sh
OBSERVE_SCALE_DOWN=false ./scripts/k8s-hpa-demo.sh
```

## 13. In-app Monitoring Dashboard

Purpose: provide demo-oriented observability inside the application without adding Prometheus, Grafana, another service, or a monitoring database.

Flow:

```text
React Monitoring Dashboard -> FastAPI /api/admin/cluster/status -> Kubernetes Python client -> Kubernetes API
```

Backend status API behavior:

- loads in-cluster Kubernetes config when running in Kubernetes,
- falls back to local kubeconfig when available,
- reads the backend Deployment,
- reads `backend-hpa`,
- lists backend Pods with selector `app=backend`,
- reads `metrics.k8s.io` Pod metrics when metrics-server is available,
- returns `metricsAvailable: false` and warnings when metrics are unavailable.

RBAC:

- ServiceAccount: `bookstore-backend`,
- Role: namespace-scoped read/list/watch for Pods, Deployments, HPAs, and Pod metrics,
- RoleBinding: binds the role to backend Pods.

Frontend dashboard behavior:

- shows Deployment replica status,
- shows HPA CPU/replica status,
- shows a backend Pods table,
- shows frontend-only rolling replica and CPU charts,
- refreshes automatically every 5 seconds,
- keeps chart samples only in browser memory.

Limitations:

- browser refresh resets chart history,
- no long-term metrics retention,
- no alerting,
- demo-oriented observability rather than production monitoring.

Why no Prometheus/Grafana:

- the course demo focuses on Kubernetes HPA mechanics and application-level visibility,
- adding Prometheus/Grafana would add services and operational complexity,
- the project intentionally avoids new services for the final demo.

## 14. Admin Demo

Purpose: demonstrate catalog and inventory management without leaving the bookstore application.

Implemented operations:

- add a book,
- increase/decrease stock by delta,
- delete an unreferenced book.

Backend safeguards:

- title is required,
- price and initial stock cannot be negative,
- cart quantities must be positive,
- stock updates cannot make stock negative,
- deleting a book referenced by historical `order_items` returns conflict.

Security note:

- the Admin Demo is intentionally unauthenticated for a course demo,
- production would require authentication, authorization/RBAC, audit logs, and likely separate admin roles.

## 15. Public demo exposure

The Kubernetes frontend Service is a NodePort Service on `30080`. On a cloud VM, the Minikube IP is usually internal to the VM and not directly reachable from a public browser.

The existing exposure script:

```bash
PUBLIC_PORT=3000 ./scripts/k8s-expose-demo.sh
```

uses host-level iptables rules to forward public TCP `3000` to `$(minikube ip):30080` and adds MASQUERADE/FORWARD rules so return traffic works.

Key points:

- demo URL: `http://<server-public-ip>:3000`,
- HTTP only,
- cloud firewall/security group must allow TCP `3000`,
- cleanup uses `PUBLIC_PORT=3000 NODE_PORT=30080 ./scripts/k8s-expose-demo.sh --cleanup`,
- production would normally use a cloud LoadBalancer, public Ingress, DNS, and TLS instead.

## 16. Testing and verification scripts

| Script | What it validates |
|---|---|
| `scripts/test-api.sh` | Local backend API smoke flow: health, DB health, books, cart, add to cart, place order, list orders. |
| `scripts/test-admin-api.sh` | Admin API smoke flow: create book, increase/decrease stock, delete book, list books. Uses `BASE_URL`. |
| `scripts/k8s-test-local.sh` | Kubernetes NodePort smoke checks: namespace, Pods, frontend-service NodePort `30080`, `/`, `/api/health`, `/api/health/db`, `/api/books`. |
| `scripts/k8s-status.sh` | Minikube and Kubernetes resource summary: all resources, Pods, Services, Ingress, HPA, and backend/frontend endpoints. |
| `scripts/k8s-fix-metrics-server.sh` | metrics-server addon repair/check plus `kubectl top` and HPA metric verification. |
| `scripts/k8s-hpa-demo.sh` | Repeatable HPA load demo using `hey`, with HPA/Deployment/Pod/top evidence and optional scale-down observation. |
| `scripts/monitor-k8s.sh` | Quick Kubernetes monitoring snapshot: Pods, HPA, node metrics, and Pod metrics. |
| `scripts/perf-test.sh` | General performance/load test against `TARGET_URL`; uses `hey` if present or a small curl fallback. |

Other useful scripts:

- `scripts/k8s-rebuild-and-deploy.sh`: standard local-image rebuild and Kubernetes deploy workflow.
- `scripts/k8s-expose-demo.sh`: iptables public demo exposure and cleanup.
- `scripts/k8s-cleanup.sh`: deletes Kubernetes resources in the `bookstore` namespace.
- `scripts/compose-up.sh`, `scripts/compose-status.sh`, `scripts/compose-logs.sh`, `scripts/compose-down.sh`: Docker Compose helpers.

## 17. Tools and technologies

| Tool/technology | Where it is used | Why it is used | What it demonstrates |
|---|---|---|---|
| React/Vite | `frontend/` | Fast SPA development and static build output | Modern frontend tier |
| Nginx | frontend container | Serves static frontend and proxies `/api` | Web server/reverse proxy tier |
| FastAPI | `backend/` | REST API with Python and Pydantic validation | Backend service tier |
| PostgreSQL | Compose `db`, Kubernetes `postgres` | Relational persistence and transactions | Stateful database tier |
| Docker | backend/frontend images and PostgreSQL runtime | Container packaging | Reproducible services |
| Docker Compose | `docker-compose.yml` | Local multi-service workflow | Local integration testing |
| Minikube | local/single-node Kubernetes | Course-friendly Kubernetes cluster | Kubernetes deployment practice |
| Kubernetes | `k8s/` manifests | Declarative orchestration | Cloud-native operations |
| ConfigMap | `k8s/configmap.yaml` | Non-secret environment config | Separation of config from images |
| Secret | `k8s/secret.yaml` | Demo DB credentials | Secret object usage |
| PVC | `k8s/postgres-deployment.yaml` | PostgreSQL data persistence | Stateful workload storage |
| Service | backend/frontend/postgres services | Stable networking and discovery | Service abstraction |
| Ingress | `k8s/ingress.yaml` | Optional host/path routing | HTTP routing in Kubernetes |
| HPA | `k8s/hpa.yaml` | Backend autoscaling by CPU | Elastic scaling |
| metrics-server | Minikube addon | Supplies Metrics API for `kubectl top` and HPA | Resource metrics dependency |
| Kubernetes Python client | backend `cluster_status.py` | Backend reads Kubernetes API | In-app cluster status integration |
| `hey` | HPA/perf scripts | Sustained HTTP load generation | Repeatable autoscaling trigger |
| iptables | `k8s-expose-demo.sh` | Public demo port forwarding to NodePort | Demo network exposure workaround |
| Bash scripts | `scripts/` | Repeatable operational workflows | Deployment/test automation |

## 18. Possible defense questions and answers

**Q: Why use Kubernetes instead of only Docker Compose?**

A: Docker Compose is good for local multi-container development, but Kubernetes demonstrates cloud-native deployment concerns: declarative manifests, Services, health probes, ConfigMaps, Secrets, PVCs, Jobs, RBAC, Ingress, and HPA autoscaling.

**Q: Why is `kubectl apply` not enough after code changes?**

A: The project uses stable local tags like `bookstore-backend:latest`. With `IfNotPresent`, Minikube can reuse an old same-tag image. The rebuild/deploy script rebuilds, removes stale Minikube images, reloads images, reapplies manifests, and recreates Pods.

**Q: Why can HPA show 300% CPU?**

A: HPA CPU utilization is relative to the container CPU request. If the backend requests `100m` CPU and uses `300m`, HPA can report about `300%`.

**Q: Why does HPA need metrics-server?**

A: HPA needs the Kubernetes Metrics API to know current CPU usage. metrics-server supplies those resource metrics. Without it, HPA CPU often appears as `<unknown>`.

**Q: Why does scale-down take time?**

A: Kubernetes HPA uses stabilization behavior to avoid rapid scaling up and down. After load stops, it waits before reducing replicas.

**Q: Why does the frontend not directly call the Kubernetes API?**

A: The browser should not receive Kubernetes credentials. The backend can use ServiceAccount credentials, read-only RBAC, and a controlled JSON endpoint.

**Q: Why add backend RBAC?**

A: The Monitoring Dashboard needs the backend to read Deployment, HPA, Pod, and metrics data. RBAC grants only namespace-scoped read/list/watch permissions needed for that endpoint.

**Q: Is the Monitoring Dashboard production-grade?**

A: No. It is intentionally lightweight and demo-oriented. It has no long-term storage, alerting, or dashboards across multiple services.

**Q: Why not use Prometheus/Grafana?**

A: The project constraints avoid adding new services. The goal is to demonstrate HPA and lightweight in-app visibility, not build a full monitoring stack.

**Q: What happens if metrics-server is unavailable?**

A: `kubectl top` fails, HPA may show `<unknown>`, and the dashboard returns `metricsAvailable: false` with warnings. The app itself can still serve catalog/cart/order APIs.

**Q: How do you prevent negative stock?**

A: The database has a `stock >= 0` check, admin stock update uses `stock + delta >= 0`, and place-order validates stock while locking relevant book rows before decrementing.

**Q: Why store price in `order_items`?**

A: It preserves the purchase-time price so historical orders remain accurate even if catalog prices change later.

**Q: Why can deleting a book fail?**

A: If historical `order_items` reference the book, deleting it would break order history joins. The admin API returns `409 Conflict` instead.

**Q: Is the Admin page secure?**

A: No. It is intentionally unauthenticated for course demo convenience. Production would need authentication, authorization, audit logs, and probably separate admin roles.

**Q: How would you improve this for production?**

A: Add authentication/RBAC, TLS, real secret management, CI/CD, cloud LoadBalancer or public Ingress, managed database, backups, Prometheus/Grafana or equivalent observability, alerting, and multi-node/high-availability deployment.

**Q: What is the role of ConfigMap and Secret?**

A: ConfigMap stores non-secret configuration like DB host and DB name. Secret stores sensitive values like DB username/password. The demo Secret is not production-grade secret management.

**Q: What is the role of PVC?**

A: The PVC gives PostgreSQL persistent storage so data can survive Pod recreation.

**Q: How does public browser access work in this Minikube setup?**

A: The frontend is exposed internally through NodePort `30080`. The iptables script forwards public TCP `3000` on the host to `$(minikube ip):30080` and adds NAT/FORWARD rules.

**Q: What are the project limitations?**

A: It uses single-node Minikube, demo-only admin access, demo-only iptables exposure, simple Secret management, no payment/shipping, no Prometheus/Grafana, and lightweight dashboard history only in browser memory.

## 19. Known limitations and future work

Known limitations:

- Admin Demo has no authentication.
- iptables public exposure is demo-only.
- Monitoring Dashboard is lightweight and not long-term monitoring.
- No Prometheus/Grafana.
- No real payment or shipping workflow.
- Single-node Minikube cluster.
- Demo Secret values are not production-grade secret management.
- PostgreSQL is a simple in-cluster Deployment rather than a managed HA database.

Possible future work:

- add user authentication and admin RBAC,
- add TLS and production Ingress/LoadBalancer,
- move secrets to a cloud secret manager or sealed/external secrets,
- add CI/CD image builds and deployments,
- add Prometheus/Grafana or a managed observability stack,
- add structured logs and alerting,
- add payment/shipping integration,
- use a managed PostgreSQL service with backups,
- run on a multi-node Kubernetes cluster.

## 20. Final presentation talking points

Use this as a short 2-3 minute opening script:

> This project is a cloud-native online bookstore built for DSAA 4040. It uses a three-tier architecture: a React/Vite frontend served by Nginx, a FastAPI backend, and a PostgreSQL database. Users can browse and search books, manage a cart, place orders, and view order history. The backend handles order placement transactionally by validating stock, creating order records, decrementing inventory, and clearing the cart atomically.
>
> For local development, the full stack runs with Docker Compose. For the cloud-native part, the same application is deployed to Minikube with Kubernetes manifests for namespace isolation, ConfigMaps, Secrets, Deployments, Services, health probes, a PostgreSQL PVC, an initialization Job, Ingress, backend RBAC, and an HPA. The backend is autoscaled from 2 to up to 5 replicas based on CPU utilization.
>
> The live demo will show the user bookstore flow, then the Admin Demo for adding a temporary book and adjusting stock, then the in-app Monitoring Dashboard. The dashboard calls a FastAPI cluster-status endpoint, and the backend reads Kubernetes Deployment, HPA, Pod, and metrics data using read-only RBAC. Finally, the HPA demo script generates load with `hey`, showing CPU rise, backend Pods scale out, and the dashboard charts update.
>
> The main lesson is that cloud-native development is not just writing application code. It also includes container image management, Kubernetes resource design, health checks, persistent storage, runtime configuration, autoscaling dependencies like metrics-server, repeatable scripts, and practical demo/operations workflows.
