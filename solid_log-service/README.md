# SolidLog::Service

Standalone log ingestion and processing service with HTTP API and built-in job scheduler.

## Overview

`solid_log-service` provides:

- **HTTP Ingestion API**: Accept logs via POST with bearer token auth
- **Query APIs**: REST endpoints for searching, filtering, and retrieving logs
- **Background Processing**: Parse raw logs, retention cleanup, field analysis
- **Built-in Scheduler**: No external dependencies (or use ActiveJob/cron)
- **Health Monitoring**: Metrics endpoint for observability

## Installation

```ruby
gem 'solid_log-service'

# Database adapter (choose one)
gem 'sqlite3', '>= 2.1'   # For SQLite (recommended for most deployments)
# OR
gem 'pg', '>= 1.1'        # For PostgreSQL
# OR
gem 'mysql2', '>= 0.5'    # For MySQL
```

## Standalone Deployment

**1. Create configuration file:**

```ruby
# config/solid_log_service.rb
SolidLog::Service.configure do |config|
  config.database_url = ENV['DATABASE_URL'] || 'sqlite3:///data/production_log.sqlite'

  # Job processing mode (default: :scheduler)
  config.job_mode = :scheduler  # or :active_job, :manual

  # Scheduler intervals (only used when job_mode = :scheduler)
  config.parser_interval = 10.seconds
  config.cache_cleanup_interval = 1.hour
  config.retention_hour = 2  # Run at 2 AM
  config.field_analysis_hour = 3  # Run at 3 AM

  # Retention policies
  config.retention_days = 30
  config.error_retention_days = 90
end
```

**2. Run the service:**

```bash
bundle exec solid_log_service
```

Or with a Procfile:
```
service: bundle exec solid_log_service
```

## Kamal Deployment

See main SolidLog documentation for Kamal deployment examples.

## API Endpoints

### Ingestion
- `POST /api/v1/ingest` - Ingest logs (single or batch)

### Queries
- `GET /api/v1/entries` - List/filter entries
- `GET /api/v1/entries/:id` - Get single entry
- `GET /api/v1/search` - Full-text search
- `GET /api/v1/facets` - Get filter options
- `GET /api/v1/timelines/request/:id` - Request timeline
- `GET /api/v1/timelines/job/:id` - Job timeline
- `GET /api/v1/health` - Health metrics

## Job Processing Modes

### Built-in Scheduler (Default)
No external dependencies. Runs jobs in background threads.

```ruby
config.job_mode = :scheduler
config.parser_interval = 10.seconds
```

### ActiveJob Integration
Leverages host app's job backend (Solid Queue, Sidekiq, etc.)

```ruby
config.job_mode = :active_job
```

### Manual (Cron)
You manage scheduling via cron.

```ruby
config.job_mode = :manual
```

Then in crontab:
```
*/1 * * * * cd /app && rails solid_log:parse_logs
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
