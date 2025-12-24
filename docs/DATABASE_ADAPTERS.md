# Database Adapters Guide

SolidLog supports SQLite, PostgreSQL, and MySQL through a database adapter system. Each adapter provides database-specific optimizations while maintaining a consistent API.

## Supported Databases

### SQLite (Default)
- **Best for**: Small to medium apps (< 1M logs/day)
- **Pros**: Zero configuration, embedded, fast for reads
- **Cons**: Single writer, limited concurrent writes
- **Full-text search**: FTS5 virtual tables
- **JSON**: `json_extract()` functions

### PostgreSQL
- **Best for**: Medium to large apps (1M+ logs/day)
- **Pros**: Excellent concurrency, JSONB support, robust FTS
- **Cons**: External service required, more complex setup
- **Full-text search**: tsvector/tsquery with GIN indexes
- **JSON**: Native JSONB type with operators

### MySQL
- **Best for**: Existing MySQL infrastructure
- **Pros**: Wide adoption, good performance, FULLTEXT search
- **Cons**: JSON support less mature than PostgreSQL
- **Full-text search**: FULLTEXT indexes
- **JSON**: Native JSON type (MySQL 5.7+)

## Configuration

### SQLite

```yaml
# config/database.yml
production:
  primary:
    adapter: sqlite3
    database: storage/production.sqlite3

  log:
    adapter: sqlite3
    database: storage/production_log.sqlite3
    migrations_paths: db/log_migrate
```

**Optimizations applied automatically:**
- WAL mode for concurrent reads
- `synchronous=NORMAL` for faster writes
- 64MB cache size
- Memory-mapped I/O

### PostgreSQL

```yaml
# config/database.yml
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

**Optimizations applied automatically:**
- `FOR UPDATE SKIP LOCKED` for concurrent parser workers
- GIN indexes for JSONB fields
- tsvector indexes for full-text search
- Automatic `ANALYZE` on optimize

**Additional setup:**

```sql
-- Enable extensions (run once)
CREATE EXTENSION IF NOT EXISTS pg_trgm;  -- For fuzzy search
```

### MySQL

```yaml
# config/database.yml
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

**Requirements:**
- MySQL 8.0+ (for `SKIP LOCKED` support)
- MySQL 5.7+ (for JSON support)

**Optimizations applied automatically:**
- `FOR UPDATE SKIP LOCKED` (MySQL 8.0+)
- FULLTEXT indexes for search
- Automatic `OPTIMIZE TABLE` on optimize
- InnoDB for transactions

## Feature Comparison

| Feature | SQLite | PostgreSQL | MySQL |
|---------|--------|------------|-------|
| Full-text search | FTS5 | tsvector | FULLTEXT |
| JSON querying | json_extract | JSONB operators | JSON_EXTRACT |
| Concurrent parsing | Emulated | Native SKIP LOCKED | SKIP LOCKED (8.0+) |
| Max throughput | 10K logs/s | 100K+ logs/s | 50K+ logs/s |
| Storage limit | ~100M entries | Unlimited | Unlimited |
| Backup | File copy | pg_dump | mysqldump |
| Replication | Litestream | Streaming | Binary logs |

## Migrations

SolidLog automatically detects your database adapter and uses the appropriate migration strategy.

### Running Migrations

```bash
# Migrations work the same regardless of database
rails solid_log:install:migrations
rails db:migrate
```

### Database-Specific Differences

**SQLite:**
- Creates FTS5 virtual table with triggers
- Uses TEXT for JSON fields
- Simpler indexes

**PostgreSQL:**
- Creates JSONB columns instead of TEXT
- Adds GIN indexes for JSONB
- Creates tsvector index for FTS
- Uses native UUID type

**MySQL:**
- Creates JSON columns (native type)
- Adds FULLTEXT indexes
- Uses generated columns for promoted fields
- InnoDB storage engine

## Adapter API

The adapter system provides a consistent interface:

```ruby
# Get current adapter
adapter = SolidLog.adapter

# Full-text search (database-specific)
Entry.search_fts("error authentication")

# JSON field extraction (database-specific)
Entry.filter_by_field("user_id", 42)

# Claim unparsed entries (database-specific locking)
RawEntry.claim_batch(batch_size: 100)

# Optimize database (database-specific)
SolidLog.adapter.optimize!
```

## Switching Databases

### From SQLite to PostgreSQL

1. **Export data:**

```bash
# Dump SQLite database
sqlite3 storage/production_log.sqlite3 .dump > solidlog_dump.sql
```

2. **Convert schema:**

```bash
# Use pgloader or manual conversion
pgloader storage/production_log.sqlite3 postgresql://localhost/myapp_log_production
```

3. **Update database.yml:**

```yaml
log:
  adapter: postgresql
  database: myapp_log_production
```

4. **Run migrations:**

```bash
rails db:migrate:status RAILS_ENV=production
rails db:migrate RAILS_ENV=production
```

5. **Create PostgreSQL-specific indexes:**

