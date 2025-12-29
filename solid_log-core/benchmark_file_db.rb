#!/usr/bin/env ruby
# File-based database benchmark - more realistic performance numbers
# Usage: cd solid_log-core && bundle exec ruby benchmark_file_db.rb

require "bundler/setup"
require "benchmark"
require "active_record"
require "active_support/all"
require "json"
require "fileutils"

# Load the core gem AFTER ActiveRecord is loaded
require_relative "lib/solid_log/core"

DB_PATH = File.join(__dir__, "tmp", "benchmark.db")

# Ensure tmp directory exists
FileUtils.mkdir_p(File.dirname(DB_PATH))

# Clean up old database
FileUtils.rm_f(DB_PATH)
FileUtils.rm_f("#{DB_PATH}-shm")
FileUtils.rm_f("#{DB_PATH}-wal")

puts "=" * 80
puts "SolidLog File-Based Database Benchmark"
puts "=" * 80
puts ""
puts "Database: #{DB_PATH}"
puts ""

# Sample log payload
SAMPLE_LOG = {
  timestamp: Time.now.utc.iso8601,
  level: "info",
  message: "Sample log message for benchmarking",
  app: "benchmark",
  env: "test",
  request_id: "req-123",
  user_id: 42,
  ip: "192.168.1.1"
}.freeze

def setup_database(db_path, wal_mode: true)
  ActiveRecord::Base.establish_connection(
    adapter: "sqlite3",
    database: db_path
  )

  # Enable WAL mode for better write performance
  if wal_mode
    ActiveRecord::Base.connection.execute("PRAGMA journal_mode=WAL")
    ActiveRecord::Base.connection.execute("PRAGMA synchronous=NORMAL")
    puts "WAL mode enabled (faster writes, better concurrency)"
  else
    ActiveRecord::Base.connection.execute("PRAGMA journal_mode=DELETE")
    ActiveRecord::Base.connection.execute("PRAGMA synchronous=FULL")
    puts "WAL mode disabled (traditional mode)"
  end
  puts ""

  # Load and run migrations
  ActiveRecord::Migration.verbose = false
  migration_files = Dir[File.expand_path("db/log_migrate/*.rb", __dir__)].sort
  migration_files.each { |file| load file }
  [CreateSolidLogRaw, CreateSolidLogEntries, CreateSolidLogFields,
   CreateSolidLogTokens, CreateSolidLogFacetCache, CreateSolidLogFtsTriggers].each do |klass|
    klass.new.migrate(:up)
  end
end

def run_benchmark_suite
  puts "Test 1: Individual vs Batch Inserts (1,000 logs)"
  puts "-" * 80

  # Individual inserts
  SolidLog::RawEntry.delete_all
  individual_time = Benchmark.realtime do
    1000.times do
      SolidLog::RawEntry.create!(
        payload: SAMPLE_LOG.to_json,
        token_id: nil
      )
    end
  end

  individual_throughput = 1000 / individual_time
  puts "Individual inserts:"
  puts "  Time: #{individual_time.round(3)}s"
  puts "  Throughput: #{individual_throughput.round(0)} logs/sec"
  puts ""

  # Batch inserts (100 per batch)
  SolidLog::RawEntry.delete_all
  batch_time = Benchmark.realtime do
    10.times do
      batch = 100.times.map do
        {
          payload: SAMPLE_LOG.to_json,
          token_id: nil,
          received_at: Time.current
        }
      end
      SolidLog::RawEntry.insert_all(batch)
    end
  end

  batch_throughput = 1000 / batch_time
  puts "Batch inserts (100/batch):"
  puts "  Time: #{batch_time.round(3)}s"
  puts "  Throughput: #{batch_throughput.round(0)} logs/sec"
  puts "  Speedup: #{(batch_throughput / individual_throughput).round(1)}x faster"
  puts ""

  # DirectLogger with auto-flushing
  SolidLog::RawEntry.delete_all
  logger = SolidLog::DirectLogger.new(batch_size: 100, flush_interval: 60)

  direct_time = Benchmark.realtime do
    1000.times do
      logger.write(SAMPLE_LOG.to_json)
    end
    logger.flush
  end

  direct_throughput = 1000 / direct_time
  puts "DirectLogger (auto-batched):"
  puts "  Time: #{direct_time.round(3)}s"
  puts "  Throughput: #{direct_throughput.round(0)} logs/sec"
  puts "  Speedup: #{(direct_throughput / individual_throughput).round(1)}x faster than individual"
  puts ""

  logger.close

  puts ""
  puts "Test 2: Eager Flush Impact (500 info + 500 error)"
  puts "-" * 80

  # With eager flush
  SolidLog::RawEntry.delete_all
  eager_logger = SolidLog::DirectLogger.new(
    batch_size: 100,
    flush_interval: 60,
    eager_flush_levels: [:error, :fatal]
  )

  eager_time = Benchmark.realtime do
    500.times { eager_logger.write({level: "info", message: "info"}.to_json) }
    500.times { eager_logger.write({level: "error", message: "error"}.to_json) }
    eager_logger.flush
  end

  eager_throughput = 1000 / eager_time
  puts "With eager flush (safe):"
  puts "  Time: #{eager_time.round(3)}s"
  puts "  Throughput: #{eager_throughput.round(0)} logs/sec"
  puts ""

  eager_logger.close

  # Without eager flush
  SolidLog::RawEntry.delete_all
  no_eager_logger = SolidLog::DirectLogger.new(
    batch_size: 100,
    flush_interval: 60,
    eager_flush_levels: []
  )

  no_eager_time = Benchmark.realtime do
    500.times { no_eager_logger.write({level: "info", message: "info"}.to_json) }
    500.times { no_eager_logger.write({level: "error", message: "error"}.to_json) }
    no_eager_logger.flush
  end

  no_eager_throughput = 1000 / no_eager_time
  puts "Without eager flush (risky):"
  puts "  Time: #{no_eager_time.round(3)}s"
  puts "  Throughput: #{no_eager_throughput.round(0)} logs/sec"
  puts "  Performance cost: #{((no_eager_throughput - eager_throughput) / no_eager_throughput * 100).round(1)}% slower with eager flush"
  puts ""

  no_eager_logger.close

  puts ""
  puts "Test 3: High-Volume Test (10,000 logs)"
  puts "-" * 80

  SolidLog::RawEntry.delete_all
  volume_logger = SolidLog::DirectLogger.new(batch_size: 100, flush_interval: 60)

  volume_time = Benchmark.realtime do
    10000.times do
      volume_logger.write(SAMPLE_LOG.to_json)
    end
    volume_logger.flush
  end

  volume_throughput = 10000 / volume_time
  puts "DirectLogger (10,000 logs):"
  puts "  Time: #{volume_time.round(3)}s"
  puts "  Throughput: #{volume_throughput.round(0)} logs/sec"
  puts "  Per log: #{(volume_time / 10000 * 1000).round(2)}ms"
  puts ""

  volume_logger.close

  # Return results for comparison
  {
    individual: individual_throughput,
    batch: batch_throughput,
    direct: direct_throughput,
    eager: eager_throughput,
    no_eager: no_eager_throughput,
    volume: volume_throughput
  }
