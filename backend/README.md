# Bookstore Backend API (FastAPI + PostgreSQL)

This backend provides the initial API foundation for the DSAA 4040 cloud-native online bookstore project. It includes:
- Health check endpoints
- Book listing and search
- Cart operations for a configured demo user
- Transactional order placement and order history retrieval

## Required Environment Variables

- `DB_HOST`
- `DB_PORT`
- `DB_NAME`
- `DB_USER`
- `DB_PASSWORD`
- `APP_USER_ID` (defaults to `demo-user`)

See `.env.example` for local defaults.

## Install Dependencies

From the `backend/` directory:

```bash
pip install -r requirements.txt
```

## Run Locally

From the `backend/` directory:

```bash
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

## API Endpoints

- `GET /api/health`
- `GET /api/health/db`
- `GET /api/books`
- `GET /api/books?search=database`
- `GET /api/cart`
- `POST /api/cart`
- `PUT /api/cart/{book_id}`
- `DELETE /api/cart/{book_id}`
- `POST /api/orders`
- `GET /api/orders`

## Runtime Testing Status

Runtime testing against a live PostgreSQL instance is intentionally deferred for now and should be completed later after Docker/local database setup.
