#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-http://localhost:8080/api/books}"
DURATION="${DURATION:-60s}"
CONCURRENCY="${CONCURRENCY:-20}"

echo "=== Performance Test ==="
echo "TARGET_URL=${TARGET_URL}"
echo "DURATION=${DURATION}"
echo "CONCURRENCY=${CONCURRENCY}"

if command -v hey >/dev/null 2>&1; then
  hey -z "$DURATION" -c "$CONCURRENCY" "$TARGET_URL"
else
  echo
  echo "'hey' is not installed. Install guidance:"
  echo "  Go: go install github.com/rakyll/hey@latest"
  echo "  macOS (Homebrew): brew install hey"
  echo
  echo "Running fallback curl loop (20 requests) ..."
  for i in $(seq 1 20); do
    curl -sS -o /dev/null -w "Request %02d -> HTTP %{http_code}\\n" "$i" "$TARGET_URL"
  done
fi
