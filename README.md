# Cloud-Native Online Bookstore on Kubernetes

## Current Status
- Database foundation implemented under `database/`.
- Backend API foundation implemented under `backend/`.
- Frontend page framework implemented under `frontend/`.

## Planned Architecture
Browser → Frontend → Backend API → PostgreSQL Database

## Current Completed Part
- PostgreSQL schema
- Initial seed data
- Basic database test script
- Transactional order placement SQL script
- FastAPI backend foundation (health, books, cart, orders)
- React + Vite frontend page framework (books, cart, orders, health status)

## Next Steps
- Execute database scripts against a live PostgreSQL instance
- Run backend API against live PostgreSQL and verify endpoint behavior
- Run frontend against backend and verify end-to-end behavior
- Add Docker Compose
- Deploy to Kubernetes
- Add ConfigMap, Secret, Ingress, HPA, health checks, monitoring, and performance testing

## Pending runtime verification
- Database scripts have not been executed against a live PostgreSQL instance.
- Backend API has not been tested against a live PostgreSQL instance.
- Frontend has not been tested against a running backend yet.
- Docker-based integration testing is planned after the initial project structure is complete.
