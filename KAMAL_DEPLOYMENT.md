# Deploying SolidLog Service with Kamal

This guide covers deploying the `solid_log-service` as a standalone container using Kamal alongside your main Rails application.

## Architecture Overview

```
┌─────────────────────┐      ┌──────────────────────┐
│   Main Rails App    │      │  SolidLog Service    │
│  (Container/Host)   │      │    (Container)       │
│                     │      │                      │
│  Writes:            │      │  Reads:              │
│  - raw_entries ──────┼─────▶│  - raw_entries       │
│                     │      │                      │
│                     │      │  Writes:             │
│                     │      │  - entries           │
│                     │◀─────┤  - fields            │
│  Reads via API      │      │  - tokens            │
│  - All tables       │      │                      │
└─────────────────────┘      └──────────────────────┘
           │                            │
           └────────────┬───────────────┘
                        ▼
               ┌─────────────────┐
               │  Shared Volume  │
               │  (SQLite DB)    │
               └─────────────────┘
```

## Available Docker Images

Three database-specific images are automatically built and published to GitHub Container Registry:

- `ghcr.io/namolnad/solid_log/solid_log-service:latest-sqlite` (smallest, ~150MB)
- `ghcr.io/namolnad/solid_log/solid_log-service:latest-postgres` (~170MB)
- `ghcr.io/namolnad/solid_log/solid_log-service:latest-mysql` (~180MB)

**Versioned tags** are also available:
- `ghcr.io/namolnad/solid_log/solid_log-service:v1.2.3-sqlite`
- `ghcr.io/namolnad/solid_log/solid_log-service:v1.2.3-postgres`
- `ghcr.io/namolnad/solid_log/solid_log-service:v1.2.3-mysql`

## Quick Start

### 1. Choose Your Deployment Scenario

<details>
<summary><strong>Option A: Deploy as Kamal Accessory</strong> ✅ Recommended</summary>

The SolidLog service runs as a Kamal accessory alongside your main application.

**config/deploy.yml:**
```yaml
service: myapp
image: myapp/myapp

# Shared volume (mounted in both main app and accessory)
volumes:
  - solidlog-data:/rails/storage  # Main app writes logs here

servers:
  web:
    hosts:
      - 192.168.1.1

# SolidLog service as accessory
accessories:
  solidlog:
    image: ghcr.io/namolnad/solid_log/solid_log-service:latest-sqlite
    host: 192.168.1.1
    cmd: bundle exec solid_log_service
    env:
      clear:
        SOLIDLOG_DATABASE_URL: "sqlite3:///app/storage/production_log.sqlite"
        SOLIDLOG_PORT: "3001"
        SOLIDLOG_BIND: "0.0.0.0"
        SOLIDLOG_PARSER_INTERVAL: "10"
        SOLIDLOG_CACHE_CLEANUP_INTERVAL: "3600"
        SOLIDLOG_RETENTION_DAYS: "30"
        SOLIDLOG_ERROR_RETENTION_DAYS: "90"
      secret:
        - SOLIDLOG_TOKEN
    volumes:
      - solidlog-data:/app/storage  # Same volume, service reads/writes here

env:
  clear:
    RAILS_ENV: production
  secret:
    - RAILS_MASTER_KEY
    - SOLIDLOG_TOKEN
```

**Deploy commands:**
```bash
# Deploy main app
kamal deploy

# Boot the SolidLog accessory
kamal accessory boot solidlog

# View logs
kamal accessory logs solidlog

# Restart (e.g., after config changes)
kamal accessory reboot solidlog

# Stop
kamal accessory stop solidlog
```

</details>

<details>
<summary><strong>Option B: Main App on Host, Service in Container (Host Mount)</strong></summary>

Your main app runs directly on the host, and the service runs in a container with a host path mount.

**config/deploy.yml:**
```yaml
service: solidlog-service
image: ghcr.io/namolnad/solid_log/solid_log-service:latest-sqlite

servers:
  solidlog:
    hosts:
      - 192.168.1.1
    cmd: bundle exec solid_log_service

# Mount host directory into container
volumes:
  - "/var/app/storage:/app/storage"

env:
  clear:
    SOLIDLOG_DATABASE_URL: "sqlite3:///app/storage/production_log.sqlite"
    SOLIDLOG_PORT: "3001"

  secret:
    - SOLIDLOG_TOKEN
```

**On your host**, ensure the main app writes to `/var/app/storage/production_log.sqlite`.

</details>

<details>
<summary><strong>Option C: PostgreSQL/MySQL Database (Production-Grade)</strong></summary>

Both apps connect to a shared PostgreSQL or MySQL database over the Docker network.

