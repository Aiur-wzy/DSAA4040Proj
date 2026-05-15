#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
BOOK_ID="${BOOK_ID:-1}"
ORDER_KEY="${ORDER_KEY:-order-consistency-$(date +%s)-${RANDOM}}"
export BOOK_ID

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "FAIL: missing $1" >&2; exit 1; }; }
require_cmd curl
require_cmd python3

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "BASE_URL=${BASE_URL}"
echo "BOOK_ID=${BOOK_ID}"
echo "ORDER_KEY=${ORDER_KEY}"

book_before="$(curl -fsS "${BASE_URL}/api/books" | python3 -c 'import json,sys,os; data=json.load(sys.stdin); bid=int(os.environ["BOOK_ID"]); print(next(b["stock"] for b in data if b["id"]==bid))')"
echo "Stock before: ${book_before}"

curl -fsS -X POST "${BASE_URL}/api/cart" -H 'Content-Type: application/json' -d "{\"book_id\":${BOOK_ID},\"quantity\":1}" >/dev/null
curl -fsS -X POST "${BASE_URL}/api/orders" -H 'Content-Type: application/json' -H "Idempotency-Key: ${ORDER_KEY}" -d '{}' >"${tmp_dir}/first.json"
curl -fsS -X POST "${BASE_URL}/api/orders" -H 'Content-Type: application/json' -H "Idempotency-Key: ${ORDER_KEY}" -d '{}' >"${tmp_dir}/second.json"

python3 - "${tmp_dir}/first.json" "${tmp_dir}/second.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    first = json.load(handle)
with open(sys.argv[2], encoding="utf-8") as handle:
    second = json.load(handle)
if first["id"] != second["id"]:
    raise SystemExit(
        f"FAIL: repeated Idempotency-Key created different orders: {first['id']} vs {second['id']}"
    )
if len(second.get("items", [])) != len(first.get("items", [])):
    raise SystemExit("FAIL: retry returned different item count")
print(f"PASS: repeated Idempotency-Key returned order {first['id']}")
PY

book_after="$(curl -fsS "${BASE_URL}/api/books" | python3 -c 'import json,sys,os; data=json.load(sys.stdin); bid=int(os.environ["BOOK_ID"]); print(next(b["stock"] for b in data if b["id"]==bid))')"
echo "Stock after: ${book_after}"
expected=$((book_before - 1))
[[ "$book_after" == "$expected" ]] || { echo "FAIL: stock changed by more than once (expected ${expected}, got ${book_after})" >&2; exit 1; }
echo "PASS: stock decremented exactly once"
