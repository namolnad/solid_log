# SolidLog Quickstart Guide

This guide will help you integrate SolidLog into your Rails application in about 15 minutes.

## Prerequisites

- Rails 8.0+ application
- Ruby 3.1+ (3.2+ recommended)
- SQLite 3.8+ (or PostgreSQL 12+, MySQL 8.0+)

## Step 1: Install the Gems

SolidLog consists of three gems. You can install all three for a complete setup, or just the ones you need.

### Option A: Install All Gems (Recommended)

Add to your `Gemfile`:

```ruby
# If you've vendored the gems locally
gem "solid_log-core", path: "vendor/gems/solid_log-core"
gem "solid_log-service", path: "vendor/gems/solid_log-service"
gem "solid_log-ui", path: "vendor/gems/solid_log-ui"

# Or if published to RubyGems (future)
# gem "solid_log-core"
# gem "solid_log-service"
# gem "solid_log-ui"
```

Then run:

```bash
bundle install
```

### Option B: Custom Installation

Install only what you need:

- **Core only**: For custom implementations
  ```ruby
  gem "solid_log-core"
  ```

- **Core + Service**: For ingestion without UI
  ```ruby
  gem "solid_log-core"
  gem "solid_log-service"
  ```

- **Core + UI**: For viewing existing logs
  ```ruby
  gem "solid_log-core"
  gem "solid_log-ui"
  ```

## Step 2: Configure Database

SolidLog uses Rails 8.0+ multi-database support. Add a `:log` database to `config/database.yml`:

### SQLite (Default)

```yaml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

development:
  primary:
    <<: *default
    database: storage/development.sqlite3

  log:
    <<: *default
    database: storage/development_log.sqlite3
    migrations_paths: db/log_migrate

test:
  primary:
    <<: *default
    database: storage/test.sqlite3

  log:
    <<: *default
    database: storage/test_log.sqlite3
    migrations_paths: db/log_migrate

production:
  primary:
    <<: *default
    database: storage/production.sqlite3

  log:
    <<: *default
    database: storage/production_log.sqlite3
    migrations_paths: db/log_migrate
```

### PostgreSQL (Recommended for High Volume)

```yaml
default: &default
  adapter: postgresql
  encoding: unicode
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  primary:
    <<: *default
    database: myapp_development

  log:
    <<: *default
    database: myapp_log_development
    migrations_paths: db/log_migrate
    pool: 10  # Higher pool for concurrent log queries

production:
  primary:
    <<: *default
    database: myapp_production
    username: myapp
    password: <%= ENV["DATABASE_PASSWORD"] %>

  log:
    <<: *default
    database: myapp_log_production
    username: myapp
    password: <%= ENV["DATABASE_PASSWORD"] %>
    migrations_paths: db/log_migrate
    pool: 20
```

### MySQL

```yaml
default: &default
  adapter: mysql2
  encoding: utf8mb4
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>

development:
  primary:
    <<: *default
    database: myapp_development

  log:
    <<: *default
    database: myapp_log_development
    migrations_paths: db/log_migrate

production:
  primary:
    <<: *default
    database: myapp_production
    username: myapp
    password: <%= ENV["DATABASE_PASSWORD"] %>

  log:
    <<: *default
    database: myapp_log_production
    username: myapp
    password: <%= ENV["DATABASE_PASSWORD"] %>
    migrations_paths: db/log_migrate
    pool: 20
```

## Step 3: Copy Migrations

Copy the migrations from each gem to your app:

```bash
# Create the log migrations directory
mkdir -p db/log_migrate

# Copy core migrations
cp solid_log-core/db/migrate/*.rb db/log_migrate/

# Note: Service and UI gems don't have migrations -
# all database schema is in the core gem
```

Or if you're developing from the monorepo:

```bash
mkdir -p db/log_migrate
cp solid_log-core/db/migrate/*.rb db/log_migrate/
```

## Step 4: Run Migrations

