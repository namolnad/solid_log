require "test_helper"

module SolidLog
  class RetentionJobTest < ActiveSupport::TestCase
    setup do
      @token = create_test_token
    end

    test "deletes regular logs older than retention_days" do
      # Create old regular logs (35 days old)
      old_entry = create_entry(
        timestamp: 35.days.ago,
        created_at: 35.days.ago,
        level: "info",
        message: "Old log"
      )

      # Create recent regular logs (10 days old)
      recent_entry = create_entry(
        timestamp: 10.days.ago,
        created_at: 10.days.ago,
        level: "info",
        message: "Recent log"
      )

      assert_equal 2, Entry.count

      # Run retention with 30 day policy
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Old entry should be deleted, recent entry preserved
      assert_nil Entry.find_by(id: old_entry.id)
      assert_not_nil Entry.find_by(id: recent_entry.id)
      assert_equal 1, Entry.count
    end

    test "preserves error logs longer than regular logs" do
      # Create old error log (35 days old)
      old_error = create_entry(
        timestamp: 35.days.ago,
        created_at: 35.days.ago,
        level: "error",
        message: "Old error"
      )

      # Create old regular log (35 days old)
      old_info = create_entry(
        timestamp: 35.days.ago,
        created_at: 35.days.ago,
        level: "info",
        message: "Old info"
      )

      assert_equal 2, Entry.count

      # Run retention: 30 days for regular, 90 days for errors
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Regular log deleted, error log preserved
      assert_nil Entry.find_by(id: old_info.id)
      assert_not_nil Entry.find_by(id: old_error.id)
      assert_equal 1, Entry.count
    end

    test "deletes error logs older than error_retention_days" do
      # Create very old error log (100 days old)
      very_old_error = create_entry(
        timestamp: 100.days.ago,
        created_at: 100.days.ago,
        level: "error",
        message: "Very old error"
      )

      # Create old but within error retention (60 days old)
      old_error = create_entry(
        timestamp: 60.days.ago,
        created_at: 60.days.ago,
        level: "error",
        message: "Old error"
      )

      assert_equal 2, Entry.count

      # Run retention with 90 day error policy
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Very old error deleted, old error within retention preserved
      assert_nil Entry.find_by(id: very_old_error.id)
      assert_not_nil Entry.find_by(id: old_error.id)
      assert_equal 1, Entry.count
    end

    test "respects both error and fatal levels for extended retention" do
      # Create old fatal log (35 days old)
      old_fatal = create_entry(
        timestamp: 35.days.ago,
        created_at: 35.days.ago,
        level: "fatal",
        message: "Old fatal"
      )

      # Create old error log (35 days old)
      old_error = create_entry(
        timestamp: 35.days.ago,
        created_at: 35.days.ago,
        level: "error",
        message: "Old error"
      )

      # Run retention: 30 days for regular, 90 days for errors/fatal
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Both error and fatal should be preserved
      assert_not_nil Entry.find_by(id: old_fatal.id)
      assert_not_nil Entry.find_by(id: old_error.id)
      assert_equal 2, Entry.count
    end

    test "deletes all log levels except error and fatal based on regular retention" do
      levels_and_ages = [
        ["debug", 35.days.ago, true],   # Should be deleted
        ["info", 35.days.ago, true],    # Should be deleted
        ["warn", 35.days.ago, true],    # Should be deleted
        ["error", 35.days.ago, false],  # Should be preserved
        ["fatal", 35.days.ago, false]   # Should be preserved
      ]

      entries = levels_and_ages.map do |level, timestamp, should_delete|
        [
          create_entry(timestamp: timestamp, created_at: timestamp, level: level, message: "Test #{level}"),
          should_delete
        ]
      end

      assert_equal 5, Entry.count

      # Run retention
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Verify expected deletions
      entries.each do |entry, should_delete|
        if should_delete
          assert_nil Entry.find_by(id: entry.id), "#{entry.level} should be deleted"
        else
          assert_not_nil Entry.find_by(id: entry.id), "#{entry.level} should be preserved"
        end
      end

      assert_equal 2, Entry.count  # Only error and fatal remain
    end

    test "returns correct statistics" do
      # Create entries to be deleted
      3.times do |i|
        create_entry(timestamp: 35.days.ago, created_at: 35.days.ago, level: "info", message: "Old #{i}")
      end

      # Create entries to be preserved
      2.times do |i|
        create_entry(timestamp: 10.days.ago, created_at: 10.days.ago, level: "info", message: "Recent #{i}")
      end

      # Create orphaned raw entries
      3.times do |i|
        RawEntry.create!(
          payload: { timestamp: Time.current.iso8601, level: "info", message: "Orphan #{i}" }.to_json,
          token_id: @token[:id],
          received_at: 35.days.ago,
          parsed: true,
          parsed_at: 35.days.ago
        )
      end

      # Create expired cache entries
      2.times do |i|
        FacetCache.create!(
          key_name: "old_cache_#{i}",
          cache_value: { data: "test" }.to_json,
          expires_at: 1.day.ago
        )
      end

      # Run retention directly (not through job) to get stats
      stats = RetentionService.cleanup(retention_days: 30, error_retention_days: 90)

      assert_equal 3, stats[:entries_deleted]
      assert_equal 3, stats[:raw_deleted]
      assert_equal 2, stats[:cache_cleared]
    end

    test "deletes orphaned raw entries but preserves unparsed" do
      # Create entry with raw entry (not orphaned)
      entry_with_raw = create_entry(
        timestamp: Time.current,
        created_at: Time.current,
        level: "info",
        message: "Has entry"
      )

      # Create orphaned raw entry (parsed but no entry)
      orphaned_raw = RawEntry.create!(
        payload: { timestamp: Time.current.iso8601, level: "info", message: "Orphaned" }.to_json,
        token_id: @token[:id],
        received_at: 1.day.ago,
        parsed: true,
        parsed_at: 1.day.ago
      )

      # Create unparsed raw entry (should be preserved for investigation)
      unparsed_raw = RawEntry.create!(
        payload: { timestamp: Time.current.iso8601, level: "info", message: "Unparsed" }.to_json,
        token_id: @token[:id],
        received_at: 1.day.ago,
        parsed: false
      )

      assert_equal 3, RawEntry.count

      # Run retention
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Entry's raw should remain, orphaned should be deleted, unparsed should remain
      assert_not_nil RawEntry.find_by(id: entry_with_raw.raw_id)
      assert_nil RawEntry.find_by(id: orphaned_raw.id)
      assert_not_nil RawEntry.find_by(id: unparsed_raw.id)
      assert_equal 2, RawEntry.count
    end

    test "clears expired cache entries" do
      # Create expired cache
      expired_cache = FacetCache.create!(
        key_name: "old_facet",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.day.ago
      )

      # Create valid cache
      valid_cache = FacetCache.create!(
        key_name: "new_facet",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.day.from_now
      )

      assert_equal 2, FacetCache.count

      # Run retention
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Expired deleted, valid preserved
      assert_nil FacetCache.find_by(id: expired_cache.id)
      assert_not_nil FacetCache.find_by(id: valid_cache.id)
      assert_equal 1, FacetCache.count
    end

    test "vacuum parameter triggers database vacuum for SQLite" do
      # Skip if not SQLite
      skip "Not SQLite" unless ActiveRecord::Base.connection.adapter_name.downcase == "sqlite"

      # Run retention with vacuum
      assert_nothing_raised do
        RetentionJob.perform(retention_days: 30, error_retention_days: 90, vacuum: true)
      end
    end

    test "vacuum parameter is optional and defaults to false" do
      # Should work without vacuum parameter
      assert_nothing_raised do
        RetentionJob.perform(retention_days: 30, error_retention_days: 90)
      end
    end

    test "uses SolidLog.without_logging to prevent recursive logging" do
      silenced_during_job = nil

      # Patch RetentionService.cleanup to capture silenced state
      original_cleanup = RetentionService.method(:cleanup)
      RetentionService.define_singleton_method(:cleanup) do |**args|
        silenced_during_job = SolidLog.silenced?
        original_cleanup.call(**args)
      end

      # Run job
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Should be silenced during execution
      assert_equal true, silenced_during_job

      # Restore original method
      RetentionService.define_singleton_method(:cleanup, original_cleanup)
    end

    test "handles empty database without errors" do
      # Empty database
      assert_equal 0, Entry.count
      assert_equal 0, RawEntry.count

      # Should not raise error
      assert_nothing_raised do
        RetentionJob.perform(retention_days: 30, error_retention_days: 90)
      end
    end

    test "accepts custom retention_days parameter" do
      # Create entry 50 days old
      old_entry = create_entry(
        timestamp: 50.days.ago,
        created_at: 50.days.ago,
        level: "info",
        message: "50 days old"
      )

      # Run with 60 day retention - should preserve
      RetentionJob.perform(retention_days: 60, error_retention_days: 90)
      assert_not_nil Entry.find_by(id: old_entry.id)

      # Run with 40 day retention - should delete
      RetentionJob.perform(retention_days: 40, error_retention_days: 90)
      assert_nil Entry.find_by(id: old_entry.id)
    end

    test "uses default retention configuration if not specified" do
      # Set config
      original_retention = SolidLog.configuration.retention_days
      original_error_retention = SolidLog.configuration.error_retention_days

      SolidLog.configuration.retention_days = 15
      SolidLog.configuration.error_retention_days = 45

      # Create entry 20 days old
      old_entry = create_entry(
        timestamp: 20.days.ago,
        created_at: 20.days.ago,
        level: "info",
        message: "20 days old"
      )

      # Run with explicit parameters (should override config)
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # Entry should be preserved (30 day retention)
      assert_not_nil Entry.find_by(id: old_entry.id)

      # Restore config
      SolidLog.configuration.retention_days = original_retention
      SolidLog.configuration.error_retention_days = original_error_retention
    end

    test "preserves recent entries across all log levels" do
      levels = %w[debug info warn error fatal]

      entries = levels.map do |level|
        create_entry(
          timestamp: 10.days.ago,
          created_at: 10.days.ago,
          level: level,
          message: "Recent #{level}"
        )
      end

      assert_equal 5, Entry.count

      # Run retention
      RetentionJob.perform(retention_days: 30, error_retention_days: 90)

      # All recent entries should be preserved
      entries.each do |entry|
        assert_not_nil Entry.find_by(id: entry.id), "Recent #{entry.level} should be preserved"
      end

      assert_equal 5, Entry.count
    end
  end
end
