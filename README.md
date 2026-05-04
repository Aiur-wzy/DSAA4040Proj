# Cloud-Native Online Bookstore on Kubernetes

## Current Status
- Database foundation implemented under `database/`.
- Backend API foundation implemented under `backend/`.
- Frontend page framework implemented under `frontend/`.
- Docker Compose integration added for local full-stack development.

## Planned Architecture
Browser → Frontend → Backend API → PostgreSQL Database

## Current Completed Part
- PostgreSQL schema
- Initial seed data
- Basic database test script
- Transactional order placement SQL script
- FastAPI backend foundation (health, books, cart, orders)
- React + Vite frontend page framework (books, cart, orders, health status)
- Docker Compose setup for db/backend/frontend

## Docker Compose

### Services
Docker Compose runs three services:
- `db`: PostgreSQL 16
- `backend`: FastAPI backend
- `frontend`: React frontend served by Nginx

### Start the stack
```bash
docker compose up --build
```

### Stop the stack
```bash
docker compose down
```

### Reset database
```bash
docker compose down -v
docker compose up --build
```

### Database initialization behavior
`database/schema.sql` and `database/seed.sql` are automatically executed only when the PostgreSQL data volume is first created.

After changing `schema.sql` or `seed.sql`, recreate the data volume so initialization scripts run again:

```bash
docker compose down -v
docker compose up --build
```

### Useful URLs
- Frontend: http://localhost:8080
- Backend health: http://localhost:8000/api/health
- Backend DB health: http://localhost:8000/api/health/db
- Backend books API: http://localhost:8000/api/books
- Frontend-proxied API health: http://localhost:8080/api/health

### Docker Compose verification checklist
- [ ] db container starts
- [ ] db healthcheck passes
- [ ] schema is initialized
- [ ] seed data is inserted
- [ ] backend starts after db is healthy
- [ ] frontend page loads
- [ ] `/api` requests through frontend are proxied to backend
- [ ] book list/search works
- [ ] cart operations work
- [ ] order placement works
- [ ] stock decreases
- [ ] cart clears
- [ ] order history displays

## Pending runtime verification
- Runtime testing may still need to be performed locally if Docker is unavailable in this execution environment.
