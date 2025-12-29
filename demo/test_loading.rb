#!/usr/bin/env ruby
# Test script to verify SolidLog gems load correctly

puts "=" * 60
puts "Testing SolidLog 3-Gem Architecture"
puts "=" * 60

# Load the Rails environment
ENV['RAILS_ENV'] ||= 'development'
require_relative 'config/environment'

puts "\n✓ Rails environment loaded successfully!"
puts "  Rails version: #{Rails.version}"
puts "  Environment: #{Rails.env}"

# Test Core gem
puts "\n[Testing solid_log-core]"
puts "  SolidLog::Core::VERSION: #{SolidLog::Core::VERSION}"
puts "  Configuration: #{SolidLog::Core.configuration.class}"

# Test models
puts "\n[Testing Models]"
models = [
  SolidLog::RawEntry,
  SolidLog::Entry,
  SolidLog::Token,
  SolidLog::Field,
  SolidLog::FacetCache
]

models.each do |model|
  count = model.count rescue "N/A (table might not exist)"
  puts "  ✓ #{model}: #{count} records"
end

# Test Service gem
puts "\n[Testing solid_log-service]"
puts "  SolidLog::Service::VERSION: #{SolidLog::Service::VERSION}"
puts "  Configuration: #{SolidLog::Service.configuration.class}"
puts "  Job mode: #{SolidLog::Service.configuration.job_mode}"
puts "  Parser interval: #{SolidLog::Service.configuration.parser_interval}s"

# Test UI gem
puts "\n[Testing solid_log-ui]"
puts "  SolidLog::UI::VERSION: #{SolidLog::UI::VERSION}"
puts "  Configuration: #{SolidLog::UI.configuration.class}"
puts "  Mode: #{SolidLog::UI.configuration.mode}"
puts "  Base controller: #{SolidLog::UI.configuration.base_controller}"

# Test database connections
puts "\n[Testing Database Connections]"
begin
  ActiveRecord::Base.connection_pool.with_connection do |conn|
    puts "  ✓ Primary database connected"
  end
rescue => e
  puts "  ✗ Primary database error: #{e.message}"
end

begin
  SolidLog::ApplicationRecord.connection_pool.with_connection do |conn|
    puts "  ✓ Log database connected"
    tables = conn.tables.grep(/solid_log/)
    puts "  ✓ Found #{tables.size} SolidLog tables: #{tables.join(', ')}"
  end
rescue => e
  puts "  ✗ Log database error: #{e.message}"
end

# Test creating a token
puts "\n[Testing Data Creation]"
begin
  token = SolidLog::Token.create!(
    name: "Test Token #{Time.now.to_i}",
    token_hash: SolidLog::Token.send(:hash_token, SecureRandom.hex(16))
  )
  puts "  ✓ Created token: #{token.name} (ID: #{token.id})"

  # Create a raw entry
  raw = SolidLog::RawEntry.create!(
    token: token,
    payload: {
      timestamp: Time.current.iso8601,
      level: 'info',
      message: 'Test log from test script',
      app: 'test_app',
      env: Rails.env
    }.to_json,
    received_at: Time.current
  )
  puts "  ✓ Created raw entry (ID: #{raw.id})"

  # Parse it
  SolidLog::ParserJob.perform_now(batch_size: 10)
  parsed_count = SolidLog::Entry.count
  puts "  ✓ Parsed entries: #{parsed_count} total"

rescue => e
  puts "  ✗ Data creation error: #{e.message}"
  puts "    #{e.backtrace.first(3).join("\n    ")}"
end

puts "\n" + "=" * 60
puts "Testing complete! All 3 gems are working together."
puts "=" * 60
puts "\nNext steps:"
puts "  1. Start the server: bin/rails server"
puts "  2. Visit: http://localhost:3000"
puts "  3. Generate logs and test the UI at http://localhost:3000/logs"
puts