end

# Test with WAL mode (recommended for production)
puts "=" * 80
puts "WAL Mode (Recommended for Production)"
puts "=" * 80
puts ""
setup_database(DB_PATH, wal_mode: true)
wal_results = run_benchmark_suite

# Disconnect and clean up
ActiveRecord::Base.connection.close
FileUtils.rm_f(DB_PATH)
FileUtils.rm_f("#{DB_PATH}-shm")
FileUtils.rm_f("#{DB_PATH}-wal")

puts "=" * 80
puts "Standard Mode (No WAL)"
puts "=" * 80
puts ""
setup_database(DB_PATH, wal_mode: false)
standard_results = run_benchmark_suite

# Disconnect
ActiveRecord::Base.connection.close

puts ""
puts "=" * 80
puts "Summary: WAL Mode vs Standard Mode"
puts "=" * 80
puts ""

comparison = [
  ["Individual inserts", wal_results[:individual], standard_results[:individual]],
  ["Batch inserts", wal_results[:batch], standard_results[:batch]],
  ["DirectLogger", wal_results[:direct], standard_results[:direct]],
  ["With eager flush", wal_results[:eager], standard_results[:eager]],
  ["Without eager flush", wal_results[:no_eager], standard_results[:no_eager]],
  ["High volume (10k)", wal_results[:volume], standard_results[:volume]]
]

printf "%-25s %15s %15s %10s\n", "Test", "WAL Mode", "Standard", "WAL Gain"
puts "-" * 80

comparison.each do |name, wal, standard|
  gain = ((wal - standard) / standard * 100).round(0)
  gain_str = gain > 0 ? "+#{gain}%" : "#{gain}%"
  printf "%-25s %10d/s %10d/s %10s\n", name, wal.round(0), standard.round(0), gain_str
end

puts ""
puts "=" * 80
puts "File-Based Database Insights"
puts "=" * 80
puts ""
puts "WAL Mode Benefits:"
puts "  - Better write concurrency (readers don't block writers)"
puts "  - Faster writes (sequential writes to WAL log)"
puts "  - Recommended for production use"
puts ""
puts "File vs In-Memory Comparison:"
puts "  - File-based is ~2-5x slower than in-memory SQLite"
puts "  - Still fast enough for high-volume logging"
puts "  - More realistic for production deployments"
puts ""
puts "PostgreSQL Expected Performance:"
puts "  - Generally 2-3x faster than file-based SQLite for writes"
puts "  - Much better for concurrent access"
puts "  - Recommended for high-traffic production apps"
puts ""

# Get database file size
db_size = File.size(DB_PATH) / 1024.0
wal_size = File.exist?("#{DB_PATH}-wal") ? File.size("#{DB_PATH}-wal") / 1024.0 : 0

puts "Database Files:"
puts "  #{DB_PATH}"
puts "  Size: #{db_size.round(2)} KB"
if wal_size > 0
  puts "  WAL: #{wal_size.round(2)} KB"
end
puts "  Total entries: #{SolidLog::RawEntry.count}"
puts ""

# Clean up
puts "Cleaning up test database..."
FileUtils.rm_f(DB_PATH)
FileUtils.rm_f("#{DB_PATH}-shm")
FileUtils.rm_f("#{DB_PATH}-wal")

puts "Done!"
puts ""
