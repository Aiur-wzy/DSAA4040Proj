# Database Layer

This folder contains the PostgreSQL foundation for the cloud-native online bookstore. It supports:
- Book catalog browsing and search
- Shopping cart storage
- Order persistence
- Transactional stock deduction during order placement

## Table Overview

- **books**: book catalog and inventory.
- **carts**: temporary shopping cart entries.
- **orders**: order-level records.
- **order_items**: item-level order details and purchase-time price snapshot.

## Run PostgreSQL Locally with Docker

```bash
docker run --name bookstore-postgres \
  -e POSTGRES_DB=bookstore \
  -e POSTGRES_USER=bookstore \
  -e POSTGRES_PASSWORD=bookstore123 \
  -p 5432:5432 \
  -d postgres:16
```

## Apply Schema

```bash
docker exec -i bookstore-postgres \
  psql -U bookstore -d bookstore < database/schema.sql
```

## Load Seed Data

```bash
docker exec -i bookstore-postgres \
  psql -U bookstore -d bookstore < database/seed.sql
```

## Run Basic Test Script

```bash
docker exec -i bookstore-postgres \
  psql -U bookstore -d bookstore < database/test.sql
```

## Run Transactional Order Placement

```bash
docker exec -i bookstore-postgres \
  psql -U bookstore -d bookstore < database/place_order.sql
```

## Inspect Database State

```bash
docker exec -it bookstore-postgres psql -U bookstore -d bookstore
```

Inside `psql`:

```sql
\dt
SELECT * FROM books;
SELECT * FROM carts;
SELECT * FROM orders;
SELECT * FROM order_items;
```

This database layer will later be connected to a Flask/FastAPI backend.
