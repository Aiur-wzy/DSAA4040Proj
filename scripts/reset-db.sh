#!/usr/bin/env bash
set -euo pipefail

echo "WARNING: This will delete the PostgreSQL volume and reset the database."
docker compose down -v
docker compose up --build
