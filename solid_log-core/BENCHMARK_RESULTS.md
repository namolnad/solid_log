# SolidLog DirectLogger Benchmark Results

Performance benchmarks for DirectLogger vs alternative logging methods using **file-based SQLite database** (realistic production scenario).

## Executive Summary

- **DirectLogger is 9x faster** than individual database inserts
- **DirectLogger is 67x faster** than HTTP logging (individual requests)
- **DirectLogger achieves 50,000+ logs/sec** on file-based database
- **Eager flush costs ~74% performance** but prevents losing crash logs
- **WAL mode is 2-3x faster** than standard SQLite mode

## Test 1: Ingestion Performance (1,000 logs, File-Based DB)

### With WAL Mode (Recommended)

| Method | Throughput | Speedup | Notes |
|--------|-----------|---------|-------|
| Individual inserts | 6,345 logs/sec | 1.0x (baseline) | Very slow, not recommended |
| Batch inserts (100/batch) | 62,625 logs/sec | 9.9x | Manual batching required |
| **DirectLogger (auto-batched)** | **56,660 logs/sec** | **8.9x** | Recommended |
| DirectLogger (10k logs) | 52,269 logs/sec | 8.2x | Sustained throughput |

### Without WAL Mode

| Method | Throughput | Speedup | Notes |
|--------|-----------|---------|-------|
| Individual inserts | 2,266 logs/sec | 1.0x (baseline) | Much slower |
| Batch inserts (100/batch) | 48,485 logs/sec | 21.4x | Still needs batching |
| **DirectLogger (auto-batched)** | **45,935 logs/sec** | **20.3x** | 23% faster with WAL |

**Key Insight:** DirectLogger automatically batches writes, giving you 9x better performance than individual inserts. WAL mode provides an additional 23% boost.

## Test 2: Crash Safety (Eager Flush)

### With WAL Mode

| Configuration | Throughput | Safety | Use Case |
|--------------|-----------|--------|----------|
| **With eager flush** | **16,882 logs/sec** | ✅ **Safe** | **Production (recommended)** |
| Without eager flush | 64,300 logs/sec | ❌ Risky | High-volume, non-critical logs |

**Performance Cost:** Eager flush is ~74% slower with WAL mode, BUT:
- You still get **16,882 logs/sec** which is plenty fast for most apps
- You **won't lose the logs explaining WHY your app crashed**
- Worth it for production use

### Without WAL Mode

| Configuration | Throughput | Safety | Use Case |
|--------------|-----------|--------|----------|
| **With eager flush** | **4,923 logs/sec** | ✅ **Safe** | Production without WAL |
| Without eager flush | 46,011 logs/sec | ❌ Risky | High-volume, non-critical logs |

**Key Finding:** WAL mode is **243% faster** for eager flush scenarios! This is the biggest performance gain from WAL mode.

### What is Eager Flush?

When your app logs an error or fatal message, DirectLogger immediately flushes ALL buffered logs (including the error) to the database. This ensures that if your app crashes immediately after the error, you don't lose the logs explaining what went wrong.

```ruby
# Default behavior (RECOMMENDED for production):
logger = SolidLog::DirectLogger.new(
  batch_size: 100,
  flush_interval: 5,
  eager_flush_levels: [:error, :fatal]  # Flush immediately on errors
)

# High-performance mode (only for non-critical logs):
logger = SolidLog::DirectLogger.new(
  batch_size: 100,
  flush_interval: 5,
  eager_flush_levels: []  # No eager flush - faster but risky
)
```

## Test 3: WAL Mode Impact

| Test | WAL Mode | Standard | Improvement |
|------|---------|----------|-------------|
| Individual inserts | 6,345/s | 2,266/s | **+180%** |
| Batch inserts | 62,625/s | 48,485/s | +29% |
| DirectLogger | 56,660/s | 45,935/s | +23% |
| **Eager flush** | **16,882/s** | **4,923/s** | **+243%** 🔥 |
| Without eager flush | 64,300/s | 46,011/s | +40% |

**Key Insight:** WAL mode provides the biggest performance gain for eager flush scenarios (+243%), making crash-safe logging much more practical.

## Test 3: DirectLogger vs HTTP Logging

| Method | Throughput | Latency/Log | Speedup |
|--------|-----------|-------------|---------|
| **DirectLogger** | **43,219 logs/sec** | **0.02ms** | **1.0x** |
| HTTP (individual) | 649 logs/sec | 1.54ms | 0.015x (67x slower) |
| HTTP (batch 100) | 26,517 logs/sec | 0.04ms | 0.61x (1.6x slower) |

**Key Insight:** HTTP has overhead from:
1. JSON serialization (client)
2. Network latency (1ms localhost, 10-50ms real network)
3. JSON parsing (server)
4. Authentication/authorization

DirectLogger skips all of this by writing directly to the database.

### When to Use What?

- **DirectLogger**: Parent Rails app logging (same database connection)
- **HTTP API**: External services, microservices, remote clients

## Test Environment

- **Database**: File-based SQLite with WAL mode
- **Ruby**: 3.3.6
- **ActiveRecord**: 8.0
- **Batch Size**: 100 logs (default)
- **Flush Interval**: 5 seconds (default)
- **File Location**: `/tmp/benchmark.db`