**config/deploy.yml with PostgreSQL:**
```yaml
service: myapp
image: myapp/myapp

servers:
  web:
    hosts:
      - 192.168.1.1

  solidlog:
    hosts:
      - 192.168.1.1
    image: ghcr.io/namolnad/solid_log/solid_log-service:latest-postgres

# PostgreSQL as accessory
accessories:
  solidlog-db:
    image: postgres:16
    host: 192.168.1.1
    env:
      clear:
        POSTGRES_DB: solidlog_production
        POSTGRES_USER: solidlog
      secret:
        - POSTGRES_PASSWORD
    volumes:
      - data:/var/lib/postgresql/data
    options:
      network: "private"

env:
  clear:
    SOLIDLOG_DATABASE_URL: "postgresql://solidlog:${POSTGRES_PASSWORD}@solidlog-db/solidlog_production"
  secret:
    - POSTGRES_PASSWORD
    - SOLIDLOG_TOKEN
```

**For MySQL**, use:
- Image: `ghcr.io/namolnad/solid_log/solid_log-service:latest-mysql`
- Accessory image: `mysql:8`
- Database URL: `SOLIDLOG_DATABASE_URL=mysql2://solidlog:${MYSQL_PASSWORD}@solidlog-db/solidlog_production`

</details>

## Configuration

### Service Configuration

Create `config/solid_log_service.rb` in your **service container** (mount as volume or bake into custom image):

```ruby
SolidLog::Service.configure do |config|
  # Job processing mode
  config.job_mode = :scheduler  # Built-in scheduler (recommended)

  # Scheduler intervals
  config.parser_interval = ENV.fetch("SOLIDLOG_PARSER_INTERVAL", 10).to_i
  config.cache_cleanup_interval = ENV.fetch("SOLIDLOG_CACHE_CLEANUP_INTERVAL", 3600).to_i
  config.retention_hour = ENV.fetch("SOLIDLOG_RETENTION_HOUR", 2).to_i
  config.field_analysis_hour = ENV.fetch("SOLIDLOG_FIELD_ANALYSIS_HOUR", 3).to_i

  # Retention policies
  config.retention_days = ENV.fetch("SOLIDLOG_RETENTION_DAYS", 30).to_i
  config.error_retention_days = ENV.fetch("SOLIDLOG_ERROR_RETENTION_DAYS", 90).to_i

  # Batch sizes
  config.max_batch_size = ENV.fetch("SOLIDLOG_MAX_BATCH_SIZE", 1000).to_i

  # CORS (if exposing API publicly)
  config.cors_origins = ENV.fetch("SOLIDLOG_CORS_ORIGINS", "*").split(",")

  # Server binding (usually set via ENV)
  config.bind = ENV.fetch("BIND", "0.0.0.0")
  config.port = ENV.fetch("PORT", 3001).to_i
end
```

### Client Configuration (Main App)

In your **main Rails app**, configure the SolidLog client:

```ruby
# config/initializers/solid_log.rb
SolidLog::Core.configure_client do |config|
  # Service URL (Docker network or public URL)
  config.service_url = ENV.fetch("SOLIDLOG_SERVICE_URL", "http://myapp-solidlog:3001")

  # Authentication token
  config.token = ENV.fetch("SOLIDLOG_TOKEN")

  # App identification
  config.app_name = "myapp"
  config.environment = Rails.env

  # Batching (optional)
  config.batch_size = 100
  config.flush_interval = 5.seconds
end

# Start the client
SolidLog::Core::Client.start
```

## Secrets Management

### Generate Authentication Token

```bash
# Generate a secure random token
ruby -r securerandom -e 'puts SecureRandom.hex(32)'
```

### Add to Kamal Secrets

```bash
# .kamal/secrets
#!/usr/bin/env ruby

require "dotenv"
Dotenv.load(".env")

puts "SOLIDLOG_TOKEN=#{ENV["SOLIDLOG_TOKEN"]}"
puts "POSTGRES_PASSWORD=#{ENV["POSTGRES_PASSWORD"]}" # if using Postgres
```

```bash
# .env (DO NOT COMMIT)
SOLIDLOG_TOKEN=your-generated-token-here
POSTGRES_PASSWORD=secure-db-password
```

## Health Checks & Monitoring

The service exposes health endpoints:

```bash
# Public health check (no auth required)
curl https://logs.myapp.com/health

# Detailed metrics (requires auth)
curl -H "Authorization: Bearer YOUR_TOKEN" \
     https://logs.myapp.com/api/v1/health
```

