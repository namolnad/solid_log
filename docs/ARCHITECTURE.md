# SolidLog Architecture

This document provides a detailed overview of SolidLog's architecture, design decisions, and implementation details.

## Table of Contents

- [Overview](#overview)
- [Design Philosophy](#design-philosophy)
- [Data Flow](#data-flow)
- [Database Schema](#database-schema)
- [Two-Table Architecture](#two-table-architecture)
- [Parser Worker Pattern](#parser-worker-pattern)
- [Field Registry](#field-registry)
- [Field Promotion](#field-promotion)
- [Full-Text Search](#full-text-search)
- [Facet Caching](#facet-caching)
- [Correlation System](#correlation-system)
- [Anti-Recursion Strategy](#anti-recursion-strategy)
- [Performance Considerations](#performance-considerations)

## Overview

SolidLog is a modular log management system built as three separate gems that work together. It provides log ingestion, storage, parsing, and viewing capabilities using SQLite (or PostgreSQL/MySQL) as the backing database. It's designed to replace expensive third-party log management services for small to medium Rails applications.

**Architecture:**

SolidLog is split into three gems, each with a specific responsibility:

1. **solid_log-core**: Database models, adapters, parser, and core services
2. **solid_log-service**: Background job processing, ingestion API, and workers
3. **solid_log-ui**: Web interface (Rails engine) with Mission Control-style UI

This modular design allows you to:
- Deploy the service layer separately from the UI
- Use only the core gem for custom implementations
- Scale components independently
- Test each layer in isolation

**Key Components:**

```
┌──────────────────────────────────────────────────────────┐
│                     solid_log-service                    │
│                   (Background Workers)                   │
├──────────────────────────────────────────────────────────┤
│  ┌────────────┐  ┌────────────┐                         │
│  │ HTTP API   │  │  Parser    │                         │
│  │ Ingestion  │  │  Workers   │                         │
│  └──────┬─────┘  └──────┬─────┘                         │
└─────────┼────────────────┼──────────────────────────────┘
          │                │
          ▼                ▼
┌──────────────────────────────────────────────────────────┐
│                     solid_log-core                       │
│              (Models, Services, Adapters)                │
├──────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────┐       │
│  │         Database (:log)                      │       │
│  │  - solid_log_raw (append-only)               │       │
│  │  - solid_log_entries (parsed, indexed)       │       │
│  │  - solid_log_entries_fts (full-text search)  │       │
│  │  - solid_log_fields (field registry)         │       │
│  │  - solid_log_tokens (API auth)               │       │
│  │  - solid_log_facet_cache (performance)       │       │
│  └──────────────────────────────────────────────┘       │
└──────────────────────────────────────────────────────────┘
          │
          ▼
┌──────────────────────────────────────────────────────────┐
│                     solid_log-ui                         │
│                  (Rails Engine - Web UI)                 │
├──────────────────────────────────────────────────────────┤
│  ┌────────────┐  ┌────────────┐  ┌────────────┐        │
│  │ Dashboard  │  │  Streams   │  │ Timeline   │        │
│  │            │  │  (Filters) │  │ (Corr.)    │        │
│  └────────────┘  └────────────┘  └────────────┘        │
│                                                          │
│  Mission Control-style interface for viewing logs       │
└──────────────────────────────────────────────────────────┘
```

## Design Philosophy

### 1. Simplicity Over Features

SolidLog prioritizes simplicity and ease of use:
- Zero external dependencies (no Redis, Elasticsearch, etc.)
- Single SQLite database file for all log data
- No complex configuration required
- Self-contained Rails engine

### 2. Performance Through Design

Rather than relying on expensive infrastructure, SolidLog achieves performance through smart design:
- Two-table architecture decouples ingestion from parsing
- Claim pattern enables concurrent processing
- Facet caching reduces repeated queries
- FTS5 provides fast full-text search without Elasticsearch
- Field promotion optimizes hot query paths

### 3. Progressive Enhancement

SolidLog works immediately but improves over time:
- Logs are queryable as soon as they're parsed
- Field registry learns from usage patterns
- Auto-promotion optimizes frequently accessed fields
- Facet caching warms up based on actual usage

### 4. Audit Trail Preservation

The two-table model ensures data integrity:
- Raw entries are never modified or deleted (except by retention policy)
- Parsing errors don't lose data
- Re-parsing is always possible
- Complete audit trail from ingestion to display

## Data Flow

### Ingestion Flow

```
1. HTTP POST → /api/v1/ingest
   ↓
2. Bearer token authentication
   ↓
3. Bulk insert into solid_log_raw
   ↓ (asynchronous)
4. ParserJob claims unparsed rows
   ↓
5. Parse JSON, extract fields
   ↓
6. Insert into solid_log_entries
   ↓
7. Update field registry
   ↓
8. FTS5 triggers sync search index
```

### Query Flow

```
1. User visits /streams with filters
   ↓
2. SearchService builds query
   ↓
3. Check facet cache for filter options
   ↓ (cache miss)
4. Query solid_log_entries
   ↓
5. Apply filters (level, app, env, time, FTS)
   ↓
6. Cache facet results (5 min TTL)
   ↓
7. Return paginated results
```

## Database Schema

### solid_log_raw

**Purpose:** Append-only ingestion buffer

```sql
CREATE TABLE solid_log_raw (
  id INTEGER PRIMARY KEY,
  received_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  token_id INTEGER NOT NULL,
  payload TEXT NOT NULL,  -- JSON string
  parsed BOOLEAN DEFAULT 0,
  parsed_at DATETIME,
  FOREIGN KEY (token_id) REFERENCES solid_log_tokens(id)
);

CREATE INDEX idx_raw_unparsed ON solid_log_raw(parsed, received_at);
```

**Characteristics:**
- Write-optimized (minimal indexes)
- No parsing logic on write path
- Preserves original payload for audit/re-parsing
- Uses `parsed` flag for claim pattern

### solid_log_entries

**Purpose:** Parsed, queryable log entries

```sql
CREATE TABLE solid_log_entries (
  id INTEGER PRIMARY KEY,
  raw_id INTEGER NOT NULL,
  created_at DATETIME NOT NULL,
  level TEXT NOT NULL,
  app TEXT,
  env TEXT,
  message TEXT,
  request_id TEXT,
  job_id TEXT,
  duration REAL,
  status_code INTEGER,
  controller TEXT,
  action TEXT,
  path TEXT,
  method TEXT,
  extra_fields TEXT,  -- JSON for non-promoted fields
  FOREIGN KEY (raw_id) REFERENCES solid_log_raw(id)
);

CREATE INDEX idx_entries_timestamp ON solid_log_entries(created_at DESC);
CREATE INDEX idx_entries_level ON solid_log_entries(level);
CREATE INDEX idx_entries_app ON solid_log_entries(app, env, created_at DESC);
CREATE INDEX idx_entries_request ON solid_log_entries(request_id);
CREATE INDEX idx_entries_job ON solid_log_entries(job_id);
```

**Characteristics:**
- Read-optimized (multiple indexes)
- Promoted fields as dedicated columns
- Remaining fields in `extra_fields` JSON
- Linked to raw entry via `raw_id`

### solid_log_entries_fts

**Purpose:** Full-text search index

```sql
CREATE VIRTUAL TABLE solid_log_entries_fts USING fts5(
  message,
  extra_text,
  content='solid_log_entries',
  content_rowid='id'
);
```

**Characteristics:**
- FTS5 virtual table (SQLite extension)
- Auto-synced via triggers
- Searches both message and extra metadata
- Porter stemming for better matching

### solid_log_fields

**Purpose:** Field registry and promotion tracking

```sql
CREATE TABLE solid_log_fields (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  field_type TEXT NOT NULL,  -- string, number, boolean, datetime
  usage_count INTEGER DEFAULT 0,
  last_seen_at DATETIME,
  promoted BOOLEAN DEFAULT 0
);
```

**Characteristics:**
- Tracks all unique fields seen in logs
- Counts usage for promotion analysis
- Type inference from values
- Promotion flag marks dedicated columns

### solid_log_tokens

**Purpose:** API authentication

```sql
CREATE TABLE solid_log_tokens (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  last_used_at DATETIME,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
```

**Characteristics:**
- BCrypt hashing for token security
- Last used timestamp for auditing
- Friendly names for management

### solid_log_facet_cache

**Purpose:** Performance optimization for filter options

```sql
CREATE TABLE solid_log_facet_cache (
  id INTEGER PRIMARY KEY,
  cache_key TEXT NOT NULL UNIQUE,
  cache_value TEXT NOT NULL,  -- JSON array
  expires_at DATETIME
);

CREATE INDEX idx_facet_expires ON solid_log_facet_cache(expires_at);
```

**Characteristics:**
- 5-minute TTL by default
- Caches DISTINCT queries for filters
- Invalidated on cache cleanup job
- Significantly reduces DB load for repeated queries

## Two-Table Architecture

### Why Two Tables?

**Problem:** Log ingestion has conflicting requirements:
- **Writes** must be extremely fast (high throughput)
- **Reads** need complex filtering, sorting, searching

**Solution:** Separate concerns into two tables:

1. **solid_log_raw**: Optimized for fast writes
   - Minimal validation
   - Single index (parsed flag)
   - Append-only (no updates except parsed flag)

2. **solid_log_entries**: Optimized for fast reads
   - Multiple indexes
   - Parsed/structured data
   - Rich query capabilities

### Benefits

1. **Performance Isolation**
   - Ingestion latency decoupled from parsing overhead
   - Parsing doesn't block writes
   - Can handle traffic spikes by buffering in raw table

2. **Data Integrity**
   - Original payload always preserved
   - Parsing errors don't lose data
   - Can re-parse with updated logic

3. **Operational Flexibility**
   - Can throttle parser workers independently
   - Can re-parse historical data
   - Can analyze raw payloads for debugging

4. **Scalability**
   - Parser workers can scale horizontally
   - Ingestion and parsing have different bottlenecks
   - Can prioritize recent logs in parser queue

### Tradeoffs

- **Storage overhead**: Data stored in both tables (mitigated by retention policy)
- **Parse delay**: Logs not immediately searchable (typically <5 minutes)
- **Complexity**: Two tables to manage vs. one

## Parser Worker Pattern

### Claim-Based Processing

The parser uses a **claim pattern** for concurrent processing:

```ruby
# RawEntry.claim_batch(100)
RawEntry.transaction do
  unparsed = RawEntry.where(parsed: false)
    .order(received_at: :asc)
    .limit(batch_size)
    .lock("FOR UPDATE SKIP LOCKED")  # PostgreSQL-style locking
    .to_a

  # Mark as claimed immediately
  unparsed.each { |entry| entry.update_column(:parsed, true) }

  return unparsed
end
```

**How it works:**

1. Multiple workers can run concurrently
2. `SKIP LOCKED` ensures each worker claims different rows
3. Claimed rows marked `parsed: true` immediately
4. If parsing fails, entry stays marked but can be retried manually

### Parser Logic

```ruby
# lib/solid_log/parser.rb
def parse(payload)
  json = JSON.parse(payload)

  # Extract standard fields
  {
    created_at: parse_timestamp(json['timestamp']),
    level: normalize_level(json['level']),
    message: json['message'],
    app: json['app'],
    env: json['env'],
    request_id: json['request_id'],
    job_id: json['job_id'],
    # ... other promoted fields
    extra_fields: extract_extra_fields(json)
  }
rescue JSON::ParserError => e
  # Log error but don't raise (entry stays in raw table)
  Rails.logger.error("Failed to parse log: #{e.message}")
  nil
end
```

### Concurrency

Configured via `SolidLog.configuration.parser_concurrency`:

```ruby
# Run 5 parser workers in parallel
5.times do
  Thread.new do
    loop do
      batch = RawEntry.claim_batch(100)
      break if batch.empty?

      batch.each do |raw_entry|
        parsed = Parser.parse(raw_entry.payload)
        Entry.create!(parsed) if parsed
      end

      sleep 1
    end
  end
end
```

## Field Registry

### Purpose

The field registry (`solid_log_fields`) tracks all unique fields that appear in log entries:

```ruby
# Automatically tracked during parsing
Field.track('user_id', 42)
# → Creates/updates field: { name: 'user_id', field_type: 'number', usage_count: 1 }

Field.track('ip', '192.168.1.1')
# → { name: 'ip', field_type: 'string', usage_count: 1 }
```

### Type Inference

```ruby
def infer_type(value)
  case value
  when Numeric
    'number'
  when TrueClass, FalseClass
    'boolean'
  when /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/
    'datetime'
  else
    'string'
  end
end
```

### Usage Tracking

Every time a field is seen during parsing:

```ruby
Field.increment_usage!('user_id')
# → usage_count += 1, last_seen_at = NOW()
```

This data powers:
- Field promotion analysis
- UI filter generation
- Usage statistics

## Field Promotion

### What is Field Promotion?

Fields that start in `extra_fields` JSON can be "promoted" to dedicated columns for performance:

**Before promotion:**
```sql
-- Slow: Must parse JSON for every row
SELECT * FROM solid_log_entries
WHERE json_extract(extra_fields, '$.user_id') = 42;
```

**After promotion:**
```sql
-- Fast: Uses index on dedicated column
SELECT * FROM solid_log_entries WHERE user_id = 42;
```

### Promotion Process

1. **Identify candidates:**
   ```ruby
   # FieldAnalyzer.analyze
   Field.where('usage_count >= ?', 1000)
     .where(promoted: false)
     .where(field_type: ['string', 'number'])  # Not all types promotable
   ```

2. **Generate migration:**
   ```bash
   rails g solid_log:promote_field user_id --type=number
   ```

   Creates migration:
   ```ruby
   add_column :solid_log_entries, :user_id, :integer
   add_index :solid_log_entries, :user_id

   # Backfill from JSON
   Entry.find_each do |entry|
     user_id = JSON.parse(entry.extra_fields)['user_id']
     entry.update_column(:user_id, user_id)
   end

   # Mark as promoted
   Field.find_by(name: 'user_id').update!(promoted: true)
   ```

3. **Future parsing:**
   ```ruby
   # Parser now extracts to both locations (backward compat)
   {
     user_id: json['user_id'],
     extra_fields: json.except('user_id', ...promoted_fields)
   }
   ```

### Auto-Promotion

When enabled:

```ruby
# config/initializers/solid_log.rb
config.auto_promote_fields = true
config.field_promotion_threshold = 1000

# Scheduled job analyzes and promotes automatically
FieldAnalysisJob.perform_now(auto_promote: true)
```

**Priority Scoring** (0-10):
```ruby
priority = 0
priority += 5 if usage_count > 10000
priority += 3 if usage_count > 1000
priority += 2 if field_type == 'number'  # Better for filtering
priority += 1 if last_seen_at > 24.hours.ago  # Recent activity
```

Fields with priority >= 8 are auto-promoted.

## Full-Text Search

### FTS5 Implementation

SQLite's FTS5 provides full-text search without external dependencies:

```sql
CREATE VIRTUAL TABLE solid_log_entries_fts USING fts5(
  message,
  extra_text,
  content='solid_log_entries',
  content_rowid='id'
);
```

### Trigger Sync

FTS5 index stays in sync via triggers:

```sql
CREATE TRIGGER solid_log_entries_fts_insert
AFTER INSERT ON solid_log_entries
BEGIN
  INSERT INTO solid_log_entries_fts(rowid, message, extra_text)
  VALUES (new.id, new.message, new.extra_fields);
END;
```

### Search Query

```ruby
# Entry.search_fts("error authentication")
Entry.joins(
  "JOIN solid_log_entries_fts ON solid_log_entries.id = solid_log_entries_fts.rowid"
).where(
  "solid_log_entries_fts MATCH ?", query
).order(created_at: :desc)
```

**Features:**
- Phrase matching: `"exact phrase"`
- Boolean operators: `error AND authentication`
- Prefix matching: `auth*`
- Column-specific: `message:error`
- Porter stemming: `running` matches `run`, `runs`

## Facet Caching

### Problem

Filter dropdowns need DISTINCT queries that scan entire table:

```sql
-- Expensive on large tables
SELECT DISTINCT app FROM solid_log_entries;
SELECT DISTINCT env FROM solid_log_entries;
SELECT DISTINCT level FROM solid_log_entries;
```

### Solution

Cache these values for 5 minutes:

```ruby
# SearchService.available_facets
def available_facets
  {
    apps: FacetCache.fetch('facets:apps', ttl: 5.minutes) {
      Entry.distinct.pluck(:app).compact.sort
    },
    envs: FacetCache.fetch('facets:envs', ttl: 5.minutes) {
      Entry.distinct.pluck(:env).compact.sort
    },
    levels: FacetCache.fetch('facets:levels', ttl: 5.minutes) {
      Entry.distinct.pluck(:level).sort
    }
  }
end
```

### Cache Implementation

```ruby
# FacetCache.fetch(key, ttl:) { ... }
def self.fetch(key, ttl:)
  cached = find_by(cache_key: key)

  if cached && cached.expires_at > Time.current
    return JSON.parse(cached.cache_value)
  end

  value = yield

  upsert(
    { cache_key: key },
    { cache_value: value.to_json, expires_at: Time.current + ttl }
  )

  value
end
```

### Cache Invalidation

```ruby
# Scheduled cleanup job
CacheCleanupJob.perform_now
# → DELETE FROM solid_log_facet_cache WHERE expires_at < NOW()
```

**Impact:** Reduces filter load time from ~500ms to ~5ms on large datasets.

## Correlation System

### Request Correlation

Logs with the same `request_id` represent a single HTTP request flow:

```ruby
# TimelineController#request
@entries = Entry.by_request_id(params[:request_id])
  .order(created_at: :asc)

# Group by controller/action for timeline view
@timeline = CorrelationService.build_timeline(@entries)
```

### Job Correlation

Logs with the same `job_id` represent a background job execution:

```ruby
# TimelineController#job
@entries = Entry.by_job_id(params[:job_id])
  .order(created_at: :asc)
```

### Timeline Visualization

```ruby
# CorrelationService.build_timeline(entries)
groups = entries.group_by do |entry|
  "#{entry.controller}##{entry.action}"
end

groups.map do |group_name, group_entries|
  {
    name: group_name,
    entries: group_entries,
    duration: group_entries.last.created_at - group_entries.first.created_at
  }
end
```

UI displays:
- Chronological log list
- Visual timeline with color-coded dots
- Duration deltas between events
- Links to related logs

## Anti-Recursion Strategy

### The Problem

Logging system logs can create infinite loops:

```
1. Log entry created
2. Rails logs the INSERT query
3. SolidLog ingests that log
4. INSERT creates new log entry
5. → Infinite recursion
```

### Solution: Multi-Layer Protection

**Layer 1: SilenceMiddleware**

```ruby
# lib/solid_log/silence_middleware.rb
def call(env)
  if env['PATH_INFO'].start_with?('/admin/logs')
    SolidLog.without_logging do
      @app.call(env)
    end
  else
    @app.call(env)
  end
end
```

**Layer 2: Thread-Local Flag**

```ruby
# lib/solid_log.rb
def self.without_logging
  Thread.current[:solid_log_silenced] = true
  ActiveRecord::Base.logger.silence do
    yield
  end
ensure
  Thread.current[:solid_log_silenced] = nil
end
```

**Layer 3: Model-Level Guards**

```ruby
# app/models/solid_log/raw_entry.rb
def self.create_from_ingest(payload)
  SolidLog.without_logging do
    create!(payload: payload)
  end
end
```

This ensures SolidLog's own operations never trigger logging.

## Performance Considerations

### SQLite Optimizations

**WAL Mode** (Write-Ahead Logging):
```sql
PRAGMA journal_mode=WAL;
-- Allows concurrent reads during writes
```

**Synchronous Mode:**
```sql
PRAGMA synchronous=NORMAL;
-- Faster writes, still safe with WAL
```

**Busy Timeout:**
```sql
PRAGMA busy_timeout=5000;
-- Wait up to 5s for locks instead of failing immediately
```

### Index Strategy

**Compound Indexes:**
```sql
CREATE INDEX idx_entries_app ON solid_log_entries(app, env, created_at DESC);
-- Optimizes common filter combination
```

**Partial Indexes** (future optimization):
```sql
CREATE INDEX idx_entries_errors ON solid_log_entries(created_at DESC)
WHERE level IN ('error', 'fatal');
-- Faster error-only queries
```

### Batch Operations

**Bulk Inserts:**
```ruby
# Avoid N+1 inserts
RawEntry.insert_all(entries)  # Single INSERT with multiple rows
```

**Batch Deletions:**
```ruby
# RetentionService deletes in batches to avoid long locks
loop do
  deleted = Entry.where('created_at < ?', cutoff).limit(1000).delete_all
  break if deleted == 0
  sleep 0.1  # Release lock between batches
end
```

### Query Optimization

**Use `.pluck` for single column:**
```ruby
# Bad: Loads full ActiveRecord objects
Entry.all.map(&:id)

# Good: Returns array of IDs directly
Entry.pluck(:id)
```

**Use `.exists?` for boolean checks:**
```ruby
# Bad: Loads records
Entry.where(level: 'error').any?

# Good: Returns true/false via SQL
Entry.where(level: 'error').exists?
```

### Scaling Limits

**SQLite can handle:**
- 100M+ rows
- 140TB database size (theoretical max)
- 10,000+ concurrent readers
- Single writer (via write queue)

**When to consider alternatives:**
- Sustained >10K inserts/second
- Multi-writer requirements
- Cross-server querying
- Petabyte-scale storage

For most Rails apps, SQLite with SolidLog scales to:
- Millions of requests/day
- Years of log retention
- Gigabytes of log storage

## Summary

SolidLog's architecture prioritizes:

1. **Simplicity**: Single SQLite database, no external services
2. **Performance**: Two-table design, smart caching, FTS5 search
3. **Reliability**: Audit trail, error handling, anti-recursion
4. **Flexibility**: Field promotion, configurable retention, extensible parsing
5. **Developer Experience**: Mission Control UI, comprehensive rake tasks, clear data model

The result is a production-ready log management system that scales with your Rails application without the complexity or cost of enterprise solutions.
