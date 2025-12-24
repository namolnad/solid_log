# SolidLog Quick Start Guide

Get SolidLog running in 5 minutes to see it in action.

## Prerequisites

- Rails 8.0+
- Ruby 3.2+
- SQLite, PostgreSQL, or MySQL

## Option 1: Quick Demo in Test/Dummy App

The fastest way to try SolidLog is using the included test dummy app:

```bash
# Clone the repo
git clone https://github.com/yourusername/solid_log.git
cd solid_log

# Install dependencies
bundle install

# Set up the test database
cd test/dummy
rails db:create
rails db:migrate

# Start the Rails server
rails server
```

### Create a Token

```bash
rails runner "result = SolidLog::Token.generate!('Demo Token'); puts 'Token: ' + result[:token]"
```

Save the token - you'll need it for sending logs.

### Send a Test Log

```bash
curl -X POST http://localhost:3000/solid_log/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN_HERE" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-12-23T10:30:00Z",
    "level": "info",
    "message": "Hello from SolidLog!",
    "app": "demo",
    "env": "development",
    "user_id": 42
  }'
```

### Parse and View Logs

```bash
# Parse the raw log entry
rails runner "SolidLog::ParserJob.perform_now"

# Open the UI
open http://localhost:3000/solid_log
```

You should see your log entry in the UI!

---

## Option 2: Add to Existing Rails App

### 1. Install the Gem

Add to your `Gemfile`:

```ruby
gem "solid_log"
```

Then:

```bash
bundle install
rails generate solid_log:install
rails db:migrate
```

### 2. Configure Database (Multi-Database Setup)

Edit `config/database.yml`:

```yaml
development:
  primary:
    adapter: sqlite3
    database: storage/development.sqlite3
  log:
    adapter: sqlite3
    database: storage/development_log.sqlite3
    migrations_paths: db/log_migrate

production:
  primary:
    adapter: postgresql
    database: myapp_production
  log:
    adapter: postgresql
    database: myapp_log_production
    migrations_paths: db/log_migrate
```

### 3. Mount the Engine

Edit `config/routes.rb`:

```ruby
Rails.application.routes.draw do
  mount SolidLog::Engine => "/solid_log"
  # ... your other routes
end
```

### 4. Create an API Token

```bash
rails runner "result = SolidLog::Token.generate!('Production'); puts result[:token]"
```

**Important:** Save this token securely - it's only shown once!

### 5. Send Logs

#### From Command Line

```bash
curl -X POST http://localhost:3000/solid_log/api/v1/ingest \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "timestamp": "2025-12-23T10:30:00Z",
    "level": "error",
    "message": "Payment processing failed",
    "request_id": "abc-123",
    "user_id": 42,
    "error_class": "Stripe::CardError"
  }'
```

#### From Ruby Code

```ruby
require "net/http"
require "json"

def send_to_solidlog(message, level: "info", **extra_fields)
  uri = URI("http://localhost:3000/solid_log/api/v1/ingest")
  
  http = Net::HTTP.new(uri.host, uri.port)
  request = Net::HTTP::Post.new(uri.path)
  request["Authorization"] = "Bearer #{ENV['SOLIDLOG_TOKEN']}"
  request["Content-Type"] = "application/json"
  
  payload = {
    timestamp: Time.current.iso8601,
    level: level,
    message: message,
    app: "myapp",
    env: Rails.env
  }.merge(extra_fields)
  
  request.body = payload.to_json
  http.request(request)
end

# Usage
send_to_solidlog("User logged in", user_id: 123, ip: "192.168.1.1")
```

### 6. Set Up Parser Worker

Choose one option:

**Option A: Background Job (Recommended)**

```ruby
# config/initializers/solid_log.rb
# Run parser every 5 minutes with Solid Queue, Sidekiq, etc.
```

**Option B: Cron Job**

```bash
# Add to crontab
*/5 * * * * cd /path/to/app && bundle exec rails solid_log:parse_logs
```

**Option C: Manual (Development Only)**

```bash
rails runner "SolidLog::ParserJob.perform_now"
```

### 7. View the UI

Visit: `http://localhost:3000/solid_log`

Features:
- 📊 Dashboard with health metrics
- 🔍 Full-text search across all logs
- 📋 Filter by level, app, environment, time
- 🔗 Correlation view (trace request_id or job_id)
- 📈 Field registry showing all discovered fields

---

## Testing the Silence Mechanism

To verify SolidLog doesn't recursively log itself:

### 1. Enable Logging to SolidLog

```ruby
# config/initializers/solid_log_client.rb
require "solid_log/log_subscriber"

SolidLog.configure do |config|
  config.client_token = ENV["SOLIDLOG_TOKEN"]
  config.ingestion_url = "http://localhost:3000/solid_log/api/v1/ingest"
end

Rails.logger.extend(ActiveSupport::TaggedLogging)
Rails.logger.broadcast_to(SolidLog::LogSubscriber.logger)

SolidLog::LogSubscriber.start_flush_thread(interval: 5, batch_size: 100)

at_exit { SolidLog::LogSubscriber.stop_flush_thread }
```

### 2. Test Recursive Logging Prevention

```ruby
# In rails console
Rails.logger.info "This will be sent to SolidLog"

# Send a log via HTTP (this should NOT create infinite recursion)
SolidLog::RawEntry.create!(
  raw_payload: {message: "Test"}.to_json,
  token_id: 1,
  received_at: Time.current
)

# Check: you should see the first log, but NOT a log about creating the RawEntry
```

---

## Next Steps

- **Configure retention**: `config.retention_days = 30`
- **Set up field promotion**: `rails solid_log:analyze_fields`
- **Add authentication**: See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- **Deploy to production**: See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)
- **Multi-database setup**: See [docs/DATABASE_ADAPTERS.md](docs/DATABASE_ADAPTERS.md)

## Troubleshooting

### Logs not appearing in UI?

```bash
# Check raw entries
rails runner "puts SolidLog::RawEntry.count"

# Check if they're parsed
rails runner "puts SolidLog::RawEntry.unparsed.count"

# Manually parse
rails runner "SolidLog::ParserJob.perform_now"

# Check entries
rails runner "puts SolidLog::Entry.count"
```

### Authentication failing?

```bash
# Verify token
rails runner "token = SolidLog::Token.find(1); puts token.authenticate('YOUR_TOKEN')"

# List all tokens
rails solid_log:list_tokens
```

### Database issues?

```bash
# Check migrations
rails db:migrate:status

# For log database
rails db:migrate:status:log

# Reset log database (WARNING: deletes all logs)
rails db:drop:log db:create:log db:migrate:log
```

## Running Tests

```bash
# Run all tests
bundle exec rake test

# Run specific test file
bundle exec ruby -Itest test/models/solid_log/entry_test.rb

# Run all tests with summary
bash test/test_summary.sh
```

See [DEVELOPMENT.md](DEVELOPMENT.md) for more details on testing and development.
