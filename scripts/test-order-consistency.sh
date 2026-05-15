#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

if [[ -z "${BASE_URL:-}" ]]; then
  require_minikube
  BASE_URL="http://$(minikube_ip):30080"
fi

require_cmd curl
require_cmd python3

TITLE="Consistency Test Book $(date +%s)"
STOCK=3
BOOK_ID=""
SUCCESS=0
FAIL=0

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

json_field() {
  python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get(sys.argv[1], ""))' "$1"
}

orders_count_for_book() {
  curl -fsS "${BASE_URL}/api/orders" | python3 -c 'import json, sys; book_id=int(sys.argv[1]); orders=json.load(sys.stdin); print(sum(1 for order in orders for item in order.get("items", []) if item.get("book_id") == book_id))' "$BOOK_ID"
}

book_stock() {
  curl -fsS "${BASE_URL}/api/books?search=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$TITLE")" | python3 -c 'import json, sys; book_id=int(sys.argv[1]); books=json.load(sys.stdin); print(next((book.get("stock") for book in books if book.get("id") == book_id), ""))' "$BOOK_ID"
}

http_json() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "${BASE_URL}${path}" -H 'Content-Type: application/json' -d "$body"
  else
    curl -sS -X "$method" "${BASE_URL}${path}"
  fi
}

http_status() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -o /tmp/order-consistency-response.json -w '%{http_code}' -X "$method" "${BASE_URL}${path}" -H 'Content-Type: application/json' -d "$body"
  else
    curl -sS -o /tmp/order-consistency-response.json -w '%{http_code}' -X "$method" "${BASE_URL}${path}"
  fi
}

cleanup() {
  if [[ -n "$BOOK_ID" ]]; then
    code="$(http_status DELETE "/api/admin/books/${BOOK_ID}" || true)"
    if [[ "$code" == "200" ]]; then
      pass "cleaned up temporary test book ${BOOK_ID}"
    else
      warn "temporary book ${BOOK_ID} could not be deleted, usually because successful order history references it. This does not modify seed rows."
    fi
  fi
  rm -f /tmp/order-consistency-response.json
}
trap cleanup EXIT

echo "Using BASE_URL=${BASE_URL}"
cart_items="$(curl -fsS "${BASE_URL}/api/cart" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("items", [])))')"
if [[ "$cart_items" != "0" ]]; then
  fail "demo cart is not empty (${cart_items} item(s)); empty it before running so this test does not clear user cart data."
fi

created="$(http_json POST /api/admin/books "{\"title\":\"${TITLE}\",\"author\":\"Experiment\",\"category\":\"Consistency\",\"price\":1.00,\"stock\":${STOCK}}")"
BOOK_ID="$(json_field id <<<"$created")"
[[ -n "$BOOK_ID" ]] || fail "could not create temporary test book"
pass "created temporary book ${BOOK_ID} with stock ${STOCK}"

before_orders="$(orders_count_for_book)"
http_json POST /api/cart "{\"book_id\":${BOOK_ID},\"quantity\":$((STOCK + 1))}" >/dev/null
code="$(http_status POST /api/orders)"
if [[ "$code" == "409" ]]; then
  pass "insufficient stock attempt returned HTTP 409"
  FAIL=$((FAIL + 1))
else
  cat /tmp/order-consistency-response.json >&2 || true
  fail "expected HTTP 409 for insufficient stock, got ${code}"
fi

after_failed_orders="$(orders_count_for_book)"
[[ "$after_failed_orders" == "$before_orders" ]] || fail "partial order data appeared after insufficient stock"
pass "no partial order was created after insufficient stock"

cart_qty="$(curl -fsS "${BASE_URL}/api/cart" | python3 -c 'import json, sys; book_id=int(sys.argv[1]); cart=json.load(sys.stdin); print(sum(item.get("quantity", 0) for item in cart.get("items", []) if item.get("book_id") == book_id))' "$BOOK_ID")"
[[ "$cart_qty" == "$((STOCK + 1))" ]] || fail "cart was not preserved after failed order"
pass "cart remains populated after failed order"

http_json PUT "/api/cart/${BOOK_ID}" "{\"quantity\":${STOCK}}" >/dev/null
code="$(http_status POST /api/orders)"
if [[ "$code" == "200" ]]; then
  pass "successful order with exact available stock returned HTTP 200"
  SUCCESS=$((SUCCESS + 1))
else
  cat /tmp/order-consistency-response.json >&2 || true
  fail "expected exact-stock order to succeed, got ${code}"
fi

final_stock="$(book_stock)"
[[ -n "$final_stock" ]] || fail "could not read final stock"
(( final_stock >= 0 )) || fail "final stock is negative (${final_stock})"
[[ "$final_stock" == "0" ]] || fail "expected final stock 0, got ${final_stock}"
pass "final stock is never negative and reached 0"

cart_items="$(curl -fsS "${BASE_URL}/api/cart" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("items", [])))')"
[[ "$cart_items" == "0" ]] || fail "cart was not cleared after successful order"
pass "cart is cleared only after successful order placement"

created_orders="$(orders_count_for_book)"
(( created_orders - before_orders == SUCCESS )) || fail "successful orders exceed expected count"
(( SUCCESS <= STOCK )) || fail "successful orders exceed available stock"
pass "successful orders (${SUCCESS}) did not exceed stock (${STOCK}); failed insufficient attempts=${FAIL}"
warn "Concurrency is limited by the shared demo-user cart model, so this script runs sequential transaction edge-case checks."
