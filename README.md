# SolidLog

**Self-hosted log management for Rails applications using SQLite**

SolidLog is a Rails-native log ingestion and viewing service that eliminates the need for paid log viewers like Datadog, Splunk, or ELK for the majority of Rails applications. Store logs in SQLite, search with full-text search, and view in a Mission Control-style UI.

## Why SolidLog?

Most Rails applications don't need expensive, complex logging infrastructure. SolidLog provides:

- **Zero external dependencies**: Everything runs in your Rails app with SQLite
- **HTTP ingestion**: Send structured logs from any service via simple HTTP POST
- **Full-text search**: Powered by SQLite's FTS5 for fast log queries
- **Request/job correlation**: Trace requests and background jobs across your system
- **Mission Control UI**: Clean, familiar interface for browsing and filtering logs
- **Field promotion**: Auto-detect frequently used fields and optimize queries
- **Live tail**: Real-time log streaming in the browser
- **Cost**: Free, self-hosted, no per-GB pricing

## Features

### Core Logging
- **HTTP Ingestion API**: Bearer token authentication, single or batch inserts
- **Two-table architecture**: Fast writes (raw table) + optimized queries (entries table)
- **Multi-database support**: SQLite, PostgreSQL, and MySQL adapters with database-specific optimizations
- **Full-text search**: Database-native FTS (SQLite FTS5, PostgreSQL tsvector, MySQL FULLTEXT)
- **Structured logging**: Automatic parsing of JSON logs (Lograge format)
- **Multi-level filtering**: Filter by level, app, environment, time range, or custom fields

### Advanced Features
- **Request correlation**: View all logs for a request_id in timeline format
- **Job correlation**: Track background job execution across workers
- **Field registry**: Dynamic tracking of all JSON fields with usage stats
- **Field promotion**: Auto-detect hot fields and promote to indexed columns
- **Facet caching**: 5-minute cache for filter options to reduce DB load
- **Live tail**: Auto-refresh log stream for real-time monitoring
- **Retention policies**: Configurable retention with longer periods for errors (30/90 days default)
- **Health dashboard**: Monitor ingestion rate, parse backlog, error rate, database size

### UI
- **Mission Control-style dashboard**: Familiar Rails UI with stats and health metrics
- **Streams view**: Filter, search, and browse logs with multiple facets
- **Timeline views**: Chronological visualization of correlated events
- **Field management**: View field registry, promote/demote fields
- **Token management**: Create and manage API tokens for ingestion

## Quick Start

Want to try SolidLog in 5 minutes? See **[QUICKSTART.md](QUICKSTART.md)** for:
- Quick demo using the test/dummy app
- Step-by-step integration guide
- Testing the recursive logging prevention

## Installation

Add this line to your application's Gemfile:

```ruby
gem "solid_log"
```

And then execute:

```bash
bundle install
rails generate solid_log:install
rails db:migrate
```

The installer will:
- Copy an initializer to `config/initializers/solid_log.rb`
- Copy migrations to `db/log_migrate/`
- Show post-installation instructions

## Configuration

Configure SolidLog in `config/initializers/solid_log.rb`:

```ruby
SolidLog.configure do |config|
  # Retention policies
  config.retention_days = 30              # Keep regular logs for 30 days
  config.error_retention_days = 90        # Keep errors for 90 days

  # Parsing & ingestion
  config.max_batch_size = 1000            # Max logs per batch insert
  config.parser_concurrency = 5           # Parallel parser workers

  # Performance
  config.facet_cache_ttl = 5.minutes      # Cache filter options for 5 min

  # UI & Auth
  config.authentication_method = :basic   # :basic, :session, or :custom
  config.ui_enabled = true                # Enable web UI

  # Field promotion
  config.auto_promote_fields = false      # Auto-promote hot fields
  config.field_promotion_threshold = 1000 # Usage count for auto-promotion
end
```

### Database Configuration

SolidLog uses Rails 8.0+ multi-database support and works with **SQLite, PostgreSQL, or MySQL**.

**SQLite (default):**
```yaml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3
  log:
    adapter: sqlite3
    database: storage/production_log.sqlite3
    migrations_paths: db/log_migrate
```

**PostgreSQL (recommended for high volume):**
```yaml
production:
  primary:
    adapter: postgresql
    database: myapp_production
  log:
    adapter: postgresql
    database: myapp_log_production
    migrations_paths: db/log_migrate
    pool: 20
```

**MySQL:**
```yaml
production:
  primary:
    adapter: mysql2
    database: myapp_production
  log:
    adapter: mysql2
    database: myapp_log_production
    migrations_paths: db/log_migrate
    pool: 20
```

