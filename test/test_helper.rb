# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
require "rails/test_help"

# Load support files
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

# Set up in-memory test database
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

# Load the schema for the log database
load File.expand_path("dummy/db/log_schema.rb", __dir__)

# Create FTS5 triggers (not captured by schema.rb)
ActiveRecord::Base.connection.execute(<<~SQL)
  CREATE TRIGGER IF NOT EXISTS solid_log_entries_fts_insert
  AFTER INSERT ON solid_log_entries
  BEGIN
    INSERT INTO solid_log_entries_fts(rowid, message, extra_fields)
    VALUES (new.id, new.message, new.extra_fields);
  END
SQL

ActiveRecord::Base.connection.execute(<<~SQL)
  CREATE TRIGGER IF NOT EXISTS solid_log_entries_fts_update
  AFTER UPDATE ON solid_log_entries
  BEGIN
    UPDATE solid_log_entries_fts
    SET message = new.message, extra_fields = new.extra_fields
    WHERE rowid = new.id;
  END
SQL

ActiveRecord::Base.connection.execute(<<~SQL)
  CREATE TRIGGER IF NOT EXISTS solid_log_entries_fts_delete
  AFTER DELETE ON solid_log_entries
  BEGIN
    DELETE FROM solid_log_entries_fts WHERE rowid = old.id;
  END
SQL

# Override SolidLog::ApplicationRecord to remove the multi-database configuration in tests
# This makes all SolidLog models use the same in-memory connection
SolidLog::ApplicationRecord.class_eval do
  # Remove the connects_to declaration
  class << self
    undef_method :connected_to if method_defined?(:connected_to)

    def connection
      ActiveRecord::Base.connection
    end

    def connection_pool
      ActiveRecord::Base.connection_pool
    end
  end
end

# Helper methods for SolidLog tests
module SolidLogTestHelpers
  # Helper to create a test token
  # Returns the hash with :id, :name, :token, :created_at
  def create_test_token(name: "Test Token")
    SolidLog.without_logging do
      result = SolidLog::Token.generate!(name)
      # Also store the actual Token object for tests that need it
      result[:model] = SolidLog::Token.find(result[:id])
      result
    end
  end

  # Helper to create a test raw entry
  def create_raw_entry(payload: nil, token: nil)
    payload ||= {
      timestamp: Time.current.iso8601,
      level: "info",
      message: "Test log message",
      app: "test-app",
      env: "test"
    }

    token ||= create_test_token

    SolidLog.without_logging do
      SolidLog::RawEntry.create!(
        raw_payload: payload.to_json,
        token_id: token.is_a?(Hash) ? SolidLog::Token.find(token[:id]).id : token.id,
        received_at: Time.current
      )
    end
  end

  # Helper to create a test entry
  def create_entry(attributes = {})
    defaults = {
      created_at: Time.current,
      level: "info",
      message: "Test log message",
      app: "test-app",
      env: "test"
    }

    SolidLog.without_logging do
      # Create a raw entry if raw_id not provided
      unless attributes[:raw_id]
        token = create_test_token unless defined?(@test_token)
        @test_token ||= token

        raw_entry = SolidLog::RawEntry.create!(
          raw_payload: defaults.merge(attributes).to_json,
          token_id: @test_token[:id],
          received_at: Time.current
        )
        attributes[:raw_id] = raw_entry.id
      end

      SolidLog::Entry.create!(defaults.merge(attributes))
    end
  end

  # Helper to create multiple entries
  def create_entries(count, attributes = {})
    count.times.map do |i|
      create_entry(attributes.merge(
        message: "Test log message #{i}",
        created_at: Time.current - i.minutes
      ))
    end
  end

  # Helper to parse a raw entry
  def parse_raw_entry(raw_entry)
    parsed = SolidLog::Parser.new.parse(raw_entry.raw_payload)
    return nil if parsed.nil?

    SolidLog.without_logging do
      SolidLog::Entry.create!(parsed.merge(raw_id: raw_entry.id))
    end
  end

  # Helper to simulate log ingestion
  def ingest_log(payload)
    token = create_test_token
    raw_entry = create_raw_entry(payload: payload, token: token)
    parse_raw_entry(raw_entry)
  end

  # Helper to wait for async operations (in tests, we run synchronously)
  def wait_for_parsing
    # In tests, parsing is synchronous, so this is a no-op
    # In real usage, this would wait for background jobs
  end
end

# Make test helpers available in all test classes
class ActiveSupport::TestCase
  include SolidLogTestHelpers if defined?(SolidLog)

  # Setup and teardown for tests
  setup do
    # Clear all SolidLog tables before each test
    if defined?(SolidLog)
      SolidLog.without_logging do
        SolidLog::RawEntry.delete_all rescue nil
        SolidLog::Entry.delete_all rescue nil
        SolidLog::Token.delete_all rescue nil
        SolidLog::Field.delete_all rescue nil
        SolidLog::FacetCache.delete_all rescue nil
      end

      # Reset configuration
      SolidLog.reset_configuration!
    end
  end

  teardown do
    # Clean up after tests
    if defined?(SolidLog)
      SolidLog.without_logging do
        SolidLog::RawEntry.delete_all rescue nil
        SolidLog::Entry.delete_all rescue nil
        SolidLog::Token.delete_all rescue nil
        SolidLog::Field.delete_all rescue nil
        SolidLog::FacetCache.delete_all rescue nil
      end
    end
  end
end
