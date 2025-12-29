# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "bundler/setup"
require "minitest/autorun"
require "active_record"
require "active_support/all"
require "active_support/security_utils"
require "logger"
require "concurrent"
require "rack"
require "rack/mock"

# Set up Rails module with logger for models that reference Rails.logger
module Rails
  def self.logger
    @logger ||= Logger.new(STDOUT)
  end

  def self.env
    @env ||= ActiveSupport::StringInquirer.new(ENV["RAILS_ENV"] || "test")
  end

  def self.application
    @application ||= Struct.new(:secret_key_base).new("test_secret_key_base_for_solidlog_tests")
  end
end

# Load the core gem
require_relative "../lib/solid_log/core"

# Set up in-memory test database
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# Run migrations from the core gem manually
# Suppress migration output during tests
ActiveRecord::Migration.verbose = false

# Load and execute migrations in order
migration_files = Dir[File.expand_path("../db/log_migrate/*.rb", __dir__)].sort
migration_files.each do |file|
  load file
end

# Get all migration classes and sort by version
migration_classes = [
  CreateSolidLogRaw,
  CreateSolidLogEntries,
  CreateSolidLogFields,
  CreateSolidLogTokens,
  CreateSolidLogFacetCache,
  CreateSolidLogFtsTriggers
]

# Run each migration
migration_classes.each do |klass|
  klass.new.migrate(:up)
end

# Initialize SolidLog configuration
SolidLog::Core.configure do |config|
  config.retention_days = 30
  config.error_retention_days = 90
  config.parser_batch_size = 200
end

# Load shared test helpers
require_relative "support/test_helpers"

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
