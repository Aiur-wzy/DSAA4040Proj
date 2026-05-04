# Cloud-Native Online Bookstore on Kubernetes

## Current Status
- Database foundation implemented under `database/`.
- Backend API foundation implemented under `backend/`.
- Frontend page framework implemented under `frontend/`.
- Docker Compose integration added for local full-stack development.
- Initial Kubernetes manifest foundation added under `k8s/`.
- Verification, monitoring, and report scaffold support files added under `scripts/` and `report/`.

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
- Kubernetes baseline manifests (namespace/config/deployments/services/ingress/hpa)
- Kubernetes PostgreSQL init Job manifest
- Verification helper scripts and report scaffold

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

## Smoke testing scripts
- `./scripts/test-api.sh`
- Override base URL examples:
  - `BASE_URL=http://localhost:8080 ./scripts/test-api.sh`
  - `BASE_URL=http://bookstore.local ./scripts/test-api.sh`

## Docker Compose helper scripts
- `./scripts/compose-status.sh`
- `./scripts/compose-logs.sh`
- Example: `./scripts/compose-logs.sh backend`

## Kubernetes helper scripts
- `./scripts/k8s-apply.sh`
- `./scripts/k8s-status.sh`
- `./scripts/k8s-cleanup.sh`

## Monitoring/performance scripts
- `./scripts/monitor-k8s.sh`
- `./scripts/perf-test.sh`
- Performance override example:
  - `DURATION=2m CONCURRENCY=50 TARGET_URL=http://bookstore.local/api/books ./scripts/perf-test.sh`

## Report scaffold
- `report/final_report.md`
- Contains section structure, TODO markers, and placeholders for screenshots/outputs/results.

## Docker Compose verification checklist
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
- Kubernetes DB init Job not yet executed.
- API smoke tests not yet executed.
- Compose helper scripts not yet executed.
- Kubernetes helper scripts not yet executed.
- Monitoring/performance scripts not yet executed.
- Report results still pending real runtime evidence.
- Runtime testing may still need to be performed locally if Docker/Kubernetes is unavailable in this execution environment.
