# Cloud-Native Online Bookstore on Kubernetes

## Current Status
- Database foundation implemented under `database/`.
- Backend API foundation implemented under `backend/`.

## Planned Architecture
Browser → Frontend → Backend API → PostgreSQL Database

## Current Completed Part
- PostgreSQL schema
- Initial seed data
- Basic database test script
- Transactional order placement SQL script
- FastAPI backend foundation (health, books, cart, orders)

## Next Steps
- Execute database scripts against a live PostgreSQL instance
- Run backend API against live PostgreSQL and verify endpoint behavior
- Implement frontend
- Add Docker Compose
- Deploy to Kubernetes
- Add ConfigMap, Secret, Ingress, HPA, health checks, monitoring, and performance testing

## Pending runtime verification
- Database scripts have not yet been executed against a live PostgreSQL instance.
- Backend API has not yet been tested against a live PostgreSQL instance.
- Docker-based integration testing is planned after the initial project structure is complete.
