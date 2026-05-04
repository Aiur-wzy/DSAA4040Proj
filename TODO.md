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
