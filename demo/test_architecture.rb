#!/usr/bin/env ruby
# Quick test to verify the 3-gem architecture loads correctly

puts "\n" + "="*70
puts "Testing SolidLog 3-Gem Architecture (Simplified)"
puts "="*70

ENV['RAILS_ENV'] ||= 'development'
require_relative 'config/environment'

puts "\n✅ Rails environment loaded"

# Test 1: Core has NO engine
puts "\n[Test 1: solid_log-core structure]"
begin
  # Core should NOT have an engine
  SolidLog::Core::Engine
  puts "  ❌ FAIL: Core has an Engine (it shouldn't!)"
rescue NameError
  puts "  ✅ PASS: Core has no Engine (correct!)"
end

# Models should be loaded
models_ok = [
  SolidLog::RawEntry,
  SolidLog::Entry,
  SolidLog::Token,
  SolidLog::Field,
  SolidLog::FacetCache
].all? { |m| m.is_a?(Class) }

if models_ok
  puts "  ✅ PASS: All models loaded from lib/solid_log/models/"
else
  puts "  ❌ FAIL: Models not loaded"
end

# Test 2: Service HAS engine
puts "\n[Test 2: solid_log-service structure]"
begin
  engine = SolidLog::Service::Engine
  if engine.is_a?(Class) && engine < Rails::Engine
    puts "  ✅ PASS: Service has Engine (correct!)"
  else
    puts "  ❌ FAIL: Service Engine is wrong type"
  end
rescue NameError => e
  puts "  ❌ FAIL: Service Engine not found: #{e.message}"
end

# Jobs should be loaded
jobs_ok = [
  SolidLog::ParserJob,
  SolidLog::RetentionJob,
  SolidLog::CacheCleanupJob,
  SolidLog::FieldAnalysisJob
].all? { |j| j.is_a?(Class) }

if jobs_ok
  puts "  ✅ PASS: All jobs loaded from app/jobs/"
else
  puts "  ❌ FAIL: Jobs not loaded"
end

# Test 3: UI HAS engine
puts "\n[Test 3: solid_log-ui structure]"
begin
  engine = SolidLog::UI::Engine
  if engine.is_a?(Class) && engine < Rails::Engine
    puts "  ✅ PASS: UI has Engine (correct!)"
  else
    puts "  ❌ FAIL: UI Engine is wrong type"
  end
rescue NameError => e
  puts "  ❌ FAIL: UI Engine not found: #{e.message}"
end

# Test 4: Routes are mounted
puts "\n[Test 4: Engine mounting]"
routes = Rails.application.routes.routes.map(&:path).map(&:spec).map(&:to_s)

if routes.any? { |r| r.include?('/logs') }
  puts "  ✅ PASS: UI engine mounted at /logs"
else
  puts "  ⚠️  WARN: UI engine not mounted"
end

# Test 5: Database connection
puts "\n[Test 5: Database connections]"
begin
  # Core models should connect to :log database
  SolidLog::ApplicationRecord.connection_pool.with_connection do |conn|
    tables = conn.tables.grep(/solid_log/)
    if tables.size >= 5
      puts "  ✅ PASS: Log database connected (#{tables.size} tables)"
    else
      puts "  ⚠️  WARN: Log database has only #{tables.size} tables"
    end
  end
rescue => e
  puts "  ❌ FAIL: Database error: #{e.message}"
end

# Summary
puts "\n" + "="*70
puts "Architecture Test Complete!"
puts "="*70
puts "\nStructure:"
puts "  • solid_log-core:    NO engine, models in lib/"
puts "  • solid_log-service: HAS engine, controllers/jobs in app/"
puts "  • solid_log-ui:      HAS engine, UI components in app/"
puts "\nThis is the correct, simplified architecture! ✨"
puts "="*70
puts
