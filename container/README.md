# Observability Stack

OpenTelemetry Collector, Prometheus, Tempo, Loki, and Grafana — available as a Podman pod or a Docker Compose stack. The Docker Compose stack additionally runs **Alertmanager** and a **Matrix bridge** that send critical/warning alerts to a Matrix room (see [Alerting → Matrix](#alerting--matrix)), plus a **Telegraf MQTT bridge** that ingests MQTT topic messages as metrics and logs (see [MQTT ingestion](#mqtt-ingestion)).

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

Prometheus (9090), Loki (3100), Tempo (3200), Alertmanager (9093), and the Matrix bridge (9088) are internal only (not exposed to the host).

## Files

| File                                              | Purpose                                    |
|---------------------------------------------------|--------------------------------------------|
| `deploy.sh` / `stop.sh`                           | Start/stop the Podman pod                  |
| `deploy-docker.sh` / `stop-docker.sh`             | Start/stop the Docker Compose stack        |
| `observability-stack.yaml`                        | Podman pod definition with all configs inline |
| `docker-compose.yaml`                             | Docker Compose service definitions         |
| `config/collector-config.yaml`                    | OTel Collector pipeline configuration      |
| `config/telegraf/telegraf.conf`                   | Telegraf MQTT→OTel bridge (topics, parsing) |
| `config/telegraf/secret.env.example`              | Template for the broker credentials (copy to `secret.env`) |
| `config/prometheus.yml`                           | Prometheus configuration (incl. alerting)  |
| `config/prometheus/rules/`                        | Prometheus alerting rules (example metric alerts) |
| `config/loki-config.yaml`                         | Loki configuration (incl. ruler)           |
| `config/loki/rules/fake/`                         | Loki LogQL alerting rules (`fake` tenant)  |
| `config/alertmanager.yaml`                        | Alertmanager routing (critical/warning → Matrix) |
| `config/matrix-receiver/config.yaml.template`     | Matrix bridge config template              |
| `config/matrix-receiver/render-config.sh`         | Renders the bridge config with the bot token |
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
                                    ^               ^
MQTT ingestion (Docker Compose only):|               |
[Broker] --MQTT--> [Telegraf] --OTLP metrics--------/    (numeric JSON fields)
                       \------- logs (Loki push) --/      (raw JSON payloads)

Grafana reads from all three backends.

Alerting (Docker Compose only):

[Prometheus rules] -\
                     >-> [Alertmanager] --webhook--> [Matrix bridge] --HTTPS--> Matrix room
[Loki ruler]       -/      (critical|warning)         (@alertbot)
```

## Alerting → Matrix

Critical and warning alerts are delivered to a Matrix room. **Docker Compose only** — the
Podman pod (`observability-stack.yaml`) does not yet include Alertmanager or the bridge.

Pipeline: Prometheus rules (`config/prometheus/rules/`) and the Loki ruler
(`config/loki/rules/fake/`) push firing alerts to **Alertmanager**, which routes anything
labelled `severity: critical` or `severity: warning` to the **matrix-alertmanager-receiver**
bridge. The bridge posts as `@alertbot` to the Matrix room over Synapse's public endpoint
(`https://chat.datainmotion.com`) — this stack runs on a **different host** than Matrix.

### One-time setup

1. **Provision the bot** (on the Matrix host, server01), from the infrastructure repo:
   ```bash
   bash matrix/provision-alertbot.sh
   ```
   It registers `@alertbot`, creates the "Observability Alerts" room, and prints
   `ALERTBOT_TOKEN` / `ALERTS_ROOM_ID`.

2. **Carry the credentials to this host** into a gitignored secret file:
   ```bash
   # container/config/matrix-receiver/secret.env
   ALERTBOT_TOKEN=syt_...
   ALERTS_ROOM_ID=!abc123:chat.datainmotion.com
   ```
   (Alternatively export `ALERTBOT_TOKEN` / `ALERTS_ROOM_ID` in the deploy environment.)

3. **Deploy** — `./deploy-docker.sh` renders `config/matrix-receiver/config.yaml` from the
   token and brings the stack up.

Verify Alertmanager picked up the routing and fire a synthetic alert:
```bash
docker compose exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yaml
docker compose exec alertmanager wget -qO- --post-data='[{"labels":{"alertname":"Test","severity":"critical"},"annotations":{"summary":"hello from alertmanager"}}]' --header='Content-Type: application/json' http://localhost:9093/api/v2/alerts
```
A message should appear in the room within `group_wait` (30s).

### Tuning alerts

- **Metric alerts:** edit `config/prometheus/rules/example-alerts.yaml`. The shipped rules are
  templates — adjust metric names/thresholds to your OTLP metrics (this Prometheus is a
  remote-write sink, so `up` does not exist here).
- **Log alerts:** edit `config/loki/rules/fake/example-log-alerts.yaml` (LogQL).
- Set `severity: critical` or `severity: warning` on a rule to route it to Matrix; any other
  severity is dropped by Alertmanager.
- Basic-auth between Alertmanager and the bridge uses a shared password — change it in both
  `config/alertmanager.yaml` and `config/matrix-receiver/config.yaml.template` before use.

## MQTT ingestion

Bring MQTT topic messages into the stack as OpenTelemetry data. **Docker Compose only** —
the Podman pod (`observability-stack.yaml`) does not include Telegraf.

The collector has no MQTT receiver, so a **Telegraf** container subscribes to your existing
broker(s) and fans each JSON message out two ways:

- **numeric JSON fields → metrics** via OTLP/gRPC to the collector (`otel-collector:4317`),
  which remote-writes them to Prometheus;
- **raw JSON payloads → logs** pushed straight to Loki (`loki:3100`) — Loki has no MQTT input
  and Telegraf's OpenTelemetry output can only emit metrics, so logs bypass the collector.

### Setup

1. **Provide broker credentials** in a gitignored secret file:
   ```bash
   cp config/telegraf/secret.env.example config/telegraf/secret.env
   # then edit secret.env:
   #   MQTT_URL=tcp://broker:1883   (or ssl://broker:8883 for TLS)
   #   MQTT_USERNAME=...
   #   MQTT_PASSWORD=...
   ```

2. **Set the topic filters** in `config/telegraf/telegraf.conf` — replace the `"#"` TODO in
   both `[[inputs.mqtt_consumer]]` blocks with your telemetry topics (MQTT wildcards: `+` one
   level, `#` the rest). The first block produces metrics, the second logs.

3. **Deploy** — `./deploy-docker.sh` brings the `telegraf` service up with the rest of the stack.

### Tuning

- **Which JSON keys become metrics:** by default every numeric field is a metric; string
  fields are dropped unless listed in `json_string_fields`. Promote selected keys to labels
  with `tag_keys`. The source topic is added as the `topic` label (`topic_tag`).
- **Timestamps:** set `json_time_key` / `json_time_format` to use a field from the payload
  instead of arrival time.
- **In Grafana:** MQTT metrics appear in Prometheus prefixed `mqtt_*`; raw messages appear in
  Loki under the `mqtt_log` / `source="mqtt"` labels.

## Podman vs Docker Compose

The Podman pod runs all containers sharing a single `localhost` network namespace (like a Kubernetes pod). The Docker Compose stack uses a dedicated bridge network where containers address each other by service name. Behaviour and exposed endpoints are identical either way.
