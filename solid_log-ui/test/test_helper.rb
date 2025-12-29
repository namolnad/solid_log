# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "bundler/setup"
require "combustion"

# Initialize Combustion (loads minimal Rails app from test/internal)
Combustion.path = "test/internal"
Combustion.initialize! :active_record, :action_controller, :action_view, :action_cable,
  load_schema: false do
  config.logger = Logger.new(nil)
  config.log_level = :fatal
  config.hosts.clear  # Disable host authorization in tests
end

# Manually load schema using execute_batch for SQLite multi-statement support
structure_sql = File.read(Rails.root.join("db", "structure.sql"))
ActiveRecord::Base.connection.raw_connection.execute_batch(structure_sql)

require "minitest/autorun"
require "rails-controller-testing"

# Load solid_log-core and solid_log-ui
require "solid_log/core"
require "solid_log/ui"

# Ensure authentication is disabled for tests
SolidLog::UI.configuration.authentication_method = :none

# Load support files
Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

# Load shared test helpers from core gem (using relative path in monorepo)
require_relative "../../solid_log-core/test/support/test_helpers"

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

class ActionDispatch::IntegrationTest
  include Rails.application.routes.url_helpers
  include Rails::Controller::Testing::TestProcess
  include Rails::Controller::Testing::TemplateAssertions
  include Rails::Controller::Testing::Integration

  # Helper to parse Turbo Stream responses
  def assert_turbo_stream(action:, target:, &block)
    assert_equal Mime[:turbo_stream], response.media_type
    assert_select "turbo-stream[action='#{action}'][target='#{target}']", &block
  end
end

class ActionCable::Channel::TestCase
  # Helper methods for channel tests
end
