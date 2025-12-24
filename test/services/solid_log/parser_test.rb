require "test_helper"

module SolidLog
  class ParserTest < ActiveSupport::TestCase
    setup do
      @parser = Parser.new
    end

    test "parses valid JSON log entry" do
      payload = {
        timestamp: "2025-01-15T10:30:45Z",
        level: "info",
        message: "User login successful",
        app: "web",
        env: "production"
      }.to_json

      result = @parser.parse(payload)

      assert_equal "info", result[:level]
      assert_equal "User login successful", result[:message]
      assert_equal "web", result[:app]
      assert_equal "production", result[:env]
      assert_instance_of Time, result[:created_at]
    end

    test "normalizes log levels" do
      ["INFO", "Info", "info"].each do |level|
        payload = {timestamp: Time.current.iso8601, level: level, message: "test"}.to_json
        result = @parser.parse(payload)

        assert_equal "info", result[:level]
      end
    end

    test "defaults to info level for unknown levels" do
      payload = {timestamp: Time.current.iso8601, level: "unknown_level", message: "test"}.to_json
      result = @parser.parse(payload)

      assert_equal "info", result[:level]
    end

    test "parses timestamp from various formats" do
      formats = [
        "2025-01-15T10:30:45Z",
        "2025-01-15T10:30:45-05:00",
        "2025-01-15T10:30:45.123Z",
        1736937045,
        1736937045123
      ]

      formats.each do |timestamp|
        payload = {timestamp: timestamp, level: "info", message: "test"}.to_json
        result = @parser.parse(payload)

        assert_instance_of Time, result[:created_at]
      end
    end

    test "uses current time if no timestamp provided" do
      payload = {level: "info", message: "test"}.to_json

      travel_to Time.current do
        result = @parser.parse(payload)

        assert_in_delta Time.current, result[:created_at], 1.second
      end
    end

    test "extracts standard fields" do
      payload = {
        timestamp: Time.current.iso8601,
        level: "info",
        message: "test",
        app: "web",
        env: "production",
        request_id: "abc-123",
        job_id: "job-456",
        duration: 145.2,
        status_code: 200,
        controller: "UsersController",
        action: "create",
        path: "/users",
        method: "POST"
      }.to_json

      result = @parser.parse(payload)

      assert_equal "web", result[:app]
      assert_equal "production", result[:env]
      assert_equal "abc-123", result[:request_id]
      assert_equal "job-456", result[:job_id]
      assert_equal 145.2, result[:duration]
      assert_equal 200, result[:status_code]
      assert_equal "UsersController", result[:controller]
      assert_equal "create", result[:action]
      assert_equal "/users", result[:path]
      assert_equal "POST", result[:method]
    end

    test "extracts custom fields to extra_fields" do
      payload = {
        timestamp: Time.current.iso8601,
        level: "info",
        message: "test",
        user_id: 42,
        custom_field: "custom_value",
        nested: {key: "value"}
      }.to_json

      result = @parser.parse(payload)

      assert result[:extra_fields].is_a?(Hash)
      assert_equal 42, result[:extra_fields]["user_id"]
      assert_equal "custom_value", result[:extra_fields]["custom_field"]
      assert_equal({"key" => "value"}, result[:extra_fields]["nested"])
    end

    test "returns nil for invalid JSON" do
      result = @parser.parse("{invalid json")

      assert_nil result
    end

    test "handles empty payload" do
      result = @parser.parse("")

      assert_nil result
    end

    test "does not track fields in registry (delegated to ParserJob)" do
      payload = {
        timestamp: Time.current.iso8601,
        level: "info",
        message: "test",
        user_id: 42,
        ip_address: "192.168.1.1"
      }.to_json

      @parser.parse(payload)

      # Parser should not track fields - that's ParserJob's responsibility
      assert_not Field.exists?(name: "user_id")
      assert_not Field.exists?(name: "ip_address")
    end

    test "handles missing message field" do
      payload = {timestamp: Time.current.iso8601, level: "info"}.to_json
      result = @parser.parse(payload)

      assert_nil result[:message]
    end
  end
end