```bash
# Create databases (if using PostgreSQL/MySQL)
rails db:create

# Run migrations for both databases
rails db:migrate

# This will migrate:
# - Your primary database (if needed)
# - Your log database with SolidLog schema
```

You should see output like:

```
== 20250101000001 CreateSolidLogTables: migrating ============================
-- create_table(:solid_log_tokens)
   -> 0.0012s
-- create_table(:solid_log_raw)
   -> 0.0008s
-- create_table(:solid_log_entries)
   -> 0.0015s
-- create_table(:solid_log_fields)
   -> 0.0007s
-- create_table(:solid_log_facet_cache)
   -> 0.0006s
== 20250101000001 CreateSolidLogTables: migrated (0.0050s) ===================
```

## Step 5: Configure SolidLog

Create an initializer at `config/initializers/solid_log.rb`:

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

  # UI & Auth (if using solid_log-ui)
  config.ui_enabled = true
  config.authentication_method = :basic   # :basic, :session, or :custom

  # Field promotion (optional)
  config.auto_promote_fields = false      # Auto-promote hot fields
  config.field_promotion_threshold = 1000 # Usage count for auto-promotion
end

# Enable WAL mode for SQLite (HIGHLY RECOMMENDED for production)
# WAL mode provides 3.4x faster eager flush performance
ActiveRecord::Base.connected_to(role: :log) do
  ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
  ActiveRecord::Base.connection.execute("PRAGMA synchronous=NORMAL")
end
```

**Why WAL Mode?**
- **3.4x faster** eager flush (16,882 vs 4,923 logs/sec)
- Better concurrency (readers don't block writers)
- Safer for production (write-ahead logging)
- Skip this if using PostgreSQL or MySQL (they have their own WAL)

## Step 6: Mount the UI (If Using solid_log-ui)

Add to `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  # Mount SolidLog UI
  mount SolidLog::UI::Engine => "/admin/logs"

  # Your other routes...
end
```

The UI will be available at `http://localhost:3000/admin/logs`

## Step 7: Create an API Token

Create a token for log ingestion:

```bash
rails solid_log:create_token["Development API"]
```

You'll see output like:

```
Token created successfully!

Name: Development API
Token: slk_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2

⚠️  IMPORTANT: This token will only be shown once!
   Save it securely. You cannot retrieve it later.

Use this token in the Authorization header:
  Authorization: Bearer slk_a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u1v2w3x4y5z6a7b8c9d0e1f2
```

**Save this token!** You'll need it for Step 9.

## Step 8: Start the Server

```bash
rails server
```

Visit `http://localhost:3000/admin/logs` - you should see the SolidLog dashboard (empty for now).

## Step 9: Send Your First Log

Test the ingestion API with curl:

```bash
curl -X POST http://localhost:3000/admin/logs/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'",
    "level": "info",
    "message": "Hello from SolidLog!",
    "app": "quickstart",
    "env": "development"
  }'
```

You should see:

```json
{
  "status": "accepted",
  "count": 1
}
```

## Step 10: Parse the Logs

Logs are stored raw and parsed asynchronously. Run the parser manually:

```bash
rails solid_log:parse_logs
```

You should see:

```
Parsing logs...
Processed 1 entries in 0.05 seconds
```

Now refresh `http://localhost:3000/admin/logs/streams` - your log should appear!

## Step 11: Set Up Background Processing

For production, you'll want logs parsed automatically. Choose one option:

### Option A: Cron Job (Simple)

Add to your crontab:

```cron
# Parse logs every 5 minutes
*/5 * * * * cd /path/to/app && bundle exec rails solid_log:parse_logs RAILS_ENV=production
```

### Option B: Background Job (Recommended)

If you're using Solid Queue, Sidekiq, or another job backend:

```ruby
# config/initializers/solid_log.rb (add to existing config)

# Schedule parser job to run every 5 minutes
if Rails.env.production?
  Rails.application.config.after_initialize do
    SolidLog::Service::ParserJob.set(wait: 5.minutes).perform_later
  end
end
```

