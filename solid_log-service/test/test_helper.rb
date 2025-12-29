# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "bundler/setup"

require "combustion"

# Initialize Combustion (loads minimal Rails app from test/internal)
# This will load Rails, ActiveRecord, etc.
# Combustion looks for test/internal relative to the gem root
Combustion.path = "test/internal"
Combustion.initialize! :active_record, :action_controller, :active_job,
  load_schema: false do  # Disable automatic schema loading - we'll do it manually
  config.logger = Logger.new(nil) # Suppress logs during tests
  config.log_level = :fatal
end

# Manually load schema using execute_batch for SQLite multi-statement support
structure_sql = File.read(Rails.root.join("db", "structure.sql"))
ActiveRecord::Base.connection.raw_connection.execute_batch(structure_sql)

require "minitest/autorun"

# Now require bundler dependencies (after Rails is loaded)
Bundler.require(:default)

# Load solid_log-core gem (includes models, migrations, parser)
require "solid_log/core"

# Schema is loaded by Combustion from test/internal/db/structure.sql

# Initialize SolidLog configuration
SolidLog::Core.configure do |config|
  config.retention_days = 30
  config.error_retention_days = 90
  config.parser_batch_size = 200
end

# Load shared test helpers from core gem (using relative path in monorepo)
require_relative "../../solid_log-core/test/support/test_helpers"

# Make test helpers available in all test classes
class ActiveSupport::TestCase
  include SolidLog::TestHelpers

  # Setup and teardown for tests
  setup do
    setup_solidlog_tests
  end

  teardown do
    teardown_solidlog_tests
  end
end

# ActionController test case helpers
class ActionDispatch::IntegrationTest
  include SolidLog::TestHelpers
end
