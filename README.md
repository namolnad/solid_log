# SolidLog

**Self-hosted log management for Rails applications using SQLite, PostgreSQL, or MySQL**

SolidLog is a modular, Rails-native log ingestion and viewing system that eliminates the need for paid log viewers like Datadog, Splunk, or ELK for the majority of Rails applications. Store logs in your choice of database, search with full-text search, and view in a Mission Control-style UI.

## Why SolidLog?

Most Rails applications don't need expensive, complex logging infrastructure. SolidLog provides:

- **Zero external dependencies**: Everything runs in your Rails app
- **Modular architecture**: Use only the components you need
- **Database flexibility**: SQLite, PostgreSQL, or MySQL with adapter-specific optimizations
- **HTTP ingestion**: Send structured logs from any service via simple HTTP POST
- **Full-text search**: Database-native FTS (SQLite FTS5, PostgreSQL tsvector, MySQL FULLTEXT)
- **Request/job correlation**: Trace requests and background jobs across your system
- **Mission Control UI**: Clean, familiar interface for browsing and filtering logs
- **Field promotion**: Auto-detect frequently used fields and optimize queries
- **Cost**: Free, self-hosted, no per-GB pricing

## Monorepo Structure

This repository contains three gems that work together:

```
solid_log/
├── solid_log-core/       # Database models, adapters, parser, services
├── solid_log-service/    # Background jobs, ingestion API, workers
├── solid_log-ui/         # Rails engine with web interface
├── demo/                 # Demo Rails app showing all 3 gems working together
├── docs/                 # Comprehensive documentation
├── Rakefile              # Run tests for all gems
└── README.md             # This file
```

### The Three Gems

#### 1. solid_log-core

**Foundation layer** - Database models, adapters, and core services

- Database schema and migrations
- ActiveRecord models (Entry, RawEntry, Token, Field, FacetCache)
- Database adapters (SQLite, PostgreSQL, MySQL)
- **DirectLogger**: High-performance, batched logging for parent app (50,000+ logs/sec)
- Parser for structured JSON logs
- Core services (SearchService, RetentionService, FieldAnalyzer, etc.)
- Anti-recursion prevention

**Use this gem when:** Building custom logging integrations or using SolidLog without the UI

[See solid_log-core README](solid_log-core/README.md)

#### 2. solid_log-service

**Service layer** - Background processing and API

- HTTP ingestion API with bearer token authentication
- Background jobs (ParserJob, RetentionJob, CacheCleanupJob, FieldAnalysisJob)
- Built-in scheduler (no external job queue required)
- Batch processing with concurrency controls
- Health check endpoints

**Use this gem when:** Running a dedicated log ingestion service

[See solid_log-service README](solid_log-service/README.md)

#### 3. solid_log-ui

**Presentation layer** - Rails engine with web interface

- Mission Control-style dashboard
- Log streams with filtering (level, app, env, time range, search)
- Timeline views for request/job correlation
- Field management interface
- Token management
- Live tail support
- ActionCable integration for real-time updates

**Use this gem when:** Mounting the log viewer in your Rails app

[See solid_log-ui README](solid_log-ui/README.md)

## Quick Start

### Try the Demo App (5 minutes)

The fastest way to see SolidLog in action is to run the demo app:

```bash
cd demo
bundle install
mkdir -p storage
touch storage/development.sqlite3 storage/development_log.sqlite3
sqlite3 storage/development_log.sqlite3 < db/log_structure.sql
bin/rails server
```

Visit `http://localhost:3000` and click "Generate Sample Logs" to create test data.

**See [demo/README.md](demo/README.md) for detailed demo app documentation.**

### Integrate into Your Rails App

For step-by-step integration instructions, see **[QUICKSTART.md](QUICKSTART.md)**.

Quick overview:

1. Add gems to your Gemfile:
   ```ruby
   gem "solid_log-core", path: "vendor/gems/solid_log-core"
   gem "solid_log-service", path: "vendor/gems/solid_log-service"
   gem "solid_log-ui", path: "vendor/gems/solid_log-ui"
   ```

2. Configure multi-database in `config/database.yml`:
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

3. Run migrations:
   ```bash
   rails db:migrate
   ```

4. Mount the UI in `config/routes.rb`:
   ```ruby
   mount SolidLog::UI::Engine => "/admin/logs"
   ```

5. Create an API token:
   ```bash
   rails solid_log:create_token["Production API"]
   ```

6. Start sending logs via HTTP POST to the ingestion endpoint

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
- **Retention policies**: Configurable retention with longer periods for errors (30/90 days default)
- **Health dashboard**: Monitor ingestion rate, parse backlog, error rate, database size