See [docs/DATABASE_ADAPTERS.md](docs/DATABASE_ADAPTERS.md) for detailed adapter documentation.

### Routes

Mount the engine in `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount SolidLog::Engine => "/admin/logs"
end
```

Access the UI at: `http://yourapp.com/admin/logs`

## Usage

### 1. Create an API Token

```bash
rails solid_log:create_token["Production API"]
```

This outputs a bearer token (only shown once). Save it securely.

### 2. Send Logs via HTTP

Send structured JSON logs to the ingestion endpoint:

```bash
curl -X POST http://yourapp.com/admin/logs/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-01-15T10:30:45Z",
    "level": "info",
    "message": "User login successful",
    "app": "web",
    "env": "production",
    "request_id": "abc-123",
    "user_id": 42,
    "ip": "192.168.1.1"
  }'
```

**Batch ingestion** (NDJSON):

```bash
curl -X POST http://yourapp.com/admin/logs/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/x-ndjson" \
  --data-binary @logs.ndjson
```

### 3. Set Up Parser Worker

Logs are stored raw and parsed asynchronously. Set up a worker process:

**Option A: Cron**
```cron
*/5 * * * * cd /path/to/app && bundle exec rails solid_log:parse_logs
```

**Option B: Systemd Service**
```ini
[Unit]
Description=SolidLog Parser Worker
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/myapp
ExecStart=/bin/bash -lc 'bundle exec rails solid_log:parse_logs'
Restart=always

[Install]
WantedBy=multi-user.target
```

**Option C: Background Job** (Recommended)
```ruby
# config/initializers/solid_log.rb
# Schedule with Solid Queue, Sidekiq, or your job backend
SolidLog::ParserJob.set(wait: 5.minutes).perform_later
```

### 4. View Logs in the UI

Navigate to `/admin/logs` to:
- Browse recent logs with filters (level, app, env, time)
- Search log messages with full-text search
- View correlated logs (by request_id or job_id)
- Monitor health metrics and error rates
- Manage fields and tokens

## Rake Tasks

```bash
# Process unparsed logs
rails solid_log:parse_logs

# Create API token
rails solid_log:create_token["Token Name"]

# List all tokens
rails solid_log:list_tokens

# View statistics
rails solid_log:stats

# Cleanup old logs (keep last 30 days)
rails solid_log:retention[30]

# Cleanup + VACUUM database
rails solid_log:retention_vacuum[30]

# View field registry and promotion candidates
rails solid_log:analyze_fields

# Auto-promote hot fields
rails solid_log:field_auto_promote

# Show health metrics
rails solid_log:health

# Clear expired cache
rails solid_log:cache_cleanup

# Optimize database
rails solid_log:optimize
```

## Lograge Integration

