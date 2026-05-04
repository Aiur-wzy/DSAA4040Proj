#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"

print_section() {
  echo
  echo "==================== $1 ===================="
}

request() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="${BASE_URL}${path}"

  echo "[$method] $url"
  if [[ -n "$data" ]]; then
    curl -sS -X "$method" "$url" -H 'Content-Type: application/json' -d "$data"
  else
    curl -sS -X "$method" "$url"
  fi
  echo
}

print_section "API Smoke Test"
echo "BASE_URL=${BASE_URL}"

print_section "1) GET /api/health"
request GET /api/health

print_section "2) GET /api/health/db"
request GET /api/health/db

print_section "3) GET /api/books"
request GET /api/books

print_section "4) GET /api/cart"
request GET /api/cart

print_section "5) POST /api/cart"
request POST /api/cart '{"book_id":1,"quantity":1}'

print_section "6) GET /api/cart (after add)"
request GET /api/cart

print_section "7) POST /api/orders"
request POST /api/orders '{}'

print_section "8) GET /api/orders"
request GET /api/orders

echo
echo "Smoke test flow completed."