### UI
- **Mission Control-style dashboard**: Familiar Rails UI with stats and health metrics
- **Streams view**: Filter, search, and browse logs with multiple facets
- **Timeline views**: Chronological visualization of correlated events
- **Field management**: View field registry, promote/demote fields
- **Token management**: Create and manage API tokens for ingestion

## Architecture

SolidLog uses a modular, three-gem architecture with a two-table storage pattern:

```
┌─────────────────────────────────────────────────────────┐
│                   Your Rails App                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  solid_log-ui (mounted at /admin/logs)           │  │
│  │  - Dashboard, Streams, Timeline, Field Mgmt      │  │
│  └────────────────────┬─────────────────────────────┘  │
│                       │                                 │
│  ┌────────────────────▼─────────────────────────────┐  │
│  │  solid_log-service (background workers)          │  │
│  │  - HTTP API, Parser Jobs, Retention, Cleanup     │  │
│  └────────────────────┬─────────────────────────────┘  │
│                       │                                 │
│  ┌────────────────────▼─────────────────────────────┐  │
│  │  solid_log-core (models & services)              │  │
│  │  - Entry, RawEntry, Token, Field models          │  │
│  │  - Database adapters, Parser, Services           │  │
│  └────────────────────┬─────────────────────────────┘  │
└────────────────────────┼──────────────────────────────┘
                         │
                         ▼
              ┌──────────────────────┐
              │   Log Database       │
              │  (:log connection)   │
              ├──────────────────────┤
              │ solid_log_raw        │  ← Fast writes (JSON blobs)
              │ solid_log_entries    │  ← Parsed, indexed, queryable
              │ solid_log_entries_fts│  ← Full-text search
              │ solid_log_fields     │  ← Field registry
              │ solid_log_tokens     │  ← API authentication
              │ solid_log_facet_cache│  ← Performance optimization
              └──────────────────────┘
```

**Data Flow:**
1. Logs arrive via HTTP POST → `solid_log_raw` (append-only, fast)
2. Parser worker claims unparsed rows → processes JSON
3. Parsed data inserted into `solid_log_entries` (indexed, queryable)
4. FTS triggers automatically sync full-text search index
5. UI queries `solid_log_entries` with filters, search, correlation

