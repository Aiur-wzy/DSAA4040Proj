#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
BOOK_TITLE="Admin Smoke Test Book $(date +%s)"
BOOK_ID=""

print_section() {
  echo
  echo "==================== $1 ===================="
}

request_json() {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local expected_status="$4"
  local url="${BASE_URL}${path}"
  local body_file
  local status

  body_file="$(mktemp)"
  echo "[$method] $url"
  if [[ -n "$data" ]]; then
    status="$(curl -sS -o "$body_file" -w '%{http_code}' -X "$method" "$url" \
      -H 'Content-Type: application/json' -d "$data")"
  else
    status="$(curl -sS -o "$body_file" -w '%{http_code}' -X "$method" "$url")"
  fi

  cat "$body_file"
  echo

  if [[ "$status" != "$expected_status" ]]; then
    echo "Expected HTTP $expected_status but got HTTP $status" >&2
    rm -f "$body_file"
    return 1
  fi

  LAST_BODY_FILE="$body_file"
}

extract_json_field() {
  local field="$1"
  python3 - "$field" "$LAST_BODY_FILE" <<'PY'
import json
import sys

field = sys.argv[1]
path = sys.argv[2]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
print(data[field])
PY
}

cleanup_body() {
  if [[ -n "${LAST_BODY_FILE:-}" ]]; then
    rm -f "$LAST_BODY_FILE"
    LAST_BODY_FILE=""
  fi
}

print_section "Admin API Smoke Test"
echo "BASE_URL=${BASE_URL}"

print_section "1) POST /api/admin/books"
create_payload=$(printf '{"title":"%s","author":"Smoke Test","category":"Admin Demo","price":12.34,"stock":3}' "$BOOK_TITLE")
request_json POST /api/admin/books "$create_payload" 200
BOOK_ID="$(extract_json_field id)"
cleanup_body
echo "Created book id: ${BOOK_ID}"

print_section "2) PATCH /api/admin/books/${BOOK_ID}/stock (+5)"
request_json PATCH "/api/admin/books/${BOOK_ID}/stock" '{"delta":5}' 200
cleanup_body

print_section "3) PATCH /api/admin/books/${BOOK_ID}/stock (-2)"
request_json PATCH "/api/admin/books/${BOOK_ID}/stock" '{"delta":-2}' 200
cleanup_body

print_section "4) DELETE /api/admin/books/${BOOK_ID}"
request_json DELETE "/api/admin/books/${BOOK_ID}" "" 200
cleanup_body

print_section "5) GET /api/books"
request_json GET /api/books "" 200
cleanup_body

echo
echo "Admin API smoke test completed."
