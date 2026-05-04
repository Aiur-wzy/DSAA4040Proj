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