### Database Modes Tested

1. **WAL Mode (Write-Ahead Logging)** - Recommended
   - Better write concurrency
   - Readers don't block writers
   - 23-243% faster depending on workload

2. **Standard Mode** - For comparison
   - Traditional journal mode
   - Single-writer model
   - Slower but more compatible

**PostgreSQL Note:** PostgreSQL is generally 2-3x faster than file-based SQLite and handles concurrent writes much better. Recommended for high-traffic production apps.

## Recommendations

### ✅ For Production (Parent App Logging) - RECOMMENDED

```ruby
# Recommended configuration for file-based SQLite with WAL
logger = SolidLog::DirectLogger.new(
  batch_size: 100,           # Good balance
  flush_interval: 5,         # Flush every 5 seconds
  eager_flush_levels: [:error, :fatal]  # Crash safety
)

config.logger = ActiveSupport::Logger.new(logger)
```

**Expected performance:**
- **File-based SQLite (WAL):** 16,000+ logs/sec with crash safety
- **PostgreSQL:** 30,000+ logs/sec (estimated)

**Enable WAL mode in SQLite:**
```ruby
# In your database.yml or initializer
ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
ActiveRecord::Base.connection.execute("PRAGMA synchronous=NORMAL")
```

### ⚡ For Maximum Performance (Non-Critical Logs)

```ruby
# High-performance configuration
logger = SolidLog::DirectLogger.new(
  batch_size: 500,           # Larger batches
  flush_interval: 10,        # Less frequent flushes
  eager_flush_levels: []     # No eager flush (RISKY!)
)
```

**Expected performance:**
- **File-based SQLite (WAL):** 60,000+ logs/sec
- **PostgreSQL:** 100,000+ logs/sec (estimated)

**⚠️ Warning:** May lose crash logs! Only use for non-critical logging.

### 🔒 For Maximum Safety (Critical Systems)

```ruby
# Maximum safety configuration
logger = SolidLog::DirectLogger.new(
  batch_size: 10,            # Small batches
  flush_interval: 1,         # Flush every second
  eager_flush_levels: [:debug, :info, :warn, :error, :fatal]  # Flush everything
)
```

**Expected performance:**
- **File-based SQLite (WAL):** 3,000+ logs/sec
- **PostgreSQL:** 5,000+ logs/sec (estimated)

**Use case:** Financial transactions, compliance, critical infrastructure

## Benchmark Commands

Run benchmarks yourself:

```bash
cd solid_log-core

# File-based database (realistic production scenario)
bundle exec ruby benchmark_file_db.rb

# In-memory database (faster, for comparison)
bundle exec ruby benchmark_ingestion.rb

# DirectLogger vs HTTP comparison
bundle exec ruby benchmark_direct_vs_http.rb
```

## Key Takeaways

1. **DirectLogger is much faster than HTTP** for parent app logging (67x faster)
2. **Batching is crucial** - 9x faster than individual inserts
3. **WAL mode is essential** - 23-243% faster depending on workload
4. **Eager flush costs performance** but prevents losing crash logs
   - With WAL: 16,882 logs/sec (production-ready)
   - Without WAL: 4,923 logs/sec (too slow)
5. **WAL makes eager flush practical** - 243% faster than standard mode
6. **File-based is realistic** - in-memory benchmarks are 2-3x too optimistic
7. **Default settings are well-balanced** for most production use cases

## Quick Reference Table

### File-Based SQLite with WAL Mode (Production Setup)

| Scenario | Configuration | Throughput | Notes |
|----------|--------------|------------|-------|
| **Production (Recommended)** | Default with eager flush | **16,882 logs/sec** | Crash-safe, good performance |
| Maximum Performance | No eager flush | 64,300 logs/sec | Risky - may lose crash logs |
| Maximum Safety | Flush all levels | ~3,000 logs/sec | For critical systems |
| Individual Inserts | No batching | 6,345 logs/sec | Don't do this! |
| Manual Batching | 100/batch | 62,625 logs/sec | DirectLogger is easier |

### Real-World Scenarios

**High-traffic web app (10,000 req/min, 5 logs/request):**
- Required throughput: ~830 logs/sec
- DirectLogger capacity: 16,882 logs/sec
- **Headroom: 20x** ✅

**Microservices (50,000 logs/min average):**
- Required throughput: ~833 logs/sec
- DirectLogger capacity: 16,882 logs/sec
- **Headroom: 20x** ✅

**Data pipeline (100,000 logs/min):**
- Required throughput: ~1,667 logs/sec
- DirectLogger capacity: 16,882 logs/sec
- **Headroom: 10x** ✅

**High-volume system (500,000 logs/min):**
- Required throughput: ~8,333 logs/sec
- DirectLogger capacity: 16,882 logs/sec
- **Headroom: 2x** ⚠️ Consider PostgreSQL

**Extreme volume (1M+ logs/min):**
- Required throughput: ~16,667 logs/sec
- DirectLogger capacity: 16,882 logs/sec
- **Headroom: 1x** ❌ Use PostgreSQL or disable eager flush
