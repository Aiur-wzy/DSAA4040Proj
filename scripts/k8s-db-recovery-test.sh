#!/usr/bin/env bash
set -euo pipefail

DB_MODE="${DB_MODE:-single}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$DB_MODE" == "ha" ]]; then
  exec "${SCRIPT_DIR}/k8s-postgres-ha-failover-test.sh"
fi

cat <<MSG
DB_MODE=${DB_MODE}: the legacy single-PostgreSQL recovery test is intentionally non-destructive.
For distributed database failover validation, run:
  DB_MODE=ha ${SCRIPT_DIR}/k8s-postgres-ha-failover-test.sh
MSG
