#!/usr/bin/env ruby
# Benchmark DirectLogger vs HTTP ingestion overhead
# This shows why DirectLogger is recommended for parent app logging

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
migration_files = Dir[File.expand_path("db/log_migrate/*.rb", __dir__)].sort
migration_files.each { |file| load file }
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
  request_id: "req-123"
}.freeze

puts "=" * 80
puts "DirectLogger vs HTTP Ingestion Comparison"
puts "=" * 80
puts ""

puts "This benchmark simulates the overhead of HTTP logging vs DirectLogger"
puts ""

puts "Test 1: DirectLogger (Direct Database Access)"
puts "-" * 80

logger = SolidLog::DirectLogger.new(batch_size: 100, flush_interval: 60)

direct_time = Benchmark.realtime do
  1000.times do
    logger.write(SAMPLE_LOG.to_json)
  end
  logger.flush
end

direct_throughput = 1000 / direct_time
puts "DirectLogger (1,000 logs):"
puts "  Time: #{direct_time.round(3)}s"
puts "  Throughput: #{direct_throughput.round(0)} logs/sec"
puts "  Per log: #{(direct_time / 1000 * 1000).round(2)}ms"
puts ""

logger.close

puts "Test 2: HTTP Overhead Simulation"
puts "-" * 80

# Simulate HTTP overhead: JSON serialization + network latency + parsing
http_time = Benchmark.realtime do
  1000.times do
    # Simulate what happens in HTTP ingestion:
    # 1. Serialize to JSON (client side)
    json_payload = SAMPLE_LOG.to_json

    # 2. HTTP overhead (simulated - normally 1-5ms per request for localhost)
    # We'll skip actual HTTP to avoid complexity, but add the typical overhead
    sleep(0.001) # 1ms simulated network latency

    # 3. Parse JSON (server side)
    JSON.parse(json_payload)

    # 4. Database insert (server side)
    SolidLog::RawEntry.create!(payload: json_payload, token_id: nil)
  end
end

http_throughput = 1000 / http_time
puts "HTTP Ingestion (1,000 logs with 1ms latency per request):"
puts "  Time: #{http_time.round(3)}s"
puts "  Throughput: #{http_throughput.round(0)} logs/sec"
puts "  Per log: #{(http_time / 1000 * 1000).round(2)}ms"
puts ""

puts "Test 3: HTTP Batch Ingestion (100 logs per request)"
puts "-" * 80

SolidLog::RawEntry.delete_all

http_batch_time = Benchmark.realtime do
  10.times do
    # Batch 100 logs into single request
    batch = 100.times.map { SAMPLE_LOG }

    # Serialize batch
    json_payload = batch.to_json

    # HTTP overhead (1 request for 100 logs)
    sleep(0.001) # 1ms latency

    # Parse and insert batch
    parsed = JSON.parse(json_payload)
    entries = parsed.map { |log| { payload: log.to_json, token_id: nil, received_at: Time.current } }
    SolidLog::RawEntry.insert_all(entries)
  end
end

http_batch_throughput = 1000 / http_batch_time
puts "HTTP Batch Ingestion (1,000 logs in 10 batches):"
puts "  Time: #{http_batch_time.round(3)}s"
puts "  Throughput: #{http_batch_throughput.round(0)} logs/sec"
puts "  Per log: #{(http_batch_time / 1000 * 1000).round(2)}ms"
puts ""

puts "=" * 80
puts "Summary:"
puts "  DirectLogger:               #{direct_throughput.round(0).to_s.rjust(8)} logs/sec (#{(direct_time / 1000 * 1000).round(2)}ms/log)"
puts "  HTTP (individual):          #{http_throughput.round(0).to_s.rjust(8)} logs/sec (#{(http_time / 1000 * 1000).round(2)}ms/log)"
puts "  HTTP (batch):               #{http_batch_throughput.round(0).to_s.rjust(8)} logs/sec (#{(http_batch_time / 1000 * 1000).round(2)}ms/log)"
puts ""
puts "  DirectLogger speedup:"
puts "    vs HTTP (individual):     #{(direct_throughput / http_throughput).round(1)}x faster"
puts "    vs HTTP (batch):          #{(direct_throughput / http_batch_throughput).round(1)}x faster"
puts "=" * 80
puts ""
puts "Key Insights:"
puts "  - DirectLogger eliminates HTTP overhead (serialization, network, parsing)"
puts "  - HTTP has ~1ms overhead per request minimum (localhost)"
puts "  - Batching helps HTTP, but DirectLogger still wins"
puts "  - For parent app logging: Use DirectLogger (#{(direct_throughput / http_throughput).round(0)}x faster)"
puts "  - For external services: Use HTTP API (no direct DB access needed)"
puts ""
puts "Note: Real network latency would be 10-50ms, making HTTP even slower."
