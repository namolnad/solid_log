ENV["RACK_ENV"] = "test"
ENV["SOLIDLOG_SECRET_KEY"] ||= "test-secret-key-for-tests"

require "bundler/setup"
require "minitest/autorun"
require "rack/test"

# Load dependencies
require "active_support"
require "active_support/core_ext"
require "active_record"
require "logger"

# Set up ActiveRecord database connection for tests
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Set up logger (suppress during tests)
ActiveRecord::Base.logger = Logger.new(nil)

# Load solid_log-core gem (includes models, migrations, parser)
require "solid_log/core"

# Load structure.sql to set up schema
structure_sql_path = File.expand_path("internal/db/structure.sql", __dir__)
structure_sql = File.read(structure_sql_path)
ActiveRecord::Base.connection.raw_connection.execute_batch(structure_sql)

# Configure SolidLog logger
SolidLog.logger = Logger.new(nil)

# Initialize SolidLog configuration
SolidLog::Core.configure do |config|
  config.retention_days = 30
  config.error_retention_days = 90
  config.parser_batch_size = 200
end

# Load solid_log-service
require_relative "../lib/solid_log/service"

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

# Rack::Test integration for endpoint tests
class RackTestCase < ActiveSupport::TestCase
  include Rack::Test::Methods
  include SolidLog::TestHelpers

  def app
    SolidLog::Service::RackApp.new
  end

  # Parse JSON response body
  def json_response
    JSON.parse(last_response.body)
  end

  # Helper to assert response status
  def assert_response(expected_status, message = nil)
    status_codes = {
      success: 200,
      ok: 200,
      accepted: 202,
      bad_request: 400,
      unauthorized: 401,
      not_found: 404,
      unprocessable_entity: 422,
      payload_too_large: 413,
      service_unavailable: 503
    }

    expected_code = status_codes[expected_status] || expected_status
    default_message = "Expected response to be #{expected_status} (#{expected_code}), but was #{last_response.status}. Body: #{last_response.body}"
    assert_equal expected_code, last_response.status, message || default_message
  end
end
