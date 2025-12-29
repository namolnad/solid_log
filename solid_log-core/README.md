# SolidLog::Core

Core models, database adapters, parser, DirectLogger, and HTTP client for the SolidLog logging system.

## Overview

`solid_log-core` provides the shared foundation for `solid_log-service` and `solid_log-ui` gems:

- **Models**: `RawEntry`, `Entry`, `Token`, `Field`, `FacetCache`
- **Database Adapters**: SQLite, PostgreSQL, MySQL adapters with database-specific optimizations
- **DirectLogger**: High-performance batched logging for parent app (50,000+ logs/sec)
- **Parser**: Structured log parsing with field extraction
- **Service Objects**: `RetentionService`, `FieldAnalyzer`, `SearchService`, `CorrelationService`
- **HTTP Client**: Buffered log sender with retry logic for remote ingestion
- **Migrations**: Database schema in `db/log_migrate/`

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'solid_log-core'

# Also ensure you have the database adapter gem for your database:
gem 'sqlite3', '>= 2.1'   # For SQLite
# OR
gem 'pg', '>= 1.1'        # For PostgreSQL
# OR
gem 'mysql2', '>= 0.5'    # For MySQL
```

**Dependencies:**
- `solid_log-core` requires only specific Rails components: `activerecord`, `activesupport`, and `activejob`
- It does **NOT** require the full `rails` gem
- Database adapter gems are optional - install only what you need

## Usage

This gem is typically used as a dependency for:
- **solid_log-service**: Standalone log ingestion service
- **solid_log-ui**: Web interface for viewing logs

### DirectLogger (Recommended for Parent App)

**DirectLogger** writes logs directly to the database for maximum performance. Use this when your Rails app has direct database access.

```ruby
# config/initializers/lograge.rb
Rails.application.configure do
  config.lograge.enabled = true
  config.lograge.formatter = Lograge::Formatters::Json.new

  # Use DirectLogger for fast, batched database writes
  config.lograge.logger = ActiveSupport::Logger.new(
    SolidLog::DirectLogger.new(
      batch_size: 100,                      # Batch size (default: 100)
      flush_interval: 5,                    # Flush every 5 seconds
      eager_flush_levels: [:error, :fatal]  # Flush immediately on errors (crash safety)
    )
  )
end
```

**Performance:**
- **16,882 logs/sec** with crash safety (SQLite + WAL mode)
- **56,660 logs/sec** without eager flush (risky - may lose crash logs)
- **9x faster** than individual database inserts
- **67x faster** than HTTP logging

**Configuration Options:**

```ruby
SolidLog::DirectLogger.new(
  batch_size: 100,                      # Logs per batch (default: 100)
  flush_interval: 5,                    # Flush interval in seconds (default: 5)
  eager_flush_levels: [:error, :fatal], # Flush these levels immediately (default: [:error, :fatal])
  token_id: nil                          # Optional token for audit trail (default: nil or ENV['SOLIDLOG_TOKEN_ID'])
)
```

**Crash Safety:**

By default, DirectLogger flushes error and fatal logs immediately to prevent losing the logs that explain WHY your app crashed:

```ruby
# Safe (recommended for production)
logger = SolidLog::DirectLogger.new(
  eager_flush_levels: [:error, :fatal]
)

# Maximum performance (risky - may lose crash context)
logger = SolidLog::DirectLogger.new(
  eager_flush_levels: []
)

# Maximum safety (slower)
logger = SolidLog::DirectLogger.new(
  batch_size: 10,
  flush_interval: 1,
  eager_flush_levels: [:debug, :info, :warn, :error, :fatal]
)
```

**Environment Variables:**

DirectLogger supports optional token configuration via environment:

```bash
export SOLIDLOG_TOKEN_ID=123  # Optional: for audit trail tracking
```

See [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) for detailed performance analysis.

### HTTP Client (For External Services)

For sending logs to a remote SolidLog service:

```ruby
SolidLog::Core.configure_client do |config|
  config.service_url = ENV['SOLIDLOG_SERVICE_URL']
  config.token = ENV['SOLIDLOG_TOKEN']
  config.app_name = 'web'
  config.environment = Rails.env
end
```

## Database Setup

**Option 1: Run migrations**

```bash
rails db:migrate
```

**Option 2: Use provided structure file**

Choose the structure file for your database type:

```bash
# For SQLite
rails db:schema:load SCHEMA=db/log_structure_sqlite.sql

# For PostgreSQL
rails db:schema:load SCHEMA=db/log_structure_postgresql.sql

# For MySQL
rails db:schema:load SCHEMA=db/log_structure_mysql.sql
```

The structure files are optimized for each database with appropriate FTS implementations:
- **SQLite**: FTS5 virtual table
- **PostgreSQL**: tsvector with GIN index
- **MySQL**: FULLTEXT index

### Enable WAL Mode for SQLite (Highly Recommended)

WAL (Write-Ahead Logging) mode provides **243% better performance** for crash-safe logging:

```ruby
# config/initializers/solid_log.rb
ActiveRecord::Base.connected_to(role: :log) do
  ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
  ActiveRecord::Base.connection.execute("PRAGMA synchronous=NORMAL")
end
```

**Benefits:**
- **3.4x faster** eager flush (16,882 vs 4,923 logs/sec)
- Better concurrency (readers don't block writers)
- Recommended for all production deployments

See [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) for performance comparison.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
