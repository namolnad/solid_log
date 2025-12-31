require "test_helper"

module SolidLog
  class ParserJobTest < ActiveSupport::TestCase
    setup do
      @token = create_test_token
    end

    test "processes unparsed raw entries and creates entries" do
      # Create 5 unparsed raw entries
      5.times do |i|
        RawEntry.create!(
          payload: {
            timestamp: Time.current.iso8601,
            level: "info",
            message: "Test message #{i}",
            app: "test-app",
            env: "test"
          }.to_json,
          token_id: @token[:id],
          received_at: Time.current
        )
      end

      assert_equal 5, RawEntry.count
      assert_equal 0, Entry.count

      # Process batch
      ParserJob.perform

      # All entries should be parsed
      assert_equal 5, Entry.count
      assert_equal 0, RawEntry.unparsed.count
    end

    test "respects batch_size parameter" do
      # Create 10 entries
      10.times do |i|
        RawEntry.create!(
          payload: { timestamp: Time.current.iso8601, level: "info", message: "Test #{i}" }.to_json,
          token_id: @token[:id],
          received_at: Time.current
        )
      end

      # Process with batch_size=5
      ParserJob.perform(batch_size: 5)

      # Only 5 should be parsed
      assert_equal 5, Entry.count
      assert_equal 5, RawEntry.unparsed.count

      # Process again
      ParserJob.perform(batch_size: 5)

      # All should be parsed now
      assert_equal 10, Entry.count
      assert_equal 0, RawEntry.unparsed.count
    end

    test "uses configured batch_size when not specified" do
      original_batch_size = SolidLog.configuration.parser_batch_size
      SolidLog.configuration.parser_batch_size = 3

      # Create 10 entries
      10.times do |i|
        RawEntry.create!(
          payload: { timestamp: Time.current.iso8601, level: "info", message: "Test #{i}" }.to_json,
          token_id: @token[:id],
          received_at: Time.current
        )
      end

      # Process without batch_size parameter - should use config
      ParserJob.perform

      # Only 3 should be parsed (configured batch size)
      assert_equal 3, Entry.count
      assert_equal 7, RawEntry.unparsed.count

      # Restore config
      SolidLog.configuration.parser_batch_size = original_batch_size
    end

    test "tracks dynamic fields and updates field registry" do
      # Create entry with dynamic fields
      RawEntry.create!(
        payload: {
          timestamp: Time.current.iso8601,
          level: "info",
          message: "User action",
          user_id: 42,
          user_name: "John Doe",
          is_admin: true,
          login_count: 5
        }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      # Field registry should be empty
      assert_equal 0, Field.count

      # Parse entry
      ParserJob.perform

      # Fields should be tracked
      assert Field.exists?(name: "user_id")
      assert Field.exists?(name: "user_name")
      assert Field.exists?(name: "is_admin")
      assert Field.exists?(name: "login_count")

      user_id_field = Field.find_by(name: "user_id")
      assert_equal 1, user_id_field.usage_count
      assert_equal "number", user_id_field.field_type
      assert_not_nil user_id_field.last_seen_at

      is_admin_field = Field.find_by(name: "is_admin")
      assert_equal "boolean", is_admin_field.field_type
    end

    test "increments field usage count for repeated fields" do
      # Create 3 entries with same dynamic field
      3.times do |i|
        RawEntry.create!(
          payload: {
            timestamp: Time.current.iso8601,
            level: "info",
            message: "Action #{i}",
            user_id: i * 10
          }.to_json,
          token_id: @token[:id],
          received_at: Time.current
        )
      end

      # Parse all entries
      ParserJob.perform

      # Field should have usage_count = 3
      user_id_field = Field.find_by(name: "user_id")
      assert_equal 3, user_id_field.usage_count
    end

    test "infers field types correctly" do
      RawEntry.create!(
        payload: {
          timestamp: Time.current.iso8601,
          level: "info",
          message: "Type test",
          string_field: "hello",
          number_field: 123,
          boolean_field: false,
          array_field: [1, 2, 3],
          object_field: { key: "value" }
        }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      ParserJob.perform

      assert_equal "string", Field.find_by(name: "string_field").field_type
      assert_equal "number", Field.find_by(name: "number_field").field_type
      assert_equal "boolean", Field.find_by(name: "boolean_field").field_type
      assert_equal "array", Field.find_by(name: "array_field").field_type
      assert_equal "object", Field.find_by(name: "object_field").field_type
    end

    test "handles parsing errors gracefully without crashing batch" do
      # Create valid entry
      RawEntry.create!(
        payload: { timestamp: Time.current.iso8601, level: "info", message: "Valid" }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      # Create invalid entry (malformed JSON)
      raw_invalid = RawEntry.create!(
        payload: "{invalid json",
        token_id: @token[:id],
        received_at: Time.current
      )

      # Create another valid entry
      RawEntry.create!(
        payload: { timestamp: Time.current.iso8601, level: "info", message: "Also valid" }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      # Process all entries
      assert_nothing_raised do
        ParserJob.perform
      end

      # Valid entries should have Entry records created
      # Invalid entry will be marked as parsed (by claim_batch) but no Entry created
      assert_equal 2, Entry.count

      # All RawEntries marked as parsed (claim_batch marks them immediately)
      assert_equal 0, RawEntry.unparsed.count
      assert raw_invalid.reload.parsed == true

      # But invalid entry should NOT have an associated Entry
      assert_nil raw_invalid.entry
    end

    test "handles parser exceptions without crashing batch" do
      # Mock Parser.parse to raise error for specific payload
      original_parse = Parser.method(:parse)
      call_count = 0

      Parser.define_singleton_method(:parse) do |payload|
        call_count += 1
        if call_count == 2
          raise StandardError, "Simulated parse error"
        end
        original_parse.call(payload)
      end

      # Create 3 entries
      3.times do |i|
        RawEntry.create!(
          payload: { timestamp: Time.current.iso8601, level: "info", message: "Test #{i}" }.to_json,
          token_id: @token[:id],
          received_at: Time.current
        )
      end

      # Process batch - should not crash despite error on entry 2
      assert_nothing_raised do
        ParserJob.perform
      end

      # Entry 1 and 3 should be parsed, entry 2 should remain unparsed
      assert_equal 2, Entry.count

      # Restore original parse method
      Parser.define_singleton_method(:parse, original_parse)
    end

    test "stores parsed data correctly in Entry fields" do
      timestamp = 1.hour.ago
      RawEntry.create!(
        payload: {
          timestamp: timestamp.iso8601,
          level: "error",
          message: "Request failed",
          app: "web",
          env: "production",
          request_id: "req-123",
          job_id: "job-456",
          duration: 250.5,
          status_code: 500,
          controller: "UsersController",
          action: "create",
          path: "/users",
          method: "POST",
          custom_field: "custom_value"
        }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      ParserJob.perform

      entry = Entry.last
      assert_equal "error", entry.level
      assert_equal "Request failed", entry.message
      assert_equal "web", entry.app
      assert_equal "production", entry.env
      assert_equal "req-123", entry.request_id
      assert_equal "job-456", entry.job_id
      assert_in_delta 250.5, entry.duration, 0.01
      assert_equal 500, entry.status_code
      assert_equal "UsersController", entry.controller
      assert_equal "create", entry.action
      assert_equal "/users", entry.path
      assert_equal "POST", entry.method

      # Timestamp should be close to 1 hour ago
      assert_in_delta timestamp.to_i, entry.timestamp.to_i, 1

      # Extra fields should be stored as JSON
      extra_fields = JSON.parse(entry.extra_fields)
      assert_equal "custom_value", extra_fields["custom_field"]
    end

    test "returns early if no unparsed entries" do
      # No entries to parse
      assert_equal 0, RawEntry.unparsed.count

      # Should not raise error
      assert_nothing_raised do
        ParserJob.perform
      end

      assert_equal 0, Entry.count
    end

    test "uses SolidLog.without_logging to prevent recursive logging" do
      silenced_during_job = nil

      # Create raw entry
      RawEntry.create!(
        payload: { timestamp: Time.current.iso8601, level: "info", message: "Test" }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      # Patch Entry.insert_all to capture silenced state
      original_insert_all = Entry.method(:insert_all)
      Entry.define_singleton_method(:insert_all) do |entries|
        silenced_during_job = SolidLog.silenced?
        original_insert_all.call(entries)
      end

      # Run job
      ParserJob.perform

      # SolidLog should be silenced during job execution
      assert_equal true, silenced_during_job

      # Restore original method
      Entry.define_singleton_method(:insert_all, original_insert_all)
    end

    test "updates last_seen_at for tracked fields" do
      # Create entry with field
      RawEntry.create!(
        payload: {
          timestamp: Time.current.iso8601,
          level: "info",
          message: "Test",
          user_id: 1
        }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      # Parse entry
      time_before = Time.current
      ParserJob.perform

      field = Field.find_by(name: "user_id")
      assert_not_nil field.last_seen_at
      assert field.last_seen_at >= time_before
    end

    test "preserves field_type if already set" do
      # Create field with existing type
      Field.create!(
        name: "user_id",
        field_type: "string",  # Wrong type, but already set
        usage_count: 0
      )

      # Create entry with numeric user_id
      RawEntry.create!(
        payload: {
          timestamp: Time.current.iso8601,
          level: "info",
          message: "Test",
          user_id: 42
        }.to_json,
        token_id: @token[:id],
        received_at: Time.current
      )

      ParserJob.perform

      # Field type should remain unchanged (preserves existing)
      field = Field.find_by(name: "user_id")
      assert_equal "string", field.field_type
      assert_equal 1, field.usage_count
    end

    test "creates entries with correct created_at timestamp" do
      RawEntry.create!(
        payload: { timestamp: 1.hour.ago.iso8601, level: "info", message: "Old log" }.to_json,
        token_id: @token[:id],
        received_at: 1.hour.ago
      )

      time_before_parsing = Time.current
      ParserJob.perform
      time_after_parsing = Time.current

      entry = Entry.last

      # timestamp should be 1 hour ago (from log payload)
      assert_in_delta 1.hour.ago.to_i, entry.timestamp.to_i, 5

      # created_at should be current time (when parsed)
      assert entry.created_at >= time_before_parsing
      assert entry.created_at <= time_after_parsing
    end

    test "processes entries in batches with multiple perform calls" do
      # Create 25 entries
      25.times do |i|
        RawEntry.create!(
          payload: { timestamp: Time.current.iso8601, level: "info", message: "Test #{i}" }.to_json,
          token_id: @token[:id],
          received_at: Time.current
        )
      end

      # Process in batches of 10
      ParserJob.perform(batch_size: 10)
      assert_equal 10, Entry.count
      assert_equal 15, RawEntry.unparsed.count

      ParserJob.perform(batch_size: 10)
      assert_equal 20, Entry.count
      assert_equal 5, RawEntry.unparsed.count

      ParserJob.perform(batch_size: 10)
      assert_equal 25, Entry.count
      assert_equal 0, RawEntry.unparsed.count
    end
  end
end
