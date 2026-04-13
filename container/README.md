# Observability Stack

OpenTelemetry Collector, Prometheus, Tempo, Loki, and Grafana — available as a Podman pod or a Docker Compose stack.

## Start

### Podman

```bash
./deploy.sh
```

### Docker Compose

```bash
./deploy-docker.sh
```

### Windows (PowerShell) — Podman only

```powershell
podman pod stop observability 2>$null; podman pod rm observability 2>$null
podman kube play .\observability-stack.yaml
```

## Stop

### Podman

```bash
./stop.sh
```

### Docker Compose

```bash
./stop-docker.sh
```

### Windows (PowerShell) — Podman only

```powershell
podman pod stop observability; podman pod rm observability
```

## Endpoints

| Service   | URL                    | Description              |
|-----------|------------------------|--------------------------|
| Grafana   | http://localhost:3000  | UI (no login required)   |
| OTLP gRPC | localhost:4317         | Telemetry ingestion      |
| OTLP HTTP | localhost:4318         | Telemetry ingestion      |

Prometheus (9090), Loki (3100), and Tempo (3200) are internal only (not exposed to the host).

## Files

| File                                              | Purpose                                    |
|---------------------------------------------------|--------------------------------------------|
| `deploy.sh` / `stop.sh`                           | Start/stop the Podman pod                  |
| `deploy-docker.sh` / `stop-docker.sh`             | Start/stop the Docker Compose stack        |
| `observability-stack.yaml`                        | Podman pod definition with all configs inline |
| `docker-compose.yaml`                             | Docker Compose service definitions         |
| `config/collector-config.yaml`                    | OTel Collector pipeline configuration      |
| `config/prometheus.yml`                           | Prometheus configuration                   |
| `config/loki-config.yaml`                         | Loki configuration                         |
| `config/tempo.yaml`                               | Tempo configuration                        |
| `config/grafana/provisioning/datasources/`        | Grafana datasource provisioning            |
| `config/grafana/provisioning/plugins/`            | Grafana plugin provisioning                |
| `config/grafana/provisioning/dashboards/`         | Grafana dashboard provisioning             |
| `grafana-dashboards/`                             | Dashboard JSON files (both deployments)    |

## Data Flow

```
                               |-> [Tempo]      (traces)   ->|
[App] --OTLP--> [Collector] ---|-> [Prometheus] (metrics)  ->|---> [Grafana]
                               |-> [Loki]       (logs)     ->|

Grafana reads from all three backends.
```

## Podman vs Docker Compose

The Podman pod runs all containers sharing a single `localhost` network namespace (like a Kubernetes pod). The Docker Compose stack uses a dedicated bridge network where containers address each other by service name. Behaviour and exposed endpoints are identical either way.