**Health check response:**
```json
{
  "status": "healthy",
  "timestamp": "2025-12-30T12:00:00Z",
  "metrics": {
    "parsing": {
      "health_status": "healthy",
      "unparsed_count": 42,
      "oldest_unparsed_age_seconds": 15
    },
    "storage": {
      "total_entries": 150000,
      "database_size_mb": 245
    }
  }
}
```

## Troubleshooting

### Check Service Logs

```bash
kamal app logs --roles=solidlog --follow
```

### Verify Database Connection

```bash
kamal app exec --roles=solidlog -i

# Inside container
bundle exec rails console
> ActiveRecord::Base.connection.execute("SELECT COUNT(*) FROM solid_log_raw_entries")
```

### Test API Endpoint

```bash
# From main app container
kamal app exec --roles=web -i

# Test ingestion
curl -X POST http://myapp-solidlog:3001/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"level":"info","message":"Test log"}'
```

### SQLite Concurrency Issues

If you see "database is locked" errors:

1. **Verify WAL mode is enabled:**
```bash
sqlite3 /app/storage/production_log.sqlite "PRAGMA journal_mode;"
# Should return: wal
```

2. **Enable WAL mode (one-time):**
```bash
sqlite3 /app/storage/production_log.sqlite "PRAGMA journal_mode=WAL;"
```

3. **Check for long-running transactions** in your main app

### Service Won't Start

1. **Check environment variables:**
```bash
kamal app exec --roles=solidlog -c "env | grep SOLIDLOG"
```

2. **Verify volume mount:**
```bash
kamal app exec --roles=solidlog -c "ls -la /app/storage"
```

3. **Check database adapter:**
```bash
# Make sure you're using the right image variant
# For SQLite:
image: ghcr.io/namolnad/solid_log/solid_log-service:latest-sqlite
```

## Scaling

### Horizontal Scaling (PostgreSQL/MySQL Only)

For SQLite, you can only run **one service instance** per host due to write contention.

For PostgreSQL/MySQL, you can scale horizontally:

```yaml
servers:
  solidlog:
    hosts:
      - 192.168.1.1
      - 192.168.1.2
      - 192.168.1.3
    image: ghcr.io/namolnad/solid_log/solid_log-service:latest-postgres
```

**Load balancing** is automatic via Kamal Proxy.

### Vertical Scaling

Adjust Puma workers/threads:

```yaml
env:
  clear:
    WEB_CONCURRENCY: "4"      # Number of Puma workers
    RAILS_MAX_THREADS: "10"   # Threads per worker
```

## Advanced Configuration

### Custom Image with Baked-In Config

Create a custom Dockerfile:

```dockerfile
FROM ghcr.io/namolnad/solid_log/solid_log-service:latest-sqlite

# Copy custom configuration
COPY config/solid_log_service.rb /app/config/

# Optional: Add custom initialization
COPY config/initializers/ /app/config/initializers/
```

### Using Traefik for SSL

```yaml
traefik:
  labels:
    traefik.http.routers.solidlog.rule: "Host(`logs.myapp.com`)"
    traefik.http.routers.solidlog.entrypoints: "websecure"
    traefik.http.routers.solidlog.tls: "true"
    traefik.http.routers.solidlog.tls.certresolver: "letsencrypt"
```

### Running Migrations

```bash
# If needed (automatic on boot, but for manual runs)
kamal app exec --roles=solidlog -c "bundle exec rails solid_log:install:migrations"
kamal app exec --roles=solidlog -c "bundle exec rails db:migrate"
```

## Example: Complete Kamal Setup for SQLite

**File: `config/deploy.yml`**
```yaml
service: myapp
image: myapp/myapp

registry:
  server: ghcr.io
  username: namolnad
  password:
    - KAMAL_REGISTRY_PASSWORD

# Shared volume for logs
volumes:
  - solidlog-data:/rails/storage

servers:
  web:
    hosts:
      - 192.168.1.100

# SolidLog as accessory
accessories:
  solidlog:
    image: ghcr.io/namolnad/solid_log/solid_log-service:latest-sqlite
    host: 192.168.1.100
    cmd: bundle exec solid_log_service
    env:
      clear:
        SOLIDLOG_DATABASE_URL: "sqlite3:///app/storage/production_log.sqlite"
        SOLIDLOG_PORT: "3001"
        SOLIDLOG_PARSER_INTERVAL: "10"
        SOLIDLOG_RETENTION_DAYS: "30"
      secret:
        - SOLIDLOG_TOKEN
    volumes:
      - solidlog-data:/app/storage

env:
  clear:
    RAILS_ENV: production
  secret:
    - RAILS_MASTER_KEY
    - SOLIDLOG_TOKEN
```

**Deploy:**
```bash
kamal setup
kamal deploy
kamal accessory boot solidlog
```

Done! 🎉
