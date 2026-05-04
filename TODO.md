Phase 1: Database foundation
    schema.sql
    seed.sql
    transaction SQL

Phase 2: Backend API
    FastAPI
    database connection
    books/cart/orders API

Phase 3: Frontend
    React page
    book list
    cart
    order button

Phase 4: Local integration
    Dockerfile
    Docker Compose
    db + backend + frontend

Phase 5: Kubernetes deployment
    Deployment
    Service
    ConfigMap
    Secret
    Ingress

Phase 6: Cloud-native features
    health checks
    HPA
    metrics-server
    monitoring commands
    load testing

Phase 7: Report and demo
    architecture diagram
    deployment screenshots
    HPA experiment
    performance table


## TODO / Verification Plan

The database foundation has been implemented but has not yet been executed against a live PostgreSQL instance.

Pending verification:

- [ ] Start PostgreSQL with Docker
- [ ] Run `database/schema.sql`
- [ ] Run `database/seed.sql`
- [ ] Run `database/test.sql`
- [ ] Run `database/place_order.sql`
- [ ] Verify that:
  - [ ] `books` contains initial seed data
  - [ ] `carts` supports upsert behavior
  - [ ] `orders` can be created
  - [ ] `order_items` stores order details
  - [ ] stock is decremented after order placement
  - [ ] cart is cleared after order placement


## Backend Runtime Verification TODO

### Environment and startup

- [ ] Create Python virtual environment under `backend/`
- [ ] Install `backend/requirements.txt`
- [ ] Start FastAPI with `uvicorn app.main:app --reload --host 0.0.0.0 --port 8000`
- [ ] Open Swagger UI at `http://localhost:8000/docs`

### Health endpoints

- [ ] `GET /api/health` returns service status without requiring PostgreSQL
- [ ] `GET /api/health/db` returns 503 when PostgreSQL is unavailable
- [ ] `GET /api/health/db` returns database connected when PostgreSQL is running

### Database setup

- [ ] Start PostgreSQL using Docker
- [ ] Run `database/schema.sql`
- [ ] Run `database/seed.sql`
- [ ] Verify `books`, `carts`, `orders`, and `order_items` exist
- [ ] Verify 8 seed books are inserted

### Books API

- [ ] `GET /api/books` returns all seed books
- [ ] `GET /api/books?search=database` returns matching books
- [ ] `GET /api/books?search=notexist` returns an empty list

### Cart API

- [ ] `GET /api/cart` returns an empty cart initially
- [ ] `POST /api/cart` adds a new book
- [ ] Repeated `POST /api/cart` increments quantity using upsert
- [ ] `POST /api/cart` with nonexistent `book_id` returns 404
- [ ] `POST /api/cart` with invalid quantity returns validation error
- [ ] `PUT /api/cart/{book_id}` updates quantity
- [ ] `PUT /api/cart/{book_id}` for missing cart item returns 404
- [ ] `DELETE /api/cart/{book_id}` removes item
- [ ] `DELETE /api/cart/{book_id}` for missing cart item returns 404

### Orders API

- [ ] `POST /api/orders` with empty cart returns 400
- [ ] `POST /api/orders` with valid cart creates one order
- [ ] Valid order placement creates corresponding `order_items`
- [ ] Valid order placement decrements `books.stock`
- [ ] Valid order placement clears `carts`
- [ ] `GET /api/orders` returns order history with item details
- [ ] Insufficient stock during order placement returns 409
- [ ] Insufficient stock does not create partial order data
- [ ] Insufficient stock does not decrement stock
- [ ] Insufficient stock does not clear cart

### Dockerfile

- [ ] `docker build -t bookstore-backend:latest ./backend` succeeds
- [ ] Backend container starts successfully
- [ ] Containerized backend can connect to PostgreSQL in later Docker Compose setup



## Frontend Runtime Verification TODO

- [ ] Run `cd frontend && npm install`
- [ ] Run `npm run build`
- [ ] Run `npm run dev`
- [ ] Open `http://localhost:5173`
- [ ] Verify frontend loads without JavaScript errors
- [ ] Verify `/api` calls use `VITE_API_BASE_URL`
- [ ] Verify book list renders when backend is running
- [ ] Verify search works
- [ ] Verify add-to-cart works
- [ ] Verify cart update works
- [ ] Verify cart delete works
- [ ] Verify place-order works
- [ ] Verify order history renders
- [ ] Verify DB health failure displays warning but does not crash UI
- [ ] Build frontend Docker image
- [ ] Verify Nginx SPA fallback works
- [ ] Verify Nginx `/api` proxy works in Docker Compose

Docker Compose 这一部分的 TODO list 应该重点记录：**它现在只是配置好了，但还没有真实运行验证**。你可以直接把下面这一段加到 `README.md` 或单独的 `TODO.md` 里。


## Docker Compose Runtime Verification TODO

### 1. Docker environment

- [ ] Verify Docker is installed locally
- [ ] Verify Docker Compose is available

