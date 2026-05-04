# Frontend (React + Vite)

## What this frontend does
This frontend provides the initial page framework for the DSAA 4040 online bookstore:
- Backend and database health status display
- Book listing and search
- Cart management (add, update quantity, remove)
- Order placement
- Order history display

## Required backend API
The frontend expects the following backend endpoints:
- GET `/api/health`
- GET `/api/health/db`
- GET `/api/books`
- GET `/api/books?search=...`
- GET `/api/cart`
- POST `/api/cart`
- PUT `/api/cart/{book_id}`
- DELETE `/api/cart/{book_id}`
- POST `/api/orders`
- GET `/api/orders`

## Install dependencies
```bash
npm install
```

## Run locally
```bash
npm run dev
```

## Set API base URL
1. Copy `.env.example` to `.env`
2. Set `VITE_API_BASE_URL` as needed

Example:
```env
VITE_API_BASE_URL=http://localhost:8000
```

## Important note
Runtime testing is deferred until database/backend/frontend integration is performed.
