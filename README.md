# Rails Hello World with Monitoring & APM

This project sets up a simple Rails application with PostgreSQL and Redis, along with a comprehensive monitoring and APM (Application Performance Monitoring) stack.

## Architecture

The application consists of the following components:
- Rails application (Hello World)
- PostgreSQL database
- Redis cache
- Monitoring & APM stack:
  - Prometheus (metrics collection)
  - Grafana (visualization)
  - Node Exporter (system metrics)
  - Redis Exporter (Redis metrics)
  - PostgreSQL Exporter (database metrics)
  - Blackbox Exporter (synthetic checks)
  - Prometheus Ruby APM (via prometheus_exporter gem)

## Prerequisites

- Docker
- Docker Compose

## Setup Instructions

1. Clone this repository
2. Run the setup script:
   ```bash
   ./setup.sh
   ```
3. Access the application:
   - Rails app: http://localhost:3000
   - Hello World endpoint: http://localhost:3000/hello
   - Grafana: http://localhost:3001 (login: admin / admin)
   - Prometheus: http://localhost:9090

## Monitoring & Alerting

### Prometheus
- Configuration: `prometheus/prometheus.yml`
- Alert rules: `prometheus/alert.rules`
- Blackbox synthetic checks: `prometheus/blackbox.yml`

### Grafana
- Provisioned Prometheus datasource: `grafana/provisioning/datasources/prometheus.yml`
- Dashboards: (add JSON files to `grafana/provisioning/dashboards` if needed)

### Key Metrics

#### Rails Application
- Request latency (APM)
- Request rate
- Error rates
- Memory usage
- CPU usage
- Garbage collection metrics

#### PostgreSQL
- Connection count
- Query performance
- Cache hit ratio
- Table sizes
- Transaction rates

#### Redis
- Memory usage
- Connected clients
- Command execution time
- Cache hit/miss ratio
- Key expiration rate

#### System Level
- CPU utilization
- Memory usage
- Disk I/O
- Network traffic
- System load

### Alerting Rules

The monitoring stack includes predefined alerting rules for:
- High request latency (>500ms for 5m)
- Error rate (>1% for 5m)
- High resource utilization (>80%)
- Service unavailability
- Database connection limits
- Memory pressure

#### Example Prometheus Alert Expressions

- **High Request Latency:**
  ```yaml
  - alert: HighRequestLatency
    expr: (rate(http_server_request_duration_seconds_sum[5m]) / rate(http_server_request_duration_seconds_count[5m])) > 0.5
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Request latency is above 500ms for 5 minutes"
      description: "The average request latency has exceeded 500ms over the last 5 minutes."
  ```
- **High Error Rate:**
  ```yaml
  - alert: HighErrorRate
    expr: |
      (
        sum(rate(http_requests_total{code=~"5.."}[5m]))
        /
        sum(rate(http_requests_total[5m]))
      ) > 0.01
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Error rate is above 1% for 5 minutes"
      description: "The proportion of 5xx responses has exceeded 1% over the last 5 minutes."
  ```

## Development

To start development:
1. Start the services:
   ```bash
   docker compose up -d
   ```
2. Access the Rails console:
   ```bash
   docker compose exec web rails console
   ```

## File Structure

- `docker-compose.yml` — Service definitions for the stack
- `setup.sh` — Automated setup for Rails app and config
- `prometheus/` — Prometheus config, alert rules, blackbox modules
- `grafana/` — Grafana provisioning (datasources, dashboards)

## Customization

- **Prometheus rules:** Edit `prometheus/alert.rules` for custom alerts.
- **Prometheus config:** Edit `prometheus/prometheus.yml` for scrape configs.
- **Grafana dashboards:** Provision or import dashboards in Grafana UI.
- **APM instrumentation:** The Rails app uses the `prometheus-client` gem for APM metrics. You can add custom instrumentation in your Rails controllers or background jobs.

## Troubleshooting

- Ensure Docker and Docker Compose are installed and running.
- If you change alert rules or Prometheus config, restart the Prometheus container:
  ```bash
  docker compose restart prometheus
  ```
- For Rails app issues, check logs:
  ```bash
  docker compose logs web
  ```

---

_Last updated: June 17, 2025_