**Benefits:**
- Fast ingestion (raw inserts don't block on parsing)
- CPU-intensive parsing doesn't block writes
- Audit trail preserved (raw entries never modified)
- Optimized queries on parsed data
- Independent scaling of components

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed design documentation.

## Documentation

Comprehensive guides are available in the repository:

- **[QUICKSTART.md](QUICKSTART.md)** - Get started in 15 minutes
- **[demo/README.md](demo/README.md)** - Demo app setup and usage
- **[docs/API.md](docs/API.md)** - HTTP API reference
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** - System design and internals
- **[docs/DATABASE_ADAPTERS.md](docs/DATABASE_ADAPTERS.md)** - SQLite, PostgreSQL, MySQL adapters
- **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** - Production deployment guide
- **[docs/RECURSIVE_LOGGING_PREVENTION.md](docs/RECURSIVE_LOGGING_PREVENTION.md)** - How SolidLog prevents logging itself

**Individual gem documentation:**
- [solid_log-core/README.md](solid_log-core/README.md)
- [solid_log-service/README.md](solid_log-service/README.md)
- [solid_log-ui/README.md](solid_log-ui/README.md)

## Development

This is a monorepo containing three gems. Each gem has its own test suite.

### Running Tests

```bash
# Run all tests for all gems
rake test

# Run tests for individual gems
rake test:core
rake test:service
rake test:ui

# Or run tests directly in each gem
cd solid_log-core && bundle exec rake test
cd solid_log-service && bundle exec rake test
cd solid_log-ui && bundle exec rake test
```

### Test Suite Quality

The test suite achieves a **10/10 quality rating** with comprehensive coverage:

- **352 tests, 1,131 assertions**
- **100% passing** across all 3 gems
- **Substantive testing**: Tests verify actual behavior, not just types
- **Edge cases**: Boundary conditions, concurrency, error handling
- **Security**: Token cryptography, authentication, hash validation
- **Data integrity**: Database constraints, validation

See [TEST_QUALITY_REPORT.md](TEST_QUALITY_REPORT.md) for detailed test quality analysis.

### Repository Structure

```
solid_log/
├── solid_log-core/
│   ├── lib/                  # Core models, services, adapters
│   ├── test/                 # Test suite (113 tests)
│   ├── solid_log-core.gemspec
│   └── README.md
│
├── solid_log-service/
│   ├── app/
│   │   ├── controllers/      # API controllers
│   │   └── jobs/             # Background jobs
│   ├── lib/                  # Service initialization
│   ├── test/                 # Test suite (127 tests)
│   ├── solid_log-service.gemspec
│   └── README.md
│
├── solid_log-ui/
│   ├── app/
│   │   ├── controllers/      # UI controllers
│   │   ├── views/            # ERB templates
│   │   ├── assets/           # JavaScript, CSS
│   │   ├── helpers/          # View helpers
│   │   └── channels/         # ActionCable channels
│   ├── config/               # Routes, engine config
│   ├── test/                 # Test suite (112 tests)
│   ├── solid_log-ui.gemspec
│   └── README.md
│
├── demo/                     # Full Rails app demonstrating all 3 gems
│   ├── app/controllers/      # Demo controller (log generator)
│   ├── config/               # Rails config, routes
│   ├── db/                   # Log database structure
│   └── README.md
│
├── docs/                     # Comprehensive documentation
│   ├── ARCHITECTURE.md
│   ├── API.md
│   ├── DATABASE_ADAPTERS.md
│   ├── DEPLOYMENT.md
│   └── RECURSIVE_LOGGING_PREVENTION.md
│
├── Rakefile                  # Top-level test runner
├── README.md                 # This file
├── QUICKSTART.md             # Integration guide
├── TEST_QUALITY_REPORT.md    # Test quality analysis
├── MIT-LICENSE
└── .gitignore
```

### Contributing

Bug reports and pull requests are welcome on GitHub.

**Before submitting a PR:**
1. Run the full test suite: `rake test`
2. Ensure all tests pass
3. Add tests for new functionality
4. Update relevant documentation

See individual gem READMEs for gem-specific development notes.

## Deployment

SolidLog can be deployed in several configurations:

### Monolith (Recommended for Most Apps)

Deploy all three gems together in your Rails app:
- UI mounted at `/admin/logs`
- Service layer runs as background jobs (via Solid Queue, Sidekiq, etc.)
- Core provides models and services

**Best for:** Small to medium apps, simple deployments

### Separated Service

Deploy the service layer separately:
- Service app: `solid_log-core` + `solid_log-service` (ingestion + parsing)
- Main app: `solid_log-core` + `solid_log-ui` (viewing only)
- Service app exposes HTTP API for ingestion
- Both apps connect to the same log database

**Best for:** High-volume logging, scaling ingestion independently

### Custom Integration

Use only `solid_log-core` for custom implementations:
- Build your own ingestion pipeline
- Use the parser and models directly
- Create custom UI or reporting

**Best for:** Advanced use cases, non-standard workflows

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for production deployment guides including:
- Kamal configuration
- Database tuning (SQLite WAL mode, PostgreSQL, MySQL)
- Multi-process setup
- Scaling considerations
- Monitoring and alerting

## Performance

SolidLog is designed for high performance with real-world benchmarks:

### DirectLogger (Parent App Logging)
- **File-based SQLite with WAL**: 16,882 logs/sec with crash safety, 56,660 logs/sec without
- **Batching**: 9x faster than individual inserts
- **Crash safety**: Eager flush for error/fatal logs (prevents losing crash context)
- **PostgreSQL**: ~30,000+ logs/sec estimated (2x faster than SQLite)

### HTTP Ingestion (External Services)
- **SQLite**: 5,000-10,000 logs/second
- **PostgreSQL**: 20,000-50,000+ logs/second
- **Batching**: Send up to 100 logs per request for best performance

### Query Performance
- **Parsing**: 5,000+ logs/second per worker
- **Search**: Sub-second FTS queries on millions of entries
- **Facet caching**: Filter options cached for 5 minutes to reduce load
- **Concurrent reads**: WAL mode (SQLite) or native (PostgreSQL/MySQL)
- **Optimized indexes**: Level, app, env, timestamps, correlation IDs

**Scaling:**
- SQLite handles 100M+ log entries efficiently
- PostgreSQL recommended for >1M logs/day or high-traffic apps
- **Enable WAL mode for SQLite** - 243% faster for crash-safe logging
- Run multiple parser workers for high ingestion loads
- Use retention policies to manage database size
- Promote hot fields for faster queries

See [solid_log-core/BENCHMARK_RESULTS.md](solid_log-core/BENCHMARK_RESULTS.md) for detailed benchmarks and configuration recommendations.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Credits

Inspired by:
- [mission_control-jobs](https://github.com/rails/mission_control-jobs) - UI design
- [Lograge](https://github.com/roidrage/lograge) - Structured logging
- [Solid Queue](https://github.com/rails/solid_queue) - SQLite-backed Rails services
- [Litestream](https://litestream.io/) - SQLite replication (recommended for backups)
