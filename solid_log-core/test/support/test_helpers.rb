# Shared test helper methods for all SolidLog gems
module SolidLog
  module TestHelpers
    # Helper to create a test token
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
      token_id = token.is_a?(Hash) ? token[:id] : token.id

      SolidLog.without_logging do
        SolidLog::RawEntry.create!(
          payload: payload.to_json,
          token_id: token_id,
          received_at: Time.current
        )
      end
    end

    # Helper to create a test entry
    def create_entry(attributes = {})
      defaults = {
        timestamp: Time.current,
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
            payload: defaults.merge(attributes).to_json,
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
          timestamp: Time.current - i.minutes,
          created_at: Time.current - i.minutes
        ))
      end
    end

    # Helper to create test fields
    def create_field(attributes = {})
      defaults = {
        field_type: "string",
        usage_count: 0,
        promoted: false,
        filter_type: "multiselect",
        last_seen_at: Time.current
      }

      SolidLog.without_logging do
        SolidLog::Field.create!(defaults.merge(attributes))
      end
    end

    # Common setup for all SolidLog tests
    def setup_solidlog_tests
      # Clear all SolidLog tables before each test
      SolidLog.without_logging do
        SolidLog::Entry.delete_all
        SolidLog::RawEntry.delete_all
        SolidLog::Field.delete_all
        SolidLog::Token.delete_all
        SolidLog::FacetCache.delete_all if defined?(SolidLog::FacetCache)
      end
    end

    # Common teardown for all SolidLog tests
    def teardown_solidlog_tests
      # Clean up after tests
      SolidLog.without_logging do
        SolidLog::Entry.delete_all
        SolidLog::RawEntry.delete_all
        SolidLog::Field.delete_all
        SolidLog::Token.delete_all
        SolidLog::FacetCache.delete_all if defined?(SolidLog::FacetCache)
      end
    end
  end
end
