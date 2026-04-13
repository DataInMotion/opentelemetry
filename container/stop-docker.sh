#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Stopping Observability Stack (Docker Compose) ==="

docker compose -f "$DIR/docker-compose.yaml" down

echo "Stack stopped."
