require "test_helper"

module SolidLog
  class EntryTest < ActiveSupport::TestCase
    test "creates entry with valid attributes" do
      entry = create_entry(
        level: "info",
        message: "Test message",
        app: "test-app",
        env: "production"
      )

      assert entry.persisted?
      assert_equal "info", entry.level
      assert_equal "Test message", entry.message
    end

    test "validates presence of level" do
      entry = Entry.new(created_at: Time.current, message: "test")

      assert_not entry.valid?
      assert_includes entry.errors[:level], "can't be blank"
    end

    test "validates presence of created_at" do
      entry = Entry.new(level: "info", message: "test")

      assert_not entry.valid?
      assert_includes entry.errors[:created_at], "can't be blank"
    end

    test "by_level scope filters by level" do
      info_entry = create_entry(level: "info")
      error_entry = create_entry(level: "error")

      results = Entry.by_level("info")

      assert_includes results, info_entry
      assert_not_includes results, error_entry
    end

    test "by_app scope filters by app" do
      web_entry = create_entry(app: "web")
      api_entry = create_entry(app: "api")

      results = Entry.by_app("web")

      assert_includes results, web_entry
      assert_not_includes results, api_entry
    end

    test "by_env scope filters by environment" do
      prod_entry = create_entry(env: "production")
      staging_entry = create_entry(env: "staging")

      results = Entry.by_env("production")

      assert_includes results, prod_entry
      assert_not_includes results, staging_entry
    end

    test "by_request_id scope filters by request ID" do
      req1 = create_entry(request_id: "abc-123")
      req2 = create_entry(request_id: "def-456")

      results = Entry.by_request_id("abc-123")

      assert_includes results, req1
      assert_not_includes results, req2
    end

    test "by_job_id scope filters by job ID" do
      job1 = create_entry(job_id: "job-123")
      job2 = create_entry(job_id: "job-456")

      results = Entry.by_job_id("job-123")

      assert_includes results, job1
      assert_not_includes results, job2
    end

    test "by_time_range scope filters by time range" do
      old_entry = create_entry(timestamp: 2.days.ago, created_at: 2.days.ago)
      recent_entry = create_entry(timestamp: 1.hour.ago, created_at: 1.hour.ago)

      results = Entry.by_time_range(1.day.ago, Time.current)

      assert_includes results, recent_entry
      assert_not_includes results, old_entry
    end

    test "recent scope orders by timestamp asc" do
      first = create_entry(timestamp: 3.hours.ago, created_at: 3.hours.ago)
      second = create_entry(timestamp: 2.hours.ago, created_at: 2.hours.ago)
      third = create_entry(timestamp: 1.hour.ago, created_at: 1.hour.ago)

      results = Entry.recent.to_a

      # Recent scope orders by timestamp ASC (oldest to newest, terminal-style)
      assert_equal [first, second, third], results
    end

    test "errors scope returns only error and fatal entries" do
      info = create_entry(level: "info")
      warn = create_entry(level: "warn")
      error = create_entry(level: "error")
      fatal = create_entry(level: "fatal")

      results = Entry.errors.to_a

      assert_includes results, error
      assert_includes results, fatal
      assert_not_includes results, info
      assert_not_includes results, warn
    end

    test "search_fts returns matching entries" do
      matching = create_entry(message: "User login successful")
      non_matching = create_entry(message: "System startup complete")

      results = Entry.search_fts("login").to_a

      # Verify FTS actually filters results (SQLite FTS5)
      assert_includes results, matching, "Should find entry with 'login' in message"
      assert_not_includes results, non_matching, "Should not find entry without 'login' in message"
    end

    test "filter_by_field filters by JSON field" do
      entry_with_field = create_entry(
        extra_fields: { user_id: 42, ip: "192.168.1.1" }.to_json
      )
      entry_with_different_value = create_entry(
        extra_fields: { user_id: 99 }.to_json
      )
      entry_without_field = create_entry(extra_fields: nil)

      # SQLite json_extract returns number as string, so compare as string
      results = Entry.filter_by_field("user_id", 42).to_a

      # Verify JSON extraction and filtering works (SQLite json_extract)
      assert_includes results, entry_with_field, "Should find entry with user_id=42"
      assert_not_includes results, entry_with_different_value, "Should not find entry with user_id=99"
      assert_not_includes results, entry_without_field, "Should not find entry without user_id"
    end

    test "correlation_timeline_for_request returns request entries" do
      request_id = "req-123"
      req_entry1 = create_entry(request_id: request_id, created_at: 2.minutes.ago)
      req_entry2 = create_entry(request_id: request_id, created_at: 1.minute.ago)
      other_entry = create_entry(request_id: "other")

      results = Entry.correlation_timeline_for_request(request_id).to_a

      assert_includes results, req_entry1
      assert_includes results, req_entry2
      assert_not_includes results, other_entry
    end

    test "correlation_timeline_for_job returns job entries" do
      job_id = "job-123"
      job_entry1 = create_entry(job_id: job_id, created_at: 2.minutes.ago)
      job_entry2 = create_entry(job_id: job_id, created_at: 1.minute.ago)
      other_entry = create_entry(job_id: "other")

      results = Entry.correlation_timeline_for_job(job_id).to_a

      assert_includes results, job_entry1
      assert_includes results, job_entry2
      assert_not_includes results, other_entry
    end

    test "facets_for returns available values for field" do
      create_entry(level: "info")
      create_entry(level: "error")
      create_entry(level: "warn")

      facets = Entry.facets_for("level")

      assert_includes facets, "info"
      assert_includes facets, "error"
      assert_includes facets, "warn"
    end

    test "extra_fields_hash parses JSON" do
      entry = create_entry(
        extra_fields: { user_id: 42, action: "login" }.to_json
      )

      hash = entry.extra_fields_hash

      assert_equal 42, hash["user_id"]
      assert_equal "login", hash["action"]
    end

    test "extra_fields_hash returns empty hash for invalid JSON" do
      entry = Entry.new(
        created_at: Time.current,
        level: "info",
        extra_fields: "{invalid json"
      )

      assert_equal({}, entry.extra_fields_hash)
    end

    test "level_badge_class returns correct CSS class" do
      assert_equal "badge-gray", create_entry(level: "debug").level_badge_class
      assert_equal "badge-blue", create_entry(level: "info").level_badge_class
      assert_equal "badge-yellow", create_entry(level: "warn").level_badge_class
      assert_equal "badge-red", create_entry(level: "error").level_badge_class
      assert_equal "badge-dark-red", create_entry(level: "fatal").level_badge_class
    end

    test "correlated? returns true when request_id present" do
      entry = create_entry(request_id: "abc-123")

      assert entry.correlated?
    end

    test "correlated? returns true when job_id present" do
      entry = create_entry(job_id: "job-123")

      assert entry.correlated?
    end

    test "correlated? returns false when no correlation IDs" do
      entry = create_entry

      assert_not entry.correlated?
    end

    test "prevents recursive logging on save" do
      # This test ensures the without_logging_wrapper works
      entry = create_entry

      assert_nothing_raised do
        entry.update!(message: "Updated message")
      end
    end

    test "prevents recursive logging on delete_all" do
      create_entries(5)

      assert_nothing_raised do
        Entry.delete_all
      end

      assert_equal 0, Entry.count
    end
  end
end
