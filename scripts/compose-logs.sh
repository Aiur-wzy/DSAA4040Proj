#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  docker compose logs --tail=100
else
  docker compose logs --tail=100 "$1"
fi