The job will automatically re-enqueue itself for continuous processing.

### Option C: Systemd Service (Linux Servers)

Create `/etc/systemd/system/solidlog-parser.service`:

```ini
[Unit]
Description=SolidLog Parser Worker
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/var/www/myapp
Environment="RAILS_ENV=production"

ExecStart=/bin/bash -lc 'while true; do bundle exec rails solid_log:parse_logs; sleep 30; done'

Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable solidlog-parser
sudo systemctl start solidlog-parser
```

## Step 12: Configure Retention Cleanup (Optional)

To automatically delete old logs, add a daily cleanup job:

### Cron

```cron
# Daily cleanup at 2 AM
0 2 * * * cd /path/to/app && bundle exec rails solid_log:retention_vacuum[30] RAILS_ENV=production
```

### Background Job

```ruby
# config/initializers/solid_log.rb

if Rails.env.production?
  Rails.application.config.after_initialize do
    # Schedule retention job daily at 2 AM
    SolidLog::Service::RetentionJob.set(wait_until: Date.tomorrow.beginning_of_day + 2.hours).perform_later
  end
end
```

## Next Steps

### Integrate with Your Application Logs

To automatically send your Rails logs to SolidLog, you have two options:

#### Option A: DirectLogger (Recommended for Parent App)

Use DirectLogger for your main Rails app - **it's 9x faster than individual inserts and 67x faster than HTTP**:

```ruby
# config/environments/production.rb

config.lograge.enabled = true
config.lograge.formatter = Lograge::Formatters::Json.new

# Use DirectLogger for direct database access (fastest!)
config.lograge.logger = ActiveSupport::Logger.new(
  SolidLog::DirectLogger.new(
    batch_size: 100,           # Flush after 100 logs
    flush_interval: 5,          # Or after 5 seconds
    eager_flush_levels: [:error, :fatal]  # Flush errors immediately
  )
)
```

**IMPORTANT - Crash Safety:** By default, DirectLogger **flushes error and fatal logs immediately** to prevent data loss if your app crashes. The logs explaining WHY it crashed won't be lost in the buffer.

**Token Configuration (Optional):**

DirectLogger's token_id is **optional** (nullable). It's only needed for audit trail tracking:

```ruby
# Option 1: No token (default - recommended for parent app)
config.lograge.logger = ActiveSupport::Logger.new(SolidLog::DirectLogger.new)

# Option 2: Use environment variable (for audit trail)
ENV["SOLIDLOG_TOKEN_ID"] = "123"  # Token ID from database
config.lograge.logger = ActiveSupport::Logger.new(SolidLog::DirectLogger.new)

# Option 3: Pass explicitly (for audit trail)
token_id = SolidLog::Token.find_by(name: "Production")&.id
config.lograge.logger = ActiveSupport::Logger.new(
  SolidLog::DirectLogger.new(token_id: token_id)
)
```

**Note:** Tokens are primarily for HTTP API authentication. DirectLogger can use `nil` token since it logs internally.

#### Option B: HTTP Logger (For External Services)

Use HTTP for services without direct database access:

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

**When to use each:**
- ✅ **DirectLogger**: Parent Rails app with database access (9x faster than individual inserts, 67x faster than HTTP)
- ✅ **HTTP Logger**: External services, microservices, remote apps

**Performance Tips:**
- Enable WAL mode for SQLite (3.4x faster eager flush - see below)
- Use default eager_flush settings for crash safety
- DirectLogger achieves 16,882 logs/sec with crash safety, 56,660 logs/sec without

### Explore the UI

Visit `http://localhost:3000/admin/logs` to:

- **Dashboard**: View recent errors, log level distribution, health metrics
- **Streams**: Browse logs with filters (level, app, env, time range)
- **Search**: Full-text search across all log messages
- **Timeline**: View correlated logs by request_id or job_id
- **Fields**: Manage field registry, promote hot fields
- **Tokens**: Create and manage API tokens

