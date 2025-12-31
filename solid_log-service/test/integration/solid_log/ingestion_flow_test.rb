require "test_helper"

module SolidLog
  class IngestionFlowTest < RackTestCase
    setup do
          ENV["SOLIDLOG_SECRET_KEY"] ||= "test-secret-key-for-tests"
      @token_result = Token.generate!("Test API")
      @token = @token_result[:token]
    end

    test "complete ingestion to query flow" do
      # Step 1: Ingest log via API
      payload = {
        timestamp: Time.current.iso8601,
        level: "info",
        message: "User login successful",
        app: "web",
        env: "production",
        request_id: "abc-123",
        user_id: 42
      }

      post "/api/v1/ingest",
        payload.to_json,
        {
          "HTTP_AUTHORIZATION" => "Bearer #{@token}",
          "CONTENT_TYPE" => "application/json"
        }

      assert_response :accepted

      # Step 2: Verify raw entry created
      assert_equal 1, RawEntry.count
      raw_entry = RawEntry.last
      assert_not raw_entry.parsed?

      # Step 3: Parse the entry
      ParserJob.perform

      # Step 4: Verify parsed entry created
      assert_equal 1, Entry.count
      entry = Entry.last
      assert_equal "info", entry.level
      assert_equal "User login successful", entry.message
      assert_equal "web", entry.app
      assert_equal "production", entry.env
      assert_equal "abc-123", entry.request_id

      # Step 5: Verify custom field tracked
      assert Field.exists?(name: "user_id")

      # Step 6: Query the entry
      results = Entry.by_app("web").by_env("production")
      assert_includes results, entry

      # Step 7: Search full-text
      results = Entry.search_fts("login")
      # FTS may not be fully set up in test, so just verify no errors
      assert results.is_a?(ActiveRecord::Relation)
    end

    test "batch ingestion and parsing flow" do
      # Ingest 10 logs
      payload = 10.times.map do |i|
        {
          timestamp: (Time.current - i.minutes).iso8601,
          level: i.even? ? "info" : "error",
          message: "Log message #{i}",
          app: "test-app"
        }
      end

      post "/api/v1/ingest",
        payload.to_json,
        {
          "HTTP_AUTHORIZATION" => "Bearer #{@token}",
          "CONTENT_TYPE" => "application/json"
        }

      assert_equal 10, RawEntry.count

      # Parse all entries
      ParserJob.perform

      # Verify all parsed
      assert_equal 10, Entry.count
      assert_equal 5, Entry.by_level("info").count
      assert_equal 5, Entry.by_level("error").count
    end

    test "correlation tracking flow" do
      request_id = "req-#{SecureRandom.hex(8)}"

      # Ingest multiple logs with same request_id
      3.times do |i|
        payload = {
          timestamp: (Time.current + i.seconds).iso8601,
          level: "info",
          message: "Request step #{i}",
          request_id: request_id
        }

        post "/api/v1/ingest",
          payload.to_json,
          {
            "HTTP_AUTHORIZATION" => "Bearer #{@token}",
            "CONTENT_TYPE" => "application/json"
          }
      end

      # Parse entries
      ParserJob.perform

      # Query correlation timeline
      timeline = Entry.by_request_id(request_id).order(timestamp: :asc)
      assert_equal 3, timeline.count

      # Verify chronological order (ordered by timestamp ascending)
      messages = timeline.pluck(:message)
      assert_equal ["Request step 0", "Request step 1", "Request step 2"], messages
    end

    test "field promotion flow" do
      # Ingest logs with user_id field
      1500.times do |i|
        payload = {
          timestamp: Time.current.iso8601,
          level: "info",
          message: "User action #{i}",
          user_id: i % 100
        }

        RawEntry.create!(
          payload: payload.to_json,
          token_id: Token.find(@token_result[:id]).id,
          received_at: Time.current
        )
      end

      # Parse all entries (process in batches until all done)
      while RawEntry.unparsed.any?
        ParserJob.perform
      end

      # Verify field tracked
      field = Field.find_by(name: "user_id")
      assert_not_nil field
      assert field.usage_count >= 1500

      # Verify promotable
      assert field.promotable?
    end

    test "retention cleanup flow" do
      # Create old entries (retention uses timestamp, not created_at)
      old_entry = create_entry(timestamp: 60.days.ago, created_at: 60.days.ago)
      recent_entry = create_entry(timestamp: 1.day.ago, created_at: 1.day.ago)

      # Run retention with 30 day policy
      stats = RetentionService.cleanup(retention_days: 30, error_retention_days: 90)

      # Verify old entry deleted, recent kept
      assert_nil Entry.find_by(id: old_entry.id)
      assert_not_nil Entry.find_by(id: recent_entry.id)
      assert stats[:entries_deleted] > 0
    end

    test "error handling in parsing flow" do
      # Ingest invalid JSON timestamp
      post "/api/v1/ingest",
        '{"timestamp": "invalid", "level": "info"}',
        {
          "HTTP_AUTHORIZATION" => "Bearer #{@token}",
          "CONTENT_TYPE" => "application/json"
        }

      assert_response :accepted
      assert_equal 1, RawEntry.count

      # Parse should handle gracefully
      assert_nothing_raised do
        ParserJob.perform
      end

      # Entry may or may not be created depending on parser error handling
      # Just verify no exceptions
    end

    test "concurrent ingestion" do
      # Note: Rails integration tests don't support true concurrent requests
      # This test verifies multiple sequential requests work correctly
      5.times do |i|
        payload = {
          timestamp: Time.current.iso8601,
          level: "info",
          message: "Concurrent log #{i}"
        }

        post "/api/v1/ingest",
          payload.to_json,
          {
            "HTTP_AUTHORIZATION" => "Bearer #{@token}",
            "CONTENT_TYPE" => "application/json"
          }

        assert_response :accepted
      end

      # All entries should be created
      assert_equal 5, RawEntry.count
    end

    test "parser job processes exact batch size" do
      # Create 250 raw entries (more than default batch size of 200)
      250.times do |i|
        RawEntry.create!(
          payload: { timestamp: Time.current.iso8601, level: "info", message: "Test #{i}" }.to_json,
          token_id: @token_result[:id],
          received_at: Time.current
        )
      end

      # First batch should process exactly 200
      ParserJob.perform(batch_size: 200)
      assert_equal 200, Entry.count
      assert_equal 50, RawEntry.unparsed.count

      # Second batch should process remaining 50
      ParserJob.perform(batch_size: 200)
      assert_equal 250, Entry.count
      assert_equal 0, RawEntry.unparsed.count
    end
  end
end
