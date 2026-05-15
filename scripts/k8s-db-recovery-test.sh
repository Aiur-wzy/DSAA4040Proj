#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/k8s.sh
source "${SCRIPT_DIR}/lib/k8s.sh"

NAMESPACE="bookstore"
NODE_PORT="${NODE_PORT:-30080}"
TITLE="DB Recovery Test Book"
BOOK_ID=""

pass() { echo "PASS: $*"; }
warn() { echo "WARN: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

resolve_kubectl
require_minikube_running
require_cmd curl
require_cmd python3

BASE_URL="${BASE_URL:-http://$(minikube_ip):${NODE_PORT}}"

echo "This validates PVC-backed recovery after PostgreSQL Pod failure, not multi-primary database HA."
echo "Using BASE_URL=${BASE_URL}"

curl -fsS "${BASE_URL}/api/health/db" >/dev/null && pass "database health is OK before failure"

books_before="$(curl -fsS "${BASE_URL}/api/books" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
orders_before="$(curl -fsS "${BASE_URL}/api/orders" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))' 2>/dev/null || echo unknown)"
echo "Books before restart: ${books_before}; orders before restart: ${orders_before}"

existing="$(curl -fsS "${BASE_URL}/api/books?search=$(python3 -c 'import urllib.parse; print(urllib.parse.quote("DB Recovery Test Book"))')" | python3 -c 'import json, sys; books=json.load(sys.stdin); print(next((book.get("id") for book in books if book.get("title") == "DB Recovery Test Book"), ""))')"
if [[ -n "$existing" ]]; then
  BOOK_ID="$existing"
  pass "found existing recovery marker book ${BOOK_ID}"
else
  created="$(curl -fsS -X POST "${BASE_URL}/api/admin/books" -H 'Content-Type: application/json' -d '{"title":"DB Recovery Test Book","author":"Experiment","category":"Recovery","price":1.00,"stock":1}')"
  BOOK_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' <<<"$created")"
  [[ -n "$BOOK_ID" ]] || fail "could not create recovery marker book"
  pass "created recovery marker book ${BOOK_ID}"
fi

postgres_pod="$(${KUBECTL[@]} get pod -n "$NAMESPACE" -l app=postgres -o jsonpath='{.items[0].metadata.name}')"
[[ -n "$postgres_pod" ]] || fail "no PostgreSQL Pod found"
warn "Deleting PostgreSQL Pod ${postgres_pod}; Deployment should recreate it and reattach the PVC."
"${KUBECTL[@]}" delete pod -n "$NAMESPACE" -l app=postgres
"${KUBECTL[@]}" wait --for=condition=ready pod -l app=postgres -n "$NAMESPACE" --timeout=240s
pass "PostgreSQL Pod became Ready again"

for attempt in {1..30}; do
  if curl -fsS "${BASE_URL}/api/health/db" >/dev/null; then
    pass "database health recovered"
    break
  fi
  if [[ "$attempt" == "30" ]]; then
    fail "database health did not recover in time"
  fi
  sleep 5
done

books_after="$(curl -fsS "${BASE_URL}/api/books" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')"
(( books_after >= books_before )) || fail "book count decreased after PostgreSQL Pod restart"
marker_present="$(curl -fsS "${BASE_URL}/api/books?search=$(python3 -c 'import urllib.parse; print(urllib.parse.quote("DB Recovery Test Book"))')" | python3 -c 'import json, sys; book_id=int(sys.argv[1]); books=json.load(sys.stdin); print("yes" if any(book.get("id") == book_id for book in books) else "no")' "$BOOK_ID")"
[[ "$marker_present" == "yes" ]] || fail "recovery marker book was not found after Pod restart"
pass "PVC-backed data remained present after PostgreSQL Pod restart"
