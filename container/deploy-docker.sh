#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== OpenTelemetry Demo - Deploy Observability Stack (Docker Compose) ==="

# Render the Matrix bridge config (injects the @alertbot token + room ID).
# The image has no shell, so the secret is substituted on the host here.
echo "Rendering Matrix receiver config..."
"$DIR/config/matrix-receiver/render-config.sh"

echo "Starting observability stack..."
docker compose -f "$DIR/docker-compose.yaml" up -d

echo ""
echo "=== Stack started ==="
echo "Grafana:     http://localhost:3000  (no login required)"
echo "OTLP gRPC:   localhost:4317"
echo "OTLP HTTP:   localhost:4318"
echo ""
echo "Internal only (not exposed): Prometheus :9090, Loki :3100, Tempo :3200"
echo ""
echo "Check status:  docker compose ps"
echo "View logs:     docker compose logs -f"
echo "Stop:          ./stop-docker.sh"
