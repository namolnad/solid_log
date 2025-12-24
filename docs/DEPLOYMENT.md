# SolidLog Deployment Guide

This guide covers deploying SolidLog to production environments with best practices for performance, reliability, and scalability.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Database Setup](#database-setup)
- [SQLite Configuration](#sqlite-configuration)
- [Parser Workers](#parser-workers)
- [Kamal Deployment](#kamal-deployment)
- [Docker Deployment](#docker-deployment)
- [Systemd Services](#systemd-services)
- [Background Jobs](#background-jobs)
- [Monitoring](#monitoring)
- [Backup & Recovery](#backup--recovery)
- [Scaling Considerations](#scaling-considerations)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

## Prerequisites

- Rails 8.0+ application
- SQLite 3.8+ (3.9+ recommended for FTS5)
- Ruby 3.1+ (3.2+ recommended)
- 2GB+ RAM for small deployments
- 10GB+ disk space (varies with retention)

## Database Setup

### Multi-Database Configuration

SolidLog requires a separate database for log storage:

```yaml
# config/database.yml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
    pool: 5

  log:
    adapter: sqlite3
    database: storage/production_log.sqlite3
    pool: 10  # Higher pool for concurrent reads
    migrations_paths: db/log_migrate
```

### Directory Structure

```bash
storage/
├── production.sqlite3          # Main app database
├── production_log.sqlite3      # SolidLog database
├── production.sqlite3-shm      # Shared memory (WAL mode)
├── production.sqlite3-wal      # Write-ahead log (WAL mode)
├── production_log.sqlite3-shm
└── production_log.sqlite3-wal
```

### Permissions

```bash
# Ensure storage directory is writable
chmod 755 storage/
chmod 644 storage/*.sqlite3

# For deployed apps
chown deploy:deploy storage/
chown deploy:deploy storage/*.sqlite3
```

### Migration

Run migrations before deploying:

```bash
rails db:migrate RAILS_ENV=production
```

This migrates both primary and log databases.

## SQLite Configuration

### WAL Mode (Write-Ahead Logging)

WAL mode enables concurrent reads during writes. Enable in migration:

```ruby
# db/log_migrate/001_enable_wal_mode.rb
class EnableWalMode < ActiveRecord::Migration[8.0]
  def up
    ActiveRecord::Base.connected_to(database: { writing: :log }) do
      execute "PRAGMA journal_mode=WAL"
      execute "PRAGMA synchronous=NORMAL"
      execute "PRAGMA busy_timeout=5000"
      execute "PRAGMA cache_size=-64000"  # 64MB cache
    end
  end
end
```

Or run manually:

```bash
sqlite3 storage/production_log.sqlite3 << EOF
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA busy_timeout=5000;
PRAGMA cache_size=-64000;
EOF
```

### Recommended PRAGMAs

| PRAGMA | Value | Purpose |
|--------|-------|---------|
| `journal_mode` | `WAL` | Enable concurrent reads |
| `synchronous` | `NORMAL` | Balance safety/performance |
| `busy_timeout` | `5000` | Wait 5s for locks |
| `cache_size` | `-64000` | 64MB in-memory cache |
| `temp_store` | `MEMORY` | Use RAM for temp tables |
| `mmap_size` | `268435456` | 256MB memory-mapped I/O |
| `page_size` | `4096` | Match OS page size |

### Performance Tuning

```ruby
# config/initializers/solid_log.rb
ActiveRecord::Base.connected_to(database: { writing: :log }) do
  connection = ActiveRecord::Base.connection

  # Performance optimizations
  connection.execute("PRAGMA temp_store=MEMORY")
  connection.execute("PRAGMA mmap_size=268435456")  # 256MB
  connection.execute("PRAGMA page_size=4096")

  # Auto-optimize statistics
  connection.execute("PRAGMA optimize")
end
```

Schedule periodic optimization:

```bash
# Daily at 3 AM
0 3 * * * cd /var/www/myapp && rails solid_log:optimize RAILS_ENV=production
```

## Parser Workers

SolidLog requires parser workers to process ingested logs.

### Option 1: Cron (Simple)

```cron
# /etc/cron.d/solidlog-parser
# Run parser every 5 minutes
*/5 * * * * deploy cd /var/www/myapp && /usr/local/bin/bundle exec rails solid_log:parse_logs RAILS_ENV=production >> /var/log/solidlog-parser.log 2>&1
```

**Pros:** Simple, no daemon management
**Cons:** Fixed interval, not real-time

### Option 2: Systemd Service (Recommended)

```ini
# /etc/systemd/system/solidlog-parser.service
[Unit]
Description=SolidLog Parser Worker
After=network.target

[Service]
Type=simple
User=deploy
Group=deploy
WorkingDirectory=/var/www/myapp
Environment="RAILS_ENV=production"
Environment="BUNDLE_PATH=/var/www/myapp/vendor/bundle"

# Run parser in loop with 30s sleep
ExecStart=/bin/bash -lc 'while true; do bundle exec rails solid_log:parse_logs; sleep 30; done'

Restart=always
RestartSec=10

# Logging
StandardOutput=append:/var/log/solidlog-parser.log
StandardError=append:/var/log/solidlog-parser.log

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable solidlog-parser
sudo systemctl start solidlog-parser
sudo systemctl status solidlog-parser
```

**Pros:** Auto-restart, log management, process supervision
**Cons:** More complex setup

### Option 3: Background Job (Most Flexible)

Use your existing job backend (Solid Queue, Sidekiq, etc.):

```ruby
# config/initializers/solid_log.rb
# Schedule parser job every 5 minutes
if Rails.env.production?
  SolidLog::ParserJob.set(wait: 5.minutes).perform_later
end
```

In `ParserJob`:

```ruby
# app/jobs/solid_log/parser_job.rb
def perform
  SolidLog.without_logging do
    process_batch
  end

  # Re-enqueue for continuous processing
  self.class.set(wait: 5.minutes).perform_later
end
```

**Pros:** Leverages existing infrastructure, easy scaling
**Cons:** Couples to job backend

### Multiple Workers

For high ingestion volumes, run multiple parser workers:

```ruby
# config/initializers/solid_log.rb
config.parser_concurrency = 10  # Allow up to 10 parallel workers
```

With systemd:

```ini
# /etc/systemd/system/solidlog-parser@.service
# Template service for multiple workers

[Service]
ExecStart=/bin/bash -lc 'bundle exec rails solid_log:parse_logs'
# ... rest of config
```

Start multiple instances:

```bash
sudo systemctl start solidlog-parser@1
sudo systemctl start solidlog-parser@2
sudo systemctl start solidlog-parser@3
```

## Kamal Deployment

[Kamal](https://kamal-deploy.org/) is the recommended deployment tool for Rails 8 apps.

### Configuration

```yaml
# config/deploy.yml
service: myapp

image: myapp/web

servers:
  web:
    hosts:
      - 192.168.1.1
    labels:
      traefik.http.routers.myapp.rule: Host(`myapp.com`)

  solidlog_parser:
    hosts:
      - 192.168.1.1
    cmd: bin/rails solid_log:parse_worker
    labels:
      traefik.enable: false

registry:
  username: myuser
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  secret:
    - SOLIDLOG_TOKEN
    - RAILS_MASTER_KEY

volumes:
  - "solidlog_storage:/app/storage"

# Database setup hook
accessories:
  db:
    image: postgres:15
    host: 192.168.1.1
    volumes:
      - "postgres_data:/var/lib/postgresql/data"
```

### Parser Worker Command

Create a worker command:

```bash
# bin/rails (add to existing file)
#!/usr/bin/env ruby

if ARGV.first == 'solid_log:parse_worker'
  # Continuous parser loop
  loop do
    system('bundle exec rails solid_log:parse_logs RAILS_ENV=production')
    sleep 30
  end
else
  # Normal rails command
  APP_PATH = File.expand_path('../config/application', __dir__)
  require_relative "../config/boot"
  require "rails/commands"
end
```

### Deploy

```bash
kamal deploy
```

This deploys:
- Web containers (Rails app + SolidLog UI)
- Parser worker containers (continuous parsing)
- Shared volume for SQLite database

### Health Checks

```yaml
# config/deploy.yml
healthcheck:
  path: /admin/logs/health
  interval: 10s
  timeout: 5s
```

Create health endpoint:

```ruby
# config/routes.rb
get '/admin/logs/health', to: proc {
  [200, {}, ['OK']]
}
```

## Docker Deployment

### Dockerfile

```dockerfile
# Dockerfile
FROM ruby:3.2-slim

RUN apt-get update -qq && \
    apt-get install -y build-essential libsqlite3-dev nodejs

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install

COPY . .

# Precompile assets
RUN SECRET_KEY_BASE=dummy rails assets:precompile

EXPOSE 3000

CMD ["rails", "server", "-b", "0.0.0.0"]
```

### Docker Compose

```yaml
# docker-compose.yml
version: '3.8'

services:
  web:
    build: .
    command: bundle exec rails server -b 0.0.0.0
    ports:
      - "3000:3000"
    volumes:
      - solidlog_storage:/app/storage
    environment:
      RAILS_ENV: production
      SOLIDLOG_TOKEN: ${SOLIDLOG_TOKEN}

  solidlog_parser:
    build: .
    command: bash -c "while true; do bundle exec rails solid_log:parse_logs; sleep 30; done"
    volumes:
      - solidlog_storage:/app/storage
    environment:
      RAILS_ENV: production

volumes:
  solidlog_storage:
```

### Run

```bash
docker-compose up -d
```

## Systemd Services

For traditional server deployments without containers.

### Web Service

```ini
# /etc/systemd/system/myapp-web.service
[Unit]
Description=MyApp Rails Server
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/myapp
Environment="RAILS_ENV=production"

ExecStart=/bin/bash -lc 'bundle exec rails server -b 0.0.0.0 -p 3000'

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Parser Service

See [Parser Workers](#parser-workers) section above.

### Retention Service

```ini
# /etc/systemd/system/solidlog-retention.service
[Unit]
Description=SolidLog Retention Cleanup

[Service]
Type=oneshot
User=deploy
WorkingDirectory=/var/www/myapp
Environment="RAILS_ENV=production"

ExecStart=/bin/bash -lc 'bundle exec rails solid_log:retention_vacuum[30]'
```

```ini
# /etc/systemd/system/solidlog-retention.timer
[Unit]
Description=Run SolidLog retention daily

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
```

Enable timer:

```bash
sudo systemctl enable solidlog-retention.timer
sudo systemctl start solidlog-retention.timer
```

## Background Jobs

### Scheduled Jobs

Configure these jobs in your job backend:

**Parser Job** (every 5 minutes):
```ruby
SolidLog::ParserJob.perform_later
```

**Cache Cleanup** (every hour):
```ruby
SolidLog::CacheCleanupJob.perform_later
```

**Field Analysis** (daily):
```ruby
SolidLog::FieldAnalysisJob.perform_later(auto_promote: true)
```

**Retention** (daily at 2 AM):
```ruby
SolidLog::RetentionJob.perform_later
```

### Solid Queue Example

```ruby
# config/initializers/solid_queue.rb
if Rails.env.production?
  Rails.application.config.after_initialize do
    # Schedule recurring jobs
    SolidQueue::RecurringTask.create_or_find_by!(
      key: 'solidlog_parser',
      schedule: 'every 5 minutes',
      job_class: 'SolidLog::ParserJob'
    )

    SolidQueue::RecurringTask.create_or_find_by!(
      key: 'solidlog_cache_cleanup',
      schedule: 'every hour',
      job_class: 'SolidLog::CacheCleanupJob'
    )

    SolidQueue::RecurringTask.create_or_find_by!(
      key: 'solidlog_field_analysis',
      schedule: 'daily at 3am',
      job_class: 'SolidLog::FieldAnalysisJob',
      arguments: [{ auto_promote: true }]
    )

    SolidQueue::RecurringTask.create_or_find_by!(
      key: 'solidlog_retention',
      schedule: 'daily at 2am',
      job_class: 'SolidLog::RetentionJob'
    )
  end
end
```

## Monitoring

### Health Checks

```bash
# Check overall health
curl http://localhost:3000/admin/logs/health

# Get detailed stats
rails solid_log:health RAILS_ENV=production
```

Output:
```
=== SolidLog Health ===

Ingestion:
  - Raw entries: 1,234,567
  - Unparsed entries: 45
  - Ingested today: 12,345

Parsing:
  - Parsed entries: 1,234,522
  - Parse success rate: 99.98%
  - Avg parse time: 2.3ms

Storage:
  - Database size: 2.3 GB
  - Oldest entry: 2025-01-15 10:30:45 UTC
  - Newest entry: 2025-02-14 16:22:10 UTC

Performance:
  - Error rate: 0.2%
  - Avg duration: 145ms
  - 95th percentile: 340ms
```

### Metrics to Monitor

1. **Parse Backlog**
   ```bash
   rails solid_log:stats | grep "Unparsed"
   ```
   Alert if >1000 unparsed entries

2. **Database Size**
   ```bash
   du -h storage/production_log.sqlite3
   ```
   Alert if approaching disk limits

3. **Error Rate**
   ```sql
   SELECT COUNT(*) FROM solid_log_entries
   WHERE level IN ('error', 'fatal')
   AND created_at > datetime('now', '-1 hour');
   ```
   Alert if >100 errors/hour

4. **Ingestion Rate**
   ```sql
   SELECT COUNT(*) FROM solid_log_raw
   WHERE received_at > datetime('now', '-5 minutes');
   ```
   Alert if drops to zero (ingestion failure)

### Integration with Monitoring Tools

**Prometheus exporter:**

```ruby
# lib/solidlog/prometheus_exporter.rb
require 'prometheus/client'

module SolidLog
  class PrometheusExporter
    def self.metrics
      prometheus = Prometheus::Client.registry

      unparsed_gauge = prometheus.gauge(
        :solidlog_unparsed_entries,
        docstring: 'Number of unparsed log entries'
      )

      db_size_gauge = prometheus.gauge(
        :solidlog_database_bytes,
        docstring: 'Database size in bytes'
      )

      error_rate_gauge = prometheus.gauge(
        :solidlog_error_rate,
        docstring: 'Percentage of error logs'
      )

      # Update metrics
      unparsed_gauge.set(RawEntry.unparsed.count)
      db_size_gauge.set(database_size_bytes)
      error_rate_gauge.set(error_rate_percentage)
    end

    private

    def self.database_size_bytes
      File.size(Rails.root.join('storage/production_log.sqlite3'))
    rescue
      0
    end

    def self.error_rate_percentage
      total = Entry.where('created_at > ?', 1.hour.ago).count
      errors = Entry.errors.where('created_at > ?', 1.hour.ago).count
      return 0 if total.zero?
      (errors.to_f / total * 100).round(2)
    end
  end
end
```

**Grafana dashboard:**
- Unparsed entries over time
- Ingestion rate (logs/minute)
- Error rate percentage
- Database size growth
- Parse duration p50/p95/p99

## Backup & Recovery

### SQLite Backup

**Option 1: Litestream (Recommended)**

[Litestream](https://litestream.io/) provides continuous SQLite replication to S3/Azure/GCS.

```yaml
# /etc/litestream.yml
dbs:
  - path: /var/www/myapp/storage/production_log.sqlite3
    replicas:
      - url: s3://mybucket/solidlog-backups
        retention: 720h  # 30 days
        sync-interval: 1s
```

Start Litestream:

```bash
sudo systemctl enable litestream
sudo systemctl start litestream
```

**Restore:**

```bash
litestream restore -o production_log.sqlite3 \
  s3://mybucket/solidlog-backups/production_log.sqlite3
```

**Option 2: Manual Backup**

```bash
#!/bin/bash
# backup-solidlog.sh

DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/backups/solidlog"
DB_PATH="/var/www/myapp/storage/production_log.sqlite3"

mkdir -p "$BACKUP_DIR"

# Use SQLite backup command (safe during writes)
sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/solidlog_$DATE.sqlite3'"

# Compress
gzip "$BACKUP_DIR/solidlog_$DATE.sqlite3"

# Delete backups older than 30 days
find "$BACKUP_DIR" -name "solidlog_*.sqlite3.gz" -mtime +30 -delete

echo "Backup completed: solidlog_$DATE.sqlite3.gz"
```

Schedule with cron:

```cron
# Daily backup at 1 AM
0 1 * * * /usr/local/bin/backup-solidlog.sh
```

**Option 3: WAL Checkpoint + Copy**

```bash
# Checkpoint WAL to main database
sqlite3 storage/production_log.sqlite3 "PRAGMA wal_checkpoint(TRUNCATE);"

# Copy database
cp storage/production_log.sqlite3 backups/solidlog_$(date +%Y%m%d).sqlite3
```

### Disaster Recovery

**Restore from backup:**

1. Stop parser workers
2. Restore database file
3. Restart services

```bash
# Stop workers
sudo systemctl stop solidlog-parser

# Restore backup
gunzip -c backups/solidlog_20250214.sqlite3.gz > storage/production_log.sqlite3

# Restart
sudo systemctl start solidlog-parser
```

**Re-parse from raw entries:**

If parsed entries are lost but raw entries remain:

```bash
# Reset all entries to unparsed
sqlite3 storage/production_log.sqlite3 << EOF
UPDATE solid_log_raw SET parsed = 0, parsed_at = NULL;
DELETE FROM solid_log_entries;
DELETE FROM solid_log_entries_fts;
EOF

# Re-run parser
rails solid_log:parse_logs
```

## Scaling Considerations

### When to Scale

Monitor these indicators:

- **Parse backlog** >5000 entries
- **Ingestion latency** >1 second
- **Query response time** >2 seconds
- **Database size** >50 GB

### Horizontal Scaling

**Multiple parser workers:**

```bash
# Run 10 concurrent parser processes
for i in {1..10}; do
  bundle exec rails solid_log:parse_logs &
done
wait
```

With systemd templates:

```bash
sudo systemctl start solidlog-parser@{1..10}
```

**Load balancing:**

Use a reverse proxy (nginx, Traefik) to load balance across multiple web instances:

```nginx
upstream solidlog {
  server 192.168.1.1:3000;
  server 192.168.1.2:3000;
  server 192.168.1.3:3000;
}

server {
  location /admin/logs {
    proxy_pass http://solidlog;
  }
}
```

**Note:** SQLite only supports single-writer, so all instances must share the same database file (e.g., via NFS).

### Vertical Scaling

**Increase resources:**

- **RAM**: Increase cache size (`PRAGMA cache_size`)
- **CPU**: More parser workers (`config.parser_concurrency`)
- **Disk**: Faster SSD for database

**Tune connection pool:**

```yaml
# config/database.yml
log:
  pool: 20  # Increase from default 5
```

### Database Sharding (Advanced)

For >100M entries, consider time-based sharding:

```ruby
# db/migrate/..._create_sharded_entries.rb
# Separate tables by month
create_table :solid_log_entries_2025_01 do |t|
  # Same schema
end

create_table :solid_log_entries_2025_02 do |t|
  # Same schema
end
```

Query logic:

```ruby
def entries_for_range(start_time, end_time)
  tables = tables_for_range(start_time, end_time)
  results = tables.flat_map do |table|
    connection.select_all("SELECT * FROM #{table} WHERE ...")
  end
end
```

### Migration to PostgreSQL

For extreme scale (>1M logs/day), migrate to PostgreSQL:

1. Create PostgreSQL database
2. Export SQLite data:
   ```bash
   sqlite3 production_log.sqlite3 .dump > dump.sql
   ```
3. Import to PostgreSQL (with modifications)
4. Update `database.yml`:
   ```yaml
   log:
     adapter: postgresql
     database: solidlog_production
   ```

## Security

### Network Security

**Restrict API access:**

```nginx
# nginx config
location /admin/logs/api {
  # Only allow from internal network
  allow 10.0.0.0/8;
  deny all;

  proxy_pass http://localhost:3000;
}
```

**Use HTTPS:**

```ruby
# config/environments/production.rb
config.force_ssl = true
```

### Database Security

**File permissions:**

```bash
chmod 640 storage/production_log.sqlite3
chown deploy:deploy storage/production_log.sqlite3
```

**Encryption at rest:**

Use filesystem encryption (LUKS, dm-crypt) or encrypted volumes.

SQLite doesn't support native encryption, but you can use:
- [SQLCipher](https://www.zetetic.net/sqlcipher/)
- Encrypted filesystem

### Token Security

**Rotate regularly:**

```bash
# Every 90 days
rails solid_log:create_token["Production API v2"]
# Update apps
# Revoke old token
```

**Audit token usage:**

```bash
rails solid_log:list_tokens
```

Check `last_used_at` for inactive tokens.

### UI Authentication

**HTTP Basic Auth (default):**

```ruby
# config/initializers/solid_log.rb
config.authentication_method = :basic
```

Credentials in Rails credentials:

```yaml
solidlog:
  username: admin
  password: <%= SecureRandom.hex(16) %>
```

**Custom authentication:**

```ruby
# Override in host app
class SolidLog::ApplicationController
  before_action :authenticate_admin!

  def authenticate_admin!
    redirect_to root_path unless current_user&.admin?
  end
end
```

## Troubleshooting

### High Parse Backlog

**Symptoms:** Thousands of unparsed entries

**Causes:**
- Parser not running
- Parser too slow
- High ingestion rate

**Solutions:**

1. Check parser status:
   ```bash
   sudo systemctl status solidlog-parser
   ```

2. Increase concurrency:
   ```ruby
   config.parser_concurrency = 20
   ```

3. Run multiple workers:
   ```bash
   sudo systemctl start solidlog-parser@{1..5}
   ```

### Database Locked Errors

**Symptoms:** `database is locked` errors

**Causes:**
- Not using WAL mode
- Long-running transactions
- Busy timeout too low

**Solutions:**

1. Enable WAL:
   ```sql
   PRAGMA journal_mode=WAL;
   ```

2. Increase timeout:
   ```sql
   PRAGMA busy_timeout=10000;  -- 10 seconds
   ```

3. Reduce transaction size:
   ```ruby
   # Instead of one big transaction
   Entry.transaction do
     1000.times { create_entry }
   end

   # Use batches
   10.times do
     Entry.transaction do
       100.times { create_entry }
     end
   end
   ```

### Slow Queries

**Symptoms:** UI loads slowly, high CPU

**Causes:**
- Missing indexes
- Large result sets
- Expired facet cache

**Solutions:**

1. Check query plan:
   ```sql
   EXPLAIN QUERY PLAN SELECT * FROM solid_log_entries WHERE ...;
   ```

2. Add indexes for slow queries:
   ```ruby
   add_index :solid_log_entries, [:app, :env, :created_at]
   ```

3. Promote frequently filtered fields:
   ```bash
   rails g solid_log:promote_field user_id --type=number
   rails db:migrate
   ```

4. Warm facet cache:
   ```bash
   rails runner "SearchService.new({}).available_facets"
   ```

### Disk Space Issues

**Symptoms:** Database growing too large

**Solutions:**

1. Reduce retention:
   ```ruby
   config.retention_days = 14
   ```

2. Run cleanup:
   ```bash
   rails solid_log:retention_vacuum[14]
   ```

3. Delete old entries:
   ```sql
   DELETE FROM solid_log_entries WHERE created_at < '2025-01-01';
   DELETE FROM solid_log_raw WHERE received_at < '2025-01-01';
   VACUUM;
   ```

### Parser Errors

**Symptoms:** Entries stuck unparsed, errors in logs

**Causes:**
- Malformed JSON
- Unexpected field types
- Parser bugs

**Solutions:**

1. Check raw entries:
   ```ruby
   RawEntry.where(parsed: false).first.raw_payload
   ```

2. Test parser manually:
   ```ruby
   payload = RawEntry.unparsed.first.raw_payload
   Parser.parse(payload)
   ```

3. Fix malformed entries:
   ```ruby
   RawEntry.where(parsed: false).find_each do |entry|
     begin
       JSON.parse(entry.raw_payload)
     rescue JSON::ParserError
       entry.update(parsed: true)  # Mark as skipped
     end
   end
   ```

## Performance Benchmarks

Typical performance on modern hardware (4 CPU, 8GB RAM, SSD):

| Operation | Throughput | Latency |
|-----------|------------|---------|
| Ingestion (single) | 5,000 req/s | 2ms |
| Ingestion (batch 100) | 50,000 logs/s | 20ms |
| Parsing | 10,000 logs/s | 0.1ms/log |
| Query (indexed) | 100 req/s | 50ms |
| Query (FTS) | 20 req/s | 200ms |
| Facet lookup (cached) | 1000 req/s | 5ms |

Database size examples:

| Logs/Day | Days Retained | Size | Notes |
|----------|---------------|------|-------|
| 10,000 | 30 | 500 MB | Small app |
| 100,000 | 30 | 5 GB | Medium app |
| 1,000,000 | 30 | 50 GB | Large app |
| 1,000,000 | 90 | 150 GB | Extended retention |

## Conclusion

SolidLog is production-ready for most Rails applications with proper configuration. Focus on:

1. **WAL mode** for concurrency
2. **Parser workers** for timely processing
3. **Backups** via Litestream or cron
4. **Monitoring** for parse backlog and errors
5. **Retention policies** to manage growth

For questions or issues, see:
- [README.md](../README.md)
- [ARCHITECTURE.md](ARCHITECTURE.md)
- [GitHub Issues](https://github.com/namolnad/solid_log/issues)
