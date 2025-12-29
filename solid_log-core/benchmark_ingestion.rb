#!/usr/bin/env ruby
# Simple ingestion benchmark - run from solid_log-core directory
# Usage: cd solid_log-core && bundle exec ruby benchmark_ingestion.rb

require "bundler/setup"
require "benchmark"
require "active_record"
require "active_support/all"
require "json"

# Load the core gem AFTER ActiveRecord is loaded
require_relative "lib/solid_log/core"

# Setup test database
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Load and run migrations
ActiveRecord::Migration.verbose = false

# Load all migration files
migration_files = Dir[File.expand_path("db/log_migrate/*.rb", __dir__)].sort
migration_files.each { |file| load file }

# Run migrations
[CreateSolidLogRaw, CreateSolidLogEntries, CreateSolidLogFields,
 CreateSolidLogTokens, CreateSolidLogFacetCache, CreateSolidLogFtsTriggers].each do |klass|
  klass.new.migrate(:up)
end

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

puts "=" * 80
puts "SolidLog Ingestion Benchmark"
puts "=" * 80
puts ""

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
  logger.flush # Ensure all buffered logs are written
end

direct_throughput = 1000 / direct_time
puts "DirectLogger (auto-batched):"
puts "  Time: #{direct_time.round(3)}s"
puts "  Throughput: #{direct_throughput.round(0)} logs/sec"
puts "  Speedup: #{(direct_throughput / individual_throughput).round(1)}x faster than individual"
puts "  Speedup: #{(direct_throughput / batch_throughput).round(1)}x faster than manual batching"
puts ""

logger.close

puts ""
puts "Test 2: DirectLogger Write Performance (buffered, no flush)"
puts "-" * 80

# This tests the raw write speed (buffering only, no DB I/O)
logger = SolidLog::DirectLogger.new(batch_size: 100000, flush_interval: 600)

buffered_time = Benchmark.realtime do
  10000.times do
    logger.write(SAMPLE_LOG.to_json)
  end
end

buffered_throughput = 10000 / buffered_time
puts "Buffered writes (10,000 logs):"
puts "  Time: #{buffered_time.round(3)}s"
puts "  Throughput: #{buffered_throughput.round(0)} logs/sec"
puts "  Per write: #{(buffered_time / 10000 * 1_000_000).round(1)} μs"
puts ""

logger.close

puts ""
puts "Test 3: Eager Flush Impact (error/fatal logs)"
puts "-" * 80

# Normal logger with eager flush
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
puts "With eager flush (500 info + 500 error):"
puts "  Time: #{eager_time.round(3)}s"
puts "  Throughput: #{eager_throughput.round(0)} logs/sec"
puts ""

# No eager flush
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
puts "Without eager flush (all buffered):"
puts "  Time: #{no_eager_time.round(3)}s"
puts "  Throughput: #{no_eager_throughput.round(0)} logs/sec"
puts "  Performance cost: #{((no_eager_throughput - eager_throughput) / no_eager_throughput * 100).round(1)}% slower with eager flush"
puts ""

eager_logger.close
no_eager_logger.close

puts "=" * 80
puts "Summary:"
puts "  Individual inserts:     #{individual_throughput.round(0).to_s.rjust(8)} logs/sec (1.0x)"
puts "  Batch inserts (100):    #{batch_throughput.round(0).to_s.rjust(8)} logs/sec (#{(batch_throughput / individual_throughput).round(1)}x)"
puts "  DirectLogger (batched): #{direct_throughput.round(0).to_s.rjust(8)} logs/sec (#{(direct_throughput / individual_throughput).round(1)}x)"
puts "  DirectLogger (buffer):  #{buffered_throughput.round(0).to_s.rjust(8)} logs/sec (#{(buffered_throughput / individual_throughput).round(0)}x)"
puts ""
puts "  With eager flush:       #{eager_throughput.round(0).to_s.rjust(8)} logs/sec (safe)"
puts "  Without eager flush:    #{no_eager_throughput.round(0).to_s.rjust(8)} logs/sec (risky)"
puts "=" * 80
puts ""
puts "Recommendations:"
puts "  - Use DirectLogger instead of individual inserts (#{(direct_throughput / individual_throughput).round(0)}x faster)"
puts "  - Keep eager flush enabled for production (only ~#{((no_eager_throughput - eager_throughput) / no_eager_throughput * 100).round(0)}% slower)"
puts "  - In-memory SQLite used - real databases will be 2-5x slower"