```sql
-- Full-text search index
CREATE INDEX idx_entries_fts ON solid_log_entries
USING GIN (to_tsvector('english', COALESCE(message, '') || ' ' || COALESCE(extra_fields::text, '')));

-- JSONB index
CREATE INDEX idx_entries_extra_fields ON solid_log_entries
USING GIN (extra_fields jsonb_path_ops);
```

### From SQLite to MySQL

Similar process, using `mysqldump` or ETL tools.

## Performance Tuning

### SQLite

```ruby
# config/initializers/solid_log.rb
ActiveRecord::Base.connected_to(database: { writing: :log }) do
  connection = ActiveRecord::Base.connection

  connection.execute("PRAGMA journal_mode=WAL")
  connection.execute("PRAGMA synchronous=NORMAL")
  connection.execute("PRAGMA cache_size=-128000")  # 128MB cache
  connection.execute("PRAGMA temp_store=MEMORY")
  connection.execute("PRAGMA mmap_size=536870912")  # 512MB mmap
end
```

### PostgreSQL

```ruby
# config/initializers/solid_log.rb
ActiveRecord::Base.connected_to(database: { writing: :log }) do
  connection = ActiveRecord::Base.connection

  connection.execute("SET work_mem = '64MB'")
  connection.execute("SET maintenance_work_mem = '256MB'")
  connection.execute("SET shared_buffers = '256MB'")  # Server config
  connection.execute("SET effective_cache_size = '1GB'")  # Server config
end
```

### MySQL

```ruby
# config/initializers/solid_log.rb
ActiveRecord::Base.connected_to(database: { writing: :log }) do
  connection = ActiveRecord::Base.connection

  connection.execute("SET SESSION innodb_lock_wait_timeout = 50")
  connection.execute("SET SESSION sort_buffer_size = 67108864")  # 64MB
end
```

## Troubleshooting

### SQLite: "database is locked"

**Cause:** WAL mode not enabled or busy timeout too low

**Solution:**
```sql
PRAGMA journal_mode=WAL;
PRAGMA busy_timeout=10000;
```

### PostgreSQL: "could not serialize access"

**Cause:** Concurrent parser workers hitting serialization errors

**Solution:**
```ruby
# Reduce parser concurrency
config.parser_concurrency = 3
```

### MySQL: "Syntax error near 'SKIP LOCKED'"

**Cause:** MySQL version < 8.0

**Solution:**
- Upgrade to MySQL 8.0+, or
- Adapter automatically falls back to legacy locking

### Full-text search not working

**SQLite:**
```sql
-- Verify FTS5 extension
SELECT * FROM sqlite_master WHERE name = 'solid_log_entries_fts';
```

**PostgreSQL:**
```sql
-- Verify GIN index
SELECT indexname FROM pg_indexes WHERE tablename = 'solid_log_entries' AND indexname LIKE '%fts%';
```

**MySQL:**
```sql
-- Verify FULLTEXT index
SHOW INDEX FROM solid_log_entries WHERE Index_type = 'FULLTEXT';
```

## Best Practices

1. **Choose database based on scale:**
   - < 100K logs/day: SQLite
   - 100K - 1M logs/day: PostgreSQL or MySQL
   - > 1M logs/day: PostgreSQL with read replicas

2. **Use connection pooling:**
   - Set appropriate pool size in database.yml
   - SQLite: pool=5 is sufficient
   - PostgreSQL/MySQL: pool=20-50 for high concurrency

3. **Monitor database size:**
   ```bash
   rails solid_log:health
   ```

4. **Run periodic optimization:**
   ```bash
   # Daily via cron
   0 3 * * * cd /app && rails solid_log:optimize
   ```

5. **Backup regularly:**
   - SQLite: Litestream for continuous backup
   - PostgreSQL: pg_dump or WAL archiving
   - MySQL: mysqldump or binary log replication

## Custom Adapters

To add support for another database:

1. **Create adapter class:**

```ruby
# lib/solid_log/adapters/cockroachdb_adapter.rb
module SolidLog
  module Adapters
    class CockroachdbAdapter < PostgresqlAdapter
      # Inherit from PostgreSQL adapter and override as needed
      def claim_batch(batch_size)
        # Custom locking strategy
      end
    end
  end
end
```

2. **Register in factory:**

```ruby
# lib/solid_log/adapters/adapter_factory.rb
when "cockroachdb"
  CockroachdbAdapter.new(connection)
```

3. **Test thoroughly:**
   - Run full test suite
   - Verify FTS works
   - Test concurrent parsing
   - Benchmark performance

## Support

For database-specific issues:
- SQLite: See [SQLite docs](https://www.sqlite.org/docs.html)
- PostgreSQL: See [PostgreSQL docs](https://www.postgresql.org/docs/)
- MySQL: See [MySQL docs](https://dev.mysql.com/doc/)

For SolidLog adapter issues:
- GitHub Issues: https://github.com/namolnad/solid_log/issues
- ARCHITECTURE.md for design details
- DEPLOYMENT.md for production setup
