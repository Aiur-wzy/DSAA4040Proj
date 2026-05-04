#!/usr/bin/env bash
set -euo pipefail

echo "=== Docker Compose Status ==="
docker compose ps

echo
echo "=== Useful URLs ==="
echo "Frontend:              http://localhost:8080"
echo "Backend health:        http://localhost:8000/api/health"
echo "Backend DB health:     http://localhost:8000/api/health/db"
echo "Backend books:         http://localhost:8000/api/books"
echo "Frontend -> API route: http://localhost:8080/api/health"