### Send Logs from Other Services

Any service can send logs via HTTP POST:

**Ruby:**
```ruby
require 'net/http'
require 'json'

uri = URI('http://localhost:3000/admin/logs/api/v1/ingest')
http = Net::HTTP.new(uri.host, uri.port)

request = Net::HTTP::Post.new(uri.path)
request['Authorization'] = "Bearer #{ENV['SOLIDLOG_TOKEN']}"
request['Content-Type'] = 'application/json'
request.body = {
  timestamp: Time.now.utc.iso8601,
  level: 'info',
  message: 'Service event occurred',
  app: 'background-worker',
  env: 'production',
  user_id: 123
}.to_json

response = http.request(request)
```

**Python:**
```python
import requests
from datetime import datetime

response = requests.post(
    'http://localhost:3000/admin/logs/api/v1/ingest',
    headers={
        'Authorization': 'Bearer YOUR_TOKEN',
        'Content-Type': 'application/json'
    },
    json={
        'timestamp': datetime.utcnow().isoformat() + 'Z',
        'level': 'info',
        'message': 'Python service event',
        'app': 'data-processor',
        'env': 'production'
    }
)
```

**Node.js:**
```javascript
const axios = require('axios');

axios.post('http://localhost:3000/admin/logs/api/v1/ingest', {
  timestamp: new Date().toISOString(),
  level: 'info',
  message: 'Node.js service event',
  app: 'api-gateway',
  env: 'production'
}, {
  headers: {
    'Authorization': `Bearer ${process.env.SOLIDLOG_TOKEN}`,
    'Content-Type': 'application/json'
  }
});
```

### Batch Ingestion

For high-volume logging, use batch ingestion with NDJSON:

```bash
# Create NDJSON file (one JSON object per line)
cat > logs.ndjson << EOF
{"timestamp":"2025-01-15T10:00:00Z","level":"info","message":"Log 1","app":"test"}
{"timestamp":"2025-01-15T10:00:01Z","level":"info","message":"Log 2","app":"test"}
{"timestamp":"2025-01-15T10:00:02Z","level":"error","message":"Log 3","app":"test"}
EOF

# Send batch
curl -X POST http://localhost:3000/admin/logs/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/x-ndjson" \
  --data-binary @logs.ndjson
```

Response:
```json
{
  "status": "accepted",
  "count": 3
}
```

## DirectLogger: Crash Safety & Configuration

### Understanding the Buffer Risk ⚠️

DirectLogger batches logs in memory for performance. This creates a risk:

**If your app crashes, buffered logs are lost - including the logs explaining WHY it crashed.**

### Default Protection (Eager Flush)

By default, DirectLogger flushes **error and fatal logs immediately**:

```ruby
SolidLog::DirectLogger.new(
  eager_flush_levels: [:error, :fatal]  # Default - flushes critical logs immediately
)
```

**How it works:**
- Info/debug/warn logs: Buffered (fast)
- Error/fatal logs: Flushed immediately (safe)
- When error occurs: All buffered logs + error log flushed together

**Example:**
```
10:00:00 - info: Request started (buffered)
10:00:01 - info: Processing params (buffered)
10:00:02 - ERROR: Database connection lost (FLUSHES ALL 3 LOGS IMMEDIATELY)
[App crashes - but logs are safe!]
```

### Configuration Options

**Maximum safety (flush everything immediately):**
```ruby
SolidLog::DirectLogger.new(
  batch_size: 1,  # Flush after every log
  eager_flush_levels: [:debug, :info, :warn, :error, :fatal]
)
# Slowest, but no buffer risk
```