```bash
docker --version
docker compose version
````

### 2. Compose configuration validation

* [ ] Validate the Compose file syntax

```bash
docker compose config
```

Expected result:

* No YAML syntax errors
* Exactly three services are listed:

  * `db`
  * `backend`
  * `frontend`
* One named volume is listed:

  * `postgres-data`

### 3. Build all services

* [ ] Build all Compose services

```bash
docker compose build
```

Expected result:

* PostgreSQL image can be pulled
* Backend image builds successfully from `./backend`
* Frontend image builds successfully from `./frontend`
* `npm install` / frontend build succeeds inside the frontend Docker build
* Python dependencies install successfully inside the backend Docker build

### 4. Start the full stack

* [ ] Start all services

```bash
docker compose up --build
```

Expected result:

* `bookstore-db` starts successfully
* PostgreSQL healthcheck passes
* `bookstore-backend` starts after database becomes healthy
* `bookstore-frontend` starts successfully
* No container exits unexpectedly

### 5. Check running containers

* [ ] Verify all containers are running

```bash
docker compose ps
```

Expected result:

* `bookstore-db` is running and healthy
* `bookstore-backend` is running
* `bookstore-frontend` is running

### 6. Verify database initialization

* [ ] Connect to PostgreSQL container

```bash
docker exec -it bookstore-db psql -U bookstore -d bookstore
```

Inside psql:

```sql
\dt
SELECT COUNT(*) FROM books;
SELECT * FROM books;
```

Expected result:

* Tables exist:

  * `books`
  * `carts`
  * `orders`
  * `order_items`
* `books` contains 8 seed records

### 7. Verify backend API through direct backend port

* [ ] Backend health endpoint works

```bash
curl http://localhost:8000/api/health
```

* [ ] Backend database health endpoint works

```bash
curl http://localhost:8000/api/health/db
```

* [ ] Backend books API works

```bash
curl http://localhost:8000/api/books
```

Expected result:

* `/api/health` returns service OK
* `/api/health/db` returns database connected
* `/api/books` returns seeded books

### 8. Verify frontend page

* [ ] Open frontend in browser

```text
http://localhost:8080
```

Expected result:

* React page loads successfully
* No blank page
* No obvious JavaScript errors in browser console
* Backend/DB status is displayed
* Book list is displayed

### 9. Verify Nginx frontend-to-backend proxy

* [ ] Test backend through frontend Nginx proxy

```bash
curl http://localhost:8080/api/health
curl http://localhost:8080/api/books
```

Expected result:

* Requests to `localhost:8080/api/...` are proxied to backend
* `/api/health` returns backend health
* `/api/books` returns seeded books

### 10. End-to-end business flow through frontend

* [ ] Search for a book
* [ ] Add a book to cart
* [ ] Add the same book again and verify quantity increases
* [ ] Update cart item quantity
* [ ] Remove cart item
* [ ] Add multiple books to cart
* [ ] Place an order
* [ ] Verify cart becomes empty after order placement
* [ ] Verify order history displays the new order
* [ ] Verify book stock decreases after order placement

### 11. Verify database state after frontend order placement

After placing an order from the frontend:

```bash
docker exec -it bookstore-db psql -U bookstore -d bookstore
```

Inside psql:

```sql
SELECT * FROM orders;
SELECT * FROM order_items;
SELECT * FROM carts;
SELECT id, title, stock FROM books ORDER BY id;
```

Expected result:

* `orders` contains the created order
* `order_items` contains order line items
* `carts` is empty for `demo-user`
* `books.stock` decreased correctly

### 12. Reset database behavior

* [ ] Stop services without deleting data

```bash
docker compose down
```

* [ ] Start again

```bash
docker compose up --build
```

Expected result:

* Existing PostgreSQL data is preserved

* [ ] Reset database by deleting volume

```bash
docker compose down -v
docker compose up --build
```

Expected result:

* PostgreSQL data volume is recreated
* `schema.sql` runs again
* `seed.sql` runs again
* Database returns to initial state with 8 books and empty carts/orders/order_items

### 13. Helper scripts

* [ ] Verify compose-up script works

```bash
./scripts/compose-up.sh
```

* [ ] Verify compose-down script works

```bash
./scripts/compose-down.sh
```

* [ ] Verify reset-db script works

```bash
./scripts/reset-db.sh
```

Expected result:

* Scripts run the intended Docker Compose commands
* `reset-db.sh` clearly warns before deleting the database volume

### 14. Error and recovery checks

* [ ] Stop database container and observe backend DB health

```bash
docker compose stop db
curl -i http://localhost:8000/api/health/db
```

Expected result:

* `/api/health/db` returns an error or unavailable status

* [ ] Restart database

```bash
docker compose start db
```

Expected result:

* Database becomes healthy again
* Backend can reconnect or works after restart

### 15. Documentation consistency

* [ ] Verify README Docker Compose commands are correct
* [ ] Verify useful URLs in README work:

  * `http://localhost:8080`
  * `http://localhost:8000/api/health`
  * `http://localhost:8000/api/health/db`
  * `http://localhost:8000/api/books`
  * `http://localhost:8080/api/health`
* [ ] Verify README explains that `/docker-entrypoint-initdb.d/` scripts only run when PostgreSQL volume is first created
* [ ] Verify README explains when to use `docker compose down -v`




