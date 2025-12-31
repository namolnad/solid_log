require "test_helper"

module SolidLog
  class CacheCleanupJobTest < ActiveSupport::TestCase
    test "cleans up expired cache entries" do
      # Create expired cache entries
      3.times do |i|
        FacetCache.create!(
          key_name: "expired_#{i}",
          cache_value: { data: "test" }.to_json,
          expires_at: 1.day.ago
        )
      end

      # Create valid cache entries
      2.times do |i|
        FacetCache.create!(
          key_name: "valid_#{i}",
          cache_value: { data: "test" }.to_json,
          expires_at: 1.day.from_now
        )
      end

      assert_equal 5, FacetCache.count
      assert_equal 3, FacetCache.expired.count
      assert_equal 2, FacetCache.valid.count

      # Run cleanup job
      CacheCleanupJob.perform

      # Expired entries should be deleted
      assert_equal 2, FacetCache.count
      assert_equal 0, FacetCache.expired.count
      assert_equal 2, FacetCache.valid.count
    end

    test "handles empty cache gracefully" do
      assert_equal 0, FacetCache.count

      # Should not raise error
      assert_nothing_raised do
        CacheCleanupJob.perform
      end

      assert_equal 0, FacetCache.count
    end

    test "handles cache with no expired entries" do
      # Create only valid cache entries
      3.times do |i|
        FacetCache.create!(
          key_name: "valid_#{i}",
          cache_value: { data: "test" }.to_json,
          expires_at: 1.day.from_now
        )
      end

      assert_equal 3, FacetCache.count
      assert_equal 0, FacetCache.expired.count

      # Run cleanup job
      CacheCleanupJob.perform

      # All entries should remain
      assert_equal 3, FacetCache.count
    end

    test "uses SolidLog.without_logging to prevent recursive logging" do
      silenced_during_job = nil

      # Create expired cache
      FacetCache.create!(
        key_name: "expired",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.day.ago
      )

      # Patch cleanup_expired! to capture silenced state
      original_cleanup = FacetCache.method(:cleanup_expired!)
      FacetCache.define_singleton_method(:cleanup_expired!) do
        silenced_during_job = SolidLog.silenced?
        original_cleanup.call
      end

      # Run job
      CacheCleanupJob.perform

      # Should be silenced during execution
      assert_equal true, silenced_during_job

      # Restore original method
      FacetCache.define_singleton_method(:cleanup_expired!, original_cleanup)
    end

    test "only deletes expired entries, not nil expires_at" do
      # Create cache with nil expires_at (never expires)
      never_expires = FacetCache.create!(
        key_name: "permanent",
        cache_value: { data: "test" }.to_json,
        expires_at: nil
      )

      # Create expired cache
      expired = FacetCache.create!(
        key_name: "expired",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.day.ago
      )

      # Create valid cache
      valid = FacetCache.create!(
        key_name: "valid",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.day.from_now
      )

      assert_equal 3, FacetCache.count

      # Run cleanup
      CacheCleanupJob.perform

      # Only expired should be deleted
      assert_not_nil FacetCache.find_by(id: never_expires.id)
      assert_nil FacetCache.find_by(id: expired.id)
      assert_not_nil FacetCache.find_by(id: valid.id)
      assert_equal 2, FacetCache.count
    end

    test "cleanup is idempotent - running multiple times is safe" do
      # Create expired cache
      FacetCache.create!(
        key_name: "expired",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.day.ago
      )

      # Create valid cache
      FacetCache.create!(
        key_name: "valid",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.day.from_now
      )

      assert_equal 2, FacetCache.count

      # Run cleanup multiple times
      3.times { CacheCleanupJob.perform }

      # Should still have only valid cache
      assert_equal 1, FacetCache.count
      assert_equal "valid", FacetCache.first.key_name
    end

    test "cleans up cache entries that just expired" do
      # Create cache that expired 1 second ago
      just_expired = FacetCache.create!(
        key_name: "just_expired",
        cache_value: { data: "test" }.to_json,
        expires_at: 1.second.ago
      )

      # Give it a moment to ensure it's definitely expired
      sleep 0.1

      assert_equal 1, FacetCache.expired.count

      # Run cleanup
      CacheCleanupJob.perform

      # Should be deleted
      assert_nil FacetCache.find_by(id: just_expired.id)
      assert_equal 0, FacetCache.count
    end
  end
end
