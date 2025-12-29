require "test_helper"

module SolidLog
  class FacetCacheTest < ActiveSupport::TestCase
    test "fetch returns cached value if not expired" do
      FacetCache.create!(
        key_name: "test_key",
        cache_value: ["value1", "value2"].to_json,
        expires_at: 1.hour.from_now
      )

      result = FacetCache.fetch("test_key", ttl: 5.minutes) do
        ["should_not_execute"]
      end

      assert_equal ["value1", "value2"], result
    end

    test "fetch executes block if cache expired" do
      FacetCache.create!(
        key_name: "test_key",
        cache_value: ["old_value"].to_json,
        expires_at: 1.hour.ago
      )

      result = FacetCache.fetch("test_key", ttl: 5.minutes) do
        ["new_value"]
      end

      assert_equal ["new_value"], result
    end

    test "fetch executes block if cache missing" do
      result = FacetCache.fetch("missing_key", ttl: 5.minutes) do
        ["computed_value"]
      end

      assert_equal ["computed_value"], result
    end

    test "fetch stores result in cache" do
      FacetCache.fetch("new_key", ttl: 5.minutes) do
        ["stored_value"]
      end

      cached = FacetCache.find_by(key_name: "new_key")

      assert_not_nil cached
      assert_equal ["stored_value"], JSON.parse(cached.cache_value)
      assert cached.expires_at > Time.current
    end

    test "cleanup_expired! removes expired entries" do
      expired = FacetCache.create!(
        key_name: "expired",
        cache_value: "[]",
        expires_at: 1.hour.ago
      )

      valid = FacetCache.create!(
        key_name: "valid",
        cache_value: "[]",
        expires_at: 1.hour.from_now
      )

      FacetCache.cleanup_expired!

      assert_nil FacetCache.find_by(id: expired.id)
      assert_not_nil FacetCache.find_by(id: valid.id)
    end

    test "cleanup_expired! returns count of deleted entries" do
      3.times do |i|
        FacetCache.create!(
          key_name: "expired_#{i}",
          cache_value: "[]",
          expires_at: 1.hour.ago
        )
      end

      count = FacetCache.cleanup_expired!

      assert_equal 3, count
    end

    test "fetch handles complex data types" do
      complex_data = {
        apps: ["web", "api"],
        envs: ["production", "staging"],
        counts: { total: 100, errors: 5 }
      }

      result = FacetCache.fetch("complex", ttl: 5.minutes) do
        complex_data
      end

      assert_equal complex_data.deep_stringify_keys, result.deep_stringify_keys
    end

    test "fetch is thread-safe" do
      # Skip for in-memory databases (threads can't share :memory: connections)
      skip "Thread-safety test requires file-based database" if ActiveRecord::Base.connection_db_config.database == ":memory:"

      call_count = Concurrent::AtomicFixnum.new(0)

      threads = 10.times.map do
        Thread.new do
          FacetCache.fetch("thread_test", ttl: 5.minutes) do
            call_count.increment
            ["value"]
          end
        end
      end

      threads.each(&:join)

      # Block should execute exactly once despite concurrent calls
      # Database locking ensures only one thread computes the value
      assert_equal 1, call_count.value, "Block should execute exactly once, not #{call_count.value} times"
    end
  end
end