For Rails apps using [Lograge](https://github.com/roidrage/lograge), configure it to send JSON to SolidLog:

```ruby
# config/environments/production.rb
config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new

# Send logs to SolidLog via HTTP
config.lograge.logger = ActiveSupport::Logger.new(
  SolidLog::HttpLogger.new(
    url: "http://localhost:3000/admin/logs/api/v1/ingest",
    token: ENV["SOLIDLOG_TOKEN"]
  )
)
```

## Architecture

SolidLog uses a two-table architecture for optimal performance:

```
┌─────────────────┐
│  HTTP Ingestion │  Fast, append-only writes
│  (Bearer Token) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ solid_log_raw   │  Append-only table (JSON blobs)
└────────┬────────┘
         │
         ▼ Parser Worker (claims unparsed rows)
┌─────────────────┐
│ solid_log_      │  Parsed, indexed, queryable
│ entries         │  + FTS5 full-text search
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Mission Control │  Web UI with filters, search,
│ UI              │  correlation, live tail
└─────────────────┘
```

**Benefits:**
- Fast ingestion (raw inserts)
- CPU-intensive parsing doesn't block writes
- Audit trail preserved (raw entries)
- Optimized queries on parsed data

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design documentation.

## API Reference

See [docs/API.md](docs/API.md) for complete API documentation.

**Quick Reference:**

```bash
POST /admin/logs/api/v1/ingest
Authorization: Bearer YOUR_TOKEN
Content-Type: application/json

{
  "timestamp": "2025-01-15T10:30:45Z",
  "level": "info|debug|warn|error|fatal",
  "message": "Log message",
  "app": "web",
  "env": "production",
  "request_id": "optional-correlation-id",
  "job_id": "optional-job-correlation-id",
  ...additional fields...
}
```

**Response:**
```json
{
  "status": "accepted",
  "count": 1
}
```

## Deployment

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for production deployment guides including:
- Kamal configuration
- SQLite tuning (WAL mode, pragmas)
- Multi-process setup
- Scaling considerations
- Monitoring and alerting

## Field Promotion

SolidLog automatically tracks all JSON fields in a registry. Frequently accessed fields can be "promoted" to dedicated columns for faster queries:

**Manual Promotion:**
```bash
rails g solid_log:promote_field user_id --type=number
rails db:migrate
```

**Auto Promotion:**
```ruby
# config/initializers/solid_log.rb
config.auto_promote_fields = true
config.field_promotion_threshold = 1000  # Promote after 1000 uses
```

Promoted fields get:
- Dedicated indexed column
- Faster filtering and sorting
- Backward compatibility (field stays in JSON too)

## Performance

SolidLog is designed for high performance on SQLite:

- **Ingestion**: 10,000+ logs/second on modern hardware
- **Parsing**: 5,000+ logs/second per worker
- **Search**: Sub-second FTS5 queries on millions of entries
- **Facet caching**: Filter options cached for 5 minutes
- **WAL mode**: Concurrent reads during writes
- **Optimized indexes**: Level, app, env, timestamps, correlation IDs

**Scaling:**
- SQLite handles 100M+ log entries efficiently
- Run multiple parser workers for high ingestion loads
- Use retention policies to manage database size
- Promote hot fields for faster queries

## Authentication

### UI Authentication

**Option 1: HTTP Basic (Default)**
```ruby
# config/initializers/solid_log.rb
SolidLog.configure do |config|
  config.authentication_method = :basic
end

# Store credentials in Rails credentials
solidlog:
  username: admin
  password: secret
```

**Option 2: Host App Session**
```ruby
# Use your app's authentication
class SolidLog::ApplicationController
  before_action :authenticate_admin!

  private

  def authenticate_admin!
    redirect_to root_path unless current_user&.admin?
  end
end
```

### API Authentication

API uses bearer tokens stored with BCrypt hashing:

```bash
# Create token
rails solid_log:create_token["Production API"]

# Use in requests
curl -H "Authorization: Bearer abc123..." http://...
```

Tokens track last usage timestamp for auditing.

## Development

```bash
# Clone repo
git clone https://github.com/namolnad/solid_log
cd solid_log

# Install dependencies
bundle install

# Run tests
rails test

# Run test app
cd test/dummy
rails db:migrate RAILS_ENV=development
rails server
```

## Documentation

Comprehensive guides are available in the repository:

- **[QUICKSTART.md](QUICKSTART.md)** - Get started in 5 minutes
- **[DEVELOPMENT.md](DEVELOPMENT.md)** - Testing and contributing guide
- **[docs/API.md](docs/API.md)** - HTTP API reference
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design and internals
- **[docs/DATABASE_ADAPTERS.md](docs/DATABASE_ADAPTERS.md)** - SQLite, PostgreSQL, MySQL adapters
- **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Production deployment guide
- **[docs/RECURSIVE_LOGGING_PREVENTION.md](docs/RECURSIVE_LOGGING_PREVENTION.md)** - How SolidLog prevents logging itself

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/namolnad/solid_log.

**For developers:** See [DEVELOPMENT.md](DEVELOPMENT.md) for:
- Running the test suite (98 tests, 262 assertions)
- Code structure and architecture
- Writing new tests
- Debugging tips

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Roadmap

- [ ] Alerting system (webhook notifications for errors)
- [ ] Export functionality (CSV, JSON)
- [ ] Log aggregations (GROUP BY queries in UI)
- [ ] Saved searches
- [ ] Dark mode
- [ ] API for querying logs
- [ ] PostgreSQL adapter (for high-volume deployments)

## Alternatives

SolidLog is designed for **small to medium Rails applications** that want simple, self-hosted logging. Consider alternatives if:

- **High volume** (>1M logs/day): Use PostgreSQL adapter or ELK/Loki
- **Multi-language**: SolidLog is Rails-native; consider ELK, Loki, or Graylog
- **Advanced features**: Datadog/New Relic offer APM, tracing, metrics
- **Compliance**: Check if self-hosted logs meet your requirements

## Credits

Inspired by:
- [mission_control-jobs](https://github.com/rails/mission_control-jobs) - UI design
- [Lograge](https://github.com/roidrage/lograge) - Structured logging
- [Solid Queue](https://github.com/rails/solid_queue) - SQLite-backed Rails services
- [Litestream](https://litestream.io/) - SQLite replication (recommended for backups)