**Maximum performance (buffer everything):**
```ruby
SolidLog::DirectLogger.new(
  batch_size: 500,
  flush_interval: 30,
  eager_flush_levels: []  # Disable eager flush
)
# Fastest, but risky - up to 500 logs or 30 seconds could be lost
# Only use if you have external log backup
```

**Recommended balance (default):**
```ruby
SolidLog::DirectLogger.new(
  batch_size: 100,
  flush_interval: 5,
  eager_flush_levels: [:error, :fatal]
)
# Fast for normal logs, safe for errors
```

### Token Configuration

DirectLogger's `token_id` is **optional** (nullable). Use it only if you need audit trail tracking:

**Priority order:**
1. Explicit `token_id` parameter
2. `ENV["SOLIDLOG_TOKEN_ID"]` environment variable
3. `nil` (default - no token required)

```ruby
# Option 1: No token (recommended for parent app)
logger = SolidLog::DirectLogger.new

# Option 2: Use environment variable (for audit trail)
ENV["SOLIDLOG_TOKEN_ID"] = SolidLog::Token.find_by(name: "Production")&.id.to_s
logger = SolidLog::DirectLogger.new

# Option 3: Pass explicitly (for audit trail)
logger = SolidLog::DirectLogger.new(
  token_id: SolidLog::Token.find_by(name: "Production")&.id
)
```

**Note:** Tokens are primarily for HTTP API authentication. DirectLogger doesn't need a token since it logs internally.

### When DirectLogger is NOT Safe

DirectLogger cannot prevent loss in these scenarios:

- **Segfault / SIGSEGV**: Immediate crash, no cleanup
- **SIGKILL / kill -9**: Forceful termination, no cleanup
- **Power loss**: Server shutdown, no cleanup
- **OOM killer**: Process killed by system

**Mitigation:**
- Enable eager flush for critical logs (default)
- Use shorter flush intervals in production (1-2 seconds)
- Have external log backup for critical systems
- Monitor for missing logs (gaps in timestamps)

## Troubleshooting

### Issue: "No route matches"

**Problem:** Routes aren't loading

**Solution:** Make sure you've mounted the engine:
```ruby
# config/routes.rb
mount SolidLog::UI::Engine => "/admin/logs"
```

### Issue: "Uninitialized constant SolidLog"

**Problem:** Gems not loaded

**Solution:** Run `bundle install` and restart your Rails server

### Issue: "ActiveRecord::StatementInvalid: no such table"

**Problem:** Migrations haven't run

**Solution:**
```bash
rails db:migrate
```

### Issue: Logs aren't appearing in UI

**Problem:** Logs haven't been parsed yet

**Solution:** Run the parser manually:
```bash
rails solid_log:parse_logs
```

### Issue: "401 Unauthorized" when sending logs

**Problem:** Invalid or missing API token

**Solution:**
- Check the token is correct
- Ensure the `Authorization: Bearer TOKEN` header is set
- Create a new token: `rails solid_log:create_token["New Token"]`

### Issue: "Database is locked" errors

**Problem:** SQLite concurrency issue

**Solution:** Enable WAL mode:
```bash
sqlite3 storage/development_log.sqlite3 "PRAGMA journal_mode=WAL;"
```

Or switch to PostgreSQL for high-volume deployments.

## What's Next?

- **[Read the Architecture Guide](docs/ARCHITECTURE.md)** to understand how SolidLog works
- **[Explore the API Documentation](docs/API.md)** for detailed API reference
- **[Review Deployment Guide](docs/DEPLOYMENT.md)** for production best practices
- **[Check Database Adapters](docs/DATABASE_ADAPTERS.md)** for adapter-specific optimizations
- **[Run the Demo App](demo/README.md)** to see all features in action

## Getting Help

- Check the [main README](README.md) for overview and features
- Browse [docs/](docs/) for comprehensive guides
- Open an issue on GitHub for bugs or questions
- Review [TEST_QUALITY_REPORT.md](TEST_QUALITY_REPORT.md) to see test coverage

Enjoy using SolidLog! 🎉
