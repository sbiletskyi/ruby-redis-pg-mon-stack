# Rails Hello World with Monitoring

This project sets up a simple Rails application with PostgreSQL and Redis, along with a comprehensive monitoring stack.

## Architecture

The application consists of the following components:
- Rails application (Hello World)
- PostgreSQL database
- Redis cache
- Monitoring stack:
  - Prometheus (metrics collection)
  - Grafana (visualization)
  - Node Exporter (system metrics)
  - Redis Exporter (Redis metrics)
  - PostgreSQL Exporter (database metrics)

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
   - Grafana: http://localhost:3001
   - Prometheus: http://localhost:9090

## Monitoring

### Key Metrics

#### Rails Application
- Request latency
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
- High latency (>500ms)
- Error rate (>1%)
- High resource utilization (>80%)
- Service unavailability
- Database connection limits
- Memory pressure

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
